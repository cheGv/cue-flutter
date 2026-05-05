// lib/widgets/assessment/ald_capture_section.dart
//
// Phase 4.0.7.25a — Adult Language & Cognitive (ALD) capture surface.
// Sections 1 (Detailed Case History — multilingual focus), 2 (Bedside
// Screening), 3 (WAB-R + MoCA + MMSE typed battery with auto AQ/CQ),
// 11 (Outcome Tracking) populated. Sections 4, 5, 6, 7, 8, 9, 10, 12,
// 15 are amber-tinted stubs queued for 4.0.7.25b/c. Sections 13 / 14
// are deliberately skipped (red flags upstream of SLP, imaging from
// neuro) — visible numeric gap in the render order is intentional.
//
// Save model parallels voice_capture_section.dart:
//   - Sections 1, 2 PATCH a jsonb column on ald_assessments.
//   - Section 3 upserts into the typed child tables (ald_wab_scores,
//     ald_cognitive_screens) keyed by ald_assessment_id.
// Each editable surface debounces on focus blur and writes its full
// payload (no field-level deltas).
//
// Design register matches voice — paper background, white cards,
// teal/amber accents, lowercase tracked eyebrows. Local color tokens
// for now; a global token sweep is a future polish session.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../models/ald_assessment.dart';
import '../../services/ald_assessment_service.dart';

const Color _ink       = Color(0xFF0E1C36);
const Color _inkGhost  = Color(0xFF6B7690);
const Color _line      = Color(0xFFE6DDCA);
const Color _teal      = Color(0xFF2A8F84);
const Color _tealSoft  = Color(0xFFD6E8E5);
const Color _amber     = Color(0xFFD68A2B);
const Color _amberSoft = Color(0xFFF4E4C4);
const Color _coral     = Color(0xFFC25450);
const Color _green     = Color(0xFF1F8870);

class AldCaptureSection extends StatefulWidget {
  final String  clientId;
  final String? visitId;
  const AldCaptureSection({
    super.key,
    required this.clientId,
    this.visitId,
  });

  @override
  State<AldCaptureSection> createState() => _AldCaptureSectionState();
}

class _AldCaptureSectionState extends State<AldCaptureSection> {
  final _service = AldAssessmentService.instance;

  AldAssessment? _assessment;
  bool _loading = true;
  String? _error;
  OutcomeComparison? _outcome;

  // ── Section 1 — Detailed Case History ─────────────────────────────
  // Demographic + linguistic
  final _ageAtAssessmentCtrl = TextEditingController();
  String? _handedness;
  final _educationYearsCtrl  = TextEditingController();
  final _occupationCtrl      = TextEditingController();
  String? _premorbidLiteracy;
  // Languages spoken — dynamic list. Each entry is (name, proficiency,
  // ageOfAcquisition). Default 1 empty row.
  final List<_LanguageEntry> _languages = [_LanguageEntry()];
  String? _dominantLanguage;
  final _codeSwitchingCtrl   = TextEditingController();
  final _premorbidVoiceHistCtrl = TextEditingController();

  // Medical / neurological onset
  DateTime? _onsetDate;
  String? _etiology;
  String? _acuityStage;
  // Time post-onset auto-derived from onset date.
  final Set<String> _lesionLocations = {};
  final _lesionNotesCtrl     = TextEditingController();
  bool _imagingAvailable     = false;
  DateTime? _imagingDate;
  String? _imagingModality;
  final _hospitalizationCtrl = TextEditingController();
  final _gcsCtrl             = TextEditingController();

  // Comorbidities
  final Set<String> _comorbidities = {};
  final _otherComorbidCtrl   = TextEditingController();
  final _medicationsCtrl     = TextEditingController();

  // Functional status
  String? _ambulation;
  bool _rightHemiparesis     = false;
  bool _visualFieldDeficit   = false;
  final _visualFieldSpecCtrl = TextEditingController();
  String? _hearingStatus;
  bool _audiologyDone        = false;
  final _audiologyResultsCtrl = TextEditingController();
  bool _externalCogScreening = false;
  final _externalCogScoresCtrl = TextEditingController();
  bool _swallowingConcerns   = false;

  // Communication profile
  final _premorbidCommStyleCtrl = TextEditingController();
  final Set<String> _currentChannels = {};
  String? _familyAwareness;
  String? _caregiverInvolvement;

  // ── Section 2 — Bedside Screening ─────────────────────────────────
  String? _consciousness;
  bool _orientPerson = false;
  bool _orientPlace  = false;
  bool _orientTime   = false;
  final _orientNotesCtrl = TextEditingController();
  final _digitFwdCtrl    = TextEditingController();
  final _digitBwdCtrl    = TextEditingController();
  final _sustainedAttentionCtrl = TextEditingController();
  // Yes/No accuracy: 10 toggle items.
  final List<bool> _yesNoAccuracy = List.filled(10, false);
  // Object naming: 5 items each tri-state (correct / paraphasia /
  // no_response). Stored as 'correct' | 'paraphasia' | 'no_response' | null.
  final List<String?> _objectNaming = List.filled(5, null);
  final _objectNamingNotesCtrl = TextEditingController();
  bool _cmd1StepPass   = false;
  final _cmd1CorrectCtrl = TextEditingController();
  bool _cmd2StepPass   = false;
  final _cmd2CorrectCtrl = TextEditingController();
  bool _cmd3StepPass   = false;
  final _cmd3CorrectCtrl = TextEditingController();
  String? _intelligibility;
  bool _readSingleWord = false;
  bool _readSentence   = false;
  bool _readCompSingle = false;
  bool _writeOwnName   = false;
  bool _writeCopySent  = false;
  bool _writeDictation = false;
  final _bedsideImpressionCtrl = TextEditingController();

  // ── Section 3A — WAB-R typed scores ───────────────────────────────
  String? _wabBatteryVersion;
  final _wabLanguageCtrl = TextEditingController();
  int _ssInfo            = 0; // 0-10
  int _ssFluency         = 0; // 0-10
  final _avcYesNoCtrl    = TextEditingController(); // 0-60
  final _avcWordRecCtrl  = TextEditingController(); // 0-60
  final _avcSeqCtrl      = TextEditingController(); // 0-80
  final _repCtrl         = TextEditingController(); // 0-100
  final _namingObjCtrl   = TextEditingController(); // 0-60
  final _namingFlCtrl    = TextEditingController(); // 0-20
  final _namingSentCtrl  = TextEditingController(); // 0-10
  final _namingRespCtrl  = TextEditingController(); // 0-10
  final _readingCtrl     = TextEditingController();
  final _writingCtrl     = TextEditingController();
  String? _aphasiaTypeOverride;
  final _wabNotesCtrl    = TextEditingController();

  // ── Section 3B — MoCA ─────────────────────────────────────────────
  final _mocaLangCtrl = TextEditingController();
  final _mocaVisuoCtrl = TextEditingController();   // 0-5
  final _mocaNamingCtrl = TextEditingController();  // 0-3
  final _mocaMemoryCtrl = TextEditingController();  // 0-5
  final _mocaAttentionCtrl = TextEditingController(); // 0-6
  final _mocaLanguageCtrl  = TextEditingController(); // 0-3
  final _mocaAbstractCtrl  = TextEditingController(); // 0-2
  final _mocaOrientCtrl    = TextEditingController(); // 0-6
  bool _mocaEducationAdj   = false;

  // ── Section 3C — MMSE ─────────────────────────────────────────────
  final _mmseLangCtrl       = TextEditingController();
  final _mmseOrientCtrl     = TextEditingController(); // 0-10
  final _mmseRegistrationCtrl = TextEditingController(); // 0-3
  final _mmseAttentionCtrl  = TextEditingController(); // 0-5
  final _mmseRecallCtrl     = TextEditingController(); // 0-3
  final _mmseLanguageCtrl   = TextEditingController(); // 0-9

  // ── Section 4 — Naming & Word Retrieval (typed) ──────────────────
  // Saves to ald_naming_measures keyed by ald_assessment_id (UNIQUE).
  // Schema column names match the 25a migration spec
  // (bnt_raw_score / fluency_semantic_animals / fluency_phonemic_f|a|s,
  // not the abbreviated forms used in pre-25b drafts).
  final _bntRawCtrl       = TextEditingController(); // 0-60
  final _bntZCtrl         = TextEditingController(); // ± float
  bool  _bntAgeAdjusted   = false;
  final _antRawCtrl       = TextEditingController();
  final _flAnimalsCtrl    = TextEditingController();
  final _flFCtrl          = TextEditingController();
  final _flACtrl          = TextEditingController();
  final _flSCtrl          = TextEditingController();
  final Set<String> _namingErrors = {};
  bool  _semCueHelps      = false;
  bool  _phonCueHelps     = false;
  bool  _choiceCueHelps   = false;
  final _namingNotesCtrl  = TextEditingController();

  // ── Section 5 — Auditory Comprehension (jsonb) ───────────────────
  String? _tokenVersion;
  final _tokenRawCtrl     = TextEditingController();
  final _tokenStdCtrl     = TextEditingController();
  final _yesNoCorrectCtrl = TextEditingController(); // 0-20
  final _cmd1PctCtrl      = TextEditingController(); // 0-100
  final _cmd2PctCtrl      = TextEditingController();
  final _cmd3PctCtrl      = TextEditingController();
  final _cmd4PctCtrl      = TextEditingController();
  final _sentSimpleCtrl   = TextEditingController(); // 0-100
  final _sentSubjRelCtrl  = TextEditingController();
  final _sentObjRelCtrl   = TextEditingController();
  final _sentPassiveCtrl  = TextEditingController();
  final _storyUsedCtrl    = TextEditingController();
  final _storyPropsCtrl   = TextEditingController(); // "X / Y"
  bool  _storyMainIdea    = false;
  String? _inferentialComp;
  final _compNotesCtrl    = TextEditingController();

  // ── Section 6 — Reading & Writing (jsonb) ────────────────────────
  final _readRegCtrl      = TextEditingController(); // "X/Y"
  final _readIrregCtrl    = TextEditingController();
  final _readNonwordsCtrl = TextEditingController();
  String? _sentReadingFluency;
  String? _paragraphReading;
  final _readWordPicCtrl  = TextEditingController();
  final _readSentPicCtrl  = TextEditingController();
  String? _paragraphComp;
  String? _readingRate;
  String? _writeOwnNameQuality;
  String? _copyWordsQuality;
  final _writeDictWordsCtrl    = TextEditingController();
  String? _writeDictSentence;
  final _spontaneousWritingCtrl = TextEditingController();
  final Set<String> _writingErrors = {};
  final _rwImpressionCtrl  = TextEditingController();

  // ── Section 7 — Discourse & Functional Communication (jsonb) ─────
  String? _pictureUsed;
  final _pictureDescVerbatimCtrl = TextEditingController();
  final _totalWordsCtrl    = TextEditingController();
  final _contentUnitsCtrl  = TextEditingController();
  final _mluCtrl           = TextEditingController();
  final _errorsPerMinCtrl  = TextEditingController();
  final _convoTopicCtrl    = TextEditingController();
  final _convoDurationCtrl = TextEditingController();
  String? _topicMaintenance;
  String? _turnTaking;
  String? _initiation;
  final Set<String> _repairStrategies = {};
  final Set<String> _channelsUsed     = {};
  String? _mostEffectiveChannel;
  final _funcCommImpressionCtrl = TextEditingController();

  // ── Section 8 — Etiology-Specific Subforms ────────────────────────
  // Multi-select chip set. Each subform persists to its own jsonb
  // column on ald_assessments regardless of whether its chip is
  // currently selected — toggling chips never drops sibling data.
  // Default selection seeds from etiology_category + WAB classification
  // on first hydrate (see _seedSubformDefaults).
  final Set<String> _subformsSelected = {};

  // 8A — Aphasia + Apraxia
  final _aaLesionCorrelationCtrl = TextEditingController();
  bool _aosSuspected         = false;
  bool _aosArticulatoryGroping = false;
  bool _aosInconsistentErrors  = false;
  bool _aosSlowRate            = false;
  bool _aosDistortedSubst      = false;
  bool _aosTrialAndError       = false;
  bool _aosAwarenessOfErrors   = false;
  final _aosDdkObsCtrl       = TextEditingController();
  String? _aosSeverity;
  bool _dysarthriaScreen     = false;
  final Set<String> _aaComorbidFeatures = {};
  final _aaNotesCtrl         = TextEditingController();

  // 8B — TBI
  final _tbiGcsAdmitCtrl     = TextEditingController();
  final _tbiCurrentLevelCtrl = TextEditingController();
  final _tbiGoatCtrl         = TextEditingController();
  String? _tbiRanchosLevel;
  final Set<String> _tbiCogConcerns      = {};
  final Set<String> _tbiBehavioralConcerns = {};
  final _tbiFimCommCtrl      = TextEditingController();
  final _tbiNotesCtrl        = TextEditingController();

  // 8C — RHD
  final _rhdMirbiCtrl        = TextEditingController();
  final Set<String> _rhdPragmaticDeficits = {};
  bool _rhdNeglect           = false;
  bool _rhdAnosognosia       = false;
  String? _rhdAffectiveComm;
  String? _rhdDiscourseProfile;
  final _rhdNotesCtrl        = TextEditingController();

  // 8D — Dementia / MCI
  String? _dementiaSubtype;
  final Set<String> _dementiaMemoryProfile = {};
  final _dementiaLanguagePatternCtrl = TextEditingController();
  final _dementiaDifferentialCtrl    = TextEditingController();
  final _dementiaTimelineCtrl        = TextEditingController();
  final _dementiaNotesCtrl           = TextEditingController();

  // 8E — PPA
  String? _ppaSubtype;
  final _ppaTimelineCtrl     = TextEditingController();
  final Set<String> _ppaSemanticFeatures = {};
  final Set<String> _ppaNonfluentFeatures = {};
  final Set<String> _ppaLogopenicFeatures = {};
  final _ppaDifferentialCtrl = TextEditingController();
  final _ppaNotesCtrl        = TextEditingController();

  // 8F — Multilingual crossover (per-language rows + crosscutting)
  final List<_LangTestEntry> _langTests = [_LangTestEntry()];
  final Set<String> _crossLinguisticProfile = {};
  String? _mostPreservedLanguage;
  String? _codeSwitchingPostInjury;
  final _culturalAssessNotesCtrl  = TextEditingController();
  String? _multilingualTxLanguage;
  final _multilingualNotesCtrl    = TextEditingController();

  // ── Section 9 — Cognitive-Communication Screen ──────────────────
  String? _attnSustained;
  String? _attnSelective;
  String? _attnDivided;
  final _attnNotesCtrl       = TextEditingController();
  String? _memImmediate;
  String? _memRecent;
  String? _memRemote;
  String? _memWorking;
  final Set<String> _memToolsUsed = {};
  String? _execPlanning;
  String? _execProblemSolving;
  String? _execFlexibility;
  String? _execInhibition;
  String? _execInitiation;
  final _execNotesCtrl       = TextEditingController();
  String? _reasoningAbstract;
  String? _reasoningCategorization;
  String? _reasoningSequencing;
  String? _pragInsight;
  String? _pragSocialUse;
  String? _pragAwarenessPartner;
  final Set<String> _cogScreenToolsUsed = {};

  // ── Section 10 — Differential Diagnosis ─────────────────────────
  final _ddPrimaryDxCtrl     = TextEditingController();
  bool _ddOverrideEtiology   = false;
  String? _ddEtiologyOverride;
  final List<TextEditingController> _ddRuleOutCtrls = [
    TextEditingController(),
    TextEditingController(),
    TextEditingController(),
  ];
  final Set<String> _ddContributingFactors = {};
  final _ddOtherContribCtrl  = TextEditingController();
  final _ddSynthesisCtrl     = TextEditingController();

  // ── Section 12 — QoL typed totals ───────────────────────────────
  // Item-level state in widget memory; only totals persist.
  final Map<int, int> _coastItems = {};   // 1..20 → 1..5
  bool _useAiq21 = false;
  final Map<int, int> _aiq21Items = {};   // 1..21 → 1..5
  bool _useSaqol = false;
  final Map<int, int> _saqolItems = {};   // 1..39 → 1..5
  bool _useCeti = false;
  final Map<int, int> _cetiItems = {};    // 1..16 → 0..100
  // Loaded totals for the "Last saved total" hint.
  int? _coastTotalLoaded;
  int? _aiq21TotalLoaded;
  int? _saqolTotalLoaded;
  int? _cetiTotalLoaded;

