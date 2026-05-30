import 'package:flutter/widgets.dart';

// Global recall-pill safe zone.
//
// The "Ask Cue" pill is pinned bottom-right in the app overlay
// (RecallAssistantOverlay → Positioned(right: 24, bottom: 24)). It floats above
// EVERY screen, so any bottom-anchored CTA can end up under it. The pill stays
// put; screens reserve the corner it occupies using the constants + wrapper
// below — one shared source of truth instead of per-screen magic numbers.
//
// The pill is a fixed-size element in the root overlay, so the reservation is a
// constant: no MediaQuery / width branching, consistent with the app's
// LayoutBuilder-based, desktop-first layout.

/// Margin between the pill and the screen's bottom-right corner — mirrors the
/// `Positioned(right: 24, bottom: 24)` in RecallAssistantOverlay.
const double kRecallPillMargin = 24;

/// Approximate rendered footprint of the pill ("Ask Cue" + ⌘K / Ctrl K).
/// Sized for the wider "Ctrl K" label (web / Windows) so it's never too tight.
/// Kept as primitive consts (not a Size) so the reservations below can be
/// const-evaluated.
const double kRecallPillWidth = 160;
const double kRecallPillHeight = 48;
const Size kRecallPillFootprint = Size(kRecallPillWidth, kRecallPillHeight);

/// Breathing room between a CTA and the pill.
const double kRecallPillGap = 16;

/// Horizontal space a bottom-anchored CTA must keep clear of the right edge so
/// it never sits under the pill (footprint width + corner margin + gap).
const double kRecallPillReservedWidth =
    kRecallPillWidth + kRecallPillMargin + kRecallPillGap; // 200

/// Vertical space scrollable content must keep clear of the bottom edge so its
/// last element rests above the pill (footprint height + corner margin + gap).
const double kRecallPillReservedHeight =
    kRecallPillHeight + kRecallPillMargin + kRecallPillGap; // 88

/// The reserved bottom-right corner box (width × height, incl. margin + gap).
const Size kRecallPillSafeArea =
    Size(kRecallPillReservedWidth, kRecallPillReservedHeight);

/// Below this much *remaining* content width, reserving the full pill width on
/// the right would crowd a button row — so we lift (reserve bottom) instead.
/// Sized so a typical multi-button footer never overflows on narrow widths.
const double _kMinContentWidthForRightReserve = 360;

/// Reserves the recall pill's footprint around a bottom-anchored action area so
/// no CTA is shadowed by the pill. Use on pinned footers, right-aligned button
/// rows, and full-width bottom bars.
///
///  • [reserveRight] (default) — clears the pill horizontally by padding the
///    right edge. On narrow widths (where right padding would crowd the row) it
///    automatically falls back to a bottom reservation instead, so CTAs never
///    overflow. The decision is LayoutBuilder-based (NOT MediaQuery), matching
///    the app's layout system.
///  • [reserveBottom] — pads the bottom edge: lifts content above the pill.
///    Right for the tail of scrollable content (also available by adding
///    [kRecallPillReservedHeight] to a scroll view's bottom padding directly).
class RecallPillSafeArea extends StatelessWidget {
  final Widget child;
  final bool reserveRight;
  final bool reserveBottom;

  const RecallPillSafeArea({
    super.key,
    required this.child,
    this.reserveRight = true,
    this.reserveBottom = false,
  });

  @override
  Widget build(BuildContext context) {
    if (!reserveRight) {
      return Padding(
        padding: EdgeInsets.only(
          bottom: reserveBottom ? kRecallPillReservedHeight : 0,
        ),
        child: child,
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final roomy = constraints.maxWidth.isFinite &&
            (constraints.maxWidth - kRecallPillReservedWidth) >=
                _kMinContentWidthForRightReserve;
        return Padding(
          padding: EdgeInsets.only(
            right: roomy ? kRecallPillReservedWidth : 0,
            // When too narrow to inset horizontally, lift instead so the row
            // clears the pill vertically without overflowing.
            bottom: roomy
                ? (reserveBottom ? kRecallPillReservedHeight : 0)
                : kRecallPillReservedHeight,
          ),
          child: child,
        );
      },
    );
  }
}
