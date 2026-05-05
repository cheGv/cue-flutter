// lib/widgets/assessment/voice_capture_section.dart
//
// Phase 4.0.7.24a / 24b — voice assessment surface. As of 24b the
// trimmed protocol Sections 1, 2, 4, 5, 6, 7, 11 are populated;
// Sections 8, 10, 12, 15 remain amber stubs queued for 4.0.7.24c.
//
// Skipped sections per the Indian-clinic protocol cut: 3 (Advanced
// Acoustic), 9 (Stimulability), 13 (Red Flags), 14 (Imaging).
//
// Save model:
//   - Sections 1, 2, 6, 7 PATCH a jsonb column on voice_assessments.
//   - Sections 4, 5 upsert into typed child tables
//     (voice_aerodynamic_measures, voice_perceptual_ratings) keyed
//     by voice_assessment_id.
// Each editable surface debounces on blur and writes its full payload
// (no field-level deltas). RSI total auto-recalculates whenever any
// of its 9 items change.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../models/voice_assessment.dart';
import '../../services/voice_assessment_service.dart';

const Color _ink       = Color(0xFF0E1C36);
const Color _inkGhost  = Color(0xFF6B7690);
const Color _line      = Color(0xFFE6DDCA);
const Color _teal      = Color(0xFF2A8F84);
const Color _tealSoft  = Color(0xFFD6E8E5);
const Color _amber     = Color(0xFFD68A2B);
const Color _amberSoft = Color(0xFFF4E4C4);
const Color _coral     = Color(0xFFC25450);
const Color _green     = Color(0xFF1F8870);

class VoiceCaptureSection extends StatefulWidget {
  final String  clientId;
  final String? visitId;
  const VoiceCaptureSection({
    super.key,
    required this.clientId,
    this.visitId,
  });

  @override
  State<VoiceCaptureSection> createState() => _VoiceCaptureSectionState();
}

class _VoiceCaptureSectionState extends State<VoiceCaptureSection> {
  final _service = VoiceAssessmentService.instance;

  VoiceAssessment? _assessment;
  bool _loading = true;
  String? _error;

  // Section 11 outcome rollup
  OutcomeComparison? _outcome;

  // Section 1 — Detailed Case History controllers
  final _onsetDateCtrl   = TextEditingController();
  final _variabilityCtrl = TextEditingController();
  final _aggravatorsCtrl = TextEditingController();
  final _relieversCtrl   = TextEditingController();
  final _prevTherapyCtrl = TextEditingController();
  final _prevSurgeryCtrl = TextEditingController();
  final _medsCtrl        = TextEditingController();
  final _allergyCtrl     = TextEditingController();
  final _psychLoadCtrl   = TextEditingController();
  final _voiceRestCtrl   = TextEditingController();
  final _hoursPerDayCtrl = TextEditingController();
  final _hydrationCtrl   = TextEditingController();
  final _caffeineCtrl    = TextEditingController();

  // Section 1 — chip / boolean state
  String? _onsetPattern;
  String? _sleepQuality;
  bool _prevTherapy = false;
  bool _prevSurgery = false;
  bool _microphoneAtWork = false;
  final Set<String> _speakingStyles = {};

  // RSI 0–5 sliders
  static const _rsiKeys = [
    'hoarseness', 'throat_clearing', 'mucus', 'swallowing',
    'cough_after_eating', 'breathing_choking', 'annoying_cough',
    'throat_lump', 'heartburn',
  ];
  final Map<String, int> _rsi = { for (final k in _rsiKeys) k: 0 };
  int get _rsiTotal => _rsi.values.fold(0, (a, b) => a + b);

  // Section 2 — Laryngeal Examination controllers
  final _performedByCtrl = TextEditingController();
  final _lesionNotesCtrl = TextEditingController();
  final _examNotesCtrl   = TextEditingController();

  String? _examType;
  DateTime? _examDate;
  final Set<String> _lesions = {};
  String? _mucosalAmplitude;
  String? _mucosalSymmetry;
  String? _glotticClosure;
  String? _supraglotticCompression;
  String? _phaseClosureSymmetry;

  // ── Section 4 (Aerodynamic + basic acoustic) — typed measures ────
  // Numeric fields stored as TextEditingControllers so empty input
  // serializes back to null. Field keys match
  // voice_aerodynamic_measures column names per the 24a migration.
  static const _aeroNumericKeys = [
    'mpt_seconds',
    's_z_ratio',
    'subglottal_pressure_estimated_cmh2o',
    'mean_airflow_rate_ml_per_sec',
    'phonation_threshold_pressure_cmh2o',
    'f0_mean_hz',
    'jitter_percent',
    'shimmer_percent',
    'hnr_db',
  ];
  late final Map<String, TextEditingController> _aeroCtrls = {
    for (final k in _aeroNumericKeys) k: TextEditingController(),
  };
  final _aeroNotesCtrl = TextEditingController();

  // ── Section 5 (Perceptual evaluation) — typed measures ───────────
  // CAPE-V scales 0–100 (sliders snap to integer). GRBAS scales 0–3
  // (chip picker). Empty rater defaults to 'primary_clinician' on
  // first save. Audio + multi-rater land in 4.0.7.24c.
  final _raterCtrl              = TextEditingController(text: 'primary_clinician');
  static const _capevSliderKeys = [
    'capev_overall_severity',
    'capev_roughness',
    'capev_breathiness',
    'capev_strain',
    'capev_pitch',
    'capev_loudness',
  ];
  final Map<String, int> _capev = {for (final k in _capevSliderKeys) k: 0};
  final _capevResonanceCtrl     = TextEditingController();
  static const _grbasKeys = [
    'grbas_grade',
    'grbas_roughness',
    'grbas_breathiness',
    'grbas_asthenia',
    'grbas_strain',
  ];
  final Map<String, int?> _grbas = {for (final k in _grbasKeys) k: null};
  final _perceptualNotesCtrl    = TextEditingController();

  // ── Section 6 (Functional voice) — narrative jsonb ──────────────
  final _readingPassageCtrl   = TextEditingController();
  final _passageUsedCtrl      = TextEditingController();
  final _convoSampleCtrl      = TextEditingController();
  final _sustainedQualityCtrl = TextEditingController();
  final _connectedQualityCtrl = TextEditingController();
  final _comparisonNotesCtrl  = TextEditingController();
  bool _fatigueTestConducted  = false;
  final _preLoadQualityCtrl   = TextEditingController();
  final _voiceLoadingTaskCtrl = TextEditingController();
  final _postLoadQualityCtrl  = TextEditingController();
  final _timeToFatigueCtrl    = TextEditingController();

  // ── Section 7 (Task-based voice) — narrative jsonb ──────────────
  final _maxLoudDbCtrl         = TextEditingController();
  final _loudQualityCtrl       = TextEditingController();
  bool _strainAtLoud           = false;
  final _minLoudDbCtrl         = TextEditingController();
  final _softQualityCtrl       = TextEditingController();
  bool _voiceBreakAtSoft       = false;
  final _highestPitchCtrl      = TextEditingController();
  final _lowestPitchCtrl       = TextEditingController();
  bool _smoothPitchGlide       = false;
  final _pitchBreakNotesCtrl   = TextEditingController();
  String? _resonanceBalance;
  final _resonanceObsCtrl      = TextEditingController();

  // ── Section 8 (Special Populations) — narrative jsonb ─────────────
  // Subform routes off _populationType. Each subform's controllers
  // persist independently in widget memory so toggling between
  // population types doesn't lose entered data within the session;
  // on save the full payload (including sibling subform data) is
  // written, so a refresh restores the active subform's fields too.
  String? _populationType;
  // Transgender
  String? _trGender;
  final _trCurrentF0Ctrl     = TextEditingController();
  final _trTargetF0LowCtrl   = TextEditingController();
  final _trTargetF0HighCtrl  = TextEditingController();
  final _trResonanceCtrl     = TextEditingController();
  final _trIntonationCtrl    = TextEditingController();
  final _trTrainingHistCtrl  = TextEditingController();
  bool _trHormoneOn          = false;
  final _trHormoneDurCtrl    = TextEditingController();
  // Puberty
  final _pubAgeOnsetCtrl     = TextEditingController();
  String? _pubMutationStability;
  String? _pubPitchBreakFreq;
  final _pubHabitualPitchCtrl = TextEditingController();
  final _pubNotesCtrl        = TextEditingController();
  // Pediatric
  final _pedHygieneCtrl      = TextEditingController();
  final _pedAbusePatternsCtrl = TextEditingController();
  final _pedBehavioralCtrl   = TextEditingController();
  final _pedSchoolLoadCtrl   = TextEditingController();
  // Geriatric
  bool _geriPresbylaryngis   = false;
  final _geriPresbylDetailsCtrl = TextEditingController();
  final _geriFunctionalLoadCtrl = TextEditingController();
  final _geriComorbiditiesCtrl  = TextEditingController();
  final _geriMedsCtrl        = TextEditingController();
  // Singer / occupational
  final _singerVoiceClassCtrl   = TextEditingController();
  final _singerRepertoireCtrl   = TextEditingController();
  final _singerTrainingCtrl     = TextEditingController();
  final _singerScheduleHrsCtrl  = TextEditingController();

  // ── Section 10 (Differential Diagnosis) — narrative jsonb ────────
  final _ddPrimaryDxCtrl     = TextEditingController();
  String? _ddEtiologyCategory;
  final _ddEtiologyNotesCtrl = TextEditingController();
  // Rule-outs grown via "+ Add rule-out". Default 3 empty rows shown.
  final List<TextEditingController> _ddRuleOutCtrls = [
    TextEditingController(),
    TextEditingController(),
    TextEditingController(),
  ];
  final Set<String> _ddContributingFactors = {};
  final _ddOtherContribCtrl  = TextEditingController();
  final _ddSynthesisCtrl     = TextEditingController();

  // ── Section 12 (QoL) — typed voice_qol_scores totals ─────────────
  // Item-level state lives in widget memory only — the schema's
  // typed columns are totals (vhi10_total, vhi30_total, vrqol_total,
  // svhi_total + vhi30 subscales). On hard refresh the totals
  // reload but the per-item answers do not (flagged in 24c report).
  final Map<int, int> _vhi10Items = {}; // q1..q10 → 0..4
  bool _useVhi30 = false;
  final Map<int, int> _vhi30Items = {}; // q1..q30 → 0..4
  final Map<int, int> _vrqolItems = {}; // q1..q10 → 1..5
  bool _useSvhi  = false;
  final Map<int, int> _svhiItems  = {}; // q1..q36 → 0..4
  // Totals as last loaded from voice_qol_scores; updated on save.
  int? _vhi10TotalLoaded;
  int? _vhi30TotalLoaded;
  int? _vrqolTotalLoaded;
  int? _svhiTotalLoaded;

  // ── Section 15 (Final Clinical Impression & Plan) — narrative ───
  final _ciFinalDxCtrl       = TextEditingController();
  final _ciIcdCodeCtrl       = TextEditingController();
  String? _ciDxConfidence;
  String? _ciSeverity;
  final _ciSeverityRationaleCtrl = TextEditingController();
  bool _ciOverrideEtiology   = false;
  String? _ciEtiologyOverride;
  final Set<String> _ciInterventions = {};
  final _ciTherapyProtocolCtrl   = TextEditingController();
  final _ciSessionCountCtrl  = TextEditingController();
  String? _ciFrequency;
  final _ciDischargeCriteriaCtrl = TextEditingController();
  bool _ciEntReferralNeeded  = false;
  final _ciEntReferralReasonCtrl = TextEditingController();
  final _ciOtherReferralsCtrl    = TextEditingController();
  final Set<String> _ciHygieneItems = {};
  final _ciHygieneNotesCtrl  = TextEditingController();

