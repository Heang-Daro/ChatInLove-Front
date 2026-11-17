import 'package:flutter/material.dart';
import 'package:love_in_chat/model/Response/MessageResponse.dart';

/// Bubble widget for system notice messages inside the conversation.
class SystemMessageBubble extends StatelessWidget {
  final MessageResponse message;

  const SystemMessageBubble({
    super.key,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.grey.shade300,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          message.content,
          style: const TextStyle(fontSize: 11, color: Colors.black87),
        ),
      ),
    );
  }
}
