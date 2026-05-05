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
        _service.compareBaselineToLatest(widget.clientId),
      ]);
      _hydrateIntelligibility(results[0] as Map<String, dynamic>);
      if (!mounted) return;
      setState(() {
        _assessment = a;
        _outcome    = results[1] as OutcomeComparison;
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
    seed('listener_familiar_caregivers_pct', 'familiar_caregivers');
    seed('listener_family_pct',              'family_non_primary');
    seed('listener_peers_pct',               'peers');
    seed('listener_teachers_pct',            'teachers');
    seed('listener_unfamiliar_adults_pct',   'unfamiliar_adults');
    seed('context_familiar_pct',             'familiar_contexts');
    seed('context_unfamiliar_pct',           'unfamiliar_contexts');
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
      'receptive_language_age_source': _receptiveAgeSource,
      'expressive_language_age_months': _parseInt(_expressiveAgeCtrl.text),
      'expressive_language_age_source': _expressiveAgeSource,
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
      'mayo_type':                     _mayoType,
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
        _stub(4,  'Five Speech Subsystems',
            'Respiration, phonation, articulation, resonance, prosody — typed measures.',
            '4.0.7.27b'),
        const SizedBox(height: 10),
        _stub(5,  'Oral Mech Examination',
            'Lip / tongue / jaw / palate / dentition — structure + function.',
            '4.0.7.27b'),
        const SizedBox(height: 10),
        _stub(6,  'Connected Speech & Intelligibility',
            'CSIM single-word + sentence, ICS, words per minute.',
            '4.0.7.27b'),
        const SizedBox(height: 10),
        _stub(7,  'Stimulability & Therapy Trial',
            'Cuing response, prosthetic / behavioral compensations.',
            '4.0.7.27b'),
        const SizedBox(height: 10),
        _stub(8,  'Etiology-Specific Subforms',
            'CP, post-encephalitis, post-TBI, genetic syndrome, pediatric stroke.',
            '4.0.7.27c'),
        const SizedBox(height: 10),
        _stub(9,  'Functional Communication Screen',
            'Setting-specific intelligibility tracked over time, peer use.',
            '4.0.7.27c'),
        const SizedBox(height: 10),
        _stub(10, 'Differential Diagnosis',
            'Mayo type, working hypothesis, dysarthria-vs-CAS rule-outs.',
            '4.0.7.27c'),
        const SizedBox(height: 10),
        _section(id: 'sec11', number: 11, title: 'Outcome Tracking',
            tagline: 'Baseline vs most recent follow-up across all measures.',
            child: _section11Body()),
        const SizedBox(height: 10),
        _stub(12, 'Functional Communication & QoL',
            'FOCUS-34, parent / teacher / peer ratings.',
            '4.0.7.27c'),
        const SizedBox(height: 10),
        _stub(15, 'Final Clinical Impression & Plan',
            'Diagnosis, severity, plan, dysphagia + AAC referral toggles.',
            '4.0.7.27c'),
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
