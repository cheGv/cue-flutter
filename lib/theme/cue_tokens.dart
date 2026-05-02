// lib/theme/cue_tokens.dart
//
// Phase 2.6 design tokens — every spacing, radius, duration, size, alpha,
// and chrome-colour decision used by the chart screen and Cue Study screen
// lives here. Adding/changing a value globally means editing one constant.
//
// Naming convention:
//   CueGap.s16          — "16-pixel gap" (literal-suffix scale)
//   CueRadius.s16       — "16-pixel border radius"
//   CueSize.cuttlefish* — pixel size, named by placement role
//   CueAlpha.*          — opacity used in mixed contexts; name describes
//                         what it modulates, not the magnitude
//   CueDuration.*       — animation durations, named by behaviour
//   CueBubbleColors.*   — chrome colours that don't live in CueColors
//
// Visual register (white day / near-black night, amber as Cue's voice,
// geometric sans, no parchment) is preserved exactly — every value here
// equals the literal it replaces.

import 'package:flutter/material.dart';

// ── Spacing scale ────────────────────────────────────────────────────────────

/// Spacing scale. Suffix = pixel value.
///
/// Use the literal-suffix scale (s4, s8, s16…) when the value is a layout
/// number with no design meaning beyond its size. Use the semantic helpers
/// at the bottom (`bubbleUserLeft`, `welcomeTopGap`) when the value
/// expresses a design decision that may shift independently.
class CueGap {
  CueGap._();

  static const double s2  = 2;
  static const double s4  = 4;
  static const double s5  = 5;
  static const double s6  = 6;
  static const double s7  = 7;
  static const double s8  = 8;
  static const double s9  = 9;
  static const double s10 = 10;
  static const double s11 = 11;
  static const double s12 = 12;
  static const double s13 = 13;
  static const double s14 = 14;
  static const double s16 = 16;
  static const double s18 = 18;
  static const double s20 = 20;
  static const double s22 = 22;
  static const double s24 = 24;
  static const double s28 = 28;
  static const double s32 = 32;
  static const double s64 = 64;
  static const double s80 = 80;

  // ── Semantic spacing decisions ─────────────────────────────────────────
  /// Left pad on a user (right-aligned) bubble — pushes off the screen edge.
  static const double bubbleUserLeftPad      = s64;
  /// Right margin on an assistant (left-aligned) bubble — keeps it
  /// narrower than the user bubble so Cue's voice never crowds the input.
  static const double bubbleAssistantRightPad = s32;
  /// Distance from screen top to the welcome-state Signature Cue.
  static const double welcomeTopGap          = s80;
  /// Vertical breathing room above the achieved-goal cluster.
  static const double goalsSectionTop        = s32;
  /// Gap between the achieved-goal cluster and the active-goal cluster.
  static const double achievedToActiveGap    = s16;
  /// Vertical gap between an eyebrow label (lowercase muted micro-label,
  /// e.g. "today's session") and the card it labels. Used on Today.
  static const double eyebrowToCard          = s12;
  /// Vertical gap from the bottom of a content card cluster up to the
  /// next section's eyebrow. Tighter than greetingToEyebrow because the
  /// card already has its own bottom padding contributing visual breathing.
  static const double cardToEyebrow          = s24;
  /// Gap between two stacked Today session brief cards.
  static const double sessionCardGap         = s12;
  /// Gap between the three This-Week pulse cards.
  static const double weekPulseGap           = s10;
  /// Vertical gap between the greeting block and the first eyebrow on Today.
  static const double greetingToEyebrow      = s32;
  /// Greeting cuttlefish ↔ greeting text gap on Today.
  static const double greetingFishToText     = s22;
  /// Phase 3.2 — gap between the all-clients search input and the first row.
  static const double searchBarToList        = s16;
  /// Phase 3.2.2 — gap between the recency dot and the client name on
  /// all-clients row cards. The subtitle is left-padded by
  /// `recencyDot + dotToName` so it aligns under the name, not the dot.
  static const double dotToName              = s12;
  /// Phase 3.3.7b — vertical gap between the three structured-conditions
  /// blocks ("what's queued" → "suitable instruments" → "at your
  /// discretion") inside an LTG card.
  static const double conditionBlockGap      = s20;
  /// Phase 3.3.7b — vertical gap between adjacent activities inside the
  /// "what's queued" list.
  static const double activityListItemGap    = s8;
}

