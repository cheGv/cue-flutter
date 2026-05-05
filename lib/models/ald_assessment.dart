// lib/models/ald_assessment.dart
//
// Phase 4.0.7.25a — typed wrappers around the ald_assessments parent
// row + four typed child tables (ald_wab_scores, ald_cognitive_screens,
// ald_naming_measures, ald_qol_scores). Same shape as VoiceAssessment:
// jsonb section payloads stay loosely typed (Map<String, dynamic>) so
// the protocol can iterate without Dart-layer schema churn; child
// tables use light typed wrappers around the columns the widget cares
// about.
//
// OutcomeRow / OutcomeGroup / OutcomeComparison live in
// outcome_comparison.dart so both voice and ALD's Section 11 read
// them from one source.

import 'outcome_comparison.dart';
export 'outcome_comparison.dart';

class AldAssessment {
  final String  id;
  final String  clientId;
  final String? visitId;
  final bool    isBaseline;
  final String? baselineAssessmentId;

  // Parent typed columns (also mirrored from Section 1's case-history
  // payload for indexed queries — drives Section 8 etiology-subform
  // routing and outcome bucketing).
  final String?       etiologyCategory;
  final String?       acuityStage;
  final int?          timePostOnsetDays;
  final List<String>  lesionLocation;
  final DateTime?     attestedAt;

  // 11 jsonb section payloads.
  final Map<String, dynamic> caseHistoryPayload;
  final Map<String, dynamic> bedsideScreenPayload;
  final Map<String, dynamic> formalBatteryPayload;
  final Map<String, dynamic> namingPayload;
  final Map<String, dynamic> auditoryComprehensionPayload;
  final Map<String, dynamic> readingWritingPayload;
  final Map<String, dynamic> discoursePayload;
  final Map<String, dynamic> etiologySpecificPayload;
  final Map<String, dynamic> cognitiveCommScreenPayload;
  final Map<String, dynamic> differentialDiagnosisPayload;
  final Map<String, dynamic> clinicalImpressionPayload;
  // Phase 4.0.7.25c — Section 8 ships 6 etiology-specific subforms,
  // each persisted to its own jsonb column on the parent so the SLP
  // can flip between subforms without losing sibling data.
  final Map<String, dynamic> aphasiaApraxiaPayload;
  final Map<String, dynamic> tbiPayload;
  final Map<String, dynamic> rhdPayload;
  final Map<String, dynamic> dementiaPayload;
  final Map<String, dynamic> ppaPayload;
  final Map<String, dynamic> multilingualPayload;

  final DateTime createdAt;

  const AldAssessment({
    required this.id,
    required this.clientId,
    this.visitId,
    required this.isBaseline,
    this.baselineAssessmentId,
    this.etiologyCategory,
    this.acuityStage,
    this.timePostOnsetDays,
    this.lesionLocation = const [],
    this.attestedAt,
    this.caseHistoryPayload           = const {},
    this.bedsideScreenPayload         = const {},
    this.formalBatteryPayload         = const {},
    this.namingPayload                = const {},
    this.auditoryComprehensionPayload = const {},
    this.readingWritingPayload        = const {},
    this.discoursePayload             = const {},
    this.etiologySpecificPayload      = const {},
    this.cognitiveCommScreenPayload   = const {},
    this.differentialDiagnosisPayload = const {},
    this.clinicalImpressionPayload    = const {},
    this.aphasiaApraxiaPayload        = const {},
    this.tbiPayload                   = const {},
    this.rhdPayload                   = const {},
    this.dementiaPayload              = const {},
    this.ppaPayload                   = const {},
    this.multilingualPayload          = const {},
    required this.createdAt,
  });

