// lib/services/assessment_bridge/ped_language_assessment_reader.dart
//
// The bridge's FIRST ROW-SHAPED reader: Pediatric Language (ASHA milestone
// check). CAS and voice both read a flat typed parent — one column per
// finding, labelled by a static allowlist authored in the reader. Ped-language
// has no clinical columns on its parent at all. Every finding is a ROW in
// ped_language_milestones, and its label is the milestone text SNAPSHOTTED
// into that row at seed time.
//
// Same two-part convention as its siblings: `read(...)` is PURE (rows in,
// envelope out) so it is testable and gate-verifiable without Supabase;
// `readById(...)` is the thin loader. Same shared emptiness rule, same uniform
// envelope.
//
// ── WHERE THE FLAT-COLUMN IDIOM DOES NOT FIT ─────────────────────────────────
//
// 1. THE ALLOWLIST COLLAPSES TO ONE COLUMN. The siblings' allowlist exists so
//    that structural columns (id, timestamps, clinician_id) can never be
//    mistaken for clinical findings. Here there is exactly one clinical column
//    on the row — `status` — and everything else is structure, label, or
//    provenance. So the allowlist is not a list; it is a fact about the row
//    shape, stated once. What replaces the allowlist's guarantee is stronger
//    than a list: `status` is constrained by a DB CHECK to exactly
//    present / emerging / absent, so the vocabulary is enforced by the
//    database rather than by a constant the next editor might extend.
//
// 2. THE LABEL IS DATA, NOT CODE. `milestone_text` is the label, and it is a
//    verbatim snapshot in the row — which is the whole point (the record
//    survives dataset edits). The cost is that a label can be BLANK in a way
//    an authored constant never can. A blank label must not delete the
//    clinician's judgement, so the finding is still emitted under a synthetic
//    positional label; the source_id carries the exact row either way. Nothing
//    is invented — a positional label claims nothing clinical.
//
// 3. ROW ORDER IS NOT GIVEN. Postgres returns child rows unordered, and the
//    siblings iterate them in whatever order arrives (a latent
//    non-determinism there). A milestone list read out of order is harder to
//    check against the band, so this reader sorts explicitly by
//    (section, milestone_order) before emitting.
//
// 4. COMPLETION IS DECLARED, NOT INFERRED. This is the one place ped-language
//    is EASIER than its siblings. CAS and voice must guess whether a capture
//    is finished from how much data is present; ped-language stamps
//    <section>_completed_at when the clinician says so. Coverage therefore
//    carries `declaredComplete` as a fact, and the mismatch case — declared
//    done, rows still unmarked — is reported as an anomaly instead of being
//    silently reconciled in either direction.
//
// ── WHAT IS DELIBERATELY NOT EMITTED ─────────────────────────────────────────
//
//   ped_language_assessments.capture_notes — the column exists but NO capture
//     path writes it (verified 2026-08-02: the only writers anywhere in the
//     tree are the RLS regression harness's write probes). Emitting it would
//     mean a stray test artifact could surface as clinician prose in a report.
//     Revisit if a notes affordance ever ships on the surface.
//
//   ped_language_milestones.example_text — Cue-authored illustration ("points
//     at the dog"), seeded structure rather than anything the clinician
//     recorded. Same reasoning that keeps cas_length_gradient.level_label out
//     of the findings list.
//
//   norm_reference / library_version — NOT per-finding noise. They are one
//     statement about the whole record, so they are lifted to the envelope
//     (see AssessmentNormStatement) and cross-checked for agreement.

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/assessment_envelope.dart';
import 'assessment_emptiness.dart';

class PedLanguageAssessmentReader {
  static const String protocol = 'pediatric-language';

  /// Dataset section order — the order the clinician captured in, and the
  /// order findings and coverage are emitted in. Duplicated deliberately from
  /// kAshaSections rather than imported: that constant lives beside the
  /// capture model, and the reporting path should not start depending on the
  /// capture path's constants for its output ordering.
  static const List<String> _sectionOrder = ['speech', 'language', 'literacy'];