// ── Border-radius scale ──────────────────────────────────────────────────────

/// Border-radius values, suffix = pixel.
class CueRadius {
  CueRadius._();

  /// Skeleton placeholder pill ends.
  static const double s3  = 3;
  /// The asymmetric "inward" corner on chat bubbles.
  static const double s4  = 4;
  static const double s8  = 8;
  /// Card / outer assistant bubble / dialog.
  static const double s16 = 16;
  /// Pill button.
  static const double s20 = 20;
  /// Suggestion chip / soft InkWell.
  static const double s22 = 22;
  /// Input bar capsule.
  static const double s26 = 26;
  /// Floating action bar capsule.
  static const double s28 = 28;
}

// ── Animation durations ──────────────────────────────────────────────────────

class CueDuration {
  CueDuration._();

  /// ListView snap-to-bottom after a new message lands.
  static const Duration scrollSnap = Duration(milliseconds: 220);
  /// "Cue is thinking…" breathing fade.
  static const Duration typingFade = Duration(milliseconds: 800);
  /// Goal-achieved full-screen overlay — auto-dismiss after this hold.
  static const Duration achievedOverlayHold = Duration(seconds: 3);
}

// ── Pixel sizes ──────────────────────────────────────────────────────────────

/// Pixel sizes for the cuttlefish, send-button, and hairlines.
///
/// The cuttlefish sizes are named by role rather than scale — every place
/// the cuttlefish appears has a documented size and they're rarely
/// interchangeable.
class CueSize {
  CueSize._();

  // ── Cuttlefish placement registry ──────────────────────────────────────
  /// Inline inside the "Think with Cue" pill on a brief.
  static const double cuttlefishThinkPill = 13;
  /// Inline inside the action-bar "Ask Cue" pill on the chart.
  static const double cuttlefishActionPill = 14;
  /// Eyebrow row above a brief / noticed moment / typing indicator.
  static const double cuttlefishEyebrow = 18;
  /// Sidebar brand mark and Cue Study AppBar title.
  static const double cuttlefishAppBar = 22;
  /// Phase 3.2.1 — companion-presence size used on Clients' "needs you"
  /// eyebrow row. Deliberately one step larger than [cuttlefishEyebrow]
  /// (18) to signal the *noticing* role on this screen, but smaller than
  /// the bubble size (28) so it doesn't dominate the 12px eyebrow text.
  static const double cuttlefishAttention = 20;
  /// Next to each assistant bubble in Cue Study chat.
  static const double cuttlefishBubble = 28;
  /// Inline on a celebrating goal card.
  static const double cuttlefishCelebrating = 52;
  /// Centred on the empty-thread welcome state.
  static const double cuttlefishWelcome = 96;
  /// Centred on the goal-achieved full-screen overlay.
  static const double cuttlefishOverlay = 200;

  // ── Cuttlefish vertical slot heights (so animation has breathing room) ──
  static const double cuttlefishEyebrowSlot = 22; // for size-18
  static const double cuttlefishAppBarSlot    = 26; // for size-22
  static const double cuttlefishBubbleSlot    = 32; // for size-28
  static const double cuttlefishAttentionSlot = 24; // for size-20

  // ── Send button (Cue Study input) ──────────────────────────────────────
  static const double sendButton = 36;
  static const double sendGlyph  = 16;

  // ── Generic ────────────────────────────────────────────────────────────
  /// Hairline border / divider thickness.
  static const double hairline = 0.5;
  /// Default loading spinner stroke.
  static const double spinnerStroke = 1.5;
  /// Phase 3.2.2 — recency dot at the left edge of all-clients row cards.
  /// Always renders (faintest tone for never-seen clients).
  static const double recencyDot = 8;
}

// ── Alpha (opacity) values ───────────────────────────────────────────────────

/// Repeated alpha values, named by what they modulate.
class CueAlpha {
  CueAlpha._();

