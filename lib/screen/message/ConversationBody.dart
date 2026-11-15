import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:love_in_chat/api/api.dart';
import 'package:love_in_chat/screen/message/GroupCallMessageCard.dart';
import 'package:love_in_chat/screen/message/VoiceMessageBubble.dart';
import 'package:love_in_chat/screen/message/message_shortcuts.dart';
import 'package:provider/provider.dart';
import 'package:love_in_chat/model/Response/MessageResponse.dart';
import 'package:love_in_chat/model/emun/MessageType.dart';
import 'package:love_in_chat/provider/AuthProvider.dart';
import 'package:love_in_chat/provider/ConversationProvider.dart';
import '../../util/AnimatedComponents.dart';

class ConversationBody extends StatefulWidget {
  final ScrollController? scrollController;

  const ConversationBody({super.key, this.scrollController});

  @override
  State<ConversationBody> createState() => _ConversationBodyState();
}

class _ConversationBodyState extends State<ConversationBody> {
  String? _editingMessageId;
  final TextEditingController _editController = TextEditingController();

  @override
  void dispose() {
    _editController.dispose();
    super.dispose();
  }

  void _startEditing(MessageResponse message) {
    setState(() {
      _editingMessageId = message.id;
      _editController.text = message.content;
    });
  }

  void _cancelEditing() {
    setState(() {
      _editingMessageId = null;
      _editController.clear();
    });
  }

