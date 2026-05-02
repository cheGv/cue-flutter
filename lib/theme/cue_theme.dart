// lib/theme/cue_theme.dart
//
// Phase 2 register shift: clinical OS → clinical companion. Pure white day,
// near-black night. Amber is Cue's only voice. No parchment. No serifs.
//
// All typography uses the system geometric sans stack (SF Pro Display on
// macOS/iOS, system-ui on web, Roboto on Android). No Google Fonts dep is
// introduced here — see cue_typography.dart for the canonical type scale.
//
// Legacy color/text constants are preserved as aliases so existing screens
// keep compiling. Old call sites automatically inherit the new palette.

import 'package:flutter/material.dart';
import 'cue_typography.dart';

// ── Color palette ────────────────────────────────────────────────────────────
class CueColors {
  CueColors._();

  // ── Day mode ─────────────────────────────────────────────────────────────
  /// Pure white. The page itself disappears.
  static const background    = Color(0xFFFFFFFF);
  /// Subtle off-white for elevated cards on white background.
  static const surface       = Color(0xFFFAFAFA);
  /// Near-black with blue tint — sidebar / dark navigation surfaces in day.
  static const sidebar       = Color(0xFF080F1A);
  /// Primary text in day mode.
  static const inkPrimary    = Color(0xFF0A1628);
  static const inkSecondary  = Color(0xFF6B6760);
  static const inkTertiary   = Color(0xFF9A8E76);
  /// 8% black hairline.
  static const divider       = Color(0x14000000);
  /// Cue's voice (day + night).
  static const amber         = Color(0xFFF59E0B);
  /// Amber on light text — used when amber is on white surface.
  static const amberDark     = Color(0xFFB8770A);
  /// Clinical data (day primary).
  static const teal          = Color(0xFF1F8870);
  /// Lighter teal for success indicators in dark contexts.
  static const tealLight     = Color(0xFF5DD3A8);
  static const coral         = Color(0xFFC25450);

  // ── Night mode ───────────────────────────────────────────────────────────
  /// Near-black with blue tint, darker than day-mode sidebar.
  static const backgroundDark    = Color(0xFF060E1A);
  /// Elevated cards in night mode.
  static const surfaceDark       = Color(0xFF0F1F35);
  /// Sidebar in night mode (even darker than night background).
  static const sidebarDark       = Color(0xFF040A12);
  static const inkDark           = Color(0xFFF0EBE1);
  static const inkSecondaryDark  = Color(0x80F0EBE1);
  static const inkTertiaryDark   = Color(0x4DF0EBE1);
  /// 8% white hairline (night).
  static const dividerDark       = Color(0x14FFFFFF);
  /// Mid-amber for borders / accent lines on dark.
  static const amberDarkNight    = Color(0xFFD97706);

  // ── Legacy aliases — keep existing screens compiling ─────────────────────
  /// Old `accent` was deep navy used for primary actions. Phase 2: keep
  /// pointing to ink for stable visual; new code should use `amber` for
  /// Cue's voice and `teal` for clinical data.
  static const accent        = inkPrimary;
  static const inkNavy       = inkPrimary;
  static const signalTeal    = teal;
  static const warmAmber     = amber;
  static const softWhite     = background;
  static const surfaceWhite  = surface;
  static const textMid       = inkSecondary;
  static const errorRed      = coral;
  static const success       = teal;
}

// ── Text helpers ─────────────────────────────────────────────────────────────
//
// Phase 2: serif removed. `display` and `body` both render in the system
// geometric sans. Existing call sites continue to work; they just look
// different now.
class CueText {
  CueText._();

  /// Display family — was Fraunces, now system geometric sans bold.
  static TextStyle display({
    double fontSize = 24,
    Color color = CueColors.inkPrimary,
    FontWeight weight = FontWeight.w700,
    double? letterSpacing,
    double? height,
  }) =>
      CueType.custom(
        fontSize:      fontSize,
        weight:        weight,
        color:         color,
        letterSpacing: letterSpacing ?? -0.4,
        height:        height ?? 1.4,
      );

