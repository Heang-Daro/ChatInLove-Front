import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:stomp_dart_client/stomp_frame.dart';

import 'StompService.dart';

const _iceServers = {
  'iceServers': [
    {'urls': 'stun:stun.l.google.com:19302'},
    {'urls': 'stun:stun1.l.google.com:19302'},
  ],
};

const _offerConstraints = {
  'mandatory': {'OfferToReceiveAudio': true, 'OfferToReceiveVideo': true},
  'optional': [],
};

const _videoConstraints = {
  'facingMode': 'user',
  'width': {'ideal': 640},
  'height': {'ideal': 480},
};

/// One active participant in the group call.
/// Only members who have explicitly joined are tracked here.
class GroupParticipant {
  final String userId;
  final String username;
  RTCPeerConnection? pc;
  MediaStream? remoteStream;
  final RTCVideoRenderer renderer;
  bool connected;

  /// True while the remote person is actually sending camera video
  /// (updated by offer/join payloads and VIDEO_STATE messages).
  bool videoOn = false;

  /// Local tracks have already been added to [pc] (first negotiation done).
  bool tracksAdded = false;

  GroupParticipant({required this.userId, required this.username})
      : renderer = RTCVideoRenderer(),
        connected = false;

  Future<void> init() => renderer.initialize();

  Future<void> dispose() async {
    await pc?.close();
    remoteStream?.dispose();
    renderer.dispose();
  }
}

/// Mesh-topology group call signaling with explicit join flow.
class GroupCallSignalingService {
  final StompService stomp;
  final String localUserId;
  final String conversationId;

  bool video;
  final List<String> memberUserIds;

  GroupCallSignalingService({
    required this.stomp,
    required this.localUserId,
    required this.conversationId,
    required this.video,
    this.memberUserIds = const [],
  });

  // ── State ──────────────────────────────────────────────────────────────────
  MediaStream? _localStream;

  /// Only participants who have JOINED the call.
  final Map<String, GroupParticipant> _activeParticipants = {};

  final Map<String, List<RTCIceCandidate>> _pendingCandidates = {};

  String? _callerId; // who started the call

  // ── Public streams ─────────────────────────────────────────────────────────
  final StreamController<void> onParticipantsChanged =
  StreamController.broadcast();

  final StreamController<MediaStream> onLocalStream =
  StreamController.broadcast();

  final StreamController<String> onParticipantDeclined =
  StreamController.broadcast();

  List<GroupParticipant> get participants =>
      List.unmodifiable(_activeParticipants.values);

  MediaStream? get localStream => _localStream;

  bool get hasLocalVideo => _localStream?.getVideoTracks().isNotEmpty ?? false;

  bool get _cameraOn =>
      _localStream?.getVideoTracks().any((t) => t.enabled) ?? false;

  // ── Caller: start the call ─────────────────────────────────────────────────
  Future<void> startCall() async {
    _callerId = localUserId;
    _localStream = await _getUserMedia();
    onLocalStream.add(_localStream!);

    stomp.subscribeToSignaling(_onPrivateFrame);
    stomp.subscribeToGroupCallTopic(conversationId, _onGroupFrame);

    final groupPayload = {
      'type': 'GROUP_CALL_STARTED',
      'callSessionId': conversationId,
      'conversationId': conversationId,
      'callType': video ? 'VIDEO' : 'AUDIO',
      'callerUserId': localUserId,
      'fromUserId': localUserId,
      'isGroup': true,
    };

    stomp.sendGroupSignal(conversationId, groupPayload);

    for (final mId in memberUserIds) {
      if (mId.isNotEmpty && mId != localUserId) {
        stomp.sendSignal(mId, groupPayload);
      }
    }

    debugPrint('[GroupCall] GROUP_CALL_STARTED broadcast sent for $conversationId');
  }

