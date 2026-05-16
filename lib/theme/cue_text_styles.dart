// lib/theme/cue_text_styles.dart
//
// Clients screen — locked visual spec tokens.
//
// This file is the single source of truth for the /clients redesign:
// the six text-style roles and the surface/border/accent palette, both
// resolved per Theme brightness (and, for text, per mobile breakpoint).
//
// Spec note: the hexes here are the Clients-screen locked palette. They
// intentionally diverge from the design-language spine in CLAUDE.md for
// this surface; the spine doc is updated to match only after the screen
// ships and is validated. Do not inline font sizes/weights/colors on the
// Clients screen — go through these tokens.

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// The six locked text roles for the Clients screen. Resolve once per
/// build with [CueTextStyles.of] — it carries both the dark/light and
/// the desktop/mobile axes.
class CueTextStyles {
  final bool isDark;
  final bool isMobile;

  const CueTextStyles._(this.isDark, this.isMobile);

  factory CueTextStyles.of(BuildContext context, {required bool isMobile}) {
    return CueTextStyles._(
      Theme.of(context).brightness == Brightness.dark,
      isMobile,
    );
  }

  /// Page identity line ("Everyone in your care.") — Playfair Display
  /// italic, burnt amber per mode.
  TextStyle get hero => GoogleFonts.playfairDisplay(
        fontStyle: FontStyle.italic,
        fontWeight: FontWeight.w400,
        fontSize: isMobile ? 22 : 30,
        height: 1.2,
        color: isDark ? const Color(0xFFF5C778) : const Color(0xFF854F0B),
      );

  /// Client name — DM Sans medium, primary text color.
  TextStyle get name => GoogleFonts.dmSans(
        fontWeight: FontWeight.w500,
        fontSize: isMobile ? 16 : 20,
        color: isDark ? const Color(0xFFF5F1E8) : const Color(0xFF2C2C2A),
      );

  /// Inline secondary info next to the name (age · diagnosis).
  TextStyle get meta => GoogleFonts.dmSans(
        fontWeight: FontWeight.w400,
        fontSize: isMobile ? 12 : 14,
        color: isDark ? const Color(0xFFA8A49A) : const Color(0xFF5F5E5A),
      );

  /// Clinical state line below the name row.
  TextStyle get prose => GoogleFonts.dmSans(
        fontWeight: FontWeight.w400,
        fontSize: isMobile ? 11 : 13,
        height: isMobile ? 1.5 : 1.55,
        color: isDark ? const Color(0xFFA8A49A) : const Color(0xFF5F5E5A),
      );

  /// Amber action line at the top of the list.
  TextStyle get action => GoogleFonts.dmSans(
        fontWeight: FontWeight.w400,
        fontSize: 13,
        color: isDark ? const Color(0xFFF5C778) : const Color(0xFF854F0B),
      );

  /// Small uppercase label (Syne, tracked). Caller passes the string
  /// already in the casing they want; this style does not transform.
  TextStyle get sectionLabel => GoogleFonts.syne(
        fontWeight: FontWeight.w500,
        fontSize: 11,
        letterSpacing: 11 * 0.12,
        color: const Color(0xFF888780),
      );
}

/// Surface / border / accent colors for the Clients screen, resolved per
/// Theme brightness. Text colors live on [CueTextStyles]; this carries
/// everything that isn't a glyph.
class CueClientsPalette {
  final bool isDark;

  const CueClientsPalette._(this.isDark);

  factory CueClientsPalette.of(BuildContext context) {
    return CueClientsPalette._(
      Theme.of(context).brightness == Brightness.dark,
    );
  }

  // ── Action line ────────────────────────────────────────────────────
  // Dark: rgba(245,158,11,0.08) fill / rgba(245,158,11,0.3) border.
  Color get actionBg =>
      isDark ? const Color(0x14F59E0B) : const Color(0xFFFAEEDA);
  Color get actionBorder =>
      isDark ? const Color(0x4DF59E0B) : const Color(0xFFEF9F27);

  // ── Search row ─────────────────────────────────────────────────────
  Color get searchBg =>
      isDark ? const Color(0xFF181715) : const Color(0xFFFAF7F0);

  /// Hairline border shared by the search input, ⌘K hint, and the
  /// ghost "+" button.
  Color get controlBorder =>
      isDark ? const Color(0xFF2D2B26) : const Color(0xFFD8D1C2);

  /// "+" glyph on the ghost new-client button.
  Color get ghostPlus =>
      isDark ? const Color(0xFFF5C778) : const Color(0xFFBA7517);

  // ── Tabs ───────────────────────────────────────────────────────────
  Color get tabSelectedBg =>
      isDark ? const Color(0xFF2A2620) : const Color(0xFFFAEEDA);

