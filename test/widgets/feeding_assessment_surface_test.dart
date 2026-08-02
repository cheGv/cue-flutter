// test/widgets/feeding_assessment_surface_test.dart
//
// Headless render proof for the feeding surface (the SSD widget-test
// convention): the three capture layers render without exception, and the
// swallow off-ramp is SIGN-TRIGGERED (clinician sign-off 2026-06-11):
//   * it does NOT fire on age alone — an 18mo+ age band with no airway sign
//     marked shows NO card (no crying wolf on typically developing
//     toddlers, which would train the safety channel to be dismissed);
//   * it DOES fire when an airway-sign behaviour is marked present, at ANY
//     age (proven here at 8 months — well below the old 18mo line);
//   * the DORMANT onOpenSwallow seam renders caution text with NO dead
//     button; a wired seam shows the handoff button and fires it.
// Uses an in-memory fake service (no network).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:cue/services/feeding_assessment_service.dart';
import 'package:cue/widgets/assessment/feeding_assessment_surface.dart';

/// The sole off-ramp trigger: the airway-sign starter behaviour, marked
/// present.
const Map<String, dynamic> _kAirwayMarkedPresent = {
  'id': 'b-airway',
  'behavior_key': 'airway_signs_textured',
  'behavior_label':
      'Coughing, choking, or wet-sounding voice with textured food',
  'airway_sign': true,
  'status': 'present',
};

class _FakeFeedingService implements FeedingAssessmentService {
  _FakeFeedingService({this.ageMonths, this.behaviorRows = const []});

  final int? ageMonths;
  final List<Map<String, dynamic>> behaviorRows;

  /// Stateful ladder storage: since the ensureLadderBands deletion, the
  /// sectional store seeds via insertRow and re-loads via loadRows —
  /// the fake must remember what was seeded, like the DB does.
  final List<Map<String, dynamic>> _ladderRows = [];
  int _nextId = 0;

  @override
  Future<Map<String, dynamic>> loadOrCreate({required String clientId}) async =>
      {
        'id': 'fake-1',
        'client_id': clientId,
        'age_months': ageMonths,
        // Every other clinical column null — empty stays empty; the surface
        // must render entirely unmarked.
      };

  @override
  Future<List<Map<String, dynamic>>> loadRows(String table, String assessmentId,
          {String orderBy = 'created_at', bool ascending = true}) async =>
      table == 'feeding_behaviors'
          ? [for (final r in behaviorRows) Map<String, dynamic>.from(r)]
          : List.of(_ladderRows);

  @override
  Future<void> saveAssessmentColumns(
      {required String assessmentId, required Map<String, dynamic> data}) async {}
  @override
  Future<String> insertRow(
      {required String table,
      required String assessmentId,
      required Map<String, dynamic> data}) async {
    final id = 'row-${_nextId++}';
    if (table == 'feeding_ladder_bands') {
      _ladderRows.add({'id': id, ...data, 'clinician_marking': null, 'notes': null});
    }
    return id;
  }
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
      'three layers render; off-ramp does NOT fire on age alone (18mo+ band, no sign marked)',
      (tester) async {
    await tester.pumpWidget(_host(FeedingAssessmentSurface(
      clientId: 'client-x',
      // 18–24mo band — under the old age trigger this fired the card.
      service: _FakeFeedingService(ageMonths: 20),
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

    // SIGN-TRIGGERED: age alone must NOT raise the off-ramp.
    expect(find.text('Airway sign marked — swallow assessment warranted'),
        findsNothing);
    expect(find.textContaining('treat this flag as the referral cue'),
        findsNothing);

    // The ladder still surfaces the age-matched band with its guidance
    // (the in-band airway WATCH-FOR text is guidance, not the trigger).
    await tester.ensureVisible(
        find.text('SECTION 2 — DEVELOPMENTAL FEEDING LADDER'));
    await tester.tap(find.text('SECTION 2 — DEVELOPMENTAL FEEDING LADDER'));
    await tester.pumpAndSettle();
    expect(find.text("THIS CHILD'S AGE BAND"), findsOneWidget);
    expect(find.text('18–24 months'), findsOneWidget);
    expect(find.text('WATCH FOR'), findsOneWidget); // matched band's prompt
    expect(find.textContaining('Western cohorts'), findsOneWidget);

    // The behaviours layer: starter chips render.
    await tester.ensureVisible(find.text('SECTION 3 — FEEDING BEHAVIOURS'));
    await tester.tap(find.text('SECTION 3 — FEEDING BEHAVIOURS'));
    await tester.pumpAndSettle();
    expect(find.text('Pocketing'), findsOneWidget);
    expect(find.text('Coughing / choking / wet voice'), findsOneWidget);
  });

  testWidgets(
      'off-ramp fires on a marked airway sign at ANY age; dormant seam = caution text, no button',
      (tester) async {
    await tester.pumpWidget(_host(FeedingAssessmentSurface(
      clientId: 'client-x',
      // 6–9mo band — well below the old 18mo line: the sign is the trigger.
      service: _FakeFeedingService(
          ageMonths: 8, behaviorRows: const [_kAirwayMarkedPresent]),
      // onOpenSwallow deliberately omitted — the Phase 1 dormant state.
    )));
    await tester.pumpAndSettle();

    expect(find.text('Airway sign marked — swallow assessment warranted'),
        findsOneWidget);
    expect(find.textContaining('marked present'), findsOneWidget);
    expect(find.textContaining('treat this flag as the referral cue'),
        findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Open swallow assessment'),
        findsNothing);
  });

  testWidgets('wired seam: the handoff button appears and fires',
      (tester) async {
    var handoffTapped = false;

    await tester.pumpWidget(_host(FeedingAssessmentSurface(
      clientId: 'client-x',
      service: _FakeFeedingService(
          ageMonths: 8, behaviorRows: const [_kAirwayMarkedPresent]),
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
