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
    ];
    for (final c in controllers) {
      c.dispose();
    }
    for (final lang in _languages) {
      lang.nameCtrl.dispose();
      lang.acquisitionAgeCtrl.dispose();
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
        _service.compareBaselineToLatest(widget.clientId),
      ]);
      _hydrateWab(results[0] as Map<String, dynamic>);
      _hydrateCognitive(results[1] as Map<String, dynamic>);
      if (!mounted) return;
      setState(() {
        _assessment = a;
        _outcome    = results[2] as OutcomeComparison;
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
        _stub(4,  'Naming & Word Retrieval',
            'BNT, action naming, verbal fluency, error profile, cuing.', '4.0.7.25b'),
        const SizedBox(height: 10),
        _stub(5,  'Auditory Comprehension',
            'Token Test, complex sentence comprehension, working memory.', '4.0.7.25b'),
        const SizedBox(height: 10),
        _stub(6,  'Reading & Writing',
            'Word + sentence + paragraph reading, copy / dictation / generative writing.', '4.0.7.25b'),
        const SizedBox(height: 10),
        _stub(7,  'Discourse & Functional Communication',
            'Picture description, narrative, conversational sample, content units.', '4.0.7.25b'),
        const SizedBox(height: 10),
        _stub(8,  'Etiology-Specific Subforms',
            '6 conditional subforms based on etiology — aphasia + apraxia, TBI, RHD, dementia, PPA, multilingual.',
            '4.0.7.25c'),
        const SizedBox(height: 10),
        _stub(9,  'Cognitive-Communication Screen',
            'Executive function, social cognition, pragmatic deficits.', '4.0.7.25c'),
        const SizedBox(height: 10),
        _stub(10, 'Differential Diagnosis',
            'Aphasia type, working hypothesis, rule-outs, contributors.', '4.0.7.25c'),
        const SizedBox(height: 10),
        _section(id: 'sec11', number: 11, title: 'Outcome Tracking',
            tagline: 'Baseline vs most recent follow-up across all measures.',
            child: _section11Body()),
        const SizedBox(height: 10),
        _stub(12, 'Functional Communication & QoL',
            'COAST, AIQ-21, SAQOL-39, CETI self-report.', '4.0.7.25c'),
        const SizedBox(height: 10),
        _stub(15, 'Final Clinical Impression & Plan',
            'Diagnosis, severity, plan, referrals, attestation.', '4.0.7.25c'),
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
