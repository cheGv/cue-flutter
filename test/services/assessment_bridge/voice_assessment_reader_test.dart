// test/services/assessment_bridge/voice_assessment_reader_test.dart
//
// VERIFICATION GATE for Step 2 of the assessment data bridge (the voice payload
// reader). The fixture below is the REAL, deliberately-partial voice assessment
// captured on client "Mythos" in the sandbox (uuqhusmgoiaxdvtgbmwh), fetched
// verbatim 2026-06-01 — the first genuinely half-filled JSONB payload we have.
//
// Wire-format note: JSONB leaves arrive parsed (int / bool / String / List);
// child-table `numeric(p,s)` columns arrive as STRINGS over PostgREST
// (e.g. mpt_seconds -> "18.00"), `integer` columns as ints — fixtures mirror
// this exactly so the gate matches what the live reader will receive.
//
// What this single record proves, all at once:
//   * filled fields            -> findings with their real values
//   * "" explicit blanks       -> NOTHING
//   * null / missing           -> NOTHING
//   * untouched {} sections    -> NOTHING
//   * meaning-traps survive     -> "no" / "nil" / "Absent" / 0.00 ARE findings
//   * boolean default-trap      -> false checkboxes EXCLUDED (never fabricate "no")
//   * non-empty lists           -> findings; nested objects -> recursed
//   * rater (DB default)        -> EXCLUDED

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cue/models/assessment_envelope.dart';
import 'package:cue/services/assessment_bridge/voice_assessment_reader.dart';

