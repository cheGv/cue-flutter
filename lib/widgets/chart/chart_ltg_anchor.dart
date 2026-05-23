import 'package:flutter/material.dart';

import '../../theme/cue_color_scheme.dart';
import '../../theme/cue_text_styles.dart';
import 'chart_card.dart';
import 'chart_format.dart';

/// LTG card — card-head ("Long-term goal · LTG N" + Edit LTG ghost) over a
/// body with the goal text (16/1.6) and a meta row (12-month info badge,
/// "Month X of Y", "Authored …"). Renders an empty-state card when no LTG.
class ChartLtgAnchor extends StatelessWidget {
  final String? ltgText;
  final int? ltgSeq;
  final int? monthsTotal;
  final int? currentMonth;
  final int substrateCellCount;
  final DateTime? authoredDate;
  final VoidCallback? onEditLtg;

  const ChartLtgAnchor({
    super.key,
    required this.ltgText,
    required this.substrateCellCount,
    this.ltgSeq,
    this.monthsTotal,
    this.currentMonth,
    this.authoredDate,
    this.onEditLtg,
  });

  @override
  Widget build(BuildContext context) {
    final t = CueChartTokens.of(context);
    final ty = CueChartType.of(context);
    final text = ltgText?.trim();

    if (text == null || text.isEmpty) {
      return CueChartCard(
        head: const CueChartCardHead(label: 'Long-term goal'),
        child: Text(
          'No long-term goal authored yet — $substrateCellCount substrate '
          'cells ready beneath.',
          style: ty.ltgBody.copyWith(color: t.textMuted),
        ),
      );
    }

    return CueChartCard(
      head: CueChartCardHead(
        label: 'Long-term goal',
        count: '· LTG ${ltgSeq ?? 1}',
        actions: [
          CueChartButton(
            style: CueChartButtonStyle.ghost,
            small: true,
            label: 'Edit LTG',
            onTap: onEditLtg,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 820),
            child: Text(text, style: ty.ltgBody),
          ),
          const SizedBox(height: 14),
          _meta(t, ty),
        ],
      ),
    );
  }

  Widget _meta(CueChartTokens t, CueChartType ty) {
    final children = <Widget>[];
    if (monthsTotal != null) {
      children.add(Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: t.infoBadgeBg,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text('$monthsTotal months', style: ty.infoBadge),
      ));
    }
    if (monthsTotal != null && currentMonth != null) {
      children.add(Text('Month $currentMonth of $monthsTotal', style: ty.ltgMeta));
    }
    if (authoredDate != null) {
      children
        ..add(Text('·', style: ty.ltgMeta.copyWith(color: t.textFaint)))
        ..add(Text('Authored ${monthDay(authoredDate!)}', style: ty.ltgMeta));
    }
    return Wrap(
      spacing: 14,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: children,
    );
  }
}
