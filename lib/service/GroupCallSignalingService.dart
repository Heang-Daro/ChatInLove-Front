import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:stomp_dart_client/stomp_frame.dart';

import 'StompService.dart';

// Re-use signal type constants from the 1-to-1 service.
const _iceServers = {
  'iceServers': [
    {'urls': 'stun:stun.l.google.com:19302'},
    {'urls': 'stun:stun1.l.google.com:19302'},
  ],
};

const _offerConstraints = {
  'mandatory': {
    'OfferToReceiveAudio': true,
    'OfferToReceiveVideo': true,
  },
  'optional': [],
};

/// Represents one remote participant in the group call.
class GroupParticipant {
  final String userId;
  final String username;
  RTCPeerConnection? pc;
  MediaStream? remoteStream;
  final RTCVideoRenderer renderer;
  bool connected;

  GroupParticipant({
    required this.userId,
    required this.username,
  })  : renderer = RTCVideoRenderer(),
        connected = false;

  Future<void> init() => renderer.initialize();

  Future<void> dispose() async {
    await pc?.close();
    remoteStream?.dispose();
    renderer.dispose();
  }
}

/// Mesh-topology group call signaling service.
///
/// Creates one [RTCPeerConnection] per remote participant and routes all
/// WebRTC signaling through the existing STOMP relay at `/app/signal/{userId}`.
///
/// Usage
/// -----
/// 1. Create the service with the list of remote members.
/// 2. Call [joinCall] — captures local media and sends CALL_OFFER to every member.
/// 3. Listen to [onParticipantsChanged] to rebuild the video grid.
/// 4. Call [leave] when done.
class GroupCallSignalingService {
  final StompService stomp;
  final String localUserId;
  final String conversationId;
  final bool video;

  GroupCallSignalingService({
    required this.stomp,
    required this.localUserId,
    required this.conversationId,
    required this.video,
  });

  // ── State ──────────────────────────────────────────────────────────────────
  MediaStream? _localStream;
  final Map<String, GroupParticipant> _participants = {};

  // ICE candidates that arrived before the remote description was set.
  final Map<String, List<RTCIceCandidate>> _pendingCandidates = {};

  // ── Public ─────────────────────────────────────────────────────────────────
  /// Fires every time the participant list or any stream changes.
  final StreamController<void> onParticipantsChanged =
      StreamController.broadcast();

  /// The local media stream (for self-preview).
  MediaStream? get localStream => _localStream;

  /// Current participants (excludes the local user).
  List<GroupParticipant> get participants => _participants.values.toList();

  // ── Join ───────────────────────────────────────────────────────────────────

  /// Captures local media and sends a CALL_OFFER to every [remoteMembers].
  /// remoteMembers is a list of {userId, username} maps.
  Future<void> joinCall(
      List<Map<String, String>> remoteMembers) async {
    _localStream = await _getUserMedia();

    // Subscribe to incoming signaling messages.
    stomp.subscribeToSignaling(_onFrame);

    for (final m in remoteMembers) {
      final userId   = m['userId']   ?? '';
      final username = m['username'] ?? '';
      if (userId.isEmpty || userId == localUserId) continue;
      await _createParticipant(userId, username, initiator: true);
    }
  }

