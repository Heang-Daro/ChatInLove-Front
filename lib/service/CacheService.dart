import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../model/Response/ConversationResponse.dart';
import '../model/Response/MessageResponse.dart';
import '../model/emun/MessageType.dart';

/// One cached conversation as shown on the "Storage" screen.
class CachedChatInfo {
  final String conversationId;
  final String name;
  final int messageCount;
  final int mediaCount;
  final int sizeBytes;
  final DateTime? lastActivity;

  const CachedChatInfo({
    required this.conversationId,
    required this.name,
    required this.messageCount,
    required this.mediaCount,
    required this.sizeBytes,
    required this.lastActivity,
  });
}

/// Totals of everything that is stored on disk for one account.
class CacheStats {
  final int cachedChats;
  final int messageCount;
  final int mediaCount;
  final int totalBytes;

  const CacheStats({
    required this.cachedChats,
    required this.messageCount,
    required this.mediaCount,
    required this.totalBytes,
  });

  static const empty = CacheStats(
    cachedChats: 0,
    messageCount: 0,
    mediaCount: 0,
    totalBytes: 0,
  );
}

/// Snapshot of the conversation list stored on disk.
class CachedConversations {
  final DateTime savedAt;
  final List<ConversationResponse> items;

  const CachedConversations({required this.savedAt, required this.items});
}

/// Snapshot of one conversation's messages stored on disk.
class CachedMessages {
  final DateTime savedAt;
  final List<MessageResponse> items;

  const CachedMessages({required this.savedAt, required this.items});
}

/// Local, on-disk cache for chat data (Telegram-style "local database").
///
/// How it works
/// ------------
/// * Every time the app receives data from the server it is written to a JSON
///   file inside `<app documents>/chat_cache/`.
/// * On the next app start (or refresh) the data is read back from disk and
///   shown immediately, so the user never stares at an empty screen while the
///   network request is still running.
/// * Only the difference between the cached snapshot and the server answer is
///   applied (new/changed conversations and new/changed messages), so the UI
///   is not rebuilt for data that did not change.
///
/// Cache layout
/// ------------
/// ```
/// <app documents>/chat_cache/
///   conversations_<userId>.json     -> {"savedAt": "...", "items": [...]}
///   messages_<userId>_<chatId>.json -> {"savedAt": "...", "items": [...]}
/// ```
class CacheService {
  CacheService._();

  static Directory? _dir;
  static bool _initialized = false;

  /// Maximum number of conversations kept in the cache file.
  static const int maxConversations = 200;

  /// Maximum number of messages kept per conversation.
  static const int maxMessagesPerConversation = 300;

  /// Maximum number of conversations whose messages are cached on disk.
  static const int maxMessageFiles = 60;

  /// Cached data older than this is considered expired and dropped.
  static const Duration cacheTtl = Duration(days: 30);

  /// Creates the cache folder. Safe to call several times.
  static Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    if (kIsWeb) return; // no file system on web

