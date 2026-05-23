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

import '../models/citation.dart' show EvidenceTier;
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

  // Phase B chart (Reading Room register). sienna = active clinical
  // commitment; chartPaper = the chart page ground; trajectory* = the
  // three-state session-tick palette.
  final Color sienna;
  final Color chartPaper;
  final Color trajectoryProgress;
  final Color trajectoryRevised;
  final Color trajectoryHolding;

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
    required this.sienna,
    required this.chartPaper,
    required this.trajectoryProgress,
    required this.trajectoryRevised,
    required this.trajectoryHolding,
  });

  // Phase 4.1.2 — day mode token shift (Option B). Light mode moves from
  // a warm-cream page (#FAF7F0) with navy primary text (kCueInk) to a
  // near-white page (#FCFAF6) with warm near-black primary text (#1F1F1D).
  // Cream surfaces sit ABOVE the page, not below it: focused / compact
  // STG surfaces are now warmer than the page they sit on. Dark mode is
  // unchanged (the dark register already has correct contrast budget).
  static const _light = CueColorsResolved._(
    isDark:         false,
    bgCanvas:       Color(0xFFFCFAF6),               // was t.kCuePaper #FAF7F0
    bgCard:         t.kCueSurfaceWhite,
    bgCardHover:    Color(0xFFFCFAF6),               // matches bgCanvas
    bgChrome:       t.kCueInk,
    bgInput:        t.kCueSurfaceWhite,
    bgMuted:        Color(0x14736B62), // 8% alpha kCueInkSecondary tone
    border:         Color(0xFFE2DDD2),               // was t.kCueBorder #E8E4DC
    borderHover:    Color(0xFFD8D2C5),
    borderEmphasis: Color(0xFFCEC8BA),
    borderMuted:    Color(0xFFEEE9DD),               // between border and bgCanvas
    textPrimary:    Color(0xFF1F1F1D),               // warm near-black, was kCueInk navy
    textBody:       Color(0xFF6B6862),               // medium-darker grey, was kCueInkSecondary
    textSecondary:  Color(0xFF6B6862),               // alias for textBody
    textMuted:      t.kCueInkTertiary,
    textDim:        Color(0xFFB4B2A9),
    olive:          t.kCueOlive,
    amber:          Color(0xFFBA7517),               // burnt amber, was kCueAmber #B45309
    amberDeep:      t.kCueAmberDeep,
    blue:           t.kCueInk,
    purple:         t.kCueInkSecondary,
    coral:          CueColors.coral,
    teal:           CueColors.teal,
    tealSurface:    Color(0x1F1F8870), // 12% alpha of CueColors.teal
    tealFaded:      Color(0x4D1F8870), // 30% alpha of CueColors.teal
    red:            CueColors.coral,
    sienna:             CueColors.sienna,
    chartPaper:         CueColors.creamPaper,
    trajectoryProgress: CueColors.trajectoryProgress,
    trajectoryRevised:  CueColors.trajectoryRevised,
    trajectoryHolding:  CueColors.trajectoryHolding,
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
    sienna:             CueColors.siennaDark,
    chartPaper:         CueColors.darkPaper,
    trajectoryProgress: CueColors.trajectoryProgressDark,
    trajectoryRevised:  CueColors.trajectoryRevisedDark,
    trajectoryHolding:  CueColors.trajectoryHolding,
  );

  factory CueColorsResolved.of(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark ? _dark : _light;
  }
}

/// Phase B evidence-ladder tier chip colors (locked 2026-05-22). Kept in the
/// token file so chart widgets stay hex-free. level_3 and practice share the
/// neutral grey treatment.
class CueEvidenceTierColors {
  final bool isDark;
  const CueEvidenceTierColors._(this.isDark);

  factory CueEvidenceTierColors.of(BuildContext context) =>
      CueEvidenceTierColors._(
        Theme.of(context).brightness == Brightness.dark,
      );

  Color bg(EvidenceTier t) => switch (t) {
        EvidenceTier.level1 =>
          isDark ? const Color(0x245DCAA5) : const Color(0x1A0A4D40),
        EvidenceTier.level2 =>
          isDark ? const Color(0x24FAC775) : const Color(0x1FBA7517),
        EvidenceTier.level3 || EvidenceTier.practice =>
          isDark ? const Color(0x24B4B2A9) : const Color(0x1F888780),
      };

