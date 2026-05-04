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
  /// 'laryngeal_exam'} maps to the corresponding column. Other
  /// sections (4, 5, 12) write to typed child tables in 24b/c.
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
            'Unknown section "$section" — Sections 4/5/12 land in 24b/c');
    }
    await _sb
        .from('voice_assessments')
        .update({column: payload})
        .eq('id', assessmentId);
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
          OutcomeRow(label: 'MPT',         baseline: n(baseAero,   'mpt_seconds'),     latest: n(latestAero,   'mpt_seconds'),     unit: 's',  direction: 'higher'),
          OutcomeRow(label: 's/z ratio',   baseline: n(baseAero,   's_z_ratio'),       latest: n(latestAero,   's_z_ratio'),       unit: '',   direction: 'lower'),
          OutcomeRow(label: 'F0 mean',     baseline: n(baseAero,   'f0_mean_hz'),      latest: n(latestAero,   'f0_mean_hz'),      unit: 'Hz', direction: 'neutral'),
          OutcomeRow(label: 'Jitter',      baseline: n(baseAero,   'jitter_pct'),      latest: n(latestAero,   'jitter_pct'),      unit: '%',  direction: 'lower'),
          OutcomeRow(label: 'Shimmer',     baseline: n(baseAero,   'shimmer_pct'),     latest: n(latestAero,   'shimmer_pct'),     unit: '%',  direction: 'lower'),
          OutcomeRow(label: 'HNR',         baseline: n(baseAero,   'hnr_db'),          latest: n(latestAero,   'hnr_db'),          unit: 'dB', direction: 'higher'),
        ]),
        OutcomeGroup(label: 'Perceptual', rows: [
          OutcomeRow(label: 'CAPE-V overall',   baseline: n(basePerc,   'cape_v_overall'),       latest: n(latestPerc,   'cape_v_overall'),       direction: 'lower'),
          OutcomeRow(label: 'CAPE-V roughness', baseline: n(basePerc,   'cape_v_roughness'),     latest: n(latestPerc,   'cape_v_roughness'),     direction: 'lower'),
          OutcomeRow(label: 'CAPE-V breathiness', baseline: n(basePerc, 'cape_v_breathiness'),   latest: n(latestPerc,   'cape_v_breathiness'),   direction: 'lower'),
          OutcomeRow(label: 'GRBAS grade',      baseline: n(basePerc,   'grbas_grade'),          latest: n(latestPerc,   'grbas_grade'),          direction: 'lower'),
        ]),
        OutcomeGroup(label: 'QoL', rows: [
          OutcomeRow(label: 'VHI-10',     baseline: n(baseQol, 'vhi10_total'),  latest: n(latestQol, 'vhi10_total'),  direction: 'lower'),
          OutcomeRow(label: 'VHI-30',     baseline: n(baseQol, 'vhi30_total'),  latest: n(latestQol, 'vhi30_total'),  direction: 'lower'),
          OutcomeRow(label: 'V-RQOL',     baseline: n(baseQol, 'vrqol_total'),  latest: n(latestQol, 'vrqol_total'),  direction: 'higher'),
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