  /// Human group names. The surface holds an identical map for its own UI;
  /// importing it would pull a Flutter widget library into the data bridge, so
  /// three strings are duplicated on purpose.
  static const Map<String, String> _sectionLabels = {
    'speech': 'Speech',
    'language': 'Language',
    'literacy': 'Literacy',
  };

  /// Enforced by DB CHECK; restated here so a value that somehow escapes the
  /// constraint is reported rather than passed off as a three-state finding.
  static const Set<String> _statusVocabulary = {
    'present',
    'emerging',
    'absent',
  };

  /// Pure transform: rows in -> envelope out.
  ///
  /// [assessment] is one ped_language_assessments row (used ONLY for its id
  /// and the three completion stamps — it carries no clinical values).
  /// [milestoneRows] are its ped_language_milestones rows, in any order.
  AssessmentEnvelope read({
    required Map<String, dynamic> assessment,
    List<Map<String, dynamic>> milestoneRows = const [],
  }) {
    final id = (assessment['id'] ?? '').toString();
    final anomalies = <AssessmentAnomaly>[];

    final rows = [...milestoneRows]..sort(_byDatasetOrder);

    // ── Findings, one per RECORDED milestone ────────────────────────────────
    final findings = <AssessmentFinding>[];
    final expected = <String, int>{};
    final recorded = <String, int>{};

    /// Rows grouped by section, kept so the completion checks below can look
    /// at the ROWS themselves (their status and creation time) rather than
    /// only at counts. A count cannot tell an unfinished fill from a
    /// milestone that did not exist yet.
    final rowsBySection = <String, List<Map<String, dynamic>>>{};

    // Provenance is collected ONLY from rows that actually produce a finding
    // — see the norm-statement block below for why an unmarked row must not
    // vote on the caveat.
    final references = <String>{};
    final versions = <String>{};

    for (final row in rows) {
      final section = _text(row['section']);
      final rowId = _text(row['id']);
      final order = _order(row['milestone_order']);
      final group = _sectionLabels[section] ?? section;

      // Every seeded row is one thing the instrument asks — recorded or not.
      expected[section] = (expected[section] ?? 0) + 1;
      (rowsBySection[section] ??= []).add(row);

      final rawStatus = row['status'];
      // THE EMPTINESS RULE. A NULL status is not-yet-captured, and it NEVER
      // materialises as a finding: silence plus the threeStatePresence scale
      // declaration is exactly what tells a reader "not captured" rather than
      // "absent". Emitting anything here would fabricate the difference away.
      if (!assessmentValueIsPresent(rawStatus)) continue;

      recorded[section] = (recorded[section] ?? 0) + 1;
      references.add(_text(row['norm_reference']));
      versions.add(_text(row['library_version']));
      final status = rawStatus.toString().trim();

      if (!_statusVocabulary.contains(status)) {
        // Unreachable through the DB CHECK, and reported rather than trusted
        // if it ever happens: the finding claims a three-state scale, so a
        // value outside that vocabulary makes the claim false. The value is
        // still emitted verbatim (dropping it would delete a clinician's
        // judgement); the anomaly is what stops it reaching a document.
        anomalies.add(AssessmentAnomaly(
          sourceId: 'ped_language_milestones/$rowId/status',
          kind: 'unknown_vocabulary',
          detail: 'A milestone in $group holds the status "$status", which is '
              'not one of present / emerging / absent.',
        ));
      }

      final rawEvidence = row['evidence_source'];
      final provenance = _provenanceFor(status, rawEvidence);
      if (provenance == FindingProvenance.notRecorded &&
          assessmentValueIsPresent(rawEvidence)) {
        // A stored source that is neither 'observed' nor 'parent_reported'.
        // It cannot be rendered, and it must not be quietly upgraded to
        // 'observed' — so it reads as not-recorded and says so out loud.
        anomalies.add(AssessmentAnomaly(
          sourceId: 'ped_language_milestones/$rowId/evidence_source',
          kind: 'unknown_vocabulary',
          detail: 'A milestone in $group holds the evidence source '
              '"${rawEvidence.toString().trim()}", which is not one of '
              'observed / parent_reported.',
        ));
      }

      final rawLabel = row['milestone_text'];
      final label = assessmentValueIsPresent(rawLabel)
          ? rawLabel.toString().trim()
          // Positional fallback — claims nothing clinical, and keeps a real
          // judgement out of the bin. See idiom note 2.
          : '$group — milestone $order';

      findings.add(AssessmentFinding(
        sourceId: 'ped_language_milestones/$rowId/status',
        sourceTable: 'ped_language_milestones',
        fieldLabel: label,
        // Verbatim. 'emerging' is clinically distinct from both neighbours and
        // is never rounded into either.
        value: status,
        group: group,
        // Every milestone is three-state by construction — the DB CHECK is the
        // vocabulary, and 'absent' is an affirmative clinical judgement the
        // clinician declared, not a gap.
        scale: FindingScale.threeStatePresence,
        provenance: provenance,
      ));
    }

    // ── Coverage, per section, with the DECLARED completion state ───────────
    //
    // The denominator is the PERSISTED row set, not the band definition: this
    // reader deliberately does not load the dataset asset, so a partial seed
    // would understate `expected`. What makes that safe is upstream — the
    // capture controller's per-key seed self-heal reconciles the row set
    // against the band on every open, so by report time the rows ARE the band.
    final coverage = <AssessmentCoverage>[];
    for (final section in _orderedSections(expected.keys)) {
      final group = _sectionLabels[section] ?? section;
      final exp = expected[section] ?? 0;
      final rec = recorded[section] ?? 0;
      final rawStamp = assessment['${section}_completed_at'];
      final declared = assessmentValueIsPresent(rawStamp);
      final stamp = declared ? _time(rawStamp) : null;

      coverage.add(AssessmentCoverage(
        group: group,
        expected: exp,
        recorded: rec,
        declaredComplete: declared,
      ));

      if (declared) {
        // Unmarked rows that EXISTED when she pressed Done. A row seeded
        // afterwards (the controller's self-heal, once the dataset gains a
        // milestone) is not an unfinished fill — it is a question she has
        // never been shown, and calling it a failed write steers her at the
        // one repair that would write 'absent' for it. Coverage still counts
        // it, so the record stays honest about what is unanswered.
        //
        // FAILS TOWARD REPORTING for every record the server stamped: since
        // the atomic completion RPC both timestamps are the server's (the
        // stamp is now() inside the function, set once; created_at is a now()
        // default), so they compare like with like, and a row is excluded
        // only when both parse AND it is strictly newer — equal, older, or
        // unparseable still counts. What "strictly newer" cannot defend is a
        // LEGACY record stamped by a CLIENT clock. Behind the server, it can
        // precede created_at for rows that existed at declaration and excuse
        // a genuine failed fill; ahead of it, it can post-date a self-heal
        // row seeded just after the declaration and count it, so Repair
        // would write 'absent' on a question never shown. Known residual,
        // shared with the capture controller; vacuous today — verified, not
        // assumed: the sandbox holds zero ped-language rows, so nothing
        // predates the server-stamped RPC.
        final missing = rowsBySection[section]!
            .where((r) => !assessmentValueIsPresent(r['status']))
            .where((r) => !_seededAfter(r, stamp))
            .length;
        if (missing > 0) {
          // The record contradicts itself: she declared the section done,
          // which should have filled every unmarked row with an explicit
          // 'absent', yet rows are still unmarked. Reading those NULLs as
          // absent would fabricate judgements; reading them as not-captured
          // would hide a failed write. Neither — report it.
          anomalies.add(AssessmentAnomaly(
            sourceId: 'ped_language_assessments/$id/$section',
            kind: 'incomplete_completion_fill',
            detail: '$group is marked done but $missing '
                '${missing == 1 ? 'milestone is' : 'milestones are'} unmarked.',
          ));
        }
      } else {
        // THE MIRROR DEFECT, and the one that over-reports. 'absent' is only
        // ever writable once a section is declared done — by the completion
        // fill, or by a tap on an already-completed section. So an 'absent'
        // row in a section with NO stamp means the row write landed and the
        // declaration did not.
        //
        // It is reachable and it is not rare: completeSection issues the row
        // update and the parent stamp as two separate non-transactional
        // calls, and when the second fails the controller reverts only its
        // in-memory state — no compensating write is ever issued. The rows
        // stay 'absent' forever, after the clinician was told the save
        // failed. Left unflagged, they read as N affirmative "not yet doing
        // this" judgements about a child that she never declared.
        final orphaned = rowsBySection[section]!
            .where((r) => _text(r['status']) == 'absent')
            .length;
        if (orphaned > 0) {
          anomalies.add(AssessmentAnomaly(
            sourceId: 'ped_language_assessments/$id/$section',
            kind: 'absence_without_declaration',
            detail: '$group holds $orphaned '
                '${orphaned == 1 ? 'milestone' : 'milestones'} recorded as '
                'absent, but the section was never marked done. Re-run Done '
                'for that section to confirm the record.',
          ));
        }
      }
    }

    // ── The norm statement, and disagreement as an anomaly ──────────────────
    //
    // Both columns are NOT NULL with no default, stamped per row at seed time.
    // Rows CAN legitimately disagree: the controller's seed self-heal inserts
    // missing rows later, stamping the then-current dataset version — so a
    // record seeded across a version bump carries two. That is a real
    // condition, not a hypothetical, and it is not something to pick a winner
    // from: which subset of the findings each version applies to is exactly
    // what has been lost.
    //
    // SCOPE: only rows that PRODUCED A FINDING vote. This is narrower than
    // "if the rows disagree" and the narrowing is deliberate. The statement
    // caveats the claims being made, and an unmarked row makes no claim — so
    // letting one veto the statement would strip the ASHA caveat off a report
    // whose every finding shares one reference set. That failure is silent
    // (the caveat simply vanishes) and unfixable by the clinician (no repair
    // exists for a version mismatch), which makes it the worse of the two
    // errors. Disagreement among rows that DO make claims is still a genuine
    // loss and still an anomaly.
    AssessmentNormStatement? normStatement;
    if (references.length > 1 || versions.length > 1) {
      anomalies.add(AssessmentAnomaly(
        sourceId: 'ped_language_assessments/$id/norm_provenance',
        kind: 'norm_provenance_disagreement',
        detail: 'The milestones in this record do not agree on which '
            'reference set or dataset version they came from '
            '(${references.length} reference values, ${versions.length} '
            'version values).',
      ));
    } else if (references.length == 1 && versions.length == 1) {
      final reference = references.first;
      final version = versions.first;
      // A single BLANK value is not a statement — under-claim rather than
      // publish an empty caveat.
      if (reference.isNotEmpty && version.isNotEmpty) {
        normStatement = AssessmentNormStatement(
          reference: reference,
          libraryVersion: version,
        );
      }
    }

    return AssessmentEnvelope(
      protocol: protocol,
      assessmentId: id,
      findings: findings,
      // Ped-language captures no numbers — every observation is a milestone
      // judgement. The list stays empty rather than being padded with counts,
      // which would read as measurement.
      measures: const [],
      coverage: coverage,
      anomalies: anomalies,
      normStatement: normStatement,
    );
  }

