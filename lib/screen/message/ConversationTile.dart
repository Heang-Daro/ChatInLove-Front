import 'package:flutter/material.dart';
import 'package:love_in_chat/model/Response/ConversationResponse.dart';
import 'package:love_in_chat/model/Response/MessageResponse.dart';
import 'package:love_in_chat/model/emun/ConversationType.dart';
import 'package:love_in_chat/model/emun/MessageType.dart';
import '../../util/AnimatedComponents.dart';
import '../ConversationPage.dart';

class ConversationTile extends StatelessWidget {
  final ConversationResponse chat;
  final String currentUserId; // required: used to find the OTHER member

  const ConversationTile({
    super.key,
    required this.chat,
    required this.currentUserId,
  });

  /// Formats a local DateTime into a readable time or date.
  /// • Same day  → HH:mm  (e.g. "13:31")
  /// • This week → Weekday (e.g. "Mon")
  /// • Older     → dd/mm  (e.g. "12/11")
  String _formatTime(DateTime local) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final msgDay = DateTime(local.year, local.month, local.day);
    final diff = today.difference(msgDay).inDays;

    if (diff == 0) {
      // Same day — show HH:mm
      return '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
    } else if (diff < 7) {
      // Within the last week — show weekday name
      const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      return days[local.weekday - 1];
    } else {
      // Older — show day/month
      return '${local.day}/${local.month}';
    }
  }

  /// Readable label for a CALL message shown in the conversation list.
  String _callLabel(String content) {
    final parts = content.split(':');
    final kind = parts.isNotEmpty ? parts[0].toUpperCase() : 'AUDIO';
    final rest = parts.length > 1 ? parts.sublist(1).join(':') : '';
    final isVideo = kind == 'VIDEO';
    switch (rest) {
      case 'MISSED':    return isVideo ? 'Missed video call' : 'Missed call';
      case 'REJECTED':  return isVideo ? 'Declined video call' : 'Declined call';
      case 'CANCELLED': return isVideo ? 'Cancelled video call' : 'Cancelled call';
      default:          return isVideo ? 'Video call · $rest' : 'Voice call · $rest';
    }
  }

  /// Icon for CALL messages in the tile subtitle.
  IconData _callIcon(String content) {
    final rest = content.contains(':') ? content.split(':').sublist(1).join(':') : '';
    final isVideo = content.toUpperCase().startsWith('VIDEO');
    if (rest == 'MISSED' || rest == 'REJECTED' || rest == 'CANCELLED') {
      return Icons.phone_missed_rounded;
    }
    return isVideo ? Icons.videocam_rounded : Icons.call_rounded;
  }

  /// Avatar for the tile — shows profile image when available.
  Widget _buildAvatar(bool isGroup, String currentUserId) {
    if (isGroup) {
      // Group: use group icon (could later support group images)
      return CircleAvatar(
        backgroundColor: Colors.pinkAccent,
        child: const Icon(Icons.group, color: Colors.white),
      );
    }
    // Private: find the other member and use their profileImageUrl.
    final other = chat.members
        .where((m) => m.userId.trim() != currentUserId.trim() && m.leftAt == null)
        .firstOrNull;
    final avatarUrl = other?.profileImageUrl;
    final initials = (other?.username.isNotEmpty == true)
        ? other!.username[0].toUpperCase()
        : '?';

    if (avatarUrl != null && avatarUrl.isNotEmpty) {
      return CircleAvatar(
        backgroundColor: Colors.pinkAccent.withValues(alpha: 0.15),
        backgroundImage: NetworkImage(avatarUrl),
        onBackgroundImageError: (_, __) {},
        child: null,
      );
    }
    return CircleAvatar(
      backgroundColor: Colors.pinkAccent,
      child: Text(initials,
          style: const TextStyle(
              color: Colors.white, fontWeight: FontWeight.bold)),
    );
  }

  IconData? _getMessageIcon(MessageType type) {
    switch (type) {
      case MessageType.IMAGE:
        return Icons.image;
      case MessageType.VIDEO:
        return Icons.videocam;
      case MessageType.VOICE:
        return Icons.mic;
      case MessageType.FILE:
        return Icons.insert_drive_file;
      case MessageType.CALL:
        return null; // handled separately with _callIcon()
      case MessageType.SYSTEM:
        return Icons.info_outline;
      case MessageType.TEXT:
      default:
        return null;
    }
  }

  String _getMessageLabel(MessageResponse lastMsg) {
    switch (lastMsg.type) {
      case MessageType.IMAGE:
        return "Image";
      case MessageType.VIDEO:
        return "Video";
      case MessageType.VOICE:
        return "Voice Note";
      case MessageType.FILE:
        return "Document";
      case MessageType.CALL:
        return _callLabel(lastMsg.content);
      case MessageType.SYSTEM:
        return lastMsg.content;
      case MessageType.TEXT:
        return lastMsg.content;
    }
  }

  Widget _buildSubtitleContent(
      BuildContext context,
      MessageResponse? lastMsg,
      bool isMyMessage,
      bool hasUnreadMessage,
      ) {
    final Color textColor = hasUnreadMessage
        ? Colors.pinkAccent
        : Theme.of(context).colorScheme.onSurfaceVariant;

    final TextStyle textStyle = TextStyle(
      fontSize: 13,
      fontWeight: hasUnreadMessage ? FontWeight.bold : FontWeight.normal,
      color: textColor,
    );

    if (lastMsg == null) {
      return Text(
        "Tap to start chatting",
        style: textStyle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      );
    }

    final IconData? iconData = lastMsg.type == MessageType.CALL
        ? _callIcon(lastMsg.content)
        : _getMessageIcon(lastMsg.type);
    final String label = _getMessageLabel(lastMsg);

    return Row(
      children: [
        if (isMyMessage && lastMsg.isRead) ...[
          const Icon(
            Icons.done_all,
            size: 16,
            color: Colors.pinkAccent,
          ),
          const SizedBox(width: 4),
        ],
        if (isMyMessage) ...[
          Text("You: ", style: textStyle),
        ],
        if (iconData != null) ...[
          Icon(
            iconData,
            size: 15,
            color: textColor,
          ),
          const SizedBox(width: 4),
        ],
        Expanded(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: textStyle,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final isGroup = chat.type == ConversationType.GROUP;

    // Resolve chat name
    String chatName = chat.name ?? "";

    if (chatName.isEmpty && !isGroup) {
      final trimmedId = currentUserId.trim();

      final otherMembers = chat.members.where(
            (m) => m.userId.trim() != trimmedId && m.leftAt == null,
      );

      if (otherMembers.isNotEmpty) {
        chatName = otherMembers.first.username;
      }
    }

    if (chatName.isEmpty) {
      chatName = isGroup ? "Group Chat" : "Chat";
    }

    final avatarIcon = isGroup ? Icons.group : Icons.person;

    // Check read/unread status of the last message
    final lastMsg = chat.lastMessage;
    final bool hasUnreadMessage = lastMsg != null &&
        !lastMsg.isRead &&
        lastMsg.senderId != currentUserId; // Only unread if sent by the other user

    final bool isMyMessage = lastMsg != null && lastMsg.senderId == currentUserId;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          Navigator.push(
            context,
            AnimatedPageRoute(
              page: ConversationPage(
                conversationId: chat.id,
                chatName: chatName,
                avatar: avatarIcon,
                isGroup: isGroup,
              ),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              _buildAvatar(isGroup, currentUserId),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            chatName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: hasUnreadMessage ? FontWeight.w900 : FontWeight.bold,
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          chat.lastMessageAt != null
                              ? _formatTime(chat.lastMessageAt!.toLocal())
                              : "",
                          style: TextStyle(
                            fontSize: 11.5,
                            color: hasUnreadMessage
                                ? Colors.pinkAccent
                                : Theme.of(context).colorScheme.onSurfaceVariant,
                            fontWeight: hasUnreadMessage ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Expanded(
                          child: _buildSubtitleContent(context, lastMsg, isMyMessage, hasUnreadMessage),
                        ),
                        if (hasUnreadMessage) ...[
                          const SizedBox(width: 6),
                          Container(
                            width: 9,
                            height: 9,
                            decoration: const BoxDecoration(
                              color: Colors.pinkAccent,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
