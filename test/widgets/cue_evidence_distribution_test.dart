// test/widgets/cue_evidence_distribution_test.dart
//
// Phase C boundary suite for the equal-weight evidence distribution. The HARD
// RULE — never rank by likelihood — is enforced structurally: options render in
// input order (reorder the input, the render follows — it never sorts by
// count); equal counts render identically; no option's visual weight scales
// with its count (same row, same label style, same dot size, same track width);
// empty options render their empty state, not hidden. Any text label still
// passes the §5 forbidden-language sweep.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:cue/widgets/assessment/cue_evidence_distribution.dart';

import 'assessment_boundary_language.dart';

Widget _host(Widget child) => MaterialApp(
      home: Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: SizedBox(width: 360, child: child),
        ),
      ),
    );

/// The label rendered in row [row] (the first Text in the row is the label).
String _rowLabel(WidgetTester tester, int row) {
  final t = tester.widget<Text>(
    find
        .descendant(
          of: find.byKey(ValueKey('cue-ev-row-$row')),
          matching: find.byType(Text),
        )
        .first,
  );
  return t.data ?? '';
}

/// How many dots are filled in row [row].
int _filled(WidgetTester tester, int row, int slots) {
  var f = 0;
  for (var j = 0; j < slots; j++) {
    if (find.byKey(ValueKey('cue-ev-dot-$row-$j-filled')).evaluate().isNotEmpty) {
      f++;
    }
  }
  return f;
}

/// How many dot slots row [row] renders (filled + empty) — its track width.
int _slotsRendered(WidgetTester tester, int row, int slots) {
  var n = 0;
  for (var j = 0; j < slots; j++) {
    final filled =
        find.byKey(ValueKey('cue-ev-dot-$row-$j-filled')).evaluate().isNotEmpty;
    final empty =
        find.byKey(ValueKey('cue-ev-dot-$row-$j-empty')).evaluate().isNotEmpty;
    if (filled || empty) n++;
  }
  return n;
}

