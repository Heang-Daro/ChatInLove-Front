import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:love_in_chat/model/Response/UserResponse.dart';
import 'package:love_in_chat/provider/AuthProvider.dart';
import 'package:love_in_chat/provider/ConversationProvider.dart';

import '../util/AnimatedComponents.dart';
import 'ConversationPage.dart';

class CreateGroupDialog extends StatefulWidget {
  const CreateGroupDialog({super.key});

  @override
  State<CreateGroupDialog> createState() => _CreateGroupDialogState();
}

class _CreateGroupDialogState extends State<CreateGroupDialog> {
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _searchController = TextEditingController();

  final List<UserResponse> _selectedMembers = [];
  List<UserResponse> _searchResults = [];
  bool _isSearching = false;
  bool _isSubmitting = false;

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _performSearch(String query) async {
    if (query.trim().isEmpty) {
      setState(() {
        _searchResults = [];
        _isSearching = false;
      });
      return;
    }

    setState(() => _isSearching = true);

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final convoProvider = Provider.of<ConversationProvider>(context, listen: false);

    final results = await convoProvider.searchUsersFuture(authProvider, query);

    if (mounted) {
      setState(() {
        _searchResults = results;
        _isSearching = false;
      });
    }
  }

  void _toggleMember(UserResponse user) {
    setState(() {
      if (_selectedMembers.any((m) => m.id == user.id)) {
        _selectedMembers.removeWhere((m) => m.id == user.id);
      } else {
        _selectedMembers.add(user);
      }
    });
  }

  void _submitGroup() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a group name')),
      );
      return;
    }

    if (_selectedMembers.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select at least 1 member for the group')),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final convoProvider = Provider.of<ConversationProvider>(context, listen: false);

    final memberIds = _selectedMembers.map((m) => m.id).toList();

    final group = await convoProvider.createGroupConversation(
      authProvider,
      name: name,
      description: _descriptionController.text.trim(),
      memberIds: memberIds,
    );

    if (mounted) {
      setState(() => _isSubmitting = false);
      if (group != null) {
        Navigator.pop(context); // Close dialog

        // Navigate to the newly created group chat with smooth transition
        Navigator.push(
          context,
          AnimatedPageRoute(
            page: ConversationPage(
              conversationId: group.id,
              chatName: group.name ?? name,
              avatar: Icons.group,
              isGroup: true,
            ),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to create group. Try again.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        padding: const EdgeInsets.all(20),
        constraints: const BoxConstraints(maxWidth: 450, maxHeight: 600),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Title Header
            Row(
              children: [
                const CircleAvatar(
                  backgroundColor: Colors.pinkAccent,
                  child: Icon(Icons.group_add, color: Colors.white),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    "Create New Group",
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.pinkAccent,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.grey),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const Divider(),
            const SizedBox(height: 8),

            // Group Name Input
            TextField(
              controller: _nameController,
              decoration: InputDecoration(
                labelText: "Group Name *",
                prefixIcon: const Icon(Icons.title, color: Colors.pinkAccent),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Colors.pinkAccent, width: 2),
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Description Input
            TextField(
              controller: _descriptionController,
              decoration: InputDecoration(
                labelText: "Description (optional)",
                prefixIcon: const Icon(Icons.description, color: Colors.pinkAccent),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 12),

            // Member Search Bar
            TextField(
              controller: _searchController,
              onChanged: _performSearch,
              decoration: InputDecoration(
                hintText: "Search users to add...",
                prefixIcon: const Icon(Icons.search, color: Colors.pinkAccent),
                suffixIcon: _isSearching
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.pinkAccent),
                      )
                    : null,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 8),

            // Selected Chips Preview
            if (_selectedMembers.isNotEmpty)
              SizedBox(
                height: 40,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: _selectedMembers.length,
                  itemBuilder: (context, index) {
                    final member = _selectedMembers[index];
                    return Container(
                      margin: const EdgeInsets.only(right: 6),
                      child: Chip(
                        avatar: CircleAvatar(
                          backgroundColor: Colors.pinkAccent.shade100,
                          child: Text(member.username[0].toUpperCase(),
                              style: const TextStyle(fontSize: 10, color: Colors.pinkAccent)),
                        ),
                        label: Text(member.username, style: const TextStyle(fontSize: 12)),
                        deleteIcon: const Icon(Icons.cancel, size: 16, color: Colors.pinkAccent),
                        onDeleted: () => _toggleMember(member),
                        backgroundColor: Colors.pink.shade50,
                      ),
                    );
                  },
                ),
              ),

            const SizedBox(height: 8),

            // Search Results List
            Expanded(
              child: _searchResults.isEmpty
                  ? Center(
                      child: Text(
                        _searchController.text.isEmpty
                            ? "Type above to search and add members"
                            : "No users found",
                        style: const TextStyle(color: Colors.grey, fontSize: 13),
                      ),
                    )
                  : ListView.builder(
                      itemCount: _searchResults.length,
                      itemBuilder: (context, index) {
                        final user = _searchResults[index];
                        final isSelected = _selectedMembers.any((m) => m.id == user.id);

                        return CheckboxListTile(
                          activeColor: Colors.pinkAccent,
                          title: Text(user.username, style: const TextStyle(fontWeight: FontWeight.w600)),
                          subtitle: Text(user.email, style: const TextStyle(fontSize: 12)),
                          secondary: CircleAvatar(
                            backgroundColor: Colors.pinkAccent.shade100,
                            child: Text(user.username[0].toUpperCase(),
                                style: const TextStyle(color: Colors.white)),
                          ),
                          value: isSelected,
                          onChanged: (_) => _toggleMember(user),
                        );
                      },
                    ),
            ),

            const SizedBox(height: 12),

            // Create Group Button
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.pinkAccent,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: _isSubmitting ? null : _submitGroup,
                icon: _isSubmitting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                      )
                    : const Icon(Icons.group_add, color: Colors.white),
                label: Text(
                  _isSubmitting ? "Creating..." : "Create Group (${_selectedMembers.length} selected)",
                  style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
