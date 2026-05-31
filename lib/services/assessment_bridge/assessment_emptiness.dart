// lib/services/assessment_bridge/assessment_emptiness.dart
//
// THE EMPTINESS RULE — the heart of Cue's anti-fabrication guarantee for the
// assessment data bridge.
//
// A captured value may become a clinical "finding" (and thus content in a
// report) ONLY IF it is genuinely present. Whether something is "present" is
// judged by the VALUE ITSELF — never by whether a key/column exists (every
// column exists even when the clinician never touched it).
//
// PRESENT  -> emit a finding. The value IS the clinician's finding, including
//             "absent", "no", "none", 0, and false. These are real clinical
//             judgements, NOT emptiness.
// ABSENT   -> emit nothing. The section/field stays blank in the report.
//
//   null            -> never entered            -> ABSENT
//   "" / whitespace -> explicit blank (cleared)  -> ABSENT
//   empty list/map  -> nothing captured          -> ABSENT
//   any other value -> a real finding            -> PRESENT
//
// SAFETY INVARIANTS — do NOT "optimise" these away in any future edit:
//   1. NEVER infer emptiness from MEANING. "absent" / "no" / "none" / 0 / false
//      are findings, not blanks. Only STRUCTURAL emptiness (null, empty string,
//      empty collection) suppresses a value. Dropping "absent" would silently
//      delete a real clinical judgement.
//   2. NEVER infer presence from a key existing. Callers must pass the VALUE;
//      a present-but-empty column ("" or null) must produce no finding.
//   3. A DB default that the clinician never chose is NOT a finding. This
//      function cannot see "was this touched?" — so any column with a
//      non-null DB default (e.g. a boolean defaulting to false) must be handled
//      by the caller, which must exclude it unless it can prove the value was
//      actually chosen. (See cas_assessment_reader.dart, sequence_order_errors.)
//
// This rule is shared by every assessment reader (CAS, voice, ped, ALD) so the
// guarantee lives in exactly one place.

bool assessmentValueIsPresent(dynamic value) {
  if (value == null) return false; // never entered
  if (value is String) return value.trim().isNotEmpty; // "" / whitespace = blank
  if (value is Map) return value.isNotEmpty; // {} = empty
  if (value is Iterable) return value.isNotEmpty; // [] = empty
  return true; // num (incl. 0), bool (incl. false), DateTime, etc. = present
}
