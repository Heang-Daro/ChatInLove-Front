import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:love_in_chat/model/Response/UserResponse.dart';
import 'package:love_in_chat/model/Response/ConversationResponse.dart';
import 'package:love_in_chat/provider/AuthProvider.dart';
import 'package:love_in_chat/provider/ConversationProvider.dart';

import 'ConversationPage.dart';

class ChatSearchDelegate extends SearchDelegate<UserResponse?> {
  @override
  List<Widget>? buildActions(BuildContext context) {
    return [
      IconButton(
        icon: const Icon(Icons.clear, color: Colors.pinkAccent),
        onPressed: () {
          query = '';
        },
      ),
    ];
  }

  @override
  Widget? buildLeading(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.arrow_back, color: Colors.pinkAccent),
      onPressed: () {
        close(context, null);
      },
    );
  }

  @override
  Widget buildResults(BuildContext context) {
    return _buildUserSearchList(context);
  }

  @override
  Widget buildSuggestions(BuildContext context) {
    if (query.trim().isEmpty) {
      return const Center(
        child: Text(
          'Type a username to search users...',
          style: TextStyle(color: Colors.grey),
        ),
      );
    }
    return _buildUserSearchList(context);
  }

  Widget _buildUserSearchList(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final conversationProvider = Provider.of<ConversationProvider>(context, listen: false);

    return FutureBuilder<List<UserResponse>>(
      future: conversationProvider.searchUsersFuture(authProvider, query),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(color: Colors.pinkAccent),
          );
        }

        if (snapshot.hasError) {
          return const Center(
            child: Text('Failed to load search results', style: TextStyle(color: Colors.grey)),
          );
        }

        final users = snapshot.data ?? [];
        if (users.isEmpty) {
          return const Center(
            child: Text('No users found', style: TextStyle(color: Colors.grey)),
          );
        }

        return ListView.builder(
          itemCount: users.length,
          itemBuilder: (context, index) {
            final user = users[index];
            return ListTile(
              leading: CircleAvatar(
                backgroundColor: Colors.pinkAccent,
                child: Text(
                  user.username.isNotEmpty ? user.username[0].toUpperCase() : '?',
                  style: const TextStyle(color: Colors.white),
                ),
              ),
              title: Text(user.username),
              subtitle: Text(user.email),
              onTap: () async {
                // Show loading indicator or handle creation
                try {
                  // Assuming createPrivateConversation returns the created/existing ConversationResponse
                  ConversationResponse? conversation = await conversationProvider.createPrivateConversation(
                    authProvider,
                    user.id,
                  );

                  if (context.mounted) {
                    // Close the search delegate
                    close(context, user);

                    // Navigate directly to the ConversationPage if conversation was successfully created/fetched
                    if (conversation != null) {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => ConversationPage(
                            conversationId: conversation.id,
                            chatName: user.username,
                            avatar: Icons.person,
                            isGroup: false,
                          ),
                        ),
                      );
                    }
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Failed to open chat: $e')),
                    );
                  }
                }
              },
            );
          },
        );
      },
    );
  }
}