import 'dart:async';
import 'dart:convert';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_callkit_incoming/entities/android_params.dart';
import 'package:flutter_callkit_incoming/entities/call_event.dart';
import 'package:flutter_callkit_incoming/entities/call_kit_params.dart';
import 'package:flutter_callkit_incoming/entities/ios_params.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import 'package:love_in_chat/api/api.dart';
import '../screen/GroupCallScreen.dart';
import 'CallOverlayController.dart';
import 'CallRingtoneService.dart';
import 'CallSignalingService.dart';
import 'StompService.dart';

/// Global navigator key attached to MaterialApp for top-level navigation from CallKit events
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

/// Top-level background message handler for FCM push notifications
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    await Firebase.initializeApp();
  } catch (e) {
    debugPrint('[FCM Background] Firebase initialize error: $e');
  }

  final data = message.data;
  debugPrint('[FCM Background] High-priority data payload received: $data');

  final type = data['type']?.toString().toUpperCase();

  if (type == 'INCOMING_CALL' || type == 'CALL_OFFER') {
    await CallKitService.showIncomingCall(data);
  } else if (type == 'CALL_CANCELLED' ||
      type == 'CALL_CANCEL' ||
      type == 'CALL_HANGUP' ||
      type == 'CALL_REJECT') {
    await CallKitService.endAllCalls();
  }
}

class CallKitService {
  static final Set<String> _handledCallIds = {};
  static final Set<String> _acceptedSessions = {};
  static CallSignalingService? _signalingService;
  static StreamSubscription? _eventSub;

  /// True while WE are ending the CallKit UI (after accept/decline), so the
  /// resulting actionCallEnded event doesn't tear down the real call.
  static bool _suppressEnded = false;

  // ── SharedPreferences keys ────────────────────────────────────────────────
  static const _kAccessToken = 'access_token';
  static const _kUserId = 'user_id';
  static const _kUsername = 'username';

  /// Must match the caller's ring timeout (CallScreen._ringTimeout = 45s)
  static const _ringDurationMs = 45000;