  // ── Callee: join an existing call ──────────────────────────────────────────
  Future<void> joinExistingCall({
    required String callerUserId,
    required String callerUsername,
  }) async {
    _callerId = callerUserId;
    _localStream ??= await _getUserMedia();
    onLocalStream.add(_localStream!);

    stomp.subscribeToSignaling(_onPrivateFrame);

    stomp.sendSignal(callerUserId, {
      'type': 'JOIN_CALL',
      'fromUserId': localUserId,
      'conversationId': conversationId,
      'callType': video ? 'VIDEO' : 'AUDIO',
      'videoOn': _cameraOn,
      'isGroup': true,
      'joinerUsername': _usernameOf(localUserId),
    });
    debugPrint('[GroupCall] JOIN_CALL sent to caller $callerUserId');
  }

  // ── Mid-call: upgrade voice → video ────────────────────────────────────────
  Future<void> enableVideo() async {
    if (hasLocalVideo) {
      toggleCamera(false);
      return;
    }

    final cam = await navigator.mediaDevices.getUserMedia({
      'audio': false,
      'video': _videoConstraints,
    });
    final track = cam.getVideoTracks().first;

    _localStream ??= await navigator.mediaDevices
        .getUserMedia({'audio': true, 'video': false});
    await _localStream!.addTrack(track);
    video = true;

    for (final p in _activeParticipants.values) {
      final pc = p.pc;
      if (pc == null) continue;
      try {
        await pc.addTrack(track, _localStream!);
        await _renegotiate(p);
      } catch (e) {
        debugPrint('[GroupCall] renegotiate with ${p.userId} failed: $e');
      }
    }

    _sendVideoState(true);
    onLocalStream.add(_localStream!);
  }

  Future<void> _renegotiate(GroupParticipant p) async {
    final pc = p.pc;
    if (pc == null) return;
    final offer = await pc.createOffer(_offerConstraints);
    await pc.setLocalDescription(offer);
    stomp.sendSignal(p.userId, {
      'type': 'CALL_OFFER',
      'fromUserId': localUserId,
      'conversationId': conversationId,
      'callType': video ? 'VIDEO' : 'AUDIO',
      'videoOn': _cameraOn,
      'sdp': offer.toMap(),
      'isGroup': true,
    });
  }

  void _sendVideoState(bool on) {
    for (final p in _activeParticipants.values) {
      stomp.sendSignal(p.userId, {
        'type': 'VIDEO_STATE',
        'fromUserId': localUserId,
        'conversationId': conversationId,
        'videoOn': on,
        'isGroup': true,
      });
    }
  }

  // ── Leave ──────────────────────────────────────────────────────────────────
  Future<void> leave() async {
    for (final p in _activeParticipants.values) {
      stomp.sendSignal(p.userId, {
        'type': 'LEAVE_CALL',
        'fromUserId': localUserId,
        'conversationId': conversationId,
        'isGroup': true,
      });
    }
    stomp.sendGroupSignal(conversationId, {
      'type': 'LEAVE_CALL',
      'fromUserId': localUserId,
      'conversationId': conversationId,
      'callerUserId': localUserId,
      'isGroup': true,
    });
    await _teardown();
  }

  // ── Signal frame routing ───────────────────────────────────────────────────
  void _onPrivateFrame(StompFrame frame) {
    if (frame.body == null) return;
    Map<String, dynamic> msg;
    try {
      msg = json.decode(frame.body!) as Map<String, dynamic>;
    } catch (_) {
      return;
    }

    if (msg['conversationId'] != conversationId) return;
    final type = msg['type']?.toString();
    final from = msg['fromUserId']?.toString() ?? '';

    switch (type) {
      case 'JOIN_CALL':
        if (localUserId == _callerId) {
          _handleJoin(from, msg);
        }
        break;
      case 'CALL_OFFER':
        if (msg['isGroup'] == true) _handleOffer(from, msg);
        break;
      case 'CALL_ANSWER':
        if (msg['isGroup'] == true) _handleAnswer(from, msg);
        break;
      case 'ICE_CANDIDATE':
        if (msg['isGroup'] == true) _handleIce(from, msg);
        break;
      case 'VIDEO_STATE':
        _handleVideoState(from, msg);
        break;
      case 'CALL_HANGUP':
      case 'LEAVE_CALL':
        _removeParticipant(from);
        break;
      case 'DECLINE_CALL':
        _handleDecline(from, msg);
        break;
    }
  }

