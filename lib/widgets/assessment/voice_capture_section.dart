// lib/widgets/assessment/voice_capture_section.dart
//
// Phase 4.0.7.24a — voice assessment surface, populated for the
// trimmed protocol Sections 1 (Detailed Case History + RSI), 2
// (Laryngeal Examination), 11 (Outcome Tracking). Sections 4, 5, 6,
// 7, 8, 10, 12, 15 are stubbed for follow-up commits 24b/c.
//
// Skipped sections per the Indian-clinic protocol cut: 3 (Advanced
// Acoustic), 9 (Stimulability), 13 (Red Flags), 14 (Imaging).
//
// Save model: each section debounces on blur of its TextField group
// and PATCHes the corresponding jsonb column. RSI total auto-
// recalculates whenever any of its 9 items change.

import 'package:flutter/material.dart';
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
      final outcome = await _service.compareBaselineToLatest(widget.clientId);
      if (!mounted) return;
      setState(() {
        _assessment = a;
        _outcome    = outcome;
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
        _stubSection(number: 4, title: 'Aerodynamic Measures',
            tagline: 'MPT, s/z, F0, jitter, shimmer, HNR.',
            comingIn: '4.0.7.24b'),
        const SizedBox(height: 10),
        _stubSection(number: 5, title: 'Perceptual Evaluation',
            tagline: 'CAPE-V + GRBAS rating from clinician samples.',
            comingIn: '4.0.7.24b'),
        const SizedBox(height: 10),
        _stubSection(number: 6, title: 'Functional Voice',
            tagline: 'Conversational voice across functional contexts.',
            comingIn: '4.0.7.24b'),
        const SizedBox(height: 10),
        _stubSection(number: 7, title: 'Task-Based Sampling',
            tagline: 'Sustained vowels, sentences, reading, conversation.',
            comingIn: '4.0.7.24b'),
        const SizedBox(height: 10),
        _stubSection(number: 8, title: 'Special Populations',
            tagline: 'Pediatric, geriatric, transgender voice considerations.',
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
        _stubSection(number: 12, title: 'Voice Handicap & QoL',
            tagline: 'VHI-10, VHI-30, V-RQOL self-report.',
            comingIn: '4.0.7.24c'),
        const SizedBox(height: 10),
        _stubSection(number: 15, title: 'Clinical Impression & Plan',
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
