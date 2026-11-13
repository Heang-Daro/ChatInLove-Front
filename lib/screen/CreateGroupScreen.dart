import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:love_in_chat/model/Response/UserResponse.dart';
import 'package:love_in_chat/provider/AuthProvider.dart';
import 'package:love_in_chat/provider/ConversationProvider.dart';
import 'package:love_in_chat/util/AppBarStyle.dart';

import '../util/AnimatedComponents.dart';
import 'ConversationPage.dart';

class CreateGroupScreen extends StatefulWidget {
  const CreateGroupScreen({super.key});

  @override
  State<CreateGroupScreen> createState() => _CreateGroupScreenState();
}

class _CreateGroupScreenState extends State<CreateGroupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _searchController = TextEditingController();
  final List<UserResponse> _selectedMembers = [];
  List<UserResponse> _searchResults = [];
  bool _isSearching = false;
  bool _isSubmitting = false;
  int _searchSequence = 0;

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _searchMembers(String value) async {
    final query = value.trim();
    final sequence = ++_searchSequence;
    if (query.isEmpty) {
      setState(() {
        _searchResults = [];
        _isSearching = false;
      });
      return;
    }

    setState(() => _isSearching = true);
    final auth = context.read<AuthProvider>();
    final provider = context.read<ConversationProvider>();
    final results = await provider.searchUsersFuture(auth, query);

    if (!mounted || sequence != _searchSequence) return;
    final selfId = auth.currentUserId;
    setState(() {
      _searchResults = results.where((user) =>
          user.id != selfId && !_selectedMembers.any((m) => m.id == user.id)).toList();
      _isSearching = false;
    });
  }

  void _toggleMember(UserResponse user) {
    setState(() {
      if (_selectedMembers.any((member) => member.id == user.id)) {
        _selectedMembers.removeWhere((member) => member.id == user.id);
      } else {
        _selectedMembers.add(user);
        _searchResults.removeWhere((result) => result.id == user.id);
      }
    });
  }

  Future<void> _createGroup() async {
    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_selectedMembers.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add at least one member to continue.')),
      );
      return;
    }

    setState(() => _isSubmitting = true);
    final auth = context.read<AuthProvider>();
    final provider = context.read<ConversationProvider>();
    final group = await provider.createGroupConversation(
      auth,
      name: _nameController.text.trim(),
      description: _descriptionController.text.trim(),
      memberIds: _selectedMembers.map((member) => member.id).toList(),
    );

    if (!mounted) return;
    setState(() => _isSubmitting = false);
    if (group == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not create the group. Please try again.')),
      );
      return;
    }

    Navigator.of(context).pushReplacement(
      AnimatedPageRoute(
        page: ConversationPage(
          conversationId: group.id,
          chatName: group.name?.trim().isNotEmpty == true
              ? group.name!
              : _nameController.text.trim(),
          avatar: Icons.group_rounded,
          isGroup: true,
        ),
      ),
    );
  }

  InputDecoration _decoration({
    required String label,
    required String hint,
    required IconData icon,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: Icon(icon, color: Colors.pinkAccent),
      filled: true,
      fillColor: Colors.pinkAccent.withValues(alpha: 0.045),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: Colors.pink.shade100),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Colors.pinkAccent, width: 1.6),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBarStyle.build(title: 'Create a group'),
      body: SafeArea(
        top: false,
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.pinkAccent.shade100, Colors.pinkAccent.shade400],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(22),
                ),
                child: const Row(
                  children: [
                    CircleAvatar(
                      radius: 27,
                      backgroundColor: Colors.white,
                      child: Icon(Icons.groups_rounded, color: Colors.pinkAccent, size: 29),
                    ),
                    SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Bring your people together', style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800)),
                          SizedBox(height: 4),
                          Text('Create a group and start chatting.', style: TextStyle(color: Colors.white)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Text('Group details', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 12),
              TextFormField(
                controller: _nameController,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
                maxLength: 50,
                decoration: _decoration(label: 'Group name', hint: 'e.g. Weekend plans', icon: Icons.edit_note_rounded),
                validator: (value) => (value == null || value.trim().isEmpty) ? 'Enter a group name' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _descriptionController,
                textCapitalization: TextCapitalization.sentences,
                maxLines: 3,
                maxLength: 160,
                decoration: _decoration(label: 'Description (optional)', hint: 'What is this group for?', icon: Icons.notes_rounded),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(child: Text('Add members', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800))),
                  Text('${_selectedMembers.length} selected', style: const TextStyle(color: Colors.pinkAccent, fontWeight: FontWeight.w700)),
                ],
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _searchController,
                onChanged: _searchMembers,
                textInputAction: TextInputAction.search,
                decoration: _decoration(label: 'Search people', hint: 'Type a username', icon: Icons.search_rounded).copyWith(
                  suffixIcon: _isSearching
                      ? const Padding(
                          padding: EdgeInsets.all(14),
                          child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.pinkAccent)),
                        )
                      : _searchController.text.isNotEmpty
                          ? IconButton(
                              tooltip: 'Clear search',
                              onPressed: () {
                                _searchController.clear();
                                _searchMembers('');
                              },
                              icon: const Icon(Icons.close_rounded),
                            )
                          : null,
                ),
              ),
              if (_selectedMembers.isNotEmpty) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _selectedMembers.map((member) => InputChip(
                    avatar: CircleAvatar(
                      backgroundColor: Colors.pinkAccent.withValues(alpha: 0.15),
                      child: Text(member.username.isNotEmpty ? member.username[0].toUpperCase() : '?', style: const TextStyle(color: Colors.pinkAccent, fontSize: 12)),
                    ),
                    label: Text(member.username),
                    onDeleted: () {
                      _toggleMember(member);
                      _searchMembers(_searchController.text);
                    },
                    deleteIconColor: Colors.pinkAccent,
                    backgroundColor: Colors.pink.shade50,
                  )).toList(),
                ),
              ],
              const SizedBox(height: 12),
              Container(
                constraints: const BoxConstraints(minHeight: 140, maxHeight: 320),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: Colors.pink.shade100),
                ),
                child: _buildSearchResults(theme),
              ),
              const SizedBox(height: 22),
              SizedBox(
                height: 54,
                child: FilledButton.icon(
                  onPressed: _isSubmitting ? null : _createGroup,
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.pinkAccent,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  icon: _isSubmitting
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.group_add_rounded),
                  label: Text(
                    _isSubmitting ? 'Creating group…' : 'Create group${_selectedMembers.isEmpty ? '' : ' (${_selectedMembers.length})'}',
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSearchResults(ThemeData theme) {
    if (_isSearching) {
      return const Center(child: CircularProgressIndicator(color: Colors.pinkAccent));
    }
    if (_searchController.text.trim().isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.person_add_alt_1_rounded, size: 30, color: Colors.pinkAccent.shade100),
              const SizedBox(height: 8),
              Text('Search for people to invite', style: TextStyle(color: theme.colorScheme.onSurfaceVariant)),
            ],
          ),
        ),
      );
    }
    if (_searchResults.isEmpty) {
      return Center(child: Text('No matching people found', style: TextStyle(color: theme.colorScheme.onSurfaceVariant)));
    }

    return ListView.separated(
      shrinkWrap: true,
      padding: const EdgeInsets.symmetric(vertical: 6),
      itemCount: _searchResults.length,
      separatorBuilder: (_, __) => const Divider(height: 1, indent: 68),
      itemBuilder: (context, index) {
        final user = _searchResults[index];
        final selected = _selectedMembers.any((member) => member.id == user.id);
        return ListTile(
          leading: CircleAvatar(
            backgroundColor: Colors.pinkAccent.withValues(alpha: 0.14),
            child: Text(user.username.isNotEmpty ? user.username[0].toUpperCase() : '?', style: const TextStyle(color: Colors.pinkAccent, fontWeight: FontWeight.w700)),
          ),
          title: Text(user.username, style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text(user.email, maxLines: 1, overflow: TextOverflow.ellipsis),
          trailing: Icon(selected ? Icons.check_circle : Icons.add_circle_outline, color: Colors.pinkAccent),
          onTap: () => _toggleMember(user),
        );
      },
    );
  }
}
