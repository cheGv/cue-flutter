// lib/services/assessment_bridge/voice_assessment_reader.dart
//
// Step 2 of the assessment data bridge: the VOICE reader. Voice (and, to follow,
// ped-dysarthria / ALD) stores its narrative findings in nested JSONB *_payload
// columns (the "wholesale-replace" pattern: the capture surface rewrites the
// whole column, so EVERY key is present even when untouched — value is "" or
// null or false). Typed numeric scores live in child measure tables.
//
// This reader walks each payload RECURSIVELY to its leaf values and applies the
// SAME shared emptiness rule (assessment_emptiness.dart) at each leaf, emitting
// into the SAME uniform envelope (assessment_envelope.dart) as the CAS reader.
// One rule, one envelope — the anti-fabrication guarantee lives in one place.
//
// `read(...)` is PURE (rows in -> envelope out) so the verification gate runs it
// against the real captured "Mythos" assessment as fixtures. `readById(...)` is
// the thin loader.

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/assessment_envelope.dart';
import 'assessment_emptiness.dart';

class VoiceAssessmentReader {
  static const String protocol = 'voice';

  // Parent typed clinical columns that MAY become findings. Explicit ALLOWLIST —
  // structural/metadata columns (id, client_id, clinician_id, visit_id,
  // baseline_assessment_id, is_baseline, attested_*, timestamps) are deliberately
  // excluded so they can never be mistaken for clinical findings. Neither listed
  // column carries a DB default, so untouched = null = suppressed by the rule.
  static const List<(String col, String label, String group)> _parentFindingFields = [
    ('rsi_total_score', 'Reflux Symptom Index (RSI) total', 'Case history'),
    ('voice_use_hours_per_day', 'Voice use — hours per day', 'Case history'),
  ];

  // The seven narrative JSONB payload columns -> human section name (group).
  static const List<(String col, String group)> _payloadSections = [
    ('case_history_payload', 'Case history'),
    ('laryngeal_exam_payload', 'Laryngeal examination'),
    ('functional_voice_payload', 'Functional voice'),
    ('task_based_payload', 'Task-based assessment'),
    ('special_populations_payload', 'Special populations'),
    ('differential_diagnosis_payload', 'Differential diagnosis'),
    ('clinical_impression_payload', 'Clinical impression'),
  ];

  // Child measure tables: curated (column, label, unit). ONLY these numeric
  // measure columns are emitted. Free-text note columns, audio URLs, ids, and —
  // critically — voice_perceptual_ratings.rater (which carries a DB DEFAULT of
  // 'primary_clinician', a default-trap, and is metadata not a measure) are
  // deliberately NOT listed, so they are never emitted.
  static const List<(String col, String label, String? unit)> _aeroMeasures = [
    ('mpt_seconds', 'Maximum phonation time', 'seconds'),
    ('s_z_ratio', 's/z ratio', null),
    ('subglottal_pressure_estimated_cmh2o', 'Estimated subglottal pressure', 'cmH2O'),
    ('mean_airflow_rate_ml_per_sec', 'Mean airflow rate', 'mL/sec'),
    ('phonation_threshold_pressure_cmh2o', 'Phonation threshold pressure', 'cmH2O'),
    ('f0_mean_hz', 'Mean fundamental frequency (F0)', 'Hz'),
    ('jitter_percent', 'Jitter', '%'),
    ('shimmer_percent', 'Shimmer', '%'),
    ('hnr_db', 'Harmonics-to-noise ratio (HNR)', 'dB'),
  ];
  static const List<(String col, String label, String? unit)> _perceptualMeasures = [
    ('capev_overall_severity', 'CAPE-V overall severity', '/100'),
    ('capev_roughness', 'CAPE-V roughness', '/100'),
    ('capev_breathiness', 'CAPE-V breathiness', '/100'),
    ('capev_strain', 'CAPE-V strain', '/100'),
    ('capev_pitch', 'CAPE-V pitch', '/100'),
    ('capev_loudness', 'CAPE-V loudness', '/100'),
    ('grbas_grade', 'GRBAS grade (G)', '/3'),
    ('grbas_roughness', 'GRBAS roughness (R)', '/3'),
    ('grbas_breathiness', 'GRBAS breathiness (B)', '/3'),
    ('grbas_asthenia', 'GRBAS asthenia (A)', '/3'),
    ('grbas_strain', 'GRBAS strain (S)', '/3'),
  ];
  static const List<(String col, String label, String? unit)> _qolMeasures = [
    ('vhi10_total', 'VHI-10 total', '/40'),
    ('vhi30_total', 'VHI-30 total', '/120'),
    ('vhi30_functional', 'VHI-30 functional subscale', null),
    ('vhi30_physical', 'VHI-30 physical subscale', null),
    ('vhi30_emotional', 'VHI-30 emotional subscale', null),
    ('vrqol_total', 'V-RQOL total', null),
    ('svhi_total', 'SVHI total', null),
  ];

