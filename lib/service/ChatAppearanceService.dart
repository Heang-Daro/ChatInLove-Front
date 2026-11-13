import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Shared, persisted background choice for conversation screens.
class ChatAppearanceService {
  ChatAppearanceService._();

  static const _preferenceKey = 'conversation_background_color';
  static const Color defaultBackground = Color(0xFFFFF7FA);
  static final ValueNotifier<Color> backgroundColor =
      ValueNotifier<Color>(defaultBackground);

  static const List<Color> availableColors = [
    Color(0xFFFFF7FA),
    Color(0xFFFFFFFF),
    Color(0xFFF3F4F6),
    Color(0xFFEAF4FF),
    Color(0xFFEAF7F0),
    Color(0xFFFFF3E8),
    Color(0xFFF1ECFA),
    Color(0xFF202127),
  ];

  static Future<void> initialize() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      final savedColor = preferences.getInt(_preferenceKey);
      if (savedColor != null) {
        backgroundColor.value = Color(savedColor);
      }
    } catch (error) {
      debugPrint('ChatAppearanceService: could not load preference: $error');
    }
  }

  static Future<void> setBackgroundColor(Color color) async {
    backgroundColor.value = color;
    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setInt(_preferenceKey, color.toARGB32());
    } catch (error) {
      debugPrint('ChatAppearanceService: could not save preference: $error');
    }
  }
}
