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
// THE MULTILINGUAL LAYER (Phase B+, 2026-06-12). The AQ formula is identical
// across every published WAB language adaptation — language changes the
// LABEL, never the arithmetic. The adaptation selector therefore changes
// exactly two things on the result: the administered-instrument detail line
// ("Telugu WAB · Pallavi 2010") and the norming caveat. It never changes the
// AQ, the band, or the math. THE ONE HONEST CONSTRAINT: the severity band is
// always shown as "Kertesz 1982 reference" — a true statement — and never
// asserted as the selected adaptation's own validated cutoff, because some
// adaptations (Kannada, Bengali) publish their own normative data and we
// have not verified which kept Kertesz's bands. Cue computes the
// language-independent AQ, labels the reference truthfully, and the
// clinician applies the administered adaptation's norms. The same honesty
// governs the 93.8 aphasia cutoff (Kertesz & Poole 1974): it is the
// English-WAB cutoff, named as such, with the adaptation caveat carrying its
// provenance — reported, never recomputed as the adaptation's own.
//
// THE BOUNDARY: the widget announces the value, the Kertesz severity band —
// or, at/above the published 93.8 aphasia cutoff (Kertesz & Poole 1974), the
// cutoff relation in its place — the arithmetic, the citation, and nothing
// else. Surfacing the cutoff is threshold-REPORTING of a published fact (§5
// boundary pair 3), never a diagnosis: no "indicates", no "consider", no
// severity commentary, no therapy direction. The Section 5 forbidden-language
// suite runs over every rendered state, in every adaptation, in
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
/// This is the PURE severity band — it never applies the aphasia cutoff.
/// Kertesz's published aphasia cutoff (AQ 93.8; Kertesz & Poole 1974) is a
/// SEPARATE instrument, handled by [wabAtOrAboveAphasiaCutoff]: at/above it a
/// score is classified no aphasia, and the widget surfaces that cutoff
/// relation in place of the band. An AQ of 96 sits in this "Mild" range yet is
/// non-aphasic by the cutoff — showing "Mild" alone would mislabel a
/// non-aphasic score, which is why the two are kept distinct. The WAB-K
/// (Kannada) own-cutoff question stays a norming caveat, not a recomputation:
/// Cue reports the English-WAB cutoff and names its provenance.
String wabKerteszBand(double aq) {
  if (aq <= 25) return 'Very severe';
  if (aq <= 50) return 'Severe';
  if (aq <= 75) return 'Moderate';
  return 'Mild';
}

/// The published aphasia/no-aphasia cutoff for the WAB AQ: AQ ≥ 93.8 is
/// classified NO APHASIA; AQ < 93.8 is aphasia present, where the severity
/// band ([wabKerteszBand]) applies. The severity band and this cutoff are
/// DIFFERENT instruments — an AQ of 96 sits in the "Mild" severity range yet
/// is non-aphasic by the cutoff, so showing "Mild" alone mislabels a
/// non-aphasic score as mild aphasia.
///
/// Source: Kertesz, A. & Poole, E. (1974). The aphasia quotient: the taxonomic
/// approach to measurement of aphasic disability. Canadian Journal of
/// Neurological Sciences, 1(1), 7–16 — the published 93.8 cutoff (100%
/// specificity / ~60% sensitivity). This is threshold REPORTING of a published
/// cutoff, not a diagnosis Cue makes (intern-scaffold §5 boundary pair 3).
const double kWabAphasiaCutoff = 93.8;

/// True when [aq] is at or above the published [kWabAphasiaCutoff] — classified
/// no aphasia. Read on the exact (unrounded) value, like [wabKerteszBand]; the
/// literature states the relation as AQ ≥ 93.8, so the boundary is inclusive.
bool wabAtOrAboveAphasiaCutoff(double aq) => aq >= kWabAphasiaCutoff;

/// Band-slot label shown at/above the cutoff — the published classification,
/// not a severity grade. Reported, never inferred.
const String kWabNoAphasiaLabel = 'No aphasia';

/// The cutoff relation + its source, said quietly AT the classification (the
/// bandNote slot), exactly as [kWabBandReferenceNote] tags the severity band —
/// so "No aphasia" never reads as Cue's verdict, only the published cutoff's.
const String kWabAphasiaCutoffNote = 'at/above 93.8 cutoff · Kertesz & Poole 1974';

