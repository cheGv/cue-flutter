// lib/models/assessment_envelope.dart
//
// The uniform "assessment" envelope produced by every assessment reader
// (CAS first; voice / ped-dysarthria / ALD to follow) and, later, folded into
// the Mirror engine's canonical_data. One shape for all protocols so the
// emptiness + source-attribution guarantees are enforced in exactly one place.
//
// Locked shape:
//   assessment: {
//     protocol, assessment_id,
//     findings: [{ source_id, source_table, field_label, value, group }],
//     measures: [{ source_id, label, value, unit, group }],
//   }
//
// Only PRESENT values ever reach here (see assessment_emptiness.dart), so
// `value` is always non-null. `source_id` is a stable path the report engine
// echoes back as a SourceClaim so every claim traces to a real captured field.

import 'package:flutter/foundation.dart';

@immutable
class AssessmentFinding {
  final String sourceId; // e.g. "cas_assessments/<row-id>/<field>"
  final String sourceTable; // e.g. "cas_assessments"
  final String fieldLabel; // human label, e.g. "Inappropriate prosody (ASHA consensus marker)"
  final Object value; // the clinician's finding (never null)
  final String group; // grouping hint, e.g. "ASHA consensus markers"

  const AssessmentFinding({
    required this.sourceId,
    required this.sourceTable,
    required this.fieldLabel,
    required this.value,
    required this.group,
  });

  Map<String, dynamic> toJson() => {
        'source_id': sourceId,
        'source_table': sourceTable,
        'field_label': fieldLabel,
        'value': value,
        'group': group,
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

@immutable
class AssessmentEnvelope {
  final String protocol; // e.g. "pediatric-cas"
  final String assessmentId;
  final List<AssessmentFinding> findings;
  final List<AssessmentMeasure> measures;

  const AssessmentEnvelope({
    required this.protocol,
    required this.assessmentId,
    this.findings = const [],
    this.measures = const [],
  });

  bool get isEmpty => findings.isEmpty && measures.isEmpty;

  Map<String, dynamic> toJson() => {
        'protocol': protocol,
        'assessment_id': assessmentId,
        'findings': findings.map((f) => f.toJson()).toList(),
        'measures': measures.map((m) => m.toJson()).toList(),
      };
}
