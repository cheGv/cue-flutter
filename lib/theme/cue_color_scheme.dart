// lib/theme/cue_color_scheme.dart
//
// Phase 5.3 — theme-resolved color accessor.
//
// The Phase 4.0.8 spine locked light-mode token names (kCueOlive,
// kCueAmber, kCueAmberDeep, kCueBorder) at specific values. Phase 5.3
// inverts the default register to dark and amplifies these accents to
// dark-readable values (#97C459, #EF9F27, #BA7517, #1F1F1F). Two const
// declarations of the same name don't compile, so the dark values for
// the colliding accents live ONLY inside this resolver — accessed as:
//
//     final cue = CueColorsResolved.of(context);
//     pillar.color   = cue.bgCard;
//     headline.color = cue.textPrimary;
//     stgDot.color   = cue.olive;
//
// The pattern mirrors the established _C.of(context) class on Profile
// (lib/screens/client_profile_screen.dart). Same shape, app-wide scope.
//
// Light fallbacks for the new dark-register accents (blue / purple /
// coral / teal / red) use nearest-available spine analogs for now —
// Round F's per-surface typography pass refines per-surface as needed.
// Phase 5.3 widgets render in dark; light-mode visits exercise the
// fallbacks defensively.

import 'package:flutter/material.dart';

import 'cue_phase4_tokens.dart' as t;
import 'cue_theme.dart' show CueColors;

class CueColorsResolved {
  final bool isDark;

  // Backgrounds
  final Color bgCanvas;
  final Color bgCard;
  final Color bgCardHover;
  final Color bgChrome;
  final Color bgInput;
  // Phase 5.3 B.3 — alpha-derived chip/pill fill, sits between bgCard and a
  // tinted accent. Used by TimelineStrip's "last 30 days" pill ground.
  final Color bgMuted;

  // Borders
  final Color border;
  final Color borderHover;
  final Color borderEmphasis;
  // Phase 5.3 B.3 — softer than border (which itself is the subtle one).
  // Used by TimelineStrip's "Last 3 events" dashed row separators.
  final Color borderMuted;

  // Text
  final Color textPrimary;
  final Color textBody;
  // Phase 5.3 B.3 — alias for textBody (same semantic slot). Introduced so
  // surfaces specced with "textSecondary" don't have to reach for textBody
  // and silently lose the conceptual mapping.
  final Color textSecondary;
  final Color textMuted;
  final Color textDim;

  // Accents
  final Color olive;
  final Color amber;
  final Color amberDeep;
  final Color blue;
  final Color purple;
  final Color coral;
  final Color teal;
  // Phase 5.3 Round A.1.2 — alpha-modulated teal derivatives. tealSurface:
  // 12% alpha of cue.teal for active-STG card grounds. tealFaded: 30% alpha
  // for dotted lines / gradients. Single source of truth so derivations
  // don't drift across surfaces.
  final Color tealSurface;
  final Color tealFaded;
  final Color red;

  const CueColorsResolved._({
    required this.isDark,
    required this.bgCanvas,
    required this.bgCard,
    required this.bgCardHover,
    required this.bgChrome,
    required this.bgInput,
    required this.bgMuted,
    required this.border,
    required this.borderHover,
    required this.borderEmphasis,
    required this.borderMuted,
    required this.textPrimary,
    required this.textBody,
    required this.textSecondary,
    required this.textMuted,
    required this.textDim,
    required this.olive,
    required this.amber,
    required this.amberDeep,
    required this.blue,
    required this.purple,
    required this.coral,
    required this.teal,
    required this.tealSurface,
    required this.tealFaded,
    required this.red,
  });

  static const _light = CueColorsResolved._(
    isDark:         false,
    bgCanvas:       t.kCuePaper,
    bgCard:         t.kCueSurfaceWhite,
    bgCardHover:    t.kCuePaper,
    bgChrome:       t.kCueInk,
    bgInput:        t.kCueSurfaceWhite,
    bgMuted:        Color(0x14736B62), // 8% alpha kCueInkSecondary tone
    border:         t.kCueBorder,
    borderHover:    Color(0xFFD8D2C5),
    borderEmphasis: Color(0xFFCEC8BA),
    borderMuted:    Color(0xFFE8E4DA), // between kCueBorder and bgCanvas
    textPrimary:    t.kCueInk,
    textBody:       t.kCueInkSecondary,
    textSecondary:  t.kCueInkSecondary, // alias for textBody
    textMuted:      t.kCueInkTertiary,
    textDim:        Color(0xFFB4B2A9),
    olive:          t.kCueOlive,
    amber:          t.kCueAmber,
    amberDeep:      t.kCueAmberDeep,
    blue:           t.kCueInk,
    purple:         t.kCueInkSecondary,
    coral:          CueColors.coral,
    teal:           CueColors.teal,
    tealSurface:    Color(0x1F1F8870), // 12% alpha of CueColors.teal
    tealFaded:      Color(0x4D1F8870), // 30% alpha of CueColors.teal
    red:            CueColors.coral,
  );

  static const _dark = CueColorsResolved._(
    isDark:         true,
    bgCanvas:       t.kCueBgCanvas,
    bgCard:         t.kCueBgCard,
    bgCardHover:    t.kCueBgCardHover,
    bgChrome:       t.kCueBgChrome,
    bgInput:        t.kCueBgInput,
    bgMuted:        Color(0x14B5B0A8), // 8% alpha textBody tone (founder bump 6→8)
    border:         Color(0xFF1F1F1F),
    borderHover:    t.kCueBorderHover,
    borderEmphasis: t.kCueBorderEmphasis,
    borderMuted:    Color(0xFF161616), // between border (1F1F1F) and bgCanvas
    textPrimary:    t.kCueTextPrimary,
    textBody:       t.kCueTextBody,
    textSecondary:  t.kCueTextBody, // alias for textBody
    textMuted:      t.kCueTextMuted,
    textDim:        t.kCueTextDim,
    olive:          Color(0xFF97C459),
    amber:          Color(0xFFEF9F27),
    amberDeep:      Color(0xFFBA7517),
    blue:           Color(0xFF85B7EB),
    purple:         Color(0xFFAFA9EC),
    coral:          Color(0xFFF0997B),
    teal:           Color(0xFF5DCAA5),
    tealSurface:    Color(0x1F5DCAA5), // 12% alpha of dark teal
    tealFaded:      Color(0x4D5DCAA5), // 30% alpha of dark teal
    red:            Color(0xFFE24B4A),
  );

  factory CueColorsResolved.of(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark ? _dark : _light;
  }
}
