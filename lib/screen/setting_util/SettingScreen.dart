import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:love_in_chat/provider/AuthProvider.dart';
import 'package:love_in_chat/provider/ConversationProvider.dart';

import '../chat/chat_list_screen.dart';
import 'CacheScreen.dart';
import 'data_storage_screen.dart';
import 'device.dart';

class SettingScreen extends StatelessWidget {
  const SettingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16.0),
      children: [
        const Text(
          "Preferences",
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.pinkAccent,
          ),
        ),
        const SizedBox(height: 10),
        Card(
          elevation: 2,
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.person_outline, color: Colors.pinkAccent),
                title: const Text("Account"),
                subtitle: const Text("Manage your profile info and email"),
                trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                onTap: () {
                  // Handle Account navigation
                },
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.chat_bubble_outline, color: Colors.pinkAccent),
                title: const Text("Chat Setting"),
                subtitle: const Text("Wallpaper, chat history, notifications"),
                trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                onTap: () {
                  // Handle Chat Setting navigation
                },
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.lock_outline, color: Colors.pinkAccent),
                title: const Text("Privacy and Security"),
                subtitle: const Text("Blocked users, password, security alerts"),
                trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                onTap: () {
                  // Handle Privacy and Security navigation
                },
              ),
              const Divider(height: 1),
              const DeviceSecurityTile(),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.offline_bolt_outlined,
                    color: Colors.pinkAccent),
                title: const Text("Offline chats"),
                subtitle: const Text(
                    "Local SQLite database: chat list, messages and sync"),
                trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const ChatListScreen()),
                  );
                },
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.data_usage_outlined,
                    color: Colors.pinkAccent),
                title: const Text("Data & Storage"),
                subtitle: const Text(
                    "See how much space the app uses and clear the cache"),
                trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const DataStorageScreen()),
                  );
                },
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.sd_storage_outlined,
                    color: Colors.pinkAccent),
                title: const Text("Storage"),
                subtitle: const Text(
                    "See and clear the chats, photos and files saved on this device"),
                trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const CacheScreen()),
                  );
                },
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.cleaning_services_outlined,
                    color: Colors.pinkAccent),
                title: const Text("Clear local cache"),
                subtitle: const Text(
                    "Remove the chats saved on this device (they will be downloaded again)"),
                trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                onTap: () async {
                  final authProvider =
                      Provider.of<AuthProvider>(context, listen: false);
                  final conversationProvider =
                      Provider.of<ConversationProvider>(context, listen: false);

                  await conversationProvider.clearLocalCache(authProvider);
                  await conversationProvider.fetchConversations(authProvider);

                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text("Local cache cleared"),
                      backgroundColor: Colors.pinkAccent,
                    ),
                  );
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        const Text(
          "Support & Legal",
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.pinkAccent,
          ),
        ),
        const SizedBox(height: 10),
        Card(
          elevation: 2,
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.privacy_tip_outlined, color: Colors.pinkAccent),
                title: const Text("Privacy Policy"),
                subtitle: const Text("Read our terms and data policies"),
                trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                onTap: () {
                  // Handle Privacy Policy navigation
                },
              ),
            ],
          ),
        ),
      ],
    );
  }
}