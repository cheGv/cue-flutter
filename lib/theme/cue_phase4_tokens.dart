// lib/theme/cue_phase4_tokens.dart
//
// Locked Phase 4.0 visual tokens. Shared by every Layer-02+ surface.
// Established in Phase 4.0.3 (case history) and extracted here in Phase
// 4.0.4 once a third surface (live entry) needed the same palette.
//
// See PHASE_4_SPEC.md Section 4 (visual conformance) and CLAUDE.md §13.15
// for the discipline these tokens enforce. Global theme refactor (replacing
// the legacy teal register on add_client_screen, today_screen, etc.) is a
// separate polish phase — these tokens deliberately co-exist with the
// legacy palette during the Phase 4.0 buildout.

import 'package:flutter/material.dart';

// Surfaces ────────────────────────────────────────────────────────────────────
const Color kCuePaper        = Color(0xFFFAF7F0); // page / region background
const Color kCueSurface      = Color(0xFFFFFFFF); // card surface

// Ink ────────────────────────────────────────────────────────────────────────
const Color kCueInk          = Color(0xFF1A1A1A);
const Color kCueSubtitleInk  = Color(0x8C1A1A1A); // ~0.55α — subtitles
const Color kCueEyebrowInk   = Color(0x731A1A1A); // ~0.45α — lowercase tracked
const Color kCueMutedInk     = Color(0xB31A1A1A); // ~0.70α — secondary buttons

// Amber accent ───────────────────────────────────────────────────────────────
const Color kCueAmber        = Color(0xFFEF9F27); // primary accent
const Color kCueAmberSurface = Color(0xFFFAEEDA); // amber surface fill
const Color kCueAmberText    = Color(0xFF633806); // amber-on-surface text
const Color kCueAmberDeep    = Color(0xFFBA7517); // recording / live timer ink
const Color kCueAmberDeeper  = Color(0xFF854F0B); // amber-on-amber-surface eyebrow

// Borders ────────────────────────────────────────────────────────────────────
const Color kCueBorder       = Color(0x14000000); // ~0.08α — primary card hairline
const Color kCueBorderStrong = Color(0x1F000000); // ~0.12α — disfluency tile border

// Geometry ───────────────────────────────────────────────────────────────────
const double kCueCardRadius   = 12.0;
const double kCueChipRadius   = 20.0;
const double kCueTileRadius   = 10.0;
const double kCueCardBorderW  = 0.5;

// Eyebrow letter-spacing helper. 0.06em at the given font size, in absolute
// pixels (Flutter's letterSpacing is absolute, not em-relative).
double kCueEyebrowLetterSpacing(double fontSize) => fontSize * 0.06;