  Future<void> _saveEditing(MessageResponse message) async {
    final newContent = _editController.text.trim();
    if (newContent.isEmpty || newContent == message.content) {
      _cancelEditing();
      return;
    }

    final authProvider = context.read<AuthProvider>();
    final convoProvider = context.read<ConversationProvider>();
    final msgId = message.id;

    _cancelEditing();

    final success = await convoProvider.editMessage(authProvider, msgId, newContent);
    if (!mounted) return;
    if (!success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Failed to edit message. Please check permissions and connection."),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  void _showMessageOptions(BuildContext context, MessageResponse message, bool isMe) {
    final isText = message.type == MessageType.TEXT;

    AnimatedBottomSheet.show(
      context: context,
      isScrollControlled: false,
      builder: (ctx) => SafeArea(
        child: Container(
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade400,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              // Copy message option
              ListTile(
                leading: const Icon(Icons.copy_rounded, color: Colors.pinkAccent),
                title: const Text("Copy Text"),
                onTap: () {
                  Navigator.pop(ctx);
                  Clipboard.setData(ClipboardData(text: message.content));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text("Copied to clipboard"),
                      duration: Duration(seconds: 1),
                    ),
                  );
                },
              ),
              // Edit option (Only for sender and text messages)
              if (isMe && isText)
                ListTile(
                  leading: const Icon(Icons.edit_rounded, color: Colors.blueAccent),
                  title: const Text("Edit Message"),
                  onTap: () {
                    Navigator.pop(ctx);
                    _startEditing(message);
                  },
                ),
              // Delete option (Only for sender)
              if (isMe)
                ListTile(
                  leading: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent),
                  title: const Text("Delete Message", style: TextStyle(color: Colors.redAccent)),
                  onTap: () {
                    Navigator.pop(ctx);
                    _confirmDelete(context, message);
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _confirmDelete(BuildContext context, MessageResponse message) {
    AnimatedDialog.show(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text("Delete Message?"),
        content: const Text("Are you sure you want to delete this message? This action cannot be undone."),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text("Cancel", style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () async {
              Navigator.pop(dialogCtx);
              final authProvider = context.read<AuthProvider>();
              final convoProvider = context.read<ConversationProvider>();
              final success = await convoProvider.deleteMessage(authProvider, message.id);
              if (!mounted) return;
              if (!success) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text("Failed to delete message. Please try again."),
                    backgroundColor: Colors.redAccent,
                  ),
                );
              }
            },
            child: const Text("Delete", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageContent(BuildContext context, MessageResponse message, bool isMe) {
    final String timeString = message.createdAt != null
        ? "${message.createdAt!.toLocal().hour.toString().padLeft(2, '0')}:${message.createdAt!.toLocal().minute.toString().padLeft(2, '0')}"
        : "";

    switch (message.type) {
      case MessageType.IMAGE:
        return Stack(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: GestureDetector(
                onTap: () {
                  AnimatedDialog.show(
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
        if (GroupCallMessageCard.isGroupCallMessage(message.content)) {
          return GroupCallMessageCard(message: message, isMe: isMe);
        }
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
        final isEditingThis = _editingMessageId == message.id;

        if (isEditingThis) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _editController,
                autofocus: true,
                maxLines: null,
                style: TextStyle(
                  color: isMe ? Colors.white : Theme.of(context).textTheme.bodyLarge?.color,
                  fontSize: 14.5,
                ),
                decoration: InputDecoration(
                  hintText: "Edit message...",
                  hintStyle: TextStyle(color: isMe ? Colors.white60 : Colors.grey),
                  isDense: true,
                  border: UnderlineInputBorder(
                    borderSide: BorderSide(color: isMe ? Colors.white70 : Colors.pinkAccent),
                  ),
                  focusedBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: isMe ? Colors.white : Colors.pinkAccent, width: 1.5),
                  ),
                ),
                onSubmitted: (_) => _saveEditing(message),
              ),
              const SizedBox(height: 6),
              Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  InkWell(
                    onTap: _cancelEditing,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      child: Text(
                        "Cancel",
                        style: TextStyle(
                          fontSize: 11,
                          color: isMe ? Colors.white70 : Colors.grey.shade600,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  InkWell(
                    onTap: () => _saveEditing(message),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: isMe ? Colors.white : Colors.pinkAccent,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        "Save",
                        style: TextStyle(
                          fontSize: 11,
                          color: isMe ? Colors.pinkAccent : Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          );
        }

        return FormattedMessageText(
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
          final totalItemCount = messages.length +
              (typingUser != null ? 1 : 0) +
              (convoProvider.isLoadingMoreMessages ? 1 : 0);

          return ListView.builder(
            controller: widget.scrollController,
            reverse: true,
            padding: const EdgeInsets.all(12),
            itemCount: totalItemCount,
            itemBuilder: (context, index) {
              // Show loading older messages indicator at top of reverse list (end of indices)
              if (convoProvider.isLoadingMoreMessages && index == totalItemCount - 1) {
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.all(8.0),
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(color: Colors.pinkAccent, strokeWidth: 2),
                    ),
                  ),
                );
              }

              if (typingUser != null && index == 0) {
                return TypingIndicator(username: typingUser);
              }

              final messageIndex = typingUser != null ? index - 1 : index;
              final message = messages[messageIndex];
              final bool isMe = message.senderId == currentUserId;

              if (message.type == MessageType.SYSTEM) {
                return _buildMessageContent(context, message, isMe);
              }

              final bool isMedia = message.type == MessageType.IMAGE ||
                  message.type == MessageType.VIDEO;
              final bool isEdited = message.editedAt != null;

              return TweenAnimationBuilder<double>(
                key: ValueKey(message.id),
                tween: Tween(begin: 0.0, end: 1.0),
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                builder: (context, value, animChild) {
                  return Opacity(
                    opacity: value,
                    child: Transform.translate(
                      offset: Offset(0, (1.0 - value) * 12),
                      child: animChild,
                    ),
                  );
                },
                child: Align(
                  alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                  child: GestureDetector(
                    onLongPress: () => _showMessageOptions(context, message, isMe),
                    child: Container(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      padding: isMedia
                          ? EdgeInsets.zero
                          : const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      constraints: BoxConstraints(
                        maxWidth: MediaQuery.of(context).size.width * 0.78,
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
                                if (isEdited) ...[
                                  Text(
                                    "edited ",
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontStyle: FontStyle.italic,
                                      color: isMe ? Colors.white60 : Colors.grey,
                                    ),
                                  ),
                                ],
                                Text(
                                  message.createdAt != null
                                      ? "${message.createdAt!.toLocal().hour.toString().padLeft(2, '0')}:${message.createdAt!.toLocal().minute.toString().padLeft(2, '0')}"
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

// ── Call bubble ───────────────────────────────────────────────────────────────
class _CallBubble extends StatelessWidget {
  final String content;
  final bool isMe;

  const _CallBubble({required this.content, required this.isMe});

  @override
  Widget build(BuildContext context) {
    final parts = content.split(':');
    final kind = parts.isNotEmpty ? parts[0].toUpperCase() : 'AUDIO';
    final rest = parts.length > 1 ? parts.sublist(1).join(':') : '';

    final isVideo     = kind == 'VIDEO';
    final isMissed    = rest == 'MISSED';
    final isDeclined  = rest == 'REJECTED';
    final isCancelled = rest == 'CANCELLED';
    final notConnected = isMissed || isDeclined || isCancelled;

    final Color fgColor  = isMe ? Colors.white : Colors.pinkAccent;
    final Color dimColor = isMe
        ? Colors.white70
        : Theme.of(context).colorScheme.onSurfaceVariant;

    final IconData icon;
    final String label;

    if (notConnected) {
      icon  = Icons.phone_missed;
      label = isMissed
          ? (isVideo ? 'Missed video call'    : 'Missed voice call')
          : isDeclined
              ? (isVideo ? 'Declined video call' : 'Declined voice call')
              : (isVideo ? 'Cancelled video call': 'Cancelled voice call');
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
