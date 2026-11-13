import 'package:drift/drift.dart';

import 'app_database.dart';

/// All database operations for the [Messages] table.
///
/// Every write goes through this class so the conflict rules live in exactly
/// one place:
///
/// * a row is identified by its **localId** (uuid v4, generated on the
///   device),
/// * a row that was already synchronised is additionally identified by its
///   **serverId**,
/// * incoming batches are matched against `serverId` first, then `localId`
///   and finally against a pending row of the same author with the same
///   content (the echo of a message we sent ourselves).
class MessageDao {
  MessageDao(this.db);

  final AppDatabase db;

  // ---------------------------------------------------------------------------
  // Streams
  // ---------------------------------------------------------------------------

  /// Watches the newest messages of a chat.
  ///
  /// The stream re-emits whenever the table changes, which means the UI is
  /// updated by the database and not by the network layer.
  Stream<List<Message>> watchMessages(String chatId, {int limit = 50}) {
    final query = db.select(db.messages)
      ..where((m) => m.chatId.equals(chatId))
      ..orderBy([
        (m) => OrderingTerm.desc(m.timestamp),
        (m) => OrderingTerm.desc(m.localId),
      ])
      ..limit(limit);

    return query.watch();
  }

  /// Watches the messages of a chat that still have to be sent.
  Stream<List<Message>> watchPendingMessages(String chatId) {
    final query = db.select(db.messages)
      ..where((m) =>
          m.chatId.equals(chatId) &
          m.status.equals(DeliveryStatus.pending.name))
      ..orderBy([(m) => OrderingTerm.asc(m.timestamp)]);

    return query.watch();
  }

  // ---------------------------------------------------------------------------
  // Optimistic writes
  // ---------------------------------------------------------------------------

  /// Inserts a message that was written on the device *before* it was sent to
  /// the server. The row is visible in the UI immediately.
  Future<void> insertOptimisticMessage(MessagesCompanion msg) async {
    await db.into(db.messages).insert(msg, mode: InsertMode.insertOrIgnore);
  }

  /// Reconciles a pending message with the answer of the server: the server
  /// id is stored and the status becomes [DeliveryStatus.sent].
  Future<void> confirmMessageSent(
    String localId,
    String serverId,
    DateTime serverTimestamp,
  ) async {
    await (db.update(db.messages)..where((m) => m.localId.equals(localId))).write(
      MessagesCompanion(
        serverId: Value(serverId),
        status: const Value(DeliveryStatus.sent),
        timestamp: Value(serverTimestamp),
      ),
    );
  }

  /// Marks a message as failed so the user can retry it.
  Future<void> markFailed(String localId) async {
    await (db.update(db.messages)..where((m) => m.localId.equals(localId))).write(
      const MessagesCompanion(status: Value(DeliveryStatus.failed)),
    );
  }

  /// Changes the delivery status of a message (used by the read receipts).
  Future<void> setStatus(String localId, DeliveryStatus status) async {
    await (db.update(db.messages)..where((m) => m.localId.equals(localId))).write(
      MessagesCompanion(status: Value(status)),
    );
  }

  // ---------------------------------------------------------------------------
  // Incoming data (REST delta sync + STOMP frames)
  // ---------------------------------------------------------------------------

  /// Upserts a batch of messages that came from the server.
  ///
  /// Duplicates are impossible: a message is matched by `serverId`, then by
  /// `localId`, then against a still pending message of the same author with
  /// the same content (our own message echoed back by the server).
  Future<void> upsertIncomingBatch(List<MessagesCompanion> messages) async {
    if (messages.isEmpty) return;

    await db.transaction(() async {
      for (final msg in messages) {
        final serverId = msg.serverId.value;
        final localId = msg.localId.value;
        if (localId.isEmpty) continue;

        final senderId = msg.senderId.value;
        final content = msg.content.value;

        Message? existing;

        // 1. Already known by its server id?
        if (serverId != null && serverId.isNotEmpty) {
          existing = await (db.select(db.messages)
                ..where((m) => m.serverId.equals(serverId))
                ..limit(1))
              .getSingleOrNull();
        }

        // 2. Already known by its local id?
        existing ??= await (db.select(db.messages)
              ..where((m) => m.localId.equals(localId))
              ..limit(1))
            .getSingleOrNull();

        // 3. Is it the echo of a message we sent ourselves?
        if (existing == null && senderId.isNotEmpty && content.isNotEmpty) {
          existing = await (db.select(db.messages)
                ..where((m) =>
                    m.chatId.equals(msg.chatId.value) &
                    m.senderId.equals(senderId) &
                    m.content.equals(content) &
                    m.status.equals(DeliveryStatus.pending.name))
                ..limit(1))
            .getSingleOrNull();
        }

        if (existing != null) {
          final match = existing;

          // The status of the existing row is kept. The only exception is
          // our own message that was still pending: the server echoed it, so
          // it is confirmed now.
          final status = (match.senderId == senderId &&
                  match.status == DeliveryStatus.pending)
              ? const Value(DeliveryStatus.sent)
              : Value(match.status);

          // Update in place.
          await (db.update(db.messages)
                ..where((m) => m.localId.equals(match.localId)))
              .write(
            MessagesCompanion(
              serverId: msg.serverId,
              content: Value(content),
              mediaLocalPath: msg.mediaLocalPath,
              mediaUrl: msg.mediaUrl,
              timestamp: msg.timestamp,
              messageType: msg.messageType,
              sequenceId: msg.sequenceId,
              status: status,
            ),
          );
        } else {
          // Brand new message.
          await db.into(db.messages).insert(
                msg.copyWith(
                  localId: Value(localId),
                  status: msg.status.present
                      ? msg.status
                      : const Value(DeliveryStatus.delivered),
                ),
                mode: InsertMode.insertOrIgnore,
              );
        }
      }
    });
  }

  // ---------------------------------------------------------------------------
  // Single row helpers
  // ---------------------------------------------------------------------------

  Future<Message?> getByLocalId(String localId) {
    return (db.select(db.messages)..where((m) => m.localId.equals(localId)))
        .getSingleOrNull();
  }

  Future<Message?> getByServerId(String serverId) {
    return (db.select(db.messages)..where((m) => m.serverId.equals(serverId)))
        .getSingleOrNull();
  }

  /// Number of messages of a chat that still have to be sent.
  Future<int> countPending(String chatId) async {
    final count = db.messages.localId.count();
    final query = db.selectOnly(db.messages)
      ..addColumns([count])
      ..where(db.messages.chatId.equals(chatId) &
          db.messages.status.equals(DeliveryStatus.pending.name));
    final row = await query.getSingle();
    return row.read(count) ?? 0;
  }

  Future<void> deleteByLocalId(String localId) async {
    await (db.delete(db.messages)..where((m) => m.localId.equals(localId))).go();
  }
}