  /// observed / parent_reported / not-recorded / not-applicable — kept apart.
  ///
  /// The third state is the one that matters and the one the schema makes
  /// reachable: the CHECK constraint forbids a source on an 'absent' row, but
  /// permits an affirmative row to carry none. Today's UI always writes one,
  /// so such a row means something went wrong — and rendering it as 'observed'
  /// would invent a clinical event. On an 'absent' row the same emptiness is
  /// structural, required by the constraint, and therefore not a gap at all.
  FindingProvenance _provenanceFor(String status, dynamic rawEvidence) {
    if (assessmentValueIsPresent(rawEvidence)) {
      switch (rawEvidence.toString().trim()) {
        case 'observed':
          return FindingProvenance.observed;
        case 'parent_reported':
          return FindingProvenance.parentReported;
      }
      // Unrenderable token: no USABLE source was recorded. Reported by the
      // caller as an anomaly; never silently promoted to observed.
      return FindingProvenance.notRecorded;
    }
    return status == 'absent'
        ? FindingProvenance.notApplicable
        : FindingProvenance.notRecorded;
  }

  /// Dataset order: section (speech, language, literacy), then
  /// milestone_order, then row id so the result is total and stable.
  /// Sections outside the dataset sort last, alphabetically.
  int _byDatasetOrder(Map<String, dynamic> a, Map<String, dynamic> b) {
    final sa = _sectionRank(_text(a['section']));
    final sb = _sectionRank(_text(b['section']));
    if (sa != sb) return sa.compareTo(sb);
    if (sa == _sectionOrder.length) {
      final byName = _text(a['section']).compareTo(_text(b['section']));
      if (byName != 0) return byName;
    }
    final oa = _order(a['milestone_order']);
    final ob = _order(b['milestone_order']);
    if (oa != ob) return oa.compareTo(ob);
    return _text(a['id']).compareTo(_text(b['id']));
  }

