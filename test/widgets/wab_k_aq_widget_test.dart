// test/widgets/wab_k_aq_widget_test.dart
//
// Intern scaffold Phase B1 — proof of the WAB-K AQ proving widget.
//
// The silent two-register interaction: scores in → AQ appears, no prompts,
// no narration. Asserts the verified formula (AQ = sum × 2) including values
// at EVERY Kertesz band boundary, the progressive insufficient states
// (0/1/2/3 subscores, missing named factually, singular/plural correct),
// the resolved announcement (value + band + math verbatim + citation and
// NOTHING else — no boundary-reassurance text), the out-of-range honesty
// (an impossible subscore never computes; it is named), recede-on-clear,
// in-place recompute on edit — and the Section 5 forbidden-language suite
// over every rendered state.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:cue/widgets/assessment/wab_k_aq_widget.dart';

import 'assessment_boundary_language.dart';

Widget _host() => const MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: WabKAqWidget(),
          ),
        ),
      ),
    );

/// Field order in the tree: 0 Spontaneous Speech, 1 Comprehension,
/// 2 Repetition, 3 Naming.
Future<void> _enter(WidgetTester tester, int field, String text) async {
  await tester.enterText(find.byType(TextField).at(field), text);
  await tester.pump();
}

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  group('formula', () {
    test('AQ is null until all four subscores are present', () {
      expect(
          computeWabAq(
              spontaneousSpeech: 14,
              comprehension: 7.5,
              repetition: 6.2,
              naming: null),
          isNull);
      expect(
          computeWabAq(
              spontaneousSpeech: null,
              comprehension: null,
              repetition: null,
              naming: null),
          isNull);
    });

    test('AQ = sum × 2 — the spec example and the extremes', () {
      expect(
          computeWabAq(
              spontaneousSpeech: 14,
              comprehension: 7.5,
              repetition: 6.2,
              naming: 5.8),
          closeTo(67.0, 1e-9));
      expect(
          computeWabAq(
              spontaneousSpeech: 0,
              comprehension: 0,
              repetition: 0,
              naming: 0),
          0.0);
      expect(
          computeWabAq(
              spontaneousSpeech: 20,
              comprehension: 10,
              repetition: 10,
              naming: 10),
          100.0);
    });
  });

  group('Kertesz bands — every boundary', () {
    // Published bands (Kertesz 1982): 0–25 very severe, 26–50 severe,
    // 51–75 moderate, 76+ mild — operationalized continuously (≤25, ≤50,
    // ≤75, >75) because fractional AQs are routine.
    test('values at and across each cutoff', () {
      expect(wabKerteszBand(0), 'Very severe');
      expect(wabKerteszBand(12.4), 'Very severe');
      expect(wabKerteszBand(25.0), 'Very severe'); // at cutoff: lower band
      expect(wabKerteszBand(25.1), 'Severe'); // just across
      expect(wabKerteszBand(26.0), 'Severe');
      expect(wabKerteszBand(50.0), 'Severe'); // at cutoff: lower band
      expect(wabKerteszBand(50.1), 'Moderate'); // just across
      expect(wabKerteszBand(51.0), 'Moderate');
      expect(wabKerteszBand(67.0), 'Moderate');
      expect(wabKerteszBand(75.0), 'Moderate'); // at cutoff: lower band
      expect(wabKerteszBand(75.1), 'Mild'); // just across
      expect(wabKerteszBand(76.0), 'Mild');
      expect(wabKerteszBand(93.8), 'Mild'); // Kertesz aphasia cutoff — still
      expect(wabKerteszBand(100.0), 'Mild'); // the published band; see code
    });
  });

  group('silent computation — the whole interaction', () {
    testWidgets('0/1/2/3 subscores wait factually; the 4th resolves the AQ',
        (tester) async {
      await tester.pumpWidget(_host());
      await tester.pumpAndSettle();

      // 0 entered.
      expect(find.text('insufficient data'), findsOneWidget);
      expect(find.text('4 more subscores needed'), findsOneWidget);
      expectNoInferentialLanguage(tester);

      // 1, 2, 3 entered — count falls, singular form correct at 1.
      await _enter(tester, 0, '14');
      expect(find.text('3 more subscores needed'), findsOneWidget);
      await _enter(tester, 1, '7.5');
      expect(find.text('2 more subscores needed'), findsOneWidget);
      await _enter(tester, 2, '6.2');
      expect(find.text('1 more subscore needed'), findsOneWidget);
      expect(find.textContaining('APHASIA'), findsNothing);
      expectNoInferentialLanguage(tester);

      // 4th lands → the result resolves in. Silently: no prompt existed.
      await _enter(tester, 3, '5.8');
      await tester.pumpAndSettle();

      expect(find.text('APHASIA QUOTIENT'), findsOneWidget);
      expect(find.text('67.0'), findsOneWidget);
      expect(find.text('Moderate'), findsOneWidget);
      expect(find.text('(14 + 7.5 + 6.2 + 5.8) × 2 = 67.0'), findsOneWidget);
      expect(find.text('per Kertesz 1982'), findsOneWidget);
      expect(find.text('insufficient data'), findsNothing);

      // NO boundary-reassurance text (cut in B0) — and no inference, ever.
      expect(find.textContaining('yours'), findsNothing);
      expect(find.textContaining('interpretation governs'), findsNothing);
      expect(find.textContaining('Computed from'), findsNothing);
      expectNoInferentialLanguage(tester);

      // The norming caveat (a real instrument fact) rides the resolved card.
      expect(find.text(kWabKNormingCaveatV1), findsOneWidget);
    });

    testWidgets('band boundary reached through the widget, not just the fn',
        (tester) async {
      await tester.pumpWidget(_host());
      await tester.pumpAndSettle();

      await _enter(tester, 0, '20');
      await _enter(tester, 1, '5');
      await _enter(tester, 2, '0');
      await _enter(tester, 3, '0');
      await tester.pumpAndSettle();
      expect(find.text('50.0'), findsOneWidget);
      expect(find.text('Severe'), findsOneWidget); // 50.0 → lower band

      await _enter(tester, 1, '5.1');
      await tester.pumpAndSettle();
      expect(find.text('50.2'), findsOneWidget);
      expect(find.text('Moderate'), findsOneWidget); // across the cutoff
    });

    testWidgets('a subscore above its maximum never computes — named, waits',
        (tester) async {
      await tester.pumpWidget(_host());
      await tester.pumpAndSettle();

      await _enter(tester, 0, '14');
      await _enter(tester, 1, '12'); // comprehension is /10
      await _enter(tester, 2, '6.2');
      await _enter(tester, 3, '5.8');
      await tester.pumpAndSettle();

      expect(find.text('insufficient data'), findsOneWidget);
      expect(
          find.text('Comprehension exceeds its /10 maximum'), findsOneWidget);
      expect(find.text('APHASIA QUOTIENT'), findsNothing);
      expect(find.textContaining('per Kertesz'), findsNothing);
      expectNoInferentialLanguage(tester);

      // Correcting it resolves.
      await _enter(tester, 1, '7.5');
      await tester.pumpAndSettle();
      expect(find.text('67.0'), findsOneWidget);
    });

    testWidgets('editing a subscore recomputes in place', (tester) async {
      await tester.pumpWidget(_host());
      await tester.pumpAndSettle();
      await _enter(tester, 0, '14');
      await _enter(tester, 1, '7.5');
      await _enter(tester, 2, '6.2');
      await _enter(tester, 3, '5.8');
      await tester.pumpAndSettle();
      expect(find.text('67.0'), findsOneWidget);

      await _enter(tester, 0, '15');
      await tester.pumpAndSettle();
      expect(find.text('69.0'), findsOneWidget);
      expect(find.text('(15 + 7.5 + 6.2 + 5.8) × 2 = 69.0'), findsOneWidget);
      expect(find.text('67.0'), findsNothing);
    });

    testWidgets('clearing a subscore recedes to the waiting state',
        (tester) async {
      await tester.pumpWidget(_host());
      await tester.pumpAndSettle();
      await _enter(tester, 0, '14');
      await _enter(tester, 1, '7.5');
      await _enter(tester, 2, '6.2');
      await _enter(tester, 3, '5.8');
      await tester.pumpAndSettle();
      expect(find.text('APHASIA QUOTIENT'), findsOneWidget);

      await _enter(tester, 3, '');
      await tester.pumpAndSettle();
      expect(find.text('APHASIA QUOTIENT'), findsNothing);
      expect(find.text('insufficient data'), findsOneWidget);
      expect(find.text('1 more subscore needed'), findsOneWidget);
      expect(find.text(kWabKNormingCaveatV1), findsNothing);
      expectNoInferentialLanguage(tester);
    });
  });
}
