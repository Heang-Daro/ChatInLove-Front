import 'dart:async';
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
import '../screen/CallScreen.dart';
import '../screen/IncomingGroupCallScreen.dart';
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

  // ── SharedPreferences keys: adjust to match your app ──────────────────────
  static const _kAccessToken = 'access_token';
  static const _kUserId = 'user_id';
  static const _kUsername = 'username';

  static void setSignalingService(CallSignalingService service) {
    _signalingService = service;
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Show / end
  // ───────────────────────────────────────────────────────────────────────────

  /// Displays the native CallKit incoming call UI (foreground, background, killed)
  static Future<void> showIncomingCall(Map<String, dynamic> data) async {
    final callId = data['callId']?.toString() ??
        data['callSessionId']?.toString() ??
        data['conversationId']?.toString() ??
        const Uuid().v4();

    // In-isolate dedupe
    if (_handledCallIds.contains(callId)) {
      debugPrint('[CallKit] Call ID $callId already handled. Skipping.');
      return;
    }

    // Cross-isolate dedupe: ask the native side (FCM background handler runs
    // in a different isolate, so the Set above is not shared with it).
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

    final callerName = data['callerName']?.toString() ??
        data['fromUsername']?.toString() ??
        data['fromUserId']?.toString() ??
        'Incoming Call';

    final isVideo = data['callType']?.toString().toUpperCase() == 'VIDEO' ||
        data['isVideo'] == 'true' ||
        data['isVideo'] == true;

    final params = CallKitParams(
      id: callId,
      nameCaller: callerName,
      appName: 'In Love',
      avatar: data['avatar']?.toString() ?? '',
      handle: callerName,
      type: isVideo ? 1 : 0,
      duration: 30000,
      textAccept: 'Accept',
      textDecline: 'Decline',
      extra: Map<String, dynamic>.from(data),
      android: const AndroidParams(
        isCustomNotification: true,
        isShowLogo: false,
        ringtonePath: 'system_ringtone_default',
        backgroundColor: '#FF4081',
        actionColor: '#4CAF50',
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

  /// Dismisses all active CallKit calls (e.g. when the caller cancels).
  static Future<void> endAllCalls() async {
    _handledCallIds.clear();
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
      // Safety net: some platforms/plugin versions never fire the event.
      Future.delayed(const Duration(seconds: 1), () => _suppressEnded = false);
    }
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Event listeners
  // ───────────────────────────────────────────────────────────────────────────

  /// Initialize CallKit event listeners for Accept, Decline, Timeout, and Ended
  static void initializeEventListeners(CallSignalingService signalingService) {
    _signalingService = signalingService;

    // Avoid registering the listener twice (would double-handle every event).
    _eventSub?.cancel();
    _eventSub = FlutterCallkitIncoming.onEvent.listen((CallEvent? event) async {
      if (event == null) return;
      debugPrint('[CallKit Event] ${event.event}: ${event.body}');

      final body = event.body is Map ? Map<String, dynamic>.from(event.body) : <String, dynamic>{};
      final rawExtra = body['extra'];
      final extra = rawExtra is Map ? Map<String, dynamic>.from(rawExtra) : body;

      switch (event.event) {
        case Event.actionCallAccept:
          await _handleCallAccept(extra);
          break;
        case Event.actionCallDecline:
          await _handleCallDecline(extra);
          break;
        case Event.actionCallTimeout:
        // Callee never answered: treat as a missed call, not a hangup.
          _handledCallIds.clear();
          await CallRingtoneService.stop();
          break;
        case Event.actionCallEnded:
          _handledCallIds.clear();
          if (_suppressEnded) {
            // We ended the CallKit UI ourselves after accept/decline.
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
  static Future<bool> postCallAction(String action, String sessionId) async {
    if (sessionId.isEmpty) return false;
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString(_kAccessToken);
      if (token == null || token.isEmpty) {
        debugPrint('[CallKit] No access token; cannot POST $action.');
        return false;
      }
      final res = await http.post(
        Uri.parse('$REST_URL/api/calls/$action/$sessionId'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      ).timeout(const Duration(seconds: 5));

      final ok = res.statusCode >= 200 && res.statusCode < 300;
      debugPrint('[CallKit] POST $action/$sessionId -> ${res.statusCode}');
      return ok;
    } catch (e) {
      debugPrint('[CallKit] POST $action error: $e');
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
    final sessionId =
        extra['callSessionId']?.toString() ?? extra['callId']?.toString() ?? '';

    // DIAGNOSTIC: if the offer/SDP isn't in this list, answerCall() will fail
    // and CallScreen will close right after opening.
    debugPrint('[CallKit] accept extra keys: ${extra.keys.toList()}');
    debugPrint('[CallKit] navigator ready: ${navigatorKey.currentState != null}, '
        'signaling set: ${_signalingService != null}');

    // Guard against the same accept being delivered twice
    // (live event + checkActiveCallsOnLaunch).
    if (sessionId.isNotEmpty) {
      if (_acceptedSessions.contains(sessionId)) {
        debugPrint('[CallKit] Session $sessionId already accepted. Skipping.');
        return;
      }
      _acceptedSessions.add(sessionId);
    }

    final conversationId = extra['conversationId']?.toString() ?? '';
    final fromUserId =
        extra['fromUserId']?.toString() ?? extra['callerUserId']?.toString() ?? '';
    final callerName =
        extra['callerName']?.toString() ?? extra['fromUsername']?.toString() ?? 'Caller';
    final isVideo = extra['callType']?.toString().toUpperCase() == 'VIDEO' ||
        extra['isVideo'] == 'true' ||
        extra['isVideo'] == true;
    final isGroup = extra['isGroup'] == true ||
        extra['isGroup'] == 'true' ||
        extra['type']?.toString() == 'GROUP_CALL_STARTED';

    // 1. Tell the server right away so the caller stops ringing,
    //    but do NOT block navigation on the network.
    unawaited(postCallAction('accept', sessionId));

    // 2. Stop ringtone & dismiss the CallKit UI (without triggering hangup).
    await CallRingtoneService.stop();
    await _endCallKitUiSilently();

    // 3. Resolve the REAL local user (not the caller).
    final prefs = await SharedPreferences.getInstance();
    final localUserId = prefs.getString(_kUserId) ?? extra['localUserId']?.toString() ?? '';
    final localUsername =
        prefs.getString(_kUsername) ?? extra['localUsername']?.toString() ?? '';

    // 4. Navigate (waiting for the navigator on cold start).
    final nav = await _waitForNavigator();
    if (nav == null) return;

    if (isGroup) {
      final groupName =
          extra['groupName']?.toString() ?? extra['chatName']?.toString() ?? 'Group Call';

      nav.push(
        MaterialPageRoute(
          builder: (_) => IncomingGroupCallScreen(
            conversationId: conversationId,
            groupName: groupName,
            isVideo: isVideo,
            localUserId: localUserId,
            callerUserId: fromUserId,
            callerUsername: callerName,
            localUsername: localUsername,
          ),
        ),
      );
      return;
    }

    var signaling = _signalingService;
    if (signaling == null) {
      debugPrint('[CallKit] Signaling service null; creating fallback instance.');
      // TODO: if your CallSignalingService/StompService needs an explicit
      // connect() (token, URL, subscriptions), do it here before navigating,
      // otherwise the cold-start call will have no signaling channel.
      signaling = CallSignalingService(
        stomp: StompService(),
        localUserId: localUserId,
      );
      _signalingService = signaling;
    }

    nav.push(
      MaterialPageRoute(
        builder: (_) => CallScreen(
          remoteUserId: fromUserId,
          remoteName: callerName,
          conversationId: conversationId,
          isVideo: isVideo,
          incomingOffer: extra,
          signalingService: signaling!,
        ),
      ),
    );
  }

  static Future<void> _handleCallDecline(Map<String, dynamic> extra) async {
    final sessionId =
        extra['callSessionId']?.toString() ?? extra['callId']?.toString() ?? '';

    await CallRingtoneService.stop();
    await _endCallKitUiSilently();

    // One source of truth: REST first; fall back to signaling only if it failed.
    final ok = await postCallAction('reject', sessionId);
    if (!ok && _signalingService != null) {
      _signalingService!.rejectCall(extra);
    }
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Cold start
  // ───────────────────────────────────────────────────────────────────────────

  /// Check active accepted call on cold launch
  static Future<void> checkActiveCallsOnLaunch(CallSignalingService signalingService) async {
    _signalingService = signalingService;

    final dynamic activeCalls = await FlutterCallkitIncoming.activeCalls();
    if (activeCalls is List && activeCalls.isNotEmpty) {
      final call = activeCalls.first;
      final rawExtra = call['extra'];
      final extra = rawExtra is Map ? Map<String, dynamic>.from(rawExtra) : <String, dynamic>{};
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
        "messageText": "Love In Chat needs notification permission for incoming calls.",
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