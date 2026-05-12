// lib/widgets/cue_top_band.dart
//
// Phase 5.4 Sprint 2 commit 1 — top-bar chrome widget. The band IS the
// top bar across the app (Path A): navigation chrome, not page content.
// This commit lands it on Client Profile; cross-surface rollout to
// Today, Roster, Assessing, Narrator follows in later Sprint 2 commits.
//
// Responsive layout (LayoutBuilder, never MediaQuery):
//   • <720px (mobile): leading + Spacer + Island + Spacer.
//   • ≥720px (desktop): leading + 12px gap + title (Syne 18 w600) +
//                       Spacer + Island + Spacer + trailing.
//   Title is dropped on mobile; consumer renders hero title below.
//
// Sibling-border pattern: bottom 1px border is a separate child
// Container of the outer Column, not a BoxDecoration on the padding
// Container. Removes the 1.1px overflow that came from including the
// border in the padding-Container's box model on the prior Path A
// attempt.
//
// Island construction goes through islandBuilder(BuildContext, bool
// isDesktop) — the band owns the LayoutBuilder and passes isDesktop
// so the caller can construct the Island with the appropriate Whisper
// maxWidth (typically 360 mobile, 720 desktop). Keeps CueTopBand
// decoupled from any specific Island widget.
//
// horizontalPadding: passed by the caller so the band's leading edge
// (where the back arrow sits) aligns with the page content's leading
// edge. Client Profile passes its computed hPad (24 desktop / 16
// mobile); future surfaces match their own page padding formula.
//
// Watch-item flagged for visual review: Island is centered via two
// equal-flex Spacers, meaning it drifts horizontally based on the
// (leading + title) width. Short names center cleanly; longer names
// push the Island right. Standard nav-bar behavior — if drift feels
// jittery across personas, follow-up commit converts to a Stack with
// Island in Align(Alignment.center) and a Row underneath for chrome.

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/cue_color_scheme.dart';
import '../theme/cue_tokens.dart';

/// Viewport-width threshold at/above which the band switches to
/// desktop layout (title visible, trailing slot rendered).
const double kCueTopBandDesktopBreakpoint = 720.0;

class CueTopBand extends StatelessWidget {
  /// Left-aligned widget. Typically [BackButton] on screens reachable
  /// via Navigator.push; may be null on root surfaces (Today, Roster).
  final Widget? leading;

  /// Title rendered on desktop only (≥720px). Mobile drops it; the
  /// consumer screen renders its own hero title below the band.
  final String? title;

  /// Right-aligned slot. Empty for Sprint 2 commit 1; reserved for
  /// future chrome (notifications, account, command palette).
  /// Rendered only on desktop.
  final Widget? trailing;

  /// Builder that constructs the Island for this band. Receives the
  /// computed [isDesktop] flag so callers can apply the appropriate
  /// Whisper maxWidth (typically 360 mobile, 720 desktop).
  final Widget Function(BuildContext context, bool isDesktop) islandBuilder;

  /// Horizontal padding inside the band's Row. Caller passes its
  /// page content padding so the band's leading edge aligns with
  /// content's leading edge. Default 16 matches mobile page hPad.
  final double horizontalPadding;

  const CueTopBand({
    super.key,
    required this.islandBuilder,
    this.leading,
    this.title,
    this.trailing,
    this.horizontalPadding = 16,
  });

  @override
  Widget build(BuildContext context) {
    final cue = CueColorsResolved.of(context);

    return LayoutBuilder(
      builder: (ctx, constraints) {
        final isDesktop =
            constraints.maxWidth >= kCueTopBandDesktopBreakpoint;

        return Column(
          mainAxisSize:       MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              // No color set — preserves parent bgCanvas via the
              // workspace Column's stretch. The bottom hairline
              // (sibling, below) is what makes the band read as a bar.
              padding: EdgeInsets.symmetric(
                horizontal: horizontalPadding,
                vertical:   CueGap.s10,
              ),
              child: Row(
                children: [
                  ?leading,
                  if (isDesktop && title != null) ...[
                    const SizedBox(width: CueGap.s12),
                    Text(
                      title!,
                      style: GoogleFonts.syne(
                        fontSize:   18,
                        fontWeight: FontWeight.w600,
                        color:      cue.textPrimary,
                      ),
                    ),
                  ],
                  const Spacer(),
                  islandBuilder(ctx, isDesktop),
                  const Spacer(),
                  if (isDesktop && trailing != null) trailing!,
                ],
              ),
            ),
            // Sibling-border: bottom 1px border as a separate child
            // Container, not part of the padding Container's box
            // model. Eliminates the 1.1px overflow from Path A.
            Container(height: 1, color: cue.border),
          ],
        );
      },
    );
  }
}
