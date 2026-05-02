// lib/widgets/cue_cuttlefish.dart
//
// Cue's brand cuttlefish — animated character widget. Phase 2 implements all
// 12 states. Single AnimationController drives a master 0..1 cycle (5s
// period) and each state derives its own sub-animations via modular phase
// math. This is functionally equivalent to per-animation controllers but
// keeps memory and ticker overhead minimal — important when small (14–22px)
// instances render in 5+ places on every screen.
//
// All drawing is hand-painted via CustomPainter from Path commands ported
// from the design SVG. No third-party rendering dep.

import 'dart:math' as math;
import 'package:flutter/material.dart';

// ── Public API ───────────────────────────────────────────────────────────────

enum CueState {
  idle,
  thinking,
  colorShift,
  signature,
  waving,
  celebrating,
  swimming,
  confused,
  excited,
  resting,
  steadyNod,
  softWave,
}

enum SignatureVariant { she, he, neutral }

class CueCuttlefish extends StatefulWidget {
  final double size;
  final CueState state;
  final SignatureVariant variant;

  const CueCuttlefish({
    super.key,
    this.size    = 32,
    this.state   = CueState.idle,
    this.variant = SignatureVariant.she,
  });

  @override
  State<CueCuttlefish> createState() => _CueCuttlefishState();
}

// ── Palette ──────────────────────────────────────────────────────────────────

class _Palette {
  static const body         = Color(0xFFF59E0B);
  static const strokesFins  = Color(0xFFD97706);
  static const eyes         = Color(0xFF1A1308);
  static const spectacles   = Color(0xFF7A4F0A);
  static const toolTeal     = Color(0xFF1F8870);
  static const toolBlue     = Color(0xFF3B82F6);
  static const toolGrey     = Color(0xFF5A5A5A);
  static const toolGold     = Color(0xFFFCD34D);
  static const blush        = Color(0xFFE89B9B);
  static const water        = Color(0xFF9CCBD8);
  static const beardShadow  = Color(0xFFB8770A);
  // ColorShift mid-tone (used in 4-stop body fill cycle)
  static const bodyDark     = Color(0xFFD97706);
}

// ── State ────────────────────────────────────────────────────────────────────

class _CueCuttlefishState extends State<CueCuttlefish>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync:    this,
      duration: const Duration(milliseconds: 5000),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width:  widget.size,
      height: widget.size,
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (_, _) => CustomPaint(
          painter: _CuttlefishPainter(
            t:       _ctrl.value,
            state:   widget.state,
            variant: widget.variant,
          ),
        ),
      ),
    );
  }
}

// ── Painter ──────────────────────────────────────────────────────────────────

class _CuttlefishPainter extends CustomPainter {
  final double           t;
  final CueState         state;
  final SignatureVariant variant;

  // Most states share this viewBox; signature widens it for tools + halo.
  static const _vbX = -30.0, _vbY = -28.0, _vbW = 60.0, _vbH = 70.0;

