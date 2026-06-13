// test/widgets/cue_trend_sparkline_test.dart
//
// Phase C boundary suite for the trend sparkline. The HARD RULE — never
// extrapolate — is enforced structurally: the pure geometry returns exactly one
// coordinate per entered datum (so no coordinate past the last point exists to
// draw at), and the widget renders exactly one dot per datum with the end named
// "latest". A projected point is unrepresentable in a passing build. Any text
// label still passes the §5 forbidden-language sweep.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:cue/widgets/assessment/cue_trend_sparkline.dart';

import 'assessment_boundary_language.dart';

Widget _host(Widget child) => MaterialApp(
      home: Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: SizedBox(width: 360, child: child),
        ),
      ),
    );

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  group('geometry — the structural no-projection guarantee', () {
    test('one coordinate per datum; the last datum is the rightmost — nothing '
        'beyond it', () {
      const pts = [
        CueTrendPoint('a', 10),
        CueTrendPoint('b', 20),
        CueTrendPoint('c', 15),
      ];
      final coords = cueTrendUnitCoords(pts);

      // Exactly one coordinate per entered point — no projected/fabricated one.
      expect(coords.length, pts.length);

      // Band-centred x: 1/6, 3/6, 5/6 — a deliberate gap follows the last datum.
      expect(coords[0].dx, closeTo(1 / 6, 1e-9));
      expect(coords[1].dx, closeTo(3 / 6, 1e-9));
      expect(coords[2].dx, closeTo(5 / 6, 1e-9));

      // The final datum IS the maximum x; the curve cannot reach past it.
      final maxDx = coords.map((c) => c.dx).reduce(math.max);
      expect(coords.last.dx, maxDx);
      expect(coords.every((c) => c.dx < 1.0), isTrue);

      // y normalised over the value range: min(10)→0, max(20)→1, 15→0.5.
      expect(coords[0].dy, closeTo(0.0, 1e-9));
      expect(coords[1].dy, closeTo(1.0, 1e-9));
      expect(coords[2].dy, closeTo(0.5, 1e-9));
    });

    test('a flat series is an honest flat line (y=0.5), never a fabricated '
        'slope', () {
      final coords = cueTrendUnitCoords(const [
        CueTrendPoint('a', 7),
        CueTrendPoint('b', 7),
        CueTrendPoint('c', 7),
      ]);
      expect(coords.every((c) => c.dy == 0.5), isTrue);
    });

    test('empty input → no coordinates (never a fabricated point)', () {
      expect(cueTrendUnitCoords(const []), isEmpty);
      expect(cueTrendUnitCoords(const [CueTrendPoint('only', 5)]).length, 1);
    });
  });

  group('rendering — stops at the last datum', () {
    testWidgets('plots exactly one dot per datum, marks the latest, draws '
        'nothing beyond', (tester) async {
      await tester.pumpWidget(_host(const CueTrendSparkline([
        CueTrendPoint('SW', 60),
        CueTrendPoint('Phr', 45),
        CueTrendPoint('Conn', 30),
      ], valueSuffix: '%')));
      await tester.pumpAndSettle();

      // One dot per datum.
      expect(find.byKey(const ValueKey('cue-trend-pt-0')), findsOneWidget);
      expect(find.byKey(const ValueKey('cue-trend-pt-1')), findsOneWidget);
      expect(find.byKey(const ValueKey('cue-trend-pt-2')), findsOneWidget);
      // No fourth (projected) point exists.
      expect(find.byKey(const ValueKey('cue-trend-pt-3')), findsNothing);

      // The end is named explicitly — the data stops here.
      expect(find.byKey(const ValueKey('cue-trend-latest')), findsOneWidget);
      expect(find.text('latest'), findsOneWidget);

      // Axis context: the value scale (max + min) and the point labels.
      expect(find.text('60%'), findsOneWidget);
      expect(find.text('30%'), findsOneWidget);
      expect(find.text('SW'), findsOneWidget);
      expect(find.text('Phr'), findsOneWidget);
      expect(find.text('Conn'), findsOneWidget);

      expectNoInferentialLanguage(tester);
    });

    testWidgets('1 point: no trend line — calm, factual, no lone dot dressed up '
        'as a chart', (tester) async {
      await tester.pumpWidget(
          _host(const CueTrendSparkline([CueTrendPoint('SW', 60)])));
      await tester.pumpAndSettle();

      expect(
          find.text('Not enough data points to show a trend.'), findsOneWidget);
      expect(find.byKey(const ValueKey('cue-trend-pt-0')), findsNothing);
      expect(find.byKey(const ValueKey('cue-trend-latest')), findsNothing);
      expectNoInferentialLanguage(tester);
    });

    testWidgets('0 points: renders nothing', (tester) async {
      await tester.pumpWidget(_host(const CueTrendSparkline([])));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('cue-trend-pt-0')), findsNothing);
      expect(find.byKey(const ValueKey('cue-trend-latest')), findsNothing);
      expect(
          find.text('Not enough data points to show a trend.'), findsNothing);
      // The component itself takes up no height — it renders nothing.
      expect(tester.getSize(find.byType(CueTrendSparkline)).height, 0);
    });

    testWidgets('a falling AND a rising series both just show their shape — no '
        'semantic colour, no verdict', (tester) async {
      // Rising.
      await tester.pumpWidget(_host(const CueTrendSparkline([
        CueTrendPoint('t1', 20),
        CueTrendPoint('t2', 55),
        CueTrendPoint('t3', 90),
      ])));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('cue-trend-pt-2')), findsOneWidget);
      expectNoInferentialLanguage(tester);

      // Falling — same component, same treatment.
      await tester.pumpWidget(_host(const CueTrendSparkline([
        CueTrendPoint('t1', 90),
        CueTrendPoint('t2', 55),
        CueTrendPoint('t3', 20),
      ])));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('cue-trend-pt-2')), findsOneWidget);
      expectNoInferentialLanguage(tester);
    });
  });
}
