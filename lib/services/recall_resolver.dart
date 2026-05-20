// lib/services/recall_resolver.dart
//
// Cue Recall Assistant — Flutter-side resolver.
//
// Inputs:  a natural-language question + the in-memory client roster.
// Output:  a [RecallAnswer] that is one of:
//            • fast        — the answer is here, render now
//            • unresolvable — intent registered, no data captured yet
//            • slowPath    — caller routes to the recall-respond edge
//                            function and shows an honest loading state
//
// Hot-path guarantees (validated against the backend build, 2026-05-19):
//   1. NO model call in this file.
//   2. NO direct Supabase import — the resolver talks to the database
//      ONLY through [RecallCardSource]. Grepping this file for
//      `package:supabase_flutter` MUST return zero hits. That's the
//      seam the local-store implementation will slot into later (B).
//   3. NO silent client picks. Ambiguous matches route to the slow path.

import 'recall_card_source.dart';
import 'recall_intent.dart';

// ─────────────────────────────────────────────────────────────────
// Answer types — discriminated by [kind].
// ─────────────────────────────────────────────────────────────────

enum RecallAnswerKind {
  /// The resolver has an answer. Render it (verbatim or templated per
  /// [RecallAnswer.verbatim]) and stop.
  fast,

  /// The intent is in the registry but isn't backed by stored data
  /// today (e.g. AAC_LAYOUT). [text] is an honest "Cue doesn't capture
  /// this yet" — render verbatim, do not route to the model.
  unresolvable,

  /// The resolver couldn't classify confidently (intent unknown,
  /// client ambiguous, card missing). Caller routes to recall-respond
  /// with an honest loading state. [note] carries the reason for
  /// telemetry / debug; do not render it to the SLP.
  slowPath,
}

class RecallAnswer {
  final RecallAnswerKind kind;
  final RecallIntent intent;

  /// Resolved client identifier and display name. Null when the slow
  /// path was triggered by ambiguous-client or unknown-client paths.
  final String? clientId;
  final String? clientName;

  /// The rendered answer text. Populated for fast and unresolvable;
  /// null for slowPath.
  final String? text;

  /// True when [text] is a free-text field carried verbatim from the
  /// recall card (e.g. parent_update, target_behaviour, soap_note).
  /// False when [text] is a structured template ("8 of 10, 80%").
  /// UI surfaces can choose to render verbatim text with provenance
  /// styling ("from the session note") and templated text without.
  final bool verbatim;

  /// Slow-path reason — telemetry only, not user-visible.
  final String? note;

  const RecallAnswer._({
    required this.kind,
    required this.intent,
    this.clientId,
    this.clientName,
    this.text,
    this.verbatim = false,
    this.note,
  });

  factory RecallAnswer.fast({
    required RecallIntent intent,
    required String clientId,
    required String clientName,
    required String text,
    required bool verbatim,
  }) {
    return RecallAnswer._(
      kind: RecallAnswerKind.fast,
      intent: intent,
      clientId: clientId,
      clientName: clientName,
      text: text,
      verbatim: verbatim,
    );
  }

  factory RecallAnswer.unresolvable({
    required RecallIntent intent,
    required String clientId,
    required String clientName,
    required String text,
  }) {
    return RecallAnswer._(
      kind: RecallAnswerKind.unresolvable,
      intent: intent,
      clientId: clientId,
      clientName: clientName,
      text: text,
    );
  }

