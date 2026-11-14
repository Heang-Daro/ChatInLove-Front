import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:love_in_chat/provider/AuthProvider.dart';
import 'setting_util/privacy_security_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final ImagePicker _picker = ImagePicker();
  bool _uploadingProfile = false;
  bool _uploadingForeground = false;

  Future<void> _pickAndUpload({required bool foreground}) async {
    final image = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (image == null || !mounted) return;
    setState(() {
      if (foreground) {
        _uploadingForeground = true;
      } else {
        _uploadingProfile = true;
      }
    });
    final error = await context.read<AuthProvider>().uploadUserImage(image, foreground: foreground);
    if (!mounted) return;
    setState(() {
      if (foreground) {
        _uploadingForeground = false;
      } else {
        _uploadingProfile = false;
      }
    });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(error ?? (foreground ? 'Foreground image updated.' : 'Profile photo updated.')),
      backgroundColor: error == null ? Colors.pinkAccent : Colors.redAccent,
      behavior: SnackBarBehavior.floating,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AuthProvider>(builder: (context, auth, _) {
      final user = auth.currentUser;
      final name = user?.username.isNotEmpty == true ? user!.username : 'My Profile';
      final email = user?.email ?? '';
      final foreground = user?.foregroundImageUrl;
      final avatar = user?.profileImageUrl;

      return SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          Stack(children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(22),
              child: SizedBox(
                width: double.infinity,
                height: 190,
                child: foreground != null && foreground.isNotEmpty
                    ? Image.network(foreground, fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => _foregroundPlaceholder())
                    : _foregroundPlaceholder(),
              ),
            ),
            Positioned(
              right: 12,
              top: 12,
              child: IconButton.filledTonal(
                tooltip: 'Change foreground image',
                onPressed: _uploadingForeground ? null : () => _pickAndUpload(foreground: true),
                icon: _uploadingForeground
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.wallpaper_outlined),
              ),
            ),
          ]),
          Transform.translate(
            offset: const Offset(0, -48),
            child: Column(children: [
              Stack(alignment: Alignment.bottomRight, children: [
                CircleAvatar(
                  radius: 54,
                  backgroundColor: Colors.white,
                  backgroundImage: avatar != null && avatar.isNotEmpty ? NetworkImage(avatar) : null,
                  child: avatar == null || avatar.isEmpty
                      ? const Icon(Icons.person, size: 58, color: Colors.pinkAccent)
                      : null,
                ),
                IconButton.filled(
                  tooltip: 'Change profile photo',
                  onPressed: _uploadingProfile ? null : () => _pickAndUpload(foreground: false),
                  icon: _uploadingProfile
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.camera_alt_outlined, size: 18),
                ),
              ]),
              const SizedBox(height: 10),
              Text(name, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.pinkAccent)),
              if (email.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(email, style: const TextStyle(fontSize: 14, color: Colors.grey)),
              ],
            ]),
          ),
          Transform.translate(
            offset: const Offset(0, -38),
            child: Card(
              elevation: 2,
              child: Column(children: [
                ListTile(
                  leading: const Icon(Icons.lock_outline, color: Colors.pinkAccent),
                  title: const Text('Privacy & Security'),
                  subtitle: const Text('Edit profile information and manage your password'),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PrivacySecurityScreen())),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.logout, color: Colors.redAccent),
                  title: const Text('Log Out', style: TextStyle(color: Colors.redAccent)),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                  onTap: () async => auth.logout(),
                ),
              ]),
            ),
          ),
        ]),
      );
    });
  }

  Widget _foregroundPlaceholder() => Container(
        color: Colors.pinkAccent.withValues(alpha: 0.12),
        alignment: Alignment.center,
        child: const Icon(Icons.photo_outlined, size: 48, color: Colors.pinkAccent),
      );
}
