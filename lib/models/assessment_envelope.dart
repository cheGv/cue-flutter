// lib/models/assessment_envelope.dart
//
// The uniform "assessment" envelope produced by every assessment reader
// (CAS + voice today; ped-language / ped-dysarthria / ALD to follow) and, later,
// folded into the Mirror engine's canonical_data. One shape for all protocols
// so the emptiness + source-attribution guarantees are enforced in exactly one
// place.
//
// Locked shape:
//   assessment: {
//     protocol, assessment_id,
//     findings:  [{ source_id, source_table, field_label, value, group, scale }],
//     measures:  [{ source_id, label, value, unit, group }],
//     coverage:  [{ group, expected, recorded }],
//     anomalies: [{ source_id, kind, detail }],
//   }
//
// Only PRESENT values ever reach `findings` (see assessment_emptiness.dart), so
// `value` is always non-null. `source_id` is a stable path the report engine
// echoes back as a SourceClaim so every claim traces to a real captured field.
//
// ── WHAT SILENCE MEANS (added 2026-08-02) ────────────────────────────────────
//
// A finding missing from the list used to have exactly one meaning: "nothing
// was recorded". That was never true across protocols, and reading it as
// absence FABRICATES a clinical claim the SLP never made. Silence is now
// interpretable ONLY through the finding's declared [FindingScale]:
//
//   threeStatePresence -> the field records present / emerging / absent, and
//                         a missing finding means NOT CAPTURED. Absence IS
//                         expressible, so its absence from the list is
//                         informative.
//   openValue          -> prose / number / rating with no way to record
//                         "I looked and it was not there". A missing finding
//                         means NOT WRITTEN and MUST NOT be read as absence.
//
// The scale is REQUIRED on every finding and has NO DEFAULT — a default is
// precisely the mechanism by which a reader could claim a capability its
// capture model does not have. Adding a reader forces the author to decide,
// field by field.
//
// The four capture states are present / emerging / absent / not-captured.
// `emerging` is clinically distinct from BOTH neighbours and must never be
// rounded into either; the three recorded states pass through verbatim as
// `value`, and not-captured is expressed by absence-from-the-list (it is
// never emitted as a finding).
//
// ── WHY COVERAGE IS REQUIRED, NOT OPTIONAL ───────────────────────────────────
//
// Interpretable silence is not the same as COMPUTABLE silence. Without a
// denominator a drafter cannot tell how much of an instrument was actually
// administered: an assessment with 3 of 12 milestones recorded produces a
// findings list that reads exactly like a complete one, and a report built
// from it overstates the record by omission. Every threeStatePresence group
// therefore carries [AssessmentCoverage] — expected vs recorded — so the
// denominator is data, not inference. openValue groups carry no coverage:
// there is no meaningful denominator for "notes she might have written".

import 'package:flutter/foundation.dart';

/// Whether a finding's field can record an affirmative absence.
///
/// Declared per finding, never inferred, because protocols are MIXED: CAS
/// records its ASHA markers and differential evidence on the three-state
/// scale while its inventories and notes are open prose, in one envelope.
enum FindingScale {
  /// Value is one of present / emerging / absent; NULL means not-captured.
  /// A missing finding for such a field means NOT CAPTURED.
  threeStatePresence,

  /// Prose, number, or rating with no absence vocabulary. A missing finding
  /// means NOT WRITTEN — never "absent".
  openValue,
}

@immutable
class AssessmentFinding {
  final String sourceId; // e.g. "cas_assessments/<row-id>/<field>"
  final String sourceTable; // e.g. "cas_assessments"
  final String fieldLabel; // human label, e.g. "Inappropriate prosody (ASHA consensus marker)"
  final Object value; // the clinician's finding (never null)
  final String group; // grouping hint, e.g. "ASHA consensus markers"

  /// REQUIRED, no default — see the file header. Governs what this
  /// finding's ABSENCE would have meant.
  final FindingScale scale;

  const AssessmentFinding({
    required this.sourceId,
    required this.sourceTable,
    required this.fieldLabel,
    required this.value,
    required this.group,
    required this.scale,
  });

