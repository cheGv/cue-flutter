// lib/animation/cue_motion.dart
//
// Phase 4.2 motion tokens. Centralizes the durations, curves, and
// magnitudes that define Cue's voice in motion. Three behaviors codify
// here: (1) page-entrance choreography on Today + Roster, (2) card
// hover rise on TodayBriefCard / ClientsRosterRow / yesterday rows,
// (3) cuttlefish glance toward hovered client on Today.
//
// Spine reference: docs/design-language-spine-2026-05-08.md, Revision
// 2026-05-10 (animation layer).
//
// Principle (banked): motion lives where the user benefits from it,
// not on every interaction. Click transitions stay default
// MaterialPageRoute; we don't paint custom theatre on navigation.

import 'package:flutter/widgets.dart';

// ── Page entrance ──────────────────────────────────────────────────────────
//
// Each major page section fades up + translates 12px on first build,
// staggered 80ms after the prior. easeOutCubic — no overshoot here;
// entrance is calm, not bouncy. Stagger is capped at 12 elements (see
// kMotionStaggerMaxIndex below) so long lists don't pop in below the
// fold while the user is already scrolling.

const Duration kMotionPageEntranceStagger  = Duration(milliseconds: 80);
const Duration kMotionPageEntranceDuration = Duration(milliseconds: 350);
const Curve    kMotionPageEntranceCurve    = Curves.easeOutCubic;
const double   kMotionPageEntranceTranslateY = 12.0;

/// Cap on staggered entrance elements. Index 0..11 stagger; index 12+
/// renders instantly. Applies to:
///   • Today's brief card stack (`_buildTodayBriefStack`)
///   • Roster list rows
/// Rationale: an SLP with 30 clients shouldn't watch each row pop in
/// over 1800+ ms — the bottom of the list would still be animating
/// after she's scrolled past it.
const int kMotionStaggerMaxIndex = 11;

// ── Hover rise ─────────────────────────────────────────────────────────────
//
// Card / row hover lift: 2px translate up, stripe widens + lengthens
// + darkens, background tints to paper. 200ms with mild overshoot via
// a custom cubic — responsive but not theatrical.

const Duration kMotionHoverDuration  = Duration(milliseconds: 200);
const double   kMotionHoverLiftY     = -2.0;

/// Hover curve — `Cubic(0.34, 1.1, 0.64, 1.0)`. Approximates an
/// easeOutBack with a 1.1-overshoot factor: enough to read as
/// responsive without crossing into "playful." The 0.34 first-x
/// matches easeOutCubic's snap; the 1.1 second-y is the gentle
/// overshoot that lets the card "settle" into its hover pose.
const Curve kMotionHoverCurve = Cubic(0.34, 1.1, 0.64, 1.0);

// ── Cuttlefish glance ──────────────────────────────────────────────────────
//
// The cuttlefish on Today's greeting block tilts her body and shifts
// her eyes toward the hovered card. Down-right convention (locked in
// the Phase 4.2 recon): the cuttlefish lives at the top of the page;
// hover targets (yesterday rows + first brief card) sit BELOW her in
// actual page geometry, so positive glanceAngle = "look down-right."
//
//        cuttlefish
//        ────●────►  glanceAngle = 0      (neutral, looking forward)
//             ╲
//              ╲─►   glanceAngle = +1.0   (max down-right)
//               ╲
//              hovered card / row
//
// In the painter:
//   • Body rotation: canvas.rotate(glanceAngle * 12° * π/180) —
//     positive = clockwise = head tilts toward the lower-right.
//   • Eye offset:   x = +glanceAngle * 2.0   (canvas +x = right)
//                   y = +glanceAngle * 1.5   (canvas +y = down)
// Negative glanceAngle is reserved for future above-cuttlefish
// targets; v1 only uses [0, +1].

const Duration kMotionGlanceDuration = Duration(milliseconds: 400);

/// Glance curve — `Cubic(0.34, 1.56, 0.64, 1.0)`. Stronger overshoot
/// than the hover curve (1.56 vs 1.1) because the glance is an
/// expressive gesture, not a UI feedback signal. The cuttlefish
/// "leans in" toward the target before settling — that's what makes
/// her feel alive instead of mechanical.
const Curve kMotionGlanceCurve = Cubic(0.34, 1.56, 0.64, 1.0);

/// Calibrated glance angles per target type. Lower magnitude for
/// targets further down the page (the geometric tilt is already
/// "more down" by virtue of position; less head-tilt is needed to
/// communicate the same intent).
class CueGlanceTargets {
  CueGlanceTargets._();

  /// Yesterday-reminder row (per-client row inside the expanded
  /// urgent-amber card). ~10° body tilt.
  static const double yesterdayRow = 0.85;

  /// Today's first brief card — the one that carries `isUpNext: true`
  /// and the amber stripe. Sits further down the page than yesterday
  /// rows, so a milder ~7° tilt reads correctly.
  static const double firstBriefCard = 0.60;

  /// Hover-out / no target hovered — neutral.
  static const double neutral = 0.0;
}

// ── Reduced-motion helper ──────────────────────────────────────────────────
//
// Canonical accessibility gate. Each animated widget reads this at
// build time and degrades gracefully:
//   • Entrance:  snap to final state (opacity 1, translateY 0).
//   • Hover:     static color shifts only — no transform, no curve.
//   • Glance:    glanceAngle stays 0.0; cuttlefish never tilts.
// Reads `MediaQuery.disableAnimations` (set by the OS / browser on
// behalf of users who prefer reduced motion).
bool kReduceMotion(BuildContext context) {
  return MediaQuery.maybeDisableAnimationsOf(context) ?? false;
}
