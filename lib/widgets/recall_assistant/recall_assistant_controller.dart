// lib/widgets/recall_assistant/recall_assistant_controller.dart
//
// State for the dedicated recall assistant surface: the session-scoped
// recent list (max 5), open/closed, route/auth suppression, idle clear,
// and the resolve / disambiguate / escalate orchestration.
//
// SEAM: depends on RecallResolver / RecallAnswer / RecallIntent ONLY. The
// concrete DirectTableCardSource + roster query + "open in Study" action
// are injected from main.dart (composition root) via [attach] — this file
// never imports Supabase or RecallCardSource.

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../services/recall_intent.dart';
import '../../services/recall_resolver.dart';
import 'recall_query.dart';

typedef RecallRosterProvider = Future<List<Map<String, dynamic>>> Function();

class RecallAssistantController extends ChangeNotifier {
  static const int kMaxRecent = 5;
  static const Duration kIdleTimeout = Duration(minutes: 30);

  RecallResolver? _resolver;
  RecallRosterProvider? _rosterProvider;
  void Function(RecallQuery query)? _onOpenInStudy;
  List<Map<String, dynamic>>? _cachedRoster;

  final List<RecallQuery> _recent = <RecallQuery>[];
  List<RecallQuery> get recent => List.unmodifiable(_recent);

  bool _isOpen = false;
  bool get isOpen => _isOpen;

  /// True on auth screens / signed-out — hides the button and disables
  /// the Cmd+K intercept so it doesn't shadow auth-screen behaviour.
  bool _suppressed = false;
  bool get suppressed => _suppressed;

  /// True while a resolve/disambiguate is in flight (drives the spinner).
  bool _busy = false;
  bool get busy => _busy;

  // Carried-client focus — persists across navigation until explicitly
  // cleared (chip ×, Clear), sign-out, or idle timeout. Set when a client's
  // chart opens, and when a query names a client that resolves uniquely.
  String? _focusedClientId;
  String? _focusedClientName;
  String? get focusedClientId => _focusedClientId;
  String? get focusedClientName => _focusedClientName;

  void setFocusedClient(String id, String name) {
    if (_focusedClientId == id && _focusedClientName == name) return;
    _focusedClientId = id;
    _focusedClientName = name;
    notifyListeners();
  }

  void clearFocusedClient() {
    if (_focusedClientId == null && _focusedClientName == null) return;
    _focusedClientId = null;
    _focusedClientName = null;
    notifyListeners();
  }

  // Double-submit guard (Fix 2): a submit of the same question text within
  // this window is discarded before touching the resolver. Belt-and-
  // suspenders for racing voice / keyboard / Enter paths regardless of root
  // cause.
  static const Duration _dedupWindow = Duration(seconds: 2);
  String? _lastSubmittedQuestion;
  DateTime? _lastSubmittedAt;

  Timer? _idleTimer;

  // ── Composition-root wiring ──────────────────────────────────────────

  void attach({
    required RecallResolver resolver,
    required RecallRosterProvider rosterProvider,
    void Function(RecallQuery query)? onOpenInStudy,
  }) {
    _resolver = resolver;
    _rosterProvider = rosterProvider;
    _onOpenInStudy = onOpenInStudy;
  }

  // ── Suppression (auth / signed-out) ──────────────────────────────────

  void setSuppressed(bool value) {
    if (_suppressed == value) return;
    _suppressed = value;
    if (value && _isOpen) _isOpen = false;
    notifyListeners();
  }

  // ── Idle / activity ──────────────────────────────────────────────────

  /// Called by any Cue interaction (pointer/key at the root, plus every
  /// recall action). Resets the 30-minute idle clock.
  void markActivity() {
    _idleTimer?.cancel();
    _idleTimer = Timer(kIdleTimeout, _onIdle);
  }

  void _onIdle() {
    final hadState = _recent.isNotEmpty ||
        _focusedClientId != null ||
        _focusedClientName != null;
    if (!hadState) return;
    _recent.clear();
    _focusedClientId = null;
    _focusedClientName = null;
    notifyListeners();
  }

  // ── Open / close ─────────────────────────────────────────────────────

  void open() {
    markActivity();
    if (_suppressed || _isOpen) return;
    // Refresh roster on open so newly-added clients become matchable.
    _cachedRoster = null;
    _isOpen = true;
    notifyListeners();
  }

  void close() {
    if (!_isOpen) return;
    _isOpen = false;
    notifyListeners();
  }

  void toggle() {
    markActivity();
    if (_suppressed) return;
    if (_isOpen) {
      _isOpen = false;
    } else {
      _cachedRoster = null;
      _isOpen = true;
    }
    notifyListeners();
  }

  // ── Recent-list lifecycle ────────────────────────────────────────────

  void clear() {
    markActivity();
    final hadState = _recent.isNotEmpty ||
        _focusedClientId != null ||
        _focusedClientName != null;
    if (!hadState) return;
    // Clear clears BOTH the recent queries and the focused client.
    _recent.clear();
    _focusedClientId = null;
    _focusedClientName = null;
    notifyListeners();
  }

  /// Sign-out: clear everything and close. Called from main.dart's auth
  /// listener.
  void onSignOut() {
    _recent.clear();
    _cachedRoster = null;
    _focusedClientId = null;
    _focusedClientName = null;
    _isOpen = false;
    notifyListeners();
  }

