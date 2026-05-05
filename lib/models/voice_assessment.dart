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
//
// Phase 4.0.7.25a — OutcomeRow / OutcomeGroup / OutcomeComparison
// extracted to lib/models/outcome_comparison.dart so ald_assessment.dart
// can reuse them. Voice's Section 11 reads them through this re-export.

export 'outcome_comparison.dart';

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
  // Phase 4.0.7.24c — narrative jsonb columns for Sections 8 / 10 / 15.
  // Section 12 (QoL) writes to the typed voice_qol_scores child table.
  final Map<String, dynamic> specialPopulationsPayload;
  final Map<String, dynamic> differentialDiagnosisPayload;
  final Map<String, dynamic> clinicalImpressionPayload;
  final DateTime createdAt;

  const VoiceAssessment({
    required this.id,
    required this.clientId,
    this.visitId,
    required this.isBaseline,
    this.baselineAssessmentId,
    required this.caseHistoryPayload,
    required this.laryngealExamPayload,
    this.functionalVoicePayload      = const {},
    this.taskBasedPayload            = const {},
    this.specialPopulationsPayload   = const {},
    this.differentialDiagnosisPayload = const {},
    this.clinicalImpressionPayload   = const {},
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
      functionalVoicePayload:       mapOf('functional_voice_payload'),
      taskBasedPayload:             mapOf('task_based_payload'),
      specialPopulationsPayload:    mapOf('special_populations_payload'),
      differentialDiagnosisPayload: mapOf('differential_diagnosis_payload'),
      clinicalImpressionPayload:    mapOf('clinical_impression_payload'),
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
