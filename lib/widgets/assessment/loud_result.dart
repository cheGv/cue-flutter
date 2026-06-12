// lib/widgets/assessment/loud_result.dart
//
// Intern scaffold Phase A — the LOUD-register computed-result component.
//
// Cue's assessment surfaces behave like a faithful intern with two registers:
// SILENT (capture fields, section chrome — calm, recessive) and LOUD (computed
// results — announced when they resolve, with the math shown and the source
// cited). This file is the loud register as a standalone, reusable widget. It
// is the proof-of-pattern ancestor of the deferred shared AssessmentScaffold;
// existing surfaces (SSD's PCC family first) migrate to it LATER, per-surface,
// with their test suites green — never as part of this file's evolution.
//
// THE BOUNDARY (structural, tested — not aspirational):
// The intern computes what inputs deterministically dictate (a formula has one
// answer) and NEVER infers what inputs merely suggest (an inference is a
// choice, and choices are the clinician's). Concretely, this component:
//   * announces a value, its published band, the arithmetic, the citation —
//     and nothing else. No "indicates", no "consider", no "leans toward", no
//     next-probe nudge, no ranked likelihood, no projected trajectory.
//   * renders "insufficient data" with what's missing NAMED FACTUALLY when
//     inputs are incomplete — never a fabricated zero, never a directive.
//   * says nothing ABOUT the boundary (revised 2026-06-12). An earlier draft
//     appended a "the ratings are yours; the arithmetic is Cue's; your
//     interpretation governs" line to every resolved result — cut as
//     condescending clutter. The clinician entering scores already knows the
//     interpretation is hers; the boundary is structural (this component has
//     no inference mechanism to need disclaiming), and the restraint IS the
//     boundary: enforced by what the component cannot say, never announced
//     in what it does.
//   * is selectively loud: a metric with no published band shows the number
//     and an explicit "no published band" — it never borrows authority.
// test/widgets/loud_result_test.dart enforces all of this, including a
// forbidden-language sweep that makes inferential output unrepresentable in
// a passing build.
//
// REGISTER & PALETTE — locked light-spine palette + typography, file-local
// consts, exactly like the sibling assessment surfaces (pre-CueSurfaceScope
// discipline; theming migrates with the surfaces, not ahead of them):
//   * JetBrains Mono 10.5 w500 tracked uppercase = the data-tag eyebrow on
//     the resolved card only. Inter = everything read.
//   * Value is Inter w700 tabular at 26 — "numbers as game changers",
//     deliberately the largest thing in the component (Rule 7).
//   * NO italic (Rule 3). Olive stripe = Cue's calm clerical contribution
//     (the brief-card-stripe register); AMBER is reserved for the optional
//     norming-caveat block — the urgent exception, per the dual-accent
//     doctrine.
//   * The resolved state ANNOUNCES BY APPEARING: insufficient → resolved is
//     an AnimatedSwitcher event (fade + small rise), not a grey line filling
//     in. Live edits within the resolved state update in place — the EVENT
//     is the state change, not every keystroke.

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// Locked spine palette (matches the sibling assessment surfaces).
const Color _ink = Color(0xFF1B2B4B); // kCueInk
const Color _inkSecondary = Color(0xFF5F5E5A); // body / secondary content
const Color _inkTertiary = Color(0xFF888780); // eyebrows / metadata
const Color _line = Color(0xFFE8E4DC); // kCueBorder hairline
const Color _olive = Color(0xFF5C6E3B); // calm default accent
const Color _amber = Color(0xFFB45309); // urgent register (kCueAmber)
const Color _amberSoft = Color(0xFFF4E4C4);

/// Insufficient → resolved is an event the eye notices; long enough to read
/// as an arrival, short enough to never feel like theatre.
const Duration kLoudResultResolveDuration = Duration(milliseconds: 260);

// ─── State model ─────────────────────────────────────────────────────────────

/// The three honest states of a computed result. Sealed: a surface cannot
/// invent a fourth state (e.g. "probably…") without the compiler objecting.
sealed class LoudResultState {
  const LoudResultState();
}

