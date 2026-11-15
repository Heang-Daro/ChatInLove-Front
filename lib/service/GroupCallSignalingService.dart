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

/// One active participant in the group call.
/// Only members who have explicitly joined are tracked here.
class GroupParticipant {
  final String userId;
  final String username;
  RTCPeerConnection? pc;
  MediaStream? remoteStream;
  final RTCVideoRenderer renderer;
  bool connected;

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
///
/// Flow (caller side):
///   1. `startCall()` — captures local media, broadcasts GROUP_CALL_STARTED to
///      the conversation topic. Does NOT create any peer connections yet.
///   2. When a member taps "Join", they send JOIN_CALL back to the caller.
///   3. `_handleJoin()` — creates a peer connection and sends a CALL_OFFER to
///      that specific member. Only then do they appear in the grid.
///
/// Flow (callee side — received via HomeScreen/ConversationProvider):
///   1. App receives GROUP_CALL_STARTED via /user/queue/signal.
///   2. UI shows an "incoming group call" banner / overlay.
///   3. User taps "Join" → `joinExistingCall()` is called.
///   4. This sends JOIN_CALL to the caller, who then sends back a CALL_OFFER.
///   5. `_handleOffer()` — creates the peer connection and answers.
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

  /// Only participants who have JOINED the call. Never the full group member list.
  final Map<String, GroupParticipant> _activeParticipants = {};

  final Map<String, List<RTCIceCandidate>> _pendingCandidates = {};

  String? _callerId; // who started the call

  // ── Public streams ─────────────────────────────────────────────────────────
  /// Fires whenever _activeParticipants changes — rebuild the grid.
  final StreamController<void> onParticipantsChanged =
      StreamController.broadcast();

  /// Fires when the local stream is ready (self-preview).
  final StreamController<MediaStream> onLocalStream =
      StreamController.broadcast();

  /// Only active (joined) participants.
  List<GroupParticipant> get participants =>
      List.unmodifiable(_activeParticipants.values);

  MediaStream? get localStream => _localStream;

  // ── Caller: start the call ─────────────────────────────────────────────────

  /// Captures local media and broadcasts GROUP_CALL_STARTED to the conversation.
  /// Does NOT create peer connections — waits for members to send JOIN_CALL.
  Future<void> startCall() async {
    _callerId = localUserId;
    _localStream = await _getUserMedia();
    onLocalStream.add(_localStream!);

    // Subscribe to both channels before broadcasting.
    stomp.subscribeToSignaling(_onPrivateFrame);
    stomp.subscribeToGroupCallTopic(conversationId, _onGroupFrame);

    stomp.sendGroupSignal(conversationId, {
      'type': 'GROUP_CALL_STARTED',
      'conversationId': conversationId,
      'callType': video ? 'VIDEO' : 'AUDIO',
      'callerUserId': localUserId,
    });

    debugPrint('[GroupCall] GROUP_CALL_STARTED broadcast sent for $conversationId');
  }

  // ── Callee: join an existing call ──────────────────────────────────────────

  /// Called when the user taps "Join" on the incoming group call banner.
  /// Captures local media and sends JOIN_CALL to the caller.
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
      'conversationId': conversationId,
      'callType': video ? 'VIDEO' : 'AUDIO',
      'isGroup': true,
      'joinerUsername': _usernameOf(localUserId),
    });
    debugPrint('[GroupCall] JOIN_CALL sent to caller $callerUserId');
  }

  // ── Leave ──────────────────────────────────────────────────────────────────

  Future<void> leave() async {
    // Notify all active participants.
    for (final p in _activeParticipants.values) {
      stomp.sendSignal(p.userId, {
        'type': 'LEAVE_CALL',
        'conversationId': conversationId,
        'isGroup': true,
      });
    }
    // Also broadcast on group topic so non-connected members see it.
    stomp.sendGroupSignal(conversationId, {
      'type': 'LEAVE_CALL',
      'conversationId': conversationId,
      'callerUserId': localUserId,
    });
    await _teardown();
  }

  // ── Signal frame routing ───────────────────────────────────────────────────

  /// Handles frames arriving on /user/queue/signal (targeted messages).
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
        // A member wants to join — we are the caller, create a peer and offer.
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
      case 'CALL_HANGUP':
      case 'LEAVE_CALL':
        _removeParticipant(from);
        break;
    }
  }

  /// Handles frames arriving on /topic/conversations/{id}/call (broadcasts).
  void _onGroupFrame(StompFrame frame) {
    // Group topic frames are informational (GROUP_CALL_STARTED, LEAVE_CALL).
    // Actual WebRTC signaling arrives via private queues.
    if (frame.body == null) return;
    Map<String, dynamic> msg;
    try {
      msg = json.decode(frame.body!) as Map<String, dynamic>;
    } catch (_) {
      return;
    }

    final type = msg['type']?.toString();
    final from = msg['fromUserId']?.toString() ?? '';
    if (from == localUserId) return; // ignore own broadcasts

    if (type == 'LEAVE_CALL') {
      _removeParticipant(from);
    }
  }

  // ── Peer connection lifecycle ──────────────────────────────────────────────

  /// Caller received JOIN_CALL — create a peer connection and send offer.
  void _handleJoin(String from, Map<String, dynamic> msg) async {
    final username = msg['joinerUsername']?.toString() ?? from;
    debugPrint('[GroupCall] $from ($username) joined — creating offer');

    final p = await _getOrCreateParticipant(from, username);
    _localStream!.getTracks().forEach((t) => p.pc!.addTrack(t, _localStream!));

    final offer = await p.pc!.createOffer(_offerConstraints);
    await p.pc!.setLocalDescription(offer);

    stomp.sendSignal(from, {
      'type': 'CALL_OFFER',
      'conversationId': conversationId,
      'callType': video ? 'VIDEO' : 'AUDIO',
      'sdp': offer.toMap(),
      'isGroup': true,
    });
    onParticipantsChanged.add(null);
  }

  /// Callee received CALL_OFFER from caller — answer it.
  void _handleOffer(String from, Map<String, dynamic> msg) async {
    debugPrint('[GroupCall] received CALL_OFFER from $from');
    final username = msg['senderUsername']?.toString() ?? from;
    final p = await _getOrCreateParticipant(from, username);
    _localStream!.getTracks().forEach((t) => p.pc!.addTrack(t, _localStream!));

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

    stomp.sendSignal(from, {
      'type': 'CALL_ANSWER',
      'conversationId': conversationId,
      'sdp': answer.toMap(),
      'isGroup': true,
    });
    onParticipantsChanged.add(null);
  }

  void _handleAnswer(String from, Map<String, dynamic> msg) async {
    final p = _activeParticipants[from];
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
      stomp.sendSignal(p.userId, {
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

  // ── Helpers ────────────────────────────────────────────────────────────────

  Future<MediaStream> _getUserMedia() async {
    return navigator.mediaDevices.getUserMedia({
      'audio': true,
      'video': video
          ? {'facingMode': 'user', 'width': {'ideal': 640}, 'height': {'ideal': 480}}
          : false,
    });
  }

  String _usernameOf(String userId) => userId; // placeholder — caller stamps it

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
  }
}
