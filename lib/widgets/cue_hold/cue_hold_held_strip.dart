// lib/widgets/cue_hold/cue_hold_held_strip.dart
//
// The Hold's held-work strip (Phase 4.1.x). A quiet overlay anchored just
// under the Hold pill that surfaces the clinician's unfinished work. It is a
// SIBLING overlay to _ExpandedChatOverlay — it never sits on the pill and
// never touches the pill's tap/long-press (→ Cue Study) gesture.
//
// Behavior:
//   • Renders ONLY when there are held items (after scoping). Zero items →
//     nothing at all (the absence IS the earned calm; no "all caught up").
//   • Shows up to 3 items + a quiet "+N more" line (an indicator, not a
//     scrollable backlog).
//   • Tapping an item routes to its resume anchor, then refreshes (so the
//     item disappears once the work is finished).
//   • Re-derives on screen entry (initState) AND on return to this screen
//     (RouteAware.didPopNext via holdRouteObserver) — the latter is what
//     keeps a just-finished note from lingering as a stale row.
//   • [scopeClientId] is passed by the host screen (the chart passes its
//     clientId; everywhere else null → most-urgent across all clients).

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../services/hold_service.dart';
import '../../theme/cue_color_scheme.dart';
import '../../theme/cue_text_styles.dart' show CueChartPalette;

class CueHoldHeldStrip extends StatefulWidget {
  final bool isMobile;

  /// Non-null only on a single-client surface (the chart) → strip scopes to
  /// that client. Null elsewhere → most-urgent across all clients.
  final String? scopeClientId;

  const CueHoldHeldStrip({
    super.key,
    required this.isMobile,
    this.scopeClientId,
  });

  @override
  State<CueHoldHeldStrip> createState() => _CueHoldHeldStripState();
}

class _CueHoldHeldStripState extends State<CueHoldHeldStrip> with RouteAware {
  static const Color _amber = Color(0xFFF5C778);
  static const int _cap = 3;

  @override
  void initState() {
    super.initState();
    // First load on screen entry. Post-frame so notify can't fire mid-build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      holdItemsController.refresh();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Subscribe to the enclosing page route so didPopNext fires when the
    // clinician returns to this screen after finishing a piece of work.
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
      animation: holdItemsController,
      builder: (context, _) {
        final ranked = HoldService.scopeAndRank(
          holdItemsController.items,
          widget.scopeClientId,
        );
        if (ranked.isEmpty) return const SizedBox.shrink(); // absent-when-zero

        final topbarHeight = widget.isMobile ? 48.0 : 56.0;
        final card = _card(context, ranked);

        if (widget.isMobile) {
          return Positioned(
            top: topbarHeight + 4,
            left: 12,
            right: 12,
            child: Align(
              alignment: Alignment.topCenter,
              heightFactor: 1.0,
              child: card,
            ),
          );
        }
        return Positioned(
          top: topbarHeight + 4,
          left: 0,
          right: 0,
          child: Align(
            alignment: Alignment.topCenter,
            heightFactor: 1.0,
            child: card,
          ),
        );
      },
    );
  }

  Widget _card(BuildContext context, List<HeldItem> ranked) {
    final p = CueChartPalette.of(context);
    final cue = CueColorsResolved.of(context);

    final visible = ranked.take(_cap).toList();
    final overflow = ranked.length - visible.length;

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: widget.isMobile ? double.infinity : 360,
      ),
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
                _row(context, visible[i], cue),
              ],
              if (overflow > 0) _overflow(overflow, p, cue),
            ],
          ),
        ),
      ),
    );
  }

  Widget _row(BuildContext context, HeldItem item, CueColorsResolved cue) {
    return InkWell(
      onTap: () => _resume(context, item),
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
            Icon(Icons.chevron_right_rounded, size: 16, color: cue.textSecondary),
          ],
        ),
      ),
    );
  }

  Widget _overflow(int n, CueChartPalette p, CueColorsResolved cue) {
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

  Future<void> _resume(BuildContext context, HeldItem item) async {
    final route = item.resume.namedRoute;
    if (route == null) return; // V1 sources are all named routes
    await Navigator.of(context).pushNamed(route);
    // Belt to the RouteObserver's braces: if the resume route popped straight
    // back, refresh now so the item drops if the work is finished.
    holdItemsController.refresh();
  }
}
