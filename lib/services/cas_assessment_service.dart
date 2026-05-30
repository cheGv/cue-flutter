// lib/services/cas_assessment_service.dart
//
// Phase 4.0.7.28 (COMMIT 2) — parent record + typed save/load for the
// Pediatric CAS (Childhood Apraxia of Speech) capture surface. Mirrors
// the ped_dysarthria service shape so the widget layer has the same
// API: a loadOrCreate parent, a typed-column patch, and child-row
// load/seed/update.
//
// IMPORTANT — schema difference from ped_dysarthria. The CAS child
// tables (cas_length_gradient, cas_ddk) are MULTI-row per assessment
// (one row per length level / per DDK task) and — per COMMIT 1 — carry
// NO unique constraint on cas_assessment_id. So we cannot upsert with
// onConflict the way the dysarthria typed tables (UNIQUE on the FK) do.
// Instead the widget seeds the canonical row set once via insert*Row
// (capturing each row id), then every save is a deterministic
// update-by-id. That keeps saves idempotent and avoids duplicate rows.
//
// cas_assessments itself is a flat typed table (no jsonb payloads, no
// visit_id, no is_baseline). loadOrCreate keys on client_id only.
//
// RLS is disabled in the sandbox (re-enable is 4.0.7.30); clinician_id
// has no server default on this table, so we set it explicitly from the
// authenticated user when one is present.

import 'package:supabase_flutter/supabase_flutter.dart';

class CasAssessmentService {
  CasAssessmentService._();
  static final instance = CasAssessmentService._();

  SupabaseClient get _sb => Supabase.instance.client;

  /// Typed columns the surface is allowed to PATCH on cas_assessments.
  /// Mirrors the dysarthria savePayloadSection allowlist guard so a
  /// typo in a column name fails loudly rather than silently no-ops.
  static const Set<String> _assessmentColumns = {
    'marker_inconsistent_errors',
    'marker_disrupted_transitions',
    'marker_inappropriate_prosody',
    'marker_inconsistent_notes',
    'marker_transitions_notes',
    'marker_prosody_notes',
    'oral_mech_exam',
    'groping_searching',
    'vowel_errors',
    'receptive_expressive_gap',
    'consonant_inventory',
    'vowel_inventory',
    'syllable_shape_inventory',
    'age_months',
    'capture_notes',
  };

  /// Returns the most recent cas_assessments row for a client, or
  /// creates a fresh one if none exists.
  Future<Map<String, dynamic>> loadOrCreate({required String clientId}) async {
    final existing = await _sb
        .from('cas_assessments')
        .select()
        .eq('client_id', clientId)
        .order('created_at', ascending: false)
        .limit(1)
        .maybeSingle();
    if (existing != null) {
      return Map<String, dynamic>.from(existing);
    }
    final inserted = await _sb
        .from('cas_assessments')
        .insert({
          'client_id':    clientId,
          'clinician_id': _sb.auth.currentUser?.id,
        })
        .select()
        .single();
    return Map<String, dynamic>.from(inserted);
  }

  /// PATCH typed columns on cas_assessments. Caller passes only the
  /// columns it wants to update; the rest stay untouched. Every key is
  /// validated against the allowlist.
  Future<void> saveAssessmentColumns({
    required String assessmentId,
    required Map<String, dynamic> data,
  }) async {
    if (data.isEmpty) return;
    for (final key in data.keys) {
      if (!_assessmentColumns.contains(key)) {
        throw ArgumentError(
            'saveAssessmentColumns: $key is not a cas_assessments column');
      }
    }
    await _sb
        .from('cas_assessments')
        .update(data)
        .eq('id', assessmentId);
  }

  // ── cas_length_gradient (multi-row, no unique constraint) ──────────

  /// All length-gradient rows for an assessment, ordered by level.
  Future<List<Map<String, dynamic>>> loadLengthGradient(
      String assessmentId) async {
    final rows = await _sb
        .from('cas_length_gradient')
        .select()
        .eq('cas_assessment_id', assessmentId)
        .order('level_order', ascending: true);
    return (rows as List)
        .whereType<Map>()
        .map((m) => Map<String, dynamic>.from(m))
        .toList();
  }

  /// Seeds one canonical length-gradient row and returns its id.
  Future<String> insertLengthGradientRow({
    required String assessmentId,
    required String levelLabel,
    required int levelOrder,
    String? exampleTokens,
  }) async {
    final r = await _sb
        .from('cas_length_gradient')
        .insert({
          'cas_assessment_id': assessmentId,
          'level_label':       levelLabel,
          'level_order':       levelOrder,
          'example_tokens':    exampleTokens,
        })
        .select('id')
        .single();
    return r['id'] as String;
  }

  /// Updates the accuracy band ('accurate' | 'partial' | 'inaccurate' |
  /// null) of a seeded length-gradient row by its id.
  Future<void> updateLengthGradientAccuracy({
    required String rowId,
    required String? accuracy,
  }) async {
    await _sb
        .from('cas_length_gradient')
        .update({'accuracy': accuracy})
        .eq('id', rowId);
  }

  // ── cas_ddk (multi-row, no unique constraint) ──────────────────────

  /// All DDK rows for an assessment (one per task: pa/ta/ka/pataka).
  Future<List<Map<String, dynamic>>> loadDdk(String assessmentId) async {
    final rows = await _sb
        .from('cas_ddk')
        .select()
        .eq('cas_assessment_id', assessmentId)
        .order('created_at', ascending: true);
    return (rows as List)
        .whereType<Map>()
        .map((m) => Map<String, dynamic>.from(m))
        .toList();
  }

  /// Seeds one canonical DDK task row and returns its id.
  Future<String> insertDdkRow({
    required String assessmentId,
    required String task,
  }) async {
    final r = await _sb
        .from('cas_ddk')
        .insert({
          'cas_assessment_id': assessmentId,
          'task':              task,
        })
        .select('id')
        .single();
    return r['id'] as String;
  }

  /// Updates a seeded DDK row's rate (syllables/sec) and — for the SMR
  /// pataka row — its sequence-order-error flag, by row id. Pass
  /// sequenceOrderErrors null to leave that column untouched (AMR rows).
  Future<void> updateDdkRow({
    required String rowId,
    required num? rateSylPerSec,
    bool? sequenceOrderErrors,
  }) async {
    final data = <String, dynamic>{'rate_syl_per_sec': rateSylPerSec};
    if (sequenceOrderErrors != null) {
      data['sequence_order_errors'] = sequenceOrderErrors;
    }
    await _sb.from('cas_ddk').update(data).eq('id', rowId);
  }

  // ── cas_ddk_norms (reference table; empty until verified norms load)─

  /// Loads every verified DDK norm row. The table only ever holds
  /// published, method-specified norms (population is a separate,
  /// later, verified-only task), so existence of a matching row IS the
  /// "verified" signal — there is no separate verified flag. Returns []
  /// when the table is empty, which is the intended ship-state default.
  Future<List<Map<String, dynamic>>> loadAllDdkNorms() async {
    try {
      final rows = await _sb.from('cas_ddk_norms').select();
      return (rows as List)
          .whereType<Map>()
          .map((m) => Map<String, dynamic>.from(m))
          .toList();
    } catch (_) {
      return [];
    }
  }
}
