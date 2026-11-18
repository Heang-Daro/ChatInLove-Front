import 'dart:async' as async;
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:stomp_dart_client/stomp_frame.dart';

import 'StompService.dart';
import 'CallKitService.dart';
import 'CallRingtoneService.dart';

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
      case SignalType.callOffer:
        return 'CALL_OFFER';
      case SignalType.callAnswer:
        return 'CALL_ANSWER';
      case SignalType.iceCandidate:
        return 'ICE_CANDIDATE';
      case SignalType.callReject:
        return 'CALL_REJECT';
      case SignalType.callCancel:
        return 'CALL_CANCEL';
      case SignalType.callHangup:
        return 'CALL_HANGUP';
      case SignalType.callBusy:
        return 'CALL_BUSY';
    }
  }
}

SignalType? _parseSignalType(String? raw) {
  switch (raw) {
    case 'CALL_OFFER':
      return SignalType.callOffer;
    case 'CALL_ANSWER':
      return SignalType.callAnswer;
    case 'ICE_CANDIDATE':
      return SignalType.iceCandidate;
    case 'CALL_REJECT':
      return SignalType.callReject;
    case 'CALL_CANCEL':
      return SignalType.callCancel;
    case 'CALL_HANGUP':
      return SignalType.callHangup;
    case 'CALL_BUSY':
      return SignalType.callBusy;
    default:
      return null;
  }
}

