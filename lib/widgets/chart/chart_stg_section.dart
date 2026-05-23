import 'package:flutter/material.dart';

import '../../theme/cue_color_scheme.dart';
import 'chart_card.dart';

/// STG section card — card-head ("Short-term goals · N active" + "New STG")
/// over a bg-stg-section body that nests the focused STG card and the compact
/// STG rows beneath it. Composition wrapper: the screen supplies the focus +
/// compact widgets.
class ChartStgSection extends StatelessWidget {
  final int activeCount;
  final Widget focus;
  final Widget? compact;
  final VoidCallback? onNewStg;

  const ChartStgSection({
    super.key,
    required this.activeCount,
    required this.focus,
    this.compact,
    this.onNewStg,
  });

  @override
  Widget build(BuildContext context) {
    final t = CueChartTokens.of(context);
    return CueChartCard(
      // Whole-card ground = bg-stg-section; the card-head paints its own
      // bg-card-head over the top, so the body region reads as stg-section.
      background: t.bgStgSection,
      head: CueChartCardHead(
        label: 'Short-term goals',
        count: '· $activeCount active',
        actions: [
          CueChartButton(
            small: true,
            icon: Icons.add,
            label: 'New STG',
            onTap: onNewStg,
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          focus,
          ?compact,
        ],
      ),
    );
  }
}
