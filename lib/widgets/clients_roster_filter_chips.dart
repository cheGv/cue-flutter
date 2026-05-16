// lib/widgets/clients_roster_filter_chips.dart
//
// /clients tab row: All / Active / Discharged. Tabs with a zero count
// are not rendered. The selected tab carries a pill ground; unselected
// tabs are bare. No sort control — default sort is most-recently-active
// and the sort affordance only returns above 10 clients.

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/cue_text_styles.dart';

class ClientsRosterTabs extends StatelessWidget {
  /// 'all' | 'active' | 'discharged' — or any other value (e.g. 'stale')
  /// when no tab should read as selected.
  final String activeFilter;
  final ValueChanged<String> onFilter;
  final int allCount;
  final int activeCount;
  final int dischargedCount;

  const ClientsRosterTabs({
    super.key,
    required this.activeFilter,
    required this.onFilter,
    required this.allCount,
    required this.activeCount,
    required this.dischargedCount,
  });

  @override
  Widget build(BuildContext context) {
    final palette = CueClientsPalette.of(context);

    final tabs = <Widget>[];
    void add(String key, String label, int count) {
      if (count == 0) return; // hide empty tabs
      if (tabs.isNotEmpty) tabs.add(const SizedBox(width: 8));
      tabs.add(_tab(palette, key, label, count));
    }

    add('all', 'All', allCount);
    add('active', 'Active', activeCount);
    add('discharged', 'Discharged', dischargedCount);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: tabs,
    );
  }

  Widget _tab(
      CueClientsPalette palette, String key, String label, int count) {
    final selected = activeFilter == key;
    final nameColor =
        selected ? palette.textPrimary : palette.textSecondary;
    final countColor =
        selected ? palette.textSecondary : palette.textTertiary;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => onFilter(key),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: selected ? palette.tabSelectedBg : Colors.transparent,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: GoogleFonts.dmSans(
                  fontSize: 14,
                  fontWeight:
                      selected ? FontWeight.w500 : FontWeight.w400,
                  color: nameColor,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '$count',
                style: GoogleFonts.dmSans(
                  fontSize: 14,
                  fontWeight: FontWeight.w400,
                  color: countColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
