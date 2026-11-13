import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:love_in_chat/data/database/app_database.dart';
import 'package:love_in_chat/data/repositories/chat_repository.dart';
import 'package:love_in_chat/model/emun/MessageType.dart';
import 'package:love_in_chat/provider/AuthProvider.dart';
import 'package:love_in_chat/util/AppBarStyle.dart';

/// Chat screen that is driven **purely** by the local database.
///
/// The list is a `ListView.builder(reverse: true)` over
/// [ChatRepository.watchMessages]. Nothing in this file talks to the network:
/// sending a message writes to SQLite and the stream pushes the new bubble
/// into the list.
class ChatScreen extends StatefulWidget {
  final String chatId;
  final String title;

  const ChatScreen({
    super.key,
    required this.chatId,
    this.title = 'Chat',
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final repo = context.read<ChatRepository>();
      repo.markChatRead(widget.chatId);
    });
  }

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _textController.text.trim();
    if (text.isEmpty || _sending) return;

    setState(() => _sending = true);
    _textController.clear();

    final repo = context.read<ChatRepository>();
    await repo.sendMessage(
      chatId: widget.chatId,
      content: text,
    );

    if (mounted) setState(() => _sending = false);
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<ChatRepository>();
    final currentUserId =
        context.read<AuthProvider>().currentUserId ?? '';

    return Scaffold(
      appBar: AppBarStyle.build(
        title: widget.title,
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<List<Message>>(
              stream: repo.watchMessages(widget.chatId),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(
                    child: Text(
                      'Could not read the local database:\n${snapshot.error}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.grey),
                    ),
                  );
                }

                final messages = snapshot.data ?? const <Message>[];

                if (messages.isEmpty) {
                  return const Center(
                    child: Text(
                      'No messages yet. Say hello!',
                      style: TextStyle(color: Colors.grey),
                    ),
                  );
                }

                // reverse: true -> index 0 is the newest message and sits at
                // the bottom of the screen.
                return ListView.builder(
                  reverse: true,
                  controller: _scrollController,
                  padding: const EdgeInsets.all(12),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final message = messages[index];
                    final isMine = message.senderId == currentUserId;

                    return _MessageBubble(
                      message: message,
                      isMine: isMine,
                      onRetry: () => repo.retryFailedMessage(message.localId),
                    );
                  },
                );
              },
            ),
          ),
          _buildInputBar(),
        ],
      ),
    );
  }

  Widget _buildInputBar() {
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          boxShadow: const [
            BoxShadow(
              color: Colors.black12,
              blurRadius: 6,
              offset: Offset(0, -2),
            ),
          ],
        ),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _textController,
                minLines: 1,
                maxLines: 4,
                textInputAction: TextInputAction.newline,
                decoration: InputDecoration(
                  hintText: 'Message',
                  filled: true,
                  fillColor: Colors.grey.shade100,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                ),
                onSubmitted: (_) => _send(),
              ),
            ),
            const SizedBox(width: 8),
            Material(
              color: Colors.pinkAccent,
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: _send,
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Icon(
                    Icons.send,
                    color: Colors.white,
                    size: _sending ? 16 : 20,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One message bubble including its delivery indicator.
class _MessageBubble extends StatelessWidget {
  final Message message;
  final bool isMine;
  final VoidCallback onRetry;

  const _MessageBubble({
    required this.message,
    required this.isMine,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.only(
      topLeft: const Radius.circular(16),
      topRight: const Radius.circular(16),
      bottomLeft: Radius.circular(isMine ? 16 : 4),
      bottomRight: Radius.circular(isMine ? 4 : 16),
    );

    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 3),
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
        decoration: BoxDecoration(
          color: isMine ? Colors.pinkAccent : Colors.grey.shade200,
          borderRadius: radius,
        ),
        child: Column(
          crossAxisAlignment:
              isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            _buildContent(context),
            const SizedBox(height: 2),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _formatTime(message.timestamp),
                  style: TextStyle(
                    fontSize: 10,
                    color: isMine ? Colors.white70 : Colors.grey.shade600,
                  ),
                ),
                if (isMine) ...[
                  const SizedBox(width: 6),
                  DeliveryIndicator(
                    status: message.status,
                    onRetry: onRetry,
                    color: Colors.white,
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    switch (message.messageType) {
      case MessageType.IMAGE:
        return ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Image.network(
            message.mediaUrl ?? message.content,
            width: 200,
            height: 160,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stack) => Container(
              width: 200,
              height: 120,
              color: Colors.black12,
              child: const Icon(Icons.broken_image, color: Colors.grey),
            ),
          ),
        );
      case MessageType.VOICE:
      case MessageType.VIDEO:
      case MessageType.FILE:
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.insert_drive_file, size: 18),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                message.content,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        );
      case MessageType.TEXT:
      case MessageType.SYSTEM:
      case MessageType.CALL:
        return Text(
          message.content,
          style: TextStyle(
            color: isMine ? Colors.white : Colors.black87,
            fontSize: 14.5,
          ),
        );
    }
  }

  static String _formatTime(DateTime time) {
    final h = time.hour.toString().padLeft(2, '0');
    final m = time.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}

/// Status icon of an outgoing message.
///
/// * [DeliveryStatus.pending]   -> clock
/// * [DeliveryStatus.sent]      -> single check
/// * [DeliveryStatus.delivered] -> double check
/// * [DeliveryStatus.read]      -> double check (blue)
/// * [DeliveryStatus.failed]    -> red error, tapping it retries the message
class DeliveryIndicator extends StatelessWidget {
  final DeliveryStatus status;
  final VoidCallback? onRetry;
  final Color color;

  const DeliveryIndicator({
    super.key,
    required this.status,
    this.onRetry,
    this.color = Colors.grey,
  });

  @override
  Widget build(BuildContext context) {
    switch (status) {
      case DeliveryStatus.pending:
        return Icon(Icons.schedule, size: 14, color: color);

      case DeliveryStatus.sent:
        return Icon(Icons.check, size: 15, color: color);

      case DeliveryStatus.delivered:
        return Icon(Icons.done_all, size: 15, color: color);

      case DeliveryStatus.read:
        return Icon(Icons.done_all, size: 15, color: Colors.lightBlueAccent);

      case DeliveryStatus.failed:
        return GestureDetector(
          onTap: onRetry,
          child: const Icon(
            Icons.error_outline,
            size: 16,
            color: Colors.redAccent,
          ),
        );
    }
  }
}
