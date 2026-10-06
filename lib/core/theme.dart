import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Design tokens ported from the Tailwind config of the HTML designs.
class C {
  static const primary = Color(0xFF006194);
  static const primaryContainer = Color(0xFF007BB9);
  static const primaryFixed = Color(0xFFCCE5FF);
  static const onPrimaryFixed = Color(0xFF001D31);
  static const onPrimaryFixedVariant = Color(0xFF004B73);
  static const secondary = Color(0xFF565E74);
  static const secondaryContainer = Color(0xFFDAE2FD);
  static const tertiary = Color(0xFF006947);
  static const tertiaryFixed = Color(0xFF6FFBBE);
  static const onTertiaryFixed = Color(0xFF002113);
  static const onTertiaryFixedVariant = Color(0xFF005236);
  static const error = Color(0xFFBA1A1A);
  static const errorContainer = Color(0xFFFFDAD6);
  static const surface = Color(0xFFF7F9FB);
  static const surfaceLowest = Color(0xFFFFFFFF);
  static const surfaceLow = Color(0xFFF2F4F6);
  static const surfaceContainer = Color(0xFFECEEF0);
  static const surfaceHigh = Color(0xFFE6E8EA);
  static const surfaceHighest = Color(0xFFE0E3E5);
  static const onSurface = Color(0xFF191C1E);
  static const onSurfaceVariant = Color(0xFF3F4850);
  static const outline = Color(0xFF707881);
  static const outlineVariant = Color(0xFFBFC7D2);
  static const amber = Color(0xFFF59E0B);
}

class T {
  static TextStyle _inter(double s, double h, FontWeight w, [double ls = 0]) =>
      GoogleFonts.inter(fontSize: s, height: h / s, fontWeight: w, letterSpacing: ls * s, color: C.onSurface);
  static TextStyle _jakarta(double s, double h, FontWeight w, [double ls = 0]) =>
      GoogleFonts.plusJakartaSans(fontSize: s, height: h / s, fontWeight: w, letterSpacing: ls * s, color: C.onSurface);

  static final headlineXl = _jakarta(32, 40, FontWeight.w700, -0.02);
  static final headlineLg = _jakarta(24, 32, FontWeight.w600, -0.015);
  static final headlineMd = _jakarta(20, 28, FontWeight.w600, -0.01);
  static final headlineSm = _jakarta(16, 24, FontWeight.w600);
  static final bodyLg = _inter(16, 24, FontWeight.w400);
  static final bodyMd = _inter(14, 20, FontWeight.w400);
  static final bodySm = _inter(12, 16, FontWeight.w400);
  static final labelLg = _inter(14, 20, FontWeight.w600, 0.01);
  static final labelMd = _inter(12, 16, FontWeight.w600, 0.02);
  static final labelSm = _inter(11, 14, FontWeight.w500, 0.03);
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
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: C.surface,
    dividerColor: C.outlineVariant,
  );
}
