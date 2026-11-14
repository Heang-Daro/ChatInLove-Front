import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:provider/provider.dart';

import 'package:love_in_chat/provider/AuthProvider.dart';
import 'package:love_in_chat/service/CallSignalingService.dart';
import 'package:love_in_chat/service/StompService.dart';

/// Full-screen in-call screen.
///
/// Handles both outgoing and incoming calls:
/// • Outgoing — pass [remoteUserId], [conversationId], [isVideo], [signalingService]
/// • Incoming — also pass [incomingOffer] (the offer map from the signal queue)
class CallScreen extends StatefulWidget {
  final String remoteUserId;
  final String remoteName;
  final String conversationId;
  final bool isVideo;
  final Map<String, dynamic>? incomingOffer; // null = we are the caller
  final CallSignalingService signalingService;

  const CallScreen({
    super.key,
    required this.remoteUserId,
    required this.remoteName,
    required this.conversationId,
    required this.isVideo,
    required this.signalingService,
    this.incomingOffer,
  });

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  final _localRenderer  = RTCVideoRenderer();
  final _remoteRenderer = RTCVideoRenderer();

  late final StreamSubscription _remoteSub;
  late final StreamSubscription _localSub;
  late final StreamSubscription _endedSub;

  bool _muted      = false;
  bool _cameraOff  = false;
  bool _speakerOn  = true;
  bool _connected  = false;
  bool _ringing    = true;   // true until remote track arrives or answer received

  Duration _elapsed = Duration.zero;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _initRenderers();
  }

  Future<void> _initRenderers() async {
    await _localRenderer.initialize();
    await _remoteRenderer.initialize();

    final sig = widget.signalingService;

    _remoteSub = sig.onRemoteStream.stream.listen((stream) {
      setState(() {
        _remoteRenderer.srcObject = stream;
        _connected = true;
        _ringing   = false;
      });
      _startTimer();
    });

    _localSub = sig.onLocalStream.stream.listen((stream) {
      setState(() => _localRenderer.srcObject = stream);
    });

    _endedSub = sig.onCallEnded.stream.listen((_) => _leave());

    if (widget.incomingOffer != null) {
      // Callee: answer the incoming offer.
      await sig.answerCall(
          offerMsg: widget.incomingOffer!, video: widget.isVideo);
    } else {
      // Caller: initiate the call.
      await sig.startCall(
        remoteUserId:   widget.remoteUserId,
        conversationId: widget.conversationId,
        video:          widget.isVideo,
      );
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
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _hangup() async {
    await widget.signalingService.hangup();
    _leave();
  }

  void _toggleMute() {
    setState(() => _muted = !_muted);
    widget.signalingService.toggleMute(_muted);
  }

  void _toggleCamera() {
    setState(() => _cameraOff = !_cameraOff);
    widget.signalingService.toggleCamera(_cameraOff);
  }

  void _switchCamera() => widget.signalingService.switchCamera();

  String get _elapsedLabel {
    final m = _elapsed.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = _elapsed.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  void dispose() {
    _timer?.cancel();
    _remoteSub.cancel();
    _localSub.cancel();
    _endedSub.cancel();
    _localRenderer.dispose();
    _remoteRenderer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(fit: StackFit.expand, children: [
        // ── Remote video (full screen) / avatar fallback ─────────────────
        if (widget.isVideo && _connected)
          RTCVideoView(_remoteRenderer, objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover)
        else
          _CallerBackground(name: widget.remoteName, ringing: _ringing, elapsed: _elapsedLabel, connected: _connected),

        // ── Local video (picture-in-picture) ─────────────────────────────
        if (widget.isVideo && !_cameraOff)
          Positioned(
            right: 16,
            top: MediaQuery.of(context).padding.top + 16,
            width: 100,
            height: 140,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: RTCVideoView(_localRenderer,
                  mirror: true,
                  objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover),
            ),
          ),

        // ── Control bar ───────────────────────────────────────────────────
        Positioned(
          left: 0, right: 0,
          bottom: MediaQuery.of(context).padding.bottom + 32,
          child: _ControlBar(
            muted:     _muted,
            cameraOff: _cameraOff,
            isVideo:   widget.isVideo,
            onMute:         _toggleMute,
            onCameraToggle: widget.isVideo ? _toggleCamera : null,
            onSwitchCamera: widget.isVideo ? _switchCamera : null,
            onHangup:       _hangup,
          ),
        ),
      ]),
    );
  }
}

// ── Background when no video ─────────────────────────────────────────────────
class _CallerBackground extends StatelessWidget {
  final String name;
  final bool ringing;
  final String elapsed;
  final bool connected;

  const _CallerBackground({
    required this.name,
    required this.ringing,
    required this.elapsed,
    required this.connected,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.pinkAccent.shade700, Colors.pink.shade900],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircleAvatar(
            radius: 56,
            backgroundColor: Colors.white24,
            child: Text(
              name.isNotEmpty ? name[0].toUpperCase() : '?',
              style: const TextStyle(fontSize: 44, color: Colors.white,
                  fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(height: 20),
          Text(name,
              style: const TextStyle(fontSize: 24, color: Colors.white,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(
            connected ? elapsed : (ringing ? 'Ringing…' : 'Connecting…'),
            style: const TextStyle(fontSize: 16, color: Colors.white70),
          ),
        ],
      ),
    );
  }
}

// ── Control bar ──────────────────────────────────────────────────────────────
class _ControlBar extends StatelessWidget {
  final bool muted;
  final bool cameraOff;
  final bool isVideo;
  final VoidCallback onMute;
  final VoidCallback? onCameraToggle;
  final VoidCallback? onSwitchCamera;
  final VoidCallback onHangup;

  const _ControlBar({
    required this.muted,
    required this.cameraOff,
    required this.isVideo,
    required this.onMute,
    required this.onHangup,
    this.onCameraToggle,
    this.onSwitchCamera,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _CtrlBtn(
          icon: muted ? Icons.mic_off : Icons.mic,
          label: muted ? 'Unmute' : 'Mute',
          onTap: onMute,
        ),
        if (isVideo) ...[
          _CtrlBtn(
            icon: cameraOff ? Icons.videocam_off : Icons.videocam,
            label: cameraOff ? 'Cam on' : 'Cam off',
            onTap: onCameraToggle ?? () {},
          ),
          _CtrlBtn(
            icon: Icons.switch_camera,
            label: 'Flip',
            onTap: onSwitchCamera ?? () {},
          ),
        ],
        // Hang-up button — large red circle
        GestureDetector(
          onTap: onHangup,
          child: Container(
            width: 68,
            height: 68,
            decoration: const BoxDecoration(
                color: Colors.redAccent, shape: BoxShape.circle),
            child: const Icon(Icons.call_end, color: Colors.white, size: 32),
          ),
        ),
      ],
    );
  }
}

class _CtrlBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _CtrlBtn(
      {required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
              color: Colors.white24, shape: BoxShape.circle),
          child: Icon(icon, color: Colors.white, size: 26),
        ),
        const SizedBox(height: 6),
        Text(label,
            style:
                const TextStyle(color: Colors.white70, fontSize: 11)),
      ]),
    );
  }
}