  /// Body family — was Inter / GoogleFonts.inter, now system geometric sans.
  static TextStyle body({
    double fontSize = 13,
    Color color = CueColors.inkPrimary,
    FontWeight weight = FontWeight.w400,
    double? letterSpacing,
    double? height,
  }) =>
      CueType.custom(
        fontSize:      fontSize,
        weight:        weight,
        color:         color,
        letterSpacing: letterSpacing ?? 0,
        height:        height ?? 1.6,
      );

  // Legacy shims.
  static TextStyle serifHeading({
    double fontSize = 22,
    Color color = CueColors.inkPrimary,
    FontWeight weight = FontWeight.w700,
  }) =>
      display(fontSize: fontSize, color: color, weight: weight);

  static TextStyle sans({
    double fontSize = 14,
    Color color = CueColors.inkPrimary,
    FontWeight weight = FontWeight.w400,
  }) =>
      body(fontSize: fontSize, color: color, weight: weight);
}

// ── Global fade page transition ──────────────────────────────────────────────
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

// ── Theme ────────────────────────────────────────────────────────────────────
class CueTheme {
  CueTheme._();

  static ThemeData get theme => dayTheme;

  // ── Day theme ──────────────────────────────────────────────────────────────
  static ThemeData get dayTheme {
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: const ColorScheme.light(
        primary:     CueColors.amber,
        secondary:   CueColors.teal,
        surface:     CueColors.background,
        error:       CueColors.coral,
        onPrimary:   Colors.white,
        onSecondary: Colors.white,
        onSurface:   CueColors.inkPrimary,
      ),
      scaffoldBackgroundColor: CueColors.background,
      dividerColor:            CueColors.divider,
    );