/// No inputs at all. Renders nothing — the silent register's section chrome
/// owns the invitation. Never a fabricated zero.
class LoudResultEmpty extends LoudResultState {
  const LoudResultEmpty();
}

/// Inputs incomplete. Calm, recessive, NOT an error — the honest waiting
/// state. [missing] names what's absent factually ("2 more subscores
/// needed"), never directs the assessment ("run X next" is clinical
/// judgment and forbidden here).
class LoudResultInsufficient extends LoudResultState {
  final String missing;

  const LoudResultInsufficient({required this.missing})
      : assert(missing != '', 'name what is missing — factually');
}

/// All inputs present: the result announces. Value large, math shown, source
/// cited — and nothing else. Silent, clean, just the result.
class LoudResultResolved extends LoudResultState {
  /// Preformatted value, unit included where one exists ("67.0", "47.6%").
  final String value;

  /// Published band/label for the value ("Moderate", "severe"). Null when the
  /// metric has no published band — the component then says so explicitly
  /// rather than staying silent or borrowing one.
  final String? band;

  /// Optional quiet tag rendered beside the band naming WHOSE band it is
  /// ("Kertesz 1982 reference") — for instruments administered in an
  /// adaptation whose own normative cutoffs are not the displayed band's.
  /// The band must never read as the adaptation's validated cutoff; this
  /// note keeps the provenance at the band, where the eye reads it. Only
  /// meaningful with a band present.
  final String? bandNote;

  /// Optional quiet line under the value row identifying what was
  /// administered ("Telugu WAB · Pallavi 2010") — a record-keeping fact,
  /// calm register, never a verdict.
  final String? detail;

  /// The arithmetic, shown: "(14 + 7.5 + 6.2 + 5.8) × 2 = 67.0". Rendered
  /// verbatim — the component never reformats or re-derives it.
  final String math;

  /// Source of the formula/band: "Kertesz 1982", "Shriberg 1982,
  /// English-normed". Rendered as "per `<citation>`".
  final String citation;

  const LoudResultResolved({
    required this.value,
    this.band,
    this.bandNote,
    this.detail,
    required this.math,
    required this.citation,
  })  : assert(value != ''),
        assert(math != '', 'the math is shown, always'),
        assert(citation != '', 'a result without a source is an assertion'),
        assert(band == null || band != '', 'no band is null, not ""'),
        assert(bandNote == null || bandNote != ''),
        assert(bandNote == null || band != null,
            'a band note tags a band — there is nothing to tag without one'),
        assert(detail == null || detail != '');
}

// ─── Widget ──────────────────────────────────────────────────────────────────

class LoudResult extends StatelessWidget {
  /// Metric name in natural case ("Aphasia Quotient", "PCC"). The resolved
  /// card uppercases it into the mono data-tag register; the insufficient
  /// state keeps it quiet Inter inline — the register shift is part of the
  /// announcement.
  final String label;

  final LoudResultState state;

  /// Optional norming/validity caveat — a REAL FACT about the instrument
  /// (e.g. a band normed on one population: "Shriberg 1982, English-normed —
  /// interpret with cultural context."), passed by the caller only when the
  /// displayed reference carries a documented limitation. This is NOT the
  /// cut boundary-reassurance line: a population-specific band is an
  /// instrument validity limitation; who interprets needs no announcing.
  /// Renders in the AMBER caution register below the resolved card ONLY —
  /// a caveat belongs to a displayed reference, and in the waiting states
  /// there is no number to mis-interpret.
  final String? caution;

