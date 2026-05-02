// lib/services/cue_calc.dart
//
// Cue Calc — deterministic local clinical math.
//
// Phase 4.0.4 ships the FIRST of 16 calculations specified in CLAUDE.md
// §14.6 (Cue Calc Phase 4.1 spec). Per §13.14 capability boundary, Cue
// Calc is Route 1: deterministic computation with hand-authored prose.
// No LLM in this calc path, ever. No proxy round-trip. No network.
//
// Future calcs (PCC, PVC, PCC-R, whole-word accuracy, speech rate,
// articulation rate, TTR, MLU-w, MLU-m, NDW, TNW, s/z ratio, MPT, DDK
// rates, intelligibility percentage) land here as additional pure
// functions. Each is paired with a hand-authored genealogy card in the
// Cue Calc surface (Phase 4.1) — not generated.

/// Computes %SS (percent syllables stuttered).
///
/// %SS = (stuttered_syllables / total_syllables) * 100, rounded to one
/// decimal place. Returns `0.0` when `totalSyllables` is `0` (no
/// denominator → no rate to report). Negative inputs are clamped to `0`
/// rather than asserting; the live-entry surface guarantees non-negative
/// counts via UI, but a defensive clamp keeps this function safe to
/// call from any future caller.
///
/// First of 16 calculations — see CLAUDE.md §14.6 and §13.14.
double computePercentSyllablesStuttered({
  required int stutteredSyllables,
  required int totalSyllables,
}) {
  if (totalSyllables <= 0) return 0.0;
  final stuttered = stutteredSyllables < 0 ? 0 : stutteredSyllables;
  final raw = (stuttered / totalSyllables) * 100;
  return double.parse(raw.toStringAsFixed(1));
}
