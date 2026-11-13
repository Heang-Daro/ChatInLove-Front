import 'package:flutter/material.dart';
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
        IconButton(icon: const Icon(Icons.call, color: Colors.white), onPressed: () {}),
        const SizedBox(width: 4),
      ],
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}