  Color fg(EvidenceTier t) => switch (t) {
        EvidenceTier.level1 =>
          isDark ? const Color(0xFF5DCAA5) : const Color(0xFF085041),
        EvidenceTier.level2 =>
          isDark ? const Color(0xFFFAC775) : const Color(0xFF633806),
        EvidenceTier.level3 || EvidenceTier.practice =>
          isDark ? const Color(0xFFB4B2A9) : const Color(0xFF444441),
      };
}

// ─────────────────────────────────────────────────────────────────────────────
// Phase B-revised — cards-on-canvas chart token set (locked 2026-05-23).
//
// Hexes copied verbatim from the `--chart-light` / `--chart-dark` CSS variables
// in docs/decisions/phase-b-chart-visual.html (the locked reference). This is
// ADDITIVE: the older Reading-Room chart tokens (CueColors.sienna / chartPaper /
// trajectory*) stay untouched because client_sessions_screen,
// session_planning_screen, and substrate_view still resolve them. The chart
// widgets simply stop importing the old register.
//
// Alpha bytes: 0.03→0x08, 0.04→0x0A, 0.06→0x0F, 0.10→0x1A, 0.12→0x1F,
// 0.15→0x26, 0.20→0x33, 0.30→0x4D, 0.40→0x66.
// ─────────────────────────────────────────────────────────────────────────────
class CueChartTokens {
  final bool isDark;

  // Surfaces
  final Color bgCanvas;
  final Color bgCard;
  final Color bgCardHead;
  final Color bgInset;
  final Color bgStgSection;
  final Color bgNarrator;
  final Color bgNarratorRail;

  // Borders
  final Color borderCard;
  final Color borderInset;
  final Color borderDivider;

  // Text (primary → faint)
  final Color textPrimary;
  final Color textBody;
  final Color textSecondary;
  final Color textTertiary;
  final Color textMuted;
  final Color textFaint;

  // Accent (orange light / amber dark)
  final Color accent;
  final Color accentSoftBg;
  final Color accentPulse;
  final Color accentPulse2;
  final Color accentShadow;

  // Primary button (inverts in dark: cream bg, dark label)
  final Color btnPrimaryBg;
  final Color btnPrimaryHover;
  final Color btnPrimaryText;

  // Evidence tiers
  final Color tier1Bg, tier1Text;
  final Color tier2Bg, tier2Text;
  final Color tier3Bg, tier3Text;
  final Color tierPracticeBg, tierPracticeText;

  // Session outcomes (bg / text / mark)
  final Color outcomeProgressBg, outcomeProgressText, outcomeProgressMark;
  final Color outcomeRevisedBg, outcomeRevisedText, outcomeRevisedMark;
  final Color outcomeHoldingBg, outcomeHoldingText, outcomeHoldingMark;

  // Info badge (LTG horizon "12 months")
  final Color infoBadgeBg, infoBadgeText;

  // Trajectory empty-track diagonal hatch
  final Color hatchFrom, hatchTo;

  // Shadows
  final List<BoxShadow> shadowCard;
  final List<BoxShadow> shadowFocus;

  const CueChartTokens._({
    required this.isDark,
    required this.bgCanvas,
    required this.bgCard,
    required this.bgCardHead,
    required this.bgInset,
    required this.bgStgSection,
    required this.bgNarrator,
    required this.bgNarratorRail,
    required this.borderCard,
    required this.borderInset,
    required this.borderDivider,
    required this.textPrimary,
    required this.textBody,
    required this.textSecondary,
    required this.textTertiary,
    required this.textMuted,
    required this.textFaint,
    required this.accent,
    required this.accentSoftBg,
    required this.accentPulse,
    required this.accentPulse2,
    required this.accentShadow,
    required this.btnPrimaryBg,
    required this.btnPrimaryHover,
    required this.btnPrimaryText,
    required this.tier1Bg,
    required this.tier1Text,
    required this.tier2Bg,
    required this.tier2Text,
    required this.tier3Bg,
    required this.tier3Text,
    required this.tierPracticeBg,
    required this.tierPracticeText,
    required this.outcomeProgressBg,
    required this.outcomeProgressText,
    required this.outcomeProgressMark,
    required this.outcomeRevisedBg,
    required this.outcomeRevisedText,
    required this.outcomeRevisedMark,
    required this.outcomeHoldingBg,
    required this.outcomeHoldingText,
    required this.outcomeHoldingMark,
    required this.infoBadgeBg,
    required this.infoBadgeText,
    required this.hatchFrom,
    required this.hatchTo,
    required this.shadowCard,
    required this.shadowFocus,
  });

