import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:love_in_chat/provider/AuthProvider.dart';
import 'package:love_in_chat/provider/ConversationProvider.dart';
import 'package:love_in_chat/model/Response/ConversationResponse.dart';

class ChatRequestScreen extends StatefulWidget {
  const ChatRequestScreen({super.key});

  @override
  State<ChatRequestScreen> createState() => _ChatRequestScreenState();
}

class _ChatRequestScreenState extends State<ChatRequestScreen> {
  // Tracks conversations currently being actioned to disable their buttons.
  final Set<String> _processing = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final auth = context.read<AuthProvider>();
      context.read<ConversationProvider>().fetchConversations(auth);
    });
  }

  Future<void> _accept(ConversationResponse request) async {
    setState(() => _processing.add(request.id));
    final auth = context.read<AuthProvider>();
    final ok = await context.read<ConversationProvider>().acceptRequest(auth, request.id);
    if (!mounted) return;
    setState(() => _processing.remove(request.id));
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(ok ? 'Chat request accepted!' : 'Could not accept request.'),
      backgroundColor: ok ? Colors.green : Colors.redAccent,
      behavior: SnackBarBehavior.floating,
    ));
  }

  Future<void> _reject(ConversationResponse request) async {
    setState(() => _processing.add(request.id));
    final auth = context.read<AuthProvider>();
    final ok = await context.read<ConversationProvider>().rejectRequest(auth, request.id);
    if (!mounted) return;
    setState(() => _processing.remove(request.id));
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(ok ? 'Chat request declined.' : 'Could not decline request.'),
      backgroundColor: ok ? Colors.grey : Colors.redAccent,
      behavior: SnackBarBehavior.floating,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Consumer2<AuthProvider, ConversationProvider>(
      builder: (context, auth, convo, _) {
        final currentUserId = auth.currentUserId ?? '';
        final requests = convo.pendingRequests(currentUserId);

        if (convo.isLoading) {
          return const Center(child: CircularProgressIndicator(color: Colors.pinkAccent));
        }

        if (requests.isEmpty) {
          return const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.mark_chat_unread_outlined, size: 56, color: Colors.pinkAccent),
                SizedBox(height: 12),
                Text(
                  'No pending chat requests',
                  style: TextStyle(color: Colors.pinkAccent, fontSize: 16),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          itemCount: requests.length,
          padding: const EdgeInsets.all(8),
          itemBuilder: (context, index) {
            final request = requests[index];
            final processing = _processing.contains(request.id);

            // Find the requester's display name from the members list.
            final requesterMember = request.members
                .where((m) => m.userId == request.requesterId)
                .firstOrNull;
            final displayName = requesterMember?.username ??
                request.name ??
                'Unknown';

            // Last message preview or a default invite text.
            final preview = request.lastMessage?.content?.isNotEmpty == true
                ? request.lastMessage!.content!
                : 'Wants to start a conversation with you.';

            final timeAgo = request.createdAt != null
                ? _formatTimeAgo(request.createdAt!)
                : '';

            return Card(
              elevation: 2,
              margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: Colors.pinkAccent,
                  child: Text(
                    displayName.isNotEmpty ? displayName[0].toUpperCase() : '?',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                ),
                title: Text(
                  displayName,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 4),
                    Text(
                      preview,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (timeAgo.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        timeAgo,
                        style: const TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ],
                  ],
                ),
                isThreeLine: true,
                trailing: processing
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.pinkAccent,
                        ),
                      )
                    : Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: 'Accept',
                            icon: const Icon(Icons.check_circle, color: Colors.green),
                            onPressed: () => _accept(request),
                          ),
                          IconButton(
                            tooltip: 'Decline',
                            icon: const Icon(Icons.cancel, color: Colors.redAccent),
                            onPressed: () => _reject(request),
                          ),
                        ],
                      ),
              ),
            );
          },
        );
      },
    );
  }

  String _formatTimeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${dt.day}/${dt.month}/${dt.year}';
  }
}
