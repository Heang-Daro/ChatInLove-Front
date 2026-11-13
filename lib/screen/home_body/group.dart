import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:love_in_chat/model/Response/ConversationResponse.dart';
import 'package:love_in_chat/provider/AuthProvider.dart';
import 'package:love_in_chat/provider/ConversationProvider.dart';
import '../message/ConversationTile.dart';

class GroupChat extends StatelessWidget {
  final List<ConversationResponse> chats;

  const GroupChat({
    super.key,
    required this.chats,
  });

  Future<void> _refresh(BuildContext context) async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    await Provider.of<ConversationProvider>(context, listen: false)
        .fetchConversations(authProvider);
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId = context.watch<AuthProvider>().currentUserId ?? "";
    final isLoading = context.watch<ConversationProvider>().isLoading;

    if (isLoading && chats.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.pinkAccent),
      );
    }

    if (chats.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.group_outlined, size: 64, color: Colors.grey),
            SizedBox(height: 12),
            Text(
              "No group chats found",
              style: TextStyle(color: Colors.grey, fontSize: 16),
            ),
            SizedBox(height: 4),
            Text(
              "Tap 'New Group' below to create one!",
              style: TextStyle(color: Colors.pinkAccent, fontSize: 13),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      color: Colors.pinkAccent,
      onRefresh: () => _refresh(context),
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        itemCount: chats.length,
        itemBuilder: (context, index) {
          return ConversationTile(
            chat: chats[index],
            currentUserId: currentUserId,
          );
        },
      ),
    );
  }
}
