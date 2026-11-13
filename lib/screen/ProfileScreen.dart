import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:love_in_chat/provider/AuthProvider.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<AuthProvider>(
      builder: (context, authProvider, child) {
        // Extract username or fallback based on current user / token claims
        final String displayName = authProvider.currentUser?.username ??
            (authProvider.currentUserId != null ? "User_${authProvider.currentUserId!.substring(0, min(6, authProvider.currentUserId!.length))}" : "My Profile");

        final String displayEmail = authProvider.currentUser?.email ?? "lovechat.user@app.com";

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              const SizedBox(height: 20),
              // Profile Avatar with Pink Border
              Stack(
                alignment: Alignment.bottomRight,
                children: [
                  Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.pinkAccent, width: 3),
                    ),
                    child: const CircleAvatar(
                      radius: 55,
                      backgroundColor: Colors.white,
                      child: Icon(Icons.person, size: 60, color: Colors.pinkAccent),
                    ),
                  ),
                  const CircleAvatar(
                    radius: 18,
                    backgroundColor: Colors.pinkAccent,
                    child: Icon(Icons.favorite, size: 16, color: Colors.white),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                displayName,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Colors.pinkAccent,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                displayEmail,
                style: const TextStyle(fontSize: 14, color: Colors.grey),
              ),
              const SizedBox(height: 24),
              // Stats Row
              const Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _ProfileStatCard(title: "Matches", count: "128"),
                  _ProfileStatCard(title: "Likes", count: "542"),
                  _ProfileStatCard(title: "Views", count: "1.2K"),
                ],
              ),
              const SizedBox(height: 30),
              // Profile Options List
              Card(
                elevation: 2,
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.favorite_border, color: Colors.pinkAccent),
                      title: const Text("My Interests"),
                      trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                      onTap: () {},
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.photo_library_outlined, color: Colors.pinkAccent),
                      title: const Text("Photo Gallery"),
                      trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                      onTap: () {},
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.lock_outline, color: Colors.pinkAccent),
                      title: const Text("Privacy & Security"),
                      trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                      onTap: () {},
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.logout, color: Colors.redAccent),
                      title: const Text("Log Out", style: TextStyle(color: Colors.redAccent)),
                      trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                      onTap: () async {
                        await authProvider.logout();
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ProfileStatCard extends StatelessWidget {
  final String title;
  final String count;

  const _ProfileStatCard({required this.title, required this.count});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          count,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.pinkAccent,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          title,
          style: const TextStyle(fontSize: 12, color: Colors.grey),
        ),
      ],
    );
  }
}

int min(int a, int b) => a < b ? a : b;