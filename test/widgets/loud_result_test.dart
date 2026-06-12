// test/widgets/loud_result_test.dart
//
// Intern scaffold Phase A — proof of the LOUD-register component.
//
// Asserts the contract in lib/widgets/assessment/loud_result.dart: the three
// honest states render correctly, the math line is verbatim, selective
// loudness ("no published band") works, the insufficient state names what's
// missing factually, the resolved state announces by APPEARING (a cross-fade
// event, not a grey line filling), the amber norming caveat renders with the
// resolved card only, the resolved card carries NO boundary-reassurance text
// (cut 2026-06-12 — the restraint is the boundary, it isn't announced) — and
// THE BOUNDARY: a forbidden-language sweep over every rendered string makes
// inferential output (indicates / consider / leans toward / you should /
// typically / prognosis…) unrepresentable in a passing build.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:cue/widgets/assessment/loud_result.dart';

// ── Boundary suite — the RED column as literal assertions ──────────────────
// Word-bounded, case-insensitive. The component's own chrome (plus realistic
// caller strings) must never match: a formula has one answer; an inference is
// a choice, and choices are the clinician's.
final List<RegExp> kForbiddenInference = [
  RegExp(r'\bindicat(es|ed|ing|ion|ive)\b', caseSensitive: false),
  RegExp(r'\bsuggest(s|ed|ing|ion|ive)?\b', caseSensitive: false),
  RegExp(r'\bconsider\b', caseSensitive: false),
  RegExp(r'\blean(s|ing)?\s+toward', caseSensitive: false),
  RegExp(r'\bthis child has\b', caseSensitive: false),
  RegExp(r'\byou should\b', caseSensitive: false),
  RegExp(r'\brecommend', caseSensitive: false),
  RegExp(r'\btypically\b', caseSensitive: false),
  RegExp(r'\bcatch up\b', caseSensitive: false),
  RegExp(r'\bprognosis\b', caseSensitive: false),
  RegExp(r'\blikel(y|ihood)\b', caseSensitive: false),
  RegExp(r'requiring intervention', caseSensitive: false),
  RegExp(r'\bdiagnos(is|es|ed|tic)\b', caseSensitive: false),
];

Iterable<String> _allRenderedText(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .map((t) => t.data ?? t.textSpan?.toPlainText() ?? '');

void _expectNoInferentialLanguage(WidgetTester tester) {
  for (final text in _allRenderedText(tester)) {
    for (final pattern in kForbiddenInference) {
      expect(pattern.hasMatch(text), isFalse,
          reason: 'forbidden inferential language "$pattern" in: "$text"');
    }
  }
}

Widget _host(Widget child) => MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: Padding(padding: const EdgeInsets.all(16), child: child),
        ),
      ),
    );

// A resolved AQ-shaped state — band variant.
const _resolvedWithBand = LoudResultResolved(
  value: '67.0',
  band: 'Moderate',
  math: '(14 + 7.5 + 6.2 + 5.8) × 2 = 67.0',
  citation: 'Kertesz 1982',
);

