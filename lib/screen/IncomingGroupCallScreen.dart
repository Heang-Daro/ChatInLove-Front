import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:love_in_chat/provider/ConversationProvider.dart';
import 'package:love_in_chat/service/CallKitService.dart';
import 'package:love_in_chat/service/CallRingtoneService.dart';
import 'package:love_in_chat/service/StompService.dart';
import 'GroupCallScreen.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Design tokens
// ─────────────────────────────────────────────────────────────────────────────

class _C {
  /// Brand colour: pinkAccent 400.
  static final Color brand = Colors.pinkAccent.shade400;
  static const Color bg = Color(0xFF0D090C);
  static const Color danger = Color(0xFFE53935);
}

/// Ringing overlay shown to group members when a group call starts.
///
/// Members see the caller's name and can choose to **Join** or **Decline**.
/// Only after tapping Join is [GroupCallScreen] pushed (which then sends
/// JOIN_CALL and starts the WebRTC peer connection).
class IncomingGroupCallScreen extends StatefulWidget {
  final String conversationId;
  final String groupName;
  final bool isVideo;
  final String localUserId;
  final String callerUserId;
  final String callerUsername;
  final String localUsername;

  const IncomingGroupCallScreen({
    super.key,
    required this.conversationId,
    required this.groupName,
    required this.isVideo,
    required this.localUserId,
    required this.callerUserId,
    required this.callerUsername,
    this.localUsername = '',
  });

  @override
  State<IncomingGroupCallScreen> createState() =>
      _IncomingGroupCallScreenState();
}

class _IncomingGroupCallScreenState extends State<IncomingGroupCallScreen> {
  /// True once the user tapped "Join" — the overlay then hands over to
  /// [GroupCallScreen] which owns the ringtone from that point on.
  bool _joined = false;

  /// Guards against double taps (Join + Decline, or Decline twice).
  bool _handled = false;

  late final ConversationProvider _convos;

  @override
  void initState() {
    super.initState();
    _convos = context.read<ConversationProvider>();
    CallRingtoneService.playRingtone();
  }

  @override
  void dispose() {
    if (!_joined) {
      CallRingtoneService.stop();
      CallKitService.endAllCalls();
      _convos.markCallEnded();
    }
    super.dispose();
  }

  void _join() {
    if (_handled) return;
    _handled = true;
    _joined = true;
    HapticFeedback.mediumImpact();
    CallRingtoneService.stop();
    CallKitService.endAllCalls();
    Navigator.of(context).pushReplacement(MaterialPageRoute(
      builder: (_) => GroupCallScreen(
        conversationId: widget.conversationId,
        groupName: widget.groupName,
        isVideo: widget.isVideo,
        localUserId: widget.localUserId,
        callerUserId: widget.callerUserId,
        callerUsername: widget.callerUsername,
      ),
    ));
  }

  void _decline() {
    if (_handled) return;
    _handled = true;
    HapticFeedback.mediumImpact();
    CallRingtoneService.stop();
    CallKitService.endAllCalls();
    try {
      StompService().sendSignal(widget.callerUserId, {
        'type': 'DECLINE_CALL',
        'fromUserId': widget.localUserId,
        'conversationId': widget.conversationId,
        'isGroup': true,
        'declinedUsername': widget.localUsername.isNotEmpty
            ? widget.localUsername
            : widget.localUserId,
      });
    } catch (_) {
      // Ignore signaling failures — declining must always work offline.
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final kind = widget.isVideo ? 'video' : 'voice';

    // System back = decline, so the caller sees "declined" instead of nothing.
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
            // Soft pink glow behind the group avatar.
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

                  // Call type pill
                  Container(
                    padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          widget.isVideo
                              ? Icons.videocam_rounded
                              : Icons.call_rounded,
                          color: Colors.white,
                          size: 16,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Group $kind call',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Group + who started it
                  Expanded(
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const _RippleAvatar(size: 128),
                          const SizedBox(height: 28),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 32),
                            child: Text(
                              widget.groupName,
                              maxLines: 2,
                              textAlign: TextAlign.center,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 28,
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.2,
                              ),
                            ),
                          ),
                          const SizedBox(height: 14),
                          _CallerChip(name: widget.callerUsername),
                          const SizedBox(height: 8),
                          const Text(
                            'started a call…',
                            style:
                            TextStyle(color: Colors.white70, fontSize: 15),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Actions
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
                          icon: widget.isVideo
                              ? Icons.videocam_rounded
                              : Icons.call_rounded,
                          label: 'Join',
                          color: _C.brand,
                          pulse: true,
                          onTap: _join,
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

// ─────────────────────────────────────────────────────────────────────────────
// Caller chip
// ─────────────────────────────────────────────────────────────────────────────

class _CallerChip extends StatelessWidget {
  final String name;
  const _CallerChip({required this.name});

  @override
  Widget build(BuildContext context) {
    final initial =
    name.trim().isNotEmpty ? name.trim()[0].toUpperCase() : '?';

    return Container(
      padding: const EdgeInsets.fromLTRB(5, 5, 14, 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircleAvatar(
            radius: 14,
            backgroundColor: _C.brand,
            child: Text(
              initial,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 200),
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Group avatar with ripple rings
// ─────────────────────────────────────────────────────────────────────────────

class _RippleAvatar extends StatefulWidget {
  final double size;
  const _RippleAvatar({required this.size});

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
                child: Icon(Icons.groups_rounded,
                    size: size * 0.48, color: Colors.white),
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

// ─────────────────────────────────────────────────────────────────────────────
// Action button
// ─────────────────────────────────────────────────────────────────────────────

class _CallButton extends StatefulWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  final bool pulse; // gentle attention pulse (used for Join)

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