/// A published WAB language adaptation. Data, not hardcoded UI — extend the
/// list when further adaptations are confirmed in the literature.
class WabAdaptation {
  /// Stable lowercase key (graduation will persist this).
  final String code;

  /// Selector display label.
  final String label;

  /// Short instrument name for the result's detail line.
  final String shortLabel;

  /// Published citation for the adaptation.
  final String citation;

  /// True where the adaptation publishes its OWN normative data (so the
  /// caveat says so). False means "not verified here" — never "has none".
  final bool publishesOwnNorms;

  const WabAdaptation({
    required this.code,
    required this.label,
    required this.shortLabel,
    required this.citation,
    this.publishesOwnNorms = false,
  });

  /// "Telugu WAB · Pallavi 2010" — the administered-instrument record line.
  String get resultLine => '$shortLabel · $citation';
}

/// Published WAB adaptations offered by the selector. Citations verified
/// 2026-06-12 (sources in the Phase B+ report):
///   * English — Kertesz, A. (1979; 1982). The Western Aphasia Battery.
///     The original; the AQ formula and severity bands are its norms.
///   * Kannada (WAB-K) — Chengappa & Kumar (2008), Normative & Clinical
///     Data on the Kannada Version of the WAB. Publishes own normative data.
///   * Telugu — Pallavi (2010), WAB in Telugu, unpublished master's
///     dissertation, University of Mysore.
///   * Malayalam — Jenny, E.P. (1992), A Test of Aphasia in Malayalam,
///     unpublished master's dissertation, University of Mysore.
///   * Hindi (WAB-H) — Kacker, Pandit & Dua (1991), "Reliability and validity
///     studies of examination for aphasia test in Hindi", Indian Journal of
///     Disability and Rehabilitation 1991;5:13–19 (verified 2026-06-13).
///     HONEST PROVENANCE: this is the Hindi examination for aphasia used AS
///     the WAB-H reference in Indian validation work — NOT a cleanly-labeled
///     standalone "Hindi WAB adaptation" the way Chengappa & Kumar is
///     explicitly the Kannada WAB. Cited as the established Hindi reference,
///     not overclaimed as a formal WAB translation.
///   * Bengali (B-WAB) — Keshree, Kumar, Basu, Chakrabarty & Kishore
///     (2013), Adaptation of the WAB in Bangla, Psychology of Language and
///     Communication 17(2):189–201. Standardized on 150 normals across five
///     age groups — publishes own normative data.
const List<WabAdaptation> kWabAdaptations = [
  WabAdaptation(
    code: 'english',
    label: 'English (WAB / WAB-R)',
    shortLabel: 'English WAB',
    citation: 'Kertesz 1982',
  ),
  WabAdaptation(
    code: 'kannada',
    label: 'Kannada (WAB-K)',
    shortLabel: 'Kannada WAB-K',
    citation: 'Chengappa & Kumar 2008',
    publishesOwnNorms: true,
  ),
  WabAdaptation(
    code: 'telugu',
    label: 'Telugu',
    shortLabel: 'Telugu WAB',
    citation: 'Pallavi 2010',
  ),
  WabAdaptation(
    code: 'malayalam',
    label: 'Malayalam',
    shortLabel: 'Malayalam WAB',
    citation: 'Jenny 1992',
  ),
  WabAdaptation(
    code: 'hindi',
    label: 'Hindi (WAB-H)',
    shortLabel: 'Hindi WAB-H',
    citation: 'Kacker, Pandit & Dua 1991',
  ),
  WabAdaptation(
    code: 'bengali',
    label: 'Bengali (B-WAB)',
    shortLabel: 'Bengali B-WAB',
    citation: 'Keshree et al. 2013',
    publishesOwnNorms: true,
  ),
];

/// The band's provenance, said quietly AT the band in every adaptation —
/// the integrity point of the multilingual layer.
const String kWabBandReferenceNote = 'Kertesz 1982 reference';