    return base.copyWith(
      textTheme: _textTheme(CueColors.inkPrimary, CueColors.inkSecondary),
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
        backgroundColor:        CueColors.background,
        foregroundColor:        CueColors.inkPrimary,
        elevation:              0,
        scrolledUnderElevation: 0,
        centerTitle:            false,
        surfaceTintColor:       Colors.transparent,
        titleTextStyle: CueType.custom(
          fontSize: 17, weight: FontWeight.w600,
          color: CueColors.inkPrimary,
        ),
        iconTheme: const IconThemeData(color: CueColors.inkPrimary, size: 22),
        shape: const Border(
          bottom: BorderSide(color: CueColors.divider, width: 0.5),
        ),
      ),
      cardTheme: CardThemeData(
        color:            CueColors.surface,
        elevation:        0,
        shadowColor:      Colors.transparent,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: CueColors.divider, width: 0.5),
        ),
        margin: EdgeInsets.zero,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: CueColors.amber,
          foregroundColor: Colors.white,
          minimumSize: const Size(0, 52),
          textStyle: CueType.custom(
              fontSize: 15, weight: FontWeight.w600, letterSpacing: 0.1),
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
          textStyle: CueType.custom(
              fontSize: 15, weight: FontWeight.w600),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 24),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: CueColors.amberDark,
          textStyle: CueType.custom(
              fontSize: 14, weight: FontWeight.w600),
        ),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: CueColors.amber,
        foregroundColor: Colors.white,
        elevation: 0, focusElevation: 0, hoverElevation: 0, highlightElevation: 0,
      ),
      dividerTheme: const DividerThemeData(
        color: CueColors.divider, thickness: 0.5, space: 0.5,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: CueColors.inkPrimary,
        contentTextStyle: CueType.custom(
            fontSize: 14, color: Colors.white),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor:  CueColors.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        titleTextStyle: CueType.custom(
            fontSize: 20, weight: FontWeight.w700,
            color: CueColors.inkPrimary, letterSpacing: -0.3),
        contentTextStyle: CueType.custom(
            fontSize: 14, color: CueColors.inkSecondary, height: 1.5),
      ),
    );
  }

  // ── Night theme ────────────────────────────────────────────────────────────
  static ThemeData get nightTheme {
    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: const ColorScheme.dark(
        primary:     CueColors.amber,
        secondary:   CueColors.tealLight,
        surface:     CueColors.surfaceDark,
        error:       CueColors.coral,
        onPrimary:   Color(0xFF060E1A),
        onSecondary: Color(0xFF060E1A),
        onSurface:   CueColors.inkDark,
      ),
      scaffoldBackgroundColor: CueColors.backgroundDark,
      dividerColor:            CueColors.dividerDark,
    );
    return base.copyWith(
      textTheme: _textTheme(CueColors.inkDark, CueColors.inkSecondaryDark),
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
        backgroundColor:        CueColors.backgroundDark,
        foregroundColor:        CueColors.inkDark,
        elevation:              0,
        scrolledUnderElevation: 0,
        centerTitle:            false,
        surfaceTintColor:       Colors.transparent,
        titleTextStyle: CueType.custom(
            fontSize: 17, weight: FontWeight.w600, color: CueColors.inkDark),
        iconTheme: const IconThemeData(color: CueColors.inkDark, size: 22),
        shape: const Border(
          bottom: BorderSide(color: CueColors.dividerDark, width: 0.5),
        ),
      ),
      cardTheme: CardThemeData(
        color:            CueColors.surfaceDark,
        elevation:        0,
        shadowColor:      Colors.transparent,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: CueColors.dividerDark, width: 0.5),
        ),
        margin: EdgeInsets.zero,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: CueColors.amber,
          foregroundColor: const Color(0xFF060E1A),
          minimumSize: const Size(0, 52),
          textStyle: CueType.custom(
              fontSize: 15, weight: FontWeight.w600, letterSpacing: 0.1),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 24),
          elevation: 0,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: CueColors.inkDark,
          side: const BorderSide(color: CueColors.dividerDark),
          minimumSize: const Size(0, 52),
          textStyle: CueType.custom(fontSize: 15, weight: FontWeight.w600),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 24),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: CueColors.amber,
          textStyle: CueType.custom(fontSize: 14, weight: FontWeight.w600),
        ),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: CueColors.amber,
        foregroundColor: Color(0xFF060E1A),
        elevation: 0, focusElevation: 0, hoverElevation: 0, highlightElevation: 0,
      ),
      dividerTheme: const DividerThemeData(
        color: CueColors.dividerDark, thickness: 0.5, space: 0.5,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: CueColors.surfaceDark,
        contentTextStyle: CueType.custom(fontSize: 14, color: CueColors.inkDark),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor:  CueColors.surfaceDark,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        titleTextStyle: CueType.custom(
            fontSize: 20, weight: FontWeight.w700,
            color: CueColors.inkDark, letterSpacing: -0.3),
        contentTextStyle: CueType.custom(
            fontSize: 14, color: CueColors.inkSecondaryDark, height: 1.5),
      ),
    );
  }

  // ── Shared helpers (legacy API surface) ────────────────────────────────────

  /// Small uppercase eyebrow label.
  static Widget eyebrow(String text) {
    return Text(
      text.toUpperCase(),
      style: CueType.labelSmall.copyWith(color: CueColors.inkSecondary),
    );
  }

  /// Section title — was Fraunces; now bold geometric sans.
  static Widget sectionTitle(String text) {
    return Text(
      text,
      style: CueType.displaySmall.copyWith(color: CueColors.inkPrimary),
    );
  }

  static Widget sectionLabel(String text) => eyebrow(text);

  static InputDecoration inputDecoration(String label,
      {String? hint, Widget? prefixIcon}) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: prefixIcon,
    );
  }

  static const soapLabels = ['Subjective', 'Objective', 'Assessment', 'Plan'];

  static const soapColors = [
    CueColors.amber,
    CueColors.teal,
    CueColors.amberDark,
    CueColors.inkPrimary,
  ];

  static const appBarGradient = LinearGradient(
    colors: [CueColors.background, CueColors.background],
  );
}

// ── Internal: TextTheme builder ──────────────────────────────────────────────

TextTheme _textTheme(Color ink, Color inkSecondary) {
  return TextTheme(
    displayLarge:  CueType.displayLarge.copyWith(color: ink),
    displayMedium: CueType.displayMedium.copyWith(color: ink),
    displaySmall:  CueType.displaySmall.copyWith(color: ink),
    bodyLarge:     CueType.bodyLarge.copyWith(color: ink),
    bodyMedium:    CueType.bodyMedium.copyWith(color: ink),
    bodySmall:     CueType.bodySmall.copyWith(color: inkSecondary),
    labelLarge:    CueType.labelLarge.copyWith(color: ink),
    labelSmall:    CueType.labelSmall.copyWith(color: inkSecondary),
  );
}