  static const _light = CueChartTokens._(
    isDark: false,
    bgCanvas: Color(0xFFF1F5F9),
    bgCard: Color(0xFFFFFFFF),
    bgCardHead: Color(0xFFF8FAFC),
    bgInset: Color(0xFFF8FAFC),
    bgStgSection: Color(0xFFF8FAFC),
    bgNarrator: Color(0xFFF8FAFC),
    bgNarratorRail: Color(0xFF0F172A),
    borderCard: Color(0xFFE2E8F0),
    borderInset: Color(0xFFE2E8F0),
    borderDivider: Color(0xFFF1F5F9),
    textPrimary: Color(0xFF0F172A),
    textBody: Color(0xFF1E293B),
    textSecondary: Color(0xFF475569),
    textTertiary: Color(0xFF64748B),
    textMuted: Color(0xFF94A3B8),
    textFaint: Color(0xFFCBD5E1),
    accent: Color(0xFFEA580C),
    accentSoftBg: Color(0xFFFFF7ED),
    accentPulse: Color(0x33EA580C),
    accentPulse2: Color(0x14EA580C),
    accentShadow: Color(0x0FEA580C),
    btnPrimaryBg: Color(0xFF0F172A),
    btnPrimaryHover: Color(0xFF1E293B),
    btnPrimaryText: Color(0xFFFFFFFF),
    tier1Bg: Color(0xFFDCFCE7),
    tier1Text: Color(0xFF14532D),
    tier2Bg: Color(0xFFDBEAFE),
    tier2Text: Color(0xFF1E3A8A),
    tier3Bg: Color(0xFFFED7AA),
    tier3Text: Color(0xFF9A3412),
    tierPracticeBg: Color(0xFFF1F5F9),
    tierPracticeText: Color(0xFF475569),
    outcomeProgressBg: Color(0xFFDCFCE7),
    outcomeProgressText: Color(0xFF14532D),
    outcomeProgressMark: Color(0xFF16A34A),
    outcomeRevisedBg: Color(0xFFFFEDD5),
    outcomeRevisedText: Color(0xFF9A3412),
    outcomeRevisedMark: Color(0xFFEA580C),
    outcomeHoldingBg: Color(0xFFF1F5F9),
    outcomeHoldingText: Color(0xFF475569),
    outcomeHoldingMark: Color(0xFF64748B),
    infoBadgeBg: Color(0xFFE0F2FE),
    infoBadgeText: Color(0xFF075985),
    hatchFrom: Color(0xFFF8FAFC),
    hatchTo: Color(0xFFF1F5F9),
    shadowCard: [
      BoxShadow(color: Color(0x0A0F172A), offset: Offset(0, 1), blurRadius: 3),
      BoxShadow(color: Color(0x080F172A), offset: Offset(0, 1), blurRadius: 2),
    ],
    shadowFocus: [
      BoxShadow(color: Color(0x0FEA580C), offset: Offset(0, 2), blurRadius: 6),
      BoxShadow(color: Color(0x0A0F172A), offset: Offset(0, 1), blurRadius: 3),
    ],
  );