  // ── Section 15 — Final Clinical Impression & Plan ───────────────
  final _ciFinalDxCtrl       = TextEditingController();
  final _ciIcdCodeCtrl       = TextEditingController();
  String? _ciSeverity;
  final _ciSeverityRationaleCtrl = TextEditingController();
  String? _ciPrognosis;
  final _ciPrognosticRationaleCtrl = TextEditingController();
  final Set<String> _ciInterventions = {};
  final _ciTherapyApproachCtrl   = TextEditingController();
  final _ciSessionCountCtrl  = TextEditingController();
  String? _ciFrequency;
  final _ciSessionDurationCtrl = TextEditingController();
  final _ciDischargeCriteriaCtrl = TextEditingController();
  final Set<String> _ciReferrals = {};
  final _ciReferralNotesCtrl = TextEditingController();
  final Set<String> _ciCaregiverEdu = {};
  final _ciFunctionalOutcomesCtrl = TextEditingController();

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
      _ageAtAssessmentCtrl, _educationYearsCtrl, _occupationCtrl,
      _codeSwitchingCtrl, _premorbidVoiceHistCtrl,
      _lesionNotesCtrl, _hospitalizationCtrl, _gcsCtrl,
      _otherComorbidCtrl, _medicationsCtrl,
      _visualFieldSpecCtrl, _audiologyResultsCtrl,
      _externalCogScoresCtrl,
      _premorbidCommStyleCtrl,
      _orientNotesCtrl, _digitFwdCtrl, _digitBwdCtrl,
      _sustainedAttentionCtrl, _objectNamingNotesCtrl,
      _cmd1CorrectCtrl, _cmd2CorrectCtrl, _cmd3CorrectCtrl,
      _bedsideImpressionCtrl,
      _wabLanguageCtrl,
      _avcYesNoCtrl, _avcWordRecCtrl, _avcSeqCtrl,
      _repCtrl, _namingObjCtrl, _namingFlCtrl, _namingSentCtrl,
      _namingRespCtrl, _readingCtrl, _writingCtrl, _wabNotesCtrl,
      _mocaLangCtrl, _mocaVisuoCtrl, _mocaNamingCtrl, _mocaMemoryCtrl,
      _mocaAttentionCtrl, _mocaLanguageCtrl, _mocaAbstractCtrl,
      _mocaOrientCtrl,
      _mmseLangCtrl, _mmseOrientCtrl, _mmseRegistrationCtrl,
      _mmseAttentionCtrl, _mmseRecallCtrl, _mmseLanguageCtrl,
      // 25b — Sections 4, 5, 6, 7 controllers
      _bntRawCtrl, _bntZCtrl, _antRawCtrl,
      _flAnimalsCtrl, _flFCtrl, _flACtrl, _flSCtrl,
      _namingNotesCtrl,
      _tokenRawCtrl, _tokenStdCtrl, _yesNoCorrectCtrl,
      _cmd1PctCtrl, _cmd2PctCtrl, _cmd3PctCtrl, _cmd4PctCtrl,
      _sentSimpleCtrl, _sentSubjRelCtrl, _sentObjRelCtrl, _sentPassiveCtrl,
      _storyUsedCtrl, _storyPropsCtrl, _compNotesCtrl,
      _readRegCtrl, _readIrregCtrl, _readNonwordsCtrl,
      _readWordPicCtrl, _readSentPicCtrl,
      _writeDictWordsCtrl, _spontaneousWritingCtrl, _rwImpressionCtrl,
      _pictureDescVerbatimCtrl, _totalWordsCtrl, _contentUnitsCtrl,
      _mluCtrl, _errorsPerMinCtrl,
      _convoTopicCtrl, _convoDurationCtrl, _funcCommImpressionCtrl,
      // 25c — Sections 8, 9, 10, 15 controllers (Section 12 stores
      // ints only, no controllers).
      _aaLesionCorrelationCtrl, _aosDdkObsCtrl, _aaNotesCtrl,
      _tbiGcsAdmitCtrl, _tbiCurrentLevelCtrl, _tbiGoatCtrl,
      _tbiFimCommCtrl, _tbiNotesCtrl,
      _rhdMirbiCtrl, _rhdNotesCtrl,
      _dementiaLanguagePatternCtrl, _dementiaDifferentialCtrl,
      _dementiaTimelineCtrl, _dementiaNotesCtrl,
      _ppaTimelineCtrl, _ppaDifferentialCtrl, _ppaNotesCtrl,
      _culturalAssessNotesCtrl, _multilingualNotesCtrl,
      _attnNotesCtrl, _execNotesCtrl,
      _ddPrimaryDxCtrl, _ddOtherContribCtrl, _ddSynthesisCtrl,
      ..._ddRuleOutCtrls,
      _ciFinalDxCtrl, _ciIcdCodeCtrl, _ciSeverityRationaleCtrl,
      _ciPrognosticRationaleCtrl, _ciTherapyApproachCtrl,
      _ciSessionCountCtrl, _ciSessionDurationCtrl,
      _ciDischargeCriteriaCtrl, _ciReferralNotesCtrl,
      _ciFunctionalOutcomesCtrl,
    ];
    for (final c in controllers) {
      c.dispose();
    }
    for (final lang in _languages) {
      lang.nameCtrl.dispose();
      lang.acquisitionAgeCtrl.dispose();
    }
    for (final lt in _langTests) {
      lt.dispose();
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
            assessmentId: a.id, tableName: 'ald_wab_scores'),
        _service.loadTypedMeasures(
            assessmentId: a.id, tableName: 'ald_cognitive_screens'),
        // 25b — Section 4 (Naming) loads from ald_naming_measures.
        _service.loadTypedMeasures(
            assessmentId: a.id, tableName: 'ald_naming_measures'),
        // 25c — Section 12 (QoL) loads from ald_qol_scores.
        _service.loadTypedMeasures(
            assessmentId: a.id, tableName: 'ald_qol_scores'),
        _service.compareBaselineToLatest(widget.clientId),
      ]);
      _hydrateWab(results[0] as Map<String, dynamic>);
      _hydrateCognitive(results[1] as Map<String, dynamic>);
      _hydrateNaming(results[2] as Map<String, dynamic>);
      _hydrateQol(results[3] as Map<String, dynamic>);
      _seedSubformDefaults(a);
      if (!mounted) return;
      setState(() {
        _assessment = a;
        _outcome    = results[4] as OutcomeComparison;
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

  void _hydrateFromAssessment(AldAssessment a) {
    final ch = a.caseHistoryPayload;
    _ageAtAssessmentCtrl.text = ch['age_at_assessment']?.toString() ?? '';
    _handedness               = ch['handedness'] as String?;
    _educationYearsCtrl.text  = ch['education_years']?.toString() ?? '';
    _occupationCtrl.text      = (ch['premorbid_occupation'] as String?) ?? '';
    _premorbidLiteracy        = ch['premorbid_literacy'] as String?;
    final langList = ch['languages_spoken'];
    if (langList is List && langList.isNotEmpty) {
      for (final e in _languages) {
        e.nameCtrl.dispose();
        e.acquisitionAgeCtrl.dispose();
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
    _codeSwitchingCtrl.text   = (ch['code_switching_pre_injury'] as String?) ?? '';
    _premorbidVoiceHistCtrl.text =
        (ch['premorbid_voice_speech_history'] as String?) ?? '';

    final onsetStr = ch['onset_date'] as String?;
    if (onsetStr != null && onsetStr.isNotEmpty) {
      _onsetDate = DateTime.tryParse(onsetStr);
    }
    _etiology                = ch['etiology'] as String? ?? a.etiologyCategory;
    _acuityStage             = ch['acuity_stage'] as String? ?? a.acuityStage;
    final lesions = ch['lesion_location'] ?? a.lesionLocation;
    if (lesions is List) {
      _lesionLocations
        ..clear()
        ..addAll(lesions.map((e) => e.toString()));
    }
    _lesionNotesCtrl.text    = (ch['lesion_location_notes'] as String?) ?? '';
    _imagingAvailable        = ch['imaging_available'] == true;
    final imgDateStr = ch['imaging_date'] as String?;
    if (imgDateStr != null && imgDateStr.isNotEmpty) {
      _imagingDate = DateTime.tryParse(imgDateStr);
    }
    _imagingModality         = ch['imaging_modality'] as String?;
    _hospitalizationCtrl.text = (ch['hospitalization_details'] as String?) ?? '';
    _gcsCtrl.text            = ch['gcs_at_presentation']?.toString() ?? '';

    final cmb = ch['comorbidities'];
    if (cmb is List) {
      _comorbidities
        ..clear()
        ..addAll(cmb.map((e) => e.toString()));
    }
    _otherComorbidCtrl.text  = (ch['other_comorbidities'] as String?) ?? '';
    _medicationsCtrl.text    = (ch['current_medications'] as String?) ?? '';

    _ambulation              = ch['ambulation'] as String?;
    _rightHemiparesis        = ch['right_hemiparesis'] == true;
    _visualFieldDeficit      = ch['visual_field_deficit'] == true;
    _visualFieldSpecCtrl.text = (ch['visual_field_specify'] as String?) ?? '';
    _hearingStatus           = ch['hearing_status'] as String?;
    _audiologyDone           = ch['audiology_done'] == true;
    _audiologyResultsCtrl.text = (ch['audiology_results'] as String?) ?? '';
    _externalCogScreening    = ch['external_cog_screening_done'] == true;
    _externalCogScoresCtrl.text = (ch['external_cog_scores'] as String?) ?? '';
    _swallowingConcerns      = ch['swallowing_concerns'] == true;

    _premorbidCommStyleCtrl.text =
        (ch['premorbid_comm_style'] as String?) ?? '';
    final ch2 = ch['current_channels'];
    if (ch2 is List) {
      _currentChannels
        ..clear()
        ..addAll(ch2.map((e) => e.toString()));
    }
    _familyAwareness         = ch['family_awareness'] as String?;
    _caregiverInvolvement    = ch['caregiver_involvement'] as String?;

    final bs = a.bedsideScreenPayload;
    _consciousness        = bs['consciousness'] as String?;
    final orient = (bs['orientation'] is Map)
        ? Map<String, dynamic>.from(bs['orientation'] as Map)
        : const <String, dynamic>{};
    _orientPerson         = orient['person'] == true;
    _orientPlace          = orient['place']  == true;
    _orientTime           = orient['time']   == true;
    _orientNotesCtrl.text = (orient['notes'] as String?) ?? '';
    _digitFwdCtrl.text    = bs['digit_span_forward']?.toString() ?? '';
    _digitBwdCtrl.text    = bs['digit_span_backward']?.toString() ?? '';
    _sustainedAttentionCtrl.text =
        (bs['sustained_attention'] as String?) ?? '';
    final yna = bs['yes_no_accuracy'];
    if (yna is List) {
      for (var i = 0; i < _yesNoAccuracy.length && i < yna.length; i++) {
        _yesNoAccuracy[i] = yna[i] == true;
      }
    }
    final on = bs['object_naming'];
    if (on is List) {
      for (var i = 0; i < _objectNaming.length && i < on.length; i++) {
        final v = on[i];
        _objectNaming[i] = v is String ? v : null;
      }
    }
    _objectNamingNotesCtrl.text =
        (bs['object_naming_notes'] as String?) ?? '';
    _cmd1StepPass = bs['cmd_1step_pass'] == true;
    _cmd1CorrectCtrl.text = bs['cmd_1step_correct']?.toString() ?? '';
    _cmd2StepPass = bs['cmd_2step_pass'] == true;
    _cmd2CorrectCtrl.text = bs['cmd_2step_correct']?.toString() ?? '';
    _cmd3StepPass = bs['cmd_3step_pass'] == true;
    _cmd3CorrectCtrl.text = bs['cmd_3step_correct']?.toString() ?? '';
    _intelligibility = bs['intelligibility'] as String?;
    _readSingleWord  = bs['read_single_word'] == true;
    _readSentence    = bs['read_sentence']    == true;
    _readCompSingle  = bs['read_comp_single'] == true;
    _writeOwnName    = bs['write_own_name']   == true;
    _writeCopySent   = bs['write_copy_sentence'] == true;
    _writeDictation  = bs['write_dictation']  == true;
    _bedsideImpressionCtrl.text =
        (bs['bedside_impression'] as String?) ?? '';

    // 25b — Section 5 (auditory comprehension) seeds from its jsonb.
    final cmp = a.auditoryComprehensionPayload;
    _tokenVersion           = cmp['token_test_version']        as String?;
    _tokenRawCtrl.text      = cmp['token_test_raw']?.toString() ?? '';
    _tokenStdCtrl.text      = cmp['token_test_standardized']?.toString() ?? '';
    _yesNoCorrectCtrl.text  = cmp['yes_no_correct']?.toString() ?? '';
    _cmd1PctCtrl.text       = cmp['cmd_1step_pct']?.toString() ?? '';
    _cmd2PctCtrl.text       = cmp['cmd_2step_pct']?.toString() ?? '';
    _cmd3PctCtrl.text       = cmp['cmd_3step_pct']?.toString() ?? '';
    _cmd4PctCtrl.text       = cmp['cmd_4step_pct']?.toString() ?? '';
    _sentSimpleCtrl.text    = cmp['sent_simple_pct']?.toString() ?? '';
    _sentSubjRelCtrl.text   = cmp['sent_subject_relative_pct']?.toString() ?? '';
    _sentObjRelCtrl.text    = cmp['sent_object_relative_pct']?.toString() ?? '';
    _sentPassiveCtrl.text   = cmp['sent_passive_pct']?.toString() ?? '';
    _storyUsedCtrl.text     = (cmp['story_used']            as String?) ?? '';
    _storyPropsCtrl.text    = (cmp['story_propositions']    as String?) ?? '';
    _storyMainIdea          = cmp['story_main_idea_grasped'] == true;
    _inferentialComp        = cmp['inferential_comprehension'] as String?;
    _compNotesCtrl.text     = (cmp['comprehension_breakdown_notes'] as String?) ?? '';

    // 25b — Section 6 (reading & writing) seeds from its jsonb.
    final rw = a.readingWritingPayload;
    _readRegCtrl.text         = (rw['read_regular_words']    as String?) ?? '';
    _readIrregCtrl.text       = (rw['read_irregular_words']  as String?) ?? '';
    _readNonwordsCtrl.text    = (rw['read_nonwords']         as String?) ?? '';
    _sentReadingFluency       = rw['sentence_reading_fluency'] as String?;
    _paragraphReading         = rw['paragraph_reading']        as String?;
    _readWordPicCtrl.text     = (rw['read_word_picture_match']     as String?) ?? '';
    _readSentPicCtrl.text     = (rw['read_sentence_picture_match'] as String?) ?? '';
    _paragraphComp            = rw['paragraph_comprehension'] as String?;
    _readingRate              = rw['reading_rate']            as String?;
    _writeOwnNameQuality      = rw['write_own_name_quality'] as String?;
    _copyWordsQuality         = rw['copy_words_quality']     as String?;
    _writeDictWordsCtrl.text  = (rw['write_dictation_words']    as String?) ?? '';
    _writeDictSentence        = rw['write_dictation_sentence'] as String?;
    _spontaneousWritingCtrl.text =
        (rw['spontaneous_writing_sample'] as String?) ?? '';
    final werr = rw['writing_errors'];
    if (werr is List) {
      _writingErrors
        ..clear()
        ..addAll(werr.map((e) => e.toString()));
    }
    _rwImpressionCtrl.text    = (rw['rw_impression'] as String?) ?? '';

    // 25b — Section 7 (discourse & functional comm) seeds from its jsonb.
    final dc = a.discoursePayload;
    _pictureUsed              = dc['picture_used'] as String?;
    _pictureDescVerbatimCtrl.text =
        (dc['picture_description_verbatim'] as String?) ?? '';
    _totalWordsCtrl.text      = dc['total_words']?.toString() ?? '';
    _contentUnitsCtrl.text    = dc['content_units']?.toString() ?? '';
    _mluCtrl.text             = dc['mlu']?.toString() ?? '';
    _errorsPerMinCtrl.text    = dc['errors_per_minute']?.toString() ?? '';
    _convoTopicCtrl.text      = (dc['conversation_topic'] as String?) ?? '';
    _convoDurationCtrl.text   = dc['conversation_duration_min']?.toString() ?? '';
    _topicMaintenance         = dc['topic_maintenance'] as String?;
    _turnTaking               = dc['turn_taking']       as String?;
    _initiation               = dc['initiation']        as String?;
    final repair = dc['repair_strategies'];
    if (repair is List) {
      _repairStrategies
        ..clear()
        ..addAll(repair.map((e) => e.toString()));
    }
    final channels = dc['channels_used'];
    if (channels is List) {
      _channelsUsed
        ..clear()
        ..addAll(channels.map((e) => e.toString()));
    }
    _mostEffectiveChannel     = dc['most_effective_channel'] as String?;
    _funcCommImpressionCtrl.text =
        (dc['functional_comm_impression'] as String?) ?? '';

    // 25c — Section 8 etiology subforms each seed from their own jsonb.
    final subSel = a.etiologySpecificPayload['subforms_selected'];
    if (subSel is List) {
      _subformsSelected
        ..clear()
        ..addAll(subSel.map((e) => e.toString()));
    }

    final aa = a.aphasiaApraxiaPayload;
    _aaLesionCorrelationCtrl.text =
        (aa['lesion_symptom_correlation'] as String?) ?? '';
    _aosSuspected           = aa['aos_suspected'] == true;
    _aosArticulatoryGroping = aa['aos_articulatory_groping'] == true;
    _aosInconsistentErrors  = aa['aos_inconsistent_errors']  == true;
    _aosSlowRate            = aa['aos_slow_rate']            == true;
    _aosDistortedSubst      = aa['aos_distorted_substitutions'] == true;
    _aosTrialAndError       = aa['aos_trial_and_error']      == true;
    _aosAwarenessOfErrors   = aa['aos_awareness_of_errors']  == true;
    _aosDdkObsCtrl.text     = (aa['aos_ddk_observation'] as String?) ?? '';
    _aosSeverity            = aa['aos_severity'] as String?;
    _dysarthriaScreen       = aa['dysarthria_screen'] == true;
    final aaCom = aa['comorbid_features'];
    if (aaCom is List) {
      _aaComorbidFeatures
        ..clear()
        ..addAll(aaCom.map((e) => e.toString()));
    }
    _aaNotesCtrl.text       = (aa['notes'] as String?) ?? '';

    final tb = a.tbiPayload;
    _tbiGcsAdmitCtrl.text     = tb['gcs_at_admission']?.toString() ?? '';
    _tbiCurrentLevelCtrl.text = (tb['current_functional_level'] as String?) ?? '';
    _tbiGoatCtrl.text         = tb['goat_score']?.toString() ?? '';
    _tbiRanchosLevel          = tb['ranchos_level'] as String?;
    final tbCog = tb['cognitive_communication_concerns'];
    if (tbCog is List) {
      _tbiCogConcerns
        ..clear()
        ..addAll(tbCog.map((e) => e.toString()));
    }
    final tbBeh = tb['behavioral_concerns'];
    if (tbBeh is List) {
      _tbiBehavioralConcerns
        ..clear()
        ..addAll(tbBeh.map((e) => e.toString()));
    }
    _tbiFimCommCtrl.text  = tb['fim_communication_subscale']?.toString() ?? '';
    _tbiNotesCtrl.text    = (tb['notes'] as String?) ?? '';

    final rh = a.rhdPayload;
    _rhdMirbiCtrl.text   = rh['mirbi_total']?.toString() ?? '';
    final rhPrag = rh['pragmatic_deficits'];
    if (rhPrag is List) {
      _rhdPragmaticDeficits
        ..clear()
        ..addAll(rhPrag.map((e) => e.toString()));
    }
    _rhdNeglect          = rh['visuospatial_neglect'] == true;
    _rhdAnosognosia      = rh['anosognosia'] == true;
    _rhdAffectiveComm    = rh['affective_communication'] as String?;
    _rhdDiscourseProfile = rh['discourse_profile'] as String?;
    _rhdNotesCtrl.text   = (rh['notes'] as String?) ?? '';

    final dem = a.dementiaPayload;
    _dementiaSubtype = dem['subtype'] as String?;
    final demMem = dem['memory_profile'];
    if (demMem is List) {
      _dementiaMemoryProfile
        ..clear()
        ..addAll(demMem.map((e) => e.toString()));
    }
    _dementiaLanguagePatternCtrl.text = (dem['language_decline_pattern'] as String?) ?? '';
    _dementiaDifferentialCtrl.text    = (dem['differential_reasoning']    as String?) ?? '';
    _dementiaTimelineCtrl.text        = (dem['caregiver_timeline']        as String?) ?? '';
    _dementiaNotesCtrl.text           = (dem['notes']                     as String?) ?? '';

    final pp = a.ppaPayload;
    _ppaSubtype = pp['subtype'] as String?;
    _ppaTimelineCtrl.text = (pp['onset_progression_timeline'] as String?) ?? '';
    final ppSem = pp['semantic_features'];
    if (ppSem is List) {
      _ppaSemanticFeatures
        ..clear()
        ..addAll(ppSem.map((e) => e.toString()));
    }
    final ppNon = pp['nonfluent_features'];
    if (ppNon is List) {
      _ppaNonfluentFeatures
        ..clear()
        ..addAll(ppNon.map((e) => e.toString()));
    }
    final ppLog = pp['logopenic_features'];
    if (ppLog is List) {
      _ppaLogopenicFeatures
        ..clear()
        ..addAll(ppLog.map((e) => e.toString()));
    }
    _ppaDifferentialCtrl.text = (pp['differential_from_typical'] as String?) ?? '';
    _ppaNotesCtrl.text        = (pp['notes'] as String?) ?? '';

    final ml = a.multilingualPayload;
    final lts = ml['language_tests'];
    if (lts is List && lts.isNotEmpty) {
      for (final lt in _langTests) {
        lt.dispose();
      }
      _langTests
        ..clear()
        ..addAll(lts.whereType<Map>().map((m) {
          final mm = Map<String, dynamic>.from(m);
          return _LangTestEntry(
            language:        mm['language']        as String?,
            wabAq:           mm['wab_aq']?.toString() ?? '',
            convoFluency:    mm['conversational_fluency'] as String?,
            naming:          mm['naming']          as String?,
            comprehension:   mm['comprehension']   as String?,
            reading:         mm['reading']         as String?,
            writing:         mm['writing']         as String?,
          );
        }));
      if (_langTests.isEmpty) _langTests.add(_LangTestEntry());
    }
    final mlCl = ml['cross_linguistic_profile'];
    if (mlCl is List) {
      _crossLinguisticProfile
        ..clear()
        ..addAll(mlCl.map((e) => e.toString()));
    }
    _mostPreservedLanguage     = ml['most_preserved_language'] as String?;
    _codeSwitchingPostInjury   = ml['code_switching_post_injury'] as String?;
    _culturalAssessNotesCtrl.text = (ml['cultural_assessment_notes'] as String?) ?? '';
    _multilingualTxLanguage    = ml['treatment_language_recommendation'] as String?;
    _multilingualNotesCtrl.text = (ml['notes'] as String?) ?? '';

    // 25c — Section 9 (cog-comm screen) seeds from its jsonb.
    final cc = a.cognitiveCommScreenPayload;
    _attnSustained          = cc['attn_sustained']          as String?;
    _attnSelective          = cc['attn_selective']          as String?;
    _attnDivided            = cc['attn_divided']            as String?;
    _attnNotesCtrl.text     = (cc['attn_notes']             as String?) ?? '';
    _memImmediate           = cc['mem_immediate']           as String?;
    _memRecent              = cc['mem_recent']              as String?;
    _memRemote              = cc['mem_remote']              as String?;
    _memWorking             = cc['mem_working']             as String?;
    final mt = cc['mem_tools_used'];
    if (mt is List) {
      _memToolsUsed
        ..clear()
        ..addAll(mt.map((e) => e.toString()));
    }
    _execPlanning           = cc['exec_planning']           as String?;
    _execProblemSolving     = cc['exec_problem_solving']    as String?;
    _execFlexibility        = cc['exec_flexibility']        as String?;
    _execInhibition         = cc['exec_inhibition']         as String?;
    _execInitiation         = cc['exec_initiation']         as String?;
    _execNotesCtrl.text     = (cc['exec_notes']             as String?) ?? '';
    _reasoningAbstract      = cc['reasoning_abstract']      as String?;
    _reasoningCategorization = cc['reasoning_categorization'] as String?;
    _reasoningSequencing    = cc['reasoning_sequencing']    as String?;
    _pragInsight            = cc['prag_insight']            as String?;
    _pragSocialUse          = cc['prag_social_use']         as String?;
    _pragAwarenessPartner   = cc['prag_awareness_partner']  as String?;
    final ct = cc['cog_screen_tools'];
    if (ct is List) {
      _cogScreenToolsUsed
        ..clear()
        ..addAll(ct.map((e) => e.toString()));
    }

    // 25c — Section 10 (differential dx) seeds from its jsonb.
    final dd = a.differentialDiagnosisPayload;
    _ddPrimaryDxCtrl.text = (dd['primary_diagnosis'] as String?) ?? '';
    _ddOverrideEtiology   = dd['override_etiology'] == true;
    _ddEtiologyOverride   = dd['etiology_override'] as String?;
    final ros = dd['rule_outs'];
    if (ros is List && ros.isNotEmpty) {
      for (final c in _ddRuleOutCtrls) {
        c.dispose();
      }
      _ddRuleOutCtrls
        ..clear()
        ..addAll(ros.map((e) => TextEditingController(text: e?.toString() ?? '')));
      while (_ddRuleOutCtrls.length < 3) {
        _ddRuleOutCtrls.add(TextEditingController());
      }
    }
    final ddFactors = dd['contributing_factors'];
    if (ddFactors is List) {
      _ddContributingFactors
        ..clear()
        ..addAll(ddFactors.map((e) => e.toString()));
    }
    _ddOtherContribCtrl.text = (dd['other_contributing'] as String?) ?? '';
    _ddSynthesisCtrl.text    = (dd['differential_reasoning'] as String?) ?? '';

    // 25c — Section 15 (clinical impression) seeds from its jsonb.
    final ci = a.clinicalImpressionPayload;
    _ciFinalDxCtrl.text       = (ci['final_diagnosis'] as String?) ?? '';
    _ciIcdCodeCtrl.text       = (ci['icd_code']        as String?) ?? '';
    _ciSeverity               = ci['severity']         as String?;
    _ciSeverityRationaleCtrl.text = (ci['severity_rationale'] as String?) ?? '';
    _ciPrognosis              = ci['prognosis']        as String?;
    _ciPrognosticRationaleCtrl.text = (ci['prognostic_rationale'] as String?) ?? '';
    final ciInt = ci['recommended_interventions'];
    if (ciInt is List) {
      _ciInterventions
        ..clear()
        ..addAll(ciInt.map((e) => e.toString()));
    }
    _ciTherapyApproachCtrl.text = (ci['therapy_approach_details'] as String?) ?? '';
    _ciSessionCountCtrl.text  = ci['estimated_session_count']?.toString() ?? '';
    _ciFrequency              = ci['frequency']         as String?;
    _ciSessionDurationCtrl.text = ci['session_duration_min']?.toString() ?? '';
    _ciDischargeCriteriaCtrl.text = (ci['discharge_criteria'] as String?) ?? '';
    final ciRef = ci['referrals'];
    if (ciRef is List) {
      _ciReferrals
        ..clear()
        ..addAll(ciRef.map((e) => e.toString()));
    }
    _ciReferralNotesCtrl.text = (ci['referral_notes'] as String?) ?? '';
    final ciEdu = ci['caregiver_education'];
    if (ciEdu is List) {
      _ciCaregiverEdu
        ..clear()
        ..addAll(ciEdu.map((e) => e.toString()));
    }
    _ciFunctionalOutcomesCtrl.text =
        (ci['functional_outcome_targets'] as String?) ?? '';
  }

  /// Seeds the Section 8 chip selection on first hydrate from etiology
  /// + lesion location + WAB classification, so the SLP doesn't have
  /// to manually pick a subform that's obviously implied. SLP-driven
  /// changes after that point persist through `subforms_selected` in
  /// etiology_specific_payload.
  void _seedSubformDefaults(AldAssessment a) {
    if (_subformsSelected.isNotEmpty) return; // already saved a pick
    final etio = a.etiologyCategory ?? _etiology;
    final lesion = a.lesionLocation;
    if (etio != null) {
      if (etio.startsWith('Stroke')) {
        _subformsSelected.add('aphasia_apraxia');
      }
      if (etio.startsWith('TBI')) {
        _subformsSelected.add('tbi');
      }
      if (etio.startsWith('Dementia')) {
        _subformsSelected.add('dementia');
      }
      if (etio.startsWith('PPA')) {
        _subformsSelected.add('ppa');
      }
    }
    if (lesion.contains('R hemisphere')) {
      _subformsSelected.add('rhd');
    }
    if (_aphasiaTypeOverride != null && _aphasiaTypeOverride != 'Not aphasic') {
      _subformsSelected.add('aphasia_apraxia');
    }
    // Multilingual is always available — auto-add when ≥ 2 languages
    // were captured in Section 1 so the SLP doesn't miss the prompt.
    if (_languages.where((e) => e.nameCtrl.text.trim().isNotEmpty).length >= 2) {
      _subformsSelected.add('multilingual');
    }
  }

  /// Seeds Section 12 from a previously saved ald_qol_scores row.
  /// Per-item answers aren't persisted (only totals); per-item state
  /// resets on hard refresh, totals reload from the typed columns.
  void _hydrateQol(Map<String, dynamic> row) {
    if (row.isEmpty) return;
    final c = row['coast_total'];
    if (c is num) _coastTotalLoaded = c.toInt();
    final a = row['aiq21_total'];
    if (a is num) {
      _aiq21TotalLoaded = a.toInt();
      _useAiq21 = true;
    }
    final s = row['saqol39_total'];
    if (s is num) {
      _saqolTotalLoaded = s.toInt();
      _useSaqol = true;
    }
    final ce = row['ceti_total'];
    if (ce is num) {
      _cetiTotalLoaded = ce.toInt();
      _useCeti = true;
    }
  }

  void _hydrateNaming(Map<String, dynamic> row) {
    if (row.isEmpty) return;
    _bntRawCtrl.text     = row['bnt_raw_score']?.toString() ?? '';
    _bntZCtrl.text       = row['bnt_z_score']?.toString() ?? '';
    _bntAgeAdjusted      = row['bnt_age_adjusted'] == true;
    _antRawCtrl.text     = row['ant_raw_score']?.toString() ?? '';
    _flAnimalsCtrl.text  = row['fluency_semantic_animals']?.toString() ?? '';
    _flFCtrl.text        = row['fluency_phonemic_f']?.toString() ?? '';
    _flACtrl.text        = row['fluency_phonemic_a']?.toString() ?? '';
    _flSCtrl.text        = row['fluency_phonemic_s']?.toString() ?? '';
    final errs = row['error_profile'];
    if (errs is List) {
      _namingErrors
        ..clear()
        ..addAll(errs.map((e) => e.toString()));
    }
    _semCueHelps         = row['semantic_cue_helps'] == true;
    _phonCueHelps        = row['phonemic_cue_helps'] == true;
    _choiceCueHelps      = row['choice_cue_helps']   == true;
    _namingNotesCtrl.text = (row['notes'] as String?) ?? '';
  }

  void _hydrateWab(Map<String, dynamic> row) {
    if (row.isEmpty) return;
    _wabBatteryVersion       = row['battery_version'] as String?;
    _wabLanguageCtrl.text    = (row['language_administered'] as String?) ?? '';
    _ssInfo                  = (row['spontaneous_info']    as num?)?.toInt() ?? 0;
    _ssFluency               = (row['spontaneous_fluency'] as num?)?.toInt() ?? 0;
    _avcYesNoCtrl.text       = row['avc_yes_no']?.toString() ?? '';
    _avcWordRecCtrl.text     = row['avc_word_recognition']?.toString() ?? '';
    _avcSeqCtrl.text         = row['avc_sequential_commands']?.toString() ?? '';
    _repCtrl.text            = row['repetition_score']?.toString() ?? '';
    _namingObjCtrl.text      = row['naming_object']?.toString() ?? '';
    _namingFlCtrl.text       = row['naming_word_fluency']?.toString() ?? '';
    _namingSentCtrl.text     = row['naming_sentence_completion']?.toString() ?? '';
    _namingRespCtrl.text     = row['naming_responsive_speech']?.toString() ?? '';
    _readingCtrl.text        = row['reading_score']?.toString() ?? '';
    _writingCtrl.text        = row['writing_score']?.toString() ?? '';
    _aphasiaTypeOverride     = row['aphasia_type_classification'] as String?;
    _wabNotesCtrl.text       = (row['notes'] as String?) ?? '';
  }

  void _hydrateCognitive(Map<String, dynamic> row) {
    if (row.isEmpty) return;
    _mocaLangCtrl.text       = (row['moca_language_administered'] as String?) ?? '';
    _mocaVisuoCtrl.text      = row['moca_visuospatial_executive']?.toString() ?? '';
    _mocaNamingCtrl.text     = row['moca_naming']?.toString() ?? '';
    _mocaMemoryCtrl.text     = row['moca_memory_recall']?.toString() ?? '';
    _mocaAttentionCtrl.text  = row['moca_attention']?.toString() ?? '';
    _mocaLanguageCtrl.text   = row['moca_language']?.toString() ?? '';
    _mocaAbstractCtrl.text   = row['moca_abstraction']?.toString() ?? '';
    _mocaOrientCtrl.text     = row['moca_orientation']?.toString() ?? '';
    _mocaEducationAdj        = row['moca_education_adjustment'] == true;
    _mmseLangCtrl.text       = (row['mmse_language_administered'] as String?) ?? '';
    _mmseOrientCtrl.text     = row['mmse_orientation']?.toString() ?? '';
    _mmseRegistrationCtrl.text = row['mmse_registration']?.toString() ?? '';
    _mmseAttentionCtrl.text  = row['mmse_attention_calculation']?.toString() ?? '';
    _mmseRecallCtrl.text     = row['mmse_recall']?.toString() ?? '';
    _mmseLanguageCtrl.text   = row['mmse_language']?.toString() ?? '';
  }

  // ── Save dispatchers ────────────────────────────────────────────────

  Future<void> _saveCaseHistory() async {
    if (_assessment == null) return;
    final lesions = _lesionLocations.toList();
    final etiology = _etiology;
    final acuity   = _acuityStage;
    final timePostOnset = _timePostOnsetDays();
    final payload = <String, dynamic>{
      'age_at_assessment':           _parseInt(_ageAtAssessmentCtrl.text),
      'handedness':                  _handedness,
      'education_years':             _parseInt(_educationYearsCtrl.text),
      'premorbid_occupation':        _occupationCtrl.text.trim(),
      'premorbid_literacy':          _premorbidLiteracy,
      'languages_spoken':            _languages.map((e) => {
                                       'name':                e.nameCtrl.text.trim(),
                                       'proficiency':         e.proficiency,
                                       'age_of_acquisition':  _parseInt(e.acquisitionAgeCtrl.text),
                                     }).where((m) => (m['name'] as String).isNotEmpty).toList(),
      'dominant_language':           _dominantLanguage,
      'code_switching_pre_injury':   _codeSwitchingCtrl.text.trim(),
      'premorbid_voice_speech_history': _premorbidVoiceHistCtrl.text.trim(),
      'onset_date':                  _onsetDate?.toIso8601String().substring(0, 10),
      'etiology':                    etiology,
      'acuity_stage':                acuity,
      'time_post_onset_days':        timePostOnset,
      'lesion_location':             lesions,
      'lesion_location_notes':       _lesionNotesCtrl.text.trim(),
      'imaging_available':           _imagingAvailable,
      'imaging_date':                _imagingDate?.toIso8601String().substring(0, 10),
      'imaging_modality':            _imagingModality,
      'hospitalization_details':     _hospitalizationCtrl.text.trim(),
      'gcs_at_presentation':         _parseInt(_gcsCtrl.text),
      'comorbidities':               _comorbidities.toList(),
      'other_comorbidities':         _otherComorbidCtrl.text.trim(),
      'current_medications':         _medicationsCtrl.text.trim(),
      'ambulation':                  _ambulation,
      'right_hemiparesis':           _rightHemiparesis,
      'visual_field_deficit':        _visualFieldDeficit,
      'visual_field_specify':        _visualFieldSpecCtrl.text.trim(),
      'hearing_status':              _hearingStatus,
      'audiology_done':              _audiologyDone,
      'audiology_results':           _audiologyResultsCtrl.text.trim(),
      'external_cog_screening_done': _externalCogScreening,
      'external_cog_scores':         _externalCogScoresCtrl.text.trim(),
      'swallowing_concerns':         _swallowingConcerns,
      'premorbid_comm_style':        _premorbidCommStyleCtrl.text.trim(),
      'current_channels':            _currentChannels.toList(),
      'family_awareness':            _familyAwareness,
      'caregiver_involvement':       _caregiverInvolvement,
    };
    try {
      await _service.savePayloadSection(
        assessmentId: _assessment!.id,
        columnName:   'case_history_payload',
        payload:      payload,
      );
      // Mirror the typed presenting-profile columns so Section 8
      // routing + indexed queries see today's selections.
      await _service.savePresentingProfile(
        assessmentId:      _assessment!.id,
        etiologyCategory:  etiology,
        acuityStage:       acuity,
        timePostOnsetDays: timePostOnset,
        lesionLocation:    lesions,
      );
    } catch (e) {
      _toast('Could not save case history: $e');
    }
  }

  Future<void> _saveBedside() async {
    if (_assessment == null) return;
    final payload = <String, dynamic>{
      'consciousness': _consciousness,
      'orientation': {
        'person': _orientPerson,
        'place':  _orientPlace,
        'time':   _orientTime,
        'notes':  _orientNotesCtrl.text.trim(),
      },
      'digit_span_forward':  _parseInt(_digitFwdCtrl.text),
      'digit_span_backward': _parseInt(_digitBwdCtrl.text),
      'sustained_attention': _sustainedAttentionCtrl.text.trim(),
      'yes_no_accuracy':     _yesNoAccuracy,
      'yes_no_total':        _yesNoTotal,
      'object_naming':       _objectNaming,
      'object_naming_correct': _objectNamingCorrect,
      'object_naming_notes': _objectNamingNotesCtrl.text.trim(),
      'cmd_1step_pass':      _cmd1StepPass,
      'cmd_1step_correct':   _parseInt(_cmd1CorrectCtrl.text),
      'cmd_2step_pass':      _cmd2StepPass,
      'cmd_2step_correct':   _parseInt(_cmd2CorrectCtrl.text),
      'cmd_3step_pass':      _cmd3StepPass,
      'cmd_3step_correct':   _parseInt(_cmd3CorrectCtrl.text),
      'intelligibility':     _intelligibility,
      'read_single_word':    _readSingleWord,
      'read_sentence':       _readSentence,
      'read_comp_single':    _readCompSingle,
      'write_own_name':      _writeOwnName,
      'write_copy_sentence': _writeCopySent,
      'write_dictation':     _writeDictation,
      'bedside_impression':  _bedsideImpressionCtrl.text.trim(),
    };
    try {
      await _service.savePayloadSection(
        assessmentId: _assessment!.id,
        columnName:   'bedside_screen_payload',
        payload:      payload,
      );
    } catch (e) {
      _toast('Could not save bedside screen: $e');
    }
  }

  Future<void> _saveWab() async {
    if (_assessment == null) return;
    final aq = _wabAphasiaQuotient();
    final cq = _wabCorticalQuotient();
    final classification = _aphasiaTypeOverride ?? _autoAphasiaType();
    final data = <String, dynamic>{
      'battery_version':              _wabBatteryVersion,
      'language_administered':        _wabLanguageCtrl.text.trim().isEmpty
                                          ? _dominantLanguage
                                          : _wabLanguageCtrl.text.trim(),
      'spontaneous_info':             _ssInfo,
      'spontaneous_fluency':          _ssFluency,
      'avc_yes_no':                   _parseInt(_avcYesNoCtrl.text),
      'avc_word_recognition':         _parseInt(_avcWordRecCtrl.text),
      'avc_sequential_commands':      _parseInt(_avcSeqCtrl.text),
      'repetition_score':             _parseDecimal(_repCtrl.text),
      'naming_object':                _parseInt(_namingObjCtrl.text),
      'naming_word_fluency':          _parseInt(_namingFlCtrl.text),
      'naming_sentence_completion':   _parseInt(_namingSentCtrl.text),
      'naming_responsive_speech':     _parseInt(_namingRespCtrl.text),
      'reading_score':                _parseDecimal(_readingCtrl.text),
      'writing_score':                _parseDecimal(_writingCtrl.text),
      'aphasia_quotient':             aq,
      'cortical_quotient':            cq,
      'aphasia_type_classification':  classification,
      'notes':                        _wabNotesCtrl.text.trim(),
    };
    try {
      await _service.saveTypedMeasures(
        assessmentId: _assessment!.id,
        tableName:    'ald_wab_scores',
        data:         data,
      );
    } catch (e) {
      _toast('Could not save WAB scores: $e');
    }
  }

  Future<void> _saveCognitive() async {
    if (_assessment == null) return;
    // MoCA + MMSE share a single ald_cognitive_screens row keyed by
    // ald_assessment_id (UNIQUE constraint per 25a migration). Both
    // get serialized in one payload; either side may be empty.
    final data = <String, dynamic>{
      'moca_language_administered':    _mocaLangCtrl.text.trim(),
      'moca_visuospatial_executive':   _parseInt(_mocaVisuoCtrl.text),
      'moca_naming':                   _parseInt(_mocaNamingCtrl.text),
      'moca_memory_recall':            _parseInt(_mocaMemoryCtrl.text),
      'moca_attention':                _parseInt(_mocaAttentionCtrl.text),
      'moca_language':                 _parseInt(_mocaLanguageCtrl.text),
      'moca_abstraction':              _parseInt(_mocaAbstractCtrl.text),
      'moca_orientation':              _parseInt(_mocaOrientCtrl.text),
      'moca_education_adjustment':     _mocaEducationAdj,
      'moca_total':                    _mocaTotal(),
      'mmse_language_administered':    _mmseLangCtrl.text.trim(),
      'mmse_orientation':              _parseInt(_mmseOrientCtrl.text),
      'mmse_registration':             _parseInt(_mmseRegistrationCtrl.text),
      'mmse_attention_calculation':    _parseInt(_mmseAttentionCtrl.text),
      'mmse_recall':                   _parseInt(_mmseRecallCtrl.text),
      'mmse_language':                 _parseInt(_mmseLanguageCtrl.text),
      'mmse_total':                    _mmseTotal(),
    };
    try {
      await _service.saveTypedMeasures(
        assessmentId: _assessment!.id,
        tableName:    'ald_cognitive_screens',
        data:         data,
      );
    } catch (e) {
      _toast('Could not save cognitive screens: $e');
    }
  }

  // 25b — Section 4 typed naming measures.
  Future<void> _saveNaming() async {
    if (_assessment == null) return;
    final data = <String, dynamic>{
      'bnt_raw_score':            _parseInt(_bntRawCtrl.text),
      'bnt_z_score':              _parseDecimal(_bntZCtrl.text),
      'bnt_age_adjusted':         _bntAgeAdjusted,
      'ant_raw_score':            _parseInt(_antRawCtrl.text),
      'fluency_semantic_animals': _parseInt(_flAnimalsCtrl.text),
      'fluency_phonemic_f':       _parseInt(_flFCtrl.text),
      'fluency_phonemic_a':       _parseInt(_flACtrl.text),
      'fluency_phonemic_s':       _parseInt(_flSCtrl.text),
      'error_profile':            _namingErrors.toList(),
      'semantic_cue_helps':       _semCueHelps,
      'phonemic_cue_helps':       _phonCueHelps,
      'choice_cue_helps':         _choiceCueHelps,
      'notes':                    _namingNotesCtrl.text.trim(),
    };
    try {
      await _service.saveTypedMeasures(
        assessmentId: _assessment!.id,
        tableName:    'ald_naming_measures',
        data:         data,
      );
    } catch (e) {
      _toast('Could not save naming measures: $e');
    }
  }

  // 25b — Section 5 narrative jsonb.
  Future<void> _saveComprehension() async {
    if (_assessment == null) return;
    final payload = <String, dynamic>{
      'token_test_version':         _tokenVersion,
      'token_test_raw':             _parseDecimal(_tokenRawCtrl.text),
      'token_test_standardized':    _parseDecimal(_tokenStdCtrl.text),
      'yes_no_correct':             _parseInt(_yesNoCorrectCtrl.text),
      'cmd_1step_pct':              _parseInt(_cmd1PctCtrl.text),
      'cmd_2step_pct':              _parseInt(_cmd2PctCtrl.text),
      'cmd_3step_pct':              _parseInt(_cmd3PctCtrl.text),
      'cmd_4step_pct':              _parseInt(_cmd4PctCtrl.text),
      'sent_simple_pct':            _parseInt(_sentSimpleCtrl.text),
      'sent_subject_relative_pct':  _parseInt(_sentSubjRelCtrl.text),
      'sent_object_relative_pct':   _parseInt(_sentObjRelCtrl.text),
      'sent_passive_pct':           _parseInt(_sentPassiveCtrl.text),
      'story_used':                 _storyUsedCtrl.text.trim(),
      'story_propositions':         _storyPropsCtrl.text.trim(),
      'story_main_idea_grasped':    _storyMainIdea,
      'inferential_comprehension':  _inferentialComp,
      'comprehension_breakdown_notes': _compNotesCtrl.text.trim(),
    };
    try {
      await _service.savePayloadSection(
        assessmentId: _assessment!.id,
        columnName:   'auditory_comprehension_payload',
        payload:      payload,
      );
    } catch (e) {
      _toast('Could not save auditory comprehension: $e');
    }
  }

  // 25b — Section 6 narrative jsonb.
  Future<void> _saveReadingWriting() async {
    if (_assessment == null) return;
    final payload = <String, dynamic>{
      'read_regular_words':           _readRegCtrl.text.trim(),
      'read_irregular_words':         _readIrregCtrl.text.trim(),
      'read_nonwords':                _readNonwordsCtrl.text.trim(),
      'sentence_reading_fluency':     _sentReadingFluency,
      'paragraph_reading':            _paragraphReading,
      'read_word_picture_match':      _readWordPicCtrl.text.trim(),
      'read_sentence_picture_match':  _readSentPicCtrl.text.trim(),
      'paragraph_comprehension':      _paragraphComp,
      'reading_rate':                 _readingRate,
      'write_own_name_quality':       _writeOwnNameQuality,
      'copy_words_quality':           _copyWordsQuality,
      'write_dictation_words':        _writeDictWordsCtrl.text.trim(),
      'write_dictation_sentence':     _writeDictSentence,
      'spontaneous_writing_sample':   _spontaneousWritingCtrl.text.trim(),
      'writing_errors':               _writingErrors.toList(),
      'rw_impression':                _rwImpressionCtrl.text.trim(),
    };
    try {
      await _service.savePayloadSection(
        assessmentId: _assessment!.id,
        columnName:   'reading_writing_payload',
        payload:      payload,
      );
    } catch (e) {
      _toast('Could not save reading & writing: $e');
    }
  }

  // 25b — Section 7 narrative jsonb.
  Future<void> _saveDiscourse() async {
    if (_assessment == null) return;
    final payload = <String, dynamic>{
      'picture_used':                 _pictureUsed,
      'picture_description_verbatim': _pictureDescVerbatimCtrl.text.trim(),
      'total_words':                  _parseInt(_totalWordsCtrl.text),
      'content_units':                _parseInt(_contentUnitsCtrl.text),
      'mlu':                          _parseDecimal(_mluCtrl.text),
      'errors_per_minute':            _parseDecimal(_errorsPerMinCtrl.text),
      'conversation_topic':           _convoTopicCtrl.text.trim(),
      'conversation_duration_min':    _parseDecimal(_convoDurationCtrl.text),
      'topic_maintenance':            _topicMaintenance,
      'turn_taking':                  _turnTaking,
      'initiation':                   _initiation,
      'repair_strategies':            _repairStrategies.toList(),
      'channels_used':                _channelsUsed.toList(),
      'most_effective_channel':       _mostEffectiveChannel,
      'functional_comm_impression':   _funcCommImpressionCtrl.text.trim(),
    };
    try {
      await _service.savePayloadSection(
        assessmentId: _assessment!.id,
        columnName:   'discourse_payload',
        payload:      payload,
      );
    } catch (e) {
      _toast('Could not save discourse & functional comm: $e');
    }
  }

  /// Sum of the three FAS phonemic fluency totals (live, for the
  /// inline display next to the three input fields).
  int _fasTotal() =>
      (_parseInt(_flFCtrl.text) ?? 0) +
      (_parseInt(_flACtrl.text) ?? 0) +
      (_parseInt(_flSCtrl.text) ?? 0);

  // 25c — Section 8 saves split into the parent metadata (chip
  // selection) and one save per subform. Each subform writes its full
  // state on every blur within that subform, so toggling chips never
  // drops sibling data.
  Future<void> _saveSubformSelection() async {
    if (_assessment == null) return;
    try {
      await _service.savePayloadSection(
        assessmentId: _assessment!.id,
        columnName:   'etiology_specific_payload',
        payload:      {'subforms_selected': _subformsSelected.toList()},
      );
    } catch (e) {
      _toast('Could not save subform selection: $e');
    }
  }

  Future<void> _saveAphasiaApraxia() async {
    if (_assessment == null) return;
    final payload = <String, dynamic>{
      'lesion_symptom_correlation':  _aaLesionCorrelationCtrl.text.trim(),
      'aos_suspected':               _aosSuspected,
      'aos_articulatory_groping':    _aosArticulatoryGroping,
      'aos_inconsistent_errors':     _aosInconsistentErrors,
      'aos_slow_rate':               _aosSlowRate,
      'aos_distorted_substitutions': _aosDistortedSubst,
      'aos_trial_and_error':         _aosTrialAndError,
      'aos_awareness_of_errors':     _aosAwarenessOfErrors,
      'aos_ddk_observation':         _aosDdkObsCtrl.text.trim(),
      'aos_severity':                _aosSeverity,
      'dysarthria_screen':           _dysarthriaScreen,
      'comorbid_features':           _aaComorbidFeatures.toList(),
      'notes':                       _aaNotesCtrl.text.trim(),
    };
    _savePayload('aphasia_apraxia_payload', payload, 'Aphasia + Apraxia');
  }

  Future<void> _saveTbi() async {
    if (_assessment == null) return;
    final payload = <String, dynamic>{
      'gcs_at_admission':                  _parseInt(_tbiGcsAdmitCtrl.text),
      'current_functional_level':          _tbiCurrentLevelCtrl.text.trim(),
      'goat_score':                        _parseDecimal(_tbiGoatCtrl.text),
      'ranchos_level':                     _tbiRanchosLevel,
      'cognitive_communication_concerns':  _tbiCogConcerns.toList(),
      'behavioral_concerns':               _tbiBehavioralConcerns.toList(),
      'fim_communication_subscale':        _parseInt(_tbiFimCommCtrl.text),
      'notes':                             _tbiNotesCtrl.text.trim(),
    };
    _savePayload('tbi_payload', payload, 'TBI');
  }

  Future<void> _saveRhd() async {
    if (_assessment == null) return;
    final payload = <String, dynamic>{
      'mirbi_total':              _parseDecimal(_rhdMirbiCtrl.text),
      'pragmatic_deficits':       _rhdPragmaticDeficits.toList(),
      'visuospatial_neglect':     _rhdNeglect,
      'anosognosia':              _rhdAnosognosia,
      'affective_communication':  _rhdAffectiveComm,
      'discourse_profile':        _rhdDiscourseProfile,
      'notes':                    _rhdNotesCtrl.text.trim(),
    };
    _savePayload('rhd_payload', payload, 'RHD');
  }

  Future<void> _saveDementia() async {
    if (_assessment == null) return;
    final payload = <String, dynamic>{
      'subtype':                   _dementiaSubtype,
      'memory_profile':            _dementiaMemoryProfile.toList(),
      'language_decline_pattern':  _dementiaLanguagePatternCtrl.text.trim(),
      'differential_reasoning':    _dementiaDifferentialCtrl.text.trim(),
      'caregiver_timeline':        _dementiaTimelineCtrl.text.trim(),
      'notes':                     _dementiaNotesCtrl.text.trim(),
    };
    _savePayload('dementia_payload', payload, 'Dementia / MCI');
  }

  Future<void> _savePpa() async {
    if (_assessment == null) return;
    final payload = <String, dynamic>{
      'subtype':                       _ppaSubtype,
      'onset_progression_timeline':    _ppaTimelineCtrl.text.trim(),
      'semantic_features':             _ppaSemanticFeatures.toList(),
      'nonfluent_features':            _ppaNonfluentFeatures.toList(),
      'logopenic_features':            _ppaLogopenicFeatures.toList(),
      'differential_from_typical':     _ppaDifferentialCtrl.text.trim(),
      'notes':                         _ppaNotesCtrl.text.trim(),
    };
    _savePayload('ppa_payload', payload, 'PPA');
  }

  Future<void> _saveMultilingual() async {
    if (_assessment == null) return;
    final tests = _langTests.map((t) => {
          'language':                t.language,
          'wab_aq':                  _parseDecimal(t.wabAqCtrl.text),
          'conversational_fluency':  t.convoFluency,
          'naming':                  t.naming,
          'comprehension':           t.comprehension,
          'reading':                 t.reading,
          'writing':                 t.writing,
        }).where((m) => m['language'] != null).toList();
    final payload = <String, dynamic>{
      'language_tests':                    tests,
      'cross_linguistic_profile':          _crossLinguisticProfile.toList(),
      'most_preserved_language':           _mostPreservedLanguage,
      'code_switching_post_injury':        _codeSwitchingPostInjury,
      'cultural_assessment_notes':         _culturalAssessNotesCtrl.text.trim(),
      'treatment_language_recommendation': _multilingualTxLanguage,
      'notes':                             _multilingualNotesCtrl.text.trim(),
    };
    _savePayload('multilingual_payload', payload, 'Multilingual');
  }

  Future<void> _saveCogComm() async {
    if (_assessment == null) return;
    final payload = <String, dynamic>{
      'attn_sustained':           _attnSustained,
      'attn_selective':           _attnSelective,
      'attn_divided':             _attnDivided,
      'attn_notes':               _attnNotesCtrl.text.trim(),
      'mem_immediate':            _memImmediate,
      'mem_recent':               _memRecent,
      'mem_remote':               _memRemote,
      'mem_working':              _memWorking,
      'mem_tools_used':           _memToolsUsed.toList(),
      'exec_planning':            _execPlanning,
      'exec_problem_solving':     _execProblemSolving,
      'exec_flexibility':         _execFlexibility,
      'exec_inhibition':          _execInhibition,
      'exec_initiation':          _execInitiation,
      'exec_notes':               _execNotesCtrl.text.trim(),
      'reasoning_abstract':       _reasoningAbstract,
      'reasoning_categorization': _reasoningCategorization,
      'reasoning_sequencing':     _reasoningSequencing,
      'prag_insight':             _pragInsight,
      'prag_social_use':          _pragSocialUse,
      'prag_awareness_partner':   _pragAwarenessPartner,
      'cog_screen_tools':         _cogScreenToolsUsed.toList(),
    };
    _savePayload('cognitive_comm_screen_payload', payload, 'Cognitive-Communication');
  }

  Future<void> _saveDifferentialDx() async {
    if (_assessment == null) return;
    final ruleOuts = _ddRuleOutCtrls
        .map((c) => c.text.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    final payload = <String, dynamic>{
      'primary_diagnosis':       _ddPrimaryDxCtrl.text.trim(),
      'override_etiology':       _ddOverrideEtiology,
      'etiology_override':       _ddEtiologyOverride,
      'rule_outs':               ruleOuts,
      'contributing_factors':    _ddContributingFactors.toList(),
      'other_contributing':      _ddOtherContribCtrl.text.trim(),
      'differential_reasoning':  _ddSynthesisCtrl.text.trim(),
    };
    _savePayload('differential_diagnosis_payload', payload, 'Differential Dx');
  }

  Future<void> _saveQol() async {
    if (_assessment == null) return;
    final coast = _coastItems.isEmpty
        ? null
        : _coastItems.values.fold<int>(0, (a, b) => a + b);
    final aiq = _useAiq21
        ? _aiq21Items.values.fold<int>(0, (a, b) => a + b)
        : null;
    final saq = _useSaqol
        ? _saqolItems.values.fold<int>(0, (a, b) => a + b)
        : null;
    final ceti = _useCeti
        ? _cetiItems.values.fold<int>(0, (a, b) => a + b)
        : null;
    final data = <String, dynamic>{
      'coast_total':   ?coast,
      'aiq21_total':   ?aiq,
      'saqol39_total': ?saq,
      'ceti_total':    ?ceti,
    };
    try {
      await _service.saveTypedMeasures(
        assessmentId: _assessment!.id,
        tableName:    'ald_qol_scores',
        data:         data,
      );
      setState(() {
        _coastTotalLoaded = coast;
        _aiq21TotalLoaded = aiq;
        _saqolTotalLoaded = saq;
        _cetiTotalLoaded  = ceti;
      });
    } catch (e) {
      _toast('Could not save QoL scores: $e');
    }
  }

  Future<void> _saveClinicalImpression() async {
    if (_assessment == null) return;
    final payload = <String, dynamic>{
      'final_diagnosis':            _ciFinalDxCtrl.text.trim(),
      'icd_code':                   _ciIcdCodeCtrl.text.trim(),
      'severity':                   _ciSeverity,
      'severity_rationale':         _ciSeverityRationaleCtrl.text.trim(),
      'prognosis':                  _ciPrognosis,
      'prognostic_rationale':       _ciPrognosticRationaleCtrl.text.trim(),
      'recommended_interventions':  _ciInterventions.toList(),
      'therapy_approach_details':   _ciTherapyApproachCtrl.text.trim(),
      'estimated_session_count':    _parseInt(_ciSessionCountCtrl.text),
      'frequency':                  _ciFrequency,
      'session_duration_min':       _parseInt(_ciSessionDurationCtrl.text),
      'discharge_criteria':         _ciDischargeCriteriaCtrl.text.trim(),
      'referrals':                  _ciReferrals.toList(),
      'referral_notes':             _ciReferralNotesCtrl.text.trim(),
      'caregiver_education':        _ciCaregiverEdu.toList(),
      'functional_outcome_targets': _ciFunctionalOutcomesCtrl.text.trim(),
    };
    _savePayload('clinical_impression_payload', payload, 'Clinical Impression');
  }

  /// Shared helper so the seven payload-section saves stay one-liners.
  void _savePayload(
      String columnName, Map<String, dynamic> payload, String label) {
    _service
        .savePayloadSection(
          assessmentId: _assessment!.id,
          columnName:   columnName,
          payload:      payload,
        )
        .catchError((e) => _toast('Could not save $label: $e'));
  }

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

  // ── Derivations ────────────────────────────────────────────────────

  int? _timePostOnsetDays() {
    if (_onsetDate == null) return null;
    return DateTime.now().difference(_onsetDate!).inDays;
  }

  /// Auto-suggest acuity stage from onset date — user can still
  /// override via the chip picker.
  String? _autoAcuityStage() {
    final d = _timePostOnsetDays();
    if (d == null) return null;
    if (d < 7)   return 'Acute (<1 wk)';
    if (d < 90)  return 'Subacute (1 wk–3 mo)';
    return 'Chronic (>3 mo)';
  }

  int get _yesNoTotal =>
      _yesNoAccuracy.where((v) => v).length;
  int get _objectNamingCorrect =>
      _objectNaming.where((v) => v == 'correct').length;

  num? _wabAphasiaQuotient() {
    final ssI = _ssInfo;
    final ssF = _ssFluency;
    final avcYn = _parseDecimal(_avcYesNoCtrl.text);
    final avcWr = _parseDecimal(_avcWordRecCtrl.text);
    final avcSq = _parseDecimal(_avcSeqCtrl.text);
    final rep   = _parseDecimal(_repCtrl.text);
    final nObj  = _parseDecimal(_namingObjCtrl.text);
    final nFl   = _parseDecimal(_namingFlCtrl.text);
    final nSent = _parseDecimal(_namingSentCtrl.text);
    final nResp = _parseDecimal(_namingRespCtrl.text);
    // AQ requires SS scores present plus at least one section in each
    // of AVC / repetition / naming. Otherwise return null.
    final hasAvc = avcYn != null || avcWr != null || avcSq != null;
    final hasNaming = nObj != null || nFl != null || nSent != null || nResp != null;
    if (rep == null || !hasAvc || !hasNaming) return null;
    final avcTotal = (avcYn ?? 0) + (avcWr ?? 0) + (avcSq ?? 0); // /200
    final namingTotal = (nObj ?? 0) + (nFl ?? 0) + (nSent ?? 0) + (nResp ?? 0); // /100
    // Standard WAB-R AQ formula:
    // AQ = (SS_info * 2) + (SS_fluency * 2) + (AVC_total / 20)
    //      + (Repetition / 10) + (Naming_total / 10)
    return (ssI * 2) + (ssF * 2) + (avcTotal / 20) + (rep / 10) + (namingTotal / 10);
  }

  num? _wabCorticalQuotient() {
    final aq = _wabAphasiaQuotient();
    final reading = _parseDecimal(_readingCtrl.text);
    final writing = _parseDecimal(_writingCtrl.text);
    if (aq == null || reading == null || writing == null) return null;
    // CQ = (AQ + reading_/10 + writing_/10) / 1.2 — simplified Indian-clinic
    // approximation; a full WAB-R CQ formula adds praxis / construction
    // (not collected here). Flagged in 25a report.
    return (aq + (reading / 10) + (writing / 10)) / 1.2;
  }

  String _aqSeverityBand(num aq) {
    if (aq >= 93.8) return 'Within Normal Limits';
    if (aq >= 75)   return 'Mild';
    if (aq >= 50)   return 'Moderate';
    if (aq >= 25)   return 'Moderate-Severe';
    return 'Severe';
  }

  String? _autoAphasiaType() {
    final aq = _wabAphasiaQuotient();
    if (aq == null) return null;
    if (aq >= 93.8) return 'Not aphasic';
    final fluent = _ssFluency >= 5;
    final avcTotal = (_parseDecimal(_avcYesNoCtrl.text) ?? 0) +
                     (_parseDecimal(_avcWordRecCtrl.text) ?? 0) +
                     (_parseDecimal(_avcSeqCtrl.text) ?? 0);
    // AVC clinical band: WAB-R AVC subscore of 8+ on the 10-point
    // standardized scale ≈ raw 160+ across the three subtests; we use
    // a simple raw threshold here for the auto-suggest only — SLP
    // override via the chip picker carries final authority.
    final avcOk    = avcTotal >= 160;
    final repetition = _parseDecimal(_repCtrl.text) ?? 0;
    final repOk    = repetition >= 80;
    final namingTotal = (_parseDecimal(_namingObjCtrl.text) ?? 0) +
                        (_parseDecimal(_namingFlCtrl.text) ?? 0) +
                        (_parseDecimal(_namingSentCtrl.text) ?? 0) +
                        (_parseDecimal(_namingRespCtrl.text) ?? 0);
    final namingOk = namingTotal >= 80;
    if (!fluent && avcOk)        return 'Broca';
    if (fluent && !avcOk && !repOk) return 'Wernicke';
    if (!fluent && !avcOk)        return 'Global';
    if (fluent && avcOk && !repOk) return 'Conduction';
    if (fluent && avcOk && repOk && !namingOk) return 'Anomic';
    return 'Mixed';
  }

  int _mocaTotal() {
    int sum = 0;
    for (final c in [
      _mocaVisuoCtrl, _mocaNamingCtrl, _mocaMemoryCtrl,
      _mocaAttentionCtrl, _mocaLanguageCtrl, _mocaAbstractCtrl,
      _mocaOrientCtrl,
    ]) {
      sum += _parseInt(c.text) ?? 0;
    }
    if (_mocaEducationAdj) sum += 1;
    if (sum > 30) sum = 30;
    return sum;
  }

  int _mmseTotal() {
    int sum = 0;
    for (final c in [
      _mmseOrientCtrl, _mmseRegistrationCtrl, _mmseAttentionCtrl,
      _mmseRecallCtrl, _mmseLanguageCtrl,
    ]) {
      sum += _parseInt(c.text) ?? 0;
    }
    if (sum > 30) sum = 30;
    return sum;
  }

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
      return _errorBox('Could not load ALD assessment: $_error');
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _section(id: 'sec1', number: 1, title: 'Detailed Case History',
            tagline: 'Demographics, multilingual profile, onset, comorbidities, function.',
            child: _section1Body()),
        const SizedBox(height: 10),
        _section(id: 'sec2', number: 2, title: 'Bedside Screening',
            tagline: 'LOC, orientation, attention, comprehension commands, naming, intelligibility.',
            child: _section2Body()),
        const SizedBox(height: 10),
        _section(id: 'sec3', number: 3, title: 'Formal Battery (WAB-R + MoCA + MMSE)',
            tagline: 'Auto AQ/CQ + aphasia type classification + cognitive screens.',
            child: _section3Body()),
        const SizedBox(height: 10),
        _section(id: 'sec4', number: 4, title: 'Naming & Word Retrieval',
            tagline: 'BNT + action naming + FAS fluency + error profile + cuing response.',
            child: _section4Body()),
        const SizedBox(height: 10),
        _section(id: 'sec5', number: 5, title: 'Auditory Comprehension',
            tagline: 'Token Test, command length, sentence complexity, story retell.',
            child: _section5Body()),
        const SizedBox(height: 10),
        _section(id: 'sec6', number: 6, title: 'Reading & Writing',
            tagline: 'Word + sentence + paragraph; copy / dictation / generative writing.',
            child: _section6Body()),
        const SizedBox(height: 10),
        _section(id: 'sec7', number: 7, title: 'Discourse & Functional Communication',
            tagline: 'Picture description, conversation, channels, repair strategies.',
            child: _section7Body()),
        const SizedBox(height: 10),
        _section(id: 'sec8',  number: 8,  title: 'Etiology-Specific Subforms',
            tagline: 'Aphasia + Apraxia, TBI, RHD, Dementia, PPA, Multilingual — auto-suggested from Section 1.',
            child: _section8Body()),
        const SizedBox(height: 10),
        _section(id: 'sec9',  number: 9,  title: 'Cognitive-Communication Screen',
            tagline: 'Attention, memory, executive function, pragmatic awareness.',
            child: _section9Body()),
        const SizedBox(height: 10),
        _section(id: 'sec10', number: 10, title: 'Differential Diagnosis',
            tagline: 'Working hypothesis, etiology, rule-outs, contributors, synthesis.',
            child: _section10Body()),
        const SizedBox(height: 10),
        _section(id: 'sec11', number: 11, title: 'Outcome Tracking',
            tagline: 'Baseline vs most recent follow-up across all measures.',
            child: _section11Body()),
        const SizedBox(height: 10),
        _section(id: 'sec12', number: 12, title: 'Functional Communication & QoL',
            tagline: 'COAST, AIQ-21, SAQOL-39, CETI typed totals.',
            child: _section12Body()),
        const SizedBox(height: 10),
        _section(id: 'sec15', number: 15, title: 'Final Clinical Impression & Plan',
            tagline: 'Diagnosis, severity, prognosis, plan, referrals, caregiver education.',
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
                  fontSize: 12,
                  color: _inkGhost,
                  fontStyle: FontStyle.italic)),
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
    final autoAcuity = _autoAcuityStage();
    final tpo = _timePostOnsetDays();
    final isTbi = _etiology?.startsWith('TBI') ?? false;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _groupLabel('A · Demographic & Linguistic Background'),
        _numField('Age at assessment', _ageAtAssessmentCtrl,
            unit: 'years', onSave: _saveCaseHistory),
        _singleChips('Handedness',
            const ['Right', 'Left', 'Ambidextrous'], _handedness, (v) {
          setState(() => _handedness = v);
          _saveCaseHistory();
        }),
        _numField('Education years', _educationYearsCtrl,
            unit: 'years', onSave: _saveCaseHistory),
        _textField('Premorbid occupation', _occupationCtrl,
            onSave: _saveCaseHistory),
        _singleChips('Premorbid literacy level',
            const ['Illiterate', 'Functional', 'Fluent', 'Highly literate'],
            _premorbidLiteracy, (v) {
          setState(() => _premorbidLiteracy = v);
          _saveCaseHistory();
        }),
        const SizedBox(height: 4),
        _groupLabel('Languages spoken'),
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
        _singleChips('Dominant language for daily use',
            _languages.map((e) => e.nameCtrl.text.trim())
                .where((s) => s.isNotEmpty)
                .toList(),
            _dominantLanguage, (v) {
          setState(() => _dominantLanguage = v);
          _saveCaseHistory();
        }),
        _textField('Code-switching habits pre-injury',
            _codeSwitchingCtrl, multi: true, onSave: _saveCaseHistory),
        _textField('Premorbid voice / speech / language history',
            _premorbidVoiceHistCtrl, multi: true, onSave: _saveCaseHistory),

        const SizedBox(height: 14),
        _groupLabel('B · Medical / Neurological Onset'),
        _datePickerRow('Date of onset / event', _onsetDate, (d) {
          setState(() {
            _onsetDate = d;
            // Auto-suggest acuity if SLP hasn't picked one yet.
            _acuityStage ??= _autoAcuityStage();
          });
          _saveCaseHistory();
        }),
        _singleChips('Etiology', const [
          'Stroke (ischemic)', 'Stroke (hemorrhagic)',
          'TBI (closed)', 'TBI (penetrating)',
          "Dementia (Alzheimer's)", 'Dementia (vascular)',
          'Dementia (Lewy body)', 'Dementia (FTD)',
          'Dementia (mixed)',
          'PPA (semantic)', 'PPA (nonfluent)', 'PPA (logopenic)',
          'Encephalitis', 'Tumor', 'Other', 'Unknown',
        ], _etiology, (v) {
          setState(() => _etiology = v);
          _saveCaseHistory();
        }),
        _singleChips('Acuity stage', const [
          'Acute (<1 wk)', 'Subacute (1 wk–3 mo)', 'Chronic (>3 mo)',
        ], _acuityStage, (v) {
          setState(() => _acuityStage = v);
          _saveCaseHistory();
        }),
        if (autoAcuity != null && _acuityStage != autoAcuity) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              'Suggested from onset date: $autoAcuity',
              style: GoogleFonts.dmSans(
                  fontSize: 11, color: _inkGhost,
                  fontStyle: FontStyle.italic),
            ),
          ),
        ],
        if (tpo != null) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text('Time post-onset: $tpo days',
                style: GoogleFonts.dmSans(
                    fontSize: 12, color: _ink,
                    fontWeight: FontWeight.w500)),
          ),
        ],
        _multiChips('Lesion location', const [
          'L frontal', 'L temporal', 'L parietal', 'L occipital',
          'R hemisphere', 'Bilateral', 'Subcortical',
          'Brainstem', 'Cerebellum', 'Unknown',
        ], _lesionLocations, (v, sel) {
          setState(() {
            if (sel) {
              _lesionLocations.add(v);
            } else {
              _lesionLocations.remove(v);
            }
          });
          _saveCaseHistory();
        }),
        _textField('Lesion location notes', _lesionNotesCtrl,
            multi: true, onSave: _saveCaseHistory),
        _yesNo('Imaging available?', _imagingAvailable, (v) {
          setState(() => _imagingAvailable = v);
          _saveCaseHistory();
        }),
        if (_imagingAvailable) ...[
          _datePickerRow('Imaging date', _imagingDate, (d) {
            setState(() => _imagingDate = d);
            _saveCaseHistory();
          }),
          _singleChips('Modality',
              const ['CT', 'MRI', 'fMRI', 'DTI', 'Other'],
              _imagingModality, (v) {
            setState(() => _imagingModality = v);
            _saveCaseHistory();
          }),
        ],
        _textField('Hospitalization details', _hospitalizationCtrl,
            multi: true, hint: 'LOS, ICU stay, acute SLP services',
            onSave: _saveCaseHistory),
        if (isTbi)
          _numField('GCS at presentation', _gcsCtrl,
              unit: '/15 (3–15)', onSave: _saveCaseHistory),

        const SizedBox(height: 14),
        _groupLabel('C · Comorbidities'),
        _multiChips('Comorbidities', const [
          'Hypertension', 'Diabetes', 'Cardiac disease', 'Renal',
          'Hearing loss', 'Vision loss', 'Depression', 'Anxiety',
          'Prior stroke', 'Prior TBI', 'Other',
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
        if (_comorbidities.contains('Other'))
          _textField('Other comorbidities', _otherComorbidCtrl,
              multi: true, onSave: _saveCaseHistory),
        _textField('Current medications', _medicationsCtrl,
            multi: true,
            hint: 'Especially antiepileptics, antidepressants, antipsychotics, SSRIs, statins',
            onSave: _saveCaseHistory),

        const SizedBox(height: 14),
        _groupLabel('D · Functional Status'),
        _singleChips('Ambulation',
            const ['Independent', 'With aid', 'Wheelchair', 'Bedbound'],
            _ambulation, (v) {
          setState(() => _ambulation = v);
          _saveCaseHistory();
        }),
        _yesNo('Right hemiparesis?', _rightHemiparesis, (v) {
          setState(() => _rightHemiparesis = v);
          _saveCaseHistory();
        }),
        _yesNo('Visual field deficit?', _visualFieldDeficit, (v) {
          setState(() => _visualFieldDeficit = v);
          _saveCaseHistory();
        }),
        if (_visualFieldDeficit)
          _textField('Specify', _visualFieldSpecCtrl,
              multi: true, onSave: _saveCaseHistory),
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
        _yesNo('Cognitive screening done elsewhere?', _externalCogScreening, (v) {
          setState(() => _externalCogScreening = v);
          _saveCaseHistory();
        }),
        if (_externalCogScreening)
          _textField('External MMSE / MoCA / other scores',
              _externalCogScoresCtrl, multi: true,
              onSave: _saveCaseHistory),
        _yesNo('Swallowing concerns?', _swallowingConcerns, (v) {
          setState(() => _swallowingConcerns = v);
          _saveCaseHistory();
        }),
        if (_swallowingConcerns)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              'Cross-link to dysphagia assessment if needed.',
              style: GoogleFonts.dmSans(
                  fontSize: 11, color: _inkGhost,
                  fontStyle: FontStyle.italic),
            ),
          ),

        const SizedBox(height: 14),
        _groupLabel('E · Communication Profile (caregiver-reported)'),
        _textField('Premorbid communication style',
            _premorbidCommStyleCtrl, multi: true,
            onSave: _saveCaseHistory),
        _multiChips('Current functional communication channels', const [
          'Vocal', 'Gestural', 'Written', 'Drawing',
          'Pointing', 'AAC device', 'Picture cards', 'Eye gaze',
        ], _currentChannels, (v, sel) {
          setState(() {
            if (sel) {
              _currentChannels.add(v);
            } else {
              _currentChannels.remove(v);
            }
          });
          _saveCaseHistory();
        }),
        _singleChips('Family awareness of communication breakdown',
            const ['Full understanding', 'Partial', 'Limited', 'None'],
            _familyAwareness, (v) {
          setState(() => _familyAwareness = v);
          _saveCaseHistory();
        }),
        _singleChips('Caregiver involvement in therapy expected?',
            const ['High', 'Moderate', 'Low', 'Not available'],
            _caregiverInvolvement, (v) {
          setState(() => _caregiverInvolvement = v);
          _saveCaseHistory();
        }),
      ],
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
                DropdownMenuItem(value: 'Native', child: Text('Native')),
                DropdownMenuItem(value: 'Fluent', child: Text('Fluent')),
                DropdownMenuItem(value: 'Conversational', child: Text('Conversational')),
                DropdownMenuItem(value: 'Passive', child: Text('Passive')),
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
                removed.nameCtrl.dispose();
                removed.acquisitionAgeCtrl.dispose();
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

  // ── Section 2 body ─────────────────────────────────────────────────
  Widget _section2Body() {
    final yesNoFlagged = _yesNoTotal < 7;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _groupLabel('A · Level of Consciousness'),
        _singleChips('LOC', const [
          'Alert', 'Drowsy', 'Fluctuating', 'Stuporous', 'Comatose',
        ], _consciousness, (v) {
          setState(() => _consciousness = v);
          _saveBedside();
        }),

        const SizedBox(height: 14),
        _groupLabel('B · Orientation'),
        _yesNo('Person', _orientPerson, (v) {
          setState(() => _orientPerson = v);
          _saveBedside();
        }),
        _yesNo('Place', _orientPlace, (v) {
          setState(() => _orientPlace = v);
          _saveBedside();
        }),
        _yesNo('Time', _orientTime, (v) {
          setState(() => _orientTime = v);
          _saveBedside();
        }),
        _textField('Notes / specific responses', _orientNotesCtrl,
            multi: true, onSave: _saveBedside),

        const SizedBox(height: 14),
        _groupLabel('C · Attention'),
        _numField('Digit span — forward', _digitFwdCtrl,
            unit: 'count', onSave: _saveBedside),
        _numField('Digit span — backward', _digitBwdCtrl,
            unit: 'count', onSave: _saveBedside),
        _textField('Sustained attention narrative', _sustainedAttentionCtrl,
            multi: true, onSave: _saveBedside),

        const SizedBox(height: 14),
        _groupLabel('D · Yes/No accuracy (10 items)'),
        Wrap(
          spacing: 6, runSpacing: 6,
          children: [
            for (var i = 0; i < 10; i++)
              GestureDetector(
                onTap: () {
                  setState(() => _yesNoAccuracy[i] = !_yesNoAccuracy[i]);
                  _saveBedside();
                },
                child: Container(
                  width: 32, height: 28,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: _yesNoAccuracy[i] ? _teal : Colors.white,
                    border: Border.all(
                        color: _yesNoAccuracy[i] ? _teal : _line),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text('${i + 1}',
                      style: GoogleFonts.dmSans(
                          fontSize: 12,
                          color: _yesNoAccuracy[i] ? Colors.white : _ink,
                          fontWeight: FontWeight.w500)),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        _qolBadge(
          label: 'Yes/No total',
          total: _yesNoTotal,
          maxScore: 10,
          flagged: yesNoFlagged,
          flagText: 'Significant comprehension deficit — consider Token Test',
        ),

        const SizedBox(height: 14),
        _groupLabel('E · Object naming (5 items)'),
        for (var i = 0; i < 5; i++) _objectNamingRow(i),
        const SizedBox(height: 4),
        Text('Correct: $_objectNamingCorrect / 5',
            style: GoogleFonts.dmSans(
                fontSize: 12, color: _ink, fontWeight: FontWeight.w500)),
        const SizedBox(height: 8),
        _textField('Object-naming notes', _objectNamingNotesCtrl,
            multi: true, onSave: _saveBedside),

        const SizedBox(height: 14),
        _groupLabel('F · Auditory comprehension commands'),
        _passWithScore('1-step commands', _cmd1StepPass, _cmd1CorrectCtrl,
            (v) {
          setState(() => _cmd1StepPass = v);
          _saveBedside();
        }),
        _passWithScore('2-step commands', _cmd2StepPass, _cmd2CorrectCtrl,
            (v) {
          setState(() => _cmd2StepPass = v);
          _saveBedside();
        }),
        _passWithScore('3-step commands', _cmd3StepPass, _cmd3CorrectCtrl,
            (v) {
          setState(() => _cmd3StepPass = v);
          _saveBedside();
        }),

        const SizedBox(height: 14),
        _groupLabel('G · Speech intelligibility'),
        _singleChips('Intelligibility', const [
          'Intelligible', 'Effortful but intelligible',
          'Partially intelligible', 'Unintelligible',
        ], _intelligibility, (v) {
          setState(() => _intelligibility = v);
          _saveBedside();
        }),

        const SizedBox(height: 14),
        _groupLabel('H · Reading screen'),
        _yesNo('Read aloud single words', _readSingleWord, (v) {
          setState(() => _readSingleWord = v);
          _saveBedside();
        }),
        _yesNo('Read aloud sentence', _readSentence, (v) {
          setState(() => _readSentence = v);
          _saveBedside();
        }),
        _yesNo('Comprehension of single read word', _readCompSingle, (v) {
          setState(() => _readCompSingle = v);
          _saveBedside();
        }),

        const SizedBox(height: 14),
        _groupLabel('I · Writing screen'),
        _yesNo('Write own name', _writeOwnName, (v) {
          setState(() => _writeOwnName = v);
          _saveBedside();
        }),
        _yesNo('Copy a sentence', _writeCopySent, (v) {
          setState(() => _writeCopySent = v);
          _saveBedside();
        }),
        _yesNo('Write to dictation (1–2 words)', _writeDictation, (v) {
          setState(() => _writeDictation = v);
          _saveBedside();
        }),

        const SizedBox(height: 14),
        _groupLabel('J · Bedside impression'),
        _textField('Clinician overall narrative', _bedsideImpressionCtrl,
            multi: true, onSave: _saveBedside),
      ],
    );
  }

  Widget _objectNamingRow(int index) {
    final v = _objectNaming[index];
    Widget chip(String value, String label) {
      final selected = v == value;
      return GestureDetector(
        onTap: () {
          setState(() => _objectNaming[index] = selected ? null : value);
          _saveBedside();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: selected ? _tealSoft.withValues(alpha: 0.6) : Colors.white,
            border: Border.all(color: selected ? _teal : _line),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(label,
              style: GoogleFonts.dmSans(
                  fontSize: 11,
                  color: selected ? _teal : _ink,
                  fontWeight: FontWeight.w500)),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          SizedBox(
            width: 24,
            child: Text('${index + 1}.',
                style: GoogleFonts.dmSans(
                    fontSize: 12, color: _inkGhost)),
          ),
          chip('correct', 'Correct'),
          const SizedBox(width: 6),
          chip('paraphasia', 'Paraphasia'),
          const SizedBox(width: 6),
          chip('no_response', 'No response'),
        ],
      ),
    );
  }

  Widget _passWithScore(String label, bool pass,
      TextEditingController ctrl, ValueChanged<bool> onPass) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Expanded(
            flex: 4,
            child: Text(label,
                style: GoogleFonts.dmSans(
                    fontSize: 13, color: _ink,
                    fontWeight: FontWeight.w500)),
          ),
          _yesNoChip('Pass', pass, () => onPass(true)),
          const SizedBox(width: 4),
          _yesNoChip('Fail', !pass, () => onPass(false)),
          const SizedBox(width: 8),
          SizedBox(
            width: 60,
            child: Focus(
              onFocusChange: (f) {
                if (!f) _saveBedside();
              },
              child: TextField(
                controller: ctrl,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                ],
                style: GoogleFonts.dmSans(fontSize: 12, color: _ink),
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  isDense: true,
                  hintText: '/5',
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Section 3 body — WAB-R + MoCA + MMSE ──────────────────────────
  Widget _section3Body() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _subsectionHeader('3A · WAB-R'),
        _section3aWab(),
        const SizedBox(height: 18),
        _subsectionHeader('3B · MoCA'),
        _section3bMoca(),
        const SizedBox(height: 18),
        _subsectionHeader('3C · MMSE'),
        _section3cMmse(),
      ],
    );
  }

  Widget _section3aWab() {
    final aq = _wabAphasiaQuotient();
    final cq = _wabCorticalQuotient();
    final auto = _autoAphasiaType();
    final activeType = _aphasiaTypeOverride ?? auto;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _groupLabel('A · Battery metadata'),
        _singleChips('Battery version', const [
          'WAB-R (English)', 'WAB-K (Kannada)', 'WAB-Hindi',
          'WAB-Tamil', 'Other adapted version',
        ], _wabBatteryVersion, (v) {
          setState(() => _wabBatteryVersion = v);
          _saveWab();
        }),
        _textField('Language administered', _wabLanguageCtrl,
            hint: _dominantLanguage ?? 'e.g. English',
            onSave: _saveWab),

        const SizedBox(height: 14),
        _groupLabel('B · Spontaneous Speech (each 0–10)'),
        _intSlider('Information content', _ssInfo, 0, 10, (v) {
          setState(() => _ssInfo = v);
        }, _saveWab),
        _intSlider('Fluency', _ssFluency, 0, 10, (v) {
          setState(() => _ssFluency = v);
        }, _saveWab),

        const SizedBox(height: 14),
        _groupLabel('C · Auditory Verbal Comprehension'),
        _numField('Yes/No questions', _avcYesNoCtrl,
            unit: '/60', onSave: _saveWab),
        _numField('Auditory word recognition', _avcWordRecCtrl,
            unit: '/60', onSave: _saveWab),
        _numField('Sequential commands', _avcSeqCtrl,
            unit: '/80', onSave: _saveWab),

        const SizedBox(height: 14),
        _groupLabel('D · Repetition'),
        _numField('Repetition score', _repCtrl,
            unit: '/100', onSave: _saveWab),

        const SizedBox(height: 14),
        _groupLabel('E · Naming & Word Finding'),
        _numField('Object naming', _namingObjCtrl,
            unit: '/60', onSave: _saveWab),
        _numField('Word fluency', _namingFlCtrl,
            unit: '/20', onSave: _saveWab),
        _numField('Sentence completion', _namingSentCtrl,
            unit: '/10', onSave: _saveWab),
        _numField('Responsive speech', _namingRespCtrl,
            unit: '/10', onSave: _saveWab),

        const SizedBox(height: 14),
        _groupLabel('F · Auto-calculated quotients'),
        _quotientCard(
          label: 'Aphasia Quotient (AQ)',
          value: aq,
          maxScore: 100,
          band: aq == null ? '—' : _aqSeverityBand(aq),
          flagged: aq != null && aq < 75,
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text('Aphasia type — auto-suggested from AQ + pattern',
              style: GoogleFonts.dmSans(
                  fontSize: 12, color: _inkGhost,
                  fontWeight: FontWeight.w500)),
        ),
        Wrap(
          spacing: 6, runSpacing: 6,
          children: [
            for (final t in const [
              'Broca', 'Wernicke', 'Global', 'Conduction', 'Anomic',
              'Transcortical motor', 'Transcortical sensory',
              'Mixed transcortical', 'Mixed', 'Not aphasic',
            ])
              _yesNoChip(t, activeType == t, () {
                setState(() => _aphasiaTypeOverride =
                    activeType == t ? null : t);
                _saveWab();
              }),
          ],
        ),
        if (auto != null && _aphasiaTypeOverride != null && _aphasiaTypeOverride != auto) ...[
          const SizedBox(height: 4),
          Text('Auto-suggestion: $auto (override active)',
              style: GoogleFonts.dmSans(
                  fontSize: 11, color: _inkGhost,
                  fontStyle: FontStyle.italic)),
        ],

        const SizedBox(height: 14),
        _groupLabel('G · Reading & Writing (optional, for CQ)'),
        _numField('Reading score', _readingCtrl,
            unit: '', onSave: _saveWab),
        _numField('Writing score', _writingCtrl,
            unit: '', onSave: _saveWab),
        _quotientCard(
          label: 'Cortical Quotient (CQ)',
          value: cq,
          maxScore: 100,
          band: cq == null ? '—' : _aqSeverityBand(cq),
          flagged: cq != null && cq < 75,
        ),
        _textField('WAB notes', _wabNotesCtrl,
            multi: true, onSave: _saveWab),
      ],
    );
  }

  Widget _section3bMoca() {
    final total = _mocaTotal();
    final flagged = total < 26;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _groupLabel('A · Metadata'),
        _textField('Language administered', _mocaLangCtrl,
            onSave: _saveCognitive),

        const SizedBox(height: 8),
        _groupLabel('B · Subscores'),
        _numField('Visuospatial / Executive', _mocaVisuoCtrl,
            unit: '/5', onSave: _saveCognitive),
        _numField('Naming', _mocaNamingCtrl,
            unit: '/3', onSave: _saveCognitive),
        _numField('Memory (delayed recall)', _mocaMemoryCtrl,
            unit: '/5', onSave: _saveCognitive),
        _numField('Attention', _mocaAttentionCtrl,
            unit: '/6', onSave: _saveCognitive),
        _numField('Language', _mocaLanguageCtrl,
            unit: '/3', onSave: _saveCognitive),
        _numField('Abstraction', _mocaAbstractCtrl,
            unit: '/2', onSave: _saveCognitive),
        _numField('Orientation', _mocaOrientCtrl,
            unit: '/6', onSave: _saveCognitive),

        const SizedBox(height: 8),
        _groupLabel('C · Education adjustment'),
        _yesNo('Education ≤ 12 years (+1 adjustment)',
            _mocaEducationAdj, (v) {
          setState(() => _mocaEducationAdj = v);
          _saveCognitive();
        }),

        const SizedBox(height: 8),
        _qolBadge(
          label: 'MoCA total',
          total: total,
          maxScore: 30,
          flagged: flagged,
          flagText: 'Cognitive impairment likely (< 26)',
        ),
      ],
    );
  }

  Widget _section3cMmse() {
    final total = _mmseTotal();
    final flagged = total < 24;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _groupLabel('A · Metadata'),
        _textField('Language administered', _mmseLangCtrl,
            onSave: _saveCognitive),

        const SizedBox(height: 8),
        _groupLabel('B · Subscores'),
        _numField('Orientation', _mmseOrientCtrl,
            unit: '/10', onSave: _saveCognitive),
        _numField('Registration', _mmseRegistrationCtrl,
            unit: '/3', onSave: _saveCognitive),
        _numField('Attention & calculation', _mmseAttentionCtrl,
            unit: '/5', onSave: _saveCognitive),
        _numField('Recall', _mmseRecallCtrl,
            unit: '/3', onSave: _saveCognitive),
        _numField('Language', _mmseLanguageCtrl,
            unit: '/9', onSave: _saveCognitive),

        const SizedBox(height: 8),
        _qolBadge(
          label: 'MMSE total',
          total: total,
          maxScore: 30,
          flagged: flagged,
          flagText: 'Cognitive impairment (< 24)',
        ),
      ],
    );
  }

  Widget _quotientCard({
    required String label,
    required num? value,
    required int maxScore,
    required String band,
    required bool flagged,
  }) {
    final color = flagged ? _amber : _green;
    final bg    = flagged ? _amberSoft : _tealSoft;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(
          color: bg.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.45)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                value == null
                    ? '$label: — / $maxScore'
                    : '$label: ${value.toStringAsFixed(1)} / $maxScore',
                style: GoogleFonts.dmSans(
                    fontSize: 13,
                    color: color,
                    fontWeight: FontWeight.w600),
              ),
            ),
            Text(band,
                style: GoogleFonts.dmSans(
                    fontSize: 11, color: color,
                    fontStyle: FontStyle.italic)),
          ],
        ),
      ),
    );
  }

  // ── Section 4 body — Naming & Word Retrieval ──────────────────────
  Widget _section4Body() {
    final fas = _fasTotal();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _groupLabel('A · Boston Naming Test (BNT)'),
        _numField('BNT raw score', _bntRawCtrl,
            unit: '/60', onSave: _saveNaming),
        _numField('Age-adjusted z-score', _bntZCtrl,
            unit: 'z (±)', onSave: _saveNaming),
        _yesNo('Age adjustment applied?', _bntAgeAdjusted, (v) {
          setState(() => _bntAgeAdjusted = v);
          _saveNaming();
        }),
        _ghostNote('z ≤ −1.5 = significant deficit; z = −1 to −1.5 = mild.'),

        const SizedBox(height: 14),
        _groupLabel('B · Action Naming Test (optional)'),
        _numField('Action Naming raw score', _antRawCtrl,
            unit: 'raw', onSave: _saveNaming),
        _ghostNote('If administered. Skip if not part of battery.'),

        const SizedBox(height: 14),
        _groupLabel('C · Verbal Fluency (60s tasks)'),
        _numField('Semantic — animals (60s)', _flAnimalsCtrl,
            unit: 'count', onSave: _saveNaming),
        _numField('Phonemic — F (60s)', _flFCtrl,
            unit: 'count', onSave: _saveNaming),
        _numField('Phonemic — A (60s)', _flACtrl,
            unit: 'count', onSave: _saveNaming),
        _numField('Phonemic — S (60s)', _flSCtrl,
            unit: 'count', onSave: _saveNaming),
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text('FAS total: $fas',
              style: GoogleFonts.dmSans(
                  fontSize: 12, color: _ink,
                  fontWeight: FontWeight.w500)),
        ),
        _ghostNote(
            'Adult Indian-context norms: Animals ≥ 15, FAS total ≥ 30 considered WNL.'),

        const SizedBox(height: 14),
        _groupLabel('D · Naming Error Profile'),
        _multiChips('Error types observed', const [
          'Semantic paraphasia', 'Phonemic paraphasia', 'Neologism',
          'Circumlocution', "Don't know responses", 'No response',
          'Perseveration', 'Mixed errors',
        ], _namingErrors, (v, sel) {
          setState(() {
            if (sel) {
              _namingErrors.add(v);
            } else {
              _namingErrors.remove(v);
            }
          });
          _saveNaming();
        }),

        const SizedBox(height: 14),
        _groupLabel('E · Cuing Effectiveness'),
        _yesNo('Semantic cue helps', _semCueHelps, (v) {
          setState(() => _semCueHelps = v);
          _saveNaming();
        }),
        _yesNo('Phonemic cue helps', _phonCueHelps, (v) {
          setState(() => _phonCueHelps = v);
          _saveNaming();
        }),
        _yesNo('Choice cue helps', _choiceCueHelps, (v) {
          setState(() => _choiceCueHelps = v);
          _saveNaming();
        }),
        _ghostNote(
            'Cuing response predicts therapy approach. Phonemic cue effective → SFA candidate. Semantic cue effective → semantic feature work.'),

        const SizedBox(height: 14),
        _groupLabel('F · Notes'),
        _textField('Naming notes', _namingNotesCtrl,
            multi: true, onSave: _saveNaming),
      ],
    );
  }

  // ── Section 5 body — Auditory Comprehension ───────────────────────
  Widget _section5Body() {
    final ynRaw = _parseInt(_yesNoCorrectCtrl.text);
    final ynFlagged = ynRaw != null && ynRaw < 14;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _groupLabel('A · Token Test'),
        _singleChips('Token Test version', const [
          'Full (62-item)', 'Short form (36-item)', 'Other',
        ], _tokenVersion, (v) {
          setState(() => _tokenVersion = v);
          _saveComprehension();
        }),
        _numField('Token Test raw score', _tokenRawCtrl,
            unit: 'raw', onSave: _saveComprehension),
        _numField('Token Test percentile / standardized', _tokenStdCtrl,
            unit: 'std', onSave: _saveComprehension),
        _ghostNote('Standardized cutoff varies by version.'),

        const SizedBox(height: 14),
        _groupLabel('B · Yes/No accuracy (extended)'),
        _numField('Yes/No questions correct', _yesNoCorrectCtrl,
            unit: '/20', onSave: _saveComprehension),
        if (ynFlagged)
          _flaggedNote('< 14/20 — significant comprehension impairment.'),

        const SizedBox(height: 14),
        _groupLabel('C · Following commands by length (% accuracy)'),
        _numField('1-step commands', _cmd1PctCtrl,
            unit: '%', onSave: _saveComprehension),
        _numField('2-step commands', _cmd2PctCtrl,
            unit: '%', onSave: _saveComprehension),
        _numField('3-step commands', _cmd3PctCtrl,
            unit: '%', onSave: _saveComprehension),
        _numField('4-step commands', _cmd4PctCtrl,
            unit: '%', onSave: _saveComprehension),

        const SizedBox(height: 14),
        _groupLabel('D · Sentence comprehension complexity (% accuracy)'),
        _numField('Simple active sentences', _sentSimpleCtrl,
            unit: '%', onSave: _saveComprehension),
        _numField('Subject-relative clauses', _sentSubjRelCtrl,
            unit: '%', onSave: _saveComprehension),
        _numField('Object-relative clauses', _sentObjRelCtrl,
            unit: '%', onSave: _saveComprehension),
        _numField('Passive sentences', _sentPassiveCtrl,
            unit: '%', onSave: _saveComprehension),
        _ghostNote(
            'Object-relative drop indicates syntactic comprehension impairment (Broca / conduction).'),

        const SizedBox(height: 14),
        _groupLabel('E · Discourse comprehension'),
        _textField('Story retell — story used', _storyUsedCtrl,
            onSave: _saveComprehension),
        _textField('Propositions retained (X / Y)', _storyPropsCtrl,
            hint: 'e.g. 6 / 10', onSave: _saveComprehension),
        _yesNo('Main idea grasped?', _storyMainIdea, (v) {
          setState(() => _storyMainIdea = v);
          _saveComprehension();
        }),
        _singleChips('Inferential comprehension',
            const ['Intact', 'Reduced', 'Severely impaired'],
            _inferentialComp, (v) {
          setState(() => _inferentialComp = v);
          _saveComprehension();
        }),

        const SizedBox(height: 14),
        _groupLabel('F · Comprehension breakdown notes'),
        _textField('Narrative', _compNotesCtrl,
            multi: true, onSave: _saveComprehension),
      ],
    );
  }

  // ── Section 6 body — Reading & Writing ────────────────────────────
  Widget _section6Body() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _groupLabel('A · Reading aloud'),
        _textField('Single regular words (X / Y)', _readRegCtrl,
            hint: 'e.g. 8 / 10', onSave: _saveReadingWriting),
        _textField('Single irregular words (X / Y)', _readIrregCtrl,
            hint: 'e.g. 4 / 10', onSave: _saveReadingWriting),
        _textField('Non-words / pseudowords (X / Y)', _readNonwordsCtrl,
            onSave: _saveReadingWriting),
        _ghostNote(
            'Surface dyslexia: irregular impaired, regular preserved. Phonological dyslexia: non-words impaired.'),
        _singleChips('Sentence reading aloud',
            const ['Fluent', 'Effortful', 'Letter-by-letter', 'Unable'],
            _sentReadingFluency, (v) {
          setState(() => _sentReadingFluency = v);
          _saveReadingWriting();
        }),
        _singleChips('Paragraph reading aloud',
            const ['Adequate', 'Slow but intelligible', 'Halting', 'Unable'],
            _paragraphReading, (v) {
          setState(() => _paragraphReading = v);
          _saveReadingWriting();
        }),

        const SizedBox(height: 14),
        _groupLabel('B · Reading comprehension'),
        _textField('Single word — picture matching (X / Y)',
            _readWordPicCtrl, onSave: _saveReadingWriting),
        _textField('Sentence — picture matching (X / Y)',
            _readSentPicCtrl, onSave: _saveReadingWriting),
        _singleChips('Paragraph comprehension',
            const ['Adequate', 'Reduced', 'Severely impaired'],
            _paragraphComp, (v) {
          setState(() => _paragraphComp = v);
          _saveReadingWriting();
        }),
        _singleChips('Reading rate',
            const ['WNL', 'Slow', 'Very slow'],
            _readingRate, (v) {
          setState(() => _readingRate = v);
          _saveReadingWriting();
        }),

        const SizedBox(height: 14),
        _groupLabel('C · Writing'),
        _singleChips('Write own name',
            const ['Legible', 'Distorted', 'Unable'],
            _writeOwnNameQuality, (v) {
          setState(() => _writeOwnNameQuality = v);
          _saveReadingWriting();
        }),
        _singleChips('Copy single words',
            const ['Accurate', 'Errors', 'Unable'],
            _copyWordsQuality, (v) {
          setState(() => _copyWordsQuality = v);
          _saveReadingWriting();
        }),
        _textField('Write to dictation — words (X / Y)',
            _writeDictWordsCtrl, onSave: _saveReadingWriting),
        _singleChips('Write to dictation — sentence',
            const ['Accurate', 'Some errors', 'Unable'],
            _writeDictSentence, (v) {
          setState(() => _writeDictSentence = v);
          _saveReadingWriting();
        }),
        _textField('Spontaneous writing sample',
            _spontaneousWritingCtrl, multi: true,
            hint: 'Capture sample or describe',
            onSave: _saveReadingWriting),
        _multiChips('Writing errors observed', const [
          'Phonological', 'Surface', 'Semantic substitution',
          'Letter omission', 'Letter substitution',
          'Agrammatic', 'Apraxic / motor',
        ], _writingErrors, (v, sel) {
          setState(() {
            if (sel) {
              _writingErrors.add(v);
            } else {
              _writingErrors.remove(v);
            }
          });
          _saveReadingWriting();
        }),

        const SizedBox(height: 14),
        _groupLabel('D · Reading + writing impression'),
        _textField('Impression', _rwImpressionCtrl,
            multi: true, onSave: _saveReadingWriting),
      ],
    );
  }

  // ── Section 7 body — Discourse & Functional Communication ─────────
  Widget _section7Body() {
    final mostEffectiveOptions =
        _channelsUsed.toList()..sort();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _groupLabel('A · Picture description'),
        _singleChips('Picture used', const [
          'Cookie Theft (BDAE)', 'WAB-R picnic scene',
          'Indian-adapted (specify)', 'Other',
        ], _pictureUsed, (v) {
          setState(() => _pictureUsed = v);
          _saveDiscourse();
        }),
        _textField('Picture description verbatim',
            _pictureDescVerbatimCtrl, multi: true,
            hint: 'Transcribed sample',
            onSave: _saveDiscourse),
        _numField('Total words produced', _totalWordsCtrl,
            unit: 'words', onSave: _saveDiscourse),
        _numField('Content units / propositions correct',
            _contentUnitsCtrl, unit: 'units', onSave: _saveDiscourse),
        _numField('Mean length of utterance (MLU)', _mluCtrl,
            unit: 'words', onSave: _saveDiscourse),
        _numField('Errors per minute', _errorsPerMinCtrl,
            unit: '/min', onSave: _saveDiscourse),
        _ghostNote(
            'MLU < 5 words suggests agrammatism. Content units / minute < 4 = reduced informativeness.'),

        const SizedBox(height: 14),
        _groupLabel('B · Conversational sample'),
        _textField('Conversation topic', _convoTopicCtrl,
            onSave: _saveDiscourse),
        _numField('Duration', _convoDurationCtrl,
            unit: 'minutes', onSave: _saveDiscourse),
        _singleChips('Topic maintenance',
            const ['Adequate', 'Reduced', 'Tangential'],
            _topicMaintenance, (v) {
          setState(() => _topicMaintenance = v);
          _saveDiscourse();
        }),
        _singleChips('Turn-taking',
            const ['Adequate', 'Reduced', 'Inappropriate'],
            _turnTaking, (v) {
          setState(() => _turnTaking = v);
          _saveDiscourse();
        }),
        _singleChips('Initiation',
            const ['Spontaneous', 'Cued', 'Absent'],
            _initiation, (v) {
          setState(() => _initiation = v);
          _saveDiscourse();
        }),
        _multiChips('Repair strategies used', const [
          'Self-correction', 'Restarts', 'Gestural',
          'Drawing', 'Caregiver scaffolding', 'None observed',
        ], _repairStrategies, (v, sel) {
          setState(() {
            if (sel) {
              _repairStrategies.add(v);
            } else {
              _repairStrategies.remove(v);
            }
          });
          _saveDiscourse();
        }),

        const SizedBox(height: 14),
        _groupLabel('C · Communicative effectiveness'),
        _multiChips('Channels used effectively', const [
          'Vocal speech', 'Gesture', 'Facial expression',
          'Drawing', 'Pointing', 'Writing', 'AAC', 'Eye gaze',
        ], _channelsUsed, (v, sel) {
          setState(() {
            if (sel) {
              _channelsUsed.add(v);
            } else {
              _channelsUsed.remove(v);
              if (_mostEffectiveChannel == v) _mostEffectiveChannel = null;
            }
          });
          _saveDiscourse();
        }),
        _singleChips('Most effective channel currently',
            mostEffectiveOptions, _mostEffectiveChannel, (v) {
          setState(() => _mostEffectiveChannel = v);
          _saveDiscourse();
        }),

        const SizedBox(height: 14),
        _groupLabel('D · Functional communication impression'),
        _textField('Impression', _funcCommImpressionCtrl,
            multi: true, onSave: _saveDiscourse),
      ],
    );
  }

  // ── Shared 25b primitives ─────────────────────────────────────────

  Widget _ghostNote(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
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

  Widget _flaggedNote(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        decoration: BoxDecoration(
          color: _amberSoft.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: _amber.withValues(alpha: 0.45)),
        ),
        child: Text(text,
            style: GoogleFonts.dmSans(
                fontSize: 12, color: _amber,
                fontWeight: FontWeight.w500)),
      ),
    );
  }

  // ── Section 8 body — Etiology-Specific Subforms ───────────────────
  // Multi-select chip set drives which subform bodies render. All
  // subform state stays in widget memory and persists to its own
  // jsonb column on save, so toggling chips on/off never drops data.
  Widget _section8Body() {
    String chipKey(String label) => switch (label) {
          'Aphasia + Apraxia'        => 'aphasia_apraxia',
          'TBI'                      => 'tbi',
          'RHD'                      => 'rhd',
          'Dementia / MCI'           => 'dementia',
          'PPA'                      => 'ppa',
          'Multilingual crossover'   => 'multilingual',
          _                          => label.toLowerCase(),
        };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _groupLabel('A · Subform selector'),
        Wrap(
          spacing: 6, runSpacing: 6,
          children: [
            for (final label in const [
              'Aphasia + Apraxia', 'TBI', 'RHD',
              'Dementia / MCI', 'PPA', 'Multilingual crossover',
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
                _saveSubformSelection();
              }),
          ],
        ),
        if (_subformsSelected.isEmpty)
          _ghostNote(
              'Pick one or more subforms based on the etiology you logged in Section 1.'),
        if (_subformsSelected.contains('aphasia_apraxia')) ...[
          const SizedBox(height: 18),
          _subsectionHeader('8A · Aphasia + Apraxia of Speech'),
          _section8aBody(),
        ],
        if (_subformsSelected.contains('tbi')) ...[
          const SizedBox(height: 18),
          _subsectionHeader('8B · Traumatic Brain Injury'),
          _section8bBody(),
        ],
        if (_subformsSelected.contains('rhd')) ...[
          const SizedBox(height: 18),
          _subsectionHeader('8C · Right Hemisphere Damage'),
          _section8cBody(),
        ],
        if (_subformsSelected.contains('dementia')) ...[
          const SizedBox(height: 18),
          _subsectionHeader('8D · Dementia / MCI'),
          _section8dBody(),
        ],
        if (_subformsSelected.contains('ppa')) ...[
          const SizedBox(height: 18),
          _subsectionHeader('8E · Primary Progressive Aphasia'),
          _section8eBody(),
        ],
        if (_subformsSelected.contains('multilingual')) ...[
          const SizedBox(height: 18),
          _subsectionHeader('8F · Multilingual Crossover'),
          _section8fBody(),
        ],
      ],
    );
  }

  Widget _section8aBody() {
    final wabType = _aphasiaTypeOverride ?? _autoAphasiaType() ?? '—';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(
            children: [
              Text('Aphasia type (auto from WAB): ',
                  style: GoogleFonts.dmSans(
                      fontSize: 12, color: _inkGhost)),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: _tealSoft.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _teal.withValues(alpha: 0.4)),
                ),
                child: Text(wabType,
                    style: GoogleFonts.dmSans(
                        fontSize: 12, color: _teal,
                        fontWeight: FontWeight.w500)),
              ),
            ],
          ),
        ),
        _textField('Lesion-symptom correlation notes',
            _aaLesionCorrelationCtrl, multi: true,
            onSave: _saveAphasiaApraxia),

        const SizedBox(height: 14),
        _groupLabel('Apraxia of Speech screen'),
        _yesNo('AOS suspected?', _aosSuspected, (v) {
          setState(() => _aosSuspected = v);
          _saveAphasiaApraxia();
        }),
        if (_aosSuspected) ...[
          _yesNo('Articulatory groping', _aosArticulatoryGroping, (v) {
            setState(() => _aosArticulatoryGroping = v);
            _saveAphasiaApraxia();
          }),
          _yesNo('Inconsistent errors', _aosInconsistentErrors, (v) {
            setState(() => _aosInconsistentErrors = v);
            _saveAphasiaApraxia();
          }),
          _yesNo('Slow articulation rate', _aosSlowRate, (v) {
            setState(() => _aosSlowRate = v);
            _saveAphasiaApraxia();
          }),
          _yesNo('Distorted substitutions', _aosDistortedSubst, (v) {
            setState(() => _aosDistortedSubst = v);
            _saveAphasiaApraxia();
          }),
          _yesNo('Trial-and-error articulatory attempts',
              _aosTrialAndError, (v) {
            setState(() => _aosTrialAndError = v);
            _saveAphasiaApraxia();
          }),
          _yesNo('Awareness of errors', _aosAwarenessOfErrors, (v) {
            setState(() => _aosAwarenessOfErrors = v);
            _saveAphasiaApraxia();
          }),
          _textField('Diadochokinetic rate observation',
              _aosDdkObsCtrl, multi: true,
              onSave: _saveAphasiaApraxia),
          _singleChips('AOS severity',
              const ['Mild', 'Moderate', 'Severe'],
              _aosSeverity, (v) {
            setState(() => _aosSeverity = v);
            _saveAphasiaApraxia();
          }),
        ],
        const SizedBox(height: 8),
        _yesNo('Dysarthria screen', _dysarthriaScreen, (v) {
          setState(() => _dysarthriaScreen = v);
          _saveAphasiaApraxia();
        }),
        _multiChips('Comorbid features observed', const [
          'Right hemiplegia', 'Hemianopsia', 'Aphemia',
          'Buccofacial apraxia', 'Limb apraxia', 'None',
        ], _aaComorbidFeatures, (v, sel) {
          setState(() {
            if (sel) {
              _aaComorbidFeatures.add(v);
            } else {
              _aaComorbidFeatures.remove(v);
            }
          });
          _saveAphasiaApraxia();
        }),
        _textField('Aphasia + Apraxia notes', _aaNotesCtrl,
            multi: true, onSave: _saveAphasiaApraxia),
      ],
    );
  }

  Widget _section8bBody() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _numField('Glasgow Coma Scale at presentation',
            _tbiGcsAdmitCtrl, unit: '/15', onSave: _saveTbi),
        _textField('Current functional level / GCS notes',
            _tbiCurrentLevelCtrl, multi: true, onSave: _saveTbi),
        _numField('Galveston Orientation & Amnesia Test (GOAT)',
            _tbiGoatCtrl, unit: '/100', onSave: _saveTbi),
        _singleChips('Ranchos Los Amigos Level', const [
          'I (No response)', 'II (Generalized response)',
          'III (Localized response)', 'IV (Confused-agitated)',
          'V (Confused-inappropriate)', 'VI (Confused-appropriate)',
          'VII (Automatic-appropriate)', 'VIII (Purposeful-appropriate)',
        ], _tbiRanchosLevel, (v) {
          setState(() => _tbiRanchosLevel = v);
          _saveTbi();
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
          _saveTbi();
        }),
        _multiChips('Behavioral concerns', const [
          'Disinhibition', 'Apathy', 'Agitation', 'Confabulation',
          'Perseveration', 'Impulsivity',
        ], _tbiBehavioralConcerns, (v, sel) {
          setState(() {
            if (sel) {
              _tbiBehavioralConcerns.add(v);
            } else {
              _tbiBehavioralConcerns.remove(v);
            }
          });
          _saveTbi();
        }),
        _numField('FIM communication subscale', _tbiFimCommCtrl,
            unit: '/7', onSave: _saveTbi),
        _textField('TBI notes', _tbiNotesCtrl,
            multi: true, onSave: _saveTbi),
      ],
    );
  }

  Widget _section8cBody() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _numField('MIRBI total', _rhdMirbiCtrl,
            unit: 'raw', onSave: _saveRhd),
        _multiChips('Pragmatic deficits', const [
          'Prosody comprehension', 'Prosody production',
          'Inferencing', 'Sarcasm/humor', 'Topic shifting',
          'Verbose output', 'Tangential speech',
          'Pragmatic awareness reduced',
        ], _rhdPragmaticDeficits, (v, sel) {
          setState(() {
            if (sel) {
              _rhdPragmaticDeficits.add(v);
            } else {
              _rhdPragmaticDeficits.remove(v);
            }
          });
          _saveRhd();
        }),
        _yesNo('Visuospatial neglect', _rhdNeglect, (v) {
          setState(() => _rhdNeglect = v);
          _saveRhd();
        }),
        _yesNo('Anosognosia (lack of awareness of deficits)',
            _rhdAnosognosia, (v) {
          setState(() => _rhdAnosognosia = v);
          _saveRhd();
        }),
        _singleChips('Affective communication',
            const ['Aprosodic', 'Hyperprosodic', 'Within normal limits'],
            _rhdAffectiveComm, (v) {
          setState(() => _rhdAffectiveComm = v);
          _saveRhd();
        }),
        _singleChips('Discourse profile', const [
          'Excessive detail', 'Tangential', 'Reduced informativeness',
          'Disorganized', 'Within normal limits',
        ], _rhdDiscourseProfile, (v) {
          setState(() => _rhdDiscourseProfile = v);
          _saveRhd();
        }),
        _textField('RHD notes', _rhdNotesCtrl,
            multi: true, onSave: _saveRhd),
      ],
    );
  }

  Widget _section8dBody() {
    final mocaT = _mocaTotal();
    final mmseT = _mmseTotal();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _singleChips('Dementia subtype', const [
          "Alzheimer's", 'Vascular', 'Lewy body', 'FTD',
          'Mixed', 'Unknown', 'MCI (not yet dementia)',
        ], _dementiaSubtype, (v) {
          setState(() => _dementiaSubtype = v);
          _saveDementia();
        }),
        _ghostNote(
            'MoCA total: $mocaT / 30  ·  MMSE total: $mmseT / 30  (from Section 3)'),
        _multiChips('Memory profile', const [
          'Episodic preserved', 'Episodic impaired',
          'Semantic preserved', 'Semantic impaired',
          'Working memory preserved', 'Working memory impaired',
        ], _dementiaMemoryProfile, (v, sel) {
          setState(() {
            if (sel) {
              _dementiaMemoryProfile.add(v);
            } else {
              _dementiaMemoryProfile.remove(v);
            }
          });
          _saveDementia();
        }),
        _textField('Language profile decline pattern',
            _dementiaLanguagePatternCtrl, multi: true,
            onSave: _saveDementia),
        _textField('Differential reasoning (AD vs vascular vs Lewy vs FTD)',
            _dementiaDifferentialCtrl, multi: true,
            onSave: _saveDementia),
        _textField('Caregiver-reported timeline of decline',
            _dementiaTimelineCtrl, multi: true,
            onSave: _saveDementia),
        _textField('Dementia notes', _dementiaNotesCtrl,
            multi: true, onSave: _saveDementia),
      ],
    );
  }

  Widget _section8eBody() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _singleChips('PPA subtype', const [
          'Semantic variant',
          'Nonfluent (agrammatic) variant',
          'Logopenic variant',
        ], _ppaSubtype, (v) {
          setState(() => _ppaSubtype = v);
          _savePpa();
        }),
        _textField('Onset and progression timeline',
            _ppaTimelineCtrl, multi: true, onSave: _savePpa),
        if (_ppaSubtype == 'Semantic variant')
          _multiChips('Semantic variant features', const [
            'Loss of single-word meaning', 'Surface dyslexia',
            'Reduced confrontation naming',
            'Impaired single-word comprehension',
            'Object recognition deficits',
            'Spared repetition',
          ], _ppaSemanticFeatures, (v, sel) {
            setState(() {
              if (sel) {
                _ppaSemanticFeatures.add(v);
              } else {
                _ppaSemanticFeatures.remove(v);
              }
            });
            _savePpa();
          }),
        if (_ppaSubtype == 'Nonfluent (agrammatic) variant')
          _multiChips('Nonfluent variant features', const [
            'Effortful speech', 'Apraxia of speech', 'Agrammatism',
            'Phonemic paraphasias',
            'Spared comprehension of single words',
          ], _ppaNonfluentFeatures, (v, sel) {
            setState(() {
              if (sel) {
                _ppaNonfluentFeatures.add(v);
              } else {
                _ppaNonfluentFeatures.remove(v);
              }
            });
            _savePpa();
          }),
        if (_ppaSubtype == 'Logopenic variant')
          _multiChips('Logopenic variant features', const [
            'Impaired single-word retrieval in spontaneous speech',
            'Impaired sentence repetition',
            'Phonological errors',
            'Spared single-word comprehension',
            'Spared object knowledge',
          ], _ppaLogopenicFeatures, (v, sel) {
            setState(() {
              if (sel) {
                _ppaLogopenicFeatures.add(v);
              } else {
                _ppaLogopenicFeatures.remove(v);
              }
            });
            _savePpa();
          }),
        _textField('Differential from typical aphasia',
            _ppaDifferentialCtrl, multi: true, onSave: _savePpa),
        _textField('PPA notes', _ppaNotesCtrl,
            multi: true, onSave: _savePpa),
      ],
    );
  }

  Widget _section8fBody() {
    final testedLanguageNames = _langTests
        .map((t) => t.language ?? '')
        .where((s) => s.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _groupLabel('Languages tested'),
        for (var i = 0; i < _langTests.length; i++) _langTestRow(i),
        Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: OutlinedButton.icon(
            onPressed: () {
              setState(() => _langTests.add(_LangTestEntry()));
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
        _multiChips('Cross-linguistic profile', const [
          'Parallel impairment (similar across languages)',
          'Differential aphasia (one language more impaired)',
          'Selective recovery (one language recovered more)',
          'Pathological switching',
          'Translation difficulties',
          'Language mixing increased post-injury',
        ], _crossLinguisticProfile, (v, sel) {
          setState(() {
            if (sel) {
              _crossLinguisticProfile.add(v);
            } else {
              _crossLinguisticProfile.remove(v);
            }
          });
          _saveMultilingual();
        }),
        _singleChips('Most preserved language for therapy',
            testedLanguageNames, _mostPreservedLanguage, (v) {
          setState(() => _mostPreservedLanguage = v);
          _saveMultilingual();
        }),
        _singleChips('Code-switching post-injury', const [
          'Reduced from premorbid', 'Similar to premorbid',
          'Increased / pathological',
        ], _codeSwitchingPostInjury, (v) {
          setState(() => _codeSwitchingPostInjury = v);
          _saveMultilingual();
        }),
        _textField(
          'Culturally-relevant assessment notes',
          _culturalAssessNotesCtrl, multi: true,
          hint: 'kinship terms, religious vocabulary, regional idioms',
          onSave: _saveMultilingual,
        ),
        _singleChips('Treatment language recommendation',
            testedLanguageNames, _multilingualTxLanguage, (v) {
          setState(() => _multilingualTxLanguage = v);
          _saveMultilingual();
        }),
        _textField('Multilingual notes', _multilingualNotesCtrl,
            multi: true, onSave: _saveMultilingual),
      ],
    );
  }

  Widget _langTestRow(int index) {
    final lt = _langTests[index];
    final premorbidLanguages = _languages
        .map((e) => e.nameCtrl.text.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: _tealSoft.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('Language test #${index + 1}',
                    style: GoogleFonts.dmSans(
                        fontSize: 12, color: _ink,
                        fontWeight: FontWeight.w600)),
              ),
              if (_langTests.length > 1)
                IconButton(
                  onPressed: () {
                    final removed = _langTests.removeAt(index);
                    removed.dispose();
                    setState(() {});
                    _saveMultilingual();
                  },
                  icon: const Icon(Icons.close_rounded,
                      size: 16, color: _inkGhost),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                      minWidth: 24, minHeight: 24),
                ),
            ],
          ),
          const SizedBox(height: 6),
          _singleChips(
            'Language',
            premorbidLanguages.isEmpty
                ? const ['L1', 'L2', 'L3']
                : premorbidLanguages,
            lt.language,
            (v) {
              setState(() => lt.language = v);
              _saveMultilingual();
            },
          ),
          _numField('WAB AQ in this language', lt.wabAqCtrl,
              unit: '/100', onSave: _saveMultilingual),
          _singleChips('Conversational fluency',
              _kSeverityScale, lt.convoFluency, (v) {
            setState(() => lt.convoFluency = v);
            _saveMultilingual();
          }),
          _singleChips('Naming', _kSeverityScale,
              lt.naming, (v) {
            setState(() => lt.naming = v);
            _saveMultilingual();
          }),
          _singleChips('Comprehension', _kSeverityScale,
              lt.comprehension, (v) {
            setState(() => lt.comprehension = v);
            _saveMultilingual();
          }),
          _singleChips('Reading', _kSeverityScale,
              lt.reading, (v) {
            setState(() => lt.reading = v);
            _saveMultilingual();
          }),
          _singleChips('Writing', _kSeverityScale,
              lt.writing, (v) {
            setState(() => lt.writing = v);
            _saveMultilingual();
          }),
        ],
      ),
    );
  }

  // ── Section 9 body — Cognitive-Communication Screen ───────────────
  Widget _section9Body() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _groupLabel('A · Attention'),
        _singleChips('Sustained attention', _kFunctionScale,
            _attnSustained, (v) {
          setState(() => _attnSustained = v);
          _saveCogComm();
        }),
        _singleChips('Selective attention', _kFunctionScale,
            _attnSelective, (v) {
          setState(() => _attnSelective = v);
          _saveCogComm();
        }),
        _singleChips('Divided attention', _kFunctionScale,
            _attnDivided, (v) {
          setState(() => _attnDivided = v);
          _saveCogComm();
        }),
        _textField('Attention notes', _attnNotesCtrl,
            multi: true, onSave: _saveCogComm),

        const SizedBox(height: 14),
        _groupLabel('B · Memory'),
        _singleChips('Immediate memory', _kFunctionScale,
            _memImmediate, (v) {
          setState(() => _memImmediate = v);
          _saveCogComm();
        }),
        _singleChips('Recent memory', _kFunctionScale,
            _memRecent, (v) {
          setState(() => _memRecent = v);
          _saveCogComm();
        }),
        _singleChips('Remote memory', _kFunctionScale,
            _memRemote, (v) {
          setState(() => _memRemote = v);
          _saveCogComm();
        }),
        _singleChips('Working memory', _kFunctionScale,
            _memWorking, (v) {
          setState(() => _memWorking = v);
          _saveCogComm();
        }),
        _multiChips('Memory screening tools used', const [
          'RBANS', 'Wechsler Memory Scale', 'Informal', 'None',
        ], _memToolsUsed, (v, sel) {
          setState(() {
            if (sel) {
              _memToolsUsed.add(v);
            } else {
              _memToolsUsed.remove(v);
            }
          });
          _saveCogComm();
        }),

        const SizedBox(height: 14),
        _groupLabel('C · Executive Function'),
        _singleChips('Planning', _kFunctionScale,
            _execPlanning, (v) {
          setState(() => _execPlanning = v);
          _saveCogComm();
        }),
        _singleChips('Problem-solving', _kFunctionScale,
            _execProblemSolving, (v) {
          setState(() => _execProblemSolving = v);
          _saveCogComm();
        }),
        _singleChips('Mental flexibility / set-shifting',
            _kFunctionScale, _execFlexibility, (v) {
          setState(() => _execFlexibility = v);
          _saveCogComm();
        }),
        _singleChips('Inhibition', _kFunctionScale,
            _execInhibition, (v) {
          setState(() => _execInhibition = v);
          _saveCogComm();
        }),
        _singleChips('Initiation', _kFunctionScale,
            _execInitiation, (v) {
          setState(() => _execInitiation = v);
          _saveCogComm();
        }),
        _textField('Executive function notes', _execNotesCtrl,
            multi: true, onSave: _saveCogComm),

        const SizedBox(height: 14),
        _groupLabel('D · Reasoning & Abstract Thinking'),
        _singleChips('Concrete vs abstract',
            const ['Intact abstract', 'Concrete', 'Severely concrete'],
            _reasoningAbstract, (v) {
          setState(() => _reasoningAbstract = v);
          _saveCogComm();
        }),
        _singleChips('Categorization', _kFunctionScale,
            _reasoningCategorization, (v) {
          setState(() => _reasoningCategorization = v);
          _saveCogComm();
        }),
        _singleChips('Sequencing', _kFunctionScale,
            _reasoningSequencing, (v) {
          setState(() => _reasoningSequencing = v);
          _saveCogComm();
        }),

        const SizedBox(height: 14),
        _groupLabel('E · Pragmatic Awareness'),
        _singleChips('Insight into communication impairment', const [
          'Full', 'Partial', 'Limited', 'Absent (anosognosia)',
        ], _pragInsight, (v) {
          setState(() => _pragInsight = v);
          _saveCogComm();
        }),
        _singleChips('Social use of language', _kFunctionScale,
            _pragSocialUse, (v) {
          setState(() => _pragSocialUse = v);
          _saveCogComm();
        }),
        _singleChips('Awareness of conversational partner',
            _kFunctionScale, _pragAwarenessPartner, (v) {
          setState(() => _pragAwarenessPartner = v);
          _saveCogComm();
        }),

        const SizedBox(height: 14),
        _groupLabel('F · Cognitive screen tools used'),
        _multiChips('Tools', const [
          'SCATBI', 'RBANS', 'CLQT', 'Cognistat',
          'ACE-III', 'Informal observation only',
        ], _cogScreenToolsUsed, (v, sel) {
          setState(() {
            if (sel) {
              _cogScreenToolsUsed.add(v);
            } else {
              _cogScreenToolsUsed.remove(v);
            }
          });
          _saveCogComm();
        }),
      ],
    );
  }

  // ── Section 10 body — Differential Diagnosis ──────────────────────
  Widget _section10Body() {
    final autoEtio = _ddOverrideEtiology
        ? (_ddEtiologyOverride ?? '—')
        : (_etiology ?? 'Pick in Section 1');
    final wabType = _aphasiaTypeOverride ?? _autoAphasiaType() ?? '—';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _groupLabel('A · Primary diagnosis'),
        _textField('Primary diagnosis (working hypothesis)',
            _ddPrimaryDxCtrl, multi: true,
            onSave: _saveDifferentialDx),
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            children: [
              Text('Aphasia type (auto from WAB): ',
                  style: GoogleFonts.dmSans(
                      fontSize: 12, color: _inkGhost)),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: _tealSoft.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _teal.withValues(alpha: 0.4)),
                ),
                child: Text(wabType,
                    style: GoogleFonts.dmSans(
                        fontSize: 12, color: _teal,
                        fontWeight: FontWeight.w500)),
              ),
            ],
          ),
        ),

        const SizedBox(height: 14),
        _groupLabel('B · Etiology category'),
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: _tealSoft.withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: _teal.withValues(alpha: 0.4)),
            ),
            child: Text(autoEtio,
                style: GoogleFonts.dmSans(
                    fontSize: 12, color: _teal,
                    fontWeight: FontWeight.w500)),
          ),
        ),
        _yesNo('Override etiology?', _ddOverrideEtiology, (v) {
          setState(() => _ddOverrideEtiology = v);
          _saveDifferentialDx();
        }),
        if (_ddOverrideEtiology)
          _singleChips('Override etiology value', const [
            'Stroke (ischemic)', 'Stroke (hemorrhagic)',
            'TBI (closed)', 'TBI (penetrating)',
            "Dementia (Alzheimer's)", 'Dementia (vascular)',
            'Dementia (Lewy body)', 'Dementia (FTD)',
            'Dementia (mixed)',
            'PPA (semantic)', 'PPA (nonfluent)', 'PPA (logopenic)',
            'Encephalitis', 'Tumor', 'Other', 'Unknown',
          ], _ddEtiologyOverride, (v) {
            setState(() => _ddEtiologyOverride = v);
            _saveDifferentialDx();
          }),

        const SizedBox(height: 14),
        _groupLabel('C · Rule-outs to consider'),
        for (var i = 0; i < _ddRuleOutCtrls.length; i++)
          _ddRuleOutRow(i),
        Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: OutlinedButton.icon(
            onPressed: () {
              setState(() =>
                  _ddRuleOutCtrls.add(TextEditingController()));
            },
            icon: const Icon(Icons.add_rounded, size: 14),
            label: Text('Add rule-out',
                style: GoogleFonts.dmSans(fontSize: 12, color: _teal)),
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: _teal.withValues(alpha: 0.45)),
              padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 6),
            ),
          ),
        ),

        _groupLabel('D · Contributing factors'),
        _multiChips('Factors', const [
          'Educational level', 'Premorbid cognitive function',
          'Hearing loss', 'Vision impairment', 'Depression',
          'Anxiety', 'Fatigue', 'Medication side effects',
          'Reduced social engagement',
          'Cultural-linguistic mismatch', 'Other',
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
        if (_ddContributingFactors.contains('Other'))
          _textField('Other contributing factors',
              _ddOtherContribCtrl, multi: true,
              onSave: _saveDifferentialDx),

        const SizedBox(height: 14),
        _groupLabel('E · Synthesis'),
        _textField('Differential reasoning — why this diagnosis over others',
            _ddSynthesisCtrl, multi: true,
            onSave: _saveDifferentialDx),
      ],
    );
  }

  Widget _ddRuleOutRow(int index) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: Focus(
              onFocusChange: (f) {
                if (!f) _saveDifferentialDx();
              },
              child: TextField(
                controller: _ddRuleOutCtrls[index],
                style: GoogleFonts.dmSans(fontSize: 13, color: _ink),
                decoration: InputDecoration(
                  hintText: 'Rule-out #${index + 1}',
                  hintStyle: GoogleFonts.dmSans(
                      fontSize: 12,
                      color: _inkGhost.withValues(alpha: 0.6)),
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ),
          ),
          if (_ddRuleOutCtrls.length > 3)
            IconButton(
              onPressed: () {
                final removed = _ddRuleOutCtrls.removeAt(index);
                removed.dispose();
                setState(() {});
                _saveDifferentialDx();
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

  // ── Section 12 body — Functional Communication & QoL ──────────────
  Widget _section12Body() {
    final coast = _coastItems.isEmpty
        ? null
        : _coastItems.values.fold<int>(0, (a, b) => a + b);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _groupLabel('A · COAST (1 None – 5 Severe)'),
        for (var i = 1; i <= 20; i++)
          _likertRow('$i. COAST item $i',
              value: _coastItems[i] ?? 1,
              min: 1, max: 5,
              onChanged: (v) {
                setState(() => _coastItems[i] = v);
              },
              onCommit: _saveQol),
        const SizedBox(height: 6),
        _qolBadge(
          label: 'COAST total',
          total: coast ?? 0,
          maxScore: 100,
        ),
        _ghostNote('Lower total = better functional communication.'),
        if (_coastTotalLoaded != null && _coastTotalLoaded != coast) ...[
          const SizedBox(height: 4),
          Text('Last saved total: $_coastTotalLoaded',
              style: GoogleFonts.dmSans(
                  fontSize: 11, color: _inkGhost,
                  fontStyle: FontStyle.italic)),
        ],

        const SizedBox(height: 14),
        _groupLabel('B · AIQ-21 (Aphasia Impact Questionnaire)'),
        _yesNo('Use AIQ-21?', _useAiq21, (v) {
          setState(() => _useAiq21 = v);
          _saveQol();
        }),
        if (_useAiq21) ...[
          for (var i = 1; i <= 21; i++)
            _likertRow(
                '$i. AIQ-21 ${i <= 7 ? "C$i" : i <= 14 ? "P${i - 7}" : "E${i - 14}"}',
                value: _aiq21Items[i] ?? 1,
                min: 1, max: 5,
                onChanged: (v) {
                  setState(() => _aiq21Items[i] = v);
                },
                onCommit: _saveQol),
          _qolBadge(
            label: 'AIQ-21 total',
            total: _aiq21Items.values.fold<int>(0, (a, b) => a + b),
            maxScore: 105,
          ),
          _ghostNote('Higher = greater impact.'),
          if (_aiq21TotalLoaded != null &&
              _aiq21TotalLoaded !=
                  _aiq21Items.values.fold<int>(0, (a, b) => a + b)) ...[
            const SizedBox(height: 4),
            Text('Last saved total: $_aiq21TotalLoaded',
                style: GoogleFonts.dmSans(
                    fontSize: 11, color: _inkGhost,
                    fontStyle: FontStyle.italic)),
          ],
        ],

        const SizedBox(height: 14),
        _groupLabel('C · SAQOL-39 (Stroke and Aphasia QoL)'),
        _yesNo('Use SAQOL-39?', _useSaqol, (v) {
          setState(() => _useSaqol = v);
          _saveQol();
        }),
        if (_useSaqol) ...[
          for (var i = 1; i <= 39; i++)
            _likertRow('$i. SAQOL-39 item $i',
                value: _saqolItems[i] ?? 1,
                min: 1, max: 5,
                onChanged: (v) {
                  setState(() => _saqolItems[i] = v);
                },
                onCommit: _saveQol),
          _qolBadge(
            label: 'SAQOL-39 total',
            total: _saqolItems.values.fold<int>(0, (a, b) => a + b),
            maxScore: 195,
          ),
          if (_saqolTotalLoaded != null &&
              _saqolTotalLoaded !=
                  _saqolItems.values.fold<int>(0, (a, b) => a + b)) ...[
            const SizedBox(height: 4),
            Text('Last saved total: $_saqolTotalLoaded',
                style: GoogleFonts.dmSans(
                    fontSize: 11, color: _inkGhost,
                    fontStyle: FontStyle.italic)),
          ],
        ],

        const SizedBox(height: 14),
        _groupLabel('D · CETI (Communicative Effectiveness Index)'),
        _yesNo('CETI completed by caregiver?', _useCeti, (v) {
          setState(() => _useCeti = v);
          _saveQol();
        }),
        if (_useCeti) ...[
          for (var i = 1; i <= 16; i++)
            _likertRow('$i. CETI item $i',
                value: _cetiItems[i] ?? 0,
                min: 0, max: 100,
                onChanged: (v) {
                  setState(() => _cetiItems[i] = v);
                },
                onCommit: _saveQol),
          _qolBadge(
            label: 'CETI total',
            total: _cetiItems.values.fold<int>(0, (a, b) => a + b),
            maxScore: 1600,
          ),
          _ghostNote(
              "Caregiver perception of patient's communication effectiveness."),
          if (_cetiTotalLoaded != null &&
              _cetiTotalLoaded !=
                  _cetiItems.values.fold<int>(0, (a, b) => a + b)) ...[
            const SizedBox(height: 4),
            Text('Last saved total: $_cetiTotalLoaded',
                style: GoogleFonts.dmSans(
                    fontSize: 11, color: _inkGhost,
                    fontStyle: FontStyle.italic)),
          ],
        ],
      ],
    );
  }

  /// 0–N (or 1–N) Likert slider row with a live readout. Used by
  /// Section 12's four QoL instruments. Same pattern voice's 24c
  /// VHI uses; max can run up to 100 (CETI VAS).
  Widget _likertRow(
    String label, {
    required int value,
    required int min,
    required int max,
    required ValueChanged<int> onChanged,
    required VoidCallback onCommit,
  }) {
    final divisions = max - min;
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
                        fontSize: 12, color: _ink)),
              ),
              Text('$value',
                  style: GoogleFonts.dmSans(
                      fontSize: 12, color: _ink,
                      fontWeight: FontWeight.w600)),
              Text(' / $max',
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
              value: value.toDouble().clamp(min.toDouble(), max.toDouble()),
              min: min.toDouble(),
              max: max.toDouble(),
              divisions: divisions,
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
    final wabType = _aphasiaTypeOverride ?? _autoAphasiaType() ?? '—';
    final autoEtio = _ddOverrideEtiology
        ? (_ddEtiologyOverride ?? '—')
        : (_etiology ?? '—');
    final aq = _wabAphasiaQuotient();
    final aqBand = aq == null ? '—' : _aqSeverityBand(aq);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _groupLabel('A · Final diagnosis'),
        _textField('Final diagnosis', _ciFinalDxCtrl,
            multi: true, onSave: _saveClinicalImpression),
        _textField('ICD-style code', _ciIcdCodeCtrl,
            hint: 'e.g. R47.01 Aphasia, F03 Unspecified Dementia, R47.81 Slurred speech',
            onSave: _saveClinicalImpression),
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            children: [
              Text('Aphasia type (auto from WAB): ',
                  style: GoogleFonts.dmSans(
                      fontSize: 12, color: _inkGhost)),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: _tealSoft.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _teal.withValues(alpha: 0.4)),
                ),
                child: Text(wabType,
                    style: GoogleFonts.dmSans(
                        fontSize: 12, color: _teal,
                        fontWeight: FontWeight.w500)),
              ),
            ],
          ),
        ),

        const SizedBox(height: 14),
        _groupLabel('B · Severity'),
        _singleChips('Severity grading',
            const ['Mild', 'Moderate', 'Severe', 'Profound'],
            _ciSeverity, (v) {
          setState(() => _ciSeverity = v);
          _saveClinicalImpression();
        }),
        _ghostNote(
            'Auto-suggested from WAB AQ ($aqBand): ≥75 Mild, 50–75 Moderate, 25–50 Mod-Severe, < 25 Severe.'),
        _textField('Severity rationale', _ciSeverityRationaleCtrl,
            multi: true, onSave: _saveClinicalImpression),

        const SizedBox(height: 14),
        _groupLabel('C · Etiology'),
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: _tealSoft.withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: _teal.withValues(alpha: 0.4)),
            ),
            child: Text(autoEtio,
                style: GoogleFonts.dmSans(
                    fontSize: 12, color: _teal,
                    fontWeight: FontWeight.w500)),
          ),
        ),

        const SizedBox(height: 14),
        _groupLabel('D · Prognosis'),
        _singleChips('Prognosis',
            const ['Good', 'Fair', 'Guarded', 'Poor'],
            _ciPrognosis, (v) {
          setState(() => _ciPrognosis = v);
          _saveClinicalImpression();
        }),
        _ghostNote(
            'Consider: time post-onset, lesion size, premorbid abilities, family support, motivation, comorbidities.'),
        _textField('Prognostic rationale', _ciPrognosticRationaleCtrl,
            multi: true, onSave: _saveClinicalImpression),

        const SizedBox(height: 14),
        _groupLabel('E · Management plan'),
        _multiChips('Recommended interventions', const [
          'Aphasia therapy', 'Cognitive-communication therapy',
          'AOS treatment (if applicable)', 'AAC consideration',
          'Caregiver training', 'Group therapy referral',
          'Computer-based home practice', 'Multilingual therapy',
          'Constraint-induced therapy (CIAT)',
          'Script training',
          'Semantic Feature Analysis (SFA)',
          'Verb Network Strengthening (VNeST)',
          'Melodic Intonation Therapy (MIT)',
          'Response Elaboration Training', 'Other',
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
        _textField('Therapy approach details',
            _ciTherapyApproachCtrl, multi: true,
            onSave: _saveClinicalImpression),
        _numField('Estimated session count', _ciSessionCountCtrl,
            unit: 'sessions', onSave: _saveClinicalImpression),
        _singleChips('Frequency', const [
          'Twice weekly', 'Weekly', 'Biweekly', 'Monthly', 'As needed',
        ], _ciFrequency, (v) {
          setState(() => _ciFrequency = v);
          _saveClinicalImpression();
        }),
        _numField('Session duration', _ciSessionDurationCtrl,
            unit: 'min', onSave: _saveClinicalImpression),
        _textField('Discharge criteria / outcome targets',
            _ciDischargeCriteriaCtrl, multi: true,
            onSave: _saveClinicalImpression),

        const SizedBox(height: 14),
        _groupLabel('F · Referrals'),
        _multiChips('Referrals needed', const [
          'Neurology', 'Psychiatry', 'Neuropsychology',
          'Audiology', 'Physiotherapy', 'Occupational therapy',
          'Social work', 'Support group', 'Caregiver counseling',
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
        _textField('Referral notes', _ciReferralNotesCtrl,
            multi: true, onSave: _saveClinicalImpression),

        const SizedBox(height: 14),
        _groupLabel('G · Caregiver education priorities'),
        _multiChips('Education topics', const [
          'Communication strategies', 'Aphasia education',
          'Behavior management', 'AAC training',
          'Home practice support',
          'Cultural-linguistic considerations',
          'Local resources', 'Aphasia association referral',
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
        _groupLabel('H · Functional outcome targets'),
        _textField(
          'Specific functional goals',
          _ciFunctionalOutcomesCtrl, multi: true,
          hint: 'e.g. phone use, return to work, conversational independence',
          onSave: _saveClinicalImpression,
        ),
      ],
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
                firstDate: DateTime(1990),
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

  Widget _intSlider(String label, int value, int min, int max,
      ValueChanged<int> onChanged, VoidCallback onCommit) {
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
                        fontSize: 12, color: _inkGhost,
                        fontWeight: FontWeight.w500)),
              ),
              Text('$value',
                  style: GoogleFonts.dmSans(
                      fontSize: 13, color: _ink,
                      fontWeight: FontWeight.w600)),
              Text(' / $max',
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
              value: value.toDouble().clamp(min.toDouble(), max.toDouble()),
              min: min.toDouble(),
              max: max.toDouble(),
              divisions: max - min,
              onChanged: (d) => onChanged(d.toInt()),
              onChangeEnd: (_) => onCommit(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _qolBadge({
    required String label,
    required int total,
    required int maxScore,
    bool flagged = false,
    String? flagText,
  }) {
    final color = flagged ? _amber : _teal;
    final bg = flagged ? _amberSoft : _tealSoft;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      decoration: BoxDecoration(
        color: bg.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$label: $total / $maxScore',
              style: GoogleFonts.dmSans(
                  fontSize: 13, color: color,
                  fontWeight: FontWeight.w600)),
          if (flagged && flagText != null) ...[
            const SizedBox(height: 2),
            Text(flagText,
                style: GoogleFonts.dmSans(
                    fontSize: 11, color: color,
                    fontStyle: FontStyle.italic)),
          ],
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

// 25c — shared severity / function scales used by Section 8F per-language
// rows and Section 9 cog-comm subscales. Top-level constants so the
// `const` literal sites in `_singleChips(...)` calls compile cheaply.
const List<String> _kFunctionScale = [
  'Adequate',
  'Mildly reduced',
  'Significantly reduced',
  'Unable to assess',
];

const List<String> _kSeverityScale = [
  'Preserved',
  'Mildly impaired',
  'Moderately impaired',
  'Severely impaired',
  'Unable',
];

/// One row in the Section 8F "Languages tested" list builder. Holds the
/// per-language picks that drive the cross-linguistic profile + treatment
/// language recommendation downstream.
class _LangTestEntry {
  String? language;
  final TextEditingController wabAqCtrl;
  String? convoFluency;
  String? naming;
  String? comprehension;
  String? reading;
  String? writing;

  _LangTestEntry({
    this.language,
    String wabAq = '',
    this.convoFluency,
    this.naming,
    this.comprehension,
    this.reading,
    this.writing,
  }) : wabAqCtrl = TextEditingController(text: wabAq);

  void dispose() {
    wabAqCtrl.dispose();
  }
}

/// One row in the Section 1 "Languages spoken" list builder.
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
}
