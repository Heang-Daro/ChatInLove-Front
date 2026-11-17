import 'package:flutter/material.dart';

/// Bubble widget for displaying voice and video call statuses
/// (e.g., missed, cancelled, declined, incoming, outgoing).
class CallMessageBubble extends StatelessWidget {
  final String content;
  final bool isMe;

  const CallMessageBubble({
    super.key,
    required this.content,
    required this.isMe,
  });

  @override
  Widget build(BuildContext context) {
    final parts = content.split(':');
    final kind = parts.isNotEmpty ? parts[0].toUpperCase() : 'AUDIO';
    final rest = parts.length > 1 ? parts.sublist(1).join(':') : '';

    final isVideo = kind == 'VIDEO';
    final isMissed = rest == 'MISSED';
    final isDeclined = rest == 'REJECTED';
    final isCancelled = rest == 'CANCELLED';
    final notConnected = isMissed || isDeclined || isCancelled;

    final Color fgColor = isMe ? Colors.white : Colors.pinkAccent;
    final Color dimColor = isMe
        ? Colors.white70
        : Theme.of(context).colorScheme.onSurfaceVariant;

    final IconData icon;
    final String label;

    if (notConnected) {
      icon = isMe ? Icons.call_missed_outgoing_rounded : Icons.phone_missed_rounded;
      if (isMissed) {
        label = isMe
            ? (isVideo ? 'No answer' : 'No answer')
            : (isVideo ? 'Missed video call' : 'Missed voice call');
      } else if (isDeclined) {
        label = isMe
            ? (isVideo ? 'Call declined' : 'Call declined')
            : (isVideo ? 'Declined video call' : 'Declined voice call');
      } else {
        label = isMe
            ? (isVideo ? 'Cancelled call' : 'Cancelled call')
            : (isVideo ? 'Missed video call' : 'Missed voice call');
      }
    } else {
      icon = isVideo
          ? Icons.videocam_rounded
          : (isMe ? Icons.call_made_rounded : Icons.call_received_rounded);
      label = isMe
          ? (isVideo ? 'Outgoing video call' : 'Outgoing voice call')
          : (isVideo ? 'Incoming video call' : 'Incoming voice call');
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          size: 20,
          color: notConnected
              ? Colors.redAccent.withValues(alpha: isMe ? 0.9 : 1.0)
              : fgColor,
        ),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                color: fgColor,
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
            if (!notConnected && rest.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                rest,
                style: TextStyle(fontSize: 11, color: dimColor),
              ),
            ],
          ],
        ),
      ],
    );
  }
}