  // ── Text registers (mirror CueTextStyles, exposed for non-glyph use
  //    like pill borders and tab counts) ──────────────────────────────
  Color get textPrimary =>
      isDark ? const Color(0xFFF5F1E8) : const Color(0xFF2C2C2A);
  Color get textSecondary =>
      isDark ? const Color(0xFFA8A49A) : const Color(0xFF5F5E5A);
  Color get textTertiary => const Color(0xFF888780);

  // ── Client rows ────────────────────────────────────────────────────
  Color get rowDivider =>
      isDark ? const Color(0xFF2A2925) : const Color(0xFFEBE6DA);

  /// Uppercase domain word inside the clinical state line.
  Color get domain =>
      isDark ? const Color(0xFF97C459) : const Color(0xFF3B6D11);

  // Status pills.
  Color get activePillBorder => const Color(0xFF3B6D11);
  Color get activePillText =>
      isDark ? const Color(0xFF97C459) : const Color(0xFF3B6D11);
  Color get dischargedPillBorder => const Color(0xFF5F5E5A);
  Color get dischargedPillText => const Color(0xFF888780);

  /// Burnt amber — empty-state primary button + hero echo.
  Color get amber =>
      isDark ? const Color(0xFFF5C778) : const Color(0xFF854F0B);
}

// ─────────────────────────────────────────────────────────────────────────────
// Phase 4.1.0 — Chart screen text-style + palette extensions.
//
// The Phase 4.0.9 `CueTextStyles` above is locked to the Clients screen and
// list-row register. The Phase 4.1.0 chart rebuild introduces a structurally
// different register: a masthead with Playfair display name + 4 meta cards,
// page-width editorial Cue prose, a collapsible LTG/STG ladder with inline
// evidence, and session history rows. Tokens live in this same file (single
// source of truth for chart-screen typography) but as a parallel class so the
// Clients tokens remain untouched.
// ─────────────────────────────────────────────────────────────────────────────

class CueChartTextStyles {
  final bool isDark;
  final bool isMobile;

  const CueChartTextStyles._(this.isDark, this.isMobile);

  factory CueChartTextStyles.of(BuildContext context, {required bool isMobile}) {
    return CueChartTextStyles._(
      Theme.of(context).brightness == Brightness.dark,
      isMobile,
    );
  }

  Color get _textPrimary =>
      isDark ? const Color(0xFFF5F1E8) : const Color(0xFF2C2C2A);
  Color get _textSecondary =>
      isDark ? const Color(0xFFA8A49A) : const Color(0xFF5F5E5A);
  Color get _amber =>
      isDark ? const Color(0xFFF5C778) : const Color(0xFFBA7517);

  /// Masthead client name — Playfair Display 36 desktop / 28 mobile.
  TextStyle get chartName => GoogleFonts.playfairDisplay(
        fontWeight: FontWeight.w500,
        fontSize: isMobile ? 28 : 36,
        height: 1.1,
        letterSpacing: (isMobile ? 28 : 36) * -0.015,
        color: _textPrimary,
      );

  /// Inline age beside the name — DM Sans 15px regular, secondary text.
  TextStyle get chartAge => GoogleFonts.dmSans(
        fontWeight: FontWeight.w400,
        fontSize: isMobile ? 14 : 15,
        color: _textSecondary,
      );

  /// Meta card label (Syne uppercase 10px tracked). Caller supplies casing.
  // Phase 4.1.1 — meta card register narrowed. Cards now read as
  // passport-strip metadata rather than dashboard tiles; sizes step down
  // so the Cue card editorial moment beneath the masthead leads.
  TextStyle get metaLabel => GoogleFonts.syne(
        fontWeight: FontWeight.w500,
        fontSize: 9,
        letterSpacing: 9 * 0.12,
        color: _textSecondary,
      );

  /// Meta card primary value — DM Sans 14px medium (Phase 4.1.1).
  TextStyle get metaValue => GoogleFonts.dmSans(
        fontWeight: FontWeight.w500,
        fontSize: 14,
        color: _textPrimary,
      );

  /// Meta card secondary context — DM Sans 10px regular (Phase 4.1.1).
  TextStyle get metaContext => GoogleFonts.dmSans(
        fontWeight: FontWeight.w400,
        fontSize: 10,
        height: 1.4,
        color: _textSecondary,
      );

  /// Diagnosis chip text — Syne 11px tracked uppercase, olive.
  TextStyle get diagnosisPill => GoogleFonts.syne(
        fontWeight: FontWeight.w500,
        fontSize: 11,
        letterSpacing: 11 * 0.1,
        color: const Color(0xFF97C459),
      );

  /// Cue editorial header label — DM Sans italic 13px amber.
  TextStyle get cueEditorialEyebrow => GoogleFonts.dmSans(
        fontStyle: FontStyle.italic,
        fontWeight: FontWeight.w400,
        fontSize: 13,
        color: _amber,
      );

