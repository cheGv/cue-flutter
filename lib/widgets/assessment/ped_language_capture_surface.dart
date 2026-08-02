// lib/widgets/assessment/ped_language_capture_surface.dart
//
// Pediatric Language capture surface — ASHA developmental milestone
// check, birth-5. Wired on clinical_area 'pediatric-language'.
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
// Lifecycle (retrofitted 2026-07-29): the completion machinery — the
// in-flight save queue, idempotent completion keyed on the section
// whose Done button was rendered, per-key seed self-heal, rollback on
// a failed completion, and the dirty-row refusal — is
// SectionalCaptureController's; this file only renders, mutates its
// marks optimistically, and hands persists to the controller. Rows a
// save failed for are VISIBLY marked "not saved" (card chip + step dot
// + a retry banner above Done); complete() refuses on them
// (refusedDirty) and the Retry affordance calls retryDirty(). Nothing
// about failure is silent. Palette is the sibling constants (teal
// migration is a later per-surface pass); the FilledButton uses
// kCueAmber with an EXPLICIT white foreground (polarity-4, CLAUDE.md).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../models/asha_milestone_library.dart';
import '../../services/ped_language_assessment_service.dart';
import '../../theme/cue_phase4_tokens.dart' show kCueAmber;
import 'sectional_capture.dart';

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

class _PedLanguageCaptureSurfaceState extends State<PedLanguageCaptureSurface> {
  final _service = PedLanguageAssessmentService.instance;

  bool _loading = true;
  String? _error;

  PedLanguageBootstrapState? _state;
  AshaAgeBand? _band;
  String _source = '';
  int? _ageMonths;
  String? _ageSource;