  _CuttlefishPainter({
    required this.t,
    required this.state,
    required this.variant,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final useSignatureVB = state == CueState.signature;
    final vbX = useSignatureVB ? -60.0 : _vbX;
    final vbY = useSignatureVB ? -45.0 : _vbY;
    final vbW = useSignatureVB ? 120.0 : _vbW;
    final vbH = useSignatureVB ?  95.0 : _vbH;

    final scale = math.min(size.width / vbW, size.height / vbH);
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    canvas.scale(scale);
    canvas.translate(-(vbX + vbW / 2), -(vbY + vbH / 2));

    switch (state) {
      case CueState.idle:        _paintIdle(canvas);        break;
      case CueState.thinking:    _paintThinking(canvas);    break;
      case CueState.waving:      _paintWaving(canvas);      break;
      case CueState.signature:   _paintSignature(canvas);   break;
      case CueState.colorShift:  _paintColorShift(canvas);  break;
      case CueState.celebrating: _paintCelebrating(canvas); break;
      case CueState.swimming:    _paintSwimming(canvas);    break;
      case CueState.confused:    _paintConfused(canvas);    break;
      case CueState.excited:     _paintExcited(canvas);     break;
      case CueState.resting:     _paintResting(canvas);     break;
      case CueState.steadyNod:   _paintSteadyNod(canvas);   break;
      case CueState.softWave:    _paintSoftWave(canvas);    break;
    }

    canvas.restore();
  }

  // ── Master cycle helpers ───────────────────────────────────────────────────
  // All sub-cycles derive from the controller's 5s master t (0..1).

  /// 0..1 saw-tooth at the requested period (seconds). t is the master 0..1.
  double _phase(double seconds) => (t * 5.0 / seconds) % 1.0;

  /// Smooth 0..1..0 ease (0 at 0, 1 at 0.5, 0 at 1).
  double _bell(double phase) => (1 - math.cos(phase * 2 * math.pi)) / 2;

  // ─────────────────────────────────────────────────────────────────────────
  //                                IDLE
  // Body translateY 0..-2 over 3.5s. Eyes blink at 94-97% of 5s. Fins morph
  // closed/open at 1.5s (right offset 0.2s). Tentacles drift ±0.8° at 3s.
  // ─────────────────────────────────────────────────────────────────────────
  void _paintIdle(Canvas canvas) {
    final bodyY     = -2.0 * _bell(_phase(3.5));
    final finLOpen  = _phase(1.5) > 0.5;
    final finROpen  = (((t * 5.0 - 0.2) / 1.5) % 1.0) > 0.5;
    final blinking  = t > 0.94 && t < 0.97;
    final driftDeg  = math.sin(_phase(3.0) * 2 * math.pi) * 0.8;

    canvas.save();
    canvas.translate(0, bodyY);
    _drawTentacles(canvas, driftDeg: driftDeg);
    _drawBody(canvas);
    _drawSideFins(canvas, leftOpen: finLOpen, rightOpen: finROpen);
    _drawEyes(canvas, _EyeMode.wOpen, blinking: blinking);
    canvas.restore();
  }

  // ─────────────────────────────────────────────────────────────────────────
  //                                THINKING
  // Body rotates -5°..-9° at 2.4s. Three thought dots above head appear with
  // staggered delays over a 2.8s sub-cycle. One arm reaches up.
  // ─────────────────────────────────────────────────────────────────────────
  void _paintThinking(Canvas canvas) {
    final rotDeg = -5.0 - 2.0 * _bell(_phase(2.4));

    canvas.save();
    canvas.rotate(rotDeg * math.pi / 180);
    _drawTentacles(canvas, driftDeg: 0);
    _drawBody(canvas);
    _drawSideFins(canvas, leftOpen: false, rightOpen: false);
    _drawEyes(canvas, _EyeMode.wOpen, blinking: false);

    // Reaching arm
    canvas.drawPath(
      Path()
        ..moveTo(5, 14)
        ..quadraticBezierTo(12, 0, 18, -22),
      Paint()
        ..color = _Palette.strokesFins
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..strokeCap = StrokeCap.round,
    );
    canvas.restore();

    // Thought dots in screen-frame, rising over 2.8s with delays.
    const dotCycle = 2.8;
    final tDot = (t * 5.0) % dotCycle;
    final dots = [
      _ThoughtDot(cx: 14, cy: -26, r: 1.0, delay: 0.0),
      _ThoughtDot(cx: 18, cy: -30, r: 1.4, delay: 0.5),
      _ThoughtDot(cx: 22, cy: -34, r: 2.0, delay: 1.0),
    ];
    for (final d in dots) {
      var phase = (tDot - d.delay) / dotCycle;
      if (phase < 0) phase += 1;
      double a;
      if (phase < 0.4) {
        a = phase / 0.4;
      } else if (phase < 0.6) {
        a = 1.0;
      } else {
        a = 1.0 - (phase - 0.6) / 0.4;
      }
      a = a.clamp(0.0, 1.0);
      canvas.drawCircle(
        Offset(d.cx, d.cy),
        d.r,
        Paint()..color = _Palette.strokesFins.withValues(alpha: a),
      );
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  //                                COLORSHIFT
  // Body fill cycles F59E0B → FCD34D → D97706 → F59E0B over 4s. Other
  // elements unchanged from idle pose.
  // ─────────────────────────────────────────────────────────────────────────
  void _paintColorShift(Canvas canvas) {
    final p = _phase(4.0); // 0..1 over 4s
    Color bodyColor;
    if (p < 1 / 3) {
      bodyColor = Color.lerp(_Palette.body,    _Palette.toolGold, p * 3)!;
    } else if (p < 2 / 3) {
      bodyColor = Color.lerp(_Palette.toolGold, _Palette.bodyDark, (p - 1/3) * 3)!;
    } else {
      bodyColor = Color.lerp(_Palette.bodyDark, _Palette.body,    (p - 2/3) * 3)!;
    }

    _drawTentacles(canvas, driftDeg: 0);
    _drawBody(canvas, fillOverride: bodyColor);
    _drawSideFins(canvas, leftOpen: false, rightOpen: false);
    _drawEyes(canvas, _EyeMode.wOpen, blinking: false);
  }

  // ─────────────────────────────────────────────────────────────────────────
  //                                SIGNATURE
  // Body bounces + rotates on 2.4s. Amber halo pulses behind. Four arms hold
  // tools. Round spectacles drawn over W-eyes. Variant overlays.
  // ─────────────────────────────────────────────────────────────────────────
  void _paintSignature(Canvas canvas) {
    final p     = _bell(_phase(2.4));
    final bodyY = -1.5 * p;
    final rot   =  1.0 * p;
    final glowA = 0.5 + 0.35 * p;
    final glowS = 1.0 + 0.06 * p;

    canvas.save();
    canvas.scale(glowS);
    canvas.drawCircle(
      const Offset(0, -3),
      26,
      Paint()..color = _Palette.body.withValues(alpha: glowA * 0.18),
    );
    canvas.restore();

    canvas.save();
    canvas.translate(0, bodyY);
    canvas.rotate(rot * math.pi / 180);

    _drawTentacles(canvas, driftDeg: 0);
    _drawBody(canvas);
    _drawSideFins(canvas, leftOpen: false, rightOpen: false);
    _drawSignatureTools(canvas);
    _drawEyes(canvas, _eyeModeForVariant(variant), blinking: false);
    _drawSpectacles(canvas);

    if (variant == SignatureVariant.she) _drawBlush(canvas);
    if (variant == SignatureVariant.he)  _drawBeardAndBrows(canvas);
    _drawSmile(canvas, variant);

    canvas.restore();
  }

  // ─────────────────────────────────────────────────────────────────────────
  //                                WAVING
  // Body translateY 0..-1.5 at 1.6s. Top-right arm rotates -15°..+8° at
  // 0.8s. Eyes are happy curves.
  // ─────────────────────────────────────────────────────────────────────────
  void _paintWaving(Canvas canvas) {
    final bodyY   = -1.5 * _bell(_phase(1.6));
    final waveT   = _bell(_phase(0.8));
    final armDeg  = -15.0 + waveT * 23.0;

    canvas.save();
    canvas.translate(0, bodyY);
    _drawTentacles(canvas, driftDeg: 0);
    _drawBody(canvas);
    _drawSideFins(canvas, leftOpen: false, rightOpen: false);
    _drawEyes(canvas, _EyeMode.happy, blinking: false);

    canvas.save();
    canvas.translate(5, 14);
    canvas.rotate(armDeg * math.pi / 180);
    canvas.drawPath(
      Path()
        ..moveTo(0, 0)
        ..quadraticBezierTo(2, -8, 8, -16),
      _strokesPaint(width: 1.6),
    );
    canvas.restore();

    canvas.restore();
  }

  // ─────────────────────────────────────────────────────────────────────────
  //                                CELEBRATING
  // Body translateY+rotate over 1s with 25% peak. Both top arms raised.
  // Sparkles at 4 positions, opacity 0/1 cycle. Star paths pop in/out.
  // ─────────────────────────────────────────────────────────────────────────
  void _paintCelebrating(Canvas canvas) {
    // 1s sub-cycle bounce (peak at 25%)
    final p1     = _phase(1.0);
    final bounce = (p1 < 0.25)
        ? p1 / 0.25
        : 1 - (p1 - 0.25) / 0.75;
    final bodyY  = -3.0 * bounce;
    final rotDeg = (p1 < 0.25 ? 0.0 : (p1 < 0.6 ? -3.0 : 3.0));

    canvas.save();
    canvas.translate(0, bodyY);
    canvas.rotate(rotDeg * math.pi / 180);
    _drawTentacles(canvas, driftDeg: 0);
    _drawBody(canvas);
    _drawSideFins(canvas, leftOpen: true, rightOpen: true);
    _drawEyes(canvas, _EyeMode.happy, blinking: false);

    // Both top arms raised (left + right)
    final arm = _strokesPaint(width: 1.6);
    canvas.drawPath(
      Path()..moveTo(-5, 14)..quadraticBezierTo(-9, -2, -14, -18),
      arm,
    );
    canvas.drawPath(
      Path()..moveTo(5, 14)..quadraticBezierTo(9, -2, 14, -18),
      arm,
    );
    canvas.restore();

    // Sparkles at 4 positions, fading over 1.5s with offsets
    const sparkles = [
      _Sparkle(x: -18, y: -22, delay: 0.0),
      _Sparkle(x:  18, y: -22, delay: 0.3),
      _Sparkle(x: -22, y:   2, delay: 0.6),
      _Sparkle(x:  22, y:   2, delay: 0.9),
    ];
    final sCycle = 1.5;
    final tS = (t * 5.0) % sCycle;
    for (final s in sparkles) {
      var ph = (tS - s.delay) / sCycle;
      if (ph < 0) ph += 1;
      final a = math.sin(ph * math.pi).clamp(0.0, 1.0);
      _drawSparkle(canvas, Offset(s.x, s.y), 2.4, a);
    }

    // Pop-in star (top center)
    final starP = _phase(2.0);
    final starA = (starP < 0.5) ? starP * 2 : (1 - starP) * 2;
    _drawStar(canvas, const Offset(0, -28), 3.0,
        Paint()..color = _Palette.toolGold.withValues(alpha: starA.clamp(0.0, 1.0)));
  }

  // ─────────────────────────────────────────────────────────────────────────
  //                                SWIMMING
  // Body translateX(-2..2) + rotate(-2°..2°) at 3s. Tentacles streamlined
  // back. Three rising bubble circles + ripple lines below.
  // ─────────────────────────────────────────────────────────────────────────
  void _paintSwimming(Canvas canvas) {
    final p   = _phase(3.0);
    final dx  = math.sin(p * 2 * math.pi) * 2.0;
    final rot = math.sin(p * 2 * math.pi) * 2.0;

    canvas.save();
    canvas.translate(dx, 0);
    canvas.rotate(rot * math.pi / 180);
    _drawTentacles(canvas, driftDeg: 0, streamlined: true);
    _drawBody(canvas);
    _drawSideFins(canvas, leftOpen: false, rightOpen: false);
    _drawEyes(canvas, _EyeMode.wOpen, blinking: false);
    canvas.restore();

    // Three rising bubbles with different periods + offsets
    final bubbles = [
      _Bubble(x: -10, period: 2.4, r: 1.6, delay: 0.0),
      _Bubble(x:   8, period: 2.8, r: 2.0, delay: 0.7),
      _Bubble(x:  -2, period: 2.2, r: 1.2, delay: 1.4),
    ];
    for (final b in bubbles) {
      var ph = ((t * 5.0 - b.delay) / b.period) % 1.0;
      if (ph < 0) ph += 1;
      final y = 28 - ph * 56; // rise from y=28 to y=-28
      final a = math.sin(ph * math.pi).clamp(0.0, 1.0);
      canvas.drawCircle(
        Offset(b.x, y),
        b.r,
        Paint()
          ..color = _Palette.water.withValues(alpha: a * 0.55)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.6,
      );
    }

    // Two ripple lines below the body
    final rippleA = 0.18 + 0.14 * _bell(_phase(3.0));
    final ripplePaint = Paint()
      ..color = _Palette.water.withValues(alpha: rippleA)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5;
    canvas.save();
    final rs = 0.85 + 0.3 * _bell(_phase(3.0));
    canvas.translate(0, 22);
    canvas.scale(rs, 1);
    canvas.drawLine(const Offset(-12, 0), const Offset(12, 0), ripplePaint);
    canvas.translate(0, 4);
    canvas.scale(0.8, 1);
    canvas.drawLine(const Offset(-10, 0), const Offset(10, 0), ripplePaint);
    canvas.restore();
  }

  // ─────────────────────────────────────────────────────────────────────────
  //                                CONFUSED
  // Body permanent rotate(-22°), translateY(-1px) bob at 2.4s. Arm scratches
  // chin. Right eye W slightly squished. Mouth = small zigzag. "?" floats.
  // ─────────────────────────────────────────────────────────────────────────
  void _paintConfused(Canvas canvas) {
    final bodyY = -1.0 * _bell(_phase(2.4));

    canvas.save();
    canvas.translate(0, bodyY);
    canvas.rotate(-22.0 * math.pi / 180);

    _drawTentacles(canvas, driftDeg: 0);
    _drawBody(canvas);
    _drawSideFins(canvas, leftOpen: false, rightOpen: true);

    // Asymmetric W eyes: right one squished
    final eyePaint = _eyesPaint();
    canvas.drawPath(
      Path()
        ..moveTo(-6, -8)
        ..quadraticBezierTo(-5, -7, -4, -8)
        ..quadraticBezierTo(-3, -7, -2, -8),
      eyePaint,
    );
    canvas.drawPath(
      Path()
        ..moveTo(2, -8)
        ..quadraticBezierTo(3.5, -7.5, 4.5, -8)
        ..quadraticBezierTo(5.5, -7.5, 6, -8),
      eyePaint,
    );

    // Zigzag mouth
    canvas.drawPath(
      Path()
        ..moveTo(-3, -2)
        ..lineTo(-1, -3)
        ..lineTo( 1, -2)
        ..lineTo( 3, -3),
      eyePaint,
    );

    // Chin-scratching arm (bobs ±4°)
    final scratchDeg = math.sin(_phase(1.4) * 2 * math.pi) * 4.0;
    canvas.save();
    canvas.translate(2, 14);
    canvas.rotate(scratchDeg * math.pi / 180);
    canvas.drawPath(
      Path()
        ..moveTo(0, 0)
        ..quadraticBezierTo(-2, -6, 2, -12),
      _strokesPaint(width: 1.6),
    );
    canvas.restore();

    canvas.restore();

    // Floating "?" beside head (in screen frame, not rotated)
    final qScale = 0.95 + 0.15 * _bell(_phase(1.8));
    final qAlpha = 0.6 + 0.4  * _bell(_phase(1.8));
    final tp = TextPainter(
      text: TextSpan(
        text: '?',
        style: TextStyle(
          color: _Palette.strokesFins.withValues(alpha: qAlpha),
          fontSize: 12 * qScale,
          fontWeight: FontWeight.w700,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(14 - tp.width / 2, -22 - tp.height / 2));
  }

  // ─────────────────────────────────────────────────────────────────────────
  //                                EXCITED
  // Body translates randomly + rotates ±3° in 5-keyframe cycle at 0.4s —
  // fast vibration. Four side arms wave widely. Nine sparkles. Big smiles.
  // ─────────────────────────────────────────────────────────────────────────
  void _paintExcited(Canvas canvas) {
    // 5-keyframe vibration over 0.4s
    final p   = _phase(0.4);
    final f   = (p * 5).floor();
    const dxs = [-1.5, 1.5, -1.0, 1.0,  0.0];
    const dys = [-1.0, 1.0,  1.5, -1.5, 0.0];
    const rds = [-3.0, 3.0, -2.0, 2.0,  0.0];
    final dx  = dxs[f];
    final dy  = dys[f];
    final rd  = rds[f];

    canvas.save();
    canvas.translate(dx, dy);
    canvas.rotate(rd * math.pi / 180);

    // Four side arms waving widely
    final armDeg = math.sin(_phase(0.6) * 2 * math.pi) * 25.0;
    canvas.save();
    canvas.translate(-13, -2);
    canvas.rotate( armDeg * math.pi / 180);
    canvas.drawPath(
      Path()..moveTo(0, 0)..quadraticBezierTo(-3, -4, -8, -8),
      _strokesPaint(width: 1.4),
    );
    canvas.restore();

    canvas.save();
    canvas.translate(13, -2);
    canvas.rotate(-armDeg * math.pi / 180);
    canvas.drawPath(
      Path()..moveTo(0, 0)..quadraticBezierTo(3, -4, 8, -8),
      _strokesPaint(width: 1.4),
    );
    canvas.restore();

    _drawTentacles(canvas, driftDeg: 0);
    _drawBody(canvas);
    _drawSideFins(canvas, leftOpen: true, rightOpen: true);

    // Big closed-eye smiles
    canvas.drawPath(
      Path()..moveTo(-6, -8)..quadraticBezierTo(-4, -11, -2, -8),
      _eyesPaint(),
    );
    canvas.drawPath(
      Path()..moveTo(2, -8)..quadraticBezierTo(4, -11, 6, -8),
      _eyesPaint(),
    );
    // Wide open mouth smile
    canvas.drawPath(
      Path()..moveTo(-4, -2)..quadraticBezierTo(0, 4, 4, -2)..close(),
      Paint()..color = _Palette.eyes.withValues(alpha: 0.85),
    );

    canvas.restore();

    // Nine sparkles at staggered offsets
    final sparkles = <_Sparkle>[
      _Sparkle(x: -22, y: -16, delay: 0.0),
      _Sparkle(x:  22, y: -16, delay: 0.1),
      _Sparkle(x: -16, y: -26, delay: 0.2),
      _Sparkle(x:  16, y: -26, delay: 0.3),
      _Sparkle(x:   0, y: -30, delay: 0.4),
      _Sparkle(x: -24, y:   2, delay: 0.5),
      _Sparkle(x:  24, y:   2, delay: 0.6),
      _Sparkle(x: -10, y: -24, delay: 0.7),
      _Sparkle(x:  10, y: -24, delay: 0.8),
    ];
    final sCycle = 1.0;
    final tS = (t * 5.0) % sCycle;
    for (final s in sparkles) {
      var ph = (tS - s.delay) / sCycle;
      if (ph < 0) ph += 1;
      final a = math.sin(ph * math.pi).clamp(0.0, 1.0);
      _drawSparkle(canvas, Offset(s.x, s.y), 1.8, a);
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  //                                RESTING
  // Body scale 1..1.03 at 4s. Tentacles tucked closer. Eyes closed (small
  // arcs). Fins lighter. Two z-circles rise from upper right with offset.
  // ─────────────────────────────────────────────────────────────────────────
  void _paintResting(Canvas canvas) {
    final s = 1.0 + 0.03 * _bell(_phase(4.0));

    canvas.save();
    canvas.scale(s);

    _drawTentacles(canvas, driftDeg: 0, tucked: true);
    _drawBody(canvas);
    _drawSideFins(canvas, leftOpen: false, rightOpen: false, alphaOverride: 0.7);

    // Closed-eye arcs
    final eyePaint = _eyesPaint();
    canvas.drawPath(
      Path()..moveTo(-6, -7.5)..quadraticBezierTo(-4, -8.5, -2, -7.5),
      eyePaint,
    );
    canvas.drawPath(
      Path()..moveTo(2, -7.5)..quadraticBezierTo(4, -8.5, 6, -7.5),
      eyePaint,
    );

    canvas.restore();

    // Two z-circles drifting up + fading, 3s cycle each, second offset 1.5s
    _drawZ(canvas, delay: 0.0);
    _drawZ(canvas, delay: 1.5);
  }

  void _drawZ(Canvas canvas, {required double delay}) {
    const cycle = 3.0;
    var ph = ((t * 5.0 - delay) / cycle) % 1.0;
    if (ph < 0) ph += 1;
    final dx = ph * 4;
    final dy = -ph * 12;
    final a  = (1 - ph).clamp(0.0, 1.0);

    canvas.save();
    canvas.translate(14 + dx, -14 + dy);
    final tp = TextPainter(
      text: TextSpan(
        text: 'z',
        style: TextStyle(
          color: _Palette.strokesFins.withValues(alpha: a * 0.85),
          fontSize: 7,
          fontWeight: FontWeight.w700,
          fontStyle: FontStyle.italic,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
    canvas.restore();
  }

  // ─────────────────────────────────────────────────────────────────────────
  //                                STEADYNOD
  // Calm steady presence. Body translateY -1.2 at 4s slow. Head/body rotate
  // 0..2° at 3s. Slow blink at 95-98% of 6s. Faint amber halo.
  // ─────────────────────────────────────────────────────────────────────────
  void _paintSteadyNod(Canvas canvas) {
    final bodyY  = -1.2 * _bell(_phase(4.0));
    final rotDeg =  2.0 * _bell(_phase(3.0));
    final p6     = (t * 5.0 / 6.0) % 1.0;
    final blink  = p6 > 0.95 && p6 < 0.98;
    final haloA  = 0.06 + 0.06 * _bell(_phase(4.0));

    // Faint amber halo
    canvas.drawCircle(
      const Offset(0, -3),
      28,
      Paint()..color = _Palette.body.withValues(alpha: haloA),
    );

    canvas.save();
    canvas.translate(0, bodyY);
    canvas.rotate(rotDeg * math.pi / 180);
    _drawTentacles(canvas, driftDeg: 0.4);
    _drawBody(canvas);
    _drawSideFins(canvas, leftOpen: false, rightOpen: false);
    _drawEyes(canvas, _EyeMode.wOpen, blinking: blink);
    canvas.restore();
  }

  // ─────────────────────────────────────────────────────────────────────────
  //                                SOFTWAVE
  // Phase 3.1 redefinition: softWave is idle + happy-curve eyes. Same body
  // float (3.5s), same fin undulation (1.5s, right offset 0.2s), same
  // tentacle drift (±0.8° at 3s), same late-cycle blink. Only the eye
  // shape differs. The earlier "calm waving arm" variant rendered with
  // frozen fins/tentacles which read as missing limbs at small sizes.
  // ─────────────────────────────────────────────────────────────────────────
  void _paintSoftWave(Canvas canvas) {
    final bodyY    = -2.0 * _bell(_phase(3.5));
    final finLOpen = _phase(1.5) > 0.5;
    final finROpen = (((t * 5.0 - 0.2) / 1.5) % 1.0) > 0.5;
    final blinking = t > 0.94 && t < 0.97;
    final driftDeg = math.sin(_phase(3.0) * 2 * math.pi) * 0.8;

    canvas.save();
    canvas.translate(0, bodyY);
    _drawTentacles(canvas, driftDeg: driftDeg);
    _drawBody(canvas);
    _drawSideFins(canvas, leftOpen: finLOpen, rightOpen: finROpen);
    _drawEyes(canvas, _EyeMode.happy, blinking: blinking);
    canvas.restore();
  }

  // ── Drawing primitives ─────────────────────────────────────────────────────

  Paint _strokesPaint({double width = 0.8}) => Paint()
    ..color       = _Palette.strokesFins
    ..style       = PaintingStyle.stroke
    ..strokeWidth = width
    ..strokeCap   = StrokeCap.round;

  Paint _eyesPaint() => Paint()
    ..color       = _Palette.eyes
    ..style       = PaintingStyle.stroke
    ..strokeWidth = 1.0
    ..strokeCap   = StrokeCap.round;

  void _drawBody(Canvas canvas, {Color? fillOverride}) {
    final body = Path()
      ..moveTo(0, -20)
      ..cubicTo(-8, -20, -13, -14, -13, -6)
      ..cubicTo(-13, 4, -11, 10, -8, 13)
      ..lineTo(-5, 14)
      ..lineTo(5, 14)
      ..lineTo(8, 13)
      ..cubicTo(11, 10, 13, 4, 13, -6)
      ..cubicTo(13, -14, 8, -20, 0, -20)
      ..close();
    canvas.drawPath(body, Paint()..color = fillOverride ?? _Palette.body);
    canvas.drawPath(body, _strokesPaint());
  }

  void _drawSideFins(Canvas canvas,
      {required bool leftOpen,
       required bool rightOpen,
       double alphaOverride = 1.0}) {
    final fillPaint = Paint()
      ..color = _Palette.body.withValues(alpha: alphaOverride);
    final strokePaint = Paint()
      ..color       = _Palette.strokesFins.withValues(alpha: alphaOverride)
      ..style       = PaintingStyle.stroke
      ..strokeWidth = 0.8;

    final closed = Path()
      ..moveTo(-13, -8)
      ..quadraticBezierTo(-22, -4, -22, 4)
      ..quadraticBezierTo(-22, 8, -19, 9)
      ..quadraticBezierTo(-15, 8, -13, 4)
      ..close();
    final open = Path()
      ..moveTo(-13, -8)
      ..quadraticBezierTo(-24, -3, -23, 5)
      ..quadraticBezierTo(-23, 9, -19, 10)
      ..quadraticBezierTo(-14, 8, -13, 4)
      ..close();

    final leftP  = leftOpen  ? open : closed;
    canvas.drawPath(leftP, fillPaint);
    canvas.drawPath(leftP, strokePaint);

    canvas.save();
    canvas.scale(-1, 1);
    final rightP = rightOpen ? open : closed;
    canvas.drawPath(rightP, fillPaint);
    canvas.drawPath(rightP, strokePaint);
    canvas.restore();
  }

  void _drawTentacles(Canvas canvas,
      {required double driftDeg,
       bool streamlined = false,
       bool tucked = false}) {
    final paint = _strokesPaint(width: 1.6);

    // Default geometry (idle/most states)
    final tentacles = <_Tentacle>[
      _Tentacle(ox: -5, ex: -6, ey: 25),
      _Tentacle(ox: -2, ex: -3, ey: 24),
      _Tentacle(ox:  2, ex:  3, ey: 24),
      _Tentacle(ox:  5, ex:  6, ey: 25),
      _Tentacle(ox: -3, ex: -4, ey: 30),
      _Tentacle(ox:  3, ex:  4, ey: 30),
    ];

    for (final tn in tentacles) {
      var ex = tn.ex;
      var ey = tn.ey;
      if (streamlined) {
        // Sweep tentacle endpoints back behind body
        ex = (tn.ex < 0) ? tn.ex - 3 : tn.ex + 3;
        ey = tn.ey - 4;
      }
      if (tucked) {
        // Pull endpoints in toward body for resting
        ex = tn.ex * 0.6;
        ey = (tn.ey - 14) * 0.5 + 14;
        if (ey > 21) ey = 21;
      }
      canvas.save();
      canvas.translate(tn.ox, 14);
      canvas.rotate(driftDeg * math.pi / 180);
      canvas.drawPath(
        Path()
          ..moveTo(0, 0)
          ..quadraticBezierTo(
              (ex - tn.ox) * 0.5, (ey - 14) * 0.5,
              ex - tn.ox,         ey - 14),
        paint,
      );
      canvas.restore();
    }
  }

  void _drawEyes(Canvas canvas, _EyeMode mode, {required bool blinking}) {
    final paint = _eyesPaint();
    canvas.save();
    if (blinking) {
      canvas.translate(0, -8);
      canvas.scale(1, 0.08);
      canvas.translate(0, 8);
    }

    final left  = Path();
    final right = Path();
    switch (mode) {
      case _EyeMode.wOpen:
        left
          ..moveTo(-6, -8)
          ..quadraticBezierTo(-5, -7, -4, -8)
          ..quadraticBezierTo(-3, -7, -2, -8);
        right
          ..moveTo( 2, -8)
          ..quadraticBezierTo( 3, -7,  4, -8)
          ..quadraticBezierTo( 5, -7,  6, -8);
        break;
      case _EyeMode.happy:
        left
          ..moveTo(-6, -8)
          ..quadraticBezierTo(-4, -10, -2, -8);
        right
          ..moveTo( 2, -8)
          ..quadraticBezierTo( 4, -10,  6, -8);
        break;
    }
    canvas.drawPath(left,  paint);
    canvas.drawPath(right, paint);
    canvas.restore();
  }

  // ── Sparkle / Star helpers ────────────────────────────────────────────────

  void _drawSparkle(Canvas canvas, Offset c, double size, double alpha) {
    if (alpha <= 0) return;
    final p = Paint()
      ..color = _Palette.toolGold.withValues(alpha: alpha)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8
      ..strokeCap   = StrokeCap.round;
    canvas.drawLine(
      Offset(c.dx - size, c.dy), Offset(c.dx + size, c.dy), p);
    canvas.drawLine(
      Offset(c.dx, c.dy - size), Offset(c.dx, c.dy + size), p);
  }

  void _drawStar(Canvas canvas, Offset c, double rOuter, Paint p) {
    final rInner = rOuter * 0.4;
    final path   = Path();
    for (int i = 0; i < 10; i++) {
      final r = i.isEven ? rOuter : rInner;
      final a = (i * math.pi / 5) - math.pi / 2;
      final px = c.dx + r * math.cos(a);
      final py = c.dy + r * math.sin(a);
      if (i == 0) {
        path.moveTo(px, py);
      } else {
        path.lineTo(px, py);
      }
    }
    path.close();
    canvas.drawPath(path, p);
  }

  // ── Variant helpers (Signature) ───────────────────────────────────────────

  _EyeMode _eyeModeForVariant(SignatureVariant v) {
    switch (v) {
      case SignatureVariant.she:     return _EyeMode.happy;
      case SignatureVariant.he:      return _EyeMode.wOpen;
      case SignatureVariant.neutral: return _EyeMode.wOpen;
    }
  }

  void _drawSpectacles(Canvas canvas) {
    final p = Paint()
      ..color       = _Palette.spectacles
      ..style       = PaintingStyle.stroke
      ..strokeWidth = 0.8
      ..strokeCap   = StrokeCap.round;
    canvas.drawCircle(const Offset(-4, -8), 3.8, p);
    canvas.drawCircle(const Offset( 4, -8), 3.8, p);
    canvas.drawLine(const Offset(-0.2, -8), const Offset(0.2, -8), p);
    canvas.drawLine(const Offset(-7.6, -8), const Offset(-9, -8), p);
    canvas.drawLine(const Offset( 7.6, -8), const Offset( 9, -8), p);
  }

  void _drawBlush(Canvas canvas) {
    final p = Paint()..color = _Palette.blush.withValues(alpha: 0.45);
    canvas.drawOval(
      Rect.fromCenter(center: const Offset(-9, -4), width: 6, height: 3), p);
    canvas.drawOval(
      Rect.fromCenter(center: const Offset( 9, -4), width: 6, height: 3), p);
  }

  void _drawBeardAndBrows(Canvas canvas) {
    final brow = Paint()
      ..color = _Palette.spectacles
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(const Offset(-7, -12.5), const Offset(-1, -13), brow);
    canvas.drawLine(const Offset( 1, -13),   const Offset( 7, -12.5), brow);

    final beard = Paint()
      ..color = _Palette.beardShadow.withValues(alpha: 0.4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.6
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(
      Path()..moveTo(-5, 0.5)..quadraticBezierTo(0, 2, 5, 0.5), beard);

    final jaw = Paint()
      ..color = _Palette.beardShadow.withValues(alpha: 0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.6
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(const Offset(-11, -3), const Offset(-12, 0), jaw);
    canvas.drawLine(const Offset( 11, -3), const Offset( 12, 0), jaw);
  }

  void _drawSmile(Canvas canvas, SignatureVariant v) {
    final paint = Paint()
      ..color       = _Palette.eyes
      ..style       = PaintingStyle.stroke
      ..strokeWidth = 0.9
      ..strokeCap   = StrokeCap.round;
    final p = Path();
    switch (v) {
      case SignatureVariant.she:
        p..moveTo(-3, -3)..quadraticBezierTo(0, 0, 3, -3);
        break;
      case SignatureVariant.he:
        p..moveTo(-3.5, -2.5)..quadraticBezierTo(0, -1, 3.5, -2.5);
        break;
      case SignatureVariant.neutral:
        p..moveTo(-3, -3)..quadraticBezierTo(0, -0.5, 3, -3);
        break;
    }
    canvas.drawPath(p, paint);
  }

  void _drawSignatureTools(Canvas canvas) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: const Offset(-22, 8), width: 8, height: 6),
        const Radius.circular(1.5),
      ),
      Paint()..color = _Palette.toolBlue,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: const Offset(22, 8), width: 4, height: 9),
        const Radius.circular(2),
      ),
      Paint()..color = _Palette.toolTeal,
    );
    canvas.drawCircle(
      const Offset(-22, -10), 3.2,
      Paint()..color = _Palette.toolGrey,
    );
    _drawStar(canvas, const Offset(22, -10), 3.6,
        Paint()..color = _Palette.toolGold);

    final arm = _strokesPaint(width: 1.4);
    canvas.drawLine(const Offset(-13, -2), const Offset(-22, -10), arm);
    canvas.drawLine(const Offset( 13, -2), const Offset( 22, -10), arm);
    canvas.drawLine(const Offset(-13,  6), const Offset(-22,  8),  arm);
    canvas.drawLine(const Offset( 13,  6), const Offset( 22,  8),  arm);
  }

  @override
  bool shouldRepaint(covariant _CuttlefishPainter old) =>
      old.t       != t ||
      old.state   != state ||
      old.variant != variant;
}

// ── Helpers ──────────────────────────────────────────────────────────────────

enum _EyeMode { wOpen, happy }

class _Tentacle {
  final double ox, ex, ey;
  const _Tentacle({required this.ox, required this.ex, required this.ey});
}

class _ThoughtDot {
  final double cx, cy, r, delay;
  const _ThoughtDot({
    required this.cx,
    required this.cy,
    required this.r,
    required this.delay,
  });
}

class _Sparkle {
  final double x, y, delay;
  const _Sparkle({required this.x, required this.y, required this.delay});
}

class _Bubble {
  final double x, period, r, delay;
  const _Bubble({
    required this.x,
    required this.period,
    required this.r,
    required this.delay,
  });
}
