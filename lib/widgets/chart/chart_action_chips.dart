import 'package:flutter/material.dart';

import '../../models/client_chart_state.dart';
import 'chart_card.dart';
import 'chart_format.dart';

/// Action chips card — four real buttons. The primary (dark in light / cream
/// in dark) is resolved from chart state; the rest are default/ghost. Taps
/// route through [onChipTap] to the screen's ChartNavigation handlers.
class ChartActionChips extends StatelessWidget {
  final ClientChartState state;
  final bool sessionToday;
  final String clientName;

  final void Function(String chipId)? onChipTap;

  const ChartActionChips({
    super.key,
    required this.state,
    required this.sessionToday,
    required this.clientName,
    this.onChipTap,
  });

  @override
  Widget build(BuildContext context) {
    final primary = resolvePrimaryAction(state, sessionToday: sessionToday);
    return CueChartCard(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          CueChartButton(
            style: CueChartButtonStyle.primary,
            icon: Icons.add,
            label: 'Capture session',
            onTap: () => onChipTap?.call('capture_session'),
          ),
          CueChartButton(
            icon: _primaryIcon(primary),
            label: primaryActionLabel(primary, clientName),
            onTap: () => onChipTap?.call('primary'),
          ),
          CueChartButton(
            icon: Icons.menu_book_outlined,
            label: 'Review last session',
            enabled: state.totalSessionCount > 0,
            onTap: () => onChipTap?.call('review_last_session'),
          ),
          CueChartButton(
            icon: Icons.add,
            label: 'New STG',
            enabled: state.ltgCount > 0,
            onTap: () => onChipTap?.call('new_stg'),
          ),
          CueChartButton(
            style: CueChartButtonStyle.ghost,
            icon: Icons.folder_open_outlined,
            label: 'Substrate',
            onTap: () => onChipTap?.call('open_substrate'),
          ),
        ],
      ),
    );
  }

  IconData _primaryIcon(ChartPrimaryAction a) => switch (a) {
        ChartPrimaryAction.authorLtg => Icons.create_outlined,
        ChartPrimaryAction.documentLastSession => Icons.article_outlined,
        ChartPrimaryAction.planTodaySession => Icons.event_outlined,
        ChartPrimaryAction.planNextSession => Icons.event_outlined,
      };
}
