// lib/widgets/recall_assistant/recall_query.dart
//
// Model for one stored (question, answer) pair in the recall assistant's
// session-scoped recent list. Pure data; depends only on the resolver
// module (RecallAnswer) — no Supabase, no Flutter.

import '../../services/recall_resolver.dart';

class RecallQuery {
  /// The SLP's original question text (never the carried-augmented form).
  final String question;

  /// The resolver's answer for this question.
  final RecallAnswer answer;

  /// When the query was answered.
  final DateTime ts;

  /// When a B-principle disambiguation picked a client, the chosen name
  /// (also used as the "Answering about X" provenance for that entry).
  final String? carriedClientName;

  /// Slow-path escalation state. [escalatedToStudy] true → the SLP tapped
  /// "Open in Cue Study" (render the "→ continued in Cue Study"
  /// annotation). [escalationSkipped] true → the SLP tapped "Skip"
  /// (render the prompt text without action buttons).
  final bool escalatedToStudy;
  final bool escalationSkipped;

  /// True when a client was focused AT SUBMIT TIME. Drives the softer
  /// "did you mean" recovery (vs. Cue Study escalation) for slow-path
  /// classification misses — see RecallAssistantQueryBlock (Fix 3).
  final bool wasFocusedAtSubmit;

  const RecallQuery({
    required this.question,
    required this.answer,
    required this.ts,
    this.carriedClientName,
    this.escalatedToStudy = false,
    this.escalationSkipped = false,
    this.wasFocusedAtSubmit = false,
  });

  RecallQuery copyWith({
    RecallAnswer? answer,
    String? carriedClientName,
    bool? escalatedToStudy,
    bool? escalationSkipped,
    bool? wasFocusedAtSubmit,
  }) {
    return RecallQuery(
      question: question,
      answer: answer ?? this.answer,
      ts: ts,
      carriedClientName: carriedClientName ?? this.carriedClientName,
      escalatedToStudy: escalatedToStudy ?? this.escalatedToStudy,
      escalationSkipped: escalationSkipped ?? this.escalationSkipped,
      wasFocusedAtSubmit: wasFocusedAtSubmit ?? this.wasFocusedAtSubmit,
    );
  }
}
