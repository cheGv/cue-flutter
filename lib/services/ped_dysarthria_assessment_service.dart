// lib/services/ped_dysarthria_assessment_service.dart
//
// Phase 4.0.7.27a — parent record + section-payload upserts + outcome
// comparison rollup for the Pediatric Dysarthria surface. Mirrors
// voice/ALD shape so the widget layer has the same API.
//
// All voice/ALD migration lessons baked in: clinician_id defaults to
// auth.uid() server-side, RLS disabled, every typed child table
// enforces UNIQUE(ped_dysarthria_assessment_id) so saves use .upsert
// with onConflict cleanly. The parent itself has 13 jsonb columns +
// a typed Section 1 spine (developmental ages, etiology, CP levels,
// Mayo, two SLP-toggled cross-domain flags).

import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/ped_dysarthria_assessment.dart';

class PedDysarthriaAssessmentService {
  PedDysarthriaAssessmentService._();
  static final instance = PedDysarthriaAssessmentService._();

  SupabaseClient get _sb => Supabase.instance.client;

  /// Returns the most recent ped_dysarthria_assessments row for a
  /// client + visit pair, or creates a fresh baseline if none exists.
  Future<PedDysarthriaAssessment> loadOrCreate({
    required String clientId,
    String? visitId,
  }) async {
    final existing = await _sb
        .from('ped_dysarthria_assessments')
        .select()
        .eq('client_id', clientId)
        .order('created_at', ascending: false)
        .limit(1)
        .maybeSingle();
    if (existing != null) {
      return PedDysarthriaAssessment.fromJson(
          Map<String, dynamic>.from(existing));
    }
    final inserted = await _sb
        .from('ped_dysarthria_assessments')
        .insert({
          'client_id':              clientId,
          'visit_id':               visitId,
          'is_baseline':            true,
          'case_history_payload':   <String, dynamic>{},
          'bedside_screen_payload': <String, dynamic>{},
        })
        .select()
        .single();
    return PedDysarthriaAssessment.fromJson(
        Map<String, dynamic>.from(inserted));
  }

  /// PATCH a named jsonb column on ped_dysarthria_assessments. The
  /// allowlist enumerates every narrative section payload the surface
  /// authors today (Sections 1, 2, 4A–4E, 5, 7, 8, 9, 10, 15).
  Future<void> savePayloadSection({
    required String assessmentId,
    required String columnName,
    required Map<String, dynamic> payload,
  }) async {
    const allowed = {
      'case_history_payload',
      'bedside_screen_payload',
      'respiration_payload',
      'phonation_payload',
      'articulation_payload',
      'resonance_payload',
      'prosody_payload',
      'oral_mech_payload',
      // 27b — Section 6 (connected speech narrative).
      'connected_speech_payload',
      'stimulability_payload',
      'etiology_specific_payload',
      'cognitive_comm_screen_payload',
      'differential_diagnosis_payload',
      'clinical_impression_payload',
    };
    if (!allowed.contains(columnName)) {
      throw ArgumentError(
          'savePayloadSection: $columnName is not a ped-dysarthria jsonb column');
    }
    await _sb
        .from('ped_dysarthria_assessments')
        .update({columnName: payload})
        .eq('id', assessmentId);
  }

  /// PATCH the parent row's typed Section 1 spine — developmental ages,
  /// etiology, CP classification levels, Mayo type, last botox date,
  /// and the two SLP-toggled cross-domain flags. Caller passes only
  /// the columns it wants to update; the rest stay untouched.
  Future<void> saveTypedColumns({
    required String assessmentId,
    required Map<String, dynamic> data,
  }) async {
    if (data.isEmpty) return;
    await _sb
        .from('ped_dysarthria_assessments')
        .update(data)
        .eq('id', assessmentId);
  }

  /// Upsert a typed child row keyed by ped_dysarthria_assessment_id.
  /// The 27a migration enforces UNIQUE on that column for every typed
  /// table so onConflict insert-or-update is one round-trip.
  Future<void> saveTypedMeasures({
    required String assessmentId,
    required String tableName,
    required Map<String, dynamic> data,
  }) async {
    const allowed = {
      'ped_dys_aerodynamic_measures',
      'ped_dys_ddk_rates',
      'ped_dys_subsystem_severity',
      'ped_dys_intelligibility',
      'ped_dys_qol_scores',
    };
    if (!allowed.contains(tableName)) {
      throw ArgumentError(
          'saveTypedMeasures: $tableName is not a ped-dysarthria typed table');
    }
    await _sb.from(tableName).upsert(
      {
        'ped_dysarthria_assessment_id': assessmentId,
        ...data,
      },
      onConflict: 'ped_dysarthria_assessment_id',
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
          .eq('ped_dysarthria_assessment_id', assessmentId)
          .maybeSingle();
      return r == null ? {} : Map<String, dynamic>.from(r);
    } catch (_) {
      return {};
    }
  }

