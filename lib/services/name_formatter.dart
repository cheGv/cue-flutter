// lib/services/name_formatter.dart
//
// Shared name-formatting helpers. Phase 3.2 introduced this module so
// every surface that renders a client's name (Today greeting, Today
// session card, Clients attention block, Clients all-clients list, chart
// AppBar) goes through the same normalisation rules.
//
// Two operations are offered:
//
//   NameFormatter.displayName(raw)
//       Used at read-time for full-name display. Normalises mixed-casing
//       data without overwriting an SLP's deliberate input. Honorifics are
//       preserved with their period and capitalisation.
//
//   NameFormatter.firstNameForGreeting(raw)
//       Used when the SLP wants to address a child personally. Strips
//       leading honorifics ("Ch.", "Smt.", "Dr.") and returns the next
//       token in title case. Falls back to the cleaned full name when
//       honorifics consume the whole string.
//
// Honorifics list is the single source of truth — Today's _firstNameOf
// helper consumes the same set so behaviour is consistent across screens.

class NameFormatter {
  NameFormatter._();

  /// Indian + global clinical honorifics seen in the prototype data set.
  /// Add to this list when new honorifics appear; do not duplicate locally
  /// in screen files.
  static const Set<String> honorifics = <String>{
    'ch', 'sri', 'shri', 'smt', 'mr', 'mrs', 'ms', 'dr',
  };

  // ── Display normalisation ───────────────────────────────────────────────
  //
  // Rules:
  //   1. Trim leading/trailing whitespace.
  //   2. If the entire input is uppercase OR entirely lowercase, apply
  //      title case to every whitespace-separated token.
  //   3. If the input already has mixed case (e.g. "Ch. Ranadir"), leave
  //      it alone — the SLP entered it deliberately.
  //   4. Honorifics keep their period + are forced into honorific-cap form
  //      (first letter upper, rest lower) regardless of the all-upper /
  //      all-lower path above.

  static String displayName(String? raw) {
    if (raw == null) return '';
    final t = raw.trim();
    if (t.isEmpty) return '';

    final isAllUpper = t.toUpperCase() == t;
    final isAllLower = t.toLowerCase() == t;
    final tokens     = t.split(RegExp(r'\s+'));

    if (isAllUpper || isAllLower) {
      return tokens.map(_titleCaseToken).join(' ');
    }

    // Mixed case — preserve as-is, but normalise honorific tokens so
    // "ch." (lowercase) becomes "Ch." even when the rest of the name is
    // mixed-case data the SLP typed deliberately.
    return tokens.map((tok) {
      final norm = tok.toLowerCase().replaceAll('.', '');
      if (honorifics.contains(norm)) return _titleCaseToken(tok);
      return tok;
    }).join(' ');
  }

  // ── First name for greeting ─────────────────────────────────────────────

  /// Returns the first usable name token in title case, after stripping
  /// any leading honorifics. Returns null only when [raw] is empty.
  static String? firstNameForGreeting(String? raw) {
    final t = raw?.trim() ?? '';
    if (t.isEmpty) return null;

    final tokens = t.split(RegExp(r'\s+'));
    var i = 0;
    while (i < tokens.length) {
      final norm = tokens[i].toLowerCase().replaceAll('.', '');
      if (honorifics.contains(norm)) {
        i++;
      } else {
        break;
      }
    }
    if (i >= tokens.length) {
      // All tokens were honorifics — show the cleaned full name so the
      // SLP at least sees something recognisable.
      final cleaned = t.replaceAll(RegExp(r'\.$'), '').trim();
      return cleaned.isEmpty ? null : _titleCaseToken(cleaned);
    }
    return _titleCaseToken(tokens[i]);
  }

  // ── Internals ───────────────────────────────────────────────────────────

  /// Single-token title case — first letter upper, rest lower. Preserves
  /// the trailing period on honorifics ("ch." → "Ch.").
  static String _titleCaseToken(String tok) {
    if (tok.isEmpty) return tok;
    final lower = tok.toLowerCase();
    return '${lower[0].toUpperCase()}${lower.substring(1)}';
  }
}
