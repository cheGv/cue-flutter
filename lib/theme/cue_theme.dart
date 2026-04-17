// lib/theme/cue_theme.dart
// Cue AI — Apple-inspired minimalist clinical design system.
// Restraint is the design. Type-driven hierarchy. Hairlines over shadows.

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// ── Color palette ──────────────────────────────────────────────────────────────
// New names first; legacy names kept as aliases so existing screens keep compiling
// and automatically adopt the new aesthetic.
class CueColors {
  CueColors._();

  // New palette
  static const background    = Color(0xFFFAFAF7); // warm off-white
  static const surface       = Color(0xFFFFFFFF);
  static const inkPrimary    = Color(0xFF0A0A0A);
  static const inkSecondary  = Color(0xFF6B6B6B);
  static const inkTertiary   = Color(0xFFA8A8A8);
  static const divider       = Color(0xFFE8E6E1);
  static const accent        = Color(0xFF1B2B4B); // deep navy
  static const amber         = Color(0xFFB8863A); // muted clinical gold
  static const success       = Color(0xFF2F7D4F);
  static const coral         = Color(0xFFC25450);

  // Legacy aliases (remap old names to new palette to avoid breakage)
  static const inkNavy       = accent;
  static const signalTeal    = accent;       // accent replaces teal everywhere
  static const warmAmber     = amber;
  static const softWhite     = background;
  static const surfaceWhite  = surface;
  static const textMid       = inkSecondary;
  static const errorRed      = coral;
}

// ── Text helpers ───────────────────────────────────────────────────────────────
class CueText {
  CueText._();

  /// Fraunces — display / serif for names, section titles, large numerals.
  static TextStyle display({
    double fontSize = 24,
    Color color = CueColors.inkPrimary,
    FontWeight weight = FontWeight.w500,
    double? letterSpacing,
    double? height,
  }) =>
      GoogleFonts.fraunces(
        fontSize: fontSize,
        color: color,
        fontWeight: weight,
        letterSpacing: letterSpacing,
        height: height,
      );

  /// Inter — body / UI text.
  static TextStyle body({
    double fontSize = 15,
    Color color = CueColors.inkPrimary,
    FontWeight weight = FontWeight.w400,
    double? letterSpacing,
    double? height,
  }) =>
      GoogleFonts.inter(
        fontSize: fontSize,
        color: color,
        fontWeight: weight,
        letterSpacing: letterSpacing,
        height: height,
      );

  // Back-compat shims for legacy call sites.
  static TextStyle serifHeading({
    double fontSize = 22,
    Color color = CueColors.inkPrimary,
    FontWeight weight = FontWeight.w500,
  }) =>
      display(fontSize: fontSize, color: color, weight: weight);

  static TextStyle sans({
    double fontSize = 14,
    Color color = CueColors.inkPrimary,
    FontWeight weight = FontWeight.w400,
  }) =>
      body(fontSize: fontSize, color: color, weight: weight);
}

// ── Global fade page transition ────────────────────────────────────────────────
class FadePageTransitionsBuilder extends PageTransitionsBuilder {
  const FadePageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return FadeTransition(
      opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
      child: child,
    );
  }
}

// ── Theme ──────────────────────────────────────────────────────────────────────
class CueTheme {
  CueTheme._();

  static ThemeData get theme {
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: const ColorScheme.light(
        primary: CueColors.accent,
        secondary: CueColors.amber,
        surface: CueColors.surface,
        error: CueColors.coral,
        onPrimary: Colors.white,
        onSecondary: Colors.white,
        onSurface: CueColors.inkPrimary,
      ),
      scaffoldBackgroundColor: CueColors.background,
      dividerColor: CueColors.divider,
    );

