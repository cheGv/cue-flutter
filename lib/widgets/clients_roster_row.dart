// lib/widgets/clients_roster_row.dart
//
// Phase 4.0.9-step-B-roster-surface-2 — single row of the Clients Roster.
// LOAD-BEARING: this row is the "numbers as game changers" surface. The
// data tokens (sessions, active goals) carry Inter weight 700 tabular
// numerics per the Revision 2026-05-10 spine narrowing.
//
// Hover state requires a StatefulWidget — Flutter web's MouseRegion +
// setState is the canonical pattern.

import 'package:flutter/material.dart';

import '../services/clients_roster_service.dart';
import '../theme/cue_phase4_tokens.dart';
import '../theme/cue_type_v3.dart';

class ClientsRosterRow extends StatefulWidget {
  final ClientRosterEntry entry;
  final VoidCallback onTap;

  const ClientsRosterRow({
    super.key,
    required this.entry,
    required this.onTap,
  });

  @override
  State<ClientsRosterRow> createState() => _ClientsRosterRowState();
}

class _ClientsRosterRowState extends State<ClientsRosterRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final e = widget.entry;
    final stripeColor = e.isDischarged ? kCueInkTertiary : kCueOlive;
    // Hover amplify: stripe widens 3 → 4px and grows 48 → 56px tall.
    final stripeW = _hover ? 4.0 : 3.0;
    final stripeH = _hover ? 56.0 : 48.0;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit:  (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          decoration: BoxDecoration(
            color: _hover ? kCuePaper : kCueSurfaceWhite,
            border: const Border(
              top: BorderSide(color: kCueBorder, width: 0.5),
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
          // Min-height bumped 78 → 88 in the 4.0.9-step-B founder-
          // verification amend — gives the bumped focus-strip and
          // data-label sizes room to breathe.
          constraints: const BoxConstraints(minHeight: 88),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Stripe column — 4px wide reserved, the actual stripe
              // floats centered inside.
              SizedBox(
                width: 4,
                height: stripeH,
                child: Center(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 120),
                    curve: Curves.easeOut,
                    width: stripeW,
                    height: stripeH,
                    decoration: BoxDecoration(
                      color: stripeColor,
                      borderRadius: BorderRadius.circular(1.5),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 18),
              Expanded(child: _mainColumn(e)),
              const SizedBox(width: 18),
              SizedBox(width: 130, child: _recencyStack(e)),
              const SizedBox(width: 18),
              SizedBox(width: 90, child: Center(child: _statePill(e))),
            ],
          ),
        ),
      ),
    );
  }

  // ── Main column: name + focus strip · data tokens · (just-enrolled) ───
  Widget _mainColumn(ClientRosterEntry e) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Name + focus strip share a baseline.
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Flexible(
              child: Text(
                e.displayName,
                overflow: TextOverflow.ellipsis,
                style: CueTypeV3.rosterClientName(),
              ),
            ),
            if (e.focusStrip.isNotEmpty) ...[
              const SizedBox(width: 12),
              Flexible(
                child: Text(
                  e.focusStrip,
                  overflow: TextOverflow.ellipsis,
                  // Focus strip — bumped 12.5 → 14 in the 4.0.9-step-B
                  // founder-verification amend (Chrome real-render). Stays
                  // Inter weight 500 / kCueInkSecondary.
                  style: const TextStyle(
                    fontFamily: 'Inter',
                    fontFamilyFallback: ['system-ui', 'sans-serif'],
                    fontSize:    14,
                    fontWeight:  FontWeight.w500,
                    letterSpacing: -0.07,
                    color:       kCueInkSecondary,
                  ),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 6),
        _dataTokens(e),
        if (e.isNew) ...[
          const SizedBox(height: 6),
          Text(
            'Just enrolled',
            style: CueTypeV3.editorialItalic(color: kCueOlive)
                .copyWith(fontSize: 12.5, height: 1.0),
          ),
        ],
      ],
    );
  }

  // Sessions count + active goals count, baseline-aligned with dot
  // divider. Zero counts render in tertiary so empty rows recess.
  Widget _dataTokens(ClientRosterEntry e) {
    final sessionsZero = e.sessionsCount == 0;
    final goalsZero    = e.activeGoalsCount == 0;
    final sessionsNumColor =
        sessionsZero ? kCueInkTertiary : kCueInk;
    final goalsNumColor =
        goalsZero ? kCueInkTertiary : kCueOlive;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(
          '${e.sessionsCount}',
          style: CueTypeV3.rosterDataNum(color: sessionsNumColor),
        ),
        const SizedBox(width: 6),
        Text(
          e.sessionsCount == 1 ? 'session' : 'sessions',
          style: CueTypeV3.rosterDataLabel(),
        ),
        const SizedBox(width: 12),
        const Text(
          '·',
          style: TextStyle(color: kCueInkTertiary, fontSize: 13),
        ),
        const SizedBox(width: 12),
        Text(
          '${e.activeGoalsCount}',
          style: CueTypeV3.rosterDataNum(color: goalsNumColor),
        ),
        const SizedBox(width: 6),
        Text(
          'active goals',
          style: CueTypeV3.rosterDataLabel(),
        ),
      ],
    );
  }

  // ── Recency stack: relative line + context line, right-aligned ──────
  Widget _recencyStack(ClientRosterEntry e) {
    // "Today" — single amber moment per Rule 2 dual-accent system on
    // this surface. All other recency lines stay kCueInk.
    final relativeColor = e.hadSessionToday ? kCueAmber : kCueInk;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          e.recencyRelative,
          textAlign: TextAlign.right,
          style: CueTypeV3.rosterRecencyRelative(color: relativeColor),
        ),
        const SizedBox(height: 2),
        Text(
          e.recencyContext,
          textAlign: TextAlign.right,
          style: CueTypeV3.rosterRecencyContext(),
        ),
      ],
    );
  }

  // ── Pill: Inter sentence-case (library-browse register) ─────────────
  Widget _statePill(ClientRosterEntry e) {
    final discharged = e.isDischarged;
    final bg = discharged ? kCueGraySurface : kCueOliveSurface;
    final textColor = discharged ? kCueInkSecondary : kCueOliveDeep;
    final label = discharged ? 'Discharged' : 'Active';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontFamily: 'Inter',
          fontFamilyFallback: const ['system-ui', 'sans-serif'],
          fontSize: 11,
          fontWeight: FontWeight.w500,
          letterSpacing: -0.055,
          color: textColor,
        ),
      ),
    );
  }
}
