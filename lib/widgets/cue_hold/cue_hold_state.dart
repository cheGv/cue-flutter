// lib/widgets/cue_hold/cue_hold_state.dart
//
// Phase 4.1.3 — Cue Hold state machine. ValueNotifier-style singleton
// (matches the project's existing themeNotifier pattern; no Provider /
// Riverpod dependency).
//
// EIGHT STATES per spec:
//   idle         — pill with cuttlefish + "Cue · ready" + mic
//   compact      — pill with context-aware label ("Cue · reading X")
//   whisper      — extended pill with italic Playfair insight prose
//   thinking     — pill, label "Cue · thinking…", three-dot animation
//   listening    — pill, label "Cue · listening…", amber ring pulse
//   expanded     — inline chat surface (anchored top-right of viewport)
//   fullActivity — full-screen popup (routes to existing CuePopup)
//   multi        — two pills side-by-side at 75% size
//
// Transitions are morph-style and animated by widgets that read this
// notifier. The controller itself only owns state + transition data.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

enum CueHoldState {
  idle,
  compact,
  whisper,
  thinking,
  listening,
  expanded,
  fullActivity,
  multi,
}

/// One row in the inline chat history rendered by CueHoldExpanded.
class CueHoldChatMessage {
  final String text;
  final bool fromUser;
  final DateTime ts;
  CueHoldChatMessage({
    required this.text,
    required this.fromUser,
    DateTime? ts,
  }) : ts = ts ?? DateTime.now();
}

/// Global singleton notifier. Import and use directly:
///   final controller = cueHoldController;
///   controller.transitionTo(CueHoldState.thinking);
final CueHoldController cueHoldController = CueHoldController();

class CueHoldController extends ChangeNotifier {
  CueHoldState _state = CueHoldState.idle;
  CueHoldState? _previousState;

  // COMPACT — short context label, e.g. "Cue · reading Rishi"
  String _contextLabel = 'Cue · ready';

  // WHISPER — italic Playfair text shown beside cuttlefish
  String _whisperText = '';
  Timer? _whisperDismissTimer;

  // EXPANDED — inline chat history + goal anchor
  final List<CueHoldChatMessage> _conversation = <CueHoldChatMessage>[];
  String? _stgAnchorId;
  String? _ltgAnchorId;
  String? _stgBodyText; // for Tier 3 intro copy in the expanded chat
  String _clientName = '';
  String _clientId = '';

  // MULTI — secondary pill state for parallel tasks
  CueHoldState? _secondaryState;
  String _secondaryLabel = '';

  // Phase 4.1.4 — independent THINKING flag for the chat-in-flight case.
  // Toggled from CueHoldExpanded when AskCueService.sendMessage is in
  // progress. The Hold pill (rendered behind the chat overlay) reads
  // this and shows the THINKING pill instead of the previous-state pill;
  // the EXPANDED state itself isn't changed so the chat overlay stays
  // mounted.
  bool _thinkingInExpanded = false;

  // ── Public read API ──────────────────────────────────────────────────────

  CueHoldState get state => _state;
  CueHoldState? get previousState => _previousState;
  String get contextLabel => _contextLabel;
  String get whisperText => _whisperText;
  List<CueHoldChatMessage> get conversation =>
      List.unmodifiable(_conversation);
  String? get stgAnchorId => _stgAnchorId;
  String? get ltgAnchorId => _ltgAnchorId;
  String? get stgBodyText => _stgBodyText;
  String get clientName => _clientName;
  String get clientId => _clientId;
  CueHoldState? get secondaryState => _secondaryState;
  String get secondaryLabel => _secondaryLabel;
  bool get thinkingInExpanded => _thinkingInExpanded;

  /// True when [state] resolves to a pill-shaped surface (vs. expanded
  /// chat / full popup / multi). Used by the renderer to pick the layout.
  bool get isPillShape =>
      _state == CueHoldState.idle ||
      _state == CueHoldState.compact ||
      _state == CueHoldState.whisper ||
      _state == CueHoldState.thinking ||
      _state == CueHoldState.listening;

  // ── Notification safety (Phase 4.1.9) ────────────────────────────────────
  //
  // Phase 4.1.6 fixed the initState side of the locked-tree hazard by
  // wrapping `setClientContext` in a post-frame callback at the call
  // site (client_profile_screen.dart). The symmetric dispose side
  // (clearClientContext + toIdle invoked from dispose) cannot use the
  // same call-site pattern: addPostFrameCallback inside dispose fires
  // after the State is gone, and dispose itself runs while the
  // scheduler is in `persistentCallbacks` (tree locked for teardown).
  //
  // The fix lives here so it covers BOTH dispose and any future caller
  // that mutates the controller from a locked phase. State mutations
  // (the field writes) still happen synchronously above each call to
  // _safeNotify — only the notifyListeners() is deferred when the
  // scheduler is in a phase where AnimatedBuilder subscribers cannot
  // safely markNeedsBuild(). When safe, the notify fires synchronously
  // (no observable change vs. the original behavior).
  void _safeNotify() {
    final phase = SchedulerBinding.instance.schedulerPhase;
    final treeLocked = phase == SchedulerPhase.persistentCallbacks ||
        phase == SchedulerPhase.midFrameMicrotasks;
    if (!treeLocked) {
      notifyListeners();
      return;
    }
    // Defer to the next frame's post-frame slot. The controller is a
    // global singleton, so capturing `this` here is safe.
    SchedulerBinding.instance.addPostFrameCallback((_) {
      notifyListeners();
    });
  }

