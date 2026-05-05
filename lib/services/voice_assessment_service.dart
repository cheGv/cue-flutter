// lib/services/voice_assessment_service.dart
//
// Phase 4.0.7.24a — voice_assessments parent record + section-payload
// upserts + outcome comparison rollup. The typed child tables
// (voice_aerodynamic_measures, voice_perceptual_ratings,
// voice_qol_scores) are read-only here; their write paths land with
// Sections 4, 5, 12 in 4.0.7.24b/c.

import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/voice_assessment.dart';

class VoiceAssessmentService {
  VoiceAssessmentService._();
  static final instance = VoiceAssessmentService._();

  SupabaseClient get _sb => Supabase.instance.client;

  /// Returns the most recent voice_assessments row for a client +
  /// visit pair. If none exists, creates a fresh baseline row and
  /// returns it. Idempotent on repeat opens of the same case screen.
  Future<VoiceAssessment> loadOrCreate({
    required String clientId,
    String? visitId,
  }) async {
    final existing = await _sb
        .from('voice_assessments')
        .select()
        .eq('client_id', clientId)
        .order('created_at', ascending: false)
        .limit(1)
        .maybeSingle();
    if (existing != null) {
      return VoiceAssessment.fromJson(Map<String, dynamic>.from(existing));
    }
    final inserted = await _sb
        .from('voice_assessments')
        .insert({
          'client_id':              clientId,
          'visit_id':               visitId,
          'is_baseline':            true,
          'case_history_payload':   <String, dynamic>{},
          'laryngeal_exam_payload': <String, dynamic>{},
        })
        .select()
        .single();
    return VoiceAssessment.fromJson(Map<String, dynamic>.from(inserted));
  }

  /// Saves a section's jsonb payload. `section` ∈ {'case_history',
  /// 'laryngeal_exam'} maps to the corresponding column. Sections 6/7
  /// use [savePayloadSection] directly with their column names; the
  /// typed child tables (4/5) use [saveTypedMeasures].
  Future<void> saveSection({
    required String assessmentId,
    required String section,
    required Map<String, dynamic> payload,
  }) async {
    String column;
    switch (section) {
      case 'case_history':   column = 'case_history_payload';   break;
      case 'laryngeal_exam': column = 'laryngeal_exam_payload'; break;
      default:
        throw ArgumentError(
            'Unknown section "$section" — Sections 6/7 use savePayloadSection');
    }
    await _sb
        .from('voice_assessments')
        .update({column: payload})
        .eq('id', assessmentId);
  }

  /// Phase 4.0.7.24b — PATCH a named jsonb column on the
  /// voice_assessments parent row. Used by Sections 6 (functional
  /// voice) and 7 (task-based) which are narrative jsonb rather than
  /// typed measures. [columnName] ∈ {'functional_voice_payload',
  /// 'task_based_payload'} as of this commit.
  Future<void> savePayloadSection({
    required String voiceAssessmentId,
    required String columnName,
    required Map<String, dynamic> payload,
  }) async {
    // 24c — three new narrative jsonb columns for Sections 8 / 10 / 15.
    const allowed = {
      'functional_voice_payload',
      'task_based_payload',
      'special_populations_payload',
      'differential_diagnosis_payload',
      'clinical_impression_payload',
    };
    if (!allowed.contains(columnName)) {
      throw ArgumentError(
          'savePayloadSection: $columnName is not a known jsonb column');
    }
    await _sb
        .from('voice_assessments')
        .update({columnName: payload})
        .eq('id', voiceAssessmentId);
  }

