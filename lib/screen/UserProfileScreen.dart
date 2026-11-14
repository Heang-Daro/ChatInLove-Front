import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import 'package:love_in_chat/model/Response/ConversationResponse.dart';
import 'package:love_in_chat/model/Response/UserResponse.dart';
import 'package:love_in_chat/model/emun/ConversationStatus.dart';
import 'package:love_in_chat/provider/AuthProvider.dart';
import 'package:love_in_chat/provider/ConversationProvider.dart';
import 'ConversationPage.dart';
import 'setting_util/privacy_security_screen.dart';

/// A unified profile screen that works for two modes:
///   • [isOwner] = true  → shows edit controls (change avatar / foreground,
///                          Privacy & Security, Log Out).
///   • [isOwner] = false → shows visitor actions (Send Message, plus a
///                          read-only view of the profile).
///
/// When [user] is null and [isOwner] is true the screen reads the current
/// user from [AuthProvider] automatically.
class UserProfileScreen extends StatefulWidget {
  final UserResponse? user;
  final bool isOwner;

  const UserProfileScreen({super.key, this.user, this.isOwner = false});

  /// Convenience constructor for the visitor view, opened from search results.
  const UserProfileScreen.visitor({super.key, required UserResponse user})
      : user = user,
        isOwner = false;

  /// Convenience constructor for the owner's own profile tab.
  const UserProfileScreen.owner({super.key})
      : user = null,
        isOwner = true;

  @override
  State<UserProfileScreen> createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends State<UserProfileScreen> {
  final ImagePicker _picker = ImagePicker();
  bool _uploadingProfile = false;
  bool _uploadingForeground = false;
  bool _sendingMessage = false;

  // ── Owner: pick and upload an image ───────────────────────────────────────
  Future<void> _pickAndUpload({required bool foreground}) async {
    final image =
        await _picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (image == null || !mounted) return;
    setState(() => foreground ? _uploadingForeground = true : _uploadingProfile = true);
    final error =
        await context.read<AuthProvider>().uploadUserImage(image, foreground: foreground);
    if (!mounted) return;
    setState(() => foreground ? _uploadingForeground = false : _uploadingProfile = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(error ??
          (foreground ? 'Foreground image updated.' : 'Profile photo updated.')),
      backgroundColor: error == null ? Colors.pinkAccent : Colors.redAccent,
      behavior: SnackBarBehavior.floating,
    ));
  }

  // ── Visitor: open or request a conversation ───────────────────────────────
  Future<void> _sendMessage(UserResponse user) async {
    if (_sendingMessage) return;
    setState(() => _sendingMessage = true);

    final auth = context.read<AuthProvider>();
    final convos = context.read<ConversationProvider>();

    final ConversationResponse? conversation =
        await convos.createPrivateConversation(auth, user.id);

    if (!mounted) return;
    setState(() => _sendingMessage = false);

    if (conversation == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open this conversation. Please try again.')),
      );
      return;
    }

