// lib/theme/cue_theme.dart
// Central design system for Cue AI

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// ── Color constants ────────────────────────────────────────────────────────────
class CueColors {
  CueColors._();

  static const inkNavy    = Color(0xFF1B2B4B);
  static const signalTeal = Color(0xFF00B4A6);
  static const warmAmber  = Color(0xFFF5A623);
  static const softWhite  = Color(0xFFF4F6FA);
  static const surfaceWhite = Color(0xFFFFFFFF);
  static const textMid    = Color(0xFF5A6475);
  static const errorRed   = Color(0xFFE05252);
}

// ── Text styles ────────────────────────────────────────────────────────────────
class CueText {
  CueText._();

  /// DM Serif Display — large headings and client names
  static TextStyle serifHeading({
    double fontSize = 22,
    Color color = CueColors.inkNavy,
    FontWeight weight = FontWeight.w400,
  }) =>
      GoogleFonts.dmSerifDisplay(fontSize: fontSize, color: color, fontWeight: weight);

  /// DM Sans — all UI labels, body, buttons
  static TextStyle sans({
    double fontSize = 14,
    Color color = CueColors.inkNavy,
    FontWeight weight = FontWeight.w400,
  }) =>
      GoogleFonts.dmSans(fontSize: fontSize, color: color, fontWeight: weight);
}

// ── Theme ──────────────────────────────────────────────────────────────────────
class CueTheme {
  CueTheme._();

  static ThemeData get theme {
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: const ColorScheme.light(
        primary: CueColors.signalTeal,
        secondary: CueColors.warmAmber,
        surface: CueColors.softWhite,
        error: CueColors.errorRed,
        onPrimary: Colors.white,
        onSecondary: Colors.white,
        onSurface: CueColors.inkNavy,
      ),
      scaffoldBackgroundColor: CueColors.softWhite,
    );

    return base.copyWith(
      textTheme: GoogleFonts.dmSansTextTheme(base.textTheme).copyWith(
        bodyMedium: GoogleFonts.dmSans(fontSize: 14, color: CueColors.inkNavy),
        bodySmall:  GoogleFonts.dmSans(fontSize: 12, color: CueColors.textMid),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Color(0xFF1B2B4B).withOpacity(0.92),
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: GoogleFonts.dmSans(
          color: Colors.white,
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      cardTheme: CardThemeData(
        color: CueColors.surfaceWhite,
        elevation: 2,
        shadowColor: Colors.black.withOpacity(0.06),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: CueColors.inkNavy.withOpacity(0.08)),
        ),
        margin: EdgeInsets.zero,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: CueColors.surfaceWhite,
        labelStyle: GoogleFonts.dmSans(color: CueColors.textMid, fontSize: 14),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: CueColors.inkNavy.withOpacity(0.2)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: CueColors.inkNavy.withOpacity(0.2)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: CueColors.signalTeal, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: CueColors.errorRed),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: CueColors.inkNavy,
          foregroundColor: Colors.white,
          textStyle: GoogleFonts.dmSans(fontSize: 15, fontWeight: FontWeight.w600),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: CueColors.inkNavy,
          side: const BorderSide(color: CueColors.inkNavy),
          textStyle: GoogleFonts.dmSans(fontSize: 15, fontWeight: FontWeight.w600),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 24),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: CueColors.inkNavy,
        contentTextStyle: GoogleFonts.dmSans(color: Colors.white, fontSize: 14),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  // ── Shared helpers ───────────────────────────────────────────────────────────

  /// Standard section label (uppercase, teal, with left border accent).
  static Widget sectionLabel(String text) {
    return Row(
      children: [
        Container(
          width: 3,
          height: 14,
          decoration: BoxDecoration(
            color: CueColors.signalTeal,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          text.toUpperCase(),
          style: GoogleFonts.dmSans(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: CueColors.inkNavy,
            letterSpacing: 1.2,
          ),
        ),
      ],
    );
  }

  /// Standard input decoration (white bg, inkNavy border at 20% opacity).
  static InputDecoration inputDecoration(String label, {String? hint, Widget? prefixIcon}) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: prefixIcon,
      filled: true,
      fillColor: CueColors.surfaceWhite,
      labelStyle: GoogleFonts.dmSans(color: CueColors.textMid, fontSize: 14),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: CueColors.inkNavy.withOpacity(0.2)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: CueColors.inkNavy.withOpacity(0.2)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: CueColors.signalTeal, width: 2),
      ),
    );
  }

  /// SOAP section colors (S / O / A / P).
  static const soapColors = [
    CueColors.signalTeal,
    CueColors.inkNavy,
    CueColors.warmAmber,
    Color(0xFF6B7FD4),
  ];

  static const soapLabels = ['Subjective', 'Objective', 'Assessment', 'Plan'];

  /// Gradient for AppBar flexibleSpace — start inkNavy → slightly lighter navy.
  static const appBarGradient = LinearGradient(
    colors: [Color(0xFF1B2B4B), Color(0xFF243A5E)],
  );
}