  const LoudResult({
    super.key,
    required this.label,
    required this.state,
    this.caution,
  }) : assert(label != '');

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: kLoudResultResolveDuration,
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeIn,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.04),
            end: Offset.zero,
          ).animate(animation),
          child: child,
        ),
      ),
      // Keyed by state TYPE: insufficient → resolved animates (the event);
      // a live recompute within resolved updates in place (no flash per
      // keystroke).
      child: KeyedSubtree(
        key: ValueKey<Type>(state.runtimeType),
        child: switch (state) {
          LoudResultEmpty() => const SizedBox.shrink(),
          LoudResultInsufficient s => _insufficient(s),
          LoudResultResolved s => _resolved(s),
        },
      ),
    );
  }

  // ── Insufficient — the silent register's voice ─────────────────────────

  Widget _insufficient(LoudResultInsufficient s) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(children: [
          Text(label,
              style: GoogleFonts.inter(
                  fontSize: 12,
                  color: _inkSecondary,
                  fontWeight: FontWeight.w500)),
          const SizedBox(width: 8),
          Text('insufficient data',
              style: GoogleFonts.inter(
                  fontSize: 12.5,
                  color: _inkTertiary,
                  fontWeight: FontWeight.w500)),
        ]),
        const SizedBox(height: 2),
        Text(s.missing,
            style: GoogleFonts.inter(
                fontSize: 12, color: _inkTertiary, height: 1.45)),
      ],
    );
  }

  // ── Resolved — the announcement ────────────────────────────────────────

  Widget _resolved(LoudResultResolved s) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: _line),
            ),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Olive stripe — Cue's calm clerical mark (the brief-card
                  // register), mirroring the caution block's amber stripe in
                  // shape but never in urgency.
                  Container(width: 3.5, color: _olive),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(label.toUpperCase(),
                              style: GoogleFonts.jetBrainsMono(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w500,
                                  color: _inkTertiary,
                                  letterSpacing: 10.5 * 0.14)),
                          const SizedBox(height: 6),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.baseline,
                            textBaseline: TextBaseline.alphabetic,
                            children: [
                              // Rule 7: the value is the largest thing here.
                              Text(s.value,
                                  style: GoogleFonts.inter(
                                      fontSize: 26,
                                      fontWeight: FontWeight.w700,
                                      color: _ink,
                                      fontFeatures: const [
                                        FontFeature.tabularFigures()
                                      ])),
                              const SizedBox(width: 10),
                              if (s.band != null) ...[
                                Flexible(
                                  child: Text(s.band!,
                                      style: GoogleFonts.inter(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                          color: _ink)),
                                ),
                                // Whose band it is, said quietly AT the band
                                // — never the administered adaptation's
                                // validated cutoff by implication.
                                if (s.bandNote != null) ...[
                                  const SizedBox(width: 6),
                                  Flexible(
                                    child: Text(s.bandNote!,
                                        style: GoogleFonts.inter(
                                            fontSize: 11.5,
                                            fontWeight: FontWeight.w500,
                                            color: _inkTertiary)),
                                  ),
                                ],
                              ] else
                                // Selective loudness: no published band is
                                // said out loud, quietly.
                                Flexible(
                                  child: Text('no published band',
                                      style: GoogleFonts.inter(
                                          fontSize: 11.5,
                                          fontWeight: FontWeight.w500,
                                          color: _inkTertiary)),
                                ),
                            ],
                          ),
                          if (s.detail != null) ...[
                            const SizedBox(height: 4),
                            Text(s.detail!,
                                style: GoogleFonts.inter(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w500,
                                    color: _inkSecondary)),
                          ],
                          const SizedBox(height: 8),
                          Text(s.math,
                              style: GoogleFonts.inter(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  color: _inkSecondary,
                                  fontFeatures: const [
                                    FontFeature.tabularFigures()
                                  ])),
                          const SizedBox(height: 2),
                          Text('per ${s.citation}',
                              style: GoogleFonts.inter(
                                  fontSize: 11.5, color: _inkTertiary)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (caution != null) ...[
          const SizedBox(height: 8),
          _cautionNote(caution!),
        ],
      ],
    );
  }

  /// AMBER caution register — left stripe + weighted text, the SSD surface's
  /// proven shape, so a norming caveat can never read as decoration.
  Widget _cautionNote(String text) => ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Container(
          color: _amberSoft.withValues(alpha: 0.45),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
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
              ],
            ),
          ),
        ),
      );
}
