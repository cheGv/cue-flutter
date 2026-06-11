// test/widgets/feeding_assessment_surface_test.dart
//
// Headless render proof for the feeding surface (the SSD widget-test
// convention): the three capture layers render without exception, the
// swallow off-ramp appears for an 18mo+ age band, the DORMANT onOpenSwallow
// seam renders caution text with NO dead button — and, when a host wires the
// seam, the handoff button appears and fires. Uses an in-memory fake service
// (no network) with age_months = 20, which lands in the 18–24mo off-ramp band.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:cue/constants/feeding_ladder_content.dart';
import 'package:cue/services/feeding_assessment_service.dart';
import 'package:cue/widgets/assessment/feeding_assessment_surface.dart';

class _FakeFeedingService implements FeedingAssessmentService {
  @override
  Future<Map<String, dynamic>> loadOrCreate({required String clientId}) async =>
      {
        'id': 'fake-1',
        'client_id': clientId,
        'age_months': 20, // 18–24mo band → off-ramp active by age
        // Every clinical column null — empty stays empty; the surface must
        // render entirely unmarked.
      };

  @override
  Future<List<Map<String, dynamic>>> ensureLadderBands(
          String assessmentId) async =>
      [
        for (final b in kFeedingLadderBands)
          {
            'id': 'band-${b.order}',
            ...FeedingAssessmentService.seedRowFor(b),
            'clinician_marking': null,
            'notes': null,
          },
      ];

  @override
  Future<List<Map<String, dynamic>>> loadRows(String table, String assessmentId,
          {String orderBy = 'created_at', bool ascending = true}) async =>
      [];

  @override
  Future<void> saveAssessmentColumns(
      {required String assessmentId, required Map<String, dynamic> data}) async {}
  @override
  Future<String> insertRow(
          {required String table,
          required String assessmentId,
          required Map<String, dynamic> data}) async =>
      'new-row';
  @override
  Future<void> updateRow(
      {required String table,
      required String rowId,
      required Map<String, dynamic> data}) async {}
  @override
  Future<void> deleteRow({required String table, required String rowId}) async {}
}

Widget _host(FeedingAssessmentSurface surface) => MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: surface)),
    );

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  testWidgets(
      'three layers render; off-ramp shows for 18mo+; dormant seam = caution text, no button',
      (tester) async {
    await tester.pumpWidget(_host(FeedingAssessmentSurface(
      clientId: 'client-x',
      service: _FakeFeedingService(),
      // onOpenSwallow deliberately omitted — the Phase 1 dormant state.
    )));
    await tester.pumpAndSettle();

    // All three capture layers are present.
    expect(find.text('SECTION 1 — ORAL-MOTOR DISSOCIATION'), findsOneWidget);
    expect(
        find.text('SECTION 2 — DEVELOPMENTAL FEEDING LADDER'), findsOneWidget);
    expect(find.text('SECTION 3 — FEEDING BEHAVIOURS'), findsOneWidget);

    // Section 1 opens by default — observable sign primary, term secondary.
    expect(find.text('Jaw stability / grading'), findsOneWidget);
    expect(find.textContaining('Does the jaw stay steady'), findsOneWidget);

    // Off-ramp: active via the 18–24mo age band; dormant seam renders the
    // caution + referral-cue line and NO handoff button.
    expect(find.text('Swallow off-ramp — the boundary of this surface'),
        findsOneWidget);
    expect(find.textContaining('treat this flag as the referral cue'),
        findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Open swallow assessment'),
        findsNothing);

    // The ladder: expand section 2 — the age-matched band auto-expands with
    // the matched pill, the watch-for prompt, and the Western-norm caveat.
    await tester.ensureVisible(
        find.text('SECTION 2 — DEVELOPMENTAL FEEDING LADDER'));
    await tester.tap(find.text('SECTION 2 — DEVELOPMENTAL FEEDING LADDER'));
    await tester.pumpAndSettle();
    expect(find.text("THIS CHILD'S AGE BAND"), findsOneWidget);
    expect(find.text('18–24 months'), findsOneWidget);
    expect(find.text('WATCH FOR'), findsOneWidget); // matched band's prompt
    expect(find.textContaining('Western cohorts'), findsOneWidget);

    // The behaviours layer: expand section 3 — starter chips render.
    await tester
        .ensureVisible(find.text('SECTION 3 — FEEDING BEHAVIOURS'));
    await tester.tap(find.text('SECTION 3 — FEEDING BEHAVIOURS'));
    await tester.pumpAndSettle();
    expect(find.text('Pocketing'), findsOneWidget);
    expect(find.text('Coughing / choking / wet voice'), findsOneWidget);
  });

  testWidgets('wired seam: the handoff button appears and fires',
      (tester) async {
    var handoffTapped = false;

    await tester.pumpWidget(_host(FeedingAssessmentSurface(
      clientId: 'client-x',
      service: _FakeFeedingService(),
      onOpenSwallow: () => handoffTapped = true,
    )));
    await tester.pumpAndSettle();

    final btn = find.widgetWithText(FilledButton, 'Open swallow assessment');
    expect(btn, findsOneWidget);
    await tester.ensureVisible(btn);
    await tester.tap(btn);
    await tester.pump();
    expect(handoffTapped, isTrue);
  });
}
