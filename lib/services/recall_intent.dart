// lib/services/recall_intent.dart
//
// Cue Recall Assistant — intent vocabulary as DATA.
//
// Adding an intent later is a registry entry, not a resolver code change.
// Same extensibility discipline as the backend's parameterised intent
// list in recall-classify (supabase/functions/recall-classify/index.ts).
//
// The matching strategy is deterministic over a bounded vocabulary:
// case-insensitive substring search for any of the matcher's keywords
// against the SLP's question text. NO model, NO network, NO heuristic
// scoring beyond "first matcher with at least one hit wins" — ordered
// from most specific intent to least so e.g. PARENT_SUMMARY ("update for
// the parent") is matched before the looser LAST_SESSION_GENERAL.

enum RecallIntent {
  lastGoal,
  lastSessionAccuracy,
  parentSummary,
  homeProgramme,
  lastSessionGeneral,
  aacLayout,
  other,
}

/// One row in the registry: which intent, which keywords trigger it,
/// and whether the intent is currently resolvable (false = registered
/// but unsupported — caller gets an honest "Cue doesn't capture X yet"
/// rather than a fabricated answer).
class IntentMatcher {
  final RecallIntent intent;
  final List<String> keywords;
  final bool isResolvable;

  const IntentMatcher({
    required this.intent,
    required this.keywords,
    this.isResolvable = true,
  });
}

/// The registry. ORDER MATTERS — earlier entries win. AAC_LAYOUT sits
/// before HOME_PROGRAMME because "AAC layout" must NOT fall through to
/// "home programme" on a phrase like "did we set up an AAC layout at
/// home." Pure data; never branches in the resolver.
const List<IntentMatcher> kRecallIntentRegistry = <IntentMatcher>[
  IntentMatcher(
    intent: RecallIntent.aacLayout,
    // Bare 'aac' is deliberately EXCLUDED: the classifier uses
    // String.contains, so 'aac' would match the client name "Isaac"
    // (misclassifying "Isaac's last goal" as AAC_LAYOUT). Every keyword
    // below is long enough to avoid that substring collision.
    keywords: <String>[
      'aac layout',
      'aac board',
      'communication board',
      'core board',
      'symbol layout',
      'her device',
      'his device',
      'speech device',
      'talker',
    ],
    isResolvable: false,
  ),
  IntentMatcher(
    intent: RecallIntent.lastSessionAccuracy,
    keywords: <String>[
      'accuracy',
      'how did she do',
      'how did he do',
      'how did they do',
      'how did it go',
      'how was the session',
      'how was last session',
      'performance',
      'percentage',
      'percent',
      'attempts',
      'score',
      'how many trials',
      'trials hit',
      'independent responses',
      'responses',
    ],
  ),
  IntentMatcher(
    intent: RecallIntent.parentSummary,
    keywords: <String>[
      'parent update',
      'the parent update',
      'what i told the parent',
      'what i sent the parent',
      'told the parent',
      'told the family',
      'told the mom',
      'told the mum',
      'told the mother',
      'told the father',
      'told the caregiver',
      'what i told mom',
      'what i told dad',
      'parent summary',
      'parent note',
      'family update',
      'send to the parent',
    ],
  ),
  IntentMatcher(
    intent: RecallIntent.homeProgramme,
    keywords: <String>[
      'home programme',
      'home program',
      'homework',
      'home practice',
      'practice at home',
      "what they're doing at home",
      'send home',
      'carryover',
      'carry-over',
    ],
  ),
  IntentMatcher(
    intent: RecallIntent.lastGoal,
    keywords: <String>[
      'last goal',
      'previous goal',
      'current goal',
      'most recent goal',
      'working goal',
      'active goal',
      'active stg',
      'the goal',
      'what goal',
      'what is the goal',
      "what's the goal",
      'working on',
      'target',
      'current target',
      "what's the target",
      'target behaviour',
      'target behavior',
      'her goal',
      'his goal',
      'their goal',
    ],
  ),
  IntentMatcher(
    intent: RecallIntent.lastSessionGeneral,
    keywords: <String>[
      'last session',
      'previous session',
      'her last session',
      'his last session',
      'what happened',
      'last time',
      'soap',
      'session note',
      'session notes',
      'her notes',
    ],
  ),
];

/// Classify [question] against the registry. Returns the first matching
/// intent (case-insensitive substring on any keyword), or
/// [RecallIntent.other] when nothing matches.
///
/// Deterministic. Pure function. No I/O. Safe to call on every keystroke
/// if a future UI surface needs live intent preview.
RecallIntent classifyRecallIntent(String question) {
  final q = question.toLowerCase();
  for (final matcher in kRecallIntentRegistry) {
    for (final kw in matcher.keywords) {
      if (q.contains(kw.toLowerCase())) {
        return matcher.intent;
      }
    }
  }
  return RecallIntent.other;
}

/// True when the classified intent has a data model the resolver can
/// surface today. AAC_LAYOUT is registered (so the resolver can give an
/// honest "not captured yet" answer rather than misclassifying it as
/// OTHER) but isResolvable=false.
bool isRecallIntentResolvable(RecallIntent intent) {
  if (intent == RecallIntent.other) return false;
  for (final matcher in kRecallIntentRegistry) {
    if (matcher.intent == intent) return matcher.isResolvable;
  }
  return false;
}