  /// Phase 4.0.7.24b — upsert one typed measures row for an assessment.
  /// [tableName] is 'voice_aerodynamic_measures' or
  /// 'voice_perceptual_ratings'. The schema does not (yet) enforce a
  /// UNIQUE(voice_assessment_id) constraint — we emulate upsert by
  /// reading the latest row first, then PATCHing it if present or
  /// inserting otherwise. A migration to add the unique constraint
  /// would let this become a single .upsert() call; flagged in the
  /// 24b report.
  Future<void> saveTypedMeasures({
    required String voiceAssessmentId,
    required String tableName,
    required Map<String, dynamic> data,
  }) async {
    const allowed = {
      'voice_aerodynamic_measures',
      'voice_perceptual_ratings',
      // 24c — Section 12 typed QoL scores
      'voice_qol_scores',
    };
    if (!allowed.contains(tableName)) {
      throw ArgumentError(
          'saveTypedMeasures: $tableName is not a known typed table');
    }
    final existing = await _sb
        .from(tableName)
        .select('id')
        .eq('voice_assessment_id', voiceAssessmentId)
        .order('created_at', ascending: false)
        .limit(1)
        .maybeSingle();
    if (existing != null && existing['id'] != null) {
      await _sb
          .from(tableName)
          .update(data)
          .eq('id', existing['id'] as String);
    } else {
      await _sb.from(tableName).insert({
        'voice_assessment_id': voiceAssessmentId,
        ...data,
      });
    }
  }

  /// Phase 4.0.7.24b — load the latest typed-measures row for an
  /// assessment. Returns an empty map when no row exists yet (fresh
  /// baseline). Used by the widget to seed Sections 4 and 5 on bootstrap.
  Future<Map<String, dynamic>> loadTypedMeasures({
    required String voiceAssessmentId,
    required String tableName,
  }) async {
    try {
      final r = await _sb
          .from(tableName)
          .select()
          .eq('voice_assessment_id', voiceAssessmentId)
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();
      return r == null ? {} : Map<String, dynamic>.from(r);
    } catch (_) {
      return {};
    }
  }

  /// All voice assessments for a client, baseline first.
  Future<List<VoiceAssessment>> loadHistory(String clientId) async {
    final rows = await _sb
        .from('voice_assessments')
        .select()
        .eq('client_id', clientId)
        .order('created_at', ascending: true);
    return (rows as List)
        .whereType<Map>()
        .map((m) => VoiceAssessment.fromJson(Map<String, dynamic>.from(m)))
        .toList();
  }