  /// All ped-dysarthria assessments for a client, baseline first.
  Future<List<PedDysarthriaAssessment>> loadHistory(String clientId) async {
    final rows = await _sb
        .from('ped_dysarthria_assessments')
        .select()
        .eq('client_id', clientId)
        .order('created_at', ascending: true);
    return (rows as List)
        .whereType<Map>()
        .map((m) => PedDysarthriaAssessment.fromJson(
            Map<String, dynamic>.from(m)))
        .toList();
  }

  /// Section 11 — baseline vs most-recent typed measures across
  /// aerodynamic, DDK, subsystem severity, intelligibility, QoL groups.
  /// Most rows stay empty until Sections 4 / 6 / 12 ship in 27b/c.
  /// The widget guards with _groupHasData so empty groups suppress.
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
            .eq('ped_dysarthria_assessment_id', assessmentId)
            .maybeSingle();
        return r == null ? null : Map<String, dynamic>.from(r);
      } catch (_) {
        return null;
      }
    }

    final results = await Future.wait([
      child('ped_dys_aerodynamic_measures',  baseline.id),
      child('ped_dys_aerodynamic_measures',  latest.id),
      child('ped_dys_ddk_rates',             baseline.id),
      child('ped_dys_ddk_rates',             latest.id),
      child('ped_dys_subsystem_severity',    baseline.id),
      child('ped_dys_subsystem_severity',    latest.id),
      child('ped_dys_intelligibility',       baseline.id),
      child('ped_dys_intelligibility',       latest.id),
      child('ped_dys_qol_scores',            baseline.id),
      child('ped_dys_qol_scores',            latest.id),
    ]);
    final baseAero = results[0]; final latestAero = results[1];
    final baseDdk  = results[2]; final latestDdk  = results[3];
    final baseSub  = results[4]; final latestSub  = results[5];
    final baseInt  = results[6]; final latestInt  = results[7];
    final baseQol  = results[8]; final latestQol  = results[9];

    num? n(Map<String, dynamic>? m, String key) =>
        m == null ? null : (m[key] is num ? m[key] as num : null);

    /// Subsystem severity columns are text bands ('None', 'Mild',
    /// 'Moderate', 'Severe', 'Profound') — map to 0..4 so Δ direction
    /// has a numeric anchor (lower = better recovery direction).
    num? sevToInt(Map<String, dynamic>? m, String key) {
      if (m == null) return null;
      final v = m[key];
      if (v is! String) return null;
      switch (v) {
        case 'None':     return 0;
        case 'Mild':     return 1;
        case 'Moderate': return 2;
        case 'Severe':   return 3;
        case 'Profound': return 4;
      }
      return null;
    }

    return OutcomeComparison(
      baselineId: baseline.id,
      latestId:   latest.id,
      groups: [
        OutcomeGroup(label: 'Aerodynamic', rows: [
          OutcomeRow(label: 'Max sustained "ah"', baseline: n(baseAero, 'mpt_seconds'),         latest: n(latestAero, 'mpt_seconds'),         unit: 's',  direction: 'higher'),
          // s/z ratio Δ direction is neutral — clinical signal is
          // deviance from 1.0, not directional. Same correction voice
          // 24a-fix1 applied.
          OutcomeRow(label: 's/z ratio',         baseline: n(baseAero, 's_z_ratio'),           latest: n(latestAero, 's_z_ratio'),           direction: 'neutral'),
          OutcomeRow(label: 'Words per breath',     baseline: n(baseAero, 'words_per_breath'),     latest: n(latestAero, 'words_per_breath'),     direction: 'higher'),
          // 27b — adds syllables/breath alongside words/breath since
          // Section 4A captures both.
          OutcomeRow(label: 'Syllables per breath', baseline: n(baseAero, 'syllables_per_breath'), latest: n(latestAero, 'syllables_per_breath'), direction: 'higher'),
        ]),
        OutcomeGroup(label: 'DDK', rows: [
          OutcomeRow(label: 'puh / sec',     baseline: n(baseDdk, 'puh_per_sec'),     latest: n(latestDdk, 'puh_per_sec'),     direction: 'higher'),
          OutcomeRow(label: 'tuh / sec',     baseline: n(baseDdk, 'tuh_per_sec'),     latest: n(latestDdk, 'tuh_per_sec'),     direction: 'higher'),
          OutcomeRow(label: 'kuh / sec',     baseline: n(baseDdk, 'kuh_per_sec'),     latest: n(latestDdk, 'kuh_per_sec'),     direction: 'higher'),
          OutcomeRow(label: 'pataka / sec',  baseline: n(baseDdk, 'pataka_per_sec'),  latest: n(latestDdk, 'pataka_per_sec'),  direction: 'higher'),
        ]),
        OutcomeGroup(label: 'Subsystem Severity (0=None, 4=Profound)', rows: [
          OutcomeRow(label: 'Respiration',   baseline: sevToInt(baseSub, 'respiration_severity'),  latest: sevToInt(latestSub, 'respiration_severity'),  direction: 'lower'),
          OutcomeRow(label: 'Phonation',     baseline: sevToInt(baseSub, 'phonation_severity'),    latest: sevToInt(latestSub, 'phonation_severity'),    direction: 'lower'),
          OutcomeRow(label: 'Articulation',  baseline: sevToInt(baseSub, 'articulation_severity'), latest: sevToInt(latestSub, 'articulation_severity'), direction: 'lower'),
          OutcomeRow(label: 'Resonance',     baseline: sevToInt(baseSub, 'resonance_severity'),    latest: sevToInt(latestSub, 'resonance_severity'),    direction: 'lower'),
          OutcomeRow(label: 'Prosody',       baseline: sevToInt(baseSub, 'prosody_severity'),      latest: sevToInt(latestSub, 'prosody_severity'),      direction: 'lower'),
        ]),
        OutcomeGroup(label: 'Intelligibility', rows: [
          OutcomeRow(label: 'ICS total',                      baseline: n(baseInt, 'ics_total'),                          latest: n(latestInt, 'ics_total'),                          direction: 'higher'),
          OutcomeRow(label: 'ICS average',                    baseline: n(baseInt, 'ics_average'),                        latest: n(latestInt, 'ics_average'),                        direction: 'higher'),
          OutcomeRow(label: 'CSIM single-word',               baseline: n(baseInt, 'csim_single_word_pct'),               latest: n(latestInt, 'csim_single_word_pct'),               unit: '%', direction: 'higher'),
          OutcomeRow(label: 'CSIM sentence',                  baseline: n(baseInt, 'csim_sentence_pct'),                  latest: n(latestInt, 'csim_sentence_pct'),                  unit: '%', direction: 'higher'),
          OutcomeRow(label: 'Familiar primary listeners',     baseline: n(baseInt, 'listener_familiar_primary_pct'),      latest: n(latestInt, 'listener_familiar_primary_pct'),      unit: '%', direction: 'higher'),
          OutcomeRow(label: 'Family (non-primary)',           baseline: n(baseInt, 'listener_family_pct'),                latest: n(latestInt, 'listener_family_pct'),                unit: '%', direction: 'higher'),
          OutcomeRow(label: 'Peers',                          baseline: n(baseInt, 'listener_peers_pct'),                 latest: n(latestInt, 'listener_peers_pct'),                 unit: '%', direction: 'higher'),
          OutcomeRow(label: 'Teachers',                       baseline: n(baseInt, 'listener_teachers_pct'),              latest: n(latestInt, 'listener_teachers_pct'),              unit: '%', direction: 'higher'),
          OutcomeRow(label: 'Unfamiliar adults',              baseline: n(baseInt, 'listener_unfamiliar_adults_pct'),     latest: n(latestInt, 'listener_unfamiliar_adults_pct'),     unit: '%', direction: 'higher'),
          OutcomeRow(label: 'Familiar contexts',              baseline: n(baseInt, 'context_familiar_pct'),               latest: n(latestInt, 'context_familiar_pct'),               unit: '%', direction: 'higher'),
          OutcomeRow(label: 'Unfamiliar contexts',            baseline: n(baseInt, 'context_unfamiliar_pct'),             latest: n(latestInt, 'context_unfamiliar_pct'),             unit: '%', direction: 'higher'),
          // Words per minute is age-dependent; direction stays neutral
          // until norms-anchored Δ logic ships.
          OutcomeRow(label: 'Words per minute',               baseline: n(baseInt, 'words_per_minute'),                   latest: n(latestInt, 'words_per_minute'),                   direction: 'neutral'),
        ]),
        OutcomeGroup(label: 'Functional Communication & QoL', rows: [
          OutcomeRow(label: 'FOCUS-34 total',         baseline: n(baseQol, 'focus34_total'),            latest: n(latestQol, 'focus34_total'),            direction: 'higher'),
          OutcomeRow(label: 'Parent confidence',      baseline: n(baseQol, 'parent_confidence_rating'), latest: n(latestQol, 'parent_confidence_rating'), direction: 'higher'),
          OutcomeRow(label: 'Teacher impact',         baseline: n(baseQol, 'teacher_impact_rating'),    latest: n(latestQol, 'teacher_impact_rating'),    direction: 'higher'),
          OutcomeRow(label: 'Peer interaction',       baseline: n(baseQol, 'peer_interaction_rating'),  latest: n(latestQol, 'peer_interaction_rating'),  direction: 'higher'),
        ]),
      ],
    );
  }

  /// Adds a follow-up assessment pointing at the original baseline.
  Future<String> addFollowUp({
    required String clientId,
    required String baselineAssessmentId,
    String? visitId,
  }) async {
    final inserted = await _sb
        .from('ped_dysarthria_assessments')
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
