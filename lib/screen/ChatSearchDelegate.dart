import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'package:love_in_chat/model/Response/ConversationResponse.dart';
import 'package:love_in_chat/model/Response/UserResponse.dart';
import 'package:love_in_chat/model/emun/ConversationStatus.dart';
import 'package:love_in_chat/provider/AuthProvider.dart';
import 'package:love_in_chat/provider/ConversationProvider.dart';
import 'ConversationPage.dart';
import 'UserProfileScreen.dart';

const Color _brand = Colors.pinkAccent;
const Duration _debounce = Duration(milliseconds: 350);

class ChatSearchDelegate extends SearchDelegate<UserResponse?> {
  final Map<String, Future<List<UserResponse>>> _searches = {};

  ChatSearchDelegate() : super(searchFieldLabel: 'Search people by username');

  @override
  ThemeData appBarTheme(BuildContext context) {
    final base = Theme.of(context);
    return base.copyWith(
      scaffoldBackgroundColor: base.colorScheme.surface,
      appBarTheme: base.appBarTheme.copyWith(
        backgroundColor: _brand,
        foregroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Colors.white),
        actionsIconTheme: const IconThemeData(color: Colors.white),
        systemOverlayStyle: SystemUiOverlayStyle.light, // readable status bar
        elevation: 0,
      ),
      textSelectionTheme: const TextSelectionThemeData(
        cursorColor: Colors.white,
        selectionHandleColor: Colors.white,
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
      return const _SearchState(
        icon: Icons.person_search_rounded,
        title: 'Find someone to chat with',
        message: 'Type a username above to find people on In Love.',
      );
    }
    return _buildResults(context);
  }

  /// Waits briefly so we don't hit the server on every keystroke.
  /// If the user kept typing, the outdated request is skipped.
  Future<List<UserResponse>> _search(
      ConversationProvider conversations,
      AuthProvider auth,
      String term,
      ) async {
    await Future.delayed(_debounce);
    if (term != query.trim()) {
      _searches.remove(term); // don't cache a skipped search
      return const [];
    }
    return conversations.searchUsersFuture(auth, term);
  }

  Widget _buildResults(BuildContext context) {
    final auth = context.read<AuthProvider>();
    final conversations = context.read<ConversationProvider>();
    final currentUserId = auth.currentUserId ?? '';
    final term = query.trim();
    final future = _searches.putIfAbsent(
      term,
          () => _search(conversations, auth, term),
    );

    return FutureBuilder<List<UserResponse>>(
      key: ValueKey(term),
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: _brand));
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

        final filtered = (snapshot.data ?? const <UserResponse>[])
            .where((u) => u.id != currentUserId)
            .toList();

        if (filtered.isEmpty) {
          return _SearchState(
            icon: Icons.person_off_outlined,
            title: 'No people found',
            message: 'Nobody matches "$term". Check the spelling or try another username.',
          );
        }

        return ListView.separated(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          itemCount: filtered.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (context, index) {
            final user = filtered[index];
            return _UserSearchCard(
              key: ValueKey(user.id),
              user: user,
              onViewProfile: () => _openProfile(context, user),
            );
          },
        );
      },
    );
  }

  void _openProfile(BuildContext context, UserResponse user) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => Scaffold(
        appBar: AppBar(
          backgroundColor: _brand,
          foregroundColor: Colors.white,
          title: Text(user.username),
          elevation: 0,
        ),
        body: UserProfileScreen.visitor(user: user),
      ),
    ));
  }
}

// ── Result card: tap anywhere = view profile, button = message ───────────────
class _UserSearchCard extends StatefulWidget {
  final UserResponse user;
  final VoidCallback onViewProfile;

  const _UserSearchCard({
    super.key,
    required this.user,
    required this.onViewProfile,
  });

  @override
  State<_UserSearchCard> createState() => _UserSearchCardState();
}

class _UserSearchCardState extends State<_UserSearchCard> {
  bool _sending = false;
  bool _requested = false;

  void _toast(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(message),
        backgroundColor: error ? Colors.redAccent : _brand,
        behavior: SnackBarBehavior.floating,
      ));
  }

  Future<void> _message() async {
    if (_sending || _requested) return;
    setState(() => _sending = true);

    final auth = context.read<AuthProvider>();
    final convos = context.read<ConversationProvider>();

    ConversationResponse? conversation;
    try {
      conversation = await convos.createPrivateConversation(auth, widget.user.id);
    } catch (_) {
      conversation = null;
    }

    if (!mounted) return;
    setState(() => _sending = false);

    if (conversation == null) {
      _toast('Could not open this chat. Please try again.', error: true);
      return;
    }

    if (conversation.status == ConversationStatus.PENDING) {
      setState(() => _requested = true);
      _toast('Request sent to ${widget.user.username}. You can chat once they accept.');
      return;
    }

    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ConversationPage(
        conversationId: conversation!.id,
        chatName: widget.user.username,
        avatar: Icons.person,
        isGroup: false,
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final user = widget.user;
    final scheme = Theme.of(context).colorScheme;

    return Card(
      margin: EdgeInsets.zero,
      color: _brand.withValues(alpha: 0.055),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: _brand.withValues(alpha: 0.12)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: widget.onViewProfile,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(children: [
            _InitialAvatar(
                name: user.username, url: user.profileImageUrl, radius: 26),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(user.username,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 15)),
                  const SizedBox(height: 2),
                  Text(user.email,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 12, color: scheme.onSurfaceVariant)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            _requested
                ? const OutlinedButton(
              onPressed: null,
              child: Text('Requested', style: TextStyle(fontSize: 12)),
            )
                : FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: _brand,
                foregroundColor: Colors.white,
                minimumSize: const Size(0, 40), // comfortable tap target
                padding: const EdgeInsets.symmetric(horizontal: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: _sending ? null : _message,
              icon: _sending
                  ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.chat_bubble_outline_rounded,
                  size: 16),
              label: const Text('Message',
                  style: TextStyle(fontSize: 12)),
            ),
          ]),
        ),
      ),
    );
  }
}

// ── Avatar: image if it loads, otherwise the first letter ────────────────────
class _InitialAvatar extends StatelessWidget {
  final String name;
  final String? url;
  final double radius;

  const _InitialAvatar({
    required this.name,
    required this.url,
    required this.radius,
  });

  @override
  Widget build(BuildContext context) {
    final initial = Container(
      color: _brand.withValues(alpha: 0.16),
      alignment: Alignment.center,
      child: Text(
        name.isNotEmpty ? name[0].toUpperCase() : '?',
        style: const TextStyle(
            color: _brand, fontWeight: FontWeight.w800, fontSize: 18),
      ),
    );

    return ClipOval(
      child: SizedBox(
        width: radius * 2,
        height: radius * 2,
        child: url == null || url!.isEmpty
            ? initial
            : Image.network(
          url!,
          fit: BoxFit.cover,
          loadingBuilder: (_, child, progress) =>
          progress == null ? child : initial,
          errorBuilder: (_, __, ___) => initial,
        ),
      ),
    );
  }
}

// ── Empty / error state ──────────────────────────────────────────────────────
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
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: _brand.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 38, color: _brand),
            ),
            const SizedBox(height: 16),
            Text(title,
                textAlign: TextAlign.center,
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text(message,
                textAlign: TextAlign.center,
                style: TextStyle(color: scheme.onSurfaceVariant)),
            if (onRetry != null) ...[
              const SizedBox(height: 12),
              FilledButton.tonalIcon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('Try again'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}