  /// Faint amber border on assistant bubbles — the visual signature of
  /// Cue speaking. Subtle in day, glow-y in night against the dark surface.
  static const double assistantBubbleBorder = 0.15;
  /// Input-bar amber border in night mode (more pronounced than day).
  static const double inputBorderNight = 0.20;
  /// Soft amber tint on the noticed-moment primary action button.
  static const double softTint = 0.10;
  /// Inactive secondary text on the soft button.
  static const double softInactiveText = 0.60;
  /// Send button when input is empty — amber dimmed to "not yet".
  static const double sendButtonDim = 0.40;
  /// Typing indicator italic-text breathing target.
  static const double typingIndicator = 0.60;
  /// Celebrating goal card surface tint, day mode.
  static const double celebratingSurfaceDay = 0.06;
  /// Celebrating goal card surface tint, night mode.
  static const double celebratingSurfaceNight = 0.08;
  /// Top strip background tint on a celebrating goal card.
  static const double celebratingStrip = 0.08;
  /// Border on a celebrating goal card.
  static const double celebratingBorder = 0.25;
  /// Sidebar logo bottom hairline.
  static const double sidebarHairline = 0.08;
  /// Active sidebar nav-item background tint.
  static const double sidebarActiveBg = 0.10;
  /// Inactive sidebar nav-item text colour, day mode.
  static const double sidebarInactiveDay = 0.35;
  /// Inactive sidebar nav-item text colour, night mode.
  static const double sidebarInactiveNight = 0.25;

  // ── Today screen (Phase 3.1) muted-text alphas ──────────────────────────
  // The Today register reads ink at four distinct mutings — eyebrow,
  // subtitle, body, and amber subline. Named so the muting can shift in
  // one place if the register is re-tuned.

  /// Eyebrow label ("today's session", "this week"), and pulse-card label.
  static const double eyebrowText = 0.5;
  /// Subtitle line on a session brief card ("Age 4 · CAS").
  static const double subtitleText = 0.55;
  /// "Last session: …" line — slightly less muted than subtitle.
  static const double bodyText = 0.78;
  /// Greeting subline ("3 sessions today — Ranadir at 09:30") — amber on
  /// amber background, dialled back so the headline reads first.
  static const double amberSubline = 0.85;
  /// Middot separator between two amber text-links on the action row.
  static const double middotDivider = 0.25;
  /// Subtle row-hover background tint on the Phase 3.2 all-clients list.
  /// Phase 3.2.2 repurposed this constant as the hover-shadow alpha — same
  /// value, same role (subtle ink lift), now applied to a BoxShadow rather
  /// than the row surface.
  static const double hoverFill = 0.04;
  /// Phase 3.2.2 — hover-state border darkening on all-clients row cards.
  /// Applied to [CueColors.inkPrimary] in place of [CueColors.divider]
  /// (which is already a low-alpha black under the hood). The 0.5px
  /// stroke width does not change.
  static const double hoverBorder = 0.12;

  // ── Phase 3.2.2 — recency-dot tier alphas (all-clients row cards) ──────
  // Drives the left-edge dot color based on days since last session. The
  // tier sits independent of any judgement copy — the dot is presence,
  // not progress.
  /// Today (or any time today): amber at full strength.
  static const double recencyToday   = 1.0;
  /// 1–7 days ago: amber dimmed.
  static const double recencyWeek    = 0.5;
  /// 8–30 days: ink at quarter strength (color also flips amber → ink).
  static const double recencyMonth   = 0.25;
  /// >30 days OR never: ink at faintest. Always renders, even for
  /// never-seen clients.
  static const double recencyDormant = 0.10;
}

// ── Bubble + send-button chrome colours ──────────────────────────────────────

/// Colours used by chat chrome that aren't in CueColors. Kept here because
/// they're tied to specific bubble decisions (user-bubble shade, send-glyph
/// contrast) rather than the global palette.
class CueBubbleColors {
  CueBubbleColors._();

  /// User's voice in day mode — slightly off pure black-blue.
  static const Color userDay = Color(0xFF0F1A2D);
  /// User's voice in night mode — matches surfaceDark so the user bubble
  /// recedes and Cue's voice gets the visual emphasis.
  static const Color userNight = Color(0xFF0F1F35);
  /// Send-button glyph — near-black on amber for high contrast +
  /// "ready to fire" feeling.
  static const Color sendGlyph = Color(0xFF1A0800);
}
