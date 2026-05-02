// lib/theme/cue_typography.dart
//
// Phase 2 type scale. Architectural geometric sans, weight + scale doing all
// hierarchy work — no serifs.
//
// Font stack: SF Pro Display on Apple platforms, system-ui on web, Roboto
// on Android. Flutter's TextStyle.fontFamily takes a single name; the
// fontFamilyFallback chain handles the cascade. On Flutter Web this maps
// directly to a CSS font-family declaration honoring the browser's system
// font.
//
// All text should derive from CueType. Do NOT introduce Google Fonts in any
// new code in this phase — system fonts only.

import 'package:flutter/material.dart';

class CueType {
  CueType._();

  // ── Font stack (geometric sans, system) ─────────────────────────────────
  static const String _primaryFamily = 'SF Pro Display';
  static const List<String> _fallback = [
    '-apple-system',
    'system-ui',
    'BlinkMacSystemFont',
    'Segoe UI',
    'Roboto',
    'Helvetica Neue',
    'Arial',
    'sans-serif',
  ];

  /// Drop-in replacement for legacy GoogleFonts.playfairDisplay / .fraunces
  /// call sites. Same kwarg shape; renders in the geometric-sans system
  /// stack instead. Phase 2 register: serifs are gone.
  static TextStyle serif({
    double? fontSize,
    FontWeight? fontWeight,
    Color? color,
    double? letterSpacing,
    double? height,
    FontStyle? fontStyle,
  }) =>
      TextStyle(
        fontFamily:         _primaryFamily,
        fontFamilyFallback: _fallback,
        fontSize:           fontSize,
        fontWeight:         fontWeight ?? FontWeight.w700,
        color:              color,
        letterSpacing:      letterSpacing ?? -0.3,
        height:             height,
        fontStyle:          fontStyle,
      );

  /// Helper for ad-hoc styling that still respects the font stack. Use this
  /// when none of the named scale entries fit (e.g. one-off AppBar titles).
  static TextStyle custom({
    double fontSize = 13,
    FontWeight weight = FontWeight.w400,
    Color? color,
    double letterSpacing = 0,
    double height = 1.6,
  }) =>
      TextStyle(
        fontFamily:         _primaryFamily,
        fontFamilyFallback: _fallback,
        fontSize:           fontSize,
        fontWeight:         weight,
        color:              color,
        letterSpacing:      letterSpacing,
        height:             height,
      );

  // ── Type scale ──────────────────────────────────────────────────────────

  /// 38 / 700 / -1.2 / 1.0 — client name.
  static const TextStyle displayLarge = TextStyle(
    fontFamily:         _primaryFamily,
    fontFamilyFallback: _fallback,
    fontSize:           38,
    fontWeight:         FontWeight.w700,
    letterSpacing:      -1.2,
    height:             1.0,
  );

  /// 22 / 700 / -0.4 / 1.4 — brief thought, hero text.
  static const TextStyle displayMedium = TextStyle(
    fontFamily:         _primaryFamily,
    fontFamilyFallback: _fallback,
    fontSize:           22,
    fontWeight:         FontWeight.w700,
    letterSpacing:      -0.4,
    height:             1.4,
  );

  /// 18 / 600 / -0.3 / 1.4 — moment titles.
  static const TextStyle displaySmall = TextStyle(
    fontFamily:         _primaryFamily,
    fontFamilyFallback: _fallback,
    fontSize:           18,
    fontWeight:         FontWeight.w600,
    letterSpacing:      -0.3,
    height:             1.4,
  );

  /// 15 / 400 / 0 / 1.65 — goal text, long content.
  static const TextStyle bodyLarge = TextStyle(
    fontFamily:         _primaryFamily,
    fontFamilyFallback: _fallback,
    fontSize:           15,
    fontWeight:         FontWeight.w400,
    letterSpacing:      0,
    height:             1.65,
  );

  /// 13 / 400 / 0 / 1.6 — chat messages, general body.
  static const TextStyle bodyMedium = TextStyle(
    fontFamily:         _primaryFamily,
    fontFamilyFallback: _fallback,
    fontSize:           13,
    fontWeight:         FontWeight.w400,
    letterSpacing:      0,
    height:             1.6,
  );

  /// 12 / 500 / -0.1 / 1.5 — metadata, captions.
  static const TextStyle bodySmall = TextStyle(
    fontFamily:         _primaryFamily,
    fontFamilyFallback: _fallback,
    fontSize:           12,
    fontWeight:         FontWeight.w500,
    letterSpacing:      -0.1,
    height:             1.5,
  );

  /// 11 / 600 / 0.04em / 1.4 — buttons, action labels.
  static const TextStyle labelLarge = TextStyle(
    fontFamily:         _primaryFamily,
    fontFamilyFallback: _fallback,
    fontSize:           11,
    fontWeight:         FontWeight.w600,
    letterSpacing:      0.44, // 11 * 0.04
    height:             1.4,
  );

  /// 9 / 700 / 0.2em / 1.2 — UPPERCASE section headers.
  /// Use Text(text.toUpperCase(), style: CueType.labelSmall) — the style
  /// itself does not transform the case.
  static const TextStyle labelSmall = TextStyle(
    fontFamily:         _primaryFamily,
    fontFamilyFallback: _fallback,
    fontSize:           9,
    fontWeight:         FontWeight.w700,
    letterSpacing:      1.8, // 9 * 0.2
    height:             1.2,
  );
}
