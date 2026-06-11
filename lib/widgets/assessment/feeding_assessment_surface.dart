// lib/widgets/assessment/feeding_assessment_surface.dart
//
// Childhood Feeding — Phase 1 (capture). Wired on clinical_area
// 'pediatric-feeding'. A FEEDING-SKILLS surface: three capture layers
// (oral-motor dissociation, the developmental feeding ladder, mealtime
// behaviours) + the swallow off-ramp caution. It is NOT a swallowing /
// dysphagia surface — airway safety is a separate later surface; this one
// only FLAGS toward it.
//
// SAFETY (stricter than SSD — airway-adjacent scope):
//   * Cue NEVER judges feeding adequacy, developmental status, or swallow
//     safety. There is no derived metric and no computed verdict anywhere on
//     this surface. The ladder SURFACES what is expected at an age; the
//     clinician marks the child against it (at level / emerging / below
//     level / not tested). The gap stays visible, never computed or labelled.
//   * Red-flag text renders as a WATCH-FOR observation prompt, never a
//     verdict. The clinician decides whether a sign is present and what it
//     means.
//   * Empty stays empty — untouched fields stay NULL and render unmarked.
//   * The swallow off-ramp renders when the child's age band is 18 months+
//     OR an airway-sign behaviour is marked present (trigger conditions are
//     DRAFT, clinician sign-off pending). The onOpenSwallow seam is DORMANT
//     in Phase 1 — null renders caution text only; the handoff button
//     appears only when a host screen wires the callback (exactly SSD's
//     onOpenCas pattern, which stayed optional until the CAS surface
//     existed to route to).
//
// CONTENT: lib/constants/feeding_ladder_content.dart (brand-neutral,
// literature-grounded; red flags / off-ramp triggers / Western-norm caveat
// are DRAFT pending clinician sign-off — graduation gate, like SSD's).
//
// TYPOGRAPHY & PALETTE — the SSD surface's locked spine registers verbatim:
// JetBrains Mono eyebrows for data tags, Inter for everything read, no
// italic on a clinical-action surface, olive calm / amber urgent, ink
// #1B2B4B, hairline #E8E4DC, radius 8/6, 4/8/12/16 rhythm. Layer-1 status
// chips are colour-coded per spec (present green / emerging amber / absent
// coral); ladder markings and behaviour statuses stay in the calm olive
// selection register — the clinician's mark is hers, the surface does not
// editorialise it. Urgency belongs to the off-ramp alone.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../constants/feeding_ladder_content.dart';
import '../../services/feeding_assessment_service.dart';

// Locked spine palette (+ the dual-accent pair) — matches the SSD surface.
const Color _ink = Color(0xFF1B2B4B); // kCueInk
const Color _inkSecondary = Color(0xFF5F5E5A); // body / secondary content
const Color _inkTertiary = Color(0xFF888780); // eyebrows / metadata
const Color _line = Color(0xFFE8E4DC); // kCueBorder hairline
const Color _olive = Color(0xFF5C6E3B); // calm default accent
const Color _oliveSoft = Color(0xFFE7EADB);
const Color _amber = Color(0xFFB45309); // urgent register (kCueAmber)
const Color _amberSoft = Color(0xFFF4E4C4);
const Color _coral = Color(0xFFC25450); // existing assessment-surface error tone
const Color _green = Color(0xFF1A7E5C); // WCAG-cleared green (Extract-button hue)

const List<String> _kPresenceValues = ['present', 'emerging', 'absent'];
const Map<String, String> _kPresenceValueToLabel = {
  'present': 'Present',
  'emerging': 'Emerging',
  'absent': 'Absent',
};

// Layer-1 colour coding per spec: present green / emerging amber / absent
// coral. (Only Layer 1 — the marks elsewhere stay in the calm olive register.)
const Map<String, Color> _kPresenceValueToColor = {
  'present': _green,
  'emerging': _amber,
  'absent': _coral,
};

const List<String> _kMarkingValues = [
  'at_level',
  'emerging',
  'below_level',
  'not_tested',
];

class FeedingAssessmentSurface extends StatefulWidget {
  final String clientId;

