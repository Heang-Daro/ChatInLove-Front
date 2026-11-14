import 'package:flutter/material.dart';
import 'UserProfileScreen.dart';

/// The owner's own profile tab — delegates entirely to UserProfileScreen.
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const UserProfileScreen.owner();
  }
}
