// lib/theme/cue_type_v3.dart
//
// Phase 4.0.8 spine typography. Canonical for new code.
// Ground truth: docs/design-language-spine-2026-05-08.md (with
// Revision 2026-05-09 appended for the eyebrow doctrine + numerics
// rule).
//
// Roles, all spine-locked:
//   • dataEyebrow      — JetBrains Mono 10.5 / 500 / +0.14em.
//                        DATA ONLY: dates, state pills, section
//                        counts, trial numbers, timestamps. Caller
//                        applies String.toUpperCase().
//   • clinicalLabel    — Inter 11.5 / 500 (light) or 600 (strong) /
//                        sentence-case. ALL human content labels:
//                        clinical card eyebrows, widget internal
//                        labels. NO uppercase, NO mono. This is the
//                        anti-coder-y rule. (Phase 4.0.8-step-B-1.2)
//   • h1               — Iowan Old Style 28 / 400 / -0.02em. One per
//                        screen. Greeting / client name / report title.
//   • h2               — Inter 14.5 / 500 / -0.011em. Names, primary
//                        clickable items, what the eye lands on first.
//   • body             — Inter 13.5 / 400 / -0.005em / 1.45 line-height.
//                        The bulk of the interface.
//   • dataMono         — JetBrains Mono 12 / 500 / tabular figures.
//                        Inline data spans: trial counts, percentages,
//                        IDs.
//   • numericDisplay   — Iowan / Georgia 400 / -0.025em. BIG WIDGET
//                        NUMERICS (size kwarg, default 28). Replaces
//                        Inter 600 for plaque-style counts. Editorial
//                        register, like financial-report headlines.
//                        (Phase 4.0.8-step-B-1.2)
//   • widgetTitle      — Inter 12.5 / 600 / sentence-case widget header.
//                        (Phase 4.0.8-step-B-1.2)
//   • widgetLabel      — Inter 11.5 / 400 / inline widget labels
//                        (Sessions / Documented / Mon / Tue). 1.2
//   • sectionTitle     — Inter 13 / 600 / sentence-case section
//                        headers ("Today's sessions", "At a glance").
//                        Replaces the surface-1 mono-uppercase eyebrow
//                        for page-level section headers. (1.2)
//   • editorialItalic  — Iowan italic 13.5 / 400. Editorial closes,
//                        parent summaries, Cue Living. Never on a
//                        clinical-action surface.
//
// Eyebrow rule split (Phase 4.0.8-step-B-surface-1.2):
//   Mono uppercase tracked = data ONLY. Sans sentence-case = ALL human
//   content labels. Sans uppercase tracked is FORBIDDEN everywhere
//   except state pills (data tags). Iowan = editorial moments + big
//   numerics.
//
// Font loading: Inter and JetBrains Mono ship via web/index.html
// `<link>` preload. Iowan Old Style is system-only on Apple platforms;
// Georgia and Charter cover universal fallback.
//
// CueType.* in cue_typography.dart remains valid for surfaces 2-8
// during their per-surface migration; once surface 8 ships, that file
// sunsets.

import 'package:flutter/material.dart';

import 'cue_phase4_tokens.dart';

class CueTypeV3 {
  CueTypeV3._();

  // ── Font stacks ─────────────────────────────────────────────────────────
  static const String _interFamily = 'Inter';
  static const String _monoFamily  = 'JetBrains Mono';
  static const String _serifFamily = 'Iowan Old Style';

  static const List<String> _interFallback = <String>[
    'system-ui',
    '-apple-system',
    'BlinkMacSystemFont',
    'Segoe UI',
    'Roboto',
    'Helvetica Neue',
    'Arial',
    'sans-serif',
  ];

  static const List<String> _monoFallback = <String>[
    'SF Mono',
    'Menlo',
    'Monaco',
    'Consolas',
    'Liberation Mono',
    'Courier New',
    'monospace',
  ];

  static const List<String> _serifFallback = <String>[
    'Georgia',
    'Charter',
    'serif',
  ];

  // ── Builders ────────────────────────────────────────────────────────────

  /// Data eyebrow — JetBrains Mono 10.5 / 500 / +0.14em tracked.
  ///
  /// **Data only.** Use for: dates ("FRI · 09 MAY 2026"), state pills
  /// ("UP NEXT"), section counts ("03"), trial numbers, timestamps.
  ///
  /// **Do NOT use for:** clinical card labels, widget headers, section
  /// titles, any human-content label. Those use [clinicalLabel],
  /// [widgetTitle], or [sectionTitle].
  ///
  /// Caller applies `String.toUpperCase()` at the use site.
  static TextStyle dataEyebrow({Color? color}) {
    return TextStyle(
      fontFamily:         _monoFamily,
      fontFamilyFallback: _monoFallback,
      fontSize:           10.5,
      fontWeight:         FontWeight.w500,
      letterSpacing:      kCueEyebrowLetterSpacing(10.5),
      color:              color ?? kCueInkTertiary,
    );
  }

  /// Clinical label — Inter 11.5 / 500 (light) or 600 (strong) /
  /// sentence-case.
  ///
  /// Use for ALL human-content labels: clinical card eyebrows
  /// ("Today's move", "Where we left off", "Context"), widget
  /// internal labels.
  ///
  /// `emphasis: 'strong'` for the eye-anchor labels ("Today's move",
  /// "Where we left off"). `emphasis: 'light'` for secondary
  /// ("Context", supporting labels).
  ///
  /// **Pass the string in sentence-case as-typed. NO toUpperCase().**
  /// Sans uppercase tracked is forbidden everywhere except state pills
  /// (which use [dataEyebrow]).
  static TextStyle clinicalLabel({
    required String emphasis,
    Color? color,
  }) {
    final isStrong = emphasis == 'strong';
    return TextStyle(
      fontFamily:         _interFamily,
      fontFamilyFallback: _interFallback,
      fontSize:           11.5,
      fontWeight:         isStrong ? FontWeight.w600 : FontWeight.w500,
      letterSpacing:      -0.0575, // -0.005em × 11.5
      color:              color ??
          (isStrong ? kCueInkSecondary : kCueInkTertiary),
    );
  }

