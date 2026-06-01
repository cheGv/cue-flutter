// test/services/assessment_bridge/assessment_context_assembler_test.dart
//
// VERIFICATION GATE for Step 3 of the assessment data bridge (the assembler).
//
// Runs the REAL readers on the REAL captured rows (CAS #2 676d24d0 and the
// partial "Mythos" voice 592a63f1, both from sandbox uuqhusmgoiaxdvtgbmwh) to
// get their envelopes, then folds each into canonical_data via the assembler,
// and asserts:
//   * the `assessment` block holds EXACTLY the reader's findings + measures,
//     byte-for-byte (every source_id / source_table / field_label / value /
//     group intact) — nothing added, dropped, renamed, or altered;
//   * client_meta is populated (real ClientChartState.toJson() shape);
//   * therapy-only keys are present but EMPTY.
//
// Fixtures are the same verbatim real rows used by the reader gates (Steps 1/2).

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cue/models/assessment_envelope.dart';
import 'package:cue/services/assessment_bridge/assessment_context_assembler.dart';
import 'package:cue/services/assessment_bridge/cas_assessment_reader.dart';
import 'package:cue/services/assessment_bridge/voice_assessment_reader.dart';

void main() {
  final assembler = AssessmentContextAssembler();

  // Real client_chart_state.toJson() shapes (fetched verbatim 2026-06-01).
  final casClientMeta = <String, dynamic>{
    'client_id': 'a8343837-492b-4412-9369-ddd730c356b6',
    'client_name': 'TRIAL RUN — Pediatric CAS (Childhood Apraxia of Speech) · 11:31',
    'age': 0,
    'ltg_count': 0, 'active_stg_count': 0, 'total_session_count': 0,
    'undocumented_session_count': 0, 'caregiver_present': true, 'substrate_cell_count': 0,
  };
  final voiceClientMeta = <String, dynamic>{
    'client_id': '803344ea-c6ce-45f4-bd8e-70fbe4a166c9',
    'client_name': 'Mythos', 'age': 24,
    'ltg_count': 0, 'active_stg_count': 0, 'total_session_count': 0,
    'undocumented_session_count': 0, 'caregiver_present': true, 'substrate_cell_count': 0,
  };

  const therapyKeys = [
    'substrate_cells', 'long_term_goals', 'short_term_goals',
    'sessions', 'citations', 'metrics',
  ];

  // ── CAS #2 — real rows (verbatim from the Step 1 gate) ─────────────────────
  final cas2 = <String, dynamic>{
    'id': '676d24d0-16c6-4470-950b-59ed723205d4',
    'client_id': 'a8343837-492b-4412-9369-ddd730c356b6',
    'clinician_id': '71a7bc1f-5a9d-4964-bc96-1b99a58f4a35',
    'marker_inconsistent_errors': 'present',
    'marker_disrupted_transitions': 'emerging',
    'marker_inappropriate_prosody': 'absent',
    'marker_inconsistent_notes': '', 'marker_transitions_notes': '', 'marker_prosody_notes': '',
    'oral_mech_exam': null, 'groping_searching': null, 'vowel_errors': null,
    'receptive_expressive_gap': null, 'consonant_inventory': null, 'vowel_inventory': null,
    'syllable_shape_inventory': null, 'age_months': null, 'capture_notes': null,
  };
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

  // ── Mythos voice — real partial row (verbatim from the Step 2 gate) ────────
  final mythos = <String, dynamic>{
    'id': '592a63f1-a780-4323-8f8d-181e497511b8',
    'client_id': '803344ea-c6ce-45f4-bd8e-70fbe4a166c9',
    'is_baseline': true, 'rsi_total_score': null, 'voice_use_hours_per_day': null,
    'case_history_payload': <String, dynamic>{
      'rsi': {'mucus': 3, 'total': 26, 'heartburn': 2, 'hoarseness': 4, 'swallowing': 3, 'throat_lump': 2, 'annoying_cough': 2, 'throat_clearing': 5, 'breathing_choking': 2, 'cough_after_eating': 3},
      'voice_use': {'caffeine_cups': null, 'hours_per_day': 6, 'speaking_styles': ['Loud projection'], 'hydration_litres': null, 'microphone_at_work': false, 'voice_rest_periods': ''},
      'onset_pattern': 'Sudden', 'sleep_quality': 'Good', 'allergy_history': 'no',
      'onset_date_or_age': '2 months', 'relieving_factors': 'steam inhalation',
      'psychological_load': '', 'aggravating_factors': 'Throat clearing and coughing',
      'current_medications': 'nil', 'previous_voice_therapy': false,
      'variability_across_day': 'variability reported - excessive use of vocie - the vocie gets feeble and loss.',
      'previous_voice_therapy_text': '', 'previous_laryngeal_surgeries': false,
      'previous_laryngeal_surgeries_text': '',
    },
    'laryngeal_exam_payload': <String, dynamic>{
      'lesions': ['Vocal fold nodules'], 'exam_date': null, 'performed_by': '',
      'glottic_closure': 'Posterior chink', 'additional_notes': '',
      'examination_type': 'Flexible nasendoscopy', 'mucosal_wave_symmetry': 'Symmetric',
      'lesions_location_notes': '', 'mucosal_wave_amplitude': 'Absent',
      'phase_closure_symmetry': 'Asymmetric', 'supraglottic_compression': 'Moderate',
    },
    'functional_voice_payload': <String, dynamic>{},
    'task_based_payload': <String, dynamic>{},
    'special_populations_payload': <String, dynamic>{},
    'differential_diagnosis_payload': <String, dynamic>{},
    'clinical_impression_payload': <String, dynamic>{},
  };
  final mythosAero = <Map<String, dynamic>>[
    {'id': '6ba0117c-b94b-41ca-a521-53287e4782f9', 'mpt_seconds': '18.00', 's_z_ratio': '0.00', 'subglottal_pressure_estimated_cmh2o': null, 'mean_airflow_rate_ml_per_sec': null, 'phonation_threshold_pressure_cmh2o': null, 'f0_mean_hz': null, 'jitter_percent': null, 'shimmer_percent': null, 'hnr_db': null, 'notes': ''},
  ];
  final mythosPerceptual = <Map<String, dynamic>>[
    {'id': 'abd14733-d2c0-41af-aaf5-46b4d39c837c', 'rater': 'primary_clinician', 'capev_overall_severity': 54, 'capev_roughness': 66, 'capev_breathiness': 67, 'capev_strain': 62, 'capev_pitch': 62, 'capev_loudness': 59, 'capev_resonance_notes': '', 'grbas_grade': 2, 'grbas_roughness': 3, 'grbas_breathiness': 2, 'grbas_asthenia': 1, 'grbas_strain': 3, 'audio_recording_url': null, 'notes': ''},
  ];

  test('GATE — CAS #2 assembles: assessment block intact, client_meta populated, therapy empty', () {
    final env = CasAssessmentReader().read(assessment: cas2, ddkRows: cas2Ddk, lengthRows: cas2Len);
    final bundle = assembler.assembleFromEnvelope(envelope: env, clientMeta: casClientMeta);
    _dumpBundle('CAS #2 (676d24d0)', bundle);

    _assertAssemblyPreservesEnvelope(bundle, env, 'pediatric-cas', '676d24d0-16c6-4470-950b-59ed723205d4', casClientMeta, therapyKeys);
    final a = bundle['assessment'] as Map<String, dynamic>;
    expect((a['findings'] as List).length, 3, reason: 'the 3 markers, intact');
    expect((a['measures'] as List).length, 9, reason: '4 DDK + 5 length, intact');
  });

  test('GATE — Mythos voice assembles: 27 findings / 13 measures intact, sources preserved', () {
    final env = VoiceAssessmentReader().read(
      assessment: mythos, aerodynamicRows: mythosAero, perceptualRows: mythosPerceptual);
    final bundle = assembler.assembleFromEnvelope(envelope: env, clientMeta: voiceClientMeta);
    _dumpBundle('Mythos voice (592a63f1)', bundle);

    _assertAssemblyPreservesEnvelope(bundle, env, 'voice', '592a63f1-a780-4323-8f8d-181e497511b8', voiceClientMeta, therapyKeys);
    final a = bundle['assessment'] as Map<String, dynamic>;
    expect((a['findings'] as List).length, 27);
    expect((a['measures'] as List).length, 13);
  });
}

