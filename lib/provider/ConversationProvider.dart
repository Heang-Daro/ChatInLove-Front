import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:love_in_chat/model/Response/ConversationResponse.dart';
import 'package:love_in_chat/model/Response/MessageResponse.dart';
import 'package:love_in_chat/model/emun/ConversationStatus.dart';
import 'package:love_in_chat/model/emun/MessageType.dart';

import '../api/api.dart';
import '../model/Response/ChatEventType.dart';
import '../model/Response/UserResponse.dart';
import '../service/CacheService.dart';
import '../service/StompService.dart';
import 'AuthProvider.dart';

class ConversationProvider extends ChangeNotifier {
  final String baseUrl = "${REST_URL}/api/conversations";
  final StompService _stompService = StompService();

  static const Duration _timeout = Duration(seconds: 15);
  static const int _conversationPageSize = 20;
  static const int _messagePageSize = 50;

  /// When the backend supports a `since=<iso timestamp>` parameter, set this
  /// to true: the server then only returns what changed after the cached
  /// snapshot was written. Until then the client-side diff does the same job.
  static const bool _sendSinceParam = false;

  // ---- Conversations state ----
  List<ConversationResponse> _conversations = [];
  List<ConversationResponse> _pendingRequests = [];
  bool _isLoading = false;
  bool _isLoadingMoreConversations = false;
  bool _isFetchingConversations = false;
  bool _hasMoreConversations = true;
  int _conversationPage = 0;

  // ---- Messages state (newest first) ----
  List<MessageResponse> _currentMessages = [];
  bool _isLoadingMessages = false;
  bool _isLoadingMoreMessages = false;
  bool _hasMoreMessages = true;
  int _messagePage = 0;
  String? _activeConversationId; // guards against stale responses
  String? _lastMarkedReadId;

  // ---- Typing state ----
  String? _activeTypingUser;
  Timer? _typingTimer;
  String? get activeTypingUser => _activeTypingUser;

  // ---- User Search state ----
  List<UserResponse> _searchResults = [];
  bool _isSearching = false;
  int _searchSeq = 0; // guards against out-of-order search responses

  String? _errorMessage;

  // ---- Local cache state ----
  // True while the visible data comes from the on-disk cache (offline first).
  bool _showingCachedData = false;
  // Last time the app successfully talked to the server.
  DateTime? _lastServerSyncAt;
  // Debounced writers so bursts of updates do not hammer the disk.
  Timer? _conversationCacheTimer;
  Timer? _messageCacheTimer;

  List<ConversationResponse> get conversations => _conversations;
  List<ConversationResponse> get incomingRequests => _pendingRequests;
  List<MessageResponse> get currentMessages => _currentMessages;
  bool get isLoading => _isLoading;
  bool get isLoadingMoreConversations => _isLoadingMoreConversations;
  bool get hasMoreConversations => _hasMoreConversations;
  bool get isLoadingMessages => _isLoadingMessages;
  bool get isLoadingMoreMessages => _isLoadingMoreMessages;
  bool get hasMoreMessages => _hasMoreMessages;
  List<UserResponse> get searchResults => _searchResults;
  bool get isSearching => _isSearching;
  String? get errorMessage => _errorMessage;

  /// True when the list on screen was restored from the local cache and is
  /// waiting for (or failed to reach) the server.
  bool get showingCachedData => _showingCachedData;

  /// Timestamp of the last successful server synchronisation.
  DateTime? get lastServerSyncAt => _lastServerSyncAt;

  Map<String, String> _headers(String token) => {
    'Content-Type': 'application/json',
    'Authorization': 'Bearer $token',
  };

  // ---------------------------------------------------------------------------
  // 0. Local disk cache (offline-first, Telegram-style local database)
  //
  //  * Server answers are written to disk (CacheService).
  //  * On start / refresh the cached snapshot is shown instantly.
  //  * The server answer is then diffed against the snapshot and only the
  //    difference is applied, so nothing that did not change is rebuilt.
  // ---------------------------------------------------------------------------

  String _cacheUserId(AuthProvider authProvider) =>
      authProvider.currentUserId ?? 'anonymous';

  /// Loads the conversation list from disk and shows it immediately.
  /// Returns true when cached data was applied.
  Future<bool> hydrateFromCache(AuthProvider authProvider) async {
    if (_conversations.isNotEmpty) return false; // live data already wins

    final cached =
        await CacheService.loadConversations(_cacheUserId(authProvider));
    if (cached == null || cached.items.isEmpty) return false;

    _conversations = cached.items;
    _lastServerSyncAt = cached.savedAt;
    _showingCachedData = true;
    notifyListeners();
    return true;
  }