  /// H1 / editorial — Iowan Old Style 28 / 400 / -0.02em.
  /// Spine rule: at most one per screen. Default color: kCueInk.
  static TextStyle h1({Color? color}) {
    return TextStyle(
      fontFamily:         _serifFamily,
      fontFamilyFallback: _serifFallback,
      fontSize:           28,
      fontWeight:         FontWeight.w400,
      letterSpacing:      -0.56, // -0.02em × 28
      color:              color ?? kCueInk,
    );
  }

  /// H2 — Inter 14.5 / 500 / -0.011em. Names, primary clickable items.
  static TextStyle h2({Color? color}) {
    return TextStyle(
      fontFamily:         _interFamily,
      fontFamilyFallback: _interFallback,
      fontSize:           14.5,
      fontWeight:         FontWeight.w500,
      letterSpacing:      -0.16, // -0.011em × 14.5
      color:              color ?? kCueInk,
    );
  }

  /// Body — Inter 13.5 / 400 / -0.005em / 1.45 line-height.
  static TextStyle body({Color? color}) {
    return TextStyle(
      fontFamily:         _interFamily,
      fontFamilyFallback: _interFallback,
      fontSize:           13.5,
      fontWeight:         FontWeight.w400,
      letterSpacing:      -0.0675, // -0.005em × 13.5
      height:             1.45,
      color:              color ?? kCueInkSecondary,
    );
  }

  /// Data mono — JetBrains Mono 12 / 500 / tabular figures.
  /// Inline data spans: trial counts, percentages, IDs.
  static TextStyle dataMono({Color? color}) {
    return TextStyle(
      fontFamily:         _monoFamily,
      fontFamilyFallback: _monoFallback,
      fontSize:           12,
      fontWeight:         FontWeight.w500,
      letterSpacing:      -0.12, // -0.01em × 12
      fontFeatures:       const <FontFeature>[FontFeature.tabularFigures()],
      color:              color ?? kCueInkSecondary,
    );
  }

  /// Numeric display — Iowan Old Style 400 / -0.025em.
  ///
  /// Big plaque-style numerics in widgets: pending count (38),
  /// tomorrow count (36), pulse stats (22). Replaces the Inter
  /// weight-600 "scoreboard" register the friend-tester signal
  /// flagged as game-y.
  ///
  /// Default size 28; callers pass concrete sizes.
  /// Default color: kCueInk. Pending widget passes kCueAmber for
  /// urgent-state counts.
  static TextStyle numericDisplay({double size = 28, Color? color}) {
    return TextStyle(
      fontFamily:         _serifFamily,
      fontFamilyFallback: _serifFallback,
      fontSize:           size,
      fontWeight:         FontWeight.w400,
      letterSpacing:      size * -0.025,
      color:              color ?? kCueInk,
      height:             1.0,
    );
  }

  /// Widget title — Inter 12.5 / 600 / sentence-case.
  /// Single-line widget headers ("This week", "Pending notes",
  /// "Cue noticed", "Active goals", "Tomorrow").
  static TextStyle widgetTitle({Color? color}) {
    return TextStyle(
      fontFamily:         _interFamily,
      fontFamilyFallback: _interFallback,
      fontSize:           12.5,
      fontWeight:         FontWeight.w600,
      letterSpacing:      -0.0625, // -0.005em × 12.5
      color:              color ?? kCueInk,
    );
  }

  /// Widget label — Inter 11.5 / 400 / sentence-case.
  /// Inline widget labels: "Sessions", "Documented", day names
  /// (Mon, Tue, Wed), goal-row helpers.
  static TextStyle widgetLabel({Color? color}) {
    return TextStyle(
      fontFamily:         _interFamily,
      fontFamilyFallback: _interFallback,
      fontSize:           11.5,
      fontWeight:         FontWeight.w400,
      letterSpacing:      -0.0575, // -0.005em × 11.5
      color:              color ?? kCueInkSecondary,
    );
  }

  /// Section title — Inter 13 / 600 / sentence-case.
  /// Page-level section headers on Today: "Today's sessions",
  /// "At a glance". Replaces the surface-1 mono-uppercase treatment
  /// per the 1.2 eyebrow doctrine.
  static TextStyle sectionTitle({Color? color}) {
    return TextStyle(
      fontFamily:         _interFamily,
      fontFamilyFallback: _interFallback,
      fontSize:           13,
      fontWeight:         FontWeight.w600,
      letterSpacing:      -0.065, // -0.005em × 13
      color:              color ?? kCueInk,
    );
  }

  /// Editorial italic — Iowan italic 13.5 / 400 / 1.5 line-height.
  /// Editorial closes, parent summaries, Cue Living, celebratory
  /// moments. Never on a clinical-action surface.
  static TextStyle editorialItalic({Color? color}) {
    return TextStyle(
      fontFamily:         _serifFamily,
      fontFamilyFallback: _serifFallback,
      fontSize:           13.5,
      fontWeight:         FontWeight.w400,
      fontStyle:          FontStyle.italic,
      letterSpacing:      -0.0675,
      height:             1.5,
      color:              color ?? kCueInkTertiary,
    );
  }
}
