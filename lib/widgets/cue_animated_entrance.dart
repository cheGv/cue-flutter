// lib/widgets/cue_animated_entrance.dart
//
// Phase 4.2 page-entrance wrapper. Wraps a child widget with a
// fade-up + translate-up animation that fires once on first build,
// after a configurable delay. Used to choreograph the entrance of
// Today and Roster page sections.
//
// Rules (locked in Phase 4.2):
//   • Fires ONCE on the wrapper's first build — not on parent
//     setState. The wrapper sits inside `if (!loading) ...content`
//     so its first build coincides with data being present, which is
//     exactly when the choreography should run.
//   • Delay is the stagger offset (0ms, 80ms, 160ms, ...).
//   • Reduced-motion: when MediaQuery.disableAnimations is true the
//     wrapper renders the child immediately at the final state —
//     no fade, no translate.
//
// Caller responsibility: pass a stable `delay` per element. Don't
// reuse one wrapper across rebuilds to retrigger — that's not what
// the choreography is for.

import 'package:flutter/material.dart';

import '../animation/cue_motion.dart';

class CueAnimatedEntrance extends StatefulWidget {
  final Widget   child;
  final Duration delay;

  const CueAnimatedEntrance({
    super.key,
    required this.child,
    this.delay = Duration.zero,
  });

  @override
  State<CueAnimatedEntrance> createState() => _CueAnimatedEntranceState();
}

class _CueAnimatedEntranceState extends State<CueAnimatedEntrance>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double>   _curved;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync:    this,
      duration: kMotionPageEntranceDuration,
    );
    _curved = CurvedAnimation(parent: _ctrl, curve: kMotionPageEntranceCurve);
    // Fire once after the stagger delay. We do not wrap this in any
    // condition that could re-fire — initState runs once per State.
    Future<void>.delayed(widget.delay, () {
      if (mounted) _ctrl.forward();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Reduced-motion: skip the choreography entirely. Render the
    // child as if it had already settled.
    if (kReduceMotion(context)) return widget.child;

    return AnimatedBuilder(
      animation: _curved,
      builder: (_, child) {
        final t = _curved.value;
        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(0, kMotionPageEntranceTranslateY * (1 - t)),
            child: child,
          ),
        );
      },
      child: widget.child,
    );
  }
}