  void _onGroupFrame(StompFrame frame) {
    if (frame.body == null) return;
    Map<String, dynamic> msg;
    try {
      msg = json.decode(frame.body!) as Map<String, dynamic>;
    } catch (_) {
      return;
    }

    final type = msg['type']?.toString();
    final from = msg['fromUserId']?.toString() ?? '';
    if (from == localUserId) return;

    if (type == 'LEAVE_CALL') {
      _removeParticipant(from);
    }
  }

  // ── Peer connection lifecycle ──────────────────────────────────────────────
  void _handleJoin(String from, Map<String, dynamic> msg) async {
    final username = msg['joinerUsername']?.toString() ?? from;
    debugPrint('[GroupCall] $from ($username) joined — creating offer');

    final p = await _getOrCreateParticipant(from, username);
    if (msg['videoOn'] is bool) p.videoOn = msg['videoOn'] as bool;

    if (!p.tracksAdded) {
      for (final t in _localStream!.getTracks()) {
        await p.pc!.addTrack(t, _localStream!);
      }
      p.tracksAdded = true;
    }

    await _renegotiate(p);
    onParticipantsChanged.add(null);
  }

  void _handleOffer(String from, Map<String, dynamic> msg) async {
    debugPrint('[GroupCall] received CALL_OFFER from $from');
    final username = msg['senderUsername']?.toString() ?? from;
    final p = await _getOrCreateParticipant(from, username);
    final pc = p.pc!;
    if (msg['videoOn'] is bool) p.videoOn = msg['videoOn'] as bool;

    if (pc.signalingState ==
        RTCSignalingState.RTCSignalingStateHaveLocalOffer) {
      final polite = localUserId != _callerId;
      if (!polite) {
        debugPrint('[GroupCall] offer collision with $from — ignoring');
        return;
      }
      await pc.setLocalDescription(RTCSessionDescription('', 'rollback'));
    }

    if (!p.tracksAdded) {
      for (final t in _localStream!.getTracks()) {
        await pc.addTrack(t, _localStream!);
      }
      p.tracksAdded = true;
    }

    final sdpMap = msg['sdp'] as Map<String, dynamic>?;
    if (sdpMap != null) {
      await pc.setRemoteDescription(RTCSessionDescription(
        sdpMap['sdp']?.toString(),
        sdpMap['type']?.toString(),
      ));
    }

    for (final c in _pendingCandidates[from] ?? []) {
      await pc.addCandidate(c);
    }
    _pendingCandidates[from] = [];

    final answer = await pc.createAnswer(_offerConstraints);
    await pc.setLocalDescription(answer);

    stomp.sendSignal(from, {
      'type': 'CALL_ANSWER',
      'fromUserId': localUserId,
      'conversationId': conversationId,
      'sdp': answer.toMap(),
      'isGroup': true,
    });
    onParticipantsChanged.add(null);
  }

  void _handleAnswer(String from, Map<String, dynamic> msg) async {
    final p = _activeParticipants[from];
    if (p == null || p.pc == null) return; // Null-safety check added
    final sdpMap = msg['sdp'] as Map<String, dynamic>?;
    if (sdpMap == null) return;

    try {
      await p.pc!.setRemoteDescription(RTCSessionDescription(
        sdpMap['sdp']?.toString(),
        sdpMap['type']?.toString(),
      ));
      for (final c in _pendingCandidates[from] ?? []) {
        await p.pc!.addCandidate(c);
      }
      _pendingCandidates[from] = [];
    } catch (e) {
      debugPrint('[GroupCall] _handleAnswer error with $from: $e');
    }
  }

  void _handleIce(String from, Map<String, dynamic> msg) async {
    final c = msg['candidate'] as Map<String, dynamic>?;
    if (c == null) return;
    final candidate = RTCIceCandidate(
      c['candidate']?.toString() ?? '',
      c['sdpMid']?.toString(),
      c['sdpMLineIndex'] is int ? c['sdpMLineIndex'] as int : 0,
    );
    final p = _activeParticipants[from];
    if (p?.pc == null) {
      _pendingCandidates.putIfAbsent(from, () => []).add(candidate);
      return;
    }
    try {
      await p!.pc!.addCandidate(candidate);
    } catch (_) {
      _pendingCandidates.putIfAbsent(from, () => []).add(candidate);
    }
  }