  /// DORMANT handoff seam (Phase 1): invoked by the swallow off-ramp's
  /// "Open swallow assessment" action once a swallow surface exists for a
  /// host screen to route to. While null (all of Phase 1), the off-ramp
  /// renders caution text only — no dead button. Mirrors SSD's onOpenCas.
  final VoidCallback? onOpenSwallow;

  /// Test seam: inject a service (e.g. an in-memory fake). Defaults to the
  /// shared singleton in production.
  final FeedingAssessmentService? service;

  const FeedingAssessmentSurface({
    super.key,
    required this.clientId,
    this.onOpenSwallow,
    this.service,
  });

  @override
  State<FeedingAssessmentSurface> createState() =>
      _FeedingAssessmentSurfaceState();
}

class _FeedingAssessmentSurfaceState extends State<FeedingAssessmentSurface> {
  late final FeedingAssessmentService _service =
      widget.service ?? FeedingAssessmentService.instance;

  String? _assessmentId;
  bool _loading = true;
  String? _error;

  // Parent — Layer 1 statuses keyed by column, plus age + capture notes.
  final _ageMonthsCtrl = TextEditingController();
  final Map<String, String?> _dissociation = {};
  final Map<String, TextEditingController> _dissociationNotes = {};
  final _captureNotesCtrl = TextEditingController();

  // Children — in-memory row lists (maps carry DB column names + id).
  List<Map<String, dynamic>> _ladderBands = [];
  List<Map<String, dynamic>> _behaviors = [];

  // Per-row text controllers, keyed '$rowId::$field'.
  final Map<String, TextEditingController> _rowCtrls = {};

  String _expanded = 'oralmotor';

  // Ladder-band expansion: null = follow the age match; '' = all collapsed;
  // otherwise an explicit band id. The age-matched band auto-expands so the
  // band the clinician needs is open the moment age is entered.
  String? _expandedBandOverride;

  // The off-ramp's age threshold derives from the first off-ramp band — one
  // source of truth with the seeded content. (Trigger DRAFT, sign-off pending.)
  static final int _offRampAgeMin =
      kFeedingLadderBands.firstWhere((b) => b.offRampBand).ageMinMonths;

  @override
  void initState() {
    super.initState();
    for (final f in kFeedingDissociationFunctions) {
      _dissociationNotes[f.column] = TextEditingController();
    }
    _bootstrap();
  }

