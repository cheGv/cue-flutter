// test/services/assessment_bridge/feeding_assessment_reader_test.dart
//
// VERIFICATION GATE for the feeding reader — the anti-fabrication boundary,
// mirrored from the SSD / CAS gates. Proves:
//   * FEEDING #1 (null parent + 7 SEEDED-BUT-UNMARKED bands) -> ZERO findings,
//     ZERO measures. This is the feeding-specific trap: every seeded band row
//     arrives FULLY POPULATED with Cue's own reference text (expected_*,
//     red_flag_prompt, band_label) — none of it may ever surface as a finding.
//     The fixtures use the REAL seed payload (FeedingAssessmentService
//     .seedRowFor), so this gate breaks if the seed ever grows a column the
//     reader would leak.
//   * FEEDING #2 (populated) -> values verbatim ("absent" is a real negative
//     finding); the ladder marking carries its band context; airway-sign data
//     carries on BOTH the label tag and the group; untouched rows contribute
//     nothing; a structural sweep proves every child-sourced finding comes
//     from a clinician-touched column; measures stay empty (this surface
//     derives nothing — by design).
//   * FEEDING #3 (structural blanks) -> whitespace / empty strings render
//     NOTHING (the emptiness rule judges the value, not the key).
//
// NOTE: these fixtures are representative (no real captured feeding rows
// exist yet). They get swapped for verbatim sandbox rows once the first real
// feeding case is captured, exactly as the CAS gate did on 2026-05-31.

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cue/constants/feeding_ladder_content.dart';
import 'package:cue/models/assessment_envelope.dart';
import 'package:cue/services/assessment_bridge/feeding_assessment_reader.dart';
import 'package:cue/services/feeding_assessment_service.dart';

