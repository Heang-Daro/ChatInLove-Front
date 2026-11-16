import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:love_in_chat/provider/ConversationProvider.dart';
import 'package:love_in_chat/service/CallRingtoneService.dart';
import 'package:love_in_chat/service/StompService.dart';
import 'GroupCallScreen.dart';

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

  late final ConversationProvider _convos;

  @override
  void initState() {
    super.initState();
    _convos = context.read<ConversationProvider>();
    CallRingtoneService.playRingtone();
  }

  @override
  void dispose() {
    // When joining we must NOT stop the ringtone here: the call screen starts
    // its own tone and this overlay is disposed after it.
    if (!_joined) {
      CallRingtoneService.stop();
      // The overlay was dismissed without joining (decline / back button) —
      // release the call slot so the next incoming call can be shown.
      _convos.markCallEnded();
    }
    super.dispose();
  }

  void _join() {
    _joined = true;
    CallRingtoneService.stop();
    // Replace this overlay with the actual call screen.
    Navigator.of(context).pushReplacement(MaterialPageRoute(
      builder: (_) => GroupCallScreen(
        conversationId: widget.conversationId,
        groupName:      widget.groupName,
        isVideo:        widget.isVideo,
        localUserId:    widget.localUserId,
        callerUserId:   widget.callerUserId,
        callerUsername: widget.callerUsername,
      ),
    ));
  }

  void _decline() {
    CallRingtoneService.stop();
    // Tell the caller this member declined so they don't wait forever.
    try {
      StompService().sendSignal(widget.callerUserId, {
        'type':            'DECLINE_CALL',
        'fromUserId':      widget.localUserId,
        'conversationId':  widget.conversationId,
        'isGroup':         true,
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
    return Scaffold(
      backgroundColor: Colors.black87,
      body: SafeArea(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // ── Call info ────────────────────────────────────────────────
            const SizedBox(height: 48),
            Column(children: [
              // Group icon
              CircleAvatar(
                radius: 60,
                backgroundColor: Colors.pinkAccent.withValues(alpha: 0.2),
                child: const Icon(Icons.group, size: 56, color: Colors.white),
              ),
              const SizedBox(height: 20),
              Text(
                widget.groupName,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 24,
                    color: Colors.white,
                    fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                '${widget.callerUsername} started a group ${widget.isVideo ? 'video' : 'voice'} call',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white60, fontSize: 15),
              ),
              const SizedBox(height: 6),
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(
                  widget.isVideo ? Icons.videocam : Icons.call,
                  color: Colors.white38,
                  size: 16,
                ),
                const SizedBox(width: 6),
                Text(
                  widget.isVideo ? 'Group video call' : 'Group voice call',
                  style: const TextStyle(color: Colors.white38, fontSize: 13),
                ),
              ]),
            ]),

            // ── Buttons ──────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.only(bottom: 48),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _CallButton(
                    icon: Icons.call_end,
                    label: 'Decline',
                    color: Colors.redAccent,
                    onTap: _decline,
                  ),
                  _CallButton(
                    icon: widget.isVideo ? Icons.videocam : Icons.call,
                    label: 'Join',
                    color: Colors.green,
                    onTap: _join,
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

class _CallButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _CallButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Column(children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            child: Icon(icon, color: Colors.white, size: 32),
          ),
          const SizedBox(height: 8),
          Text(label,
              style: const TextStyle(color: Colors.white70, fontSize: 13)),
        ]),
      );
}