/// Shared assertions: the assessment block equals the reader's envelope exactly
/// (no add/drop/alter, every source tag intact); client_meta populated;
/// therapy-only keys present but empty.
void _assertAssemblyPreservesEnvelope(
  Map<String, dynamic> bundle,
  AssessmentEnvelope env,
  String protocol,
  String assessmentId,
  Map<String, dynamic> clientMeta,
  List<String> therapyKeys,
) {
  final a = bundle['assessment'] as Map<String, dynamic>;
  expect(a['protocol'], protocol);
  expect(a['assessment_id'], assessmentId);

  // The findings/measures lists must equal the reader's toJson output EXACTLY —
  // this is the "nothing added, dropped, renamed, or altered" guarantee, and it
  // includes every source_id / source_table / field_label / value / group.
  expect(a['findings'], equals(env.findings.map((f) => f.toJson()).toList()),
      reason: 'findings must arrive byte-for-byte as the reader emitted them');
  expect(a['measures'], equals(env.measures.map((m) => m.toJson()).toList()),
      reason: 'measures must arrive byte-for-byte as the reader emitted them');

  // Explicit source-attribution checks (defence-in-depth).
  final bundleSourceIds = (a['findings'] as List).map((f) => (f as Map)['source_id'] as String).toSet();
  expect(bundleSourceIds, env.findings.map((f) => f.sourceId).toSet(),
      reason: 'no finding gained or lost its source_id in assembly');
  for (final f in (a['findings'] as List).cast<Map>()) {
    expect((f['source_id'] as String).isNotEmpty, isTrue, reason: 'every finding keeps a source_id');
    expect((f['source_table'] as String).isNotEmpty, isTrue, reason: 'every finding keeps a source_table');
  }

  // client_meta populated and passed through unchanged.
  expect(bundle['client_meta'], same(clientMeta));
  expect((bundle['client_meta'] as Map).isNotEmpty, isTrue);
  expect((bundle['client_meta'] as Map)['client_name'], isNotNull);

  // therapy-only keys present but EMPTY.
  for (final k in therapyKeys) {
    expect(bundle.containsKey(k), isTrue, reason: '$k present');
    expect(bundle[k], isEmpty, reason: '$k empty for an assessment draft');
  }
}

