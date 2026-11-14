import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:stomp_dart_client/stomp_frame.dart';

import 'StompService.dart';

// ── Signal types ──────────────────────────────────────────────────────────────
enum SignalType {
  callOffer,
  callAnswer,
  iceCandidate,
  callReject,
  callCancel,
  callHangup,
  callBusy,
}

extension SignalTypeExt on SignalType {
  String get wire {
    switch (this) {
      case SignalType.callOffer:     return 'CALL_OFFER';
      case SignalType.callAnswer:    return 'CALL_ANSWER';
      case SignalType.iceCandidate:  return 'ICE_CANDIDATE';
      case SignalType.callReject:    return 'CALL_REJECT';
      case SignalType.callCancel:    return 'CALL_CANCEL';
      case SignalType.callHangup:    return 'CALL_HANGUP';
      case SignalType.callBusy:      return 'CALL_BUSY';
    }
  }
}

SignalType? _parseSignalType(String? raw) {
  switch (raw) {
    case 'CALL_OFFER':     return SignalType.callOffer;
    case 'CALL_ANSWER':    return SignalType.callAnswer;
    case 'ICE_CANDIDATE':  return SignalType.iceCandidate;
    case 'CALL_REJECT':    return SignalType.callReject;
    case 'CALL_CANCEL':    return SignalType.callCancel;
    case 'CALL_HANGUP':    return SignalType.callHangup;
    case 'CALL_BUSY':      return SignalType.callBusy;
    default:               return null;
  }
}

// ── STUN/TURN configuration ───────────────────────────────────────────────────
const _iceServers = {
  'iceServers': [
    // Google's public STUN server — suitable for most networks.
    // Add a TURN server here if you need relay for symmetric NAT:
    // { 'urls': 'turn:your.turn.server', 'username': '...', 'credential': '...' }
    {'urls': 'stun:stun.l.google.com:19302'},
    {'urls': 'stun:stun1.l.google.com:19302'},
  ]
};

const _offerSdpConstraints = {
  'mandatory': {
    'OfferToReceiveAudio': true,
    'OfferToReceiveVideo': true,
  },
  'optional': [],
};

/// Manages a single WebRTC peer connection and its STOMP signaling channel.
///
/// Usage
/// -----
///  1. Call [listenForIncoming] once when the app starts (or when the user
///     logs in) to subscribe to the STOMP `/user/queue/signal` destination.
///  2. When the user initiates a call: [startCall].
///  3. When the user answers an incoming call: [answerCall].
///  4. To end: [hangup].
///
/// The service fires the callbacks set on it so the UI layer can react without
/// coupling to WebRTC internals.
class CallSignalingService {
  final StompService _stomp;
  final String localUserId;

  CallSignalingService({required StompService stomp, required this.localUserId})
      : _stomp = stomp;

  // ── State ─────────────────────────────────────────────────────────────────
  RTCPeerConnection? _pc;
  MediaStream? _localStream;
  String? _remoteUserId;
  String? _conversationId;
  bool _isOffer = false; // true = we are the caller

  final List<RTCIceCandidate> _pendingCandidates = [];

  // ── Public streams ────────────────────────────────────────────────────────
  /// Fires when a remote track is added (video/audio stream ready to render).
  final StreamController<MediaStream> onRemoteStream =
      StreamController.broadcast();

  /// Fires when the local stream is ready (to show self-preview).
  final StreamController<MediaStream> onLocalStream =
      StreamController.broadcast();

  /// Fires when an incoming call arrives with:
  ///   { fromUserId, conversationId, callType, sdp }
  final StreamController<Map<String, dynamic>> onIncomingCall =
      StreamController.broadcast();

  /// Fires when the remote peer hangs up, rejects, or cancels.
  final StreamController<SignalType> onCallEnded =
      StreamController.broadcast();

  // ── STOMP subscription ────────────────────────────────────────────────────

