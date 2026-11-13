import 'package:drift/drift.dart';

import 'app_database.dart';

/// All database operations for the [Chats] table.
class ChatDao {
  ChatDao(this.db);

  final AppDatabase db;

  // ---------------------------------------------------------------------------
  // Streams
  // ---------------------------------------------------------------------------

  /// Watches every chat, newest activity first.
  Stream<List<Chat>> watchChats({int limit = 100}) {
    final query = db.select(db.chats)
      ..orderBy([(c) => OrderingTerm.desc(c.updatedAt)])
      ..limit(limit);
    return query.watch();
  }

  /// Watches a single chat.
  Stream<Chat?> watchChat(String chatId) {
    final query = db.select(db.chats)..where((c) => c.id.equals(chatId));
    return query.watchSingleOrNull();
  }

  // ---------------------------------------------------------------------------
  // Reads
  // ---------------------------------------------------------------------------

  Future<Chat?> getChat(String chatId) {
    return (db.select(db.chats)..where((c) => c.id.equals(chatId)))
        .getSingleOrNull();
  }

  Future<List<String>> allChatIds() async {
    final rows = await db.select(db.chats).get();
    return rows.map((c) => c.id).toList();
  }

  /// Highest server sequence id that was synchronised for a chat.
  Future<int> lastSequenceId(String chatId) async {
    final chat = await getChat(chatId);
    return chat?.lastSequenceId ?? 0;
  }

  // ---------------------------------------------------------------------------
  // Writes
  // ---------------------------------------------------------------------------

  /// Creates or updates a chat. Fields that are not given keep their current
  /// value.
  Future<void> upsertChat({
    required String id,
    String? name,
    String? lastMessage,
    int? unreadCount,
    DateTime? updatedAt,
    int? lastSequenceId,
  }) async {
    final existing = await getChat(id);

    await db.into(db.chats).insert(
          ChatsCompanion.insert(
            id: id,
            name: Value(name ?? existing?.name ?? ''),
            lastMessage: Value(lastMessage ?? existing?.lastMessage),
            unreadCount: Value(unreadCount ?? existing?.unreadCount ?? 0),
            updatedAt: Value(updatedAt ?? existing?.updatedAt ?? DateTime.now()),
            lastSequenceId:
                Value(lastSequenceId ?? existing?.lastSequenceId ?? 0),
          ),
          mode: InsertMode.insertOrReplace,
        );
  }

  /// Updates the chat after a new message arrived.
  ///
  /// [incrementUnread] is `false` for messages the user has just sent.
  Future<void> touchChat({
    required String chatId,
    String? name,
    required String lastMessage,
    bool incrementUnread = true,
    DateTime? updatedAt,
    int? sequenceId,
  }) async {
    final existing = await getChat(chatId);
    final unread = (existing?.unreadCount ?? 0) + (incrementUnread ? 1 : 0);

    await db.into(db.chats).insert(
          ChatsCompanion.insert(
            id: chatId,
            name: Value(name ?? existing?.name ?? ''),
            lastMessage: Value(lastMessage),
            unreadCount: Value(unread),
            updatedAt: Value(updatedAt ?? DateTime.now()),
            lastSequenceId:
                Value(sequenceId ?? existing?.lastSequenceId ?? 0),
          ),
          mode: InsertMode.insertOrReplace,
        );
  }

  /// Marks every message of a chat as read.
  Future<void> markRead(String chatId) async {
    await (db.update(db.chats)..where((c) => c.id.equals(chatId))).write(
      const ChatsCompanion(unreadCount: Value(0)),
    );
  }

  /// Stores the highest synchronised sequence id of a chat.
  Future<void> setLastSequenceId(String chatId, int sequenceId) async {
    final existing = await getChat(chatId);
    if (existing == null) {
      await upsertChat(id: chatId, lastSequenceId: sequenceId);
      return;
    }
    if (sequenceId <= existing.lastSequenceId) return;

    await (db.update(db.chats)..where((c) => c.id.equals(chatId))).write(
      ChatsCompanion(lastSequenceId: Value(sequenceId)),
    );
  }

  /// Removes a chat and all of its messages from the device.
  Future<void> deleteChat(String chatId) async {
    await db.transaction(() async {
      await (db.delete(db.messages)..where((m) => m.chatId.equals(chatId))).go();
      await (db.delete(db.chats)..where((c) => c.id.equals(chatId))).go();
    });
  }
}