  Map<String, dynamic> toJson() => {
        'source_id': sourceId,
        'source_table': sourceTable,
        'field_label': fieldLabel,
        'value': value,
        'group': group,
        'scale': scale.name,
      };
}

@immutable
class AssessmentMeasure {
  final String sourceId; // e.g. "cas_ddk/<row-id>/rate_syl_per_sec"
  final String label; // human label, e.g. "Diadochokinetic rate — /pa/"
  final Object value; // the measured value (never null)
  final String? unit; // e.g. "syllables/sec"; null when unitless
  final String group; // e.g. "Diadochokinetic rates"

  const AssessmentMeasure({
    required this.sourceId,
    required this.label,
    required this.value,
    required this.group,
    this.unit,
  });

  Map<String, dynamic> toJson() => {
        'source_id': sourceId,
        'label': label,
        'value': value,
        'unit': unit,
        'group': group,
      };
}

/// The denominator for one threeStatePresence group: how many fields the
/// instrument offers vs how many the clinician actually recorded. Makes
/// "what was omitted" computable instead of merely inferable.
@immutable
class AssessmentCoverage {
  final String group;

  /// threeStatePresence fields this group offers. openValue fields are NOT
  /// counted — there is no denominator for prose.
  final int expected;

  /// How many of those carried a recorded value (present/emerging/absent).
  final int recorded;

  const AssessmentCoverage({
    required this.group,
    required this.expected,
    required this.recorded,
  });

  /// Fields on the three-state scale the clinician has not yet marked.
  int get notCaptured => expected - recorded;

  bool get isComplete => recorded == expected;

  Map<String, dynamic> toJson() => {
        'group': group,
        'expected': expected,
        'recorded': recorded,
      };
}

/// A defect in the RECORD, surfaced rather than interpreted.
///
/// The motivating case: a section stamped complete whose rows are still
/// unmarked — the completion fill did not finish. That NULL must not be read
/// as absent (it would fabricate a claim) NOR as not-captured (it would hide a
/// write failure). The reader emits this instead and guesses nothing.
///
/// Consumer policy, deliberately NOT the reader's business: the draft gate
/// refuses while any anomaly is present, names the section, and offers repair.
/// The proxy is never called and the REPORT never mentions it — a clinical
/// document read by parents and schools is the wrong place for an engineering
/// defect notice.
@immutable
class AssessmentAnomaly {
  /// Stable path to the affected thing, e.g.
  /// `ped_language_assessments/<id>/speech`.
  final String sourceId;

  /// Machine key, e.g. "incomplete_completion_fill".
  final String kind;

  /// One plain sentence for the clinician-facing refusal.
  final String detail;

  const AssessmentAnomaly({
    required this.sourceId,
    required this.kind,
    required this.detail,
  });

  Map<String, dynamic> toJson() => {
        'source_id': sourceId,
        'kind': kind,
        'detail': detail,
      };
}

@immutable
class AssessmentEnvelope {
  final String protocol; // e.g. "pediatric-cas"
  final String assessmentId;
  final List<AssessmentFinding> findings;
  final List<AssessmentMeasure> measures;

  /// One entry per threeStatePresence group. Empty for protocols with no
  /// three-state fields (voice today).
  final List<AssessmentCoverage> coverage;

  /// Non-empty means the record is defective — see [AssessmentAnomaly].
  final List<AssessmentAnomaly> anomalies;

  const AssessmentEnvelope({
    required this.protocol,
    required this.assessmentId,
    this.findings = const [],
    this.measures = const [],
    this.coverage = const [],
    this.anomalies = const [],
  });

  bool get isEmpty => findings.isEmpty && measures.isEmpty;

  /// True when the record carries a defect the clinician must repair before
  /// anything is drafted from it.
  bool get hasAnomalies => anomalies.isNotEmpty;

  Map<String, dynamic> toJson() => {
        'protocol': protocol,
        'assessment_id': assessmentId,
        'findings': findings.map((f) => f.toJson()).toList(),
        'measures': measures.map((m) => m.toJson()).toList(),
        'coverage': coverage.map((c) => c.toJson()).toList(),
        'anomalies': anomalies.map((a) => a.toJson()).toList(),
      };
}
