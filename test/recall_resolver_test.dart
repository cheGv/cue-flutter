// test/recall_resolver_test.dart
//
// Isolation test for the Flutter-side recall resolver.
//
// • No Supabase, no network, no live JWT — uses a FakeRecallCardSource
//   that returns canned RecallCard objects keyed by client_id. This
//   demonstrates the seam: the resolver doesn't care where cards come
//   from, only that the source can produce them.
// • Tests the end-to-end paths the design conversation defined:
//     - LAST_GOAL on the ZZ Latency Test Child (fallback to last
//       session's target_behaviour when active_stgs is empty)
//     - LAST_SESSION_ACCURACY templating
//     - PARENT_SUMMARY verbatim
//     - HOME_PROGRAMME missing → honest template
//     - AAC_LAYOUT registered-but-unresolvable
//     - OTHER → slow path
//     - Ambiguous client → slow path with reason
//     - Unknown client → slow path

import 'package:flutter_test/flutter_test.dart';

import 'package:cue/services/recall_card_source.dart';
import 'package:cue/services/recall_intent.dart';
import 'package:cue/services/recall_resolver.dart';

class FakeRecallCardSource implements RecallCardSource {
  final Map<String, RecallCard> _cards;
  int callCount = 0;

  FakeRecallCardSource(this._cards);

  @override
  Future<RecallCard?> getCard(String clientId) async {
    callCount += 1;
    return _cards[clientId];
  }
}

// Mirrors the sandbox-verified test child's card content (2026-05-19).
// Goal text + notes are verbatim from the sandbox card payload.
final _zzCard = RecallCard.fromJson(<String, dynamic>{
  'client_id': '1aeba020-a649-4e0f-be8f-50b5f9fa9ca4',
  'assembled_at': '2026-05-19T17:34:37.944409+00:00',
  'active_stgs': <Map<String, dynamic>>[],
  'active_ltgs': <Map<String, dynamic>>[],
  'last_session': <String, dynamic>{
    'id': 4,
    'date': '2026-05-17',
    'attempts': 10,
    'independent_responses': 8,
    'prompted_responses': 2,
    'parent_update': 'Vamshi engaged well today — strong attention.',
    'home_programme': null,
    'soap_note': null,
    'notes': 'Accuracy ~55%, no upward trend yet',
    'target_behaviour':
        'Produce /r/ in initial position in single words, 80% accuracy',
    'activity_name': null,
    'next_session_focus': null,
    'client_affect': null,
    'goal_met': null,
    'created_at': '2026-05-19T07:33:26.526149+00:00',
  },
});

// Roster shape mirrors what _TodayScreenState._allClients carries.
final _roster = <Map<String, dynamic>>[
  {'id': '1aeba020-a649-4e0f-be8f-50b5f9fa9ca4', 'name': 'ZZ Latency Test Child'},
  {'id': '1a28700f-04d2-4c7e-ac1b-c77354c4ed5f', 'name': 'ZZ Empty Card Test'},
];

