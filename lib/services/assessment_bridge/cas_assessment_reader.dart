// lib/services/assessment_bridge/cas_assessment_reader.dart
//
// Step 1 of the assessment data bridge: the CAS (Childhood Apraxia of Speech)
// reader. Reads the flat-typed-column capture pattern —
//   cas_assessments (parent) + cas_ddk + cas_length_gradient (children)
// — and produces the uniform `assessment` envelope (assessment_envelope.dart),
// applying THE EMPTINESS RULE (assessment_emptiness.dart) so that blank /
// never-entered values never become clinical findings.
//
// `read(...)` is PURE (takes already-loaded rows, no Supabase) so the
// verification gate can run it against real captured rows as fixtures.
// `readById(...)` is the thin convenience that loads the three tables first.

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/assessment_envelope.dart';
import 'assessment_emptiness.dart';

class CasAssessmentReader {
  static const String protocol = 'pediatric-cas';

  // Clinical columns on cas_assessments that MAY become findings, with their
  // human label and grouping. Explicit ALLOWLIST — structural/metadata columns
  // (id, client_id, clinician_id, created_at, updated_at) are deliberately NOT
  // here, so they can never be mistaken for clinical findings.
  // None of these columns carry a DB default, so an untouched column is null
  // and the emptiness rule suppresses it cleanly.
  //
  // SCALE (2026-08-02). CAS is a MIXED protocol and this list is where that
  // fact lives. The ASHA markers and the differential-evidence fields are
  // captured on the surface's shared 3-state scale — present / emerging /
  // absent, canonical lowercase (cas_assessment_surface.dart:50) — so they
  // CAN record an affirmative absence and their silence means not-captured.
  // Everything else here is open prose or a number: the inventories, the
  // oral-mech exam, capture notes, and every *_notes companion. A blank note
  // means she wrote no note — never that the thing it describes was absent.
  // Emptiness in a prose field is a fact about the field, not its subject.
  static const List<(String column, String label, String group, FindingScale scale)>
      _findingFields = [
    ('marker_inconsistent_errors', 'Inconsistent errors (ASHA consensus marker)', 'ASHA consensus markers', FindingScale.threeStatePresence),
    ('marker_disrupted_transitions', 'Disrupted lexical/phrasal transitions (ASHA consensus marker)', 'ASHA consensus markers', FindingScale.threeStatePresence),
    ('marker_inappropriate_prosody', 'Inappropriate prosody (ASHA consensus marker)', 'ASHA consensus markers', FindingScale.threeStatePresence),
    ('marker_inconsistent_notes', 'Inconsistent errors — notes', 'ASHA consensus markers', FindingScale.openValue),
    ('marker_transitions_notes', 'Disrupted transitions — notes', 'ASHA consensus markers', FindingScale.openValue),
    ('marker_prosody_notes', 'Inappropriate prosody — notes', 'ASHA consensus markers', FindingScale.openValue),
    ('oral_mech_exam', 'Oral mechanism examination', 'Oral mechanism & evidence', FindingScale.openValue),
    ('groping_searching', 'Groping / searching behaviour', 'Oral mechanism & evidence', FindingScale.threeStatePresence),
    ('vowel_errors', 'Vowel errors', 'Oral mechanism & evidence', FindingScale.threeStatePresence),
    ('receptive_expressive_gap', 'Receptive–expressive gap', 'Oral mechanism & evidence', FindingScale.threeStatePresence),
    ('consonant_inventory', 'Consonant inventory', 'Phonetic inventory', FindingScale.openValue),
    ('vowel_inventory', 'Vowel inventory', 'Phonetic inventory', FindingScale.openValue),
    ('syllable_shape_inventory', 'Syllable shape inventory', 'Phonetic inventory', FindingScale.openValue),
    ('age_months', 'Age (months)', 'Demographics', FindingScale.openValue),
    ('capture_notes', 'Capture notes', 'Notes', FindingScale.openValue),
  ];

