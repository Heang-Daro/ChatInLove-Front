import 'package:flutter/material.dart';

class ChatInputBar extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onSendPressed;
  final VoidCallback onAttachmentPressed;

  const ChatInputBar({
    super.key,
    required this.controller,
    required this.onSendPressed,
    required this.onAttachmentPressed,
  });

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      color: Theme.of(context).cardColor,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // Messenger-style attachment icon button
          IconButton(
            icon: const Icon(Icons.add_circle_rounded, color: Colors.blue, size: 28),
            onPressed: onAttachmentPressed,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
          const SizedBox(width: 8),

          // Expanding text field with pill shape
          Expanded(
            child: TextField(
              controller: controller,
              maxLines: 4,
              minLines: 1,
              decoration: InputDecoration(
                hintText: "Aa", // Classic Messenger placeholder hint
                hintStyle: TextStyle(color: isDarkMode ? Colors.grey[500] : Colors.grey),
                filled: true,
                fillColor: isDarkMode ? Colors.grey[850] : Colors.grey[200],
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(20),
                  borderSide: BorderSide.none,
                ),
              ),
              onSubmitted: (_) => onSendPressed(),
            ),
          ),
          const SizedBox(width: 8),

          // Send button styled like Messenger
          IconButton(
            icon: const Icon(Icons.send_rounded, color: Colors.blue, size: 22),
            onPressed: onSendPressed,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }
}