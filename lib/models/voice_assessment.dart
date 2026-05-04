// lib/models/voice_assessment.dart
//
// Phase 4.0.7.24a — typed wrappers around the voice_assessments parent
// row. Section payloads are stored as jsonb columns and surfaced as
// Map<String, dynamic> here; the widget owns the field-shape contract
// rather than enforcing it at the Dart type layer (faster iteration
// while the protocol settles in 24b/c).
//
// Outcome comparison rolls up the typed child tables
// (voice_aerodynamic_measures, voice_perceptual_ratings,
// voice_qol_scores) into a side-by-side baseline-vs-latest snapshot
// for Section 11.

class VoiceAssessment {
  final String  id;
  final String  clientId;
  final String? visitId;
  final bool    isBaseline;
  final String? baselineAssessmentId;
  final Map<String, dynamic> caseHistoryPayload;
  final Map<String, dynamic> laryngealExamPayload;
  // Phase 4.0.7.24b — narrative jsonb columns for Sections 6 / 7.
  final Map<String, dynamic> functionalVoicePayload;
  final Map<String, dynamic> taskBasedPayload;
  final DateTime createdAt;

  const VoiceAssessment({
    required this.id,
    required this.clientId,
    this.visitId,
    required this.isBaseline,
    this.baselineAssessmentId,
    required this.caseHistoryPayload,
    required this.laryngealExamPayload,
    this.functionalVoicePayload = const {},
    this.taskBasedPayload       = const {},
    required this.createdAt,
  });

  factory VoiceAssessment.fromJson(Map<String, dynamic> json) {
    Map<String, dynamic> mapOf(String key) => (json[key] is Map)
        ? Map<String, dynamic>.from(json[key] as Map)
        : <String, dynamic>{};
    return VoiceAssessment(
      id:                     (json['id']         ?? '').toString(),
      clientId:               (json['client_id']  ?? '').toString(),
      visitId:                json['visit_id'] as String?,
      isBaseline:             json['is_baseline'] == true,
      baselineAssessmentId:   json['baseline_assessment_id'] as String?,
      caseHistoryPayload:     mapOf('case_history_payload'),
      laryngealExamPayload:   mapOf('laryngeal_exam_payload'),
      functionalVoicePayload: mapOf('functional_voice_payload'),
      taskBasedPayload:       mapOf('task_based_payload'),
      createdAt: _parseTs(json['created_at']) ?? DateTime.now(),
    );
  }

  static DateTime? _parseTs(dynamic v) {
    if (v is String && v.isNotEmpty) {
      try { return DateTime.parse(v).toLocal(); } catch (_) {}
    }
    return null;
  }
}

/// Single roll-up row in the Section 11 outcome comparison table.
/// `direction` controls Δ color logic — 'lower' means smaller is
/// better (jitter, shimmer, CAPE-V, VHI), 'higher' means larger is
/// better (MPT, F0 stability, V-RQOL), 'neutral' renders gray Δ.
class OutcomeRow {
  final String  label;
  final num?    baseline;
  final num?    latest;
  final String  unit;
  final String  direction; // 'lower' | 'higher' | 'neutral'

  const OutcomeRow({
    required this.label,
    this.baseline,
    this.latest,
    this.unit = '',
    this.direction = 'neutral',
  });

  num? get delta {
    if (baseline == null || latest == null) return null;
    return latest! - baseline!;
  }

  /// Returns 'improved' / 'regressed' / 'unchanged' / 'partial'
  /// depending on direction + delta. 'partial' means only one of
  /// baseline / latest has data.
  String get verdict {
    if (baseline == null && latest == null) return 'partial';
    if (baseline == null || latest == null) return 'partial';
    final d = delta!;
    if (d == 0) return 'unchanged';
    if (direction == 'lower') return d < 0 ? 'improved' : 'regressed';
    if (direction == 'higher') return d > 0 ? 'improved' : 'regressed';
    return 'unchanged';
  }
}

class OutcomeGroup {
  final String label;
  final List<OutcomeRow> rows;
  const OutcomeGroup({required this.label, required this.rows});
}

class OutcomeComparison {
  final String? baselineId;
  final String? latestId;
  final List<OutcomeGroup> groups;

  const OutcomeComparison({
    this.baselineId,
    this.latestId,
    required this.groups,
  });

  bool get hasFollowUp =>
      baselineId != null && latestId != null && baselineId != latestId;
}