    return base.copyWith(
      textTheme: GoogleFonts.interTextTheme(base.textTheme).copyWith(
        bodyLarge:  GoogleFonts.inter(fontSize: 15, color: CueColors.inkPrimary),
        bodyMedium: GoogleFonts.inter(fontSize: 14, color: CueColors.inkPrimary),
        bodySmall:  GoogleFonts.inter(fontSize: 13, color: CueColors.inkSecondary),
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android:  FadePageTransitionsBuilder(),
          TargetPlatform.iOS:      FadePageTransitionsBuilder(),
          TargetPlatform.linux:    FadePageTransitionsBuilder(),
          TargetPlatform.macOS:    FadePageTransitionsBuilder(),
          TargetPlatform.windows:  FadePageTransitionsBuilder(),
          TargetPlatform.fuchsia:  FadePageTransitionsBuilder(),
        },
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: CueColors.surface,
        foregroundColor: CueColors.inkPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: GoogleFonts.inter(
          color: CueColors.inkPrimary,
          fontSize: 17,
          fontWeight: FontWeight.w600,
        ),
        iconTheme: const IconThemeData(color: CueColors.inkPrimary, size: 22),
        shape: const Border(
          bottom: BorderSide(color: CueColors.divider, width: 1),
        ),
      ),
      cardTheme: CardThemeData(
        color: CueColors.surface,
        elevation: 0,
        shadowColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: CueColors.divider, width: 1),
        ),
        margin: EdgeInsets.zero,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: false,
        labelStyle: GoogleFonts.inter(color: CueColors.inkSecondary, fontSize: 14),
        hintStyle: GoogleFonts.inter(color: CueColors.inkTertiary, fontSize: 15),
        contentPadding: const EdgeInsets.symmetric(horizontal: 0, vertical: 14),
        border: const UnderlineInputBorder(
          borderSide: BorderSide(color: CueColors.divider, width: 1),
        ),
        enabledBorder: const UnderlineInputBorder(
          borderSide: BorderSide(color: CueColors.divider, width: 1),
        ),
        focusedBorder: const UnderlineInputBorder(
          borderSide: BorderSide(color: CueColors.accent, width: 1.5),
        ),
        errorBorder: const UnderlineInputBorder(
          borderSide: BorderSide(color: CueColors.coral, width: 1),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: CueColors.accent,
          foregroundColor: Colors.white,
          minimumSize: const Size(0, 52),
          textStyle: GoogleFonts.inter(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.1,
          ),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 24),
          elevation: 0,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: CueColors.inkPrimary,
          side: const BorderSide(color: CueColors.divider),
          minimumSize: const Size(0, 52),
          textStyle: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w600),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 24),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: CueColors.accent,
          textStyle: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600),
        ),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: CueColors.accent,
        foregroundColor: Colors.white,
        elevation: 0,
        focusElevation: 0,
        hoverElevation: 0,
        highlightElevation: 0,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return Colors.white;
          return Colors.white;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return CueColors.accent;
          return CueColors.divider;
        }),
        trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
      ),
      dividerTheme: const DividerThemeData(
        color: CueColors.divider,
        thickness: 1,
        space: 1,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: CueColors.inkPrimary,
        contentTextStyle: GoogleFonts.inter(color: Colors.white, fontSize: 14),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: CueColors.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        titleTextStyle: GoogleFonts.fraunces(
          fontSize: 20,
          fontWeight: FontWeight.w500,
          color: CueColors.inkPrimary,
        ),
        contentTextStyle: GoogleFonts.inter(
          fontSize: 14,
          color: CueColors.inkSecondary,
          height: 1.5,
        ),
      ),
    );
  }

  // ── Shared helpers ───────────────────────────────────────────────────────────

  /// Small uppercase eyebrow label (e.g. "RECENT SESSIONS").
  static Widget eyebrow(String text) {
    return Text(
      text.toUpperCase(),
      style: GoogleFonts.inter(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        color: CueColors.inkSecondary,
        letterSpacing: 1.5,
      ),
    );
  }

  /// Fraunces section title (e.g. "Goals", "Trial data").
  static Widget sectionTitle(String text) {
    return Text(
      text,
      style: GoogleFonts.fraunces(
        fontSize: 22,
        fontWeight: FontWeight.w500,
        color: CueColors.inkPrimary,
      ),
    );
  }

  /// Legacy section label — now renders as eyebrow so old screens look right.
  static Widget sectionLabel(String text) => eyebrow(text);

  /// Legacy input decoration — now returns an underline-style decoration.
  static InputDecoration inputDecoration(String label,
      {String? hint, Widget? prefixIcon}) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: prefixIcon,
    );
  }

  /// SOAP section labels.
  static const soapLabels = ['Subjective', 'Objective', 'Assessment', 'Plan'];

  /// Back-compat: SOAP colors (all single accent now).
  static const soapColors = [
    CueColors.accent,
    CueColors.accent,
    CueColors.accent,
    CueColors.accent,
  ];

  /// Back-compat gradient (single color now — no gradient visible).
  static const appBarGradient = LinearGradient(
    colors: [CueColors.surface, CueColors.surface],
  );
}