  static const _dark = CueChartTokens._(
    isDark: true,
    bgCanvas: Color(0xFF14110D),
    bgCard: Color(0xFF1F1C17),
    bgCardHead: Color(0xFF2A2620),
    bgInset: Color(0xFF28241F),
    bgStgSection: Color(0xFF2A2620),
    bgNarrator: Color(0xFF28241F),
    bgNarratorRail: Color(0xFFFEF3C7),
    borderCard: Color(0xFF3A342C),
    borderInset: Color(0xFF3A342C),
    borderDivider: Color(0xFF2A2620),
    textPrimary: Color(0xFFFEFCE8),
    textBody: Color(0xFFF5F0E3),
    textSecondary: Color(0xFFD1C7B3),
    textTertiary: Color(0xFFA39685),
    textMuted: Color(0xFF7A6F5E),
    textFaint: Color(0xFF4D4438),
    accent: Color(0xFFFB923C),
    accentSoftBg: Color(0x1FFB923C),
    accentPulse: Color(0x4DFB923C),
    accentPulse2: Color(0x1AFB923C),
    accentShadow: Color(0x26FB923C),
    btnPrimaryBg: Color(0xFFFEF3C7),
    btnPrimaryHover: Color(0xFFFDE68A),
    btnPrimaryText: Color(0xFF14110D),
    tier1Bg: Color(0x2622C55E),
    tier1Text: Color(0xFF86EFAC),
    tier2Bg: Color(0x2660A5FA),
    tier2Text: Color(0xFF93C5FD),
    tier3Bg: Color(0x26FB923C),
    tier3Text: Color(0xFFFDBA74),
    tierPracticeBg: Color(0x0FFFFFFF),
    tierPracticeText: Color(0xFFA39685),
    outcomeProgressBg: Color(0x2622C55E),
    outcomeProgressText: Color(0xFF86EFAC),
    outcomeProgressMark: Color(0xFF22C55E),
    outcomeRevisedBg: Color(0x26FB923C),
    outcomeRevisedText: Color(0xFFFDBA74),
    outcomeRevisedMark: Color(0xFFFB923C),
    outcomeHoldingBg: Color(0x0FFFFFFF),
    outcomeHoldingText: Color(0xFFA39685),
    outcomeHoldingMark: Color(0xFF78716C),
    infoBadgeBg: Color(0x2638BDF8),
    infoBadgeText: Color(0xFF7DD3FC),
    hatchFrom: Color(0xFF28241F),
    hatchTo: Color(0xFF2E2A23),
    shadowCard: [
      BoxShadow(color: Color(0x66000000), offset: Offset(0, 1), blurRadius: 3),
      BoxShadow(color: Color(0x4D000000), offset: Offset(0, 1), blurRadius: 2),
    ],
    shadowFocus: [
      BoxShadow(color: Color(0x1FFB923C), offset: Offset(0, 2), blurRadius: 8),
      BoxShadow(color: Color(0x66000000), offset: Offset(0, 1), blurRadius: 3),
    ],
  );

  factory CueChartTokens.of(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? _dark : _light;

  // Evidence-tier chip colors. lvl-3 is its own (orange) register, distinct
  // from practice (neutral) — matching the reference (the old
  // CueEvidenceTierColors collapsed level3 + practice).
  Color tierBg(EvidenceTier t) => switch (t) {
        EvidenceTier.level1 => tier1Bg,
        EvidenceTier.level2 => tier2Bg,
        EvidenceTier.level3 => tier3Bg,
        EvidenceTier.practice => tierPracticeBg,
      };
  Color tierText(EvidenceTier t) => switch (t) {
        EvidenceTier.level1 => tier1Text,
        EvidenceTier.level2 => tier2Text,
        EvidenceTier.level3 => tier3Text,
        EvidenceTier.practice => tierPracticeText,
      };

  // Session-outcome resolution by sessions.outcome db value (null → neutral).
  Color outcomeMark(String? db) => switch (db) {
        'progress' => outcomeProgressMark,
        'plan_revised' => outcomeRevisedMark,
        'holding' => outcomeHoldingMark,
        _ => outcomeHoldingMark,
      };
  Color outcomeBg(String? db) => switch (db) {
        'progress' => outcomeProgressBg,
        'plan_revised' => outcomeRevisedBg,
        'holding' => outcomeHoldingBg,
        _ => outcomeHoldingBg,
      };
  Color outcomeText(String? db) => switch (db) {
        'progress' => outcomeProgressText,
        'plan_revised' => outcomeRevisedText,
        'holding' => outcomeHoldingText,
        _ => outcomeHoldingText,
      };
  // Short uppercase tag label. Neutral, §language-discipline-safe word for the
  // null case (a documented session with no outcome classification).
  String outcomeLabel(String? db) => switch (db) {
        'progress' => 'Progress',
        'plan_revised' => 'Revised',
        'holding' => 'Holding',
        _ => 'Logged',
      };
}
