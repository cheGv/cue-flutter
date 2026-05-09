// lib/widgets/clients_roster_filter_chips.dart
//
// Phase 4.0.9-step-B-roster-surface-2 — filter chip strip + sort
// dropdown. Active chip carries kCueOliveSurface ground; inactive chips
// are bare. Counts trail in Inter (not mono) per the Revision 2026-05-10
// numerics rule.

import 'package:flutter/material.dart';

import '../theme/cue_phase4_tokens.dart';
import '../theme/cue_type_v3.dart';

class ClientsRosterFilterChips extends StatelessWidget {
  final String activeFilter; // 'all' | 'active' | 'discharged'
  final ValueChanged<String> onFilter;
  final int allCount;
  final int activeCount;
  final int dischargedCount;
  final String sortBy; // 'recent' (only option in v1)
  final ValueChanged<String> onSort;

  const ClientsRosterFilterChips({
    super.key,
    required this.activeFilter,
    required this.onFilter,
    required this.allCount,
    required this.activeCount,
    required this.dischargedCount,
    required this.sortBy,
    required this.onSort,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _chip('All', allCount, activeFilter == 'all',
            () => onFilter('all')),
        const SizedBox(width: 8),
        _chip('Active', activeCount, activeFilter == 'active',
            () => onFilter('active')),
        const SizedBox(width: 8),
        _chip('Discharged', dischargedCount,
            activeFilter == 'discharged', () => onFilter('discharged')),
        const Spacer(),
        _sortControl(),
      ],
    );
  }

  Widget _chip(
      String label, int count, bool active, VoidCallback onTap) {
    final bg = active ? kCueOliveSurface : Colors.transparent;
    final textColor = active ? kCueOliveDeep : kCueInkSecondary;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Chip label — bumped 13 → 14.5 in amend #2 so the
            // primary filter control carries weight. Active w600 /
            // inactive w500 split preserved (active is eye-anchor).
            Text(
              label,
              style: TextStyle(
                fontFamily: 'Inter',
                fontFamilyFallback: const ['system-ui', 'sans-serif'],
                fontSize: 14.5,
                fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                letterSpacing: -0.0725, // -0.005em × 14.5
                color: textColor,
              ),
            ),
            const SizedBox(width: 6),
            // Chip count — bumped 12/400 → 13/500 in amend #2.
            // Count is a data tag; weight matches its relationship
            // to the label.
            Text(
              '$count',
              style: const TextStyle(
                fontFamily: 'Inter',
                fontFamilyFallback: ['system-ui', 'sans-serif'],
                fontSize: 13,
                fontWeight: FontWeight.w500,
                letterSpacing: -0.065,
                color: kCueInkTertiary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sortControl() {
    // Sort dropdown — only "Recent" available in v1; alphabetical and
    // others ship later. The dropdown affordance is real (not a stub)
    // so SLPs see the future option without us shipping the logic.
    // Sort control — bumped 13/varied → 14.5/500/InkSecondary in
    // amend #2 to match the filter-chip register. Both the "Sort:"
    // prefix and the dropdown value sit at the same scale so the
    // pair reads as one control.
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Sort: ',
          style: CueTypeV3.body(color: kCueInkSecondary).copyWith(
            fontSize:   14.5,
            fontWeight: FontWeight.w500,
          ),
        ),
        DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            value: sortBy,
            icon: const Icon(
              Icons.keyboard_arrow_down_rounded,
              size: 18,
              color: kCueInkSecondary,
            ),
            isDense: true,
            style: const TextStyle(
              fontFamily: 'Inter',
              fontFamilyFallback: ['system-ui', 'sans-serif'],
              fontSize: 14.5,
              fontWeight: FontWeight.w500,
              letterSpacing: -0.0725, // -0.005em × 14.5
              color: kCueInkSecondary,
            ),
            items: const [
              DropdownMenuItem(value: 'recent', child: Text('Recent')),
            ],
            onChanged: (v) {
              if (v != null) onSort(v);
            },
          ),
        ),
      ],
    );
  }
}