  /// Call this when the app receives a group CALL_OFFER from someone (callee
  /// path — user was invited, so they create their own peer connection and answer).
  Future<void> handleInvite(Map<String, dynamic> offer) async {
    _localStream ??= await _getUserMedia();
    stomp.subscribeToSignaling(_onFrame);

    final fromId = offer['fromUserId']?.toString() ?? '';
    final username = offer['senderUsername']?.toString() ?? fromId;
    if (fromId.isEmpty) return;

    var p = _participants[fromId];
    if (p == null) {
      p = GroupParticipant(userId: fromId, username: username);
      await p.init();
      _participants[fromId] = p;
      _pendingCandidates[fromId] = [];
    }

    await _createPeerConnection(p);
    _localStream!.getTracks().forEach((t) => p!.pc!.addTrack(t, _localStream!));

    // Apply the offer SDP.
    final sdpMap = offer['sdp'] as Map<String, dynamic>?;
    if (sdpMap != null) {
      await p.pc!.setRemoteDescription(RTCSessionDescription(
        sdpMap['sdp']?.toString(),
        sdpMap['type']?.toString(),
      ));
    }

    // Flush buffered ICE candidates.
    for (final c in _pendingCandidates[fromId] ?? []) {
      await p.pc!.addCandidate(c);
    }
    _pendingCandidates.remove(fromId);

    // Send answer.
    final answer = await p.pc!.createAnswer(_offerConstraints);
    await p.pc!.setLocalDescription(answer);
    _send(fromId, {
      'type': 'CALL_ANSWER',
      'conversationId': conversationId,
      'callType': video ? 'VIDEO' : 'AUDIO',
      'sdp': answer.toMap(),
      'isGroup': true,
    });
    onParticipantsChanged.add(null);
  }

  // ── Leave ──────────────────────────────────────────────────────────────────

  Future<void> leave() async {
    for (final p in _participants.values) {
      _send(p.userId, {
        'type': 'CALL_HANGUP',
        'conversationId': conversationId,
        'isGroup': true,
      });
    }
    await _teardown();
  }

  // ── Peer creation ──────────────────────────────────────────────────────────

  Future<void> _createParticipant(
      String userId, String username, {required bool initiator}) async {
    var p = _participants[userId];
    if (p == null) {
      p = GroupParticipant(userId: userId, username: username);
      await p.init();
      _participants[userId] = p;
      _pendingCandidates[userId] = [];
    }

    await _createPeerConnection(p);
    _localStream!.getTracks().forEach((t) => p!.pc!.addTrack(t, _localStream!));

    if (initiator) {
      final offer = await p.pc!.createOffer(_offerConstraints);
      await p.pc!.setLocalDescription(offer);
      _send(userId, {
        'type': 'CALL_OFFER',
        'conversationId': conversationId,
        'callType': video ? 'VIDEO' : 'AUDIO',
        'sdp': offer.toMap(),
        'isGroup': true,
        'senderUsername': '',  // filled in by SignalingController's fromUserId stamp
      });
    }
    onParticipantsChanged.add(null);
  }

