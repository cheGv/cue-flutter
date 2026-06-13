// lib/widgets/assessment/cue_trend_sparkline.dart
//
// Intern scaffold Phase C — the VISUAL register, component 1: the trend
// sparkline that STOPS.
//
// THE PRINCIPLE (the boundary, for visuals). The visual register makes the
// data's SHAPE legible so the clinician's own pattern-recognition engages
// faster. It is salience, not judgment: it REVEALS structure the clinician
// interprets, it never arranges structure so the interpretation is pre-made.
// A chart is more persuasive than a sentence — it bypasses the skepticism a
// sentence invites and lands as "the data says" — so the boundary here is
// stricter, not looser.
//
// THE HARD RULE (structural, tested): NEVER EXTRAPOLATE. This component draws
// where the data IS and where it has BEEN — the entered points, in order,
// connected — and renders NOTHING past the final datum. No dotted continuation,
// no "expected next" point, no forecast. The guarantee is built in, not painted
// on: [cueTrendUnitCoords] returns EXACTLY one coordinate per entered point, so
// there is no coordinate past the last datum for anything to be drawn at. The
// line cannot reach where the data hasn't been. The end is marked explicitly
// ("latest") so the stop is legible rather than hidden.
//
// What it does NOT do: no semantic colour (rising≠good, falling≠bad — colouring
// the slope would be judgment); the line is one calm olive everywhere. No
// trend verdict in words (that is the clinician's read of the shape). With 0 or
// 1 points there is no trend to draw, so it says so factually and draws no lone
// point masquerading as a chart — never a fabricated datum.
//
// REGISTER & PALETTE — locked light-spine palette + typography, file-local
// consts, exactly like the sibling assessment components (LoudResult,
// WabKAqWidget). Olive = the calm reading-aid register; the visual is quiet, a
// reading aid and not a centerpiece.
//
// CONTAINED & STANDALONE: wired to NO surface, no schema, no service — a pure
// reusable component, the LoudResult ritual. The boundary suite in
// test/widgets/cue_trend_sparkline_test.dart makes projection unrepresentable
// in a passing build.

import 'dart:math' as math;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// Locked spine palette (matches the sibling assessment components).
const Color _inkTertiary = Color(0xFF888780); // axis / metadata
const Color _olive = Color(0xFF5C6E3B); // calm reading-aid accent (line + dots)

/// One entered datum: a [label] (an x-axis category or re-assessment date) and
/// its [value]. Plotted exactly as entered — never resampled, never sorted.
class CueTrendPoint {
  final String label;
  final double value;
  const CueTrendPoint(this.label, this.value);
}

/// Pure geometry — the structural heart of the "never extrapolate" rule.
///
/// Maps each entered point to a unit-square coordinate: x runs left→right
/// across the sequence (band-centred at `(i + 0.5) / n`, so a deliberate gap
/// follows the final datum — the data visibly STOPS), y runs bottom→top across
/// the value range (0 = lowest entered value, 1 = highest). There is EXACTLY
/// one coordinate per input point: the sequence starts at the first datum and
/// ends at the last. No coordinate exists past the final point, so nothing —
/// no segment, dot, or marker — can be drawn there. Projection is impossible by
/// construction, not by restraint.
///
/// A flat series (all values equal) centres every point at y = 0.5 — an honest
/// flat line, never a fabricated slope.
List<Offset> cueTrendUnitCoords(List<CueTrendPoint> points) {
  final n = points.length;
  if (n == 0) return const [];
  var min = points.first.value;
  var max = points.first.value;
  for (final p in points) {
    min = math.min(min, p.value);
    max = math.max(max, p.value);
  }
  final span = max - min;
  return [
    for (var i = 0; i < n; i++)
      Offset((i + 0.5) / n, span == 0 ? 0.5 : (points[i].value - min) / span),
  ];
}

class CueTrendSparkline extends StatelessWidget {
  /// Ordered, as entered. Rendered in sequence; never sorted or resampled.
  final List<CueTrendPoint> points;

  /// Optional unit shown on the value-scale ticks ('%', '/session', …).
  final String? valueSuffix;

  const CueTrendSparkline(this.points, {super.key, this.valueSuffix});

  static const double _plotH = 64;
  static const double _r = 3.5; // dot radius — uniform across every point
  static const double _scaleW = 34; // fixed value-scale column (keeps x aligned)
  static const double _gap = 10;

