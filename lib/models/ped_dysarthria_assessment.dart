// lib/models/ped_dysarthria_assessment.dart
//
// Phase 4.0.7.27a — typed wrappers for the Pediatric Dysarthria
// surface. Mirrors voice/ALD: parent row carries 13 jsonb section
// payloads + a typed Section 1 spine (developmental ages, etiology,
// CP classification levels, Mayo type, two SLP-toggled cross-domain
// flags). Five typed measure tables hang off the assessment for
// numeric capture (aerodynamic, DDK, subsystem severity,
// intelligibility, QoL).
//
// All voice/ALD 9-fix lessons are baked in: clinician_id defaults
// to auth.uid() server-side, RLS is disabled (4.0.7.30 hardens),
// every typed child table enforces UNIQUE(ped_dysarthria_assessment_id)
// so saves use .upsert with onConflict.

export 'outcome_comparison.dart';

class PedDysarthriaAssessment {
  final String  id;
  final String  clientId;
  final String? visitId;
  final bool    isBaseline;
  final String? baselineAssessmentId;

  // ── Typed Section 1 spine ────────────────────────────────────────
  // Developmental ages (5 of them) each pair an integer age-in-months
  // with a source tag ('Informal SLP estimate' / 'Formal cognitive
  // battery' / 'External report (specify in notes)'). Stored as 10
  // separate parent columns so future indexed queries on
  // expressive-vs-speech-age gaps don't have to dig into jsonb.
  final int?    mentalAgeMonths;
  final String? mentalAgeSource;
  final int?    receptiveLanguageAgeMonths;
  final String? receptiveLanguageAgeSource;
  final int?    expressiveLanguageAgeMonths;
  final String? expressiveLanguageAgeSource;
  final int?    speechAgeMonths;
  final String? speechAgeSource;
  final int?    socialPragmaticAgeMonths;
  final String? socialPragmaticAgeSource;

  // Etiology + CP classification + Mayo. CP levels stay null when
  // etiology isn't cerebral_palsy; Mayo can be filled regardless.
  final String? etiologyCategory;
  final String? cpSubtype;
  final String? gmfcsLevel;
  final String? macsLevel;
  final String? cfcsLevel;
  final String? edacsLevel;
  final String? vfcsLevel;
  final DateTime? lastBotoxDate;
  final String? mayoType;

  // Cross-domain alert flags — SLP toggles these in Section 15. Never
  // auto-computed from clinical findings (V1 product law).
  final bool flagDysphagiaReferral;
  final bool flagAacAssessment;

  // ── 13 jsonb section payloads ────────────────────────────────────
  final Map<String, dynamic> caseHistoryPayload;
  final Map<String, dynamic> bedsideScreenPayload;
  final Map<String, dynamic> respirationPayload;
  final Map<String, dynamic> phonationPayload;
  final Map<String, dynamic> articulationPayload;
  final Map<String, dynamic> resonancePayload;
  final Map<String, dynamic> prosodyPayload;
  final Map<String, dynamic> oralMechPayload;
  // Phase 4.0.7.27b — Section 6 narrative jsonb (passage notes,
  // pause patterns, subsystem-level breakdown observations).
  final Map<String, dynamic> connectedSpeechPayload;
  final Map<String, dynamic> stimulabilityPayload;
  final Map<String, dynamic> etiologySpecificPayload;
  final Map<String, dynamic> cognitiveCommScreenPayload;
  final Map<String, dynamic> differentialDiagnosisPayload;
  final Map<String, dynamic> clinicalImpressionPayload;

  final DateTime createdAt;

