// lib/constants/cas_levels.dart
//
// The canonical CAS complexity ladder — the CAS block's
// `progression_structure` (docs/cue-block-interface-v0.md §3). Single
// app-side source of truth for the rung list, shared by:
//   • CasAssessmentSurface — seeds cas_length_gradient rows (the one-time
//     assessment snapshot);
//   • CasSessionDials — per-session capture rows written to
//     cas_session_progress (the resumption loop's write half).
//
// NOT a DB enum on purpose: level_label / level_order are free per-row in
// both tables, so the structure stays editable per practice without a
// migration. The brief engine (assemble_cas_progress_brief) never consumes
// this list declaratively — it infers order from level_order arriving in
// the data.
//
// Lifted verbatim from cas_assessment_surface.dart's library-private
// _kCasLevels when the capture surface became the second consumer.

typedef CasComplexityLevel = ({
  int order,
  String label,
  String tokens,
  String display,
});

const List<CasComplexityLevel> kCasComplexityLevels = [
  (order: 1, label: 'CV', tokens: 'ba, mu', display: 'CV — ba, mu'),
  (order: 2, label: 'CVC', tokens: 'cup, dog', display: 'CVC — cup, dog'),
  (order: 3, label: 'bisyllabic', tokens: 'baby, water',
      display: 'Bisyllabic — baby, water'),
  (order: 4, label: 'trisyllabic', tokens: 'banana',
      display: 'Trisyllabic — banana'),
  (order: 5, label: 'polysyllabic_phrase', tokens: 'butterfly, "I want more"',
      display: 'Polysyllabic / phrase — butterfly, "I want more"'),
];
