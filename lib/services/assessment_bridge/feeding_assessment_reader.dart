// lib/services/assessment_bridge/feeding_assessment_reader.dart
//
// The Childhood Feeding reader — sibling to ssd_assessment_reader.dart /
// cas_assessment_reader.dart, same null-safety contract. Reads the flat-typed
// parent + multi-row children —
//   feeding_assessments (+ feeding_ladder_bands, feeding_behaviors)
// — and produces the uniform `assessment` envelope, applying THE EMPTINESS
// RULE (assessment_emptiness.dart) so blank / never-entered values never
// become clinical findings.
//
// READER PROTOCOL: 'pediatric-feeding' — IDENTITY with the clinical_area slug
// (the CAS / voice convention). SSD needed a distinct singular protocol
// because its plural area slug plausibly forks into sub-protocols; feeding's
// foreseeable fork (swallowing) is a SEPARATE clinical area with its own
// surface, not a second protocol under this one, so no map entry is needed.
//
// FEEDING-SPECIFIC SAFETY (on top of the shared contract):
//   * SEEDED REFERENCE CONTENT IS NEVER A FINDING. Every feeding_ladder_bands
//     row arrives fully populated with Cue's own seeded text (band_label,
//     expected_texture / _self_feeding / _oral_motor, red_flag_prompt,
//     off_ramp_band) — reference material the clinician marked AGAINST, not
//     data about the child. Only the clinician-touched columns
//     (clinician_marking, notes) may become findings; band_label is used
//     INSIDE finding labels for context, never as a value. Without this rule
//     a freshly seeded, untouched assessment would emit dozens of "findings"
//     authored by Cue itself.
//   * airway_sign is CLASSIFICATION METADATA (set by the starter set at
//     insert, not a per-row clinician judgement) — it never becomes a
//     standalone finding; it TAGS the row's status/notes findings (label
//     suffix + a distinct group) so airway data carries with full provenance.
//   * The off-ramp's derived state (offRampActive) is DELIBERATELY not
//     emitted. Cue never computes a clinical recommendation into a report:
//     the marked airway-sign behaviour IS the captured datum; the referral
//     statement is the clinician's to write.
//   * NO MEASURES, by design. This surface stores no raw counts and derives
//     no numbers (the ladder never computes a gap, there is no severity
//     metric). An empty measures list is the correct, honest output — not a
//     gap to fill.
//
// `read(...)` is PURE (rows in -> envelope out) so the verification gate runs
// it against captured rows as fixtures. `readById(...)` is the thin loader.

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/assessment_envelope.dart';
import 'assessment_emptiness.dart';

class FeedingAssessmentReader {
  static const String protocol = 'pediatric-feeding';

  // Clinical parent columns that MAY become findings. Explicit ALLOWLIST —
  // structural/metadata columns (id, client_id, clinician_id, timestamps) are
  // excluded. Labels carry the CLINICAL TERM register (the report needs the
  // term; the observable-sign phrasing is capture-surface UX) and mirror
  // kFeedingDissociationFunctions. No column carries a clinical DB default,
  // so an untouched column is null and the emptiness rule suppresses it.
  static const List<(String column, String label, String group)>
      _findingFields = [
    ('age_months', 'Age (months)', 'Demographics'),
    ('jaw_stability', 'Jaw stability / grading', 'Oral-motor dissociation'),
    ('jaw_stability_notes', 'Jaw stability / grading — notes',
        'Oral-motor dissociation'),
    ('jaw_lip_dissociation', 'Jaw–lip dissociation', 'Oral-motor dissociation'),
    ('jaw_lip_dissociation_notes', 'Jaw–lip dissociation — notes',
        'Oral-motor dissociation'),
    ('jaw_tongue_dissociation', 'Jaw–tongue dissociation',
        'Oral-motor dissociation'),
    ('jaw_tongue_dissociation_notes', 'Jaw–tongue dissociation — notes',
        'Oral-motor dissociation'),
    ('lip_control', 'Lip control', 'Oral-motor dissociation'),
    ('lip_control_notes', 'Lip control — notes', 'Oral-motor dissociation'),
    ('tongue_control', 'Tongue control', 'Oral-motor dissociation'),
    ('tongue_control_notes', 'Tongue control — notes',
        'Oral-motor dissociation'),
    ('capture_notes', 'Capture notes', 'Notes'),
  ];