    if (conversation.status == ConversationStatus.PENDING) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'Chat request sent to ${user.username}. You can chat once they accept.'),
          backgroundColor: Colors.pinkAccent,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    // ACCEPTED — open the conversation directly.
    if (!mounted) return;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ConversationPage(
        conversationId: conversation.id,
        chatName: user.username,
        avatar: Icons.person,
        isGroup: false,
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isOwner) {
      return Consumer<AuthProvider>(builder: (context, auth, _) {
        final u = auth.currentUser;
        return _buildProfile(
          context,
          username: u?.username.isNotEmpty == true ? u!.username : 'My Profile',
          email: u?.email ?? '',
          avatarUrl: u?.profileImageUrl,
          foregroundUrl: u?.foregroundImageUrl,
        );
      });
    }

    final u = widget.user!;
    return _buildProfile(
      context,
      username: u.username,
      email: u.email,
      avatarUrl: u.profileImageUrl,
      foregroundUrl: u.foregroundImageUrl,
    );
  }

  Widget _buildProfile(
    BuildContext context, {
    required String username,
    required String email,
    String? avatarUrl,
    String? foregroundUrl,
  }) {
    return SingleChildScrollView(
      padding: EdgeInsets.zero,
      child: Column(children: [
        // ── Foreground / banner ──────────────────────────────────────────────
        Stack(children: [
          ClipRRect(
            borderRadius:
                const BorderRadius.vertical(bottom: Radius.circular(24)),
            child: SizedBox(
              width: double.infinity,
              height: 200,
              child: foregroundUrl != null && foregroundUrl.isNotEmpty
                  ? Image.network(foregroundUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _foregroundPlaceholder())
                  : _foregroundPlaceholder(),
            ),
          ),
          if (widget.isOwner)
            Positioned(
              right: 12,
              top: 12,
              child: IconButton.filledTonal(
                tooltip: 'Change banner',
                onPressed: _uploadingForeground
                    ? null
                    : () => _pickAndUpload(foreground: true),
                icon: _uploadingForeground
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.wallpaper_outlined),
              ),
            ),
        ]),

        // ── Avatar + name ────────────────────────────────────────────────────
        Transform.translate(
          offset: const Offset(0, -44),
          child: Column(children: [
            Stack(alignment: Alignment.bottomRight, children: [
              CircleAvatar(
                radius: 52,
                backgroundColor: Colors.white,
                backgroundImage: avatarUrl != null && avatarUrl.isNotEmpty
                    ? NetworkImage(avatarUrl)
                    : null,
                child: avatarUrl == null || avatarUrl.isEmpty
                    ? const Icon(Icons.person, size: 56, color: Colors.pinkAccent)
                    : null,
              ),
              if (widget.isOwner)
                IconButton.filled(
                  tooltip: 'Change photo',
                  onPressed: _uploadingProfile
                      ? null
                      : () => _pickAndUpload(foreground: false),
                  icon: _uploadingProfile
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.camera_alt_outlined, size: 18),
                ),
            ]),
            const SizedBox(height: 10),
            Text(username,
                style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Colors.pinkAccent)),
            if (email.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(email,
                  style: const TextStyle(fontSize: 14, color: Colors.grey)),
            ],
            const SizedBox(height: 16),

            // ── Action buttons ──────────────────────────────────────────────
            if (!widget.isOwner) ...[
              _VisitorActions(
                user: widget.user!,
                sending: _sendingMessage,
                onSendMessage: () => _sendMessage(widget.user!),
              ),
              const SizedBox(height: 8),
            ],
          ]),
        ),

        // ── Menu items ───────────────────────────────────────────────────────
        Transform.translate(
          offset: const Offset(0, -32),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: widget.isOwner ? _ownerMenu(context) : _visitorInfo(email),
          ),
        ),
      ]),
    );
  }

  // ── Owner menu (Privacy & Security, Log Out) ────────────────────────────
  Widget _ownerMenu(BuildContext context) {
    final auth = context.read<AuthProvider>();
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Column(children: [
        ListTile(
          leading:
              const Icon(Icons.lock_outline, color: Colors.pinkAccent),
          title: const Text('Privacy & Security'),
          subtitle:
              const Text('Edit profile information and manage your password'),
          trailing: const Icon(Icons.arrow_forward_ios, size: 16),
          onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => const PrivacySecurityScreen())),
        ),
        const Divider(height: 1),
        ListTile(
          leading: const Icon(Icons.logout, color: Colors.redAccent),
          title: const Text('Log Out',
              style: TextStyle(color: Colors.redAccent)),
          trailing: const Icon(Icons.arrow_forward_ios, size: 16),
          onTap: () async => auth.logout(),
        ),
      ]),
    );
  }

  // ── Visitor info card (read-only) ───────────────────────────────────────
  Widget _visitorInfo(String email) {
    if (email.isEmpty) return const SizedBox.shrink();
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ListTile(
        leading: const Icon(Icons.email_outlined, color: Colors.pinkAccent),
        title: const Text('Email'),
        subtitle: Text(email),
      ),
    );
  }

  Widget _foregroundPlaceholder() => Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Colors.pinkAccent.withValues(alpha: 0.3),
              Colors.pinkAccent.withValues(alpha: 0.08),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        alignment: Alignment.center,
        child: const Icon(Icons.photo_outlined, size: 48, color: Colors.pinkAccent),
      );
}

// ── Visitor action buttons ──────────────────────────────────────────────────
class _VisitorActions extends StatelessWidget {
  final UserResponse user;
  final bool sending;
  final VoidCallback onSendMessage;

  const _VisitorActions({
    required this.user,
    required this.sending,
    required this.onSendMessage,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(children: [
        // Send Message button
        Expanded(
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.pinkAccent,
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
            ),
            onPressed: sending ? null : onSendMessage,
            icon: sending
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.send_rounded, size: 18),
            label: Text(sending ? 'Opening…' : 'Send Message'),
          ),
        ),
      ]),
    );
  }
}
