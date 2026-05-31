import '../models/client_brief_signals.dart';

// Client briefing — Layer 3: PHRASING.
//
// Renders a [ClientBriefSignals] (Layer 2) as the brief sentence in Cue's
// locked voice. Deterministic TEMPLATE — NOT a model call: the facts are
// structured and the templates fixed, so there is nothing to hallucinate.
//
// Voice (locked): warm Indian-English colleague handoff, client-name-first.
// Goals are ALWAYS named by type ("short-term goal") + code on the actionable
// goal; never a bare code like "1.A". Many pending goals are reported as a
// COUNT, never a list of codes (a brief, not a dashboard). One headline + at
// most one lighter secondary thread.
//
// LAW: phrases ONLY the facts in [signals]. No progress evaluation ("doing
// well/poorly"), no forecast, no advice/instruction — report, don't conclude.
// Uses the client's NAME possessive, never he/she/his/her (Cue holds no gender
// field; name-possessive reads naturally and never mis-genders).

/// The single brief sentence for the status band. Pure: same signals → same
/// string, always.
String phraseClientBrief(ClientBriefSignals s, {required String clientName}) {
  final name = clientName.trim().isEmpty ? 'this client' : clientName.trim();

  switch (s.lead) {
    case BriefLead.newActivity:
      final n = s.sessionsSinceLastVisit;
      final head =
          '$name — ${_num(n)} ${_plural(n, 'session')} logged since you '
          'last opened the file.';
      final secondary = _pendingSecondary(s);
      return secondary == null ? head : '$head $secondary';

    case BriefLead.pending:
      return _pendingHeadline(s, name);

    case BriefLead.longGap:
      // Days is the fact; kept exact (no rounding to weeks) so we report only
      // what we have.
      final head = "It's been ${s.daysSinceLastSeen} days since you saw $name.";
      final secondary = _pendingSecondary(s);
      return secondary == null ? head : '$head $secondary';

    case BriefLead.firstVisit:
      final n = s.activeGoalCount;
      if (n <= 0) {
        return "Opening $name's file for the first time.";
      }
      return "Opening $name's file for the first time — "
          "${_num(n)} ${_plural(n, 'short-term goal')} on the plan.";

    case BriefLead.nothingNew:
      return '$name is steady — nothing new since your last session.';
  }
}

// Pending as the HEADLINE (pending lead): name the code(s) with type when 1–2;
// report a bare COUNT when many (never list six codes).
String _pendingHeadline(ClientBriefSignals s, String name) {
  final codes = s.pendingGoalCodes;
  final n = codes.length;
  if (n == 0) {
    // Defensive: the pending lead implies n > 0. Fall back to the steady line.
    return '$name is steady — nothing new since your last session.';
  }
  if (n == 1) {
    return '$name has one short-term goal still to be taken up — '
        'short-term goal ${codes[0]}.';
  }
  if (n == 2) {
    return '$name has two short-term goals still to be taken up — '
        'short-term goals ${codes[0]} and ${codes[1]}.';
  }
  return '$name has ${_num(n)} short-term goals still to be taken up.';
}

// Pending as a lighter SECONDARY thread (under newActivity / longGap): a count
// only, never codes — the "other short-term goals" register.
String? _pendingSecondary(ClientBriefSignals s) {
  final n = s.pendingGoalCodes.length;
  if (n == 0) return null;
  final verb = n == 1 ? 'is' : 'are';
  return '${_cap(_num(n))} ${_plural(n, 'short-term goal')} $verb still to be '
      'taken up.';
}

// ── small deterministic helpers ──────────────────────────────────────────────

const _words = [
  'zero', 'one', 'two', 'three', 'four', 'five', 'six',
  'seven', 'eight', 'nine', 'ten', 'eleven', 'twelve',
];

/// Spell small counts as words (warm register); digits beyond twelve. Used for
/// session + goal counts. Day gaps stay as digits at the call site.
String _num(int n) => (n >= 0 && n < _words.length) ? _words[n] : n.toString();

String _cap(String s) =>
    s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';

/// "short-term goal" → "short-term goals"; "session" → "sessions".
String _plural(int n, String singular) => n == 1 ? singular : '${singular}s';
