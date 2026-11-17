import 'package:flutter/material.dart';
import 'package:love_in_chat/api/api.dart';
import 'package:love_in_chat/model/Response/MessageResponse.dart';

/// Bubble widget for displaying file attachments.
class FileMessageBubble extends StatelessWidget {
  final MessageResponse message;
  final bool isMe;

  const FileMessageBubble({
    super.key,
    required this.message,
    required this.isMe,
  });

  @override
  Widget build(BuildContext context) {
    final fileName = fileNameFromUrl(message.content);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: isMe ? Colors.white24 : Colors.pink.shade50,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            Icons.insert_drive_file_rounded,
            color: isMe ? Colors.white : Colors.pinkAccent,
            size: 26,
          ),
        ),
        const SizedBox(width: 10),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                fileName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: isMe ? Colors.white : Theme.of(context).textTheme.bodyLarge?.color,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                "Attachment Document",
                style: TextStyle(
                  fontSize: 11,
                  color: isMe ? Colors.white70 : Colors.grey,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
