import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:stomp_dart_client/stomp.dart';
import 'package:stomp_dart_client/stomp_config.dart';
import 'package:stomp_dart_client/stomp_frame.dart';
import 'package:love_in_chat/api/api.dart';
import 'package:love_in_chat/model/Response/MessageResponse.dart';
import 'package:love_in_chat/provider/AuthProvider.dart';

class StompService {
  static final StompService _instance = StompService._internal();

  factory StompService() => _instance;

  StompService._internal();

  StompClient? _stompClient;
  bool _isConnected = false;

  Function(MessageResponse message)? _onPrivateMessageReceived;

  /// Extra listeners (e.g. the offline repository) that want to see every
  /// incoming message without replacing the primary callback.
  final List<Function(MessageResponse message)> _incomingMessageListeners = [];

  final Map<String, Function(MessageResponse)> _activeConversationSubscriptions = {};
  final Map<String, Function(Map<String, dynamic>)> _activeTypingSubscriptions = {};

  final List<VoidCallback> _pendingSubscriptions = [];

  bool get isConnected => _isConnected;

  /// Registers an additional listener for incoming messages.
  void addIncomingMessageListener(Function(MessageResponse message) listener) {
    if (!_incomingMessageListeners.contains(listener)) {
      _incomingMessageListeners.add(listener);
    }
  }

  /// Removes a listener that was added with [addIncomingMessageListener].
  void removeIncomingMessageListener(
      Function(MessageResponse message) listener) {
    _incomingMessageListeners.remove(listener);
  }

  /// Forwards a message to the primary callback and to every extra listener.
  void _notifyIncoming(MessageResponse message) {
    _onPrivateMessageReceived?.call(message);
    for (final listener in List.of(_incomingMessageListeners)) {
      try {
        listener(message);
      } catch (e) {
        debugPrint('Error in incoming message listener: $e');
      }
    }
  }

  void connect(
      AuthProvider authProvider, {
        required Function(MessageResponse message) onMessageReceived,
        required Function(Map<String, dynamic> typingData) onTypingReceived,
      }) {
    _onPrivateMessageReceived = onMessageReceived;

    if (_isConnected && _stompClient != null) return;

    final token = authProvider.accessToken;
    if (token == null) {
      debugPrint('STOMP Connection failed: No access token available.');
      return;
    }

    final wsUrl = '$SOCKET_URL/chat';

    _stompClient = StompClient(
      config: StompConfig(
        url: wsUrl,
        reconnectDelay: const Duration(seconds: 3),
        onConnect: (StompFrame frame) {
          _isConnected = true;
          debugPrint('>>> STOMP SOCKET CONNECTED SUCCESSFULLY TO $wsUrl! <<<');

          // 1. Subscribe to private queue
          _stompClient?.subscribe(
            destination: '/user/queue/private',
            callback: (StompFrame frame) {
              if (frame.body != null) {
                try {
                  final data = json.decode(frame.body!);
                  debugPrint('>>> PRIVATE QUEUE MESSAGE RECEIVED: ${frame.body} <<<');
                  _notifyIncoming(MessageResponse.fromJson(data));
                } catch (e) {
                  debugPrint('Error parsing private queue message: $e');
                }
              }
            },
          );

          // 1.5. Subscribe to global user conversation queue
          subscribeToUserInbox((message) {
            _notifyIncoming(message);
          });

          // 2. Re-bind active conversation topic subscriptions
          _activeConversationSubscriptions.forEach((id, callback) {
            _doSubscribeConversation(id, callback);
          });

          // 3. Re-bind active typing topic subscriptions
          _activeTypingSubscriptions.forEach((id, callback) {
            _doSubscribeTyping(id, callback);
          });

          // 4. Flush any pending subscriptions
          final pending = List<VoidCallback>.from(_pendingSubscriptions);
          _pendingSubscriptions.clear();
          for (var sub in pending) {
            sub();
          }

          // 5. Re-subscribe to the signal queue if any callback was registered
          //    (handles reconnects — without this, incoming calls stop arriving
          //    after a STOMP reconnect because the subscription is lost).
          _liveSignalSubscriptions.clear();
          for (final sigCb in List.of(_signalingCallbacks)) {
            _subscribeSignal(sigCb);
          }
        },
        onWebSocketError: (error) {
          _isConnected = false;
          debugPrint('STOMP WebSocket Error: $error');
        },
        onStompError: (frame) {
          _isConnected = false;
          debugPrint('STOMP Protocol Error: ${frame.body}');
        },
        onDisconnect: (frame) {
          _isConnected = false;
          debugPrint('STOMP Disconnected');
        },
        stompConnectHeaders: {'Authorization': 'Bearer $token'},
        webSocketConnectHeaders: {'Authorization': 'Bearer $token'},
      ),
    );

    _stompClient?.activate();
  }

