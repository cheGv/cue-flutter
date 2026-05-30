// lib/widgets/assessment/cas_assessment_surface.dart
//
// Phase 4.0.7.28 (COMMIT 2) — Pediatric CAS (Childhood Apraxia of
// Speech) capture surface. Wired on clinical_area 'pediatric-cas',
// mirroring the ped_dysarthria capture pattern (CAS's closest
// differential — both carry typed child tables and DDK rates).
//
// Framing is DSM-5-TR-correct: CAS has no apraxia-specific diagnostic
// criteria; it sits inside the Speech Sound Disorder envelope. This
// surface structures ASHA-2007 consensus-marker evidence and two LIVE
// within-child pattern readouts (length-gradient slope, AMR/SMR
// dissociation) — NEITHER of which depends on population norms. It
// NEVER prints a diagnosis, a "consistent with CAS" verdict, or any
// human-quantifying score. The clinical call is the SLP's.
//
// DDK SD-banding is wired but DORMANT: it reads cas_ddk_norms (empty at
// ship) and shows "norm reference pending validation" until verified,
// method-specified published norms are loaded. It never fabricates or
// interpolates a band.
//
// Save model (see CasAssessmentService for the why): cas_assessments is
// a flat typed table patched per logical group; the multi-row child
// tables (cas_length_gradient, cas_ddk) carry NO unique constraint, so
// the canonical row set is seeded once on load (capturing row ids) and
// every edit is a deterministic update-by-id. Persistence is direct
// save-on-change / save-on-blur — no Timer debounce, matching the
// dysarthria surface.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../services/cas_assessment_service.dart';

// Palette — reused verbatim from the ped_dysarthria capture surface so
// the two sibling motor-speech surfaces read identically. (Teal
// migration per the design-language spine is a later per-surface pass,
// applied to both surfaces together.)
const Color _ink       = Color(0xFF0E1C36);
const Color _inkGhost  = Color(0xFF6B7690);
const Color _line      = Color(0xFFE6DDCA);
const Color _teal      = Color(0xFF2A8F84);
const Color _tealSoft  = Color(0xFFD6E8E5);
const Color _amber     = Color(0xFFD68A2B);
const Color _amberSoft = Color(0xFFF4E4C4);
const Color _coral     = Color(0xFFC25450);

// 3-state presence scale (markers + differential evidence). Stored
// canonical lowercase; displayed title-case.
const List<String> _kPresenceLabels = ['Present', 'Emerging', 'Absent'];
const Map<String, String> _kPresenceLabelToValue = {
  'Present': 'present',
  'Emerging': 'emerging',
  'Absent': 'absent',
};
const Map<String, String> _kPresenceValueToLabel = {
  'present': 'Present',
  'emerging': 'Emerging',
  'absent': 'Absent',
};

// Length-gradient accuracy scale. Displayed ✓ / ~ / ✗; stored canonical
// accurate / partial / inaccurate (the slope readout needs an ordered
// value).
const List<String> _kAccuracyLabels = ['✓', '~', '✗'];
const Map<String, String> _kAccuracyLabelToValue = {
  '✓': 'accurate',
  '~': 'partial',
  '✗': 'inaccurate',
};
const Map<String, String> _kAccuracyValueToLabel = {
  'accurate': '✓',
  'partial': '~',
  'inaccurate': '✗',
};

// Canonical length-gradient rows (level_order 1–5). Persisted to
// cas_length_gradient; `display` is the SLP-facing row label.
const List<({int order, String label, String tokens, String display})>
    _kCasLevels = [
  (order: 1, label: 'CV', tokens: 'ba, mu', display: 'CV — ba, mu'),
  (order: 2, label: 'CVC', tokens: 'cup, dog', display: 'CVC — cup, dog'),
  (order: 3, label: 'bisyllabic', tokens: 'baby, water',
      display: 'Bisyllabic — baby, water'),
  (order: 4, label: 'trisyllabic', tokens: 'banana',
      display: 'Trisyllabic — banana'),
  (order: 5, label: 'polysyllabic_phrase', tokens: 'butterfly, "I want more"',
      display: 'Polysyllabic / phrase — butterfly, "I want more"'),
];