  static void setSignalingService(CallSignalingService service) {
    _signalingService = service;
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Payload & Deep Map Normalization Helpers
  // ───────────────────────────────────────────────────────────────────────────

  static Map<String, dynamic> _deepNormalizeMap(dynamic raw) {
    if (raw is Map<String, dynamic>) {
      return raw.map((k, v) => MapEntry(k, _normalizeValue(v)));
    }
    if (raw is Map) {
      return raw.map((k, v) => MapEntry(k.toString(), _normalizeValue(v)));
    }
    return <String, dynamic>{};
  }

  static dynamic _normalizeValue(dynamic value) {
    if (value is Map) {
      return _deepNormalizeMap(value);
    }
    if (value is List) {
      return value.map(_normalizeValue).toList();
    }
    return value;
  }

  /// ធានាថា offer['sdp'] តែងតែមានទម្រង់ {'type': 'offer', 'sdp': '...'} ត្រឹមត្រូវ
  /// ទោះបីជាមកពី FCM String ឬ STOMP Map ក៏ដោយ
  static Map<String, dynamic> _normalizeOfferPayload(dynamic raw) {
    final map = _deepNormalizeMap(raw);
    final rawSdp = map['sdp'];

    if (rawSdp is String && rawSdp.isNotEmpty) {
      if (rawSdp.trim().startsWith('{')) {
        try {
          final decoded = jsonDecode(rawSdp);
          if (decoded is Map) {
            map['sdp'] = _deepNormalizeMap(decoded);
          }
        } catch (_) {}
      } else {
        map['sdp'] = <String, dynamic>{
          'type': map['sdpType']?.toString() ?? 'offer',
          'sdp': rawSdp,
        };
      }
    }
    return map;
  }

  static bool _isTrue(dynamic v) => v == true || v?.toString() == 'true';

  static bool _isVideoCall(Map<String, dynamic> d) =>
      d['callType']?.toString().toUpperCase() == 'VIDEO' || _isTrue(d['isVideo']);

  static bool _isGroupCall(Map<String, dynamic> d) =>
      _isTrue(d['isGroup']) || d['type']?.toString() == 'GROUP_CALL_STARTED';

  static String _sessionIdOf(Map<String, dynamic> d) =>
      d['callSessionId']?.toString() ?? d['callId']?.toString() ?? '';

  static String _callerNameOf(Map<String, dynamic> d, {String fallback = 'Caller'}) =>
      d['callerName']?.toString() ??
          d['fromUsername']?.toString() ??
          d['callerUsername']?.toString() ??
          fallback;

  static String _callerIdOf(Map<String, dynamic> d) =>
      d['fromUserId']?.toString() ?? d['callerUserId']?.toString() ?? '';

  // ───────────────────────────────────────────────────────────────────────────
  // Show / end
  // ───────────────────────────────────────────────────────────────────────────

  /// Displays the native CallKit incoming call UI (foreground, background, killed)
  static Future<void> showIncomingCall(Map<String, dynamic> data) async {
    final normalizedData = _normalizeOfferPayload(data);

    final callId = normalizedData['callId']?.toString() ??
        normalizedData['callSessionId']?.toString() ??
        normalizedData['conversationId']?.toString() ??
        const Uuid().v4();

    // In-isolate dedupe
    if (_handledCallIds.contains(callId)) {
      debugPrint('[CallKit] Call ID $callId already handled. Skipping.');
      return;
    }

    // Cross-isolate dedupe
    try {
      final active = await FlutterCallkitIncoming.activeCalls();
      if (active is List && active.any((c) => c['id']?.toString() == callId)) {
        debugPrint('[CallKit] Call ID $callId already active natively. Skipping.');
        _handledCallIds.add(callId);
        return;
      }
    } catch (e) {
      debugPrint('[CallKit] activeCalls check failed: $e');
    }

    _handledCallIds.add(callId);

    final callerName = _callerNameOf(
      normalizedData,
      fallback: normalizedData['fromUserId']?.toString() ?? 'Incoming Call',
    );
    final isVideo = _isVideoCall(normalizedData);
    final isGroup = _isGroupCall(normalizedData);
    final groupName = normalizedData['groupName']?.toString() ??
        normalizedData['chatName']?.toString() ??
        'Group Call';

    final params = CallKitParams(
      id: callId,
      nameCaller: isGroup ? groupName : callerName,
      appName: 'In Love',
      avatar: normalizedData['avatar']?.toString() ?? '',
      handle: isGroup ? '$callerName started a group call' : callerName,
      type: isVideo ? 1 : 0,
      duration: _ringDurationMs,
      textAccept: isGroup ? 'Join' : 'Accept',
      textDecline: 'Decline',
      extra: normalizedData,
      android: const AndroidParams(
        isCustomNotification: true,
        isShowLogo: false,
        ringtonePath: 'system_ringtone_default',
        backgroundColor: '#1A0F16',
        actionColor: '#F50057',
        textColor: '#ffffff',
      ),
      ios: const IOSParams(
        iconName: 'CallKitIcon',
        handleType: 'generic',
        supportsVideo: true,
        maximumCallGroups: 1,
        maximumCallsPerCallGroup: 1,
        audioSessionActive: true,
        audioSessionPreferredSampleRate: 44100.0,
        audioSessionPreferredIOBufferDuration: 0.005,
        supportsGrouping: false,
        supportsUngrouping: false,
        supportsHolding: false,
        supportsDTMF: true,
      ),
    );

    await FlutterCallkitIncoming.showCallkitIncoming(params);
  }

  /// Dismisses all active CallKit calls
  static Future<void> endAllCalls() async {
    _handledCallIds.clear();
    _acceptedSessions.clear();
    await FlutterCallkitIncoming.endAllCalls();
  }

  /// Ends the CallKit UI after the user accepted/declined, without letting the
  /// resulting "ended" event hang up the real call.
  static Future<void> _endCallKitUiSilently() async {
    _suppressEnded = true;
    _handledCallIds.clear();
    try {
      await FlutterCallkitIncoming.endAllCalls();
    } finally {
      Future.delayed(const Duration(seconds: 1), () => _suppressEnded = false);
    }
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Event listeners
  // ───────────────────────────────────────────────────────────────────────────

  /// Initialize CallKit event listeners for Accept, Decline, Timeout, and Ended
  static void initializeEventListeners(CallSignalingService signalingService) {
    _signalingService = signalingService;

    _eventSub?.cancel();
    _eventSub = FlutterCallkitIncoming.onEvent.listen((CallEvent? event) async {
      if (event == null) return;
      debugPrint('[CallKit Event] ${event.event}:${event.body}');

      final body = _deepNormalizeMap(event.body);
      final extra = body['extra'] is Map
          ? _deepNormalizeMap(body['extra'])
          : body;

      switch (event.event) {
        case Event.actionCallAccept:
          await _handleCallAccept(extra);
          break;
        case Event.actionCallDecline:
          await _handleCallDecline(extra);
          break;
        case Event.actionCallTimeout:
          _handledCallIds.clear();
          await CallRingtoneService.stop();
          break;
        case Event.actionCallEnded:
          _handledCallIds.clear();
          if (_suppressEnded) {
            _suppressEnded = false;
            break;
          }
          await CallRingtoneService.stop();
          break;
        default:
          break;
      }
    });
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Accept / Decline
  // ───────────────────────────────────────────────────────────────────────────

  /// POST /api/calls/{action}/{sessionId}. Returns true on 2xx.
  static Future<bool> postCallAction(String action, String sessionId,
      {Map<String, dynamic>? sdp}) async {
    if (sessionId.isEmpty) return false;
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString(_kAccessToken);
      if (token == null || token.isEmpty) return false;

      final bodyData = <String, dynamic>{};
      if (sdp != null) {
        bodyData['sdp'] = sdp;
      }

      final res = await http
          .post(
        Uri.parse('$REST_URL/api/calls/$action/$sessionId'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode(bodyData),
      )
          .timeout(const Duration(seconds: 5));

      return res.statusCode >= 200 && res.statusCode < 300;
    } catch (e) {
      debugPrint('[CallKit] POST $action error:$e');
      return false;
    }
  }

  /// Waits for MaterialApp to build (needed on cold start from a killed state).
  static Future<NavigatorState?> _waitForNavigator() async {
    for (var i = 0; i < 50; i++) {
      final nav = navigatorKey.currentState;
      if (nav != null) return nav;
      await Future.delayed(const Duration(milliseconds: 100));
    }
    debugPrint('[CallKit] Navigator not ready after 5s.');
    return null;
  }

  static Future<void> _handleCallAccept(Map<String, dynamic> extra) async {
    final normalizedExtra = _normalizeOfferPayload(extra);
    final sessionId = _sessionIdOf(normalizedExtra);

    debugPrint('[CallKit] accept extra keys: ${normalizedExtra.keys.toList()}');
    debugPrint('[CallKit] navigator ready: ${navigatorKey.currentState != null}, '
        'signaling set: ${_signalingService != null}');

    // Guard against duplicate accept events
    if (sessionId.isNotEmpty) {
      if (_acceptedSessions.contains(sessionId)) {
        debugPrint('[CallKit] Session $sessionId already accepted. Skipping.');
        return;
      }
      _acceptedSessions.add(sessionId);
    }

    final conversationId = normalizedExtra['conversationId']?.toString() ?? '';
    final fromUserId = _callerIdOf(normalizedExtra);
    final callerName = _callerNameOf(normalizedExtra);
    final isVideo = _isVideoCall(normalizedExtra);
    final isGroup = _isGroupCall(normalizedExtra);

    // 1. Tell the server right away so the caller stops ringing
    unawaited(postCallAction('accept', sessionId));

    // 2. Stop ringtone & dismiss the CallKit UI silently
    await CallRingtoneService.stop();
    await _endCallKitUiSilently();

    // 3. Resolve local user
    final prefs = await SharedPreferences.getInstance();
    final localUserId = prefs.getString(_kUserId) ??
        normalizedExtra['localUserId']?.toString() ??
        '';

    // 4. Navigate / Show Call Overlay
    final nav = await _waitForNavigator();
    if (nav == null) return;

    if (isGroup) {
      final groupName = normalizedExtra['groupName']?.toString() ??
          normalizedExtra['chatName']?.toString() ??
          'Group Call';

      nav.push(
        MaterialPageRoute(
          builder: (_) => GroupCallScreen(
            conversationId: conversationId,
            groupName: groupName,
            isVideo: isVideo,
            localUserId: localUserId,
            callerUserId: fromUserId,
            callerUsername: callerName,
          ),
        ),
      );
      return;
    }

    var signaling = _signalingService;
    if (signaling == null) {
      debugPrint('[CallKit] Signaling service null; creating fallback instance.');
      signaling = CallSignalingService(
        stomp: StompService(),
        localUserId: localUserId,
      );
      _signalingService = signaling;
    }

    // រង់ចាំ 1 frame ដើម្បីឱ្យ Overlay របស់ Navigator រួចរាល់ (សំខាន់ពេល Cold Start)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      CallOverlayController.showCall(
        remoteUserId: fromUserId,
        remoteName: callerName,
        conversationId: conversationId,
        isVideo: isVideo,
        incomingOffer: normalizedExtra,
        signalingService: signaling!,
      );
    });
  }

