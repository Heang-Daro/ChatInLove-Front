import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';

import 'package:love_in_chat/api/api.dart';
import 'package:love_in_chat/model/Response/UserResponse.dart';
import 'package:love_in_chat/provider/AuthProvider.dart';
import '../../util/AppBarStyle.dart';

class PrivacySecurityScreen extends StatefulWidget {
  const PrivacySecurityScreen({super.key});

  @override
  State<PrivacySecurityScreen> createState() => _PrivacySecurityScreenState();
}

class _PrivacySecurityScreenState extends State<PrivacySecurityScreen> {
  final _profileFormKey = GlobalKey<FormState>();
  final _passwordFormKey = GlobalKey<FormState>();
  late final TextEditingController _usernameController;
  late final TextEditingController _emailController;
  final _currentPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _loadingProfile = true;
  bool _savingProfile = false;
  bool _changingPassword = false;
  bool _hideCurrentPassword = true;
  bool _hideNewPassword = true;
  bool _hideConfirmPassword = true;

  @override
  void initState() {
    super.initState();
    final user = context.read<AuthProvider>().currentUser;
    _usernameController = TextEditingController(text: user?.username ?? '');
    _emailController = TextEditingController(text: user?.email ?? '');
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadProfileFromServer());
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _emailController.dispose();
    _currentPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  /// Load the principal directly before showing editable account data. This
  /// avoids initializing the form from an old or partially loaded in-memory user.
  Future<void> _loadProfileFromServer() async {
    final auth = context.read<AuthProvider>();
    try {
      final response = await auth.authorizedRequest((token) => http.get(
            Uri.parse('${REST_URL}/api/auth/principal'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
          ));

      if (!mounted) return;
      if (response.statusCode == 200) {
        final user = UserResponse.fromJson(
          Map<String, dynamic>.from(json.decode(response.body) as Map),
        );
        setState(() {
          _usernameController.text = user.username;
          _emailController.text = user.email;
          _loadingProfile = false;
        });
      } else {
        setState(() => _loadingProfile = false);
        _showMessage('Could not load your latest account information.', isError: true);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingProfile = false);
      _showMessage('Could not load your latest account information. Check your connection.', isError: true);
    }
  }

  Future<void> _saveProfile() async {
    if (!_profileFormKey.currentState!.validate()) return;
    setState(() => _savingProfile = true);
    final error = await context.read<AuthProvider>().updateProfile(
          username: _usernameController.text,
          email: _emailController.text,
        );
    if (!mounted) return;
    setState(() => _savingProfile = false);
    _showMessage(error ?? 'Your profile information has been updated.', isError: error != null);
  }

  Future<void> _changePassword() async {
    if (!_passwordFormKey.currentState!.validate()) return;
    setState(() => _changingPassword = true);
    final error = await context.read<AuthProvider>().changePassword(
          currentPassword: _currentPasswordController.text,
          newPassword: _newPasswordController.text,
        );
    if (!mounted) return;
    setState(() => _changingPassword = false);
    if (error == null) {
      _currentPasswordController.clear();
      _newPasswordController.clear();
      _confirmPasswordController.clear();
    }
    _showMessage(error ?? 'Your password has been changed.', isError: error != null);
  }

  void _showMessage(String message, {required bool isError}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.redAccent : Colors.pinkAccent,
        behavior: SnackBarBehavior.floating,
      ));
  }

  InputDecoration _decoration(String label, IconData icon, {Widget? suffix}) => InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: Colors.pinkAccent),
        suffixIcon: suffix,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Colors.pinkAccent, width: 1.5),
        ),
      );

  Widget _passwordField({
    required String label,
    required TextEditingController controller,
    required bool hidden,
    required VoidCallback toggle,
    String? Function(String?)? validator,
  }) => TextFormField(
        controller: controller,
        obscureText: hidden,
        autocorrect: false,
        enableSuggestions: false,
        validator: validator ?? (value) => (value == null || value.isEmpty) ? 'Enter $label' : null,
        decoration: _decoration(
          label,
          Icons.lock_outline,
          suffix: IconButton(
            tooltip: hidden ? 'Show $label' : 'Hide $label',
            onPressed: toggle,
            icon: Icon(hidden ? Icons.visibility_outlined : Icons.visibility_off_outlined),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBarStyle.build(title: 'Privacy and Security'),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Manage your personal information and protect your account.',
            style: TextStyle(color: Colors.grey, height: 1.4),
          ),
          const SizedBox(height: 18),
          _sectionCard(
            icon: Icons.person_outline,
            title: 'Personal information',
            subtitle: 'Update the name and email associated with your account.',
            child: Form(
              key: _profileFormKey,
              child: Column(
                children: [
                  TextFormField(
                    controller: _usernameController,
                    textCapitalization: TextCapitalization.none,
                    enabled: !_loadingProfile && !_savingProfile,
                    validator: (value) {
                      final text = value?.trim() ?? '';
                      if (text.isEmpty) return 'Username is required';
                      if (text.length < 2 || text.length > 50) return 'Use 2 to 50 characters';
                      return null;
                    },
                    decoration: _decoration('Username', Icons.person_outline),
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    enabled: !_loadingProfile && !_savingProfile,
                    validator: (value) {
                      final email = value?.trim() ?? '';
                      if (email.isEmpty) return 'Email is required';
                      if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email)) {
                        return 'Enter a valid email address';
                      }
                      return null;
                    },
                    decoration: _decoration('Email address', Icons.email_outlined),
                  ),
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _loadingProfile || _savingProfile ? null : _saveProfile,
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.pinkAccent,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      icon: _loadingProfile || _savingProfile
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.save_outlined),
                      label: Text(_loadingProfile ? 'Loading information...' : _savingProfile ? 'Saving...' : 'Save information'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          _sectionCard(
            icon: Icons.password_outlined,
            title: 'Change password',
            subtitle: 'Confirm your current password before choosing a new one.',
            child: Form(
              key: _passwordFormKey,
              child: Column(
                children: [
                  _passwordField(
                    label: 'your current password',
                    controller: _currentPasswordController,
                    hidden: _hideCurrentPassword,
                    toggle: () => setState(() => _hideCurrentPassword = !_hideCurrentPassword),
                  ),
                  const SizedBox(height: 14),
                  _passwordField(
                    label: 'a new password',
                    controller: _newPasswordController,
                    hidden: _hideNewPassword,
                    toggle: () => setState(() => _hideNewPassword = !_hideNewPassword),
                    validator: (value) {
                      if (value == null || value.isEmpty) return 'New password is required';
                      if (value.length < 8) return 'Use at least 8 characters';
                      return null;
                    },
                  ),
                  const SizedBox(height: 14),
                  _passwordField(
                    label: 'your new password again',
                    controller: _confirmPasswordController,
                    hidden: _hideConfirmPassword,
                    toggle: () => setState(() => _hideConfirmPassword = !_hideConfirmPassword),
                    validator: (value) => value != _newPasswordController.text ? 'Passwords do not match' : null,
                  ),
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _changingPassword ? null : _changePassword,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.pinkAccent,
                        side: const BorderSide(color: Colors.pinkAccent),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      icon: _changingPassword
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.pinkAccent))
                          : const Icon(Icons.lock_reset_outlined),
                      label: Text(_changingPassword ? 'Changing...' : 'Change password'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 18),
          const ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.info_outline, color: Colors.pinkAccent),
            title: Text('Password tips'),
            subtitle: Text('Use at least 8 characters and avoid reusing a password from another account.'),
          ),
        ],
      ),
    );
  }

  Widget _sectionCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required Widget child,
  }) => Card(
        elevation: 1,
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, color: Colors.pinkAccent),
                  const SizedBox(width: 10),
                  Expanded(child: Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700))),
                ],
              ),
              const SizedBox(height: 6),
              Text(subtitle, style: const TextStyle(color: Colors.grey, height: 1.35)),
              const SizedBox(height: 18),
              child,
            ],
          ),
        ),
      );
}
