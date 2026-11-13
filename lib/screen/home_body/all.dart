import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:love_in_chat/provider/AuthProvider.dart';
import 'package:love_in_chat/provider/ConversationProvider.dart';
import 'package:love_in_chat/model/Response/ConversationResponse.dart';
import '../../model/emun/ConversationType.dart';
import '../message/ConversationTile.dart';
import 'private.dart';
import 'group.dart';

class AllChat extends StatefulWidget {
  const AllChat({super.key});

  @override
  State<AllChat> createState() => _AllChatState();
}

class _AllChatState extends State<AllChat> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fetchConversations();
      _initWebSocket();
    });

    _scrollController.addListener(_onScroll);
  }

  void _fetchConversations() {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    Provider.of<ConversationProvider>(context, listen: false).fetchConversations(authProvider);
  }

  void _initWebSocket() {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final conversationProvider = Provider.of<ConversationProvider>(context, listen: false);

    // Initialize socket connection via ConversationProvider for centralized real-time updates
    conversationProvider.initSocket(authProvider);
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      Provider.of<ConversationProvider>(context, listen: false).loadMoreConversations(authProvider);
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ConversationProvider>(
      builder: (context, conversationProvider, child) {
        final allConversations = conversationProvider.conversations;

        // Filter chats using your ConversationType enum
        final privateChats = allConversations.where((c) => c.type == ConversationType.PRIVATE).toList();
        final groupChats = allConversations.where((c) => c.type == ConversationType.GROUP).toList();

        return Column(
          children: [
            // Pill-Shaped Filter Bar Header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
              child: SizedBox(
                height: 25,
                child: TabBar(
                  controller: _tabController,
                  labelColor: Colors.pink,
                  unselectedLabelColor: const Color(0xFF808080),
                  labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  tabs: const [
                    Tab(text: "All"),
                    Tab(text: "Private"),
                    Tab(text: "Groups"),
                  ],
                ),
              ),
            ),

            // Small hint while the list comes from the local cache
            if (conversationProvider.showingCachedData)
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                color: Colors.pinkAccent.withOpacity(0.08),
                child: Row(
                  children: [
                    const SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.pinkAccent,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        "Showing saved messages — syncing…",
                        style: TextStyle(
                          color: Colors.grey.shade700,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            // Tab Content Views
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildChatList(conversationProvider, allConversations),
                  PrivateChat(chats: privateChats),
                  GroupChat(chats: groupChats),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildChatList(ConversationProvider provider, List<ConversationResponse> chats) {
    if (provider.isLoading && chats.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.pinkAccent),
      );
    }

    if (chats.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.chat_bubble_outline, size: 64, color: Colors.grey),
            SizedBox(height: 12),
            Text(
              "No chats available",
              style: TextStyle(color: Colors.grey, fontSize: 16),
            ),
            SizedBox(height: 4),
            Text(
              "Start a conversation to see it here",
              style: TextStyle(color: Colors.pinkAccent, fontSize: 13),
            ),
          ],
        ),
      );
    }

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final currentUserId = authProvider.currentUserId ?? "";

    return RefreshIndicator(
      color: Colors.pinkAccent,
      onRefresh: () async => _fetchConversations(),
      child: ListView.builder(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        itemCount: chats.length + (provider.isLoadingMoreConversations ? 1 : 0),
        itemBuilder: (context, index) {
          // Render loading spinner at the bottom when fetching more pages
          if (index == chats.length) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(10.0),
                child: CircularProgressIndicator(color: Colors.pinkAccent),
              ),
            );
          }

          return ConversationTile(
            chat: chats[index],
            currentUserId: currentUserId,
          );
        },
      ),
    );
  }
}