    try {
      final docs = await getApplicationDocumentsDirectory();
      final dir = Directory('${docs.path}${Platform.pathSeparator}chat_cache');
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      _dir = dir;
    } catch (e) {
      debugPrint('CacheService: could not create cache dir: $e');
      _dir = null;
    }
  }

  static bool get isSupported => !kIsWeb && _dir != null;

  // ---------------------------------------------------------------------------
  // File helpers
  // ---------------------------------------------------------------------------

  static String _safe(String value) =>
      value.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');

  static File? _conversationsFile(String userId) {
    final dir = _dir;
    if (dir == null) return null;
    return File(
      '${dir.path}${Platform.pathSeparator}conversations_${_safe(userId)}.json',
    );
  }

  static File? _messagesFile(String userId, String conversationId) {
    final dir = _dir;
    if (dir == null) return null;
    return File(
      '${dir.path}${Platform.pathSeparator}messages_'
      '${_safe(userId)}_${_safe(conversationId)}.json',
    );
  }

  /// Writes JSON atomically (temp file + rename) so a crash mid-write can
  /// never leave a half-written cache behind.
  static Future<void> _writeJson(File file, Map<String, dynamic> data) async {
    try {
      final tmp = File('${file.path}.tmp');
      await tmp.writeAsString(json.encode(data), flush: true);
      if (await file.exists()) {
        await file.delete();
      }
      await tmp.rename(file.path);
    } catch (e) {
      debugPrint('CacheService: write failed for ${file.path}: $e');
    }
  }

  static Future<Map<String, dynamic>?> _readJson(File file) async {
    try {
      if (!await file.exists()) return null;
      final raw = await file.readAsString();
      if (raw.trim().isEmpty) return null;
      final decoded = json.decode(raw);
      if (decoded is Map<String, dynamic>) return decoded;
      return null;
    } catch (e) {
      debugPrint('CacheService: read failed for ${file.path}: $e');
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // Conversations
  // ---------------------------------------------------------------------------

  /// Reads the cached conversation list of a user. Returns null when there is
  /// nothing cached yet.
  static Future<CachedConversations?> loadConversations(String userId) async {
    await init();
    final file = _conversationsFile(userId);
    if (file == null) return null;

    final data = await _readJson(file);
    if (data == null) return null;

    try {
      final rawItems = (data['items'] as List?) ?? const [];
      final items = rawItems
          .whereType<Map>()
          .map((e) => ConversationResponse.fromJson(Map<String, dynamic>.from(e)))
          .toList();
      final savedAt = DateTime.tryParse(data['savedAt'] ?? '') ?? DateTime.now();
      return CachedConversations(savedAt: savedAt, items: items);
    } catch (e) {
      debugPrint('CacheService: bad conversation cache: $e');
      return null;
    }
  }

  /// Stores the conversation list of a user on disk.
  static Future<void> saveConversations(
    String userId,
    List<ConversationResponse> items,
  ) async {
    await init();
    final file = _conversationsFile(userId);
    if (file == null) return;

    final trimmed = items.length > maxConversations
        ? items.sublist(0, maxConversations)
        : items;

    await _writeJson(file, {
      'savedAt': DateTime.now().toIso8601String(),
      'items': trimmed.map((e) => e.toJson()).toList(),
    });
  }

  // ---------------------------------------------------------------------------
  // Messages
  // ---------------------------------------------------------------------------

  /// Reads the cached messages of one conversation.
  static Future<CachedMessages?> loadMessages(
    String userId,
    String conversationId,
  ) async {
    await init();
    final file = _messagesFile(userId, conversationId);
    if (file == null) return null;

    final data = await _readJson(file);
    if (data == null) return null;

    try {
      final rawItems = (data['items'] as List?) ?? const [];
      final items = rawItems
          .whereType<Map>()
          .map((e) => MessageResponse.fromJson(Map<String, dynamic>.from(e)))
          .toList();
      final savedAt = DateTime.tryParse(data['savedAt'] ?? '') ?? DateTime.now();
      return CachedMessages(savedAt: savedAt, items: items);
    } catch (e) {
      debugPrint('CacheService: bad message cache: $e');
      return null;
    }
  }

  /// Stores the messages of one conversation on disk.
  static Future<void> saveMessages(
    String userId,
    String conversationId,
    List<MessageResponse> items,
  ) async {
    await init();
    final file = _messagesFile(userId, conversationId);
    if (file == null) return;

    final trimmed = items.length > maxMessagesPerConversation
        ? items.sublist(0, maxMessagesPerConversation)
        : items;

    await _writeJson(file, {
      'savedAt': DateTime.now().toIso8601String(),
      'conversationId': conversationId,
      'userId': userId,
      'items': trimmed.map((e) => e.toJson()).toList(),
    });

    await _pruneMessageFiles(keepConversationId: conversationId);
  }

  /// Keeps the number of message files bounded: the oldest files are deleted
  /// once more than [maxMessageFiles] conversations are cached.
  static Future<void> _pruneMessageFiles({String? keepConversationId}) async {
    final dir = _dir;
    if (dir == null) return;

    try {
      final files = await dir
          .list()
          .where((e) => e is File && e.path.contains('messages_'))
          .cast<File>()
          .toList();

      if (files.length <= maxMessageFiles) return;

      final withTime = <MapEntry<File, DateTime>>[];
      for (final f in files) {
        final stat = await f.stat();
        withTime.add(MapEntry(f, stat.modified));
      }
      withTime.sort((a, b) => a.value.compareTo(b.value));

      var toDelete = withTime.length - maxMessageFiles;
      for (final entry in withTime) {
        if (toDelete <= 0) break;
        final name = entry.key.path.split(Platform.pathSeparator).last;
        if (keepConversationId != null &&
            name.endsWith('_${_safe(keepConversationId)}.json')) {
          continue; // never delete the file we just wrote
        }
        try {
          await entry.key.delete();
        } catch (_) {}
        toDelete--;
      }
    } catch (e) {
      debugPrint('CacheService: prune failed: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // Inspection (used by the "Storage" screen)
  // ---------------------------------------------------------------------------

  /// True when a message holds a file (image, video, voice note, document).
  static bool isMediaMessage(MessageResponse message) {
    switch (message.type) {
      case MessageType.IMAGE:
      case MessageType.VIDEO:
      case MessageType.VOICE:
      case MessageType.FILE:
        return message.content.trim().isNotEmpty;
      case MessageType.TEXT:
      case MessageType.SYSTEM:
      case MessageType.CALL:
        return false;
    }
  }

  /// Every message file that belongs to a user, with its parsed content.
  static Future<List<_CachedMessageFile>> _readUserMessageFiles(
    String userId,
  ) async {
    await init();
    final dir = _dir;
    if (dir == null) return [];

    final files = <_CachedMessageFile>[];
    try {
      await for (final entity in dir.list()) {
        if (entity is! File) continue;
        final fileName = entity.path.split(Platform.pathSeparator).last;
        if (!fileName.startsWith('messages_') || !fileName.endsWith('.json')) {
          continue;
        }

        final data = await _readJson(entity);
        if (data == null) continue;

        final rawItems = (data['items'] as List?) ?? const [];
        final messages = rawItems
            .whereType<Map>()
            .map((e) => MessageResponse.fromJson(Map<String, dynamic>.from(e)))
            .toList();

        int size = 0;
        try {
          size = await entity.length();
        } catch (_) {}

        files.add(_CachedMessageFile(
          file: entity,
          conversationId:
              (data['conversationId'] as String?) ?? _conversationIdFromName(fileName),
          savedAt: DateTime.tryParse(data['savedAt'] ?? '') ?? DateTime.now(),
          sizeBytes: size,
          messages: messages,
        ));
      }
    } catch (e) {
      debugPrint('CacheService: could not list cache files: $e');
    }
    return files;
  }

  /// Fallback for files written before the conversation id was stored inside
  /// the file: `messages_<user>_<conversationId>.json`.
  static String _conversationIdFromName(String fileName) {
    final withoutExtension = fileName.substring(0, fileName.length - 5);
    final parts = withoutExtension.split('_');
    if (parts.length <= 2) return withoutExtension;
    return parts.sublist(2).join('_');
  }

  /// Lists every conversation that currently has cached messages.
  static Future<List<CachedChatInfo>> listCachedChats(String userId) async {
    final files = await _readUserMessageFiles(userId);
    final conversations = await loadConversations(userId);

    final names = <String, String>{};
    for (final c in conversations?.items ?? const <ConversationResponse>[]) {
      names[c.id] = c.name?.trim().isNotEmpty == true ? c.name! : 'Chat';
    }

    final result = <CachedChatInfo>[];
    for (final file in files) {
      final media =
          file.messages.where((m) => isMediaMessage(m)).length;
      DateTime? lastActivity;
      for (final m in file.messages) {
        final t = m.createdAt;
        if (t == null) continue;
        if (lastActivity == null || t.isAfter(lastActivity)) lastActivity = t;
      }
      result.add(CachedChatInfo(
        conversationId: file.conversationId,
        name: names[file.conversationId] ?? 'Chat',
        messageCount: file.messages.length,
        mediaCount: media,
        sizeBytes: file.sizeBytes,
        lastActivity: lastActivity ?? file.savedAt,
      ));
    }

    result.sort((a, b) =>
        (b.lastActivity ?? DateTime(0)).compareTo(a.lastActivity ?? DateTime(0)));
    return result;
  }

  /// Totals of the cache of one account.
  static Future<CacheStats> getStats(String userId) async {
    final files = await _readUserMessageFiles(userId);

    var messages = 0;
    var media = 0;
    var bytes = 0;

    for (final file in files) {
      messages += file.messages.length;
      media += file.messages.where((m) => isMediaMessage(m)).length;
      bytes += file.sizeBytes;
    }

    final conversations = await loadConversations(userId);
    if (conversations != null) {
      final convFile = _conversationsFile(userId);
      if (convFile != null) {
        try {
          if (await convFile.exists()) bytes += await convFile.length();
        } catch (_) {}
      }
    }

    return CacheStats(
      cachedChats: files.length,
      messageCount: messages,
      mediaCount: media,
      totalBytes: bytes,
    );
  }

  /// All cached media (image / video / voice / file) of one conversation.
  static Future<List<MessageResponse>> cachedMediaOfConversation(
    String userId,
    String conversationId,
  ) async {
    final cached = await loadMessages(userId, conversationId);
    if (cached == null) return const [];
    return cached.items.where(isMediaMessage).toList();
  }

  // ---------------------------------------------------------------------------
  // Targeted clearing
  // ---------------------------------------------------------------------------

  /// Removes the cached messages of a single conversation.
  static Future<void> clearConversationCache(
    String userId,
    String conversationId,
  ) async {
    await init();
    final file = _messagesFile(userId, conversationId);
    if (file == null) return;
    try {
      if (await file.exists()) await file.delete();
    } catch (e) {
      debugPrint('CacheService: could not clear conversation cache: $e');
    }
  }

  /// Removes every cached photo / video / voice note / document but keeps the
  /// text messages. Returns the number of removed media messages.
  static Future<int> clearCachedMedia(String userId) async {
    final files = await _readUserMessageFiles(userId);
    var removed = 0;

    for (final file in files) {
      final kept = file.messages.where((m) => !isMediaMessage(m)).toList();
      final count = file.messages.length - kept.length;
      if (count == 0) continue;

      removed += count;
      await _writeJson(file.file, {
        'savedAt': DateTime.now().toIso8601String(),
        'conversationId': file.conversationId,
        'userId': userId,
        'items': kept.map((e) => e.toJson()).toList(),
      });
    }
    return removed;
  }

  // ---------------------------------------------------------------------------
  // Maintenance
  // ---------------------------------------------------------------------------

  /// Removes every cached file of a user (called on logout).
  static Future<void> clearUser(String userId) async {
    await init();
    final dir = _dir;
    if (dir == null) return;

    try {
      await for (final entity in dir.list()) {
        if (entity is! File) continue;
        final name = entity.path.split(Platform.pathSeparator).last;
        if (name.contains(_safe(userId))) {
          try {
            await entity.delete();
          } catch (_) {}
        }
      }
    } catch (e) {
      debugPrint('CacheService: clearUser failed: $e');
    }
  }

  /// Removes the whole cache folder (used by "clear cache" in settings).
  static Future<void> clearAll() async {
    await init();
    final dir = _dir;
    if (dir == null) return;
    try {
      await dir.delete(recursive: true);
    } catch (_) {}
    _dir = null;
    _initialized = false;
  }
}

/// Internal helper: one cached message file on disk.
class _CachedMessageFile {
  final File file;
  final String conversationId;
  final DateTime savedAt;
  final int sizeBytes;
  final List<MessageResponse> messages;

  const _CachedMessageFile({
    required this.file,
    required this.conversationId,
    required this.savedAt,
    required this.sizeBytes,
    required this.messages,
  });
}