void main() {
  final reader = FeedingAssessmentReader();

  Map<String, dynamic> nullParent(String id) => {
        'id': id,
        'client_id': 'client-x',
        'clinician_id': 'clinician-x',
        'age_months': null,
        'jaw_stability': null,
        'jaw_stability_notes': null,
        'jaw_lip_dissociation': null,
        'jaw_lip_dissociation_notes': null,
        'jaw_tongue_dissociation': null,
        'jaw_tongue_dissociation_notes': null,
        'lip_control': null,
        'lip_control_notes': null,
        'tongue_control': null,
        'tongue_control_notes': null,
        'capture_notes': null,
      };

  // Exactly what a freshly seeded DB row looks like: the REAL seed payload
  // (full reference content) + id + untouched clinical columns.
  List<Map<String, dynamic>> seededUnmarkedBands() => [
        for (final b in kFeedingLadderBands)
          {
            'id': 'band-${b.order}',
            ...FeedingAssessmentService.seedRowFor(b),
            'clinician_marking': null,
            'notes': null,
          },
      ];

  test(
      'GATE — FEEDING #1 (null parent + 7 seeded-but-unmarked bands): '
      'ZERO findings, ZERO measures — seeded reference text never leaks', () {
    final env = reader.read(
      assessment: nullParent('feed-1'),
      ladderBands: seededUnmarkedBands(),
    );
    _dump('FEEDING #1 (nothing entered; bands fully seeded)', env);
    expect(env.findings, isEmpty,
        reason: 'Cue-authored band content (expected_*, red_flag_prompt, '
            'band_label, off_ramp_band) must NEVER surface as findings');
    expect(env.measures, isEmpty);
    expect(env.isEmpty, isTrue);
  });

  test(
      'GATE — FEEDING #2 (populated): verbatim values, band context, '
      'airway tag carries, untouched rows silent, no measures', () {
    final parent = nullParent('feed-2')
      ..addAll({
        'age_months': 20,
        'jaw_stability': 'present',
        'tongue_control': 'absent', // a REAL negative finding — must survive
        'jaw_lip_dissociation_notes': 'Lips ride the jaw on cup sips.',
        'capture_notes': 'Observed across one snack and one bottle feed.',
      });

    final bands = seededUnmarkedBands();
    // Mark exactly ONE band (18–24mo); its neighbour stays untouched.
    final band5 = bands.firstWhere((b) => b['band_key'] == '18_24mo');
    band5['clinician_marking'] = 'below_level';
    band5['notes'] = 'Chews with vertical munch only at 20 months.';

    final env = reader.read(
      assessment: parent,
      ladderBands: bands,
      behaviors: [
        {
          'id': 'bh-airway',
          'behavior_key': 'airway_signs_textured',
          'behavior_label':
              'Coughing, choking, or wet-sounding voice with textured food',
          'airway_sign': true,
          'status': 'present',
          'notes': null,
        },
        {
          'id': 'bh-pocketing',
          'behavior_key': 'pocketing',
          'behavior_label':
              'Pocketing — holding food in the cheeks without swallowing',
          'airway_sign': false,
          'status': 'absent', // checked, not observed — a real finding
          'notes': null,
        },
        {
          // Free-typed, never marked — but the clinician wrote notes: the
          // notes carry, the absent status emits nothing.
          'id': 'bh-free',
          'behavior_key': null,
          'behavior_label': 'Turns head away from spoon after two bites',
          'airway_sign': false,
          'status': null,
          'notes': 'Consistent across both observed meals.',
        },
        {
          // Added but never touched — contributes nothing at all.
          'id': 'bh-untouched',
          'behavior_key': 'food_selectivity',
          'behavior_label': 'Food selectivity / narrowing repertoire',
          'airway_sign': false,
          'status': null,
          'notes': null,
        },
      ],
    );
    _dump('FEEDING #2 (populated)', env);

    expect(env.protocol, 'pediatric-feeding');

    // Parent: verbatim values; "absent" survives as a real judgement.
    expect(
        env.findings
            .firstWhere((f) => f.sourceId.endsWith('/jaw_stability'))
            .value,
        'present');
    expect(
        env.findings
            .firstWhere((f) => f.sourceId.endsWith('/tongue_control'))
            .value,
        'absent');
    expect(
        env.findings
            .any((f) => f.sourceId.endsWith('/jaw_lip_dissociation_notes')),
        isTrue);
    expect(
        env.findings.firstWhere((f) => f.sourceId.endsWith('/age_months')).value,
        20);

    // Ladder: the ONE marked band carries marking + notes WITH band context;
    // every other band row is silent.
    final marking = env.findings
        .firstWhere((f) => f.sourceId.endsWith('/clinician_marking'));
    expect(marking.value, 'below_level');
    expect(marking.fieldLabel, contains('18–24 months'));
    expect(marking.sourceTable, 'feeding_ladder_bands');
    final ladderFindings = env.findings
        .where((f) => f.sourceTable == 'feeding_ladder_bands')
        .toList();
    expect(ladderFindings, hasLength(2)); // marking + notes, one band only
    expect(ladderFindings.every((f) => f.sourceId.contains('/band-5/')), isTrue,
        reason: 'untouched bands must contribute nothing');

    // Airway-sign data carries on BOTH the label tag and the group.
    final airway =
        env.findings.firstWhere((f) => f.sourceId == 'feeding_behaviors/bh-airway/status');
    expect(airway.value, 'present');
    expect(airway.fieldLabel, endsWith('(airway sign)'));
    expect(airway.group, 'Feeding behaviours (airway signs)');

    // Non-airway negative finding stays plain — and survives.
    final pocketing = env.findings
        .firstWhere((f) => f.sourceId == 'feeding_behaviors/bh-pocketing/status');
    expect(pocketing.value, 'absent');
    expect(pocketing.fieldLabel, isNot(contains('airway')));
    expect(pocketing.group, 'Feeding behaviours');

    // Free-typed row: notes carry, no status finding; untouched row: nothing.
    expect(
        env.findings.any((f) => f.sourceId == 'feeding_behaviors/bh-free/notes'),
        isTrue);
    expect(
        env.findings.any((f) => f.sourceId == 'feeding_behaviors/bh-free/status'),
        isFalse);
    expect(env.findings.any((f) => f.sourceId.contains('bh-untouched')), isFalse);

    // STRUCTURAL SWEEP — every child-sourced finding comes from a
    // clinician-touched column; no seeded reference column can ever leak.
    const childClinicianColumns = {'clinician_marking', 'notes', 'status'};
    for (final f in env.findings.where(
        (f) => f.sourceTable != 'feeding_assessments')) {
      expect(childClinicianColumns.contains(f.sourceId.split('/').last), isTrue,
          reason: '${f.sourceId} is not a clinician-touched column');
    }

    // This surface derives nothing — measures are empty even on a full capture.
    expect(env.measures, isEmpty,
        reason: 'feeding stores no raw counts and derives no numbers');
  });

  test('GATE — FEEDING #3 (structural blanks): whitespace renders NOTHING',
      () {
    final parent = nullParent('feed-3')
      ..addAll({
        'jaw_stability_notes': '   ', // whitespace = explicit blank
        'capture_notes': '',
      });
    final bands = seededUnmarkedBands();
    bands.first['notes'] = ''; // cleared, never written

    final env = reader.read(
      assessment: parent,
      ladderBands: bands,
      behaviors: [
        {
          'id': 'bh-blank',
          'behavior_key': null,
          'behavior_label': '',
          'airway_sign': false,
          'status': null,
          'notes': '   ',
        },
      ],
    );
    _dump('FEEDING #3 (structural blanks)', env);

    expect(env.findings, isEmpty);
    expect(env.measures, isEmpty);
    expect(env.isEmpty, isTrue);
  });
}

void _dump(String label, AssessmentEnvelope env) {
  final b = StringBuffer()
    ..writeln('\n──────────────────────────────────────────────')
    ..writeln('FEEDING READER OUTPUT — $label')
    ..writeln('protocol=${env.protocol}  assessment_id=${env.assessmentId}')
    ..writeln('FINDINGS (${env.findings.length}):');
  for (final f in env.findings) {
    b.writeln('  • [${f.group}] ${f.fieldLabel} = "${f.value}"   <${f.sourceId}>');
  }
  b.writeln('MEASURES (${env.measures.length}):');
  for (final m in env.measures) {
    b.writeln('  • [${m.group}] ${m.label} = ${m.value}${m.unit != null ? ' ${m.unit}' : ''}   <${m.sourceId}>');
  }
  b.writeln('──────────────────────────────────────────────');
  debugPrint(b.toString());
}
