// lib/widgets/recall_assistant/recall_assistant_query_block.dart
//
// Renders ONE (question, answer) pair. Switches rendering on the answer's
// kind + verbatim + slow-path reason into the five spec'd registers:
//   (a) fast verbatim     — client pill + italic body + "from the session note"
//   (b) fast templated     — client pill + plain body
//   (c) unresolvable       — italic muted body, no pill
//   (d) slow-path escalate — inset card, "Open in Cue Study" / "Skip"
//   (e) ambiguous client   — "which one?" + tappable client chips
//
// Pure presentation. Depends on the resolver module (RecallAnswer kinds)
// + the RecallQuery model — no Supabase. Card colours are hardcoded to
// the dark elevated surface register (the card is always dark).

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../services/recall_resolver.dart';
import 'recall_query.dart';

class RecallAssistantQueryBlock extends StatelessWidget {
  final RecallQuery query;
  final ValueChanged<String> onPickClient; // disambiguation chip tapped
  final VoidCallback onOpenInStudy;
  final VoidCallback onSkipEscalation;

  /// Current focused client name — drives the "did you mean" recovery copy.
  final String? focusedClientName;

  /// Recovery suggestion-chip tapped — submits the given intent phrasing.
  final ValueChanged<String> onSuggestion;

  const RecallAssistantQueryBlock({
    super.key,
    required this.query,
    required this.onPickClient,
    required this.onOpenInStudy,
    required this.onSkipEscalation,
    required this.onSuggestion,
    this.focusedClientName,
  });