  // ── Resolve ──────────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> _ensureRoster() async {
    final cached = _cachedRoster;
    if (cached != null) return cached;
    final provider = _rosterProvider;
    if (provider == null) return const <Map<String, dynamic>>[];
    try {
      final roster = await provider();
      _cachedRoster = roster;
      return roster;
    } catch (_) {
      return const <Map<String, dynamic>>[];
    }
  }

  Future<void> submit(String question) async {
    final q = question.trim();
    if (q.isEmpty || _busy) return;

    // Fix 2 — double-submit guard. The same text within the dedup window is
    // discarded before the resolver is touched.
    final now = DateTime.now();
    if (_lastSubmittedQuestion == q &&
        _lastSubmittedAt != null &&
        now.difference(_lastSubmittedAt!) < _dedupWindow) {
      debugPrint('[recall] duplicate submit discarded within '
          '${_dedupWindow.inSeconds}s: "$q"');
      return;
    }
    _lastSubmittedQuestion = q;
    _lastSubmittedAt = now;

    markActivity();

    // Captured BEFORE any focus mutation below: whether a client was focused
    // at submit time. Drives the softer "did you mean" recovery vs. Cue
    // Study escalation for slow-path classification misses (Fix 3).
    final focusWasSet = (_focusedClientName?.trim().isNotEmpty ?? false);

    final resolver = _resolver;
    if (resolver == null) {
      _pushRecent(RecallQuery(
        question: q,
        answer: RecallAnswer.slowPath(
          intent: RecallIntent.other,
          note: 'resolver not attached',
        ),
        ts: DateTime.now(),
        wasFocusedAtSubmit: focusWasSet,
      ));
      return;
    }

    _busy = true;
    notifyListeners();
    try {
      final roster = await _ensureRoster();
      var answer = await resolver.resolve(question: q, clientRoster: roster);
      String? carried;

      final namedNoClient = answer.kind == RecallAnswerKind.slowPath &&
          answer.note == 'no client matched';
      final focusName = _focusedClientName?.trim() ?? '';
      if (namedNoClient && focusName.isNotEmpty) {
        // No client in the question + a focused client is set → re-resolve
        // as if the focused client's name were appended (the verified
        // resolver's own matching path; resolver unchanged). Focus stays.
        final retry = await resolver.resolve(
          question: '$q $focusName',
          clientRoster: roster,
        );
        final stillNoClient = retry.kind == RecallAnswerKind.slowPath &&
            retry.note == 'no client matched';
        if (!stillNoClient) {
          answer = retry;
          carried = _focusedClientName;
        }
      } else if (answer.clientId != null && answer.clientId!.isNotEmpty) {
        // The query named a client that resolved uniquely → it becomes the
        // focus for subsequent unnamed queries.
        _focusedClientId = answer.clientId;
        _focusedClientName = answer.clientName;
      }

      _recent.insert(
        0,
        RecallQuery(
          question: q,
          answer: answer,
          ts: DateTime.now(),
          carriedClientName: carried,
          wasFocusedAtSubmit: focusWasSet,
        ),
      );
      while (_recent.length > kMaxRecent) {
        _recent.removeLast();
      }
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  /// B-principle disambiguation: re-resolve with the chosen client's full
  /// name appended (the verified resolver's own matching path), then
  /// replace the ambiguous entry in-place.
  Future<void> disambiguate(RecallQuery original, String clientFullName) async {
    final resolver = _resolver;
    if (resolver == null || _busy) return;
    markActivity();
    _busy = true;
    notifyListeners();
    try {
      final roster = await _ensureRoster();
      final answer = await resolver.resolve(
        question: '${original.question} $clientFullName',
        clientRoster: roster,
      );
      // The disambiguated client becomes the focus.
      if (answer.clientId != null && answer.clientId!.isNotEmpty) {
        _focusedClientId = answer.clientId;
        _focusedClientName = answer.clientName ?? clientFullName;
      }
      final idx = _recent.indexOf(original);
      final replacement = RecallQuery(
        question: original.question,
        answer: answer,
        ts: original.ts,
        carriedClientName: clientFullName,
        wasFocusedAtSubmit: original.wasFocusedAtSubmit,
      );
      if (idx != -1) {
        _recent[idx] = replacement;
      } else {
        _recent.insert(0, replacement);
        while (_recent.length > kMaxRecent) {
          _recent.removeLast();
        }
      }
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  // ── Slow-path escalation ─────────────────────────────────────────────

  /// "Open in Cue Study": annotate the entry, close the card, and hand
  /// off to the injected Study action. NEVER calls the model directly —
  /// the SLP chose to escalate.
  void openInStudy(RecallQuery query) {
    markActivity();
    final idx = _recent.indexOf(query);
    if (idx != -1) {
      _recent[idx] = query.copyWith(escalatedToStudy: true);
    }
    _isOpen = false;
    notifyListeners();
    _onOpenInStudy?.call(query);
  }

  /// "Skip": leave the entry visible with its escalation prompt but no
  /// buttons, so the SLP sees she chose not to escalate.
  void skipEscalation(RecallQuery query) {
    markActivity();
    final idx = _recent.indexOf(query);
    if (idx == -1) return;
    _recent[idx] = query.copyWith(escalationSkipped: true);
    notifyListeners();
  }

  void _pushRecent(RecallQuery q) {
    _recent.insert(0, q);
    while (_recent.length > kMaxRecent) {
      _recent.removeLast();
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _idleTimer?.cancel();
    super.dispose();
  }
}

/// Global singleton — matches the cueHoldController pattern (no Provider /
/// Riverpod). Constructed at import; wired in main() via [attach].
final RecallAssistantController recallAssistantController =
    RecallAssistantController();