  // Accordion expansion state — Section 1 default-expanded
  String _expanded = 'sec1';

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    for (final c in [
      _onsetDateCtrl, _variabilityCtrl, _aggravatorsCtrl, _relieversCtrl,
      _prevTherapyCtrl, _prevSurgeryCtrl, _medsCtrl, _allergyCtrl,
      _psychLoadCtrl, _voiceRestCtrl, _hoursPerDayCtrl, _hydrationCtrl,
      _caffeineCtrl, _performedByCtrl, _lesionNotesCtrl, _examNotesCtrl,
      // 24b — Sections 4, 5, 6, 7 controllers
      _aeroNotesCtrl, _raterCtrl, _capevResonanceCtrl, _perceptualNotesCtrl,
      _readingPassageCtrl, _passageUsedCtrl, _convoSampleCtrl,
      _sustainedQualityCtrl, _connectedQualityCtrl, _comparisonNotesCtrl,
      _preLoadQualityCtrl, _voiceLoadingTaskCtrl, _postLoadQualityCtrl,
      _timeToFatigueCtrl,
      _maxLoudDbCtrl, _loudQualityCtrl, _minLoudDbCtrl, _softQualityCtrl,
      _highestPitchCtrl, _lowestPitchCtrl, _pitchBreakNotesCtrl,
      _resonanceObsCtrl,
      ..._aeroCtrls.values,
      // 24c — Section 8 / 10 / 15 controllers (Section 12 only holds
      // ints, no controllers to dispose).
      _trCurrentF0Ctrl, _trTargetF0LowCtrl, _trTargetF0HighCtrl,
      _trResonanceCtrl, _trIntonationCtrl, _trTrainingHistCtrl,
      _trHormoneDurCtrl,
      _pubAgeOnsetCtrl, _pubHabitualPitchCtrl, _pubNotesCtrl,
      _pedHygieneCtrl, _pedAbusePatternsCtrl, _pedBehavioralCtrl,
      _pedSchoolLoadCtrl,
      _geriPresbylDetailsCtrl, _geriFunctionalLoadCtrl,
      _geriComorbiditiesCtrl, _geriMedsCtrl,
      _singerVoiceClassCtrl, _singerRepertoireCtrl, _singerTrainingCtrl,
      _singerScheduleHrsCtrl,
      _ddPrimaryDxCtrl, _ddEtiologyNotesCtrl, _ddOtherContribCtrl,
      _ddSynthesisCtrl,
      ..._ddRuleOutCtrls,
      _ciFinalDxCtrl, _ciIcdCodeCtrl, _ciSeverityRationaleCtrl,
      _ciTherapyProtocolCtrl, _ciSessionCountCtrl,
      _ciDischargeCriteriaCtrl, _ciEntReferralReasonCtrl,
      _ciOtherReferralsCtrl, _ciHygieneNotesCtrl,
    ]) {
      c.dispose();
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
      // 24b/24c — typed-table reads run in parallel; all soft-fail to
      // {} so a fresh baseline lands without surfacing a load error.
      final results = await Future.wait([
        _service.loadTypedMeasures(
            voiceAssessmentId: a.id,
            tableName: 'voice_aerodynamic_measures'),
        _service.loadTypedMeasures(
            voiceAssessmentId: a.id,
            tableName: 'voice_perceptual_ratings'),
        _service.loadTypedMeasures(
            voiceAssessmentId: a.id,
            tableName: 'voice_qol_scores'),
        _service.compareBaselineToLatest(widget.clientId),
      ]);
      _hydrateAerodynamic(results[0] as Map<String, dynamic>);
      _hydratePerceptual(results[1] as Map<String, dynamic>);
      _hydrateQol(results[2] as Map<String, dynamic>);
      if (!mounted) return;
      setState(() {
        _assessment = a;
        _outcome    = results[3] as OutcomeComparison;
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

  void _hydrateFromAssessment(VoiceAssessment a) {
    final ch = a.caseHistoryPayload;
    _onsetPattern     = ch['onset_pattern'] as String?;
    _onsetDateCtrl.text   = (ch['onset_date_or_age'] as String?) ?? '';
    _variabilityCtrl.text = (ch['variability_across_day'] as String?) ?? '';
    _aggravatorsCtrl.text = (ch['aggravating_factors'] as String?) ?? '';
    _relieversCtrl.text   = (ch['relieving_factors']  as String?) ?? '';
    _prevTherapy          = ch['previous_voice_therapy'] == true;
    _prevTherapyCtrl.text = (ch['previous_voice_therapy_text'] as String?) ?? '';
    _prevSurgery          = ch['previous_laryngeal_surgeries'] == true;
    _prevSurgeryCtrl.text = (ch['previous_laryngeal_surgeries_text'] as String?) ?? '';
    _medsCtrl.text        = (ch['current_medications'] as String?) ?? '';
    _allergyCtrl.text     = (ch['allergy_history']     as String?) ?? '';
    _sleepQuality         = ch['sleep_quality'] as String?;
    _psychLoadCtrl.text   = (ch['psychological_load'] as String?) ?? '';
    final rsi = ch['rsi'] as Map?;
    if (rsi != null) {
      for (final k in _rsiKeys) {
        final v = rsi[k];
        if (v is num) _rsi[k] = v.toInt();
      }
    }
    final voiceUse = ch['voice_use'] as Map?;
    if (voiceUse != null) {
      _hoursPerDayCtrl.text =
          voiceUse['hours_per_day']?.toString() ?? '';
      final styles = voiceUse['speaking_styles'];
      if (styles is List) {
        _speakingStyles
          ..clear()
          ..addAll(styles.map((e) => e.toString()));
      }
      _microphoneAtWork =
          voiceUse['microphone_at_work'] == true;
      _voiceRestCtrl.text =
          (voiceUse['voice_rest_periods'] as String?) ?? '';
      _hydrationCtrl.text =
          voiceUse['hydration_litres']?.toString() ?? '';
      _caffeineCtrl.text =
          voiceUse['caffeine_cups']?.toString() ?? '';
    }

    final le = a.laryngealExamPayload;
    _examType = le['examination_type'] as String?;
    _performedByCtrl.text = (le['performed_by'] as String?) ?? '';
    final examDateStr = le['exam_date'] as String?;
    if (examDateStr != null && examDateStr.isNotEmpty) {
      _examDate = DateTime.tryParse(examDateStr);
    }
    final lesionsList = le['lesions'];
    if (lesionsList is List) {
      _lesions
        ..clear()
        ..addAll(lesionsList.map((e) => e.toString()));
    }
    _lesionNotesCtrl.text = (le['lesions_location_notes'] as String?) ?? '';
    _mucosalAmplitude       = le['mucosal_wave_amplitude'] as String?;
    _mucosalSymmetry        = le['mucosal_wave_symmetry']  as String?;
    _glotticClosure         = le['glottic_closure']        as String?;
    _supraglotticCompression = le['supraglottic_compression'] as String?;
    _phaseClosureSymmetry   = le['phase_closure_symmetry'] as String?;
    _examNotesCtrl.text     = (le['additional_notes'] as String?) ?? '';

    // 24b — Sections 6 (functional voice) and 7 (task-based) seed
    // from their jsonb columns on the parent assessment row.
    final fv = a.functionalVoicePayload;
    _readingPassageCtrl.text   = (fv['reading_passage_observations'] as String?) ?? '';
    _passageUsedCtrl.text      = (fv['passage_used']                 as String?) ?? '';
    _convoSampleCtrl.text      = (fv['conversational_sample']        as String?) ?? '';
    _sustainedQualityCtrl.text = (fv['sustained_phonation_quality']  as String?) ?? '';
    _connectedQualityCtrl.text = (fv['connected_speech_quality']     as String?) ?? '';
    _comparisonNotesCtrl.text  = (fv['comparison_notes']             as String?) ?? '';
    _fatigueTestConducted      = fv['fatigue_test_conducted'] == true;
    final ft = (fv['fatigue_test'] is Map)
        ? Map<String, dynamic>.from(fv['fatigue_test'] as Map)
        : const <String, dynamic>{};
    _preLoadQualityCtrl.text   = (ft['pre_load_voice_quality']  as String?) ?? '';
    _voiceLoadingTaskCtrl.text = (ft['voice_loading_task']      as String?) ?? '';
    _postLoadQualityCtrl.text  = (ft['post_load_voice_quality'] as String?) ?? '';
    _timeToFatigueCtrl.text    = ft['time_to_fatigue_minutes']?.toString() ?? '';

    final tb = a.taskBasedPayload;
    final loud = (tb['loud_voice'] is Map)
        ? Map<String, dynamic>.from(tb['loud_voice'] as Map)
        : const <String, dynamic>{};
    _maxLoudDbCtrl.text   = loud['max_loudness_db_spl']?.toString() ?? '';
    _loudQualityCtrl.text = (loud['quality'] as String?) ?? '';
    _strainAtLoud         = loud['strain_noted'] == true;
    final soft = (tb['soft_voice'] is Map)
        ? Map<String, dynamic>.from(tb['soft_voice'] as Map)
        : const <String, dynamic>{};
    _minLoudDbCtrl.text   = soft['min_loudness_db_spl']?.toString() ?? '';
    _softQualityCtrl.text = (soft['quality'] as String?) ?? '';
    _voiceBreakAtSoft     = soft['voice_break_or_aphonia'] == true;
    final glide = (tb['pitch_glide'] is Map)
        ? Map<String, dynamic>.from(tb['pitch_glide'] as Map)
        : const <String, dynamic>{};
    _highestPitchCtrl.text    = (glide['highest_pitch'] as String?) ?? '';
    _lowestPitchCtrl.text     = (glide['lowest_pitch']  as String?) ?? '';
    _smoothPitchGlide         = glide['smooth_glide'] == true;
    _pitchBreakNotesCtrl.text = (glide['pitch_break_notes'] as String?) ?? '';
    final res = (tb['resonance'] is Map)
        ? Map<String, dynamic>.from(tb['resonance'] as Map)
        : const <String, dynamic>{};
    _resonanceBalance       = res['balance'] as String?;
    _resonanceObsCtrl.text  = (res['observations'] as String?) ?? '';

    // 24c — Section 8 (special populations) seeds from its jsonb.
    final sp = a.specialPopulationsPayload;
    _populationType = sp['population_type'] as String?;
    final tr = (sp['transgender'] is Map)
        ? Map<String, dynamic>.from(sp['transgender'] as Map)
        : const <String, dynamic>{};
    _trGender                = tr['target_gender'] as String?;
    _trCurrentF0Ctrl.text    = tr['current_f0_hz']?.toString() ?? '';
    _trTargetF0LowCtrl.text  = tr['target_f0_low_hz']?.toString() ?? '';
    _trTargetF0HighCtrl.text = tr['target_f0_high_hz']?.toString() ?? '';
    _trResonanceCtrl.text    = (tr['resonance_formant_notes'] as String?) ?? '';
    _trIntonationCtrl.text   = (tr['intonation_patterns'] as String?) ?? '';
    _trTrainingHistCtrl.text = (tr['voice_training_history'] as String?) ?? '';
    _trHormoneOn             = tr['hormone_therapy_on'] == true;
    _trHormoneDurCtrl.text   = tr['hormone_therapy_duration_months']?.toString() ?? '';
    final pub = (sp['puberty'] is Map)
        ? Map<String, dynamic>.from(sp['puberty'] as Map)
        : const <String, dynamic>{};
    _pubAgeOnsetCtrl.text     = pub['age_at_voice_change_onset']?.toString() ?? '';
    _pubMutationStability     = pub['mutation_stability'] as String?;
    _pubPitchBreakFreq        = pub['pitch_break_frequency'] as String?;
    _pubHabitualPitchCtrl.text = (pub['habitual_pitch_vs_expected'] as String?) ?? '';
    _pubNotesCtrl.text        = (pub['notes'] as String?) ?? '';
    final ped = (sp['pediatric'] is Map)
        ? Map<String, dynamic>.from(sp['pediatric'] as Map)
        : const <String, dynamic>{};
    _pedHygieneCtrl.text       = (ped['vocal_hygiene_awareness'] as String?) ?? '';
    _pedAbusePatternsCtrl.text = (ped['voice_abuse_patterns']    as String?) ?? '';
    _pedBehavioralCtrl.text    = (ped['behavioral_concerns']     as String?) ?? '';
    _pedSchoolLoadCtrl.text    = (ped['school_voice_load']       as String?) ?? '';
    final geri = (sp['geriatric'] is Map)
        ? Map<String, dynamic>.from(sp['geriatric'] as Map)
        : const <String, dynamic>{};
    _geriPresbylaryngis           = geri['presbylaryngis_signs'] == true;
    _geriPresbylDetailsCtrl.text  = (geri['presbylaryngis_details']  as String?) ?? '';
    _geriFunctionalLoadCtrl.text  = (geri['functional_voice_load']    as String?) ?? '';
    _geriComorbiditiesCtrl.text   = (geri['comorbidities_affecting']  as String?) ?? '';
    _geriMedsCtrl.text            = (geri['medication_review']        as String?) ?? '';
    final singer = (sp['singer_occupational'] is Map)
        ? Map<String, dynamic>.from(sp['singer_occupational'] as Map)
        : const <String, dynamic>{};
    _singerVoiceClassCtrl.text  = (singer['voice_classification']  as String?) ?? '';
    _singerRepertoireCtrl.text  = (singer['repertoire']             as String?) ?? '';
    _singerTrainingCtrl.text    = (singer['training_background']    as String?) ?? '';
    _singerScheduleHrsCtrl.text = singer['performance_hours_per_week']?.toString() ?? '';

    // 24c — Section 10 (differential diagnosis) seeds from its jsonb.
    final dd = a.differentialDiagnosisPayload;
    _ddPrimaryDxCtrl.text     = (dd['primary_diagnosis']  as String?) ?? '';
    _ddEtiologyCategory       = dd['etiology_category']   as String?;
    _ddEtiologyNotesCtrl.text = (dd['etiology_notes']     as String?) ?? '';
    final ruleOuts = dd['rule_outs'];
    if (ruleOuts is List && ruleOuts.isNotEmpty) {
      // Replace the default 3 with however many landed; pad to at
      // least 3 so the form still shows empty rows on the bottom.
      for (final c in _ddRuleOutCtrls) {
        c.dispose();
      }
      _ddRuleOutCtrls
        ..clear()
        ..addAll(ruleOuts.map((e) =>
            TextEditingController(text: e?.toString() ?? '')));
      while (_ddRuleOutCtrls.length < 3) {
        _ddRuleOutCtrls.add(TextEditingController());
      }
    }
    final factors = dd['contributing_factors'];
    if (factors is List) {
      _ddContributingFactors
        ..clear()
        ..addAll(factors.map((e) => e.toString()));
    }
    _ddOtherContribCtrl.text = (dd['other_contributing']    as String?) ?? '';
    _ddSynthesisCtrl.text    = (dd['differential_reasoning'] as String?) ?? '';

    // 24c — Section 15 (clinical impression & plan) seeds from its jsonb.
    final ci = a.clinicalImpressionPayload;
    _ciFinalDxCtrl.text       = (ci['final_diagnosis']      as String?) ?? '';
    _ciIcdCodeCtrl.text       = (ci['icd_code']             as String?) ?? '';
    _ciDxConfidence           = ci['diagnosis_confidence']  as String?;
    _ciSeverity               = ci['severity']              as String?;
    _ciSeverityRationaleCtrl.text = (ci['severity_rationale'] as String?) ?? '';
    _ciOverrideEtiology       = ci['override_etiology'] == true;
    _ciEtiologyOverride       = ci['etiology_override']     as String?;
    final interv = ci['recommended_interventions'];
    if (interv is List) {
      _ciInterventions
        ..clear()
        ..addAll(interv.map((e) => e.toString()));
    }
    _ciTherapyProtocolCtrl.text   = (ci['therapy_protocol_details']  as String?) ?? '';
    _ciSessionCountCtrl.text      = ci['estimated_session_count']?.toString() ?? '';
    _ciFrequency                  = ci['frequency']               as String?;
    _ciDischargeCriteriaCtrl.text = (ci['discharge_criteria']     as String?) ?? '';
    _ciEntReferralNeeded          = ci['ent_referral_needed'] == true;
    _ciEntReferralReasonCtrl.text = (ci['ent_referral_reason']    as String?) ?? '';
    _ciOtherReferralsCtrl.text    = (ci['other_referrals']        as String?) ?? '';
    final hyg = ci['vocal_hygiene_items'];
    if (hyg is List) {
      _ciHygieneItems
        ..clear()
        ..addAll(hyg.map((e) => e.toString()));
    }
    _ciHygieneNotesCtrl.text = (ci['vocal_hygiene_notes'] as String?) ?? '';
  }

  /// Seeds Section 12 from a previously saved voice_qol_scores row.
  /// Per-item answers are NOT persisted (only totals), so on hard
  /// refresh the totals reload but the slider rows show 0/1 defaults.
  void _hydrateQol(Map<String, dynamic> row) {
    if (row.isEmpty) return;
    final v10 = row['vhi10_total'];
    if (v10 is num) _vhi10TotalLoaded = v10.toInt();
    final v30 = row['vhi30_total'];
    if (v30 is num) {
      _vhi30TotalLoaded = v30.toInt();
      _useVhi30 = true;
    }
    final vrq = row['vrqol_total'];
    if (vrq is num) _vrqolTotalLoaded = vrq.toInt();
    final svhi = row['svhi_total'];
    if (svhi is num) {
      _svhiTotalLoaded = svhi.toInt();
      _useSvhi = true;
    }
  }

  void _hydrateAerodynamic(Map<String, dynamic> row) {
    if (row.isEmpty) return;
    for (final k in _aeroNumericKeys) {
      final v = row[k];
      if (v is num) _aeroCtrls[k]!.text = _trimZero(v);
    }
    _aeroNotesCtrl.text = (row['notes'] as String?) ?? '';
  }

  void _hydratePerceptual(Map<String, dynamic> row) {
    if (row.isEmpty) return;
    final rater = row['rater'];
    if (rater is String && rater.isNotEmpty) _raterCtrl.text = rater;
    for (final k in _capevSliderKeys) {
      final v = row[k];
      if (v is num) _capev[k] = v.toInt().clamp(0, 100);
    }
    _capevResonanceCtrl.text = (row['capev_resonance_notes'] as String?) ?? '';
    for (final k in _grbasKeys) {
      final v = row[k];
      _grbas[k] = (v is num) ? v.toInt().clamp(0, 3) : null;
    }
    _perceptualNotesCtrl.text = (row['notes'] as String?) ?? '';
  }

  /// Strips trailing ".0" from integer-valued doubles so a typed
  /// "15" doesn't reload as "15.0" and look weird to the SLP.
  String _trimZero(num v) {
    if (v is int) return v.toString();
    final d = v.toDouble();
    return d == d.roundToDouble() ? d.toInt().toString() : d.toString();
  }

  // ── Save dispatchers ────────────────────────────────────────────────
  Future<void> _saveCaseHistory() async {
    if (_assessment == null) return;
    final payload = <String, dynamic>{
      'onset_pattern':                     _onsetPattern,
      'onset_date_or_age':                 _onsetDateCtrl.text.trim(),
      'variability_across_day':            _variabilityCtrl.text.trim(),
      'aggravating_factors':               _aggravatorsCtrl.text.trim(),
      'relieving_factors':                 _relieversCtrl.text.trim(),
      'previous_voice_therapy':            _prevTherapy,
      'previous_voice_therapy_text':       _prevTherapyCtrl.text.trim(),
      'previous_laryngeal_surgeries':      _prevSurgery,
      'previous_laryngeal_surgeries_text': _prevSurgeryCtrl.text.trim(),
      'current_medications':               _medsCtrl.text.trim(),
      'allergy_history':                   _allergyCtrl.text.trim(),
      'sleep_quality':                     _sleepQuality,
      'psychological_load':                _psychLoadCtrl.text.trim(),
      'rsi': {
        for (final k in _rsiKeys) k: _rsi[k],
        'total': _rsiTotal,
      },
      'voice_use': {
        'hours_per_day':       int.tryParse(_hoursPerDayCtrl.text.trim()),
        'speaking_styles':     _speakingStyles.toList(),
        'microphone_at_work':  _microphoneAtWork,
        'voice_rest_periods':  _voiceRestCtrl.text.trim(),
        'hydration_litres':    num.tryParse(_hydrationCtrl.text.trim()),
        'caffeine_cups':       num.tryParse(_caffeineCtrl.text.trim()),
      },
    };
    try {
      await _service.saveSection(
        assessmentId: _assessment!.id,
        section:      'case_history',
        payload:      payload,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save case history: $e')),
        );
      }
    }
  }

  Future<void> _saveLaryngealExam() async {
    if (_assessment == null) return;
    final payload = <String, dynamic>{
      'examination_type':        _examType,
      'performed_by':            _performedByCtrl.text.trim(),
      'exam_date':               _examDate?.toIso8601String().substring(0, 10),
      'lesions':                 _lesions.toList(),
      'lesions_location_notes':  _lesionNotesCtrl.text.trim(),
      'mucosal_wave_amplitude':  _mucosalAmplitude,
      'mucosal_wave_symmetry':   _mucosalSymmetry,
      'glottic_closure':         _glotticClosure,
      'supraglottic_compression': _supraglotticCompression,
      'phase_closure_symmetry':  _phaseClosureSymmetry,
      'additional_notes':        _examNotesCtrl.text.trim(),
    };
    try {
      await _service.saveSection(
        assessmentId: _assessment!.id,
        section:      'laryngeal_exam',
        payload:      payload,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save laryngeal exam: $e')),
        );
      }
    }
  }

  // 24b — Section 4 typed measures.
  Future<void> _saveAerodynamic() async {
    if (_assessment == null) return;
    final data = <String, dynamic>{
      for (final k in _aeroNumericKeys) k: _parseDecimal(_aeroCtrls[k]!.text),
      'notes': _aeroNotesCtrl.text.trim(),
    };
    try {
      await _service.saveTypedMeasures(
        voiceAssessmentId: _assessment!.id,
        tableName:         'voice_aerodynamic_measures',
        data:              data,
      );
    } catch (e) {
      _toast('Could not save aerodynamic measures: $e');
    }
  }

  // 24b — Section 5 typed measures.
  Future<void> _savePerceptual() async {
    if (_assessment == null) return;
    final rater = _raterCtrl.text.trim().isEmpty
        ? 'primary_clinician'
        : _raterCtrl.text.trim();
    final data = <String, dynamic>{
      'rater': rater,
      for (final k in _capevSliderKeys) k: _capev[k],
      'capev_resonance_notes': _capevResonanceCtrl.text.trim(),
      for (final k in _grbasKeys) k: _grbas[k],
      // audio_recording_url stays unset until 4.0.7.24c ships capture.
      'notes': _perceptualNotesCtrl.text.trim(),
    };
    try {
      await _service.saveTypedMeasures(
        voiceAssessmentId: _assessment!.id,
        tableName:         'voice_perceptual_ratings',
        data:              data,
      );
    } catch (e) {
      _toast('Could not save perceptual ratings: $e');
    }
  }

  // 24b — Section 6 narrative jsonb.
  Future<void> _saveFunctionalVoice() async {
    if (_assessment == null) return;
    final payload = <String, dynamic>{
      'reading_passage_observations': _readingPassageCtrl.text.trim(),
      'passage_used':                 _passageUsedCtrl.text.trim(),
      'conversational_sample':        _convoSampleCtrl.text.trim(),
      'sustained_phonation_quality':  _sustainedQualityCtrl.text.trim(),
      'connected_speech_quality':     _connectedQualityCtrl.text.trim(),
      'comparison_notes':             _comparisonNotesCtrl.text.trim(),
      'fatigue_test_conducted':       _fatigueTestConducted,
      if (_fatigueTestConducted)
        'fatigue_test': {
          'pre_load_voice_quality':   _preLoadQualityCtrl.text.trim(),
          'voice_loading_task':       _voiceLoadingTaskCtrl.text.trim(),
          'post_load_voice_quality':  _postLoadQualityCtrl.text.trim(),
          'time_to_fatigue_minutes':  _parseDecimal(_timeToFatigueCtrl.text),
        },
    };
    try {
      await _service.savePayloadSection(
        voiceAssessmentId: _assessment!.id,
        columnName:        'functional_voice_payload',
        payload:           payload,
      );
    } catch (e) {
      _toast('Could not save functional voice: $e');
    }
  }

  // 24b — Section 7 narrative jsonb.
  Future<void> _saveTaskBased() async {
    if (_assessment == null) return;
    final payload = <String, dynamic>{
      'loud_voice': {
        'max_loudness_db_spl': _parseDecimal(_maxLoudDbCtrl.text),
        'quality':             _loudQualityCtrl.text.trim(),
        'strain_noted':        _strainAtLoud,
      },
      'soft_voice': {
        'min_loudness_db_spl':    _parseDecimal(_minLoudDbCtrl.text),
        'quality':                _softQualityCtrl.text.trim(),
        'voice_break_or_aphonia': _voiceBreakAtSoft,
      },
      'pitch_glide': {
        'highest_pitch':     _highestPitchCtrl.text.trim(),
        'lowest_pitch':      _lowestPitchCtrl.text.trim(),
        'smooth_glide':      _smoothPitchGlide,
        'pitch_break_notes': _pitchBreakNotesCtrl.text.trim(),
      },
      'resonance': {
        'balance':      _resonanceBalance,
        'observations': _resonanceObsCtrl.text.trim(),
      },
    };
    try {
      await _service.savePayloadSection(
        voiceAssessmentId: _assessment!.id,
        columnName:        'task_based_payload',
        payload:           payload,
      );
    } catch (e) {
      _toast('Could not save task-based sampling: $e');
    }
  }

  // 24c — Section 8 narrative jsonb. Writes the active subform plus
  // any sibling subform data already in widget memory so toggling
  // population types in-session doesn't drop sibling answers.
  Future<void> _saveSpecialPopulations() async {
    if (_assessment == null) return;
    final payload = <String, dynamic>{
      'population_type': _populationType,
      'transgender': {
        'target_gender':                   _trGender,
        'current_f0_hz':                   _parseDecimal(_trCurrentF0Ctrl.text),
        'target_f0_low_hz':                _parseDecimal(_trTargetF0LowCtrl.text),
        'target_f0_high_hz':               _parseDecimal(_trTargetF0HighCtrl.text),
        'resonance_formant_notes':         _trResonanceCtrl.text.trim(),
        'intonation_patterns':             _trIntonationCtrl.text.trim(),
        'voice_training_history':          _trTrainingHistCtrl.text.trim(),
        'hormone_therapy_on':              _trHormoneOn,
        'hormone_therapy_duration_months': _parseDecimal(_trHormoneDurCtrl.text),
      },
      'puberty': {
        'age_at_voice_change_onset':  _parseDecimal(_pubAgeOnsetCtrl.text),
        'mutation_stability':         _pubMutationStability,
        'pitch_break_frequency':      _pubPitchBreakFreq,
        'habitual_pitch_vs_expected': _pubHabitualPitchCtrl.text.trim(),
        'notes':                      _pubNotesCtrl.text.trim(),
      },
      'pediatric': {
        'vocal_hygiene_awareness': _pedHygieneCtrl.text.trim(),
        'voice_abuse_patterns':    _pedAbusePatternsCtrl.text.trim(),
        'behavioral_concerns':     _pedBehavioralCtrl.text.trim(),
        'school_voice_load':       _pedSchoolLoadCtrl.text.trim(),
      },
      'geriatric': {
        'presbylaryngis_signs':     _geriPresbylaryngis,
        'presbylaryngis_details':   _geriPresbylDetailsCtrl.text.trim(),
        'functional_voice_load':    _geriFunctionalLoadCtrl.text.trim(),
        'comorbidities_affecting':  _geriComorbiditiesCtrl.text.trim(),
        'medication_review':        _geriMedsCtrl.text.trim(),
      },
      'singer_occupational': {
        'voice_classification':       _singerVoiceClassCtrl.text.trim(),
        'repertoire':                 _singerRepertoireCtrl.text.trim(),
        'training_background':        _singerTrainingCtrl.text.trim(),
        'performance_hours_per_week': _parseDecimal(_singerScheduleHrsCtrl.text),
      },
    };
    try {
      await _service.savePayloadSection(
        voiceAssessmentId: _assessment!.id,
        columnName:        'special_populations_payload',
        payload:           payload,
      );
    } catch (e) {
      _toast('Could not save special populations: $e');
    }
  }

  // 24c — Section 10 narrative jsonb.
  Future<void> _saveDifferentialDiagnosis() async {
    if (_assessment == null) return;
    final ruleOuts = _ddRuleOutCtrls
        .map((c) => c.text.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    final payload = <String, dynamic>{
      'primary_diagnosis':       _ddPrimaryDxCtrl.text.trim(),
      'etiology_category':       _ddEtiologyCategory,
      'etiology_notes':          _ddEtiologyNotesCtrl.text.trim(),
      'rule_outs':               ruleOuts,
      'contributing_factors':    _ddContributingFactors.toList(),
      'other_contributing':      _ddOtherContribCtrl.text.trim(),
      'differential_reasoning':  _ddSynthesisCtrl.text.trim(),
    };
    try {
      await _service.savePayloadSection(
        voiceAssessmentId: _assessment!.id,
        columnName:        'differential_diagnosis_payload',
        payload:           payload,
      );
    } catch (e) {
      _toast('Could not save differential diagnosis: $e');
    }
  }

  // 24c — Section 12 typed QoL totals to voice_qol_scores. Per-item
  // answers stay in widget memory only (the schema's typed columns
  // are totals + VHI-30 subscale totals).
  Future<void> _saveQol() async {
    if (_assessment == null) return;
    final vhi10 = _vhi10Total;
    final data = <String, dynamic>{
      'vhi10_total': ?vhi10,
      if (_useVhi30) ...{
        'vhi30_total':       _vhi30Total,
        'vhi30_functional':  _vhi30FunctionalTotal,
        'vhi30_physical':    _vhi30PhysicalTotal,
        'vhi30_emotional':   _vhi30EmotionalTotal,
      },
      'vrqol_total': _vrqolTotal,
      if (_useSvhi) 'svhi_total': _svhiTotal,
    };
    try {
      await _service.saveTypedMeasures(
        voiceAssessmentId: _assessment!.id,
        tableName:         'voice_qol_scores',
        data:              data,
      );
      // Reflect the saved totals in the loaded badges immediately.
      setState(() {
        _vhi10TotalLoaded  = vhi10;
        _vhi30TotalLoaded  = _useVhi30 ? _vhi30Total  : null;
        _vrqolTotalLoaded  = _vrqolTotal;
        _svhiTotalLoaded   = _useSvhi  ? _svhiTotal   : null;
      });
    } catch (e) {
      _toast('Could not save QoL scores: $e');
    }
  }

  // QoL totals — sums over the in-memory item maps. Returns null when
  // no item has been touched, so we don't write a 0 into the typed
  // column and confuse the outcome comparison.
  int? get _vhi10Total =>
      _vhi10Items.isEmpty ? null : _vhi10Items.values.fold<int>(0, (a, b) => a + b);
  int get _vhi30Total =>
      _vhi30Items.values.fold<int>(0, (a, b) => a + b);
  int get _vhi30FunctionalTotal =>
      _vhi30SumRange(1, 10);
  int get _vhi30PhysicalTotal =>
      _vhi30SumRange(11, 20);
  int get _vhi30EmotionalTotal =>
      _vhi30SumRange(21, 30);
  int _vhi30SumRange(int from, int to) {
    var sum = 0;
    for (var i = from; i <= to; i++) {
      sum += _vhi30Items[i] ?? 0;
    }
    return sum;
  }
  int get _vrqolTotal =>
      _vrqolItems.values.fold<int>(0, (a, b) => a + b);
  int get _svhiTotal =>
      _svhiItems.values.fold<int>(0, (a, b) => a + b);

  // 24c — Section 15 narrative jsonb.
  Future<void> _saveClinicalImpression() async {
    if (_assessment == null) return;
    final payload = <String, dynamic>{
      'final_diagnosis':            _ciFinalDxCtrl.text.trim(),
      'icd_code':                   _ciIcdCodeCtrl.text.trim(),
      'diagnosis_confidence':       _ciDxConfidence,
      'severity':                   _ciSeverity,
      'severity_rationale':         _ciSeverityRationaleCtrl.text.trim(),
      'override_etiology':          _ciOverrideEtiology,
      'etiology_override':          _ciEtiologyOverride,
      'recommended_interventions':  _ciInterventions.toList(),
      'therapy_protocol_details':   _ciTherapyProtocolCtrl.text.trim(),
      'estimated_session_count':    _parseDecimal(_ciSessionCountCtrl.text),
      'frequency':                  _ciFrequency,
      'discharge_criteria':         _ciDischargeCriteriaCtrl.text.trim(),
      'ent_referral_needed':        _ciEntReferralNeeded,
      'ent_referral_reason':        _ciEntReferralReasonCtrl.text.trim(),
      'other_referrals':            _ciOtherReferralsCtrl.text.trim(),
      'vocal_hygiene_items':        _ciHygieneItems.toList(),
      'vocal_hygiene_notes':        _ciHygieneNotesCtrl.text.trim(),
    };
    try {
      await _service.savePayloadSection(
        voiceAssessmentId: _assessment!.id,
        columnName:        'clinical_impression_payload',
        payload:           payload,
      );
    } catch (e) {
      _toast('Could not save clinical impression: $e');
    }
  }

  /// Empty / unparseable text → null, so the typed jsonb / numeric
  /// columns receive a real null rather than 0.
  num? _parseDecimal(String s) {
    final t = s.trim();
    if (t.isEmpty) return null;
    return num.tryParse(t);
  }

  void _toast(String msg) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Follow-up assessment created.')),
        );
      }
      final outcome = await _service.compareBaselineToLatest(widget.clientId);
      if (mounted) setState(() => _outcome = outcome);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not add follow-up: $e')),
        );
      }
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
      return _errorBox('Could not load voice assessment: $_error');
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _section(id: 'sec1', number: 1, title: 'Detailed Case History',
            tagline: 'Onset, medical context, RSI screen, voice use profile.',
            child: _section1Body()),
        const SizedBox(height: 10),
        _section(id: 'sec2', number: 2, title: 'Laryngeal Examination',
            tagline: 'ENT findings transcribed — closure, mucosal wave, lesions.',
            child: _section2Body()),
        const SizedBox(height: 10),
        _section(id: 'sec4', number: 4, title: 'Aerodynamic Measures',
            tagline: 'MPT, s/z, basic acoustic — F0, jitter, shimmer, HNR.',
            child: _section4Body()),
        const SizedBox(height: 10),
        _section(id: 'sec5', number: 5, title: 'Perceptual Evaluation',
            tagline: 'CAPE-V + GRBAS rating from clinician samples.',
            child: _section5Body()),
        const SizedBox(height: 10),
        _section(id: 'sec6', number: 6, title: 'Functional Voice',
            tagline: 'Conversational voice across functional contexts.',
            child: _section6Body()),
        const SizedBox(height: 10),
        _section(id: 'sec7', number: 7, title: 'Task-Based Sampling',
            tagline: 'Loud / soft, pitch glide, resonance balance.',
            child: _section7Body()),
        const SizedBox(height: 10),
        _section(id: 'sec8', number: 8, title: 'Special Populations',
            tagline: 'Transgender, puberty, pediatric, geriatric, singer.',
            child: _section8Body()),
        const SizedBox(height: 10),
        _section(id: 'sec10', number: 10, title: 'Differential Diagnosis',
            tagline: 'Working hypothesis, etiology, rule-outs, contributors.',
            child: _section10Body()),
        const SizedBox(height: 10),
        _section(id: 'sec11', number: 11, title: 'Outcome Tracking',
            tagline: 'Baseline vs most recent follow-up across all measures.',
            child: _section11Body()),
        const SizedBox(height: 10),
        _section(id: 'sec12', number: 12, title: 'Voice Handicap & Quality of Life',
            tagline: 'VHI-10, V-RQOL — VHI-30 / SVHI behind toggles.',
            child: _section12Body()),
        const SizedBox(height: 10),
        _section(id: 'sec15', number: 15, title: 'Final Clinical Impression & Plan',
            tagline: 'Diagnosis, severity, plan, referrals, hygiene.',
            child: _section15Body()),
      ],
    );
  }

  // ── Section primitives ──────────────────────────────────────────────
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
  Widget _stubSection({
    required int number,
    required String title,
    required String tagline,
    required String comingIn,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color:        _amberSoft.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: _amber.withValues(alpha: 0.30),
            style: BorderStyle.solid),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _groupLabel('A · Onset & Variability'),
        _singleChips('Onset pattern', const ['Sudden', 'Gradual', 'Unknown'],
            _onsetPattern, (v) {
          setState(() => _onsetPattern = v);
          _saveCaseHistory();
        }),
        _textField('Onset date / age', _onsetDateCtrl, hint: 'e.g. 6 months ago, age 38'),
        _textField('Variability across day', _variabilityCtrl,
            multi: true, hint: 'When worse, when better, fatigue-related?'),
        _textField('Aggravating factors', _aggravatorsCtrl, multi: true),
        _textField('Relieving factors',  _relieversCtrl,   multi: true),

        const SizedBox(height: 14),
        _groupLabel('B · Medical History'),
        _yesNoWithText('Previous voice therapy', _prevTherapy, _prevTherapyCtrl,
            (v) {
          setState(() => _prevTherapy = v);
          _saveCaseHistory();
        }),
        _yesNoWithText('Previous laryngeal surgeries',
            _prevSurgery, _prevSurgeryCtrl, (v) {
          setState(() => _prevSurgery = v);
          _saveCaseHistory();
        }),
        _textField('Current medications', _medsCtrl,
            multi: true,
            hint: 'Especially reflux meds, steroids, hormones, antihistamines'),
        _textField('Allergy history', _allergyCtrl),
        _singleChips('Sleep quality', const ['Good', 'Fair', 'Poor'],
            _sleepQuality, (v) {
          setState(() => _sleepQuality = v);
          _saveCaseHistory();
        }),
        _textField('Psychological load — stress / anxiety',
            _psychLoadCtrl, multi: true),

        const SizedBox(height: 14),
        _groupLabel('C · Reflux Symptom Index (RSI) — 0–5 each'),
        _rsiRow('Hoarseness or voice problem',                   'hoarseness'),
        _rsiRow('Clearing throat',                                'throat_clearing'),
        _rsiRow('Excess throat mucus / postnasal drip',           'mucus'),
        _rsiRow('Difficulty swallowing food, liquids, or pills',  'swallowing'),
        _rsiRow('Coughing after eating or lying down',            'cough_after_eating'),
        _rsiRow('Breathing difficulties or choking episodes',     'breathing_choking'),
        _rsiRow('Troublesome or annoying cough',                  'annoying_cough'),
        _rsiRow('Sensation of something sticking in throat',      'throat_lump'),
        _rsiRow('Heartburn, chest pain, indigestion, stomach acid','heartburn'),
        const SizedBox(height: 8),
        _rsiTotalRow(),

        const SizedBox(height: 14),
        _groupLabel('D · Voice Use Profile'),
        _textField('Hours of voiced output per day', _hoursPerDayCtrl,
            keyboardType: TextInputType.number, hint: '0–24'),
        _multiChips('Speaking style',
            const ['Quiet', 'Conversational', 'Loud projection',
                   'Shouting', 'Singing'],
            _speakingStyles, (v, sel) {
          setState(() {
            if (sel) {
              _speakingStyles.add(v);
            } else {
              _speakingStyles.remove(v);
            }
          });
          _saveCaseHistory();
        }),
        _yesNo('Microphone available at work?', _microphoneAtWork, (v) {
          setState(() => _microphoneAtWork = v);
          _saveCaseHistory();
        }),
        _textField('Daily voice rest periods?', _voiceRestCtrl, multi: true),
        _textField('Hydration (litres of water/day)', _hydrationCtrl,
            keyboardType: TextInputType.number),
        _textField('Caffeine / tea cups per day', _caffeineCtrl,
            keyboardType: TextInputType.number),
      ],
    );
  }

  // ── Section 2 body ─────────────────────────────────────────────────
  Widget _section2Body() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _groupLabel('A · Source'),
        _singleChips('Examination type', const [
          'Videostroboscopy',
          'Flexible nasendoscopy',
          'High-speed videoendoscopy',
          'Rigid laryngoscopy',
        ], _examType, (v) {
          setState(() => _examType = v);
          _saveLaryngealExam();
        }),
        _textField('Performed by', _performedByCtrl, hint: 'ENT name'),
        _datePickerRow('Date of examination', _examDate, (d) {
          setState(() => _examDate = d);
          _saveLaryngealExam();
        }),

        const SizedBox(height: 14),
        _groupLabel('B · Findings'),
        _multiChips('Lesions / pathology', const [
          'Vocal fold nodules', 'Polyp', 'Cyst', "Reinke's edema",
          'Granuloma', 'Sulcus vocalis', 'Vocal fold paresis',
          'Paralysis', 'None', 'Other',
        ], _lesions, (v, sel) {
          setState(() {
            if (sel) {
              _lesions.add(v);
            } else {
              _lesions.remove(v);
            }
          });
          _saveLaryngealExam();
        }),
        _textField('Lesions location notes', _lesionNotesCtrl, multi: true),
        _singleChips('Mucosal wave amplitude',
            const ['Normal', 'Reduced', 'Absent', 'Asymmetric'],
            _mucosalAmplitude, (v) {
          setState(() => _mucosalAmplitude = v);
          _saveLaryngealExam();
        }),
        _singleChips('Mucosal wave symmetry',
            const ['Symmetric', 'Asymmetric (specify side)'],
            _mucosalSymmetry, (v) {
          setState(() => _mucosalSymmetry = v);
          _saveLaryngealExam();
        }),
        _singleChips('Glottic closure pattern',
            const ['Complete', 'Anterior chink', 'Posterior chink',
                   'Hourglass', 'Spindle', 'Incomplete (other)'],
            _glotticClosure, (v) {
          setState(() => _glotticClosure = v);
          _saveLaryngealExam();
        }),
        _singleChips('Supraglottic compression',
            const ['None', 'Mild', 'Moderate', 'Severe'],
            _supraglotticCompression, (v) {
          setState(() => _supraglotticCompression = v);
          _saveLaryngealExam();
        }),
        _singleChips('Phase closure symmetry',
            const ['Symmetric', 'Asymmetric'],
            _phaseClosureSymmetry, (v) {
          setState(() => _phaseClosureSymmetry = v);
          _saveLaryngealExam();
        }),

        const SizedBox(height: 14),
        _groupLabel('C · Free narrative'),
        _textField('Additional examination notes', _examNotesCtrl, multi: true),
      ],
    );
  }

  // ── Section 4 body — Aerodynamic Measures + Basic Acoustic ────────
  Widget _section4Body() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _groupLabel('A · Aerodynamic'),
        _numericField(
          'Maximum Phonation Time (MPT)',
          _aeroCtrls['mpt_seconds']!,
          unit: 'seconds',
          reference: 'Adult reference ≥ 15 s',
          onSave: _saveAerodynamic,
        ),
        _numericField(
          's/z ratio',
          _aeroCtrls['s_z_ratio']!,
          unit: 'ratio',
          reference: 'Healthy reference ~ 1.0',
          onSave: _saveAerodynamic,
        ),
        _numericField(
          'Subglottal pressure (estimated)',
          _aeroCtrls['subglottal_pressure_estimated_cmh2o']!,
          unit: 'cmH₂O',
          reference: 'Optional',
          onSave: _saveAerodynamic,
        ),
        _numericField(
          'Mean airflow rate',
          _aeroCtrls['mean_airflow_rate_ml_per_sec']!,
          unit: 'mL/sec',
          reference: 'Optional',
          onSave: _saveAerodynamic,
        ),
        _numericField(
          'Phonation threshold pressure',
          _aeroCtrls['phonation_threshold_pressure_cmh2o']!,
          unit: 'cmH₂O',
          reference: 'If equipment available',
          onSave: _saveAerodynamic,
        ),

        const SizedBox(height: 14),
        _groupLabel('B · Basic Acoustic'),
        _numericField('F0 mean',  _aeroCtrls['f0_mean_hz']!,
            unit: 'Hz', onSave: _saveAerodynamic),
        _numericField('Jitter',   _aeroCtrls['jitter_percent']!,
            unit: '%',  onSave: _saveAerodynamic),
        _numericField('Shimmer',  _aeroCtrls['shimmer_percent']!,
            unit: '%',  onSave: _saveAerodynamic),
        _numericField('HNR',      _aeroCtrls['hnr_db']!,
            unit: 'dB', onSave: _saveAerodynamic),

        const SizedBox(height: 14),
        _groupLabel('C · Notes'),
        _textFieldGeneric(
          'Aerodynamic & acoustic notes',
          _aeroNotesCtrl,
          multi: true,
          onSave: _saveAerodynamic,
        ),
      ],
    );
  }

  // ── Section 5 body — Perceptual Evaluation (CAPE-V + GRBAS) ───────
  Widget _section5Body() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _groupLabel('A · Rater'),
        _textFieldGeneric(
          'Rater',
          _raterCtrl,
          hint: 'primary_clinician',
          onSave: _savePerceptual,
        ),
        Tooltip(
          message: 'Multiple raters in 4.0.7.24c',
          child: Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: OutlinedButton.icon(
              onPressed: null,
              icon: const Icon(Icons.add_rounded, size: 14),
              label: Text('Add rater',
                  style: GoogleFonts.dmSans(fontSize: 12)),
              style: OutlinedButton.styleFrom(
                foregroundColor: _inkGhost,
                side: BorderSide(color: _line),
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 6),
              ),
            ),
          ),
        ),

        const SizedBox(height: 6),
        _groupLabel('B · CAPE-V (0–100)'),
        _capevSliderRow('Overall severity', 'capev_overall_severity'),
        _capevSliderRow('Roughness',        'capev_roughness'),
        _capevSliderRow('Breathiness',      'capev_breathiness'),
        _capevSliderRow('Strain',           'capev_strain'),
        _capevSliderRow('Pitch',            'capev_pitch'),
        _capevSliderRow('Loudness',         'capev_loudness'),
        _textFieldGeneric(
          'Resonance notes',
          _capevResonanceCtrl,
          multi: true,
          onSave: _savePerceptual,
        ),

        const SizedBox(height: 14),
        _groupLabel('C · GRBAS (0–3 each)'),
        _grbasRow('Grade (G)',       'grbas_grade'),
        _grbasRow('Roughness (R)',   'grbas_roughness'),
        _grbasRow('Breathiness (B)', 'grbas_breathiness'),
        _grbasRow('Asthenia (A)',    'grbas_asthenia'),
        _grbasRow('Strain (S)',      'grbas_strain'),

        const SizedBox(height: 14),
        _groupLabel('D · Audio recording'),
        Tooltip(
          message: 'Coming in 4.0.7.24c',
          child: Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            margin:  const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color:        _amberSoft.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(8),
              border:       Border.all(color: _amber.withValues(alpha: 0.30)),
            ),
            child: Row(
              children: [
                Icon(Icons.mic_none_outlined, size: 18, color: _amber),
                const SizedBox(width: 8),
                Text('Audio recording — coming in 4.0.7.24c',
                    style: GoogleFonts.dmSans(
                        fontSize: 12,
                        color: _amber,
                        fontWeight: FontWeight.w500)),
              ],
            ),
          ),
        ),

        const SizedBox(height: 6),
        _groupLabel('E · Notes'),
        _textFieldGeneric(
          'Perceptual notes',
          _perceptualNotesCtrl,
          multi: true,
          onSave: _savePerceptual,
        ),
      ],
    );
  }

  // ── Section 6 body — Functional Voice ─────────────────────────────
  Widget _section6Body() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _groupLabel('A · Reading passage'),
        _textFieldGeneric('Passage used', _passageUsedCtrl,
            hint: 'Rainbow passage / Indian passage / clinic-specific',
            onSave: _saveFunctionalVoice),
        _textFieldGeneric('Reading passage observations',
            _readingPassageCtrl, multi: true, onSave: _saveFunctionalVoice),

        const SizedBox(height: 14),
        _groupLabel('B · Conversational sample'),
        _textFieldGeneric('Conversational sample observations',
            _convoSampleCtrl, multi: true, onSave: _saveFunctionalVoice),

        const SizedBox(height: 14),
        _groupLabel('C · Sustained vs connected'),
        _textFieldGeneric('Sustained phonation quality',
            _sustainedQualityCtrl, multi: true,
            onSave: _saveFunctionalVoice),
        _textFieldGeneric('Connected speech quality',
            _connectedQualityCtrl, multi: true,
            onSave: _saveFunctionalVoice),
        _textFieldGeneric(
            "Comparison notes — what's better, what's worse",
            _comparisonNotesCtrl, multi: true,
            onSave: _saveFunctionalVoice),

        const SizedBox(height: 14),
        _groupLabel('D · Fatigue testing'),
        _yesNo('Fatigue test conducted?', _fatigueTestConducted, (v) {
          setState(() => _fatigueTestConducted = v);
          _saveFunctionalVoice();
        }),
        if (_fatigueTestConducted) ...[
          _textFieldGeneric('Pre-load voice quality',
              _preLoadQualityCtrl, multi: true,
              onSave: _saveFunctionalVoice),
          _textFieldGeneric('Voice loading task — what was performed',
              _voiceLoadingTaskCtrl, multi: true,
              onSave: _saveFunctionalVoice),
          _textFieldGeneric('Post-load voice quality',
              _postLoadQualityCtrl, multi: true,
              onSave: _saveFunctionalVoice),
          _numericField('Time to voice fatigue', _timeToFatigueCtrl,
              unit: 'minutes', onSave: _saveFunctionalVoice),
        ],
      ],
    );
  }

  // ── Section 7 body — Task-Based Voice ─────────────────────────────
  Widget _section7Body() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _groupLabel('A · Loud voice'),
        _numericField('Maximum loudness achieved', _maxLoudDbCtrl,
            unit: 'dB SPL', onSave: _saveTaskBased),
        _textFieldGeneric('Quality at loud voice',
            _loudQualityCtrl, multi: true, onSave: _saveTaskBased),
        _yesNo('Strain noted at loud voice', _strainAtLoud, (v) {
          setState(() => _strainAtLoud = v);
          _saveTaskBased();
        }),

        const SizedBox(height: 14),
        _groupLabel('B · Soft voice'),
        _numericField('Minimum loudness achieved', _minLoudDbCtrl,
            unit: 'dB SPL', onSave: _saveTaskBased),
        _textFieldGeneric('Quality at soft voice',
            _softQualityCtrl, multi: true, onSave: _saveTaskBased),
        _yesNo('Voice break / aphonia at soft voice', _voiceBreakAtSoft,
            (v) {
          setState(() => _voiceBreakAtSoft = v);
          _saveTaskBased();
        }),

        const SizedBox(height: 14),
        _groupLabel('C · Pitch glide'),
        _textFieldGeneric('Highest pitch (Hz or musical note)',
            _highestPitchCtrl, hint: 'e.g. 880 Hz or A5',
            onSave: _saveTaskBased),
        _textFieldGeneric('Lowest pitch (Hz or musical note)',
            _lowestPitchCtrl,  hint: 'e.g. 110 Hz or A2',
            onSave: _saveTaskBased),
        _yesNo('Smooth glide?', _smoothPitchGlide, (v) {
          setState(() => _smoothPitchGlide = v);
          _saveTaskBased();
        }),
        _textFieldGeneric('Pitch break / register transition notes',
            _pitchBreakNotesCtrl, multi: true, onSave: _saveTaskBased),

        const SizedBox(height: 14),
        _groupLabel('D · Resonance'),
        _singleChips(
          'Resonance balance',
          const ['Balanced', 'Hyponasal', 'Hypernasal',
                 'Cul-de-sac', 'Mixed'],
          _resonanceBalance,
          (v) {
            setState(() => _resonanceBalance = v);
            _saveTaskBased();
          },
        ),
        _textFieldGeneric('Resonance observations',
            _resonanceObsCtrl, multi: true, onSave: _saveTaskBased),
      ],
    );
  }

  // ── Section 8 body — Special Populations ──────────────────────────
  // The chip in GROUP A routes which subform renders below. All
  // subform controllers persist in widget memory whether or not the
  // chip is currently selected, so toggling between population types
  // doesn't lose entered data within the session. On save, the
  // serialized payload includes every subform's data (not just the
  // active one), so a refresh restores the full state.
  Widget _section8Body() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _groupLabel('A · Population type'),
        _singleChips(
          'Population type',
          const [
            'Adult voice',
            'Transgender voice',
            'Puberty / pubertal voice mutation',
            'Pediatric voice',
            'Geriatric / aging voice',
            'Singer / occupational voice user',
          ],
          _populationType,
          (v) {
            setState(() => _populationType = v);
            _saveSpecialPopulations();
          },
        ),
        const SizedBox(height: 8),
        if (_populationType == null ||
            _populationType == 'Adult voice')
          _ghostNote(
              'Standard adult voice protocol applies. No special-population fields needed.'),
        if (_populationType == 'Transgender voice') ...[
          const SizedBox(height: 6),
          _groupLabel('B · Transgender voice'),
          _singleChips('Target gender',
              const ['Feminine', 'Masculine', 'Non-binary'],
              _trGender, (v) {
            setState(() => _trGender = v);
            _saveSpecialPopulations();
          }),
          // Auto-prefill hint pulled from Section 4's f0_mean_hz when
          // the SLP hasn't typed a value yet — keeps the flow moving
          // without overwriting clinician-entered values.
          _numericFieldWithPrefill(
            'Current F0',
            _trCurrentF0Ctrl,
            unit: 'Hz',
            prefillFrom: _aeroCtrls['f0_mean_hz']!.text,
            onSave: _saveSpecialPopulations,
          ),
          Row(
            children: [
              Expanded(
                child: _numericField('Target F0 — low',
                    _trTargetF0LowCtrl,
                    unit: 'Hz', onSave: _saveSpecialPopulations),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _numericField('Target F0 — high',
                    _trTargetF0HighCtrl,
                    unit: 'Hz', onSave: _saveSpecialPopulations),
              ),
            ],
          ),
          _textFieldGeneric('Resonance — formant frequencies',
              _trResonanceCtrl, multi: true,
              onSave: _saveSpecialPopulations),
          _textFieldGeneric('Intonation patterns',
              _trIntonationCtrl, multi: true,
              hint: 'Rising / falling / flat observations',
              onSave: _saveSpecialPopulations),
          _textFieldGeneric('Voice training history',
              _trTrainingHistCtrl, multi: true,
              onSave: _saveSpecialPopulations),
          _yesNo('Hormone therapy on?', _trHormoneOn, (v) {
            setState(() => _trHormoneOn = v);
            _saveSpecialPopulations();
          }),
          if (_trHormoneOn)
            _numericField('Hormone therapy duration', _trHormoneDurCtrl,
                unit: 'months', onSave: _saveSpecialPopulations),
        ],
        if (_populationType == 'Puberty / pubertal voice mutation') ...[
          const SizedBox(height: 6),
          _groupLabel('B · Puberty'),
          _numericField('Age at voice change onset', _pubAgeOnsetCtrl,
              unit: 'years', onSave: _saveSpecialPopulations),
          _singleChips('Mutation stability',
              const ['Stable', 'Unstable', 'Reverting (mutational falsetto)'],
              _pubMutationStability, (v) {
            setState(() => _pubMutationStability = v);
            _saveSpecialPopulations();
          }),
          _singleChips('Pitch breaks frequency',
              const ['Rare', 'Occasional', 'Frequent', 'Constant'],
              _pubPitchBreakFreq, (v) {
            setState(() => _pubPitchBreakFreq = v);
            _saveSpecialPopulations();
          }),
          _textFieldGeneric('Habitual pitch vs. expected',
              _pubHabitualPitchCtrl, multi: true,
              onSave: _saveSpecialPopulations),
          _textFieldGeneric('Notes', _pubNotesCtrl, multi: true,
              onSave: _saveSpecialPopulations),
        ],
        if (_populationType == 'Pediatric voice') ...[
          const SizedBox(height: 6),
          _groupLabel('B · Pediatric voice'),
          _textFieldGeneric('Vocal hygiene awareness (parent + child)',
              _pedHygieneCtrl, multi: true,
              onSave: _saveSpecialPopulations),
          _textFieldGeneric('Voice abuse / overuse patterns',
              _pedAbusePatternsCtrl, multi: true,
              hint: 'Yelling, vocal play, sports',
              onSave: _saveSpecialPopulations),
          _textFieldGeneric('Behavioral concerns',
              _pedBehavioralCtrl, multi: true,
              onSave: _saveSpecialPopulations),
          _textFieldGeneric('School / daycare voice load',
              _pedSchoolLoadCtrl, multi: true,
              onSave: _saveSpecialPopulations),
        ],
        if (_populationType == 'Geriatric / aging voice') ...[
          const SizedBox(height: 6),
          _groupLabel('B · Geriatric voice'),
          _yesNo('Presbylaryngis signs', _geriPresbylaryngis, (v) {
            setState(() => _geriPresbylaryngis = v);
            _saveSpecialPopulations();
          }),
          if (_geriPresbylaryngis)
            _textFieldGeneric('Presbylaryngis details',
                _geriPresbylDetailsCtrl, multi: true,
                onSave: _saveSpecialPopulations),
          _textFieldGeneric('Functional voice load',
              _geriFunctionalLoadCtrl, multi: true,
              onSave: _saveSpecialPopulations),
          _textFieldGeneric('Comorbidities affecting voice',
              _geriComorbiditiesCtrl, multi: true,
              hint: "Parkinson's, COPD, hearing loss, dental",
              onSave: _saveSpecialPopulations),
          _textFieldGeneric('Medication review',
              _geriMedsCtrl, multi: true,
              onSave: _saveSpecialPopulations),
        ],
        if (_populationType == 'Singer / occupational voice user') ...[
          const SizedBox(height: 6),
          _groupLabel('B · Singer / occupational'),
          _textFieldGeneric('Voice classification',
              _singerVoiceClassCtrl,
              hint: 'soprano / alto / tenor / bass / occupational speaker',
              onSave: _saveSpecialPopulations),
          _textFieldGeneric('Repertoire / vocal demands',
              _singerRepertoireCtrl, multi: true,
              onSave: _saveSpecialPopulations),
          _textFieldGeneric('Training background',
              _singerTrainingCtrl, multi: true,
              onSave: _saveSpecialPopulations),
          _numericField('Performance schedule load',
              _singerScheduleHrsCtrl, unit: 'hrs/week',
              onSave: _saveSpecialPopulations),
          const SizedBox(height: 4),
          _ghostNote('Singing Voice Handicap Index — see Section 12.'),
        ],
      ],
    );
  }

  // ── Section 10 body — Differential Diagnosis ──────────────────────
  Widget _section10Body() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _groupLabel('A · Likely diagnosis'),
        _textFieldGeneric(
          'Primary diagnosis (working hypothesis)',
          _ddPrimaryDxCtrl,
          multi: true,
          hint: "What you're leaning toward, in your own words.",
          onSave: _saveDifferentialDiagnosis,
        ),

        const SizedBox(height: 14),
        _groupLabel('B · Etiology category'),
        _singleChips(
          'Etiology',
          const [
            'Behavioral', 'Organic', 'Neurogenic',
            'Psychogenic', 'Iatrogenic', 'Functional', 'Mixed',
          ],
          _ddEtiologyCategory,
          (v) {
            setState(() => _ddEtiologyCategory = v);
            _saveDifferentialDiagnosis();
          },
        ),
        _textFieldGeneric('Etiology notes', _ddEtiologyNotesCtrl,
            multi: true, onSave: _saveDifferentialDiagnosis),

        const SizedBox(height: 14),
        _groupLabel('C · Rule-outs to consider'),
        for (var i = 0; i < _ddRuleOutCtrls.length; i++)
          _ruleOutRow(i),
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
        _multiChips(
          'Contributing factors',
          const [
            'Vocal abuse / misuse', 'LPR / GERD', 'Allergies',
            'Smoking', 'Alcohol', 'Hydration', 'Stress / anxiety',
            'Sleep deprivation', 'Hormonal',
            'Occupational vocal load', 'Other',
          ],
          _ddContributingFactors,
          (v, sel) {
            setState(() {
              if (sel) {
                _ddContributingFactors.add(v);
              } else {
                _ddContributingFactors.remove(v);
              }
            });
            _saveDifferentialDiagnosis();
          },
        ),
        if (_ddContributingFactors.contains('Other'))
          _textFieldGeneric('Other contributing factors',
              _ddOtherContribCtrl, multi: true,
              onSave: _saveDifferentialDiagnosis),

        const SizedBox(height: 14),
        _groupLabel('E · Synthesis'),
        _textFieldGeneric(
          'Differential reasoning — why this diagnosis over others',
          _ddSynthesisCtrl,
          multi: true,
          onSave: _saveDifferentialDiagnosis,
        ),
      ],
    );
  }

  Widget _ruleOutRow(int index) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: Focus(
              onFocusChange: (f) {
                if (!f) _saveDifferentialDiagnosis();
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
                _saveDifferentialDiagnosis();
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

  // ── Section 12 body — Voice Handicap & Quality of Life ────────────
  Widget _section12Body() {
    final v10 = _vhi10Total;
    final v10Flagged = (v10 ?? 0) > 11;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _groupLabel('A · VHI-10 (0 Never – 4 Always)'),
        for (var i = 1; i <= _vhi10Items.length || i <= 10; i++)
          if (i <= 10) _likertRow(
            '$i. ${_vhi10Wording[i - 1]}',
            value: _vhi10Items[i] ?? 0,
            min: 0, max: 4,
            onChanged: (v) {
              setState(() => _vhi10Items[i] = v);
            },
            onCommit: _saveQol,
          ),
        const SizedBox(height: 6),
        _qolTotalRow(
          label: 'VHI-10 total',
          total: v10,
          maxScore: 40,
          flagged: v10Flagged,
          flagText: 'Total > 11 suggests significant voice handicap',
        ),
        if (_vhi10TotalLoaded != null && _vhi10TotalLoaded != v10) ...[
          const SizedBox(height: 4),
          Text('Last saved total: $_vhi10TotalLoaded',
              style: GoogleFonts.dmSans(
                  fontSize: 11, color: _inkGhost,
                  fontStyle: FontStyle.italic)),
        ],

        const SizedBox(height: 14),
        _groupLabel('B · VHI-30 (longer alternative)'),
        _yesNo('Use VHI-30 instead of VHI-10?', _useVhi30, (v) {
          setState(() => _useVhi30 = v);
          _saveQol();
        }),
        if (_useVhi30) ...[
          for (var i = 1; i <= 30; i++)
            _likertRow(
              'F${i <= 10 ? i : (i <= 20 ? "P${i - 10}" : "E${i - 20}")}. VHI-30 item $i',
              value: _vhi30Items[i] ?? 0,
              min: 0, max: 4,
              onChanged: (v) {
                setState(() => _vhi30Items[i] = v);
              },
              onCommit: _saveQol,
            ),
          const SizedBox(height: 6),
          _qolSubscaleRow('Functional (F1–F10)', _vhi30FunctionalTotal, 40),
          _qolSubscaleRow('Physical (P1–P10)',   _vhi30PhysicalTotal,   40),
          _qolSubscaleRow('Emotional (E1–E10)',  _vhi30EmotionalTotal,  40),
          _qolTotalRow(
            label: 'VHI-30 total',
            total: _vhi30Total,
            maxScore: 120,
            flagged: _vhi30Total > 33,
            flagText: 'Total > 33 suggests significant voice handicap',
          ),
          if (_vhi30TotalLoaded != null && _vhi30TotalLoaded != _vhi30Total) ...[
            const SizedBox(height: 4),
            Text('Last saved total: $_vhi30TotalLoaded',
                style: GoogleFonts.dmSans(
                    fontSize: 11, color: _inkGhost,
                    fontStyle: FontStyle.italic)),
          ],
        ],

        const SizedBox(height: 14),
        _groupLabel('C · V-RQOL (1 None – 5 Problem is "as bad as it can be")'),
        for (var i = 1; i <= 10; i++)
          _likertRow(
            '$i. V-RQOL item $i',
            value: _vrqolItems[i] ?? 1,
            min: 1, max: 5,
            onChanged: (v) {
              setState(() => _vrqolItems[i] = v);
            },
            onCommit: _saveQol,
          ),
        const SizedBox(height: 6),
        _qolTotalRow(
          label: 'V-RQOL raw total',
          total: _vrqolItems.isEmpty ? null : _vrqolTotal,
          maxScore: 50,
        ),
        if (_vrqolItems.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(
            'Standardized 0–100: ${_vrqolStandardized().toStringAsFixed(1)} (higher = better)',
            style: GoogleFonts.dmSans(
                fontSize: 11, color: _inkGhost),
          ),
        ],
        if (_vrqolTotalLoaded != null &&
            _vrqolTotalLoaded != (_vrqolItems.isEmpty ? null : _vrqolTotal)) ...[
          const SizedBox(height: 4),
          Text('Last saved raw total: $_vrqolTotalLoaded',
              style: GoogleFonts.dmSans(
                  fontSize: 11, color: _inkGhost,
                  fontStyle: FontStyle.italic)),
        ],

        const SizedBox(height: 14),
        _groupLabel('D · Singing Voice Handicap Index'),
        _yesNo('Use SVHI (singer / occupational only)?',
            _useSvhi, (v) {
          setState(() => _useSvhi = v);
          _saveQol();
        }),
        if (_useSvhi) ...[
          for (var i = 1; i <= 36; i++)
            _likertRow('$i. SVHI item $i',
                value: _svhiItems[i] ?? 0,
                min: 0, max: 4,
                onChanged: (v) {
                  setState(() => _svhiItems[i] = v);
                },
                onCommit: _saveQol),
          const SizedBox(height: 6),
          _qolTotalRow(
            label: 'SVHI total',
            total: _svhiTotal,
            maxScore: 144,
            flagged: _svhiTotal > 30,
            flagText: 'SVHI > 30 suggests singing-voice handicap',
          ),
          if (_svhiTotalLoaded != null && _svhiTotalLoaded != _svhiTotal) ...[
            const SizedBox(height: 4),
            Text('Last saved total: $_svhiTotalLoaded',
                style: GoogleFonts.dmSans(
                    fontSize: 11, color: _inkGhost,
                    fontStyle: FontStyle.italic)),
          ],
        ],
      ],
    );
  }

  /// V-RQOL standardized 0–100 score per Hogikyan & Sethuraman 1999:
  /// (raw - 10) / 40 * 100, then inverted so higher = better. Range
  /// 0..100. Empty input returns 100 (ideal — no symptom load yet).
  double _vrqolStandardized() {
    if (_vrqolItems.isEmpty) return 100.0;
    final raw = _vrqolTotal;
    final clamped = raw.clamp(10, 50);
    return ((50 - clamped) / 40) * 100.0;
  }

  static const List<String> _vhi10Wording = [
    'My voice makes it difficult for people to hear me',
    'People have difficulty understanding me in a noisy room',
    "My family has difficulty hearing me when I call them throughout the house",
    'I use the phone less often than I would like',
    'I tend to avoid groups of people because of my voice',
    'I speak with friends, neighbors, or relatives less often because of my voice',
    "People ask \"What's wrong with your voice?\"",
    'My voice difficulties restrict personal and social life',
    'I feel left out of conversations because of my voice',
    'My voice problem causes me to lose income',
  ];

  // ── Section 15 body — Final Clinical Impression & Plan ────────────
  Widget _section15Body() {
    // GROUP C reads etiology from Section 10 unless the override is on.
    final etiologyDisplay = _ciOverrideEtiology
        ? (_ciEtiologyOverride ?? '—')
        : (_ddEtiologyCategory ?? 'Pick in Section 10');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _groupLabel('A · Final diagnosis'),
        _textFieldGeneric('Final diagnosis', _ciFinalDxCtrl,
            multi: true, onSave: _saveClinicalImpression),
        _textFieldGeneric('ICD-style code', _ciIcdCodeCtrl,
            hint: 'e.g. R49.0 Dysphonia',
            onSave: _saveClinicalImpression),
        _singleChips(
          'Diagnosis confidence',
          const ['Provisional', 'Working', 'Confirmed'],
          _ciDxConfidence,
          (v) {
            setState(() => _ciDxConfidence = v);
            _saveClinicalImpression();
          },
        ),

        const SizedBox(height: 14),
        _groupLabel('B · Severity'),
        _singleChips('Severity grading',
            const ['Mild', 'Moderate', 'Severe', 'Profound'],
            _ciSeverity, (v) {
          setState(() => _ciSeverity = v);
          _saveClinicalImpression();
        }),
        _textFieldGeneric('Severity rationale',
            _ciSeverityRationaleCtrl, multi: true,
            onSave: _saveClinicalImpression),

        const SizedBox(height: 14),
        _groupLabel('C · Etiology'),
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: _tealSoft.withValues(alpha: 0.45),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: _teal.withValues(alpha: 0.4)),
                ),
                child: Text(etiologyDisplay,
                    style: GoogleFonts.dmSans(
                        fontSize: 12, color: _teal,
                        fontWeight: FontWeight.w500)),
              ),
              const SizedBox(width: 8),
              Text(
                _ciOverrideEtiology
                    ? 'Override ON'
                    : 'Auto-pulled from Section 10',
                style: GoogleFonts.dmSans(
                    fontSize: 11,
                    color: _inkGhost,
                    fontStyle: FontStyle.italic),
              ),
            ],
          ),
        ),
        _yesNo('Override etiology?', _ciOverrideEtiology, (v) {
          setState(() => _ciOverrideEtiology = v);
          _saveClinicalImpression();
        }),
        if (_ciOverrideEtiology)
          _singleChips(
            'Override etiology value',
            const [
              'Behavioral', 'Organic', 'Neurogenic',
              'Psychogenic', 'Iatrogenic', 'Functional', 'Mixed',
            ],
            _ciEtiologyOverride,
            (v) {
              setState(() => _ciEtiologyOverride = v);
              _saveClinicalImpression();
            },
          ),

        const SizedBox(height: 14),
        _groupLabel('D · Management plan'),
        _multiChips(
          'Recommended interventions',
          const [
            'Voice therapy', 'Vocal hygiene counseling',
            'Medical referral (ENT)', 'Surgical consult',
            'Behavioral therapy', 'Stress management',
            'Reflux management', 'Hydration protocol',
            'Vocal rest', 'Singing-voice specialist',
          ],
          _ciInterventions,
          (v, sel) {
            setState(() {
              if (sel) {
                _ciInterventions.add(v);
              } else {
                _ciInterventions.remove(v);
              }
            });
            _saveClinicalImpression();
          },
        ),
        _textFieldGeneric('Therapy protocol details',
            _ciTherapyProtocolCtrl, multi: true,
            hint: 'RVT, SOVT, LSVT, Lee Silverman, etc.',
            onSave: _saveClinicalImpression),
        _numericField('Estimated session count',
            _ciSessionCountCtrl, unit: 'sessions',
            onSave: _saveClinicalImpression),
        _singleChips('Frequency',
            const ['Weekly', 'Biweekly', 'Monthly', 'As needed'],
            _ciFrequency, (v) {
          setState(() => _ciFrequency = v);
          _saveClinicalImpression();
        }),
        _textFieldGeneric('Discharge criteria / outcome targets',
            _ciDischargeCriteriaCtrl, multi: true,
            onSave: _saveClinicalImpression),

        const SizedBox(height: 14),
        _groupLabel('E · Referrals'),
        _yesNo('ENT referral needed?', _ciEntReferralNeeded, (v) {
          setState(() => _ciEntReferralNeeded = v);
          _saveClinicalImpression();
        }),
        if (_ciEntReferralNeeded)
          _textFieldGeneric('ENT referral reason',
              _ciEntReferralReasonCtrl, multi: true,
              onSave: _saveClinicalImpression),
        _textFieldGeneric('Other referrals',
            _ciOtherReferralsCtrl, multi: true,
            onSave: _saveClinicalImpression),

        const SizedBox(height: 14),
        _groupLabel('F · Vocal hygiene plan'),
        _multiChips(
          'Hygiene items',
          const [
            'Hydration ≥ 2L/day', 'Reduced caffeine',
            'Reduced alcohol', 'Smoking cessation',
            'Voice rest periods', 'Reduced throat clearing',
            'Reflux precautions', 'Humidification',
            'Reduced talking on phone', 'Reduced singing',
          ],
          _ciHygieneItems,
          (v, sel) {
            setState(() {
              if (sel) {
                _ciHygieneItems.add(v);
              } else {
                _ciHygieneItems.remove(v);
              }
            });
            _saveClinicalImpression();
          },
        ),
        _textFieldGeneric('Personalized hygiene notes',
            _ciHygieneNotesCtrl, multi: true,
            onSave: _saveClinicalImpression),
      ],
    );
  }

  // ── Shared 24c primitives ─────────────────────────────────────────

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

  /// Numeric field with an optional prefill hint — when [prefillFrom]
  /// is non-empty AND [ctrl] is empty, the prefill value populates
  /// the input on next focus loss as a soft suggestion.
  Widget _numericFieldWithPrefill(
    String label,
    TextEditingController ctrl, {
    required String unit,
    required String prefillFrom,
    required VoidCallback onSave,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _numericField(label, ctrl, unit: unit, onSave: onSave),
        if (prefillFrom.trim().isNotEmpty && ctrl.text.trim().isEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: GestureDetector(
              onTap: () {
                ctrl.text = prefillFrom.trim();
                onSave();
                setState(() {});
              },
              child: Text(
                'Prefill from Section 4 F0 = $prefillFrom Hz',
                style: GoogleFonts.dmSans(
                    fontSize: 11,
                    color: _amber,
                    fontStyle: FontStyle.italic,
                    decoration: TextDecoration.underline),
              ),
            ),
          ),
      ],
    );
  }

  /// 0-N (or 1-N) Likert row with a slider snapped to integer values
  /// and a live readout. Used by VHI-10, VHI-30, V-RQOL, SVHI.
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
                      fontSize: 12,
                      color: _ink,
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

  Widget _qolTotalRow({
    required String label,
    required int? total,
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
          Text('$label: ${total ?? '—'} / $maxScore',
              style: GoogleFonts.dmSans(
                  fontSize: 13,
                  color: color,
                  fontWeight: FontWeight.w600)),
          if (flagged && flagText != null) ...[
            const SizedBox(height: 2),
            Text(flagText,
                style: GoogleFonts.dmSans(
                    fontSize: 11,
                    color: color,
                    fontStyle: FontStyle.italic)),
          ],
        ],
      ),
    );
  }

  Widget _qolSubscaleRow(String label, int total, int maxScore) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text('$label: $total / $maxScore',
          style: GoogleFonts.dmSans(
              fontSize: 12, color: _inkGhost)),
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
              color:        _tealSoft.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(8),
              border:       Border.all(color: _tealSoft),
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
        _outcomeHeaderRow(),
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

  Widget _outcomeHeaderRow() {
    return Row(
      children: [
        const Expanded(flex: 4, child: SizedBox()),
        Expanded(flex: 2, child: _headCell('Baseline')),
        Expanded(flex: 2, child: _headCell('Latest')),
        Expanded(flex: 2, child: _headCell('Δ')),
      ],
    );
  }

  Widget _headCell(String text) => Text(text,
      style: GoogleFonts.syne(
          fontSize: 9,
          fontWeight: FontWeight.w600,
          color: _inkGhost,
          letterSpacing: 1.2));

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
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            flex: 4,
            child: Text('${r.label}${r.unit.isEmpty ? '' : ' (${r.unit})'}',
                style: GoogleFonts.dmSans(fontSize: 12, color: _ink)),
          ),
          Expanded(flex: 2, child: _outcomeCell(r.baseline)),
          Expanded(flex: 2, child: _outcomeCell(r.latest)),
          Expanded(
            flex: 2,
            child: Text(deltaText,
                style: GoogleFonts.dmSans(
                    fontSize: 12,
                    color: color,
                    fontWeight: FontWeight.w600)),
          ),
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
    TextInputType? keyboardType,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: GoogleFonts.dmSans(
                  fontSize: 12,
                  color: _inkGhost,
                  fontWeight: FontWeight.w500)),
          const SizedBox(height: 4),
          Focus(
            onFocusChange: (focused) {
              if (!focused) _saveCaseHistory();
            },
            child: TextField(
              controller: ctrl,
              maxLines: multi ? 3 : 1,
              keyboardType: keyboardType ?? TextInputType.text,
              style: GoogleFonts.dmSans(fontSize: 13, color: _ink),
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: GoogleFonts.dmSans(
                    fontSize: 12, color: _inkGhost.withValues(alpha: 0.6)),
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
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Expanded(
            child: Text(label,
                style: GoogleFonts.dmSans(
                    fontSize: 13, color: _ink, fontWeight: FontWeight.w500)),
          ),
          _yesNoChip('Yes', value, () => onChanged(true)),
          const SizedBox(width: 6),
          _yesNoChip('No', !value, () => onChanged(false)),
        ],
      ),
    );
  }

  Widget _yesNoWithText(
    String label,
    bool value,
    TextEditingController ctrl,
    ValueChanged<bool> onChanged,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _yesNo(label, value, onChanged),
          if (value)
            Focus(
              onFocusChange: (f) {
                if (!f) _saveCaseHistory();
              },
              child: TextField(
                controller: ctrl,
                style: GoogleFonts.dmSans(fontSize: 13, color: _ink),
                decoration: InputDecoration(
                  hintText: 'Details',
                  hintStyle: GoogleFonts.dmSans(
                      fontSize: 12, color: _inkGhost.withValues(alpha: 0.6)),
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ),
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
                  fontSize: 12,
                  color: _inkGhost,
                  fontWeight: FontWeight.w500)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final o in options)
                _yesNoChip(o, selected == o, () => onChanged(o == selected ? null : o)),
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
                  fontSize: 12,
                  color: _inkGhost,
                  fontWeight: FontWeight.w500)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
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
                    fontSize: 13,
                    color: _ink,
                    fontWeight: FontWeight.w500)),
          ),
          OutlinedButton.icon(
            onPressed: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: value ?? DateTime.now(),
                firstDate: DateTime(2010),
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

  // ── 24b primitives — numeric field, slider row, GRBAS row ─────────

  /// Numeric (decimal) input with a unit label and optional reference
  /// hint shown ghost-italic below. Saves on focus loss via [onSave].
  Widget _numericField(
    String label,
    TextEditingController ctrl, {
    required String unit,
    String? reference,
    required VoidCallback onSave,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: GoogleFonts.dmSans(
                  fontSize: 12,
                  color: _inkGhost,
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
          if (reference != null) ...[
            const SizedBox(height: 4),
            Text(reference,
                style: GoogleFonts.dmSans(
                    fontSize: 11,
                    color: _inkGhost,
                    fontStyle: FontStyle.italic)),
          ],
        ],
      ),
    );
  }

  /// Text field with caller-controlled save dispatcher (so the same
  /// primitive can be reused across Sections 4–7 without each one
  /// having to reach for _saveCaseHistory by default).
  Widget _textFieldGeneric(
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
                  fontSize: 12,
                  color: _inkGhost,
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
                    fontSize: 12, color: _inkGhost.withValues(alpha: 0.6)),
                border: const OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// CAPE-V 0–100 slider with the live integer value at the end of
  /// the row. Slider snaps to integer values via divisions: 100; the
  /// row stores ints in _capev so the persisted column receives
  /// 0–100 rather than a 0.0–1.0 float.
  Widget _capevSliderRow(String label, String key) {
    final v = _capev[key] ?? 0;
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
                        fontSize: 12,
                        color: _inkGhost,
                        fontWeight: FontWeight.w500)),
              ),
              Text('$v',
                  style: GoogleFonts.dmSans(
                      fontSize: 13,
                      color: _ink,
                      fontWeight: FontWeight.w600)),
              Text(' / 100',
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
              value: v.toDouble(),
              min: 0,
              max: 100,
              divisions: 100,
              onChanged: (d) => setState(() => _capev[key] = d.toInt()),
              onChangeEnd: (_) => _savePerceptual(),
            ),
          ),
        ],
      ),
    );
  }

  /// GRBAS 0–3 chip picker. Single-select; tapping the active value
  /// clears it (allows the SLP to leave a scale unrated rather than
  /// being forced to commit to 0).
  Widget _grbasRow(String label, String key) {
    final v = _grbas[key];
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Expanded(
            child: Text(label,
                style: GoogleFonts.dmSans(
                    fontSize: 12,
                    color: _ink,
                    fontWeight: FontWeight.w500)),
          ),
          for (var i = 0; i <= 3; i++)
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: GestureDetector(
                onTap: () {
                  setState(() => _grbas[key] = (v == i) ? null : i);
                  _savePerceptual();
                },
                child: Container(
                  width: 32,
                  height: 28,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color:  v == i ? _teal : Colors.white,
                    border: Border.all(color: v == i ? _teal : _line),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text('$i',
                      style: GoogleFonts.dmSans(
                          fontSize: 12,
                          color: v == i ? Colors.white : _ink,
                          fontWeight: FontWeight.w500)),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ── RSI primitives ─────────────────────────────────────────────────
  Widget _rsiRow(String label, String key) {
    final v = _rsi[key] ?? 0;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: GoogleFonts.dmSans(fontSize: 12, color: _ink)),
          const SizedBox(height: 4),
          Row(
            children: [
              for (var i = 0; i <= 5; i++)
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: GestureDetector(
                    onTap: () {
                      setState(() => _rsi[key] = i);
                      _saveCaseHistory();
                    },
                    child: Container(
                      width: 32,
                      height: 28,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: v == i
                            ? _teal
                            : Colors.white,
                        border: Border.all(
                            color: v == i ? _teal : _line),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text('$i',
                          style: GoogleFonts.dmSans(
                              fontSize: 12,
                              color: v == i ? Colors.white : _ink,
                              fontWeight: FontWeight.w500)),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _rsiTotalRow() {
    final total = _rsiTotal;
    final flagged = total > 13;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      decoration: BoxDecoration(
        color:        flagged
            ? _amberSoft.withValues(alpha: 0.5)
            : _tealSoft.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(8),
        border:       Border.all(
            color: flagged ? _amber : _tealSoft),
      ),
      child: Row(
        children: [
          Text('RSI total: $total / 45',
              style: GoogleFonts.dmSans(
                  fontSize: 13,
                  color: flagged ? _amber : _teal,
                  fontWeight: FontWeight.w600)),
          if (flagged) ...[
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                'RSI > 13 suggests LPR — consider ENT/GI consult',
                style: GoogleFonts.dmSans(
                    fontSize: 11, color: _amber, fontStyle: FontStyle.italic),
              ),
            ),
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
