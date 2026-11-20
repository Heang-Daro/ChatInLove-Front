import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:love_in_chat/model/Response/ConversationResponse.dart';
import 'package:love_in_chat/provider/AuthProvider.dart';
import 'package:love_in_chat/provider/ConversationProvider.dart';
import '../../screen/CallScreen.dart';
import '../../screen/GroupCallScreen.dart';
import '../../util/AnimatedComponents.dart';
import 'ConversationDetailPage.dart';

class ConversationHeader extends StatelessWidget implements PreferredSizeWidget {
  final String conversationId;
  final String chatName;
  final IconData avatar;
  final bool isGroup;

  const ConversationHeader({
    super.key,
    required this.conversationId,
    required this.chatName,
    required this.avatar,
    required this.isGroup,
  });

  void _navigateToInfo(BuildContext context) {
    ConversationDetailPage.navigate(
      context,
      conversationId: conversationId,
      chatName: chatName,
      avatar: avatar,
      isGroup: isGroup,
    );
  }

  void _showRenameDialog(BuildContext context, String currentTitle) {
    final controller = TextEditingController(text: currentTitle);

    AnimatedDialog.show(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.edit_rounded, color: Colors.pinkAccent),
            SizedBox(width: 8),
            Text("Edit Conversation Title"),
          ],
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(
            hintText: "Enter title...",
            filled: true,
            fillColor: Colors.pink.withValues(alpha: 0.05),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Colors.pinkAccent, width: 1.5),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Cancel", style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.pinkAccent,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () async {
              final newTitle = controller.text.trim();
              if (newTitle.isEmpty) return;
              Navigator.pop(ctx);

              final authProvider = context.read<AuthProvider>();
              final convoProvider = context.read<ConversationProvider>();
              final success = await convoProvider.updateConversation(
                authProvider,
                conversationId,
                name: newTitle,
              );

              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(success ? "Title updated" : "Failed to update title"),
                    backgroundColor: success ? Colors.pinkAccent : Colors.redAccent,
                  ),
                );
              }
            },
            child: const Text("Save", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ConversationProvider>(
      builder: (context, convoProvider, _) {
        final currentConvo = convoProvider.conversations
            .where((c) => c.id == conversationId)
            .firstOrNull;
        final displayTitle = currentConvo?.name?.isNotEmpty == true
            ? currentConvo!.name!
            : chatName;

        return AppBar(
          backgroundColor: Colors.pinkAccent,
          title: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => _navigateToInfo(context),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
              child: Row(
                children: [
                  CircleAvatar(
                    backgroundColor: Colors.white,
                    radius: 18,
                    child: Icon(avatar, color: Colors.pinkAccent, size: 20),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          displayTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 16, color: Colors.white, fontWeight: FontWeight.bold),
                        ),
                        if (isGroup)
                          const Text(
                            "Tap for group info & members",
                            style: TextStyle(fontSize: 11, color: Colors.white70),
                          )
                        else
                          Builder(builder: (context) {
                            final currentUserId = context.read<AuthProvider>().currentUserId ?? '';
                            final other = currentConvo?.members
                                .where((m) => m.userId != currentUserId && m.leftAt == null)
                                .firstOrNull;
                            if (other == null) {
                              return const Text("Tap for contact info",
                                  style: TextStyle(fontSize: 11, color: Colors.white70));
                            }
                            final presence = convoProvider.presenceService.get(other.userId);
                            final label = convoProvider.presenceService.lastSeenLabel(other.userId);
                            return Row(mainAxisSize: MainAxisSize.min, children: [
                              Container(
                                width: 7,
                                height: 7,
                                decoration: BoxDecoration(
                                  color: presence?.online == true ? Colors.lightGreenAccent : Colors.white54,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 5),
                              Text(label.isEmpty ? "Tap for contact info" : label,
                                  style: const TextStyle(fontSize: 11, color: Colors.white70)),
                            ]);
                          }),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            // Quick rename button
            IconButton(
              tooltip: 'Edit Title',
              icon: const Icon(Icons.edit_note_rounded, color: Colors.white),
              onPressed: () => _showRenameDialog(context, displayTitle),
            ),
            // Audio call button
            IconButton(
              tooltip: isGroup ? 'Group voice call' : 'Voice call',
              icon: const Icon(Icons.call, color: Colors.white),
              onPressed: () => _startCall(context, video: false),
            ),
            // Video call button
            IconButton(
              tooltip: isGroup ? 'Group video call' : 'Video call',
              icon: const Icon(Icons.videocam_outlined, color: Colors.white),
              onPressed: () => _startCall(context, video: true),
            ),
            const SizedBox(width: 4),
          ],
        );
      },
    );
  }

  void _startCall(BuildContext context, {required bool video}) {
    final auth = context.read<AuthProvider>();
    final convos = context.read<ConversationProvider>();
    final currentUserId = auth.currentUserId ?? '';

    final conv = convos.conversations
        .where((c) => c.id == conversationId)
        .firstOrNull;
    if (conv == null) return;

    if (isGroup) {
      // ── Group call — caller path ─────────────────────────────────────────
      final memberUserIds = conv.members
          .where((m) => m.userId != currentUserId && m.leftAt == null)
          .map((m) => m.userId)
          .toList();

      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => GroupCallScreen(
          conversationId: conversationId,
          groupName:      chatName,
          isVideo:        video,
          localUserId:    currentUserId,
          memberUserIds:  memberUserIds,
          // callerUserId is null → this device is the caller
        ),
      ));
    } else {
      // ── 1-to-1 call ──────────────────────────────────────────────────────
      final other = conv.members
          .where((m) => m.userId != currentUserId && m.leftAt == null)
          .firstOrNull;
      if (other == null) return;

      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => CallScreen(
          remoteUserId:     other.userId,
          remoteName:       other.username,
          conversationId:   conversationId,
          isVideo:          video,
          signalingService: convos.callSignaling,
        ),
      ));
    }
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}
