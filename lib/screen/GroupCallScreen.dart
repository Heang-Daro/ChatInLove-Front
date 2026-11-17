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
import 'package:love_in_chat/service/CallRingtoneService.dart';
import 'package:love_in_chat/service/GroupCallSignalingService.dart';
import 'package:love_in_chat/service/StompService.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Design tokens
// ─────────────────────────────────────────────────────────────────────────────

class _C {
  /// Brand colour: pinkAccent 400.
  static final Color brand = Colors.pinkAccent.shade400;
  static const Color bg = Color(0xFF0D090C);
  static const Color surface = Color(0xFF241820);
  static const Color danger = Color(0xFFE53935);

  static const List<Color> avatarPalette = [
    Color(0xFFF50057), // pinkAccent 400
    Color(0xFF7C4DFF),
    Color(0xFFFF6E40),
    Color(0xFF00BFA5),
    Color(0xFF448AFF),
    Color(0xFFFFAB40),
  ];

  static Color avatarColor(String name) {
    final sum = name.codeUnits.fold<int>(0, (a, b) => a + b);
    return avatarPalette[sum % avatarPalette.length];
  }
}

String _initial(String name) =>
    name.trim().isNotEmpty ? name.trim()[0].toUpperCase() : '?';

// ─────────────────────────────────────────────────────────────────────────────
// Screen
// ─────────────────────────────────────────────────────────────────────────────

/// Full-screen group call screen.
///
/// [callerUserId] is non-null when this device is the **callee** joining an
/// existing call. When null, this device is the **caller** starting a new call.
class GroupCallScreen extends StatefulWidget {
  final String conversationId;
  final String groupName;
  final bool isVideo;
  final String localUserId;
  final String? callerUserId; // null = we are the caller
  final String? callerUsername; // display name for the caller (callee path)
  final List<String> memberUserIds;

  const GroupCallScreen({
    super.key,
    required this.conversationId,
    required this.groupName,
    required this.isVideo,
    required this.localUserId,
    this.callerUserId,
    this.callerUsername,
    this.memberUserIds = const [],
  });

  @override
  State<GroupCallScreen> createState() => _GroupCallScreenState();
}

class _GroupCallScreenState extends State<GroupCallScreen> {
  late final GroupCallSignalingService _sig;
  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();

  late final StreamSubscription _changeSub;
  late final StreamSubscription _localSub;
  late final StreamSubscription _declinedSub;

  bool _muted = false;
  bool _camOff = false;
  bool _joined = false; // true once at least one peer connects
  bool _msgSent = false;
  bool _leaving = false; // guards a double teardown
  bool _showUi = true; // header + controls (auto-hide in video calls)

  Duration _elapsed = Duration.zero;
  Timer? _timer;
  Timer? _hideTimer;

  bool get _isCaller => widget.callerUserId == null;

  @override
  void initState() {
    super.initState();
    _localRenderer.initialize();

    _sig = GroupCallSignalingService(
      stomp: StompService(),
      localUserId: widget.localUserId,
      conversationId: widget.conversationId,
      video: widget.isVideo,
      memberUserIds: widget.memberUserIds,
    );

    _changeSub = _sig.onParticipantsChanged.stream.listen((_) {
      if (!mounted) return;
      setState(() {});
      if (!_joined && _sig.participants.any((p) => p.connected)) {
        _joined = true;
        // Stop ringback/ringtone once first participant connects.
        CallRingtoneService.stop();
        _startTimer();
        _scheduleHide();
      }
      // Nobody left to look at: bring the controls back.
      if (_sig.participants.isEmpty && !_showUi) {
        setState(() => _showUi = true);
      }
    });

    _localSub = _sig.onLocalStream.stream.listen((stream) {
      if (mounted) setState(() => _localRenderer.srcObject = stream);
    });

    // Caller side: a member that taps "Decline" on the incoming-call overlay.
    _declinedSub = _sig.onParticipantDeclined.stream.listen((name) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            backgroundColor: _C.surface,
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 150),
            shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            duration: const Duration(seconds: 2),
            content: Row(
              children: [
                Icon(Icons.call_end_rounded, color: _C.brand, size: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '$name declined the call',
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
        );
    });

    _start();
  }

