import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:love_in_chat/model/Response/UserResponse.dart';
import 'package:love_in_chat/model/Response/ConversationResponse.dart';
import 'package:love_in_chat/provider/AuthProvider.dart';
import 'package:love_in_chat/provider/ConversationProvider.dart';
import 'ConversationPage.dart';

class ChatSearchDelegate extends SearchDelegate<UserResponse?> {
  final Map<String, Future<List<UserResponse>>> _searches = {};
  bool _openingConversation = false;

  ChatSearchDelegate() : super(searchFieldLabel: 'Search people by username');

  @override
  ThemeData appBarTheme(BuildContext context) {
    final theme = Theme.of(context);
    return theme.copyWith(
      appBarTheme: theme.appBarTheme.copyWith(
        backgroundColor: theme.colorScheme.surface,
        foregroundColor: theme.colorScheme.onSurface,
        elevation: 0,
      ),
      inputDecorationTheme: theme.inputDecorationTheme.copyWith(
        hintStyle: TextStyle(color: theme.colorScheme.onSurfaceVariant),
        border: InputBorder.none,
      ),
    );
  }

  @override
  List<Widget> buildActions(BuildContext context) => [
        if (query.isNotEmpty)
          IconButton(
            tooltip: 'Clear search',
            icon: const Icon(Icons.close_rounded),
            onPressed: () => query = '',
          ),
      ];

  @override
  Widget? buildLeading(BuildContext context) => IconButton(
        tooltip: 'Back',
        icon: const Icon(Icons.arrow_back_rounded),
        onPressed: () => close(context, null),
      );

  @override
  Widget buildResults(BuildContext context) => _buildResults(context);

  @override
  Widget buildSuggestions(BuildContext context) {
    if (query.trim().isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.pinkAccent.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.person_search_rounded, size: 38, color: Colors.pinkAccent),
              ),
              const SizedBox(height: 16),
              Text(
                'Find someone to chat with',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              Text(
                'Type a username above to find people on In Love.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      );
    }
    return _buildResults(context);
  }

  Widget _buildResults(BuildContext context) {
    final auth = context.read<AuthProvider>();
    final conversations = context.read<ConversationProvider>();
    final term = query.trim();
    final future = _searches.putIfAbsent(
      term,
      () => conversations.searchUsersFuture(auth, term),
    );

    return FutureBuilder<List<UserResponse>>(
      key: ValueKey(term),
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: Colors.pinkAccent));
        }
        if (snapshot.hasError) {
          return _SearchState(
            icon: Icons.cloud_off_outlined,
            title: 'Search unavailable',
            message: 'Check your connection and try again.',
            onRetry: () {
              _searches.remove(term);
              showResults(context);
            },
          );
        }

        final users = snapshot.data ?? const <UserResponse>[];
        if (users.isEmpty) {
          return const _SearchState(
            icon: Icons.person_off_outlined,
            title: 'No people found',
            message: 'Try another username.',
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          itemCount: users.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            final user = users[index];
            return Card(
              margin: EdgeInsets.zero,
              clipBehavior: Clip.antiAlias,
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                leading: CircleAvatar(
                  backgroundColor: Colors.pinkAccent.withValues(alpha: 0.14),
                  child: Text(
                    user.username.isNotEmpty ? user.username[0].toUpperCase() : '?',
                    style: const TextStyle(color: Colors.pinkAccent, fontWeight: FontWeight.w700),
                  ),
                ),
                title: Text(user.username, style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text(user.email, maxLines: 1, overflow: TextOverflow.ellipsis),
                trailing: const Icon(Icons.chat_bubble_outline_rounded, color: Colors.pinkAccent),
                onTap: _openingConversation
                    ? null
                    : () => _openConversation(context, auth, conversations, user),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _openConversation(
    BuildContext context,
    AuthProvider auth,
    ConversationProvider conversations,
    UserResponse user,
  ) async {
    if (_openingConversation) return;
    _openingConversation = true;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator(color: Colors.pinkAccent)),
    );

    try {
      final ConversationResponse? conversation =
          await conversations.createPrivateConversation(auth, user.id);
      if (!context.mounted) return;
      Navigator.of(context, rootNavigator: true).pop();

      if (conversation == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open this conversation. Please try again.')),
        );
        return;
      }

      close(context, user);
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ConversationPage(
            conversationId: conversation.id,
            chatName: user.username,
            avatar: Icons.person,
            isGroup: false,
          ),
        ),
      );
    } catch (error) {
      if (context.mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open chat: $error')),
        );
      }
    } finally {
      _openingConversation = false;
    }
  }
}

class _SearchState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final VoidCallback? onRetry;

  const _SearchState({
    required this.icon,
    required this.title,
    required this.message,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 42, color: Colors.pinkAccent),
              const SizedBox(height: 12),
              Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
              const SizedBox(height: 6),
              Text(message, textAlign: TextAlign.center),
              if (onRetry != null) ...[
                const SizedBox(height: 8),
                TextButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh), label: const Text('Try again')),
              ],
            ],
          ),
        ),
      );
}