  static Future<void> _handleCallDecline(Map<String, dynamic> extra) async {
    final normalizedExtra = _normalizeOfferPayload(extra);
    final sessionId = _sessionIdOf(normalizedExtra);

    await CallRingtoneService.stop();
    await _endCallKitUiSilently();

    if (_isGroupCall(normalizedExtra)) {
      try {
        final prefs = await SharedPreferences.getInstance();
        final localUserId = prefs.getString(_kUserId) ??
            normalizedExtra['localUserId']?.toString() ??
            '';
        final localUsername = prefs.getString(_kUsername) ??
            normalizedExtra['localUsername']?.toString() ??
            '';
        final callerId = _callerIdOf(normalizedExtra);
        if (callerId.isNotEmpty) {
          StompService().sendSignal(callerId, {
            'type': 'DECLINE_CALL',
            'fromUserId': localUserId,
            'conversationId': normalizedExtra['conversationId']?.toString() ?? '',
            'isGroup': true,
            'declinedUsername':
            localUsername.isNotEmpty ? localUsername : localUserId,
          });
        }
      } catch (e) {
        debugPrint('[CallKit] group decline signal failed: $e');
      }
      return;
    }

    final ok = await postCallAction('reject', sessionId);
    if (!ok && _signalingService != null) {
      _signalingService!.rejectCall(normalizedExtra);
    }
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Cold start
  // ───────────────────────────────────────────────────────────────────────────

  /// Check active accepted call on cold launch
  static Future<void> checkActiveCallsOnLaunch(
      CallSignalingService signalingService) async {
    _signalingService = signalingService;

    final dynamic activeCalls = await FlutterCallkitIncoming.activeCalls();
    if (activeCalls is List && activeCalls.isNotEmpty) {
      final call = _deepNormalizeMap(activeCalls.first);
      final extra = call['extra'] is Map
          ? _deepNormalizeMap(call['extra'])
          : <String, dynamic>{};
      final isAccepted = call['isAccepted'] == true || call['accepted'] == true;

      if (isAccepted && extra.isNotEmpty) {
        debugPrint('[CallKit ColdStart] Active accepted call found: $extra');
        await _handleCallAccept(extra);
      }
    }
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Permissions & tokens
  // ───────────────────────────────────────────────────────────────────────────

  /// Request Notification and Full Intent permissions for Android 13+ / 14
  static Future<void> requestPermissions() async {
    try {
      await FlutterCallkitIncoming.requestNotificationPermission({
        "title": "Notification permission",
        "messageText":
        "Love In Chat needs notification permission for incoming calls.",
        "textAccept": "Allow",
        "textDecline": "Deny"
      });
      await FlutterCallkitIncoming.requestFullIntentPermission();
    } catch (e) {
      debugPrint('[CallKit Permissions] Request error: $e');
    }
  }

  /// Fetch iOS VoIP token
  static Future<String?> getVoipToken() async {
    try {
      return await FlutterCallkitIncoming.getDevicePushTokenVoIP();
    } catch (e) {
      debugPrint('[CallKit VoIP Token] Error: $e');
      return null;
    }
  }

  /// Fetch FCM Push Token
  static Future<String?> getFcmToken() async {
    try {
      return await FirebaseMessaging.instance.getToken();
    } catch (e) {
      debugPrint('[FCM Token] Error: $e');
      return null;
    }
  }
}