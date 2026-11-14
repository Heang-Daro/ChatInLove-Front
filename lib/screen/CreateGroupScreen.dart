import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:love_in_chat/model/Response/UserResponse.dart';
import 'package:love_in_chat/provider/AuthProvider.dart';
import 'package:love_in_chat/provider/ConversationProvider.dart';
import 'package:love_in_chat/util/AppBarStyle.dart';

import '../util/AnimatedComponents.dart';
import 'ConversationPage.dart';

const Color _brand = Colors.pinkAccent;
const Duration _debounce = Duration(milliseconds: 350);

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

  Timer? _debounceTimer;
  int _searchSequence = 0;
  bool _isSearching = false;
  bool _searchFailed = false;
  bool _isSubmitting = false;
  bool _showMemberError = false;
  bool _created = false;

  bool get _hasChanges =>
      !_created &&
      (_nameController.text.trim().isNotEmpty ||
          _descriptionController.text.trim().isNotEmpty ||
          _selectedMembers.isNotEmpty);

  bool _isSelected(UserResponse u) => _selectedMembers.any((m) => m.id == u.id);

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _nameController.dispose();
    _descriptionController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _toast(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(message),
        backgroundColor: error ? Colors.redAccent : _brand,
        behavior: SnackBarBehavior.floating,
      ));
  }

  // ── Search (debounced, with error + retry) ────────────────────────────────
  void _onSearchChanged(String value) {
    _debounceTimer?.cancel();
    final query = value.trim();
    if (query.isEmpty) {
      _searchSequence++;
      setState(() {
        _searchResults = [];
        _isSearching = false;
        _searchFailed = false;
      });
      return;
    }
    setState(() {
      _isSearching = true;
      _searchFailed = false;
    });
    _debounceTimer = Timer(_debounce, () => _runSearch(query));
  }

  Future<void> _runSearch(String query) async {
    final sequence = ++_searchSequence;
    final auth = context.read<AuthProvider>();
    final provider = context.read<ConversationProvider>();

    List<UserResponse>? results;
    try {
      results = await provider.searchUsersFuture(auth, query);
    } catch (_) {
      results = null;
    }

    // Ignore answers to searches the user has already moved past.
    if (!mounted || sequence != _searchSequence) return;
    final selfId = auth.currentUserId;
    setState(() {
      _isSearching = false;
      _searchFailed = results == null;
      _searchResults = results?.where((u) => u.id != selfId).toList() ?? [];
    });
  }

  void _toggleMember(UserResponse user) {
    setState(() {
      if (_isSelected(user)) {
        _selectedMembers.removeWhere((m) => m.id == user.id);
      } else {
        _selectedMembers.add(user);
        _showMemberError = false;
      }
    });
  }

  // ── Create ────────────────────────────────────────────────────────────────
  Future<void> _createGroup() async {
    FocusScope.of(context).unfocus();
    final formOk = _formKey.currentState?.validate() ?? false;
    if (_selectedMembers.isEmpty) {
      setState(() => _showMemberError = true);
    }
    if (!formOk || _selectedMembers.isEmpty) return;

    setState(() => _isSubmitting = true);
    final auth = context.read<AuthProvider>();
    final provider = context.read<ConversationProvider>();

    dynamic group;
    try {
      group = await provider.createGroupConversation(
        auth,
        name: _nameController.text.trim(),
        description: _descriptionController.text.trim(),
        memberIds: _selectedMembers.map((m) => m.id).toList(),
      );
    } catch (_) {
      group = null;
    }

    if (!mounted) return;
    setState(() => _isSubmitting = false);

    if (group == null) {
      _toast('Could not create the group. Check your connection and try again.',
          error: true);
      return;
    }

    _created = true; // skip the "discard changes?" prompt
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

  Future<void> _confirmDiscard() async {
    final leave = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Discard this group?'),
        content: const Text('Your group details and members will be lost.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Keep editing')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    if (leave == true && mounted) Navigator.of(context).pop();
  }

  // ── UI ────────────────────────────────────────────────────────────────────
  InputDecoration _decoration({
    required String label,
    required String hint,
    required IconData icon,
  }) {
    final outline = Theme.of(context).colorScheme.outlineVariant;
    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: Icon(icon, color: _brand),
      filled: true,
      fillColor: _brand.withValues(alpha: 0.045),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: outline),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: _brand, width: 1.6),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return PopScope(
      canPop: !_hasChanges || _isSubmitting,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmDiscard();
      },
      child: Scaffold(
        appBar: AppBarStyle.build(title: 'New group'),
        // Always-visible action: no scrolling to find the button.
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
            child: SizedBox(
              height: 54,
              child: FilledButton.icon(
                onPressed: _isSubmitting ? null : _createGroup,
                style: FilledButton.styleFrom(
                  backgroundColor: _brand,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                ),
                icon: _isSubmitting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.group_add_rounded),
                label: Text(
                  _isSubmitting
                      ? 'Creating group…'
                      : _selectedMembers.isEmpty
                          ? 'Create group'
                          : 'Create group with ${_selectedMembers.length} ${_selectedMembers.length == 1 ? 'member' : 'members'}',
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 16),
                ),
              ),
            ),
          ),
        ),
        body: Form(
          key: _formKey,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          child: ListView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
            children: [
              TextFormField(
                controller: _nameController,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
                maxLength: 50,
                onChanged: (_) => setState(() {}),
                decoration: _decoration(
                    label: 'Group name',
                    hint: 'e.g. Weekend plans',
                    icon: Icons.edit_note_rounded),
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? 'Enter a group name'
                    : null,
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _descriptionController,
                textCapitalization: TextCapitalization.sentences,
                textInputAction: TextInputAction.newline,
                maxLines: 2,
                maxLength: 160,
                onChanged: (_) => setState(() {}),
                decoration: _decoration(
                    label: 'Description (optional)',
                    hint: 'What is this group for?',
                    icon: Icons.notes_rounded),
              ),
              const SizedBox(height: 16),

              // ── Members ─────────────────────────────────────────────────
              Row(children: [
                Expanded(
                  child: Text('Members',
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w800)),
                ),
                if (_selectedMembers.isNotEmpty)
                  Text('${_selectedMembers.length} selected',
                      style: const TextStyle(
                          color: _brand, fontWeight: FontWeight.w700)),
              ]),
              const SizedBox(height: 10),

              if (_selectedMembers.isNotEmpty) ...[
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final member in _selectedMembers)
                      InputChip(
                        avatar: _UserAvatar(user: member, radius: 12),
                        label: Text(member.username),
                        deleteButtonTooltipMessage:
                            'Remove ${member.username}',
                        onDeleted: () => _toggleMember(member),
                        deleteIconColor: _brand,
                        backgroundColor: _brand.withValues(alpha: 0.1),
                        side: BorderSide.none,
                      ),
                  ],
                ),
                const SizedBox(height: 12),
              ],

              TextField(
                controller: _searchController,
                onChanged: _onSearchChanged,
                onSubmitted: (v) {
                  _debounceTimer?.cancel();
                  if (v.trim().isNotEmpty) _runSearch(v.trim());
                },
                textInputAction: TextInputAction.search,
                decoration: _decoration(
                  label: 'Search people',
                  hint: 'Type a username',
                  icon: Icons.search_rounded,
                ).copyWith(
                  suffixIcon: _searchController.text.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Clear search',
                          icon: const Icon(Icons.close_rounded),
                          onPressed: () {
                            _searchController.clear();
                            _onSearchChanged('');
                          },
                        ),
                ),
              ),
              if (_isSearching)
                const Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: LinearProgressIndicator(
                      minHeight: 2, color: _brand, backgroundColor: Colors.transparent),
                ),

              if (_showMemberError && _selectedMembers.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8, left: 4),
                  child: Text('Add at least one member to continue.',
                      style: TextStyle(color: scheme.error, fontSize: 12)),
                ),

              const SizedBox(height: 8),
              _buildResults(theme),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildResults(ThemeData theme) {
    final scheme = theme.colorScheme;
    final hasQuery = _searchController.text.trim().isNotEmpty;

    Widget message(IconData icon, String text, {Widget? action}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Column(children: [
            Icon(icon, size: 30, color: _brand.withValues(alpha: 0.6)),
            const SizedBox(height: 8),
            Text(text,
                textAlign: TextAlign.center,
                style: TextStyle(color: scheme.onSurfaceVariant)),
            if (action != null) action,
          ]),
        );

    if (!hasQuery) {
      // Don't take up space once members are chosen.
      if (_selectedMembers.isNotEmpty) return const SizedBox.shrink();
      return message(Icons.person_add_alt_1_rounded,
          'Search for people to add to your group.');
    }
    if (_searchFailed) {
      return message(
        Icons.cloud_off_outlined,
        'Search unavailable. Check your connection.',
        action: TextButton.icon(
          onPressed: () {
            setState(() {
              _isSearching = true;
              _searchFailed = false;
            });
            _runSearch(_searchController.text.trim());
          },
          icon: const Icon(Icons.refresh),
          label: const Text('Try again'),
        ),
      );
    }
    if (_isSearching && _searchResults.isEmpty) {
      return const SizedBox(height: 80);
    }
    if (_searchResults.isEmpty) {
      return message(Icons.person_off_outlined,
          'No one matches "${_searchController.text.trim()}".');
    }

    // Results stay visible after tapping, so a person can undo a mistake.
    return Column(children: [
      for (final user in _searchResults)
        _ResultTile(
          user: user,
          selected: _isSelected(user),
          onTap: () => _toggleMember(user),
        ),
    ]);
  }
}

