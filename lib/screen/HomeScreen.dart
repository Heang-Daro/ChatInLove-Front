import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:love_in_chat/data/repositories/chat_repository.dart';
import 'package:love_in_chat/model/Response/ConversationResponse.dart';
import 'package:love_in_chat/model/emun/ConversationType.dart';
import '../provider/AuthProvider.dart';
import '../provider/ConversationProvider.dart';
import '../service/NotificationService.dart';
import '../util/AnimatedComponents.dart';
import '../util/AppBarStyle.dart';
import 'ChatRequestScreen.dart';
import 'ChatSearchDelegate.dart';
import 'ConversationPage.dart';
import 'CreateGroupDialog.dart';
import 'ProfileScreen.dart';
import 'setting_util/SettingScreen.dart';
import 'home_body/all.dart';
import 'message/ConversationTile.dart';

class HomeScreen extends StatefulWidget {
  final Function(ThemeMode) onThemeChanged;
  final ThemeMode currentThemeMode;

  const HomeScreen({
    super.key,
    required this.onThemeChanged,
    required this.currentThemeMode,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;
  bool _notificationsEnabled = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final conversationProvider = Provider.of<ConversationProvider>(context, listen: false);

      // Listen for incoming messages on other chats and post native Android status bar notification with ringtone sound!
      conversationProvider.onNewMessageNotification = (message) {
        if (!_notificationsEnabled) return;

        // Find conversation details
        final chat = conversationProvider.conversations.firstWhere(
          (c) => c.id == message.conversationId,
          orElse: () => ConversationResponse(
            id: message.conversationId,
            type: ConversationType.PRIVATE,
            members: const [],
          ),
        );

        final chatName = chat.name ?? "New Message";

        // Post native Android system notification in notification bar with sound!
        NotificationService.showNotification(
          id: message.conversationId.hashCode,
          title: chatName,
          body: message.previewText,
          payload: message.conversationId,
        );
      };

      // Initialize real-time WebSocket connection
      conversationProvider.initSocket(authProvider);

      // The offline repository listens to the same socket and writes every
      // incoming message into the local SQLite database.
      try {
        Provider.of<ChatRepository>(context, listen: false).startListening();
      } catch (_) {
        // The repository is optional, the app also works without it.
      }

      // Fetch conversation list
      conversationProvider.fetchConversations(authProvider);
    });
  }

  late final List<Widget> _screens = [
    const AllChat(),
    const ChatRequestScreen(),
    const ProfileScreen(),
    const SettingScreen(),
  ];

  void _showNotificationSettings() {
    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Row(
                children: [
                  Icon(Icons.notifications_active, color: Colors.pinkAccent),
                  SizedBox(width: 8),
                  Text("Notification Mode"),
                ],
              ),
              content: SwitchListTile(
                title: const Text("Phone Notifications"),
                subtitle: const Text("Show alerts when someone sends a message"),
                value: _notificationsEnabled,
                activeColor: Colors.pinkAccent,
                onChanged: (bool value) {
                  setDialogState(() => _notificationsEnabled = value);
                  setState(() => _notificationsEnabled = value);
                },
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text(
                    "Close",
                    style: TextStyle(color: Colors.pinkAccent),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppBarStyle.backgroundColor,
        foregroundColor: Colors.white,
        shape: AppBarStyle.bottomBorder,
        title: Row(
          children: [
            Icon(
              _selectedIndex == 2
                  ? Icons.person
                  : _selectedIndex == 3
                  ? Icons.settings
                  : Icons.favorite,
              color: Colors.white,
              size: 26,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                _selectedIndex == 2
                    ? "My Profile"
                    : _selectedIndex == 3
                    ? "Settings"
                    : "In Love",
                style: AppBarStyle.titleStyle,
              ),
            ),
            Row(
              children: [
                if (_selectedIndex == 2)
                  IconButton(
                    onPressed: () {},
                    icon: const Icon(Icons.edit, color: Colors.white),
                  )
                else if (_selectedIndex != 3)
                  IconButton(
                    onPressed: () {
                      showSearch(
                        context: context,
                        delegate: ChatSearchDelegate(),
                      );
                    },
                    icon: const Icon(Icons.search, color: Colors.white),
                  ),
                const SizedBox(width: 4),
                PopupMenuButton<dynamic>(
                  icon: const Icon(Icons.more_vert, color: Colors.white),
                  onSelected: (value) {
                    if (value is ThemeMode) {
                      widget.onThemeChanged(value);
                    } else if (value == 'notification_mode') {
                      _showNotificationSettings();
                    }
                  },
                  itemBuilder: (BuildContext context) => [
                    const PopupMenuItem<ThemeMode>(
                      value: ThemeMode.light,
                      child: Row(
                        children: [
                          Icon(Icons.light_mode, color: Colors.pinkAccent),
                          SizedBox(width: 10),
                          Text('Light Theme'),
                        ],
                      ),
                    ),
                    const PopupMenuItem<ThemeMode>(
                      value: ThemeMode.dark,
                      child: Row(
                        children: [
                          Icon(Icons.dark_mode, color: Colors.pinkAccent),
                          SizedBox(width: 10),
                          Text('Dark Theme'),
                        ],
                      ),
                    ),
                    const PopupMenuItem<ThemeMode>(
                      value: ThemeMode.system,
                      child: Row(
                        children: [
                          Icon(Icons.brightness_auto, color: Colors.pinkAccent),
                          SizedBox(width: 10),
                          Text('System Default'),
                        ],
                      ),
                    ),
                    const PopupMenuDivider(),
                    const PopupMenuItem<String>(
                      value: 'notification_mode',
                      child: Row(
                        children: [
                          Icon(Icons.notifications, color: Colors.pinkAccent),
                          SizedBox(width: 10),
                          Text('Notification Mode'),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
      body: _screens[_selectedIndex],
      floatingActionButton: _selectedIndex == 0
          ? FloatingActionButton.extended(
              backgroundColor: Colors.pinkAccent,
              elevation: 4,
              icon: const Icon(Icons.group_add, color: Colors.white),
              label: const Text(
                "New Group",
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (context) => const CreateGroupDialog(),
                );
              },
            )
          : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) {
          setState(() => _selectedIndex = index);
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.wechat_outlined),
            selectedIcon: Icon(Icons.wechat, color: Colors.pinkAccent),
            label: 'Chats',
          ),
          NavigationDestination(
            icon: Icon(Icons.message_outlined),
            selectedIcon: Icon(Icons.message, color: Colors.pinkAccent),
            label: 'Requests',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person, color: Colors.pinkAccent),
            label: 'Profile',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings, color: Colors.pinkAccent),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}

// Chats tab: now uses ConversationTile (correct name + working tap)
class AllChatWithProvider extends StatelessWidget {
  const AllChatWithProvider({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer2<ConversationProvider, AuthProvider>(
      builder: (context, provider, auth, child) {
        if (provider.isLoading) {
          return const Center(
            child: CircularProgressIndicator(color: Colors.pinkAccent),
          );
        }

        if (provider.errorMessage != null) {
          return Center(
            child: Text(
              provider.errorMessage!,
              style: const TextStyle(color: Colors.grey),
            ),
          );
        }

        final conversations = provider.conversations;

        if (conversations.isEmpty) {
          return const Center(
            child: Text(
              "No conversations available",
              style: TextStyle(color: Colors.grey),
            ),
          );
        }

        final currentUserId = auth.currentUserId;
        print('AllChatWithProvider currentUserId = $currentUserId');

        if (currentUserId == null || currentUserId.isEmpty) {
          return const Center(
            child: CircularProgressIndicator(color: Colors.pinkAccent),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          itemCount: conversations.length,
          itemBuilder: (context, index) {
            return ConversationTile(
              chat: conversations[index],
              currentUserId: currentUserId,
            );
          },
        );
      },
    );
  }
}