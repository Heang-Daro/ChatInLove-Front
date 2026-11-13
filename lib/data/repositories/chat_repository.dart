import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

import '../../api/api.dart';
import '../../model/Response/MessageResponse.dart';
import '../../model/emun/MessageType.dart';
import '../../provider/AuthProvider.dart';
import '../../service/StompService.dart';
import '../database/app_database.dart';
import '../database/chat_dao.dart';
import '../database/message_dao.dart';

/// Offline-first chat repository.
///
/// The database is the single source of truth for the UI:
///
/// 1. [sendMessage] writes the message to SQLite **first** (`pending`) and
///    returns immediately – the bubble is on screen without any network round
///    trip.
/// 2. The message is sent to the backend. On success the row is reconciled
///    ([MessageDao.confirmMessageSent]), on failure it is marked `failed` and
///    can be retried with [retryFailedMessage].
/// 3. Incoming messages (REST delta sync and STOMP frames) are written with
///    [MessageDao.upsertIncomingBatch], which resolves duplicates by
///    `serverId` / `localId`.
class ChatRepository {
  ChatRepository({
    required this.db,
    required this.auth,
    String? baseUrl,
    Uuid? uuidGenerator,
  })  : baseUrl = baseUrl ?? REST_URL,
        _uuid = uuidGenerator ?? const Uuid();

  final AppDatabase db;
  final AuthProvider auth;
  final String baseUrl;
  final Uuid _uuid;

  static const Duration _timeout = Duration(seconds: 15);

  MessageDao get _messages => MessageDao(db);
  ChatDao get _chats => ChatDao(db);

  // ---------------------------------------------------------------------------
  // Streams (the UI only ever reads from here)
  // ---------------------------------------------------------------------------

  /// Newest messages of a chat. Emits again on every local change.
  Stream<List<Message>> watchMessages(String chatId, {int limit = 50}) {
    return _messages.watchMessages(chatId, limit: limit);
  }

  /// All chats that are stored on the device.
  Stream<List<Chat>> watchChats() => _chats.watchChats();

  /// A single chat.
  Stream<Chat?> watchChat(String chatId) => _chats.watchChat(chatId);

  // ---------------------------------------------------------------------------
  // Optimistic send
  // ---------------------------------------------------------------------------

  /// Sends a message optimistically.
  ///
  /// Returns the client side uuid of the new message. The message is visible
  /// in the UI immediately, even when the device is offline.
  Future<String> sendMessage({
    required String chatId,
    required String content,
    MessageType type = MessageType.TEXT,
    String? mediaLocalPath,
    String? mediaUrl,
  }) async {
    final localId = _uuid.v4();
    final senderId = auth.currentUserId ?? 'unknown';
    final now = DateTime.now();

    // 1. Local write -> the stream of the chat emits the new bubble.
    await _messages.insertOptimisticMessage(
      MessagesCompanion.insert(
        localId: localId,
        serverId: const Value(null),
        chatId: chatId,
        senderId: senderId,
        content: content,
        mediaLocalPath: Value(mediaLocalPath),
        mediaUrl: Value(mediaUrl),
        timestamp: now,
        status: DeliveryStatus.pending,
        messageType: type,
      ),
    );

    await _chats.touchChat(
      chatId: chatId,
      lastMessage: content,
      incrementUnread: false,
      updatedAt: now,
    );

    // 2. Network dispatch (does not block the UI).
    unawaited(_dispatch(
      localId: localId,
      chatId: chatId,
      content: content,
      type: type,
    ));

    return localId;
  }

  /// Sends a message that failed earlier.
  Future<void> retryFailedMessage(String localId) async {
    final message = await _messages.getByLocalId(localId);
    if (message == null) return;

    await _messages.setStatus(localId, DeliveryStatus.pending);

    await _dispatch(
      localId: localId,
      chatId: message.chatId,
      content: message.content,
      type: message.messageType,
    );
  }

