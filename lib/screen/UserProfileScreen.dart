import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import 'package:love_in_chat/model/Response/ConversationResponse.dart';
import 'package:love_in_chat/model/Response/UserResponse.dart';
import 'package:love_in_chat/model/emun/ConversationStatus.dart';
import 'package:love_in_chat/provider/AuthProvider.dart';
import 'package:love_in_chat/provider/ConversationProvider.dart';
import 'ConversationPage.dart';
import 'setting_util/privacy_security_screen.dart';

const Color _brand = Colors.pinkAccent;
const double _bannerHeight = 190;
const double _avatarRadius = 52;

/// Unified profile screen.
///   • [isOwner] = true  → edit controls (avatar, banner, privacy, log out)
///   • [isOwner] = false → visitor view (read-only + Send Message)
class UserProfileScreen extends StatefulWidget {
  final UserResponse? user;
  final bool isOwner;

  const UserProfileScreen({super.key, this.user, this.isOwner = false});

  const UserProfileScreen.visitor({super.key, required UserResponse user})
      : user = user,
        isOwner = false;

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
  bool _requestSent = false; // visitor: chat request already pending

  // ── Helpers ───────────────────────────────────────────────────────────────
  void _toast(String message, {bool error = false}) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(message),
        backgroundColor: error ? Colors.redAccent : _brand,
        behavior: SnackBarBehavior.floating,
      ));
  }

  // ── Owner: choose source, pick, upload ───────────────────────────────────
  Future<ImageSource?> _chooseSource() {
    return showModalBottomSheet<ImageSource>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: const Text('Choose from gallery'),
            onTap: () => Navigator.pop(ctx, ImageSource.gallery),
          ),
          ListTile(
            leading: const Icon(Icons.photo_camera_outlined),
            title: const Text('Take a photo'),
            onTap: () => Navigator.pop(ctx, ImageSource.camera),
          ),
        ]),
      ),
    );
  }

  Future<void> _pickAndUpload({required bool foreground}) async {
    if (_uploadingProfile || _uploadingForeground) return;

    final source = await _chooseSource();
    if (source == null || !mounted) return;

    XFile? image;
    try {
      image = await _picker.pickImage(
        source: source,
        imageQuality: 85,
        maxWidth: foreground ? 1600 : 1024, // keep uploads small on mobile data
      );
    } catch (_) {
      _toast('Could not access ${source == ImageSource.camera ? 'the camera' : 'your photos'}. '
          'Check app permissions in Settings.', error: true);
      return;
    }
    if (image == null || !mounted) return;

    setState(() =>
        foreground ? _uploadingForeground = true : _uploadingProfile = true);

    String? error;
    try {
      error = await context
          .read<AuthProvider>()
          .uploadUserImage(image, foreground: foreground);
    } catch (_) {
      error = 'Upload failed. Check your connection and try again.';
    }

    if (!mounted) return;
    setState(() =>
        foreground ? _uploadingForeground = false : _uploadingProfile = false);
    _toast(
      error ?? (foreground ? 'Banner updated' : 'Profile photo updated'),
      error: error != null,
    );
  }

  // ── Owner: confirm before logging out ────────────────────────────────────
  Future<void> _confirmLogout() async {
    final auth = context.read<AuthProvider>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Log out?'),
        content: const Text('You will need to sign in again to see your chats.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Log out'),
          ),
        ],
      ),
    );
    if (ok == true) await auth.logout();
  }

  // ── Visitor: open or request a conversation ──────────────────────────────
  Future<void> _sendMessage(UserResponse user) async {
    if (_sendingMessage || _requestSent) return;
    setState(() => _sendingMessage = true);

    final auth = context.read<AuthProvider>();
    final convos = context.read<ConversationProvider>();

    ConversationResponse? conversation;
    try {
      conversation = await convos.createPrivateConversation(auth, user.id);
    } catch (_) {
      conversation = null;
    }

    if (!mounted) return;
    setState(() => _sendingMessage = false);

    if (conversation == null) {
      _toast('Could not open this chat. Check your connection and try again.',
          error: true);
      return;
    }

    if (conversation.status == ConversationStatus.PENDING) {
      setState(() => _requestSent = true);
      _toast('Request sent to ${user.username}. You can chat once they accept.');
      return;
    }

    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ConversationPage(
        conversationId: conversation!.id,
        chatName: user.username,
        avatar: Icons.person,
        isGroup: false,
      ),
    ));
  }

  // ── Full-screen image viewer ─────────────────────────────────────────────
  void _openImage(String? url, String heroTag) {
    if (url == null || url.isEmpty) return;
    Navigator.of(context).push(PageRouteBuilder(
      opaque: false,
      barrierColor: Colors.black87,
      barrierDismissible: true,
      pageBuilder: (_, __, ___) => _ImageViewer(url: url, heroTag: heroTag),
    ));
  }

  // ── Build ────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    if (widget.isOwner) {
      return Consumer<AuthProvider>(builder: (context, auth, _) {
        final u = auth.currentUser;
        return _buildProfile(
          context,
          username:
              u?.username.isNotEmpty == true ? u!.username : 'My profile',
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
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return SingleChildScrollView(
      child: Center(
        child: ConstrainedBox(
          // Keeps the layout readable on tablets / web.
          constraints: const BoxConstraints(maxWidth: 640),
          child: Column(children: [
            // ── Banner + overlapping avatar (one Stack = no layout gap) ─────
            Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.topCenter,
              children: [
                GestureDetector(
                  onTap: () => _openImage(foregroundUrl, 'banner'),
                  child: Hero(
                    tag: 'banner',
                    child: ClipRRect(
                      borderRadius: const BorderRadius.vertical(
                          bottom: Radius.circular(24)),
                      child: SizedBox(
                        width: double.infinity,
                        height: _bannerHeight,
                        child: _NetworkImage(
                          url: foregroundUrl,
                          fallback: const _BannerPlaceholder(),
                        ),
                      ),
                    ),
                  ),
                ),
                if (widget.isOwner)
                  Positioned(
                    right: 12,
                    top: 12,
                    child: SafeArea(
                      child: IconButton.filledTonal(
                        tooltip: 'Change banner',
                        onPressed: _uploadingForeground
                            ? null
                            : () => _pickAndUpload(foreground: true),
                        icon: _uploadingForeground
                            ? const _Spinner(size: 20)
                            : const Icon(Icons.wallpaper_outlined),
                      ),
                    ),
                  ),
                Positioned(
                  bottom: -_avatarRadius,
                  child: _AvatarWithEdit(
                    url: avatarUrl,
                    isOwner: widget.isOwner,
                    uploading: _uploadingProfile,
                    onView: () => _openImage(avatarUrl, 'avatar'),
                    onEdit: () => _pickAndUpload(foreground: false),
                  ),
                ),
              ],
            ),

            // Space for the half of the avatar that hangs below the banner.
            const SizedBox(height: _avatarRadius + 12),

            // ── Name + email ────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(children: [
                Text(
                  username,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold, color: _brand),
                ),
                if (email.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    email,
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.bodyMedium
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ],
              ]),
            ),
            const SizedBox(height: 20),

            // ── Visitor primary action ──────────────────────────────────────
            if (!widget.isOwner) ...[
              _VisitorActions(
                sending: _sendingMessage,
                requestSent: _requestSent,
                onSendMessage: () => _sendMessage(widget.user!),
              ),
              const SizedBox(height: 20),
            ],

            // ── Menu / info ─────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
              child: widget.isOwner
                  ? _ownerMenu(context, email)
                  : _visitorInfo(context, email),
            ),
          ]),
        ),
      ),
    );
  }

  // ── Owner menu ────────────────────────────────────────────────────────────
  Widget _ownerMenu(BuildContext context, String email) {
    return Column(children: [
      Card(
        elevation: 0,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: Theme.of(context).dividerColor),
        ),
        child: ListTile(
          leading: const Icon(Icons.lock_outline, color: _brand),
          title: const Text('Privacy & security'),
          subtitle: const Text('Edit your details and change your password'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const PrivacySecurityScreen()),
          ),
        ),
      ),
      const SizedBox(height: 12),
      Card(
        elevation: 0,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: Theme.of(context).dividerColor),
        ),
        child: ListTile(
          leading: const Icon(Icons.logout, color: Colors.redAccent),
          title: const Text('Log out',
              style: TextStyle(color: Colors.redAccent)),
          onTap: _confirmLogout,
        ),
      ),
    ]);
  }

  // ── Visitor info (read-only) ──────────────────────────────────────────────
  Widget _visitorInfo(BuildContext context, String email) {
    if (email.isEmpty) return const SizedBox.shrink();
    return Card(
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Theme.of(context).dividerColor),
      ),
      child: ListTile(
        leading: const Icon(Icons.email_outlined, color: _brand),
        title: const Text('Email'),
        subtitle: Text(email),
        trailing: IconButton(
          tooltip: 'Copy email',
          icon: const Icon(Icons.copy_outlined, size: 20),
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: email));
            _toast('Email copied');
          },
        ),
      ),
    );
  }
}

