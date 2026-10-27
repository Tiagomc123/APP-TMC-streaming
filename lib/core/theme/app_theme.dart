import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Tema escuro profundo no estilo YouTube / YouCine:
/// preto azulado, cantos arredondados padronizados e tipografia minimalista.
class AppTheme {
  AppTheme._();

  static const Color bg = Color(0xFF070A12);
  static const Color surface = Color(0xFF121826);
  static const Color card = Color(0xFF1A2233);
  static const Color accent = Color(0xFF3D7BFF);
  static const Color gold = Color(0xFFF5C451);
  static const Color red = Color(0xFFE5484D);
  static const Color green = Color(0xFF35C46A);

  /// Escala unica de raio. Card, chip, folha e poster usam um destes valores.
  static const double radiusSm = 10;
  static const double radius = 16;
  static const double radiusLg = 22;

  static const EdgeInsets padScreen = EdgeInsets.fromLTRB(16, 14, 16, 24);
  static const EdgeInsets padCard = EdgeInsets.all(14);

  static final BorderRadius brSm = BorderRadius.circular(radiusSm);
  static final BorderRadius br = BorderRadius.circular(radius);
  static final BorderRadius brLg = BorderRadius.circular(radiusLg);

  static const Duration fast = Duration(milliseconds: 140);

  static final ThemeData dark = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: bg,
    canvasColor: bg,
    colorScheme: const ColorScheme.dark(
      primary: accent,
      secondary: gold,
      surface: surface,
      error: red,
    ),
    fontFamily: GoogleFonts.poppins().fontFamily,
    appBarTheme: const AppBarTheme(
      backgroundColor: bg,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        color: Colors.white,
        fontSize: 19,
        fontWeight: FontWeight.w900,
        letterSpacing: 2.5,
      ),
    ),
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: Color(0xFF0B0F1A),
      selectedItemColor: gold,
      unselectedItemColor: Colors.white38,
      type: BottomNavigationBarType.fixed,
      showUnselectedLabels: true,
      elevation: 0,
      selectedLabelStyle: TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
      unselectedLabelStyle: TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: card,
      selectedColor: accent,
      disabledColor: surface,
      labelStyle: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
      secondaryLabelStyle: const TextStyle(color: Colors.white, fontSize: 12),
      side: const BorderSide(color: Colors.white12),
      shape: RoundedRectangleBorder(borderRadius: brLg),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: card,
      contentTextStyle: const TextStyle(color: Colors.white),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: br),
    ),
    dividerTheme: const DividerThemeData(color: Colors.white10, thickness: 1, space: 1),
  );
}