// ── STUN/TURN configuration ───────────────────────────────────────────────────
const _iceServers = {
  'iceServers': [
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

class CallSignalingService {
  final StompService _stomp;
  final String localUserId;

  CallSignalingService({required StompService stomp, required this.localUserId})
      : _stomp = stomp;

  /// Expose STOMP instance properly
  StompService get stomp => _stomp;

  // ── State ─────────────────────────────────────────────────────────────────
  RTCPeerConnection? _pc;
  MediaStream? _localStream;
  MediaStream? _remoteStream;
  String? _remoteUserId;
  String? _conversationId;
  String? _callSessionId;
  bool _isOffer = false;

  MediaStream? get latestLocalStream => _localStream;
  MediaStream? get latestRemoteStream => _remoteStream;

  final List<RTCIceCandidate> _pendingCandidates = [];

  // ── Public streams ────────────────────────────────────────────────────────
  final async.StreamController<MediaStream> onRemoteStream =
  async.StreamController<MediaStream>.broadcast();

  final async.StreamController<MediaStream> onLocalStream =
  async.StreamController<MediaStream>.broadcast();

  final async.StreamController<Map<String, dynamic>> onIncomingCall =
  async.StreamController<Map<String, dynamic>>.broadcast();

  final async.StreamController<SignalType> onCallEnded =
  async.StreamController<SignalType>.broadcast();

  // ── Safe stream emitters ──────────────────────────────────────────────────

  void _emitRemoteStream(MediaStream stream) {
    _remoteStream = stream;
    if (!onRemoteStream.isClosed) {
      onRemoteStream.add(stream);
    }
  }

  void _emitLocalStream(MediaStream stream) {
    _localStream = stream;
    if (!onLocalStream.isClosed) {
      onLocalStream.add(stream);
    }
  }

  void _emitIncomingCall(Map<String, dynamic> msg) {
    if (!onIncomingCall.isClosed) {
      onIncomingCall.add(msg);
    }
  }

  void _emitCallEnded(SignalType type) {
    if (!onCallEnded.isClosed) {
      onCallEnded.add(type);
    }
  }

  // ── STOMP subscription ────────────────────────────────────────────────────

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
    if (type == null) {
      if (msg['type']?.toString() == 'GROUP_CALL_STARTED') {
        final caller = msg['fromUserId'] ?? msg['callerUserId'];
        if (caller != null && caller != localUserId) {
          msg['isGroup'] = true;
          msg['fromUserId'] = caller;
          _emitIncomingCall(msg);
        }
      }
      return;
    }
    debugPrint('[Signaling] received $type from ${msg['fromUserId']}');

    switch (type) {
      case SignalType.callOffer:
        final fromId = (msg['fromUserId'] ?? msg['callerUserId'])?.toString();
        if (fromId != null && fromId.isNotEmpty && fromId != localUserId) {
          // Do NOT clear _pendingCandidates here. Trickle ICE routinely makes
          // candidates arrive before the offer (observed 24 candidates then the
          // offer); wiping them on offer receipt leaves the callee with no
          // remote candidates and the call never connects. Stale candidates
          // from a previous call are already dropped by _teardown().
          _emitIncomingCall(msg);
        }
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
        _emitCallEnded(type);
        CallKitService.endAllCalls();
        break;
    }
  }

  // ── Outbound signaling helpers ────────────────────────────────────────────

  void _send(String targetUserId, Map<String, dynamic> payload) {
    _stomp.sendSignal(targetUserId, payload);
  }

  // ── Start a call (caller side) ────────────────────────────────────────────

  Future<void> startCall({
    required String remoteUserId,
    required String conversationId,
    bool video = false,
  }) async {
    await _teardown();
    _remoteUserId = remoteUserId;
    _conversationId = conversationId;
    _isOffer = true;

    final stream = await _getUserMedia(video: video);
    _emitLocalStream(stream);

    await _createPeerConnection();
    _localStream!.getTracks().forEach((t) => _pc!.addTrack(t, _localStream!));

    final offer = await _pc!.createOffer(_offerSdpConstraints);
    await _pc!.setLocalDescription(offer);

    _send(remoteUserId, {
      'type': SignalType.callOffer.wire,
      'fromUserId': localUserId,
      'conversationId': conversationId,
      'callType': video ? 'VIDEO' : 'AUDIO',
      'sdp': offer.toMap(),
    });
  }

  // ── Answer an incoming call (callee side) ─────────────────────────────────

  Future<void> answerCall({
    required Map<String, dynamic> offerMsg,
    bool video = false,
  }) async {
    final savedCandidates = List<RTCIceCandidate>.from(_pendingCandidates);
    await _teardown();
    _pendingCandidates.addAll(savedCandidates);

    _callSessionId = offerMsg['callSessionId']?.toString();
    _remoteUserId = offerMsg['fromUserId']?.toString();
    _conversationId = offerMsg['conversationId']?.toString();
    _isOffer = false;

    final stream = await _getUserMedia(video: video);
    _emitLocalStream(stream);

    await _createPeerConnection();
    _localStream!.getTracks().forEach((t) => _pc!.addTrack(t, _localStream!));

    final rawSdp = offerMsg['sdp'];
    Map<String, dynamic>? sdpMap;
    if (rawSdp is Map<String, dynamic>) {
      sdpMap = rawSdp;
    } else if (rawSdp is Map) {
      sdpMap = rawSdp.map((k, v) => MapEntry(k.toString(), v));
    } else if (rawSdp is String && rawSdp.isNotEmpty) {
      if (rawSdp.trim().startsWith('{')) {
        sdpMap = jsonDecode(rawSdp) as Map<String, dynamic>;
      } else {
        sdpMap = {
          'type': offerMsg['sdpType']?.toString() ?? 'offer',
          'sdp': rawSdp,
        };
      }
    }

    if (sdpMap != null && sdpMap['sdp'] != null) {
      final offer = RTCSessionDescription(
          sdpMap['sdp']?.toString(), sdpMap['type']?.toString() ?? 'offer');
      await _pc!.setRemoteDescription(offer);
    } else {
      throw StateError('Missing SDP offer in incoming call payload');
    }

    for (final c in _pendingCandidates) {
      try {
        await _pc!.addCandidate(c);
      } catch (e) {
        debugPrint('[Signaling] Error flushing buffered candidate: $e');
      }
    }
    _pendingCandidates.clear();

    final answer = await _pc!.createAnswer(_offerSdpConstraints);
    await _pc!.setLocalDescription(answer);

    if (_remoteUserId != null && _remoteUserId!.isNotEmpty) {
      _send(_remoteUserId!, {
        'type': SignalType.callAnswer.wire,
        'fromUserId': localUserId,
        'conversationId': _conversationId,
        'sdp': answer.toMap(),
      });
    }

    if (_callSessionId != null && _callSessionId!.isNotEmpty) {
      async.unawaited(CallKitService.postCallAction(
        'accept',
        _callSessionId!,
        sdp: answer.toMap(),
      ));
    }
  }

  /// បើកកាមេរ៉ាអំឡុងពេលកំពុង Voice Call (Upgrade Audio -> Video Call)
  Future<void> enableVideo() async {
    if (_pc == null || _localStream == null) return;
    if (_localStream!.getVideoTracks().isNotEmpty) {
      toggleCamera(false);
      return;
    }

    final videoStream = await navigator.mediaDevices.getUserMedia({
      'audio': false,
      'video': {
        'facingMode': 'user',
        'width': {'ideal': 1280},
        'height': {'ideal': 720},
      },
    });

    final videoTrack = videoStream.getVideoTracks().first;
    await _localStream!.addTrack(videoTrack);
    await _pc!.addTrack(videoTrack, _localStream!);
    _emitLocalStream(_localStream!);

    if (_remoteUserId != null && _remoteUserId!.isNotEmpty) {
      final offer = await _pc!.createOffer(_offerSdpConstraints);
      await _pc!.setLocalDescription(offer);
      _send(_remoteUserId!, {
        'type': SignalType.callOffer.wire,
        'fromUserId': localUserId,
        'conversationId': _conversationId,
        'callType': 'VIDEO',
        'sdp': offer.toMap(),
      });
    }
  }

  void rejectCall(Map<String, dynamic> offerMsg) {
    final from = offerMsg['fromUserId']?.toString();
    if (from == null) return;
    _send(from, {
      'type': SignalType.callReject.wire,
      'fromUserId': localUserId,
      'conversationId': offerMsg['conversationId'],
    });
  }

  // ── Hang up ───────────────────────────────────────────────────────────────

  Future<void> hangup() async {
    if (_remoteUserId != null) {
      _send(_remoteUserId!, {
        'type': _isOffer
            ? SignalType.callCancel.wire
            : SignalType.callHangup.wire,
        'fromUserId': localUserId,
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
        'fromUserId': localUserId,
        'conversationId': _conversationId,
        'candidate': candidate.toMap(),
      });
    };

    _pc!.onTrack = (event) {
      if (event.streams.isNotEmpty) {
        _emitRemoteStream(event.streams.first);
      } else if (event.track.kind == 'audio' || event.track.kind == 'video') {
        createLocalMediaStream('remote_${event.track.id}').then((ms) {
          ms.addTrack(event.track);
          _emitRemoteStream(ms);
        });
      }
    };

    _pc!.onConnectionState = (state) {
      debugPrint('[WebRTC] connection state: $state');
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
          state == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected) {
        _emitCallEnded(SignalType.callHangup);
        _teardown();
      }
    };
  }

  void _handleAnswer(Map<String, dynamic> msg) async {
    await CallRingtoneService.stop();
    await CallKitService.endAllCalls();

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
      c['sdpMLineIndex'] is int
          ? c['sdpMLineIndex'] as int
          : int.tryParse(c['sdpMLineIndex']?.toString() ?? '0') ?? 0,
    );

    if (_pc != null && await _pc!.getRemoteDescription() != null) {
      try {
        await _pc!.addCandidate(candidate);
        debugPrint('[Signaling] Successfully added ICE candidate');
      } catch (e) {
        debugPrint('[Signaling] Error adding candidate: $e');
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
    _remoteStream = null;
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

  Future<void> switchCamera() async {
    final tracks = _localStream?.getVideoTracks() ?? [];
    if (tracks.isEmpty) return;
    await Helper.switchCamera(tracks.first);
  }

  void dispose() {
    _teardown();
    if (!onRemoteStream.isClosed) onRemoteStream.close();
    if (!onLocalStream.isClosed) onLocalStream.close();
    if (!onIncomingCall.isClosed) onIncomingCall.close();
    if (!onCallEnded.isClosed) onCallEnded.close();
  }
}