  /// Pure transform: rows in -> envelope out. [assessment] is one
  /// voice_assessments row (with its JSONB payload columns already parsed to
  /// Maps). Each child is a list of that table's rows for this assessment
  /// (voice_perceptual_ratings can have several — one per rater — so all are
  /// lists; aerodynamic/qol will have at most one).
  AssessmentEnvelope read({
    required Map<String, dynamic> assessment,
    List<Map<String, dynamic>> aerodynamicRows = const [],
    List<Map<String, dynamic>> perceptualRows = const [],
    List<Map<String, dynamic>> qolRows = const [],
  }) {
    final id = (assessment['id'] ?? '').toString();
    final findings = <AssessmentFinding>[];

    // ── Parent typed clinical columns ───────────────────────────────────────
    for (final (col, label, group) in _parentFindingFields) {
      final v = assessment[col];
      if (!assessmentValueIsPresent(v)) continue; // THE EMPTINESS RULE
      findings.add(AssessmentFinding(
        sourceId: 'voice_assessments/$id/$col',
        sourceTable: 'voice_assessments',
        fieldLabel: label,
        value: v as Object,
        group: group,
        // Voice records totals, hours, ratings and prose — nothing here has
        // an absence vocabulary. A GRBAS 0 or a CAPE-V minimum is an
        // affirmative "normal", not "not there"; and a blank field means
        // she wrote nothing. See the FindingScale doc.
        scale: FindingScale.openValue,
      ));
    }

    // ── Narrative payloads — recursive leaf walk ────────────────────────────
    for (final (col, group) in _payloadSections) {
      final raw = assessment[col];
      if (raw is! Map) continue; // null / non-map -> nothing (untouched {} too)
      _walkPayload(
        node: Map<String, dynamic>.from(raw),
        path: col,
        labelPrefix: '',
        group: group,
        rowId: id,
        out: findings,
      );
    }

    // ── Child measures ──────────────────────────────────────────────────────
    final measures = <AssessmentMeasure>[];
    _emitMeasures(aerodynamicRows, 'voice_aerodynamic_measures', 'Aerodynamic measures', _aeroMeasures, measures);
    _emitMeasures(perceptualRows, 'voice_perceptual_ratings', 'Perceptual ratings (CAPE-V / GRBAS)', _perceptualMeasures, measures);
    _emitMeasures(qolRows, 'voice_qol_scores', 'Voice quality of life', _qolMeasures, measures);

    return AssessmentEnvelope(
      protocol: protocol,
      assessmentId: id,
      findings: findings,
      measures: measures,
    );
  }