  const PedDysarthriaAssessment({
    required this.id,
    required this.clientId,
    this.visitId,
    required this.isBaseline,
    this.baselineAssessmentId,
    this.mentalAgeMonths,
    this.mentalAgeSource,
    this.receptiveLanguageAgeMonths,
    this.receptiveLanguageAgeSource,
    this.expressiveLanguageAgeMonths,
    this.expressiveLanguageAgeSource,
    this.speechAgeMonths,
    this.speechAgeSource,
    this.socialPragmaticAgeMonths,
    this.socialPragmaticAgeSource,
    this.etiologyCategory,
    this.cpSubtype,
    this.gmfcsLevel,
    this.macsLevel,
    this.cfcsLevel,
    this.edacsLevel,
    this.vfcsLevel,
    this.lastBotoxDate,
    this.mayoType,
    this.flagDysphagiaReferral = false,
    this.flagAacAssessment     = false,
    this.caseHistoryPayload           = const {},
    this.bedsideScreenPayload         = const {},
    this.respirationPayload           = const {},
    this.phonationPayload             = const {},
    this.articulationPayload          = const {},
    this.resonancePayload             = const {},
    this.prosodyPayload               = const {},
    this.oralMechPayload              = const {},
    this.connectedSpeechPayload       = const {},
    this.stimulabilityPayload         = const {},
    this.etiologySpecificPayload      = const {},
    this.cognitiveCommScreenPayload   = const {},
    this.differentialDiagnosisPayload = const {},
    this.clinicalImpressionPayload    = const {},
    required this.createdAt,
  });

  factory PedDysarthriaAssessment.fromJson(Map<String, dynamic> json) {
    Map<String, dynamic> mapOf(String key) => (json[key] is Map)
        ? Map<String, dynamic>.from(json[key] as Map)
        : <String, dynamic>{};
    int? intOf(String key) => (json[key] as num?)?.toInt();
    DateTime? dateOf(String key) {
      final v = json[key];
      if (v is String && v.isNotEmpty) {
        try { return DateTime.parse(v).toLocal(); } catch (_) {}
      }
      return null;
    }
    return PedDysarthriaAssessment(
      id:                   (json['id']        ?? '').toString(),
      clientId:             (json['client_id'] ?? '').toString(),
      visitId:              json['visit_id'] as String?,
      isBaseline:           json['is_baseline'] == true,
      baselineAssessmentId: json['baseline_assessment_id'] as String?,
      mentalAgeMonths:              intOf('mental_age_months'),
      mentalAgeSource:              json['mental_age_source'] as String?,
      receptiveLanguageAgeMonths:   intOf('receptive_language_age_months'),
      // 27a-fix1 — schema source columns drop the "language_" prefix
      // (receptive_age_source / expressive_age_source) even though the
      // months columns keep it. Asymmetric but matches the migration.
      receptiveLanguageAgeSource:   json['receptive_age_source'] as String?,
      expressiveLanguageAgeMonths:  intOf('expressive_language_age_months'),
      expressiveLanguageAgeSource:  json['expressive_age_source'] as String?,
      speechAgeMonths:              intOf('speech_age_months'),
      speechAgeSource:              json['speech_age_source'] as String?,
      socialPragmaticAgeMonths:     intOf('social_pragmatic_age_months'),
      socialPragmaticAgeSource:     json['social_pragmatic_age_source'] as String?,
      etiologyCategory:    json['etiology_category'] as String?,
      cpSubtype:           json['cp_subtype']        as String?,
      gmfcsLevel:          json['gmfcs_level']       as String?,
      macsLevel:           json['macs_level']        as String?,
      cfcsLevel:           json['cfcs_level']        as String?,
      edacsLevel:          json['edacs_level']       as String?,
      vfcsLevel:           json['vfcs_level']        as String?,
      lastBotoxDate:       dateOf('last_botox_date'),
      mayoType:            json['mayo_dysarthria_type'] as String?,
      flagDysphagiaReferral: json['flag_dysphagia_referral'] == true,
      flagAacAssessment:     json['flag_aac_assessment']     == true,
      caseHistoryPayload:           mapOf('case_history_payload'),
      bedsideScreenPayload:         mapOf('bedside_screen_payload'),
      respirationPayload:           mapOf('respiration_payload'),
      phonationPayload:             mapOf('phonation_payload'),
      articulationPayload:          mapOf('articulation_payload'),
      resonancePayload:             mapOf('resonance_payload'),
      prosodyPayload:               mapOf('prosody_payload'),
      oralMechPayload:              mapOf('oral_mech_payload'),
      connectedSpeechPayload:       mapOf('connected_speech_payload'),
      stimulabilityPayload:         mapOf('stimulability_payload'),
      etiologySpecificPayload:      mapOf('etiology_specific_payload'),
      cognitiveCommScreenPayload:   mapOf('cognitive_comm_screen_payload'),
      differentialDiagnosisPayload: mapOf('differential_diagnosis_payload'),
      clinicalImpressionPayload:    mapOf('clinical_impression_payload'),
      createdAt: dateOf('created_at') ?? DateTime.now(),
    );
  }
}