  /// Drops everything that is currently in memory and on disk for the given
  /// account. Used by "Clear local cache" in the settings.
  Future<void> clearLocalCache(AuthProvider authProvider) async {
    final userId = _cacheUserId(authProvider);
    _conversationCacheTimer?.cancel();
    _messageCacheTimer?.cancel();
    await CacheService.clearUser(userId);

    _conversations = [];
    _currentMessages = [];
    _conversationPage = 0;
    _messagePage = 0;
    _hasMoreConversations = true;
    _hasMoreMessages = true;
    _showingCachedData = false;
    _lastServerSyncAt = null;
    notifyListeners();
  }

  /// Removes the cached (and in-memory) messages of a single conversation.
  /// Used by the "Storage" screen when the user clears one chat.
  Future<void> clearConversationMessages(
    AuthProvider authProvider,
    String conversationId,
  ) async {
    await CacheService.clearConversationCache(
      _cacheUserId(authProvider),
      conversationId,
    );

    if (_activeConversationId == conversationId) {
      _messageCacheTimer?.cancel();
      _currentMessages = [];
      _messagePage = 0;
      _hasMoreMessages = true;
      notifyListeners();
    }
  }

  /// Merges the server answer into the cached conversation list.
  ///
  /// * Conversations returned by the server replace the cached copy (newest
  ///   information wins).
  /// * Cached conversations the server did not mention are kept, so opening
  ///   the app offline still shows the whole list.
  /// * The result is sorted by "last activity", newest first.
  List<ConversationResponse> _mergeConversations(
    List<ConversationResponse> cached,
    List<ConversationResponse> server,
  ) {
    final serverIds = server.map((c) => c.id).toSet();

    final byId = <String, ConversationResponse>{
      for (final c in cached) c.id: c,
    };
    for (final s in server) {
      byId[s.id] = s;
    }

    final merged = byId.values.toList()
      ..sort((a, b) => _activityTime(b).compareTo(_activityTime(a)));

    // Drop cached conversations that are too old to be relevant anymore.
    // Conversations coming from the server are always kept.
    final cutoff = DateTime.now().subtract(CacheService.cacheTtl);
    return merged
        .where((c) =>
            serverIds.contains(c.id) || _activityTime(c).isAfter(cutoff))
        .toList();
  }

  /// Merges the server messages into the cached ones.
  /// Server messages win, cached messages that the server did not send yet
  /// (older history, offline messages) are kept.
  List<MessageResponse> _mergeMessages(
    List<MessageResponse> cached,
    List<MessageResponse> server,
  ) {
    final serverIds = server.map((m) => m.id).toSet();

    final byId = <String, MessageResponse>{
      for (final m in cached) m.id: m,
    };
    for (final s in server) {
      byId[s.id] = s;
    }

    final merged = byId.values.toList()
      ..sort((a, b) => _messageTime(b).compareTo(_messageTime(a)));

    final cutoff = DateTime.now().subtract(CacheService.cacheTtl);
    return merged
        .where((m) => serverIds.contains(m.id) || _messageTime(m).isAfter(cutoff))
        .toList();
  }

