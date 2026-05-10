// lib/widgets/cue_glance_target.dart
//
// Phase 4.2 cuttlefish glance target. Wraps a hoverable element
// (yesterday-reminder row, first brief card) and reports a glance
// angle to the parent on enter / exit.
//
// The parent (today_screen.dart's _TodayState) holds a single
// `_glanceAngle` double and tweens it via TweenAnimationBuilder
// around the cuttlefish. When this wrapper's MouseRegion fires
// onEnter, it calls onGlanceChange(target). On exit, it calls
// onGlanceChange(neutral). The parent setState's the glance and
// the tween animates the cuttlefish toward the new value.
//
// This widget is hover-only chrome. It does NOT consume tap events
// or modify hit-testing of the child — clicks pass straight through.
// Reduced-motion: glance is suppressed at the painter level
// (CueCuttlefish reads kReduceMotion and forces glanceAngle = 0);
// this wrapper still calls onGlanceChange but the parent's tween
// resolves to a no-op visually.

import 'package:flutter/material.dart';

class CueGlanceTarget extends StatelessWidget {
  final Widget               child;
  /// Target glance angle when this element is hovered. Positive =
  /// look down-right (per Phase 4.2 lock). See `CueGlanceTargets`
  /// in cue_motion.dart for calibrated values.
  final double               glanceAngle;
  /// Called with [glanceAngle] on hover-enter, with neutral (0.0)
  /// on hover-exit.
  final ValueChanged<double> onGlanceChange;

  const CueGlanceTarget({
    super.key,
    required this.child,
    required this.glanceAngle,
    required this.onGlanceChange,
  });

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      // Don't override the cursor — let the child's own InkWell /
      // GestureDetector control click affordance.
      opaque: false,
      onEnter: (_) => onGlanceChange(glanceAngle),
      onExit:  (_) => onGlanceChange(0.0),
      child: child,
    );
  }
}