// DDK task rows. pa/ta/ka feed AMR; pataka feeds SMR.
const List<String> _kDdkTasks = ['pa', 'ta', 'ka', 'pataka'];

class CasAssessmentSurface extends StatefulWidget {
  final String clientId;
  const CasAssessmentSurface({super.key, required this.clientId});

  @override
  State<CasAssessmentSurface> createState() => _CasAssessmentSurfaceState();
}

class _CasAssessmentSurfaceState extends State<CasAssessmentSurface> {
  final _service = CasAssessmentService.instance;

  String? _assessmentId;
  bool _loading = true;
  String? _error;

  // ── Section B — ASHA consensus markers ───────────────────────────
  String? _markerInconsistent;
  String? _markerTransitions;
  String? _markerProsody;
  final _markerInconsistentNotesCtrl = TextEditingController();
  final _markerTransitionsNotesCtrl = TextEditingController();
  final _markerProsodyNotesCtrl = TextEditingController();

  // ── Section C — Length-gradient probe ────────────────────────────
  final Map<int, String?> _lenAccuracy = {}; // level_order → canonical
  final Map<int, String> _lenRowIds = {};    // level_order → row id

  // ── Section D — DDK panel ────────────────────────────────────────
  final _ageMonthsCtrl = TextEditingController();
  final _ddkPaCtrl = TextEditingController();
  final _ddkTaCtrl = TextEditingController();
  final _ddkKaCtrl = TextEditingController();
  final _ddkPatakaCtrl = TextEditingController();
  bool _ddkSequenceErrors = false;
  final Map<String, String> _ddkRowIds = {}; // task → row id
  List<Map<String, dynamic>> _norms = [];

  // ── Section E — Supporting & differential evidence ───────────────
  final _oralMechExamCtrl = TextEditingController();
  String? _gropingSearching;
  String? _vowelErrors;
  String? _receptiveExpressiveGap;
  final _consonantInventoryCtrl = TextEditingController();
  final _vowelInventoryCtrl = TextEditingController();
  final _syllableShapeInventoryCtrl = TextEditingController();

  // Accordion — first marker open by default.
  String _expanded = 'm_inconsistent';

