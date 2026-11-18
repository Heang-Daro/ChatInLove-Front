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
import 'package:love_in_chat/service/CallOverlayController.dart';
import 'package:love_in_chat/service/CallRingtoneService.dart';
import 'package:love_in_chat/service/CallSignalingService.dart';
import 'HomeScreen.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Design tokens
// ─────────────────────────────────────────────────────────────────────────────

class _C {
  static final Color brand = Colors.pinkAccent.shade400;
  static const Color bg = Color(0xFF0D090C);
  static const Color surface = Color(0xFF241820);
  static const Color danger = Color(0xFFE53935);
  static const Color online = Color(0xFF4CD964);
}

String _initial(String name) =>
    name.trim().isNotEmpty ? name.trim()[0].toUpperCase() : '?';

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
  static const _ringTimeout = Duration(seconds: 45);

  final _localRenderer = RTCVideoRenderer();
  final _remoteRenderer = RTCVideoRenderer();

  StreamSubscription? _remoteSub;
  StreamSubscription? _localSub;
  StreamSubscription? _endedSub;

  AuthProvider? _auth;
  ConversationProvider? _convos;

  bool _muted = false;
  late bool _cameraOff;
  bool _speakerOn = true;
  bool _connected = false;
  bool _ringing = true;
  bool _messageSent = false;
  bool _leaving = false;
  bool _showUi = true;
  bool _minimized = false;

  bool get _isCaller => widget.incomingOffer == null;

  bool get _hasActiveVideo {
    if (!_connected) return false;
    final remoteTracks = _remoteRenderer.srcObject?.getVideoTracks() ?? [];
    final remoteVideoActive =
        remoteTracks.isNotEmpty && remoteTracks.any((t) => t.enabled);
    return !_cameraOff || remoteVideoActive;
  }

  Duration _elapsed = Duration.zero;
  Timer? _timer;
  Timer? _ringTimer;
  Timer? _hideTimer;

  // ── Call summary message ─────────────────────────────────────────────────

  String _callContent(String outcome) {
    final kind = widget.isVideo ? 'VIDEO' : 'AUDIO';
    return '$kind:$outcome';
  }

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
    if (_messageSent || !_isCaller) return;
    if (_auth == null || _convos == null) return;

    _messageSent = true;
    try {
      await _convos!.sendMessage(
        _auth!,
        widget.conversationId,
        _callContent(outcome),
        type: app_msg.MessageType.CALL,
      );
    } catch (e) {
      debugPrint('[CallScreen] could not send call message: $e');
    }
  }

  // ── Minimize / Expand ────────────────────────────────────────────────────

  void _minimizeCall() {
    if (_minimized || _leaving) return;
    HapticFeedback.lightImpact();
    CallOverlayController.isMinimized = true;
    setState(() => _minimized = true);
  }

  void _expandCall() {
    if (!_minimized) return;
    HapticFeedback.selectionClick();
    CallOverlayController.isMinimized = false;
    setState(() {
      _minimized = false;
      _showUi = true;
    });
    _scheduleHide();
  }

  // ── Lifecycle ────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _cameraOff = !widget.isVideo;
    try {
      _auth = context.read<AuthProvider>();
      _convos = context.read<ConversationProvider>();
    } catch (e) {
      debugPrint('[CallScreen] Provider lookup skipped in overlay: $e');
    }
    _initCall();
  }

  Future<void> _onRemoteStreamReady(MediaStream stream) async {
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
  }

  Future<void> _initCall() async {
    unawaited(CallRingtoneService.stop());

    await _localRenderer.initialize();
    await _remoteRenderer.initialize();
    if (!mounted) return;

    final sig = widget.signalingService;

    // ភ្ជាប់ Stream Listeners
    _remoteSub = sig.onRemoteStream.stream.listen(_onRemoteStreamReady);

    _localSub = sig.onLocalStream.stream.listen((stream) {
      if (!mounted) return;
      setState(() => _localRenderer.srcObject = stream);
    });

    _endedSub = sig.onCallEnded.stream.listen((type) async {
      _ringTimer?.cancel();
      if (_connected) {
        await _sendCallMessage(_durationLabel);
      } else {
        await _sendCallMessage(
          type == SignalType.callReject ? 'REJECTED' : 'MISSED',
        );
      }
      _leave();
    });

    // ពិនិត្យមើលថាតើ Stream មានរួចហើយឬនៅ (ការពារ Race Condition)
    if (sig.latestLocalStream != null) {
      _localRenderer.srcObject = sig.latestLocalStream;
    }
    if (sig.latestRemoteStream != null) {
      await _onRemoteStreamReady(sig.latestRemoteStream!);
    }

    try {
      await Helper.setSpeakerphoneOn(true);
    } catch (e) {
      debugPrint('[CallScreen] setSpeakerphoneOn error: $e');
    }
    if (!mounted) return;

    try {
      if (_isCaller) {
        await CallRingtoneService.playRingback();
        _ringTimer = Timer(_ringTimeout, _onRingTimeout);

        await sig.startCall(
          remoteUserId: widget.remoteUserId,
          conversationId: widget.conversationId,
          video: widget.isVideo,
        );
      } else {
        // រង់ចាំ STOMP ភ្ជាប់រួចរាល់ (អតិបរមា 3 វិនាទី) ករណី Activity ទើប Resume
        for (int i = 0; i < 30; i++) {
          if (sig.stomp.isConnected) break;
          await Future.delayed(const Duration(milliseconds: 100));
        }

        await sig.answerCall(
          offerMsg: widget.incomingOffer!,
          video: widget.isVideo,
        );
      }
    } catch (e) {
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

  Future<void> _onRingTimeout() async {
    if (_connected || _leaving) return;
    await _hangup(outcomeOverride: 'MISSED');
  }

  Future<void> _leave() async {
    if (_leaving) return;
    _leaving = true;

    _timer?.cancel();
    _ringTimer?.cancel();
    _hideTimer?.cancel();

    try {
      _convos?.markCallEnded();
    } catch (_) {}

    if (CallOverlayController.isShowing) {
      CallOverlayController.closeCall();
      return;
    }

    if (!mounted) return;
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

  Future<void> _onBack() async {
    if (_connected) {
      _minimizeCall();
      return;
    }
    _hangup();
  }

  // ── Auto-hiding UI ───────────────────────────────────────────────────────

  void _scheduleHide() {
    _hideTimer?.cancel();
    if (!_hasActiveVideo) return;
    _hideTimer = Timer(const Duration(seconds: 5), () {
      if (mounted && _hasActiveVideo) {
        setState(() => _showUi = false);
      }
    });
  }

  void _toggleUi() {
    if (!_hasActiveVideo) return;
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

  Future<void> _toggleCamera() async {
    _touchUi();
    final nextCameraOff = !_cameraOff;

    final hasVideoTrack =
    (_localRenderer.srcObject?.getVideoTracks().isNotEmpty ?? false);

    if (!nextCameraOff && !hasVideoTrack) {
      try {
        await widget.signalingService.enableVideo();
      } catch (e) {
        debugPrint('[CallScreen] enableVideo error: $e');
        return;
      }
    } else {
      widget.signalingService.toggleCamera(nextCameraOff);
    }

    if (!mounted) return;
    setState(() {
      _cameraOff = nextCameraOff;
      if (nextCameraOff) _showUi = true;
    });
    if (!nextCameraOff) _scheduleHide();
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
    final liveVideo = _hasActiveVideo;

    if (_minimized) {
      return _FloatingCallBubble(
        remoteName: widget.remoteName,
        isVideo: liveVideo,
        connected: _connected,
        statusLabel: _statusLabel,
        remoteRenderer: _remoteRenderer,
        hasRemoteVideo: liveVideo && _remoteRenderer.srcObject != null,
        onExpand: _expandCall,
        onHangup: () {
          HapticFeedback.mediumImpact();
          _hangup();
        },
      );
    }

    final pad = MediaQuery.of(context).padding;
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

            // Stage
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _toggleUi,
                child: _buildStage(pad.top + 84, pad.bottom + 160),
              ),
            ),

            // Bottom scrim
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

            // Header (Live Video Call)
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
                    onMinimize: _minimizeCall,
                  ),
                ),
              ),

            // ប៊ូតុង Minimize សម្រាប់ Voice Call ឬពេលកំពុង Ringing
            if (!liveVideo)
              Positioned(
                top: pad.top + 10,
                left: 16,
                child: IconButton(
                  onPressed: _minimizeCall,
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.white.withValues(alpha: 0.14),
                  ),
                  icon: const Icon(
                    Icons.picture_in_picture_alt_rounded,
                    color: Colors.white,
                    size: 20,
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
    if (_hasActiveVideo) {
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

    final showPreview = !_cameraOff && _localRenderer.srcObject != null;

    return Stack(
      fit: StackFit.expand,
      children: [
        if (showPreview) ...[
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
// Floating Call Bubble (Minimized State)
// ─────────────────────────────────────────────────────────────────────────────

class _FloatingCallBubble extends StatefulWidget {
  final String remoteName;
  final bool isVideo;
  final bool connected;
  final String statusLabel;
  final RTCVideoRenderer remoteRenderer;
  final bool hasRemoteVideo;
  final VoidCallback onExpand;
  final VoidCallback onHangup;

  const _FloatingCallBubble({
    required this.remoteName,
    required this.isVideo,
    required this.connected,
    required this.statusLabel,
    required this.remoteRenderer,
    required this.hasRemoteVideo,
    required this.onExpand,
    required this.onHangup,
  });

  @override
  State<_FloatingCallBubble> createState() => _FloatingCallBubbleState();
}

class _FloatingCallBubbleState extends State<_FloatingCallBubble> {
  double _left = 16;
  double _top = 90;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final w = widget.isVideo ? 124.0 : 168.0;
    final h = widget.isVideo ? 176.0 : 68.0;
    final initial = _initial(widget.remoteName);

    return Stack(
      children: [
        Positioned(
          left: _left.clamp(12.0, size.width - w - 12.0),
          top: _top.clamp(40.0, size.height - h - 40.0),
          child: Material(
            color: Colors.transparent,
            child: GestureDetector(
              onTap: widget.onExpand,
              onPanUpdate: (d) {
                setState(() {
                  _left += d.delta.dx;
                  _top += d.delta.dy;
                });
              },
              onPanEnd: (_) {
                setState(() {
                  _left = (_left + w / 2 > size.width / 2)
                      ? size.width - w - 12.0
                      : 12.0;
                });
              },
              child: Container(
                width: w,
                height: h,
                decoration: BoxDecoration(
                  color: const Color(0xFF1E131A),
                  borderRadius: BorderRadius.circular(widget.isVideo ? 18 : 34),
                  border: Border.all(color: _C.brand, width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.55),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(widget.isVideo ? 16 : 32),
                  child: widget.isVideo
                      ? Stack(
                    fit: StackFit.expand,
                    children: [
                      if (widget.hasRemoteVideo)
                        RTCVideoView(
                          widget.remoteRenderer,
                          objectFit: RTCVideoViewObjectFit
                              .RTCVideoViewObjectFitCover,
                        )
                      else
                        Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            CircleAvatar(
                              radius: 26,
                              backgroundColor: _C.brand,
                              child: Text(
                                initial,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8),
                              child: Text(
                                widget.statusLabel,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                            const SizedBox(height: 24),
                          ],
                        ),
                      Positioned(
                        bottom: 6,
                        left: 0,
                        right: 0,
                        child: Row(
                          mainAxisAlignment:
                          MainAxisAlignment.spaceEvenly,
                          children: [
                            _miniBtn(
                              icon: Icons.open_in_full_rounded,
                              color: Colors.black54,
                              onTap: widget.onExpand,
                            ),
                            _miniBtn(
                              icon: Icons.call_end_rounded,
                              color: _C.danger,
                              onTap: widget.onHangup,
                            ),
                          ],
                        ),
                      ),
                    ],
                  )
                      : Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 20,
                          backgroundColor: _C.brand,
                          child: Text(
                            initial,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.remoteName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                widget.statusLabel,
                                style: TextStyle(
                                  color: widget.connected
                                      ? _C.online
                                      : Colors.white70,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _miniBtn({
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        child: Icon(icon, color: Colors.white, size: 15),
      ),
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
  final VoidCallback onMinimize;

  const _VideoHeader({
    required this.name,
    required this.status,
    required this.muted,
    required this.onMinimize,
  });

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;

    return Container(
      padding: EdgeInsets.fromLTRB(16, top + 10, 20, 32),
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
          IconButton(
            onPressed: onMinimize,
            style: IconButton.styleFrom(
              backgroundColor: Colors.white.withValues(alpha: 0.14),
            ),
            icon: const Icon(
              Icons.picture_in_picture_alt_rounded,
              color: Colors.white,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
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
  final VoidCallback onMute;
  final VoidCallback onSpeaker;
  final VoidCallback onCameraToggle;
  final VoidCallback onSwitchCamera;
  final VoidCallback onHangup;

  const _ControlBar({
    required this.muted,
    required this.cameraOff,
    required this.speakerOn,
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
      _ControlButton(
        icon: speakerOn ? Icons.volume_up_rounded : Icons.hearing_rounded,
        label: speakerOn ? 'Speaker' : 'Earpiece',
        active: speakerOn,
        onTap: onSpeaker,
      ),
      _ControlButton(
        icon: cameraOff ? Icons.videocam_off_rounded : Icons.videocam_rounded,
        label: cameraOff ? 'Start cam' : 'Stop cam',
        active: cameraOff,
        onTap: onCameraToggle,
      ),
      if (!cameraOff)
        _ControlButton(
          icon: Icons.flip_camera_ios_rounded,
          label: 'Flip',
          onTap: onSwitchCamera,
        ),
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
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
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
                if (i > 0) const SizedBox(width: 12),
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
  final bool active;
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
            width: 58,
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