// ── Avatar with optional edit button ─────────────────────────────────────────
class _AvatarWithEdit extends StatelessWidget {
  final String? url;
  final bool isOwner;
  final bool uploading;
  final VoidCallback onView;
  final VoidCallback onEdit;

  const _AvatarWithEdit({
    required this.url,
    required this.isOwner,
    required this.uploading,
    required this.onView,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final surface = Theme.of(context).colorScheme.surface;
    return Stack(alignment: Alignment.bottomRight, children: [
      GestureDetector(
        onTap: onView,
        child: Hero(
          tag: 'avatar',
          child: Container(
            padding: const EdgeInsets.all(4), // ring that separates avatar from banner
            decoration: BoxDecoration(color: surface, shape: BoxShape.circle),
            child: ClipOval(
              child: SizedBox(
                width: _avatarRadius * 2,
                height: _avatarRadius * 2,
                child: _NetworkImage(
                  url: url,
                  fallback: Container(
                    color: Colors.pinkAccent.withValues(alpha: 0.12),
                    child: const Icon(Icons.person,
                        size: 56, color: _brand),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
      if (isOwner)
        Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: surface, width: 3),
          ),
          child: IconButton.filled(
            tooltip: 'Change photo',
            style: IconButton.styleFrom(
              backgroundColor: _brand,
              foregroundColor: Colors.white,
              minimumSize: const Size(40, 40),
            ),
            onPressed: uploading ? null : onEdit,
            icon: uploading
                ? const _Spinner(size: 18, color: Colors.white)
                : const Icon(Icons.camera_alt_outlined, size: 18),
          ),
        ),
    ]);
  }
}

// ── Visitor action ───────────────────────────────────────────────────────────
class _VisitorActions extends StatelessWidget {
  final bool sending;
  final bool requestSent;
  final VoidCallback onSendMessage;

  const _VisitorActions({
    required this.sending,
    required this.requestSent,
    required this.onSendMessage,
  });

  @override
  Widget build(BuildContext context) {
    final shape =
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(14));

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: SizedBox(
        width: double.infinity,
        height: 48,
        child: requestSent
            ? OutlinedButton.icon(
                style: OutlinedButton.styleFrom(shape: shape),
                onPressed: null,
                icon: const Icon(Icons.hourglass_top_rounded, size: 18),
                label: const Text('Request sent'),
              )
            : FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: _brand,
                  foregroundColor: Colors.white,
                  shape: shape,
                ),
                onPressed: sending ? null : onSendMessage,
                icon: sending
                    ? const _Spinner(size: 18, color: Colors.white)
                    : const Icon(Icons.chat_bubble_outline_rounded, size: 18),
                label: Text(sending ? 'Opening chat…' : 'Send message'),
              ),
      ),
    );
  }
}

// ── Network image with loading + error states ────────────────────────────────
class _NetworkImage extends StatelessWidget {
  final String? url;
  final Widget fallback;

