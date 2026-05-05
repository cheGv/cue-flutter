// lib/services/ald_assessment_service.dart
//
// Phase 4.0.7.25a — parent record + section-payload upserts + outcome
// comparison rollup for the Adult Language & Cognitive (ALD) surface.
// Mirrors voice_assessment_service.dart's shape so the widget layer
// has the same API to lean on.
//
// Per the 4.0.7.25a migration, ald_assessments has clinician_id
// defaulted to auth.uid(), RLS disabled (Phase 4.0.7.30 will tighten),
// and unique(ald_assessment_id) on every typed child table — so
// upserts route through .upsert with onConflict.

import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/ald_assessment.dart';

class AldAssessmentService {
  AldAssessmentService._();
  static final instance = AldAssessmentService._();

  SupabaseClient get _sb => Supabase.instance.client;

  /// Returns the most recent ald_assessments row for a client + visit
  /// pair. If none exists, creates a fresh baseline row and returns it.
  Future<AldAssessment> loadOrCreate({
    required String clientId,
    String? visitId,
  }) async {
    final existing = await _sb
        .from('ald_assessments')
        .select()
        .eq('client_id', clientId)
        .order('created_at', ascending: false)
        .limit(1)
        .maybeSingle();
    if (existing != null) {
      return AldAssessment.fromJson(Map<String, dynamic>.from(existing));
    }
    final inserted = await _sb
        .from('ald_assessments')
        .insert({
          'client_id':                 clientId,
          'visit_id':                  visitId,
          'is_baseline':               true,
          'case_history_payload':      <String, dynamic>{},
          'bedside_screen_payload':    <String, dynamic>{},
        })
        .select()
        .single();
    return AldAssessment.fromJson(Map<String, dynamic>.from(inserted));
  }

  /// PATCH a named jsonb column on ald_assessments. Used by every
  /// narrative section (1, 2, 5, 6, 7, 8, 9, 10, 15) — typed
  /// instruments use [saveTypedMeasures] instead.
  Future<void> savePayloadSection({
    required String assessmentId,
    required String columnName,
    required Map<String, dynamic> payload,
  }) async {
    const allowed = {
      'case_history_payload',
      'bedside_screen_payload',
      'formal_battery_payload',          // notes-only narrative; scores live in typed tables
      'naming_payload',
      'auditory_comprehension_payload',
      'reading_writing_payload',
      'discourse_payload',
      'etiology_specific_payload',
      'cognitive_comm_screen_payload',
      'differential_diagnosis_payload',
      'clinical_impression_payload',
    };
    if (!allowed.contains(columnName)) {
      throw ArgumentError(
          'savePayloadSection: $columnName is not an ALD jsonb column');
    }
    await _sb
        .from('ald_assessments')
        .update({columnName: payload})
        .eq('id', assessmentId);
  }

  /// PATCH the parent's typed columns that mirror Section 1's
  /// case-history selections (etiology, acuity, lesion location).
  /// These drive Section 8 routing + indexed queries — Section 1's
  /// jsonb still holds the full payload for the SLP's history.
  Future<void> savePresentingProfile({
    required String assessmentId,
    String? etiologyCategory,
    String? acuityStage,
    int?    timePostOnsetDays,
    List<String>? lesionLocation,
  }) async {
    final patch = <String, dynamic>{
      'etiology_category':    ?etiologyCategory,
      'acuity_stage':         ?acuityStage,
      'time_post_onset_days': ?timePostOnsetDays,
      'lesion_location':      ?lesionLocation,
    };
    if (patch.isEmpty) return;
    await _sb
        .from('ald_assessments')
        .update(patch)
        .eq('id', assessmentId);
  }

  /// Upsert a typed child row keyed by ald_assessment_id. The 25a
  /// migration enforces UNIQUE(ald_assessment_id) on every typed
  /// table, so onConflict cleanly does insert-or-update in one round.
  Future<void> saveTypedMeasures({
    required String assessmentId,
    required String tableName,
    required Map<String, dynamic> data,
  }) async {
    const allowed = {
      'ald_wab_scores',
      'ald_cognitive_screens',
      'ald_naming_measures',
      'ald_qol_scores',
    };
    if (!allowed.contains(tableName)) {
      throw ArgumentError(
          'saveTypedMeasures: $tableName is not an ALD typed table');
    }
    await _sb.from(tableName).upsert(
      {
        'ald_assessment_id': assessmentId,
        ...data,
      },
      onConflict: 'ald_assessment_id',
    );
  }

  /// Loads the latest typed-measures row for an assessment from the
  /// named child table. Returns {} when no row exists.
  Future<Map<String, dynamic>> loadTypedMeasures({
    required String assessmentId,
    required String tableName,
  }) async {
    try {
      final r = await _sb
          .from(tableName)
          .select()
          .eq('ald_assessment_id', assessmentId)
          .maybeSingle();
      return r == null ? {} : Map<String, dynamic>.from(r);
    } catch (_) {
      return {};
    }
  }

  /// All ALD assessments for a client, baseline first.
  Future<List<AldAssessment>> loadHistory(String clientId) async {
    final rows = await _sb
        .from('ald_assessments')
        .select()
        .eq('client_id', clientId)
        .order('created_at', ascending: true);
    return (rows as List)
        .whereType<Map>()
        .map((m) => AldAssessment.fromJson(Map<String, dynamic>.from(m)))
        .toList();
  }