  /// Subscribe to the signal queue. Call this once after STOMP connects.
  void listenForIncoming() {
    _stomp.subscribeToSignaling(_onSignalFrame);
  }

  void _onSignalFrame(StompFrame frame) {
    if (frame.body == null) return;
    Map<String, dynamic> msg;
    try {
      msg = json.decode(frame.body!) as Map<String, dynamic>;
    } catch (_) {
      return;
    }

    final type = _parseSignalType(msg['type']?.toString());
    if (type == null) return;
    debugPrint('[Signaling] received $type from ${msg['fromUserId']}');

    switch (type) {
      case SignalType.callOffer:
        onIncomingCall.add(msg);
        break;
      case SignalType.callAnswer:
        _handleAnswer(msg);
        break;
      case SignalType.iceCandidate:
        _handleRemoteCandidate(msg);
        break;
      case SignalType.callReject:
      case SignalType.callCancel:
      case SignalType.callHangup:
      case SignalType.callBusy:
        _teardown();
        onCallEnded.add(type);
        break;
    }
  }

  // ── Outbound signaling helpers ────────────────────────────────────────────

  void _send(String targetUserId, Map<String, dynamic> payload) {
    _stomp.sendSignal(targetUserId, payload);
  }

  // ── Start a call (caller side) ────────────────────────────────────────────

  /// Initiates an outgoing call to [remoteUserId].
  ///
  /// [video] = false → audio-only call.
  Future<void> startCall({
    required String remoteUserId,
    required String conversationId,
    bool video = false,
  }) async {
    _remoteUserId = remoteUserId;
    _conversationId = conversationId;
    _isOffer = true;

    _localStream = await _getUserMedia(video: video);
    onLocalStream.add(_localStream!);

    await _createPeerConnection();
    _localStream!.getTracks().forEach((t) => _pc!.addTrack(t, _localStream!));

    final offer = await _pc!.createOffer(_offerSdpConstraints);
    await _pc!.setLocalDescription(offer);

    _send(remoteUserId, {
      'type': SignalType.callOffer.wire,
      'conversationId': conversationId,
      'callType': video ? 'VIDEO' : 'AUDIO',
      'sdp': offer.toMap(),
    });
  }

  // ── Answer an incoming call (callee side) ─────────────────────────────────

  /// Call this after the user accepts an incoming offer.
  ///
  /// [offerMsg] is the map delivered via [onIncomingCall].
  Future<void> answerCall({
    required Map<String, dynamic> offerMsg,
    bool video = false,
  }) async {
    _remoteUserId = offerMsg['fromUserId']?.toString();
    _conversationId = offerMsg['conversationId']?.toString();
    _isOffer = false;

    _localStream = await _getUserMedia(video: video);
    onLocalStream.add(_localStream!);

    await _createPeerConnection();
    _localStream!.getTracks().forEach((t) => _pc!.addTrack(t, _localStream!));

    final sdpMap = offerMsg['sdp'] as Map<String, dynamic>?;
    if (sdpMap != null) {
      final offer = RTCSessionDescription(
          sdpMap['sdp']?.toString(), sdpMap['type']?.toString());
      await _pc!.setRemoteDescription(offer);
    }

    // Flush buffered ICE candidates that arrived before the remote description.
    for (final c in _pendingCandidates) {
      await _pc!.addCandidate(c);
    }
    _pendingCandidates.clear();

    final answer = await _pc!.createAnswer(_offerSdpConstraints);
    await _pc!.setLocalDescription(answer);

    _send(_remoteUserId!, {
      'type': SignalType.callAnswer.wire,
      'conversationId': _conversationId,
      'sdp': answer.toMap(),
    });
  }

  /// Reject an incoming call (before answering).
  void rejectCall(Map<String, dynamic> offerMsg) {
    final from = offerMsg['fromUserId']?.toString();
    if (from == null) return;
    _send(from, {
      'type': SignalType.callReject.wire,
      'conversationId': offerMsg['conversationId'],
    });
  }