  @override
  Widget build(BuildContext context) {
    // 0 points → render nothing; the surface's own chrome owns the invitation.
    if (points.isEmpty) return const SizedBox.shrink();
    // 1 point → no trend to draw. Calm and factual, like LoudResult's
    // insufficient state — never a fabricated second point, never a lone dot
    // dressed up as a chart.
    if (points.length == 1) {
      return Text(
        'Not enough data points to show a trend.',
        style:
            GoogleFonts.inter(fontSize: 12, color: _inkTertiary, height: 1.45),
      );
    }
    return _plot();
  }

  Widget _plot() {
    final unit = cueTrendUnitCoords(points);
    final maxV = points.map((p) => p.value).reduce(math.max);
    final minV = points.map((p) => p.value).reduce(math.min);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
                width: _scaleW, height: _plotH, child: _valueScale(maxV, minV)),
            const SizedBox(width: _gap),
            Expanded(
              child: SizedBox(
                height: _plotH,
                child: LayoutBuilder(builder: (context, c) {
                  final w = c.maxWidth;
                  const usableH = _plotH - 2 * (_r + 2);
                  final px = [
                    for (final u in unit)
                      Offset(u.dx * w, (_r + 2) + (1 - u.dy) * usableH),
                  ];
                  return Stack(
                    clipBehavior: Clip.none,
                    children: [
                      // The line — drawn ONLY through the entered points; the
                      // painter has no coordinate past the last to draw to.
                      Positioned.fill(
                        child: CustomPaint(painter: _SparkLinePainter(px)),
                      ),
                      for (var i = 0; i < px.length; i++)
                        Positioned(
                          left: px[i].dx - _r,
                          top: px[i].dy - _r,
                          child: _Dot(key: ValueKey('cue-trend-pt-$i')),
                        ),
                      // The end, named explicitly — the no-projection rule made
                      // legible. Marks WHERE the data stops, not which value is
                      // "the answer".
                      Positioned(
                        left: math.min(px.last.dx + _r + 3, w - 30),
                        top: px.last.dy - 7,
                        child: Text(
                          'latest',
                          key: const ValueKey('cue-trend-latest'),
                          style: GoogleFonts.inter(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: _olive),
                        ),
                      ),
                    ],
                  );
                }),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        // Point labels, band-centred to sit under their dots.
        Padding(
          padding: const EdgeInsets.only(left: _scaleW + _gap),
          child: Row(
            children: [
              for (final p in points)
                Expanded(
                  child: Text(
                    p.label,
                    style: GoogleFonts.inter(fontSize: 10.5, color: _inkTertiary),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _valueScale(double maxV, double minV) {
    final style = GoogleFonts.inter(
        fontSize: 10,
        color: _inkTertiary,
        fontFeatures: const [FontFeature.tabularFigures()]);
    if (maxV == minV) {
      return Center(child: Text(_fmt(maxV), style: style));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(_fmt(maxV), style: style),
        Text(_fmt(minV), style: style),
      ],
    );
  }

  String _fmt(double v) {
    final s = v == v.roundToDouble() ? v.toInt().toString() : v.toString();
    return valueSuffix == null ? s : '$s$valueSuffix';
  }
}

/// Uniform data-point dot — identical for every point (no point is louder than
/// another; the data's shape is what is read, not any single value).
class _Dot extends StatelessWidget {
  const _Dot({super.key});

  @override
  Widget build(BuildContext context) {
    const d = CueTrendSparkline._r * 2;
    return Container(
      width: d,
      height: d,
      decoration: const BoxDecoration(color: _olive, shape: BoxShape.circle),
    );
  }
}

/// Draws the connecting line — and ONLY the connecting line, segment by segment
/// between consecutive entered points. The path's final `lineTo` is the last
/// datum; it has nowhere past it to go.
class _SparkLinePainter extends CustomPainter {
  final List<Offset> px;
  const _SparkLinePainter(this.px);

  @override
  void paint(Canvas canvas, Size size) {
    if (px.length < 2) return;
    final paint = Paint()
      ..color = _olive
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final path = Path()..moveTo(px.first.dx, px.first.dy);
    for (var i = 1; i < px.length; i++) {
      path.lineTo(px[i].dx, px[i].dy);
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_SparkLinePainter old) => !listEquals(old.px, px);
}
