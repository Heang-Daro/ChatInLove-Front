import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../provider/AuthProvider.dart';
import '../provider/ConversationProvider.dart';
import '../service/NotificationService.dart';

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

      conversationProvider.onNewMessageNotification = (message) async {
        if (!_notificationsEnabled) return;

        final chat = conversationProvider.conversations.firstWhere(
          (c) => c.id == message.conversationId,
          orElse: () => ConversationResponse(
            id: message.conversationId,
            type: ConversationType.PRIVATE,
            members: const [],
          ),
        );

        final chatName = chat.name ?? 'New Message';

        await NotificationService.showNotification(
          id: message.conversationId.hashCode,
          title: chatName,
          body: message.previewText,
          payload: message.conversationId,
        );
      };

      conversationProvider.initSocket(authProvider);

      try {
        Provider.of<ChatRepository>(context, listen: false).startListening();
      } catch (_) {}

      conversationProvider.fetchConversations(authProvider);
    });
  }

  Future<void> _enableWebNotifications() async {
    if (!kIsWeb) return;

    final granted = await NotificationService.requestPermission();
    if (!mounted) return;

    if (granted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Browser notifications enabled.')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Notifications were not enabled. Please allow them in your browser settings.')),
      );
    }
  }

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
                  Text('Notification Mode'),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SwitchListTile(
                    title: const Text('Phone Notifications'),
                    subtitle: const Text('Show alerts when someone sends a message'),
                    value: _notificationsEnabled,
                    activeColor: Colors.pinkAccent,
                    onChanged: (bool value) {
                      setDialogState(() => _notificationsEnabled = value);
                      setState(() => _notificationsEnabled = value);
                    },
                  ),
                  if (kIsWeb)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _enableWebNotifications,
                          icon: const Icon(Icons.notifications_none),
                          label: const Text('Enable browser notifications'),
                        ),
                      ),
                    ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Close', style: TextStyle(color: Colors.pinkAccent)),
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
                    ? 'My Profile'
                    : _selectedIndex == 3
                        ? 'Settings'
                        : 'In Love',
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
                      onThemeChanged(value);
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
                'New Group',
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
