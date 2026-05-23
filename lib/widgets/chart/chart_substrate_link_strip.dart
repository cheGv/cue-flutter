import 'package:flutter/material.dart';

import '../../theme/cue_text_styles.dart';
import 'chart_card.dart';

/// Substrate link card — a single row pointing into the Phase A substrate
/// route. Tap navigates via ChartNavigation.openSubstrate (wired by the screen).
class ChartSubstrateLinkStrip extends StatelessWidget {
  final int substrateCellCount;
  final VoidCallback? onOpenSubstrate;

  const ChartSubstrateLinkStrip({
    super.key,
    required this.substrateCellCount,
    this.onOpenSubstrate,
  });

  @override
  Widget build(BuildContext context) {
    final ty = CueChartType.of(context);
    return CueChartCard(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Row(
        children: [
          Expanded(
            child: Text.rich(TextSpan(children: [
              TextSpan(text: 'Substrate', style: ty.substrateStrong),
              TextSpan(
                text: ' · $substrateCellCount cells across six layers',
                style: ty.substrateLabel,
              ),
            ])),
          ),
          const SizedBox(width: 16),
          CueChartButton(
            small: true,
            label: 'Open substrate →',
            onTap: onOpenSubstrate,
          ),
        ],
      ),
    );
  }
}
