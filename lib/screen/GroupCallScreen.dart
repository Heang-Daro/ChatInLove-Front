import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:provider/provider.dart';

import 'package:love_in_chat/model/emun/MessageType.dart' as app_msg;
import 'package:love_in_chat/model/Response/ConversationMemberResponse.dart';
import 'package:love_in_chat/provider/AuthProvider.dart';
import 'package:love_in_chat/provider/ConversationProvider.dart';
import 'package:love_in_chat/service/GroupCallSignalingService.dart';
import 'package:love_in_chat/service/StompService.dart';

/// Full-screen group call screen (mesh WebRTC).
///
/// Pass the full [members] list of the conversation. The screen filters out
/// the local user and calls every other active member.
class GroupCallScreen extends StatefulWidget {
  final String conversationId;
  final String groupName;
  final bool isVideo;
  final List<ConversationMemberResponse> members;
  final String localUserId;

  const GroupCallScreen({
    super.key,
    required this.conversationId,
    required this.groupName,
    required this.isVideo,
    required this.members,
    required this.localUserId,
  });

  @override
  State<GroupCallScreen> createState() => _GroupCallScreenState();
}

class _GroupCallScreenState extends State<GroupCallScreen> {
  late final GroupCallSignalingService _sig;
  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();

  late final StreamSubscription _changeSub;

  bool _muted     = false;
  bool _camOff    = false;
  bool _joined    = false;
  bool _msgSent   = false;

  Duration _elapsed = Duration.zero;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _localRenderer.initialize();

    _sig = GroupCallSignalingService(
      stomp:          StompService(),
      localUserId:    widget.localUserId,
      conversationId: widget.conversationId,
      video:          widget.isVideo,
    );

    _changeSub = _sig.onParticipantsChanged.stream.listen((_) {
      if (mounted) setState(() {});
      // Start the timer once anyone connects.
      if (!_joined && _sig.participants.any((p) => p.connected)) {
        _joined = true;
        _startTimer();
      }
    });

    _join();
  }

  Future<void> _join() async {
    final remoteMembers = widget.members
        .where((m) => m.userId != widget.localUserId && m.leftAt == null)
        .map((m) => {'userId': m.userId, 'username': m.username})
        .toList();

    await _sig.joinCall(remoteMembers);

    if (_sig.localStream != null && mounted) {
      setState(() => _localRenderer.srcObject = _sig.localStream);
    }
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _elapsed += const Duration(seconds: 1));
    });
  }

  Future<void> _leave() async {
    _timer?.cancel();
    if (!_msgSent) {
      _msgSent = true;
      try {
        final auth  = context.read<AuthProvider>();
        final convos = context.read<ConversationProvider>();
        final kind  = widget.isVideo ? 'VIDEO' : 'AUDIO';
        final outcome = _joined ? _elapsedLabel : 'MISSED';
        await convos.sendMessage(auth, widget.conversationId,
            '$kind:$outcome', type: app_msg.MessageType.CALL);
      } catch (_) {}
    }
    await _sig.leave();
    if (mounted) Navigator.of(context).pop();
  }

  String get _elapsedLabel {
    final m = _elapsed.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = _elapsed.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  void dispose() {
    _changeSub.cancel();
    _localRenderer.dispose();
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final participants = _sig.participants;
    final totalTiles   = participants.length + 1; // +1 for local

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(fit: StackFit.expand, children: [
        // ── Video grid ──────────────────────────────────────────────────────
        SafeArea(
          bottom: false,
          child: Column(children: [
            // Header bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(widget.groupName,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold)),
                      Text(
                        _joined
                            ? _elapsedLabel
                            : '${participants.isEmpty ? 'Calling…' : '${participants.length} joined'}',
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ]),
            ),
            // Tiles
            Expanded(
              child: _VideoGrid(
                localRenderer:  _localRenderer,
                localName:      'You',
                participants:   participants,
                isVideo:        widget.isVideo,
              ),
            ),
          ]),
        ),

        // ── Control bar ─────────────────────────────────────────────────────
        Positioned(
          left: 0, right: 0,
          bottom: MediaQuery.of(context).padding.bottom + 24,
          child: _GroupControlBar(
            muted:    _muted,
            camOff:   _camOff,
            isVideo:  widget.isVideo,
            onMute: () {
              setState(() => _muted = !_muted);
              _sig.toggleMute(_muted);
            },
            onCamToggle: widget.isVideo
                ? () {
                    setState(() => _camOff = !_camOff);
                    _sig.toggleCamera(_camOff);
                  }
                : null,
            onSwitchCam: widget.isVideo ? _sig.switchCamera : null,
            onLeave: _leave,
          ),
        ),
      ]),
    );
  }
}

