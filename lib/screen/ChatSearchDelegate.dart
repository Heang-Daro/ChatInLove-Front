import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:love_in_chat/model/Response/UserResponse.dart';
import 'package:love_in_chat/provider/AuthProvider.dart';
import 'package:love_in_chat/provider/ConversationProvider.dart';
import 'UserProfileScreen.dart';

class ChatSearchDelegate extends SearchDelegate<UserResponse?> {
  final Map<String, Future<List<UserResponse>>> _searches = {};

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
                child: const Icon(Icons.person_search_rounded,
                    size: 38, color: Colors.pinkAccent),
              ),
              const SizedBox(height: 16),
              Text(
                'Find someone to chat with',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              Text(
                'Type a username above to find people on In Love.',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant),
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
    final currentUserId = auth.currentUserId ?? '';
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
          return const Center(
              child: CircularProgressIndicator(color: Colors.pinkAccent));
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
        // Hide the current user from their own search results.
        final filtered =
            users.where((u) => u.id != currentUserId).toList();

        if (filtered.isEmpty) {
          return const _SearchState(
            icon: Icons.person_off_outlined,
            title: 'No people found',
            message: 'Try another username.',
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          itemCount: filtered.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (context, index) {
            final user = filtered[index];
            return _UserSearchCard(
              user: user,
              onViewProfile: () => _openProfile(context, user),
              onSendMessage: () => _openProfile(context, user, jumpToMessage: true),
            );
          },
        );
      },
    );
  }

  void _openProfile(BuildContext context, UserResponse user,
      {bool jumpToMessage = false}) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => Scaffold(
        appBar: AppBar(
          backgroundColor: Colors.pinkAccent,
          foregroundColor: Colors.white,
          title: Text(user.username),
          elevation: 0,
        ),
        body: UserProfileScreen.visitor(user: user),
      ),
    ));
  }
}

// ── Individual result card ──────────────────────────────────────────────────
class _UserSearchCard extends StatelessWidget {
  final UserResponse user;
  final VoidCallback onViewProfile;
  final VoidCallback onSendMessage;

  const _UserSearchCard({
    required this.user,
    required this.onViewProfile,
    required this.onSendMessage,
  });

  @override
  Widget build(BuildContext context) {
    final hasAvatar =
        user.profileImageUrl != null && user.profileImageUrl!.isNotEmpty;

    return Card(
      margin: EdgeInsets.zero,
      color: Colors.pinkAccent.withValues(alpha: 0.055),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: Colors.pinkAccent.withValues(alpha: 0.12)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(children: [
          // Avatar
          CircleAvatar(
            radius: 26,
            backgroundColor: Colors.pinkAccent.withValues(alpha: 0.16),
            backgroundImage:
                hasAvatar ? NetworkImage(user.profileImageUrl!) : null,
            child: hasAvatar
                ? null
                : Text(
                    user.username.isNotEmpty
                        ? user.username[0].toUpperCase()
                        : '?',
                    style: const TextStyle(
                        color: Colors.pinkAccent,
                        fontWeight: FontWeight.w800,
                        fontSize: 18),
                  ),
          ),
          const SizedBox(width: 14),

          // Name + email
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(user.username,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 15)),
                const SizedBox(height: 2),
                Text(user.email,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant)),
              ],
            ),
          ),
          const SizedBox(width: 8),

          // Action buttons
          _ActionButton(
            icon: Icons.person_outline_rounded,
            label: 'Profile',
            onTap: onViewProfile,
          ),
          const SizedBox(width: 8),
          _ActionButton(
            icon: Icons.send_rounded,
            label: 'Message',
            filled: true,
            onTap: onSendMessage,
          ),
        ]),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool filled;
  final VoidCallback onTap;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.filled = false,
  });

  @override
  Widget build(BuildContext context) {
    if (filled) {
      return FilledButton.icon(
        style: FilledButton.styleFrom(
          backgroundColor: Colors.pinkAccent,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        onPressed: onTap,
        icon: Icon(icon, size: 16),
        label: Text(label, style: const TextStyle(fontSize: 12)),
      );
    }
    return OutlinedButton.icon(
      style: OutlinedButton.styleFrom(
        foregroundColor: Colors.pinkAccent,
        side: const BorderSide(color: Colors.pinkAccent),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      onPressed: onTap,
      icon: Icon(icon, size: 16),
      label: Text(label, style: const TextStyle(fontSize: 12)),
    );
  }
}

// ── Empty / error state ─────────────────────────────────────────────────────
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
              Text(title,
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 16)),
              const SizedBox(height: 6),
              Text(message, textAlign: TextAlign.center),
              if (onRetry != null) ...[
                const SizedBox(height: 8),
                TextButton.icon(
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Try again')),
              ],
            ],
          ),
        ),
      );
}