  // ── Hang up ───────────────────────────────────────────────────────────────

  /// End the call (either side).
  Future<void> hangup() async {
    if (_remoteUserId != null) {
      _send(_remoteUserId!, {
        'type': _isOffer
            ? SignalType.callCancel.wire   // caller cancels before answer
            : SignalType.callHangup.wire,  // either side ends active call
        'conversationId': _conversationId,
      });
    }
    await _teardown();
  }

  // ── Peer connection lifecycle ─────────────────────────────────────────────

  Future<void> _createPeerConnection() async {
    _pc = await createPeerConnection(_iceServers);

    _pc!.onIceCandidate = (candidate) {
      if (_remoteUserId == null) return;
      _send(_remoteUserId!, {
        'type': SignalType.iceCandidate.wire,
        'conversationId': _conversationId,
        'candidate': candidate.toMap(),
      });
    };

    _pc!.onTrack = (event) {
      if (event.streams.isNotEmpty) {
        onRemoteStream.add(event.streams.first);
      }
    };

    _pc!.onConnectionState = (state) {
      debugPrint('[WebRTC] connection state: $state');
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
          state == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected) {
        onCallEnded.add(SignalType.callHangup);
        _teardown();
      }
    };
  }

  void _handleAnswer(Map<String, dynamic> msg) async {
    final sdpMap = msg['sdp'] as Map<String, dynamic>?;
    if (sdpMap == null || _pc == null) return;
    final answer = RTCSessionDescription(
        sdpMap['sdp']?.toString(), sdpMap['type']?.toString());
    await _pc!.setRemoteDescription(answer);

    for (final c in _pendingCandidates) {
      await _pc!.addCandidate(c);
    }
    _pendingCandidates.clear();
  }

  void _handleRemoteCandidate(Map<String, dynamic> msg) async {
    final c = msg['candidate'] as Map<String, dynamic>?;
    if (c == null) return;
    final candidate = RTCIceCandidate(
      c['candidate']?.toString() ?? '',
      c['sdpMid']?.toString(),
      c['sdpMLineIndex'] is int ? c['sdpMLineIndex'] as int : 0,
    );
    if (_pc?.signalingState != null) {
      try {
        await _pc!.addCandidate(candidate);
      } catch (_) {
        _pendingCandidates.add(candidate);
      }
    } else {
      _pendingCandidates.add(candidate);
    }
  }

  Future<MediaStream> _getUserMedia({required bool video}) async {
    final constraints = {
      'audio': true,
      'video': video
          ? {
              'facingMode': 'user',
              'width': {'ideal': 1280},
              'height': {'ideal': 720},
            }
          : false,
    };
    return await navigator.mediaDevices.getUserMedia(constraints);
  }

  Future<void> _teardown() async {
    _pendingCandidates.clear();
    _localStream?.getTracks().forEach((t) => t.stop());
    _localStream?.dispose();
    _localStream = null;
    await _pc?.close();
    _pc = null;
    _remoteUserId = null;
    _conversationId = null;
  }

  // ── Speaker / mute toggles ────────────────────────────────────────────────

  void toggleMute(bool muted) {
    _localStream?.getAudioTracks().forEach((t) => t.enabled = !muted);
  }

  void toggleCamera(bool cameraOff) {
    _localStream?.getVideoTracks().forEach((t) => t.enabled = !cameraOff);
  }

  /// Switch between front and back camera (mobile only).
  Future<void> switchCamera() async {
    final tracks = _localStream?.getVideoTracks() ?? [];
    if (tracks.isEmpty) return;
    await Helper.switchCamera(tracks.first);
  }

  void dispose() {
    _teardown();
    onRemoteStream.close();
    onLocalStream.close();
    onIncomingCall.close();
    onCallEnded.close();
  }
}
