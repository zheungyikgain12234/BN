import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Light, compact green palette: pale page, white cards, one confident green for actions.
class C {
  static const primary = Color(0xFF1F7A52);
  static const primaryContainer = Color(0xFF2B8E62);
  static const primaryFixed = Color(0xFFD5EBDD);
  static const onPrimaryFixed = Color(0xFF0B2A1A);
  static const onPrimaryFixedVariant = Color(0xFF1F5A3E);
  static const secondary = Color(0xFF4A5F52);
  static const secondaryContainer = Color(0xFFD8E6DC);
  static const tertiary = Color(0xFF0F6B55);
  static const tertiaryFixed = Color(0xFFB4EAD2);
  static const onTertiaryFixed = Color(0xFF002113);
  static const onTertiaryFixedVariant = Color(0xFF0B4F3D);
  static const error = Color(0xFFB3261E);
  static const errorContainer = Color(0xFFF6D3CF);
  static const surface = Color(0xFFF4F8F5);
  static const surfaceLowest = Color(0xFFFFFFFF);
  static const surfaceLow = Color(0xFFECF3EE);
  static const surfaceContainer = Color(0xFFE2ECE5);
  static const surfaceHigh = Color(0xFFD6E3DA);
  static const surfaceHighest = Color(0xFFCBDACF);
  static const onSurface = Color(0xFF16241C);
  static const onSurfaceVariant = Color(0xFF33473B);
  static const outline = Color(0xFF5F7266);
  static const outlineVariant = Color(0xFFB4C6B9);
  static const amber = Color(0xFFF59E0B);
}

/// Compact type scale (Inter throughout).
class T {
  static TextStyle _inter(double s, double h, FontWeight w, [double ls = 0]) =>
      GoogleFonts.inter(fontSize: s, height: h / s, fontWeight: w, letterSpacing: ls * s, color: C.onSurface);

  static final headlineXl = _inter(24, 30, FontWeight.w700, -0.015);
  static final headlineLg = _inter(20, 28, FontWeight.w700, -0.01);
  static final headlineMd = _inter(16, 24, FontWeight.w600, -0.005);
  static final headlineSm = _inter(14, 20, FontWeight.w600);
  static final bodyLg = _inter(14, 22, FontWeight.w400);
  static final bodyMd = _inter(13, 20, FontWeight.w400);
  static final bodySm = _inter(12, 16, FontWeight.w400);
  static final labelLg = _inter(13, 18, FontWeight.w600);
  static final labelMd = _inter(12, 16, FontWeight.w600);
  static final labelSm = _inter(11, 14, FontWeight.w500, 0.02);
}

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(seedColor: C.primary).copyWith(
    primary: C.primary,
    onPrimary: Colors.white,
    secondary: C.secondary,
    tertiary: C.tertiary,
    error: C.error,
    surface: C.surface,
  );
  final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(8));
  final buttonText = T.labelLg;
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: C.surface,
    dividerColor: C.outlineVariant,
    visualDensity: VisualDensity.compact,
    fontFamily: GoogleFonts.inter().fontFamily,
    filledButtonTheme: FilledButtonThemeData(style: FilledButton.styleFrom(minimumSize: const Size(0, 38), padding: const EdgeInsets.symmetric(horizontal: 14), shape: shape, textStyle: buttonText)),
    outlinedButtonTheme: OutlinedButtonThemeData(style: OutlinedButton.styleFrom(minimumSize: const Size(0, 38), padding: const EdgeInsets.symmetric(horizontal: 14), shape: shape, side: const BorderSide(color: C.outlineVariant), textStyle: buttonText)),
    textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(minimumSize: const Size(0, 34), shape: shape, textStyle: buttonText)),
    dialogTheme: DialogThemeData(
      backgroundColor: C.surfaceLowest,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      titleTextStyle: T.headlineMd,
      contentTextStyle: T.bodyMd,
    ),
    dataTableTheme: DataTableThemeData(dataTextStyle: T.bodyMd, headingTextStyle: T.labelMd),
    tabBarTheme: TabBarThemeData(labelStyle: T.labelLg, unselectedLabelStyle: T.labelLg.copyWith(fontWeight: FontWeight.w500), dividerColor: C.outlineVariant),
    snackBarTheme: SnackBarThemeData(contentTextStyle: T.bodyMd.copyWith(color: Colors.white)),
  );
}
