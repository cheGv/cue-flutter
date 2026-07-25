// lib/widgets/assessment/ped_language_capture_surface.dart
//
// Pediatric Language capture surface (Step 5) — ASHA developmental
// milestone check, birth-5. Wired on clinical_area 'pediatric-language'.
//
// Shape: one section at a time (speech → language → literacy) with a
// three-step progress header. Each milestone is a tappable card — tap
// marks it PRESENT (multi-select); a visible "Emerging" chip carries
// the middle state; once marked, a visible Observed | Parent-reported
// toggle records the evidence basis (default Observed — she is in
// session). "Done" advances the section and turns every still-unmarked
// row into an explicit 'absent' — unselected only becomes a clinical
// record when the SLP declares the section done, never before.
//
// The band is locked to the child's age on file (date_of_birth exact,
// else stated years midpoint) and ONLY that band renders. No age on
// file → an invitation to add one; over 60 months → an honest
// out-of-range state. The band never stretches.
//
// This surface structures a developmental reference; it never scores,
// totals, or concludes. The dataset's own provenance sentence renders
// verbatim in the header — milestone wording is ASHA's, the examples
// are Cue-authored Indian-English familiarity aids.
//
// Save model (see PedLanguageAssessmentService): rows are seeded once
// at assessment creation with dataset text snapshotted; every tap is an
// optimistic setState + deterministic update-by-id, save-on-change with
// no debounce — matching the CAS / dysarthria siblings. Palette is the
// sibling constants (teal migration is a later per-surface pass); the
// one FilledButton uses kCueAmber with an EXPLICIT white foreground
// (the polarity-4 lesson, CLAUDE.md).

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../models/asha_milestone_library.dart';
import '../../services/ped_language_assessment_service.dart';
import '../../theme/cue_phase4_tokens.dart' show kCueAmber;

// Palette — reused verbatim from the CAS / ped_dysarthria capture
// surfaces so the assessment siblings read identically.
const Color _ink       = Color(0xFF0E1C36);
const Color _inkGhost  = Color(0xFF6B7690);
const Color _line      = Color(0xFFE6DDCA);
const Color _teal      = Color(0xFF2A8F84);
const Color _tealSoft  = Color(0xFFD6E8E5);
const Color _amber     = Color(0xFFD68A2B);
const Color _amberSoft = Color(0xFFF4E4C4);
const Color _coral     = Color(0xFFC25450);

const Map<String, String> _kSectionLabels = {
  'speech':   'Speech',
  'language': 'Language',
  'literacy': 'Literacy',
};

/// Header derivation line — the band and HOW the age that chose it was
/// derived, rendered verbatim from the stored derived_age_months /
/// age_source. Top-level and pure so tests pin the header against the
/// stored derivation. DOB states the exact age; a stated age names the
/// midpoint assumption instead of dressing it up as exact.
String pedLanguageAgeDerivationLine({
  required AshaAgeBand band,
  required int derivedAgeMonths,
  required String ageSource,
}) {
  final range = 'Band ${band.minMonths}–${band.maxMonths} m';
  if (ageSource == 'dob') {
    return '$range · exact age ${formatAgeMonths(derivedAgeMonths)} '
        'from date of birth';
  }
  final statedYears = (derivedAgeMonths - 6) ~/ 12;
  return '$range · from stated age $statedYears y, '
      'assumed $derivedAgeMonths m';
}

/// '34' → '2 y 10 m'; exact years and under-1 collapse ('24' → '2 y',
/// '6' → '6 m').
String formatAgeMonths(int months) {
  final y = months ~/ 12;
  final m = months % 12;
  if (y == 0) return '$m m';
  if (m == 0) return '$y y';
  return '$y y $m m';
}

class PedLanguageCaptureSurface extends StatefulWidget {
  final String clientId;
  const PedLanguageCaptureSurface({super.key, required this.clientId});

  @override
  State<PedLanguageCaptureSurface> createState() =>
      _PedLanguageCaptureSurfaceState();
}

