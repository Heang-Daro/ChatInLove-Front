import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show FontFeature, ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:provider/provider.dart';

import 'package:love_in_chat/model/emun/MessageType.dart' as app_msg;
import 'package:love_in_chat/provider/AuthProvider.dart';
import 'package:love_in_chat/provider/ConversationProvider.dart';
import 'package:love_in_chat/service/CallKitService.dart';
import 'package:love_in_chat/service/CallRingtoneService.dart';
import 'package:love_in_chat/service/CallSignalingService.dart';
import 'HomeScreen.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Design tokens
// ─────────────────────────────────────────────────────────────────────────────

class _C {
  /// Brand colour: pinkAccent 400.
  static final Color brand = Colors.pinkAccent.shade400;
  static const Color bg = Color(0xFF0D090C);
  static const Color surface = Color(0xFF241820);
  static const Color danger = Color(0xFFE53935);
  static const Color online = Color(0xFF4CD964);
}

String _initial(String name) =>
    name.trim().isNotEmpty ? name.trim()[0].toUpperCase() : '?';

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
  bool _showUi = true; // header + controls (auto-hide in connected video)

  bool get _isCaller => widget.incomingOffer == null;

  Duration _elapsed = Duration.zero;
  Timer? _timer;
  Timer? _ringTimer;
  Timer? _hideTimer;

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

  String get _statusLabel {
    if (_connected) return _durationLabel;
    return _isCaller && _ringing ? 'Ringing…' : 'Connecting…';
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
      _scheduleHide();
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
          SnackBar(
            behavior: SnackBarBehavior.floating,
            backgroundColor: _C.surface,
            content: Row(
              children: [
                Icon(Icons.error_outline_rounded, color: _C.brand, size: 18),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text('Could not start the call.',
                      style: TextStyle(color: Colors.white)),
                ),
              ],
            ),
          ),
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
    _hideTimer?.cancel();
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

  /// System back: while ringing it cancels right away; during a live call it
  /// asks first so a stray swipe cannot end the conversation.
  Future<void> _onBack() async {
    if (!_connected) {
      _hangup();
      return;
    }
    final end = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _C.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('End call?',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
        content: Text(
          'Your call with ${widget.remoteName} will end.',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('Stay', style: TextStyle(color: _C.brand)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: _C.danger),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('End call'),
          ),
        ],
      ),
    );
    if (end == true && mounted) _hangup();
  }

  // ── Auto-hiding UI (connected video calls only) ───────────────────────────

  void _scheduleHide() {
    _hideTimer?.cancel();
    if (!widget.isVideo || !_connected) return;
    _hideTimer = Timer(const Duration(seconds: 5), () {
      if (mounted) setState(() => _showUi = false);
    });
  }

  void _toggleUi() {
    if (!widget.isVideo || !_connected) return;
    setState(() => _showUi = !_showUi);
    if (_showUi) _scheduleHide();
  }

  void _touchUi() {
    HapticFeedback.lightImpact();
    _scheduleHide();
  }

  // ── Controls ─────────────────────────────────────────────────────────────

  void _toggleMute() {
    _touchUi();
    setState(() => _muted = !_muted);
    widget.signalingService.toggleMute(_muted);
  }

  void _toggleCamera() {
    _touchUi();
    setState(() => _cameraOff = !_cameraOff);
    widget.signalingService.toggleCamera(_cameraOff);
  }

  Future<void> _toggleSpeaker() async {
    HapticFeedback.lightImpact();
    final next = !_speakerOn;
    try {
      await Helper.setSpeakerphoneOn(next);
    } catch (_) {}
    if (mounted) setState(() => _speakerOn = next);
  }

  void _switchCamera() {
    _touchUi();
    widget.signalingService.switchCamera();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _ringTimer?.cancel();
    _hideTimer?.cancel();
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

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final pad = MediaQuery.of(context).padding;
    final liveVideo = widget.isVideo && _connected;
    final uiVisible = _showUi || !liveVideo;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _onBack();
      },
      child: Scaffold(
        backgroundColor: _C.bg,
        body: Stack(
          fit: StackFit.expand,
          children: [
            const _Backdrop(),

            // Stage (tap toggles the UI in a live video call).
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _toggleUi,
                child: _buildStage(pad.top + 84, pad.bottom + 160),
              ),
            ),

            // Bottom scrim so the controls stay readable over video.
            if (liveVideo)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: IgnorePointer(
                  child: _AutoHide(
                    visible: uiVisible,
                    hiddenOffset: Offset.zero,
                    child: Container(
                      height: 240,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                          colors: [
                            Colors.black.withValues(alpha: 0.75),
                            Colors.transparent,
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),

            // Header (name + timer) for a live video call.
            if (liveVideo)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: _AutoHide(
                  visible: uiVisible,
                  hiddenOffset: const Offset(0, -0.4),
                  child: _VideoHeader(
                    name: widget.remoteName,
                    status: _statusLabel,
                    muted: _muted,
                  ),
                ),
              ),

            // Controls
            Positioned(
              left: 0,
              right: 0,
              bottom: pad.bottom + 24,
              child: _AutoHide(
                visible: uiVisible,
                hiddenOffset: const Offset(0, 0.4),
                child: Center(
                  child: _ControlBar(
                    muted: _muted,
                    cameraOff: _cameraOff,
                    speakerOn: _speakerOn,
                    isVideo: widget.isVideo,
                    onMute: _toggleMute,
                    onSpeaker: _toggleSpeaker,
                    onCameraToggle: _toggleCamera,
                    onSwitchCamera: _switchCamera,
                    onHangup: () {
                      HapticFeedback.mediumImpact();
                      _hangup();
                    },
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStage(double topInset, double bottomInset) {
    // Live video: remote full-bleed + draggable self-view.
    if (widget.isVideo && _connected) {
      return _PipStage(
        topInset: topInset,
        bottomInset: bottomInset,
        remote: RTCVideoView(
          _remoteRenderer,
          objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
        ),
        local: _cameraOff
            ? const _CameraOffPlaceholder()
            : RTCVideoView(
          _localRenderer,
          mirror: true,
          objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
        ),
      );
    }

    // Ringing / connecting / audio call.
    final showPreview = widget.isVideo &&
        !_cameraOff &&
        _localRenderer.srcObject != null;

    return Stack(
      fit: StackFit.expand,
      children: [
        if (showPreview) ...[
          // Your own camera behind the "calling" UI, dimmed.
          RTCVideoView(
            _localRenderer,
            mirror: true,
            objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
          ),
          Container(color: Colors.black.withValues(alpha: 0.55)),
        ],
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 120),
            child: _CallerInfo(
              name: widget.remoteName,
              status: _statusLabel,
              connected: _connected,
              waiting: !_connected,
              muted: _muted,
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Backdrop / animation helpers
// ─────────────────────────────────────────────────────────────────────────────

class _Backdrop extends StatelessWidget {
  const _Backdrop();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: const Alignment(0, -0.5),
          radius: 1.3,
          colors: [_C.brand.withValues(alpha: 0.30), _C.bg],
        ),
      ),
    );
  }
}

/// Fades + slides its child in and out, and blocks touches while hidden.
class _AutoHide extends StatelessWidget {
  final bool visible;
  final Offset hiddenOffset;
  final Widget child;

  const _AutoHide({
    required this.visible,
    required this.hiddenOffset,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: !visible,
      child: AnimatedSlide(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
        offset: visible ? Offset.zero : hiddenOffset,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 250),
          opacity: visible ? 1 : 0,
          child: child,
        ),
      ),
    );
  }
}

class _PulseDot extends StatefulWidget {
  final Color color;
  const _PulseDot({required this.color});

  @override
  State<_PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<_PulseDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween<double>(begin: 0.35, end: 1).animate(_c),
      child: Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Caller info (ringing / connecting / audio call)
// ─────────────────────────────────────────────────────────────────────────────

class _CallerInfo extends StatelessWidget {
  final String name;
  final String status;
  final bool connected;
  final bool waiting;
  final bool muted;

  const _CallerInfo({
    required this.name,
    required this.status,
    required this.connected,
    required this.waiting,
    required this.muted,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _RippleAvatar(name: name, rippling: waiting, size: 128),
          const SizedBox(height: 28),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 28,
                color: Colors.white,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.2,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (connected) ...[
                const _PulseDot(color: _C.online),
                const SizedBox(width: 8),
              ],
              Text(
                status,
                style: const TextStyle(
                  fontSize: 17,
                  color: Colors.white70,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            child: muted
                ? Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.mic_off_rounded,
                        color: _C.brand, size: 15),
                    const SizedBox(width: 6),
                    const Text('Microphone off',
                        style: TextStyle(
                            color: Colors.white, fontSize: 12)),
                  ],
                ),
              ),
            )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }
}

/// Avatar with expanding rings while waiting, a solid pink ring once connected.
class _RippleAvatar extends StatefulWidget {
  final String name;
  final bool rippling;
  final double size;

  const _RippleAvatar({
    required this.name,
    required this.rippling,
    required this.size,
  });

  @override
  State<_RippleAvatar> createState() => _RippleAvatarState();
}

class _RippleAvatarState extends State<_RippleAvatar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  );

  @override
  void initState() {
    super.initState();
    if (widget.rippling) _c.repeat();
  }

  @override
  void didUpdateWidget(covariant _RippleAvatar old) {
    super.didUpdateWidget(old);
    if (widget.rippling && !_c.isAnimating) {
      _c.repeat();
    } else if (!widget.rippling && _c.isAnimating) {
      _c.stop();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.size;
    final box = size * 2.1;

    return SizedBox(
      width: box,
      height: box,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          return Stack(
            alignment: Alignment.center,
            children: [
              if (widget.rippling)
                for (var i = 0; i < 3; i++) _ring((_c.value + i / 3) % 1.0),
              // Solid ring + avatar
              Container(
                width: size + 14,
                height: size + 14,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: widget.rippling
                        ? Colors.white.withValues(alpha: 0.35)
                        : _C.brand,
                    width: 3,
                  ),
                ),
              ),
              CircleAvatar(
                radius: size / 2,
                backgroundColor: _C.brand,
                child: Text(
                  _initial(widget.name),
                  style: TextStyle(
                    fontSize: size * 0.4,
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _ring(double t) {
    final scale = 1.0 + t * 0.95;
    return Opacity(
      opacity: (1 - t) * 0.35,
      child: Container(
        width: (widget.size + 14) * scale,
        height: (widget.size + 14) * scale,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: _C.brand,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Live video: header + picture-in-picture
// ─────────────────────────────────────────────────────────────────────────────

class _VideoHeader extends StatelessWidget {
  final String name;
  final String status;
  final bool muted;

  const _VideoHeader({
    required this.name,
    required this.status,
    required this.muted,
  });

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;

    return Container(
      padding: EdgeInsets.fromLTRB(20, top + 10, 20, 32),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black.withValues(alpha: 0.7),
            Colors.transparent,
          ],
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    const _PulseDot(color: _C.online),
                    const SizedBox(width: 6),
                    Text(
                      status,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 14,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (muted)
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.14),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.mic_off_rounded, color: _C.brand, size: 18),
            ),
        ],
      ),
    );
  }
}

class _CameraOffPlaceholder extends StatelessWidget {
  const _CameraOffPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: _C.surface,
      alignment: Alignment.center,
      child: const Icon(Icons.videocam_off_rounded,
          color: Colors.white54, size: 28),
    );
  }
}

/// Remote full-bleed, small draggable self-view that snaps to the corners.
/// Tap the small view to swap the two.
class _PipStage extends StatefulWidget {
  final double topInset;
  final double bottomInset;
  final Widget remote;
  final Widget local;

  const _PipStage({
    required this.topInset,
    required this.bottomInset,
    required this.remote,
    required this.local,
  });

  @override
  State<_PipStage> createState() => _PipStageState();
}

class _PipStageState extends State<_PipStage> {
  static const double _w = 108;
  static const double _h = 152;
  static const double _margin = 12;

  bool _swapped = false;
  bool _right = true;
  bool _bottom = false;
  Offset? _drag;

  @override
  Widget build(BuildContext context) {
    final main = _swapped ? widget.local : widget.remote;
    final pip = _swapped ? widget.remote : widget.local;

    return LayoutBuilder(
      builder: (context, c) {
        final minX = _margin;
        final maxX = math.max(minX, c.maxWidth - _w - _margin);
        final minY = widget.topInset;
        final maxY = math.max(minY, c.maxHeight - _h - widget.bottomInset);

        final snapped = Offset(_right ? maxX : minX, _bottom ? maxY : minY);
        final pos = _drag ?? snapped;
        final dragging = _drag != null;

        return Stack(
          children: [
            Positioned.fill(child: main),
            AnimatedPositioned(
              duration:
              dragging ? Duration.zero : const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              left: pos.dx,
              top: pos.dy,
              width: _w,
              height: _h,
              child: GestureDetector(
                onTap: () {
                  HapticFeedback.selectionClick();
                  setState(() => _swapped = !_swapped);
                },
                onPanStart: (_) => setState(() => _drag = snapped),
                onPanUpdate: (d) {
                  final cur = _drag ?? snapped;
                  setState(() {
                    _drag = Offset(
                      (cur.dx + d.delta.dx).clamp(minX, maxX).toDouble(),
                      (cur.dy + d.delta.dy).clamp(minY, maxY).toDouble(),
                    );
                  });
                },
                onPanEnd: (_) {
                  final p = _drag ?? snapped;
                  setState(() {
                    _right = p.dx + _w / 2 > c.maxWidth / 2;
                    _bottom = p.dy + _h / 2 > (minY + maxY + _h) / 2;
                    _drag = null;
                  });
                },
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: _C.brand, width: 2),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.45),
                        blurRadius: 14,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: pip,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Control bar
// ─────────────────────────────────────────────────────────────────────────────

class _ControlBar extends StatelessWidget {
  final bool muted;
  final bool cameraOff;
  final bool speakerOn;
  final bool isVideo;
  final VoidCallback onMute;
  final VoidCallback onSpeaker;
  final VoidCallback onCameraToggle;
  final VoidCallback onSwitchCamera;
  final VoidCallback onHangup;

  const _ControlBar({
    required this.muted,
    required this.cameraOff,
    required this.speakerOn,
    required this.isVideo,
    required this.onMute,
    required this.onSpeaker,
    required this.onCameraToggle,
    required this.onSwitchCamera,
    required this.onHangup,
  });

  @override
  Widget build(BuildContext context) {
    final buttons = <Widget>[
      _ControlButton(
        icon: muted ? Icons.mic_off_rounded : Icons.mic_rounded,
        label: muted ? 'Unmute' : 'Mute',
        active: muted,
        onTap: onMute,
      ),
      // Speaker toggle — only on voice calls (video always uses speaker)
      if (!isVideo)
        _ControlButton(
          icon: speakerOn ? Icons.volume_up_rounded : Icons.hearing_rounded,
          label: speakerOn ? 'Speaker' : 'Earpiece',
          active: speakerOn,
          onTap: onSpeaker,
        ),
      if (isVideo) ...[
        _ControlButton(
          icon: cameraOff
              ? Icons.videocam_off_rounded
              : Icons.videocam_rounded,
          label: cameraOff ? 'Start cam' : 'Stop cam',
          active: cameraOff,
          onTap: onCameraToggle,
        ),
        _ControlButton(
          icon: Icons.flip_camera_ios_rounded,
          label: 'Flip',
          enabled: !cameraOff,
          onTap: onSwitchCamera,
        ),
      ],
      _ControlButton(
        icon: Icons.call_end_rounded,
        label: 'End',
        danger: true,
        size: 64,
        onTap: onHangup,
      ),
    ];

    return ClipRRect(
      borderRadius: BorderRadius.circular(40),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.42),
            borderRadius: BorderRadius.circular(40),
            border: Border.all(color: Colors.white12),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < buttons.length; i++) ...[
                if (i > 0) const SizedBox(width: 18),
                buttons[i],
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ControlButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool active; // toggled on (muted, speaker on, camera off…)
  final bool enabled;
  final bool danger;
  final double size;

  const _ControlButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.active = false,
    this.enabled = true,
    this.danger = false,
    this.size = 56,
  });

  @override
  Widget build(BuildContext context) {
    final Color bg = danger
        ? _C.danger
        : active
        ? Colors.white
        : Colors.white.withValues(alpha: 0.16);
    final Color fg = (active && !danger) ? _C.bg : Colors.white;

    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 150),
        opacity: enabled ? 1 : 0.35,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: enabled ? onTap : null,
          child: SizedBox(
            width: 64,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  height: 64,
                  child: Center(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: size,
                      height: size,
                      decoration: BoxDecoration(
                        color: bg,
                        shape: BoxShape.circle,
                        boxShadow: danger
                            ? [
                          BoxShadow(
                            color: _C.danger.withValues(alpha: 0.45),
                            blurRadius: 14,
                            offset: const Offset(0, 4),
                          ),
                        ]
                            : null,
                      ),
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 180),
                        transitionBuilder: (child, anim) =>
                            ScaleTransition(scale: anim, child: child),
                        child: Icon(
                          icon,
                          key: ValueKey(icon),
                          color: fg,
                          size: size * 0.45,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}