import 'package:flutter/material.dart';
import 'package:love_in_chat/model/Response/ConversationResponse.dart';

class CardConversation extends StatelessWidget {
  final ConversationResponse conversationResponse;

  const CardConversation({
    super.key,
    required this.conversationResponse,
  });

  @override
  Widget build(BuildContext context) {
    // Determine if it's a group chat based on your ConversationType
    final bool isGroup = conversationResponse.type.toString().toUpperCase().contains('GROUP');

    // Fallback name if conversation name is null (e.g., use the first member's name for private chats)
    final String displayName = conversationResponse.name ??
        (conversationResponse.members.isNotEmpty
            ? conversationResponse.members.first.username
            : 'Chat');

    // Get the last message text or fallback placeholder
    // (media messages store a file path, never show it raw)
    final String lastMessageText = conversationResponse.lastMessage?.previewText ?? "No messages yet";

    // Format time if available
    final String timeText = conversationResponse.lastMessageAt != null
        ? _formatTime(conversationResponse.lastMessageAt!)
        : "";

    return Card(
      elevation: 1,
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        leading: CircleAvatar(
          backgroundColor: Colors.pinkAccent,
          child: Icon(
            isGroup ? Icons.group : Icons.person,
            color: Colors.white,
          ),
        ),
        title: Text(
          displayName,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(
          lastMessageText,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Text(
          timeText,
          style: const TextStyle(fontSize: 12, color: Colors.grey),
        ),
        onTap: () {
          // TODO: Navigate to ConversationPage with this conversationResponse
        },
      ),
    );
  }

  // Helper method to format DateTime to a readable short time string
  String _formatTime(DateTime dateTime) {
    final hour = dateTime.hour.toString().padLeft(2, '0');
    final minute = dateTime.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }
}