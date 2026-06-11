// test/services/feeding_assessment_service_test.dart
//
// Headless proofs for the feeding service + ladder content — everything that
// does NOT need the network. The live save/load path is covered by the gated
// ONLINE round-trip (feeding_sandbox_roundtrip_test.dart), mirroring SSD's
// split between headless logic tests and the sandbox gate.
//
// The load-bearing assertions:
//   * EMPTY STAYS EMPTY — the ladder seed carries structural/reference fields
//     ONLY; clinician_marking / notes are never in the payload, so a freshly
//     seeded band cannot carry a fabricated mark.
//   * The allowlists FAIL LOUDLY — an unknown parent column or child table is
//     an ArgumentError, never a silent no-op.
//   * The seven bands are well-formed: ordered, uniquely keyed, contiguous
//     age windows, off-ramp flags on exactly the 18mo+ bands.

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:cue/constants/feeding_ladder_content.dart';
import 'package:cue/services/feeding_assessment_service.dart';

void main() {
  // A client that never connects — the guards under test throw before any
  // network call, so construction is all these tests need.
  final svc = FeedingAssessmentService.withClient(
      SupabaseClient('http://localhost', 'offline-test-key'));

  group('allowlists fail loudly', () {
    test('saveAssessmentColumns rejects an unknown parent column', () async {
      await expectLater(
        svc.saveAssessmentColumns(
            assessmentId: 'x', data: {'not_a_column': 1}),
        throwsArgumentError,
      );
    });

    test('a known clinical column passes the guard', () {
      expect(
          FeedingAssessmentService.assessmentColumns
              .containsAll(<String>{
            'age_months',
            'jaw_stability',
            'jaw_stability_notes',
            'jaw_lip_dissociation',
            'jaw_tongue_dissociation',
            'lip_control',
            'tongue_control',
            'capture_notes',
          }),
          isTrue);
    });

    test('child-row ops reject an unknown table', () async {
      await expectLater(
          svc.loadRows('ssd_target_sounds', 'x'), throwsArgumentError);
      await expectLater(
          svc.insertRow(table: 'clients', assessmentId: 'x', data: const {}),
          throwsArgumentError);
      await expectLater(
          svc.deleteRow(table: 'feeding_assessments', rowId: 'x'),
          throwsArgumentError);
    });
  });

  group('ladder seed — empty stays empty', () {
    test('seed payload carries structural/reference fields ONLY', () {
      for (final band in kFeedingLadderBands) {
        final seed = FeedingAssessmentService.seedRowFor(band);
        // Never a fabricated clinical value:
        expect(seed.containsKey('clinician_marking'), isFalse,
            reason: 'seed must never pre-mark a band (${band.key})');
        expect(seed.containsKey('notes'), isFalse,
            reason: 'seed must never pre-fill notes (${band.key})');
        // The structural/reference payload is complete:
        expect(seed['band_key'], band.key);
        expect(seed['band_order'], band.order);
        expect(seed['band_label'], band.label);
        expect(seed['age_min_months'], band.ageMinMonths);
        expect(seed['age_max_months'], band.ageMaxMonths);
        expect(seed['expected_texture'], isNotEmpty);
        expect(seed['expected_self_feeding'], isNotEmpty);
        expect(seed['expected_oral_motor'], isNotEmpty);
        expect(seed['red_flag_prompt'], isNotEmpty);
        expect(seed['off_ramp_band'], band.offRampBand);
      }
    });
  });

  group('the seven bands are well-formed', () {
    test('7 bands, ordered 1..7, uniquely keyed', () {
      expect(kFeedingLadderBands, hasLength(7));
      for (var i = 0; i < kFeedingLadderBands.length; i++) {
        expect(kFeedingLadderBands[i].order, i + 1);
      }
      expect(kFeedingLadderBands.map((b) => b.key).toSet(), hasLength(7));
    });

    test('age windows are contiguous; only the last is open-ended', () {
      for (var i = 0; i < kFeedingLadderBands.length - 1; i++) {
        expect(kFeedingLadderBands[i].ageMaxMonths,
            kFeedingLadderBands[i + 1].ageMinMonths,
            reason: 'band ${i + 1} must hand off to band ${i + 2} seamlessly');
      }
      expect(kFeedingLadderBands.last.ageMaxMonths, isNull);
    });

    test('off-ramp flags sit on exactly the 18mo+ bands', () {
      for (final b in kFeedingLadderBands) {
        expect(b.offRampBand, b.ageMinMonths >= 18,
            reason: '${b.key}: off-ramp iff the band starts at 18mo+');
      }
    });

    test('feedingBandForAge resolves matches and boundaries', () {
      expect(feedingBandForAge(null), isNull);
      expect(feedingBandForAge(-1), isNull);
      expect(feedingBandForAge(0)!.key, '0_6mo');
      expect(feedingBandForAge(5)!.key, '0_6mo');
      expect(feedingBandForAge(6)!.key, '6_9mo'); // max is exclusive
      expect(feedingBandForAge(20)!.key, '18_24mo');
      expect(feedingBandForAge(36)!.key, '30_36mo_plus');
      expect(feedingBandForAge(200)!.key, '30_36mo_plus'); // open-ended
    });
  });

  group('starter behaviours', () {
    test('uniquely keyed, labelled, exactly one airway sign', () {
      expect(kFeedingStarterBehaviors.map((b) => b.key).toSet(),
          hasLength(kFeedingStarterBehaviors.length));
      for (final b in kFeedingStarterBehaviors) {
        expect(b.label, isNotEmpty);
        expect(b.chipLabel, isNotEmpty);
      }
      final airway =
          kFeedingStarterBehaviors.where((b) => b.airwaySign).toList();
      expect(airway, hasLength(1),
          reason: 'one overt airway-sign starter keeps the off-ramp trigger '
              'reachable without over-classifying');
      expect(airway.single.key, 'airway_signs_textured');
    });
  });
}