TextStyle _labelStyleOf(WidgetTester tester, String label) =>
    tester.widget<Text>(find.text(label)).style!;

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  group('trackSlots — the shared, data-driven track width', () {
    test('the max count present, clamped to a readable [3, 8]', () {
      expect(CueEvidenceDistribution.trackSlots(const []), 0);
      // All empty → still a visible track (min 3) so absence is readable.
      expect(
          CueEvidenceDistribution.trackSlots(const [
            CueEvidenceOption('a', 0),
            CueEvidenceOption('b', 0),
          ]),
          3);
      expect(
          CueEvidenceDistribution.trackSlots(
              const [CueEvidenceOption('a', 5)]),
          5);
      // Clamped so the track never balloons.
      expect(
          CueEvidenceDistribution.trackSlots(
              const [CueEvidenceOption('a', 12)]),
          8);
    });
  });

  group('order — content-neutral, never ranked by likelihood', () {
    testWidgets('renders in input order even when that is NOT count order',
        (tester) async {
      // If it sorted by count (desc) the order would be Beta(7), Gamma(4),
      // Alpha(1). It must NOT.
      const opts = [
        CueEvidenceOption('Alpha', 1),
        CueEvidenceOption('Beta', 7),
        CueEvidenceOption('Gamma', 4),
      ];
      await tester.pumpWidget(_host(const CueEvidenceDistribution(opts)));
      await tester.pumpAndSettle();

      expect(_rowLabel(tester, 0), 'Alpha'); // lowest count, still FIRST
      expect(_rowLabel(tester, 1), 'Beta');
      expect(_rowLabel(tester, 2), 'Gamma');
      expectNoInferentialLanguage(tester);
    });

    testWidgets('reordering the input reorders the render — it follows the '
        'input, not the count', (tester) async {
      const opts = [
        CueEvidenceOption('Beta', 7),
        CueEvidenceOption('Alpha', 1),
        CueEvidenceOption('Gamma', 4),
      ];
      await tester.pumpWidget(_host(const CueEvidenceDistribution(opts)));
      await tester.pumpAndSettle();

      expect(_rowLabel(tester, 0), 'Beta');
      expect(_rowLabel(tester, 1), 'Alpha');
      expect(_rowLabel(tester, 2), 'Gamma');
    });
  });

  group('equal weight — no count gets louder', () {
    testWidgets('equal counts render identically — no tiebreak emphasis',
        (tester) async {
      const opts = [
        CueEvidenceOption('First', 3),
        CueEvidenceOption('Second', 3),
      ];
      await tester.pumpWidget(_host(const CueEvidenceDistribution(opts)));
      await tester.pumpAndSettle();
      final slots = CueEvidenceDistribution.trackSlots(opts);

      expect(_filled(tester, 0, slots), 3);
      expect(_filled(tester, 1, slots), 3); // identical fill
      // Identical label styling — no bold/size/colour tiebreak.
      final a = _labelStyleOf(tester, 'First');
      final b = _labelStyleOf(tester, 'Second');
      expect(a.fontSize, b.fontSize);
      expect(a.fontWeight, b.fontWeight);
      expect(a.color, b.color);
    });

    testWidgets('visual weight does not scale with count — the high-count '
        'option is not dominant', (tester) async {
      const opts = [
        CueEvidenceOption('Low', 1),
        CueEvidenceOption('High', 6),
        CueEvidenceOption('Zero', 0),
      ];
      await tester.pumpWidget(_host(const CueEvidenceDistribution(opts)));
      await tester.pumpAndSettle();
      final slots = CueEvidenceDistribution.trackSlots(opts); // 6

      // Same track WIDTH (slot count) for every row, whatever the count.
      for (var row = 0; row < opts.length; row++) {
        expect(_slotsRendered(tester, row, slots), slots,
            reason: 'row $row must render the same number of slots');
      }
      // The fill reflects the data, with equal treatment.
      expect(_filled(tester, 0, slots), 1);
      expect(_filled(tester, 1, slots), 6);
      expect(_filled(tester, 2, slots), 0);

      // Label style identical for the highest- and lowest-count options.
      final hi = _labelStyleOf(tester, 'High');
      final lo = _labelStyleOf(tester, 'Low');
      expect(hi.fontSize, lo.fontSize);
      expect(hi.fontWeight, lo.fontWeight);

      // A filled dot and an empty dot are the SAME size — fill never resizes.
      final filledSize =
          tester.getSize(find.byKey(const ValueKey('cue-ev-dot-1-0-filled')));
      final emptySize =
          tester.getSize(find.byKey(const ValueKey('cue-ev-dot-2-0-empty')));
      expect(filledSize, emptySize);
    });
  });

  group('absence is information', () {
    testWidgets('an option with no evidence shows its empty state, not hidden',
        (tester) async {
      const opts = [
        CueEvidenceOption('Present', 4),
        CueEvidenceOption('Absent', 0),
      ];
      await tester.pumpWidget(_host(const CueEvidenceDistribution(opts)));
      await tester.pumpAndSettle();
      final slots = CueEvidenceDistribution.trackSlots(opts); // 4

      // The zero-evidence option is rendered (not hidden, not de-emphasized).
      expect(find.byKey(const ValueKey('cue-ev-row-1')), findsOneWidget);
      expect(find.text('Absent'), findsOneWidget);
      expect(find.text('0'), findsOneWidget); // its tally reads zero
      expect(_filled(tester, 1, slots), 0);
      for (var j = 0; j < slots; j++) {
        expect(find.byKey(ValueKey('cue-ev-dot-1-$j-empty')), findsOneWidget);
      }
    });

    testWidgets('empty options list renders nothing', (tester) async {
      await tester.pumpWidget(_host(const CueEvidenceDistribution([])));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('cue-ev-row-0')), findsNothing);
    });
  });

  group('§5 forbidden-language sweep over labels and tallies', () {
    testWidgets('a realistic differential set passes the sweep', (tester) async {
      await tester.pumpWidget(_host(const CueEvidenceDistribution([
        CueEvidenceOption('Articulation', 2),
        CueEvidenceOption('Phonological delay', 5),
        CueEvidenceOption('Consistent atypical', 3),
        CueEvidenceOption('Inconsistent phonological', 0),
      ])));
      await tester.pumpAndSettle();
      expectNoInferentialLanguage(tester);
    });
  });
}
