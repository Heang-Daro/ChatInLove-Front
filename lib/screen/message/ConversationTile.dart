import 'package:flutter/material.dart';
import 'package:love_in_chat/model/Response/ConversationResponse.dart';
import 'package:love_in_chat/model/Response/MessageResponse.dart';
import 'package:love_in_chat/model/emun/ConversationType.dart';
import 'package:love_in_chat/model/emun/MessageType.dart';
import '../../util/AnimatedComponents.dart';
import '../ConversationPage.dart';

class ConversationTile extends StatelessWidget {
  final ConversationResponse chat;
  final String currentUserId; // required: used to find the OTHER member

  const ConversationTile({
    super.key,
    required this.chat,
    required this.currentUserId,
  });

  IconData? _getMessageIcon(MessageType type) {
    switch (type) {
      case MessageType.IMAGE:
        return Icons.image;
      case MessageType.VIDEO:
        return Icons.videocam;
      case MessageType.VOICE:
        return Icons.mic;
      case MessageType.FILE:
        return Icons.insert_drive_file;
      case MessageType.CALL:
        return Icons.phone;
      case MessageType.SYSTEM:
        return Icons.info_outline;
      case MessageType.TEXT:
      default:
        return null;
    }
  }

  String _getMessageLabel(MessageResponse lastMsg) {
    switch (lastMsg.type) {
      case MessageType.IMAGE:
        return "Image";
      case MessageType.VIDEO:
        return "Video";
      case MessageType.VOICE:
        return "Voice Note";
      case MessageType.FILE:
        return "Document";
      case MessageType.CALL:
        return "Call";
      case MessageType.SYSTEM:
        return lastMsg.content;
      case MessageType.TEXT:
        return lastMsg.content;
    }
  }

  Widget _buildSubtitleContent(
      BuildContext context,
      MessageResponse? lastMsg,
      bool isMyMessage,
      bool hasUnreadMessage,
      ) {
    final Color textColor = hasUnreadMessage
        ? Colors.pinkAccent
        : Theme.of(context).colorScheme.onSurfaceVariant;

    final TextStyle textStyle = TextStyle(
      fontSize: 13,
      fontWeight: hasUnreadMessage ? FontWeight.bold : FontWeight.normal,
      color: textColor,
    );

    if (lastMsg == null) {
      return Text(
        "Tap to start chatting",
        style: textStyle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      );
    }

    final IconData? iconData = _getMessageIcon(lastMsg.type);
    final String label = _getMessageLabel(lastMsg);

    return Row(
      children: [
        if (isMyMessage && lastMsg.isRead) ...[
          const Icon(
            Icons.done_all,
            size: 16,
            color: Colors.pinkAccent,
          ),
          const SizedBox(width: 4),
        ],
        if (isMyMessage) ...[
          Text("You: ", style: textStyle),
        ],
        if (iconData != null) ...[
          Icon(
            iconData,
            size: 15,
            color: textColor,
          ),
          const SizedBox(width: 4),
        ],
        Expanded(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: textStyle,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final isGroup = chat.type == ConversationType.GROUP;

    // Resolve chat name
    String chatName = chat.name ?? "";

    if (chatName.isEmpty && !isGroup) {
      final trimmedId = currentUserId.trim();

      final otherMembers = chat.members.where(
            (m) => m.userId.trim() != trimmedId && m.leftAt == null,
      );

      if (otherMembers.isNotEmpty) {
        chatName = otherMembers.first.username;
      }
    }

    if (chatName.isEmpty) {
      chatName = isGroup ? "Group Chat" : "Chat";
    }

    final avatarIcon = isGroup ? Icons.group : Icons.person;

    // Check read/unread status of the last message
    final lastMsg = chat.lastMessage;
    final bool hasUnreadMessage = lastMsg != null &&
        !lastMsg.isRead &&
        lastMsg.senderId != currentUserId; // Only unread if sent by the other user

    final bool isMyMessage = lastMsg != null && lastMsg.senderId == currentUserId;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      leading: CircleAvatar(
        backgroundColor: Colors.pinkAccent,
        child: Icon(avatarIcon, color: Colors.white),
      ),
      title: Text(
        chatName,
        style: TextStyle(
          fontWeight: hasUnreadMessage ? FontWeight.w900 : FontWeight.bold,
          color: Theme.of(context).colorScheme.onSurface,
        ),
      ),
      subtitle: _buildSubtitleContent(context, lastMsg, isMyMessage, hasUnreadMessage),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            chat.lastMessageAt != null
                ? "${chat.lastMessageAt!.hour}:${chat.lastMessageAt!.minute.toString().padLeft(2, '0')}"
                : "",
            style: TextStyle(
              fontSize: 12,
              color: hasUnreadMessage ? Colors.pinkAccent : Theme.of(context).colorScheme.onSurfaceVariant,
              fontWeight: hasUnreadMessage ? FontWeight.bold : FontWeight.normal,
            ),
          ),
          const SizedBox(height: 4),
          // Unread pink dot badge for incoming messages
          if (hasUnreadMessage)
            Container(
              width: 10,
              height: 10,
              decoration: const BoxDecoration(
                color: Colors.pinkAccent,
                shape: BoxShape.circle,
              ),
            ),
        ],
      ),
      onTap: () {
        Navigator.push(
          context,
          AnimatedPageRoute(
            page: ConversationPage(
              conversationId: chat.id,
              chatName: chatName,
              avatar: avatarIcon,
              isGroup: isGroup,
            ),
          ),
        );
      },
    );
  }
}
