import 'package:flutter/material.dart';
import 'package:love_in_chat/model/Response/MessageResponse.dart';
import 'package:love_in_chat/model/emun/MessageType.dart';

class MessageBubble extends StatelessWidget {
  final MessageResponse message;
  final bool isMe;
  final String? senderAvatarUrl;

  const MessageBubble({
    super.key,
    required this.message,
    required this.isMe,
    this.senderAvatarUrl,
  });

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final String timeString = message.createdAt != null
        ? "${message.createdAt!.hour.toString().padLeft(2, '0')}:${message.createdAt!.minute.toString().padLeft(2, '0')}"
        : "";

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 10),
      child: Row(
        mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // Facebook Messenger style: Show sender avatar for incoming messages
          if (!isMe) ...[
            CircleAvatar(
              radius: 14,
              backgroundColor: Colors.pink.shade100,
              child: Text(
                message.senderUsername.isNotEmpty
                    ? message.senderUsername[0].toUpperCase()
                    : "?",
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: Colors.pinkAccent,
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],

          // Facebook Messenger Bubble Container
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.72,
              ),
              decoration: BoxDecoration(
                // Facebook Messenger Gradient for Sent Messages
                gradient: isMe
                    ? const LinearGradient(
                        colors: [Color(0xFFFF007A), Color(0xFF9E00FF)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      )
                    : null,
                color: isMe
                    ? null
                    : (isDark ? const Color(0xFF3E4042) : const Color(0xFFE4E6EB)),
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(20),
                  topRight: const Radius.circular(20),
                  bottomLeft: Radius.circular(isMe ? 20 : 4),
                  bottomRight: Radius.circular(isMe ? 4 : 20),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildContent(context, isDark),
                  const SizedBox(height: 3),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        timeString,
                        style: TextStyle(
                          fontSize: 9.5,
                          color: isMe
                              ? Colors.white70
                              : (isDark ? Colors.grey.shade400 : Colors.grey.shade600),
                        ),
                      ),
                      if (isMe) ...[
                        const SizedBox(width: 4),
                        Icon(
                          message.isRead ? Icons.check_circle : Icons.check_circle_outline,
                          size: 11,
                          color: Colors.white70,
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(BuildContext context, bool isDark) {
    final Color textColor = isMe
        ? Colors.white
        : (isDark ? Colors.white : Colors.black87);

    switch (message.type) {
      case MessageType.IMAGE:
        return ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Image.network(
            message.content,
            width: 220,
            height: 160,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Container(
              width: 220,
              height: 100,
              color: Colors.grey.shade300,
              child: const Icon(Icons.broken_image, color: Colors.grey),
            ),
          ),
        );

      case MessageType.VOICE:
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.play_circle_fill, color: textColor, size: 28),
            const SizedBox(width: 8),
            Text("Voice Note", style: TextStyle(color: textColor, fontWeight: FontWeight.bold)),
          ],
        );

      case MessageType.VIDEO:
        return Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: 220,
              height: 140,
              decoration: BoxDecoration(
                color: Colors.black87,
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(Icons.play_circle_fill, size: 48, color: Colors.white),
            ),
          ],
        );

      case MessageType.FILE:
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.insert_drive_file, color: textColor, size: 24),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                message.content.split('/').last,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: textColor, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        );

      case MessageType.TEXT:
      default:
        return Text(
          message.content,
          style: TextStyle(color: textColor, fontSize: 14.5),
        );
    }
  }
}