  void _doSubscribeConversation(String conversationId, Function(MessageResponse) onMessage) {
    if (_stompClient == null || !_isConnected) return;
    _stompClient!.subscribe(
      destination: '/topic/conversations/$conversationId',
      callback: (StompFrame frame) {
        if (frame.body != null) {
          try {
            final data = json.decode(frame.body!);
            debugPrint('>>> WEBSOCKET ROOM MESSAGE RECEIVED FOR $conversationId: ${frame.body} <<<');
            onMessage(MessageResponse.fromJson(data));
          } catch (e) {
            debugPrint('Error parsing conversation message: $e');
          }
        }
      },
    );
  }

  void subscribeToConversation(String conversationId, Function(MessageResponse) onMessage) {
    _activeConversationSubscriptions[conversationId] = onMessage;
    if (_isConnected && _stompClient != null) {
      _doSubscribeConversation(conversationId, onMessage);
    } else {
      _pendingSubscriptions.add(() => _doSubscribeConversation(conversationId, onMessage));
    }
  }

  void _doSubscribeTyping(String conversationId, Function(Map<String, dynamic>) onTyping) {
    if (_stompClient == null || !_isConnected) return;
    _stompClient!.subscribe(
      destination: '/topic/conversations/$conversationId/typing',
      callback: (StompFrame frame) {
        if (frame.body != null) {
          try {
            final data = json.decode(frame.body!) as Map<String, dynamic>;
            onTyping(data);
          } catch (e) {
            debugPrint('Error parsing typing notification: $e');
          }
        }
      },
    );
  }

  void subscribeToTyping(String conversationId, Function(Map<String, dynamic>) onTyping) {
    _activeTypingSubscriptions[conversationId] = onTyping;
    if (_isConnected && _stompClient != null) {
      _doSubscribeTyping(conversationId, onTyping);
    } else {
      _pendingSubscriptions.add(() => _doSubscribeTyping(conversationId, onTyping));
    }
  }

  void sendTypingEvent(String conversationId, {bool isTyping = true}) {
    if (_isConnected && _stompClient != null) {
      _stompClient!.send(
        destination: '/app/chat.typing/$conversationId',
        body: json.encode({'isTyping': isTyping}),
      );
    }
  }

  // NEW: Added method to send messages easily from Flutter UI
  void sendMessage(String conversationId, String content) {
    if (_isConnected && _stompClient != null) {
      _stompClient!.send(
        destination: '/app/chat.send/$conversationId',
        body: json.encode({
          'content': content,
        }),
      );
      debugPrint('>>> SENT MESSAGE TO /app/chat.send/$conversationId <<<');
    } else {
      debugPrint('Cannot send message: STOMP client is not connected.');
    }
  }

  void subscribeToUserInbox(Function(MessageResponse) onNewMessage) {
    void doSubscribe() {
      if (_stompClient == null || !_isConnected) return;
      _stompClient!.subscribe(
        destination: '/user/queue/conversations',
        callback: (StompFrame frame) {
          if (frame.body != null) {
            try {
              final data = json.decode(frame.body!);
              debugPrint('>>> GLOBAL USER INBOX MESSAGE RECEIVED: ${frame.body} <<<');
              onNewMessage(MessageResponse.fromJson(data));
            } catch (e) {
              debugPrint('Error parsing global inbox message: $e');
            }
          }
        },
      );
    }

    if (_isConnected && _stompClient != null) {
      doSubscribe();
    } else {
      _pendingSubscriptions.add(doSubscribe);
    }
  }

