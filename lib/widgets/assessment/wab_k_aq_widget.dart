// lib/widgets/assessment/wab_k_aq_widget.dart
//
// Intern scaffold Phase B1 — the WAB-K Aphasia Quotient PROVING WIDGET.
//
// This is the two-register pattern proven on the cleanest possible
// instrument: four subscore capture fields (the SILENT register) + the AQ
// LoudResult (the LOUD register) computing live. It is deliberately a
// CONTAINED widget — wired to NOTHING persistent: no clinical_area, no
// schema, no service, no reader. Guru administers the WAB clinically and
// this graduates to a full sibling surface LATER (the SSD/feeding ritual),
// as a separate gated step after the pattern is reviewed. Do not bolt
// persistence onto this file; graduation replaces it.
//
// THE INTERACTION — silent computation. Scores in → AQ appears. No prompts,
// no "ready to calculate?", no narration. While fewer than four subscores
// are entered the readout waits quietly ("insufficient data — N more
// subscore(s) needed"); the moment the fourth lands, the result resolves in.
// Editing a subscore recomputes in place; clearing one recedes to waiting.
//
// THE FORMULA (verified against the literature, 2026-06-12 — see the
// citation block on [computeWabAq] / [wabKerteszBand]):
//   AQ = (Spontaneous Speech [/20] + Comprehension [/10] + Repetition [/10]
//        + Naming [/10]) × 2, range 0–100.
// The clinician enters the four SCALED subscores exactly as the WAB
// protocol derives them (auditory verbal comprehension raw/200 ÷ 20,
// repetition raw/100 ÷ 10, naming raw/100 ÷ 10 — that scaling happens on
// her protocol sheet, not here). Entries above a subscore's published
// maximum do not compute: the readout names the violation factually and
// waits. Never a fabricated AQ.
//
// THE BOUNDARY: the widget announces the value, the Kertesz band, the
// arithmetic, the citation — and nothing else. No "indicates", no
// "consider", no severity commentary, no therapy direction. The Section 5
// forbidden-language suite runs over every rendered state in
// test/widgets/wab_k_aq_widget_test.dart.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import 'loud_result.dart';

// Locked spine palette (matches the sibling assessment surfaces).
const Color _ink = Color(0xFF1B2B4B); // kCueInk
const Color _inkTertiary = Color(0xFF888780); // metadata / suffixes

/// Published subscore maxima (WAB AQ components; see [computeWabAq]).
const double kWabSpontaneousSpeechMax = 20;
const double kWabComprehensionMax = 10;
const double kWabRepetitionMax = 10;
const double kWabNamingMax = 10;

/// AQ = (Spontaneous Speech + Comprehension + Repetition + Naming) × 2.
///
/// Sources (verified 2026-06-12):
///   * Kertesz, A. (1982). The Western Aphasia Battery. Grune & Stratton.
///   * Formula with the ×2 and the 20/10/10/10 component maxima:
///     Sci Reports 12, 13965 (2022), nature.com/articles/s41598-022-17997-0 —
///     "AQ = (Spontaneous + Comprehension ÷ 20 + Repetition ÷ 10 +
///     Naming ÷ 10) × 2"; component points 20/10/10/10, sum 50, ×2 → 100.
///   * Strokengine WAB measure review: AQ sums the four spoken-language
///     subtests (spontaneous speech, auditory verbal comprehension,
///     repetition, naming and word finding).
///
/// Returns null until all four subscores are present — the readout renders
/// "insufficient data", never a fabricated value.
double? computeWabAq({
  required double? spontaneousSpeech,
  required double? comprehension,
  required double? repetition,
  required double? naming,
}) {
  if (spontaneousSpeech == null ||
      comprehension == null ||
      repetition == null ||
      naming == null) {
    return null;
  }
  return (spontaneousSpeech + comprehension + repetition + naming) * 2;
}

/// Kertesz severity band for an AQ.
///
/// Published bands (Kertesz 1982; confirmed 2026-06-12 via Strokengine's WAB
/// measure review and consistent across the clinical literature):
///   0–25 very severe · 26–50 severe · 51–75 moderate · 76+ mild.
///
/// Operationalization: the published table is integer-styled; the ÷20/÷10
/// subscore scalings make fractional AQs routine, so the bands are read
/// continuously — ≤25, ≤50, ≤75, >75 — banding on the exact (unrounded)
/// value.
///
/// NOT encoded here: Kertesz's recommended aphasia cutoff of AQ 93.8 (100%
/// specificity / 60% sensitivity per Strokengine). An AQ above it still
/// renders the published "Mild" band; whether Cue should additionally state
/// the cutoff relation — and whether WAB-K (Kannada) cutoffs belong here
/// instead of/alongside the English-WAB norms — is flagged for Guru in the
/// Phase B report, not decided in code.
String wabKerteszBand(double aq) {
  if (aq <= 25) return 'Very severe';
  if (aq <= 50) return 'Severe';
  if (aq <= 75) return 'Moderate';
  return 'Mild';
}