// ── Responsive video grid ─────────────────────────────────────────────────────
class _VideoGrid extends StatelessWidget {
  final RTCVideoRenderer localRenderer;
  final String localName;
  final List<GroupParticipant> participants;
  final bool isVideo;

  const _VideoGrid({
    required this.localRenderer,
    required this.localName,
    required this.participants,
    required this.isVideo,
  });

  @override
  Widget build(BuildContext context) {
    final tiles = <Widget>[
      _ParticipantTile(
        renderer: localRenderer,
        name: localName,
        isLocal: true,
        isVideo: isVideo,
        connected: true,
      ),
      for (final p in participants)
        _ParticipantTile(
          renderer: p.renderer,
          name: p.username,
          isLocal: false,
          isVideo: isVideo,
          connected: p.connected,
        ),
    ];

    final count = tiles.length;
    int cols;
    if (count <= 1)      cols = 1;
    else if (count <= 4) cols = 2;
    else                 cols = 3;

    return GridView.count(
      crossAxisCount: cols,
      padding: const EdgeInsets.all(4),
      mainAxisSpacing: 4,
      crossAxisSpacing: 4,
      children: tiles,
    );
  }
}

class _ParticipantTile extends StatelessWidget {
  final RTCVideoRenderer renderer;
  final String name;
  final bool isLocal;
  final bool isVideo;
  final bool connected;

  const _ParticipantTile({
    required this.renderer,
    required this.name,
    required this.isLocal,
    required this.isVideo,
    required this.connected,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Stack(fit: StackFit.expand, children: [
        isVideo && connected
            ? RTCVideoView(renderer,
                mirror: isLocal,
                objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover)
            : Container(
                color: Colors.grey.shade900,
                alignment: Alignment.center,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircleAvatar(
                      radius: 28,
                      backgroundColor: Colors.pinkAccent.withValues(alpha: 0.3),
                      child: Text(
                        name.isNotEmpty ? name[0].toUpperCase() : '?',
                        style: const TextStyle(
                            fontSize: 24,
                            color: Colors.white,
                            fontWeight: FontWeight.bold),
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (!connected)
                      const SizedBox(
                        width: 18, height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white54),
                      ),
                  ],
                ),
              ),
        // Name label
        Positioned(
          left: 8, bottom: 8,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: Colors.black54,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(name,
                style: const TextStyle(
                    color: Colors.white, fontSize: 11)),
          ),
        ),
      ]),
    );
  }
}

// ── Control bar ───────────────────────────────────────────────────────────────
class _GroupControlBar extends StatelessWidget {
  final bool muted;
  final bool camOff;
  final bool isVideo;
  final VoidCallback onMute;
  final VoidCallback? onCamToggle;
  final VoidCallback? onSwitchCam;
  final VoidCallback onLeave;

  const _GroupControlBar({
    required this.muted,
    required this.camOff,
    required this.isVideo,
    required this.onMute,
    required this.onLeave,
    this.onCamToggle,
    this.onSwitchCam,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _Btn(icon: muted ? Icons.mic_off : Icons.mic,
             label: muted ? 'Unmute' : 'Mute', onTap: onMute),
        if (isVideo) ...[
          _Btn(icon: camOff ? Icons.videocam_off : Icons.videocam,
               label: camOff ? 'Cam on' : 'Cam off',
               onTap: onCamToggle ?? () {}),
          _Btn(icon: Icons.switch_camera, label: 'Flip',
               onTap: onSwitchCam ?? () {}),
        ],
        GestureDetector(
          onTap: onLeave,
          child: Container(
            width: 64, height: 64,
            decoration: const BoxDecoration(
                color: Colors.redAccent, shape: BoxShape.circle),
            child: const Icon(Icons.call_end, color: Colors.white, size: 30),
          ),
        ),
      ],
    );
  }
}

class _Btn extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _Btn({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Column(children: [
          Container(
            width: 54, height: 54,
            decoration:
                BoxDecoration(color: Colors.white24, shape: BoxShape.circle),
            child: Icon(icon, color: Colors.white, size: 24),
          ),
          const SizedBox(height: 5),
          Text(label,
              style: const TextStyle(color: Colors.white70, fontSize: 11)),
        ]),
      );
}