  /// Pure transform: rows in -> envelope out. Applies the emptiness rule to
  /// every candidate value. [assessment] is one cas_assessments row;
  /// [ddkRows] / [lengthRows] are its child rows (any order).
  AssessmentEnvelope read({
    required Map<String, dynamic> assessment,
    List<Map<String, dynamic>> ddkRows = const [],
    List<Map<String, dynamic>> lengthRows = const [],
  }) {
    final id = (assessment['id'] ?? '').toString();

    // ── Findings (parent flat columns) ──────────────────────────────────────
    final findings = <AssessmentFinding>[];
    // Coverage denominators, counted over threeStatePresence fields ONLY —
    // prose has no meaningful denominator. Built alongside the findings so
    // the two can never disagree.
    final expectedByGroup = <String, int>{};
    final recordedByGroup = <String, int>{};
    for (final (column, label, group, scale) in _findingFields) {
      if (scale == FindingScale.threeStatePresence) {
        expectedByGroup[group] = (expectedByGroup[group] ?? 0) + 1;
      }
      final value = assessment[column];
      if (!assessmentValueIsPresent(value)) continue; // THE EMPTINESS RULE
      if (scale == FindingScale.threeStatePresence) {
        recordedByGroup[group] = (recordedByGroup[group] ?? 0) + 1;
      }
      findings.add(AssessmentFinding(
        sourceId: 'cas_assessments/$id/$column',
        sourceTable: 'cas_assessments',
        fieldLabel: label,
        // Verbatim — 'emerging' is clinically distinct from both neighbours
        // and is never rounded to either.
        value: value as Object,
        group: group,
        scale: scale,
      ));
    }
    final coverage = [
      for (final entry in expectedByGroup.entries)
        AssessmentCoverage(
          group: entry.key,
          expected: entry.value,
          recorded: recordedByGroup[entry.key] ?? 0,
        ),
    ];

    // ── Measures (child rows) ───────────────────────────────────────────────
    final measures = <AssessmentMeasure>[];

    // DDK: one rate per task. rate_syl_per_sec has NO DB default -> null when
    // untouched -> suppressed by the rule.
    //
    // NOTE (clinically-meaningful-default subtlety, flagged): cas_ddk.
    // sequence_order_errors carries a DB DEFAULT of `false`. A stored `false`
    // is therefore indistinguishable from "never touched", so emitting it would
    // risk FABRICATING a "no sequencing errors" claim the clinician never made
    // (and it is only meaningful for the pataka task anyway). We therefore do
    // NOT emit sequence_order_errors here — under-reporting (safe) over
    // fabricating (unsafe). Capturing genuine pataka sequencing findings needs a
    // touched-vs-default signal (e.g. the surface writing null when untouched,
    // or a separate "assessed" flag) and is deferred to a later, deliberate step.
    for (final row in ddkRows) {
      final rowId = (row['id'] ?? '').toString();
      final task = (row['task'] ?? '').toString();
      final rate = row['rate_syl_per_sec'];
      if (assessmentValueIsPresent(rate)) {
        measures.add(AssessmentMeasure(
          sourceId: 'cas_ddk/$rowId/rate_syl_per_sec',
          label: 'Diadochokinetic rate — /$task/',
          value: rate as Object,
          unit: 'syllables/sec',
          group: 'Diadochokinetic rates',
        ));
      }
    }

    // Length gradient: one accuracy per level. accuracy has NO DB default ->
    // null when untouched -> suppressed. level_label / example_tokens are seeded
    // structure (not clinician findings) and are used only for the label.
    for (final row in lengthRows) {
      final rowId = (row['id'] ?? '').toString();
      final level = (row['level_label'] ?? '').toString();
      final accuracy = row['accuracy'];
      if (assessmentValueIsPresent(accuracy)) {
        measures.add(AssessmentMeasure(
          sourceId: 'cas_length_gradient/$rowId/accuracy',
          label: 'Length-gradient accuracy — $level',
          value: accuracy as Object,
          group: 'Length gradient',
        ));
      }
    }

    return AssessmentEnvelope(
      protocol: protocol,
      assessmentId: id,
      findings: findings,
      measures: measures,
      coverage: coverage,
      // CAS capture has no section-completion contract (no completed_at
      // stamps), so the incomplete-fill anomaly class cannot arise here.
      anomalies: const [],
    );
  }

  /// Convenience: load a CAS assessment + its children by id, then [read] them.
  /// (Not exercised by the pure-transform verification gate.)
  Future<AssessmentEnvelope> readById(
    String assessmentId, {
    SupabaseClient? client,
  }) async {
    final sb = client ?? Supabase.instance.client;
    final assessment = await sb
        .from('cas_assessments')
        .select()
        .eq('id', assessmentId)
        .single();
    final ddk = await sb
        .from('cas_ddk')
        .select()
        .eq('cas_assessment_id', assessmentId);
    final length = await sb
        .from('cas_length_gradient')
        .select()
        .eq('cas_assessment_id', assessmentId);
    return read(
      assessment: Map<String, dynamic>.from(assessment),
      ddkRows: (ddk as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList(),
      lengthRows: (length as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList(),
    );
  }
}