  // ── Transitions ──────────────────────────────────────────────────────────

  void _setState(CueHoldState next) {
    if (_state == next) return;
    _previousState = _state;
    _state = next;
    _safeNotify();
  }

  void toIdle() {
    _whisperDismissTimer?.cancel();
    _contextLabel = 'Cue · ready';
    _setState(CueHoldState.idle);
  }

  void toCompact(String label) {
    _whisperDismissTimer?.cancel();
    _contextLabel = label.isEmpty ? 'Cue · ready' : label;
    _setState(CueHoldState.compact);
  }

  /// Triggers a WHISPER state with auto-dismiss after [duration]. Spec
  /// default is 8 seconds; callers can override for testing.
  void toWhisper(
    String text, {
    Duration duration = const Duration(seconds: 8),
  }) {
    _whisperDismissTimer?.cancel();
    _whisperText = text;
    _setState(CueHoldState.whisper);
    _whisperDismissTimer = Timer(duration, () {
      if (_state == CueHoldState.whisper) {
        _whisperText = '';
        _setState(CueHoldState.compact);
      }
    });
  }

  void toThinking() {
    _whisperDismissTimer?.cancel();
    _contextLabel = 'Cue · thinking…';
    _setState(CueHoldState.thinking);
  }

  void toListening() {
    _whisperDismissTimer?.cancel();
    _contextLabel = 'Cue · listening…';
    _setState(CueHoldState.listening);
  }

  /// Opens the inline chat. The caller (chart / today) supplies client
  /// context so the chat assistant can reference it. Conversation
  /// history persists across collapse → re-open until [closeExpanded]
  /// is called (the "close X" button) or the app restarts.
  void expand({
    required String clientId,
    required String clientName,
    String? stgId,
    String? ltgId,
    String? stgBodyText,
  }) {
    _whisperDismissTimer?.cancel();
    _clientId = clientId;
    _clientName = clientName;
    _stgAnchorId = stgId;
    _ltgAnchorId = ltgId;
    _stgBodyText = stgBodyText;
    _setState(CueHoldState.expanded);
  }

  /// "Minimize" — collapses the expanded chat to the previous pill state,
  /// keeping conversation history in memory.
  void minimizeExpanded() {
    if (_state != CueHoldState.expanded) return;
    final back = _previousState ?? CueHoldState.idle;
    _setState(back);
  }

  /// "Close X" — collapses to IDLE and clears conversation history.
  void closeExpanded() {
    if (_state != CueHoldState.expanded) {
      _conversation.clear();
      _stgAnchorId = null;
      _ltgAnchorId = null;
      _stgBodyText = null;
      return;
    }
    _conversation.clear();
    _stgAnchorId = null;
    _ltgAnchorId = null;
    _stgBodyText = null;
    _contextLabel = 'Cue · ready';
    _setState(CueHoldState.idle);
  }

  void appendChatMessage(CueHoldChatMessage msg) {
    _conversation.add(msg);
    _safeNotify();
  }

  /// Phase 4.1.4 — attaches the active client context to the controller
  /// without opening the chat. Called by the chart screen on mount so a
  /// plain pill tap from the chart fires the EXPANDED chat at Tier 2
  /// (client-aware intro) without first requiring a "Think with Cue" tap.
  void setClientContext({
    required String clientId,
    required String clientName,
  }) {
    if (_clientId == clientId && _clientName == clientName) return;
    _clientId = clientId;
    _clientName = clientName;
    _safeNotify();
  }

  void clearClientContext() {
    // Only clear when the chat isn't currently open against this client;
    // if EXPANDED, leave the in-flight conversation's context intact.
    if (_state == CueHoldState.expanded) return;
    if (_clientId.isEmpty && _clientName.isEmpty) return;
    _clientId = '';
    _clientName = '';
    _stgAnchorId = null;
    _ltgAnchorId = null;
    _stgBodyText = null;
    _safeNotify();
  }

  /// Phase 4.1.4 — used by the EXPANDED chat to flip the Hold pill into a
  /// THINKING register while a query is in flight. Does NOT change
  /// [state]; the chat overlay stays mounted.
  void setThinkingInExpanded(bool value) {
    if (_thinkingInExpanded == value) return;
    _thinkingInExpanded = value;
    _safeNotify();
  }

  void toFullActivity() {
    _whisperDismissTimer?.cancel();
    _setState(CueHoldState.fullActivity);
  }

  void closeFullActivity() {
    if (_state != CueHoldState.fullActivity) return;
    _setState(_previousState ?? CueHoldState.idle);
  }

  /// Splits the current pill into MULTI-STATE: keeps the current state
  /// as the primary pill and adds a secondary pill rendering [secondary]
  /// alongside it. Used when two parallel tasks (e.g. THINKING + LISTENING)
  /// need to coexist briefly. Phase 4.1.3 wires this via the dev shortcut
  /// ⌘⇧M only; real triggers land in Phase 1.5.
  void toMulti(CueHoldState secondary, String secondaryLabel) {
    _whisperDismissTimer?.cancel();
    _secondaryState = secondary;
    _secondaryLabel = secondaryLabel;
    _setState(CueHoldState.multi);
  }

  /// Collapses multi back to the primary state.
  void exitMulti() {
    if (_state != CueHoldState.multi) return;
    final prev = _previousState ?? CueHoldState.idle;
    _secondaryState = null;
    _secondaryLabel = '';
    _setState(prev);
  }

  @override
  void dispose() {
    _whisperDismissTimer?.cancel();
    super.dispose();
  }
}