  @override
  void dispose() {
    _ageMonthsCtrl.dispose();
    _captureNotesCtrl.dispose();
    for (final c in _dissociationNotes.values) {
      c.dispose();
    }
    for (final c in _rowCtrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  // ── Bootstrap / hydrate ────────────────────────────────────────────

  Future<void> _bootstrap() async {
    try {
      final a = await _service.loadOrCreate(clientId: widget.clientId);
      _assessmentId = a['id'] as String;
      _hydrateParent(a);
      _ladderBands = await _service.ensureLadderBands(_assessmentId!);
      _behaviors = await _service.loadRows('feeding_behaviors', _assessmentId!);
      _hydrateRowCtrls();
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

  void _hydrateParent(Map<String, dynamic> a) {
    final age = a['age_months'];
    _ageMonthsCtrl.text = age == null ? '' : '$age';
    for (final f in kFeedingDissociationFunctions) {
      _dissociation[f.column] = a[f.column] as String?;
      _dissociationNotes[f.column]!.text =
          (a['${f.column}_notes'] as String?) ?? '';
    }
    _captureNotesCtrl.text = (a['capture_notes'] as String?) ?? '';
  }

  void _hydrateRowCtrls() {
    for (final r in _ladderBands) {
      _mk(r, ['notes']);
    }
    for (final r in _behaviors) {
      _mk(r, ['behavior_label', 'notes']);
    }
  }

  void _mk(Map<String, dynamic> row, List<String> fields) {
    final id = row['id'] as String;
    for (final f in fields) {
      final key = '$id::$f';
      if (_rowCtrls.containsKey(key)) continue;
      final v = row[f];
      _rowCtrls[key] = TextEditingController(text: v == null ? '' : '$v');
    }
  }

  TextEditingController _rc(String rowId, String field) =>
      _rowCtrls['$rowId::$field']!;

  // ── Saves ──────────────────────────────────────────────────────────

  Future<void> _saveCols(Map<String, dynamic> data) async {
    if (_assessmentId == null) return;
    try {
      await _service.saveAssessmentColumns(
          assessmentId: _assessmentId!, data: data);
    } catch (e) {
      _toast('Could not save: $e');
    }
  }

  Future<void> _saveRow(
      String table, String rowId, Map<String, dynamic> data) async {
    try {
      await _service.updateRow(table: table, rowId: rowId, data: data);
    } catch (e) {
      _toast('Could not save row: $e');
    }
  }

  Future<void> _addBehavior(Map<String, dynamic> seed) async {
    if (_assessmentId == null) return;
    try {
      final id = await _service.insertRow(
          table: 'feeding_behaviors', assessmentId: _assessmentId!, data: seed);
      final row = {'id': id, ...seed};
      _mk(row, ['behavior_label', 'notes']);
      setState(() => _behaviors.add(row));
    } catch (e) {
      _toast('Could not add behaviour: $e');
    }
  }

  Future<void> _removeBehavior(Map<String, dynamic> row) async {
    final id = row['id'] as String;
    try {
      await _service.deleteRow(table: 'feeding_behaviors', rowId: id);
      for (final k
          in _rowCtrls.keys.where((k) => k.startsWith('$id::')).toList()) {
        _rowCtrls.remove(k)?.dispose();
      }
      setState(() => _behaviors.remove(row));
    } catch (e) {
      _toast('Could not remove behaviour: $e');
    }
  }

  // ── Off-ramp + ladder derivations (display state, never judgements) ──

  int? get _ageMonths => _parseInt(_ageMonthsCtrl.text);

  /// The DB band row matching the entered age (display highlight only).
  Map<String, dynamic>? get _matchedBandRow {
    final age = _ageMonths;
    if (age == null || age < 0) return null;
    for (final r in _ladderBands) {
      final min = r['age_min_months'];
      final max = r['age_max_months'];
      if (min is! int) continue;
      if (age >= min && (max == null || age < (max as int))) return r;
    }
    return null;
  }

  bool get _airwayBehaviorMarked => _behaviors.any(
      (b) => b['airway_sign'] == true && b['status'] == 'present');

  /// DRAFT trigger (sign-off pending): age in an off-ramp band (18mo+) OR an
  /// airway-sign behaviour marked present.
  bool get _offRampActive =>
      ((_ageMonths ?? -1) >= _offRampAgeMin) || _airwayBehaviorMarked;

  // ── Type system (spine registers — verbatim from the SSD surface) ───

  TextStyle _eyebrow({Color color = _inkTertiary, double size = 10.5}) =>
      GoogleFonts.jetBrainsMono(
          fontSize: size,
          fontWeight: FontWeight.w500,
          color: color,
          letterSpacing: size * 0.14);

  TextStyle get _label => GoogleFonts.inter(
      fontSize: 12.5,
      fontWeight: FontWeight.w600,
      color: _ink,
      letterSpacing: -0.05);

  TextStyle get _rowLabel => GoogleFonts.inter(
      fontSize: 11.5, fontWeight: FontWeight.w500, color: _inkSecondary);

  TextStyle get _caption => GoogleFonts.inter(
      fontSize: 12,
      fontWeight: FontWeight.w400,
      color: _inkSecondary,
      height: 1.45);

  TextStyle get _input => GoogleFonts.inter(
      fontSize: 13.5, fontWeight: FontWeight.w400, color: _ink);

  // ── Build ───────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const SizedBox(
          height: 100, child: Center(child: CircularProgressIndicator()));
    }
    if (_error != null) {
      return _errorBox('Could not load feeding assessment: $_error');
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ghostNote(
            'Feeding-SKILLS capture: oral-motor dissociation, the developmental '
            'feeding ladder, and mealtime behaviours. This is not a swallowing / '
            'dysphagia assessment — airway safety has its own boundary and its '
            'own (separate) assessment. Expectations and watch-for prompts come '
            'from the developmental-feeding literature (Arvedson; Delaney & '
            'Goday; the New York State Early Intervention guideline; ASHA '
            'practice guidance; the Goday et al. pediatric feeding disorder '
            'consensus). Every judgement — adequacy, developmental status, what '
            'a sign means — is yours; Cue computes nothing here.'),
        const SizedBox(height: 16),
        _section(
            id: 'oralmotor',
            number: 1,
            title: 'Oral-motor dissociation',
            tagline:
                'Five functions — the observable sign first, the term second. You mark.',
            child: _oralMotorBody()),
        const SizedBox(height: 12),
        _section(
            id: 'ladder',
            number: 2,
            title: 'Developmental feeding ladder',
            tagline:
                'Age in → the expected band surfaces. You mark the child against it.',
            child: _ladderBody()),
        const SizedBox(height: 12),
        _section(
            id: 'behaviors',
            number: 3,
            title: 'Feeding behaviours',
            tagline:
                'Add what you observed — starter set or your own words. Present / absent.',
            child: _behaviorsBody()),
        if (_offRampActive) ...[
          const SizedBox(height: 16),
          _offRampCard(),
        ],
        const SizedBox(height: 16),
        _footerLink(),
        // Bottom breathing room — the off-ramp / caveat must never sit
        // clipped at the viewport edge (SSD convention).
        const SizedBox(height: 32),
      ],
    );
  }

