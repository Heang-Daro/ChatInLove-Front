import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:love_in_chat/provider/AuthProvider.dart';
import 'package:love_in_chat/provider/ConversationProvider.dart';
import '../../screen/CallScreen.dart';
import '../../screen/GroupCallScreen.dart';
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

  @override
  Widget build(BuildContext context) {
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
                      chatName,
                      style: const TextStyle(fontSize: 16, color: Colors.white),
                    ),
                    Text(
                      isGroup ? "Tap for group info & members" : "Tap for contact info",
                      style: const TextStyle(fontSize: 11, color: Colors.white70),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.info_outline, color: Colors.white),
          onPressed: () => _navigateToInfo(context),
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
      // ── Group call ───────────────────────────────────────────────────────
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => GroupCallScreen(
          conversationId: conversationId,
          groupName:      chatName,
          isVideo:        video,
          members:        conv.members,
          localUserId:    currentUserId,
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
