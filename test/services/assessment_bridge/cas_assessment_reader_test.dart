// test/services/assessment_bridge/cas_assessment_reader_test.dart
//
// VERIFICATION GATE for Step 1 of the assessment data bridge (the CAS reader).
//
// The fixtures below are the TWO REAL captured CAS assessments from the sandbox
// (uuqhusmgoiaxdvtgbmwh), fetched verbatim 2026-05-31 — NOT synthetic. Per the
// audit lesson (synthetic fixtures miss the safety bugs that matter), the gate
// runs the reader against real data and asserts the anti-fabrication boundary:
//   * CAS #1 (everything null)         -> ZERO findings, ZERO measures.
//   * CAS #2 (markers present/emerging/absent; notes ""; rest null)
//                                       -> EXACTLY the 3 marker findings
//                                          (incl. "absent"); "" notes and null
//                                          fields emit NOTHING; plus the real
//                                          DDK + length-gradient measures.

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cue/models/assessment_envelope.dart';
import 'package:cue/services/assessment_bridge/cas_assessment_reader.dart';

void main() {
  final reader = CasAssessmentReader();

  // ── CAS #1 — client da79d397 — created, NOTHING entered (all columns null) ──
  final cas1 = <String, dynamic>{
    'id': '647193c9-3917-407e-bfe3-9f7bb2a0c413',
    'client_id': 'da79d397-9e7c-4ae9-85eb-573462329b83',
    'clinician_id': '71a7bc1f-5a9d-4964-bc96-1b99a58f4a35',
    'marker_inconsistent_errors': null,
    'marker_disrupted_transitions': null,
    'marker_inappropriate_prosody': null,
    'marker_inconsistent_notes': null,
    'marker_transitions_notes': null,
    'marker_prosody_notes': null,
    'oral_mech_exam': null,
    'groping_searching': null,
    'vowel_errors': null,
    'receptive_expressive_gap': null,
    'consonant_inventory': null,
    'vowel_inventory': null,
    'syllable_shape_inventory': null,
    'age_months': null,
    'capture_notes': null,
  };
  final cas1Ddk = <Map<String, dynamic>>[
    {'id': 'd91a371c-a8f2-4981-b9eb-64b2bc053577', 'task': 'pa', 'rate_syl_per_sec': null, 'sequence_order_errors': false, 'method': null, 'notes': null},
    {'id': '886038c5-681d-4817-a9c9-3aebfba72b2b', 'task': 'ta', 'rate_syl_per_sec': null, 'sequence_order_errors': false, 'method': null, 'notes': null},
    {'id': 'b17235b1-626c-4953-9504-885778e3ec7c', 'task': 'ka', 'rate_syl_per_sec': null, 'sequence_order_errors': false, 'method': null, 'notes': null},
    {'id': 'fe2bce29-a9d2-4da7-af52-17a2a1e028a2', 'task': 'pataka', 'rate_syl_per_sec': null, 'sequence_order_errors': false, 'method': null, 'notes': null},
  ];
  final cas1Len = <Map<String, dynamic>>[
    {'id': '281b198f-c64e-48cf-908c-75cfaa471672', 'level_label': 'CV', 'level_order': 1, 'example_tokens': 'ba, mu', 'accuracy': null, 'notes': null},
    {'id': '1a57a083-73dd-48c9-b910-63e5611ea2e3', 'level_label': 'CVC', 'level_order': 2, 'example_tokens': 'cup, dog', 'accuracy': null, 'notes': null},
    {'id': '03ab2f10-4d46-48bb-bc9f-745ed727c498', 'level_label': 'bisyllabic', 'level_order': 3, 'example_tokens': 'baby, water', 'accuracy': null, 'notes': null},
    {'id': '898ba06b-f7e3-413e-b4cb-8a398eb2de3d', 'level_label': 'trisyllabic', 'level_order': 4, 'example_tokens': 'banana', 'accuracy': null, 'notes': null},
    {'id': '714602d8-badc-4e3d-9987-cf4f627715d6', 'level_label': 'polysyllabic_phrase', 'level_order': 5, 'example_tokens': 'butterfly, "I want more"', 'accuracy': null, 'notes': null},
  ];

  // ── CAS #2 — client a8343837 — markers filled; notes ""; everything else null ──
  final cas2 = <String, dynamic>{
    'id': '676d24d0-16c6-4470-950b-59ed723205d4',
    'client_id': 'a8343837-492b-4412-9369-ddd730c356b6',
    'clinician_id': '71a7bc1f-5a9d-4964-bc96-1b99a58f4a35',
    'marker_inconsistent_errors': 'present',
    'marker_disrupted_transitions': 'emerging',
    'marker_inappropriate_prosody': 'absent', // a REAL finding — must survive
    'marker_inconsistent_notes': '', // explicit blank -> nothing
    'marker_transitions_notes': '', // explicit blank -> nothing
    'marker_prosody_notes': '', // explicit blank -> nothing
    'oral_mech_exam': null,
    'groping_searching': null,
    'vowel_errors': null,
    'receptive_expressive_gap': null,
    'consonant_inventory': null,
    'vowel_inventory': null,
    'syllable_shape_inventory': null,
    'age_months': null,
    'capture_notes': null,
  };
  // numeric(4,2) serialises as the string "2.00" over the wire — kept verbatim.
  final cas2Ddk = <Map<String, dynamic>>[
    {'id': '4896dcbc-b761-4898-bd4d-7382fb6ad9a2', 'task': 'pa', 'rate_syl_per_sec': '2.00', 'sequence_order_errors': false, 'method': null, 'notes': null},
    {'id': '6ccf6047-176d-42bd-bf7a-d4272d7e1e96', 'task': 'ta', 'rate_syl_per_sec': '2.00', 'sequence_order_errors': false, 'method': null, 'notes': null},
    {'id': '8d352483-0ac0-4671-b615-df4a46131696', 'task': 'ka', 'rate_syl_per_sec': '2.00', 'sequence_order_errors': false, 'method': null, 'notes': null},
    {'id': '904fbde7-b0a1-40bb-a7d5-ce170d781ed7', 'task': 'pataka', 'rate_syl_per_sec': '2.00', 'sequence_order_errors': true, 'method': null, 'notes': null},
  ];
  final cas2Len = <Map<String, dynamic>>[
    {'id': '68bf23c4-de16-41e7-a25c-b466544d9cc9', 'level_label': 'CV', 'level_order': 1, 'example_tokens': 'ba, mu', 'accuracy': 'partial', 'notes': null},
    {'id': 'a6cf15e8-347f-43ce-ab1d-c08406671e2f', 'level_label': 'CVC', 'level_order': 2, 'example_tokens': 'cup, dog', 'accuracy': 'inaccurate', 'notes': null},
    {'id': 'a0d97a45-5cf6-48fb-9f0d-d7f1bc2e1eba', 'level_label': 'bisyllabic', 'level_order': 3, 'example_tokens': 'baby, water', 'accuracy': 'inaccurate', 'notes': null},
    {'id': '32132178-64c4-4153-965f-50aca60ca41c', 'level_label': 'trisyllabic', 'level_order': 4, 'example_tokens': 'banana', 'accuracy': 'inaccurate', 'notes': null},
    {'id': 'fce68e28-7a63-4031-beb2-96fa9176067a', 'level_label': 'polysyllabic_phrase', 'level_order': 5, 'example_tokens': 'butterfly, "I want more"', 'accuracy': 'inaccurate', 'notes': null},
  ];

  test('GATE — CAS #1 (all null): ZERO findings, ZERO measures', () {
    final env = reader.read(assessment: cas1, ddkRows: cas1Ddk, lengthRows: cas1Len);
    _dump('CAS #1 (647193c9 — nothing entered)', env);

    expect(env.findings, isEmpty, reason: 'an all-null assessment must produce no findings');
    expect(env.measures, isEmpty, reason: 'null DDK rates / null accuracies must produce no measures');
  });

  test('GATE — CAS #2: EXACTLY 3 marker findings incl "absent"; no blanks; no nulls; real measures', () {
    final env = reader.read(assessment: cas2, ddkRows: cas2Ddk, lengthRows: cas2Len);
    _dump('CAS #2 (676d24d0 — markers filled)', env);

    // field -> value, keyed by the last path segment of source_id
    final byField = {for (final f in env.findings) f.sourceId.split('/').last: f.value};

    // exactly the three markers, nothing else
    expect(env.findings.length, 3, reason: 'only the 3 filled markers are findings');
    expect(byField['marker_inconsistent_errors'], 'present');
    expect(byField['marker_disrupted_transitions'], 'emerging');
    expect(byField['marker_inappropriate_prosody'], 'absent'); // MUST be present

    // the three "" notes must NOT become findings (explicit blank = nothing)
    for (final blankCol in ['marker_inconsistent_notes', 'marker_transitions_notes', 'marker_prosody_notes']) {
      expect(byField.containsKey(blankCol), isFalse, reason: '$blankCol is "" and must NOT be a finding');
    }
    // every null field must NOT become a finding
    for (final nullCol in [
      'oral_mech_exam', 'groping_searching', 'vowel_errors', 'receptive_expressive_gap',
      'consonant_inventory', 'vowel_inventory', 'syllable_shape_inventory', 'age_months', 'capture_notes',
    ]) {
      expect(byField.containsKey(nullCol), isFalse, reason: '$nullCol is null and must NOT be a finding');
    }

    // real child measures: 4 DDK rates + 5 length accuracies = 9
    expect(env.measures.length, 9, reason: '4 filled DDK rates + 5 filled accuracies');
    expect(env.measures.where((m) => m.group == 'Diadochokinetic rates').length, 4);
    expect(env.measures.where((m) => m.group == 'Length gradient').length, 5);

    // sequence_order_errors is excluded (DB-default-false ambiguity) — even the
    // genuine pataka=true is NOT emitted in Step 1 (flagged for a later step)
    expect(env.measures.any((m) => m.sourceId.contains('sequence_order_errors')), isFalse);
  });
}

// Prints the reader's output so the gate is visible to the eye in `flutter test`.
void _dump(String label, AssessmentEnvelope env) {
  final b = StringBuffer()
    ..writeln('\n──────────────────────────────────────────────')
    ..writeln('READER OUTPUT — $label')
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