  /// Pure transform: rows in -> envelope out. Applies the emptiness rule to
  /// every candidate value. [assessment] is one feeding_assessments row; the
  /// lists are its child rows (any order).
  AssessmentEnvelope read({
    required Map<String, dynamic> assessment,
    List<Map<String, dynamic>> ladderBands = const [],
    List<Map<String, dynamic>> behaviors = const [],
  }) {
    final id = (assessment['id'] ?? '').toString();

    // ── Findings: parent flat columns (allowlist + emptiness) ──────────────
    final findings = <AssessmentFinding>[];
    for (final (column, label, group) in _findingFields) {
      final value = assessment[column];
      if (!assessmentValueIsPresent(value)) continue; // THE EMPTINESS RULE
      findings.add(AssessmentFinding(
        sourceId: 'feeding_assessments/$id/$column',
        sourceTable: 'feeding_assessments',
        fieldLabel: label,
        value: value as Object,
        group: group,
      ));
    }

    // ── Findings: ladder bands — CLINICIAN-TOUCHED COLUMNS ONLY ────────────
    // The seeded reference columns never become findings (see header).
    // band_label provides label context so each marking is self-describing
    // ("against which band?"); the marking value stays verbatim
    // (at_level | emerging | below_level | not_tested — not_tested included:
    // an explicit "not tested" is a real clinical statement, not emptiness).
    for (final row in ladderBands) {
      final rowId = (row['id'] ?? '').toString();
      final bandLabel = _labelOr(row['band_label'], '(unlabelled band)');

      final marking = row['clinician_marking'];
      if (assessmentValueIsPresent(marking)) {
        findings.add(AssessmentFinding(
          sourceId: 'feeding_ladder_bands/$rowId/clinician_marking',
          sourceTable: 'feeding_ladder_bands',
          fieldLabel: 'Feeding ladder — $bandLabel — clinician marking',
          value: marking as Object,
          group: 'Developmental feeding ladder',
        ));
      }
      final notes = row['notes'];
      if (assessmentValueIsPresent(notes)) {
        findings.add(AssessmentFinding(
          sourceId: 'feeding_ladder_bands/$rowId/notes',
          sourceTable: 'feeding_ladder_bands',
          fieldLabel: 'Feeding ladder — $bandLabel — notes',
          value: notes as Object,
          group: 'Developmental feeding ladder',
        ));
      }
    }

    // ── Findings: behaviours — status + notes; airway metadata TAGS them ───
    // status verbatim (present | absent — "absent" is a real negative
    // finding: checked, not observed). A row added but never marked and
    // never annotated contributes nothing.
    for (final row in behaviors) {
      final rowId = (row['id'] ?? '').toString();
      final label = _labelOr(row['behavior_label'], '(unlabelled behaviour)');
      final airway = row['airway_sign'] == true;
      final group =
          airway ? 'Feeding behaviours (airway signs)' : 'Feeding behaviours';
      final airwayTag = airway ? ' (airway sign)' : '';

      final status = row['status'];
      if (assessmentValueIsPresent(status)) {
        findings.add(AssessmentFinding(
          sourceId: 'feeding_behaviors/$rowId/status',
          sourceTable: 'feeding_behaviors',
          fieldLabel: 'Behaviour — $label$airwayTag',
          value: status as Object,
          group: group,
        ));
      }
      final notes = row['notes'];
      if (assessmentValueIsPresent(notes)) {
        findings.add(AssessmentFinding(
          sourceId: 'feeding_behaviors/$rowId/notes',
          sourceTable: 'feeding_behaviors',
          fieldLabel: 'Behaviour — $label$airwayTag — notes',
          value: notes as Object,
          group: group,
        ));
      }
    }

    // No measures, by design — this surface stores no raw counts and derives
    // nothing (see header). The empty list is the honest output.
    return AssessmentEnvelope(
      protocol: protocol,
      assessmentId: id,
      findings: findings,
      measures: const [],
    );
  }

  /// Convenience: load a feeding assessment + its children by id, then
  /// [read] them.
  Future<AssessmentEnvelope> readById(
    String assessmentId, {
    SupabaseClient? client,
  }) async {
    final sb = client ?? Supabase.instance.client;
    final assessment = await sb
        .from('feeding_assessments')
        .select()
        .eq('id', assessmentId)
        .single();
    return read(
      assessment: Map<String, dynamic>.from(assessment),
      ladderBands: await _kids(sb, 'feeding_ladder_bands', assessmentId),
      behaviors: await _kids(sb, 'feeding_behaviors', assessmentId),
    );
  }

  static Future<List<Map<String, dynamic>>> _kids(
      SupabaseClient sb, String table, String assessmentId) async {
    final rows =
        await sb.from(table).select().eq('feeding_assessment_id', assessmentId);
    return (rows as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  static String _labelOr(dynamic raw, String fallback) {
    final s = (raw ?? '').toString().trim();
    return s.isEmpty ? fallback : s;
  }
}