  /// Section 11 — rolls up baseline vs most-recent typed measures
  /// across aerodynamic / perceptual / QoL groups. When only the
  /// baseline exists (no follow-ups yet) the comparison's hasFollowUp
  /// is false and the widget renders the empty state.
  Future<OutcomeComparison> compareBaselineToLatest(String clientId) async {
    final history = await loadHistory(clientId);
    if (history.isEmpty) return const OutcomeComparison(groups: []);
    final baseline = history.first;
    final latest   = history.length > 1 ? history.last : history.first;

    Future<Map<String, dynamic>?> latestChild(
        String table, String assessmentId) async {
      try {
        final r = await _sb
            .from(table)
            .select()
            .eq('voice_assessment_id', assessmentId)
            .order('created_at', ascending: false)
            .limit(1)
            .maybeSingle();
        return r == null ? null : Map<String, dynamic>.from(r);
      } catch (_) {
        return null;
      }
    }

    final results = await Future.wait([
      latestChild('voice_aerodynamic_measures', baseline.id),
      latestChild('voice_aerodynamic_measures', latest.id),
      latestChild('voice_perceptual_ratings',   baseline.id),
      latestChild('voice_perceptual_ratings',   latest.id),
      latestChild('voice_qol_scores',           baseline.id),
      latestChild('voice_qol_scores',           latest.id),
    ]);
    final baseAero    = results[0];
    final latestAero  = results[1];
    final basePerc    = results[2];
    final latestPerc  = results[3];
    final baseQol     = results[4];
    final latestQol   = results[5];

    num? n(Map<String, dynamic>? m, String key) =>
        m == null ? null : (m[key] is num ? m[key] as num : null);

    return OutcomeComparison(
      baselineId: baseline.id,
      latestId:   latest.id,
      groups: [
        OutcomeGroup(label: 'Aerodynamic', rows: [
          // 24b — column names match the 24a migration spec
          // (jitter_percent, shimmer_percent — not the *_pct shorthand
          // used in pre-24b drafts). s/z ratio Δ direction is now
          // 'neutral' (24a-fix1) because the clinical signal is
          // deviance-from-1.0, not directional.
          OutcomeRow(label: 'MPT',         baseline: n(baseAero,   'mpt_seconds'),     latest: n(latestAero,   'mpt_seconds'),     unit: 's',  direction: 'higher'),
          OutcomeRow(label: 's/z ratio',   baseline: n(baseAero,   's_z_ratio'),       latest: n(latestAero,   's_z_ratio'),       unit: '',   direction: 'neutral'),
          OutcomeRow(label: 'F0 mean',     baseline: n(baseAero,   'f0_mean_hz'),      latest: n(latestAero,   'f0_mean_hz'),      unit: 'Hz', direction: 'neutral'),
          OutcomeRow(label: 'Jitter',      baseline: n(baseAero,   'jitter_percent'),  latest: n(latestAero,   'jitter_percent'),  unit: '%',  direction: 'lower'),
          OutcomeRow(label: 'Shimmer',     baseline: n(baseAero,   'shimmer_percent'), latest: n(latestAero,   'shimmer_percent'), unit: '%',  direction: 'lower'),
          OutcomeRow(label: 'HNR',         baseline: n(baseAero,   'hnr_db'),          latest: n(latestAero,   'hnr_db'),          unit: 'dB', direction: 'higher'),
        ]),
        OutcomeGroup(label: 'Perceptual', rows: [
          // 24b — column names match the 24a migration spec
          // (capev_*_severity / capev_roughness / capev_breathiness,
          // not the cape_v_* shorthand used in pre-24b drafts).
          OutcomeRow(label: 'CAPE-V overall',     baseline: n(basePerc, 'capev_overall_severity'), latest: n(latestPerc, 'capev_overall_severity'), direction: 'lower'),
          OutcomeRow(label: 'CAPE-V roughness',   baseline: n(basePerc, 'capev_roughness'),        latest: n(latestPerc, 'capev_roughness'),        direction: 'lower'),
          OutcomeRow(label: 'CAPE-V breathiness', baseline: n(basePerc, 'capev_breathiness'),      latest: n(latestPerc, 'capev_breathiness'),      direction: 'lower'),
          OutcomeRow(label: 'GRBAS grade',        baseline: n(basePerc, 'grbas_grade'),            latest: n(latestPerc, 'grbas_grade'),            direction: 'lower'),
        ]),
        OutcomeGroup(label: 'QoL', rows: [
          // 24c — Section 12 lands typed QoL scores. VHI-* / SVHI are
          // handicap scales (lower = better); V-RQOL is a quality of
          // life scale (higher = better).
          OutcomeRow(label: 'VHI-10',     baseline: n(baseQol, 'vhi10_total'),  latest: n(latestQol, 'vhi10_total'),  direction: 'lower'),
          OutcomeRow(label: 'VHI-30',     baseline: n(baseQol, 'vhi30_total'),  latest: n(latestQol, 'vhi30_total'),  direction: 'lower'),
          OutcomeRow(label: 'V-RQOL',     baseline: n(baseQol, 'vrqol_total'),  latest: n(latestQol, 'vrqol_total'),  direction: 'higher'),
          OutcomeRow(label: 'SVHI',       baseline: n(baseQol, 'svhi_total'),   latest: n(latestQol, 'svhi_total'),   direction: 'lower'),
        ]),
      ],
    );
  }

  /// Adds a new follow-up assessment row pointing at the original
  /// baseline. Returns the new row ID.
  Future<String> addFollowUp({
    required String clientId,
    required String baselineAssessmentId,
    String? visitId,
  }) async {
    final inserted = await _sb
        .from('voice_assessments')
        .insert({
          'client_id':              clientId,
          'visit_id':               visitId,
          'is_baseline':            false,
          'baseline_assessment_id': baselineAssessmentId,
          'case_history_payload':   <String, dynamic>{},
          'laryngeal_exam_payload': <String, dynamic>{},
        })
        .select('id')
        .single();
    return (inserted['id'] as String?) ?? '';
  }
}