  const _NetworkImage({required this.url, required this.fallback});

  @override
  Widget build(BuildContext context) {
    if (url == null || url!.isEmpty) return fallback;
    return Image.network(
      url!,
      fit: BoxFit.cover,
      gaplessPlayback: true, // no flicker when the image URL changes
      loadingBuilder: (context, child, progress) {
        if (progress == null) return child;
        return Stack(fit: StackFit.expand, children: [
          fallback,
          const Center(child: _Spinner(size: 24)),
        ]);
      },
      errorBuilder: (_, __, ___) => fallback,
    );
  }
}

class _BannerPlaceholder extends StatelessWidget {
  const _BannerPlaceholder();

  @override
  Widget build(BuildContext context) => Container(
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
      );
}

class _Spinner extends StatelessWidget {
  final double size;
  final Color? color;
  const _Spinner({required this.size, this.color});

  @override
  Widget build(BuildContext context) => SizedBox(
        width: size,
        height: size,
        child: CircularProgressIndicator(strokeWidth: 2, color: color),
      );
}

// ── Full-screen, pinch-to-zoom viewer ────────────────────────────────────────
class _ImageViewer extends StatelessWidget {
  final String url;
  final String heroTag;
  const _ImageViewer({required this.url, required this.heroTag});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.pop(context),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Stack(children: [
          Center(
            child: Hero(
              tag: heroTag,
              child: InteractiveViewer(
                minScale: 1,
                maxScale: 4,
                child: Image.network(url, fit: BoxFit.contain),
              ),
            ),
          ),
          SafeArea(
            child: Align(
              alignment: Alignment.topRight,
              child: IconButton(
                tooltip: 'Close',
                color: Colors.white,
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(context),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}