  factory AldAssessment.fromJson(Map<String, dynamic> json) {
    Map<String, dynamic> mapOf(String key) => (json[key] is Map)
        ? Map<String, dynamic>.from(json[key] as Map)
        : <String, dynamic>{};
    List<String> listOf(String key) {
      final v = json[key];
      if (v is List) return v.map((e) => e.toString()).toList();
      return const [];
    }
    return AldAssessment(
      id:                   (json['id']        ?? '').toString(),
      clientId:             (json['client_id'] ?? '').toString(),
      visitId:              json['visit_id'] as String?,
      isBaseline:           json['is_baseline'] == true,
      baselineAssessmentId: json['baseline_assessment_id'] as String?,
      etiologyCategory:     json['etiology_category'] as String?,
      acuityStage:          json['acuity_stage'] as String?,
      timePostOnsetDays:    (json['time_post_onset_days'] as num?)?.toInt(),
      lesionLocation:       listOf('lesion_location'),
      attestedAt:           _parseTs(json['attested_at']),
      caseHistoryPayload:           mapOf('case_history_payload'),
      bedsideScreenPayload:         mapOf('bedside_screen_payload'),
      formalBatteryPayload:         mapOf('formal_battery_payload'),
      namingPayload:                mapOf('naming_payload'),
      auditoryComprehensionPayload: mapOf('auditory_comprehension_payload'),
      readingWritingPayload:        mapOf('reading_writing_payload'),
      discoursePayload:             mapOf('discourse_payload'),
      etiologySpecificPayload:      mapOf('etiology_specific_payload'),
      cognitiveCommScreenPayload:   mapOf('cognitive_comm_screen_payload'),
      differentialDiagnosisPayload: mapOf('differential_diagnosis_payload'),
      clinicalImpressionPayload:    mapOf('clinical_impression_payload'),
      aphasiaApraxiaPayload:        mapOf('aphasia_apraxia_payload'),
      tbiPayload:                   mapOf('tbi_payload'),
      rhdPayload:                   mapOf('rhd_payload'),
      dementiaPayload:              mapOf('dementia_payload'),
      ppaPayload:                   mapOf('ppa_payload'),
      multilingualPayload:          mapOf('multilingual_payload'),
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

/// Typed WAB-R subscores. AQ + CQ are persisted server-side once
/// computed but the widget recomputes them locally for live display.
class WabScores {
  final String? batteryVersion;
  final String? languageAdministered;
  final num?    spontaneousInfo;
  final num?    spontaneousFluency;
  final num?    avcYesNo;
  final num?    avcWordRecognition;
  final num?    avcSequentialCommands;
  final num?    repetitionScore;
  final num?    namingObject;
  final num?    namingWordFluency;
  final num?    namingSentenceCompletion;
  final num?    namingResponsiveSpeech;
  final num?    readingScore;
  final num?    writingScore;
  final num?    aphasiaQuotient;
  final num?    corticalQuotient;
  final String? aphasiaTypeClassification;
  final String? notes;

  const WabScores({
    this.batteryVersion,
    this.languageAdministered,
    this.spontaneousInfo,
    this.spontaneousFluency,
    this.avcYesNo,
    this.avcWordRecognition,
    this.avcSequentialCommands,
    this.repetitionScore,
    this.namingObject,
    this.namingWordFluency,
    this.namingSentenceCompletion,
    this.namingResponsiveSpeech,
    this.readingScore,
    this.writingScore,
    this.aphasiaQuotient,
    this.corticalQuotient,
    this.aphasiaTypeClassification,
    this.notes,
  });
}

/// Typed MoCA + MMSE row. The schema keeps both screens on a single
/// ald_cognitive_screens row per assessment so the widget writes one
/// payload covering whichever fields the SLP filled.
class CognitiveScreens {
  final String? mocaLanguageAdministered;
  final num?    mocaVisuospatialExecutive;
  final num?    mocaNaming;
  final num?    mocaMemoryRecall;
  final num?    mocaAttention;
  final num?    mocaLanguage;
  final num?    mocaAbstraction;
  final num?    mocaOrientation;
  final bool?   mocaEducationAdjustment;
  final num?    mocaTotal;

  final String? mmseLanguageAdministered;
  final num?    mmseOrientation;
  final num?    mmseRegistration;
  final num?    mmseAttentionCalculation;
  final num?    mmseRecall;
  final num?    mmseLanguage;
  final num?    mmseTotal;

  const CognitiveScreens({
    this.mocaLanguageAdministered,
    this.mocaVisuospatialExecutive,
    this.mocaNaming,
    this.mocaMemoryRecall,
    this.mocaAttention,
    this.mocaLanguage,
    this.mocaAbstraction,
    this.mocaOrientation,
    this.mocaEducationAdjustment,
    this.mocaTotal,
    this.mmseLanguageAdministered,
    this.mmseOrientation,
    this.mmseRegistration,
    this.mmseAttentionCalculation,
    this.mmseRecall,
    this.mmseLanguage,
    this.mmseTotal,
  });
}

/// Section 4 typed measures — populated in 4.0.7.25b. Kept here so the
/// service's loadTypedMeasures has a place to land BNT / fluency totals.
class NamingMeasures {
  final num?    bntRaw;
  final num?    actionNamingRaw;
  final num?    verbalFluencySemantic;
  final num?    verbalFluencyPhonemic;
  final Map<String, dynamic> errorProfile;
  final String? cuingEffectiveness;

  const NamingMeasures({
    this.bntRaw,
    this.actionNamingRaw,
    this.verbalFluencySemantic,
    this.verbalFluencyPhonemic,
    this.errorProfile = const {},
    this.cuingEffectiveness,
  });
}

/// Section 12 typed QoL totals — populated in 4.0.7.25c.
class AldQolScores {
  final num? coastTotal;
  final num? aiq21Total;
  final num? saqol39Total;
  final num? cetiTotal;

  const AldQolScores({
    this.coastTotal,
    this.aiq21Total,
    this.saqol39Total,
    this.cetiTotal,
  });
}

// Re-export so callers can reach OutcomeComparison through this module.
typedef AldOutcomeComparison = OutcomeComparison;