  /// Section 11 — baseline vs most-recent typed measures across WAB,
  /// MoCA, MMSE, naming, QoL groups. Sections 4 and 12 land in 25b/c
  /// so most rows will be empty until those ship; the widget guards
  /// each group with _groupHasData so the table only renders rows
  /// that actually have numbers on at least one side.
  Future<OutcomeComparison> compareBaselineToLatest(String clientId) async {
    final history = await loadHistory(clientId);
    if (history.isEmpty) return const OutcomeComparison(groups: []);
    final baseline = history.first;
    final latest   = history.length > 1 ? history.last : history.first;

    Future<Map<String, dynamic>?> child(
        String table, String assessmentId) async {
      try {
        final r = await _sb
            .from(table)
            .select()
            .eq('ald_assessment_id', assessmentId)
            .maybeSingle();
        return r == null ? null : Map<String, dynamic>.from(r);
      } catch (_) {
        return null;
      }
    }

    final results = await Future.wait([
      child('ald_wab_scores',         baseline.id),
      child('ald_wab_scores',         latest.id),
      child('ald_cognitive_screens',  baseline.id),
      child('ald_cognitive_screens',  latest.id),
      child('ald_naming_measures',    baseline.id),
      child('ald_naming_measures',    latest.id),
      child('ald_qol_scores',         baseline.id),
      child('ald_qol_scores',         latest.id),
    ]);
    final baseWab    = results[0];
    final latestWab  = results[1];
    final baseCog    = results[2];
    final latestCog  = results[3];
    final baseNam    = results[4];
    final latestNam  = results[5];
    final baseQol    = results[6];
    final latestQol  = results[7];

    num? n(Map<String, dynamic>? m, String key) =>
        m == null ? null : (m[key] is num ? m[key] as num : null);

    /// Sum the three FAS phonemic subscores from a naming row.
    /// Returns null when none of the three are populated, so the
    /// outcome row stays empty rather than reading "0" misleadingly.
    num? fasTotalOf(Map<String, dynamic>? m) {
      if (m == null) return null;
      final f = n(m, 'fluency_phonemic_f');
      final a = n(m, 'fluency_phonemic_a');
      final s = n(m, 'fluency_phonemic_s');
      if (f == null && a == null && s == null) return null;
      return (f ?? 0) + (a ?? 0) + (s ?? 0);
    }

    return OutcomeComparison(
      baselineId: baseline.id,
      latestId:   latest.id,
      groups: [
        OutcomeGroup(label: 'WAB', rows: [
          OutcomeRow(label: 'Aphasia Quotient',  baseline: n(baseWab, 'aphasia_quotient'),  latest: n(latestWab, 'aphasia_quotient'),  unit: '/100', direction: 'higher'),
          OutcomeRow(label: 'Cortical Quotient', baseline: n(baseWab, 'cortical_quotient'), latest: n(latestWab, 'cortical_quotient'), unit: '/100', direction: 'higher'),
        ]),
        OutcomeGroup(label: 'Naming & Word Retrieval', rows: [
          // 25b — column names match the migration spec
          // (bnt_raw_score / fluency_semantic_animals /
          // fluency_phonemic_*). FAS total is computed client-side
          // by summing the three phonemic subscores.
          OutcomeRow(label: 'BNT raw',                  baseline: n(baseNam, 'bnt_raw_score'),            latest: n(latestNam, 'bnt_raw_score'),            unit: '/60', direction: 'higher'),
          OutcomeRow(label: 'BNT z-score',              baseline: n(baseNam, 'bnt_z_score'),              latest: n(latestNam, 'bnt_z_score'),              direction: 'higher'),
          OutcomeRow(label: 'Action naming raw',        baseline: n(baseNam, 'ant_raw_score'),            latest: n(latestNam, 'ant_raw_score'),            direction: 'higher'),
          OutcomeRow(label: 'Verbal fluency — animals', baseline: n(baseNam, 'fluency_semantic_animals'), latest: n(latestNam, 'fluency_semantic_animals'), direction: 'higher'),
          OutcomeRow(label: 'Verbal fluency — FAS total',
              baseline: fasTotalOf(baseNam),
              latest:   fasTotalOf(latestNam),
              direction: 'higher'),
        ]),
        OutcomeGroup(label: 'Cognitive Screens', rows: [
          OutcomeRow(label: 'MoCA total', baseline: n(baseCog, 'moca_total'), latest: n(latestCog, 'moca_total'), unit: '/30', direction: 'higher'),
          OutcomeRow(label: 'MMSE total', baseline: n(baseCog, 'mmse_total'), latest: n(latestCog, 'mmse_total'), unit: '/30', direction: 'higher'),
        ]),
        OutcomeGroup(label: 'Functional Communication & QoL', rows: [
          // 25c populates these.
          OutcomeRow(label: 'COAST',     baseline: n(baseQol, 'coast_total'),    latest: n(latestQol, 'coast_total'),    direction: 'higher'),
          OutcomeRow(label: 'AIQ-21',    baseline: n(baseQol, 'aiq21_total'),    latest: n(latestQol, 'aiq21_total'),    direction: 'lower'),
          OutcomeRow(label: 'SAQOL-39',  baseline: n(baseQol, 'saqol39_total'),  latest: n(latestQol, 'saqol39_total'),  direction: 'higher'),
          OutcomeRow(label: 'CETI',      baseline: n(baseQol, 'ceti_total'),     latest: n(latestQol, 'ceti_total'),     direction: 'higher'),
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
        .from('ald_assessments')
        .insert({
          'client_id':              clientId,
          'visit_id':               visitId,
          'is_baseline':            false,
          'baseline_assessment_id': baselineAssessmentId,
          'case_history_payload':   <String, dynamic>{},
          'bedside_screen_payload': <String, dynamic>{},
        })
        .select('id')
        .single();
    return (inserted['id'] as String?) ?? '';
  }
}