  /// Walk a JSONB payload to its LEAVES. Each present leaf becomes a finding;
  /// nested keys build a dotted source_id path and a human label.
  ///
  /// THE DEFAULT TRAP (Step-2 manifestation, same lesson as CAS
  /// sequence_order_errors): the capture surface writes `false` for an UNTOUCHED
  /// checkbox (wholesale-replace), so a stored boolean `false` is indistinguishable
  /// from "never answered". Emitting it would FABRICATE a clinical "no" the
  /// clinician may never have made — so a boolean `false` leaf is EXCLUDED
  /// (under-report, never fabricate). A boolean `true` is an affirmative
  /// selection (the surface defaults to false, not true) and IS emitted.
  /// Numbers are NOT affected: 0 / 0.00 has no DB/UI default here (untouched =
  /// null), so a stored 0 is a real measured value and is kept.
  void _walkPayload({
    required Map<String, dynamic> node,
    required String path,
    required String labelPrefix,
    required String group,
    required String rowId,
    required List<AssessmentFinding> out,
  }) {
    for (final entry in node.entries) {
      final key = entry.key;
      final value = entry.value;
      final childPath = '$path.$key';
      final label = labelPrefix.isEmpty
          ? _humanize(key)
          : '$labelPrefix — ${_humanize(key)}';

      if (value is Map) {
        // Recurse into nested objects (e.g. case_history.rsi, .voice_use).
        // An empty {} simply yields no leaves -> nothing.
        _walkPayload(
          node: Map<String, dynamic>.from(value),
          path: childPath,
          labelPrefix: label,
          group: group,
          rowId: rowId,
          out: out,
        );
        continue;
      }

      // DEFAULT TRAP: ambiguous untouched-checkbox false -> exclude.
      if (value is bool && value == false) continue;

      if (!assessmentValueIsPresent(value)) continue; // null / "" / [] -> nothing

      out.add(AssessmentFinding(
        sourceId: 'voice_assessments/$rowId/$childPath',
        sourceTable: 'voice_assessments',
        fieldLabel: label,
        value: value as Object,
        group: group,
        // Narrative payload leaves — prose and ratings, no absence
        // vocabulary anywhere in voice capture.
        scale: FindingScale.openValue,
      ));
    }
  }

  void _emitMeasures(
    List<Map<String, dynamic>> rows,
    String table,
    String group,
    List<(String col, String label, String? unit)> spec,
    List<AssessmentMeasure> out,
  ) {
    for (final row in rows) {
      final rowId = (row['id'] ?? '').toString();
      for (final (col, label, unit) in spec) {
        final v = row[col];
        if (!assessmentValueIsPresent(v)) continue; // THE EMPTINESS RULE
        out.add(AssessmentMeasure(
          sourceId: '$table/$rowId/$col',
          label: label,
          value: v as Object,
          unit: unit,
          group: group,
        ));
      }
    }
  }

  // "onset_date_or_age" -> "Onset date or age". The source_id carries the exact
  // key path; this label is only a human hint, never a fabricated claim.
  String _humanize(String key) {
    final spaced = key.replaceAll('_', ' ').trim();
    if (spaced.isEmpty) return key;
    return spaced[0].toUpperCase() + spaced.substring(1);
  }

  /// Convenience: load a voice assessment + its children by id, then [read].
  /// (Not exercised by the pure-transform verification gate.)
  Future<AssessmentEnvelope> readById(
    String assessmentId, {
    SupabaseClient? client,
  }) async {
    final sb = client ?? Supabase.instance.client;
    final assessment = await sb
        .from('voice_assessments')
        .select()
        .eq('id', assessmentId)
        .single();
    Future<List<Map<String, dynamic>>> kids(String table) async {
      final rows = await sb.from(table).select().eq('voice_assessment_id', assessmentId);
      return (rows as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }

    return read(
      assessment: Map<String, dynamic>.from(assessment),
      aerodynamicRows: await kids('voice_aerodynamic_measures'),
      perceptualRows: await kids('voice_perceptual_ratings'),
      qolRows: await kids('voice_qol_scores'),
    );
  }
}
