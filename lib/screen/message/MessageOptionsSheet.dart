import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'package:love_in_chat/model/Response/MessageResponse.dart';
import 'package:love_in_chat/model/emun/MessageType.dart';
import 'package:love_in_chat/provider/AuthProvider.dart';
import 'package:love_in_chat/provider/ConversationProvider.dart';
import '../../util/AnimatedComponents.dart';

/// Helper methods for presenting message action options (Copy, Edit, Delete)
/// and confirmation dialogs.
class MessageOptionsSheet {
  static void showOptions({
    required BuildContext context,
    required MessageResponse message,
    required bool isMe,
    required VoidCallback onStartEditing,
  }) {
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
                    onStartEditing();
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

  static void _confirmDelete(BuildContext context, MessageResponse message) {
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
              if (!context.mounted) return;
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
}
