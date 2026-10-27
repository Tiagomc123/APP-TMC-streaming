import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  AppTheme._();

  static const Color bg = Color(0xFF070A12);
  static const Color surface = Color(0xFF121826);
  static const Color card = Color(0xFF1A2233);
  static const Color accent = Color(0xFF3D7BFF);
  static const Color gold = Color(0xFFF5C451);
  static const Color red = Color(0xFFE5484D);
  static const Color green = Color(0xFF35C46A);

  /// A familia e aplicada via `fontFamily` (String) e nao via
  /// `GoogleFonts.poppinsTextTheme()`. Assim nao existe qualquer chance de
  /// descompasso de tipo entre o TextTheme do google_fonts e o do material.
  static final ThemeData dark = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: bg,
    colorScheme: const ColorScheme.dark(
      primary: accent,
      secondary: gold,
      surface: surface,
      error: red,
    ),
    fontFamily: GoogleFonts.poppins().fontFamily,
    appBarTheme: const AppBarTheme(backgroundColor: bg, elevation: 0),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: card,
      contentTextStyle: TextStyle(color: Colors.white),
      behavior: SnackBarBehavior.floating,
    ),
  );
}