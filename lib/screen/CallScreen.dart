import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:provider/provider.dart';

import 'package:love_in_chat/model/emun/MessageType.dart' as app_msg;
import 'package:love_in_chat/provider/AuthProvider.dart';
import 'package:love_in_chat/provider/ConversationProvider.dart';
import 'package:love_in_chat/service/CallKitService.dart';
import 'package:love_in_chat/service/CallRingtoneService.dart';
import 'package:love_in_chat/service/CallSignalingService.dart';
import 'HomeScreen.dart';

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
  /// How long the caller waits for an answer before giving up.
  static const _ringTimeout = Duration(seconds: 45);

  final _localRenderer = RTCVideoRenderer();
  final _remoteRenderer = RTCVideoRenderer();

  // Nullable: they are assigned after async work, and dispose() may run first.
  StreamSubscription? _remoteSub;
  StreamSubscription? _localSub;
  StreamSubscription? _endedSub;

  // Captured up-front so we can still send the call message even if the
  // widget is already leaving the tree (context.read after await is unsafe).
  late final AuthProvider _auth;
  late final ConversationProvider _convos;

  bool _muted = false;
  bool _cameraOff = false;
  bool _speakerOn = true;
  bool _connected = false;
  bool _ringing = true;
  bool _messageSent = false; // guard against double-sending
  bool _leaving = false; // guard against double pop

  bool get _isCaller => widget.incomingOffer == null;

  Duration _elapsed = Duration.zero;
  Timer? _timer;
  Timer? _ringTimer;

  // ── Call summary message ─────────────────────────────────────────────────

  /// Encodes the call outcome as the message content stored in the DB.
  /// Format: "AUDIO:mm:ss" | "VIDEO:mm:ss" | "AUDIO:MISSED" etc.
  String _callContent(String outcome) {
    final kind = widget.isVideo ? 'VIDEO' : 'AUDIO';
    return '$kind:$outcome';
  }

  /// mm:ss (minutes may exceed 59 so the stored format stays parseable).
  String get _durationLabel {
    final m = _elapsed.inMinutes.toString().padLeft(2, '0');
    final s = _elapsed.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  Future<void> _sendCallMessage(String outcome) async {
    if (_messageSent) return;
    // CRITICAL: Only the caller logs the call summary message.
    // If the callee logs it, the server attributes the message to the callee,
    // making it appear as if the callee called the caller!
    if (!_isCaller) return;

    _messageSent = true;
    try {
      await _convos.sendMessage(
        _auth,
        widget.conversationId,
        _callContent(outcome),
        type: app_msg.MessageType.CALL,
      );
    } catch (e) {
      debugPrint('[CallScreen] could not send call message: $e');
    }
  }

  // ── Lifecycle ────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _auth = context.read<AuthProvider>();
    _convos = context.read<ConversationProvider>();
    _initCall();
  }

  Future<void> _initCall() async {
    // Ringtone belongs to the incoming UI; make sure it's off now that the
    // call screen is open. (CallKit UI is already dismissed by CallKitService.)
    unawaited(CallRingtoneService.stop());

    await _localRenderer.initialize();
    await _remoteRenderer.initialize();
    if (!mounted) return;

    final sig = widget.signalingService;

    // Subscribe BEFORE starting/answering so no early event is missed.
    _remoteSub = sig.onRemoteStream.stream.listen((stream) async {
      // Remote stream arrived => call answered. Stop ringback.
      _ringTimer?.cancel();
      await CallRingtoneService.stop();
      if (!mounted) return;
      setState(() {
        _remoteRenderer.srcObject = stream;
        _connected = true;
        _ringing = false;
      });
      _startTimer();
    });

    _localSub = sig.onLocalStream.stream.listen((stream) {
      if (!mounted) return;
      setState(() => _localRenderer.srcObject = stream);
    });

    _endedSub = sig.onCallEnded.stream.listen((type) async {
      // Remote side ended the call.
      _ringTimer?.cancel();
      if (_connected) {
        await _sendCallMessage(_durationLabel);
      } else {
        // We were ringing when the remote cancelled or declined.
        await _sendCallMessage(
          type == SignalType.callReject ? 'REJECTED' : 'MISSED',
        );
      }
      _leave();
    });

    // Loudspeaker by default (voice AND video, matching the UI state).
    try {
      await Helper.setSpeakerphoneOn(true);
    } catch (e) {
      debugPrint('[CallScreen] setSpeakerphoneOn error: $e');
    }
    if (!mounted) return;

    try {
      if (_isCaller) {
        // Ringback while waiting for the callee to answer.
        await CallRingtoneService.playRingback();
        _ringTimer = Timer(_ringTimeout, _onRingTimeout);

        await sig.startCall(
          remoteUserId: widget.remoteUserId,
          conversationId: widget.conversationId,
          video: widget.isVideo,
        );
      } else {
        await sig.answerCall(
            offerMsg: widget.incomingOffer!, video: widget.isVideo);
      }
    } catch (e) {
      // Typically: camera/mic permission denied or signaling failure.
      debugPrint('[CallScreen] call setup failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not start the call.')),
        );
      }
      try {
        await sig.hangup();
      } catch (_) {}
      _leave();
    }
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _elapsed += const Duration(seconds: 1));
    });
  }

  /// Caller waited too long with no answer.
  Future<void> _onRingTimeout() async {
    if (_connected || _leaving) return;
    await _hangup(outcomeOverride: 'MISSED');
  }

  Future<void> _leave() async {
    if (_leaving) return; // hangup() + onCallEnded can both land here
    _leaving = true;

    _timer?.cancel();
    _ringTimer?.cancel();
    if (!mounted) return;

    try {
      _convos.markCallEnded();
    } catch (_) {}

    final nav = Navigator.of(context);
    if (nav.canPop()) {
      nav.pop();
    } else {
      nav.pushReplacement(
        MaterialPageRoute(
          builder: (_) => HomeScreen(
            onThemeChanged: (_) {},
            currentThemeMode: ThemeMode.system,
          ),
        ),
      );
    }
  }

  Future<void> _hangup({String? outcomeOverride}) async {
    if (_leaving) return;
    _ringTimer?.cancel();

    // Determine outcome before tearing down.
    final outcome =
        outcomeOverride ?? (_connected ? _durationLabel : 'CANCELLED');
    try {
      await widget.signalingService.hangup();
    } catch (e) {
      debugPrint('[CallScreen] hangup error: $e');
    }
    await _sendCallMessage(outcome);
    _leave();
  }

  // ── Controls ─────────────────────────────────────────────────────────────

  void _toggleMute() {
    setState(() => _muted = !_muted);
    widget.signalingService.toggleMute(_muted);
  }

  void _toggleCamera() {
    setState(() => _cameraOff = !_cameraOff);
    widget.signalingService.toggleCamera(_cameraOff);
  }

  Future<void> _toggleSpeaker() async {
    final next = !_speakerOn;
    try {
      await Helper.setSpeakerphoneOn(next);
    } catch (_) {}
    if (mounted) setState(() => _speakerOn = next);
  }

  void _switchCamera() => widget.signalingService.switchCamera();

  @override
  void dispose() {
    _timer?.cancel();
    _ringTimer?.cancel();
    _remoteSub?.cancel();
    _localSub?.cancel();
    _endedSub?.cancel();
    _localRenderer.dispose();
    _remoteRenderer.dispose();
    CallRingtoneService.stop();
    CallKitService.endAllCalls();
    Helper.setSpeakerphoneOn(false).catchError((_) {});
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // System back = hang up. Otherwise the screen disappears while the call
    // (and mic/camera) keeps running with no UI.
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _hangup();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(fit: StackFit.expand, children: [
          // ── Remote video (full screen) / avatar fallback ───────────────
          if (widget.isVideo && _connected)
            RTCVideoView(_remoteRenderer,
                objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover)
          else
            _CallerBackground(
              name: widget.remoteName,
              ringing: _ringing,
              elapsed: _durationLabel,
              connected: _connected,
            ),

          // ── Local video (picture-in-picture) ───────────────────────────
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
                    objectFit:
                    RTCVideoViewObjectFit.RTCVideoViewObjectFitCover),
              ),
            ),

          // ── Control bar ────────────────────────────────────────────────
          Positioned(
            left: 0,
            right: 0,
            bottom: MediaQuery.of(context).padding.bottom + 32,
            child: _ControlBar(
              muted: _muted,
              cameraOff: _cameraOff,
              speakerOn: _speakerOn,
              isVideo: widget.isVideo,
              onMute: _toggleMute,
              onSpeaker: !widget.isVideo ? _toggleSpeaker : null,
              onCameraToggle: widget.isVideo ? _toggleCamera : null,
              onSwitchCamera: widget.isVideo ? _switchCamera : null,
              onHangup: _hangup,
            ),
          ),
        ]),
      ),
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
              style: const TextStyle(
                  fontSize: 44,
                  color: Colors.white,
                  fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(height: 20),
          Text(name,
              style: const TextStyle(
                  fontSize: 24,
                  color: Colors.white,
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
  final bool speakerOn;
  final bool isVideo;
  final VoidCallback onMute;
  final VoidCallback? onSpeaker;
  final VoidCallback? onCameraToggle;
  final VoidCallback? onSwitchCamera;
  final VoidCallback onHangup;

  const _ControlBar({
    required this.muted,
    required this.cameraOff,
    required this.speakerOn,
    required this.isVideo,
    required this.onMute,
    required this.onHangup,
    this.onSpeaker,
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
        // Speaker toggle — only on voice calls (video always uses speaker)
        if (!isVideo)
          _CtrlBtn(
            icon: speakerOn ? Icons.volume_up : Icons.hearing,
            label: speakerOn ? 'Speaker' : 'Earpiece',
            onTap: onSpeaker ?? () {},
            active: speakerOn,
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
  final bool active;

  const _CtrlBtn(
      {required this.icon,
        required this.label,
        required this.onTap,
        this.active = false});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
              color: active ? Colors.white38 : Colors.white24,
              shape: BoxShape.circle),
          child: Icon(icon, color: Colors.white, size: 26),
        ),
        const SizedBox(height: 6),
        Text(label,
            style: const TextStyle(color: Colors.white70, fontSize: 11)),
      ]),
    );
  }
}