  int _sectionRank(String section) {
    final i = _sectionOrder.indexOf(section);
    return i < 0 ? _sectionOrder.length : i;
  }

  /// Known sections in dataset order, then any unknown ones alphabetically.
  List<String> _orderedSections(Iterable<String> present) {
    final seen = present.toSet();
    return [
      for (final s in _sectionOrder)
        if (seen.contains(s)) s,
      ...(seen.where((s) => !_sectionOrder.contains(s)).toList()..sort()),
    ];
  }

  String _text(Object? v) => v == null ? '' : v.toString().trim();

  /// A timestamp column, or null when absent or unparseable. Never throws —
  /// an unreadable timestamp must not take a report path down.
  DateTime? _time(Object? v) {
    if (v is DateTime) return v;
    final s = _text(v);
    return s.isEmpty ? null : DateTime.tryParse(s);
  }

  /// True only when this row demonstrably came into existence AFTER the
  /// section was declared done.
  ///
  /// Deliberately conservative. Since the atomic completion RPC the stamp is
  /// server now(), set once — the same clock as created_at's now() default —
  /// so for every server-stamped record the comparison is exact, and it
  /// fails toward reporting: if either value is missing or unparseable, or
  /// the row is not strictly newer, the answer is false and the row counts.
  ///
  /// Stated honestly, what "strictly newer" cannot defend: a LEGACY record
  /// stamped by a CLIENT clock. Behind the server, that stamp can precede
  /// created_at for rows that existed at the declaration and excuse a genuine
  /// failed fill; ahead of it, it can post-date a self-heal row seeded just
  /// after the declaration and count it, so a Repair would write 'absent' on
  /// a question never shown. A known residual shared with the capture
  /// controller (SectionalCaptureController._seededAfterDeclaration, the
  /// identical rule); vacuous today — verified, not assumed: the sandbox
  /// holds zero ped-language rows, so nothing predates the server-stamped
  /// RPC.
  bool _seededAfter(Map<String, dynamic> row, DateTime? stamp) {
    if (stamp == null) return false;
    final created = _time(row['created_at']);
    if (created == null) return false;
    return created.isAfter(stamp);
  }

  int _order(Object? v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v?.toString() ?? '') ?? 0;
  }

  /// Convenience: load one assessment + its milestone rows, then [read] them.
  ///
  /// Queries Supabase directly, like its siblings, rather than borrowing
  /// PedLanguageAssessmentService's loaders. The capture service's queries
  /// exist to serve the capture surface and are free to change with it; a
  /// reporting path that silently inherited those changes would be a
  /// surprising place to discover them.
  Future<AssessmentEnvelope> readById(
    String assessmentId, {
    SupabaseClient? client,
  }) async {
    final sb = client ?? Supabase.instance.client;
    final assessment = await sb
        .from('ped_language_assessments')
        .select()
        .eq('id', assessmentId)
        .single();
    final rows = await sb
        .from('ped_language_milestones')
        .select()
        .eq('ped_language_assessment_id', assessmentId);
    return read(
      assessment: Map<String, dynamic>.from(assessment),
      milestoneRows: (rows as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList(),
    );
  }
}
