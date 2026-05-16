// lib/widgets/cue_hold/cue_hold_pill.dart
//
// Phase 4.1.3 — the standard pill surface for the Cue Hold. Renders the
// IDLE / COMPACT / THINKING / LISTENING states. WHISPER and EXPANDED
// have their own dedicated widgets (cue_hold_whisper.dart,
// cue_hold_expanded.dart).
//
// All four states share the same outer shape (22px circle on the left
// with 14px cuttlefish + text + trailing mic icon). The differences:
//
//   IDLE       — label "Cue · ready"; cuttlefish breathes (4s opacity
//                oscillation, easeInOut)
//   COMPACT    — label from controller (context-aware), e.g.
//                "Cue · reading Rishi"; cuttlefish slow-rotates 15deg
//                back and forth on a 6s cycle
//   THINKING   — label "Cue · thinking…"; three dots fade in/out
//                staggered 200ms apart, looping
//   LISTENING  — label "Cue · listening…"; amber ring pulse around the
//                cuttlefish circle (22→36px diameter, opacity 0.4→0.0,
//                1.2s cycle); mic icon swaps to Icons.stop_rounded
//
// Sizing: standard pill is ~38px tall, width content-driven (min 180px).
// The CueHold wrapper handles the scale-down to 75% when in MULTI-STATE.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../theme/cue_text_styles.dart' show CueChartPalette;
import 'cue_hold_state.dart';

class CueHoldPill extends StatefulWidget {
  /// The state to render. Must be one of the pill-shape states
  /// (idle / compact / thinking / listening).
  final CueHoldState state;

  /// Label text — supplied by the controller. Pre-formatted ("Cue · …").
  final String label;

  /// Single-tap fires expand (inline chat).
  final VoidCallback? onTap;

  /// Long-press (500ms) fires the full activity popup.
  final VoidCallback? onLongPress;

  /// Mic icon tap. In IDLE / COMPACT / THINKING it starts LISTENING;
  /// in LISTENING it stops. Caller (CueHold widget) routes the tap.
  final VoidCallback? onMicTap;

  const CueHoldPill({
    super.key,
    required this.state,
    required this.label,
    this.onTap,
    this.onLongPress,
    this.onMicTap,
  });

  @override
  State<CueHoldPill> createState() => _CueHoldPillState();
}

class _CueHoldPillState extends State<CueHoldPill>
    with TickerProviderStateMixin {
  late final AnimationController _breath; // IDLE
  late final AnimationController _rotate; // COMPACT
  late final AnimationController _dots; // THINKING
  late final AnimationController _ring; // LISTENING

  static const Color _amber = Color(0xFFF5C778);

  @override
  void initState() {
    super.initState();
    _breath = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat(reverse: true);
    _rotate = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 6),
    )..repeat(reverse: true);
    _dots = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
    _ring = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _breath.dispose();
    _rotate.dispose();
    _dots.dispose();
    _ring.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = CueChartPalette.of(context);
    final isListening = widget.state == CueHoldState.listening;
    final isThinking = widget.state == CueHoldState.thinking;

    return Semantics(
      label: widget.label,
      button: true,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: widget.onTap,
          onLongPress: widget.onLongPress,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.fromLTRB(10, 8, 16, 8),
            decoration: BoxDecoration(
              color: p.holdSurface,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: p.holdBorder, width: 0.5),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                _mark(),
                const SizedBox(width: 8),
                _label(),
                if (isThinking) ...[
                  const SizedBox(width: 8),
                  _ThinkingDots(controller: _dots, color: _amber),
                ],
                const SizedBox(width: 10),
                _divider(p.holdBorder),
                const SizedBox(width: 10),
                _micIcon(isListening),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _mark() {
    final svg = SvgPicture.asset(
      'assets/brand/cue_mark.svg',
      width: 14,
      height: 14,
      colorFilter: const ColorFilter.mode(_amber, BlendMode.srcIn),
    );

    Widget inner;
    switch (widget.state) {
      case CueHoldState.idle:
        inner = AnimatedBuilder(
          animation: _breath,
          builder: (_, child) {
            final t = (_breath.value * math.pi).abs();
            final opacity = 0.85 + 0.15 * math.sin(t);
            return Opacity(opacity: opacity, child: child);
          },
          child: svg,
        );
        break;
      case CueHoldState.compact:
        inner = AnimatedBuilder(
          animation: _rotate,
          builder: (_, child) {
            // Sine eased back and forth across ±15deg.
            final theta = math.sin(_rotate.value * math.pi * 2) *
                (15 * math.pi / 180);
            return Transform.rotate(angle: theta, child: child);
          },
          child: svg,
        );
        break;
      case CueHoldState.listening:
        inner = svg;
        break;
      case CueHoldState.thinking:
      default:
        inner = svg;
    }

    final circle = Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        color: _amber.withValues(alpha: 0.12),
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: inner,
    );

    if (widget.state == CueHoldState.listening) {
      return SizedBox(
        width: 36,
        height: 36,
        child: Stack(
          alignment: Alignment.center,
          children: [
            AnimatedBuilder(
              animation: _ring,
              builder: (_, _) {
                final t = _ring.value; // 0 → 1
                final diameter = 22.0 + (36.0 - 22.0) * t;
                final alpha = (0.4 * (1 - t)).clamp(0.0, 1.0);
                return Container(
                  width: diameter,
                  height: diameter,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: _amber.withValues(alpha: alpha),
                      width: 1.5,
                    ),
                  ),
                );
              },
            ),
            circle,
          ],
        ),
      );
    }

    return circle;
  }

  Widget _label() {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      transitionBuilder: (child, anim) =>
          FadeTransition(opacity: anim, child: child),
      child: Text(
        widget.label,
        key: ValueKey(widget.label),
        style: GoogleFonts.dmSans(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: _amber,
          height: 1.0,
        ),
      ),
    );
  }

  Widget _divider(Color color) =>
      Container(width: 0.5, height: 12, color: color);

  Widget _micIcon(bool isListening) {
    return GestureDetector(
      onTap: widget.onMicTap,
      behavior: HitTestBehavior.opaque,
      child: Icon(
        isListening ? Icons.stop_rounded : Icons.mic_none_rounded,
        size: 13,
        color: _amber,
      ),
    );
  }
}

class _ThinkingDots extends StatelessWidget {
  final AnimationController controller;
  final Color color;
  const _ThinkingDots({required this.controller, required this.color});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 22,
      height: 8,
      child: AnimatedBuilder(
        animation: controller,
        builder: (_, _) {
          return Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: List<Widget>.generate(3, (i) {
              final phase = (controller.value - i * 0.2) % 1.0;
              final opacity =
                  (math.sin(phase * math.pi).clamp(0.0, 1.0)).toDouble();
              return Opacity(
                opacity: 0.25 + 0.75 * opacity,
                child: Container(
                  width: 4,
                  height: 4,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                ),
              );
            }),
          );
        },
      ),
    );
  }
}