  TextEditingController _ddkCtrl(String task) => switch (task) {
        'pa' => _ddkPaCtrl,
        'ta' => _ddkTaCtrl,
        'ka' => _ddkKaCtrl,
        'pataka' => _ddkPatakaCtrl,
        _ => throw ArgumentError('unknown ddk task $task'),
      };

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    for (final c in <TextEditingController>[
      _markerInconsistentNotesCtrl,
      _markerTransitionsNotesCtrl,
      _markerProsodyNotesCtrl,
      _ageMonthsCtrl,
      _ddkPaCtrl,
      _ddkTaCtrl,
      _ddkKaCtrl,
      _ddkPatakaCtrl,
      _oralMechExamCtrl,
      _consonantInventoryCtrl,
      _vowelInventoryCtrl,
      _syllableShapeInventoryCtrl,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _bootstrap() async {
    try {
      final a = await _service.loadOrCreate(clientId: widget.clientId);
      _assessmentId = a['id'] as String;
      _hydrateAssessment(a);
      await _ensureLengthRows();
      await _ensureDdkRows();
      _norms = await _service.loadAllDdkNorms();
      if (!mounted) return;
      setState(() => _loading = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  void _hydrateAssessment(Map<String, dynamic> a) {
    _markerInconsistent = a['marker_inconsistent_errors'] as String?;
    _markerTransitions = a['marker_disrupted_transitions'] as String?;
    _markerProsody = a['marker_inappropriate_prosody'] as String?;
    _markerInconsistentNotesCtrl.text =
        (a['marker_inconsistent_notes'] as String?) ?? '';
    _markerTransitionsNotesCtrl.text =
        (a['marker_transitions_notes'] as String?) ?? '';
    _markerProsodyNotesCtrl.text =
        (a['marker_prosody_notes'] as String?) ?? '';
    final age = a['age_months'];
    _ageMonthsCtrl.text = age == null ? '' : '$age';
    _oralMechExamCtrl.text = (a['oral_mech_exam'] as String?) ?? '';
    _gropingSearching = a['groping_searching'] as String?;
    _vowelErrors = a['vowel_errors'] as String?;
    _receptiveExpressiveGap = a['receptive_expressive_gap'] as String?;
    _consonantInventoryCtrl.text = (a['consonant_inventory'] as String?) ?? '';
    _vowelInventoryCtrl.text = (a['vowel_inventory'] as String?) ?? '';
    _syllableShapeInventoryCtrl.text =
        (a['syllable_shape_inventory'] as String?) ?? '';
  }

  /// Seeds the five canonical length-gradient rows if absent, then
  /// builds the level_order → row-id map and hydrates captured
  /// accuracy. Idempotent across reloads.
  Future<void> _ensureLengthRows() async {
    final rows = await _service.loadLengthGradient(_assessmentId!);
    final byOrder = <int, Map<String, dynamic>>{};
    for (final r in rows) {
      final o = r['level_order'];
      if (o is int) byOrder[o] = r;
    }
    for (final lvl in _kCasLevels) {
      final existing = byOrder[lvl.order];
      if (existing != null) {
        _lenRowIds[lvl.order] = existing['id'] as String;
        _lenAccuracy[lvl.order] = existing['accuracy'] as String?;
      } else {
        final id = await _service.insertLengthGradientRow(
          assessmentId: _assessmentId!,
          levelLabel: lvl.label,
          levelOrder: lvl.order,
          exampleTokens: lvl.tokens,
        );
        _lenRowIds[lvl.order] = id;
        _lenAccuracy[lvl.order] = null;
      }
    }
  }

  /// Seeds the four canonical DDK task rows if absent, then builds the
  /// task → row-id map and hydrates captured rates / sequence flag.
  Future<void> _ensureDdkRows() async {
    final rows = await _service.loadDdk(_assessmentId!);
    final byTask = <String, Map<String, dynamic>>{};
    for (final r in rows) {
      final t = r['task'];
      if (t is String) byTask[t] = r;
    }
    for (final task in _kDdkTasks) {
      final existing = byTask[task];
      if (existing != null) {
        _ddkRowIds[task] = existing['id'] as String;
        final rate = existing['rate_syl_per_sec'];
        _ddkCtrl(task).text = rate == null ? '' : '$rate';
        if (task == 'pataka') {
          _ddkSequenceErrors = existing['sequence_order_errors'] == true;
        }
      } else {
        final id = await _service.insertDdkRow(
            assessmentId: _assessmentId!, task: task);
        _ddkRowIds[task] = id;
      }
    }
  }

  // ── Saves ────────────────────────────────────────────────────────

  Future<void> _saveMarkers() async {
    if (_assessmentId == null) return;
    try {
      await _service.saveAssessmentColumns(
        assessmentId: _assessmentId!,
        data: {
          'marker_inconsistent_errors': _markerInconsistent,
          'marker_disrupted_transitions': _markerTransitions,
          'marker_inappropriate_prosody': _markerProsody,
          'marker_inconsistent_notes': _markerInconsistentNotesCtrl.text.trim(),
          'marker_transitions_notes': _markerTransitionsNotesCtrl.text.trim(),
          'marker_prosody_notes': _markerProsodyNotesCtrl.text.trim(),
        },
      );
    } catch (e) {
      _toast('Could not save markers: $e');
    }
  }

  Future<void> _saveAge() async {
    if (_assessmentId == null) return;
    final age = _parseDecimal(_ageMonthsCtrl.text)?.round();
    try {
      await _service.saveAssessmentColumns(
        assessmentId: _assessmentId!,
        data: {'age_months': age},
      );
    } catch (e) {
      _toast('Could not save age: $e');
    }
  }

  Future<void> _saveEvidence() async {
    if (_assessmentId == null) return;
    try {
      await _service.saveAssessmentColumns(
        assessmentId: _assessmentId!,
        data: {
          'oral_mech_exam': _oralMechExamCtrl.text.trim(),
          'groping_searching': _gropingSearching,
          'vowel_errors': _vowelErrors,
          'receptive_expressive_gap': _receptiveExpressiveGap,
          'consonant_inventory': _consonantInventoryCtrl.text.trim(),
          'vowel_inventory': _vowelInventoryCtrl.text.trim(),
          'syllable_shape_inventory': _syllableShapeInventoryCtrl.text.trim(),
        },
      );
    } catch (e) {
      _toast('Could not save evidence: $e');
    }
  }

  Future<void> _saveLengthRow(int order) async {
    final id = _lenRowIds[order];
    if (id == null) return;
    try {
      await _service.updateLengthGradientAccuracy(
        rowId: id,
        accuracy: _lenAccuracy[order],
      );
    } catch (e) {
      _toast('Could not save length-gradient row: $e');
    }
  }

  Future<void> _saveDdkRate(String task) async {
    final id = _ddkRowIds[task];
    if (id == null) return;
    final rate = _parseDecimal(_ddkCtrl(task).text);
    try {
      await _service.updateDdkRow(
        rowId: id,
        rateSylPerSec: rate,
        sequenceOrderErrors: task == 'pataka' ? _ddkSequenceErrors : null,
      );
    } catch (e) {
      _toast('Could not save DDK rate: $e');
    }
  }

  // ── Live computations (no norm dependency) ───────────────────────

  /// Mean of the present (entered) pa/ta/ka rates; null if none entered.
  num? _amrAvg() {
    final vals = <num>[];
    for (final c in [_ddkPaCtrl, _ddkTaCtrl, _ddkKaCtrl]) {
      final v = _parseDecimal(c.text);
      if (v != null) vals.add(v);
    }
    if (vals.isEmpty) return null;
    final sum = vals.fold<num>(0, (a, b) => a + b);
    return sum / vals.length;
  }

  int? _accuracyOrdinal(String? v) => switch (v) {
        'accurate' => 2,
        'partial' => 1,
        'inaccurate' => 0,
        _ => null,
      };

  /// A norm row matching the entered age + task ('amr' | 'smr'), or null.
  /// cas_ddk_norms is empty at ship, so this returns null by default —
  /// the intended dormant state. Never interpolates.
  Map<String, dynamic>? _findNorm(String task) {
    final age = _parseDecimal(_ageMonthsCtrl.text)?.round();
    if (age == null) return null;
    for (final n in _norms) {
      final t = (n['task'] as String?)?.toLowerCase();
      final minA = n['age_months_min'];
      final maxA = n['age_months_max'];
      if (t == task &&
          minA is num &&
          maxA is num &&
          age >= minA.toInt() &&
          age <= maxA.toInt()) {
        return n;
      }
    }
    return null;
  }

  bool _hasVerifiedBand(String task, num? value) =>
      value != null && _findNorm(task) != null;

  // ── Build ────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const SizedBox(
          height: 100, child: Center(child: CircularProgressIndicator()));
    }
    if (_error != null) {
      return _errorBox('Could not load Pediatric CAS assessment: $_error');
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // A — Authority banner.
        _ghostNote(
            'DSM-5-TR categorises CAS under Speech Sound Disorder (315.39 / F80.0) — no apraxia-specific criteria exist. ASHA 2007 supplies the differential markers below. This surface structures evidence; the diagnostic call is yours.'),
        const SizedBox(height: 14),
        // B — ASHA consensus markers (three cards).
        _section(
          id: 'm_inconsistent',
          number: 1,
          title: 'Inconsistent errors on consonants & vowels',
          tagline: 'ASHA 2007 consensus marker · 3-state, no score.',
          child: _markerBody(
            note: 'Same word ×3–5 — log token-to-token variability',
            value: _markerInconsistent,
            onChanged: (v) {
              setState(() => _markerInconsistent = v);
              _saveMarkers();
            },
            notesCtrl: _markerInconsistentNotesCtrl,
          ),
        ),
        const SizedBox(height: 10),
        _section(
          id: 'm_transitions',
          number: 2,
          title: 'Disrupted coarticulatory transitions',
          tagline: 'ASHA 2007 consensus marker · 3-state, no score.',
          child: _markerBody(
            note: 'Syllable sequencing + DDK smoothness',
            value: _markerTransitions,
            onChanged: (v) {
              setState(() => _markerTransitions = v);
              _saveMarkers();
            },
            notesCtrl: _markerTransitionsNotesCtrl,
          ),
        ),
        const SizedBox(height: 10),
        _section(
          id: 'm_prosody',
          number: 3,
          title: 'Inappropriate prosody',
          tagline: 'ASHA 2007 consensus marker · 3-state, no score.',
          child: _markerBody(
            note: 'Lexical / phrasal stress — equal or misplaced',
            value: _markerProsody,
            onChanged: (v) {
              setState(() => _markerProsody = v);
              _saveMarkers();
            },
            notesCtrl: _markerProsodyNotesCtrl,
          ),
        ),
        const SizedBox(height: 10),
        // C — Length-gradient probe.
        _section(
          id: 'length',
          number: 4,
          title: 'Length-gradient probe',
          tagline: 'Live descriptive slope, CV → polysyllabic phrase.',
          child: _lengthBody(),
        ),
        const SizedBox(height: 10),
        // D — DDK panel.
        _section(
          id: 'ddk',
          number: 5,
          title: 'Diadochokinesis — AMR / SMR',
          tagline:
              'Live AMR/SMR dissociation + teaching layer. Norm banding dormant until verified norms load.',
          child: _ddkBody(),
        ),
        const SizedBox(height: 10),
        // E — Supporting & differential evidence.
        _section(
          id: 'evidence',
          number: 6,
          title: 'Supporting & differential evidence',
          tagline:
              'Oral mech, groping, vowel errors, receptive>expressive gap, inventories.',
          child: _evidenceBody(),
        ),
        const SizedBox(height: 14),
        // F — Footer link.
        _footerLink(),
      ],
    );
  }

  // ── Section bodies ───────────────────────────────────────────────

  Widget _markerBody({
    required String note,
    required String? value,
    required ValueChanged<String?> onChanged,
    required TextEditingController notesCtrl,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ghostNote(note),
        const SizedBox(height: 4),
        _presenceChips('Marker status', value, onChanged),
        _textField('Notes', notesCtrl,
            multi: true, hint: 'Optional — what you observed',
            onSave: _saveMarkers),
      ],
    );
  }