  void disconnect() {
    _stompClient?.deactivate();
    _isConnected = false;
    _stompClient = null;
    _pendingSubscriptions.clear();
    _activeConversationSubscriptions.clear();
    _activeTypingSubscriptions.clear();
    _signalingCallbacks.clear();
    _liveSignalSubscriptions.clear();
    debugPrint('STOMP client deactivated and cleaned up.');
  }

  // ── WebRTC signaling ───────────────────────────────────────────────────────

  /// The active signaling callbacks — stored so they are re-registered on
  /// reconnect.
  ///
  /// A list is used because several services listen on the same queue (the
  /// 1-on-1 call service AND the group call service). Keeping only a single
  /// callback meant a group call silently disabled 1-on-1 call signalling.
  final List<Function(StompFrame)> _signalingCallbacks = [];

  /// Callbacks that currently have a live broker subscription. Used to avoid
  /// duplicate subscriptions (a duplicate delivers every frame twice).
  final Set<Function(StompFrame)> _liveSignalSubscriptions = {};

  /// Subscribe to incoming WebRTC signaling messages on /user/queue/signal.
  /// Storing the callback ensures it is re-subscribed automatically after a
  /// STOMP reconnection (which previously caused the 1-on-1 incoming call to
  /// stop arriving after the first reconnect).
  void subscribeToSignaling(Function(StompFrame) onFrame) {
    if (!_signalingCallbacks.contains(onFrame)) {
      _signalingCallbacks.add(onFrame);
    }
    // If the socket is not connected yet, the onConnect handler subscribes
    // every registered callback — so nothing to do here.
    _subscribeSignal(onFrame);
  }

  void _subscribeSignal(Function(StompFrame) onFrame) {
    if (_stompClient == null || !_isConnected) return;
    if (_liveSignalSubscriptions.contains(onFrame)) return;
    _liveSignalSubscriptions.add(onFrame);
    _stompClient!.subscribe(
      destination: '/user/queue/signal',
      callback: onFrame,
    );
  }

  /// Remove a signaling subscriber (e.g. when a call service is disposed).
  void unsubscribeFromSignaling(Function(StompFrame) onFrame) {
    _signalingCallbacks.remove(onFrame);
    _liveSignalSubscriptions.remove(onFrame);
  }

  /// Subscribe to group call events on a conversation's /call topic.
  /// Used to receive GROUP_CALL_STARTED broadcasts.
  void subscribeToGroupCallTopic(
      String conversationId, Function(StompFrame) onFrame) {
    void doSub() {
      if (_stompClient == null || !_isConnected) return;
      _stompClient!.subscribe(
        destination: '/topic/conversations/$conversationId/call',
        callback: onFrame,
      );
    }
    if (_isConnected && _stompClient != null) {
      doSub();
    } else {
      _pendingSubscriptions.add(doSub);
    }
  }

  /// Forward a 1-to-1 signaling payload to [targetUserId] via STOMP.
  void sendSignal(String targetUserId, Map<String, dynamic> payload) {
    if (_stompClient == null || !_isConnected) {
      debugPrint('[Signaling] STOMP not connected — cannot send signal');
      return;
    }
    _stompClient!.send(
      destination: '/app/signal/$targetUserId',
      body: json.encode(payload),
    );
  }

  /// Broadcast a group call event to all members of [conversationId].
  void sendGroupSignal(String conversationId, Map<String, dynamic> payload) {
    if (_stompClient == null || !_isConnected) {
      debugPrint('[Signaling] STOMP not connected — cannot send group signal');
      return;
    }
    _stompClient!.send(
      destination: '/app/signal/group/$conversationId',
      body: json.encode(payload),
    );
  }
}