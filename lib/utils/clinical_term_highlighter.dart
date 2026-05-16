// lib/utils/clinical_term_highlighter.dart
//
// Phase 4.1.1 — Cue · Evidence body auto-highlighter.
//
// Takes a raw evidence prose string and returns a List<TextSpan> in which
// any term from the category lists below is wrapped in a citation-style
// span (amber wash + bottom-border, inherits italic + color from base).
//
// CATEGORIES (deliberately conservative — only highlight clinically
// load-bearing tokens, never general English). Extend the const maps when
// new evidence vocabulary lands in chart prose.
//
//   PROTOCOLS      — named protocol acronyms (PROMPT, OPT, CTAR…)
//   EVIDENCE_LEVEL — research-level designators (Level I, RCT…)
//   POPULATION     — clinical population markers (post-stroke, pediatric…)
//   DOSAGE         — number + unit pairs ("3 sets of 10", "20 min")
//   INSTRUMENTAL   — instrumental-assessment names (VFSS, FEES…)
//
// USAGE:
//   final cue = CueChartPalette.of(context);
//   final spans = highlightClinicalTerms(
//     prose,
//     baseStyle,
//     bg: cue.clinicalHighlightBg,
//     borderColor: cue.clinicalHighlightBorder,
//   );
//   return RichText(text: TextSpan(style: baseStyle, children: spans));
//
// Match semantics:
//   • Protocol/instrumental/level matches are whole-word, case-sensitive
//     (preserves clinical capitalization conventions).
//   • Population markers match case-insensitive whole-word.
//   • Dosage pattern is a single regex covering quantity + unit.
//   • Overlapping matches are resolved leftmost-longest.

import 'package:flutter/material.dart';

// ── Term lists ───────────────────────────────────────────────────────────────

const List<String> kClinicalProtocols = <String>[
  'CTAR', 'Shaker', 'SOVT', 'PROMPT', 'OPT', 'COSMI', 'DTTC', 'ReST',
  'LSVT', 'Hanen', 'NDBI', 'ImPACT', 'EMT', 'Heimlich',
];

const List<String> kClinicalEvidenceLevels = <String>[
  'Level I', 'Level II', 'Level III', 'Level IV', 'Level V',
  'RCT', 'meta-analysis', 'systematic review',
];

const List<String> kClinicalPopulations = <String>[
  'post-stroke', 'pediatric', 'adult', 'geriatric',
  'non-speaking', 'minimally-verbal',
];

const List<String> kClinicalInstrumental = <String>[
  'VFSS', 'FEES', 'MBSS', 'FEEST', 'instrumental',
];

// Dosage pattern: number (optionally x/×) + space + unit word.
// Matches "3 sets", "3 sets of 10", "20 min", "10 minutes", "week 2 of 4",
// "20 minutes", "2 weeks", "12 sessions", "5 trials". The pattern stops at
// "of N" so "3 sets of 10" is captured as one span (not two).
final RegExp _kDosageRegex = RegExp(
  r'\b(?:week\s+\d+(?:\s+of\s+\d+)?'
  r'|\d+\s*(?:sets?|trials?|minutes?|min|weeks?|sessions?)'
  r'(?:\s+of\s+\d+)?)\b',
  caseSensitive: false,
);

// ── Public entry point ──────────────────────────────────────────────────────

class _Match {
  final int start;
  final int end;
  const _Match(this.start, this.end);
}

/// Returns a list of [TextSpan]s in which any clinical term inside [text]
/// is wrapped in a citation-style span. [baseStyle] is the inherited
/// italic / weight / size used for the surrounding prose; the highlight
/// wraps in a WidgetSpan that inherits this style.
List<InlineSpan> highlightClinicalTerms(
  String text,
  TextStyle baseStyle, {
  required Color bg,
  required Color borderColor,
}) {
  if (text.isEmpty) return const <InlineSpan>[];
  final matches = _collectMatches(text);
  if (matches.isEmpty) {
    return <InlineSpan>[TextSpan(text: text, style: baseStyle)];
  }

  final out = <InlineSpan>[];
  int cursor = 0;
  for (final m in matches) {
    if (m.start > cursor) {
      out.add(TextSpan(
        text: text.substring(cursor, m.start),
        style: baseStyle,
      ));
    }
    out.add(WidgetSpan(
      alignment: PlaceholderAlignment.baseline,
      baseline: TextBaseline.alphabetic,
      child: _ClinicalChip(
        text: text.substring(m.start, m.end),
        baseStyle: baseStyle,
        bg: bg,
        borderColor: borderColor,
      ),
    ));
    cursor = m.end;
  }
  if (cursor < text.length) {
    out.add(TextSpan(text: text.substring(cursor), style: baseStyle));
  }
  return out;
}

// ── Match collection ────────────────────────────────────────────────────────

List<_Match> _collectMatches(String text) {
  final matches = <_Match>[];

  // Whole-word, case-sensitive (protocols, levels, instrumental).
  for (final list in <List<String>>[
    kClinicalProtocols,
    kClinicalEvidenceLevels,
    kClinicalInstrumental,
  ]) {
    for (final term in list) {
      matches.addAll(_findWholeWord(text, term, caseSensitive: true));
    }
  }

  // Whole-word, case-insensitive (population markers).
  for (final term in kClinicalPopulations) {
    matches.addAll(_findWholeWord(text, term, caseSensitive: false));
  }

  // Dosage regex.
  for (final m in _kDosageRegex.allMatches(text)) {
    matches.add(_Match(m.start, m.end));
  }

  return _resolveOverlaps(matches);
}

Iterable<_Match> _findWholeWord(
  String text,
  String term, {
  required bool caseSensitive,
}) sync* {
  final escaped = RegExp.escape(term);
  // \b doesn't work cleanly around hyphenated terms ("post-stroke") because
  // '-' is a word boundary too. For hyphenated terms we anchor on whitespace
  // / start / end / punctuation instead.
  final hasHyphen = term.contains('-') || term.contains(' ');
  final pattern = hasHyphen
      ? r'(?:^|(?<=[\s,.;:()\[\]"]))' + escaped + r'(?=[\s,.;:()\[\]"]|$)'
      : r'\b' + escaped + r'\b';
  final re = RegExp(pattern, caseSensitive: caseSensitive);
  for (final m in re.allMatches(text)) {
    yield _Match(m.start, m.end);
  }
}

/// Leftmost-longest resolution: sort by (start asc, length desc), then walk
/// keeping non-overlapping matches.
List<_Match> _resolveOverlaps(List<_Match> raw) {
  if (raw.isEmpty) return raw;
  raw.sort((a, b) {
    if (a.start != b.start) return a.start.compareTo(b.start);
    return (b.end - b.start).compareTo(a.end - a.start);
  });
  final out = <_Match>[];
  int lastEnd = -1;
  for (final m in raw) {
    if (m.start < lastEnd) continue; // overlaps previous; skip
    out.add(m);
    lastEnd = m.end;
  }
  return out;
}

// ── Chip widget ─────────────────────────────────────────────────────────────

class _ClinicalChip extends StatelessWidget {
  final String text;
  final TextStyle baseStyle;
  final Color bg;
  final Color borderColor;

  const _ClinicalChip({
    required this.text,
    required this.baseStyle,
    required this.bg,
    required this.borderColor,
  });

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: bg,
          border: Border(bottom: BorderSide(color: borderColor, width: 1)),
        ),
        child: Text(text, style: baseStyle),
      ),
    );
  }
}
