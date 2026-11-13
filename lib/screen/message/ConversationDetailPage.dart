import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:love_in_chat/model/Response/ConversationResponse.dart';
import 'package:love_in_chat/model/Response/UserResponse.dart';
import 'package:love_in_chat/model/emun/ConversationType.dart';
import 'package:love_in_chat/provider/AuthProvider.dart';
import 'package:love_in_chat/provider/ConversationProvider.dart';

class ConversationDetailPage extends StatefulWidget {
  final String conversationId;
  final String chatName;
  final IconData avatar;
  final bool isGroup;

  const ConversationDetailPage({
    super.key,
    required this.conversationId,
    required this.chatName,
    required this.avatar,
    this.isGroup = false,
  });

  static void navigate(
    BuildContext context, {
    required String conversationId,
    required String chatName,
    required IconData avatar,
    required bool isGroup,
  }) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ConversationDetailPage(
          conversationId: conversationId,
          chatName: chatName,
          avatar: avatar,
          isGroup: isGroup,
        ),
      ),
    );
  }

  @override
  State<ConversationDetailPage> createState() => _ConversationDetailPageState();
}

class _ConversationDetailPageState extends State<ConversationDetailPage> {
  bool _isMuted = false;

  void _openAddMembersDialog(ConversationResponse conversation) {
    showDialog(
      context: context,
      builder: (context) => _AddMembersDialog(
        conversationId: widget.conversationId,
        existingMemberIds: conversation.members.map((m) => m.userId).toList(),
      ),
    );
  }