  /// Cue editorial prose — Playfair Display italic 24/20 primary text.
  /// `tabularFigures` keeps digit widths consistent so dates ("May 13th")
  /// and ordinals don't shift other glyphs as Playfair italic loads.
  TextStyle get cueEditorialProse => GoogleFonts.playfairDisplay(
        fontStyle: FontStyle.italic,
        fontWeight: FontWeight.w400,
        fontSize: isMobile ? 20 : 24,
        height: 1.5,
        color: _textPrimary,
        fontFeatures: const [FontFeature.tabularFigures()],
      );

  /// Ladder eyebrow (LTG / STG / "Active steps · N") — Syne uppercase tracked.
  TextStyle get ladderEyebrow => GoogleFonts.syne(
        fontWeight: FontWeight.w500,
        fontSize: 10,
        letterSpacing: 10 * 0.14,
        color: _textSecondary,
      );

  /// Domain code pill text — Syne 10px tracked, olive.
  TextStyle get domainPill => GoogleFonts.syne(
        fontWeight: FontWeight.w500,
        fontSize: 10,
        letterSpacing: 10 * 0.12,
        color: const Color(0xFF97C459),
      );

  /// Ladder body prose — DM Sans 14px line-height 1.55.
  TextStyle get ladderBody => GoogleFonts.dmSans(
        fontWeight: FontWeight.w400,
        fontSize: 14,
        height: 1.55,
        color: _textPrimary,
      );

  /// Ladder duration meta — DM Sans 11px secondary.
  TextStyle get ladderDuration => GoogleFonts.dmSans(
        fontWeight: FontWeight.w400,
        fontSize: 11,
        color: _textSecondary,
      );

  /// Active-step row primary text — DM Sans 13px primary.
  TextStyle get stepText => GoogleFonts.dmSans(
        fontWeight: FontWeight.w400,
        fontSize: 13,
        height: 1.5,
        color: _textPrimary,
      );

  /// Active-step row week-progress meta — DM Sans 13px secondary.
  TextStyle get stepWeek => GoogleFonts.dmSans(
        fontWeight: FontWeight.w400,
        fontSize: 13,
        color: _textSecondary,
      );

  /// Cue's evidence inline body — DM Sans italic 13px line-height 1.6.
  TextStyle get evidenceBody => GoogleFonts.dmSans(
        fontStyle: FontStyle.italic,
        fontWeight: FontWeight.w400,
        fontSize: 13,
        height: 1.6,
        color: _textSecondary,
      );

  /// Session-history header — Syne uppercase 10px tracked.
  TextStyle get historyHeader => GoogleFonts.syne(
        fontWeight: FontWeight.w500,
        fontSize: 10,
        letterSpacing: 10 * 0.1,
        color: _textSecondary,
      );

  /// Session-row pull quote — DM Sans 13px primary.
  TextStyle get historyQuote => GoogleFonts.dmSans(
        fontWeight: FontWeight.w400,
        fontSize: 13,
        height: 1.5,
        color: _textPrimary,
      );

  /// Session-row meta — DM Sans 11px secondary.
  TextStyle get historyMeta => GoogleFonts.dmSans(
        fontWeight: FontWeight.w400,
        fontSize: 11,
        color: _textSecondary,
      );

  /// Session-row body when expanded — DM Sans 13px line-height 1.6 primary.
  TextStyle get historyBody => GoogleFonts.dmSans(
        fontWeight: FontWeight.w400,
        fontSize: 13,
        height: 1.6,
        color: _textPrimary,
      );

  /// Floating action-bar action label — DM Sans 13px medium.
  TextStyle get actionBarLabel => GoogleFonts.dmSans(
        fontWeight: FontWeight.w500,
        fontSize: 13,
        color: _textPrimary,
      );
}

/// Phase 4.1.0 — Chart screen palette extension. The chart screen's meta
/// cards, evidence surfaces, and citation highlights use surface tones that
/// don't exist elsewhere in the app, so they live in their own class rather
/// than enlarging [CueColorsResolved]. Other chart colors (textPrimary,
/// olive, amber) come from [CueColorsResolved] — this class only adds what's
/// chart-screen-specific.
class CueChartPalette {
  final bool isDark;

  const CueChartPalette._(this.isDark);

  factory CueChartPalette.of(BuildContext context) {
    return CueChartPalette._(
      Theme.of(context).brightness == Brightness.dark,
    );
  }

  // ── Meta cards (4 cards across the masthead) ───────────────────────────
  Color get metaCardSurface =>
      isDark ? const Color(0x661F1E1A) : const Color(0x99FFFFFF);
  Color get metaCardBorder =>
      isDark ? const Color(0xFF2A2925) : const Color(0xFFE8E2D4);

