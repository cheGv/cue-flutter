// lib/theme/cue_phase4_tokens.dart
//
// Phase 4.0.8 — spine-aligned visual tokens.
//
// Ground truth: docs/design-language-spine-2026-05-08.md.
// Step B-surface-1 (this file's current revision) corrects the eight
// tokens the spine locks (paper / surface / ink / ink-secondary /
// ink-tertiary / amber / amber-deep / border) and adjusts the
// geometry tokens to the spine's "6 for cards, 8 for medium
// containers, larger only when explicitly editorial" rule. The
// eyebrow letter-spacing helper now matches the spine's +0.14em.
//
// Pre-spine tokens are preserved as @Deprecated aliases so surfaces
// 2-8 keep compiling during the per-surface migration laid out in
// the spine doc's implementation order. Each alias points to the new
// canonical token (or carries a one-line replacement note for
// editorial-register decisions). Surfaces sunset their alias usage as
// they migrate; surface 8 deletes the aliases.
//
// Some pre-spine tokens (kCueSubtitleInk / kCueEyebrowInk /
// kCueMutedInk / kCueAmberSurface / kCueAmberText / kCueBorderStrong)
// remain non-deprecated for now — they encode alpha and supporting-
// surface decisions the spine doesn't directly contradict, and
// per-surface migration may decide each independently. Their hex
// bases are intentionally NOT updated to the new ink hue; surfaces
// using them get to choose between the legacy ink-on-amber blend
// and a fresh derivation from the spine kCueInk during their own
// migration commit.

import 'package:flutter/material.dart';

// ── Surfaces ─────────────────────────────────────────────────────────────────
const Color kCuePaper        = Color(0xFFFAF7F0); // page / region background
const Color kCueSurfaceWhite = Color(0xFFFFFFFF); // card surface (spine name)

@Deprecated('Use kCueSurfaceWhite — sunset target: surface 8 cleanup')
const Color kCueSurface      = kCueSurfaceWhite;

// ── Ink ──────────────────────────────────────────────────────────────────────
const Color kCueInk          = Color(0xFF1B2B4B); // primary text + active accents
const Color kCueInkSecondary = Color(0xFF5F5E5A); // body text, secondary content
const Color kCueInkTertiary  = Color(0xFF888780); // eyebrow labels, metadata

// Pre-spine ink derivations (alpha-modulated against #1A1A1A). Preserved
// at their legacy hue intentionally — surfaces using them migrate per
// their own register, deciding whether to rebase against kCueInk's new
// #1B2B4B or keep the warmer #1A1A1A blend.
const Color kCueSubtitleInk  = Color(0x8C1A1A1A); // ~0.55α — subtitles
const Color kCueEyebrowInk   = Color(0x731A1A1A); // ~0.45α — lowercase tracked
const Color kCueMutedInk     = Color(0xB31A1A1A); // ~0.70α — secondary buttons

// ── Amber accent (urgent register) ───────────────────────────────────────────
//
// Phase 4.0.8-step-B-surface-1.2 — dual-accent semantic system. Amber
// signals urgency: attention deadlines, primary actions, "Up next"
// indicators, the yesterday-reminder. Olive (below) handles every other
// accent need — calm/steady/clinical/navigation. The split was learned
// from the friend-tester signal: a single amber accent across the whole
// surface produced shouty register; restraint requires two registers,
// not zero.
const Color kCueAmber        = Color(0xFFB45309); // urgent accent
const Color kCueAmberDeep    = Color(0xFF854F0B); // pending pill text, warning state

// ── Olive accent (calm register) ─────────────────────────────────────────────
//
// Phase 4.0.8-step-B-surface-1.2 — calm/steady accent. Olive owns:
//   • clinical state indicators (left-stripe on session brief cards)
//   • clinical card eyebrows ("Today's move")
//   • inline trial counts in card prose
//   • sidebar active state (desaturated for dark ground — see
//     #B8C572 inline in app_layout.dart)
//   • non-urgent state pill grounds
// Olive is the default UI accent on Today; amber is the exception
// reserved for urgency. Friend-tester signal locked this: a patrician
// calm register that doesn't slip toward outdoor/military.
const Color kCueOlive        = Color(0xFF5C6E3B); // calm/steady accent
const Color kCueOliveSurface = Color(0xFFEDEBD8); // pill grounds, optional tint
const Color kCueOliveDeep    = Color(0xFF3F4A28); // text on olive surface

@Deprecated('Use kCueAmberDeep — sunset target: surface 8 cleanup')
const Color kCueAmberDeeper  = kCueAmberDeep;

// Pre-spine amber supporting tones — surface backgrounds and on-surface
// text. Preserved; per-surface migration decides whether to keep or
// derive new tints from the spine kCueAmber.
const Color kCueAmberSurface = Color(0xFFFAEEDA); // amber surface fill
const Color kCueAmberText    = Color(0xFF633806); // amber-on-surface text

// ── Quiet gray surface ───────────────────────────────────────────────────────
//
// Phase 4.0.9-step-A — added for the Roster surface 2 design. Distinct
// from kCueBorder (a hairline color, not a fill). Use for: discharged
// pills, archived items, deactivated states — anywhere the register is
// "present but recessed."
const Color kCueGraySurface  = Color(0xFFF1EFE8); // quiet gray fill

// ── Borders ──────────────────────────────────────────────────────────────────
const Color kCueBorder       = Color(0xFFE8E4DC); // hairline border (spine)
const Color kCueBorderStrong = Color(0x1F000000); // ~0.12α — disfluency tile border

// ── Geometry ─────────────────────────────────────────────────────────────────
//
// Spine rule: 6px for cards, 8px for medium containers, larger only when
// explicitly editorial. kCueChipRadius and kCueTileRadius retained as
// deprecated aliases pointing to the spine values; surfaces migrate by
// referencing the new constants directly.
const double kCueCardRadius   = 6.0;   // spine: cards
const double kCueMediumRadius = 8.0;   // spine: medium containers
const double kCueCardBorderW  = 0.5;

@Deprecated('Use kCueMediumRadius — sunset target: surface 8 cleanup')
const double kCueTileRadius   = kCueMediumRadius;

@Deprecated('Editorial register only — call out the editorial intent at the use site, or migrate to kCueMediumRadius. Sunset target: surface 8 cleanup.')
const double kCueChipRadius   = 20.0;

// Eyebrow letter-spacing helper. Spine specifies +0.14em at the given
// font size; Flutter's letterSpacing is absolute pixels.
double kCueEyebrowLetterSpacing(double fontSize) => fontSize * 0.14;
