// lib/widgets/assessment/ped_dysarthria_capture_section.dart
//
// Phase 4.0.7.27a — Pediatric Dysarthria capture surface. Sections 1
// (massive case history with developmental ages, CP classification,
// expanded comm profile E.1–E.7), 2 (bedside / initial observation),
// 11 (outcome tracking) populated. Sections 4, 5, 6, 7, 8, 9, 10, 12,
// 15 are amber-tinted stubs queued for 4.0.7.27b/c.
//
// V1 product law — NO AUTO-FLAGGING. The two parent-row flags
// (flag_dysphagia_referral / flag_aac_assessment) are SLP-toggled in
// Section 15 only. Developmental-age discrepancies, intelligibility
// drops, and AAC candidacy are all reported as neutral capture; the
// SLP makes the clinical call, not Cue.
//
// Save model:
//   - Sections 1, 2, plus future 4/5/7/8/9/10/15 narrative payloads
//     PATCH a jsonb column on ped_dysarthria_assessments.
//   - Section 1's typed Section-1 spine (5 dev-age columns + 5
//     source columns + etiology + 5 CP levels + Mayo + last_botox_date)
//     PATCHes typed parent columns via saveTypedColumns.
//   - Section 1's E.2 setting-specific intelligibility writes to the
//     ped_dys_intelligibility typed table; Section 6 (4.0.7.27b)
//     writes to the same row's ICS / CSIM / WPM columns. Both
//     surfaces share one row per assessment via UNIQUE constraint;
//     partial upsert is safe — only the columns specified in the
//     payload get touched.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../models/ped_dysarthria_assessment.dart';
import '../../services/ped_dysarthria_assessment_service.dart';

const Color _ink       = Color(0xFF0E1C36);
const Color _inkGhost  = Color(0xFF6B7690);
const Color _line      = Color(0xFFE6DDCA);
const Color _teal      = Color(0xFF2A8F84);
const Color _tealSoft  = Color(0xFFD6E8E5);
const Color _amber     = Color(0xFFD68A2B);
const Color _amberSoft = Color(0xFFF4E4C4);
const Color _coral     = Color(0xFFC25450);
const Color _green     = Color(0xFF1F8870);

// Shared severity / source scales used in multiple Section 1 rows.
const List<String> _kFreqScale = ['Rare', 'Sometimes', 'Often', 'Always'];
const List<String> _kAgeSourceOptions = [
  'Informal SLP estimate',
  'Formal cognitive battery',
  'External report (specify in notes)',
];

class PedDysarthriaCaptureSection extends StatefulWidget {
  final String  clientId;
  final String? visitId;
  const PedDysarthriaCaptureSection({
    super.key,
    required this.clientId,
    this.visitId,
  });

  @override
  State<PedDysarthriaCaptureSection> createState() =>
      _PedDysarthriaCaptureSectionState();
}

