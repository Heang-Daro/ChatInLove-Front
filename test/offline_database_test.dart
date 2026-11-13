// `isNull` / `isNotNull` exist in drift and in the matcher package.
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_in_chat/data/database/app_database.dart';
import 'package:love_in_chat/data/database/chat_dao.dart';
import 'package:love_in_chat/data/database/message_dao.dart';
import 'package:love_in_chat/model/emun/MessageType.dart';

/// Tests of the offline-first data layer.
///
/// They run against an in-memory SQLite database, so no device is needed:
/// `flutter test`
void main() {
  late AppDatabase db;
  late MessageDao messages;
  late ChatDao chats;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    messages = MessageDao(db);
    chats = ChatDao(db);
  });

  tearDown(() async {
    await db.close();
  });

  MessagesCompanion serverMessage({
    required String serverId,
    required String chatId,
    required String senderId,
    String content = 'hello',
    DateTime? timestamp,
  }) {
    return MessagesCompanion.insert(
      localId: 'local-$serverId',
      serverId: Value(serverId),
      chatId: chatId,
      senderId: senderId,
      content: content,
      timestamp: timestamp ?? DateTime(2024, 1, 1),
      status: DeliveryStatus.delivered,
      messageType: MessageType.TEXT,
    );
  }

  group('watchMessages', () {
    test('emits the newest message first', () async {
      await messages.insertOptimisticMessage(
        MessagesCompanion.insert(
          localId: 'a',
          chatId: 'c1',
          senderId: 'me',
          content: 'older',
          timestamp: DateTime(2024, 1, 1),
          status: DeliveryStatus.pending,
          messageType: MessageType.TEXT,
        ),
      );
      await messages.insertOptimisticMessage(
        MessagesCompanion.insert(
          localId: 'b',
          chatId: 'c1',
          senderId: 'me',
          content: 'newer',
          timestamp: DateTime(2024, 1, 2),
          status: DeliveryStatus.pending,
          messageType: MessageType.TEXT,
        ),
      );

      final rows = await messages.watchMessages('c1').first;
      expect(rows.map((m) => m.content).toList(), ['newer', 'older']);
    });

    test('only returns the messages of the requested chat', () async {
      await messages.insertOptimisticMessage(
        MessagesCompanion.insert(
          localId: 'a',
          chatId: 'c1',
          senderId: 'me',
          content: 'in c1',
          timestamp: DateTime(2024, 1, 1),
          status: DeliveryStatus.pending,
          messageType: MessageType.TEXT,
        ),
      );
      await messages.insertOptimisticMessage(
        MessagesCompanion.insert(
          localId: 'b',
          chatId: 'c2',
          senderId: 'me',
          content: 'in c2',
          timestamp: DateTime(2024, 1, 1),
          status: DeliveryStatus.pending,
          messageType: MessageType.TEXT,
        ),
      );

      final rows = await messages.watchMessages('c1').first;
      expect(rows.length, 1);
      expect(rows.first.content, 'in c1');
    });
  });

  group('optimistic send', () {
    test('the message is visible before the server answers', () async {
      await messages.insertOptimisticMessage(
        MessagesCompanion.insert(
          localId: 'local-1',
          chatId: 'c1',
          senderId: 'me',
          content: 'sending...',
          timestamp: DateTime.now(),
          status: DeliveryStatus.pending,
          messageType: MessageType.TEXT,
        ),
      );

      final row = await messages.getByLocalId('local-1');
      expect(row, isNotNull);
      expect(row!.status, DeliveryStatus.pending);
      expect(row.serverId, isNull);
    });

    test('confirmMessageSent stores the server id and the timestamp',
        () async {
      await messages.insertOptimisticMessage(
        MessagesCompanion.insert(
          localId: 'local-1',
          chatId: 'c1',
          senderId: 'me',
          content: 'sending...',
          timestamp: DateTime(2024, 1, 1),
          status: DeliveryStatus.pending,
          messageType: MessageType.TEXT,
        ),
      );

      final serverTime = DateTime(2024, 1, 2, 10, 30);
      await messages.confirmMessageSent('local-1', 'server-1', serverTime);

      final row = await messages.getByLocalId('local-1');
      expect(row!.serverId, 'server-1');
      expect(row.status, DeliveryStatus.sent);
      expect(row.timestamp, serverTime);
    });

    test('a failed message can be retried', () async {
      await messages.insertOptimisticMessage(
        MessagesCompanion.insert(
          localId: 'local-1',
          chatId: 'c1',
          senderId: 'me',
          content: 'sending...',
          timestamp: DateTime(2024, 1, 1),
          status: DeliveryStatus.pending,
          messageType: MessageType.TEXT,
        ),
      );

      await messages.markFailed('local-1');
      expect((await messages.getByLocalId('local-1'))!.status,
          DeliveryStatus.failed);

      await messages.setStatus('local-1', DeliveryStatus.pending);
      expect((await messages.getByLocalId('local-1'))!.status,
          DeliveryStatus.pending);
    });
  });

  group('upsertIncomingBatch', () {
    test('does not create duplicates for the same server id', () async {
      await messages.upsertIncomingBatch([
        serverMessage(serverId: 's1', chatId: 'c1', senderId: 'other'),
      ]);
      await messages.upsertIncomingBatch([
        serverMessage(serverId: 's1', chatId: 'c1', senderId: 'other'),
      ]);

      final rows = await messages.watchMessages('c1').first;
      expect(rows.length, 1);
    });

    test('updates an existing message instead of inserting it twice',
        () async {
      await messages.upsertIncomingBatch([
        serverMessage(serverId: 's1', chatId: 'c1', senderId: 'other'),
      ]);
      await messages.upsertIncomingBatch([
        serverMessage(
          serverId: 's1',
          chatId: 'c1',
          senderId: 'other',
          content: 'edited',
        ),
      ]);

      final rows = await messages.watchMessages('c1').first;
      expect(rows.length, 1);
      expect(rows.first.content, 'edited');
    });

    test('reconciles our own pending message with the server echo', () async {
      await messages.insertOptimisticMessage(
        MessagesCompanion.insert(
          localId: 'local-1',
          chatId: 'c1',
          senderId: 'me',
          content: 'hello',
          timestamp: DateTime(2024, 1, 1),
          status: DeliveryStatus.pending,
          messageType: MessageType.TEXT,
        ),
      );

      await messages.upsertIncomingBatch([
        serverMessage(serverId: 's1', chatId: 'c1', senderId: 'me'),
      ]);

      final rows = await messages.watchMessages('c1').first;
      expect(rows.length, 1, reason: 'the echo must not duplicate the bubble');
      expect(rows.first.localId, 'local-1');
      expect(rows.first.serverId, 's1');
      expect(rows.first.status, DeliveryStatus.sent,
          reason: 'the server echo confirms our own pending message');
    });
  });

  group('chats', () {
    test('the unread counter is increased for incoming messages', () async {
      await chats.touchChat(
        chatId: 'c1',
        name: 'Anna',
        lastMessage: 'hi',
      );
      await chats.touchChat(
        chatId: 'c1',
        lastMessage: 'how are you?',
      );

      final chat = await chats.getChat('c1');
      expect(chat!.unreadCount, 2);
      expect(chat.name, 'Anna');
      expect(chat.lastMessage, 'how are you?');
    });

    test('markRead resets the unread counter', () async {
      await chats.touchChat(chatId: 'c1', lastMessage: 'hi');
      await chats.markRead('c1');
      expect((await chats.getChat('c1'))!.unreadCount, 0);
    });

    test('the last sequence id only moves forward', () async {
      await chats.upsertChat(id: 'c1', lastSequenceId: 10);
      await chats.setLastSequenceId('c1', 5);
      expect(await chats.lastSequenceId('c1'), 10);

      await chats.setLastSequenceId('c1', 42);
      expect(await chats.lastSequenceId('c1'), 42);
    });
  });
}