/// Norming caveat v1 — wording flagged for Guru's review in the Phase B
/// report. The limitation is documented, not invented: the severity bands
/// are English-WAB norms (Kertesz 1982), while the Kannada WAB-K publishes
/// its own normative data (AIISH; Chengappa & Kumar's WAB-K normative
/// study).
const String kWabKNormingCaveatV1 =
    'Severity bands are Kertesz 1982 (English WAB) norms — the Kannada '
    'WAB-K publishes its own normative data; interpret with that context.';

class WabKAqWidget extends StatefulWidget {
  const WabKAqWidget({super.key});

  @override
  State<WabKAqWidget> createState() => _WabKAqWidgetState();
}

class _Subscore {
  final String label;
  final double max;
  final TextEditingController ctrl = TextEditingController();
  _Subscore(this.label, this.max);

  /// Parsed value; null when empty or unparseable (unparseable input counts
  /// as not-entered, never as zero).
  double? get value => double.tryParse(ctrl.text.trim());
}

class _WabKAqWidgetState extends State<WabKAqWidget> {
  late final List<_Subscore> _subscores = [
    _Subscore('Spontaneous Speech', kWabSpontaneousSpeechMax),
    _Subscore('Comprehension', kWabComprehensionMax),
    _Subscore('Repetition', kWabRepetitionMax),
    _Subscore('Naming', kWabNamingMax),
  ];

  @override
  void dispose() {
    for (final s in _subscores) {
      s.ctrl.dispose();
    }
    super.dispose();
  }

  /// The readout state the current inputs deterministically dictate.
  LoudResultState _aqState() {
    // A subscore above its published maximum cannot compute — name it
    // factually and wait. (Negatives are unreachable: the input formatter
    // admits only digits and the decimal point.)
    for (final s in _subscores) {
      final v = s.value;
      if (v != null && v > s.max) {
        return LoudResultInsufficient(
            missing:
                '${s.label} exceeds its /${s.max.toStringAsFixed(0)} maximum');
      }
    }

    final values = [for (final s in _subscores) s.value];
    final missing = values.where((v) => v == null).length;
    if (missing > 0) {
      return LoudResultInsufficient(
          missing: '$missing more subscore${missing == 1 ? '' : 's'} needed');
    }

    final aq = computeWabAq(
      spontaneousSpeech: values[0],
      comprehension: values[1],
      repetition: values[2],
      naming: values[3],
    )!;
    final terms = values.map((v) => _fmtTerm(v!)).join(' + ');
    return LoudResultResolved(
      value: aq.toStringAsFixed(1),
      band: wabKerteszBand(aq),
      math: '($terms) × 2 = ${aq.toStringAsFixed(1)}',
      citation: 'Kertesz 1982',
    );
  }

  /// "14" stays 14; "7.5" stays 7.5 — terms render as entered, never padded.
  String _fmtTerm(double v) =>
      v == v.truncateToDouble() ? v.toStringAsFixed(0) : v.toString();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(children: [
          Expanded(child: _numField(_subscores[0])),
          const SizedBox(width: 12),
          Expanded(child: _numField(_subscores[1])),
        ]),
        Row(children: [
          Expanded(child: _numField(_subscores[2])),
          const SizedBox(width: 12),
          Expanded(child: _numField(_subscores[3])),
        ]),
        const SizedBox(height: 8),
        LoudResult(
          label: 'Aphasia Quotient',
          state: _aqState(),
          caution: kWabKNormingCaveatV1,
        ),
      ],
    );
  }

  /// Silent-register numeric field — the SSD surface's proven shape: quiet
  /// label, dense outlined input, the published maximum as a suffix tag.
  Widget _numField(_Subscore s) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(s.label,
            style: GoogleFonts.inter(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: _ink,
                letterSpacing: -0.05)),
        const SizedBox(height: 4),
        TextField(
          controller: s.ctrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))
          ],
          style: GoogleFonts.inter(
              fontSize: 13.5, fontWeight: FontWeight.w400, color: _ink),
          decoration: InputDecoration(
            suffixText: '/${s.max.toStringAsFixed(0)}',
            suffixStyle: GoogleFonts.inter(fontSize: 12, color: _inkTertiary),
            border: const OutlineInputBorder(),
            isDense: true,
          ),
          onChanged: (_) => setState(() {}),
        ),
      ]),
    );
  }
}