/// Local mutable mirror of one ped_language_milestones row.
class _Mark {
  final String rowId;
  final int order;
  final String text;
  final String? example;
  String? status;   // present | emerging | absent | null (not yet captured)
  String? evidence; // observed | parent_reported | null

  _Mark({
    required this.rowId,
    required this.order,
    required this.text,
    required this.example,
    required this.status,
    required this.evidence,
  });
}

class _PedLanguageCaptureSurfaceState extends State<PedLanguageCaptureSurface> {
  final _service = PedLanguageAssessmentService.instance;

  bool _loading = true;
  String? _error;

  PedLanguageBootstrapState? _state;
  String? _assessmentId;
  AshaAgeBand? _band;
  String _source = '';
  int? _ageMonths;
  String? _ageSource;

  /// section → marks in milestone_order.
  final Map<String, List<_Mark>> _marks = {};

  /// section → declared-done (from *_completed_at).
  final Map<String, bool> _completed = {};

  int _sectionIndex = 0;

  /// In-flight per-row saves. Completing a section awaits these so the
  /// declared record matches what was on screen, not a racing PATCH.
  final Set<Future<void>> _pendingSaves = {};

  /// Guards _completeSection against double-taps — a second tap 150 ms
  /// after the first must not complete the NEXT, unreviewed section.
  bool _completing = false;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    try {
      final b = await _service.loadOrCreate(clientId: widget.clientId);
      _state = b.state;
      _source = b.source;
      _ageMonths = b.ageMonths;
      _ageSource = b.ageSource;
      if (b.state == PedLanguageBootstrapState.ready) {
        _assessmentId = b.assessment!['id'] as String;
        _band = b.band;
        for (final section in kAshaSections) {
          _completed[section] =
              b.assessment!['${section}_completed_at'] != null;
          _marks[section] = [
            for (final r in b.rows)
              if (r['section'] == section)
                _Mark(
                  rowId:    r['id'] as String,
                  order:    r['milestone_order'] as int,
                  text:     r['milestone_text'] as String,
                  example:  r['example_text'] as String?,
                  status:   r['status'] as String?,
                  evidence: r['evidence_source'] as String?,
                ),
          ]..sort((a, b) => a.order.compareTo(b.order));
        }
        // Open on the first section not yet declared done.
        _sectionIndex = kAshaSections
            .indexWhere((s) => _completed[s] != true)
            .clamp(0, kAshaSections.length - 1);
        if (kAshaSections.every((s) => _completed[s] == true)) {
          _sectionIndex = 0;
        }
      }
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

  bool get _allDone => kAshaSections.every((s) => _completed[s] == true);

  String get _currentSection => kAshaSections[_sectionIndex];

  // ── Saves (optimistic, save-on-change, toast on failure) ──────────

  Future<void> _saveMark(_Mark m) {
    late final Future<void> save;
    save = () async {
      try {
        await _service.updateMilestone(
          rowId: m.rowId,
          status: m.status,
          evidenceSource: m.evidence,
        );
      } catch (e) {
        _toast('Could not save milestone: $e');
      } finally {
        _pendingSaves.remove(save);
      }
    }();
    _pendingSaves.add(save);
    return save;
  }

  /// Tap on the card body. Before the section is declared done, toggles
  /// present ↔ not-yet-captured. After, toggles present ↔ absent — the
  /// null state no longer exists once the section is a declared record.
  void _tapCard(_Mark m) {
    setState(() {
      if (m.status == 'present') {
        m.status = _completed[_currentSection] == true ? 'absent' : null;
        m.evidence = null;
      } else {
        m.status = 'present';
        m.evidence ??= 'observed';
      }
    });
    _saveMark(m);
  }

  /// The visible Emerging chip. Toggles emerging on/off; off falls back
  /// the same way as unmarking present does.
  void _tapEmerging(_Mark m) {
    setState(() {
      if (m.status == 'emerging') {
        m.status = _completed[_currentSection] == true ? 'absent' : null;
        m.evidence = null;
      } else {
        m.status = 'emerging';
        m.evidence ??= 'observed';
      }
    });
    _saveMark(m);
  }

  void _setEvidence(_Mark m, String evidence) {
    if (m.evidence == evidence) return;
    setState(() => m.evidence = evidence);
    _saveMark(m);
  }

  Future<void> _completeSection() async {
    // Capture the section BEFORE any state change — and refuse a
    // re-entry or a tap on an already-declared section outright.
    final section = _currentSection;
    final id = _assessmentId;
    if (id == null || _completing || _completed[section] == true) return;
    setState(() => _completing = true);

    // Let in-flight row saves land so "unmarked" below means exactly
    // what the screen shows. These futures never throw (they toast).
    while (_pendingSaves.isNotEmpty) {
      await Future.wait(_pendingSaves.toList());
    }
    if (!mounted) return;

    final flipped =
        _marks[section]!.where((m) => m.status == null).toList();
    final sectionIndexBefore = _sectionIndex;
    setState(() {
      for (final m in flipped) {
        m.status = 'absent';
      }
      _completed[section] = true;
      if (_sectionIndex < kAshaSections.length - 1) _sectionIndex += 1;
    });
    try {
      await _service.completeSection(
        assessmentId: id,
        section: section,
        unmarkedRowIds: [for (final m in flipped) m.rowId],
      );
    } catch (e) {
      // Roll the declaration back — a section must never read "on
      // record" when the DB never recorded it (the ghost note replaces
      // the Done button, so without this there is no retry path).
      if (mounted) {
        setState(() {
          for (final m in flipped) {
            m.status = null;
          }
          _completed[section] = false;
          _sectionIndex = sectionIndexBefore;
        });
      }
      _toast('Could not save section completion: $e');
    } finally {
      if (mounted) {
        setState(() => _completing = false);
      } else {
        _completing = false;
      }
    }
  }

  // ── Build ─────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const SizedBox(
          height: 100, child: Center(child: CircularProgressIndicator()));
    }
    if (_error != null) {
      return _errorBox('Could not load Pediatric Language capture: $_error');
    }
    return switch (_state!) {
      PedLanguageBootstrapState.noAge => _noAgeState(),
      PedLanguageBootstrapState.invalidDob => _invalidDobState(),
      PedLanguageBootstrapState.outOfAgeRange => _outOfRangeState(),
      PedLanguageBootstrapState.ready => _captureBody(),
    };
  }

  Widget _noAgeState() => _ghostNote(
      'The milestone check opens on the age band that matches this child. '
      'Add a date of birth (or an age) to the client record and reopen — '
      'the matching band loads by itself.');

  Widget _invalidDobState() => _ghostNote(
      'The date of birth on this client record is in the future — likely '
      'a data-entry slip. Correct it and reopen; the matching band loads '
      'by itself.');

  Widget _outOfRangeState() => _ghostNote(
      'The ASHA milestone set covers birth to 5 years. This child\'s age '
      'on file is ${_ageLine()} — outside the set\'s range, so no band is '
      'shown.');

  Widget _captureBody() {
    final band = _band!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _header(band),
        const SizedBox(height: 12),
        _progressSteps(),
        const SizedBox(height: 14),
        if (_allDone) ...[
          _completedSummary(),
          const SizedBox(height: 14),
        ],
        if (band.note != null && _sectionIndex == 0) ...[
          _ghostNote(band.note!),
          const SizedBox(height: 10),
        ],
        ..._sectionCards(),
        const SizedBox(height: 14),
        _doneButton(),
      ],
    );
  }

  Widget _header(AshaAgeBand band) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(band.label,
            style: GoogleFonts.dmSans(
                fontSize: 17, fontWeight: FontWeight.w700, color: _ink)),
        const SizedBox(height: 3),
        if (_ageMonths != null && _ageSource != null)
          Text(
              pedLanguageAgeDerivationLine(
                band: band,
                derivedAgeMonths: _ageMonths!,
                ageSource: _ageSource!,
              ),
              style: GoogleFonts.dmSans(fontSize: 12, color: _inkGhost)),
        const SizedBox(height: 8),
        Text(_source,
            style: GoogleFonts.dmSans(
                fontSize: 11,
                color: _inkGhost,
                fontStyle: FontStyle.italic)),
      ],
    );
  }

  String _ageLine() {
    final months = _ageMonths;
    if (months == null) return '';
    final y = months ~/ 12;
    final m = months % 12;
    final age = y == 0 ? '$m months' : (m == 0 ? '$y years' : '$y y $m m');
    final from = _ageSource == 'dob'
        ? 'from date of birth'
        : 'from stated age (midpoint)';
    return '$age · $from';
  }

  Widget _progressSteps() {
    return Row(
      children: [
        for (var i = 0; i < kAshaSections.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(child: _step(i)),
        ],
      ],
    );
  }

  Widget _step(int i) {
    final section = kAshaSections[i];
    final marks = _marks[section]!;
    final markedCount = marks.where((m) => m.status != null).length;
    final active = i == _sectionIndex;
    final done = _completed[section] == true;
    return GestureDetector(
      onTap: () => setState(() => _sectionIndex = i),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
        decoration: BoxDecoration(
          color: active ? _amberSoft.withValues(alpha: 0.45) : null,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
              color: active ? _amber.withValues(alpha: 0.6) : _line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(_kSectionLabels[section]!.toUpperCase(),
                      style: GoogleFonts.syne(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 1.4,
                          color: active ? _ink : _inkGhost)),
                ),
                if (done)
                  const Icon(Icons.check_rounded, size: 14, color: _teal),
              ],
            ),
            const SizedBox(height: 3),
            Text('$markedCount of ${marks.length}',
                style: GoogleFonts.dmSans(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    fontFeatures: const [FontFeature.tabularFigures()],
                    color: active ? _ink : _inkGhost)),
          ],
        ),
      ),
    );
  }

  List<Widget> _sectionCards() {
    final marks = _marks[_currentSection]!;
    return [
      for (final m in marks) ...[
        _milestoneCard(m),
        const SizedBox(height: 8),
      ],
    ];
  }

  Widget _milestoneCard(_Mark m) {
    final present = m.status == 'present';
    final emerging = m.status == 'emerging';
    final absent = m.status == 'absent';
    final marked = present || emerging;

    final Color border = present
        ? _teal
        : emerging
            ? _amber
            : _line;
    final Color? fill = present
        ? _tealSoft.withValues(alpha: 0.35)
        : emerging
            ? _amberSoft.withValues(alpha: 0.35)
            : null;

    return InkWell(
      onTap: () => _tapCard(m),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: fill,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(m.text,
                      style: GoogleFonts.dmSans(
                          fontSize: 13.5,
                          height: 1.35,
                          fontWeight:
                              marked ? FontWeight.w600 : FontWeight.w500,
                          color: absent ? _inkGhost : _ink)),
                ),
                const SizedBox(width: 8),
                if (present)
                  const Icon(Icons.check_circle_rounded,
                      size: 18, color: _teal)
                else if (emerging)
                  const Icon(Icons.trending_up_rounded,
                      size: 18, color: _amber)
                else if (absent)
                  Text('absent',
                      style: GoogleFonts.dmSans(
                          fontSize: 11,
                          fontStyle: FontStyle.italic,
                          color: _inkGhost)),
              ],
            ),
            if (m.example != null && m.example!.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(m.example!,
                  style: GoogleFonts.dmSans(
                      fontSize: 12,
                      height: 1.3,
                      fontStyle: FontStyle.italic,
                      color: _inkGhost)),
            ],
            const SizedBox(height: 8),
            Row(
              children: [
                _chip(
                  label: 'Emerging',
                  selected: emerging,
                  color: _amber,
                  soft: _amberSoft,
                  onTap: () => _tapEmerging(m),
                ),
                if (marked) ...[
                  const SizedBox(width: 12),
                  Container(width: 1, height: 16, color: _line),
                  const SizedBox(width: 12),
                  _chip(
                    label: 'Observed',
                    selected: m.evidence == 'observed',
                    color: _teal,
                    soft: _tealSoft,
                    onTap: () => _setEvidence(m, 'observed'),
                  ),
                  const SizedBox(width: 6),
                  _chip(
                    label: 'Parent-reported',
                    selected: m.evidence == 'parent_reported',
                    color: _teal,
                    soft: _tealSoft,
                    onTap: () => _setEvidence(m, 'parent_reported'),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _chip({
    required String label,
    required bool selected,
    required Color color,
    required Color soft,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: selected ? soft : null,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: selected ? color : _line,
              width: selected ? 1.2 : 1),
        ),
        child: Text(label,
            style: GoogleFonts.dmSans(
                fontSize: 11,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                color: selected ? _ink : _inkGhost)),
      ),
    );
  }

  Widget _doneButton() {
    final section = _currentSection;
    if (_completed[section] == true) {
      // Reviewing a declared-done section — nothing to declare again.
      return _ghostNote(_allDone
          ? 'All three sections are on record. Tap any milestone to revise.'
          : 'This section is on record. Tap any milestone to revise, or '
              'pick the next section above.');
    }
    final last = _sectionIndex == kAshaSections.length - 1;
    final next = last
        ? 'finish capture'
        : 'next: ${_kSectionLabels[kAshaSections[_sectionIndex + 1]]}';
    return FilledButton(
      onPressed: _completing ? null : _completeSection,
      style: FilledButton.styleFrom(
        backgroundColor: kCueAmber,
        // Explicit — never inherit the active brightness default
        // (polarity-4, CLAUDE.md). Disabled stays the same hue at half
        // alpha, matching the amber-site convention.
        foregroundColor: Colors.white,
        disabledBackgroundColor: kCueAmber.withValues(alpha: 0.5),
        disabledForegroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 13),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10)),
      ),
      child: Text('Done — $next',
          style:
              GoogleFonts.dmSans(fontSize: 13.5, fontWeight: FontWeight.w600)),
    );
  }

  Widget _completedSummary() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _tealSoft.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('MILESTONE CHECK ON RECORD',
              style: GoogleFonts.syne(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.6,
                  color: _inkGhost)),
          const SizedBox(height: 8),
          for (final section in kAshaSections)
            Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Text(
                '${_kSectionLabels[section]}: ${_summaryLine(section)}',
                style: GoogleFonts.dmSans(fontSize: 12.5, color: _ink),
              ),
            ),
        ],
      ),
    );
  }

  String _summaryLine(String section) {
    final marks = _marks[section]!;
    int count(String s) => marks.where((m) => m.status == s).length;
    final parts = <String>[
      '${count('present')} present',
      if (count('emerging') > 0) '${count('emerging')} emerging',
      '${count('absent')} absent',
    ];
    final parentReported = marks
        .where((m) =>
            m.evidence == 'parent_reported' &&
            (m.status == 'present' || m.status == 'emerging'))
        .length;
    if (parentReported > 0) {
      parts.add('$parentReported parent-reported');
    }
    return parts.join(' · ');
  }

  // ── Small shared pieces ───────────────────────────────────────────

  Widget _ghostNote(String msg) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: _tealSoft.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(msg,
            style: GoogleFonts.dmSans(
                fontSize: 12.5, height: 1.4, color: _inkGhost)),
      );

  Widget _errorBox(String msg) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: _coral.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(msg,
            style: GoogleFonts.dmSans(fontSize: 12, color: _ink)),
      );

  void _toast(String msg) {
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(msg)));
    }
  }
}