class _ResultTile extends StatelessWidget {
  final UserResponse user;
  final bool selected;
  final VoidCallback onTap;

  const _ResultTile({
    required this.user,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      selected: selected,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 4),
        leading: _UserAvatar(user: user, radius: 22),
        title: Text(user.username,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(user.email, maxLines: 1, overflow: TextOverflow.ellipsis),
        trailing: Icon(
          selected ? Icons.check_circle : Icons.add_circle_outline,
          color: _brand,
        ),
        onTap: onTap,
      ),
    );
  }
}

class _UserAvatar extends StatelessWidget {
  final UserResponse user;
  final double radius;

  const _UserAvatar({required this.user, required this.radius});

  @override
  Widget build(BuildContext context) {
    final url = user.profileImageUrl;
    final initial = Container(
      color: _brand.withValues(alpha: 0.15),
      alignment: Alignment.center,
      child: Text(
        user.username.isNotEmpty ? user.username[0].toUpperCase() : '?',
        style: TextStyle(
            color: _brand,
            fontWeight: FontWeight.w700,
            fontSize: radius * 0.8),
      ),
    );

    return ClipOval(
      child: SizedBox(
        width: radius * 2,
        height: radius * 2,
        child: (url == null || url.isEmpty)
            ? initial
            : Image.network(
                url,
                fit: BoxFit.cover,
                loadingBuilder: (_, child, p) => p == null ? child : initial,
                errorBuilder: (_, __, ___) => initial,
              ),
      ),
    );
  }
}
