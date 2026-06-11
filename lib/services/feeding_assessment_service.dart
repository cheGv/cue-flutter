// lib/services/feeding_assessment_service.dart
//
// Childhood Feeding — Phase 1 (capture). Parent record + typed save/load for
// the feeding capture surface. Mirrors SsdAssessmentService: a flat typed
// parent (feeding_assessments) patched per logical group through an ALLOWLIST
// guard, plus multi-row children with NO unique constraint — so child rows are
// managed by explicit insert / update-by-id / delete (no upsert). Persistence
// is direct save-on-change / save-on-blur.
//
// feeding_ladder_bands is SEEDED (7 developmental bands, content version-
// frozen into the rows from kFeedingLadderBands — clinical provenance: a past
// assessment keeps the reference text it was marked against). feeding_behaviors
// is CLINICIAN-ADDED — the surface inserts/removes rows as the clinician works.
//
// SAFETY: the seed carries ONLY structural/reference fields. clinician_marking
// and notes are never seeded — empty stays empty; Cue never fabricates a mark.
//
// RLS is disabled in the sandbox (hardening is a later migration); clinician_id
// has no server default, so it is set explicitly from the authenticated user.

import 'package:supabase_flutter/supabase_flutter.dart';

import '../constants/feeding_ladder_content.dart';

class FeedingAssessmentService {
  FeedingAssessmentService._([this._injectedClient]);
  static final instance = FeedingAssessmentService._();

  /// Test seam: a service bound to a specific Supabase client (e.g. a directly
  /// constructed sandbox client in an integration test). Production uses
  /// [instance], which reads Supabase.instance.client.
  factory FeedingAssessmentService.withClient(SupabaseClient client) =>
      FeedingAssessmentService._(client);

  final SupabaseClient? _injectedClient;

  SupabaseClient get _sb => _injectedClient ?? Supabase.instance.client;

  /// Typed columns the surface may PATCH on feeding_assessments. A key outside
  /// this set fails loudly rather than silently no-opping.
  static const Set<String> assessmentColumns = {
    'age_months',
    'jaw_stability',
    'jaw_stability_notes',
    'jaw_lip_dissociation',
    'jaw_lip_dissociation_notes',
    'jaw_tongue_dissociation',
    'jaw_tongue_dissociation_notes',
    'lip_control',
    'lip_control_notes',
    'tongue_control',
    'tongue_control_notes',
    'capture_notes',
  };

  /// Child tables the generic row methods may touch.
  static const Set<String> childTables = {
    'feeding_ladder_bands',
    'feeding_behaviors',
  };

  // ── Parent ─────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> loadOrCreate({required String clientId}) async {
    final existing = await _sb
        .from('feeding_assessments')
        .select()
        .eq('client_id', clientId)
        .order('created_at', ascending: false)
        .limit(1)
        .maybeSingle();
    if (existing != null) return Map<String, dynamic>.from(existing);
    final inserted = await _sb
        .from('feeding_assessments')
        .insert({
          'client_id': clientId,
          'clinician_id': _sb.auth.currentUser?.id,
        })
        .select()
        .single();
    return Map<String, dynamic>.from(inserted);
  }

  Future<void> saveAssessmentColumns({
    required String assessmentId,
    required Map<String, dynamic> data,
  }) async {
    if (data.isEmpty) return;
    for (final key in data.keys) {
      if (!assessmentColumns.contains(key)) {
        throw ArgumentError(
            'saveAssessmentColumns: $key is not a feeding_assessments column');
      }
    }
    await _sb.from('feeding_assessments').update(data).eq('id', assessmentId);
  }

  // ── Generic child-row ops (insert / update-by-id / delete / load) ───

  Future<List<Map<String, dynamic>>> loadRows(
    String table,
    String assessmentId, {
    String orderBy = 'created_at',
    bool ascending = true,
  }) async {
    _assertChild(table);
    final rows = await _sb
        .from(table)
        .select()
        .eq('feeding_assessment_id', assessmentId)
        .order(orderBy, ascending: ascending);
    return (rows as List)
        .whereType<Map>()
        .map((m) => Map<String, dynamic>.from(m))
        .toList();
  }

  Future<String> insertRow({
    required String table,
    required String assessmentId,
    required Map<String, dynamic> data,
  }) async {
    _assertChild(table);
    final r = await _sb
        .from(table)
        .insert({'feeding_assessment_id': assessmentId, ...data})
        .select('id')
        .single();
    return r['id'] as String;
  }

  Future<void> updateRow({
    required String table,
    required String rowId,
    required Map<String, dynamic> data,
  }) async {
    _assertChild(table);
    if (data.isEmpty) return;
    await _sb.from(table).update(data).eq('id', rowId);
  }

  Future<void> deleteRow({required String table, required String rowId}) async {
    _assertChild(table);
    await _sb.from(table).delete().eq('id', rowId);
  }

  // ── feeding_ladder_bands — seed the 7 bands once ─────────────────────

  /// The insert payload for one band: structural + reference fields ONLY.
  /// clinician_marking / notes are deliberately NOT here — the seed must
  /// never fabricate a clinical value (empty stays empty). Pure and static
  /// so the headless test can hold the seed to that rule.
  static Map<String, dynamic> seedRowFor(FeedingLadderBand band) => {
        'band_key': band.key,
        'band_order': band.order,
        'band_label': band.label,
        'age_min_months': band.ageMinMonths,
        'age_max_months': band.ageMaxMonths,
        'expected_texture': band.expectedTexture,
        'expected_self_feeding': band.expectedSelfFeeding,
        'expected_oral_motor': band.expectedOralMotor,
        'red_flag_prompt': band.redFlagPrompt, // DRAFT — sign-off pending
        'off_ramp_band': band.offRampBand,
      };

  /// Seeds the seven ladder bands if absent (keyed by band_key — band
  /// identity, not list position, is the invariant); returns them ordered.
  Future<List<Map<String, dynamic>>> ensureLadderBands(
      String assessmentId) async {
    final rows = await loadRows('feeding_ladder_bands', assessmentId,
        orderBy: 'band_order', ascending: true);
    final byKey = <String, Map<String, dynamic>>{};
    for (final r in rows) {
      final k = r['band_key'];
      if (k is String) byKey[k] = r;
    }
    for (final band in kFeedingLadderBands) {
      if (byKey.containsKey(band.key)) continue;
      await insertRow(
        table: 'feeding_ladder_bands',
        assessmentId: assessmentId,
        data: seedRowFor(band),
      );
    }
    return loadRows('feeding_ladder_bands', assessmentId,
        orderBy: 'band_order', ascending: true);
  }

  void _assertChild(String table) {
    if (!childTables.contains(table)) {
      throw ArgumentError(
          'FeedingAssessmentService: $table is not a feeding child table');
    }
  }
}
