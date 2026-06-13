// test/widgets/wab_k_aq_widget_test.dart
//
// Intern scaffold Phase B1 + B+ — proof of the WAB-K AQ proving widget.
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
//
// B+ multilingual layer: the adaptation selector changes the administered-
// instrument detail line and the norming caveat ONLY. Same subscores → same
// AQ → same band in every adaptation; the band wears "Kertesz 1982
// reference" in every adaptation (never the language's own validated
// cutoff); the §5 suite runs clean across every selected-language state.
//
// Aphasia cutoff (Kertesz & Poole 1974): AQ ≥ 93.8 is classified no aphasia,
// surfaced in place of the "Mild" severity band (band and cutoff are different
// instruments); AQ just below stays banded; the cutoff caveat names the cutoff
// reference, not the severity bands; §5 stays clean over the new output.

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

/// Open the adaptation dropdown and pick [label].
Future<void> _selectAdaptation(WidgetTester tester, String label) async {
  await tester.tap(find.byType(DropdownButtonFormField<WabAdaptation>));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

/// Enter the spec-example subscores → AQ 67.0, Moderate.
Future<void> _enterExampleScores(WidgetTester tester) async {
  await _enter(tester, 0, '14');
  await _enter(tester, 1, '7.5');
  await _enter(tester, 2, '6.2');
  await _enter(tester, 3, '5.8');
  await tester.pumpAndSettle();
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
      // wabKerteszBand is the PURE severity band — it never applies the 93.8
      // aphasia cutoff (that is wabAtOrAboveAphasiaCutoff, exercised in the
      // next group and surfaced by the widget). So on the severity scale 93.8
      // and 100 are still 'Mild'; the cutoff relation is layered on top.
      expect(wabKerteszBand(93.8), 'Mild');
      expect(wabKerteszBand(100.0), 'Mild');
    });
  });

  group('aphasia cutoff (93.8) — Kertesz & Poole 1974', () {
    // The cutoff is a DIFFERENT instrument from the severity band: AQ ≥ 93.8 is
    // classified no aphasia, even though the severity scale would call that
    // range "Mild". Reporting a published cutoff, never diagnosing.
    test('wabAtOrAboveAphasiaCutoff: inclusive at 93.8, on the exact value', () {
      expect(kWabAphasiaCutoff, 93.8);
      expect(wabAtOrAboveAphasiaCutoff(93.79), isFalse);
      expect(wabAtOrAboveAphasiaCutoff(93.8), isTrue); // at cutoff: inclusive
      expect(wabAtOrAboveAphasiaCutoff(93.81), isTrue);
      expect(wabAtOrAboveAphasiaCutoff(96.0), isTrue);
      expect(wabAtOrAboveAphasiaCutoff(100.0), isTrue);
      expect(wabAtOrAboveAphasiaCutoff(93.6), isFalse); // just below → banded
      expect(wabAtOrAboveAphasiaCutoff(75.0), isFalse);
      expect(wabAtOrAboveAphasiaCutoff(0), isFalse);
    });

    test('cutoff caveat names the cutoff reference, not the severity bands', () {
      // English: its own cutoff (Kertesz & Poole 1974) — no caveat, either
      // register.
      expect(wabAdaptationCaveat(kWabAdaptations[0], atOrAboveCutoff: true),
          isNull);
      // Own-norms adaptation: the cutoff reference is named (not "Severity
      // bands"), then the own-norms context.
      expect(
        wabAdaptationCaveat(
            kWabAdaptations.firstWhere((a) => a.code == 'kannada'),
            atOrAboveCutoff: true),
        'The 93.8 aphasia cutoff is the Kertesz & Poole 1974 (English WAB) '
        'reference — Kannada WAB-K publishes its own normative data; interpret '
        'with that context.',
      );
      // Generic adaptation.
      expect(
        wabAdaptationCaveat(
            kWabAdaptations.firstWhere((a) => a.code == 'hindi'),
            atOrAboveCutoff: true),
        'The 93.8 aphasia cutoff is the Kertesz & Poole 1974 (English WAB) '
        "reference — interpret against the administered adaptation's norms.",
      );
    });

    testWidgets(
        'AQ ≥ 93.8 surfaces the cutoff relation in place of the "Mild" band',
        (tester) async {
      await tester.pumpWidget(_host());
      await tester.pumpAndSettle();

      // 20 + 10 + 9 + 9 = 48 → AQ 96.0 — the spec's mislabel example, which
      // used to render "Mild".
      await _enter(tester, 0, '20');
      await _enter(tester, 1, '10');
      await _enter(tester, 2, '9');
      await _enter(tester, 3, '9');
      await tester.pumpAndSettle();

      expect(find.text('96.0'), findsOneWidget);
      expect(find.text(kWabNoAphasiaLabel), findsOneWidget); // 'No aphasia'
      expect(find.text(kWabAphasiaCutoffNote), findsOneWidget);
      // The mislabel is gone: no severity band shown at/above the cutoff.
      expect(find.text('Mild'), findsNothing);
      // Formula source unchanged — the AQ is still Kertesz 1982.
      expect(find.text('per Kertesz 1982'), findsOneWidget);
      // English carries its own cutoff — no caveat block (both variants say
      // "interpret"; none is shown here).
      expect(find.textContaining('interpret'), findsNothing);
      // Reporting a published cutoff is not inferential language.
      expectNoInferentialLanguage(tester);
    });

    testWidgets('AQ just below 93.8 stays the severity band, no cutoff line',
        (tester) async {
      await tester.pumpWidget(_host());
      await tester.pumpAndSettle();

      // 20 + 9 + 9 + 8.8 = 46.8 → AQ 93.6, just below the cutoff.
      await _enter(tester, 0, '20');
      await _enter(tester, 1, '9');
      await _enter(tester, 2, '9');
      await _enter(tester, 3, '8.8');
      await tester.pumpAndSettle();

      expect(find.text('93.6'), findsOneWidget);
      expect(find.text('Mild'), findsOneWidget); // banded as before
      expect(find.text(kWabBandReferenceNote), findsOneWidget);
      expect(find.text(kWabNoAphasiaLabel), findsNothing);
      expect(find.text(kWabAphasiaCutoffNote), findsNothing);
      expectNoInferentialLanguage(tester);
    });

    testWidgets('crossing 93.8 by one edit flips band → cutoff relation',
        (tester) async {
      await tester.pumpWidget(_host());
      await tester.pumpAndSettle();

      // 20 + 9 + 9 + 8.8 → AQ 93.6, Mild.
      await _enter(tester, 0, '20');
      await _enter(tester, 1, '9');
      await _enter(tester, 2, '9');
      await _enter(tester, 3, '8.8');
      await tester.pumpAndSettle();
      expect(find.text('Mild'), findsOneWidget);
      expect(find.text(kWabNoAphasiaLabel), findsNothing);

      // Nudge naming 8.8 → 9 (sum 47 → AQ 94.0), crossing the cutoff.
      await _enter(tester, 3, '9');
      await tester.pumpAndSettle();
      expect(find.text('94.0'), findsOneWidget);
      expect(find.text(kWabNoAphasiaLabel), findsOneWidget);
      expect(find.text('Mild'), findsNothing);
      expectNoInferentialLanguage(tester);
    });

    testWidgets('cutoff caveat shows for a non-English adaptation, §5 clean',
        (tester) async {
      await tester.pumpWidget(_host());
      await tester.pumpAndSettle();
      // AQ 96.0, above the cutoff.
      await _enter(tester, 0, '20');
      await _enter(tester, 1, '10');
      await _enter(tester, 2, '9');
      await _enter(tester, 3, '9');
      await tester.pumpAndSettle();

      await _selectAdaptation(tester, 'Kannada (WAB-K)');

      expect(find.text('96.0'), findsOneWidget);
      expect(find.text(kWabNoAphasiaLabel), findsOneWidget);
      // The caveat now names the CUTOFF reference, not "Severity bands".
      final caveat = wabAdaptationCaveat(
          kWabAdaptations.firstWhere((a) => a.code == 'kannada'),
          atOrAboveCutoff: true);
      expect(find.text(caveat!), findsOneWidget);
      expect(find.textContaining('Severity bands are'), findsNothing);
      expectNoInferentialLanguage(tester);
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

      // B+: the band wears its provenance; the administered instrument is
      // recorded; English (the default, explicit) carries no caveat — the
      // displayed bands ARE its own norms.
      expect(find.text(kWabBandReferenceNote), findsOneWidget);
      expect(find.text('English WAB · Kertesz 1982'), findsOneWidget);
      expect(find.textContaining('Severity bands are'), findsNothing);
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
      expect(find.text('English WAB · Kertesz 1982'), findsNothing);
      expectNoInferentialLanguage(tester);
    });
  });

  group('multilingual layer — language changes the label, never the math', () {
    test('the registry: six published adaptations, unique codes, cited', () {
      expect(kWabAdaptations.length, 6);
      expect(kWabAdaptations.map((a) => a.code).toSet().length, 6);
      expect(kWabAdaptations.first.code, 'english');
      for (final a in kWabAdaptations) {
        expect(a.citation, isNotEmpty);
        expect(a.resultLine, '${a.shortLabel} · ${a.citation}');
      }
    });

    test('caveat: none for English; own-norms named; generic otherwise', () {
      expect(wabAdaptationCaveat(kWabAdaptations[0]), isNull);
      expect(
        wabAdaptationCaveat(
            kWabAdaptations.firstWhere((a) => a.code == 'kannada')),
        'Severity bands are the Kertesz 1982 (English WAB) reference — '
        'Kannada WAB-K publishes its own normative data; interpret with '
        'that context.',
      );
      expect(
        wabAdaptationCaveat(
            kWabAdaptations.firstWhere((a) => a.code == 'bengali')),
        'Severity bands are the Kertesz 1982 (English WAB) reference — '
        'Bengali B-WAB publishes its own normative data; interpret with '
        'that context.',
      );
      for (final code in ['telugu', 'malayalam', 'hindi']) {
        expect(
          wabAdaptationCaveat(
              kWabAdaptations.firstWhere((a) => a.code == code)),
          'Severity bands are the Kertesz 1982 (English WAB) reference — '
          "interpret against the administered adaptation's norms.",
          reason: 'generic reference caveat expected for $code',
        );
      }
    });

    testWidgets('the selection is explicit from the first frame',
        (tester) async {
      await tester.pumpWidget(_host());
      await tester.pumpAndSettle();
      expect(find.text('English (WAB / WAB-R)'), findsOneWidget);
    });

    testWidgets(
        'same subscores → same AQ, same band, same math, Kertesz-reference '
        'tag, correct detail + caveat — in EVERY adaptation', (tester) async {
      await tester.pumpWidget(_host());
      await tester.pumpAndSettle();
      await _enterExampleScores(tester);

      for (final a in kWabAdaptations) {
        await _selectAdaptation(tester, a.label);

        // The arithmetic is language-independent — identical everywhere.
        expect(find.text('67.0'), findsOneWidget,
            reason: 'AQ must not change for ${a.code}');
        expect(find.text('Moderate'), findsOneWidget,
            reason: 'band must not change for ${a.code}');
        expect(find.text('(14 + 7.5 + 6.2 + 5.8) × 2 = 67.0'), findsOneWidget,
            reason: 'math must not change for ${a.code}');
        expect(find.text('per Kertesz 1982'), findsOneWidget,
            reason: 'formula citation must not change for ${a.code}');

        // The band is the Kertesz REFERENCE in every language — never
        // relabeled as the adaptation's own validated cutoff.
        expect(find.text(kWabBandReferenceNote), findsOneWidget,
            reason: 'band provenance must show for ${a.code}');

        // The administered instrument is recorded, cited.
        expect(find.text(a.resultLine), findsOneWidget,
            reason: 'detail line wrong for ${a.code}');

        // The caveat tracks the adaptation honestly.
        final caveat = wabAdaptationCaveat(a);
        if (caveat == null) {
          expect(find.textContaining('Severity bands are'), findsNothing,
              reason: 'English carries no caveat');
        } else {
          expect(find.text(caveat), findsOneWidget,
              reason: 'caveat wrong for ${a.code}');
        }

        // §5: no inferential language in any selected-language state.
        expectNoInferentialLanguage(tester);
      }
    });

    testWidgets('switching adaptation while waiting changes no waiting text',
        (tester) async {
      await tester.pumpWidget(_host());
      await tester.pumpAndSettle();
      await _enter(tester, 0, '14');

      await _selectAdaptation(tester, 'Telugu');
      expect(find.text('insufficient data'), findsOneWidget);
      expect(find.text('3 more subscores needed'), findsOneWidget);
      // No caveat, no detail line in the waiting state — there is no number
      // to contextualize yet.
      expect(find.textContaining('Severity bands are'), findsNothing);
      expect(find.text('Telugu WAB · Pallavi 2010'), findsNothing);
      expectNoInferentialLanguage(tester);
    });
  });
}