  Future<void> _start() async {
    if (!_isCaller) {
      // Joiner path: the user already accepted on the incoming-call overlay,
      // so no ringtone here — just ask the caller for an offer.
      await _sig.joinExistingCall(
        callerUserId: widget.callerUserId!,
        callerUsername: widget.callerUsername ?? widget.callerUserId!,
      );
    } else {
      // Caller path: play ringback and broadcast GROUP_CALL_STARTED.
      CallRingtoneService.playRingback();
      await _sig.startCall();
    }
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _elapsed += const Duration(seconds: 1));
    });
  }

  // ── Auto-hiding UI (video calls only) ──────────────────────────────────────

  void _scheduleHide() {
    _hideTimer?.cancel();
    if (!widget.isVideo || !_joined) return;
    _hideTimer = Timer(const Duration(seconds: 5), () {
      if (mounted && _sig.participants.isNotEmpty) {
        setState(() => _showUi = false);
      }
    });
  }

  void _toggleUi() {
    if (!widget.isVideo) return;
    setState(() => _showUi = !_showUi);
    if (_showUi) _scheduleHide();
  }

  /// Any press on a control keeps the controls visible a bit longer.
  void _touchUi() {
    HapticFeedback.lightImpact();
    _scheduleHide();
  }

  // ── Leaving ────────────────────────────────────────────────────────────────

  Future<void> _confirmLeave() async {
    final leave = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _C.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Leave call?',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
        content: const Text(
          'You will be disconnected from this group call.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('Stay', style: TextStyle(color: _C.brand)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: _C.danger),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Leave'),
          ),
        ],
      ),
    );
    if (leave == true && mounted) _leave();
  }

  Future<void> _leave() async {
    if (_leaving) return;
    _leaving = true;
    _timer?.cancel();
    _hideTimer?.cancel();
    // Capture the provider before any await to avoid using BuildContext
    // across an async gap.
    final convos = context.read<ConversationProvider>();
    // Only the caller logs the group call summary message
    if (!_msgSent && _isCaller) {
      _msgSent = true;
      try {
        final auth = context.read<AuthProvider>();
        final kind = widget.isVideo ? 'VIDEO' : 'AUDIO';
        final outcome = _joined ? _elapsedLabel : 'MISSED';
        await convos.sendMessage(auth, widget.conversationId, '$kind:$outcome',
            type: app_msg.MessageType.CALL);
      } catch (_) {}
    }
    await _sig.leave();
    // Allow a new incoming call to be shown once this one is finished.
    convos.markCallEnded();
    if (mounted) Navigator.of(context).pop();
  }

  /// mm:ss (minutes keep counting past 60 so the message format is stable).
  String get _elapsedLabel {
    final m = _elapsed.inMinutes.toString().padLeft(2, '0');
    final s = _elapsed.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  void dispose() {
    _changeSub.cancel();
    _localSub.cancel();
    _declinedSub.cancel();
    _localRenderer.dispose();
    _timer?.cancel();
    _hideTimer?.cancel();
    CallRingtoneService.stop();
    // If the screen was dismissed without pressing the hang-up button,
    // still tear down the peer connections and notify the others.
    if (!_leaving) {
      _leaving = true;
      _sig.leave();
    }
    super.dispose();
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final remotes = _sig.participants;
    final pad = MediaQuery.of(context).padding;
    final topInset = pad.top + 84;
    final bottomInset = pad.bottom + 150;
    final uiVisible = _showUi || !widget.isVideo;

    return PopScope(
      // Back gesture asks for confirmation instead of silently dropping the call.
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmLeave();
      },
      child: Scaffold(
        backgroundColor: _C.bg,
        body: Stack(
          fit: StackFit.expand,
          children: [
            const _Backdrop(),

            // Stage (tap toggles the UI in video calls).
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _toggleUi,
                child: _buildStage(remotes, topInset, bottomInset),
              ),
            ),

            // Header
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: _AutoHide(
                visible: uiVisible,
                hiddenOffset: const Offset(0, -0.4),
                child: _CallHeader(
                  title: widget.groupName,
                  status: _joined
                      ? _elapsedLabel
                      : (_isCaller ? 'Ringing…' : 'Connecting…'),
                  live: _joined,
                  count: remotes.length + 1, // +1 for local
                ),
              ),
            ),

            // Controls
            Positioned(
              left: 0,
              right: 0,
              bottom: pad.bottom + 20,
              child: _AutoHide(
                visible: uiVisible,
                hiddenOffset: const Offset(0, 0.4),
                child: Center(
                  child: _GroupControlBar(
                    muted: _muted,
                    camOff: _camOff,
                    isVideo: widget.isVideo,
                    onMute: () {
                      _touchUi();
                      setState(() => _muted = !_muted);
                      _sig.toggleMute(_muted);
                    },
                    onCamToggle: () {
                      _touchUi();
                      setState(() => _camOff = !_camOff);
                      _sig.toggleCamera(_camOff);
                    },
                    onSwitchCam: () {
                      _touchUi();
                      _sig.switchCamera();
                    },
                    onLeave: () {
                      HapticFeedback.mediumImpact();
                      _leave();
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

  Widget _buildStage(
      List<GroupParticipant> remotes,
      double topInset,
      double bottomInset,
      ) {
    // Audio call: avatars only.
    if (!widget.isVideo) {
      return Padding(
        padding: EdgeInsets.only(top: topInset, bottom: bottomInset),
        child: _AudioStage(localMuted: _muted, participants: remotes),
      );
    }

    _ParticipantTile local({required bool compact}) => _ParticipantTile(
      renderer: _localRenderer,
      name: 'You',
      isLocal: true,
      showVideo: !_camOff,
      connected: true,
      muted: _muted,
      compact: compact,
      radius: compact ? 16 : 0,
    );

    // Alone: full-screen self preview (like FaceTime / WhatsApp).
    if (remotes.isEmpty) return local(compact: false);

    // 1:1: remote full-bleed + draggable self-view.
    if (remotes.length == 1) {
      final p = remotes.first;
      return _PipStage(
        topInset: topInset,
        bottomInset: bottomInset,
        remote: ({required bool compact}) => _ParticipantTile(
          key: ObjectKey(p),
          renderer: p.renderer,
          name: p.username,
          isLocal: false,
          showVideo: p.connected,
          connected: p.connected,
          compact: compact,
          radius: compact ? 16 : 0,
        ),
        local: local,
      );
    }

    // Group: adaptive grid.
    return Padding(
      padding: EdgeInsets.fromLTRB(4, topInset - 8, 4, bottomInset - 8),
      child: _VideoGrid(
        tiles: [
          local(compact: false).copyWith(radius: 18),
          for (final p in remotes)
            _ParticipantTile(
              key: ObjectKey(p),
              renderer: p.renderer,
              name: p.username,
              isLocal: false,
              showVideo: p.connected,
              connected: p.connected,
              radius: 18,
            ),
        ],
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
          center: const Alignment(0, -0.85),
          radius: 1.3,
          colors: [_C.brand.withValues(alpha: 0.22), _C.bg],
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
// Header
// ─────────────────────────────────────────────────────────────────────────────

class _CallHeader extends StatelessWidget {
  final String title;
  final String status;
  final bool live;
  final int count;

  const _CallHeader({
    required this.title,
    required this.status,
    required this.live,
    required this.count,
  });

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;

    return Container(
      padding: EdgeInsets.fromLTRB(20, top + 10, 16, 28),
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
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.2,
                  ),
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    if (live) ...[
                      const _PulseDot(color: Color(0xFF4CD964)),
                      const SizedBox(width: 6),
                    ],
                    Text(
                      status,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.people_alt_rounded,
                    color: Colors.white, size: 16),
                const SizedBox(width: 6),
                Text(
                  '$count',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Video layouts
// ─────────────────────────────────────────────────────────────────────────────

/// Adaptive grid: tiles fill the whole area (no wasted space, no scrolling).
class _VideoGrid extends StatelessWidget {
  final List<Widget> tiles;
  const _VideoGrid({required this.tiles});

  static int _columns(int n, bool landscape) {
    if (n <= 1) return 1;
    if (n == 2) return landscape ? 2 : 1;
    if (n <= 4) return 2;
    if (n <= 6) return landscape ? 3 : 2;
    return 3;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final n = tiles.length;
        final cols = _columns(n, c.maxWidth > c.maxHeight);
        final rows = (n / cols).ceil();

        return Column(
          children: [
            for (var r = 0; r < rows; r++)
              Expanded(
                child: Row(
                  children: [
                    for (var i = r * cols; i < math.min(n, (r + 1) * cols); i++)
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.all(3),
                          child: tiles[i],
                        ),
                      ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}

typedef _TileBuilder = _ParticipantTile Function({required bool compact});

/// 1:1 layout: the other person full-screen, a small draggable self-view that
/// snaps to the corners. Tap the small view to swap.
class _PipStage extends StatefulWidget {
  final double topInset;
  final double bottomInset;
  final _TileBuilder remote;
  final _TileBuilder local;

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
    final main = _swapped ? widget.local(compact: false) : widget.remote(compact: false);
    final pip = _swapped ? widget.remote(compact: true) : widget.local(compact: true);

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
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.45),
                        blurRadius: 14,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: pip,
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
// Participant tile (video)
// ─────────────────────────────────────────────────────────────────────────────

class _ParticipantTile extends StatelessWidget {
  final RTCVideoRenderer renderer;
  final String name;
  final bool isLocal;
  final bool showVideo; // render the stream (otherwise an avatar is shown)
  final bool connected;
  final bool muted;
  final bool compact;
  final double radius;

  const _ParticipantTile({
    super.key,
    required this.renderer,
    required this.name,
    required this.isLocal,
    required this.showVideo,
    required this.connected,
    this.muted = false,
    this.compact = false,
    this.radius = 16,
  });

  _ParticipantTile copyWith({double? radius}) => _ParticipantTile(
    key: key,
    renderer: renderer,
    name: name,
    isLocal: isLocal,
    showVideo: showVideo,
    connected: connected,
    muted: muted,
    compact: compact,
    radius: radius ?? this.radius,
  );

  @override
  Widget build(BuildContext context) {
    final borderRadius = BorderRadius.circular(radius);
    final highlight = isLocal && compact;

    return Container(
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        border: radius == 0
            ? null
            : Border.all(
          color: highlight ? _C.brand : Colors.white12,
          width: highlight ? 2 : 1,
        ),
      ),
      child: ClipRRect(
        borderRadius: borderRadius,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (showVideo && connected)
              RepaintBoundary(
                child: RTCVideoView(
                  renderer,
                  mirror: isLocal,
                  objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                ),
              )
            else
              _AvatarPlaceholder(
                name: name,
                connected: connected,
                compact: compact,
              ),

            // Name label
            Positioned(
              left: compact ? 6 : 10,
              bottom: compact ? 6 : 10,
              right: compact ? 6 : 10,
              child: Align(
                alignment: Alignment.bottomLeft,
                child: _NameChip(name: name, muted: muted, compact: compact),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AvatarPlaceholder extends StatelessWidget {
  final String name;
  final bool connected;
  final bool compact;

  const _AvatarPlaceholder({
    required this.name,
    required this.connected,
    required this.compact,
  });

  @override
  Widget build(BuildContext context) {
    final color = _C.avatarColor(name);

    return LayoutBuilder(
      builder: (context, c) {
        final shortest = math.min(c.maxWidth, c.maxHeight);
        final radius = (shortest * 0.2).clamp(20.0, 52.0).toDouble();

        return Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [color.withValues(alpha: 0.35), _C.surface],
            ),
          ),
          alignment: Alignment.center,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                alignment: Alignment.center,
                children: [
                  CircleAvatar(
                    radius: radius,
                    backgroundColor: color,
                    child: Text(
                      _initial(name),
                      style: TextStyle(
                        fontSize: radius * 0.9,
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  if (!connected)
                    SizedBox(
                      width: radius * 2 + 12,
                      height: radius * 2 + 12,
                      child: const CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: Colors.white70,
                      ),
                    ),
                ],
              ),
              if (!connected && !compact) ...[
                const SizedBox(height: 14),
                const Text(
                  'Connecting…',
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _NameChip extends StatelessWidget {
  final String name;
  final bool muted;
  final bool compact;

  const _NameChip({
    required this.name,
    required this.muted,
    required this.compact,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 6 : 9,
        vertical: compact ? 2 : 4,
      ),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (muted) ...[
            Icon(Icons.mic_off_rounded,
                color: _C.brand, size: compact ? 11 : 14),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white,
                fontSize: compact ? 10 : 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Audio call stage
// ─────────────────────────────────────────────────────────────────────────────

class _AudioStage extends StatelessWidget {
  final bool localMuted;
  final List<GroupParticipant> participants;

  const _AudioStage({required this.localMuted, required this.participants});

  @override
  Widget build(BuildContext context) {
    final n = participants.length + 1;
    final size = n <= 2 ? 112.0 : (n <= 4 ? 92.0 : 72.0);

    return LayoutBuilder(
      builder: (context, c) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: c.maxHeight),
          child: Center(
            child: Wrap(
              alignment: WrapAlignment.center,
              runAlignment: WrapAlignment.center,
              spacing: 24,
              runSpacing: 28,
              children: [
                _AudioCard(
                  name: 'You',
                  connected: true,
                  muted: localMuted,
                  size: size,
                ),
                for (final p in participants)
                  _AudioCard(
                    key: ObjectKey(p),
                    name: p.username,
                    connected: p.connected,
                    muted: false,
                    size: size,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AudioCard extends StatelessWidget {
  final String name;
  final bool connected;
  final bool muted;
  final double size;

  const _AudioCard({
    super.key,
    required this.name,
    required this.connected,
    required this.muted,
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    final color = _C.avatarColor(name);

    return SizedBox(
      width: size + 28,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: size + 14,
            height: size + 14,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Ring: solid when connected, spinning while connecting.
                if (connected)
                  Container(
                    width: size + 12,
                    height: size + 12,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: _C.brand, width: 2.5),
                    ),
                  )
                else
                  SizedBox(
                    width: size + 12,
                    height: size + 12,
                    child: const CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: Colors.white54,
                    ),
                  ),
                CircleAvatar(
                  radius: size / 2,
                  backgroundColor: color,
                  child: Text(
                    _initial(name),
                    style: TextStyle(
                      fontSize: size * 0.4,
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                if (muted)
                  Positioned(
                    right: 2,
                    bottom: 2,
                    child: Container(
                      padding: const EdgeInsets.all(5),
                      decoration: BoxDecoration(
                        color: _C.surface,
                        shape: BoxShape.circle,
                        border: Border.all(color: _C.bg, width: 2),
                      ),
                      child: Icon(Icons.mic_off_rounded,
                          color: _C.brand, size: 14),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (!connected)
            const Padding(
              padding: EdgeInsets.only(top: 2),
              child: Text('Connecting…',
                  style: TextStyle(color: Colors.white54, fontSize: 11)),
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Control bar
// ─────────────────────────────────────────────────────────────────────────────

class _GroupControlBar extends StatelessWidget {
  final bool muted;
  final bool camOff;
  final bool isVideo;
  final VoidCallback onMute;
  final VoidCallback onCamToggle;
  final VoidCallback onSwitchCam;
  final VoidCallback onLeave;

  const _GroupControlBar({
    required this.muted,
    required this.camOff,
    required this.isVideo,
    required this.onMute,
    required this.onCamToggle,
    required this.onSwitchCam,
    required this.onLeave,
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
      if (isVideo) ...[
        _ControlButton(
          icon: camOff ? Icons.videocam_off_rounded : Icons.videocam_rounded,
          label: camOff ? 'Start cam' : 'Stop cam',
          active: camOff,
          onTap: onCamToggle,
        ),
        _ControlButton(
          icon: Icons.flip_camera_ios_rounded,
          label: 'Flip',
          enabled: !camOff,
          onTap: onSwitchCam,
        ),
      ],
      _ControlButton(
        icon: Icons.call_end_rounded,
        label: 'Leave',
        danger: true,
        size: 64,
        onTap: onLeave,
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
  final bool active; // toggled on (e.g. muted)
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