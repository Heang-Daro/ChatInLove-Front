import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:love_in_chat/service/CallKitService.dart';
import 'package:love_in_chat/service/CallOverlayController.dart';
import 'package:love_in_chat/service/CallRingtoneService.dart';
import 'package:love_in_chat/service/CallSignalingService.dart';

class _C {
  static final Color brand = Colors.pinkAccent.shade400;
  static const Color bg = Color(0xFF0D090C);
  static const Color danger = Color(0xFFE53935);
}

class IncomingCallScreen extends StatefulWidget {
  final Map<String, dynamic> offer;
  final String callerName;
  final CallSignalingService signalingService;
  final Stream<void>? cancelStream;

  const IncomingCallScreen({
    super.key,
    required this.offer,
    required this.callerName,
    required this.signalingService,
    this.cancelStream,
  });

  @override
  State<IncomingCallScreen> createState() => _IncomingCallScreenState();
}

class _IncomingCallScreenState extends State<IncomingCallScreen> {
  bool _handled = false;
  StreamSubscription<void>? _cancelSub;

  bool get _isVideo =>
      widget.offer['callType']?.toString().toUpperCase() == 'VIDEO';

  String get _sessionId =>
      widget.offer['callSessionId']?.toString() ??
          widget.offer['callId']?.toString() ??
          '';

  Map<String, dynamic> _deepNormalizeMap(dynamic raw) {
    if (raw is Map) {
      return raw.map((k, v) => MapEntry(
        k.toString(),
        v is Map ? _deepNormalizeMap(v) : v,
      ));
    }
    return <String, dynamic>{};
  }

  @override
  void initState() {
    super.initState();
    CallRingtoneService.playRingtone();

    _cancelSub = widget.cancelStream?.listen((_) {
      if (_handled || !mounted) return;
      _handled = true;
      CallRingtoneService.stop();
      Navigator.of(context).pop();
    });
  }

  @override
  void dispose() {
    _cancelSub?.cancel();
    CallRingtoneService.stop();
    super.dispose();
  }

  void _decline() {
    if (_handled) return;
    _handled = true;
    HapticFeedback.mediumImpact();
    CallRingtoneService.stop();

    final offer = _deepNormalizeMap(widget.offer);
    final signaling = widget.signalingService;
    final sessionId = _sessionId;

    if (mounted) Navigator.of(context).pop();

    unawaited(() async {
      final ok = await CallKitService.postCallAction('reject', sessionId);
      if (!ok) signaling.rejectCall(offer);
    }());
  }

  void _accept() {
    if (_handled) return;
    _handled = true;
    HapticFeedback.mediumImpact();
    CallRingtoneService.stop();

    final normalizedOffer = _deepNormalizeMap(widget.offer);
    unawaited(CallKitService.postCallAction('accept', _sessionId));

    // បិទ IncomingCallScreen ជាមុនសិន ដើម្បីត្រឡប់ទៅ HomeScreen / ChatScreen
    final rootCtx = navigatorKey.currentContext ?? context;
    if (mounted) Navigator.of(context).pop();

    // បើក CallScreen ជា Overlay លើ App (ពេល Minimize នឹងឃើញ Screen ខាងក្រោមច្បាស់ 100%)
    CallOverlayController.showCall(
      context: rootCtx,
      remoteUserId: normalizedOffer['fromUserId']?.toString() ?? '',
      remoteName: widget.callerName,
      conversationId: normalizedOffer['conversationId']?.toString() ?? '',
      isVideo: _isVideo,
      incomingOffer: normalizedOffer,
      signalingService: widget.signalingService,
    );
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.callerName;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _decline();
      },
      child: Scaffold(
        backgroundColor: _C.bg,
        body: Stack(
          fit: StackFit.expand,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(0, -0.35),
                  radius: 1.3,
                  colors: [_C.brand.withValues(alpha: 0.32), _C.bg],
                ),
              ),
            ),
            SafeArea(
              child: Column(
                children: [
                  const SizedBox(height: 28),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                            _isVideo
                                ? Icons.videocam_rounded
                                : Icons.call_rounded,
                            color: Colors.white,
                            size: 16),
                        const SizedBox(width: 8),
                        Text(
                          _isVideo
                              ? 'Incoming video call'
                              : 'Incoming voice call',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _RippleAvatar(name: name, size: 128),
                          const SizedBox(height: 28),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 32),
                            child: Text(
                              name,
                              maxLines: 2,
                              textAlign: TextAlign.center,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 30,
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.2,
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'is calling you…',
                            style:
                            TextStyle(color: Colors.white70, fontSize: 16),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(40, 0, 40, 48),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _CallButton(
                          icon: Icons.call_end_rounded,
                          label: 'Decline',
                          color: _C.danger,
                          onTap: _decline,
                        ),
                        _CallButton(
                          icon: _isVideo
                              ? Icons.videocam_rounded
                              : Icons.call_rounded,
                          label: 'Accept',
                          color: _C.brand,
                          pulse: true,
                          onTap: _accept,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RippleAvatar extends StatefulWidget {
  final String name;
  final double size;

  const _RippleAvatar({required this.name, required this.size});

  @override
  State<_RippleAvatar> createState() => _RippleAvatarState();
}

class _RippleAvatarState extends State<_RippleAvatar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.size;
    final box = size * 2.1;
    final initial = widget.name.trim().isNotEmpty
        ? widget.name.trim()[0].toUpperCase()
        : '?';

    return SizedBox(
      width: box,
      height: box,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          return Stack(
            alignment: Alignment.center,
            children: [
              for (var i = 0; i < 3; i++) _ring((_c.value + i / 3) % 1.0),
              Container(
                width: size + 14,
                height: size + 14,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.35),
                    width: 3,
                  ),
                ),
              ),
              CircleAvatar(
                radius: size / 2,
                backgroundColor: _C.brand,
                child: Text(
                  initial,
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
        decoration: BoxDecoration(shape: BoxShape.circle, color: _C.brand),
      ),
    );
  }
}

class _CallButton extends StatefulWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  final bool pulse;

  const _CallButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
    this.pulse = false,
  });

  @override
  State<_CallButton> createState() => _CallButtonState();
}

class _CallButtonState extends State<_CallButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  @override
  void initState() {
    super.initState();
    if (widget.pulse) _c.repeat(reverse: true);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scale = widget.pulse
        ? Tween<double>(begin: 1.0, end: 1.08)
        .animate(CurvedAnimation(parent: _c, curve: Curves.easeInOut))
        : const AlwaysStoppedAnimation<double>(1.0);

    return Semantics(
      button: true,
      label: widget.label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ScaleTransition(
              scale: scale,
              child: Container(
                width: 76,
                height: 76,
                decoration: BoxDecoration(
                  color: widget.color,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: widget.color.withValues(alpha: 0.5),
                      blurRadius: 18,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Icon(widget.icon, color: Colors.white, size: 34),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              widget.label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}