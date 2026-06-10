// lib/widgets/cue_hold/cue_hold.dart
//
// Phase 4.1.3 — main Cue Hold widget. Watches [cueHoldController] and
// renders the surface appropriate to the current state.
//
// Phase 4.2.x (Task B) — the PILL is the held-work surface, and it now
// OWNS the held-work data lifecycle (the role the retired CueHoldHeldStrip
// used to play). At rest it reads holdItemsController, scoped by
// [heldScopeClientId]:
//   • no held work → "Cue · ready", amber dot OFF
//   • held work    → "Cue · {n} to sign", amber dot ON
// Tapping the pill opens a small CHOOSER anchored under it (OverlayPortal)
// listing the held items; a row taps through to its HeldResume route and
// refreshes on return. The brain (hold_service.dart, holdItemsController)
// is untouched; only the route-observer SUBSCRIBER + the initial-load
// trigger relocated here from the strip (initState / didChangeDependencies
// / didPopNext / dispose below).
//
// State → surface mapping:
//   idle / compact / thinking / listening  →  CueHoldPill
//   whisper                                 →  CueHoldWhisper
//   expanded                                →  CueHoldExpanded  (unreachable
//                                              after Task A; flagged dead code)
//   multi                                   →  CueHoldMulti
//   fullActivity                            →  CuePopup via long-press
//                                              (rendered by the host screen)

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../services/hold_service.dart';
import '../../theme/cue_color_scheme.dart';
import '../../theme/cue_text_styles.dart' show CueChartPalette;
import 'cue_hold_expanded.dart';
import 'cue_hold_multi.dart';
import 'cue_hold_pill.dart';
import 'cue_hold_state.dart';
import 'cue_hold_whisper.dart';

class CueHold extends StatefulWidget {
  /// When true, the layout switches to mobile-friendly width.
  final bool isMobile;

  /// Phase 4.2.x — scopes the held-count label / dot / chooser. Non-null
  /// on a single-client surface (the chart) → that client's items only;
  /// null elsewhere → most-urgent across all clients. Threaded through
  /// _TopBar from AppLayout.
  final String? heldScopeClientId;

  const CueHold({super.key, this.isMobile = false, this.heldScopeClientId});

  @override
  State<CueHold> createState() => _CueHoldState();
}

class _CueHoldState extends State<CueHold> with RouteAware {
  static const Color _amber = Color(0xFFF5C778);
  static const int _cap = 3;

  // Anchors the chooser overlay under the pill.
  final LayerLink _link = LayerLink();
  final OverlayPortalController _chooser = OverlayPortalController();

  // Rebuilds the pill on BOTH controller-state changes (idle/thinking/…)
  // and held-work changes (count/dot/chooser). Created once to avoid
  // resubscribe churn.
  late final Listenable _pillListenable;

  @override
  void initState() {
    super.initState();
    _pillListenable =
        Listenable.merge([cueHoldController, holdItemsController]);
    // Initial derive on mount — MOVED from the retired CueHoldHeldStrip.
    // CueHold is mounted on every AppLayout screen (in _TopBar), so this
    // gives the same first-load coverage the strip had. Post-frame so the
    // controller's notify can't fire mid-build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      holdItemsController.refresh();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Subscribe to the page route so didPopNext fires when the clinician
    // returns after finishing a piece of work — MOVED from the strip. The
    // route observer object lives in hold_service.dart (unchanged); only
    // its subscriber moves here.
    final route = ModalRoute.of(context);
    if (route is PageRoute<dynamic>) {
      holdRouteObserver.subscribe(this, route);
    }
  }

  @override
  void didPopNext() {
    // Returned to this screen → re-derive so resolved work disappears.
    holdItemsController.refresh();
  }

  @override
  void dispose() {
    holdRouteObserver.unsubscribe(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _pillListenable,
      builder: (context, _) {
        final c = cueHoldController;
        final scoped = HoldService.scopeAndRank(
          holdItemsController.items,
          widget.heldScopeClientId,
        );

        // Same precedence as before: while EXPANDED / FULL ACTIVITY are
        // active the pill is a visual anchor showing the previous pill
        // state (or THINKING while a query is in flight). Only FULL
        // ACTIVITY is still reachable (long-press); EXPANDED is dead.
        Widget pill;
        if (c.state == CueHoldState.fullActivity ||
            c.state == CueHoldState.expanded) {
          if (c.state == CueHoldState.expanded && c.thinkingInExpanded) {
            pill = _renderState(context, CueHoldState.thinking, c, scoped);
          } else {
            pill = _renderState(
                context, c.previousState ?? CueHoldState.idle, c, scoped);
          }
        } else {
          pill = _renderState(context, c.state, c, scoped);
        }

        return CompositedTransformTarget(
          link: _link,
          child: OverlayPortal(
            controller: _chooser,
            overlayChildBuilder: (ctx) => _buildChooserOverlay(ctx, scoped),
            child: pill,
          ),
        );
      },
    );
  }