/// Section 4A — typed aerodynamic measures. Wrapper exists so the
/// service's loadTypedMeasures has a place to land MPT / s-z / breath
/// metrics; the widget reads the raw row map directly today.
class AerodynamicMeasures {
  final num?    mptSeconds;
  final num?    sZRatio;
  final num?    vitalCapacityMl;
  final num?    wordsPerBreath;
  final num?    syllablesPerBreath;
  final String? breathPattern;
  final String? airWastageNotes;
  const AerodynamicMeasures({
    this.mptSeconds,
    this.sZRatio,
    this.vitalCapacityMl,
    this.wordsPerBreath,
    this.syllablesPerBreath,
    this.breathPattern,
    this.airWastageNotes,
  });
}

/// Section 4 — typed DDK rates. Field names mirror the schema's
/// ddk_regularity / ddk_accuracy columns (27b-fix1 correction).
class DdkRates {
  final num? puhPerSec;
  final num? tuhPerSec;
  final num? kuhPerSec;
  final num? patakaPerSec;
  final String? ddkRegularity;
  final String? ddkAccuracy;
  const DdkRates({
    this.puhPerSec,
    this.tuhPerSec,
    this.kuhPerSec,
    this.patakaPerSec,
    this.ddkRegularity,
    this.ddkAccuracy,
  });
}

/// Section 4 — typed five-subsystem severity row.
class SubsystemSeverity {
  final String? respirationSeverity;
  final String? phonationSeverity;
  final String? articulationSeverity;
  final String? resonanceSeverity;
  final String? prosodySeverity;
  final String? primarySubsystem;
  const SubsystemSeverity({
    this.respirationSeverity,
    this.phonationSeverity,
    this.articulationSeverity,
    this.resonanceSeverity,
    this.prosodySeverity,
    this.primarySubsystem,
  });
}

/// Section 1 E.2 + Section 6 — typed intelligibility row. Section 1's
/// E.2 group writes the listener-setting + context columns; Section 6
/// (4.0.7.27b) adds CSIM single-word / sentence and ICS items + WPM.
/// Both surfaces share one row per assessment via UNIQUE constraint
/// on ped_dysarthria_assessment_id.
class Intelligibility {
  final num? icsTotal;
  final num? icsAverage;
  final num? csimSingleWordPct;
  final num? csimSentencePct;
  final num? listenerFamiliarCaregiversPct;
  final num? listenerFamilyPct;
  final num? listenerPeersPct;
  final num? listenerTeachersPct;
  final num? listenerUnfamiliarAdultsPct;
  final num? contextFamiliarPct;
  final num? contextUnfamiliarPct;
  final num? wordsPerMinute;
  const Intelligibility({
    this.icsTotal,
    this.icsAverage,
    this.csimSingleWordPct,
    this.csimSentencePct,
    this.listenerFamiliarCaregiversPct,
    this.listenerFamilyPct,
    this.listenerPeersPct,
    this.listenerTeachersPct,
    this.listenerUnfamiliarAdultsPct,
    this.contextFamiliarPct,
    this.contextUnfamiliarPct,
    this.wordsPerMinute,
  });
}

/// Section 12 — typed pediatric dysarthria QoL row. FOCUS-34 is the
/// primary instrument; the three rating columns are caregiver /
/// teacher / peer perspective sliders for triangulation.
class PedDysQolScores {
  final num? focus34Total;
  final num? parentConfidenceRating;
  final num? teacherImpactRating;
  final num? peerInteractionRating;
  const PedDysQolScores({
    this.focus34Total,
    this.parentConfidenceRating,
    this.teacherImpactRating,
    this.peerInteractionRating,
  });
}
