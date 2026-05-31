import 'package:flutter/material.dart';

import '../../theme/cue_color_scheme.dart';
import '../../theme/cue_text_styles.dart';

/// Which lifecycle phase a goal is in — drives which menu items show.
enum GoalLifecyclePhase { active, completed, closed }

/// Overflow menu of soft lifecycle controls for a goal (STG or LTG). Two
/// orthogonal axes:
///   • STATUS — Mark achieved / Mark discontinued (when active), or Reactivate
///     (when completed/closed). Keeps the goal visible.
///   • ARCHIVE — hides the goal (reversibly). Always offered, last, tinted as
///     the destructive-but-undoable action.
///
/// Pure presentation: every action is a callback the caller wires to the
/// repository + an Undo affordance. No Supabase here.
class GoalLifecycleMenu extends StatelessWidget {
  final GoalLifecyclePhase phase;

  /// Noun for labels/tooltips, e.g. 'short-term goal' or 'long-term goal'.
  final String goalKind;

  final VoidCallback? onMarkAchieved;
  final VoidCallback? onMarkDiscontinued;
  final VoidCallback? onReactivate;
  final VoidCallback? onArchive;

  const GoalLifecycleMenu({
    super.key,
    required this.phase,
    this.goalKind = 'goal',
    this.onMarkAchieved,
    this.onMarkDiscontinued,
    this.onReactivate,
    this.onArchive,
  });

  // Destructive-but-reversible tint (matches the shared archive dialog).
  static const Color _archiveTint = Color(0xFFC25450);

  @override
  Widget build(BuildContext context) {
    final t = CueChartTokens.of(context);
    final ty = CueChartType.of(context);

    PopupMenuItem<_Lc> item(_Lc value, IconData icon, String label,
        {Color? color}) {
      final c = color ?? t.textBody;
      return PopupMenuItem<_Lc>(
        value: value,
        height: 42,
        child: Row(
          children: [
            Icon(icon, size: 16, color: c),
            const SizedBox(width: 10),
            Text(label, style: ty.button(c)),
          ],
        ),
      );
    }

    return PopupMenuButton<_Lc>(
      tooltip: 'Goal options',
      position: PopupMenuPosition.under,
      color: t.bgCard,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: t.borderCard),
      ),
      icon: Icon(Icons.more_horiz, size: 18, color: t.textTertiary),
      splashRadius: 18,
      itemBuilder: (context) => [
        if (phase == GoalLifecyclePhase.active) ...[
          item(_Lc.achieved, Icons.check_circle_outline, 'Mark achieved'),
          item(_Lc.discontinued, Icons.do_not_disturb_alt_outlined,
              'Mark discontinued'),
        ] else
          item(_Lc.reactivate, Icons.refresh, 'Reactivate'),
        const PopupMenuDivider(),
        item(_Lc.archive, Icons.archive_outlined, 'Archive $goalKind',
            color: _archiveTint),
      ],
      onSelected: (v) {
        switch (v) {
          case _Lc.achieved:
            onMarkAchieved?.call();
          case _Lc.discontinued:
            onMarkDiscontinued?.call();
          case _Lc.reactivate:
            onReactivate?.call();
          case _Lc.archive:
            onArchive?.call();
        }
      },
    );
  }
}

enum _Lc { achieved, discontinued, reactivate, archive }