  factory RecallAnswer.slowPath({
    required RecallIntent intent,
    required String note,
    String? clientId,
    String? clientName,
  }) {
    return RecallAnswer._(
      kind: RecallAnswerKind.slowPath,
      intent: intent,
      clientId: clientId,
      clientName: clientName,
      note: note,
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// Client matcher — bounded vocabulary, deterministic.
// ─────────────────────────────────────────────────────────────────

class _ClientMatch {
  final String id;
  final String name;
  final int score;
  const _ClientMatch({required this.id, required this.name, required this.score});
}

/// Find client matches in [roster] for the given [question]. Each entry
/// in [roster] is the same `Map<String, dynamic>` shape the rest of the
/// app uses (id, name, …). Returns the top-scoring matches; multiple
/// equally-top matches mean "ambiguous" — caller routes to slow path.
///
/// Scoring:
///   100 — full name appears as a substring (case-insensitive)
///    80 — first name appears as a whole word (\\b match)
///   skip — no match
List<_ClientMatch> _matchClients(
  String question,
  List<Map<String, dynamic>> roster,
) {
  final q = question.toLowerCase();
  final matches = <_ClientMatch>[];
  for (final c in roster) {
    final nameRaw = (c['name'] as String?)?.trim();
    if (nameRaw == null || nameRaw.isEmpty) continue;
    final idRaw = c['id']?.toString();
    if (idRaw == null || idRaw.isEmpty) continue;

    final nameLower = nameRaw.toLowerCase();
    if (q.contains(nameLower)) {
      matches.add(_ClientMatch(id: idRaw, name: nameRaw, score: 100));
      continue;
    }

    final firstName = nameLower.split(RegExp(r'\s+')).first;
    if (firstName.length < 2) continue;
    final wordPattern =
        RegExp(r'\b' + RegExp.escape(firstName) + r'\b', caseSensitive: false);
    if (wordPattern.hasMatch(q)) {
      matches.add(_ClientMatch(id: idRaw, name: nameRaw, score: 80));
    }
  }
  matches.sort((a, b) => b.score.compareTo(a.score));
  return matches;
}

// ─────────────────────────────────────────────────────────────────
// The resolver.
// ─────────────────────────────────────────────────────────────────

class RecallResolver {
  final RecallCardSource _source;

  /// The resolver depends ONLY on [RecallCardSource]. A future
  /// LocalStoreCardSource is swapped in by changing the binding here;
  /// no other code in this file changes. This is the load-bearing seam.
  RecallResolver({required RecallCardSource source}) : _source = source;

  /// Resolve [question] against the in-memory [clientRoster]. Returns
  /// a fast answer when intent+client are confidently resolved AND the
  /// card carries the data; an unresolvable answer when the intent is
  /// registered-but-unsupported; a slow-path signal otherwise.
  ///
  /// [clientRoster]: each entry must have at minimum `id` and `name`.
  /// Shape matches what _TodayScreenState._allClients / ClientProfileScreen
  /// already pass around — no new type required.
  Future<RecallAnswer> resolve({
    required String question,
    required List<Map<String, dynamic>> clientRoster,
  }) async {
    // Step 1: classify intent (pure, on-device).
    final intent = classifyRecallIntent(question);

    // Step 2: match client (pure, on-device).
    final matches = _matchClients(question, clientRoster);

    // If zero or ambiguous client matches, slow path. B-principle:
    // never silently pick a client when two clients have the same
    // top score.
    if (matches.isEmpty) {
      return RecallAnswer.slowPath(
        intent: intent,
        note: 'no client matched',
      );
    }
    if (matches.length > 1 && matches[0].score == matches[1].score) {
      return RecallAnswer.slowPath(
        intent: intent,
        note: 'ambiguous client: '
            '${matches.where((m) => m.score == matches[0].score).map((m) => m.name).join(", ")}',
      );
    }
    final client = matches.first;

    // If intent is OTHER, slow path with the resolved client (the model
    // tier gets the client context for free).
    if (intent == RecallIntent.other) {
      return RecallAnswer.slowPath(
        intent: intent,
        clientId: client.id,
        clientName: client.name,
        note: 'intent not in registry',
      );
    }

    // Step 3: registered-but-unresolvable intents return an honest
    // answer without hitting the data source.
    if (!isRecallIntentResolvable(intent)) {
      return RecallAnswer.unresolvable(
        intent: intent,
        clientId: client.id,
        clientName: client.name,
        text: _unresolvableMessage(intent),
      );
    }

    // Step 4: fetch the card via the seam. NO direct DB call here.
    final card = await _source.getCard(client.id);
    if (card == null) {
      return RecallAnswer.slowPath(
        intent: intent,
        clientId: client.id,
        clientName: client.name,
        note: 'card unavailable',
      );
    }

    // Step 5: assemble the answer. Free-text → verbatim; structured →
    // template; missing data → honest "not recorded yet" template.
    return _assemble(intent, client, card);
  }

  // ── Answer assembly — pure, no I/O. ─────────────────────────────

  RecallAnswer _assemble(
    RecallIntent intent,
    _ClientMatch client,
    RecallCard card,
  ) {
    switch (intent) {
      case RecallIntent.lastGoal:
        return _assembleLastGoal(client, card);
      case RecallIntent.lastSessionAccuracy:
        return _assembleAccuracy(client, card);
      case RecallIntent.parentSummary:
        return _assembleVerbatimField(
          client,
          card,
          intent: intent,
          getter: (s) => s.parentUpdate,
          missingTemplate: 'No parent update was recorded for the last session.',
        );
      case RecallIntent.homeProgramme:
        return _assembleVerbatimField(
          client,
          card,
          intent: intent,
          getter: (s) => s.homeProgramme,
          missingTemplate: 'No home programme was recorded for the last session.',
        );
      case RecallIntent.lastSessionGeneral:
        return _assembleLastSessionGeneral(client, card);
      case RecallIntent.aacLayout:
      case RecallIntent.other:
        // Defensive: these were filtered out above. If we reach here
        // something is logically wrong upstream; route to slow path.
        return RecallAnswer.slowPath(
          intent: intent,
          clientId: client.id,
          clientName: client.name,
          note: 'assembler reached for non-fast intent',
        );
    }
  }

  RecallAnswer _assembleLastGoal(_ClientMatch client, RecallCard card) {
    // Prefer the first active STG's target_behavior (the canonical
    // "current goal"). Fall back to the last session's target_behaviour
    // (what was being worked on most recently). Fall back to an honest
    // template if neither exists.
    final stg = card.activeStgs.isNotEmpty ? card.activeStgs.first : null;
    final stgText = (stg?['target_behavior'] as String?)?.trim();
    if (stgText != null && stgText.isNotEmpty) {
      return RecallAnswer.fast(
        intent: RecallIntent.lastGoal,
        clientId: client.id,
        clientName: client.name,
        text: stgText,
        verbatim: true,
      );
    }
    final lastSessionGoal = card.lastSession?.targetBehaviour;
    if (lastSessionGoal != null && lastSessionGoal.isNotEmpty) {
      return RecallAnswer.fast(
        intent: RecallIntent.lastGoal,
        clientId: client.id,
        clientName: client.name,
        text: lastSessionGoal,
        verbatim: true,
      );
    }
    return RecallAnswer.fast(
      intent: RecallIntent.lastGoal,
      clientId: client.id,
      clientName: client.name,
      text: 'No active goal recorded for ${client.name} yet.',
      verbatim: false,
    );
  }

  RecallAnswer _assembleAccuracy(_ClientMatch client, RecallCard card) {
    final ls = card.lastSession;
    if (ls == null) {
      return RecallAnswer.fast(
        intent: RecallIntent.lastSessionAccuracy,
        clientId: client.id,
        clientName: client.name,
        text: 'No sessions recorded for ${client.name} yet.',
        verbatim: false,
      );
    }
    final attempts = ls.attempts;
    final indep = ls.independentResponses;
    final date = ls.date;
    if (attempts == null || attempts <= 0 || indep == null) {
      return RecallAnswer.fast(
        intent: RecallIntent.lastSessionAccuracy,
        clientId: client.id,
        clientName: client.name,
        text: date == null
            ? 'No scored trials in the last session.'
            : 'No scored trials in the $date session.',
        verbatim: false,
      );
    }
    final pct = ((indep / attempts) * 100).round();
    final datePrefix = date == null ? 'Last session' : 'Last session ($date)';
    return RecallAnswer.fast(
      intent: RecallIntent.lastSessionAccuracy,
      clientId: client.id,
      clientName: client.name,
      text: '$datePrefix: $indep of $attempts ($pct%).',
      verbatim: false,
    );
  }

  RecallAnswer _assembleVerbatimField(
    _ClientMatch client,
    RecallCard card, {
    required RecallIntent intent,
    required String? Function(RecallLastSession) getter,
    required String missingTemplate,
  }) {
    final ls = card.lastSession;
    if (ls == null) {
      return RecallAnswer.fast(
        intent: intent,
        clientId: client.id,
        clientName: client.name,
        text: 'No sessions recorded for ${client.name} yet.',
        verbatim: false,
      );
    }
    final value = getter(ls)?.trim();
    if (value == null || value.isEmpty) {
      return RecallAnswer.fast(
        intent: intent,
        clientId: client.id,
        clientName: client.name,
        text: missingTemplate,
        verbatim: false,
      );
    }
    return RecallAnswer.fast(
      intent: intent,
      clientId: client.id,
      clientName: client.name,
      text: value,
      verbatim: true,
    );
  }

  RecallAnswer _assembleLastSessionGeneral(_ClientMatch client, RecallCard card) {
    final ls = card.lastSession;
    if (ls == null) {
      return RecallAnswer.fast(
        intent: RecallIntent.lastSessionGeneral,
        clientId: client.id,
        clientName: client.name,
        text: 'No sessions recorded for ${client.name} yet.',
        verbatim: false,
      );
    }
    // Prefer soap_note → notes → client_affect. Same precedence as
    // _TodayScreenState._briefNarrativeFromSession (today_screen.dart:
    // 1473) so the recall fast path and the Today card stay in sync.
    final soap = ls.soapNote;
    if (soap != null && soap.isNotEmpty) {
      return RecallAnswer.fast(
        intent: RecallIntent.lastSessionGeneral,
        clientId: client.id,
        clientName: client.name,
        text: soap,
        verbatim: true,
      );
    }
    final notes = ls.notes;
    if (notes != null && notes.isNotEmpty) {
      return RecallAnswer.fast(
        intent: RecallIntent.lastSessionGeneral,
        clientId: client.id,
        clientName: client.name,
        text: notes,
        verbatim: true,
      );
    }
    final affect = ls.clientAffect;
    if (affect != null && affect.isNotEmpty) {
      return RecallAnswer.fast(
        intent: RecallIntent.lastSessionGeneral,
        clientId: client.id,
        clientName: client.name,
        text: 'Client affect: $affect.',
        verbatim: true,
      );
    }
    return RecallAnswer.fast(
      intent: RecallIntent.lastSessionGeneral,
      clientId: client.id,
      clientName: client.name,
      text: 'No narrative recorded for the last session.',
      verbatim: false,
    );
  }

  String _unresolvableMessage(RecallIntent intent) {
    switch (intent) {
      case RecallIntent.aacLayout:
        return "Cue doesn't capture AAC layout yet.";
      default:
        return "Cue doesn't capture that field yet.";
    }
  }
}
