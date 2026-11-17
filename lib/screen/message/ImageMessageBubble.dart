import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:love_in_chat/model/Response/MessageResponse.dart';
import 'package:love_in_chat/provider/AuthProvider.dart';
import '../../util/AnimatedComponents.dart';

/// Bubble widget for displaying image messages with interactive fullscreen preview.
class ImageMessageBubble extends StatelessWidget {
  final MessageResponse message;
  final bool isMe;

  const ImageMessageBubble({
    super.key,
    required this.message,
    required this.isMe,
  });

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final token = authProvider.accessToken;
    final headers = (token != null && token.isNotEmpty)
        ? {'Authorization': 'Bearer $token'}
        : null;

    final String timeString = message.createdAt != null
        ? "${message.createdAt!.toLocal().hour.toString().padLeft(2, '0')}:${message.createdAt!.toLocal().minute.toString().padLeft(2, '0')}"
        : "";

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
                          headers: headers,
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
              headers: headers,
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
  }
}