void main() {
  late FakeRecallCardSource source;
  late RecallResolver resolver;

  setUp(() {
    source = FakeRecallCardSource({
      _zzCard.clientId: _zzCard,
    });
    resolver = RecallResolver(source: source);
  });

  group('intent classification', () {
    test('"last goal" → LAST_GOAL', () {
      expect(classifyRecallIntent('what was the last goal for Rishi'),
          RecallIntent.lastGoal);
    });
    test('"accuracy" → LAST_SESSION_ACCURACY', () {
      expect(classifyRecallIntent("how was Rishi's accuracy last session"),
          RecallIntent.lastSessionAccuracy);
    });
    test('"home programme" → HOME_PROGRAMME', () {
      expect(classifyRecallIntent('what was the home programme for Rishi'),
          RecallIntent.homeProgramme);
    });
    test('"AAC layout" → AAC_LAYOUT (registered-but-unresolvable)', () {
      expect(classifyRecallIntent("what's Rishi's AAC layout"),
          RecallIntent.aacLayout);
      expect(isRecallIntentResolvable(RecallIntent.aacLayout), isFalse);
    });
    test('unrecognised phrasing → OTHER', () {
      expect(classifyRecallIntent('why is Rishi regressing'),
          RecallIntent.other);
    });
  });

  group('intent classification — expanded synonyms (Fix 1)', () {
    test('"previous goal" → LAST_GOAL', () {
      expect(classifyRecallIntent('what was the previous goal'),
          RecallIntent.lastGoal);
    });
    test('"current target" → LAST_GOAL', () {
      expect(classifyRecallIntent('remind me of his current target'),
          RecallIntent.lastGoal);
    });
    test('"performance" → LAST_SESSION_ACCURACY', () {
      expect(classifyRecallIntent('how was her performance'),
          RecallIntent.lastSessionAccuracy);
    });
    test('"carryover" → HOME_PROGRAMME', () {
      expect(classifyRecallIntent('what carryover did we send'),
          RecallIntent.homeProgramme);
    });
    test('"talker" → AAC_LAYOUT (registered-but-unresolvable)', () {
      expect(classifyRecallIntent('does she use a talker'),
          RecallIntent.aacLayout);
      expect(isRecallIntentResolvable(RecallIntent.aacLayout), isFalse);
    });
  });

  group('end-to-end resolve', () {
    test(
        'LAST_GOAL for ZZ Latency Test Child falls back to last session\'s '
        'target_behaviour when active_stgs is empty', () async {
      final answer = await resolver.resolve(
        question: 'what was the last goal for ZZ Latency Test Child',
        clientRoster: _roster,
      );
      expect(answer.kind, RecallAnswerKind.fast);
      expect(answer.intent, RecallIntent.lastGoal);
      expect(answer.clientName, 'ZZ Latency Test Child');
      expect(answer.verbatim, isTrue);
      expect(answer.text,
          'Produce /r/ in initial position in single words, 80% accuracy');
      expect(source.callCount, 1);
    });

    test('LAST_SESSION_ACCURACY produces templated string', () async {
      final answer = await resolver.resolve(
        question: "what was ZZ Latency Test Child's accuracy",
        clientRoster: _roster,
      );
      expect(answer.kind, RecallAnswerKind.fast);
      expect(answer.intent, RecallIntent.lastSessionAccuracy);
      expect(answer.verbatim, isFalse);
      expect(answer.text, 'Last session (2026-05-17): 8 of 10 (80%).');
    });

    test('PARENT_SUMMARY returns verbatim parent_update', () async {
      final answer = await resolver.resolve(
        question: 'what was the parent update for ZZ Latency Test Child',
        clientRoster: _roster,
      );
      expect(answer.kind, RecallAnswerKind.fast);
      expect(answer.intent, RecallIntent.parentSummary);
      expect(answer.verbatim, isTrue);
      expect(answer.text, 'Vamshi engaged well today — strong attention.');
    });

    test('HOME_PROGRAMME missing in card → honest template', () async {
      final answer = await resolver.resolve(
        question: 'what was the home programme for ZZ Latency Test Child',
        clientRoster: _roster,
      );
      expect(answer.kind, RecallAnswerKind.fast);
      expect(answer.intent, RecallIntent.homeProgramme);
      expect(answer.verbatim, isFalse);
      expect(answer.text,
          'No home programme was recorded for the last session.');
    });

    test('AAC_LAYOUT → unresolvable, no card fetch needed', () async {
      final answer = await resolver.resolve(
        question: "what's the AAC layout for ZZ Latency Test Child",
        clientRoster: _roster,
      );
      expect(answer.kind, RecallAnswerKind.unresolvable);
      expect(answer.intent, RecallIntent.aacLayout);
      expect(answer.text, "Cue doesn't capture AAC layout yet.");
      // Critical: must NOT have hit the source — unresolvable short-
      // circuits before getCard.
      expect(source.callCount, 0);
    });

    test('OTHER → slow path with resolved client context', () async {
      final answer = await resolver.resolve(
        question: 'why is ZZ Latency Test Child regressing',
        clientRoster: _roster,
      );
      expect(answer.kind, RecallAnswerKind.slowPath);
      expect(answer.intent, RecallIntent.other);
      expect(answer.clientName, 'ZZ Latency Test Child');
      expect(answer.note, contains('intent not in registry'));
    });

    test('unknown client → slow path, no client picked silently', () async {
      final answer = await resolver.resolve(
        question: 'what was the last goal for Aarav',
        clientRoster: _roster,
      );
      expect(answer.kind, RecallAnswerKind.slowPath);
      expect(answer.note, 'no client matched');
      expect(answer.clientId, isNull);
    });

    test('card missing for client → slow path', () async {
      final answer = await resolver.resolve(
        question: 'what was the last goal for ZZ Empty Card Test',
        clientRoster: _roster,
      );
      expect(answer.kind, RecallAnswerKind.slowPath);
      expect(answer.clientName, 'ZZ Empty Card Test');
      expect(answer.note, 'card unavailable');
    });
  });

  group('B-principle — never silently pick a client', () {
    test('ambiguous full names → slow path with both names in note',
        () async {
      // Two distinct clients sharing a first name. Question mentions
      // only the first name → both score 80 → ambiguous.
      final ambiguousRoster = <Map<String, dynamic>>[
        {'id': 'id-rishi-1', 'name': 'Rishi Kumar'},
        {'id': 'id-rishi-2', 'name': 'Rishi Patel'},
      ];
      final answer = await resolver.resolve(
        question: 'what was the last goal for Rishi',
        clientRoster: ambiguousRoster,
      );
      expect(answer.kind, RecallAnswerKind.slowPath);
      expect(answer.note, contains('ambiguous client'));
      expect(answer.note, contains('Rishi Kumar'));
      expect(answer.note, contains('Rishi Patel'));
      expect(answer.clientId, isNull);
    });

    test('full-name match in question beats first-name match', () async {
      final ambiguousRoster = <Map<String, dynamic>>[
        {'id': 'id-rishi-1', 'name': 'Rishi Kumar'},
        {'id': 'id-rishi-2', 'name': 'Rishi Patel'},
      ];
      final answer = await resolver.resolve(
        question: 'what was the last goal for Rishi Kumar',
        clientRoster: ambiguousRoster,
      );
      // No card in the source for that id → slow path, but with a
      // resolved client — proving the matcher uniquely picked Kumar
      // (score 100) over Patel (score 80).
      expect(answer.kind, RecallAnswerKind.slowPath);
      expect(answer.note, 'card unavailable');
      expect(answer.clientName, 'Rishi Kumar');
    });
  });
}
