import 'package:flutter/material.dart';

import '../../models/short_term_goal.dart';
import '../../theme/cue_color_scheme.dart';
import '../../theme/cue_text_styles.dart';
import 'chart_card.dart';
import 'goal_lifecycle_menu.dart';

/// A quiet section of STGs that have left the active set but remain visible for
/// clinical history — either "Completed" (achieved/mastered) or "Closed"
/// (discontinued). Each row carries the lifecycle menu so the clinician can
/// Reactivate or Archive. Renders nothing when [stgs] is empty.
///
/// These are NOT focusable and NOT in the active list; they exist purely to
/// preserve the record. Archived goals never appear here (they're hidden
/// entirely).
class ChartLifecycleGoals extends StatelessWidget {
  final String title; // 'Completed' | 'Closed'
  final GoalLifecyclePhase phase; // completed | closed
  final List<ShortTermGoal> stgs;
  final Map<String, String> stgNumbers;
  final void Function(ShortTermGoal stg) onReactivate;
  final void Function(ShortTermGoal stg) onArchive;

  const ChartLifecycleGoals({
    super.key,
    required this.title,
    required this.phase,
    required this.stgs,
    required this.stgNumbers,
    required this.onReactivate,
    required this.onArchive,
  });

  @override
  Widget build(BuildContext context) {
    if (stgs.isEmpty) return const SizedBox.shrink();
    final n = stgs.length;
    return CueChartCard(
      padding: const EdgeInsets.fromLTRB(20, 12, 12, 12),
      head: CueChartCardHead(label: title, count: '· $n'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < stgs.length; i++)
            _Row(
              stg: stgs[i],
              number: stgNumbers[stgs[i].id] ??
                  'STG ${stgs[i].sequenceNum ?? '—'}',
              phase: phase,
              showTopBorder: i > 0,
              onReactivate: () => onReactivate(stgs[i]),
              onArchive: () => onArchive(stgs[i]),
            ),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  final ShortTermGoal stg;
  final String number;
  final GoalLifecyclePhase phase;
  final bool showTopBorder;
  final VoidCallback onReactivate;
  final VoidCallback onArchive;

  const _Row({
    required this.stg,
    required this.number,
    required this.phase,
    required this.showTopBorder,
    required this.onReactivate,
    required this.onArchive,
  });

  @override
  Widget build(BuildContext context) {
    final t = CueChartTokens.of(context);
    final ty = CueChartType.of(context);
    final body = stg.specific.trim().isNotEmpty
        ? stg.specific.trim()
        : (stg.targetBehavior ?? stg.measurable);
    final tint =
        phase == GoalLifecyclePhase.completed ? t.accent : t.textMuted;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: showTopBorder
          ? BoxDecoration(
              border: Border(top: BorderSide(color: t.borderDivider)),
            )
          : null,
      child: Row(
        children: [
          SizedBox(width: 56, child: Text(number, style: ty.compactNum)),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              body,
              style: ty.compactBody.copyWith(color: t.textSecondary),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: t.bgInset,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              stg.status.displayLabel().toUpperCase(),
              style: ty.compactNum.copyWith(color: tint, letterSpacing: 0.5),
            ),
          ),
          const SizedBox(width: 4),
          GoalLifecycleMenu(
            phase: phase,
            goalKind: 'short-term goal',
            onReactivate: onReactivate,
            onArchive: onArchive,
          ),
        ],
      ),
    );
  }
}