void main() {
  final reader = VoiceAssessmentReader();

  // ── Mythos — voice_assessments 592a63f1 (real, partially filled) ───────────
  final mythos = <String, dynamic>{
    'id': '592a63f1-a780-4323-8f8d-181e497511b8',
    'client_id': '803344ea-c6ce-45f4-bd8e-70fbe4a166c9',
    'is_baseline': true, // metadata (DB default true) — never a finding
    'rsi_total_score': null, // parent column null (real RSI total lives in payload)
    'voice_use_hours_per_day': null,
    'case_history_payload': <String, dynamic>{
      'rsi': <String, dynamic>{
        'mucus': 3, 'total': 26, 'heartburn': 2, 'hoarseness': 4, 'swallowing': 3,
        'throat_lump': 2, 'annoying_cough': 2, 'throat_clearing': 5,
        'breathing_choking': 2, 'cough_after_eating': 3,
      },
      'voice_use': <String, dynamic>{
        'caffeine_cups': null, // null -> nothing
        'hours_per_day': 6, // finding
        'speaking_styles': ['Loud projection'], // non-empty list -> finding
        'hydration_litres': null, // null -> nothing
        'microphone_at_work': false, // DEFAULT-TRAP boolean -> excluded
        'voice_rest_periods': '', // "" -> nothing
      },
      'onset_pattern': 'Sudden',
      'sleep_quality': 'Good',
      'allergy_history': 'no', // meaning-trap: "no" IS a finding
      'onset_date_or_age': '2 months',
      'relieving_factors': 'steam inhalation',
      'psychological_load': '', // "" -> nothing
      'aggravating_factors': 'Throat clearing and coughing',
      'current_medications': 'nil', // meaning-trap: "nil" IS a finding
      'previous_voice_therapy': false, // DEFAULT-TRAP boolean -> excluded
      'variability_across_day':
          'variability reported - excessive use of vocie - the vocie gets feeble and loss.',
      'previous_voice_therapy_text': '', // "" -> nothing
      'previous_laryngeal_surgeries': false, // DEFAULT-TRAP boolean -> excluded
      'previous_laryngeal_surgeries_text': '', // "" -> nothing
    },
    'laryngeal_exam_payload': <String, dynamic>{
      'lesions': ['Vocal fold nodules'], // list -> finding
      'exam_date': null, // null -> nothing
      'performed_by': '', // "" -> nothing
      'glottic_closure': 'Posterior chink',
      'additional_notes': '', // "" -> nothing
      'examination_type': 'Flexible nasendoscopy',
      'mucosal_wave_symmetry': 'Symmetric',
      'lesions_location_notes': '', // "" -> nothing
      'mucosal_wave_amplitude': 'Absent', // meaning-trap: "Absent" IS a finding
      'phase_closure_symmetry': 'Asymmetric',
      'supraglottic_compression': 'Moderate',
    },
    // Five sections left UNTOUCHED -> {} -> nothing.
    'functional_voice_payload': <String, dynamic>{},
    'task_based_payload': <String, dynamic>{},
    'special_populations_payload': <String, dynamic>{},
    'differential_diagnosis_payload': <String, dynamic>{},
    'clinical_impression_payload': <String, dynamic>{},
  };

  // numeric(p,s) -> String over the wire; integer -> int.
  final mythosAero = <Map<String, dynamic>>[
    {
      'id': '6ba0117c-b94b-41ca-a521-53287e4782f9',
      'mpt_seconds': '18.00', // finding (measure)
      's_z_ratio': '0.00', // ZERO is a real measure -> must survive
      'subglottal_pressure_estimated_cmh2o': null,
      'mean_airflow_rate_ml_per_sec': null,
      'phonation_threshold_pressure_cmh2o': null,
      'f0_mean_hz': null,
      'jitter_percent': null,
      'shimmer_percent': null,
      'hnr_db': null,
      'notes': '',
    },
  ];
  final mythosPerceptual = <Map<String, dynamic>>[
    {
      'id': 'abd14733-d2c0-41af-aaf5-46b4d39c837c',
      'rater': 'primary_clinician', // DB default -> excluded (metadata + default-trap)
      'capev_overall_severity': 54, 'capev_roughness': 66, 'capev_breathiness': 67,
      'capev_strain': 62, 'capev_pitch': 62, 'capev_loudness': 59,
      'capev_resonance_notes': '',
      'grbas_grade': 2, 'grbas_roughness': 3, 'grbas_breathiness': 2,
      'grbas_asthenia': 1, 'grbas_strain': 3,
      'audio_recording_url': null,
      'notes': '',
    },
  ];
  final mythosQol = <Map<String, dynamic>>[]; // section not filled -> no row

  test('GATE — Mythos voice: counts, untouched sections empty, half-filled story', () {
    final env = reader.read(
      assessment: mythos,
      aerodynamicRows: mythosAero,
      perceptualRows: mythosPerceptual,
      qolRows: mythosQol,
    );
    _dump('Mythos voice (592a63f1 — partially filled)', env);

    // 20 case-history findings (10 RSI sub-scores + hours_per_day + speaking_styles
    // + 8 top-level) + 7 laryngeal findings = 27. The 3 false booleans, every "",
    // every null, and all 5 untouched {} sections contribute NOTHING.
    expect(env.findings.length, 27, reason: 'only genuinely-filled leaves become findings');

    // 2 aerodynamic (mpt, s/z) + 11 perceptual (6 CAPE-V + 5 GRBAS) = 13. qol none.
    expect(env.measures.length, 13, reason: '2 aero + 11 perceptual; rater excluded');

    // Untouched {} sections must contribute zero findings.
    const untouched = {
      'Functional voice', 'Task-based assessment', 'Special populations',
      'Differential diagnosis', 'Clinical impression',
    };
    expect(env.findings.where((f) => untouched.contains(f.group)), isEmpty,
        reason: 'sections left as {} must produce nothing');

    // Half-filled story: case history has BOTH a filled field and a blank one,
    // and only the filled one survives.
    final ids = env.findings.map((f) => f.sourceId).toSet();
    expect(ids.contains('voice_assessments/${mythos['id']}/case_history_payload.allergy_history'), isTrue);
    expect(ids.any((s) => s.endsWith('case_history_payload.psychological_load')), isFalse,
        reason: '"" must produce nothing even in a filled section');
  });

  test('GATE — Mythos voice: meaning-traps survive; blanks/nulls/default-traps excluded', () {
    final env = reader.read(
      assessment: mythos,
      aerodynamicRows: mythosAero,
      perceptualRows: mythosPerceptual,
      qolRows: mythosQol,
    );

    String? lastSeg(String id) => id.split('/').last.split('.').last;
    final findingByLeaf = {for (final f in env.findings) lastSeg(f.sourceId)!: f.value};

    // ── Meaning-traps MUST be findings (never dropped by "meaning") ──
    expect(findingByLeaf['allergy_history'], 'no', reason: '"no" is a real answer');
    expect(findingByLeaf['current_medications'], 'nil', reason: '"nil" is a real answer');
    expect(findingByLeaf['mucosal_wave_amplitude'], 'Absent', reason: '"Absent" is a real finding');
    // 0.00 s/z ratio survives as a measure (zero is a real value).
    final sz = env.measures.firstWhere((m) => m.sourceId.endsWith('s_z_ratio'));
    expect(sz.value, '0.00', reason: 'a measured 0.00 must survive');

    // ── Non-empty lists / nested objects become findings ──
    expect(findingByLeaf['speaking_styles'], ['Loud projection']);
    expect(findingByLeaf['lesions'], ['Vocal fold nodules']);
    expect(findingByLeaf['total'], 26, reason: 'nested rsi.total recursed and kept');
    expect(findingByLeaf['hours_per_day'], 6, reason: 'nested voice_use.hours_per_day recursed and kept');

    // ── Boolean DEFAULT-TRAP fields EXCLUDED (never fabricate a "no") ──
    for (final trap in ['microphone_at_work', 'previous_voice_therapy', 'previous_laryngeal_surgeries']) {
      expect(env.findings.any((f) => f.sourceId.endsWith(trap)), isFalse,
          reason: '$trap is an ambiguous default false -> excluded');
    }

    // ── Explicit "" blanks EXCLUDED ──
    for (final blank in [
      'psychological_load', 'voice_rest_periods', 'previous_voice_therapy_text',
      'previous_laryngeal_surgeries_text', 'performed_by', 'additional_notes',
      'lesions_location_notes',
    ]) {
      expect(env.findings.any((f) => f.sourceId.endsWith(blank)), isFalse,
          reason: '"$blank" is "" -> must be nothing');
    }

    // ── null fields EXCLUDED (payload + parent + child) ──
    for (final nul in ['caffeine_cups', 'hydration_litres', 'exam_date']) {
      expect(env.findings.any((f) => f.sourceId.endsWith(nul)), isFalse,
          reason: '"$nul" is null -> must be nothing');
    }
    expect(env.findings.any((f) => f.sourceId.endsWith('rsi_total_score')), isFalse);
    expect(env.findings.any((f) => f.sourceId.endsWith('voice_use_hours_per_day')), isFalse);
    // null aerodynamic measures excluded (only mpt + s/z present)
    expect(env.measures.where((m) => m.group == 'Aerodynamic measures').length, 2);

    // ── rater (DB default) EXCLUDED from measures ──
    expect(env.measures.any((m) => m.sourceId.contains('rater')), isFalse);
    expect(env.measures.any((m) => m.value == 'primary_clinician'), isFalse);

    // perceptual: exactly 6 CAPE-V + 5 GRBAS
    expect(env.measures.where((m) => m.group == 'Perceptual ratings (CAPE-V / GRBAS)').length, 11);
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
