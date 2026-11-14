import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:love_in_chat/model/Response/UserResponse.dart';
import 'package:love_in_chat/model/Response/ConversationResponse.dart';
import 'package:love_in_chat/model/emun/ConversationStatus.dart';
import 'package:love_in_chat/provider/AuthProvider.dart';
import 'package:love_in_chat/provider/ConversationProvider.dart';
import 'ConversationPage.dart';

class ChatSearchDelegate extends SearchDelegate<UserResponse?> {
  final Map<String, Future<List<UserResponse>>> _searches = {};
  bool _openingConversation = false;

  ChatSearchDelegate() : super(searchFieldLabel: 'Search people by username');

  @override
  ThemeData appBarTheme(BuildContext context) {
    final base = Theme.of(context);
    return base.copyWith(
      scaffoldBackgroundColor: base.colorScheme.surface,
      appBarTheme: base.appBarTheme.copyWith(
        backgroundColor: Colors.pinkAccent,
        foregroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Colors.white),
        actionsIconTheme: const IconThemeData(color: Colors.white),
        elevation: 0,
      ),
      inputDecorationTheme: const InputDecorationTheme(
        hintStyle: TextStyle(color: Colors.white70),
        border: InputBorder.none,
      ),
    );
  }

  @override
  TextStyle? get searchFieldStyle => const TextStyle(
        color: Colors.white,
        fontSize: 18,
        fontWeight: FontWeight.w500,
      );

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
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (context, index) {
            final user = users[index];
            return Card(
              margin: EdgeInsets.zero,
              color: Colors.pinkAccent.withValues(alpha: 0.055),
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
                side: BorderSide(color: Colors.pinkAccent.withValues(alpha: 0.12)),
              ),
              clipBehavior: Clip.antiAlias,
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                leading: CircleAvatar(
                  radius: 25,
                  backgroundColor: Colors.pinkAccent.withValues(alpha: 0.16),
                  child: Text(
                    user.username.isNotEmpty ? user.username[0].toUpperCase() : '?',
                    style: const TextStyle(color: Colors.pinkAccent, fontWeight: FontWeight.w800),
                  ),
                ),
                title: Text(user.username, style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text(user.email, maxLines: 1, overflow: TextOverflow.ellipsis),
                trailing: Container(
                  padding: const EdgeInsets.all(9),
                  decoration: BoxDecoration(color: Colors.pinkAccent.withValues(alpha: 0.12), shape: BoxShape.circle),
                  child: const Icon(Icons.chat_bubble_outline_rounded, color: Colors.pinkAccent, size: 19),
                ),
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
      Navigator.of(context, rootNavigator: true).pop(); // dismiss spinner

      if (conversation == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open this conversation. Please try again.')),
        );
        return;
      }

      // The backend may return a PENDING conversation when the recipient must
      // approve the request first. Opening the chat in that state causes a 403
      // which previously triggered a logout. Show a friendly message instead.
      if (conversation.status == ConversationStatus.PENDING) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Chat request sent to ${user.username}. You can chat once they accept.'),
            backgroundColor: Colors.pinkAccent,
            behavior: SnackBarBehavior.floating,
          ),
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