  Widget _lengthBody() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final lvl in _kCasLevels) _accuracyChips(lvl.display, lvl.order),
        const SizedBox(height: 4),
        _slopeReadout(),
        const SizedBox(height: 8),
        _ghostNote(
            'Breakdown that steepens with length is the CAS signature — and what separates it from a stable phonological disorder. You read the pattern.'),
      ],
    );
  }

  Widget _slopeReadout() {
    final captured = <int, int>{};
    for (final lvl in _kCasLevels) {
      final ord = _accuracyOrdinal(_lenAccuracy[lvl.order]);
      if (ord != null) captured[lvl.order] = ord;
    }
    if (captured.length < 2) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _groupLabel('Length slope'),
          _ghostNote(
              'Capture accuracy at two or more lengths to read the slope.'),
        ],
      );
    }
    final orders = captured.keys.toList()..sort();
    final lowOrd = captured[orders.first]!;
    final highOrd = captured[orders.last]!;
    final String msg;
    if (highOrd < lowOrd) {
      msg = 'Steep decline — length-dependent breakdown';
    } else if (highOrd == lowOrd) {
      msg = 'Stable across lengths';
    } else {
      msg = 'Accuracy holds at longer lengths';
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _groupLabel('Length slope'),
        _ghostNote(msg),
      ],
    );
  }

  Widget _ddkBody() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _numField('Child age', _ageMonthsCtrl, unit: 'mo', onSave: () {
          _saveAge();
          setState(() {});
        }),
        _ghostNote(
            'Rate = syllables ÷ time. Norms, when loaded, are method-specific — a child must be compared against a norm using the same method. Mixing count-by-time and time-by-count is the classic error.'),
        const SizedBox(height: 6),
        // AMR block.
        _subsectionHeader('alternating motion rate — one articulator, repeated'),
        _subText('Weakness here points toward strength/tone (dysarthria territory).'),
        const SizedBox(height: 8),
        _numField('/pʌ/ (pa)', _ddkPaCtrl, unit: 'syl/sec', onSave: () {
          _saveDdkRate('pa');
          setState(() {});
        }),
        _numField('/tʌ/ (ta)', _ddkTaCtrl, unit: 'syl/sec', onSave: () {
          _saveDdkRate('ta');
          setState(() {});
        }),
        _numField('/kʌ/ (ka)', _ddkKaCtrl, unit: 'syl/sec', onSave: () {
          _saveDdkRate('ka');
          setState(() {});
        }),
        const SizedBox(height: 6),
        // SMR block — visually accented.
        _smrBlock(),
        const SizedBox(height: 12),
        // AMR → SMR dissociation (live, within-child).
        _dissociationReadout(),
        const SizedBox(height: 12),
        // SD banding (dormant until verified norms load).
        _normBandingBlock(),
        const SizedBox(height: 10),
        // Permanent Indian-language caveat.
        _cautionNote(
            'Published pediatric DDK norms are English-language (e.g. Robbins & Klee 1987; Dutch CAI). No validated pediatric DDK norm exists for Kannada, Telugu, or Hindi. Dravidian languages differ in baseline rate — interpret bilingual children with caution.'),
      ],
    );
  }

  Widget _smrBlock() {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
      decoration: BoxDecoration(
        color: _tealSoft.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _teal.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _subsectionHeader(
                    'sequential motion rate — switching between articulators'),
              ),
              const SizedBox(width: 8),
              _tag('CAS-relevant'),
            ],
          ),
          _subText('Tests sequencing & transitions — the planning question.'),
          const SizedBox(height: 8),
          _numField('/pʌ-tʌ-kʌ/ (pataka)', _ddkPatakaCtrl, unit: 'syl/sec',
              onSave: () {
            _saveDdkRate('pataka');
            setState(() {});
          }),
          _sequenceCheckbox(),
          const SizedBox(height: 4),
          _ghostNote(
              'Mis-sequencing > slowing is the planning signal — watch order, not just speed.'),
        ],
      ),
    );
  }

  Widget _sequenceCheckbox() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: () {
          setState(() => _ddkSequenceErrors = !_ddkSequenceErrors);
          _saveDdkRate('pataka');
        },
        borderRadius: BorderRadius.circular(6),
        child: Row(
          children: [
            SizedBox(
              width: 24,
              height: 24,
              child: Checkbox(
                value: _ddkSequenceErrors,
                onChanged: (v) {
                  setState(() => _ddkSequenceErrors = v ?? false);
                  _saveDdkRate('pataka');
                },
                activeColor: _teal,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text('Sequence-order errors (pa-ka-ta)',
                  style: GoogleFonts.dmSans(
                      fontSize: 13,
                      color: _ink,
                      fontWeight: FontWeight.w500)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _dissociationReadout() {
    final amrAvg = _amrAvg();
    final smr = _parseDecimal(_ddkPatakaCtrl.text);
    if (amrAvg == null || smr == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _groupLabel('AMR → SMR dissociation'),
          _ghostNote(
              'Enter at least one AMR rate (pa/ta/ka) and the SMR rate (pataka) to read the within-child dissociation.'),
        ],
      );
    }
    if (amrAvg <= 0) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _groupLabel('AMR → SMR dissociation'),
          _ghostNote('Enter a non-zero AMR rate to read the dissociation.'),
        ],
      );
    }
    final ratio = smr / amrAvg;
    final ratio1 = (ratio * 10).roundToDouble() / 10;
    final String msg;
    if (ratio < 0.7) {
      msg =
          'SMR markedly slower than AMR. This dissociation — sequencing worse than single-articulator speed — is the pattern the CAS literature flags as a planning signal. Pair with sequence-order errors and inconsistency to build the case.';
    } else {
      msg =
          'SMR roughly proportional to AMR — no strong dissociation. A flat profile is less specific to motor planning.';
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _groupLabel('AMR → SMR dissociation'),
        _ghostNote('SMR ÷ AMR-avg = ${_fmtNum(ratio1)}.  $msg'),
      ],
    );
  }

  Widget _normBandingBlock() {
    final amrAvg = _amrAvg();
    final smr = _parseDecimal(_ddkPatakaCtrl.text);
    final anyPending =
        !_hasVerifiedBand('amr', amrAvg) || !_hasVerifiedBand('smr', smr);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _groupLabel('Norm comparison — SD banding'),
        _normBandRow('amr', 'AMR (pa/ta/ka avg)', amrAvg),
        const SizedBox(height: 6),
        _normBandRow('smr', 'SMR (pataka)', smr),
        if (anyPending) ...[
          const SizedBox(height: 8),
          _ghostNote(
              'No verified norm loaded for this age. The pattern readouts above (length-gradient slope, AMR/SMR dissociation) do not depend on norms and remain valid.'),
        ],
      ],
    );
  }

  Widget _normBandRow(String task, String label, num? value) {
    final norm = _findNorm(task);
    if (norm == null || value == null) {
      return _pendingPill(label);
    }
    final mean = (norm['mean_syl_per_sec'] as num).toDouble();
    final sd = (norm['sd_syl_per_sec'] as num).toDouble();
    final src = (norm['source_citation'] as String?) ?? '';
    final String band;
    if (value >= mean - sd) {
      band = 'within range';
    } else if (value >= mean - 2 * sd) {
      band = 'mildly below';
    } else {
      band = 'markedly below';
    }
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: _tealSoft.withValues(alpha: 0.30),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _tealSoft),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$label — $band',
              style: GoogleFonts.dmSans(
                  fontSize: 13, color: _ink, fontWeight: FontWeight.w600)),
          const SizedBox(height: 2),
          Text('mean ${_fmtNum(mean)} · SD ${_fmtNum(sd)} syl/sec · $src',
              style: GoogleFonts.dmSans(fontSize: 11, color: _inkGhost)),
        ],
      ),
    );
  }

  Widget _pendingPill(String label) {
    return Row(
      children: [
        Expanded(
          child: Text(label,
              style: GoogleFonts.dmSans(
                  fontSize: 12,
                  color: _inkGhost,
                  fontWeight: FontWeight.w500)),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: _line.withValues(alpha: 0.45),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _line),
          ),
          child: Text('norm reference pending validation',
              style: GoogleFonts.dmSans(
                  fontSize: 11,
                  color: _inkGhost,
                  fontWeight: FontWeight.w500)),
        ),
      ],
    );
  }

  Widget _evidenceBody() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _textField('Oral mech exam', _oralMechExamCtrl,
            multi: true,
            hint: 'Structure + function findings',
            onSave: _saveEvidence),
        _presenceChips('Groping / searching', _gropingSearching, (v) {
          setState(() => _gropingSearching = v);
          _saveEvidence();
        }),
        _presenceChips('Vowel errors', _vowelErrors, (v) {
          setState(() => _vowelErrors = v);
          _saveEvidence();
        }),
        _presenceChips('Receptive > expressive gap', _receptiveExpressiveGap,
            (v) {
          setState(() => _receptiveExpressiveGap = v);
          _saveEvidence();
        }),
        _textField('Consonant inventory', _consonantInventoryCtrl,
            multi: true, hint: 'Phones present', onSave: _saveEvidence),
        _textField('Vowel inventory', _vowelInventoryCtrl,
            multi: true, hint: 'Vowels present', onSave: _saveEvidence),
        _textField('Syllable-shape inventory', _syllableShapeInventoryCtrl,
            multi: true, hint: 'e.g. CV, CVC, CVCV', onSave: _saveEvidence),
      ],
    );
  }

  Widget _footerLink() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.south_rounded, size: 14, color: _teal),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
                'Feeds Diagnostic synthesis — you write the statement & pick ICD-11 / DSM codes.',
                style: GoogleFonts.dmSans(
                    fontSize: 12,
                    color: _teal,
                    fontWeight: FontWeight.w500,
                    fontStyle: FontStyle.italic)),
          ),
        ],
      ),
    );
  }

  // ── Value-mapping chip shims (both delegate to _singleChips) ──────

  Widget _presenceChips(
      String label, String? value, ValueChanged<String?> onChanged) {
    return _singleChips(
      label,
      _kPresenceLabels,
      value == null ? null : _kPresenceValueToLabel[value],
      (lbl) => onChanged(lbl == null ? null : _kPresenceLabelToValue[lbl]),
    );
  }

  Widget _accuracyChips(String label, int order) {
    final value = _lenAccuracy[order];
    return _singleChips(
      label,
      _kAccuracyLabels,
      value == null ? null : _kAccuracyValueToLabel[value],
      (lbl) {
        setState(() =>
            _lenAccuracy[order] = lbl == null ? null : _kAccuracyLabelToValue[lbl]);
        _saveLengthRow(order);
      },
    );
  }

  // ── Primitives (reused verbatim from ped_dysarthria) ─────────────

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
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _line),
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
                fontSize: 12,
                color: _ink,
                fontStyle: FontStyle.italic,
                height: 1.5)),
      ),
    );
  }

  /// Amber-register variant of _ghostNote for the permanent, prominent
  /// Indian-language norms caveat. Same box geometry, caution palette.
  Widget _cautionNote(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(
          color: _amberSoft.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: _amber.withValues(alpha: 0.45)),
        ),
        child: Text(text,
            style: GoogleFonts.dmSans(
                fontSize: 12,
                color: _ink,
                fontStyle: FontStyle.italic,
                height: 1.5)),
      ),
    );
  }

  Widget _subText(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Text(text,
          style: GoogleFonts.dmSans(
              fontSize: 12,
              color: _inkGhost,
              fontStyle: FontStyle.italic,
              height: 1.4)),
    );
  }

  Widget _tag(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: _teal.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(text.toUpperCase(),
          style: GoogleFonts.syne(
              fontSize: 9,
              fontWeight: FontWeight.w700,
              color: _teal,
              letterSpacing: 1.0)),
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
                suffixStyle:
                    GoogleFonts.dmSans(fontSize: 12, color: _inkGhost),
                border: const OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ),
        ],
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
          if (options.isEmpty)
            Text('—',
                style: GoogleFonts.dmSans(
                    fontSize: 12,
                    color: _inkGhost,
                    fontStyle: FontStyle.italic))
          else
            Wrap(
              spacing: 6,
              runSpacing: 6,
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

  String _fmtNum(num v) {
    if (v is int) return v.toString();
    final asDouble = v.toDouble();
    if (asDouble == asDouble.roundToDouble()) {
      return asDouble.toInt().toString();
    }
    return asDouble.toStringAsFixed(2);
  }

  num? _parseDecimal(String s) {
    final t = s.trim();
    if (t.isEmpty) return null;
    return num.tryParse(t);
  }

  void _toast(String msg) {
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(msg)));
    }
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