// A resolved PCC-R-shaped state — no published band.
const _resolvedNoBand = LoudResultResolved(
  value: '52.3%',
  math: '(33 + 11) ÷ 84 × 100 = 52.3%',
  citation: 'Shriberg & Kwiatkowski 1982',
);

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  group('state model', () {
    test('blank essentials cannot construct — guards throw', () {
      final blank = ''; // runtime value: asserts fire, not const evaluation
      expect(() => LoudResultResolved(value: blank, math: 'x', citation: 'c'),
          throwsAssertionError);
      expect(() => LoudResultResolved(value: '67.0', math: blank, citation: 'c'),
          throwsAssertionError);
      expect(() => LoudResultResolved(value: '67.0', math: 'x', citation: blank),
          throwsAssertionError);
      expect(() => LoudResultResolved(
            value: '67.0', math: 'x', citation: 'c', band: blank),
          throwsAssertionError);
      expect(() => LoudResultInsufficient(missing: blank), throwsAssertionError);
    });
  });

  group('empty state', () {
    testWidgets('renders nothing — never a fabricated zero', (tester) async {
      await tester.pumpWidget(_host(const LoudResult(
        label: 'Aphasia Quotient',
        state: LoudResultEmpty(),
      )));
      await tester.pumpAndSettle();

      expect(find.byType(Text), findsNothing);
      expect(find.text('Aphasia Quotient'), findsNothing);
      expect(find.text('insufficient data'), findsNothing);
    });
  });

  group('insufficient state', () {
    testWidgets('calm and factual: label + insufficient data + what is missing',
        (tester) async {
      await tester.pumpWidget(_host(const LoudResult(
        label: 'Aphasia Quotient',
        state: LoudResultInsufficient(missing: '2 more subscores needed'),
      )));
      await tester.pumpAndSettle();

      expect(find.text('Aphasia Quotient'), findsOneWidget);
      expect(find.text('insufficient data'), findsOneWidget);
      expect(find.text('2 more subscores needed'), findsOneWidget);
      _expectNoInferentialLanguage(tester);
    });

    testWidgets('NOT loud: no card register, nothing at announcement size',
        (tester) async {
      await tester.pumpWidget(_host(const LoudResult(
        label: 'Aphasia Quotient',
        state: LoudResultInsufficient(missing: '2 more subscores needed'),
      )));
      await tester.pumpAndSettle();

      // No mono data-tag eyebrow (that register belongs to the resolved card).
      expect(find.text('APHASIA QUOTIENT'), findsNothing);
      // Nothing rendered at announcement size.
      final loud = tester
          .widgetList<Text>(find.byType(Text))
          .any((t) => (t.style?.fontSize ?? 0) >= 20);
      expect(loud, isFalse, reason: 'insufficient must stay recessive');
    });
  });

  group('resolved state', () {
    testWidgets('announces: value large, band, math verbatim, citation — '
        'and nothing else', (tester) async {
      await tester.pumpWidget(_host(const LoudResult(
        label: 'Aphasia Quotient',
        state: _resolvedWithBand,
      )));
      await tester.pumpAndSettle();

      // The data-tag eyebrow.
      expect(find.text('APHASIA QUOTIENT'), findsOneWidget);
      // Value is the largest thing in the component (Rule 7).
      final valueText = tester.widget<Text>(find.text('67.0'));
      final maxOther = tester
          .widgetList<Text>(find.byType(Text))
          .where((t) => t.data != '67.0')
          .map((t) => t.style?.fontSize ?? 0)
          .reduce((a, b) => a > b ? a : b);
      expect(valueText.style!.fontSize!, greaterThan(maxOther));
      // Band, math (verbatim), citation.
      expect(find.text('Moderate'), findsOneWidget);
      expect(find.text('(14 + 7.5 + 6.2 + 5.8) × 2 = 67.0'), findsOneWidget);
      expect(find.text('per Kertesz 1982'), findsOneWidget);
      // NO boundary-reassurance text (cut 2026-06-12) — the clinician knows
      // the interpretation is hers; the restraint is the boundary.
      expect(find.textContaining('yours'), findsNothing);
      expect(find.textContaining("Cue's"), findsNothing);
      expect(find.textContaining('interpretation governs'), findsNothing);
      expect(find.textContaining('Computed from'), findsNothing);
      _expectNoInferentialLanguage(tester);
    });

    testWidgets('math line renders verbatim — no reformatting', (tester) async {
      const oddMath = '0.473 × (12 − 3) + 7 = 11.257   [unrounded]';
      await tester.pumpWidget(_host(const LoudResult(
        label: 'Index',
        state: LoudResultResolved(
          value: '11.257',
          band: 'n/a band label',
          math: oddMath,
          citation: 'Author 2001',
        ),
      )));
      await tester.pumpAndSettle();
      expect(find.text(oddMath), findsOneWidget);
    });

    testWidgets('value without band: number shown, "no published band" explicit',
        (tester) async {
      await tester.pumpWidget(_host(const LoudResult(
        label: 'PCC-R',
        state: _resolvedNoBand,
      )));
      await tester.pumpAndSettle();

      expect(find.text('52.3%'), findsOneWidget);
      expect(find.text('no published band'), findsOneWidget);
      _expectNoInferentialLanguage(tester);
    });
  });

  group('caution register', () {
    const caveat = 'English-normed reference — interpret with caution for '
        'non-English samples.';

    testWidgets('renders below the resolved card when provided',
        (tester) async {
      await tester.pumpWidget(_host(const LoudResult(
        label: 'PCC',
        state: _resolvedNoBand,
        caution: caveat,
      )));
      await tester.pumpAndSettle();
      expect(find.text(caveat), findsOneWidget);
      _expectNoInferentialLanguage(tester);
    });

    testWidgets('never renders in the waiting states', (tester) async {
      await tester.pumpWidget(_host(const LoudResult(
        label: 'PCC',
        state: LoudResultInsufficient(missing: 'consonant counts needed'),
        caution: caveat,
      )));
      await tester.pumpAndSettle();
      expect(find.text(caveat), findsNothing);

      await tester.pumpWidget(_host(const LoudResult(
        label: 'PCC',
        state: LoudResultEmpty(),
        caution: caveat,
      )));
      await tester.pumpAndSettle();
      expect(find.text(caveat), findsNothing);
    });
  });

  group('announcement — resolving is an event', () {
    testWidgets('insufficient → resolved cross-fades: both states mid-flight, '
        'card fully landed after', (tester) async {
      await tester.pumpWidget(_host(const LoudResult(
        label: 'Aphasia Quotient',
        state: LoudResultInsufficient(missing: '2 more subscores needed'),
      )));
      await tester.pumpAndSettle();
      expect(find.text('insufficient data'), findsOneWidget);

      await tester.pumpWidget(_host(const LoudResult(
        label: 'Aphasia Quotient',
        state: _resolvedWithBand,
      )));
      // Mid-transition (~100ms of 260ms): the announcement is arriving while
      // the waiting line departs — a state change the eye notices.
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('67.0'), findsOneWidget);
      expect(find.text('insufficient data'), findsOneWidget);
      final fades = tester.widgetList<FadeTransition>(
          find.ancestor(
              of: find.text('67.0'), matching: find.byType(FadeTransition)));
      expect(fades.any((f) => f.opacity.value < 1.0), isTrue,
          reason: 'the resolved card must ARRIVE, not snap');

      // Landed: announcement fully opaque, waiting state gone.
      await tester.pumpAndSettle();
      expect(find.text('67.0'), findsOneWidget);
      expect(find.text('insufficient data'), findsNothing);
    });

    testWidgets('live recompute within resolved updates in place — no re-event',
        (tester) async {
      await tester.pumpWidget(_host(const LoudResult(
        label: 'Aphasia Quotient',
        state: _resolvedWithBand,
      )));
      await tester.pumpAndSettle();

      await tester.pumpWidget(_host(const LoudResult(
        label: 'Aphasia Quotient',
        state: LoudResultResolved(
          value: '69.4',
          band: 'Moderate',
          math: '(15 + 7.5 + 6.4 + 5.8) × 2 = 69.4',
          citation: 'Kertesz 1982',
        ),
      )));
      await tester.pump(const Duration(milliseconds: 16));

      // New value present immediately, fully opaque — no second announcement.
      expect(find.text('69.4'), findsOneWidget);
      expect(find.text('67.0'), findsNothing);
      final fades = tester.widgetList<FadeTransition>(
          find.ancestor(
              of: find.text('69.4'), matching: find.byType(FadeTransition)));
      expect(fades.every((f) => f.opacity.value == 1.0), isTrue,
          reason: 'a keystroke is not an event; the state change is');
    });
  });
}