void _dumpBundle(String label, Map<String, dynamic> bundle) {
  final a = bundle['assessment'] as Map<String, dynamic>;
  final cm = bundle['client_meta'] as Map<String, dynamic>;
  final b = StringBuffer()
    ..writeln('\n══════════════════════════════════════════════')
    ..writeln('ASSEMBLED canonical_data — $label')
    ..writeln('client_meta: name="${cm['client_name']}" age=${cm['age']} (keys: ${cm.keys.length})')
    ..writeln('therapy-only keys (all empty): '
        '${['substrate_cells', 'long_term_goals', 'short_term_goals', 'sessions', 'citations', 'metrics'].map((k) => '$k=${(bundle[k] as List).length}').join('  ')}')
    ..writeln('assessment.protocol=${a['protocol']}  assessment_id=${a['assessment_id']}')
    ..writeln('assessment.findings (${(a['findings'] as List).length}):');
  for (final f in (a['findings'] as List).cast<Map>()) {
    b.writeln('  • [${f['group']}] ${f['field_label']} = "${f['value']}"   <${f['source_id']}>');
  }
  b.writeln('assessment.measures (${(a['measures'] as List).length}):');
  for (final m in (a['measures'] as List).cast<Map>()) {
    b.writeln('  • [${m['group']}] ${m['label']} = ${m['value']}${m['unit'] != null ? ' ${m['unit']}' : ''}   <${m['source_id']}>');
  }
  b.writeln('══════════════════════════════════════════════');
  debugPrint(b.toString());
}