  void _confirmLeaveOrDelete(bool isGroup) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(isGroup ? "Leave Group" : "Delete Chat"),
        content: Text(
          isGroup
              ? "Are you sure you want to leave ${widget.chatName}? You will no longer receive messages."
              : "Are you sure you want to delete this chat with ${widget.chatName}?",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Cancel", style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () {
              Navigator.pop(ctx); // Close dialog
              Navigator.pop(context); // Return from detail page
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(isGroup ? "Left group" : "Chat deleted"),
                ),
              );
            },
            child: Text(
              isGroup ? "Leave" : "Delete",
              style: const TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(30),
          child: Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: Colors.pink.shade50,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: Colors.pinkAccent, size: 22),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: Colors.black87,
          ),
        ),
      ],
    );
  }

  Widget _buildSectionCard({required List<Widget> children}) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
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
            type: widget.isGroup ? ConversationType.GROUP : ConversationType.PRIVATE,
            name: widget.chatName,
            members: const [],
          ),
        );

        final members = conversation.members;

        return Scaffold(
          body: CustomScrollView(
            slivers: [
              // Telegram/Messenger style SliverAppBar
              SliverAppBar(
                expandedHeight: 240.0,
                pinned: true,
                backgroundColor: Colors.pinkAccent,
                iconTheme: const IconThemeData(color: Colors.white),
                flexibleSpace: FlexibleSpaceBar(
                  centerTitle: true,
                  title: Text(
                    widget.chatName,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                  background: Stack(
                    alignment: Alignment.center,
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.pink.shade400,
                              Colors.pinkAccent,
                            ],
                          ),
                        ),
                      ),
                      Positioned(
                        top: 50,
                        child: Column(
                          children: [
                            CircleAvatar(
                              radius: 46,
                              backgroundColor: Colors.white,
                              child: CircleAvatar(
                                radius: 43,
                                backgroundColor: Colors.pink.shade100,
                                child: Icon(
                                  widget.avatar,
                                  size: 48,
                                  color: Colors.pinkAccent,
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              widget.isGroup
                                  ? "${members.length} members"
                                  : "Online",
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                  child: Column(
                    children: [
                      // Quick Action Buttons
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          _buildQuickActionButton(
                            icon: Icons.call_outlined,
                            label: "Audio",
                            onTap: () {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text("Starting audio call...")),
                              );
                            },
                          ),
                          _buildQuickActionButton(
                            icon: Icons.videocam_outlined,
                            label: "Video",
                            onTap: () {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text("Starting video call...")),
                              );
                            },
                          ),
                          _buildQuickActionButton(
                            icon: _isMuted
                                ? Icons.notifications_off_outlined
                                : Icons.notifications_none_outlined,
                            label: _isMuted ? "Unmute" : "Mute",
                            onTap: () {
                              setState(() => _isMuted = !_isMuted);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    _isMuted
                                        ? "Notifications muted"
                                        : "Notifications unmuted",
                                  ),
                                ),
                              );
                            },
                          ),
                          _buildQuickActionButton(
                            icon: Icons.search_rounded,
                            label: "Search",
                            onTap: () {
                              Navigator.pop(context); // Go back to chat
                            },
                          ),
                        ],
                      ),

                      const SizedBox(height: 20),

                      // Group Info / Description Card
                      _buildSectionCard(
                        children: [
                          if (widget.isGroup) ...[
                            ListTile(
                              leading: const Icon(Icons.info_outline, color: Colors.pinkAccent),
                              title: const Text("Description"),
                              subtitle: Text(
                                (conversation.description != null &&
                                        conversation.description!.isNotEmpty)
                                    ? conversation.description!
                                    : "No description set for this group.",
                                style: const TextStyle(color: Colors.black87),
                              ),
                            ),
                            const Divider(height: 1, indent: 56),
                          ] else ...[
                            ListTile(
                              leading: const Icon(Icons.alternate_email, color: Colors.pinkAccent),
                              title: const Text("Username"),
                              subtitle: Text("@${widget.chatName.replaceAll(' ', '').toLowerCase()}"),
                            ),
                            const Divider(height: 1, indent: 56),
                          ],
                          SwitchListTile(
                            secondary: const Icon(Icons.notifications_active_outlined,
                                color: Colors.pinkAccent),
                            title: const Text("Notifications"),
                            value: !_isMuted,
                            activeTrackColor: Colors.pinkAccent,
                            onChanged: (val) {
                              setState(() => _isMuted = !val);
                            },
                          ),
                        ],
                      ),

                      const SizedBox(height: 16),

                      // Members Section (If Group)
                      if (widget.isGroup) ...[
                        _buildSectionCard(
                          children: [
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    "Group Members (${members.length})",
                                    style: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.pinkAccent,
                                    ),
                                  ),
                                  TextButton.icon(
                                    onPressed: () => _openAddMembersDialog(conversation),
                                    icon: const Icon(Icons.person_add, size: 18, color: Colors.pinkAccent),
                                    label: const Text("Add", style: TextStyle(color: Colors.pinkAccent)),
                                  ),
                                ],
                              ),
                            ),
                            if (members.isEmpty)
                              const Padding(
                                padding: EdgeInsets.all(16.0),
                                child: Text(
                                  "No member list available",
                                  style: TextStyle(color: Colors.grey),
                                ),
                              )
                            else
                              ListView.separated(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                itemCount: members.length,
                                separatorBuilder: (_, _) => const Divider(height: 1, indent: 68),
                                itemBuilder: (context, index) {
                                  final member = members[index];
                                  final isAdmin = member.role.toUpperCase() == "ADMIN";

                                  return ListTile(
                                    leading: CircleAvatar(
                                      backgroundColor: Colors.pink.shade100,
                                      child: Text(
                                        member.username.isNotEmpty
                                            ? member.username[0].toUpperCase()
                                            : "?",
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
                                    subtitle: Text(
                                      isAdmin ? "Administrator" : "Member",
                                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                                    ),
                                    trailing: isAdmin
                                        ? Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 8, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: Colors.pink.shade50,
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
                                        : null,
                                  );
                                },
                              ),
                          ],
                        ),
                        const SizedBox(height: 16),
                      ],

                      // Shared Media / Links / Files Section (Telegram / Messenger style)
                      _buildSectionCard(
                        children: [
                          ListTile(
                            leading: const Icon(Icons.perm_media_outlined, color: Colors.pinkAccent),
                            title: const Text("Shared Media & Files"),
                            trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 16),
                            onTap: () {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text("Shared media coming soon")),
                              );
                            },
                          ),
                          const Divider(height: 1, indent: 56),
                          ListTile(
                            leading: const Icon(Icons.lock_outline, color: Colors.pinkAccent),
                            title: const Text("Encryption"),
                            subtitle: const Text("Messages are end-to-end encrypted"),
                            trailing: const Icon(Icons.verified_user, color: Colors.green, size: 20),
                          ),
                        ],
                      ),

                      const SizedBox(height: 20),

                      // Leave / Delete Action
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.redAccent,
                            side: const BorderSide(color: Colors.redAccent),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          onPressed: () => _confirmLeaveOrDelete(widget.isGroup),
                          icon: Icon(
                            widget.isGroup ? Icons.exit_to_app : Icons.delete_outline,
                          ),
                          label: Text(
                            widget.isGroup ? "Leave Group" : "Delete Conversation",
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),

                      const SizedBox(height: 30),
                    ],
                  ),
                ),
              ),
            ],
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
        Navigator.pop(context);
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
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.pinkAccent,
                        ),
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
