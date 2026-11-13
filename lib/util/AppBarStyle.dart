import 'package:flutter/material.dart';

/// The look of every app bar of the app.
///
/// The settings page is a tab of the home screen, so its app bar is the one
/// of [HomeScreen]. Every screen that opens its own app bar uses this helper
/// to stay exactly the same: same background, same pink border, same white
/// Montserrat title.
class AppBarStyle {
  const AppBarStyle._();

  /// The pink of the app bar (same value as the home screen).
  static const Color backgroundColor = Color(0xBAFD4080);

  /// The pink line under the app bar.
  static const Border bottomBorder = Border(
    bottom: BorderSide(width: 1.5, color: Colors.pinkAccent),
  );

  /// The title of the app bar.
  static const TextStyle titleStyle = TextStyle(
    color: Colors.white,
    fontFamily: "Montserrat",
    fontSize: 22,
    fontWeight: FontWeight.bold,
    shadows: [
      Shadow(
        offset: Offset(1.5, 1.5),
        blurRadius: 3.0,
        color: Color(0x4D000000),
      ),
    ],
  );

  /// Builds an app bar with the style of the app.
  static AppBar build({
    required String title,
    Widget? leading,
    List<Widget>? actions,
    PreferredSizeWidget? bottom,
    bool centerTitle = false,
  }) {
    return AppBar(
      backgroundColor: backgroundColor,
      foregroundColor: Colors.white,
      elevation: 0,
      shadowColor: Colors.transparent,
      shape: bottomBorder,
      iconTheme: const IconThemeData(color: Colors.white),
      actionsIconTheme: const IconThemeData(color: Colors.white),
      titleSpacing: 16,
      centerTitle: centerTitle,
      title: Text(title, style: titleStyle),
      leading: leading,
      actions: actions,
      bottom: bottom,
    );
  }
}
