import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:love_in_chat/data/database/app_database.dart';
import 'package:love_in_chat/data/repositories/chat_repository.dart';
import 'package:love_in_chat/util/AppBarStyle.dart';

import 'chat_screen.dart';

/// Offline chat list.
///
/// Reads the chats from the local database, shows the unread counter and
/// offers a manual "sync missed messages" action. Pull to refresh downloads
/// the conversation list from the backend into SQLite.
class ChatListScreen extends StatefulWidget {
  const ChatListScreen({super.key});

  @override
  State<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen> {
  bool _syncing = false;

  Future<void> _refresh() async {
    final repo = context.read<ChatRepository>();
    await repo.refreshChatList();
    await repo.syncMissedMessages(0);
  }

  Future<void> _syncMissed() async {
    if (_syncing) return;
    setState(() => _syncing = true);

    final repo = context.read<ChatRepository>();
    final count = await repo.syncMissedMessages(0);
    await repo.refreshChatList();

    if (!mounted) return;
    setState(() => _syncing = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          count == 0 ? 'Everything is up to date' : '$count message(s) synced',
        ),
        backgroundColor: Colors.pinkAccent,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<ChatRepository>();

    return Scaffold(
      appBar: AppBarStyle.build(
        title: "Offline chats",
        actions: [
          IconButton(
            tooltip: "Sync missed messages",
            onPressed: _syncing ? null : _syncMissed,
            icon: _syncing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.sync, color: Colors.white),
          ),
        ],
      ),
      body: StreamBuilder<List<Chat>>(
        stream: repo.watchChats(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Text(
                'Database error:\n${snapshot.error}',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.grey),
              ),
            );
          }

          final chats = snapshot.data ?? const <Chat>[];

          if (chats.isEmpty) {
            return RefreshIndicator(
              color: Colors.pinkAccent,
              onRefresh: _refresh,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: const [
                  SizedBox(height: 120),
                  Center(
                    child: Text(
                      'No chats cached yet.\nPull down to download them.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey),
                    ),
                  ),
                ],
              ),
            );
          }

          return RefreshIndicator(
            color: Colors.pinkAccent,
            onRefresh: _refresh,
            child: ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              itemCount: chats.length,
              itemBuilder: (context, index) {
                final chat = chats[index];
                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: Colors.pinkAccent.withOpacity(0.15),
                    child: const Icon(Icons.forum, color: Colors.pinkAccent),
                  ),
                  title: Text(
                    chat.name.isEmpty ? 'Chat' : chat.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    chat.lastMessage ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: chat.unreadCount > 0
                      ? CircleAvatar(
                          radius: 11,
                          backgroundColor: Colors.pinkAccent,
                          child: Text(
                            '${chat.unreadCount}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        )
                      : null,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ChatScreen(
                          chatId: chat.id,
                          title: chat.name.isEmpty ? 'Chat' : chat.name,
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          );
        },
      ),
    );
  }
}
