// lib/widgets/goal_achieved_overlay.dart
//
// Three-second full-screen celebration when an SLP marks a goal achieved.
// After dismiss, the chart's goal card flips to its inline "celebrating"
// state (see CelebratingGoalCard). Phase 2.6: tokens centralised.

import 'package:flutter/material.dart';
import '../theme/cue_theme.dart';
import '../theme/cue_tokens.dart';
import '../theme/cue_typography.dart';
import 'cue_cuttlefish.dart';

/// Full-screen overlay shown for ~3s when a goal is marked achieved.
class GoalAchievedOverlay extends StatefulWidget {
  final Map<String, dynamic> goal;
  final Duration             duration;

  const GoalAchievedOverlay({
    super.key,
    required this.goal,
    this.duration = CueDuration.achievedOverlayHold,
  });

  @override
  State<GoalAchievedOverlay> createState() => _GoalAchievedOverlayState();
}

class _GoalAchievedOverlayState extends State<GoalAchievedOverlay> {
  @override
  void initState() {
    super.initState();
    Future.delayed(widget.duration, () {
      if (mounted) Navigator.of(context).maybePop();
    });
  }

  @override
  Widget build(BuildContext context) {
    final goalText = ((widget.goal['goal_text']     as String?) ??
                      (widget.goal['original_text'] as String?) ??
                      'Goal achieved').trim();

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation:       0,
      insetPadding:    EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(CueGap.s24),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CueCuttlefish(
                  size:  CueSize.cuttlefishOverlay,
                  state: CueState.celebrating),
              const SizedBox(height: CueGap.s16),
              Text(
                'Goal achieved',
                style: CueType.displaySmall
                    .copyWith(color: CueColors.amber),
              ),
              const SizedBox(height: CueGap.s8),
              ConstrainedBox(
                // 480 maxWidth tied to the displayMedium reading width —
                // not a token, single-call magic number, kept inline.
                constraints: const BoxConstraints(maxWidth: 480),
                child: Text(
                  goalText,
                  textAlign: TextAlign.center,
                  style: CueType.displayMedium
                      .copyWith(color: Colors.white),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Inline celebrating goal card — shown in the chart's goals list when a
/// goal has status='achieved'. Subdued teal-tinted surface + a smaller
/// celebrating Cue at left.
class CelebratingGoalCard extends StatelessWidget {
  final Map<String, dynamic> goal;
  final String?              achievementSummary;
  final String?              achievedDate;

  const CelebratingGoalCard({
    super.key,
    required this.goal,
    this.achievementSummary,
    this.achievedDate,
  });

  @override
  Widget build(BuildContext context) {
    final isNight = Theme.of(context).brightness == Brightness.dark;
    final tealBase = isNight ? CueColors.tealLight : CueColors.teal;
    final surfaceBg = isNight
        ? CueColors.tealLight
            .withValues(alpha: CueAlpha.celebratingSurfaceNight)
        : CueColors.teal
            .withValues(alpha: CueAlpha.celebratingSurfaceDay);
    final stripBg     = tealBase.withValues(alpha: CueAlpha.celebratingStrip);
    final borderColor = tealBase.withValues(alpha: CueAlpha.celebratingBorder);
    final textColor   =
        isNight ? CueColors.inkDark : CueColors.inkPrimary;

    final goalText = ((goal['goal_text']     as String?) ??
                      (goal['original_text'] as String?) ??
                      '').trim();

    return Container(
      decoration: BoxDecoration(
        color: surfaceBg,
        border: Border.all(color: borderColor, width: CueSize.hairline),
        borderRadius: BorderRadius.circular(CueRadius.s16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top strip: cuttlefish + achievement label
          Container(
            padding: const EdgeInsets.fromLTRB(
                CueGap.s16, CueGap.s14, CueGap.s16, CueGap.s14),
            decoration: BoxDecoration(
              color: stripBg,
              borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(CueRadius.s16)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const CueCuttlefish(
                    size:  CueSize.cuttlefishCelebrating,
                    state: CueState.celebrating),
                const SizedBox(width: CueGap.s12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'GOAL ACHIEVED',
                        style: CueType.labelSmall.copyWith(color: tealBase),
                      ),
                      const SizedBox(height: CueGap.s4),
                      Text(
                        achievementSummary ?? 'Mastered',
                        style: CueType.displaySmall.copyWith(
                            color: textColor),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // Body: goal text + achievement date
          Padding(
            padding: const EdgeInsets.fromLTRB(
                CueGap.s16, CueGap.s14, CueGap.s16, CueGap.s16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (goalText.isNotEmpty)
                  Text(
                    goalText,
                    style: CueType.bodyLarge.copyWith(color: textColor),
                  ),
                if (achievedDate != null) ...[
                  const SizedBox(height: CueGap.s8),
                  Text(
                    'Achieved ${achievedDate!}',
                    style: CueType.bodySmall.copyWith(
                        color: isNight
                            ? CueColors.inkSecondaryDark
                            : CueColors.inkSecondary),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
