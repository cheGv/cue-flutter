// test/services/ped_language_age_derivation_test.dart
//
// Task 4 — the derived age band is visible and auditable. Two pure
// contracts under test, no Supabase client needed:
//   1. PedLanguageAssessmentService.resolveAge — exactly what gets
//      persisted as derived_age_months / age_source on both paths
//      (DOB exact; stated years -> midpoint under the honest name).
//   2. pedLanguageAgeDerivationLine — the capture-surface header line,
//      rendered verbatim from the same stored values.
// The no-age / future-DOB / over-60-month states stay as launched;
// resolveAge's blocked states are pinned here too so the remodel
// cannot have moved them.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:cue/models/asha_milestone_library.dart';
import 'package:cue/services/ped_language_assessment_service.dart';
import 'package:cue/widgets/assessment/ped_language_capture_surface.dart';

void main() {
  // Fixed clock: derivation must be deterministic under test.
  final now = DateTime(2026, 7, 25);

  late AshaMilestoneLibrary lib;

  setUpAll(() {
    lib = AshaMilestoneLibrary.fromJsonString(
        File('assets/data/asha_language_milestones_0_5.json')
            .readAsStringSync());
  });

  group('resolveAge — the persisted derivation', () {
    test('dob path writes exact full months and age_source dob', () {
      final r = PedLanguageAssessmentService.resolveAge(
          dobIso: '2023-09-10', statedYears: null, now: now);
      expect(r.state, PedLanguageBootstrapState.ready);
      expect(r.ageMonths, 34); // 2023-09-10 -> 2026-07-25 = 34 full months
      expect(r.ageSource, 'dob');
    });

    test('dob path is day-of-month aware (birthday not yet reached)', () {
      final r = PedLanguageAssessmentService.resolveAge(
          dobIso: '2026-06-30', statedYears: null, now: now);
      expect(r.ageMonths, 0); // the 25th is before the 30th
      expect(r.ageSource, 'dob');
    });

    test('stated-years path writes the midpoint under the honest name', () {
      final r = PedLanguageAssessmentService.resolveAge(
          dobIso: null, statedYears: 3, now: now);
      expect(r.state, PedLanguageBootstrapState.ready);
      expect(r.ageMonths, 42); // 3*12 + 6
      expect(r.ageSource, 'stated_years_midpoint');
    });

    test('dob wins when both are on file', () {
      final r = PedLanguageAssessmentService.resolveAge(
          dobIso: '2023-09-10', statedYears: 4, now: now);
      expect(r.ageMonths, 34);
      expect(r.ageSource, 'dob');
    });

    test('blocked states unchanged: no age, zero-placeholder, future dob',
        () {
      expect(
          PedLanguageAssessmentService.resolveAge(
                  dobIso: null, statedYears: null, now: now)
              .state,
          PedLanguageBootstrapState.noAge);
      expect(
          PedLanguageAssessmentService.resolveAge(
                  dobIso: '', statedYears: 0, now: now)
              .state,
          PedLanguageBootstrapState.noAge);
      final future = PedLanguageAssessmentService.resolveAge(
          dobIso: '2027-01-01', statedYears: null, now: now);
      expect(future.state, PedLanguageBootstrapState.invalidDob);
      expect(future.ageMonths, isNull);
      expect(future.ageSource, isNull);
    });
  });

  group('header line matches the stored derivation', () {
    test('stated-years midpoint names band, stated age, and assumption',
        () {
      expect(
        pedLanguageAgeDerivationLine(
          band: lib.bandById('3_to_4y')!,
          derivedAgeMonths: 42,
          ageSource: 'stated_years_midpoint',
        ),
        'Band 37–48 m · from stated age 3 y, assumed 42 m',
      );
    });

    test('dob states the exact age', () {
      expect(
        pedLanguageAgeDerivationLine(
          band: lib.bandById('2_to_3y')!,
          derivedAgeMonths: 34,
          ageSource: 'dob',
        ),
        'Band 25–36 m · exact age 2 y 10 m from date of birth',
      );
    });

    test('exact-year and under-1 ages collapse cleanly', () {
      expect(
        pedLanguageAgeDerivationLine(
          band: lib.bandById('19_to_24m')!,
          derivedAgeMonths: 24,
          ageSource: 'dob',
        ),
        'Band 19–24 m · exact age 2 y from date of birth',
      );
      expect(
        pedLanguageAgeDerivationLine(
          band: lib.bandById('birth_to_1y')!,
          derivedAgeMonths: 6,
          ageSource: 'dob',
        ),
        'Band 0–12 m · exact age 6 m from date of birth',
      );
    });

    test('stated years reconstructed from stored months round-trips for '
        'every plausible stated age', () {
      for (var years = 1; years <= 4; years++) {
        final months = years * 12 + 6;
        final band = lib.bandForAgeMonths(months)!;
        final line = pedLanguageAgeDerivationLine(
          band: band,
          derivedAgeMonths: months,
          ageSource: 'stated_years_midpoint',
        );
        expect(line, contains('from stated age $years y'),
            reason: 'stated $years y');
        expect(line, contains('assumed $months m'),
            reason: 'stated $years y');
      }
    });
  });
}
