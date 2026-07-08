import 'package:flutter/material.dart';

/// 应用暗色主题
class AppTheme {
  static const Color bg = Color(0xFF0F0F14);
  static const Color surface = Color(0xFF1A1A24);
  static const Color surface2 = Color(0xFF24243A);
  static const Color border = Color(0xFF2A2A40);
  static const Color text = Color(0xFFE0E0E0);
  static const Color text2 = Color(0xFF9090A8);
  static const Color accent = Color(0xFF6C5CE7);
  static const Color accent2 = Color(0xFFA29BFE);
  static const Color danger = Color(0xFFE74C3C);
  static const Color danger2 = Color(0xFFFF6B6B);
  static const Color success = Color(0xFF00B894);
  static const Color warning = Color(0xFFFDCB6E);

  static const double radius = 12.0;
  static const double radiusSm = 8.0;

  static ThemeData get darkTheme {
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: bg,
      colorScheme: const ColorScheme.dark(
        primary: accent,
        secondary: accent2,
        surface: surface,
        error: danger,
      ),
      cardTheme: CardThemeData(
        color: surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius),
          side: const BorderSide(color: border, width: 1),
        ),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: surface,
        elevation: 0,
        centerTitle: false,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: surface2,
        contentTextStyle: const TextStyle(color: text),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
