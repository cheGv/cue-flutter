// lib/constants/cue_lexicon.dart
//
// Phase C — Cue Mirror, Component Two (Format Drafter).
// Cue's default neutral replacements for the deficit-style vocabulary an SLP's
// own report format may use. The clinician decides per-template whether Cue
// swaps each term for the neutral phrasing or keeps her original wording (the
// once-per-template lexicon-defaults step). The map keys are the SLP's own
// terms shown as DATA for her swap decision — they are never Cue's own copy.

const Map<String, String> kCueNeutralReplacements = {
  'delay': 'emerging speech and language profile',
  'poor': 'emerging',
  'decline': 'shift in profile',
  'deficit': 'area for support',
  'failure': 'opportunity for further work',
  'regression': 'shift in skills profile',
  'not achieved': 'in progress',
  'inadequate': 'developing',
};

/// Cue's neutral replacement for [term], case-insensitive. Falls back to a
/// generic neutral description when the term isn't in the curated map.
String cueNeutralReplacement(String term) =>
    kCueNeutralReplacements[term.toLowerCase()] ?? 'a neutral description';
