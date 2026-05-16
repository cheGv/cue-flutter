// lib/widgets/cue_hold/cue_hold_multi.dart
//
// Phase 4.1.3 — MULTI-STATE. Two pills side-by-side at 75% size,
// representing parallel Cue tasks (e.g. THINKING while LISTENING).
//
// Phase 4.1.3 ships only the rendering surface — real parallel-task
// triggers land in Phase 1.5. The dev shortcut ⌘⇧M kicks the
// controller into a sample multi state.
//
// Tapping either pill expands that pill's state inline (state 6
// EXPANDED) — caller wires that via [onTapPrimary] / [onTapSecondary].
// The other pill stays at compact size and continues its work.

import 'package:flutter/material.dart';

import 'cue_hold_pill.dart';
import 'cue_hold_state.dart';

class CueHoldMulti extends StatelessWidget {
  final CueHoldState primary;
  final String primaryLabel;
  final CueHoldState secondary;
  final String secondaryLabel;
  final VoidCallback? onTapPrimary;
  final VoidCallback? onTapSecondary;
  final VoidCallback? onLongPressAny;
  final VoidCallback? onMicTapPrimary;
  final VoidCallback? onMicTapSecondary;

  const CueHoldMulti({
    super.key,
    required this.primary,
    required this.primaryLabel,
    required this.secondary,
    required this.secondaryLabel,
    this.onTapPrimary,
    this.onTapSecondary,
    this.onLongPressAny,
    this.onMicTapPrimary,
    this.onMicTapSecondary,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Transform.scale(
          scale: 0.75,
          alignment: Alignment.centerRight,
          child: CueHoldPill(
            state: primary,
            label: primaryLabel,
            onTap: onTapPrimary,
            onLongPress: onLongPressAny,
            onMicTap: onMicTapPrimary,
          ),
        ),
        const SizedBox(width: 6),
        Transform.scale(
          scale: 0.75,
          alignment: Alignment.centerLeft,
          child: CueHoldPill(
            state: secondary,
            label: secondaryLabel,
            onTap: onTapSecondary,
            onLongPress: onLongPressAny,
            onMicTap: onMicTapSecondary,
          ),
        ),
      ],
    );
  }
}
