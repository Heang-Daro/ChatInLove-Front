import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:love_in_chat/provider/AuthProvider.dart';
import 'package:love_in_chat/provider/ConversationProvider.dart';

import '../chat/chat_list_screen.dart';
import 'CacheScreen.dart';
import 'account_settings_screen.dart';
import 'chat_settings_screen.dart';
import 'data_storage_screen.dart';
import 'device.dart';
import 'privacy_security_screen.dart';

class SettingScreen extends StatelessWidget {
  const SettingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('Preferences', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.pinkAccent)),
        const SizedBox(height: 10),
        Card(
          elevation: 2,
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.person_outline, color: Colors.pinkAccent),
                title: const Text('Account'),
                subtitle: const Text('View your profile information and sign-in'),
                trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AccountSettingsScreen())),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.chat_bubble_outline, color: Colors.pinkAccent),
                title: const Text('Chat settings'),
                subtitle: const Text('Choose a background for your conversations'),
                trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ChatSettingsScreen())),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.lock_outline, color: Colors.pinkAccent),
                title: const Text('Privacy and Security'),
                subtitle: const Text('Edit profile information and change your password'),
                trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PrivacySecurityScreen())),
              ),
              const Divider(height: 1),
              const DeviceSecurityTile(),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.offline_bolt_outlined, color: Colors.pinkAccent),
                title: const Text('Offline chats'),
                subtitle: const Text('Local chat list, messages and sync'),
                trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ChatListScreen())),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.data_usage_outlined, color: Colors.pinkAccent),
                title: const Text('Data & Storage'),
                subtitle: const Text('Review app storage and clear cache'),
                trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const DataStorageScreen())),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.sd_storage_outlined, color: Colors.pinkAccent),
                title: const Text('Storage'),
                subtitle: const Text('Manage cached chats and media'),
                trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CacheScreen())),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.cleaning_services_outlined, color: Colors.pinkAccent),
                title: const Text('Clear local cache'),
                subtitle: const Text('Remove chats saved on this device'),
                trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                onTap: () async {
                  final auth = context.read<AuthProvider>();
                  final conversations = context.read<ConversationProvider>();
                  await conversations.clearLocalCache(auth);
                  await conversations.fetchConversations(auth);
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Local cache cleared'), backgroundColor: Colors.pinkAccent),
                  );
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        const Text('Support & Legal', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.pinkAccent)),
        const SizedBox(height: 10),
        Card(
          elevation: 2,
          child: ListTile(
            leading: const Icon(Icons.privacy_tip_outlined, color: Colors.pinkAccent),
            title: const Text('Privacy Policy'),
            subtitle: const Text('Read our terms and data policies'),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: () {},
          ),
        ),
      ],
    );
  }
}