  // ── Diagnosis pill (olive at low alpha) ────────────────────────────────
  Color get diagnosisPillBg => const Color(0x1F97C459); // ~0.12 alpha olive
  Color get diagnosisPillBorder => const Color(0x4097C459); // ~0.25 alpha

  // ── Evidence inline surface (amber-tinted, left-border accent) ─────────
  Color get evidenceSurface => const Color(0x0AF5C778); // ~0.04 alpha amber
  Color get evidenceBorderLeft => const Color(0x59F5C778); // ~0.35 alpha amber

  // ── Citation highlight inside Cue's editorial prose ────────────────────
  //
  // Phase 4.1.3 item B.2 — light-mode treatment shifts to a slightly more
  // saturated warm tint (#F0E5C8) with a 1.5px amber border so the
  // highlighted phrase survives against the near-white page (#FCFAF6).
  // Dark mode keeps the original low-alpha amber wash.
  Color get citationBg =>
      isDark ? const Color(0x1FF5C778) : const Color(0xFFF0E5C8);
  Color get citationBorder =>
      isDark ? const Color(0x59F5C778) : const Color(0xFFBA7517);
  double get citationBorderWidth => isDark ? 1.0 : 1.5;

  // ── Clinical-term auto-highlight inside Cue's evidence body ────────────
  // Reuses the citation palette; separate getters so future tuning of one
  // doesn't drift the other.
  Color get clinicalHighlightBg =>
      isDark ? const Color(0x26F5C778) : const Color(0x1FF5C778); // 0.15 / 0.12 alpha
  Color get clinicalHighlightBorder => const Color(0x59F5C778); // 0.35 alpha

  // ── The Hold (global cuttlefish pill in the top bar) ───────────────────
  Color get holdSurface =>
      isDark ? const Color(0xD91F1E1A) : const Color(0xD9FFFFFF); // 0.85 alpha
  Color get holdBorder => const Color(0x40F5C778); // ~0.25 alpha amber

  // ── Floating action bar pill ───────────────────────────────────────────
  Color get actionBarSurface =>
      isDark ? const Color(0xF71F1E1A) : const Color(0xF7FFFFFF);
  Color get actionBarBorder =>
      isDark ? const Color(0xFF2D2B26) : const Color(0xFFE8E2D4);
  Color get actionBarDivider =>
      isDark ? const Color(0xFF2D2B26) : const Color(0xFFE8E2D4);
  Color get actionBarShadow =>
      isDark ? const Color(0x802C2C2A) : const Color(0x262C2C2A);

  // ── Section dividers used by the ladder and history rows ───────────────
  Color get sectionDivider =>
      isDark ? const Color(0xFF2A2925) : const Color(0xFFE2DDD2);

  // ── Phase 4.1.2 — STG-in-focus surfaces and evidence tier colors ───────
  //
  // Light mode: page is near-white (#FCFAF6); focused STG sits ABOVE the
  // page on a warmer cream wash (#F4ECD8); compact STG rows use a subtler
  // intermediate tint (#F8F2E4). Dark mode reverses the elevation
  // metaphor — focused surface is slightly more saturated than compact.

  Color get focusedSurface =>
      isDark ? const Color(0x801F1E1A) : const Color(0xFFF4ECD8);
  Color get compactSurface =>
      isDark ? const Color(0x4D1F1E1A) : const Color(0xFFF8F2E4);

  // Evidence tier chip colors per Phase 4.1.2 spec.
  Color get evidenceLevelI =>
      isDark ? const Color(0xFF5DCAA5) : const Color(0xFF0F6E56);
  Color get evidenceLevelII =>
      isDark ? const Color(0xFFF5C778) : const Color(0xFF854F0B);
  Color get evidenceLevelIIIIV =>
      isDark ? const Color(0xFFA8A49A) : const Color(0xFF5F5E5A);

  // Subtle amber wash for the "Think with Cue" pill in the focused STG.
  Color get amberAccentSurface =>
      isDark ? const Color(0x1AF5C778) : const Color(0x0FBA7517); // 10% / 6% alpha
  Color get amberAccentBorder =>
      isDark ? const Color(0x66F5C778) : const Color(0x66BA7517); // 40% alpha

  // ── Discharged / archived gray surface (per spine doc kCueGraySurface) ─
  Color get graySurface =>
      isDark ? const Color(0xFF1F1E1A) : const Color(0xFFF1EFE8);

  // ── Timeline-strip tick colors (mapped from session outcome_type when
  //     present; defaults to olive when the field is absent) ──────────────
  Color get tickProgress => const Color(0xFF97C459);
  Color get tickRevised => const Color(0xFFF5C778);
}
