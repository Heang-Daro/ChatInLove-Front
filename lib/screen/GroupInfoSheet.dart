import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:love_in_chat/model/Response/ConversationResponse.dart';
import 'package:love_in_chat/model/Response/UserResponse.dart';
import 'package:love_in_chat/model/emun/ConversationType.dart';
import 'package:love_in_chat/provider/AuthProvider.dart';
import 'package:love_in_chat/provider/ConversationProvider.dart';

class GroupInfoSheet extends StatefulWidget {
  final String conversationId;
  final String chatName;

  const GroupInfoSheet({
    super.key,
    required this.conversationId,
    required this.chatName,
  });

  static void show(BuildContext context, {required String conversationId, required String chatName}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => GroupInfoSheet(
        conversationId: conversationId,
        chatName: chatName,
      ),
    );
  }

  @override
  State<GroupInfoSheet> createState() => _GroupInfoSheetState();
}

class _GroupInfoSheetState extends State<GroupInfoSheet> {
  void _openAddMembersDialog(ConversationResponse conversation) {
    showDialog(
      context: context,
      builder: (context) => _AddMembersDialog(
        conversationId: widget.conversationId,
        existingMemberIds: conversation.members.map((m) => m.userId).toList(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ConversationProvider>(
      builder: (context, convoProvider, child) {
        final conversation = convoProvider.conversations.firstWhere(
          (c) => c.id == widget.conversationId,
          orElse: () => ConversationResponse(
            id: widget.conversationId,
            type: ConversationType.GROUP,
            name: widget.chatName,
            members: const [],
          ),
        );

        final members = conversation.members;

        return Container(
          decoration: BoxDecoration(
            color: Theme.of(context).scaffoldBackgroundColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: EdgeInsets.only(
            top: 12,
            left: 20,
            right: 20,
            bottom: MediaQuery.of(context).viewInsets.bottom + 20,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Top handle
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade400,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 16),

                // Group Avatar
                CircleAvatar(
                  radius: 40,
                  backgroundColor: Colors.pinkAccent.shade100,
                  child: const Icon(Icons.group, size: 44, color: Colors.pinkAccent),
                ),
                const SizedBox(height: 12),

                // Group Name
                Text(
                  conversation.name ?? widget.chatName,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),

                if (conversation.description != null && conversation.description!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    conversation.description!,
                    style: const TextStyle(color: Colors.grey, fontSize: 13),
                    textAlign: TextAlign.center,
                  ),
                ],

                const SizedBox(height: 8),

                // Members Count Chip
                Chip(
                  avatar: const Icon(Icons.people, size: 16, color: Colors.pinkAccent),
                  label: Text("${members.length} Members"),
                  backgroundColor: Colors.pink.shade50,
                  side: BorderSide.none,
                ),

                const SizedBox(height: 16),

                // Add Member Action Button
                SizedBox(
                  width: double.infinity,
                  height: 44,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.pinkAccent,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: () => _openAddMembersDialog(conversation),
                    icon: const Icon(Icons.person_add, color: Colors.white, size: 20),
                    label: const Text(
                      "Add Members",
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),

                const SizedBox(height: 20),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    "Group Members",
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: Colors.pinkAccent,
                    ),
                  ),
                ),
                const SizedBox(height: 8),

                // Members List
                if (members.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Text("No member list available", style: TextStyle(color: Colors.grey)),
                  )
                else
                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: members.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final member = members[index];
                      final isAdmin = member.role.toUpperCase() == "ADMIN";

                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: CircleAvatar(
                          backgroundColor: Colors.pink.shade100,
                          child: Text(
                            member.username.isNotEmpty ? member.username[0].toUpperCase() : "?",
                            style: const TextStyle(
                              color: Colors.pinkAccent,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        title: Text(
                          member.username,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        trailing: isAdmin
                            ? Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.pinkAccent.shade100,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Text(
                                  "ADMIN",
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.pinkAccent,
                                  ),
                                ),
                              )
                            : const Text(
                                "MEMBER",
                                style: TextStyle(fontSize: 11, color: Colors.grey),
                              ),
                      );
                    },
                  ),

                const SizedBox(height: 20),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _AddMembersDialog extends StatefulWidget {
  final String conversationId;
  final List<String> existingMemberIds;

  const _AddMembersDialog({
    required this.conversationId,
    required this.existingMemberIds,
  });

  @override
  State<_AddMembersDialog> createState() => _AddMembersDialogState();
}

class _AddMembersDialogState extends State<_AddMembersDialog> {
  final _searchController = TextEditingController();
  final List<UserResponse> _selectedUsers = [];
  List<UserResponse> _searchResults = [];
  bool _isSearching = false;
  bool _isAdding = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String query) async {
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
        // Filter out users who are already in the group
        _searchResults = results
            .where((u) => !widget.existingMemberIds.contains(u.id))
            .toList();
        _isSearching = false;
      });
    }
  }

  void _toggleUser(UserResponse user) {
    setState(() {
      if (_selectedUsers.any((u) => u.id == user.id)) {
        _selectedUsers.removeWhere((u) => u.id == user.id);
      } else {
        _selectedUsers.add(user);
      }
    });
  }

  void _submitAddMembers() async {
    if (_selectedUsers.isEmpty) return;

    setState(() => _isAdding = true);

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final convoProvider = Provider.of<ConversationProvider>(context, listen: false);

    final newIds = _selectedUsers.map((u) => u.id).toList();
    final success = await convoProvider.addMembersToGroup(
      authProvider,
      widget.conversationId,
      newIds,
    );

    if (mounted) {
      setState(() => _isAdding = false);
      if (success) {
        Navigator.pop(context); // Close dialog
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('New members added successfully!')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to add members. Try again.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Row(
        children: [
          Icon(Icons.person_add, color: Colors.pinkAccent),
          SizedBox(width: 8),
          Text("Add Members"),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _searchController,
              onChanged: _onSearchChanged,
              decoration: InputDecoration(
                hintText: "Search username...",
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
            const SizedBox(height: 12),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 200),
              child: _searchResults.isEmpty
                  ? Center(
                      child: Text(
                        _searchController.text.isEmpty
                            ? "Type to search users"
                            : "No new users found",
                        style: const TextStyle(color: Colors.grey, fontSize: 12),
                      ),
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      itemCount: _searchResults.length,
                      itemBuilder: (context, index) {
                        final user = _searchResults[index];
                        final isSelected = _selectedUsers.any((u) => u.id == user.id);

                        return CheckboxListTile(
                          activeColor: Colors.pinkAccent,
                          title: Text(user.username),
                          value: isSelected,
                          onChanged: (_) => _toggleUser(user),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text("Cancel", style: TextStyle(color: Colors.grey)),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: Colors.pinkAccent),
          onPressed: _selectedUsers.isEmpty || _isAdding ? null : _submitAddMembers,
          child: _isAdding
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                )
              : Text(
                  "Add (${_selectedUsers.length})",
                  style: const TextStyle(color: Colors.white),
                ),
        ),
      ],
    );
  }
}