  Widget _renderState(
    BuildContext context,
    CueHoldState state,
    CueHoldController c,
    List<HeldItem> scoped,
  ) {
    switch (state) {
      case CueHoldState.expanded:
        return CueHoldExpanded(controller: c, isMobile: widget.isMobile);
      case CueHoldState.whisper:
        return CueHoldWhisper(
          text: c.whisperText,
          onTap: _onPillTap,
          onLongPress: c.toFullActivity,
          onMicTap: () => _onMicTap(context),
        );
      case CueHoldState.multi:
        return CueHoldMulti(
          primary: c.previousState ?? CueHoldState.idle,
          primaryLabel: c.contextLabel,
          secondary: c.secondaryState ?? CueHoldState.thinking,
          secondaryLabel: c.secondaryLabel,
          onTapPrimary: _onPillTap,
          onTapSecondary: _onPillTap,
          onLongPressAny: c.toFullActivity,
          onMicTapPrimary: () => _onMicTap(context),
        );
      case CueHoldState.idle:
      case CueHoldState.compact:
      case CueHoldState.thinking:
      case CueHoldState.listening:
      default:
        // Phase 4.2.x — the held register REPLACES the retired Study-
        // minimize dot. It lights up when SCOPED held work exists and the
        // pill is a parked pill (idle/compact), suppressed behind the
        // Study popup (fullActivity) and the dead expanded anchor.
        final hasHeld = scoped.isNotEmpty &&
            (state == CueHoldState.idle ||
                state == CueHoldState.compact) &&
            c.state != CueHoldState.expanded &&
            c.state != CueHoldState.fullActivity;
        // The count label only replaces idle's "Cue · ready" resting
        // label; compact's "reading X" / thinking / listening labels stay.
        final label = (hasHeld && state == CueHoldState.idle)
            ? _heldLabel(scoped.length)
            : c.contextLabel;
        return CueHoldPill(
          state: state,
          label: label,
          onTap: _onPillTap,
          onLongPress: c.toFullActivity,
          onMicTap: () => _onMicTap(context),
          held: hasHeld,
        );
    }
  }

  /// Phase 4.2.x — the reserved pill tap. Opens the held-work chooser when
  /// scoped held work exists; does nothing when there's none (no empty
  /// chooser). Long-press (→ Study) is unchanged and lives on the pill.
  void _onPillTap() {
    final scoped = HoldService.scopeAndRank(
      holdItemsController.items,
      widget.heldScopeClientId,
    );
    if (scoped.isEmpty) return;
    _chooser.show();
  }

  // ── Held-work chooser (anchored under the pill) ──────────────────────────

  Widget _buildChooserOverlay(BuildContext context, List<HeldItem> scoped) {
    if (scoped.isEmpty) {
      // Nothing left to resume — close on the next frame (can't mutate the
      // controller mid-build). Keeps the pill from latching an empty panel.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _chooser.isShowing) _chooser.hide();
      });
      return const SizedBox.shrink();
    }
    return Stack(
      children: [
        // Tap-outside barrier.
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: _chooser.hide,
          ),
        ),
        CompositedTransformFollower(
          link: _link,
          showWhenUnlinked: false,
          targetAnchor: Alignment.bottomCenter,
          followerAnchor: Alignment.topCenter,
          offset: const Offset(0, 6),
          child: _chooserCard(context, scoped),
        ),
      ],
    );
  }

  Widget _chooserCard(BuildContext context, List<HeldItem> scoped) {
    final p = CueChartPalette.of(context);
    final cue = CueColorsResolved.of(context);
    final screenW = MediaQuery.of(context).size.width;
    final double maxW =
        widget.isMobile ? (screenW - 24).clamp(0.0, 360.0).toDouble() : 360.0;

    final visible = scoped.take(_cap).toList();
    final overflow = scoped.length - visible.length;

    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxW),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: cue.isDark
                  ? const Color(0x66000000)
                  : const Color(0x26000000),
              offset: const Offset(0, 8),
              blurRadius: 32,
            ),
          ],
        ),
        child: Material(
          color: p.holdSurface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: p.holdBorder, width: 0.5),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < visible.length; i++) ...[
                if (i > 0)
                  Divider(height: 0.5, thickness: 0.5, color: p.holdBorder),
                _chooserRow(context, visible[i], cue),
              ],
              if (overflow > 0) _chooserOverflow(overflow, p, cue),
            ],
          ),
        ),
      ),
    );
  }

  Widget _chooserRow(
      BuildContext context, HeldItem item, CueColorsResolved cue) {
    return InkWell(
      onTap: () => _resumeFromChooser(context, item),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        child: Row(
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: const BoxDecoration(
                color: _amber,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                item.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.dmSans(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w500,
                  color: cue.textPrimary,
                  height: 1.1,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Icon(Icons.chevron_right_rounded,
                size: 16, color: cue.textSecondary),
          ],
        ),
      ),
    );
  }

  Widget _chooserOverflow(int n, CueChartPalette p, CueColorsResolved cue) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: p.holdBorder, width: 0.5)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Text(
        '+$n more',
        style: GoogleFonts.dmSans(
          fontSize: 11.5,
          color: cue.textSecondary,
          height: 1.1,
        ),
      ),
    );
  }

  Future<void> _resumeFromChooser(BuildContext context, HeldItem item) async {
    final route = item.resume.namedRoute;
    if (route == null) return; // V1 sources are all named routes
    _chooser.hide(); // close before navigating so it can't float over the route
    await Navigator.of(context).pushNamed(route);
    // Belt to the route observer's braces: refresh so a finished item
    // drops from the count (didPopNext also fires on return).
    holdItemsController.refresh();
  }

  String _heldLabel(int count) {
    // Every held item produced today is the pendingAiReview ("Ready to
    // sign") kind, so the resting label reads "{n} to sign".
    // SEAM: when draftNote items can surface here too, split the phrasing
    // by kind rather than calling everything "to sign".
    return 'Cue · $count to sign';
  }

  /// Phase 4.1.4 — mic icon is visually present but not wired to real
  /// voice capture yet. Tap shows a SnackBar instead of transitioning to
  /// LISTENING. (Unchanged by Task B.)
  void _onMicTap(BuildContext context) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Voice capture — coming in Phase 4.1.5'),
        duration: Duration(seconds: 2),
      ),
    );
  }
}
