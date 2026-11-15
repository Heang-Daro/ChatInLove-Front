import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:love_in_chat/model/Response/MessageResponse.dart';
import 'package:love_in_chat/provider/AuthProvider.dart';
import 'package:love_in_chat/provider/ConversationProvider.dart';
import '../../screen/GroupCallScreen.dart';

/// Chat bubble rendered for messages with content starting with "GROUP_CALL:".
///
/// Content format set by SignalingController:
///   "GROUP_CALL:{callSessionId}:{callType}"
///
/// When status is ACTIVE the card shows a "Join call" button.
/// When status is ENDED it shows "Call ended".
///
/// Real-time participant updates arrive via ConversationProvider which
/// re-broadcasts group call signals that contain "activeParticipants".
class GroupCallMessageCard extends StatelessWidget {
  final MessageResponse message;
  final bool isMe;

  const GroupCallMessageCard({
    super.key,
    required this.message,
    required this.isMe,
  });

  /// Parse content: "GROUP_CALL:{sessionId}:{callType}"
  static bool isGroupCallMessage(String content) =>
      content.startsWith('GROUP_CALL:');

  @override
  Widget build(BuildContext context) {
    final parts        = message.content.split(':');
    final callSessionId = parts.length > 1 ? parts[1] : '';
    final callType      = parts.length > 2 ? parts[2].toUpperCase() : 'AUDIO';
    final isVideo       = callType == 'VIDEO';

    final convos = context.watch<ConversationProvider>();
    final auth   = context.read<AuthProvider>();

    // Check if the group call session is still active.
    final activeCall = convos.activeGroupCalls[callSessionId];
    final isActive   = activeCall != null;
    final convId     = message.conversationId;

    final Color bg = isMe
        ? Colors.pinkAccent.withValues(alpha: 0.15)
        : Theme.of(context).colorScheme.surfaceContainerHighest;

    return Container(
      constraints: const BoxConstraints(maxWidth: 260),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isActive ? Colors.pinkAccent : Colors.grey.shade400,
          width: 1.2,
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Header ───────────────────────────────────────────────────────
          Row(children: [
            Icon(
              isVideo ? Icons.videocam_rounded : Icons.call_rounded,
              color: isActive ? Colors.pinkAccent : Colors.grey,
              size: 20,
            ),
            const SizedBox(width: 8),
            Text(
              isVideo ? 'Group video call' : 'Group voice call',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
                color: isActive
                    ? Theme.of(context).colorScheme.onSurface
                    : Colors.grey,
              ),
            ),
          ]),

          // ── Participant count ─────────────────────────────────────────────
          if (isActive && activeCall!.participantCount > 0) ...[
            const SizedBox(height: 4),
            Text(
              '${activeCall.participantCount} participant'
              '${activeCall.participantCount == 1 ? '' : 's'}',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],

          const SizedBox(height: 10),

          // ── Action button ─────────────────────────────────────────────────
          if (isActive)
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.pinkAccent,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: () => _joinCall(context, convId, callSessionId,
                    activeCall!.callerUserId, isVideo, auth),
                icon: Icon(
                  isVideo ? Icons.videocam : Icons.call,
                  size: 16,
                  color: Colors.white,
                ),
                label: const Text('Join call',
                    style: TextStyle(color: Colors.white, fontSize: 13)),
              ),
            )
          else
            Row(children: [
              const Icon(Icons.call_end, color: Colors.grey, size: 15),
              const SizedBox(width: 6),
              Text('Call ended',
                  style: TextStyle(
                      color: Colors.grey.shade500,
                      fontSize: 12,
                      fontStyle: FontStyle.italic)),
            ]),
        ],
      ),
    );
  }

  void _joinCall(
    BuildContext context,
    String conversationId,
    String callSessionId,
    String callerUserId,
    bool isVideo,
    AuthProvider auth,
  ) {
    final conv = context.read<ConversationProvider>().conversations
        .where((c) => c.id == conversationId)
        .firstOrNull;

    final callerMember = conv?.members
        .where((m) => m.userId == callerUserId)
        .firstOrNull;

    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => GroupCallScreen(
        conversationId:  conversationId,
        groupName:       conv?.name ?? 'Group call',
        isVideo:         isVideo,
        localUserId:     auth.currentUserId ?? '',
        callerUserId:    callerUserId,
        callerUsername:  callerMember?.username ?? callerUserId,
      ),
    ));
  }
}

/// Lightweight model carried in ConversationProvider for active group calls.
class ActiveGroupCallInfo {
  final String callSessionId;
  final String conversationId;
  final String callerUserId;
  final int participantCount;

  const ActiveGroupCallInfo({
    required this.callSessionId,
    required this.conversationId,
    required this.callerUserId,
    required this.participantCount,
  });
}