  void _handleVideoState(String from, Map<String, dynamic> msg) {
    final p = _activeParticipants[from];
    if (p == null) return;
    p.videoOn = msg['videoOn'] == true;
    onParticipantsChanged.add(null);
  }

  Future<GroupParticipant> _getOrCreateParticipant(
      String userId, String username) async {
    var p = _activeParticipants[userId];
    if (p == null) {
      p = GroupParticipant(userId: userId, username: username);
      await p.init();
      _activeParticipants[userId] = p;
      _pendingCandidates[userId] = [];
    }
    if (p.pc == null) await _createPeerConnection(p);
    return p;
  }

  Future<void> _createPeerConnection(GroupParticipant p) async {
    final pc = await createPeerConnection(_iceServers);
    p.pc = pc;

    pc.onIceCandidate = (c) {
      if (c.candidate == null || c.candidate!.isEmpty) return; // Candidate check added
      stomp.sendSignal(p.userId, {
        'type': 'ICE_CANDIDATE',
        'fromUserId': localUserId,
        'conversationId': conversationId,
        'isGroup': true,
        'candidate': c.toMap(),
      });
    };

    pc.onTrack = (event) {
      if (event.streams.isNotEmpty) {
        final stream = event.streams.first;
        p.remoteStream = stream;

        if (event.track.kind == 'video' &&
            p.renderer.srcObject?.id == stream.id) {
          p.renderer.srcObject = null;
        }
        p.renderer.srcObject = stream;

        p.connected = true;
        onParticipantsChanged.add(null);
      }
    };

    pc.onConnectionState = (state) {
      debugPrint('[GroupCall] ${p.userId} connection state: $state');
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected ||
          state == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
        _removeParticipant(p.userId);
      }
    };
  }

  void _removeParticipant(String userId) {
    final p = _activeParticipants.remove(userId);
    _pendingCandidates.remove(userId);
    p?.dispose();
    onParticipantsChanged.add(null);
    debugPrint('[GroupCall] $userId left/disconnected');
  }

  void _handleDecline(String from, Map<String, dynamic> msg) {
    final name = msg['declinedUsername']?.toString() ?? from;
    _removeParticipant(from);
    if (!onParticipantDeclined.isClosed) onParticipantDeclined.add(name);
    debugPrint('[GroupCall] $from ($name) declined the call');
  }

  // ── Helpers ────────────────────────────────────────────────────────────────
  Future<MediaStream> _getUserMedia() async {
    return navigator.mediaDevices.getUserMedia({
      'audio': true,
      'video': video ? _videoConstraints : false,
    });
  }

  String _usernameOf(String userId) => userId;

  void toggleMute(bool muted) =>
      _localStream?.getAudioTracks().forEach((t) => t.enabled = !muted);

  void toggleCamera(bool off) {
    final tracks = _localStream?.getVideoTracks() ?? [];
    if (tracks.isEmpty) return;
    for (final t in tracks) {
      t.enabled = !off;
    }
    _sendVideoState(!off);
  }

  Future<void> switchCamera() async {
    final tracks = _localStream?.getVideoTracks() ?? [];
    if (tracks.isEmpty) return;
    await Helper.switchCamera(tracks.first);
  }

  Future<void> _teardown() async {
    stomp.unsubscribeFromSignaling(_onPrivateFrame);
    for (final p in _activeParticipants.values) {
      await p.dispose();
    }
    _activeParticipants.clear();
    _pendingCandidates.clear();
    _localStream?.getTracks().forEach((t) => t.stop());
    _localStream?.dispose();
    _localStream = null;
    if (!onParticipantsChanged.isClosed) onParticipantsChanged.close();
    if (!onLocalStream.isClosed) onLocalStream.close();
    if (!onParticipantDeclined.isClosed) onParticipantDeclined.close();
  }
}