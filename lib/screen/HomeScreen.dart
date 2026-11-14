import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:love_in_chat/data/repositories/chat_repository.dart';
import 'package:love_in_chat/model/Response/ConversationResponse.dart';
import 'package:love_in_chat/model/emun/ConversationType.dart';
import '../provider/AuthProvider.dart';
import '../provider/ConversationProvider.dart';
import '../service/NotificationService.dart';
import '../util/AppBarStyle.dart';
import 'ChatRequestScreen.dart';
import 'ChatSearchDelegate.dart';
import 'CreateGroupScreen.dart';
import 'GroupCallScreen.dart';
import 'IncomingCallScreen.dart';
import 'ProfileScreen.dart';
import 'setting_util/SettingScreen.dart';
import 'home_body/all.dart';

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

  late final List<Widget> _screens = [
    const AllChat(),
    const ChatRequestScreen(),
    const ProfileScreen(),
    const SettingScreen(),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final authProvider = context.read<AuthProvider>();
      final conversationProvider = context.read<ConversationProvider>();

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
        await NotificationService.showNotification(
          id: message.conversationId.hashCode,
          title: chat.name ?? 'New Message',
          body: message.previewText,
          payload: message.conversationId,
        );
      };

      conversationProvider.initSocket(authProvider);
      // Listen for incoming WebRTC calls and show the ringing overlay.
      conversationProvider.onIncomingCall = (offer) {
        if (!mounted) return;
        final fromId = offer['fromUserId']?.toString() ?? '';
        final isGroup = offer['isGroup'] == true;

        if (isGroup) {
          // ── Incoming group call ──────────────────────────────────────────
          final convId = offer['conversationId']?.toString() ?? '';
          final conv = conversationProvider.conversations
              .where((c) => c.id == convId)
              .firstOrNull;
          final members = conv?.members ?? [];
          final localUserId = context.read<AuthProvider>().currentUserId ?? '';
          final callType = offer['callType']?.toString().toUpperCase();

          Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => GroupCallScreen(
              conversationId: convId,
              groupName:      conv?.name ?? 'Group call',
              isVideo:        callType == 'VIDEO',
              members:        members,
              localUserId:    localUserId,
            ),
          ));
        } else {
          // ── Incoming 1-to-1 call ─────────────────────────────────────────
          String callerName = fromId;
          for (final c in conversationProvider.conversations) {
            final member = c.members
                .where((m) => m.userId == fromId)
                .firstOrNull;
            if (member != null) { callerName = member.username; break; }
          }
          Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => IncomingCallScreen(
              offer: offer,
              callerName: callerName,
              signalingService: conversationProvider.callSignaling,
            ),
          ));
        }
      };
      try {
        context.read<ChatRepository>().startListening();
      } catch (_) {
        // The repository is optional; the app can run without it.
      }
      conversationProvider.fetchConversations(authProvider);
    });
  }

  Future<void> _enableWebNotifications() async {
    if (!kIsWeb) return;
    final granted = await NotificationService.requestPermission();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(granted
            ? 'Browser notifications enabled.'
            : 'Notifications were not enabled. Allow them in browser settings.'),
      ),
    );
  }

  void _showNotificationSettings() {
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
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
                onChanged: (value) {
                  setDialogState(() => _notificationsEnabled = value);
                  setState(() => _notificationsEnabled = value);
                },
              ),
              if (kIsWeb)
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _enableWebNotifications,
                    icon: const Icon(Icons.notifications_none),
                    label: const Text('Enable browser notifications'),
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
        ),
      ),
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
            if (_selectedIndex != 3)
              IconButton(
                tooltip: 'Search people',
                onPressed: () => showSearch(
                  context: context,
                  delegate: ChatSearchDelegate(),
                ),
                icon: const Icon(Icons.search_rounded, color: Colors.white),
              ),
            PopupMenuButton<dynamic>(
              icon: const Icon(Icons.more_vert, color: Colors.white),
              onSelected: (value) {
                if (value is ThemeMode) {
                  widget.onThemeChanged(value);
                } else if (value == 'notification_mode') {
                  _showNotificationSettings();
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem<ThemeMode>(
                  value: ThemeMode.light,
                  child: Row(children: [Icon(Icons.light_mode, color: Colors.pinkAccent), SizedBox(width: 10), Text('Light Theme')]),
                ),
                const PopupMenuItem<ThemeMode>(
                  value: ThemeMode.dark,
                  child: Row(children: [Icon(Icons.dark_mode, color: Colors.pinkAccent), SizedBox(width: 10), Text('Dark Theme')]),
                ),
                const PopupMenuItem<ThemeMode>(
                  value: ThemeMode.system,
                  child: Row(children: [Icon(Icons.brightness_auto, color: Colors.pinkAccent), SizedBox(width: 10), Text('System Default')]),
                ),
                const PopupMenuDivider(),
                const PopupMenuItem<String>(
                  value: 'notification_mode',
                  child: Row(children: [Icon(Icons.notifications, color: Colors.pinkAccent), SizedBox(width: 10), Text('Notification Mode')]),
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
              icon: const Icon(Icons.group_add_rounded, color: Colors.white),
              label: const Text(
                'New Group',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const CreateGroupScreen()),
              ),
            )
          : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) => setState(() => _selectedIndex = index),
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.wechat_outlined),
            selectedIcon: Icon(Icons.wechat, color: Colors.pinkAccent),
            label: 'Chats',
          ),
          NavigationDestination(
            icon: Consumer<ConversationProvider>(
              builder: (_, convo, __) {
                final count = convo.incomingRequests.length;
                if (count == 0) return const Icon(Icons.message_outlined);
                return Badge(
                  label: Text('$count'),
                  backgroundColor: Colors.pinkAccent,
                  child: const Icon(Icons.message_outlined),
                );
              },
            ),
            selectedIcon: Consumer<ConversationProvider>(
              builder: (_, convo, __) {
                final count = convo.incomingRequests.length;
                if (count == 0) return const Icon(Icons.message, color: Colors.pinkAccent);
                return Badge(
                  label: Text('$count'),
                  backgroundColor: Colors.pinkAccent,
                  child: const Icon(Icons.message, color: Colors.pinkAccent),
                );
              },
            ),
            label: 'Requests',
          ),
          const NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person, color: Colors.pinkAccent),
            label: 'Profile',
          ),
          const NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings, color: Colors.pinkAccent),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}