  // ── Register colours (dark card) ──
  static const Color _bodyStrong = Color(0xEBFFFFFF); // white @ 0.92
  static const Color _muted = Color(0x8CFFFFFF); // white @ 0.55
  static const Color _label = Color(0x66FFFFFF); // white @ 0.40
  static const Color _pillBg = Color(0xFFF5C778); // amber
  static const Color _pillText = Color(0xFF5C3D00); // amber-dark
  static const Color _insetBg = Color(0x1F78716C); // rgba(120,113,108,.12)
  static const Color _insetBorder = Color(0x33FFFFFF);
  static const Color _primaryBtnBg = Color(0xFF534AB7);
  static const Color _primaryBtnText = Color(0xFFEEEDFE);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Question label — always, above the answer.
        Text(
          query.question,
          style: GoogleFonts.dmSans(fontSize: 12, color: _label, height: 1.3),
        ),
        const SizedBox(height: 6),
        _answerBlock(),
      ],
    );
  }

  Widget _answerBlock() {
    final a = query.answer;
    switch (a.kind) {
      case RecallAnswerKind.fast:
        return a.verbatim ? _fastVerbatim(a) : _fastTemplated(a);
      case RecallAnswerKind.unresolvable:
        return _unresolvable(a);
      case RecallAnswerKind.slowPath:
        final note = a.note ?? '';
        if (note.startsWith('ambiguous client')) return _ambiguous(note);
        return _escalationOrRecovery();
    }
  }

  // (a) FAST VERBATIM
  Widget _fastVerbatim(RecallAnswer a) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (a.clientName != null) _clientPill(a.clientName!),
        if (a.clientName != null) const SizedBox(height: 6),
        Text(
          a.text ?? '',
          style: GoogleFonts.dmSans(
            fontSize: 15,
            fontStyle: FontStyle.italic,
            color: _bodyStrong,
            height: 1.6,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'from the session note',
          style: GoogleFonts.dmSans(fontSize: 12, color: _label),
        ),
      ],
    );
  }

  // (b) FAST TEMPLATED
  Widget _fastTemplated(RecallAnswer a) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (a.clientName != null) _clientPill(a.clientName!),
        if (a.clientName != null) const SizedBox(height: 6),
        Text(
          a.text ?? '',
          style: GoogleFonts.dmSans(
            fontSize: 15,
            color: _bodyStrong,
            height: 1.6,
          ),
        ),
      ],
    );
  }

  // (c) UNRESOLVABLE
  Widget _unresolvable(RecallAnswer a) {
    return Text(
      a.text ?? "Cue doesn't capture this yet.",
      style: GoogleFonts.dmSans(
        fontSize: 14,
        fontStyle: FontStyle.italic,
        color: _muted,
        height: 1.5,
      ),
    );
  }

  // (d) SLOW-PATH — escalation OR softer recovery (Fix 3).
  //
  // A client focused at submit time makes a slow-path classification miss
  // far more likely a phrasing miss than a genuinely open-ended question →
  // show a "did you mean" recovery with suggestion chips. With no focus,
  // slow-path truly means "needs reasoning" → the Cue Study escalation card.
  Widget _escalationOrRecovery() {
    if (query.escalatedToStudy) return _continuedAnnotation();
    final fc = focusedClientName?.trim() ?? '';
    if (query.wasFocusedAtSubmit && fc.isNotEmpty) return _recovery(fc);
    return _escalationCard();
  }

  Widget _continuedAnnotation() {
    return Text(
      '→ continued in Cue Study',
      style: GoogleFonts.dmSans(
        fontSize: 13,
        color: _muted,
        fontStyle: FontStyle.italic,
      ),
    );
  }

  // Cue Study escalation — used when NO client was focused (slow-path then
  // truly means "this needs reasoning").
  Widget _escalationCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _insetBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _insetBorder, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'This deserves more thought — open in Cue Study?',
            style: GoogleFonts.dmSans(
              fontSize: 14,
              color: _bodyStrong,
              height: 1.5,
            ),
          ),
          if (!query.escalationSkipped) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                _primaryButton('Open in Cue Study', onOpenInStudy),
                const SizedBox(width: 10),
                _secondaryButton('Skip', onSkipEscalation),
              ],
            ),
          ],
        ],
      ),
    );
  }

  // Softer "did you mean" recovery — compact, not card-styled. Used when a
  // client was focused at submit time (likely a phrasing miss).
  static const List<({String label, String phrase})> _recoverySuggestions = [
    (label: 'Last goal', phrase: 'last goal'),
    (label: 'Last accuracy', phrase: 'last accuracy'),
    (label: 'Home programme', phrase: 'home programme'),
    (label: 'Parent update', phrase: 'parent update'),
  ];

  Widget _recovery(String clientName) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "I didn't quite catch that. Try one of these about $clientName:",
          style: GoogleFonts.dmSans(
            fontSize: 13,
            color: _bodyStrong,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final s in _recoverySuggestions)
              _suggestionChip(s.label, s.phrase),
          ],
        ),
        const SizedBox(height: 8),
        InkWell(
          onTap: onOpenInStudy,
          borderRadius: BorderRadius.circular(6),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Text(
              'Open in Cue Study instead?',
              style: GoogleFonts.dmSans(
                fontSize: 12,
                color: _muted,
                decoration: TextDecoration.underline,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _suggestionChip(String label, String phrase) {
    return InkWell(
      onTap: () => onSuggestion(phrase),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: const Color(0x14FFFFFF),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: _insetBorder, width: 0.5),
        ),
        child: Text(
          label,
          style: GoogleFonts.dmSans(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: _bodyStrong,
          ),
        ),
      ),
    );
  }

  // (e) AMBIGUOUS CLIENT
  Widget _ambiguous(String note) {
    // note shape: "ambiguous client: Name A, Name B"
    final raw = note.replaceFirst('ambiguous client:', '').trim();
    final names = raw
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    final typed = query.question;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Two clients match — which one?',
          style: GoogleFonts.dmSans(
            fontSize: 14,
            color: _bodyStrong,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final n in names) _clientChoiceChip(n),
          ],
        ),
        // Keep the typed text discoverable for context.
        if (typed.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            'for "$typed"',
            style: GoogleFonts.dmSans(fontSize: 11, color: _label),
          ),
        ],
      ],
    );
  }

  // ── Shared bits ──

  Widget _clientPill(String name) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: _pillBg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        name,
        style: GoogleFonts.dmSans(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: _pillText,
        ),
      ),
    );
  }

  Widget _clientChoiceChip(String name) {
    return InkWell(
      onTap: () => onPickClient(name),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0x14FFFFFF),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: _insetBorder, width: 0.5),
        ),
        child: Text(
          name,
          style: GoogleFonts.dmSans(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: _bodyStrong,
          ),
        ),
      ),
    );
  }

  Widget _primaryButton(String label, VoidCallback onTap) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: _primaryBtnBg,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            label,
            style: GoogleFonts.dmSans(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: _primaryBtnText,
            ),
          ),
        ),
      ),
    );
  }

  Widget _secondaryButton(String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: _insetBorder, width: 0.5),
        ),
        child: Text(
          label,
          style: GoogleFonts.dmSans(fontSize: 13, color: _muted),
        ),
      ),
    );
  }
}
