import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'package:love_in_chat/api/api.dart';
import 'package:love_in_chat/model/Response/MessageResponse.dart';
import 'package:love_in_chat/model/emun/MessageType.dart';
import 'package:love_in_chat/provider/AuthProvider.dart';
import 'package:love_in_chat/provider/ConversationProvider.dart';
import 'package:love_in_chat/service/CacheService.dart';
import 'package:love_in_chat/util/AppBarStyle.dart';

/// Telegram style "Storage" screen.
///
/// Shows everything the app keeps on the device:
///  * how much space the cache uses
///  * how many chats / messages / photos are cached
///  * the cached photo, video, voice and file links of every chat
/// and allows removing any of it.
class CacheScreen extends StatefulWidget {
  const CacheScreen({super.key});

  @override
  State<CacheScreen> createState() => _CacheScreenState();
}

class _CacheScreenState extends State<CacheScreen> {
  CacheStats _stats = CacheStats.empty;
  List<CachedChatInfo> _chats = const [];
  bool _loading = true;
  String? _userId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  String? _currentUserId() {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    return auth.currentUserId;
  }

  Future<void> _load() async {
    final userId = _currentUserId();
    if (userId == null || userId.isEmpty) {
      if (mounted) setState(() => _loading = false);
      return;
    }

    _userId = userId;
    final stats = await CacheService.getStats(userId);
    final chats = await CacheService.listCachedChats(userId);

    if (!mounted) return;
    setState(() {
      _stats = stats;
      _chats = chats;
      _loading = false;
    });
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) return "0 B";
    const units = ["B", "KB", "MB", "GB"];
    var value = bytes.toDouble();
    var unit = 0;
    while (value >= 1024 && unit < units.length - 1) {
      value /= 1024;
      unit++;
    }
    final text = value >= 100 || unit == 0
        ? value.toStringAsFixed(0)
        : value.toStringAsFixed(1);
    return "$text ${units[unit]}";
  }

  // ---------------------------------------------------------------------------
  // Actions
  // ---------------------------------------------------------------------------

  Future<void> _clearOne(CachedChatInfo chat) async {
    final userId = _userId;
    if (userId == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Clear cached chat?"),
        content: Text(
          "The saved messages of “${chat.name}” will be removed from this "
          "device. They will be downloaded again the next time you open the chat.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("Cancel"),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(
              "Clear",
              style: TextStyle(color: Colors.pinkAccent),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await CacheService.clearConversationCache(userId, chat.conversationId);

    // The chat is still open in the app, so drop the in-memory copy too.
    final conversationProvider =
        Provider.of<ConversationProvider>(context, listen: false);
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    await conversationProvider.clearConversationMessages(
      authProvider,
      chat.conversationId,
    );

    await _load();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text("Cached messages of ${chat.name} removed"),
        backgroundColor: Colors.pinkAccent,
      ),
    );
  }

  Future<void> _clearMedia() async {
    final userId = _userId;
    if (userId == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Clear cached media?"),
        content: const Text(
          "All cached photos, videos, voice notes and documents will be "
          "removed. Text messages stay on the device.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("Cancel"),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(
              "Clear",
              style: TextStyle(color: Colors.pinkAccent),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final removed = await CacheService.clearCachedMedia(userId);
    await _load();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text("$removed cached file(s) removed"),
        backgroundColor: Colors.pinkAccent,
      ),
    );
  }

  Future<void> _clearEverything() async {
    final userId = _userId;
    if (userId == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Clear all cache?"),
        content: const Text(
          "Every message and file saved on this device will be removed. "
          "Everything is downloaded again when you are online.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("Cancel"),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(
              "Clear all",
              style: TextStyle(color: Colors.pinkAccent),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final conversationProvider =
        Provider.of<ConversationProvider>(context, listen: false);
    await conversationProvider.clearLocalCache(authProvider);

    await _load();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("Cache cleared"),
        backgroundColor: Colors.pinkAccent,
      ),
    );
  }

  void _copyLink(String url) {
    Clipboard.setData(ClipboardData(text: url));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("Link copied"),
        backgroundColor: Colors.pinkAccent,
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Media sheet: the cached links of one chat
  // ---------------------------------------------------------------------------

  Future<void> _openMedia(CachedChatInfo chat) async {
    final userId = _userId;
    if (userId == null) return;

    final media = await CacheService.cachedMediaOfConversation(
      userId,
      chat.conversationId,
    );

    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (context) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.6,
          maxChildSize: 0.9,
          builder: (context, scrollController) {
            return Column(
              children: [
                Container(
                  margin: const EdgeInsets.only(top: 10, bottom: 6),
                  width: 45,
                  height: 5,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          chat.name,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      ),
                      Text(
                        "${media.length} file(s)",
                        style: TextStyle(color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 18),
                Expanded(
                  child: media.isEmpty
                      ? Center(
                          child: Text(
                            "No cached files in this chat",
                            style: TextStyle(color: Colors.grey.shade600),
                          ),
                        )
                      : ListView.builder(
                          controller: scrollController,
                          itemCount: media.length,
                          itemBuilder: (context, index) {
                            final message = media[index];
                            final url = resolveFileUrl(message.content);
                            return _MediaTile(
                              message: message,
                              url: url,
                              onTap: () => _previewImage(message, url),
                              onCopy: () => _copyLink(url),
                            );
                          },
                        ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _previewImage(MessageResponse message, String url) {
    if (message.type != MessageType.IMAGE) {
      _copyLink(url);
      return;
    }

    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: InteractiveViewer(
                child: Image.network(
                  url,
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stack) => const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      "Image could not be loaded",
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  Text(
                    url,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white70, fontSize: 11),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      TextButton.icon(
                        onPressed: () => _copyLink(url),
                        icon: const Icon(Icons.copy, color: Colors.pinkAccent),
                        label: const Text(
                          "Copy link",
                          style: TextStyle(color: Colors.pinkAccent),
                        ),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text(
                          "Close",
                          style: TextStyle(color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBarStyle.build(
        title: "Storage",
        actions: [
          if (!_loading && _stats.totalBytes > 0)
            IconButton(
              tooltip: "Clear all cache",
              onPressed: _clearEverything,
              icon: const Icon(Icons.delete_sweep),
            ),
        ],
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: Colors.pinkAccent),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _buildSummaryCard(),
                const SizedBox(height: 16),
                _buildActions(),
                const SizedBox(height: 16),
                Text(
                  "Cached chats",
                  style: TextStyle(
                    color: Colors.grey.shade700,
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 8),
                if (_chats.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 30),
                    child: Column(
                      children: [
                        Icon(Icons.sd_storage_outlined,
                            size: 54, color: Colors.grey.shade400),
                        const SizedBox(height: 10),
                        Text(
                          "Nothing cached yet",
                          style: TextStyle(color: Colors.grey.shade600),
                        ),
                      ],
                    ),
                  )
                else
                  ..._chats.map((chat) => _buildChatTile(chat)),
              ],
            ),
    );
  }

  Widget _buildSummaryCard() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          children: [
            const Icon(Icons.sd_storage, size: 40, color: Colors.pinkAccent),
            const SizedBox(height: 8),
            Text(
              _formatBytes(_stats.totalBytes),
              style: const TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: Colors.pinkAccent,
              ),
            ),
            const Text(
              "used by the local cache",
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                _statBox("Chats", "${_stats.cachedChats}"),
                _statBox("Messages", "${_stats.messageCount}"),
                _statBox("Files", "${_stats.mediaCount}"),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _statBox(String label, String value) {
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.pinkAccent,
            ),
          ),
          Text(
            label,
            style: const TextStyle(color: Colors.grey, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildActions() {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _stats.mediaCount == 0 ? null : _clearMedia,
            icon: const Icon(Icons.image_outlined, size: 18),
            label: const Text("Clear files"),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.pinkAccent,
              side: const BorderSide(color: Colors.pinkAccent),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _stats.totalBytes == 0 ? null : _clearEverything,
            icon: const Icon(Icons.delete_outline, size: 18),
            label: const Text("Clear all"),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.redAccent,
              side: const BorderSide(color: Colors.redAccent),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildChatTile(CachedChatInfo chat) {
    return Card(
      elevation: 1,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: Colors.pinkAccent.withOpacity(0.15),
          child: const Icon(Icons.forum, color: Colors.pinkAccent),
        ),
        title: Text(
          chat.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
        ),
        subtitle: Text(
          "${chat.messageCount} messages • ${chat.mediaCount} files • "
          "${_formatBytes(chat.sizeBytes)}",
          style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: "Show cached files",
              onPressed: () => _openMedia(chat),
              icon: const Icon(Icons.photo_library_outlined,
                  color: Colors.pinkAccent),
            ),
            IconButton(
              tooltip: "Clear this chat",
              onPressed: () => _clearOne(chat),
              icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
            ),
          ],
        ),
        onTap: () => _openMedia(chat),
      ),
    );
  }
}

/// One cached file row: thumbnail, name and the stored link.
class _MediaTile extends StatelessWidget {
  final MessageResponse message;
  final String url;
  final VoidCallback onTap;
  final VoidCallback onCopy;

  const _MediaTile({
    required this.message,
    required this.url,
    required this.onTap,
    required this.onCopy,
  });

  IconData get _icon {
    switch (message.type) {
      case MessageType.IMAGE:
        return Icons.image;
      case MessageType.VIDEO:
        return Icons.videocam;
      case MessageType.VOICE:
        return Icons.mic;
      case MessageType.FILE:
        return Icons.insert_drive_file;
      case MessageType.TEXT:
      case MessageType.SYSTEM:
      case MessageType.CALL:
        return Icons.insert_drive_file;
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = message.previewText;

    return ListTile(
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          width: 44,
          height: 44,
          child: message.type == MessageType.IMAGE
              ? Image.network(
                  url,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stack) => Container(
                    color: Colors.grey.shade200,
                    child: const Icon(Icons.broken_image, color: Colors.grey),
                  ),
                )
              : Container(
                  color: Colors.pinkAccent.withOpacity(0.12),
                  child: Icon(_icon, color: Colors.pinkAccent),
                ),
        ),
      ),
      title: Text(
        name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        url,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: Colors.grey.shade600, fontSize: 11),
      ),
      trailing: IconButton(
        tooltip: "Copy link",
        onPressed: onCopy,
        icon: const Icon(Icons.copy, size: 18, color: Colors.pinkAccent),
      ),
      onTap: onTap,
    );
  }
}
