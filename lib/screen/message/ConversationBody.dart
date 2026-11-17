import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:love_in_chat/model/Response/MessageResponse.dart';
import 'package:love_in_chat/model/emun/MessageType.dart';
import 'package:love_in_chat/provider/AuthProvider.dart';
import 'package:love_in_chat/provider/ConversationProvider.dart';
import 'package:love_in_chat/screen/message/CallMessageBubble.dart';
import 'package:love_in_chat/screen/message/FileMessageBubble.dart';
import 'package:love_in_chat/screen/message/GroupCallMessageCard.dart';
import 'package:love_in_chat/screen/message/ImageMessageBubble.dart';
import 'package:love_in_chat/screen/message/MessageOptionsSheet.dart';
import 'package:love_in_chat/screen/message/SystemMessageBubble.dart';
import 'package:love_in_chat/screen/message/VideoMessageBubble.dart';
import 'package:love_in_chat/screen/message/VoiceMessageBubble.dart';
import 'package:love_in_chat/screen/message/message_shortcuts.dart';
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

  Widget _buildMessageContent(BuildContext context, MessageResponse message, bool isMe) {
    switch (message.type) {
      case MessageType.IMAGE:
        return ImageMessageBubble(message: message, isMe: isMe);

      case MessageType.VOICE:
        return VoiceMessageBubble(
          audioUrl: message.mediaUrl,
          isMe: isMe,
        );

      case MessageType.VIDEO:
        return VideoMessageBubble(
          videoUrl: message.mediaUrl,
          isMe: isMe,
        );

      case MessageType.FILE:
        return FileMessageBubble(message: message, isMe: isMe);

      case MessageType.CALL:
        if (GroupCallMessageCard.isGroupCallMessage(message.content)) {
          return GroupCallMessageCard(message: message, isMe: isMe);
        }
        return CallMessageBubble(content: message.content, isMe: isMe);

      case MessageType.SYSTEM:
        return SystemMessageBubble(message: message);

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
          isMe: isMe,
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
                    onLongPress: () => MessageOptionsSheet.showOptions(
                      context: context,
                      message: message,
                      isMe: isMe,
                      onStartEditing: () => _startEditing(message),
                    ),
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