/// Norming caveat for the selected adaptation — a documented instrument
/// fact, kept brief (never reassurance). English gets none: there the
/// displayed bands ARE the administered instrument's own norms. Adaptations
/// with verified own normative data are named; the rest get the generic
/// reference statement.
String? wabAdaptationCaveat(WabAdaptation a, {bool atOrAboveCutoff = false}) {
  if (a.code == 'english') return null;
  // The displayed reference is English-WAB whether it is the severity band
  // (Kertesz 1982) or the aphasia cutoff (Kertesz & Poole 1974); the caveat
  // names whichever is on screen, so it never cites a band that isn't shown.
  final ref = atOrAboveCutoff
      ? 'The 93.8 aphasia cutoff is the Kertesz & Poole 1974 (English WAB) '
          'reference'
      : 'Severity bands are the Kertesz 1982 (English WAB) reference';
  if (a.publishesOwnNorms) {
    return '$ref — ${a.shortLabel} publishes its own normative data; '
        'interpret with that context.';
  }
  return "$ref — interpret against the administered adaptation's norms.";
}

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

  /// Selected adaptation — explicit at all times; defaults to the original
  /// instrument. Changes the detail line and the caveat, never the
  /// arithmetic.
  WabAdaptation _adaptation = kWabAdaptations.first;

  @override
  void dispose() {
    for (final s in _subscores) {
      s.ctrl.dispose();
    }
    super.dispose();
  }

  /// The readout — result state plus the norming caveat that belongs to it —
  /// the current inputs deterministically dictate. State and caveat resolve
  /// together because the caveat's wording tracks whether the cutoff relation
  /// or the severity band is the displayed reference.
  ({LoudResultState state, String? caution}) _readout() {
    // A subscore above its published maximum cannot compute — name it
    // factually and wait. (Negatives are unreachable: the input formatter
    // admits only digits and the decimal point.)
    for (final s in _subscores) {
      final v = s.value;
      if (v != null && v > s.max) {
        return (
          state: LoudResultInsufficient(
              missing:
                  '${s.label} exceeds its /${s.max.toStringAsFixed(0)} maximum'),
          caution: null,
        );
      }
    }

    final values = [for (final s in _subscores) s.value];
    final missing = values.where((v) => v == null).length;
    if (missing > 0) {
      return (
        state: LoudResultInsufficient(
            missing: '$missing more subscore${missing == 1 ? '' : 's'} needed'),
        caution: null,
      );
    }

    final aq = computeWabAq(
      spontaneousSpeech: values[0],
      comprehension: values[1],
      repetition: values[2],
      naming: values[3],
    )!;
    final terms = values.map((v) => _fmtTerm(v!)).join(' + ');
    final atOrAboveCutoff = wabAtOrAboveAphasiaCutoff(aq);
    return (
      state: LoudResultResolved(
        value: aq.toStringAsFixed(1),
        // At/above the published 93.8 cutoff the score is classified no
        // aphasia; showing the "Mild" severity band there would mislabel a
        // non-aphasic score. Below it, the severity band applies as before.
        // The band/classification wears its provenance; the detail line
        // records what was administered. Neither changes the number.
        band: atOrAboveCutoff ? kWabNoAphasiaLabel : wabKerteszBand(aq),
        bandNote:
            atOrAboveCutoff ? kWabAphasiaCutoffNote : kWabBandReferenceNote,
        detail: _adaptation.resultLine,
        math: '($terms) × 2 = ${aq.toStringAsFixed(1)}',
        citation: 'Kertesz 1982',
      ),
      caution:
          wabAdaptationCaveat(_adaptation, atOrAboveCutoff: atOrAboveCutoff),
    );
  }

  /// "14" stays 14; "7.5" stays 7.5 — terms render as entered, never padded.
  String _fmtTerm(double v) =>
      v == v.truncateToDouble() ? v.toStringAsFixed(0) : v.toString();

  @override
  Widget build(BuildContext context) {
    final readout = _readout();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(children: [
          Expanded(child: _adaptationSelector()),
          const SizedBox(width: 12),
          const Expanded(child: SizedBox()),
        ]),
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
          state: readout.state,
          caution: readout.caution,
        ),
      ],
    );
  }

  /// Silent-register setting, not the focus: which published adaptation was
  /// administered. Quiet label + dense outlined dropdown matching the
  /// subscore fields.
  Widget _adaptationSelector() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Adaptation',
            style: GoogleFonts.inter(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: _ink,
                letterSpacing: -0.05)),
        const SizedBox(height: 4),
        DropdownButtonFormField<WabAdaptation>(
          initialValue: _adaptation,
          isExpanded: true,
          isDense: true,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            isDense: true,
            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          ),
          style: GoogleFonts.inter(
              fontSize: 13.5, fontWeight: FontWeight.w400, color: _ink),
          items: [
            for (final a in kWabAdaptations)
              DropdownMenuItem(value: a, child: Text(a.label)),
          ],
          onChanged: (a) {
            if (a != null) setState(() => _adaptation = a);
          },
        ),
      ]),
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
