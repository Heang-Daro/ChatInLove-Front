import 'package:flutter/material.dart';
import 'package:love_in_chat/api/api.dart';
import 'package:love_in_chat/screen/message/VoiceMessageBubble.dart';
import 'package:provider/provider.dart';
import 'package:love_in_chat/model/Response/MessageResponse.dart';
import 'package:love_in_chat/model/emun/MessageType.dart';
import 'package:love_in_chat/provider/AuthProvider.dart';
import 'package:love_in_chat/provider/ConversationProvider.dart';
import '../../util/AnimatedComponents.dart';

class ConversationBody extends StatelessWidget {
  const ConversationBody({super.key});

  Widget _buildMessageContent(BuildContext context, MessageResponse message, bool isMe) {
    final String timeString = message.createdAt != null
        ? "${message.createdAt!.hour.toString().padLeft(2, '0')}:${message.createdAt!.minute.toString().padLeft(2, '0')}"
        : "";

    switch (message.type) {
      case MessageType.IMAGE:
        return Stack(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: GestureDetector(
                onTap: () {
                  showDialog(
                    context: context,
                    builder: (_) => Dialog(
                      backgroundColor: Colors.transparent,
                      insetPadding: const EdgeInsets.all(8),
                      child: Stack(
                        alignment: Alignment.topRight,
                        children: [
                          InteractiveViewer(
                            child: Image.network(
                              message.mediaUrl,
                              errorBuilder: (context, error, stackTrace) => const Padding(
                                padding: EdgeInsets.all(20.0),
                                child: Icon(Icons.broken_image, size: 64, color: Colors.white70),
                              ),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close, color: Colors.white, size: 30),
                            onPressed: () => Navigator.pop(context),
                          ),
                        ],
                      ),
                    ),
                  );
                },
                child: Image.network(
                  message.mediaUrl,
                  width: 250,
                  height: 200,
                  fit: BoxFit.cover,
                  loadingBuilder: (context, child, loadingProgress) {
                    if (loadingProgress == null) return child;
                    return Container(
                      width: 250,
                      height: 200,
                      color: isMe ? Colors.pink.shade300 : Colors.grey.shade300,
                      child: const Center(
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                      ),
                    );
                  },
                  errorBuilder: (context, error, stackTrace) => Container(
                    width: 250,
                    height: 140,
                    color: Colors.grey.shade300,
                    child: const Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.broken_image, color: Colors.grey, size: 32),
                        SizedBox(height: 4),
                        Text("Image unavailable", style: TextStyle(fontSize: 12, color: Colors.grey)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            // Telegram-style timestamp overlay on bottom right of the image
            Positioned(
              bottom: 6,
              right: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      timeString,
                      style: const TextStyle(color: Colors.white, fontSize: 10),
                    ),
                    if (isMe) ...[
                      const SizedBox(width: 3),
                      Icon(
                        message.isRead ? Icons.done_all : Icons.done,
                        size: 12,
                        color: Colors.white,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        );

      case MessageType.VOICE:
        return VoiceMessageBubble(
          audioUrl: message.mediaUrl,
          isMe: isMe,
        );

      case MessageType.VIDEO:
        return Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: 250,
              height: 160,
              decoration: BoxDecoration(
                color: Colors.black87,
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Stack(
                alignment: Alignment.center,
                children: [
                  Icon(Icons.play_circle_fill_rounded, size: 54, color: Colors.white70),
                  Positioned(
                    bottom: 8,
                    left: 10,
                    child: Row(
                      children: [
                        Icon(Icons.videocam, size: 14, color: Colors.white70),
                        SizedBox(width: 4),
                        Text("Video", style: TextStyle(color: Colors.white70, fontSize: 11)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Positioned(
              bottom: 6,
              right: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  timeString,
                  style: const TextStyle(color: Colors.white, fontSize: 10),
                ),
              ),
            ),
          ],
        );

      case MessageType.FILE:
        final fileName = fileNameFromUrl(message.content);
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: isMe ? Colors.white24 : Colors.pink.shade50,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                Icons.insert_drive_file_rounded,
                color: isMe ? Colors.white : Colors.pinkAccent,
                size: 26,
              ),
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    fileName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: isMe ? Colors.white : Theme.of(context).textTheme.bodyLarge?.color,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    "Attachment Document",
                    style: TextStyle(
                      fontSize: 11,
                      color: isMe ? Colors.white70 : Colors.grey,
                    ),
                  ),
                ],
              ),
            ),
          ],
        );

      case MessageType.CALL:
        return _CallBubble(content: message.content, isMe: isMe);

      case MessageType.SYSTEM:
        return Center(
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 6),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              message.content,
              style: const TextStyle(fontSize: 11, color: Colors.black87),
            ),
          ),
        );