  /// Sends the message to the backend and reconciles the local row.
  Future<void> _dispatch({
    required String localId,
    required String chatId,
    required String content,
    required MessageType type,
  }) async {
    try {
      final response = await auth.authorizedRequest((token) async {
        return await http.post(
          Uri.parse('$baseUrl/api/conversations/$chatId/messages'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
          body: json.encode({
            'content': content,
            'messageType': type.name,
          }),
        );
      }).timeout(_timeout);

      if (response.statusCode == 200 || response.statusCode == 201) {
        final body = json.decode(response.body);
        if (body is Map<String, dynamic>) {
          final serverId = body['id'] as String? ?? '';
          final serverTimestamp =
              DateTime.tryParse(body['createdAt'] ?? '') ?? DateTime.now();

          if (serverId.isNotEmpty) {
            await _messages.confirmMessageSent(
              localId,
              serverId,
              serverTimestamp,
            );
          } else {
            await _messages.setStatus(localId, DeliveryStatus.sent);
          }
        } else {
          await _messages.setStatus(localId, DeliveryStatus.sent);
        }
      } else {
        await _messages.markFailed(localId);
      }
    } on TimeoutException {
      await _messages.markFailed(localId);
    } catch (e) {
      debugPrint('ChatRepository: send failed: $e');
      await _messages.markFailed(localId);
    }
  }

  // ---------------------------------------------------------------------------
  // Incoming data
  // ---------------------------------------------------------------------------

  /// Listens to the STOMP connection and writes every incoming message into
  /// the database.
  void startListening() {
    _stomp.addIncomingMessageListener(_onIncomingMessage);
  }

  /// Stops listening to the STOMP connection.
  void stopListening() {
    _stomp.removeIncomingMessageListener(_onIncomingMessage);
  }

  final StompService _stomp = StompService();

  void _onIncomingMessage(MessageResponse message) {
    unawaited(handleIncomingMessage(message));
  }

  /// Writes one incoming message into the database and updates its chat.
  Future<void> handleIncomingMessage(MessageResponse message) async {
    final companion = _companionFromServer(message);
    await _messages.upsertIncomingBatch([companion]);

    final chat = await _chats.getChat(message.conversationId);
    await _chats.touchChat(
      chatId: message.conversationId,
      name: chat?.name,
      lastMessage: message.previewText,
      incrementUnread: true,
      updatedAt: message.createdAt ?? DateTime.now(),
    );
  }

  /// Fetches everything that was missed while the device was offline.
  ///
  /// [lastSequenceId] is the highest sequence id the device already knows.
  /// When [chatId] is null every cached chat is synchronised, otherwise only
  /// that one. Returns the number of messages that were received.
  Future<int> syncMissedMessages(int lastSequenceId, {String? chatId}) async {
    final chatIds =
        chatId != null ? <String>[chatId] : await _chats.allChatIds();

    var synced = 0;

    for (final id in chatIds) {
      final from = chatId != null ? lastSequenceId : await _chats.lastSequenceId(id);

      try {
        final response = await auth.authorizedRequest((token) async {
          return await http.get(
            Uri.parse('$baseUrl/api/conversations/$id/messages').replace(
              queryParameters: {
                'after': '$from',
                'size': '200',
              },
            ),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
          );
        }).timeout(_timeout);

        if (response.statusCode != 200) continue;

        final decoded = json.decode(response.body);
        final List<dynamic> content;
        if (decoded is Map<String, dynamic>) {
          content = (decoded['content'] as List?) ?? const [];
        } else if (decoded is List) {
          content = decoded;
        } else {
          content = const [];
        }

        final batch = <MessagesCompanion>[];
        var maxSequence = from;

        for (final raw in content) {
          if (raw is! Map) continue;
          final map = Map<String, dynamic>.from(raw);
          final sequence = map['sequenceId'];
          if (sequence is int && sequence > maxSequence) maxSequence = sequence;
          batch.add(_companionFromServerMap(map));
        }

        if (batch.isNotEmpty) {
          await _messages.upsertIncomingBatch(batch);
          synced += batch.length;
        }
        await _chats.setLastSequenceId(id, maxSequence);
      } on TimeoutException {
        // Keep the local state, the next reconnect tries again.
      } catch (e) {
        debugPrint('ChatRepository: sync failed for $id: $e');
      }
    }

    return synced;
  }

  /// Downloads the conversation list from the backend into the database, so the
  /// chat list is available offline as well.
  Future<int> refreshChatList() async {
    try {
      final response = await auth.authorizedRequest((token) async {
        return await http.get(
          Uri.parse('$baseUrl/api/conversations').replace(
            queryParameters: {'page': '0', 'size': '100'},
          ),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
        );
      }).timeout(_timeout);

      if (response.statusCode != 200) return 0;

      final decoded = json.decode(response.body);
      final List<dynamic> content;
      if (decoded is Map<String, dynamic>) {
        content = (decoded['content'] as List?) ?? const [];
      } else if (decoded is List) {
        content = decoded;
      } else {
        content = const [];
      }

      var count = 0;
      for (final raw in content) {
        if (raw is! Map) continue;
        final map = Map<String, dynamic>.from(raw);
        final id = map['id'] as String?;
        if (id == null || id.isEmpty) continue;

        final name = map['name'] as String?;
        final lastMessage = map['lastMessage'];
        final preview = lastMessage is Map
            ? (lastMessage['content'] as String? ?? '')
            : null;
        final updatedAt = DateTime.tryParse(map['lastMessageAt'] ?? '') ??
            DateTime.tryParse(map['createdAt'] ?? '') ??
            DateTime.now();

        await _chats.upsertChat(
          id: id,
          name: name,
          lastMessage: preview,
          updatedAt: updatedAt,
        );
        count++;
      }
      return count;
    } catch (e) {
      debugPrint('ChatRepository: could not refresh chat list: $e');
      return 0;
    }
  }

  // ---------------------------------------------------------------------------
  // Conversion helpers
  // ---------------------------------------------------------------------------

  MessagesCompanion _companionFromServer(MessageResponse message) {
    return _companionFromServerMap({
      'id': message.id,
      'conversationId': message.conversationId,
      'senderId': message.senderId,
      'senderUsername': message.senderUsername,
      'content': message.content,
      'type': message.type.name,
      'createdAt': message.createdAt?.toIso8601String(),
      'isRead': message.isRead,
    });
  }

  MessagesCompanion _companionFromServerMap(Map<String, dynamic> map) {
    final typeName = (map['type'] as String? ?? 'TEXT').toUpperCase();
    final type = MessageType.values.firstWhere(
      (e) => e.name.toUpperCase() == typeName,
      orElse: () => MessageType.TEXT,
    );

    final content = map['content'] as String? ?? '';
    final isMedia = type != MessageType.TEXT && type != MessageType.SYSTEM;

    return MessagesCompanion.insert(
      localId: _uuid.v4(),
      serverId: Value(map['id'] as String?),
      chatId: map['conversationId'] as String? ?? '',
      senderId: map['senderId'] as String? ?? '',
      content: content,
      mediaLocalPath: const Value(null),
      mediaUrl:
          Value(isMedia && content.isNotEmpty ? resolveFileUrl(content) : null),
      timestamp: DateTime.tryParse(map['createdAt'] ?? '') ?? DateTime.now(),
      status: DeliveryStatus.delivered,
      messageType: type,
      sequenceId: Value(map['sequenceId'] as int?),
    );
  }

  /// Marks a chat as read (resets the unread counter).
  Future<void> markChatRead(String chatId) => _chats.markRead(chatId);

  /// Removes everything of this account from the device.
  Future<void> clearLocalData() async {
    await db.transaction(() async {
      await db.delete(db.messages).go();
      await db.delete(db.chats).go();
    });
  }
}