  DateTime _activityTime(ConversationResponse c) =>
      c.lastMessageAt ?? c.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);

  DateTime _messageTime(MessageResponse m) =>
      m.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);

  /// Writes the conversation list to disk (debounced).
  void _scheduleConversationCacheSave(AuthProvider authProvider) {
    final userId = _cacheUserId(authProvider);
    _conversationCacheTimer?.cancel();
    _conversationCacheTimer = Timer(const Duration(milliseconds: 400), () {
      CacheService.saveConversations(userId, List.of(_conversations));
    });
  }

  /// Writes the messages of the active conversation to disk (debounced).
  void _scheduleMessageCacheSave(
    AuthProvider authProvider,
    String conversationId,
  ) {
    final userId = _cacheUserId(authProvider);
    _messageCacheTimer?.cancel();
    _messageCacheTimer = Timer(const Duration(milliseconds: 400), () {
      CacheService.saveMessages(userId, conversationId, List.of(_currentMessages));
    });
  }

  // ---------------------------------------------------------------------------
  // 0. WebSocket Initialization & Realtime hooks
  // ---------------------------------------------------------------------------

  void initSocket(AuthProvider authProvider) {
    _stompService.connect(
      authProvider,
      onMessageReceived: (message) {
        handleIncomingPrivateMessage(authProvider, message);
      },
      onTypingReceived: (typingData) {
        // Global or fallback typing listener if needed
      },
    );
  }

  void subscribeToActiveConversation(String conversationId) {
    _stompService.subscribeToConversation(conversationId, (message) {
      if (_activeConversationId == conversationId) {
        if (!_currentMessages.any((m) => m.id == message.id)) {
          _currentMessages.insert(0, message);
          _typingTimer?.cancel();
          _activeTypingUser = null;
        }
      }

      // ALWAYS update lastMessage and lastMessageAt in _conversations list in real-time!
      final idx = _conversations.indexWhere((c) => c.id == message.conversationId);
      if (idx != -1) {
        final targetChat = _conversations.removeAt(idx);
        final updatedChat = ConversationResponse(
          id: targetChat.id,
          type: targetChat.type,
          name: targetChat.name,
          description: targetChat.description,
          createdAt: targetChat.createdAt,
          lastMessageAt: message.createdAt ?? DateTime.now(),
          members: targetChat.members,
          lastMessage: message,
          status: targetChat.status,
          requesterId: targetChat.requesterId,
        );
        _conversations.insert(0, updatedChat);
      }
      notifyListeners();
    });

    _stompService.subscribeToTyping(conversationId, (typingData) {
      final username = typingData['username'];
      final isTyping = typingData['isTyping'] ?? false;
      final userId = typingData['userId'];

      if (userId != null && authProviderUserId != null && userId == authProviderUserId) {
        return;
      }

      _typingTimer?.cancel();
      if (isTyping == true && username != null && username.toString().isNotEmpty) {
        _activeTypingUser = username.toString();
        _typingTimer = Timer(const Duration(seconds: 4), () {
          _activeTypingUser = null;
          notifyListeners();
        });
      } else {
        _activeTypingUser = null;
      }
      notifyListeners();
    });
  }

  void sendTyping(String conversationId, {bool isTyping = true}) {
    _stompService.sendTypingEvent(conversationId, isTyping: isTyping);
  }

  String? authProviderUserId;

  // ---------------------------------------------------------------------------
  // 1. User Search
  // ---------------------------------------------------------------------------

  Future<List<UserResponse>> _fetchUsers(AuthProvider authProvider, String query) async {
    final response = await authProvider.authorizedRequest((token) async {
      return await http.get(
        Uri.parse('$REST_URL/api/users/search')
            .replace(queryParameters: {'username': query.trim()}),
        headers: _headers(token),
      );
    }).timeout(_timeout);

    if (response.statusCode == 200) {
      final List<dynamic> body = json.decode(response.body);
      return body.map((item) => UserResponse.fromJson(item)).toList();
    }
    return [];
  }

  Future<List<UserResponse>> searchUsersFuture(AuthProvider authProvider, String query) async {
    if (query.trim().isEmpty) return [];
    try {
      return await _fetchUsers(authProvider, query);
    } catch (e) {
      debugPrint("Error searching users: $e");
      return [];
    }
  }

  Future<void> searchUsers(AuthProvider authProvider, String query) async {
    final seq = ++_searchSeq;

    if (query.trim().isEmpty) {
      _searchResults = [];
      _isSearching = false;
      notifyListeners();
      return;
    }

    _isSearching = true;
    notifyListeners();

    List<UserResponse> results = [];
    try {
      results = await _fetchUsers(authProvider, query);
    } catch (e) {
      debugPrint("Error searching users: $e");
    }

    if (seq != _searchSeq) return;
    _searchResults = results;
    _isSearching = false;
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // 2. Conversations
  // ---------------------------------------------------------------------------

  Future<void> fetchConversations(AuthProvider authProvider) async {
    // Only one server request for the list at a time (the chat screen and the
    // home screen both ask for it on start).
    if (_isFetchingConversations) return;
    _isFetchingConversations = true;

    try {
      await _fetchConversationsInternal(authProvider);
    } finally {
      _isFetchingConversations = false;
    }
  }

  /// Fetches pending chat requests directed at the current user from the
  /// dedicated server endpoint GET /api/conversations/requests.
  Future<void> fetchPendingRequests(AuthProvider authProvider) async {
    try {
      final response = await authProvider.authorizedRequest((token) async {
        return await http.get(
          Uri.parse('$baseUrl/requests').replace(
              queryParameters: {'page': '0', 'size': '50'}),
          headers: _headers(token),
        );
      }).timeout(_timeout);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        List<ConversationResponse> list = [];
        if (data is Map<String, dynamic> && data.containsKey('content')) {
          list = (data['content'] as List)
              .map((e) => ConversationResponse.fromJson(e))
              .toList();
        } else if (data is List) {
          list = data.map((e) => ConversationResponse.fromJson(e)).toList();
        }
        _pendingRequests = list;
        // Subscribe to WebSocket topics for incoming request conversations
        // so the sender's first message triggers a real-time notification.
        for (final req in _pendingRequests) {
          _stompService.subscribeToConversation(req.id, (message) {
            handleIncomingPrivateMessage(authProvider, message);
          });
        }
        notifyListeners();
      }
    } catch (e) {
      debugPrint('fetchPendingRequests error: $e');
    }
  }

  Future<void> _fetchConversationsInternal(AuthProvider authProvider) async {
    // 1. Offline-first: show the cached list immediately (no spinner if the
    //    cache already has something to show).
    if (_conversations.isEmpty) {
      await hydrateFromCache(authProvider);
    }

    _isLoading = _conversations.isEmpty;
    _errorMessage = null;
    notifyListeners();

    try {
      // 2. Ask the server only for what we do not have yet. The `since`
      //    parameter is optional on the backend; when it is ignored the
      //    client-side diff below still removes every unchanged item.
      final query = <String, String>{
        'page': '0',
        'size': '$_conversationPageSize',
      };
      final since = _lastServerSyncAt?.toUtc().toIso8601String();
      if (since != null && _sendSinceParam) query['since'] = since;

      final response = await authProvider.authorizedRequest((token) async {
        return await http.get(
          Uri.parse(baseUrl).replace(queryParameters: query),
          headers: _headers(token),
        );
      }).timeout(_timeout);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        List<ConversationResponse> serverList = [];

        if (data is Map<String, dynamic> && data.containsKey('content')) {
          final List content = data['content'] ?? [];
          serverList =
              content.map((e) => ConversationResponse.fromJson(e)).toList();
          _conversationPage = 0;
          _hasMoreConversations = !(data['last'] ?? true);
        } else if (data is List) {
          serverList = data.map((e) => ConversationResponse.fromJson(e)).toList();
          _hasMoreConversations = false;
        }

        // 3. Apply only the difference between cache and server.
        final merged = _mergeConversations(_conversations, serverList);
        final changed = merged.length != _conversations.length ||
            !_sameConversationSnapshot(merged, _conversations);
        _conversations = merged;
        _showingCachedData = false;
        _lastServerSyncAt = DateTime.now();

        if (changed) {
          _scheduleConversationCacheSave(authProvider);
        }

        // Bind real-time WebSocket subscriptions for all user conversations
        _bindAllConversationTopicSubscriptions(authProvider);

        // Also refresh the incoming requests list in the background.
        fetchPendingRequests(authProvider);
      } else if (_conversations.isEmpty) {
        _errorMessage = "Failed to load conversations";
      }
    } on TimeoutException {
      // The cached list stays on screen, we only report the problem when the
      // user would otherwise see an empty screen.
      if (_conversations.isEmpty) {
        _errorMessage = "Connection timed out. Please try again.";
      } else {
        _showingCachedData = true;
      }
    } catch (e) {
      if (_conversations.isEmpty) {
        _errorMessage = "Error: $e";
      } else {
        _showingCachedData = true;
      }
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Cheap comparison of two conversation lists (ids + last activity).
  bool _sameConversationSnapshot(
    List<ConversationResponse> a,
    List<ConversationResponse> b,
  ) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].id != b[i].id) return false;
      if (a[i].lastMessageAt != b[i].lastMessageAt) return false;
    }
    return true;
  }

  void _bindAllConversationTopicSubscriptions(AuthProvider authProvider) {
    for (var convo in _conversations) {
      _stompService.subscribeToConversation(convo.id, (message) {
        handleIncomingPrivateMessage(authProvider, message);
      });
    }
  }

  Future<void> loadMoreConversations(AuthProvider authProvider) async {
    if (_isLoadingMoreConversations || _isLoading || !_hasMoreConversations) return;
    _isLoadingMoreConversations = true;
    notifyListeners();

    try {
      final nextPage = _conversationPage + 1;
      final response = await authProvider.authorizedRequest((token) async {
        return await http.get(
          Uri.parse(baseUrl).replace(queryParameters: {
            'page': '$nextPage',
            'size': '$_conversationPageSize',
          }),
          headers: _headers(token),
        );
      }).timeout(_timeout);

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        final List content = data['content'] ?? [];
        _conversations = _mergeConversations(
          _conversations,
          content.map((e) => ConversationResponse.fromJson(e)).toList(),
        );
        _conversationPage = nextPage;
        _hasMoreConversations = !(data['last'] ?? true);
        _scheduleConversationCacheSave(authProvider);
      } else {
        _errorMessage = "Failed to load more conversations";
      }
    } on TimeoutException {
      _errorMessage = "Connection timed out. Please try again.";
    } catch (e) {
      _errorMessage = "Error: $e";
    } finally {
      _isLoadingMoreConversations = false;
      notifyListeners();
    }
  }

  // ---------------------------------------------------------------------------
  // 3. Messages
  // ---------------------------------------------------------------------------

  Future<void> fetchMessages(AuthProvider authProvider, String conversationId) async {
    _activeConversationId = conversationId;
    _messagePage = 0;
    _hasMoreMessages = true;
    _isLoadingMessages = true;
    _lastMarkedReadId = null;
    _errorMessage = null;

    // 1. Offline-first: show the cached messages of this chat immediately.
    final cached =
        await CacheService.loadMessages(_cacheUserId(authProvider), conversationId);
    if (_activeConversationId != conversationId) return;

    if (cached != null && cached.items.isNotEmpty) {
      _currentMessages = cached.items;
      _showingCachedData = true;
    } else {
      _currentMessages = [];
    }
    notifyListeners();

    initSocket(authProvider);
    subscribeToActiveConversation(conversationId);

    try {
      // 2. Ask the server for the newest page. Only the difference against
      //    the cached snapshot is applied further down.
      final query = <String, String>{
        'page': '0',
        'size': '$_messagePageSize',
      };
      final since = cached?.savedAt.toUtc().toIso8601String();
      if (since != null && _sendSinceParam) query['since'] = since;

      final response = await authProvider.authorizedRequest((token) async {
        return await http.get(
          Uri.parse('$baseUrl/$conversationId/messages')
              .replace(queryParameters: query),
          headers: _headers(token),
        );
      }).timeout(_timeout);

      if (_activeConversationId != conversationId) return;

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        final List content = data['content'] ?? [];
        final fetched = content.map((e) => MessageResponse.fromJson(e)).toList();

        _currentMessages = _mergeMessages(_currentMessages, fetched);
        _hasMoreMessages = !(data['last'] ?? true);
        _showingCachedData = false;

        _scheduleMessageCacheSave(authProvider, conversationId);
      } else if (_currentMessages.isEmpty) {
        _errorMessage = "Failed to load messages";
      }
    } on TimeoutException {
      if (_activeConversationId == conversationId) {
        if (_currentMessages.isEmpty) {
          _errorMessage = "Connection timed out. Please try again.";
        } else {
          _showingCachedData = true;
        }
      }
    } catch (e) {
      if (_activeConversationId == conversationId) {
        if (_currentMessages.isEmpty) {
          _errorMessage = "Error: $e";
        } else {
          _showingCachedData = true;
        }
      }
    } finally {
      if (_activeConversationId == conversationId) {
        _isLoadingMessages = false;
        notifyListeners();
      }
    }
  }

  Future<void> loadMoreMessages(AuthProvider authProvider, String conversationId) async {
    if (_isLoadingMoreMessages || _isLoadingMessages || !_hasMoreMessages) return;
    _isLoadingMoreMessages = true;
    notifyListeners();

    try {
      final nextPage = _messagePage + 1;
      final response = await authProvider.authorizedRequest((token) async {
        return await http.get(
          Uri.parse('$baseUrl/$conversationId/messages').replace(
            queryParameters: {'page': '$nextPage', 'size': '$_messagePageSize'},
          ),
          headers: _headers(token),
        );
      }).timeout(_timeout);

      if (_activeConversationId != conversationId) return;

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        final List content = data['content'] ?? [];
        final fetched = content.map((e) => MessageResponse.fromJson(e)).toList();
        // Same merge as the first page: cached messages are kept, the server
        // wins for the messages it returned, duplicates are removed.
        _currentMessages = _mergeMessages(_currentMessages, fetched);
        _messagePage = nextPage;
        _hasMoreMessages = !(data['last'] ?? true);
        _scheduleMessageCacheSave(authProvider, conversationId);
      } else {
        _errorMessage = "Failed to load older messages";
      }
    } on TimeoutException {
      _errorMessage = "Connection timed out. Please try again.";
    } catch (e) {
      _errorMessage = "Error: $e";
    } finally {
      if (_activeConversationId == conversationId) {
        _isLoadingMoreMessages = false;
        notifyListeners();
      }
    }
  }

  // ---------------------------------------------------------------------------
  // 4. Send a message & upload files
  // ---------------------------------------------------------------------------

  Future<bool> sendMessage(
      AuthProvider authProvider,
      String conversationId,
      String content, {
        MessageType type = MessageType.TEXT,
      }) async {
    _errorMessage = null;
    try {
      final response = await authProvider.authorizedRequest((token) async {
        return await http.post(
          Uri.parse('$baseUrl/$conversationId/messages'),
          headers: _headers(token),
          body: json.encode({
            "content": content,
            "messageType": type.name,
          }),
        );
      }).timeout(_timeout);

      if (response.statusCode == 201 || response.statusCode == 200) {
        final newMessage = MessageResponse.fromJson(json.decode(response.body));
        if (_activeConversationId == conversationId &&
            !_currentMessages.any((m) => m.id == newMessage.id)) {
          _currentMessages.insert(0, newMessage);
        }
        final idx = _conversations.indexWhere((c) => c.id == conversationId);
        if (idx != -1) {
          final targetChat = _conversations.removeAt(idx);
          final updatedChat = ConversationResponse(
            id: targetChat.id,
            type: targetChat.type,
            name: targetChat.name,
            description: targetChat.description,
            createdAt: targetChat.createdAt,
            lastMessageAt: newMessage.createdAt ?? DateTime.now(),
            members: targetChat.members,
            lastMessage: newMessage,
            status: targetChat.status,
            requesterId: targetChat.requesterId,
          );
          _conversations.insert(0, updatedChat);
        } else {
          fetchConversations(authProvider);
        }
        // Persist the new state to the local cache right away.
        _scheduleConversationCacheSave(authProvider);
        if (_activeConversationId == conversationId) {
          _scheduleMessageCacheSave(authProvider, conversationId);
        }
        notifyListeners();
        return true;
      } else {
        _errorMessage = "Message not sent (${response.statusCode})";
      }
    } on TimeoutException {
      _errorMessage = "Message not sent: connection timed out.";
    } catch (e) {
      debugPrint("Failed to send message: $e");
      _errorMessage = "Message not sent. Check your connection.";
    }
    notifyListeners();
    return false;
  }

  Future<bool> uploadAndSendMessage(
      AuthProvider authProvider,
      String conversationId,
      List<int> bytes,
      String fileName, {
        MessageType? overrideType,
      }) async {
    _errorMessage = null;
    try {
      final token = authProvider.accessToken;
      if (token == null) return false;

      final uri = Uri.parse('$REST_URL/api/files/upload');
      final request = http.MultipartRequest('POST', uri);
      request.headers['Authorization'] = 'Bearer $token';

      request.files.add(http.MultipartFile.fromBytes(
        'file',
        bytes,
        filename: fileName,
      ));

      final streamedResponse = await request.send().timeout(_timeout);
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        String fileUrl = data['url'] ?? '';

        // 🛑 កន្លែងនេះហើយដែលធ្វើឱ្យវាបាត់ Supabase Domain!
        if (fileUrl.startsWith('http://') || fileUrl.startsWith('https://')) {
          final parsed = Uri.tryParse(fileUrl);
          if (parsed != null && parsed.path.isNotEmpty) {
            fileUrl = parsed.path + (parsed.hasQuery ? '?${parsed.query}' : '');
          }
        }

        MessageType msgType = overrideType ?? MessageType.FILE;
        if (overrideType == null && data['messageType'] != null) {
          final typeStr = data['messageType'].toString().toUpperCase();
          msgType = MessageType.values.firstWhere(
                (e) => e.name.toUpperCase() == typeStr,
            orElse: () => MessageType.FILE,
          );
        }

        return await sendMessage(authProvider, conversationId, fileUrl, type: msgType);
      } else {
        _errorMessage = "Failed to upload file (${response.statusCode})";
      }
    } catch (e) {
      debugPrint('Error uploading file: $e');
      _errorMessage = "Error uploading file. Check connection.";
    }
    notifyListeners();
    return false;
  }

  // ---------------------------------------------------------------------------
  // 5. Create or get private conversation
  // ---------------------------------------------------------------------------

  Future<ConversationResponse?> createPrivateConversation(
      AuthProvider authProvider, String recipientId) async {
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final response = await authProvider.authorizedRequest((token) async {
          return await http.post(
            Uri.parse('$baseUrl/private'),
            headers: _headers(token),
            body: jsonEncode({'recipientId': recipientId}),
          );
        }).timeout(_timeout);

        if (response.statusCode == 200 || response.statusCode == 201) {
          final conversation =
          ConversationResponse.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
          _upsertConversationAtTop(conversation);
          _scheduleConversationCacheSave(authProvider);
          notifyListeners();
          return conversation;
        }
        if (response.statusCode == 409 && attempt == 0) continue;

        debugPrint('Failed to create private conversation: ${response.statusCode}\n${response.body}');
        return null;
      } catch (e) {
        debugPrint('Error creating private conversation: $e');
        return null;
      }
    }
    return null;
  }

  void _upsertConversationAtTop(ConversationResponse conversation) {
    _conversations.removeWhere((c) => c.id == conversation.id);
    _conversations.insert(0, conversation);
  }

  Future<ConversationResponse?> createGroupConversation(
      AuthProvider authProvider, {
        required String name,
        String? description,
        required List<String> memberIds,
      }) async {
    try {
      final response = await authProvider.authorizedRequest((token) async {
        return await http.post(
          Uri.parse('$baseUrl/group'),
          headers: _headers(token),
          body: jsonEncode({
            'name': name,
            if (description != null && description.isNotEmpty) 'description': description,
            'memberIds': memberIds,
          }),
        );
      }).timeout(_timeout);

      if (response.statusCode == 200 || response.statusCode == 201) {
        final conversation =
        ConversationResponse.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
        _upsertConversationAtTop(conversation);
        _scheduleConversationCacheSave(authProvider);
        notifyListeners();
        return conversation;
      }
      debugPrint('Failed to create group conversation: ${response.statusCode}\n${response.body}');
      return null;
    } catch (e) {
      debugPrint('Error creating group conversation: $e');
      return null;
    }
  }

  Future<bool> addMembersToGroup(
      AuthProvider authProvider, String conversationId, List<String> newMemberIds) async {
    try {
      final response = await authProvider.authorizedRequest((token) async {
        return await http.post(
          Uri.parse('$baseUrl/$conversationId/members'),
          headers: _headers(token),
          body: jsonEncode({'memberIds': newMemberIds}),
        );
      }).timeout(_timeout);

      if (response.statusCode == 200 || response.statusCode == 201) {
        await fetchConversations(authProvider);
        return true;
      }
      return false;
    } catch (e) {
      debugPrint("Error adding group members: $e");
      return false;
    }
  }

  // ---------------------------------------------------------------------------
  // 6. Mark as read & Edit & Delete
  // ---------------------------------------------------------------------------

  Future<void> markAsRead(AuthProvider authProvider, String conversationId) async {
    if (_activeConversationId != conversationId || _currentMessages.isEmpty) return;

    final lastId = _currentMessages.first.id;
    if (lastId == _lastMarkedReadId) return;
    _lastMarkedReadId = lastId;

    try {
      await authProvider.authorizedRequest((token) async {
        return await http.post(
          Uri.parse('$baseUrl/$conversationId/messages/$lastId/read'),
          headers: _headers(token),
        );
      }).timeout(_timeout);
    } catch (e) {
      _lastMarkedReadId = null;
      debugPrint("Failed to mark as read: $e");
    }
  }

  Future<bool> editMessage(
      AuthProvider authProvider, String messageId, String newContent) async {
    try {
      final response = await authProvider.authorizedRequest((token) async {
        return await http.put(
          Uri.parse('$baseUrl/messages/$messageId'),
          headers: _headers(token),
          body: jsonEncode({'content': newContent}),
        );
      }).timeout(_timeout);

      if (response.statusCode == 200) {
        final updatedMessage = MessageResponse.fromJson(jsonDecode(response.body));
        final index = _currentMessages.indexWhere((m) => m.id == messageId);
        if (index != -1) {
          _currentMessages[index] = updatedMessage;
          final activeId = _activeConversationId;
          if (activeId != null) {
            _scheduleMessageCacheSave(authProvider, activeId);
          }
          notifyListeners();
        }
        return true;
      }
      return false;
    } catch (e) {
      debugPrint("Failed to edit message: $e");
      return false;
    }
  }

  Future<bool> deleteMessage(
      AuthProvider authProvider, String messageId) async {
    try {
      final response = await authProvider.authorizedRequest((token) async {
        return await http.delete(
          Uri.parse('$baseUrl/messages/$messageId'),
          headers: _headers(token),
        );
      }).timeout(_timeout);

      if (response.statusCode == 200 || response.statusCode == 204) {
        _currentMessages.removeWhere((m) => m.id == messageId);
        if (_activeConversationId != null) {
          _scheduleMessageCacheSave(authProvider, _activeConversationId!);
        }
        notifyListeners();
        return true;
      }
      return false;
    } catch (e) {
      debugPrint("Failed to delete message: $e");
      return false;
    }
  }

  Future<void> markAllMessagesAsRead(
      AuthProvider authProvider, String conversationId) async {
    try {
      await authProvider.authorizedRequest((token) async {
        return await http.post(
          Uri.parse('$baseUrl/$conversationId/read-all'),
          headers: _headers(token),
        );
      }).timeout(_timeout);
    } catch (e) {
      debugPrint("Failed to mark all as read: $e");
    }
  }

  // ---------------------------------------------------------------------------
  // 7. Realtime Handlers
  // ---------------------------------------------------------------------------

  void handleChatEvent(AuthProvider authProvider, ChatEvent event) {
    final m = event.message;

    if (_activeConversationId == m.conversationId) {
      final i = _currentMessages.indexWhere((x) => x.id == m.id);
      switch (event.type) {
        case ChatEventType.created:
          if (i == -1) _currentMessages.insert(0, m);
          break;
        case ChatEventType.edited:
        case ChatEventType.deleted:
          if (i != -1) _currentMessages[i] = m;
          break;
      }
    }

    if (event.type == ChatEventType.created) {
      final idx = _conversations.indexWhere((c) => c.id == m.conversationId);
      if (idx != -1) {
        final targetChat = _conversations.removeAt(idx);
        final updatedChat = ConversationResponse(
          id: targetChat.id,
          type: targetChat.type,
          name: targetChat.name,
          description: targetChat.description,
          createdAt: targetChat.createdAt,
          lastMessageAt: m.createdAt ?? DateTime.now(),
          members: targetChat.members,
          lastMessage: m,
          status: targetChat.status,
          requesterId: targetChat.requesterId,
        );
        _conversations.insert(0, updatedChat);
      } else {
        // Automatically fetch conversations if a message arrives for a chat not yet in list
        fetchConversations(authProvider);
      }
    }
    // Persist the real-time update to the local cache as well.
    _scheduleConversationCacheSave(authProvider);
    if (_activeConversationId == m.conversationId) {
      _scheduleMessageCacheSave(authProvider, m.conversationId);
    }

    notifyListeners();
  }

  void Function(MessageResponse message)? onNewMessageNotification;

  /// Clears all in-memory conversation and message state when the user switches
  /// accounts. The local disk cache is NOT cleared here — CacheService.clearUser
  /// handles that in AuthProvider. Called by AccountSwitcherScreen.
  void resetForAccountSwitch() {
    _conversations = [];
    _pendingRequests = [];
    _currentMessages = [];
    _conversationPage = 0;
    _messagePage = 0;
    _hasMoreConversations = true;
    _hasMoreMessages = true;
    _activeConversationId = null;
    _lastMarkedReadId = null;
    _errorMessage = null;
    _showingCachedData = false;
    _lastServerSyncAt = null;
    _searchResults = [];
    _activeTypingUser = null;
    _typingTimer?.cancel();
    _conversationCacheTimer?.cancel();
    _messageCacheTimer?.cancel();
    authProviderUserId = null;
    _stompService.disconnect();
    notifyListeners();
  }

  void handleIncomingPrivateMessage(AuthProvider authProvider, MessageResponse message) {
    final known = _conversations.any((c) => c.id == message.conversationId);
    if (!known) {
      // Might be a new chat request — refresh both lists.
      fetchConversations(authProvider);
      fetchPendingRequests(authProvider);
    }

    handleChatEvent(authProvider, ChatEvent(ChatEventType.created, message));

    if (_activeConversationId == message.conversationId) {
      _typingTimer?.cancel();
      _activeTypingUser = null;
      notifyListeners();
    } else {
      onNewMessageNotification?.call(message);
    }
  }

  // ---------------------------------------------------------------------------
  // 8. Chat Request Actions (accept / reject)
  // ---------------------------------------------------------------------------

  /// Incoming chat requests directed at the current user.
  /// Sourced from the dedicated GET /api/conversations/requests endpoint.
  List<ConversationResponse> pendingRequests(String currentUserId) => _pendingRequests;

  Future<bool> acceptRequest(AuthProvider authProvider, String conversationId) async {
    try {
      final response = await authProvider.authorizedRequest((token) async {
        return await http.post(
          Uri.parse('$baseUrl/$conversationId/accept'),
          headers: _headers(token),
        );
      }).timeout(_timeout);

      if (response.statusCode == 200) {
        final updated = ConversationResponse.fromJson(json.decode(response.body));
        // Move from pending list into accepted conversations.
        _pendingRequests.removeWhere((c) => c.id == conversationId);
        _upsertConversationAtTop(updated);
        _scheduleConversationCacheSave(authProvider);
        notifyListeners();
        return true;
      }
      debugPrint('acceptRequest failed: ${response.statusCode} ${response.body}');
      return false;
    } catch (e) {
      debugPrint('acceptRequest error: $e');
      return false;
    }
  }

  Future<bool> rejectRequest(AuthProvider authProvider, String conversationId) async {
    try {
      final response = await authProvider.authorizedRequest((token) async {
        return await http.post(
          Uri.parse('$baseUrl/$conversationId/reject'),
          headers: _headers(token),
        );
      }).timeout(_timeout);

      if (response.statusCode == 200 || response.statusCode == 204) {
        _pendingRequests.removeWhere((c) => c.id == conversationId);
        _conversations.removeWhere((c) => c.id == conversationId);
        _scheduleConversationCacheSave(authProvider);
        notifyListeners();
        return true;
      }
      debugPrint('rejectRequest failed: ${response.statusCode} ${response.body}');
      return false;
    } catch (e) {
      debugPrint('rejectRequest error: $e');
      return false;
    }
  }
}