  SectionalCaptureController<PedLanguageMark>? _controller;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    _controller?.removeListener(_onControllerChanged);
    _controller?.dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _bootstrap() async {
    try {
      final b = await _service.resolveParent(clientId: widget.clientId);
      _state = b.state;
      _source = b.source;
      _ageMonths = b.ageMonths;
      _ageSource = b.ageSource;
      if (b.state == PedLanguageBootstrapState.ready) {
        _band = b.band;
        final controller = SectionalCaptureController<PedLanguageMark>(
          config: pedLanguageSectionalConfig(b.band!),
          store: PedLanguageSectionalStore(
            assessmentId: b.assessment!['id'] as String,
            band: b.band!,
            library: await AshaMilestoneLibrary.load(),
          ),
        );
        // Seed self-heal + row load + completion hydration — the one
        // and only bootstrap path.
        await controller.bootstrap();
        controller.addListener(_onControllerChanged);
        _controller = controller;
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

  // ── Saves (optimistic; the controller tracks + dirty-marks) ───────

  void _save(PedLanguageMark m) {
    unawaited(_controller!
        .trackRowSave(
            m.id,
            // Reads the mark's CURRENT state at execution, so a retained
            // retry persists what the clinician sees now.
            () => _service.updateMilestone(
                rowId: m.id, status: m.status, evidenceSource: m.evidence))
        .catchError((Object e) => _toast('Could not save milestone: $e')));
  }

  /// Tap on the card body. Before the section is declared done, toggles
  /// present ↔ not-yet-captured. After, toggles present ↔ absent — the
  /// null state no longer exists once the section is a declared record.
  void _tapCard(PedLanguageMark m) {
    final completed = _controller!.isCompleted(m.section);
    setState(() {
      if (m.status == 'present') {
        m.status = completed ? 'absent' : null;
        m.evidence = null;
      } else {
        m.status = 'present';
        m.evidence ??= 'observed';
      }
    });
    _save(m);
  }

  /// The visible Emerging chip. Toggles emerging on/off; off falls back
  /// the same way as unmarking present does.
  void _tapEmerging(PedLanguageMark m) {
    final completed = _controller!.isCompleted(m.section);
    setState(() {
      if (m.status == 'emerging') {
        m.status = completed ? 'absent' : null;
        m.evidence = null;
      } else {
        m.status = 'emerging';
        m.evidence ??= 'observed';
      }
    });
    _save(m);
  }

  void _setEvidence(PedLanguageMark m, String evidence) {
    if (m.evidence == evidence) return;
    setState(() => m.evidence = evidence);
    _save(m);
  }

  // ── Completion + dirty retry (controller-owned semantics) ─────────

  /// [section] is the section whose Done button was RENDERED — the
  /// controller keys on it, so a stale tap can never touch a different
  /// section.
  Future<void> _onDone(String section) async {
    final result = await _controller!.complete(section);
    switch (result.outcome) {
      case SectionalCompletionOutcome.completed:
      case SectionalCompletionOutcome.alreadyCompleted:
      case SectionalCompletionOutcome.refusedBusy:
        break; // named no-ops; the listener re-renders any advance
      case SectionalCompletionOutcome.refusedDirty:
        _toastWithRetry(
            '${result.dirtyRowIds.length} milestone'
            '${result.dirtyRowIds.length == 1 ? ' is' : 's are'} not saved '
            '— retry before declaring this section done.');
      case SectionalCompletionOutcome.rolledBack:
        _toast('Could not save section completion: ${result.error}');
    }
  }

  Future<void> _retryDirty() async {
    final still = await _controller!.retryDirty();
    if (still.isNotEmpty && mounted) {
      _toast('Still not saved — check the connection and retry.');
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
    final c = _controller!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _header(band),
        const SizedBox(height: 12),
        _progressSteps(),
        const SizedBox(height: 14),
        if (c.allCompleted) ...[
          _completedSummary(),
          const SizedBox(height: 14),
        ],
        if (band.note != null && c.currentIndex == 0) ...[
          _ghostNote(band.note!),
          const SizedBox(height: 10),
        ],
        ..._sectionCards(),
        if (_dirtyInCurrentSection().isNotEmpty) ...[
          const SizedBox(height: 6),
          _dirtyBanner(),
        ],
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

  List<PedLanguageMark> _dirtyInSection(String section) {
    final dirty = _controller!.dirtyRowIds;
    return [
      for (final m in _controller!.rowsIn(section))
        if (dirty.contains(m.id)) m,
    ];
  }

  List<PedLanguageMark> _dirtyInCurrentSection() =>
      _dirtyInSection(_controller!.currentSectionId);

  Widget _step(int i) {
    final c = _controller!;
    final section = kAshaSections[i];
    final marks = c.rowsIn(section);
    final active = i == c.currentIndex;
    final done = c.isCompleted(section);
    final hasDirty = _dirtyInSection(section).isNotEmpty;
    return GestureDetector(
      onTap: () => c.goTo(section),
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
                if (hasDirty)
                  Container(
                    width: 7,
                    height: 7,
                    margin: const EdgeInsets.only(right: 4),
                    decoration: const BoxDecoration(
                        color: _coral, shape: BoxShape.circle),
                  ),
                if (done)
                  const Icon(Icons.check_rounded, size: 14, color: _teal),
              ],
            ),
            const SizedBox(height: 3),
            Text('${c.markedCount(section)} of ${marks.length}',
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
    final marks = _controller!.rowsIn(_controller!.currentSectionId);
    return [
      for (final m in marks) ...[
        _milestoneCard(m),
        const SizedBox(height: 8),
      ],
    ];
  }

  Widget _milestoneCard(PedLanguageMark m) {
    final present = m.status == 'present';
    final emerging = m.status == 'emerging';
    final absent = m.status == 'absent';
    final marked = present || emerging;
    final dirty = _controller!.dirtyRowIds.contains(m.id);

    final Color border = dirty
        ? _coral
        : present
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
                if (dirty)
                  Text('not saved',
                      style: GoogleFonts.dmSans(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: _coral))
                else if (present)
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

  /// Visible, actionable unsaved-state: names the count, offers Retry.
  Widget _dirtyBanner() {
    final dirty = _dirtyInCurrentSection();
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      decoration: BoxDecoration(
        color: _coral.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _coral.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
                '${dirty.length} milestone${dirty.length == 1 ? '' : 's'} '
                'not saved.',
                style: GoogleFonts.dmSans(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: _ink)),
          ),
          TextButton(
            onPressed: _retryDirty,
            style: TextButton.styleFrom(foregroundColor: _coral),
            child: Text('Retry',
                style: GoogleFonts.dmSans(
                    fontSize: 12.5, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  Widget _doneButton() {
    final c = _controller!;
    final section = c.currentSectionId;
    if (c.isCompleted(section)) {
      // Reviewing a declared-done section — nothing to declare again.
      return _ghostNote(c.allCompleted
          ? 'All three sections are on record. Tap any milestone to revise.'
          : 'This section is on record. Tap any milestone to revise, or '
              'pick the next section above.');
    }
    final last = c.currentIndex == kAshaSections.length - 1;
    final next = last
        ? 'finish capture'
        : 'next: ${_kSectionLabels[kAshaSections[c.currentIndex + 1]]}';
    return FilledButton(
      // The section is captured at RENDER time and the controller keys
      // on it — a stale tap cannot complete a different section.
      onPressed: c.completing ? null : () => _onDone(section),
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
    final marks = _controller!.rowsIn(section);
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

  void _toastWithRetry(String msg) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(msg),
        action: SnackBarAction(label: 'RETRY', onPressed: _retryDirty),
      ));
    }
  }
}