class _PedDysarthriaCaptureSectionState
    extends State<PedDysarthriaCaptureSection> {
  final _service = PedDysarthriaAssessmentService.instance;

  PedDysarthriaAssessment? _assessment;
  bool _loading = true;
  String? _error;
  OutcomeComparison? _outcome;

  // ── Section 1 — Group A: Demographic + Developmental ─────────────
  final _chronoAgeMonthsCtrl = TextEditingController();
  bool _correctedAgeUsed     = false;
  final _correctedAgeMonthsCtrl = TextEditingController();
  final _gestationalWeeksCtrl   = TextEditingController();
  final Set<String> _birthComplications = {};
  final _birthComplicationsDetailCtrl = TextEditingController();
  // Developmental milestones — all in months.
  final _msHeadCtrl    = TextEditingController();
  final _msSittingCtrl = TextEditingController();
  final _msStandCtrl   = TextEditingController();
  final _msWalkCtrl    = TextEditingController();
  final _msBreastSpoonCtrl = TextEditingController();
  final _msSpoonChewCtrl   = TextEditingController();
  final _msBabblingCtrl    = TextEditingController();
  final _msFirstWordsCtrl  = TextEditingController();
  final _msTwoWordCtrl     = TextEditingController();
  // Five typed dev-age + source pairs.
  final _mentalAgeCtrl       = TextEditingController();
  String? _mentalAgeSource;
  final _receptiveAgeCtrl    = TextEditingController();
  String? _receptiveAgeSource;
  final _expressiveAgeCtrl   = TextEditingController();
  String? _expressiveAgeSource;
  final _speechAgeCtrl       = TextEditingController();
  String? _speechAgeSource;
  final _socialPragAgeCtrl   = TextEditingController();
  String? _socialPragAgeSource;
  final _devAgeSourceDetailCtrl = TextEditingController();
  String? _educationalPlacement;
  // Languages spoken — uses _LanguageEntry pattern.
  final List<_LanguageEntry> _languages = [_LanguageEntry()];
  String? _dominantLanguage;

  // ── Section 1 — Group B: Speech History ──────────────────────────
  final _firstSpeechConcernAgeCtrl = TextEditingController();
  final Set<String> _whoFirstNoticed   = {};
  final _whoFirstNoticedOtherCtrl     = TextEditingController();
  final Set<String> _trajectory         = {};
  final _intelligibilityTimelineCtrl   = TextEditingController();
  // Family observations toggles.
  bool _famObsKnowsButCant      = false;
  bool _famObsGivesUp           = false;
  String? _famObsGivesUpFreq;
  bool _famObsGesturesForSpeech = false;
  String? _famObsGesturesFreq;
  bool _famObsWorseTired        = false;
  bool _famObsWorseEmotional    = false;
  bool _famObsWorseUnfamiliar   = false;
  bool _famObsPeersCompare      = false;
  bool _famObsFamilyModifies    = false;
  final _famObsFamilyModifiesHowCtrl = TextEditingController();
  final _droolingOnsetCtrl  = TextEditingController();
  final _droolingPatternCtrl = TextEditingController();
  final Set<String> _voiceQualityConcerns = {};

  // ── Section 1 — Group C: Medical / Neurological ──────────────────
  String? _etiology;
  // CP classification (rendered when etiology = cerebral_palsy).
  String? _cpSubtype;
  String? _gmfcsLevel;
  String? _macsLevel;
  String? _cfcsLevel;
  String? _edacsLevel;
  String? _vfcsLevel;
  // For all etiologies.
  DateTime? _lastBotoxDate;
  String? _mayoType;
  bool _imagingAvailable     = false;
  String? _imagingModality;
  DateTime? _imagingDate;
  final _imagingFindingsCtrl = TextEditingController();
  String? _hearingStatus;
  bool _audiologyDone        = false;
  final _audiologyResultsCtrl = TextEditingController();
  String? _visionStatus;
  final _visionSpecifyCtrl   = TextEditingController();
  final Set<String> _comorbidities = {};
  final _medicationsCtrl     = TextEditingController();

  // ── Section 1 — Group D: Functional Status ───────────────────────
  String? _mobility;
  String? _postureHeadControl;
  String? _handFunctionAac;
  String? _selfFeedingIndep;
  String? _droolingSeverity;
  String? _droolingFrequency;

  // ── Section 1 — Group E: Communication Profile (E.1–E.7) ─────────
  // E.1
  final Set<String> _channelsUsed = {};
  String? _mostUsedChannel;
  String? _mostEffectiveChannel;
  // E.2 — typed setting-specific intelligibility (saves to ped_dys_intelligibility)
  final Map<String, int> _settingPct = {
    'familiar_caregivers':   0,
    'family_non_primary':    0,
    'peers':                 0,
    'teachers':              0,
    'unfamiliar_adults':     0,
    'familiar_contexts':     0,
    'unfamiliar_contexts':   0,
  };
  // Track which sliders the SLP has touched so we don't write 0 to
  // every column on first save (typed nulls stay null).
  final Set<String> _settingPctTouched = {};
  // E.3
  String? _breakdownFrequency;
  final Set<String> _childRepairStrategies = {};
  final Set<String> _caregiverRepairStrategies = {};
  // E.4
  String? _bestTimeOfDay;
  String? _worstTimeOfDay;
  String? _speechMealtime;
  String? _speechPlay;
  String? _speechStructured;
  String? _speechPostureCompare;
  // E.5 — AAC (gated; state preserved when toggle off)
  bool _aacInTrial          = false;
  final Set<String> _aacTypesUsed = {};
  bool _aacCurrentlyUsed    = false;
  final Set<String> _aacAbandonReasons = {};
  String? _aacFamilyAcceptance;
  bool _totalCommApproach   = false;
  final _totalCommNotesCtrl = TextEditingController();
  // E.6 — Behavioral response (observational, no severity scale)
  String? _behavioralResponse;
  final _behavioralResponseSettingCtrl = TextEditingController();
  final Set<String> _behavioralConcerns = {};
  String? _peerInteractionQuality;
  final _educationalImpactCtrl   = TextEditingController();
  // E.7 — Family priorities and goals
  final List<TextEditingController> _familyPriorities = [
    TextEditingController(),
    TextEditingController(),
    TextEditingController(),
  ];
  final _familyGoalsCtrl    = TextEditingController();
  final _caregiverExpectationsCtrl = TextEditingController();
  final _culturalLinguisticCtrl    = TextEditingController();

  // ── Section 2 — Bedside / Initial Observation ────────────────────
  String? _cooperation;
  String? _attentionToTask;
  final _fatigueOnsetCtrl   = TextEditingController();
  String? _positioning;
  final _audioRefCtrl       = TextEditingController();
  final _totalUtterancesCtrl = TextEditingController();
  final _mluWordsCtrl       = TextEditingController();
  String? _spontaneousIntel;
  final Set<String> _firstImpressionFlags = {};
  String? _imitVowel;
  String? _imitCvVc;
  String? _imitSingleWord;
  String? _imitMultiSyllabic;

  // ── Section 4A — Respiration ─────────────────────────────────────
  String? _respVitalCapacity;
  final _respMaxAhCtrl       = TextEditingController(); // typed
  final _respWordsPerBreathCtrl = TextEditingController(); // typed
  final _respSyllablesPerBreathCtrl = TextEditingController(); // typed
  String? _respBreathSupportPattern; // typed
  String? _respPhonationSync;
  String? _respBreathDirection;
  String? _respAirWastage; // typed
  final _respNotesCtrl       = TextEditingController();
  String? _respSeverity; // typed → ped_dys_subsystem_severity

  // ── Section 4B — Phonation ───────────────────────────────────────
  final Set<String> _phonVoiceQualities = {};
  bool _phonMptSameAsAh      = false;
  final _phonMptCtrl         = TextEditingController();
  final _phonSzRatioCtrl     = TextEditingController(); // typed
  String? _phonHabitualPitch;
  String? _phonPitchRange;
  String? _phonLoudnessLevel;
  String? _phonLoudnessRange;
  String? _phonVoiceOnset;
  bool _phonGlottalIncomp    = false;
  bool _phonHyperaddux       = false;
  final _phonEntFindingsCtrl = TextEditingController();
  String? _phonSeverity;

  // ── Section 4C — Articulation + DDK ──────────────────────────────
  final _ddkPuhCtrl    = TextEditingController(); // typed
  final _ddkTuhCtrl    = TextEditingController(); // typed
  final _ddkKuhCtrl    = TextEditingController(); // typed
  final _ddkPatakaCtrl = TextEditingController(); // typed
  String? _ddkRegularity; // typed
  String? _ddkAccuracy;   // typed
  final _phonemeInventoryCtrl = TextEditingController();
  final _phonemesMasteredCtrl  = TextEditingController();
  final _phonemesEmergingCtrl  = TextEditingController();
  final _phonemesAbsentCtrl    = TextEditingController();
  final Set<String> _articImprecisionPattern = {};
  final Set<String> _articPlaceErrors        = {};
  final Set<String> _articMannerErrors       = {};
  String? _articVoicing;
  String? _articSeverity;

  // ── Section 4D — Resonance ───────────────────────────────────────
  String? _resonanceBalance;
  bool _nasalEmission        = false;
  final _nasalEmissionSoundsCtrl = TextEditingController();
  bool _nasalTurbulence      = false;
  bool _vpConnectedAdequate  = false;
  bool _vpPressureAdequate   = false;
  final _resonanceNotesCtrl  = TextEditingController();
  String? _resonanceSeverity;

  // ── Section 4E — Prosody ─────────────────────────────────────────
  String? _rate;
  // _wpmCtrl is shared with Section 6 — both surfaces write to
  // ped_dys_intelligibility.words_per_minute. Last-write-wins is the
  // contract; sharing one controller means both UI sites display the
  // same live value.
  final _wpmCtrl             = TextEditingController(); // typed (shared)
  String? _rhythm;
  final Set<String> _stressPattern = {};
  final Set<String> _intonation    = {};
  final _atypicalIntonationCtrl = TextEditingController();
  String? _phrasing;
  final _prosodyNotesCtrl    = TextEditingController();
  String? _prosodySeverity;

  /// Section 4 wrap-up — primary subsystem auto-derives from severities
  /// (any 'Severe' picks promoted; multiple severes → comma-joined).
  /// SLP can override via the chip below.
  String? _primarySubsystemOverride;

  // ── Section 5 — Oral Mech Examination ────────────────────────────
  final Set<String> _omLips      = {};
  final Set<String> _omTongue    = {};
  final Set<String> _omJaw       = {};
  String? _omSoftPalate;
  String? _omHardPalate;
  final _omHardPalateDetailCtrl = TextEditingController();
  String? _omOcclusionClass;
  bool _omMissingTeeth       = false;
  final _omMissingTeethCtrl  = TextEditingController();
  String? _omPharyngealMovement;
  String? _omGagReflex;
  String? _omDroolingPattern;
  String? _omLipClosureChewing;
  String? _omTongueLateralization;
  String? _omTongueElevation;
  String? _omTongueProtrusion;
  String? _omVelumElevation;
  String? _omCoughStrength;
  String? _omSwallowTrigger;
  String? _omOralTone;
  final Set<String> _omPrimitiveReflexes = {};
  String? _omVolitionalReflexive;
  final _omNotesCtrl         = TextEditingController();

  // ── Section 6 — Connected Speech & Intelligibility ───────────────
  String? _passageUsed;
  final _passageDetailCtrl   = TextEditingController();
  final _connectedAudioRefCtrl = TextEditingController();
  // Shares _wpmCtrl with Section 4E.
  final _pauseDurationCtrl   = TextEditingController();
  final _subsystemBreakdownCtrl = TextEditingController();
  // ICS items 1..7, each 1..5 (Never..Always).
  final Map<int, int> _icsItems = {};
  final _csimSingleWordCtrl  = TextEditingController(); // typed
  final _csimSentenceCtrl    = TextEditingController(); // typed
  final _intelligibilityNotesCtrl = TextEditingController(); // typed

  // ── Section 7 — Stimulability & Therapy Trial ────────────────────
  String? _stimLoudResponse;
  bool _stimLoudSustained    = false;
  bool _stimLoudIntelligibilityImproves = false;
  final _stimLoudNotesCtrl   = TextEditingController();
  String? _stimRateResponse;
  String? _stimPacingResponse;
  final _stimRateNotesCtrl   = TextEditingController();
  String? _stimTactileResponse;
  String? _stimVisualModelResponse;
  String? _stimPhoneticPlacementResponse;
  final _stimArticNotesCtrl  = TextEditingController();
  String? _stimOpenMouthResponse;
  String? _stimOralAirflowResponse;
  final _stimResonanceNotesCtrl = TextEditingController();
  final Set<String> _stimRecommendedApproaches = {};
  final _stimApproachReasoningCtrl = TextEditingController();

  // ── Section 8 — Etiology-specific subforms (chip-driven) ─────────
  // Multi-select chip set, persisted in etiology_specific selection
  // (kept on cerebral_palsy_payload as a sibling key to keep schema
  // surface area minimal). Each subform writes its own jsonb column.
  final Set<String> _subformsSelected = {};

  // 8A — Cerebral Palsy
  final _cpSpasticityDistCtrl   = TextEditingController();
  final _cpMovementPatternCtrl  = TextEditingController();
  final _cpPosturalSupportCtrl  = TextEditingController();
  final _cpBotoxHistoryCtrl     = TextEditingController();
  String? _cpBotoxImpactSpeech;
  final _cpOrthopedicSurgeryCtrl = TextEditingController();
  final _cpNotesCtrl            = TextEditingController();

  // 8B — Post-encephalitis / meningitis
  String? _peAcuteIllnessType;
  DateTime? _peOnsetDate;
  String? _peAcuteSeverity;
  String? _peRecoveryTrajectory;
  final _peRecoveryDetailsCtrl  = TextEditingController();
  final Set<String> _peComorbidImpairments = {};
  final _peSequelaeNotesCtrl    = TextEditingController();

  // 8C — Post-TBI
  String? _tbiMechanism;
  final _tbiOtherMechanismCtrl  = TextEditingController();
  final _tbiGcsCtrl             = TextEditingController();
  final _tbiTimePostInjuryCtrl  = TextEditingController();
  final _tbiComaDurationCtrl    = TextEditingController();
  final _tbiPtaDurationCtrl     = TextEditingController();
  String? _tbiRecoveryTrajectory;
  final Set<String> _tbiCogConcerns       = {};
  final Set<String> _tbiBehavioralConcerns = {};
  String? _tbiRanchosLevel;
  final _tbiNotesCtrl           = TextEditingController();

  // 8D — Genetic syndrome
  final _genConfirmedEtiologyCtrl = TextEditingController();
  final _genTestingDetailsCtrl  = TextEditingController();
  final _genMotorSpeechFeaturesCtrl = TextEditingController();
  final _genFamilyHistoryCtrl   = TextEditingController();
  bool _genCounselingReceived   = false;
  final _genNotesCtrl           = TextEditingController();

  // 8E — Mixed / Idiopathic
  final _miDifferentialReasoningCtrl = TextEditingController();
  final _miWorkingHypothesisCtrl     = TextEditingController();
  final Set<String> _miPendingInvestigations = {};
  final _miInvestigationTimelineCtrl = TextEditingController();
  final _miNotesCtrl                 = TextEditingController();

  // ── Section 9 — Functional Communication Screen ─────────────────
  String? _recLangApproach;
  final _recLangBatteryCtrl       = TextEditingController();
  String? _recLangProfile;
  final _recLangNotesCtrl         = TextEditingController();
  String? _expLangApproach;
  final _expLangBatteryCtrl       = TextEditingController();
  String? _expLangEstimate;
  final _expLangNotesCtrl         = TextEditingController();
  String? _symbolicPlay;
  String? _cognitiveLevel;
  final Set<String> _cogBatteries = {};
  final _cogSymbolicNotesCtrl     = TextEditingController();
  String? _aacCandidacy;
  final _aacReasoningCtrl         = TextEditingController();
  bool _augInputEffective         = false;
  final _augInputDetailsCtrl      = TextEditingController();
  String? _primaryCommConcern;
  final _commSynthesisCtrl        = TextEditingController();

  // ── Section 10 — Differential Diagnosis ─────────────────────────
  bool _ddOverrideMayo            = false;
  String? _ddMayoOverride;
  String? _ddOverallSeverity;
  final _ddSeverityRationaleCtrl  = TextEditingController();
  bool _ddOverrideSubsystems      = false;
  final Set<String> _ddSubsystemsAffectedOverride = {};
  final _ddDiffFromCasCtrl        = TextEditingController();
  final _ddDiffFromPhonologicalCtrl = TextEditingController();
  final _ddDiffFromDelayCtrl      = TextEditingController();
  final _ddDiffFromArticulationCtrl = TextEditingController();
  String? _ddHypothesisConfidence;
  final _ddHypothesisStatementCtrl = TextEditingController();
  final Set<String> _ddContributingFactors = {};
  final _ddContributingNotesCtrl   = TextEditingController();

  // ── Section 12 — QoL typed totals ───────────────────────────────
  // Per-item FOCUS-34 answers in widget memory; only total persists.
  String? _focus34AdminMode;
  final Map<int, int> _focus34Items = {};
  int _parentConfidence  = 5;
  int _teacherImpact     = 5;
  int _peerInteraction   = 5;
  final _qolNotesCtrl    = TextEditingController();
  int? _focus34TotalLoaded;
  int? _parentConfidenceLoaded;
  int? _teacherImpactLoaded;
  int? _peerInteractionLoaded;

  // ── Section 15 — Final Clinical Impression & Plan ───────────────
  final _ciFinalDxCtrl       = TextEditingController();
  final _ciIcdCodeCtrl       = TextEditingController();
  String? _ciCogLinguistic;
  String? _ciFamilySupport;
  final Set<String> _ciComorbiditiesAffectingOutcome = {};
  String? _ciEtiologyTrajectory;
  String? _ciOverallPrognosis;
  final _ciPrognosticRationaleCtrl = TextEditingController();
  final Set<String> _ciInterventions = {};
  final _ciTherapyReasoningCtrl  = TextEditingController();
  final _ciIntensityCtrl     = TextEditingController();
  final _ciSessionCountCtrl  = TextEditingController();
  final _ciSessionDurationCtrl = TextEditingController();
  String? _ciFrequency;
  final _ciDischargeCriteriaCtrl = TextEditingController();
  final _ciFunctionalOutcomesCtrl = TextEditingController();
  final Set<String> _ciReferrals = {};
  final _ciReferralReasoningCtrl = TextEditingController();
  // Cross-domain alert flags — typed parent BOOLEAN columns,
  // SLP-toggled (V1 product law: never auto-computed).
  bool _flagDysphagiaReferral    = false;
  bool _flagAacAssessment        = false;
  final Set<String> _ciCaregiverEdu = {};
  final _ciFinalNarrativeCtrl   = TextEditingController();

  // Accordion expansion — Section 1 default-expanded.
  String _expanded = 'sec1';

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    final controllers = <TextEditingController>[
      _chronoAgeMonthsCtrl, _correctedAgeMonthsCtrl, _gestationalWeeksCtrl,
      _birthComplicationsDetailCtrl,
      _msHeadCtrl, _msSittingCtrl, _msStandCtrl, _msWalkCtrl,
      _msBreastSpoonCtrl, _msSpoonChewCtrl,
      _msBabblingCtrl, _msFirstWordsCtrl, _msTwoWordCtrl,
      _mentalAgeCtrl, _receptiveAgeCtrl, _expressiveAgeCtrl,
      _speechAgeCtrl, _socialPragAgeCtrl, _devAgeSourceDetailCtrl,
      _firstSpeechConcernAgeCtrl, _whoFirstNoticedOtherCtrl,
      _intelligibilityTimelineCtrl,
      _famObsFamilyModifiesHowCtrl,
      _droolingOnsetCtrl, _droolingPatternCtrl,
      _imagingFindingsCtrl, _audiologyResultsCtrl,
      _visionSpecifyCtrl, _medicationsCtrl,
      _totalCommNotesCtrl,
      _behavioralResponseSettingCtrl, _educationalImpactCtrl,
      _familyGoalsCtrl, _caregiverExpectationsCtrl,
      _culturalLinguisticCtrl,
      _fatigueOnsetCtrl,
      _audioRefCtrl, _totalUtterancesCtrl, _mluWordsCtrl,
      ..._familyPriorities,
      // 27b — Sections 4, 5, 6, 7 controllers.
      _respMaxAhCtrl, _respWordsPerBreathCtrl, _respSyllablesPerBreathCtrl,
      _respNotesCtrl,
      _phonMptCtrl, _phonSzRatioCtrl, _phonEntFindingsCtrl,
      _ddkPuhCtrl, _ddkTuhCtrl, _ddkKuhCtrl, _ddkPatakaCtrl,
      _phonemeInventoryCtrl, _phonemesMasteredCtrl,
      _phonemesEmergingCtrl, _phonemesAbsentCtrl,
      _nasalEmissionSoundsCtrl, _resonanceNotesCtrl,
      _wpmCtrl, _atypicalIntonationCtrl, _prosodyNotesCtrl,
      _omHardPalateDetailCtrl, _omMissingTeethCtrl, _omNotesCtrl,
      _passageDetailCtrl, _connectedAudioRefCtrl,
      _pauseDurationCtrl, _subsystemBreakdownCtrl,
      _csimSingleWordCtrl, _csimSentenceCtrl, _intelligibilityNotesCtrl,
      _stimLoudNotesCtrl, _stimRateNotesCtrl, _stimArticNotesCtrl,
      _stimResonanceNotesCtrl, _stimApproachReasoningCtrl,
      // 27c — Sections 8, 9, 10, 12, 15 controllers.
      _cpSpasticityDistCtrl, _cpMovementPatternCtrl, _cpPosturalSupportCtrl,
      _cpBotoxHistoryCtrl, _cpOrthopedicSurgeryCtrl, _cpNotesCtrl,
      _peRecoveryDetailsCtrl, _peSequelaeNotesCtrl,
      _tbiOtherMechanismCtrl, _tbiGcsCtrl, _tbiTimePostInjuryCtrl,
      _tbiComaDurationCtrl, _tbiPtaDurationCtrl, _tbiNotesCtrl,
      _genConfirmedEtiologyCtrl, _genTestingDetailsCtrl,
      _genMotorSpeechFeaturesCtrl, _genFamilyHistoryCtrl, _genNotesCtrl,
      _miDifferentialReasoningCtrl, _miWorkingHypothesisCtrl,
      _miInvestigationTimelineCtrl, _miNotesCtrl,
      _recLangBatteryCtrl, _recLangNotesCtrl,
      _expLangBatteryCtrl, _expLangNotesCtrl,
      _cogSymbolicNotesCtrl, _aacReasoningCtrl, _augInputDetailsCtrl,
      _commSynthesisCtrl,
      _ddSeverityRationaleCtrl, _ddDiffFromCasCtrl,
      _ddDiffFromPhonologicalCtrl, _ddDiffFromDelayCtrl,
      _ddDiffFromArticulationCtrl, _ddHypothesisStatementCtrl,
      _ddContributingNotesCtrl,
      _qolNotesCtrl,
      _ciFinalDxCtrl, _ciIcdCodeCtrl, _ciPrognosticRationaleCtrl,
      _ciTherapyReasoningCtrl, _ciIntensityCtrl, _ciSessionCountCtrl,
      _ciSessionDurationCtrl, _ciDischargeCriteriaCtrl,
      _ciFunctionalOutcomesCtrl, _ciReferralReasoningCtrl,
      _ciFinalNarrativeCtrl,
    ];
    for (final c in controllers) {
      c.dispose();
    }
    for (final lang in _languages) {
      lang.dispose();
    }
    super.dispose();
  }

  Future<void> _bootstrap() async {
    try {
      final a = await _service.loadOrCreate(
        clientId: widget.clientId,
        visitId:  widget.visitId,
      );
      _hydrateFromAssessment(a);
      final results = await Future.wait([
        _service.loadTypedMeasures(
            assessmentId: a.id, tableName: 'ped_dys_intelligibility'),
        // 27b — Sections 4 + 6 hydrate from these typed tables.
        _service.loadTypedMeasures(
            assessmentId: a.id, tableName: 'ped_dys_aerodynamic_measures'),
        _service.loadTypedMeasures(
            assessmentId: a.id, tableName: 'ped_dys_ddk_rates'),
        _service.loadTypedMeasures(
            assessmentId: a.id, tableName: 'ped_dys_subsystem_severity'),
        // 27c — Section 12 (QoL) loads from ped_dys_qol_scores.
        _service.loadTypedMeasures(
            assessmentId: a.id, tableName: 'ped_dys_qol_scores'),
        _service.compareBaselineToLatest(widget.clientId),
      ]);
      _hydrateIntelligibility(results[0] as Map<String, dynamic>);
      _hydrateAerodynamic(results[1] as Map<String, dynamic>);
      _hydrateDdk(results[2] as Map<String, dynamic>);
      _hydrateSubsystemSeverity(results[3] as Map<String, dynamic>);
      _hydrateQol(results[4] as Map<String, dynamic>);
      _seedSubformDefaults(a);
      if (!mounted) return;
      setState(() {
        _assessment = a;
        _outcome    = results[5] as OutcomeComparison;
        _loading    = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error   = '$e';
        _loading = false;
      });
    }
  }

  void _hydrateFromAssessment(PedDysarthriaAssessment a) {
    // Typed Section 1 spine.
    _mentalAgeCtrl.text       = a.mentalAgeMonths?.toString() ?? '';
    _mentalAgeSource          = a.mentalAgeSource;
    _receptiveAgeCtrl.text    = a.receptiveLanguageAgeMonths?.toString() ?? '';
    _receptiveAgeSource       = a.receptiveLanguageAgeSource;
    _expressiveAgeCtrl.text   = a.expressiveLanguageAgeMonths?.toString() ?? '';
    _expressiveAgeSource      = a.expressiveLanguageAgeSource;
    _speechAgeCtrl.text       = a.speechAgeMonths?.toString() ?? '';
    _speechAgeSource          = a.speechAgeSource;
    _socialPragAgeCtrl.text   = a.socialPragmaticAgeMonths?.toString() ?? '';
    _socialPragAgeSource      = a.socialPragmaticAgeSource;
    _etiology                 = a.etiologyCategory;
    _cpSubtype                = a.cpSubtype;
    _gmfcsLevel               = a.gmfcsLevel;
    _macsLevel                = a.macsLevel;
    _cfcsLevel                = a.cfcsLevel;
    _edacsLevel               = a.edacsLevel;
    _vfcsLevel                = a.vfcsLevel;
    _lastBotoxDate            = a.lastBotoxDate;
    _mayoType                 = a.mayoType;

    // Section 1 jsonb payload — most fields.
    final ch = a.caseHistoryPayload;
    _chronoAgeMonthsCtrl.text = ch['chronological_age_months']?.toString() ?? '';
    _correctedAgeUsed         = ch['corrected_age_used'] == true;
    _correctedAgeMonthsCtrl.text = ch['corrected_age_months']?.toString() ?? '';
    _gestationalWeeksCtrl.text   = ch['gestational_age_weeks']?.toString() ?? '';
    final bc = ch['birth_complications'];
    if (bc is List) {
      _birthComplications
        ..clear()
        ..addAll(bc.map((e) => e.toString()));
    }
    _birthComplicationsDetailCtrl.text =
        (ch['birth_complications_detail'] as String?) ?? '';
    final ms = (ch['milestones'] is Map)
        ? Map<String, dynamic>.from(ch['milestones'] as Map)
        : const <String, dynamic>{};
    _msHeadCtrl.text          = ms['head_control']?.toString() ?? '';
    _msSittingCtrl.text       = ms['sitting']?.toString() ?? '';
    _msStandCtrl.text         = ms['standing']?.toString() ?? '';
    _msWalkCtrl.text          = ms['walking']?.toString() ?? '';
    _msBreastSpoonCtrl.text   = ms['breast_to_spoon']?.toString() ?? '';
    _msSpoonChewCtrl.text     = ms['spoon_to_chewing']?.toString() ?? '';
    _msBabblingCtrl.text      = ms['babbling']?.toString() ?? '';
    _msFirstWordsCtrl.text    = ms['first_words']?.toString() ?? '';
    _msTwoWordCtrl.text       = ms['two_word_combinations']?.toString() ?? '';
    _devAgeSourceDetailCtrl.text =
        (ch['developmental_age_source_detail'] as String?) ?? '';
    _educationalPlacement     = ch['educational_placement'] as String?;

    final langList = ch['languages_spoken'];
    if (langList is List && langList.isNotEmpty) {
      for (final e in _languages) {
        e.dispose();
      }
      _languages
        ..clear()
        ..addAll(langList.whereType<Map>().map((m) {
          final mm = Map<String, dynamic>.from(m);
          return _LanguageEntry(
            name:           (mm['name'] as String?) ?? '',
            proficiency:    mm['proficiency'] as String?,
            acquisitionAge: mm['age_of_acquisition']?.toString() ?? '',
          );
        }));
      if (_languages.isEmpty) _languages.add(_LanguageEntry());
    }
    _dominantLanguage         = ch['dominant_language'] as String?;

    // Group B
    _firstSpeechConcernAgeCtrl.text =
        ch['first_speech_concern_age_months']?.toString() ?? '';
    final wfn = ch['who_first_noticed'];
    if (wfn is List) {
      _whoFirstNoticed
        ..clear()
        ..addAll(wfn.map((e) => e.toString()));
    }
    _whoFirstNoticedOtherCtrl.text =
        (ch['who_first_noticed_other'] as String?) ?? '';
    final tr = ch['speech_trajectory'];
    if (tr is List) {
      _trajectory
        ..clear()
        ..addAll(tr.map((e) => e.toString()));
    }
    _intelligibilityTimelineCtrl.text =
        (ch['intelligibility_timeline'] as String?) ?? '';
    final fo = (ch['family_observations'] is Map)
        ? Map<String, dynamic>.from(ch['family_observations'] as Map)
        : const <String, dynamic>{};
    _famObsKnowsButCant      = fo['knows_but_cant']      == true;
    _famObsGivesUp           = fo['gives_up']            == true;
    _famObsGivesUpFreq       = fo['gives_up_freq']       as String?;
    _famObsGesturesForSpeech = fo['gestures_for_speech'] == true;
    _famObsGesturesFreq      = fo['gestures_freq']       as String?;
    _famObsWorseTired        = fo['worse_when_tired']    == true;
    _famObsWorseEmotional    = fo['worse_when_emotional'] == true;
    _famObsWorseUnfamiliar   = fo['worse_unfamiliar_env']  == true;
    _famObsPeersCompare      = fo['peers_compare_different'] == true;
    _famObsFamilyModifies    = fo['family_modifies_language'] == true;
    _famObsFamilyModifiesHowCtrl.text =
        (fo['family_modifies_how'] as String?) ?? '';
    _droolingOnsetCtrl.text  = (ch['drooling_onset']   as String?) ?? '';
    _droolingPatternCtrl.text = (ch['drooling_pattern'] as String?) ?? '';
    final vqc = ch['voice_quality_concerns'];
    if (vqc is List) {
      _voiceQualityConcerns
        ..clear()
        ..addAll(vqc.map((e) => e.toString()));
    }

    // Group C — imaging + hearing + vision + comorbidities
    _imagingAvailable        = ch['imaging_available'] == true;
    _imagingModality         = ch['imaging_modality']  as String?;
    final imgDate = ch['imaging_date'] as String?;
    if (imgDate != null && imgDate.isNotEmpty) {
      _imagingDate = DateTime.tryParse(imgDate);
    }
    _imagingFindingsCtrl.text   = (ch['imaging_findings'] as String?) ?? '';
    _hearingStatus              = ch['hearing_status'] as String?;
    _audiologyDone              = ch['audiology_done'] == true;
    _audiologyResultsCtrl.text  = (ch['audiology_results'] as String?) ?? '';
    _visionStatus               = ch['vision_status'] as String?;
    _visionSpecifyCtrl.text     = (ch['vision_specify'] as String?) ?? '';
    final cb = ch['comorbidities'];
    if (cb is List) {
      _comorbidities
        ..clear()
        ..addAll(cb.map((e) => e.toString()));
    }
    _medicationsCtrl.text       = (ch['current_medications'] as String?) ?? '';

    // Group D
    _mobility           = ch['mobility'] as String?;
    _postureHeadControl = ch['posture_head_control'] as String?;
    _handFunctionAac    = ch['hand_function_aac']     as String?;
    _selfFeedingIndep   = ch['self_feeding_independence'] as String?;
    _droolingSeverity   = ch['drooling_severity']   as String?;
    _droolingFrequency  = ch['drooling_frequency']  as String?;

    // Group E.1, E.3, E.4, E.5, E.6, E.7
    final cu = ch['channels_used'];
    if (cu is List) {
      _channelsUsed
        ..clear()
        ..addAll(cu.map((e) => e.toString()));
    }
    _mostUsedChannel       = ch['most_used_channel'] as String?;
    _mostEffectiveChannel  = ch['most_effective_channel'] as String?;
    _breakdownFrequency    = ch['breakdown_frequency'] as String?;
    final crs = ch['child_repair_strategies'];
    if (crs is List) {
      _childRepairStrategies
        ..clear()
        ..addAll(crs.map((e) => e.toString()));
    }
    final cgs = ch['caregiver_repair_strategies'];
    if (cgs is List) {
      _caregiverRepairStrategies
        ..clear()
        ..addAll(cgs.map((e) => e.toString()));
    }
    _bestTimeOfDay         = ch['best_time_of_day']  as String?;
    _worstTimeOfDay        = ch['worst_time_of_day'] as String?;
    _speechMealtime        = ch['speech_mealtime']  as String?;
    _speechPlay            = ch['speech_play']      as String?;
    _speechStructured      = ch['speech_structured'] as String?;
    _speechPostureCompare  = ch['speech_posture_compare'] as String?;

    _aacInTrial            = ch['aac_in_trial'] == true;
    final aacT = ch['aac_types_used'];
    if (aacT is List) {
      _aacTypesUsed
        ..clear()
        ..addAll(aacT.map((e) => e.toString()));
    }
    _aacCurrentlyUsed      = ch['aac_currently_used'] == true;
    final aacAb = ch['aac_abandonment_reasons'];
    if (aacAb is List) {
      _aacAbandonReasons
        ..clear()
        ..addAll(aacAb.map((e) => e.toString()));
    }
    _aacFamilyAcceptance   = ch['aac_family_acceptance'] as String?;
    _totalCommApproach     = ch['total_communication_approach'] == true;
    _totalCommNotesCtrl.text = (ch['total_communication_notes'] as String?) ?? '';

    _behavioralResponse    = ch['behavioral_response'] as String?;
    _behavioralResponseSettingCtrl.text =
        (ch['behavioral_response_setting'] as String?) ?? '';
    final bhc = ch['behavioral_concerns'];
    if (bhc is List) {
      _behavioralConcerns
        ..clear()
        ..addAll(bhc.map((e) => e.toString()));
    }
    _peerInteractionQuality = ch['peer_interaction_quality'] as String?;
    _educationalImpactCtrl.text = (ch['educational_impact'] as String?) ?? '';

    final fp = ch['family_priorities'];
    if (fp is List && fp.isNotEmpty) {
      for (final c in _familyPriorities) {
        c.dispose();
      }
      _familyPriorities
        ..clear()
        ..addAll(fp.map((e) => TextEditingController(text: e?.toString() ?? '')));
      while (_familyPriorities.length < 3) {
        _familyPriorities.add(TextEditingController());
      }
    }
    _familyGoalsCtrl.text         = (ch['family_goals'] as String?) ?? '';
    _caregiverExpectationsCtrl.text = (ch['caregiver_expectations'] as String?) ?? '';
    _culturalLinguisticCtrl.text  = (ch['cultural_linguistic_priorities'] as String?) ?? '';

    // Section 2 jsonb.
    final bs = a.bedsideScreenPayload;
    _cooperation             = bs['cooperation'] as String?;
    _attentionToTask         = bs['attention_to_task'] as String?;
    _fatigueOnsetCtrl.text   = (bs['fatigue_onset'] as String?) ?? '';
    _positioning             = bs['positioning'] as String?;
    _audioRefCtrl.text       = (bs['audio_reference'] as String?) ?? '';
    _totalUtterancesCtrl.text = bs['total_utterances']?.toString() ?? '';
    _mluWordsCtrl.text       = bs['mean_length_utterance_words']?.toString() ?? '';
    _spontaneousIntel        = bs['spontaneous_intelligibility'] as String?;
    final ff = bs['first_impression_flags'];
    if (ff is List) {
      _firstImpressionFlags
        ..clear()
        ..addAll(ff.map((e) => e.toString()));
    }
    _imitVowel        = bs['imitation_vowel']         as String?;
    _imitCvVc         = bs['imitation_cv_vc']         as String?;
    _imitSingleWord   = bs['imitation_single_word']   as String?;
    _imitMultiSyllabic = bs['imitation_multi_syllabic'] as String?;

    // 27b — Section 4 (five subsystems) — five granular jsonb columns
    // on the parent (respiration_payload through prosody_payload),
    // each carrying that subsystem's narrative fields. Typed measures
    // (aerodynamic, DDK, severity) live in their own child tables.
    final fs = a.respirationPayload;
    _respVitalCapacity        = fs['vital_capacity_estimate'] as String?;
    _respPhonationSync        = fs['phonation_sync']           as String?;
    _respBreathDirection      = fs['breath_direction']         as String?;
    _respNotesCtrl.text       = (fs['respiration_notes'] as String?) ?? '';
    // Phonation narrative
    final phon = a.phonationPayload;
    final pq = phon['voice_qualities'];
    if (pq is List) {
      _phonVoiceQualities..clear()..addAll(pq.map((e) => e.toString()));
    }
    _phonMptSameAsAh          = phon['mpt_same_as_ah'] == true;
    _phonMptCtrl.text         = phon['phonation_mpt_seconds']?.toString() ?? '';
    _phonHabitualPitch        = phon['habitual_pitch']  as String?;
    _phonPitchRange           = phon['pitch_range']     as String?;
    _phonLoudnessLevel        = phon['loudness_level']  as String?;
    _phonLoudnessRange        = phon['loudness_range']  as String?;
    _phonVoiceOnset           = phon['voice_onset']     as String?;
    _phonGlottalIncomp        = phon['glottal_incompetence'] == true;
    _phonHyperaddux           = phon['hyperadduction'] == true;
    _phonEntFindingsCtrl.text = (phon['ent_findings'] as String?) ?? '';
    // Articulation narrative
    final art = a.articulationPayload;
    _phonemeInventoryCtrl.text = (art['phoneme_inventory']  as String?) ?? '';
    _phonemesMasteredCtrl.text = (art['phonemes_mastered']  as String?) ?? '';
    _phonemesEmergingCtrl.text = (art['phonemes_emerging']  as String?) ?? '';
    _phonemesAbsentCtrl.text   = (art['phonemes_absent']    as String?) ?? '';
    final aip = art['imprecision_pattern'];
    if (aip is List) {
      _articImprecisionPattern..clear()..addAll(aip.map((e) => e.toString()));
    }
    final ape = art['place_errors'];
    if (ape is List) {
      _articPlaceErrors..clear()..addAll(ape.map((e) => e.toString()));
    }
    final ame = art['manner_errors'];
    if (ame is List) {
      _articMannerErrors..clear()..addAll(ame.map((e) => e.toString()));
    }
    _articVoicing             = art['voicing_contrast'] as String?;
    // Resonance narrative
    final res = a.resonancePayload;
    _resonanceBalance         = res['resonance_balance'] as String?;
    _nasalEmission            = res['nasal_emission']    == true;
    _nasalEmissionSoundsCtrl.text = (res['nasal_emission_sounds'] as String?) ?? '';
    _nasalTurbulence          = res['nasal_turbulence']  == true;
    _vpConnectedAdequate      = res['vp_connected_adequate'] == true;
    _vpPressureAdequate       = res['vp_pressure_adequate'] == true;
    _resonanceNotesCtrl.text  = (res['resonance_notes'] as String?) ?? '';
    // Prosody narrative
    final pr = a.prosodyPayload;
    _rate                     = pr['rate']                 as String?;
    _rhythm                   = pr['rhythm']               as String?;
    final sp = pr['stress_pattern'];
    if (sp is List) {
      _stressPattern..clear()..addAll(sp.map((e) => e.toString()));
    }
    final inton = pr['intonation'];
    if (inton is List) {
      _intonation..clear()..addAll(inton.map((e) => e.toString()));
    }
    _atypicalIntonationCtrl.text = (pr['atypical_intonation_specify'] as String?) ?? '';
    _phrasing                 = pr['phrasing'] as String?;
    _prosodyNotesCtrl.text    = (pr['prosody_notes'] as String?) ?? '';
    _primarySubsystemOverride = pr['primary_subsystem_override'] as String?;

    // 27b — Section 5 (oral mech) jsonb.
    final om = a.oralMechPayload;
    void seedSet(String key, Set<String> target) {
      final v = om[key];
      if (v is List) {
        target..clear()..addAll(v.map((e) => e.toString()));
      }
    }
    seedSet('lips',   _omLips);
    seedSet('tongue', _omTongue);
    seedSet('jaw',    _omJaw);
    _omSoftPalate           = om['soft_palate']            as String?;
    _omHardPalate           = om['hard_palate']            as String?;
    _omHardPalateDetailCtrl.text = (om['hard_palate_detail'] as String?) ?? '';
    _omOcclusionClass       = om['dentition_occlusion_class'] as String?;
    _omMissingTeeth         = om['missing_teeth'] == true;
    _omMissingTeethCtrl.text = (om['missing_teeth_detail'] as String?) ?? '';
    _omPharyngealMovement   = om['pharyngeal_wall_movement'] as String?;
    _omGagReflex            = om['gag_reflex'] as String?;
    _omDroolingPattern      = om['drooling_pattern'] as String?;
    _omLipClosureChewing    = om['lip_closure_chewing'] as String?;
    _omTongueLateralization = om['tongue_lateralization'] as String?;
    _omTongueElevation      = om['tongue_elevation'] as String?;
    _omTongueProtrusion     = om['tongue_protrusion_retraction'] as String?;
    _omVelumElevation       = om['velum_elevation_a_phonation'] as String?;
    _omCoughStrength        = om['cough_strength'] as String?;
    _omSwallowTrigger       = om['swallow_trigger'] as String?;
    _omOralTone             = om['oral_muscle_tone'] as String?;
    seedSet('primitive_reflexes', _omPrimitiveReflexes);
    _omVolitionalReflexive  = om['volitional_reflexive'] as String?;
    _omNotesCtrl.text       = (om['oral_mech_notes'] as String?) ?? '';

    // 27b — Section 6 (connected speech) jsonb.
    final cs = a.connectedSpeechPayload;
    _passageUsed                 = cs['passage_used']             as String?;
    _passageDetailCtrl.text      = (cs['passage_detail']          as String?) ?? '';
    _connectedAudioRefCtrl.text  = (cs['audio_reference']         as String?) ?? '';
    _pauseDurationCtrl.text      = (cs['pause_duration_patterns'] as String?) ?? '';
    _subsystemBreakdownCtrl.text = (cs['subsystem_breakdown']     as String?) ?? '';

    // 27b — Section 7 (stimulability) jsonb.
    final st = a.stimulabilityPayload;
    _stimLoudResponse       = st['loud_response']        as String?;
    _stimLoudSustained      = st['loud_sustained']       == true;
    _stimLoudIntelligibilityImproves = st['loud_intelligibility_improves'] == true;
    _stimLoudNotesCtrl.text = (st['loud_notes']         as String?) ?? '';
    _stimRateResponse       = st['rate_response']        as String?;
    _stimPacingResponse     = st['pacing_response']      as String?;
    _stimRateNotesCtrl.text = (st['rate_notes']         as String?) ?? '';
    _stimTactileResponse    = st['tactile_response']     as String?;
    _stimVisualModelResponse = st['visual_model_response'] as String?;
    _stimPhoneticPlacementResponse = st['phonetic_placement_response'] as String?;
    _stimArticNotesCtrl.text = (st['articulatory_notes'] as String?) ?? '';
    _stimOpenMouthResponse  = st['open_mouth_response']  as String?;
    _stimOralAirflowResponse = st['oral_airflow_response'] as String?;
    _stimResonanceNotesCtrl.text = (st['resonance_notes'] as String?) ?? '';
    final ra = st['recommended_approaches'];
    if (ra is List) {
      _stimRecommendedApproaches..clear()..addAll(ra.map((e) => e.toString()));
    }
    _stimApproachReasoningCtrl.text = (st['approach_reasoning'] as String?) ?? '';

    // 27c — Section 8 etiology subforms each from their own jsonb.
    final cp = a.cerebralPalsyPayload;
    final subSel = cp['subforms_selected'];
    if (subSel is List) {
      _subformsSelected
        ..clear()
        ..addAll(subSel.map((e) => e.toString()));
    }
    _cpSpasticityDistCtrl.text   = (cp['spasticity_distribution'] as String?) ?? '';
    _cpMovementPatternCtrl.text  = (cp['movement_pattern']        as String?) ?? '';
    _cpPosturalSupportCtrl.text  = (cp['postural_support']        as String?) ?? '';
    _cpBotoxHistoryCtrl.text     = (cp['botox_history_speech']    as String?) ?? '';
    _cpBotoxImpactSpeech         = cp['botox_impact_speech']      as String?;
    _cpOrthopedicSurgeryCtrl.text = (cp['orthopedic_surgery_history'] as String?) ?? '';
    _cpNotesCtrl.text            = (cp['notes'] as String?) ?? '';

    final pe = a.postEncephalitisPayload;
    _peAcuteIllnessType   = pe['acute_illness_type'] as String?;
    final peOnset = pe['acute_illness_onset_date'] as String?;
    if (peOnset != null && peOnset.isNotEmpty) {
      _peOnsetDate = DateTime.tryParse(peOnset);
    }
    _peAcuteSeverity      = pe['acute_illness_severity']  as String?;
    _peRecoveryTrajectory = pe['recovery_trajectory']      as String?;
    _peRecoveryDetailsCtrl.text = (pe['recovery_details']  as String?) ?? '';
    final peCom = pe['comorbid_impairments'];
    if (peCom is List) {
      _peComorbidImpairments..clear()..addAll(peCom.map((e) => e.toString()));
    }
    _peSequelaeNotesCtrl.text = (pe['sequelae_notes'] as String?) ?? '';

    final tb = a.postTbiPayload;
    _tbiMechanism             = tb['mechanism_of_injury'] as String?;
    _tbiOtherMechanismCtrl.text = (tb['other_mechanism_specify'] as String?) ?? '';
    _tbiGcsCtrl.text          = tb['gcs_at_presentation']?.toString() ?? '';
    _tbiTimePostInjuryCtrl.text = tb['time_post_injury_months']?.toString() ?? '';
    _tbiComaDurationCtrl.text = tb['coma_duration_days']?.toString() ?? '';
    _tbiPtaDurationCtrl.text  = tb['pta_duration_days']?.toString() ?? '';
    _tbiRecoveryTrajectory    = tb['recovery_trajectory'] as String?;
    final tbCog = tb['cognitive_communication_concerns'];
    if (tbCog is List) {
      _tbiCogConcerns..clear()..addAll(tbCog.map((e) => e.toString()));
    }
    final tbBeh = tb['behavioral_concerns'];
    if (tbBeh is List) {
      _tbiBehavioralConcerns..clear()..addAll(tbBeh.map((e) => e.toString()));
    }
    _tbiRanchosLevel          = tb['ranchos_level'] as String?;
    _tbiNotesCtrl.text        = (tb['notes'] as String?) ?? '';

    final gen = a.geneticSyndromePayload;
    _genConfirmedEtiologyCtrl.text   = (gen['confirmed_etiology']         as String?) ?? '';
    _genTestingDetailsCtrl.text      = (gen['genetic_testing_details']    as String?) ?? '';
    _genMotorSpeechFeaturesCtrl.text = (gen['motor_speech_features']      as String?) ?? '';
    _genFamilyHistoryCtrl.text       = (gen['family_history']             as String?) ?? '';
    _genCounselingReceived           = gen['counseling_received'] == true;
    _genNotesCtrl.text               = (gen['notes'] as String?) ?? '';

    final mi = a.mixedIdiopathicPayload;
    _miDifferentialReasoningCtrl.text = (mi['differential_reasoning']  as String?) ?? '';
    _miWorkingHypothesisCtrl.text     = (mi['working_hypothesis']      as String?) ?? '';
    final miInv = mi['pending_investigations'];
    if (miInv is List) {
      _miPendingInvestigations..clear()..addAll(miInv.map((e) => e.toString()));
    }
    _miInvestigationTimelineCtrl.text = (mi['investigation_timeline']  as String?) ?? '';
    _miNotesCtrl.text                 = (mi['notes']                   as String?) ?? '';

    // 27c — Section 9 (functional communication screen).
    final fc = a.functionalCommunicationPayload;
    _recLangApproach        = fc['receptive_approach']    as String?;
    _recLangBatteryCtrl.text = (fc['receptive_battery']   as String?) ?? '';
    _recLangProfile         = fc['receptive_profile']     as String?;
    _recLangNotesCtrl.text  = (fc['receptive_notes']      as String?) ?? '';
    _expLangApproach        = fc['expressive_approach']   as String?;
    _expLangBatteryCtrl.text = (fc['expressive_battery']  as String?) ?? '';
    _expLangEstimate        = fc['expressive_estimate']   as String?;
    _expLangNotesCtrl.text  = (fc['expressive_notes']     as String?) ?? '';
    _symbolicPlay           = fc['symbolic_play']         as String?;
    _cognitiveLevel         = fc['cognitive_level']       as String?;
    final cogBat = fc['cognitive_batteries'];
    if (cogBat is List) {
      _cogBatteries..clear()..addAll(cogBat.map((e) => e.toString()));
    }
    _cogSymbolicNotesCtrl.text = (fc['cognitive_symbolic_notes'] as String?) ?? '';
    _aacCandidacy           = fc['aac_candidacy']         as String?;
    _aacReasoningCtrl.text  = (fc['aac_reasoning']        as String?) ?? '';
    _augInputEffective      = fc['aug_input_effective']   == true;
    _augInputDetailsCtrl.text = (fc['aug_input_details']  as String?) ?? '';
    _primaryCommConcern     = fc['primary_comm_concern']  as String?;
    _commSynthesisCtrl.text = (fc['synthesis_notes']      as String?) ?? '';

    // 27c — Section 10 (differential diagnosis).
    final dd = a.differentialDiagnosisPayload;
    _ddOverrideMayo         = dd['override_mayo'] == true;
    _ddMayoOverride         = dd['mayo_override']         as String?;
    _ddOverallSeverity      = dd['overall_severity']      as String?;
    _ddSeverityRationaleCtrl.text = (dd['severity_rationale'] as String?) ?? '';
    _ddOverrideSubsystems   = dd['override_subsystems'] == true;
    final dso = dd['subsystems_affected_override'];
    if (dso is List) {
      _ddSubsystemsAffectedOverride..clear()..addAll(dso.map((e) => e.toString()));
    }
    _ddDiffFromCasCtrl.text          = (dd['diff_from_cas']           as String?) ?? '';
    _ddDiffFromPhonologicalCtrl.text = (dd['diff_from_phonological']  as String?) ?? '';
    _ddDiffFromDelayCtrl.text        = (dd['diff_from_delay']         as String?) ?? '';
    _ddDiffFromArticulationCtrl.text = (dd['diff_from_articulation']  as String?) ?? '';
    _ddHypothesisConfidence          = dd['hypothesis_confidence']    as String?;
    _ddHypothesisStatementCtrl.text  = (dd['hypothesis_statement']    as String?) ?? '';
    final ddF = dd['contributing_factors'];
    if (ddF is List) {
      _ddContributingFactors..clear()..addAll(ddF.map((e) => e.toString()));
    }
    _ddContributingNotesCtrl.text    = (dd['contributing_notes']      as String?) ?? '';

    // 27c — Section 15 (clinical impression) + cross-domain flags.
    final ci = a.clinicalImpressionPayload;
    _ciFinalDxCtrl.text       = (ci['final_diagnosis']      as String?) ?? '';
    _ciIcdCodeCtrl.text       = (ci['icd_code']             as String?) ?? '';
    _ciCogLinguistic          = ci['cognitive_linguistic']  as String?;
    _ciFamilySupport          = ci['family_support']        as String?;
    final cca = ci['comorbidities_affecting_outcome'];
    if (cca is List) {
      _ciComorbiditiesAffectingOutcome..clear()
        ..addAll(cca.map((e) => e.toString()));
    }
    _ciEtiologyTrajectory     = ci['etiology_trajectory']   as String?;
    _ciOverallPrognosis       = ci['overall_prognosis']     as String?;
    _ciPrognosticRationaleCtrl.text = (ci['prognostic_rationale'] as String?) ?? '';
    final ciInt = ci['recommended_interventions'];
    if (ciInt is List) {
      _ciInterventions..clear()..addAll(ciInt.map((e) => e.toString()));
    }
    _ciTherapyReasoningCtrl.text = (ci['therapy_reasoning'] as String?) ?? '';
    _ciIntensityCtrl.text     = ci['therapy_intensity_per_week']?.toString() ?? '';
    _ciSessionCountCtrl.text  = ci['estimated_session_count']?.toString() ?? '';
    _ciSessionDurationCtrl.text = ci['session_duration_min']?.toString() ?? '';
    _ciFrequency              = ci['frequency']             as String?;
    _ciDischargeCriteriaCtrl.text = (ci['discharge_criteria'] as String?) ?? '';
    _ciFunctionalOutcomesCtrl.text = (ci['functional_outcome_targets'] as String?) ?? '';
    final ciRef = ci['referrals'];
    if (ciRef is List) {
      _ciReferrals..clear()..addAll(ciRef.map((e) => e.toString()));
    }
    _ciReferralReasoningCtrl.text = (ci['referral_reasoning'] as String?) ?? '';
    final ciEdu = ci['caregiver_education'];
    if (ciEdu is List) {
      _ciCaregiverEdu..clear()..addAll(ciEdu.map((e) => e.toString()));
    }
    _ciFinalNarrativeCtrl.text = (ci['final_narrative'] as String?) ?? '';
    // Cross-domain flags from typed parent BOOLEAN columns.
    _flagDysphagiaReferral    = a.flagDysphagiaReferral;
    _flagAacAssessment        = a.flagAacAssessment;
  }

  /// Seeds Section 8 chip selection on first hydrate from etiology
  /// captured in Section 1. SLP changes after that point persist
  /// through cerebral_palsy_payload.subforms_selected. Mapping uses
  /// the human-readable etiology values the Section 1 chip picker
  /// writes (e.g. 'Cerebral palsy', not snake_case).
  void _seedSubformDefaults(PedDysarthriaAssessment a) {
    if (_subformsSelected.isNotEmpty) return; // SLP already chose
    final etio = a.etiologyCategory ?? _etiology;
    if (etio == null) return;
    if (etio == 'Cerebral palsy') {
      _subformsSelected.add('cp');
    }
    if (etio.startsWith('Post-encephalitis') ||
        etio.contains('meningitis')) {
      _subformsSelected.add('post_enc_men');
    }
    if (etio.startsWith('Post-TBI')) {
      _subformsSelected.add('post_tbi');
    }
    if (etio == 'Genetic syndrome') {
      _subformsSelected.add('genetic');
    }
    if (etio.startsWith('Idiopathic') ||
        etio == 'Other neurological' ||
        etio == 'Mitochondrial disease' ||
        etio == 'Pediatric stroke') {
      _subformsSelected.add('mixed_idiopathic');
    }
  }

  /// Seeds Section 12 from a previously saved ped_dys_qol_scores row.
  /// Per-item FOCUS-34 answers aren't persisted; totals reload from
  /// the typed columns and per-item state resets on hard refresh.
  void _hydrateQol(Map<String, dynamic> row) {
    if (row.isEmpty) return;
    final f = row['focus34_total'];
    if (f is num) _focus34TotalLoaded = f.toInt();
    final pc = row['parent_confidence_rating'];
    if (pc is num) {
      _parentConfidenceLoaded = pc.toInt();
      _parentConfidence       = pc.toInt().clamp(1, 10);
    }
    final ti = row['teacher_impact_rating'];
    if (ti is num) {
      _teacherImpactLoaded = ti.toInt();
      _teacherImpact       = ti.toInt().clamp(1, 10);
    }
    final pi = row['peer_interaction_rating'];
    if (pi is num) {
      _peerInteractionLoaded = pi.toInt();
      _peerInteraction       = pi.toInt().clamp(1, 10);
    }
    _qolNotesCtrl.text = (row['notes'] as String?) ?? '';
  }

  // 27b — typed Section 4 hydrators.

  void _hydrateAerodynamic(Map<String, dynamic> row) {
    if (row.isEmpty) return;
    _respMaxAhCtrl.text       = row['max_sustained_ah_seconds']?.toString() ?? '';
    _respWordsPerBreathCtrl.text = row['words_per_breath']?.toString() ?? '';
    _respSyllablesPerBreathCtrl.text = row['syllables_per_breath']?.toString() ?? '';
    _respBreathSupportPattern = row['breath_support_pattern'] as String?;
    _respAirWastage           = row['air_wastage']            as String?;
    _phonSzRatioCtrl.text     = row['s_z_ratio']?.toString() ?? '';
  }

  void _hydrateDdk(Map<String, dynamic> row) {
    if (row.isEmpty) return;
    _ddkPuhCtrl.text    = row['puh_per_sec']?.toString() ?? '';
    _ddkTuhCtrl.text    = row['tuh_per_sec']?.toString() ?? '';
    _ddkKuhCtrl.text    = row['kuh_per_sec']?.toString() ?? '';
    _ddkPatakaCtrl.text = row['pataka_per_sec']?.toString() ?? '';
    // 27b-fix1 — schema columns are ddk_regularity / ddk_accuracy.
    _ddkRegularity      = row['ddk_regularity'] as String?;
    _ddkAccuracy        = row['ddk_accuracy']   as String?;
  }

  void _hydrateSubsystemSeverity(Map<String, dynamic> row) {
    if (row.isEmpty) return;
    _respSeverity      = row['respiration_severity']  as String?;
    _phonSeverity      = row['phonation_severity']    as String?;
    _articSeverity     = row['articulation_severity'] as String?;
    _resonanceSeverity = row['resonance_severity']    as String?;
    _prosodySeverity   = row['prosody_severity']      as String?;
    _primarySubsystemOverride = row['primary_subsystem'] as String?;
  }

  void _hydrateIntelligibility(Map<String, dynamic> row) {
    if (row.isEmpty) return;
    void seed(String key, String mapKey) {
      final v = row[key];
      if (v is num) {
        _settingPct[mapKey] = v.toInt();
        _settingPctTouched.add(mapKey);
      }
    }
    // 27b — schema column is listener_familiar_primary_pct, not _caregivers_.
    seed('listener_familiar_primary_pct', 'familiar_caregivers');
    seed('listener_family_pct',              'family_non_primary');
    seed('listener_peers_pct',               'peers');
    seed('listener_teachers_pct',            'teachers');
    seed('listener_unfamiliar_adults_pct',   'unfamiliar_adults');
    seed('context_familiar_pct',             'familiar_contexts');
    seed('context_unfamiliar_pct',           'unfamiliar_contexts');
    // 27b — Section 6 ICS / CSIM / WPM seed from the same row.
    for (var i = 1; i <= 7; i++) {
      final v = row['ics_item$i'];
      if (v is num) _icsItems[i] = v.toInt();
    }
    final csw = row['csim_single_word_pct'];
    if (csw is num) _csimSingleWordCtrl.text = _trimNum(csw);
    final css = row['csim_sentence_pct'];
    if (css is num) _csimSentenceCtrl.text   = _trimNum(css);
    final wpm = row['words_per_minute'];
    if (wpm is num) _wpmCtrl.text            = _trimNum(wpm);
    _intelligibilityNotesCtrl.text = (row['notes'] as String?) ?? '';
  }

  String _trimNum(num v) {
    if (v is int) return v.toString();
    final d = v.toDouble();
    return d == d.roundToDouble() ? d.toInt().toString() : d.toString();
  }

  // ── Save dispatchers ────────────────────────────────────────────────

  Future<void> _saveCaseHistory() async {
    if (_assessment == null) return;
    // Build the parent-typed-spine patch first (etiology, CP levels,
    // dev ages, Mayo, last botox). Then the jsonb payload.
    final typed = <String, dynamic>{
      'mental_age_months':             _parseInt(_mentalAgeCtrl.text),
      'mental_age_source':             _mentalAgeSource,
      'receptive_language_age_months': _parseInt(_receptiveAgeCtrl.text),
      // 27a-fix1 — schema source columns drop "language_" prefix.
      'receptive_age_source':          _receptiveAgeSource,
      'expressive_language_age_months': _parseInt(_expressiveAgeCtrl.text),
      'expressive_age_source':         _expressiveAgeSource,
      'speech_age_months':             _parseInt(_speechAgeCtrl.text),
      'speech_age_source':             _speechAgeSource,
      'social_pragmatic_age_months':   _parseInt(_socialPragAgeCtrl.text),
      'social_pragmatic_age_source':   _socialPragAgeSource,
      'etiology_category':             _etiology,
      'cp_subtype':                    _cpSubtype,
      'gmfcs_level':                   _gmfcsLevel,
      'macs_level':                    _macsLevel,
      'cfcs_level':                    _cfcsLevel,
      'edacs_level':                   _edacsLevel,
      'vfcs_level':                    _vfcsLevel,
      'last_botox_date':               _lastBotoxDate?.toIso8601String().substring(0, 10),
      'mayo_dysarthria_type':          _mayoType,
    };
    final payload = <String, dynamic>{
      'chronological_age_months':      _parseInt(_chronoAgeMonthsCtrl.text),
      'corrected_age_used':            _correctedAgeUsed,
      'corrected_age_months':          _parseInt(_correctedAgeMonthsCtrl.text),
      'gestational_age_weeks':         _parseInt(_gestationalWeeksCtrl.text),
      'birth_complications':           _birthComplications.toList(),
      'birth_complications_detail':    _birthComplicationsDetailCtrl.text.trim(),
      'milestones': {
        'head_control':         _parseInt(_msHeadCtrl.text),
        'sitting':              _parseInt(_msSittingCtrl.text),
        'standing':             _parseInt(_msStandCtrl.text),
        'walking':              _parseInt(_msWalkCtrl.text),
        'breast_to_spoon':      _parseInt(_msBreastSpoonCtrl.text),
        'spoon_to_chewing':     _parseInt(_msSpoonChewCtrl.text),
        'babbling':             _parseInt(_msBabblingCtrl.text),
        'first_words':          _parseInt(_msFirstWordsCtrl.text),
        'two_word_combinations': _parseInt(_msTwoWordCtrl.text),
      },
      'developmental_age_source_detail': _devAgeSourceDetailCtrl.text.trim(),
      'educational_placement':         _educationalPlacement,
      'languages_spoken':              _languages.map((e) => {
                                         'name':                e.nameCtrl.text.trim(),
                                         'proficiency':         e.proficiency,
                                         'age_of_acquisition':  _parseInt(e.acquisitionAgeCtrl.text),
                                       }).where((m) => (m['name'] as String).isNotEmpty).toList(),
      'dominant_language':             _dominantLanguage,
      'first_speech_concern_age_months': _parseInt(_firstSpeechConcernAgeCtrl.text),
      'who_first_noticed':             _whoFirstNoticed.toList(),
      'who_first_noticed_other':       _whoFirstNoticedOtherCtrl.text.trim(),
      'speech_trajectory':             _trajectory.toList(),
      'intelligibility_timeline':      _intelligibilityTimelineCtrl.text.trim(),
      'family_observations': {
        'knows_but_cant':            _famObsKnowsButCant,
        'gives_up':                  _famObsGivesUp,
        'gives_up_freq':             _famObsGivesUpFreq,
        'gestures_for_speech':       _famObsGesturesForSpeech,
        'gestures_freq':             _famObsGesturesFreq,
        'worse_when_tired':          _famObsWorseTired,
        'worse_when_emotional':      _famObsWorseEmotional,
        'worse_unfamiliar_env':      _famObsWorseUnfamiliar,
        'peers_compare_different':   _famObsPeersCompare,
        'family_modifies_language':  _famObsFamilyModifies,
        'family_modifies_how':       _famObsFamilyModifiesHowCtrl.text.trim(),
      },
      'drooling_onset':                _droolingOnsetCtrl.text.trim(),
      'drooling_pattern':              _droolingPatternCtrl.text.trim(),
      'voice_quality_concerns':        _voiceQualityConcerns.toList(),
      'imaging_available':             _imagingAvailable,
      'imaging_modality':              _imagingModality,
      'imaging_date':                  _imagingDate?.toIso8601String().substring(0, 10),
      'imaging_findings':              _imagingFindingsCtrl.text.trim(),
      'hearing_status':                _hearingStatus,
      'audiology_done':                _audiologyDone,
      'audiology_results':             _audiologyResultsCtrl.text.trim(),
      'vision_status':                 _visionStatus,
      'vision_specify':                _visionSpecifyCtrl.text.trim(),
      'comorbidities':                 _comorbidities.toList(),
      'current_medications':           _medicationsCtrl.text.trim(),
      'mobility':                      _mobility,
      'posture_head_control':          _postureHeadControl,
      'hand_function_aac':             _handFunctionAac,
      'self_feeding_independence':     _selfFeedingIndep,
      'drooling_severity':             _droolingSeverity,
      'drooling_frequency':            _droolingFrequency,
      'channels_used':                 _channelsUsed.toList(),
      'most_used_channel':             _mostUsedChannel,
      'most_effective_channel':        _mostEffectiveChannel,
      'breakdown_frequency':           _breakdownFrequency,
      'child_repair_strategies':       _childRepairStrategies.toList(),
      'caregiver_repair_strategies':   _caregiverRepairStrategies.toList(),
      'best_time_of_day':              _bestTimeOfDay,
      'worst_time_of_day':             _worstTimeOfDay,
      'speech_mealtime':               _speechMealtime,
      'speech_play':                   _speechPlay,
      'speech_structured':             _speechStructured,
      'speech_posture_compare':        _speechPostureCompare,
      'aac_in_trial':                  _aacInTrial,
      // AAC subsection state — always serialized so toggling the
      // E.5 master switch off doesn't drop in-progress data.
      'aac_types_used':                _aacTypesUsed.toList(),
      'aac_currently_used':            _aacCurrentlyUsed,
      'aac_abandonment_reasons':       _aacAbandonReasons.toList(),
      'aac_family_acceptance':         _aacFamilyAcceptance,
      'total_communication_approach':  _totalCommApproach,
      'total_communication_notes':     _totalCommNotesCtrl.text.trim(),
      'behavioral_response':           _behavioralResponse,
      'behavioral_response_setting':   _behavioralResponseSettingCtrl.text.trim(),
      'behavioral_concerns':           _behavioralConcerns.toList(),
      'peer_interaction_quality':      _peerInteractionQuality,
      'educational_impact':            _educationalImpactCtrl.text.trim(),
      'family_priorities':             _familyPriorities.map((c) => c.text.trim()).toList(),
      'family_goals':                  _familyGoalsCtrl.text.trim(),
      'caregiver_expectations':        _caregiverExpectationsCtrl.text.trim(),
      'cultural_linguistic_priorities': _culturalLinguisticCtrl.text.trim(),
    };
    try {
      await _service.savePayloadSection(
        assessmentId: _assessment!.id,
        columnName:   'case_history_payload',
        payload:      payload,
      );
      await _service.saveTypedColumns(
        assessmentId: _assessment!.id,
        data:         typed,
      );
    } catch (e) {
      _toast('Could not save case history: $e');
    }
  }

  /// E.2 setting-specific intelligibility writes to ped_dys_intelligibility.
  /// Only sliders the SLP has touched are sent to the typed columns;
  /// untouched stays NULL on the typed table side. Sections 6's CSIM /
  /// ICS / WPM columns are left untouched by this save (partial upsert).
  Future<void> _saveIntelligibilitySettings() async {
    if (_assessment == null) return;
    if (_settingPctTouched.isEmpty) return;
    final data = <String, dynamic>{};
    void writeIfTouched(String mapKey, String column) {
      if (_settingPctTouched.contains(mapKey)) {
        data[column] = _settingPct[mapKey];
      }
    }
    writeIfTouched('familiar_caregivers',  'listener_familiar_caregivers_pct');
    writeIfTouched('family_non_primary',   'listener_family_pct');
    writeIfTouched('peers',                'listener_peers_pct');
    writeIfTouched('teachers',             'listener_teachers_pct');
    writeIfTouched('unfamiliar_adults',    'listener_unfamiliar_adults_pct');
    writeIfTouched('familiar_contexts',    'context_familiar_pct');
    writeIfTouched('unfamiliar_contexts',  'context_unfamiliar_pct');
    if (data.isEmpty) return;
    try {
      await _service.saveTypedMeasures(
        assessmentId: _assessment!.id,
        tableName:    'ped_dys_intelligibility',
        data:         data,
      );
    } catch (e) {
      _toast('Could not save intelligibility settings: $e');
    }
  }

  Future<void> _saveBedside() async {
    if (_assessment == null) return;
    final payload = <String, dynamic>{
      'cooperation':                 _cooperation,
      'attention_to_task':           _attentionToTask,
      'fatigue_onset':               _fatigueOnsetCtrl.text.trim(),
      'positioning':                 _positioning,
      'audio_reference':             _audioRefCtrl.text.trim(),
      'total_utterances':            _parseInt(_totalUtterancesCtrl.text),
      'mean_length_utterance_words': _parseDecimal(_mluWordsCtrl.text),
      'spontaneous_intelligibility': _spontaneousIntel,
      'first_impression_flags':      _firstImpressionFlags.toList(),
      'imitation_vowel':             _imitVowel,
      'imitation_cv_vc':             _imitCvVc,
      'imitation_single_word':       _imitSingleWord,
      'imitation_multi_syllabic':    _imitMultiSyllabic,
    };
    try {
      await _service.savePayloadSection(
        assessmentId: _assessment!.id,
        columnName:   'bedside_screen_payload',
        payload:      payload,
      );
    } catch (e) {
      _toast('Could not save bedside: $e');
    }
  }

  // 27b — Section 4 typed: aerodynamic measures.
  Future<void> _saveAerodynamic() async {
    if (_assessment == null) return;
    final data = <String, dynamic>{
      'max_sustained_ah_seconds':  _parseDecimal(_respMaxAhCtrl.text),
      's_z_ratio':                 _parseDecimal(_phonSzRatioCtrl.text),
      'words_per_breath':          _parseDecimal(_respWordsPerBreathCtrl.text),
      'syllables_per_breath':      _parseDecimal(_respSyllablesPerBreathCtrl.text),
      'breath_support_pattern':    _respBreathSupportPattern,
      'air_wastage':               _respAirWastage,
    };
    try {
      await _service.saveTypedMeasures(
        assessmentId: _assessment!.id,
        tableName:    'ped_dys_aerodynamic_measures',
        data:         data,
      );
    } catch (e) {
      _toast('Could not save aerodynamic measures: $e');
    }
  }

  // 27b — Section 4C typed: DDK rates.
  Future<void> _saveDdk() async {
    if (_assessment == null) return;
    final data = <String, dynamic>{
      'puh_per_sec':    _parseDecimal(_ddkPuhCtrl.text),
      'tuh_per_sec':    _parseDecimal(_ddkTuhCtrl.text),
      'kuh_per_sec':    _parseDecimal(_ddkKuhCtrl.text),
      'pataka_per_sec': _parseDecimal(_ddkPatakaCtrl.text),
      // 27b-fix1 — schema columns are ddk_regularity / ddk_accuracy.
      'ddk_regularity': _ddkRegularity,
      'ddk_accuracy':   _ddkAccuracy,
    };
    try {
      await _service.saveTypedMeasures(
        assessmentId: _assessment!.id,
        tableName:    'ped_dys_ddk_rates',
        data:         data,
      );
    } catch (e) {
      _toast('Could not save DDK rates: $e');
    }
  }

  // 27b — Section 4 typed: subsystem severity row + auto-derived primary.
  Future<void> _saveSubsystemSeverity() async {
    if (_assessment == null) return;
    final auto = _autoPrimarySubsystem();
    final primary = _primarySubsystemOverride ?? auto;
    final data = <String, dynamic>{
      'respiration_severity':   _respSeverity,
      'phonation_severity':     _phonSeverity,
      'articulation_severity':  _articSeverity,
      'resonance_severity':     _resonanceSeverity,
      'prosody_severity':       _prosodySeverity,
      'primary_subsystem':      primary,
    };
    try {
      await _service.saveTypedMeasures(
        assessmentId: _assessment!.id,
        tableName:    'ped_dys_subsystem_severity',
        data:         data,
      );
    } catch (e) {
      _toast('Could not save subsystem severity: $e');
    }
  }

  /// Auto-derive primary subsystem from severities — first 'Severe',
  /// then comma-joined when multiple. Returns null when no subsystem
  /// is rated Severe yet (SLP can override either way).
  String? _autoPrimarySubsystem() {
    final severeNames = <String>[];
    if (_respSeverity     == 'Severe') severeNames.add('Respiration');
    if (_phonSeverity     == 'Severe') severeNames.add('Phonation');
    if (_articSeverity    == 'Severe') severeNames.add('Articulation');
    if (_resonanceSeverity == 'Severe') severeNames.add('Resonance');
    if (_prosodySeverity  == 'Severe') severeNames.add('Prosody');
    if (severeNames.isEmpty) return null;
    return severeNames.join(', ');
  }

  // 27b — Section 4 narrative: per-subsystem jsonb columns.
  Future<void> _saveRespirationNarrative() async {
    _savePayload('respiration_payload', {
      'vital_capacity_estimate': _respVitalCapacity,
      'phonation_sync':          _respPhonationSync,
      'breath_direction':        _respBreathDirection,
      'respiration_notes':       _respNotesCtrl.text.trim(),
    }, 'Respiration');
  }

  Future<void> _savePhonationNarrative() async {
    _savePayload('phonation_payload', {
      'voice_qualities':         _phonVoiceQualities.toList(),
      'mpt_same_as_ah':          _phonMptSameAsAh,
      'phonation_mpt_seconds':   _parseDecimal(_phonMptCtrl.text),
      'habitual_pitch':          _phonHabitualPitch,
      'pitch_range':             _phonPitchRange,
      'loudness_level':          _phonLoudnessLevel,
      'loudness_range':          _phonLoudnessRange,
      'voice_onset':             _phonVoiceOnset,
      'glottal_incompetence':    _phonGlottalIncomp,
      'hyperadduction':          _phonHyperaddux,
      'ent_findings':            _phonEntFindingsCtrl.text.trim(),
    }, 'Phonation');
  }

  Future<void> _saveArticulationNarrative() async {
    _savePayload('articulation_payload', {
      'phoneme_inventory':       _phonemeInventoryCtrl.text.trim(),
      'phonemes_mastered':       _phonemesMasteredCtrl.text.trim(),
      'phonemes_emerging':       _phonemesEmergingCtrl.text.trim(),
      'phonemes_absent':         _phonemesAbsentCtrl.text.trim(),
      'imprecision_pattern':     _articImprecisionPattern.toList(),
      'place_errors':            _articPlaceErrors.toList(),
      'manner_errors':           _articMannerErrors.toList(),
      'voicing_contrast':        _articVoicing,
    }, 'Articulation');
  }

  Future<void> _saveResonanceNarrative() async {
    _savePayload('resonance_payload', {
      'resonance_balance':       _resonanceBalance,
      'nasal_emission':          _nasalEmission,
      'nasal_emission_sounds':   _nasalEmissionSoundsCtrl.text.trim(),
      'nasal_turbulence':        _nasalTurbulence,
      'vp_connected_adequate':   _vpConnectedAdequate,
      'vp_pressure_adequate':    _vpPressureAdequate,
      'resonance_notes':         _resonanceNotesCtrl.text.trim(),
    }, 'Resonance');
  }

  Future<void> _saveProsodyNarrative() async {
    _savePayload('prosody_payload', {
      'rate':                          _rate,
      'rhythm':                        _rhythm,
      'stress_pattern':                _stressPattern.toList(),
      'intonation':                    _intonation.toList(),
      'atypical_intonation_specify':   _atypicalIntonationCtrl.text.trim(),
      'phrasing':                      _phrasing,
      'prosody_notes':                 _prosodyNotesCtrl.text.trim(),
      'primary_subsystem_override':    _primarySubsystemOverride,
    }, 'Prosody');
  }

  /// Both Section 4E and Section 6 write WPM to the same typed
  /// ped_dys_intelligibility row. Last-write-wins is the contract;
  /// the shared _wpmCtrl means both UI sites display the same live
  /// value, so the SLP never sees stale data on whichever surface
  /// they happen to be viewing.
  Future<void> _saveWpm() async {
    if (_assessment == null) return;
    final wpm = _parseDecimal(_wpmCtrl.text);
    if (wpm == null) return;
    try {
      await _service.saveTypedMeasures(
        assessmentId: _assessment!.id,
        tableName:    'ped_dys_intelligibility',
        data:         {'words_per_minute': wpm},
      );
    } catch (e) {
      _toast('Could not save words per minute: $e');
    }
  }

  // 27b — Section 5 narrative.
  Future<void> _saveOralMech() async {
    _savePayload('oral_mech_payload', {
      'lips':                       _omLips.toList(),
      'tongue':                     _omTongue.toList(),
      'jaw':                        _omJaw.toList(),
      'soft_palate':                _omSoftPalate,
      'hard_palate':                _omHardPalate,
      'hard_palate_detail':         _omHardPalateDetailCtrl.text.trim(),
      'dentition_occlusion_class':  _omOcclusionClass,
      'missing_teeth':              _omMissingTeeth,
      'missing_teeth_detail':       _omMissingTeethCtrl.text.trim(),
      'pharyngeal_wall_movement':   _omPharyngealMovement,
      'gag_reflex':                 _omGagReflex,
      'drooling_pattern':           _omDroolingPattern,
      'lip_closure_chewing':        _omLipClosureChewing,
      'tongue_lateralization':      _omTongueLateralization,
      'tongue_elevation':           _omTongueElevation,
      'tongue_protrusion_retraction': _omTongueProtrusion,
      'velum_elevation_a_phonation': _omVelumElevation,
      'cough_strength':             _omCoughStrength,
      'swallow_trigger':            _omSwallowTrigger,
      'oral_muscle_tone':           _omOralTone,
      'primitive_reflexes':         _omPrimitiveReflexes.toList(),
      'volitional_reflexive':       _omVolitionalReflexive,
      'oral_mech_notes':            _omNotesCtrl.text.trim(),
    }, 'Oral Mech');
  }

  // 27b — Section 6 narrative + typed ICS/CSIM saves. The narrative
  // jsonb (passage, audio reference, pause patterns) goes to
  // connected_speech_payload. ICS items + totals + CSIM + WPM go to
  // ped_dys_intelligibility (partial upsert; Section 1 E.2 setting-%
  // columns stay untouched).
  Future<void> _saveConnectedSpeechNarrative() async {
    _savePayload('connected_speech_payload', {
      'passage_used':             _passageUsed,
      'passage_detail':           _passageDetailCtrl.text.trim(),
      'audio_reference':          _connectedAudioRefCtrl.text.trim(),
      'pause_duration_patterns':  _pauseDurationCtrl.text.trim(),
      'subsystem_breakdown':      _subsystemBreakdownCtrl.text.trim(),
    }, 'Connected speech');
  }

  Future<void> _saveIntelligibilityTyped() async {
    if (_assessment == null) return;
    final total = _icsItems.values.fold<int>(0, (a, b) => a + b);
    final hasItems = _icsItems.values.any((v) => v > 0);
    final data = <String, dynamic>{
      for (var i = 1; i <= 7; i++)
        if (_icsItems[i] != null) 'ics_item$i': _icsItems[i],
      if (hasItems) 'ics_total': total,
      if (hasItems) 'ics_average': total / 7,
      'csim_single_word_pct':  _parseDecimal(_csimSingleWordCtrl.text),
      'csim_sentence_pct':     _parseDecimal(_csimSentenceCtrl.text),
      'notes':                 _intelligibilityNotesCtrl.text.trim(),
    };
    try {
      await _service.saveTypedMeasures(
        assessmentId: _assessment!.id,
        tableName:    'ped_dys_intelligibility',
        data:         data,
      );
    } catch (e) {
      _toast('Could not save intelligibility measures: $e');
    }
  }

  // 27b — Section 7 narrative.
  Future<void> _saveStimulability() async {
    _savePayload('stimulability_payload', {
      'loud_response':                  _stimLoudResponse,
      'loud_sustained':                 _stimLoudSustained,
      'loud_intelligibility_improves':  _stimLoudIntelligibilityImproves,
      'loud_notes':                     _stimLoudNotesCtrl.text.trim(),
      'rate_response':                  _stimRateResponse,
      'pacing_response':                _stimPacingResponse,
      'rate_notes':                     _stimRateNotesCtrl.text.trim(),
      'tactile_response':               _stimTactileResponse,
      'visual_model_response':          _stimVisualModelResponse,
      'phonetic_placement_response':    _stimPhoneticPlacementResponse,
      'articulatory_notes':             _stimArticNotesCtrl.text.trim(),
      'open_mouth_response':            _stimOpenMouthResponse,
      'oral_airflow_response':          _stimOralAirflowResponse,
      'resonance_notes':                _stimResonanceNotesCtrl.text.trim(),
      'recommended_approaches':         _stimRecommendedApproaches.toList(),
      'approach_reasoning':             _stimApproachReasoningCtrl.text.trim(),
    }, 'Stimulability');
  }

  /// Shared save helper so the seven payload-section saves stay one-liners.
  void _savePayload(
      String columnName, Map<String, dynamic> payload, String label) {
    if (_assessment == null) return;
    _service
        .savePayloadSection(
          assessmentId: _assessment!.id,
          columnName:   columnName,
          payload:      payload,
        )
        .catchError((e) => _toast('Could not save $label: $e'));
  }

  // 27c — Section 8 narrative jsonbs (5 subforms). Each persists to
  // its own column; subform chip selection itself rides as a sibling
  // key on cerebral_palsy_payload so we don't need a new column for
  // the metadata.
  Future<void> _saveCerebralPalsy() async {
    _savePayload('cerebral_palsy_payload', {
      'subforms_selected':         _subformsSelected.toList(),
      'spasticity_distribution':   _cpSpasticityDistCtrl.text.trim(),
      'movement_pattern':          _cpMovementPatternCtrl.text.trim(),
      'postural_support':          _cpPosturalSupportCtrl.text.trim(),
      'botox_history_speech':      _cpBotoxHistoryCtrl.text.trim(),
      'botox_impact_speech':       _cpBotoxImpactSpeech,
      'orthopedic_surgery_history': _cpOrthopedicSurgeryCtrl.text.trim(),
      'notes':                     _cpNotesCtrl.text.trim(),
    }, 'Cerebral Palsy');
  }

  Future<void> _savePostEncephalitis() async {
    _savePayload('post_encephalitis_payload', {
      'acute_illness_type':        _peAcuteIllnessType,
      'acute_illness_onset_date':  _peOnsetDate?.toIso8601String().substring(0, 10),
      'acute_illness_severity':    _peAcuteSeverity,
      'recovery_trajectory':       _peRecoveryTrajectory,
      'recovery_details':          _peRecoveryDetailsCtrl.text.trim(),
      'comorbid_impairments':      _peComorbidImpairments.toList(),
      'sequelae_notes':            _peSequelaeNotesCtrl.text.trim(),
    }, 'Post-encephalitis / meningitis');
  }

  Future<void> _savePostTbi() async {
    _savePayload('post_tbi_payload', {
      'mechanism_of_injury':       _tbiMechanism,
      'other_mechanism_specify':   _tbiOtherMechanismCtrl.text.trim(),
      'gcs_at_presentation':       _parseInt(_tbiGcsCtrl.text),
      'time_post_injury_months':   _parseInt(_tbiTimePostInjuryCtrl.text),
      'coma_duration_days':        _parseInt(_tbiComaDurationCtrl.text),
      'pta_duration_days':         _parseInt(_tbiPtaDurationCtrl.text),
      'recovery_trajectory':       _tbiRecoveryTrajectory,
      'cognitive_communication_concerns': _tbiCogConcerns.toList(),
      'behavioral_concerns':       _tbiBehavioralConcerns.toList(),
      'ranchos_level':             _tbiRanchosLevel,
      'notes':                     _tbiNotesCtrl.text.trim(),
    }, 'Post-TBI');
  }

  Future<void> _saveGeneticSyndrome() async {
    _savePayload('genetic_syndrome_payload', {
      'confirmed_etiology':        _genConfirmedEtiologyCtrl.text.trim(),
      'genetic_testing_details':   _genTestingDetailsCtrl.text.trim(),
      'motor_speech_features':     _genMotorSpeechFeaturesCtrl.text.trim(),
      'family_history':            _genFamilyHistoryCtrl.text.trim(),
      'counseling_received':       _genCounselingReceived,
      'notes':                     _genNotesCtrl.text.trim(),
    }, 'Genetic syndrome');
  }

  Future<void> _saveMixedIdiopathic() async {
    _savePayload('mixed_idiopathic_payload', {
      'differential_reasoning':    _miDifferentialReasoningCtrl.text.trim(),
      'working_hypothesis':        _miWorkingHypothesisCtrl.text.trim(),
      'pending_investigations':    _miPendingInvestigations.toList(),
      'investigation_timeline':    _miInvestigationTimelineCtrl.text.trim(),
      'notes':                     _miNotesCtrl.text.trim(),
    }, 'Mixed / Idiopathic');
  }

  // 27c — Section 9.
  Future<void> _saveFunctionalCommunication() async {
    _savePayload('functional_communication_payload', {
      'receptive_approach':        _recLangApproach,
      'receptive_battery':         _recLangBatteryCtrl.text.trim(),
      'receptive_profile':         _recLangProfile,
      'receptive_notes':           _recLangNotesCtrl.text.trim(),
      'expressive_approach':       _expLangApproach,
      'expressive_battery':        _expLangBatteryCtrl.text.trim(),
      'expressive_estimate':       _expLangEstimate,
      'expressive_notes':          _expLangNotesCtrl.text.trim(),
      'symbolic_play':             _symbolicPlay,
      'cognitive_level':           _cognitiveLevel,
      'cognitive_batteries':       _cogBatteries.toList(),
      'cognitive_symbolic_notes':  _cogSymbolicNotesCtrl.text.trim(),
      'aac_candidacy':             _aacCandidacy,
      'aac_reasoning':             _aacReasoningCtrl.text.trim(),
      'aug_input_effective':       _augInputEffective,
      'aug_input_details':         _augInputDetailsCtrl.text.trim(),
      'primary_comm_concern':      _primaryCommConcern,
      'synthesis_notes':           _commSynthesisCtrl.text.trim(),
    }, 'Functional Communication');
  }

  // 27c — Section 10 + Mayo override write-back to typed parent column.
  Future<void> _saveDifferentialDx() async {
    _savePayload('differential_diagnosis_payload', {
      'override_mayo':             _ddOverrideMayo,
      'mayo_override':             _ddMayoOverride,
      'overall_severity':          _ddOverallSeverity,
      'severity_rationale':        _ddSeverityRationaleCtrl.text.trim(),
      'override_subsystems':       _ddOverrideSubsystems,
      'subsystems_affected_override': _ddSubsystemsAffectedOverride.toList(),
      'diff_from_cas':             _ddDiffFromCasCtrl.text.trim(),
      'diff_from_phonological':    _ddDiffFromPhonologicalCtrl.text.trim(),
      'diff_from_delay':           _ddDiffFromDelayCtrl.text.trim(),
      'diff_from_articulation':    _ddDiffFromArticulationCtrl.text.trim(),
      'hypothesis_confidence':     _ddHypothesisConfidence,
      'hypothesis_statement':      _ddHypothesisStatementCtrl.text.trim(),
      'contributing_factors':      _ddContributingFactors.toList(),
      'contributing_notes':        _ddContributingNotesCtrl.text.trim(),
    }, 'Differential Dx');
    // When SLP overrides Mayo type in Section 10, mirror to parent
    // mayo_dysarthria_type so Section 15's auto-pull + future report
    // composer see the final value.
    if (_ddOverrideMayo && _ddMayoOverride != null) {
      try {
        await _service.saveTypedColumns(
          assessmentId: _assessment!.id,
          data:         {'mayo_dysarthria_type': _ddMayoOverride},
        );
      } catch (e) {
        _toast('Could not write back Mayo override: $e');
      }
    }
  }

  // 27c — Section 12 typed QoL.
  Future<void> _saveQol() async {
    if (_assessment == null) return;
    final f34 = _focus34Items.isEmpty
        ? null
        : _focus34Items.values.fold<int>(0, (a, b) => a + b);
    final data = <String, dynamic>{
      'focus34_total':            ?f34,
      'parent_confidence_rating': _parentConfidence,
      'teacher_impact_rating':    _teacherImpact,
      'peer_interaction_rating':  _peerInteraction,
      'notes':                    _qolNotesCtrl.text.trim(),
    };
    try {
      await _service.saveTypedMeasures(
        assessmentId: _assessment!.id,
        tableName:    'ped_dys_qol_scores',
        data:         data,
      );
      setState(() {
        _focus34TotalLoaded     = f34;
        _parentConfidenceLoaded = _parentConfidence;
        _teacherImpactLoaded    = _teacherImpact;
        _peerInteractionLoaded  = _peerInteraction;
      });
    } catch (e) {
      _toast('Could not save QoL scores: $e');
    }
  }

  // 27c — Section 15 narrative + cross-domain alert flags to typed
  // parent BOOLEAN columns. NEVER auto-derived — SLP-toggled only.
  Future<void> _saveClinicalImpression() async {
    _savePayload('clinical_impression_payload', {
      'final_diagnosis':           _ciFinalDxCtrl.text.trim(),
      'icd_code':                  _ciIcdCodeCtrl.text.trim(),
      'cognitive_linguistic':      _ciCogLinguistic,
      'family_support':            _ciFamilySupport,
      'comorbidities_affecting_outcome': _ciComorbiditiesAffectingOutcome.toList(),
      'etiology_trajectory':       _ciEtiologyTrajectory,
      'overall_prognosis':         _ciOverallPrognosis,
      'prognostic_rationale':      _ciPrognosticRationaleCtrl.text.trim(),
      'recommended_interventions': _ciInterventions.toList(),
      'therapy_reasoning':         _ciTherapyReasoningCtrl.text.trim(),
      'therapy_intensity_per_week': _parseDecimal(_ciIntensityCtrl.text),
      'estimated_session_count':   _parseInt(_ciSessionCountCtrl.text),
      'session_duration_min':      _parseInt(_ciSessionDurationCtrl.text),
      'frequency':                 _ciFrequency,
      'discharge_criteria':        _ciDischargeCriteriaCtrl.text.trim(),
      'functional_outcome_targets': _ciFunctionalOutcomesCtrl.text.trim(),
      'referrals':                 _ciReferrals.toList(),
      'referral_reasoning':        _ciReferralReasoningCtrl.text.trim(),
      'caregiver_education':       _ciCaregiverEdu.toList(),
      'final_narrative':           _ciFinalNarrativeCtrl.text.trim(),
    }, 'Clinical Impression');
  }

  Future<void> _saveCrossDomainFlags() async {
    if (_assessment == null) return;
    try {
      await _service.saveTypedColumns(
        assessmentId: _assessment!.id,
        data: {
          'flag_dysphagia_referral': _flagDysphagiaReferral,
          'flag_aac_assessment':     _flagAacAssessment,
        },
      );
    } catch (e) {
      _toast('Could not save cross-domain flags: $e');
    }
  }

  // _savePayload is defined above (Section 4 narrative dispatchers
  // share it with these new 27c saves).

  Future<void> _addFollowUp() async {
    if (_assessment == null) return;
    final baselineId = _assessment!.isBaseline
        ? _assessment!.id
        : (_assessment!.baselineAssessmentId ?? _assessment!.id);
    try {
      await _service.addFollowUp(
        clientId: widget.clientId,
        baselineAssessmentId: baselineId,
        visitId: widget.visitId,
      );
      _toast('Follow-up assessment created.');
      final outcome = await _service.compareBaselineToLatest(widget.clientId);
      if (mounted) setState(() => _outcome = outcome);
    } catch (e) {
      _toast('Could not add follow-up: $e');
    }
  }

  // ── Mayo auto-suggestion (HINT ONLY — SLP override carries authority) ──
  String? _mayoSuggestion() {
    if (_etiology != 'Cerebral palsy') return null;
    if (_cpSubtype == null) return null;
    if (_cpSubtype!.startsWith('Spastic'))    return 'Spastic';
    if (_cpSubtype!.startsWith('Dyskinetic')) return 'Hyperkinetic';
    if (_cpSubtype == 'Ataxic')               return 'Ataxic';
    if (_cpSubtype == 'Hypotonic')            return 'Flaccid';
    if (_cpSubtype == 'Mixed')                return 'Mixed';
    return null;
  }

  // ── Helpers ────────────────────────────────────────────────────────

  int? _parseInt(String s) {
    final t = s.trim();
    if (t.isEmpty) return null;
    return int.tryParse(t);
  }

  num? _parseDecimal(String s) {
    final t = s.trim();
    if (t.isEmpty) return null;
    return num.tryParse(t);
  }

  void _toast(String msg) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg)));
    }
  }

  // ── Build ──────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const SizedBox(
          height: 100, child: Center(child: CircularProgressIndicator()));
    }
    if (_error != null) {
      return _errorBox('Could not load Pediatric Dysarthria assessment: $_error');
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _section(id: 'sec1', number: 1, title: 'Detailed Case History',
            tagline: 'Demographics, dev ages, etiology + CP levels, comm profile E.1–E.7.',
            child: _section1Body()),
        const SizedBox(height: 10),
        _section(id: 'sec2', number: 2, title: 'Bedside / Initial Observation',
            tagline: 'Behavioral state, spontaneous speech sample, imitative screen.',
            child: _section2Body()),
        const SizedBox(height: 10),
        _section(id: 'sec4', number: 4, title: 'Five Speech Subsystems',
            tagline: 'Respiration, phonation, articulation, resonance, prosody — typed severity per subsystem.',
            child: _section4Body()),
        const SizedBox(height: 10),
        _section(id: 'sec5', number: 5, title: 'Oral Mech Examination',
            tagline: 'Lips / tongue / jaw / palate / dentition + function + tone.',
            child: _section5Body()),
        const SizedBox(height: 10),
        _section(id: 'sec6', number: 6, title: 'Connected Speech & Intelligibility',
            tagline: 'Reading passage, ICS 7-item, CSIM single-word + sentence, WPM.',
            child: _section6Body()),
        const SizedBox(height: 10),
        _section(id: 'sec7', number: 7, title: 'Stimulability & Therapy Trial',
            tagline: 'Loudness / rate / placement / resonance probe responses; therapy match.',
            child: _section7Body()),
        const SizedBox(height: 10),
        _section(id: 'sec8',  number: 8,  title: 'Etiology-Specific Subforms',
            tagline: 'CP, post-encephalitis/meningitis, post-TBI, genetic, mixed/idiopathic — auto-suggested from Section 1.',
            child: _section8Body()),
        const SizedBox(height: 10),
        _section(id: 'sec9',  number: 9,  title: 'Functional Communication Screen',
            tagline: 'Receptive + expressive language, symbolic / cognitive level, AAC candidacy.',
            child: _section9Body()),
        const SizedBox(height: 10),
        _section(id: 'sec10', number: 10, title: 'Differential Diagnosis',
            tagline: 'Mayo final classification, severity, subsystems, dysarthria-vs-CAS reasoning.',
            child: _section10Body()),
        const SizedBox(height: 10),
        _section(id: 'sec11', number: 11, title: 'Outcome Tracking',
            tagline: 'Baseline vs most recent follow-up across all measures.',
            child: _section11Body()),
        const SizedBox(height: 10),
        _section(id: 'sec12', number: 12, title: 'Functional Communication & QoL',
            tagline: 'FOCUS-34 typed total + 3 caregiver / teacher / peer ratings.',
            child: _section12Body()),
        const SizedBox(height: 10),
        _section(id: 'sec15', number: 15, title: 'Final Clinical Impression & Plan',
            tagline: 'Diagnosis, severity, prognosis, plan, referrals, cross-domain alert flags.',
            child: _section15Body()),
      ],
    );
  }

  // ── Section primitives ─────────────────────────────────────────────

  Widget _section({
    required String id,
    required int number,
    required String title,
    required String tagline,
    required Widget child,
  }) {
    final open = _expanded == id;
    return Container(
      decoration: BoxDecoration(
        color:        Colors.white,
        borderRadius: BorderRadius.circular(12),
        border:       Border.all(color: _line),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = open ? '' : id),
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('SECTION $number — ${title.toUpperCase()}',
                            style: GoogleFonts.syne(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: _teal,
                                letterSpacing: 1.6)),
                        const SizedBox(height: 4),
                        Text(tagline,
                            style: GoogleFonts.dmSans(
                                fontSize: 12,
                                color: _inkGhost,
                                fontStyle: FontStyle.italic)),
                      ],
                    ),
                  ),
                  Icon(open ? Icons.expand_less : Icons.expand_more,
                      color: _inkGhost),
                ],
              ),
            ),
          ),
          if (open) ...[
            const Divider(height: 1, color: _line),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
              child: child,
            ),
          ],
        ],
      ),
    );
  }

  // ignore: unused_element
  Widget _stub(int number, String title, String tagline, String comingIn) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color:        _amberSoft.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _amber.withValues(alpha: 0.30)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('SECTION $number — ${title.toUpperCase()}',
                  style: GoogleFonts.syne(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: _amber,
                      letterSpacing: 1.6)),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color:        _amber.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text('STUB',
                    style: GoogleFonts.syne(
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        color: _amber,
                        letterSpacing: 1.2)),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(tagline,
              style: GoogleFonts.dmSans(
                  fontSize: 12, color: _inkGhost, fontStyle: FontStyle.italic)),
          const SizedBox(height: 4),
          Text('Coming in $comingIn.',
              style: GoogleFonts.dmSans(
                  fontSize: 11, color: _amber, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  // ── Section 1 body ─────────────────────────────────────────────────
  Widget _section1Body() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _subsectionHeader('A · Demographic & Developmental'),
        _section1aBody(),
        const SizedBox(height: 18),
        _subsectionHeader('B · Speech History'),
        _section1bBody(),
        const SizedBox(height: 18),
        _subsectionHeader('C · Medical / Neurological History'),
        _section1cBody(),
        const SizedBox(height: 18),
        _subsectionHeader('D · Functional Status'),
        _section1dBody(),
        const SizedBox(height: 18),
        _subsectionHeader('E · Communication Profile'),
        _section1eBody(),
      ],
    );
  }

  Widget _section1aBody() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _numField('Chronological age', _chronoAgeMonthsCtrl,
            unit: 'months', onSave: _saveCaseHistory),
        _yesNo('Use corrected age?', _correctedAgeUsed, (v) {
          setState(() => _correctedAgeUsed = v);
          _saveCaseHistory();
        }),
        if (_correctedAgeUsed)
          _numField('Corrected age', _correctedAgeMonthsCtrl,
              unit: 'months', onSave: _saveCaseHistory),
        _numField('Gestational age at birth', _gestationalWeeksCtrl,
            unit: 'weeks', onSave: _saveCaseHistory),
        _multiChips('Birth complications', const [
          'HIE', 'Birth asphyxia', 'Preterm', 'NICU stay',
          'Kernicterus', 'Other',
        ], _birthComplications, (v, sel) {
          setState(() {
            if (sel) {
              _birthComplications.add(v);
            } else {
              _birthComplications.remove(v);
            }
          });
          _saveCaseHistory();
        }),
        if (_birthComplications.isNotEmpty)
          _textField('Birth complications detail',
              _birthComplicationsDetailCtrl, multi: true,
              onSave: _saveCaseHistory),

        const SizedBox(height: 8),
        _groupLabel('Developmental milestones (months)'),
        _numField('Head control',  _msHeadCtrl,    unit: 'mo', onSave: _saveCaseHistory),
        _numField('Sitting',       _msSittingCtrl, unit: 'mo', onSave: _saveCaseHistory),
        _numField('Standing',      _msStandCtrl,   unit: 'mo', onSave: _saveCaseHistory),
        _numField('Walking',       _msWalkCtrl,    unit: 'mo', onSave: _saveCaseHistory),
        _numField('Breast/bottle → spoon transition',
            _msBreastSpoonCtrl, unit: 'mo', onSave: _saveCaseHistory),
        _numField('Spoon → chewing',
            _msSpoonChewCtrl,   unit: 'mo', onSave: _saveCaseHistory),
        _numField('Babbling',      _msBabblingCtrl,    unit: 'mo', onSave: _saveCaseHistory),
        _numField('First words',   _msFirstWordsCtrl,  unit: 'mo', onSave: _saveCaseHistory),
        _numField('2-word combinations',
            _msTwoWordCtrl,    unit: 'mo', onSave: _saveCaseHistory),

        const SizedBox(height: 14),
        _groupLabel('Developmental age estimates'),
        _ageWithSourceRow('Mental age', _mentalAgeCtrl, _mentalAgeSource, (v) {
          setState(() => _mentalAgeSource = v);
          _saveCaseHistory();
        }),
        _ageWithSourceRow('Receptive language age', _receptiveAgeCtrl,
            _receptiveAgeSource, (v) {
          setState(() => _receptiveAgeSource = v);
          _saveCaseHistory();
        }),
        _ageWithSourceRow('Expressive language age', _expressiveAgeCtrl,
            _expressiveAgeSource, (v) {
          setState(() => _expressiveAgeSource = v);
          _saveCaseHistory();
        }),
        _ghostNote(
            'In dysarthria, expressive age may be artificially reduced by motor execution; flag if you suspect this is motor-driven, not language-driven.'),
        _ageWithSourceRow('Speech age', _speechAgeCtrl, _speechAgeSource,
            (v) {
          setState(() => _speechAgeSource = v);
          _saveCaseHistory();
        }),
        _ageWithSourceRow('Social-pragmatic age', _socialPragAgeCtrl,
            _socialPragAgeSource, (v) {
          setState(() => _socialPragAgeSource = v);
          _saveCaseHistory();
        }),
        _ghostNote('Especially relevant when ASD comorbid.'),
        _textField('Source detail / batteries used',
            _devAgeSourceDetailCtrl, multi: true,
            onSave: _saveCaseHistory),

        const SizedBox(height: 8),
        _singleChips('Educational placement', const [
          'Regular school', 'Inclusive school', 'Special school',
          'Homeschool', 'Not yet enrolled',
        ], _educationalPlacement, (v) {
          setState(() => _educationalPlacement = v);
          _saveCaseHistory();
        }),

        const SizedBox(height: 8),
        _groupLabel('Languages exposed to'),
        for (var i = 0; i < _languages.length; i++) _languageRow(i),
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: OutlinedButton.icon(
            onPressed: () {
              setState(() => _languages.add(_LanguageEntry()));
            },
            icon: const Icon(Icons.add_rounded, size: 14),
            label: Text('Add language',
                style: GoogleFonts.dmSans(fontSize: 12, color: _teal)),
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: _teal.withValues(alpha: 0.45)),
              padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 6),
            ),
          ),
        ),
        _singleChips('Dominant language for therapy',
            _languages.map((e) => e.nameCtrl.text.trim())
                .where((s) => s.isNotEmpty)
                .toList(),
            _dominantLanguage, (v) {
          setState(() => _dominantLanguage = v);
          _saveCaseHistory();
        }),
      ],
    );
  }

  Widget _section1bBody() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _numField('Age first speech concerns noted',
            _firstSpeechConcernAgeCtrl, unit: 'months',
            onSave: _saveCaseHistory),
        _multiChips('Who first noticed?', const [
          'Parent / guardian',
          'Pediatrician',
          'Family member (grandparent / sibling / extended family)',
          'School / teacher / daycare staff',
          'Audiology screening',
          'ENT consultation',
          'Other healthcare provider (PT / OT / neurologist)',
          'Self (older child)',
          'Other',
        ], _whoFirstNoticed, (v, sel) {
          setState(() {
            if (sel) {
              _whoFirstNoticed.add(v);
            } else {
              _whoFirstNoticed.remove(v);
            }
          });
          _saveCaseHistory();
        }),
        if (_whoFirstNoticed.contains('Other'))
          _textField('Other (specify)', _whoFirstNoticedOtherCtrl,
              onSave: _saveCaseHistory),
        _multiChips('Speech development trajectory',
            const ['Slow to start', 'Plateaued', 'Regressed', 'Inconsistent'],
            _trajectory, (v, sel) {
          setState(() {
            if (sel) {
              _trajectory.add(v);
            } else {
              _trajectory.remove(v);
            }
          });
          _saveCaseHistory();
        }),
        _textField('Family-reported speech intelligibility timeline',
            _intelligibilityTimelineCtrl, multi: true,
            onSave: _saveCaseHistory),

        const SizedBox(height: 8),
        _groupLabel('Family observations'),
        _yesNo("Child seems to know what to say but can't get it out",
            _famObsKnowsButCant, (v) {
          setState(() => _famObsKnowsButCant = v);
          _saveCaseHistory();
        }),
        _yesNo('Child gives up trying to speak', _famObsGivesUp, (v) {
          setState(() => _famObsGivesUp = v);
          _saveCaseHistory();
        }),
        if (_famObsGivesUp)
          _singleChips('Frequency', _kFreqScale, _famObsGivesUpFreq, (v) {
            setState(() => _famObsGivesUpFreq = v);
            _saveCaseHistory();
          }),
        _yesNo('Child substitutes gestures or pointing for speech',
            _famObsGesturesForSpeech, (v) {
          setState(() => _famObsGesturesForSpeech = v);
          _saveCaseHistory();
        }),
        if (_famObsGesturesForSpeech)
          _singleChips('Frequency', _kFreqScale, _famObsGesturesFreq, (v) {
            setState(() => _famObsGesturesFreq = v);
            _saveCaseHistory();
          }),
        _yesNo('Speech is worse when tired', _famObsWorseTired, (v) {
          setState(() => _famObsWorseTired = v);
          _saveCaseHistory();
        }),
        _yesNo('Speech is worse when emotional / excited',
            _famObsWorseEmotional, (v) {
          setState(() => _famObsWorseEmotional = v);
          _saveCaseHistory();
        }),
        _yesNo('Speech is worse in unfamiliar environments',
            _famObsWorseUnfamiliar, (v) {
          setState(() => _famObsWorseUnfamiliar = v);
          _saveCaseHistory();
        }),
        _yesNo("Peers compare child's speech as different",
            _famObsPeersCompare, (v) {
          setState(() => _famObsPeersCompare = v);
          _saveCaseHistory();
        }),
        _yesNo('Family modifies their own language to communicate',
            _famObsFamilyModifies, (v) {
          setState(() => _famObsFamilyModifies = v);
          _saveCaseHistory();
        }),
        if (_famObsFamilyModifies)
          _textField('How does family modify?', _famObsFamilyModifiesHowCtrl,
              multi: true, onSave: _saveCaseHistory),

        const SizedBox(height: 8),
        _textField('Drooling onset (month/year if known)',
            _droolingOnsetCtrl, onSave: _saveCaseHistory),
        _textField('Current drooling pattern', _droolingPatternCtrl,
            multi: true, onSave: _saveCaseHistory),
        _multiChips('Voice quality concerns observed by family', const [
          'Hoarse', 'Quiet', 'Strained', 'Wet/gurgly',
          'Pitch breaks', 'None observed',
        ], _voiceQualityConcerns, (v, sel) {
          setState(() {
            if (sel) {
              _voiceQualityConcerns.add(v);
            } else {
              _voiceQualityConcerns.remove(v);
            }
          });
          _saveCaseHistory();
        }),
      ],
    );
  }

  Widget _section1cBody() {
    final isCp = _etiology == 'Cerebral palsy';
    final mayoSugg = _mayoSuggestion();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _singleChips('Etiology category', const [
          'Cerebral palsy',
          'Post-encephalitis / meningitis sequelae',
          'Post-TBI (pediatric)',
          'Genetic syndrome',
          'Pediatric stroke',
          'Mitochondrial disease',
          'Other neurological',
          'Idiopathic / unknown',
        ], _etiology, (v) {
          setState(() => _etiology = v);
          _saveCaseHistory();
        }),
        if (isCp) ...[
          const SizedBox(height: 8),
          _groupLabel('CP classification'),
          _singleChips('CP subtype', const [
            'Spastic quadriplegic', 'Spastic diplegic',
            'Spastic hemiplegic', 'Spastic monoplegic',
            'Dyskinetic athetoid', 'Dyskinetic dystonic',
            'Ataxic', 'Hypotonic', 'Mixed',
          ], _cpSubtype, (v) {
            setState(() => _cpSubtype = v);
            _saveCaseHistory();
          }),
          _classificationRow('GMFCS',
              const ['I', 'II', 'III', 'IV', 'V'],
              const {
                'I':   'Walks without limitations',
                'II':  'Walks with limitations',
                'III': 'Walks using a hand-held mobility device',
                'IV':  'Self-mobility with limitations; may use powered mobility',
                'V':   'Transported in a manual wheelchair',
              },
              _gmfcsLevel, (v) {
                setState(() => _gmfcsLevel = v);
                _saveCaseHistory();
              }),
          _classificationRow('MACS',
              const ['I', 'II', 'III', 'IV', 'V'],
              const {
                'I':   'Handles objects easily and successfully',
                'II':  'Handles most objects but with reduced quality / speed',
                'III': 'Handles objects with difficulty; needs help to prepare / modify activities',
                'IV':  'Handles a limited selection of easily managed objects in adapted situations',
                'V':   'Does not handle objects; severely limited ability to perform even simple actions',
              },
              _macsLevel, (v) {
                setState(() => _macsLevel = v);
                _saveCaseHistory();
              }),
          _classificationRow('CFCS',
              const ['I', 'II', 'III', 'IV', 'V'],
              const {
                'I':   'Effective sender and receiver with unfamiliar and familiar partners',
                'II':  'Effective but slower-paced with unfamiliar and/or familiar partners',
                'III': 'Effective sender and receiver with familiar partners only',
                'IV':  'Inconsistent sender and/or receiver with familiar partners',
                'V':   'Seldom effective sender and receiver even with familiar partners',
              },
              _cfcsLevel, (v) {
                setState(() => _cfcsLevel = v);
                _saveCaseHistory();
              }),
          _classificationRow('EDACS',
              const ['I', 'II', 'III', 'IV', 'V'],
              const {
                'I':   'Eats and drinks safely and efficiently',
                'II':  'Eats and drinks safely but with some limitations to efficiency',
                'III': 'Eats and drinks with some limitations to safety; may be limitations to efficiency',
                'IV':  'Eats and drinks with significant limitations to safety',
                'V':   'Unable to eat or drink safely; tube feeding may be considered',
              },
              _edacsLevel, (v) {
                setState(() => _edacsLevel = v);
                _saveCaseHistory();
              }),
          _classificationRow('VFCS',
              const ['I', 'II', 'III', 'IV', 'V'],
              const {
                'I':   'Uses visual function easily and successfully',
                'II':  'Uses visual function successfully but needs some self-initiated compensatory strategies',
                'III': 'Uses visual function but needs some adaptations',
                'IV':  'Uses visual function in adapted environments but performance is reduced',
                'V':   'Does not use visual function even in highly adapted environments',
              },
              _vfcsLevel, (v) {
                setState(() => _vfcsLevel = v);
                _saveCaseHistory();
              }),
        ],
        const SizedBox(height: 14),
        _datePickerRow('Date of last Botox injection',
            _lastBotoxDate, (d) {
          setState(() => _lastBotoxDate = d);
          _saveCaseHistory();
        }),
        _ghostNote(
            'Speech subsystem assessment timing matters — Botox effect peaks 2–4 weeks, fades by 12–16 weeks. Note timing relative to last injection for longitudinal tracking.'),
        _singleChips('Mayo dysarthria classification', const [
          'Spastic', 'Flaccid', 'Ataxic', 'Hypokinetic',
          'Hyperkinetic', 'Mixed', 'Unilateral UMN',
        ], _mayoType, (v) {
          setState(() => _mayoType = v);
          _saveCaseHistory();
        }),
        if (mayoSugg != null && _mayoType != mayoSugg)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              'Suggested from etiology + CP subtype: $mayoSugg (tap to override).',
              style: GoogleFonts.dmSans(
                  fontSize: 11, color: _inkGhost,
                  fontStyle: FontStyle.italic),
            ),
          ),

        const SizedBox(height: 14),
        _yesNo('Imaging available?', _imagingAvailable, (v) {
          setState(() => _imagingAvailable = v);
          _saveCaseHistory();
        }),
        if (_imagingAvailable) ...[
          _singleChips('Imaging modality',
              const ['CT', 'MRI', 'fMRI', 'DTI', 'Other'],
              _imagingModality, (v) {
            setState(() => _imagingModality = v);
            _saveCaseHistory();
          }),
          _datePickerRow('Imaging date', _imagingDate, (d) {
            setState(() => _imagingDate = d);
            _saveCaseHistory();
          }),
          _textField('Key findings', _imagingFindingsCtrl,
              multi: true, onSave: _saveCaseHistory),
        ],
        _singleChips('Hearing status', const [
          'WNL', 'Mild loss', 'Moderate loss', 'Severe loss',
          'Audiology pending',
        ], _hearingStatus, (v) {
          setState(() => _hearingStatus = v);
          _saveCaseHistory();
        }),
        _yesNo('Audiology screening done?', _audiologyDone, (v) {
          setState(() => _audiologyDone = v);
          _saveCaseHistory();
        }),
        if (_audiologyDone)
          _textField('Audiology results', _audiologyResultsCtrl,
              multi: true, onSave: _saveCaseHistory),
        _singleChips('Vision status', const [
          'WNL', 'Corrected with glasses', 'Visual impairment (specify)',
        ], _visionStatus, (v) {
          setState(() => _visionStatus = v);
          _saveCaseHistory();
        }),
        if (_visionStatus == 'Visual impairment (specify)')
          _textField('Specify', _visionSpecifyCtrl,
              multi: true, onSave: _saveCaseHistory),
        _multiChips('Comorbidities', const [
          'Intellectual disability', 'ASD', 'Seizure disorder',
          'Feeding/swallowing concerns (cross-link to dysphagia)',
          'Drooling functional impact', 'Visual impairment',
          'Hearing impairment', 'Sensory processing differences',
          'Other',
        ], _comorbidities, (v, sel) {
          setState(() {
            if (sel) {
              _comorbidities.add(v);
            } else {
              _comorbidities.remove(v);
            }
          });
          _saveCaseHistory();
        }),
        _textField('Current medications', _medicationsCtrl,
            multi: true,
            hint: 'Especially: antispasticity, antiepileptics, Botox history',
            onSave: _saveCaseHistory),
      ],
    );
  }

  Widget _section1dBody() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _singleChips('Mobility',
            const ['Independent', 'With aid', 'Wheelchair', 'Limited'],
            _mobility, (v) {
          setState(() => _mobility = v);
          _saveCaseHistory();
        }),
        _singleChips('Posture / head control',
            const ['Adequate', 'Variable', 'Poor'],
            _postureHeadControl, (v) {
          setState(() => _postureHeadControl = v);
          _saveCaseHistory();
        }),
        if (_postureHeadControl == 'Poor' || _postureHeadControl == 'Variable')
          _ghostNote('Affects breath support.'),
        _singleChips('Hand function for AAC potential', const [
          'Adequate', 'Reduced fine motor',
          'Severe motor limitation', 'Eye gaze potential',
        ], _handFunctionAac, (v) {
          setState(() => _handFunctionAac = v);
          _saveCaseHistory();
        }),
        _singleChips('Self-feeding independence', const [
          'Independent', 'Modified independent',
          'Some assistance', 'Full assistance',
        ], _selfFeedingIndep, (v) {
          setState(() => _selfFeedingIndep = v);
          _saveCaseHistory();
        }),
        _groupLabel('Drooling severity (Thomas-Stonell & Greenberg)'),
        _singleChips('Severity', const [
          'None', 'Mild', 'Moderate', 'Severe', 'Profound', 'Extreme',
        ], _droolingSeverity, (v) {
          setState(() => _droolingSeverity = v);
          _saveCaseHistory();
        }),
        _singleChips('Frequency', const [
          'Never', 'Occasional', 'Frequent', 'Constant',
        ], _droolingFrequency, (v) {
          setState(() => _droolingFrequency = v);
          _saveCaseHistory();
        }),
      ],
    );
  }

  Widget _section1eBody() {
    final channelOpts = _channelsUsed.toList()..sort();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _groupLabel('E.1 — Channels and modalities'),
        _multiChips('Channels used', const [
          'Vocal speech', 'Vocalizations (non-speech sounds)',
          'Gestures', 'Signs (formal sign language)',
          'Signs (informal home signs)', 'Picture cards',
          'AAC device', 'Eye gaze',
          'Yes/No system (head movements / blink)', 'Mixed',
        ], _channelsUsed, (v, sel) {
          setState(() {
            if (sel) {
              _channelsUsed.add(v);
            } else {
              _channelsUsed.remove(v);
              if (_mostUsedChannel == v) _mostUsedChannel = null;
              if (_mostEffectiveChannel == v) _mostEffectiveChannel = null;
            }
          });
          _saveCaseHistory();
        }),
        _singleChips('Most-used channel currently', channelOpts,
            _mostUsedChannel, (v) {
          setState(() => _mostUsedChannel = v);
          _saveCaseHistory();
        }),
        _singleChips('Most-effective channel currently', channelOpts,
            _mostEffectiveChannel, (v) {
          setState(() => _mostEffectiveChannel = v);
          _saveCaseHistory();
        }),

        const SizedBox(height: 14),
        _groupLabel('E.2 — Setting-specific intelligibility'),
        _settingPctSlider('Familiar listeners (parents / primary caregivers)',
            'familiar_caregivers'),
        _settingPctSlider('Family but not primary caregivers',
            'family_non_primary'),
        _settingPctSlider('Peers',     'peers'),
        _settingPctSlider('Teachers',  'teachers'),
        _settingPctSlider('Unfamiliar adults (clinic / community)',
            'unfamiliar_adults'),
        _settingPctSlider('Familiar contexts',   'familiar_contexts'),
        _settingPctSlider('Unfamiliar contexts', 'unfamiliar_contexts'),

        const SizedBox(height: 14),
        _groupLabel('E.3 — Communication breakdown and repair'),
        _singleChips('Frequency of communication breakdown',
            const ['Rare', 'Sometimes', 'Often', 'Constant'],
            _breakdownFrequency, (v) {
          setState(() => _breakdownFrequency = v);
          _saveCaseHistory();
        }),
        _multiChips('Repair strategies CHILD uses', const [
          'Repeats the same way', 'Repeats louder', 'Repeats slower',
          'Tries different word', 'Uses gesture', 'Points to object',
          'Writes / draws', 'Uses AAC', 'Gives up',
          'Becomes distressed', 'Becomes withdrawn',
          'Asks listener to guess',
        ], _childRepairStrategies, (v, sel) {
          setState(() {
            if (sel) {
              _childRepairStrategies.add(v);
            } else {
              _childRepairStrategies.remove(v);
            }
          });
          _saveCaseHistory();
        }),
        _multiChips('Repair strategies CAREGIVER uses', const [
          'Asks child to repeat', 'Guesses and confirms',
          'Offers choices (yes/no narrowing)',
          'Uses context to fill in',
          'Asks another family member',
          'Models clearer production',
          "Ignores / doesn't engage repair",
        ], _caregiverRepairStrategies, (v, sel) {
          setState(() {
            if (sel) {
              _caregiverRepairStrategies.add(v);
            } else {
              _caregiverRepairStrategies.remove(v);
            }
          });
          _saveCaseHistory();
        }),

        const SizedBox(height: 14),
        _groupLabel('E.4 — Communication across activities and time'),
        _singleChips('Best time of day for speech',
            const ['Morning', 'Mid-day', 'Afternoon', 'Evening', 'No clear pattern'],
            _bestTimeOfDay, (v) {
          setState(() => _bestTimeOfDay = v);
          _saveCaseHistory();
        }),
        _singleChips('Worst time of day for speech',
            const ['Morning', 'Mid-day', 'Afternoon', 'Evening', 'No clear pattern'],
            _worstTimeOfDay, (v) {
          setState(() => _worstTimeOfDay = v);
          _saveCaseHistory();
        }),
        _singleChips('Speech during mealtimes',
            const ['Same as baseline', 'Worse', 'Better', 'Avoids speaking'],
            _speechMealtime, (v) {
          setState(() => _speechMealtime = v);
          _saveCaseHistory();
        }),
        _singleChips('Speech during play / motivated activities',
            const ['Better', 'Same', 'Worse'],
            _speechPlay, (v) {
          setState(() => _speechPlay = v);
          _saveCaseHistory();
        }),
        _singleChips('Speech during structured tasks (school / homework)',
            const ['Better', 'Same', 'Worse'],
            _speechStructured, (v) {
          setState(() => _speechStructured = v);
          _saveCaseHistory();
        }),
        _singleChips('Speech in upright supported posture vs reclined',
            const ['Better upright', 'No difference', 'Worse upright', 'Not yet observed'],
            _speechPostureCompare, (v) {
          setState(() => _speechPostureCompare = v);
          _saveCaseHistory();
        }),

        const SizedBox(height: 14),
        _groupLabel('E.5 — AAC history'),
        _yesNo('AAC trial considered or in use?', _aacInTrial, (v) {
          setState(() => _aacInTrial = v);
          _saveCaseHistory();
        }),
        if (_aacInTrial) ...[
          _multiChips('AAC type used', const [
            'Picture cards (PECS / non-PECS)',
            'Communication board', 'Single-message device',
            'Dedicated SGD (specify brand)',
            'Tablet-based app (specify)',
            'Sign language', 'Eye gaze system',
          ], _aacTypesUsed, (v, sel) {
            setState(() {
              if (sel) {
                _aacTypesUsed.add(v);
              } else {
                _aacTypesUsed.remove(v);
              }
            });
            _saveCaseHistory();
          }),
          _yesNo('AAC currently used?', _aacCurrentlyUsed, (v) {
            setState(() => _aacCurrentlyUsed = v);
            _saveCaseHistory();
          }),
          _multiChips('AAC abandonment reason (if abandoned)', const [
            'Cost', 'Family preference', 'Limited training',
            'Child rejected', 'Recommended discontinuation',
            'School unable to support', 'Other (specify)',
          ], _aacAbandonReasons, (v, sel) {
            setState(() {
              if (sel) {
                _aacAbandonReasons.add(v);
              } else {
                _aacAbandonReasons.remove(v);
              }
            });
            _saveCaseHistory();
          }),
          _singleChips('Family acceptance of AAC',
              const ['Embraced', 'Cautious', 'Reluctant', 'Resistant'],
              _aacFamilyAcceptance, (v) {
            setState(() => _aacFamilyAcceptance = v);
            _saveCaseHistory();
          }),
          _yesNo('Total communication approach in family?',
              _totalCommApproach, (v) {
            setState(() => _totalCommApproach = v);
            _saveCaseHistory();
          }),
          if (_totalCommApproach)
            _textField('Total communication notes', _totalCommNotesCtrl,
                multi: true, onSave: _saveCaseHistory),
        ],

        const SizedBox(height: 14),
        _groupLabel('E.6 — Behavioral response to communication breakdown'),
        _singleChips('Behavioral response observed', const [
          'Engaged and persistent', 'Engaged but tires',
          'Withdraws when challenged', 'Becomes distressed',
          'Disengages',
        ], _behavioralResponse, (v) {
          setState(() => _behavioralResponse = v);
          _saveCaseHistory();
        }),
        _textField('Setting where this is most observed',
            _behavioralResponseSettingCtrl, multi: true,
            onSave: _saveCaseHistory),
        _multiChips('Behavioral concerns linked to communication breakdown',
            const [
              'Withdrawal', 'Aggression', 'Self-injury',
              'Avoidance of communication situations',
              'None observed',
            ], _behavioralConcerns, (v, sel) {
          setState(() {
            if (sel) {
              _behavioralConcerns.add(v);
            } else {
              _behavioralConcerns.remove(v);
            }
          });
          _saveCaseHistory();
        }),
        _singleChips('Peer interaction quality', const [
          'Engaged with peers', 'Limited peer interaction',
          'Avoids peers', 'Excluded by peers',
        ], _peerInteractionQuality, (v) {
          setState(() => _peerInteractionQuality = v);
          _saveCaseHistory();
        }),
        _textField('Educational impact', _educationalImpactCtrl,
            multi: true, onSave: _saveCaseHistory),

        const SizedBox(height: 14),
        _groupLabel('E.7 — Family priorities and goals'),
        _groupLabel('Top 3 family-reported priorities'),
        for (var i = 0; i < _familyPriorities.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Focus(
              onFocusChange: (f) {
                if (!f) _saveCaseHistory();
              },
              child: TextField(
                controller: _familyPriorities[i],
                style: GoogleFonts.dmSans(fontSize: 13, color: _ink),
                decoration: InputDecoration(
                  hintText: 'Priority #${i + 1}',
                  hintStyle: GoogleFonts.dmSans(
                      fontSize: 12,
                      color: _inkGhost.withValues(alpha: 0.6)),
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ),
          ),
        _textField('Family-stated functional goals', _familyGoalsCtrl,
            multi: true, onSave: _saveCaseHistory),
        _textField('Caregiver expectations', _caregiverExpectationsCtrl,
            multi: true,
            hint: 'Capture verbatim — realistic / hopeful / pessimistic',
            onSave: _saveCaseHistory),
        _textField('Cultural / linguistic communication priorities',
            _culturalLinguisticCtrl, multi: true,
            hint: 'Language family wants child to speak in, religious vocabulary, kinship terms',
            onSave: _saveCaseHistory),
      ],
    );
  }

  // ── Section 2 body ─────────────────────────────────────────────────
  Widget _section2Body() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _groupLabel('A · Behavioral state'),
        _singleChips('Cooperation',
            const ['Excellent', 'Good', 'Variable', 'Poor'],
            _cooperation, (v) {
          setState(() => _cooperation = v);
          _saveBedside();
        }),
        _singleChips('Attention to task',
            const ['Sustained', 'Variable', 'Brief', 'Unable'],
            _attentionToTask, (v) {
          setState(() => _attentionToTask = v);
          _saveBedside();
        }),
        _textField('Fatigue onset', _fatigueOnsetCtrl, multi: true,
            hint: 'During which task / how quickly',
            onSave: _saveBedside),
        _singleChips('Positioning during assessment', const [
          'Seated independently', 'Supported sitting',
          'Reclined', "Caregiver's lap", 'Other',
        ], _positioning, (v) {
          setState(() => _positioning = v);
          _saveBedside();
        }),

        const SizedBox(height: 14),
        _groupLabel('B · Spontaneous speech sample'),
        _textField('Audio reference / transcription', _audioRefCtrl,
            multi: true, onSave: _saveBedside),
        _numField('Total utterances captured', _totalUtterancesCtrl,
            unit: 'count', onSave: _saveBedside),
        _numField('Mean length of utterance', _mluWordsCtrl,
            unit: 'words', onSave: _saveBedside),
        _singleChips('Apparent intelligibility in spontaneous speech', const [
          'Intelligible', 'Effortful but intelligible',
          'Partially intelligible', 'Unintelligible',
        ], _spontaneousIntel, (v) {
          setState(() => _spontaneousIntel = v);
          _saveBedside();
        }),
        _multiChips('Five-subsystem first-impression flags', const [
          'Respiratory concerns (short breath groups, audible inhalation, reduced loudness on long utterances)',
          'Phonatory concerns (breathy / strained / harsh / wet / pitch instability)',
          'Articulatory concerns (imprecise consonants / vowel distortions)',
          'Resonance concerns (hypernasal / hyponasal / mixed / cul-de-sac)',
          'Prosodic concerns (monopitch / monoloudness / reduced rate / excess and equal stress)',
        ], _firstImpressionFlags, (v, sel) {
          setState(() {
            if (sel) {
              _firstImpressionFlags.add(v);
            } else {
              _firstImpressionFlags.remove(v);
            }
          });
          _saveBedside();
        }),

        const SizedBox(height: 14),
        _groupLabel('C · Imitative speech screening'),
        _singleChips('Vowel imitation',
            const ['Accurate', 'Distorted', 'Unable'],
            _imitVowel, (v) {
          setState(() => _imitVowel = v);
          _saveBedside();
        }),
        _singleChips('CV / VC syllable imitation',
            const ['Accurate', 'Distorted', 'Inconsistent', 'Unable'],
            _imitCvVc, (v) {
          setState(() => _imitCvVc = v);
          _saveBedside();
        }),
        _singleChips('Single word imitation',
            const ['Accurate', 'Distorted', 'Inconsistent', 'Unable'],
            _imitSingleWord, (v) {
          setState(() => _imitSingleWord = v);
          _saveBedside();
        }),
        _singleChips('Multi-syllabic imitation accuracy',
            const ['Accurate', 'Reduces syllables', 'Distorted', 'Unable'],
            _imitMultiSyllabic, (v) {
          setState(() => _imitMultiSyllabic = v);
          _saveBedside();
        }),
      ],
    );
  }

  // ── Section 4 body — Five Speech Subsystems ───────────────────────
  Widget _section4Body() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _subsectionHeader('4A · Respiration'),
        _section4aBody(),
        const SizedBox(height: 18),
        _subsectionHeader('4B · Phonation'),
        _section4bBody(),
        const SizedBox(height: 18),
        _subsectionHeader('4C · Articulation'),
        _section4cBody(),
        const SizedBox(height: 18),
        _subsectionHeader('4D · Resonance'),
        _section4dBody(),
        const SizedBox(height: 18),
        _subsectionHeader('4E · Prosody'),
        _section4eBody(),
        const SizedBox(height: 18),
        _section4PrimarySubsystem(),
      ],
    );
  }

  Widget _section4aBody() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _singleChips('Vital capacity estimate',
            const ['Adequate', 'Reduced', 'Severely reduced'],
            _respVitalCapacity, (v) {
          setState(() => _respVitalCapacity = v);
          _saveRespirationNarrative();
        }),
        _numField("Maximum sustained 'ah'", _respMaxAhCtrl,
            unit: 'sec', onSave: _saveAerodynamic),
        _numField('Words per breath in connected speech',
            _respWordsPerBreathCtrl, unit: 'words',
            onSave: _saveAerodynamic),
        _numField('Syllables per breath', _respSyllablesPerBreathCtrl,
            unit: 'syl', onSave: _saveAerodynamic),
        _singleChips('Breath support pattern', const [
          'Clavicular', 'Thoracic', 'Abdominal-diaphragmatic',
          'Reverse', 'Mixed',
        ], _respBreathSupportPattern, (v) {
          setState(() => _respBreathSupportPattern = v);
          _saveAerodynamic();
        }),
        _singleChips('Synchronization with phonation onset',
            const ['Adequate', 'Delayed', 'Inconsistent'],
            _respPhonationSync, (v) {
          setState(() => _respPhonationSync = v);
          _saveRespirationNarrative();
        }),
        _singleChips('Breath direction',
            const ['Audible inhalation', 'Silent', 'Forced'],
            _respBreathDirection, (v) {
          setState(() => _respBreathDirection = v);
          _saveRespirationNarrative();
        }),
        _singleChips('Air wastage during speech',
            const ['None', 'Mild', 'Moderate', 'Severe'],
            _respAirWastage, (v) {
          setState(() => _respAirWastage = v);
          _saveAerodynamic();
        }),
        _textField('Respiration notes', _respNotesCtrl,
            multi: true, onSave: _saveRespirationNarrative),
        _severityRow('Respiratory subsystem severity', _respSeverity,
            (v) {
          setState(() => _respSeverity = v);
          _saveSubsystemSeverity();
        }),
      ],
    );
  }

  Widget _section4bBody() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _multiChips('Voice quality', const [
          'Breathy', 'Strained', 'Harsh', 'Wet/gurgly',
          'Hoarse', 'Tremulous', 'Pitch breaks',
          'Aphonic / whispered',
        ], _phonVoiceQualities, (v, sel) {
          setState(() {
            if (sel) {
              _phonVoiceQualities.add(v);
            } else {
              _phonVoiceQualities.remove(v);
            }
          });
          _savePhonationNarrative();
        }),
        _yesNo("Same as 'ah' above", _phonMptSameAsAh, (v) {
          setState(() {
            _phonMptSameAsAh = v;
            if (v) _phonMptCtrl.text = _respMaxAhCtrl.text;
          });
          _savePhonationNarrative();
        }),
        if (!_phonMptSameAsAh)
          _numField('Maximum phonation time', _phonMptCtrl,
              unit: 'sec', onSave: _savePhonationNarrative),
        _numField('s/z ratio', _phonSzRatioCtrl,
            unit: 'ratio', onSave: _saveAerodynamic),
        _singleChips('Habitual pitch',
            const ['Adequate', 'Too high', 'Too low', 'Variable'],
            _phonHabitualPitch, (v) {
          setState(() => _phonHabitualPitch = v);
          _savePhonationNarrative();
        }),
        _singleChips('Pitch range',
            const ['Adequate', 'Restricted', 'Excessive'],
            _phonPitchRange, (v) {
          setState(() => _phonPitchRange = v);
          _savePhonationNarrative();
        }),
        _singleChips('Loudness level',
            const ['Adequate', 'Reduced', 'Excessive', 'Variable'],
            _phonLoudnessLevel, (v) {
          setState(() => _phonLoudnessLevel = v);
          _savePhonationNarrative();
        }),
        _singleChips('Loudness range / dynamic control',
            const ['Adequate', 'Reduced', 'Inconsistent'],
            _phonLoudnessRange, (v) {
          setState(() => _phonLoudnessRange = v);
          _savePhonationNarrative();
        }),
        _singleChips('Voice onset',
            const ['Smooth', 'Hard', 'Breathy', 'Effortful'],
            _phonVoiceOnset, (v) {
          setState(() => _phonVoiceOnset = v);
          _savePhonationNarrative();
        }),
        _yesNo('Glottal incompetence signs', _phonGlottalIncomp, (v) {
          setState(() => _phonGlottalIncomp = v);
          _savePhonationNarrative();
        }),
        _yesNo('Hyperadduction signs', _phonHyperaddux, (v) {
          setState(() => _phonHyperaddux = v);
          _savePhonationNarrative();
        }),
        _textField('ENT findings transcribed (if available)',
            _phonEntFindingsCtrl, multi: true,
            onSave: _savePhonationNarrative),
        _severityRow('Phonatory subsystem severity', _phonSeverity, (v) {
          setState(() => _phonSeverity = v);
          _saveSubsystemSeverity();
        }),
      ],
    );
  }

  Widget _section4cBody() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _groupLabel('Diadochokinetic rates'),
        _numField('puh repetitions / sec', _ddkPuhCtrl,
            unit: '/sec', onSave: _saveDdk),
        _numField('tuh repetitions / sec', _ddkTuhCtrl,
            unit: '/sec', onSave: _saveDdk),
        _numField('kuh repetitions / sec', _ddkKuhCtrl,
            unit: '/sec', onSave: _saveDdk),
        _numField('puh-tuh-kuh sequence rep / sec', _ddkPatakaCtrl,
            unit: '/sec', onSave: _saveDdk),
        _ghostNote(
            'Pediatric DDK norms broaden with age — by ~6 yo expect ~5/sec for monosyllabic, ~3/sec for sequenced; younger children lower.'),
        _singleChips('DDK regularity',
            const ['Regular', 'Slightly irregular', 'Markedly irregular'],
            _ddkRegularity, (v) {
          setState(() => _ddkRegularity = v);
          _saveDdk();
        }),
        _singleChips('DDK accuracy',
            const ['Accurate', 'Distorted', 'Substituted'],
            _ddkAccuracy, (v) {
          setState(() => _ddkAccuracy = v);
          _saveDdk();
        }),
        const SizedBox(height: 8),
        _groupLabel('Phoneme inventory'),
        _textField(
            'Inventory (consonants initial / medial / final + vowels)',
            _phonemeInventoryCtrl, multi: true,
            onSave: _saveArticulationNarrative),
        _textField('Phonemes mastered for age', _phonemesMasteredCtrl,
            multi: true, onSave: _saveArticulationNarrative),
        _textField('Phonemes emerging', _phonemesEmergingCtrl,
            multi: true, onSave: _saveArticulationNarrative),
        _textField('Phonemes absent', _phonemesAbsentCtrl,
            multi: true, onSave: _saveArticulationNarrative),
        _multiChips('Phoneme imprecision pattern', const [
          'Imprecise consonants', 'Vowel distortions',
          'Distorted substitutions (vs categorical)',
          'Phoneme prolongation', 'Repeated phonemes',
        ], _articImprecisionPattern, (v, sel) {
          setState(() {
            if (sel) {
              _articImprecisionPattern.add(v);
            } else {
              _articImprecisionPattern.remove(v);
            }
          });
          _saveArticulationNarrative();
        }),
        _multiChips('Place of articulation — affected', const [
          'Bilabial', 'Labiodental', 'Dental', 'Alveolar',
          'Palatal', 'Velar', 'Glottal',
        ], _articPlaceErrors, (v, sel) {
          setState(() {
            if (sel) {
              _articPlaceErrors.add(v);
            } else {
              _articPlaceErrors.remove(v);
            }
          });
          _saveArticulationNarrative();
        }),
        _multiChips('Manner of articulation — affected', const [
          'Stop', 'Fricative', 'Affricate',
          'Nasal', 'Liquid', 'Glide',
        ], _articMannerErrors, (v, sel) {
          setState(() {
            if (sel) {
              _articMannerErrors.add(v);
            } else {
              _articMannerErrors.remove(v);
            }
          });
          _saveArticulationNarrative();
        }),
        _singleChips('Voicing contrast accuracy',
            const ['Adequate', 'Reduced', 'Severely reduced'],
            _articVoicing, (v) {
          setState(() => _articVoicing = v);
          _saveArticulationNarrative();
        }),
        _severityRow('Articulatory subsystem severity', _articSeverity,
            (v) {
          setState(() => _articSeverity = v);
          _saveSubsystemSeverity();
        }),
      ],
    );
  }

  Widget _section4dBody() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _singleChips('Resonance balance', const [
          'WNL', 'Hypernasal — mild', 'Hypernasal — moderate',
          'Hypernasal — severe', 'Hyponasal', 'Mixed', 'Cul-de-sac',
        ], _resonanceBalance, (v) {
          setState(() => _resonanceBalance = v);
          _saveResonanceNarrative();
        }),
        _yesNo('Nasal emission', _nasalEmission, (v) {
          setState(() => _nasalEmission = v);
          _saveResonanceNarrative();
        }),
        if (_nasalEmission)
          _textField('During which sounds', _nasalEmissionSoundsCtrl,
              multi: true, onSave: _saveResonanceNarrative),
        _yesNo('Nasal turbulence', _nasalTurbulence, (v) {
          setState(() => _nasalTurbulence = v);
          _saveResonanceNarrative();
        }),
        _yesNo('Velopharyngeal function adequate during connected speech',
            _vpConnectedAdequate, (v) {
          setState(() => _vpConnectedAdequate = v);
          _saveResonanceNarrative();
        }),
        _yesNo('VP adequate during pressure consonants',
            _vpPressureAdequate, (v) {
          setState(() => _vpPressureAdequate = v);
          _saveResonanceNarrative();
        }),
        _textField('Resonance notes', _resonanceNotesCtrl,
            multi: true, onSave: _saveResonanceNarrative),
        _severityRow('Resonance subsystem severity', _resonanceSeverity,
            (v) {
          setState(() => _resonanceSeverity = v);
          _saveSubsystemSeverity();
        }),
      ],
    );
  }

  Widget _section4eBody() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _singleChips('Rate', const ['Slow', 'WNL', 'Fast', 'Variable'],
            _rate, (v) {
          setState(() => _rate = v);
          _saveProsodyNarrative();
        }),
        _numField('Rate measurement (words per minute)', _wpmCtrl,
            unit: 'wpm', onSave: _saveWpm),
        _ghostNote(
            'WPM is shared with Section 6 — both write to the same typed column. Last write wins.'),
        _singleChips('Rhythm',
            const ['Smooth', 'Halting', 'Scanning', 'Variable'],
            _rhythm, (v) {
          setState(() => _rhythm = v);
          _saveProsodyNarrative();
        }),
        _multiChips('Stress pattern', const [
          'WNL', 'Excess and equal stress',
          'Reduced stress (monoloudness)',
          'Inappropriate stress placement',
        ], _stressPattern, (v, sel) {
          setState(() {
            if (sel) {
              _stressPattern.add(v);
            } else {
              _stressPattern.remove(v);
            }
          });
          _saveProsodyNarrative();
        }),
        _multiChips('Intonation', const [
          'WNL', 'Monopitch', 'Reduced melodic contour',
          'Atypical patterns',
        ], _intonation, (v, sel) {
          setState(() {
            if (sel) {
              _intonation.add(v);
            } else {
              _intonation.remove(v);
            }
          });
          _saveProsodyNarrative();
        }),
        if (_intonation.contains('Atypical patterns'))
          _textField('Atypical intonation specify',
              _atypicalIntonationCtrl, multi: true,
              onSave: _saveProsodyNarrative),
        _singleChips('Phrasing', const [
          'Adequate', 'Short phrases', 'Prolonged pauses',
          'Inappropriate breaks',
        ], _phrasing, (v) {
          setState(() => _phrasing = v);
          _saveProsodyNarrative();
        }),
        _textField('Prosody notes', _prosodyNotesCtrl,
            multi: true, onSave: _saveProsodyNarrative),
        _severityRow('Prosodic subsystem severity', _prosodySeverity,
            (v) {
          setState(() => _prosodySeverity = v);
          _saveSubsystemSeverity();
        }),
      ],
    );
  }

  Widget _section4PrimarySubsystem() {
    final auto = _autoPrimarySubsystem();
    final display = _primarySubsystemOverride ?? auto ?? 'Not yet determined';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _groupLabel('Primary subsystem affected'),
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: _tealSoft.withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: _teal.withValues(alpha: 0.4)),
            ),
            child: Text(display,
                style: GoogleFonts.dmSans(
                    fontSize: 12, color: _teal,
                    fontWeight: FontWeight.w500)),
          ),
        ),
        if (auto != null && _primarySubsystemOverride != null && _primarySubsystemOverride != auto)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text('Auto-derived: $auto (override active)',
                style: GoogleFonts.dmSans(
                    fontSize: 11, color: _inkGhost,
                    fontStyle: FontStyle.italic)),
          ),
        _singleChips('Override primary subsystem', const [
          'Respiration', 'Phonation', 'Articulation',
          'Resonance', 'Prosody',
        ], _primarySubsystemOverride, (v) {
          setState(() => _primarySubsystemOverride = v);
          _saveSubsystemSeverity();
          _saveProsodyNarrative();
        }),
      ],
    );
  }

  Widget _severityRow(String label, String? value,
      ValueChanged<String?> onChanged) {
    return _singleChips(label, const ['Mild', 'Moderate', 'Severe'],
        value, onChanged);
  }

  // ── Section 5 body — Oral Mech Examination ────────────────────────
  Widget _section5Body() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _groupLabel('A · Structural'),
        _multiChips('Lips', const [
          'Symmetric', 'Asymmetric', 'Range WNL', 'Range reduced',
          'Strength WNL', 'Strength reduced',
        ], _omLips, (v, sel) {
          setState(() {
            if (sel) {
              _omLips.add(v);
            } else {
              _omLips.remove(v);
            }
          });
          _saveOralMech();
        }),
        _multiChips('Tongue', const [
          'Range WNL', 'Range reduced',
          'Strength WNL', 'Strength reduced',
          'Dexterity WNL', 'Dexterity reduced',
          'Fasciculations present',
        ], _omTongue, (v, sel) {
          setState(() {
            if (sel) {
              _omTongue.add(v);
            } else {
              _omTongue.remove(v);
            }
          });
          _saveOralMech();
        }),
        _multiChips('Jaw', const [
          'Range WNL', 'Range reduced', 'Stable', 'Unstable',
          'Deviation on opening — left', 'Deviation on opening — right',
        ], _omJaw, (v, sel) {
          setState(() {
            if (sel) {
              _omJaw.add(v);
            } else {
              _omJaw.remove(v);
            }
          });
          _saveOralMech();
        }),
        _singleChips('Soft palate', const [
          'Symmetric on phonation', 'Asymmetric on phonation',
          'Reduced elevation', 'Absent elevation',
        ], _omSoftPalate, (v) {
          setState(() => _omSoftPalate = v);
          _saveOralMech();
        }),
        _singleChips('Hard palate', const [
          'Intact', 'Cleft (specify)', 'Submucous cleft', 'High arched',
        ], _omHardPalate, (v) {
          setState(() => _omHardPalate = v);
          _saveOralMech();
        }),
        if (_omHardPalate == 'Cleft (specify)' ||
            _omHardPalate == 'Submucous cleft')
          _textField('Hard palate detail', _omHardPalateDetailCtrl,
              multi: true, onSave: _saveOralMech),
        _singleChips('Dentition occlusion class', const [
          'Class I', 'Class II', 'Class III', 'Mixed dentition',
        ], _omOcclusionClass, (v) {
          setState(() => _omOcclusionClass = v);
          _saveOralMech();
        }),
        _yesNo('Missing teeth', _omMissingTeeth, (v) {
          setState(() => _omMissingTeeth = v);
          _saveOralMech();
        }),
        if (_omMissingTeeth)
          _textField('Missing teeth detail', _omMissingTeethCtrl,
              multi: true, onSave: _saveOralMech),
        _singleChips('Pharyngeal wall movement', const [
          'Adequate', 'Reduced', 'Asymmetric', 'Not visualizable',
        ], _omPharyngealMovement, (v) {
          setState(() => _omPharyngealMovement = v);
          _saveOralMech();
        }),
        _singleChips('Gag reflex', const [
          'Present and symmetric', 'Absent', 'Hyperactive', 'Asymmetric',
        ], _omGagReflex, (v) {
          setState(() => _omGagReflex = v);
          _saveOralMech();
        }),
        _singleChips('Drooling pattern',
            const ['Anterior', 'Posterior', 'Both', 'Minimal', 'None'],
            _omDroolingPattern, (v) {
          setState(() => _omDroolingPattern = v);
          _saveOralMech();
        }),

        const SizedBox(height: 14),
        _groupLabel('B · Functional'),
        _singleChips('Lip closure during chewing',
            const ['Adequate', 'Inconsistent', 'Inadequate'],
            _omLipClosureChewing, (v) {
          setState(() => _omLipClosureChewing = v);
          _saveOralMech();
        }),
        _singleChips('Tongue lateralization to teeth',
            const ['Adequate', 'Reduced', 'Severely reduced', 'Unable'],
            _omTongueLateralization, (v) {
          setState(() => _omTongueLateralization = v);
          _saveOralMech();
        }),
        _singleChips('Tongue elevation',
            const ['Adequate', 'Reduced', 'Severely reduced', 'Unable'],
            _omTongueElevation, (v) {
          setState(() => _omTongueElevation = v);
          _saveOralMech();
        }),
        _singleChips('Tongue protrusion / retraction',
            const ['Adequate', 'Reduced', 'Severely reduced', 'Unable'],
            _omTongueProtrusion, (v) {
          setState(() => _omTongueProtrusion = v);
          _saveOralMech();
        }),
        _singleChips('Velum elevation on /a/ phonation',
            const ['Symmetric', 'Asymmetric', 'Reduced', 'Absent'],
            _omVelumElevation, (v) {
          setState(() => _omVelumElevation = v);
          _saveOralMech();
        }),
        _singleChips('Cough strength',
            const ['Strong', 'Adequate', 'Weak', 'Absent'],
            _omCoughStrength, (v) {
          setState(() => _omCoughStrength = v);
          _saveOralMech();
        }),
        _singleChips('Swallow trigger',
            const ['Timely', 'Delayed', 'Absent'],
            _omSwallowTrigger, (v) {
          setState(() => _omSwallowTrigger = v);
          _saveOralMech();
        }),

        const SizedBox(height: 14),
        _groupLabel('C · Tone and reflexes'),
        _singleChips('Oral muscle tone', const [
          'Normotonic', 'Hypertonic', 'Hypotonic', 'Mixed', 'Variable',
        ], _omOralTone, (v) {
          setState(() => _omOralTone = v);
          _saveOralMech();
        }),
        _multiChips('Primitive reflexes retained', const [
          'ATNR (Asymmetric tonic neck reflex)', 'Bite reflex',
          'Tongue thrust', 'Rooting', 'None observed',
        ], _omPrimitiveReflexes, (v, sel) {
          setState(() {
            if (sel) {
              _omPrimitiveReflexes.add(v);
            } else {
              _omPrimitiveReflexes.remove(v);
            }
          });
          _saveOralMech();
        }),
        _singleChips('Volitional vs reflexive movement dissociation',
            const ['Adequate', 'Reduced', 'Severely reduced'],
            _omVolitionalReflexive, (v) {
          setState(() => _omVolitionalReflexive = v);
          _saveOralMech();
        }),

        const SizedBox(height: 14),
        _groupLabel('D · Notes'),
        _textField('Oral mech examination overall notes',
            _omNotesCtrl, multi: true, onSave: _saveOralMech),
      ],
    );
  }

  // ── Section 6 body — Connected Speech & Intelligibility ───────────
  static const List<String> _icsItemWording = [
    "Does your child's speech make sense to immediate family?",
    "Does your child's speech make sense to extended family / relatives?",
    "Does your child's speech make sense to your child's friends?",
    "Does your child's speech make sense to other acquaintances?",
    "Does your child's speech make sense to your child's teachers?",
    "Does your child's speech make sense to strangers?",
    "Does your child's speech make sense to you?",
  ];
  static const List<String> _icsLikertLabels = [
    'Never', 'Rarely', 'Sometimes', 'Usually', 'Always',
  ];

  Widget _section6Body() {
    final hasItems = _icsItems.values.any((v) => v > 0);
    final icsTotal = _icsItems.values.fold<int>(0, (a, b) => a + b);
    final icsAvg   = hasItems ? icsTotal / 7 : 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _groupLabel('A · Reading passage / connected speech'),
        _singleChips('Passage used', const [
          'Rainbow Passage',
          'Chosen Indian-language passage (specify)',
          'Generated from picture',
          'Other (specify)',
        ], _passageUsed, (v) {
          setState(() => _passageUsed = v);
          _saveConnectedSpeechNarrative();
        }),
        if (_passageUsed == 'Chosen Indian-language passage (specify)' ||
            _passageUsed == 'Other (specify)')
          _textField('Passage detail', _passageDetailCtrl,
              multi: true, onSave: _saveConnectedSpeechNarrative),
        _textField('Audio reference / transcription',
            _connectedAudioRefCtrl, multi: true,
            hint: 'Audio attachment lands in a future commit',
            onSave: _saveConnectedSpeechNarrative),
        _numField('Words per minute', _wpmCtrl,
            unit: 'wpm', onSave: _saveWpm),
        _ghostNote(
            'WPM is shared with Section 4E — both write to the same typed column. Last write wins.'),
        _textField('Pause duration patterns', _pauseDurationCtrl,
            multi: true, onSave: _saveConnectedSpeechNarrative),
        _textField('Subsystem-level breakdown observations',
            _subsystemBreakdownCtrl, multi: true,
            onSave: _saveConnectedSpeechNarrative),

        const SizedBox(height: 14),
        _groupLabel('B · Intelligibility measures'),
        _groupLabel('ICS — Intelligibility in Context Scale'),
        for (var i = 1; i <= 7; i++)
          _icsItemRow(i),
        const SizedBox(height: 6),
        _qolBadge(
          label: 'ICS total',
          total: hasItems ? icsTotal : 0,
          maxScore: 35,
        ),
        if (hasItems) ...[
          const SizedBox(height: 4),
          Text('ICS average: ${icsAvg.toStringAsFixed(2)} / 5',
              style: GoogleFonts.dmSans(
                  fontSize: 12, color: _ink,
                  fontWeight: FontWeight.w500)),
        ],

        const SizedBox(height: 14),
        _groupLabel("CSIM — Children's Speech Intelligibility Measure"),
        _numField('CSIM single-word', _csimSingleWordCtrl,
            unit: '%', onSave: _saveIntelligibilityTyped),
        _numField('CSIM sentence-level', _csimSentenceCtrl,
            unit: '%', onSave: _saveIntelligibilityTyped),
        _ghostNote(
            'Score from standardized 50-word CSIM administration. If improvised, document in audio reference above.'),

        const SizedBox(height: 14),
        _groupLabel('C · Notes'),
        _textField('Intelligibility notes', _intelligibilityNotesCtrl,
            multi: true, onSave: _saveIntelligibilityTyped),
      ],
    );
  }

  Widget _icsItemRow(int i) {
    final v = _icsItems[i] ?? 0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$i. ${_icsItemWording[i - 1]}',
              style: GoogleFonts.dmSans(
                  fontSize: 12, color: _ink, height: 1.4)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6, runSpacing: 6,
            children: [
              for (var k = 0; k < 5; k++)
                _yesNoChip('${k + 1} · ${_icsLikertLabels[k]}',
                    v == k + 1, () {
                  setState(() => _icsItems[i] = (v == k + 1) ? 0 : k + 1);
                  _saveIntelligibilityTyped();
                }),
            ],
          ),
        ],
      ),
    );
  }

  Widget _qolBadge({
    required String label,
    required int total,
    required int maxScore,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      decoration: BoxDecoration(
        color: _tealSoft.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _teal.withValues(alpha: 0.45)),
      ),
      child: Text('$label: $total / $maxScore',
          style: GoogleFonts.dmSans(
              fontSize: 13, color: _teal,
              fontWeight: FontWeight.w600)),
    );
  }

  // ── Section 7 body — Stimulability & Therapy Trial ────────────────
  Widget _section7Body() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _groupLabel("A · Loudness manipulation (LSVT-LOUD probe)"),
        _singleChips("Response to 'speak loud' cue",
            const ['None', 'Partial', 'Robust'],
            _stimLoudResponse, (v) {
          setState(() => _stimLoudResponse = v);
          _saveStimulability();
        }),
        _yesNo('Loudness sustained over 5+ seconds', _stimLoudSustained,
            (v) {
          setState(() => _stimLoudSustained = v);
          _saveStimulability();
        }),
        _yesNo('Intelligibility improvement with louder voice',
            _stimLoudIntelligibilityImproves, (v) {
          setState(() => _stimLoudIntelligibilityImproves = v);
          _saveStimulability();
        }),
        _textField('Loudness probe notes', _stimLoudNotesCtrl,
            multi: true, onSave: _saveStimulability),

        const SizedBox(height: 14),
        _groupLabel('B · Rate manipulation'),
        _singleChips('Response to slowed rate',
            const ['None', 'Partial', 'Improved intelligibility'],
            _stimRateResponse, (v) {
          setState(() => _stimRateResponse = v);
          _saveStimulability();
        }),
        _singleChips('Pacing board / metronome response', const [
          'Effective', 'Partially effective', 'No effect', 'Not trialed',
        ], _stimPacingResponse, (v) {
          setState(() => _stimPacingResponse = v);
          _saveStimulability();
        }),
        _textField('Rate manipulation notes', _stimRateNotesCtrl,
            multi: true, onSave: _saveStimulability),

        const SizedBox(height: 14),
        _groupLabel('C · Articulatory placement cuing'),
        _singleChips('Tactile cue response (PROMPT-style)', const [
          'Robust response', 'Partial response',
          'No response', 'Not trialed',
        ], _stimTactileResponse, (v) {
          setState(() => _stimTactileResponse = v);
          _saveStimulability();
        }),
        _singleChips('Visual model response', const [
          'Robust response', 'Partial response',
          'No response', 'Not trialed',
        ], _stimVisualModelResponse, (v) {
          setState(() => _stimVisualModelResponse = v);
          _saveStimulability();
        }),
        _singleChips('Phonetic placement cue response', const [
          'Robust response', 'Partial response',
          'No response', 'Not trialed',
        ], _stimPhoneticPlacementResponse, (v) {
          setState(() => _stimPhoneticPlacementResponse = v);
          _saveStimulability();
        }),
        _textField('Articulatory cuing notes', _stimArticNotesCtrl,
            multi: true, onSave: _saveStimulability),

        const SizedBox(height: 14),
        _groupLabel('D · Resonance manipulation'),
        _singleChips('Open-mouth posture response', const [
          'Effective', 'Partially effective',
          'No effect', 'Not trialed',
        ], _stimOpenMouthResponse, (v) {
          setState(() => _stimOpenMouthResponse = v);
          _saveStimulability();
        }),
        _singleChips('Increased oral airflow cuing response', const [
          'Effective', 'Partially effective',
          'No effect', 'Not trialed',
        ], _stimOralAirflowResponse, (v) {
          setState(() => _stimOralAirflowResponse = v);
          _saveStimulability();
        }),
        _textField('Resonance manipulation notes',
            _stimResonanceNotesCtrl, multi: true,
            onSave: _saveStimulability),

        const SizedBox(height: 14),
        _groupLabel('E · Therapy approach predicted'),
        _multiChips('Recommended therapy approaches', const [
          'LSVT-LOUD candidate', 'SPEAK OUT! candidate',
          'PROMPT candidate', 'Resonance therapy',
          'Rate control therapy',
          'Compensatory / strategic approach',
          'AAC consideration', 'Articulation drill',
          'Beckman oral motor (note: weak evidence — consider carefully)',
        ], _stimRecommendedApproaches, (v, sel) {
          setState(() {
            if (sel) {
              _stimRecommendedApproaches.add(v);
            } else {
              _stimRecommendedApproaches.remove(v);
            }
          });
          _saveStimulability();
        }),
        _textField('Therapy approach reasoning',
            _stimApproachReasoningCtrl, multi: true,
            onSave: _saveStimulability),
      ],
    );
  }

  // ── Section 8 body — Etiology-Specific Subforms ───────────────────
  Widget _section8Body() {
    String chipKey(String label) => switch (label) {
          'CP'                                => 'cp',
          'Post-encephalitis / meningitis'    => 'post_enc_men',
          'Post-TBI'                          => 'post_tbi',
          'Genetic syndrome'                  => 'genetic',
          'Mixed / Idiopathic'                => 'mixed_idiopathic',
          _                                   => label.toLowerCase(),
        };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _groupLabel('Subform selector'),
        Wrap(
          spacing: 6, runSpacing: 6,
          children: [
            for (final label in const [
              'CP', 'Post-encephalitis / meningitis', 'Post-TBI',
              'Genetic syndrome', 'Mixed / Idiopathic',
            ])
              _yesNoChip(label, _subformsSelected.contains(chipKey(label)),
                  () {
                final k = chipKey(label);
                setState(() {
                  if (_subformsSelected.contains(k)) {
                    _subformsSelected.remove(k);
                  } else {
                    _subformsSelected.add(k);
                  }
                });
                _saveCerebralPalsy();
              }),
          ],
        ),
        if (_subformsSelected.isEmpty)
          _ghostNote(
              'Pick one or more subforms based on the etiology you logged in Section 1. Multiple etiologies (e.g. post-TBI on top of CP) are supported.'),
        if (_subformsSelected.contains('cp')) ...[
          const SizedBox(height: 18),
          _subsectionHeader('8A · Cerebral Palsy'),
          _section8aBody(),
        ],
        if (_subformsSelected.contains('post_enc_men')) ...[
          const SizedBox(height: 18),
          _subsectionHeader('8B · Post-encephalitis or meningitis sequelae'),
          _section8bBody(),
        ],
        if (_subformsSelected.contains('post_tbi')) ...[
          const SizedBox(height: 18),
          _subsectionHeader('8C · Post-TBI'),
          _section8cBody(),
        ],
        if (_subformsSelected.contains('genetic')) ...[
          const SizedBox(height: 18),
          _subsectionHeader('8D · Genetic syndrome'),
          _section8dBody(),
        ],
        if (_subformsSelected.contains('mixed_idiopathic')) ...[
          const SizedBox(height: 18),
          _subsectionHeader('8E · Mixed / Idiopathic'),
          _section8eBody(),
        ],
      ],
    );
  }

  Widget _section8aBody() {
    final cpSummary = _cpSubtype ?? '—';
    final levels = [
      if (_gmfcsLevel != null) 'GMFCS $_gmfcsLevel',
      if (_macsLevel != null)  'MACS $_macsLevel',
      if (_cfcsLevel != null)  'CFCS $_cfcsLevel',
      if (_edacsLevel != null) 'EDACS $_edacsLevel',
      if (_vfcsLevel != null)  'VFCS $_vfcsLevel',
    ].join(' · ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _readOnlyRow('CP subtype (from Section 1)', cpSummary),
        _readOnlyRow('Classification levels (from Section 1)',
            levels.isEmpty ? '—' : levels),
        _textField('Spasticity distribution observation',
            _cpSpasticityDistCtrl, multi: true,
            onSave: _saveCerebralPalsy),
        _textField('Movement disorder pattern (during speech, at rest)',
            _cpMovementPatternCtrl, multi: true,
            onSave: _saveCerebralPalsy),
        _textField('Postural support during speech',
            _cpPosturalSupportCtrl, multi: true,
            onSave: _saveCerebralPalsy),
        _textField('Botox history affecting speech-relevant muscles',
            _cpBotoxHistoryCtrl, multi: true,
            onSave: _saveCerebralPalsy),
        _readOnlyRow('Date of last Botox injection (from Section 1)',
            _lastBotoxDate?.toIso8601String().substring(0, 10) ?? '—'),
        _singleChips('Botox impact on speech (subjective)',
            const ['Improved', 'No change', 'Worsened', 'Not yet observed'],
            _cpBotoxImpactSpeech, (v) {
          setState(() => _cpBotoxImpactSpeech = v);
          _saveCerebralPalsy();
        }),
        _textField('Orthopedic surgery history affecting respiration',
            _cpOrthopedicSurgeryCtrl, multi: true,
            hint: 'Scoliosis, spinal fusion, hip surgery, etc.',
            onSave: _saveCerebralPalsy),
        _textField('CP-specific notes', _cpNotesCtrl,
            multi: true, onSave: _saveCerebralPalsy),
      ],
    );
  }

  Widget _section8bBody() {
    final monthsPostIllness = _peOnsetDate == null
        ? null
        : (DateTime.now().difference(_peOnsetDate!).inDays / 30.4).round();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _singleChips('Acute illness type', const [
          'Encephalitis (viral)', 'Encephalitis (bacterial)',
          'Meningitis (viral)', 'Meningitis (bacterial)',
          'Meningoencephalitis', 'Unknown',
        ], _peAcuteIllnessType, (v) {
          setState(() => _peAcuteIllnessType = v);
          _savePostEncephalitis();
        }),
        _datePickerRow('Acute illness onset date', _peOnsetDate, (d) {
          setState(() => _peOnsetDate = d);
          _savePostEncephalitis();
        }),
        if (monthsPostIllness != null)
          _readOnlyRow('Time post-illness', '$monthsPostIllness months'),
        _singleChips('Acute illness severity',
            const ['Mild', 'Moderate', 'Severe', 'Critical (PICU)'],
            _peAcuteSeverity, (v) {
          setState(() => _peAcuteSeverity = v);
          _savePostEncephalitis();
        }),
        _singleChips('Recovery trajectory observed', const [
          'Improving', 'Plateau', 'Variable', 'Declining',
          'Too early to tell',
        ], _peRecoveryTrajectory, (v) {
          setState(() => _peRecoveryTrajectory = v);
          _savePostEncephalitis();
        }),
        _textField('Recovery details', _peRecoveryDetailsCtrl,
            multi: true, onSave: _savePostEncephalitis),
        _multiChips('Comorbid impairments post-illness', const [
          'Cognitive impairment', 'Motor impairment', 'Seizure disorder',
          'Hearing loss', 'Vision impairment', 'Behavioral changes',
          'Sleep disturbance', 'None observed',
        ], _peComorbidImpairments, (v, sel) {
          setState(() {
            if (sel) {
              _peComorbidImpairments.add(v);
            } else {
              _peComorbidImpairments.remove(v);
            }
          });
          _savePostEncephalitis();
        }),
        _textField('Sequelae notes', _peSequelaeNotesCtrl,
            multi: true, onSave: _savePostEncephalitis),
      ],
    );
  }

  Widget _section8cBody() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _singleChips('Mechanism of injury', const [
          'Road traffic accident', 'Fall',
          'Non-accidental injury', 'Sports', 'Other (specify)',
        ], _tbiMechanism, (v) {
          setState(() => _tbiMechanism = v);
          _savePostTbi();
        }),
        if (_tbiMechanism == 'Other (specify)')
          _textField('Other mechanism specify', _tbiOtherMechanismCtrl,
              onSave: _savePostTbi),
        _numField('GCS at presentation', _tbiGcsCtrl,
            unit: '/15', onSave: _savePostTbi),
        _numField('Time post-injury', _tbiTimePostInjuryCtrl,
            unit: 'months', onSave: _savePostTbi),
        _numField('Coma duration', _tbiComaDurationCtrl,
            unit: 'days', onSave: _savePostTbi),
        _numField('Post-traumatic amnesia (PTA) duration',
            _tbiPtaDurationCtrl, unit: 'days', onSave: _savePostTbi),
        _singleChips('Recovery trajectory observed', const [
          'Improving', 'Plateau', 'Variable', 'Declining',
          'Too early to tell',
        ], _tbiRecoveryTrajectory, (v) {
          setState(() => _tbiRecoveryTrajectory = v);
          _savePostTbi();
        }),
        _multiChips('Cognitive-communication concerns', const [
          'Attention', 'Memory', 'Executive function',
          'Pragmatics', 'Awareness', 'Word retrieval',
          'Reasoning', 'Information processing speed',
        ], _tbiCogConcerns, (v, sel) {
          setState(() {
            if (sel) {
              _tbiCogConcerns.add(v);
            } else {
              _tbiCogConcerns.remove(v);
            }
          });
          _savePostTbi();
        }),
        _multiChips('Behavioral concerns', const [
          'Disinhibition', 'Apathy', 'Agitation',
          'Confabulation', 'Perseveration', 'Impulsivity',
        ], _tbiBehavioralConcerns, (v, sel) {
          setState(() {
            if (sel) {
              _tbiBehavioralConcerns.add(v);
            } else {
              _tbiBehavioralConcerns.remove(v);
            }
          });
          _savePostTbi();
        }),
        _singleChips('Ranchos Los Amigos Level (current)', const [
          'I (No response)', 'II (Generalized)', 'III (Localized)',
          'IV (Confused-agitated)', 'V (Confused-inappropriate)',
          'VI (Confused-appropriate)', 'VII (Automatic-appropriate)',
          'VIII (Purposeful-appropriate)',
        ], _tbiRanchosLevel, (v) {
          setState(() => _tbiRanchosLevel = v);
          _savePostTbi();
        }),
        _textField('TBI-specific notes', _tbiNotesCtrl,
            multi: true, onSave: _savePostTbi),
      ],
    );
  }

  Widget _section8dBody() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _textField('Confirmed genetic etiology',
            _genConfirmedEtiologyCtrl,
            hint: 'e.g. Worster-Drought, Möbius, Down syndrome, 22q11.2, FOXP2',
            onSave: _saveGeneticSyndrome),
        _textField('Genetic testing details', _genTestingDetailsCtrl,
            multi: true, hint: 'Which test, when, result',
            onSave: _saveGeneticSyndrome),
        _textField('Syndrome-specific motor speech features',
            _genMotorSpeechFeaturesCtrl, multi: true,
            onSave: _saveGeneticSyndrome),
        _textField('Family history', _genFamilyHistoryCtrl,
            multi: true,
            hint: 'Other affected family members, inheritance pattern',
            onSave: _saveGeneticSyndrome),
        _yesNo('Genetic counseling received?', _genCounselingReceived,
            (v) {
          setState(() => _genCounselingReceived = v);
          _saveGeneticSyndrome();
        }),
        _textField('Genetic syndrome notes', _genNotesCtrl,
            multi: true, onSave: _saveGeneticSyndrome),
      ],
    );
  }

  Widget _section8eBody() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _textField('Differential reasoning',
            _miDifferentialReasoningCtrl, multi: true,
            hint: "Why not a specific etiology yet",
            onSave: _saveMixedIdiopathic),
        _textField('Working hypothesis', _miWorkingHypothesisCtrl,
            multi: true, onSave: _saveMixedIdiopathic),
        _multiChips('Pending investigations', const [
          'Genetic testing', 'Neuroimaging', 'EEG',
          'Metabolic workup', 'Audiological evaluation',
          'Ophthalmological evaluation', 'None pending',
        ], _miPendingInvestigations, (v, sel) {
          setState(() {
            if (sel) {
              _miPendingInvestigations.add(v);
            } else {
              _miPendingInvestigations.remove(v);
            }
          });
          _saveMixedIdiopathic();
        }),
        _textField('Investigation timeline',
            _miInvestigationTimelineCtrl, multi: true,
            onSave: _saveMixedIdiopathic),
        _textField('Mixed / idiopathic notes', _miNotesCtrl,
            multi: true, onSave: _saveMixedIdiopathic),
      ],
    );
  }

  // ── Section 9 body — Functional Communication Screen ──────────────
  Widget _section9Body() {
    final receptiveAge = _receptiveAgeCtrl.text.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _groupLabel('A · Receptive language'),
        _singleChips('Receptive language assessment approach', const [
          'Informal observation only', 'Formal assessment',
          'External report',
        ], _recLangApproach, (v) {
          setState(() => _recLangApproach = v);
          _saveFunctionalCommunication();
        }),
        if (_recLangApproach == 'Formal assessment' ||
            _recLangApproach == 'External report')
          _textField('Receptive language battery used',
              _recLangBatteryCtrl, onSave: _saveFunctionalCommunication),
        _readOnlyRow('Receptive language age estimate (Section 1)',
            receptiveAge.isEmpty ? '—' : '$receptiveAge mo'),
        _singleChips('Receptive language profile', const [
          'Within normal limits', 'Mildly reduced',
          'Moderately reduced', 'Severely reduced',
          'Unable to assess',
        ], _recLangProfile, (v) {
          setState(() => _recLangProfile = v);
          _saveFunctionalCommunication();
        }),
        _textField('Receptive notes', _recLangNotesCtrl,
            multi: true, onSave: _saveFunctionalCommunication),

        const SizedBox(height: 14),
        _groupLabel('B · Expressive language attempts'),
        _singleChips('Expressive language assessment approach', const [
          'Informal observation only', 'Formal assessment',
          'External report',
        ], _expLangApproach, (v) {
          setState(() => _expLangApproach = v);
          _saveFunctionalCommunication();
        }),
        if (_expLangApproach == 'Formal assessment' ||
            _expLangApproach == 'External report')
          _textField('Expressive battery used', _expLangBatteryCtrl,
              onSave: _saveFunctionalCommunication),
        _singleChips('Intelligibility-corrected expressive estimate',
            const [
              'Within normal limits', 'Mildly reduced',
              'Moderately reduced', 'Severely reduced',
              'Cannot determine due to motor severity',
            ], _expLangEstimate, (v) {
          setState(() => _expLangEstimate = v);
          _saveFunctionalCommunication();
        }),
        _ghostNote(
            'Account for motor execution affecting expressive output. If child can convey complex ideas via gesture / AAC / writing, language is preserved even when speech intelligibility is severely reduced.'),
        _textField('Expressive notes', _expLangNotesCtrl,
            multi: true, onSave: _saveFunctionalCommunication),

        const SizedBox(height: 14),
        _groupLabel('C · Symbolic play and cognition'),
        _singleChips('Symbolic play observation', const [
          'Age-appropriate', 'Emerging', 'Limited',
          'Not observed', 'Not assessable',
        ], _symbolicPlay, (v) {
          setState(() => _symbolicPlay = v);
          _saveFunctionalCommunication();
        }),
        _singleChips('Cognitive level estimate (informal)', const [
          'Age-appropriate', 'Mildly delayed', 'Moderately delayed',
          'Severely delayed', 'Cannot determine',
        ], _cognitiveLevel, (v) {
          setState(() => _cognitiveLevel = v);
          _saveFunctionalCommunication();
        }),
        _multiChips('Cognitive batteries used (if formal)', const [
          'WPPSI', 'WISC', 'MISIC', 'Vineland', 'Bayley',
          'Other (specify)',
        ], _cogBatteries, (v, sel) {
          setState(() {
            if (sel) {
              _cogBatteries.add(v);
            } else {
              _cogBatteries.remove(v);
            }
          });
          _saveFunctionalCommunication();
        }),
        _textField('Cognitive-symbolic notes', _cogSymbolicNotesCtrl,
            multi: true, onSave: _saveFunctionalCommunication),

        const SizedBox(height: 14),
        _groupLabel('D · AAC candidacy considerations'),
        _singleChips('AAC candidacy at this assessment', const [
          'Strong candidate', 'Moderate candidate',
          'Continue speech-only',
          'Already using AAC effectively', 'Reassess in future',
        ], _aacCandidacy, (v) {
          setState(() => _aacCandidacy = v);
          _saveFunctionalCommunication();
        }),
        _textField('AAC reasoning', _aacReasoningCtrl,
            multi: true, onSave: _saveFunctionalCommunication),
        _ghostNote(
            'AAC candidacy is a clinical judgment, not auto-derived. Consider: motor-language gap, family readiness, intelligibility ceiling, fatigue patterns.'),
        _yesNo('Augmented input strategies effective',
            _augInputEffective, (v) {
          setState(() => _augInputEffective = v);
          _saveFunctionalCommunication();
        }),
        if (_augInputEffective)
          _textField('Augmented input details', _augInputDetailsCtrl,
              multi: true, onSave: _saveFunctionalCommunication),

        const SizedBox(height: 14),
        _groupLabel('E · Communication-cognition synthesis'),
        _singleChips('Primary communication concern', const [
          'Motor execution (dysarthria)',
          'Language (developmental)',
          'Mixed motor-language',
          'Cognitive-communication',
          'Behavioral / regulatory',
        ], _primaryCommConcern, (v) {
          setState(() => _primaryCommConcern = v);
          _saveFunctionalCommunication();
        }),
        _textField('Synthesis notes', _commSynthesisCtrl,
            multi: true, onSave: _saveFunctionalCommunication),
      ],
    );
  }

  // ── Section 10 body — Differential Diagnosis ──────────────────────
  Widget _section10Body() {
    final autoMayo = _mayoType ?? '—';
    final autoSubsystems = <String>[
      if (_respSeverity == 'Severe' || _respSeverity == 'Moderate') 'Respiration',
      if (_phonSeverity == 'Severe' || _phonSeverity == 'Moderate') 'Phonation',
      if (_articSeverity == 'Severe' || _articSeverity == 'Moderate') 'Articulation',
      if (_resonanceSeverity == 'Severe' || _resonanceSeverity == 'Moderate') 'Resonance',
      if (_prosodySeverity == 'Severe' || _prosodySeverity == 'Moderate') 'Prosody',
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _groupLabel('A · Mayo dysarthria type final classification'),
        _readOnlyRow('Mayo type (from Section 1)', autoMayo),
        _ghostNote(
            'Section 1 captures initial Mayo classification hypothesis. Section 10 is where you finalize after observing five subsystems.'),
        _yesNo('Override Mayo type?', _ddOverrideMayo, (v) {
          setState(() => _ddOverrideMayo = v);
          _saveDifferentialDx();
        }),
        if (_ddOverrideMayo)
          _singleChips('Mayo type override', const [
            'Spastic', 'Flaccid', 'Ataxic', 'Hypokinetic',
            'Hyperkinetic', 'Mixed', 'Unilateral UMN',
          ], _ddMayoOverride, (v) {
            setState(() {
              _ddMayoOverride = v;
              if (v != null) _mayoType = v; // sync to Section 1's local
            });
            _saveDifferentialDx();
          }),

        const SizedBox(height: 14),
        _groupLabel('B · Severity grading'),
        _singleChips('Overall severity',
            const ['Mild', 'Moderate', 'Severe', 'Profound'],
            _ddOverallSeverity, (v) {
          setState(() => _ddOverallSeverity = v);
          _saveDifferentialDx();
        }),
        _textField('Severity rationale', _ddSeverityRationaleCtrl,
            multi: true, onSave: _saveDifferentialDx),

        const SizedBox(height: 14),
        _groupLabel('C · Subsystems most affected'),
        _readOnlyRow(
            'Auto-pulled (Moderate or Severe in Section 4)',
            autoSubsystems.isEmpty ? '—' : autoSubsystems.join(', ')),
        _yesNo('Override subsystems-affected list?',
            _ddOverrideSubsystems, (v) {
          setState(() => _ddOverrideSubsystems = v);
          _saveDifferentialDx();
        }),
        if (_ddOverrideSubsystems)
          _multiChips('Subsystems most affected (override)',
              const ['Respiration', 'Phonation', 'Articulation',
                     'Resonance', 'Prosody'],
              _ddSubsystemsAffectedOverride, (v, sel) {
            setState(() {
              if (sel) {
                _ddSubsystemsAffectedOverride.add(v);
              } else {
                _ddSubsystemsAffectedOverride.remove(v);
              }
            });
            _saveDifferentialDx();
          }),

        const SizedBox(height: 14),
        _groupLabel('D · Differential reasoning'),
        _ghostNote(
            'Dysarthria = motor execution / weakness. CAS = motor planning / inconsistency. Key differentiators: consistency of errors, oral mech findings, neurological signs.'),
        _textField('Differentiating from CAS', _ddDiffFromCasCtrl,
            multi: true, onSave: _saveDifferentialDx),
        _textField('Differentiating from phonological disorder',
            _ddDiffFromPhonologicalCtrl, multi: true,
            onSave: _saveDifferentialDx),
        _textField('Differentiating from speech-language delay',
            _ddDiffFromDelayCtrl, multi: true,
            onSave: _saveDifferentialDx),
        _textField('Differentiating from articulation disorder',
            _ddDiffFromArticulationCtrl, multi: true,
            onSave: _saveDifferentialDx),

        const SizedBox(height: 14),
        _groupLabel('E · Working hypothesis'),
        _singleChips('Working hypothesis confidence',
            const ['Provisional', 'Working', 'Confirmed'],
            _ddHypothesisConfidence, (v) {
          setState(() => _ddHypothesisConfidence = v);
          _saveDifferentialDx();
        }),
        _textField('Working hypothesis statement',
            _ddHypothesisStatementCtrl, multi: true,
            onSave: _saveDifferentialDx),

        const SizedBox(height: 14),
        _groupLabel('F · Contributing factors'),
        _multiChips('Factors', const [
          'Cognitive level', 'Hearing status',
          'Behavioral / cooperation', 'Family support',
          'Fatigue / endurance', 'Comorbid orthopedic',
          'Comorbid feeding', 'Limited language exposure',
          'Multilingual environment', 'Socioeconomic factors',
          'Educational placement appropriate',
          'Inappropriate placement',
        ], _ddContributingFactors, (v, sel) {
          setState(() {
            if (sel) {
              _ddContributingFactors.add(v);
            } else {
              _ddContributingFactors.remove(v);
            }
          });
          _saveDifferentialDx();
        }),
        _textField('Contributing factors notes',
            _ddContributingNotesCtrl, multi: true,
            onSave: _saveDifferentialDx),
      ],
    );
  }

  // ── Section 12 body — FOCUS-34 + 3 ratings ────────────────────────
  Widget _section12Body() {
    final hasItems = _focus34Items.values.any((v) => v > 0);
    final f34Total = _focus34Items.values.fold<int>(0, (a, b) => a + b);
    final showFocus = _focus34AdminMode != null &&
        _focus34AdminMode != 'Not administered';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _groupLabel('A · FOCUS-34 (Focus on Outcomes of Communication Under Six)'),
        _ghostNote(
            'FOCUS-34 is the gold-standard pediatric communication outcome measure. 34 items each 0–7. Higher = better functional communication. Currently captured as total only — per-item persistence is on the 4.0.7.27c-fix1 backlog.'),
        _singleChips('FOCUS-34 administration mode', const [
          'Caregiver self-completed',
          'Clinician-administered with caregiver',
          'Not administered',
        ], _focus34AdminMode, (v) {
          setState(() => _focus34AdminMode = v);
          _saveQol();
        }),
        if (showFocus) ...[
          for (var i = 1; i <= 34; i++) _focus34Row(i),
          const SizedBox(height: 6),
          _qolBadge(
            label: 'FOCUS-34 total',
            total: hasItems ? f34Total : 0,
            maxScore: 238, // 34 × 7
          ),
          if (_focus34TotalLoaded != null && _focus34TotalLoaded != f34Total) ...[
            const SizedBox(height: 4),
            Text('Last saved total: $_focus34TotalLoaded',
                style: GoogleFonts.dmSans(
                    fontSize: 11, color: _inkGhost,
                    fontStyle: FontStyle.italic)),
          ],
          _ghostNote(
              'FOCUS-34 tracks change over time. Capture baseline now, re-administer at 3–6 month intervals.'),
        ],

        const SizedBox(height: 14),
        _groupLabel('B · Caregiver / teacher / peer ratings (1–10)'),
        _ratingSlider('Parent communication confidence',
            _parentConfidence, (v) {
          setState(() => _parentConfidence = v);
        }, _saveQol),
        _ghostNote(
            'How confident does the parent feel that their child can communicate in daily life?'),
        if (_parentConfidenceLoaded != null && _parentConfidenceLoaded != _parentConfidence) ...[
          Text('Last saved: $_parentConfidenceLoaded',
              style: GoogleFonts.dmSans(
                  fontSize: 11, color: _inkGhost,
                  fontStyle: FontStyle.italic)),
        ],
        _ratingSlider('Teacher communication impact',
            _teacherImpact, (v) {
          setState(() => _teacherImpact = v);
        }, _saveQol),
        _ghostNote(
            "How much does the child's communication difficulty affect classroom participation? Higher = greater impact (lower is better).") ,
        if (_teacherImpactLoaded != null && _teacherImpactLoaded != _teacherImpact) ...[
          Text('Last saved: $_teacherImpactLoaded',
              style: GoogleFonts.dmSans(
                  fontSize: 11, color: _inkGhost,
                  fontStyle: FontStyle.italic)),
        ],
        _ratingSlider('Peer interaction quality',
            _peerInteraction, (v) {
          setState(() => _peerInteraction = v);
        }, _saveQol),
        _ghostNote(
            'How effectively does the child communicate with peers? Higher = better.'),
        if (_peerInteractionLoaded != null && _peerInteractionLoaded != _peerInteraction) ...[
          Text('Last saved: $_peerInteractionLoaded',
              style: GoogleFonts.dmSans(
                  fontSize: 11, color: _inkGhost,
                  fontStyle: FontStyle.italic)),
        ],

        const SizedBox(height: 14),
        _groupLabel('C · Notes'),
        _textField('QoL administration notes', _qolNotesCtrl,
            multi: true, onSave: _saveQol),
      ],
    );
  }

  Widget _focus34Row(int i) {
    final v = _focus34Items[i] ?? 0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('$i. FOCUS-34 item $i',
                    style: GoogleFonts.dmSans(
                        fontSize: 12, color: _ink)),
              ),
              Text('$v',
                  style: GoogleFonts.dmSans(
                      fontSize: 12, color: _ink,
                      fontWeight: FontWeight.w600)),
              Text(' / 7',
                  style: GoogleFonts.dmSans(
                      fontSize: 11, color: _inkGhost)),
            ],
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 2,
              activeTrackColor: _teal,
              inactiveTrackColor: _line,
              thumbColor: _teal,
              overlayColor: _teal.withValues(alpha: 0.18),
            ),
            child: Slider(
              value: v.toDouble(),
              min: 0, max: 7, divisions: 7,
              onChanged: (d) => setState(() => _focus34Items[i] = d.toInt()),
              onChangeEnd: (_) => _saveQol(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _ratingSlider(String label, int value,
      ValueChanged<int> onChanged, VoidCallback onCommit) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(label,
                    style: GoogleFonts.dmSans(
                        fontSize: 12, color: _inkGhost,
                        fontWeight: FontWeight.w500)),
              ),
              Text('$value',
                  style: GoogleFonts.dmSans(
                      fontSize: 13, color: _ink,
                      fontWeight: FontWeight.w600)),
              Text(' / 10',
                  style: GoogleFonts.dmSans(
                      fontSize: 11, color: _inkGhost)),
            ],
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 3,
              activeTrackColor: _teal,
              inactiveTrackColor: _line,
              thumbColor: _teal,
              overlayColor: _teal.withValues(alpha: 0.18),
            ),
            child: Slider(
              value: value.toDouble().clamp(1, 10),
              min: 1, max: 10, divisions: 9,
              onChanged: (d) => onChanged(d.toInt()),
              onChangeEnd: (_) => onCommit(),
            ),
          ),
        ],
      ),
    );
  }

  // ── Section 15 body — Final Clinical Impression & Plan ────────────
  Widget _section15Body() {
    final mayoFinal = (_ddOverrideMayo ? _ddMayoOverride : null) ?? _mayoType ?? '—';
    final severityFinal = _ddOverallSeverity ?? '—';
    final etiologyDisplay = _etiology ?? '—';
    final subsystemsAffected = _ddOverrideSubsystems
        ? _ddSubsystemsAffectedOverride.toList()
        : <String>[
            if (_respSeverity == 'Severe' || _respSeverity == 'Moderate') 'Respiration',
            if (_phonSeverity == 'Severe' || _phonSeverity == 'Moderate') 'Phonation',
            if (_articSeverity == 'Severe' || _articSeverity == 'Moderate') 'Articulation',
            if (_resonanceSeverity == 'Severe' || _resonanceSeverity == 'Moderate') 'Resonance',
            if (_prosodySeverity == 'Severe' || _prosodySeverity == 'Moderate') 'Prosody',
          ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _groupLabel('A · Final diagnosis'),
        _textField('Final diagnosis', _ciFinalDxCtrl,
            multi: true, onSave: _saveClinicalImpression),
        _textField('ICD-style code', _ciIcdCodeCtrl,
            hint: 'e.g. R47.1 Dysarthria and anarthria, or G80.x for CP-related',
            onSave: _saveClinicalImpression),
        _readOnlyRow('Mayo dysarthria type (from Section 10)', mayoFinal),
        _readOnlyRow('Severity grading (from Section 10)', severityFinal),

        const SizedBox(height: 14),
        _groupLabel('B · Etiology classification'),
        _readOnlyRow('Etiology (from Section 1)', etiologyDisplay),

        const SizedBox(height: 14),
        _groupLabel('C · Subsystems affected (most-to-least)'),
        _readOnlyRow('Subsystems',
            subsystemsAffected.isEmpty ? '—' : subsystemsAffected.join(' · ')),

        const SizedBox(height: 14),
        _groupLabel('D · Prognostic factors'),
        _readOnlyRow(
            'Stimulability response (from Section 7)',
            _stimRecommendedApproaches.isEmpty
                ? '—'
                : '${_stimRecommendedApproaches.length} approach(es) recommended'),
        _singleChips('Cognitive-linguistic profile',
            const ['Strong (preserved cognition / language)',
                   'Moderate', 'Limited'],
            _ciCogLinguistic, (v) {
          setState(() => _ciCogLinguistic = v);
          _saveClinicalImpression();
        }),
        _singleChips('Family support',
            const ['Strong', 'Moderate', 'Limited', 'Concerns'],
            _ciFamilySupport, (v) {
          setState(() => _ciFamilySupport = v);
          _saveClinicalImpression();
        }),
        _multiChips('Comorbidities affecting outcome (auto-populated, editable)',
            const [
              'Intellectual disability', 'ASD', 'Seizure disorder',
              'Feeding/swallowing concerns', 'Drooling functional impact',
              'Visual impairment', 'Hearing impairment',
              'Sensory processing differences', 'Other',
            ], _ciComorbiditiesAffectingOutcome, (v, sel) {
          setState(() {
            if (sel) {
              _ciComorbiditiesAffectingOutcome.add(v);
            } else {
              _ciComorbiditiesAffectingOutcome.remove(v);
            }
          });
          _saveClinicalImpression();
        }),
        _singleChips('Etiology trajectory', const [
          'Improving (post-acute recovery phase)',
          'Stable', 'Progressive', 'Unknown',
        ], _ciEtiologyTrajectory, (v) {
          setState(() => _ciEtiologyTrajectory = v);
          _saveClinicalImpression();
        }),
        _singleChips('Overall prognosis',
            const ['Good', 'Fair', 'Guarded', 'Poor'],
            _ciOverallPrognosis, (v) {
          setState(() => _ciOverallPrognosis = v);
          _saveClinicalImpression();
        }),
        _textField('Prognostic rationale', _ciPrognosticRationaleCtrl,
            multi: true, onSave: _saveClinicalImpression),

        const SizedBox(height: 14),
        _groupLabel('E · Management plan'),
        _multiChips('Recommended therapy approaches', const [
          'LSVT-LOUD', 'SPEAK OUT!', 'PROMPT',
          'Articulation drill', 'Rate control therapy',
          'Breath group manipulation', 'Loudness building',
          'Phrasing strategies',
          'Compensatory / strategic approach',
          'AAC integration', 'Parent / caregiver training',
          'Beckman oral motor (note: weak evidence)',
        ], _ciInterventions, (v, sel) {
          setState(() {
            if (sel) {
              _ciInterventions.add(v);
            } else {
              _ciInterventions.remove(v);
            }
          });
          _saveClinicalImpression();
        }),
        _textField('Therapy approach reasoning',
            _ciTherapyReasoningCtrl, multi: true,
            onSave: _saveClinicalImpression),
        _numField('Therapy intensity', _ciIntensityCtrl,
            unit: 'sessions/week', onSave: _saveClinicalImpression),
        _numField('Estimated session count', _ciSessionCountCtrl,
            unit: 'sessions', onSave: _saveClinicalImpression),
        _numField('Session duration', _ciSessionDurationCtrl,
            unit: 'min', onSave: _saveClinicalImpression),
        _singleChips('Frequency', const [
          'Twice weekly', 'Weekly', 'Biweekly', 'Monthly', 'As needed',
        ], _ciFrequency, (v) {
          setState(() => _ciFrequency = v);
          _saveClinicalImpression();
        }),
        _textField('Discharge criteria', _ciDischargeCriteriaCtrl,
            multi: true, onSave: _saveClinicalImpression),
        _textField('Functional outcome targets',
            _ciFunctionalOutcomesCtrl, multi: true,
            onSave: _saveClinicalImpression),

        const SizedBox(height: 14),
        _groupLabel('F · Referrals'),
        _multiChips('Referrals needed', const [
          'Neurology', 'Orthopedics (postural / spasticity)',
          'Physiatry', 'Audiology',
          'OT (postural support / AAC access)',
          'Feeding clinic', 'Educational support',
          'Genetic counseling', 'Psychology', 'Other',
        ], _ciReferrals, (v, sel) {
          setState(() {
            if (sel) {
              _ciReferrals.add(v);
            } else {
              _ciReferrals.remove(v);
            }
          });
          _saveClinicalImpression();
        }),
        _textField('Referral reasoning', _ciReferralReasoningCtrl,
            multi: true, onSave: _saveClinicalImpression),

        const SizedBox(height: 14),
        _groupLabel('G · Cross-domain alerts'),
        _yesNo('Flag for dysphagia assessment?',
            _flagDysphagiaReferral, (v) {
          setState(() => _flagDysphagiaReferral = v);
          _saveCrossDomainFlags();
        }),
        _ghostNote(
            'Toggle on if oral mech findings, feeding concerns from Section 1, or EDACS level suggests dysphagia evaluation is warranted.'),
        _yesNo('Flag for AAC assessment?', _flagAacAssessment, (v) {
          setState(() => _flagAacAssessment = v);
          _saveCrossDomainFlags();
        }),
        _ghostNote(
            'Toggle on if intelligibility patterns, motor-language gap, or family priorities suggest AAC trial is warranted.'),

        const SizedBox(height: 14),
        _groupLabel('H · Caregiver education priorities'),
        _multiChips('Education topics', const [
          'Communication strategies', 'Posture for speech',
          'AAC access training', 'Home practice support',
          'School communication advocacy',
          'Realistic expectations setting', 'Sibling involvement',
          'Multi-language strategy',
        ], _ciCaregiverEdu, (v, sel) {
          setState(() {
            if (sel) {
              _ciCaregiverEdu.add(v);
            } else {
              _ciCaregiverEdu.remove(v);
            }
          });
          _saveClinicalImpression();
        }),

        const SizedBox(height: 14),
        _groupLabel('I · Final clinical synthesis'),
        _textField('Final clinical narrative', _ciFinalNarrativeCtrl,
            multi: true,
            hint: 'The 1-paragraph summary that goes into the SLP final report',
            onSave: _saveClinicalImpression),
      ],
    );
  }

  Widget _readOnlyRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 220,
            child: Text(label,
                style: GoogleFonts.dmSans(
                    fontSize: 12, color: _inkGhost,
                    fontWeight: FontWeight.w500)),
          ),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: _tealSoft.withValues(alpha: 0.45),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: _teal.withValues(alpha: 0.4)),
              ),
              child: Text(value,
                  style: GoogleFonts.dmSans(
                      fontSize: 12, color: _teal,
                      fontWeight: FontWeight.w500)),
            ),
          ),
        ],
      ),
    );
  }

  // ── Section 11 body — outcome comparison ───────────────────────────
  Widget _section11Body() {
    final outcome = _outcome;
    if (outcome == null || !outcome.hasFollowUp) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
            decoration: BoxDecoration(
              color: _tealSoft.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: _tealSoft),
            ),
            child: Text(
              'Baseline locked. Outcome tracking begins on the next assessment.',
              style: GoogleFonts.dmSans(
                  fontSize: 13, color: _ink, height: 1.5),
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _addFollowUp,
            icon: const Icon(Icons.add_rounded, size: 16, color: _teal),
            label: Text('Add follow-up assessment',
                style: GoogleFonts.dmSans(
                    fontSize: 13, color: _teal, fontWeight: FontWeight.w500)),
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: _teal.withValues(alpha: 0.45)),
              padding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 8),
            ),
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(flex: 4, child: SizedBox()),
            Expanded(flex: 2, child: _headCell('Baseline')),
            Expanded(flex: 2, child: _headCell('Latest')),
            Expanded(flex: 2, child: _headCell('Δ')),
          ],
        ),
        for (final group in outcome.groups) ...[
          if (_groupHasData(group)) ...[
            const SizedBox(height: 10),
            _groupLabel(group.label),
            for (final row in group.rows)
              if (row.baseline != null || row.latest != null)
                _outcomeDataRow(row),
          ],
        ],
        const SizedBox(height: 14),
        OutlinedButton.icon(
          onPressed: _addFollowUp,
          icon: const Icon(Icons.add_rounded, size: 16, color: _teal),
          label: Text('Add follow-up assessment',
              style: GoogleFonts.dmSans(
                  fontSize: 13, color: _teal, fontWeight: FontWeight.w500)),
          style: OutlinedButton.styleFrom(
            side: BorderSide(color: _teal.withValues(alpha: 0.45)),
            padding: const EdgeInsets.symmetric(
                horizontal: 14, vertical: 8),
          ),
        ),
      ],
    );
  }

  bool _groupHasData(OutcomeGroup g) =>
      g.rows.any((r) => r.baseline != null || r.latest != null);

  Widget _headCell(String text) => Text(text,
      style: GoogleFonts.syne(
          fontSize: 9, fontWeight: FontWeight.w600,
          color: _inkGhost, letterSpacing: 1.2));

  Widget _outcomeDataRow(OutcomeRow r) {
    final color = switch (r.verdict) {
      'improved'  => _green,
      'regressed' => _coral,
      _           => _inkGhost,
    };
    final delta = r.delta;
    final deltaText = delta == null
        ? '—'
        : (delta == 0
            ? '0'
            : (delta > 0 ? '+${_fmtNum(delta)}' : _fmtNum(delta)));
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(flex: 4,
              child: Text('${r.label}${r.unit.isEmpty ? '' : ' (${r.unit})'}',
                  style: GoogleFonts.dmSans(fontSize: 12, color: _ink))),
          Expanded(flex: 2, child: _outcomeCell(r.baseline)),
          Expanded(flex: 2, child: _outcomeCell(r.latest)),
          Expanded(flex: 2,
              child: Text(deltaText,
                  style: GoogleFonts.dmSans(
                      fontSize: 12, color: color,
                      fontWeight: FontWeight.w600))),
        ],
      ),
    );
  }

  Widget _outcomeCell(num? v) => Text(v == null ? '—' : _fmtNum(v),
      style: GoogleFonts.dmSans(fontSize: 12, color: _ink));

  String _fmtNum(num v) {
    if (v is int) return v.toString();
    final asDouble = v.toDouble();
    if (asDouble == asDouble.roundToDouble()) {
      return asDouble.toInt().toString();
    }
    return asDouble.toStringAsFixed(2);
  }

  // ── Field primitives ───────────────────────────────────────────────

  Widget _subsectionHeader(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(text,
          style: GoogleFonts.syne(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: _teal,
              letterSpacing: 1.4)),
    );
  }

  Widget _groupLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(text.toUpperCase(),
          style: GoogleFonts.syne(
              fontSize: 9,
              fontWeight: FontWeight.w600,
              color: _inkGhost,
              letterSpacing: 1.4)),
    );
  }

  Widget _ghostNote(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(
          color: _tealSoft.withValues(alpha: 0.30),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: _tealSoft),
        ),
        child: Text(text,
            style: GoogleFonts.dmSans(
                fontSize: 12, color: _ink,
                fontStyle: FontStyle.italic, height: 1.5)),
      ),
    );
  }

  Widget _textField(
    String label,
    TextEditingController ctrl, {
    bool multi = false,
    String? hint,
    required VoidCallback onSave,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: GoogleFonts.dmSans(
                  fontSize: 12, color: _inkGhost,
                  fontWeight: FontWeight.w500)),
          const SizedBox(height: 4),
          Focus(
            onFocusChange: (focused) {
              if (!focused) onSave();
            },
            child: TextField(
              controller: ctrl,
              maxLines: multi ? 3 : 1,
              style: GoogleFonts.dmSans(fontSize: 13, color: _ink),
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: GoogleFonts.dmSans(
                    fontSize: 12,
                    color: _inkGhost.withValues(alpha: 0.6)),
                border: const OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _numField(
    String label,
    TextEditingController ctrl, {
    required String unit,
    required VoidCallback onSave,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: GoogleFonts.dmSans(
                  fontSize: 12, color: _inkGhost,
                  fontWeight: FontWeight.w500)),
          const SizedBox(height: 4),
          Focus(
            onFocusChange: (focused) {
              if (!focused) onSave();
            },
            child: TextField(
              controller: ctrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
              ],
              style: GoogleFonts.dmSans(fontSize: 13, color: _ink),
              decoration: InputDecoration(
                suffixText: unit,
                suffixStyle: GoogleFonts.dmSans(
                    fontSize: 12, color: _inkGhost),
                border: const OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _yesNo(String label, bool value, ValueChanged<bool> onChanged) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Expanded(
            child: Text(label,
                style: GoogleFonts.dmSans(
                    fontSize: 13, color: _ink,
                    fontWeight: FontWeight.w500)),
          ),
          _yesNoChip('Yes', value, () => onChanged(true)),
          const SizedBox(width: 6),
          _yesNoChip('No', !value, () => onChanged(false)),
        ],
      ),
    );
  }

  Widget _yesNoChip(String label, bool selected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: selected ? _tealSoft.withValues(alpha: 0.55) : Colors.white,
          border: Border.all(color: selected ? _teal : _line),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(label,
            style: GoogleFonts.dmSans(
                fontSize: 12,
                color: selected ? _teal : _ink,
                fontWeight: FontWeight.w500)),
      ),
    );
  }

  Widget _singleChips(
    String label,
    List<String> options,
    String? selected,
    ValueChanged<String?> onChanged,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: GoogleFonts.dmSans(
                  fontSize: 12, color: _inkGhost,
                  fontWeight: FontWeight.w500)),
          const SizedBox(height: 6),
          if (options.isEmpty)
            Text('—',
                style: GoogleFonts.dmSans(
                    fontSize: 12, color: _inkGhost,
                    fontStyle: FontStyle.italic))
          else
            Wrap(
              spacing: 6, runSpacing: 6,
              children: [
                for (final o in options)
                  _yesNoChip(o, selected == o,
                      () => onChanged(o == selected ? null : o)),
              ],
            ),
        ],
      ),
    );
  }

  Widget _multiChips(
    String label,
    List<String> options,
    Set<String> selected,
    void Function(String, bool) onToggle,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: GoogleFonts.dmSans(
                  fontSize: 12, color: _inkGhost,
                  fontWeight: FontWeight.w500)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6, runSpacing: 6,
            children: [
              for (final o in options)
                _yesNoChip(o, selected.contains(o),
                    () => onToggle(o, !selected.contains(o))),
            ],
          ),
        ],
      ),
    );
  }

  Widget _datePickerRow(
      String label, DateTime? value, ValueChanged<DateTime> onChanged) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Expanded(
            child: Text(label,
                style: GoogleFonts.dmSans(
                    fontSize: 13, color: _ink,
                    fontWeight: FontWeight.w500)),
          ),
          OutlinedButton.icon(
            onPressed: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: value ?? DateTime.now(),
                firstDate: DateTime(2000),
                lastDate: DateTime.now().add(const Duration(days: 1)),
              );
              if (picked != null) onChanged(picked);
            },
            icon: const Icon(Icons.calendar_today_outlined, size: 14),
            label: Text(value == null
                ? 'Pick date'
                : value.toIso8601String().substring(0, 10)),
            style: OutlinedButton.styleFrom(
              foregroundColor: _ink,
              side: BorderSide(color: _line),
              padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 6),
            ),
          ),
        ],
      ),
    );
  }

  /// Age-in-months input + source dropdown side-by-side. Used by the
  /// 5 developmental-age rows in Section 1A. Each writes to typed
  /// parent columns (mental_age_months / mental_age_source / etc.).
  Widget _ageWithSourceRow(
    String label,
    TextEditingController ctrl,
    String? source,
    ValueChanged<String?> onSourceChange,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: GoogleFonts.dmSans(
                  fontSize: 12, color: _inkGhost,
                  fontWeight: FontWeight.w500)),
          const SizedBox(height: 4),
          Row(
            children: [
              SizedBox(
                width: 90,
                child: Focus(
                  onFocusChange: (f) {
                    if (!f) _saveCaseHistory();
                  },
                  child: TextField(
                    controller: ctrl,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                    ],
                    style: GoogleFonts.dmSans(fontSize: 13, color: _ink),
                    decoration: InputDecoration(
                      suffixText: 'mo',
                      suffixStyle: GoogleFonts.dmSans(
                          fontSize: 11, color: _inkGhost),
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButtonFormField<String?>(
                  initialValue: source,
                  isDense: true,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(
                        horizontal: 8, vertical: 12),
                  ),
                  hint: Text('Source',
                      style: GoogleFonts.dmSans(
                          fontSize: 12, color: _inkGhost)),
                  style: GoogleFonts.dmSans(fontSize: 12, color: _ink),
                  items: [
                    for (final o in _kAgeSourceOptions)
                      DropdownMenuItem(value: o, child: Text(o,
                          overflow: TextOverflow.ellipsis)),
                  ],
                  onChanged: onSourceChange,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// CP classification row — single Roman-numeral chip selection plus
  /// the descriptor text rendered as a ghost-italic line BELOW the
  /// chip row when one is selected. Tap targets are 44+ px so 320 px
  /// viewports stay usable.
  Widget _classificationRow(
    String label,
    List<String> options,
    Map<String, String> descriptors,
    String? selected,
    ValueChanged<String?> onChanged,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: GoogleFonts.dmSans(
                  fontSize: 12, color: _inkGhost,
                  fontWeight: FontWeight.w500)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6, runSpacing: 6,
            children: [
              for (final o in options)
                GestureDetector(
                  onTap: () => onChanged(o == selected ? null : o),
                  child: Container(
                    constraints: const BoxConstraints(
                        minWidth: 44, minHeight: 44),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: selected == o
                          ? _tealSoft.withValues(alpha: 0.55)
                          : Colors.white,
                      border: Border.all(
                          color: selected == o ? _teal : _line),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Text(o,
                        style: GoogleFonts.dmSans(
                            fontSize: 13,
                            color: selected == o ? _teal : _ink,
                            fontWeight: FontWeight.w600)),
                  ),
                ),
            ],
          ),
          if (selected != null && descriptors[selected] != null) ...[
            const SizedBox(height: 4),
            Text(descriptors[selected]!,
                style: GoogleFonts.dmSans(
                    fontSize: 11, color: _inkGhost,
                    fontStyle: FontStyle.italic, height: 1.4)),
          ],
        ],
      ),
    );
  }

  /// E.2 setting-specific intelligibility slider (0–100). Records
  /// touched-state so first save doesn't cascade zeros into every
  /// typed column.
  Widget _settingPctSlider(String label, String key) {
    final value = _settingPct[key] ?? 0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(label,
                    style: GoogleFonts.dmSans(
                        fontSize: 12, color: _ink)),
              ),
              Text('$value',
                  style: GoogleFonts.dmSans(
                      fontSize: 12, color: _ink,
                      fontWeight: FontWeight.w600)),
              Text(' %',
                  style: GoogleFonts.dmSans(
                      fontSize: 11, color: _inkGhost)),
            ],
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 2,
              activeTrackColor: _teal,
              inactiveTrackColor: _line,
              thumbColor: _teal,
              overlayColor: _teal.withValues(alpha: 0.18),
            ),
            child: Slider(
              value: value.toDouble(),
              min: 0, max: 100, divisions: 100,
              onChanged: (d) {
                setState(() {
                  _settingPct[key] = d.toInt();
                  _settingPctTouched.add(key);
                });
              },
              onChangeEnd: (_) => _saveIntelligibilitySettings(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _languageRow(int index) {
    final entry = _languages[index];
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 4,
            child: Focus(
              onFocusChange: (f) {
                if (!f) _saveCaseHistory();
              },
              child: TextField(
                controller: entry.nameCtrl,
                style: GoogleFonts.dmSans(fontSize: 13, color: _ink),
                decoration: InputDecoration(
                  hintText: 'Language',
                  hintStyle: GoogleFonts.dmSans(
                      fontSize: 12, color: _inkGhost.withValues(alpha: 0.6)),
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 5,
            child: DropdownButtonFormField<String?>(
              initialValue: entry.proficiency,
              isDense: true,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                isDense: true,
                contentPadding: EdgeInsets.symmetric(
                    horizontal: 8, vertical: 12),
              ),
              hint: Text('Proficiency',
                  style: GoogleFonts.dmSans(fontSize: 12, color: _inkGhost)),
              style: GoogleFonts.dmSans(fontSize: 13, color: _ink),
              items: const [
                DropdownMenuItem(value: 'Native',         child: Text('Native')),
                DropdownMenuItem(value: 'Fluent',         child: Text('Fluent')),
                DropdownMenuItem(value: 'Conversational', child: Text('Conversational')),
                DropdownMenuItem(value: 'Passive',        child: Text('Passive')),
              ],
              onChanged: (v) {
                setState(() => entry.proficiency = v);
                _saveCaseHistory();
              },
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 70,
            child: Focus(
              onFocusChange: (f) {
                if (!f) _saveCaseHistory();
              },
              child: TextField(
                controller: entry.acquisitionAgeCtrl,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                ],
                style: GoogleFonts.dmSans(fontSize: 13, color: _ink),
                decoration: InputDecoration(
                  hintText: 'Age',
                  hintStyle: GoogleFonts.dmSans(
                      fontSize: 12, color: _inkGhost.withValues(alpha: 0.6)),
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ),
          ),
          if (_languages.length > 1)
            IconButton(
              onPressed: () {
                final removed = _languages.removeAt(index);
                removed.dispose();
                setState(() {});
                _saveCaseHistory();
              },
              icon: const Icon(Icons.close_rounded,
                  size: 16, color: _inkGhost),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(
                  minWidth: 28, minHeight: 28),
            ),
        ],
      ),
    );
  }

  Widget _errorBox(String msg) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: _coral.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(msg,
            style: GoogleFonts.dmSans(fontSize: 12, color: _ink)),
      );
}

/// Mirror of ALD's per-language row builder. Kept file-private here
/// rather than extracted to a shared file so each capture surface
/// owns its own list-builder plumbing — extracting to lib/widgets/
/// shared/ would be a follow-up cleanup pass once a third surface
/// needs it.
class _LanguageEntry {
  final TextEditingController nameCtrl;
  final TextEditingController acquisitionAgeCtrl;
  String? proficiency;

  _LanguageEntry({
    String name           = '',
    String acquisitionAge = '',
    this.proficiency,
  })  : nameCtrl           = TextEditingController(text: name),
        acquisitionAgeCtrl = TextEditingController(text: acquisitionAge);

  void dispose() {
    nameCtrl.dispose();
    acquisitionAgeCtrl.dispose();
  }
}
