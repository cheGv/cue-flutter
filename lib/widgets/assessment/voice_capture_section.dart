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
      // 24b — typed-table reads run in parallel; both soft-fail to {}
      // so a fresh baseline lands without surfacing a load error.
      final results = await Future.wait([
        _service.loadTypedMeasures(
            voiceAssessmentId: a.id,
            tableName: 'voice_aerodynamic_measures'),
        _service.loadTypedMeasures(
            voiceAssessmentId: a.id,
            tableName: 'voice_perceptual_ratings'),
        _service.compareBaselineToLatest(widget.clientId),
      ]);
      _hydrateAerodynamic(results[0] as Map<String, dynamic>);
      _hydratePerceptual(results[1] as Map<String, dynamic>);
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
        _stubSection(number: 8, title: 'Special Populations',
            tagline: 'Transgender voice, puberty, pediatric, geriatric.',
            comingIn: '4.0.7.24c'),
        const SizedBox(height: 10),
        _stubSection(number: 10, title: 'Differential Diagnosis',
            tagline: 'Functional vs organic vs neurogenic vs psychogenic.',
            comingIn: '4.0.7.24c'),
        const SizedBox(height: 10),
        _section(id: 'sec11', number: 11, title: 'Outcome Tracking',
            tagline: 'Baseline vs most recent follow-up across all measures.',
            child: _section11Body()),
        const SizedBox(height: 10),
        _stubSection(number: 12, title: 'Voice Handicap & Quality of Life',
            tagline: 'VHI-10, VHI-30, V-RQOL self-report.',
            comingIn: '4.0.7.24c'),
        const SizedBox(height: 10),
        _stubSection(number: 15, title: 'Final Clinical Impression & Plan',
            tagline: 'Diagnosis, prognosis, treatment plan, attestation.',
            comingIn: '4.0.7.24c'),
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
