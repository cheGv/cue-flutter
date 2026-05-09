// lib/widgets/clients_roster_summary_plaque.dart
//
// Phase 4.0.9-step-B-roster-surface-2 — top-of-page numerics plaque.
// Three cells: total clients · active goals · sessions logged. Inter
// weight 600 plaque numerics at 30px (one register up from row data,
// per spine: this is a page header artifact, not inline prose).

import 'package:flutter/material.dart';

import '../theme/cue_phase4_tokens.dart';
import '../theme/cue_type_v3.dart';

class ClientsRosterSummaryPlaque extends StatelessWidget {
  final int totalClients;
  final int activeGoals;
  final int sessionsLogged;

  const ClientsRosterSummaryPlaque({
    super.key,
    required this.totalClients,
    required this.activeGoals,
    required this.sessionsLogged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        border: Border(
          top:    BorderSide(color: kCueBorder, width: 0.5),
          bottom: BorderSide(color: kCueBorder, width: 0.5),
        ),
      ),
      padding: const EdgeInsets.symmetric(vertical: 18),
      child: Row(
        children: [
          Expanded(
            child: _cell('Total clients', totalClients, kCueInk),
          ),
          const _Divider(),
          Expanded(
            child: _cell('Active goals', activeGoals, kCueOlive),
          ),
          const _Divider(),
          Expanded(
            child: _cell('Sessions logged', sessionsLogged, kCueInk),
          ),
        ],
      ),
    );
  }

  Widget _cell(String label, int value, Color valueColor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$value',
          style: TextStyle(
            fontFamily: 'Inter',
            fontFamilyFallback: const ['system-ui', 'sans-serif'],
            fontSize:       30,
            fontWeight:     FontWeight.w600,
            letterSpacing: -0.6,
            fontFeatures:   const <FontFeature>[FontFeature.tabularFigures()],
            color:          valueColor,
            height:         1.0,
          ),
        ),
        const SizedBox(height: 6),
        // Plaque label — bumped 12.5/400 → 14.5/500 in amend #2 so
        // the labels read unambiguously alongside the 30px tabular
        // numerics above them.
        Text(
          label,
          style: CueTypeV3.rosterDataLabel(color: kCueInkSecondary)
              .copyWith(fontSize: 14.5, fontWeight: FontWeight.w500),
        ),
      ],
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();
  @override
  Widget build(BuildContext context) => Container(
        width: 0.5,
        height: 38,
        color: kCueBorder,
        margin: const EdgeInsets.symmetric(horizontal: 24),
      );
}
