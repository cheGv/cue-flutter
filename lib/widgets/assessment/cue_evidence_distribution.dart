// lib/widgets/assessment/cue_evidence_distribution.dart
//
// Intern scaffold Phase C — the VISUAL register, component 2: the equal-weight
// evidence distribution.
//
// THE PRINCIPLE (the boundary, for visuals). The visual REVEALS structure the
// clinician interprets; it never arranges structure so the interpretation is
// pre-made. Symmetric revelation (show the data's shape evenly, the clinician
// reads it) is safe; asymmetric emphasis (make one option louder/bigger/
// sorted-first because it is "the likely answer") is the boundary crossed. A
// chart persuades harder than a sentence, so the boundary here is stricter.
//
// THE HARD RULE (structural, tested): NEVER RANK BY LIKELIHOOD. This shows
// WHERE evidence has accumulated across a set of options, with strictly equal
// visual treatment, so the clinician sees the distribution at a glance and
// draws their own conclusion. It does NOT:
//   * sort, size, bold, position-first, or highlight any option by its count —
//     [build] contains no sort; options render in their INPUT (definition,
//     content-neutral) order; reorder the input and the render reorders with
//     it, never by count;
//   * scale any option's visual WEIGHT with its count — every row is one fixed
//     height, one label style, one dot size, and the SAME dot-track width. Only
//     how many dots are FILLED (and the tally text) varies, because that is the
//     evidence itself — the data shown evenly, not an option made dominant.
// "Lots of evidence" is not "the answer" (evidence points many ways); the
// component shows the tally and says nothing about which option is correct.
//
// Absence is information: an option with no evidence renders its empty state
// (all dots empty, count 0) — never hidden, never de-emphasized.
//
// REGISTER & PALETTE — locked light-spine palette, file-local consts, exactly
// like the sibling assessment components. Olive = the calm reading-aid
// register; quiet, a reading aid and not a centerpiece.
//
// CONTAINED & STANDALONE: wired to NO surface, no schema, no service. The
// boundary suite in test/widgets/cue_evidence_distribution_test.dart makes
// ranking/sizing unrepresentable in a passing build.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// Locked spine palette (matches the sibling assessment components).
const Color _ink = Color(0xFF1B2B4B); // kCueInk
const Color _inkSecondary = Color(0xFF5F5E5A); // tally text
const Color _line = Color(0xFFE8E4DC); // kCueBorder hairline (empty dot)
const Color _olive = Color(0xFF5C6E3B); // calm reading-aid accent (filled dot)

/// One option and the COUNT of captured evidence items pointing at it. Count 0
/// is a real, rendered state — absence of evidence is itself information the
/// clinician reads.
class CueEvidenceOption {
  final String label;
  final int count;
  const CueEvidenceOption(this.label, this.count)
      : assert(count >= 0, 'evidence count is a tally, never negative');
}

/// Equal-weight evidence distribution across [options]. Every option is
/// rendered in the SAME register — same row height, same label style, same dot
/// size, same dot-track width, same position rule (input order). Only the
/// number of FILLED dots and the tally text vary, because that is the data.
class CueEvidenceDistribution extends StatelessWidget {
  /// Rendered in this exact order (definition / content-neutral). NEVER sorted
  /// by count — see [build].
  final List<CueEvidenceOption> options;

  const CueEvidenceDistribution(this.options, {super.key});

  static const double _labelW = 132;
  static const double _tallyW = 20;
  static const double _dotD = 9;

  /// The shared dot-track length: the largest count present, clamped to a
  /// readable range. Data-driven WIDTH — and identical for every row, so a
  /// higher count fills more of the SAME track, never a longer or bigger one.
  static int trackSlots(List<CueEvidenceOption> options) {
    if (options.isEmpty) return 0;
    final maxCount = options.map((o) => o.count).reduce(math.max);
    return maxCount.clamp(3, 8);
  }

  // ONE label style, ONE tally style — shared by every row, so no option's
  // prominence can scale with its count.
  static final TextStyle _labelStyle =
      GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w500, color: _ink);
  static final TextStyle _tallyStyle = GoogleFonts.inter(
      fontSize: 12,
      fontWeight: FontWeight.w600,
      color: _inkSecondary,
      fontFeatures: const [FontFeature.tabularFigures()]);

  @override
  Widget build(BuildContext context) {
    if (options.isEmpty) return const SizedBox.shrink();
    // NOTE: `options` is iterated as given — there is deliberately NO sort here.
    // Ordering by count would rank by likelihood; that is the parked question,
    // not this build.
    final slots = trackSlots(options);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < options.length; i++) ...[
          if (i > 0) const SizedBox(height: 8),
          _row(i, options[i], slots),
        ],
      ],
    );
  }

  /// EVERY row is built here with identical structure and styling. `o.count`
  /// drives ONLY how many dots are filled and the tally text — never the row
  /// height, the label weight, the dot size, or the position.
  Widget _row(int index, CueEvidenceOption o, int slots) {
    return Row(
      key: ValueKey('cue-ev-row-$index'),
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: _labelW,
          child: Text(o.label,
              style: _labelStyle, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
        const SizedBox(width: 12),
        Expanded(child: _dots(index, o.count, slots)),
        const SizedBox(width: 10),
        SizedBox(
          width: _tallyW,
          child: Text('${o.count}',
              textAlign: TextAlign.right, style: _tallyStyle),
        ),
      ],
    );
  }

  Widget _dots(int index, int count, int slots) {
    return Wrap(
      spacing: 5,
      runSpacing: 5,
      children: [
        for (var j = 0; j < slots; j++)
          _EvidenceDot(
            key: ValueKey(
                'cue-ev-dot-$index-$j-${j < count ? 'filled' : 'empty'}'),
            filled: j < count,
          ),
      ],
    );
  }
}

/// One evidence slot — fixed size whether filled or empty (size never scales
/// with count). Filled = olive disc; empty = hairline ring (absence shown, not
/// hidden).
class _EvidenceDot extends StatelessWidget {
  final bool filled;
  const _EvidenceDot({super.key, required this.filled});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: CueEvidenceDistribution._dotD,
      height: CueEvidenceDistribution._dotD,
      decoration: BoxDecoration(
        color: filled ? _olive : Colors.transparent,
        shape: BoxShape.circle,
        border: filled ? null : Border.all(color: _line, width: 1.4),
      ),
    );
  }
}