  // ── Section 1 — oral-motor dissociation ─────────────────────────────

  Widget _oralMotorBody() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _subText('Watch a few bites and sips, then mark each function. '
            'Unmarked stays unmarked — nothing here defaults.'),
        const SizedBox(height: 8),
        for (var i = 0; i < kFeedingDissociationFunctions.length; i++) ...[
          _dissociationBlock(kFeedingDissociationFunctions[i]),
          if (i < kFeedingDissociationFunctions.length - 1)
            const Divider(height: 20, color: _line),
        ],
      ],
    );
  }

  Widget _dissociationBlock(FeedingDissociationFunction f) {
    final status = _dissociation[f.column];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Observable sign PRIMARY, clinical term secondary — the report needs
        // the term; the mealtime observation needs the plain question.
        Text(f.observableSign,
            style: GoogleFonts.inter(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: _ink,
                height: 1.45)),
        const SizedBox(height: 2),
        Text(f.term,
            style: GoogleFonts.inter(
                fontSize: 11, fontWeight: FontWeight.w500, color: _inkTertiary)),
        const SizedBox(height: 8),
        _codedChips(status, (v) {
          setState(() => _dissociation[f.column] = v);
          _saveCols({f.column: v});
        }),
        const SizedBox(height: 8),
        _rowText('Notes', _dissociationNotes[f.column]!,
            hint: 'optional',
            onSave: () => _saveCols(
                {'${f.column}_notes': _dissociationNotes[f.column]!.text.trim()})),
      ],
    );
  }

  // ── Section 2 — developmental feeding ladder ────────────────────────

  Widget _ladderBody() {
    final matched = _matchedBandRow;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _numField('Child age', _ageMonthsCtrl, unit: 'mo', onSave: () {
          _saveCols({'age_months': _parseInt(_ageMonthsCtrl.text)});
          setState(() {});
        }),
        _ghostNote(
            'The ladder shows what is EXPECTED in each age window — it never '
            'says a child is behind. Enter the age to surface the matching '
            'band, read what is expected there, and mark what this child '
            'manages. The gap is yours to see and yours to interpret.'),
        if (matched == null)
          _subText('No age entered yet — open any band below to read it.'),
        const SizedBox(height: 4),
        for (final row in _ladderBands) _bandTile(row, matched),
      ],
    );
  }

  Widget _bandTile(Map<String, dynamic> row, Map<String, dynamic>? matched) {
    final id = row['id'] as String;
    final isMatched = matched != null && matched['id'] == id;
    final override = _expandedBandOverride;
    final open =
        override == null ? isMatched : (override.isNotEmpty && override == id);
    final marking = row['clinician_marking'] as String?;
    final offRamp = row['off_ramp_band'] == true;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        decoration: BoxDecoration(
          color: isMatched ? _oliveSoft.withValues(alpha: 0.18) : Colors.white,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
              color: isMatched ? _olive : _line, width: isMatched ? 1.3 : 1),
        ),
        child: Column(children: [
          InkWell(
            onTap: () => setState(() =>
                _expandedBandOverride = open ? '' : (id == '' ? null : id)),
            borderRadius: BorderRadius.circular(6),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
              child: Row(children: [
                Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Text('${row['band_label']}',
                              style: GoogleFonts.inter(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w600,
                                  color: _ink)),
                          if (isMatched) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: _oliveSoft,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text("THIS CHILD'S AGE BAND",
                                  style: _eyebrow(color: _olive, size: 9)),
                            ),
                          ],
                        ]),
                        if (marking != null) ...[
                          const SizedBox(height: 2),
                          Text('Marked: ${_humanize(marking)}',
                              style: GoogleFonts.inter(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w500,
                                  color: _olive)),
                        ],
                      ]),
                ),
                Icon(open ? Icons.expand_less : Icons.expand_more,
                    size: 20, color: _inkTertiary),
              ]),
            ),
          ),
          if (open) ...[
            const Divider(height: 1, color: _line),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              child:
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _expectationLine('Texture', '${row['expected_texture'] ?? ''}'),
                _expectationLine(
                    'Self-feeding', '${row['expected_self_feeding'] ?? ''}'),
                _expectationLine(
                    'Oral-motor', '${row['expected_oral_motor'] ?? ''}'),
                const SizedBox(height: 8),
                _watchForBlock('${row['red_flag_prompt'] ?? ''}'),
                if (offRamp)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.alt_route_rounded,
                              size: 14, color: _amber),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                                'Airway signs at this band sit beyond '
                                'feeding-skills scope — see the swallow '
                                'off-ramp below.',
                                style: GoogleFonts.inter(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w500,
                                    color: _amber,
                                    height: 1.4)),
                          ),
                        ]),
                  ),
                // The clinician's call — calm olive register, no colour
                // editorialising on "below level".
                _markingChips(row),
                _rowText('Notes', _rc(id, 'notes'),
                    hint: 'optional',
                    onSave: () => _saveRow('feeding_ladder_bands', id,
                        {'notes': _rc(id, 'notes').text.trim()})),
                // Western-norm caveat travels with every band the clinician
                // reads (DRAFT wording, founder's version pending).
                _cautionNote(kFeedingWesternNormCaveat),
              ]),
            ),
          ],
        ]),
      ),
    );
  }

  Widget _expectationLine(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(width: 92, child: Text(label, style: _rowLabel)),
        Expanded(
          child: Text(value,
              style: GoogleFonts.inter(
                  fontSize: 12.5, color: _ink, height: 1.45)),
        ),
      ]),
    );
  }

  /// Red-flag content as a WATCH-FOR observation prompt — amber register,
  /// explicitly framed as a prompt, never a verdict. (Prompt text is DRAFT,
  /// clinician sign-off pending before graduation.)
  Widget _watchForBlock(String prompt) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Container(
          color: _amberSoft.withValues(alpha: 0.35),
          child: IntrinsicHeight(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Container(width: 3.5, color: _amber),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('WATCH FOR', style: _eyebrow(color: _amber, size: 9.5)),
                        const SizedBox(height: 4),
                        Text(prompt,
                            style: GoogleFonts.inter(
                                fontSize: 12.5,
                                color: _ink,
                                fontWeight: FontWeight.w500,
                                height: 1.5)),
                        const SizedBox(height: 4),
                        Text(
                            'Observation prompt — you decide whether it is '
                            'present and what it means.',
                            style: GoogleFonts.inter(
                                fontSize: 11, color: _inkTertiary, height: 1.4)),
                      ]),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _markingChips(Map<String, dynamic> row) {
    final id = row['id'] as String;
    return _oliveChips(
      'This child, against this band',
      _kMarkingValues,
      row['clinician_marking'] as String?,
      (v) {
        setState(() => row['clinician_marking'] = v);
        _saveRow('feeding_ladder_bands', id, {'clinician_marking': v});
      },
    );
  }

  // ── Section 3 — feeding behaviours ──────────────────────────────────

  Widget _behaviorsBody() {
    final addedKeys = _behaviors.map((b) => b['behavior_key']).toSet();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _subText('Tap a starter to add it, or add your own in your words. '
            'Mark each present or absent — "absent" is a real finding '
            '(checked, not observed).'),
        const SizedBox(height: 8),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final s in kFeedingStarterBehaviors)
            _starterChip(s, alreadyAdded: addedKeys.contains(s.key)),
        ]),
        const SizedBox(height: 12),
        for (final row in _behaviors) _behaviorRow(row),
        _addButton(
            'Add behaviour in your words',
            () => _addBehavior({
                  'behavior_key': null,
                  'behavior_label': '',
                  'airway_sign': false, // explicit, never a DB default
                })),
        const SizedBox(height: 12),
        _textField('Capture notes', _captureNotesCtrl,
            multi: true,
            hint: 'Optional',
            onSave: () =>
                _saveCols({'capture_notes': _captureNotesCtrl.text.trim()})),
      ],
    );
  }

  Widget _starterChip(FeedingStarterBehavior s, {required bool alreadyAdded}) {
    return GestureDetector(
      onTap: alreadyAdded
          ? null
          : () => _addBehavior({
                'behavior_key': s.key,
                'behavior_label': s.label,
                'airway_sign': s.airwaySign, // explicit, never a DB default
              }),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
        decoration: BoxDecoration(
          color: alreadyAdded
              ? _oliveSoft.withValues(alpha: 0.4)
              : Colors.white,
          border: Border.all(color: alreadyAdded ? _oliveSoft : _line),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(alreadyAdded ? Icons.check_rounded : Icons.add_rounded,
              size: 13, color: alreadyAdded ? _inkTertiary : _olive),
          const SizedBox(width: 4),
          Text(s.chipLabel,
              style: GoogleFonts.inter(
                  fontSize: 12,
                  color: alreadyAdded ? _inkTertiary : _ink,
                  fontWeight: FontWeight.w500)),
        ]),
      ),
    );
  }

  Widget _behaviorRow(Map<String, dynamic> row) {
    final id = row['id'] as String;
    final freeTyped = row['behavior_key'] == null;
    final airway = row['airway_sign'] == true;
    return _rowCard(
      onRemove: () => _removeBehavior(row),
      children: [
        if (freeTyped)
          _rowText('Behaviour', _rc(id, 'behavior_label'),
              hint: 'what you observed, in your words',
              onSave: () => _saveRow('feeding_behaviors', id,
                  {'behavior_label': _rc(id, 'behavior_label').text.trim()}))
        else
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${row['behavior_label']}',
                  style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: _ink,
                      height: 1.4)),
              if (airway) ...[
                const SizedBox(height: 4),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: _amberSoft.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child:
                      Text('AIRWAY SIGN', style: _eyebrow(color: _amber, size: 9)),
                ),
              ],
            ]),
          ),
        _oliveChips('Status', const ['present', 'absent'],
            row['status'] as String?, (v) {
          setState(() => row['status'] = v);
          _saveRow('feeding_behaviors', id, {'status': v});
        }),
        _rowText('Notes', _rc(id, 'notes'),
            hint: 'optional',
            onSave: () => _saveRow('feeding_behaviors', id,
                {'notes': _rc(id, 'notes').text.trim()})),
      ],
    );
  }

  // ── The swallow off-ramp (safety boundary; seam dormant in Phase 1) ──

  Widget _offRampCard() {
    final escalated = _airwayBehaviorMarked;
    final tone = escalated ? _coral : _amber;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: _amberSoft.withValues(alpha: escalated ? 0.55 : 0.4),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: tone.withValues(alpha: 0.7), width: 1.2),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.alt_route_rounded, size: 18, color: tone),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
                escalated
                    ? 'Airway sign marked — swallow assessment warranted'
                    : 'Swallow off-ramp — the boundary of this surface',
                style: GoogleFonts.inter(
                    fontSize: 14, color: tone, fontWeight: FontWeight.w700)),
          ),
        ]),
        const SizedBox(height: 8),
        // DRAFT wording — founder's version pending (graduation gate).
        Text(kFeedingOffRampCaution,
            style: GoogleFonts.inter(fontSize: 12.5, color: _ink, height: 1.45)),
        if (escalated) ...[
          const SizedBox(height: 8),
          for (final b in _behaviors.where(
              (b) => b['airway_sign'] == true && b['status'] == 'present'))
            Text('→ ${b['behavior_label']} — marked present',
                style: GoogleFonts.inter(
                    fontSize: 12.5,
                    color: _ink,
                    fontWeight: FontWeight.w600,
                    height: 1.45)),
        ],
        const SizedBox(height: 10),
        if (widget.onOpenSwallow != null)
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              onPressed: widget.onOpenSwallow,
              icon: const Icon(Icons.arrow_forward_rounded,
                  size: 16, color: Colors.white),
              label: Text('Open swallow assessment',
                  style: GoogleFonts.inter(
                      fontSize: 13,
                      color: Colors.white,
                      fontWeight: FontWeight.w600)),
              style: FilledButton.styleFrom(
                backgroundColor: _amber,
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
            ),
          )
        else
          // Phase 1: the seam is dormant — caution text, no dead button.
          Text(
              'The swallow / instrumental assessment surface ships later in '
              'Cue — treat this flag as the referral cue.',
              style: GoogleFonts.inter(
                  fontSize: 12, color: _inkSecondary, height: 1.45)),
      ]),
    );
  }

  Widget _footerLink() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Icon(Icons.south_rounded, size: 14, color: _olive),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
              'Feeds Diagnostic synthesis — the feeding-skills statement is '
              'yours to write; swallow safety is a separate assessment.',
              style: GoogleFonts.inter(
                  fontSize: 12, color: _olive, fontWeight: FontWeight.w500)),
        ),
      ]),
    );
  }

  // ── Primitives (SSD surface verbatim) ───────────────────────────────

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
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _line),
      ),
      child: Column(children: [
        InkWell(
          onTap: () => setState(() => _expanded = open ? '' : id),
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
            child: Row(children: [
              Expanded(
                child:
                    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('SECTION $number — ${title.toUpperCase()}',
                      style: _eyebrow(color: _olive)),
                  const SizedBox(height: 4),
                  Text(tagline, style: _caption),
                ]),
              ),
              Icon(open ? Icons.expand_less : Icons.expand_more,
                  color: _inkTertiary),
            ]),
          ),
        ),
        if (open) ...[
          const Divider(height: 1, color: _line),
          Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16), child: child),
        ],
      ]),
    );
  }

  Widget _rowCard(
      {required List<Widget> children, required VoidCallback onRemove}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 12, 8, 4),
        decoration: BoxDecoration(
          color: _oliveSoft.withValues(alpha: 0.25),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: _line),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          ...children,
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: onRemove,
              icon: const Icon(Icons.close_rounded, size: 14, color: _coral),
              label: Text('Remove',
                  style: GoogleFonts.inter(fontSize: 12, color: _coral)),
              style: TextButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _addButton(String label, VoidCallback onTap) {
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        onPressed: onTap,
        icon: const Icon(Icons.add_rounded, size: 16, color: _olive),
        label: Text(label,
            style: GoogleFonts.inter(
                fontSize: 13, color: _olive, fontWeight: FontWeight.w600)),
        style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 4)),
      ),
    );
  }

  /// Calm guidance block — olive-soft ground, regular Inter (never italic on
  /// a clinical surface).
  Widget _ghostNote(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          decoration: BoxDecoration(
            color: _oliveSoft.withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: _oliveSoft),
          ),
          child: Text(text,
              style: GoogleFonts.inter(fontSize: 12.5, color: _ink, height: 1.5)),
        ),
      );

  /// AMBER caution register — the urgent exception (norming / boundary
  /// caveats). Left stripe + weighted text so it can never read as decoration.
  Widget _cautionNote(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Container(
            color: _amberSoft.withValues(alpha: 0.45),
            child: IntrinsicHeight(
              child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Container(width: 3.5, color: _amber),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                    child: Text(text,
                        style: GoogleFonts.inter(
                            fontSize: 12.5,
                            color: _ink,
                            fontWeight: FontWeight.w600,
                            height: 1.5)),
                  ),
                ),
              ]),
            ),
          ),
        ),
      );

  Widget _subText(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text(text, style: _caption),
      );

  Widget _textField(
    String label,
    TextEditingController ctrl, {
    bool multi = false,
    String? hint,
    required VoidCallback onSave,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: _label),
        const SizedBox(height: 4),
        Focus(
          onFocusChange: (f) {
            if (!f) onSave();
          },
          child: TextField(
            controller: ctrl,
            minLines: 1,
            maxLines: multi ? 3 : 1,
            style: _input,
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: GoogleFonts.inter(
                  fontSize: 12, color: _inkTertiary.withValues(alpha: 0.8)),
              border: const OutlineInputBorder(),
              isDense: true,
            ),
          ),
        ),
      ]),
    );
  }

  Widget _rowText(
    String label,
    TextEditingController ctrl, {
    String? hint,
    required VoidCallback onSave,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: _rowLabel),
        const SizedBox(height: 4),
        Focus(
          onFocusChange: (f) {
            if (!f) onSave();
          },
          child: TextField(
            controller: ctrl,
            style: _input,
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: GoogleFonts.inter(
                  fontSize: 12, color: _inkTertiary.withValues(alpha: 0.8)),
              border: const OutlineInputBorder(),
              isDense: true,
            ),
          ),
        ),
      ]),
    );
  }

  Widget _numField(
    String label,
    TextEditingController ctrl, {
    String? unit,
    required VoidCallback onSave,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: _label),
        const SizedBox(height: 4),
        Focus(
          onFocusChange: (f) {
            if (!f) onSave();
          },
          child: TextField(
            controller: ctrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9]'))],
            style: _input,
            decoration: InputDecoration(
              suffixText: unit,
              suffixStyle: GoogleFonts.inter(fontSize: 12, color: _inkTertiary),
              border: const OutlineInputBorder(),
              isDense: true,
            ),
          ),
        ),
      ]),
    );
  }

  /// Layer-1 chips — colour-coded per spec (present green / emerging amber /
  /// absent coral). The colour names the MARK's register; the mark is hers.
  Widget _codedChips(String? value, ValueChanged<String?> onChanged) {
    return Wrap(spacing: 6, runSpacing: 6, children: [
      for (final v in _kPresenceValues)
        GestureDetector(
          onTap: () => onChanged(v == value ? null : v),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
            decoration: BoxDecoration(
              color: value == v
                  ? _kPresenceValueToColor[v]!.withValues(alpha: 0.12)
                  : Colors.white,
              border: Border.all(
                  color: value == v ? _kPresenceValueToColor[v]! : _line),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text(_kPresenceValueToLabel[v]!,
                style: GoogleFonts.inter(
                    fontSize: 12,
                    color: value == v ? _kPresenceValueToColor[v]! : _ink,
                    fontWeight: FontWeight.w500)),
          ),
        ),
    ]);
  }

  /// Calm olive selection chips (the SSD register) — for the ladder marking
  /// and behaviour status, where the surface must not editorialise the call.
  Widget _oliveChips(String label, List<String> options, String? value,
      ValueChanged<String?> onChanged) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: _rowLabel),
        const SizedBox(height: 6),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final o in options)
            GestureDetector(
              onTap: () => onChanged(o == value ? null : o),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
                decoration: BoxDecoration(
                  color: value == o
                      ? _oliveSoft.withValues(alpha: 0.7)
                      : Colors.white,
                  border: Border.all(color: value == o ? _olive : _line),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(_humanize(o),
                    style: GoogleFonts.inter(
                        fontSize: 12,
                        color: value == o ? _olive : _ink,
                        fontWeight: FontWeight.w500)),
              ),
            ),
        ]),
      ]),
    );
  }

  String _humanize(String code) => code
      .replaceAll('_', ' ')
      .replaceFirstMapped(RegExp(r'^.'), (m) => m[0]!.toUpperCase());

  int? _parseInt(String s) {
    final t = s.trim();
    if (t.isEmpty) return null;
    return int.tryParse(t) ?? double.tryParse(t)?.round();
  }

  void _toast(String msg) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  Widget _errorBox(String msg) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
            color: _coral.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(8)),
        child: Text(msg, style: GoogleFonts.inter(fontSize: 12.5, color: _ink)),
      );
}