  Future<void> _createPeerConnection(GroupParticipant p) async {
    final pc = await createPeerConnection(_iceServers);
    p.pc = pc;

    pc.onIceCandidate = (c) {
      _send(p.userId, {
        'type': 'ICE_CANDIDATE',
        'conversationId': conversationId,
        'isGroup': true,
        'candidate': c.toMap(),
      });
    };

    pc.onTrack = (event) {
      if (event.streams.isNotEmpty) {
        p.remoteStream = event.streams.first;
        p.renderer.srcObject = event.streams.first;
        p.connected = true;
        onParticipantsChanged.add(null);
      }
    };

    pc.onConnectionState = (state) {
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected ||
          state == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
        _participants.remove(p.userId);
        p.dispose();
        onParticipantsChanged.add(null);
      }
    };
  }

  // ── Signal frame routing ───────────────────────────────────────────────────

  void _onFrame(StompFrame frame) {
    if (frame.body == null) return;
    Map<String, dynamic> msg;
    try {
      msg = json.decode(frame.body!) as Map<String, dynamic>;
    } catch (_) {
      return;
    }

    // Only handle messages that belong to this group call.
    if (msg['conversationId'] != conversationId) return;
    if (msg['isGroup'] != true) return;

    final type = msg['type']?.toString();
    final from = msg['fromUserId']?.toString() ?? '';
    if (from.isEmpty) return;

    switch (type) {
      case 'CALL_OFFER':
        _handleOffer(from, msg);
        break;
      case 'CALL_ANSWER':
        _handleAnswer(from, msg);
        break;
      case 'ICE_CANDIDATE':
        _handleIce(from, msg);
        break;
      case 'CALL_HANGUP':
      case 'CALL_REJECT':
      case 'CALL_CANCEL':
        _removeParticipant(from);
        break;
    }
  }

  void _handleOffer(String from, Map<String, dynamic> msg) async {
    // A new participant joined and sent us an offer.
    final username = msg['senderUsername']?.toString() ?? from;
    var p = _participants[from];
    if (p == null) {
      p = GroupParticipant(userId: from, username: username);
      await p.init();
      _participants[from] = p;
      _pendingCandidates[from] = [];
    }
    if (p.pc == null) {
      _localStream ??= await _getUserMedia();
      await _createPeerConnection(p);
      _localStream!.getTracks().forEach((t) => p!.pc!.addTrack(t, _localStream!));
    }

    final sdpMap = msg['sdp'] as Map<String, dynamic>?;
    if (sdpMap != null) {
      await p.pc!.setRemoteDescription(RTCSessionDescription(
        sdpMap['sdp']?.toString(),
        sdpMap['type']?.toString(),
      ));
    }

    for (final c in _pendingCandidates[from] ?? []) {
      await p.pc!.addCandidate(c);
    }
    _pendingCandidates.remove(from);

    final answer = await p.pc!.createAnswer(_offerConstraints);
    await p.pc!.setLocalDescription(answer);
    _send(from, {
      'type': 'CALL_ANSWER',
      'conversationId': conversationId,
      'isGroup': true,
      'sdp': answer.toMap(),
    });
    onParticipantsChanged.add(null);
  }

  void _handleAnswer(String from, Map<String, dynamic> msg) async {
    final p = _participants[from];
    if (p?.pc == null) return;
    final sdpMap = msg['sdp'] as Map<String, dynamic>?;
    if (sdpMap == null) return;
    await p!.pc!.setRemoteDescription(RTCSessionDescription(
      sdpMap['sdp']?.toString(),
      sdpMap['type']?.toString(),
    ));
    for (final c in _pendingCandidates[from] ?? []) {
      await p.pc!.addCandidate(c);
    }
    _pendingCandidates.remove(from);
  }

  void _handleIce(String from, Map<String, dynamic> msg) async {
    final c = msg['candidate'] as Map<String, dynamic>?;
    if (c == null) return;
    final candidate = RTCIceCandidate(
      c['candidate']?.toString() ?? '',
      c['sdpMid']?.toString(),
      c['sdpMLineIndex'] is int ? c['sdpMLineIndex'] as int : 0,
    );
    final p = _participants[from];
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

  void _removeParticipant(String userId) {
    final p = _participants.remove(userId);
    p?.dispose();
    onParticipantsChanged.add(null);
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  void _send(String targetUserId, Map<String, dynamic> payload) {
    stomp.sendSignal(targetUserId, payload);
  }

  Future<MediaStream> _getUserMedia() async {
    return navigator.mediaDevices.getUserMedia({
      'audio': true,
      'video': video
          ? {'facingMode': 'user', 'width': {'ideal': 640}, 'height': {'ideal': 480}}
          : false,
    });
  }

  // ── Mute / camera ──────────────────────────────────────────────────────────

  void toggleMute(bool muted) =>
      _localStream?.getAudioTracks().forEach((t) => t.enabled = !muted);

  void toggleCamera(bool off) =>
      _localStream?.getVideoTracks().forEach((t) => t.enabled = !off);

  Future<void> switchCamera() async {
    final tracks = _localStream?.getVideoTracks() ?? [];
    if (tracks.isEmpty) return;
    await Helper.switchCamera(tracks.first);
  }

  Future<void> _teardown() async {
    for (final p in _participants.values) {
      await p.dispose();
    }
    _participants.clear();
    _pendingCandidates.clear();
    _localStream?.getTracks().forEach((t) => t.stop());
    _localStream?.dispose();
    _localStream = null;
    onParticipantsChanged.close();
  }
}