      case MessageType.TEXT:
      default:
        return Text(
          message.content,
          style: TextStyle(
            color: isMe ? Colors.white : Theme.of(context).textTheme.bodyLarge?.color,
            fontSize: 14.5,
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Consumer<ConversationProvider>(
        builder: (context, convoProvider, child) {
          // Only block the screen with a spinner when there is really nothing
          // to show. Cached messages stay visible while the server syncs.
          if (convoProvider.isLoadingMessages &&
              convoProvider.currentMessages.isEmpty) {
            return const Center(
              child: CircularProgressIndicator(color: Colors.pinkAccent),
            );
          }

          final messages = convoProvider.currentMessages;
          final typingUser = convoProvider.activeTypingUser;

          if (messages.isEmpty && typingUser == null) {
            return const Center(
              child: Text('No messages yet. Say hello!', style: TextStyle(color: Colors.grey)),
            );
          }

          final authProvider = Provider.of<AuthProvider>(context, listen: false);
          final currentUserId = authProvider.currentUserId ?? "";

          final totalItemCount = messages.length + (typingUser != null ? 1 : 0);

          return ListView.builder(
            reverse: true, // newest messages at the bottom
            padding: const EdgeInsets.all(12),
            itemCount: totalItemCount,
            itemBuilder: (context, index) {
              if (typingUser != null && index == 0) {
                return TypingIndicator(username: typingUser);
              }

              final messageIndex = typingUser != null ? index - 1 : index;
              final message = messages[messageIndex];
              final bool isMe = message.senderId == currentUserId;

              if (message.type == MessageType.SYSTEM) {
                return _buildMessageContent(context, message, isMe);
              }

              final bool isMedia = message.type == MessageType.IMAGE || message.type == MessageType.VIDEO;

              return Align(
                alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  padding: isMedia
                      ? EdgeInsets.zero
                      : const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  constraints: BoxConstraints(
                    maxWidth: MediaQuery.of(context).size.width * 0.78, // FIXED: Added proper multiplying operator '*'
                  ),
                  decoration: BoxDecoration(
                    gradient: isMe && !isMedia
                        ? LinearGradient(
                      colors: [Colors.pinkAccent.shade200, Colors.pinkAccent.shade400],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    )
                        : null,
                    color: isMe ? null : Theme.of(context).cardColor,
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(18),
                      topRight: const Radius.circular(18),
                      bottomLeft: Radius.circular(isMe ? 18 : 4),
                      bottomRight: Radius.circular(isMe ? 4 : 18),
                    ),
                    border: isMe ? null : Border.all(color: Colors.pink.withValues(alpha: 0.15)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.04),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildMessageContent(context, message, isMe),
                      if (!isMedia) ...[
                        const SizedBox(height: 4),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              message.createdAt != null
                                  ? "${message.createdAt!.hour.toString().padLeft(2, '0')}:${message.createdAt!.minute.toString().padLeft(2, '0')}"
                                  : "",
                              style: TextStyle(
                                fontSize: 10,
                                color: isMe ? Colors.white70 : Colors.grey,
                              ),
                            ),
                            if (isMe) ...[
                              const SizedBox(width: 4),
                              Icon(
                                message.isRead ? Icons.done_all : Icons.done,
                                size: 13,
                                color: Colors.white70,
                              ),
                            ],
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

// ── Call bubble ──────────────────────────────────────────────────────────────
/// Parses the CALL message content and renders an icon + label.
///
/// Content format (written by CallScreen / IncomingCallScreen):
///   "AUDIO:02:34"   → voice call, connected, 2 min 34 sec
///   "VIDEO:05:01"   → video call, connected, 5 min 1 sec
///   "AUDIO:MISSED"  → missed voice call
///   "VIDEO:MISSED"  → missed video call
///   "AUDIO:REJECTED"→ declined voice call
///   "VIDEO:REJECTED"→ declined video call
///   "AUDIO:CANCELLED"→ caller cancelled before answer
///   "VIDEO:CANCELLED"→ caller cancelled before answer
class _CallBubble extends StatelessWidget {
  final String content;
  final bool isMe;

  const _CallBubble({required this.content, required this.isMe});

  @override
  Widget build(BuildContext context) {
    final parts = content.split(':');
    final kind = parts.isNotEmpty ? parts[0].toUpperCase() : 'AUDIO';
    // duration is everything after the kind prefix (handles mm:ss with colons)
    final rest = parts.length > 1 ? parts.sublist(1).join(':') : '';

    final isVideo  = kind == 'VIDEO';
    final isMissed = rest == 'MISSED';
    final isDeclined   = rest == 'REJECTED';
    final isCancelled  = rest == 'CANCELLED';
    final notConnected = isMissed || isDeclined || isCancelled;

    final Color fgColor = isMe ? Colors.white : Colors.pinkAccent;
    final Color dimColor = isMe
        ? Colors.white70
        : Theme.of(context).colorScheme.onSurfaceVariant;

    IconData icon;
    String label;

    if (notConnected) {
      icon  = Icons.phone_missed;
      label = isMissed
          ? (isVideo ? 'Missed video call' : 'Missed voice call')
          : isDeclined
              ? (isVideo ? 'Declined video call' : 'Declined voice call')
              : (isVideo ? 'Cancelled video call' : 'Cancelled voice call');
    } else {
      icon  = isVideo ? Icons.videocam_rounded : Icons.call_rounded;
      label = isVideo ? 'Video call' : 'Voice call';
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          size: 20,
          color: notConnected ? Colors.redAccent.withValues(alpha: isMe ? 0.9 : 1.0) : fgColor,
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
