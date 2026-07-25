// test/services/ped_language_seed_rows_test.dart
//
// Task 3 — provenance stamping at seed time. seedRowsFor is the pure
// static producing exactly the row set _seedBand inserts, so this test
// pins the contract without a Supabase client: every seeded row carries
// norm_reference (the dataset's source sentence verbatim) and
// library_version (the loud-fail-parsed dataset version), alongside the
// existing milestone-text snapshot. The DB half of the contract — NOT
// NULL, no default, so a row cannot be inserted without them — lives in
// migration 20260725105832 and was proven by sandbox round-trip
// (23502 on a provenance-less insert).

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:cue/models/asha_milestone_library.dart';
import 'package:cue/services/ped_language_assessment_service.dart';

void main() {
  late AshaMilestoneLibrary lib;

  setUpAll(() {
    lib = AshaMilestoneLibrary.fromJsonString(
        File('assets/data/asha_language_milestones_0_5.json')
            .readAsStringSync());
  });

  test('every seeded row carries both provenance fields, every band', () {
    for (final band in lib.bands) {
      final rows =
          PedLanguageAssessmentService.seedRowsFor('fake-id', band, lib);
      expect(rows.length, band.milestoneCount,
          reason: '${band.bandId} row count');
      for (final row in rows) {
        expect(row['norm_reference'], lib.source,
            reason: '${band.bandId} norm_reference');
        expect(row['library_version'], lib.version,
            reason: '${band.bandId} library_version');
      }
    }
  });

  test('seeded rows still snapshot the dataset text and identity', () {
    final band = lib.bandById('2_to_3y')!;
    final rows =
        PedLanguageAssessmentService.seedRowsFor('fake-id', band, lib);
    final first = rows.first;
    expect(first['ped_language_assessment_id'], 'fake-id');
    expect(first['section'], 'speech');
    expect(first['milestone_order'], 1);
    expect(first['milestone_text'],
        band.sections['speech']!.first.milestone);
    expect(first['example_text'], band.sections['speech']!.first.example);
  });

  test('provenance values are non-empty (belt for the NOT NULL braces)', () {
    expect(lib.source.trim(), isNotEmpty);
    expect(lib.version.trim(), isNotEmpty);
  });
}
