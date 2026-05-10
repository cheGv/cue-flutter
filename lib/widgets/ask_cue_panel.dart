// lib/widgets/ask_cue_panel.dart
//
// Phase 5.1+5.2 — Ask Cue panel. Unified chat surface invoked from
// the Profile (client-scoped) and reachable from Edit Goal in a
// future migration (goal-scoped). For now the existing
// CueReasoningPanel still services Edit Goal; this panel handles the
// client-scoped Profile path.
//
// Layout (per founder Q5/Q6 decisions): two-column workspace lives
// on Profile (chart left, this panel right) at viewport ≥ 1024.
// Below 1024, this panel is wrapped by AskCueDrawer and slides in
// on demand. Three-column with a thread sidebar was dropped — the
// sidebar math didn't fit at 1280. Instead, threads live as an
// inline expandable list at the bottom of THIS panel (scope-dot
// prefixed, hairline-separated rows).
//
// Design tokens (Phase 4.0.8 spine, per founder's design language
// lock):
//   • Background: kCueSurfaceWhite / kCuePaper
//   • Body text: Inter 13.5 / 1.7 line-height / kCueInk
//   • Eyebrow:   Mono 9.5 / kCueAmber / 0.18em tracked
//   • HUD strip: warm paper (NOT dark sidebar — would clash)
//   • Input:     rounded-pill, white, hairline border, amber on focus
//
// Streaming UX: the panel listens to AskCueService.sendMessage's
// Stream<String>. v1 emits one chunk; the typing-indicator + bubble
// fill-in machinery is in place for the SSE swap (Phase 5.3).

import 'dart:async';
import 'package:flutter/material.dart';

import '../models/reasoning_message.dart';
import '../models/reasoning_thread.dart';
import '../services/ask_cue_service.dart';
import '../theme/cue_phase4_tokens.dart';
import '../theme/cue_type_v3.dart';

class AskCuePanel extends StatefulWidget {
  final String clientId;
  final String clientName;
  /// Optional goal anchor — when non-null, the panel runs in
  /// goal-scoped mode (citations render as action chips, not
  /// inline footnotes). v1 only the Profile passes null (client-
  /// scoped); the Edit Goal migration to this widget is deferred.
  final String? ltgId;
  final String? stgId;

  const AskCuePanel({
    super.key,
    required this.clientId,
    required this.clientName,
    this.ltgId,
    this.stgId,
  });

  @override
  State<AskCuePanel> createState() => _AskCuePanelState();
}

class _AskCuePanelState extends State<AskCuePanel> {
  final _service = AskCueService.instance;
  final _inputCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  final _inputFocus = FocusNode();

  String? _threadId;
  List<ReasoningThread> _threads = const [];
  final List<ReasoningMessage> _messages = [];
  bool _loadingHistory = true;
  bool _sending = false;
  String? _error;

  // Streaming buffer for the in-flight assistant response.
  String _streamingText = '';
  bool _streaming = false;
  StreamSubscription<String>? _streamSub;

  bool get _isClientScoped => widget.ltgId == null && widget.stgId == null;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    _streamSub?.cancel();
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    _inputFocus.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    try {
      // Pull all threads for this client (both goal-scoped and
      // client-scoped) so the inline thread list renders.
      final threads = await _service.listThreads(clientId: widget.clientId);
      // Default selection: most-recent thread matching this scope.
      ReasoningThread? selected;
      for (final t in threads) {
        if (_isClientScoped && t.ltgId == null && t.stgId == null) {
          selected = t;
          break;
        }
        if (!_isClientScoped &&
            ((widget.ltgId != null && t.ltgId == widget.ltgId) ||
             (widget.stgId != null && t.stgId == widget.stgId))) {
          selected = t;
          break;
        }
      }
      List<ReasoningMessage> history = const [];
      if (selected != null) {
        history = await _service.loadHistory(selected.id);
      }
      if (!mounted) return;
      setState(() {
        _threads = threads;
        _threadId = selected?.id;
        _messages
          ..clear()
          ..addAll(history);
        _loadingHistory = false;
      });
      _scrollToBottomSoon();
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '$e';
          _loadingHistory = false;
        });
      }
    }
  }

  Future<void> _switchThread(ReasoningThread t) async {
    if (t.id == _threadId) return;
    setState(() {
      _loadingHistory = true;
      _threadId = t.id;
      _messages.clear();
      _streamingText = '';
      _streaming = false;
    });
    try {
      final history = await _service.loadHistory(t.id);
      if (!mounted) return;
      setState(() {
        _messages
          ..clear()
          ..addAll(history);
        _loadingHistory = false;
      });
      _scrollToBottomSoon();
    } catch (e) {
      if (mounted) setState(() => _loadingHistory = false);
    }
  }

  void _newThread() {
    setState(() {
      _threadId = null;
      _messages.clear();
      _streamingText = '';
      _streaming = false;
    });
    _inputFocus.requestFocus();
  }

  void _scrollToBottomSoon() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollCtrl.hasClients) return;
      _scrollCtrl.animateTo(
        _scrollCtrl.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _send() async {
    final text = _inputCtrl.text.trim();
    if (text.isEmpty || _sending || _streaming) return;
    _inputCtrl.clear();

    // Optimistic user-message bubble — assigned a temporary id; the
    // server-persisted row replaces it after the stream completes
    // (we just append the assistant turn; the user turn is already
    // rendered).
    final tempUser = ReasoningMessage(
      id:           'temp-${DateTime.now().microsecondsSinceEpoch}',
      threadId:     _threadId ?? '',
      role:         'user',
      content:      text,
      citations:    const [],
      frameworkIds: const [],
      appliedToGoal: false,
      createdAt:    DateTime.now(),
    );

    setState(() {
      _sending = true;
      _streaming = true;
      _streamingText = '';
      _error = null;
      _messages.add(tempUser);
    });
    _scrollToBottomSoon();

    final result = _service.sendMessage(
      threadId:    _threadId,
      clientId:    widget.clientId,
      ltgId:       widget.ltgId,
      stgId:       widget.stgId,
      userMessage: text,
    );

    _streamSub = result.textStream.listen(
      (chunk) {
        setState(() => _streamingText += chunk);
        _scrollToBottomSoon();
      },
      onError: (Object e) {
        if (!mounted) return;
        setState(() {
          _streaming = false;
          _sending = false;
          _error = 'Cue couldn\'t respond. Try again.';
        });
      },
    );

    try {
      final completion = await result.completion;
      if (!mounted) return;
      setState(() {
        _threadId = completion.threadId;
        _messages.add(completion.assistantMessage);
        _streaming = false;
        _streamingText = '';
        _sending = false;
      });
      _scrollToBottomSoon();
      // Refresh thread list so a brand-new thread shows up.
      _refreshThreadList();
    } catch (_) {
      // Already surfaced via stream's onError.
    }
  }

  Future<void> _refreshThreadList() async {
    try {
      final threads =
          await _service.listThreads(clientId: widget.clientId);
      if (!mounted) return;
      setState(() => _threads = threads);
    } catch (_) {/* silent */}
  }

  // ── Build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: kCueSurfaceWhite,
        border: Border(
          left: BorderSide(color: kCueBorder, width: 0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _hudStrip(),
          Expanded(child: _conversation()),
          _inputDock(),
        ],
      ),
    );
  }

  // HUD strip: warm paper, single pulse dot, "Ready" label, scope.
  Widget _hudStrip() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 12),
      decoration: const BoxDecoration(
        color: kCueSurfaceWhite,
        border: Border(
          bottom: BorderSide(color: kCueBorder, width: 0.5),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
              color: Color(0xFF8FBA68), // soft olive-green pulse
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            _streaming ? 'Thinking' : 'Ready',
            style: CueTypeV3.dataEyebrow(color: kCueAmber).copyWith(
              fontSize: 9.5,
              letterSpacing: 9.5 * 0.18,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _isClientScoped
                  ? 'Ask Cue · ${widget.clientName}'
                  : 'Ask Cue · this goal',
              overflow: TextOverflow.ellipsis,
              style: CueTypeV3.body(color: kCueInkSecondary)
                  .copyWith(fontSize: 12.5),
            ),
          ),
          IconButton(
            tooltip: 'New thread',
            onPressed: _streaming ? null : _newThread,
            icon: const Icon(Icons.add_comment_outlined,
                size: 18, color: kCueInkSecondary),
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }

  Widget _conversation() {
    if (_loadingHistory) {
      return const Center(child: CircularProgressIndicator());
    }
    final isEmpty = _messages.isEmpty && !_streaming;
    return ListView(
      controller: _scrollCtrl,
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      children: [
        if (isEmpty) _emptyBriefing(),
        for (final m in _messages) _messageBubble(m),
        if (_streaming) _streamingBubble(),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(_error!,
              style: CueTypeV3.body(color: kCueAmberDeep)
                  .copyWith(fontSize: 12.5)),
        ],
        if (_threads.isNotEmpty) ...[
          const SizedBox(height: 24),
          _threadListInline(),
        ],
      ],
    );
  }

  Widget _emptyBriefing() {
    final greeting = _isClientScoped
        ? 'What\'s on your mind about ${widget.clientName}?'
        : 'What would you like to think through on this goal?';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            greeting,
            style: TextStyle(
              fontFamily: 'Iowan Old Style',
              fontFamilyFallback: const ['Georgia', 'Charter', 'serif'],
              fontSize: 22,
              fontStyle: FontStyle.italic,
              letterSpacing: -0.11, // -0.005em × 22
              color: kCueInk,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            _isClientScoped
                ? 'Cue knows the chart. Ask about anything — '
                    'patterns across sessions, where to focus next, '
                    'parent communication, evidence to cite.'
                : 'Cue knows the goal anchor. Ask about framework '
                    'fit, calibration, or how to apply this STG '
                    'in a session.',
            style: CueTypeV3.body(color: kCueInkSecondary)
                .copyWith(fontSize: 13.5, height: 1.6),
          ),
        ],
      ),
    );
  }

  Widget _messageBubble(ReasoningMessage m) {
    final isUser = m.role == 'user';
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Align(
        alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: isUser ? kCueInk : kCuePaper,
              borderRadius: BorderRadius.circular(12),
            ),
            child: SelectableText(
              m.content,
              style: TextStyle(
                fontFamily: 'Inter',
                fontFamilyFallback: const ['system-ui', 'sans-serif'],
                fontSize: 13.5,
                fontWeight: FontWeight.w400,
                letterSpacing: -0.0675,
                height: 1.7,
                color: isUser ? kCueSurfaceWhite : kCueInk,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _streamingBubble() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Align(
        alignment: Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: kCuePaper,
              borderRadius: BorderRadius.circular(12),
            ),
            child: _streamingText.isEmpty
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      _PulseDot(),
                      SizedBox(width: 4),
                      _PulseDot(delayMs: 160),
                      SizedBox(width: 4),
                      _PulseDot(delayMs: 320),
                    ],
                  )
                : Text(
                    _streamingText,
                    style: const TextStyle(
                      fontFamily: 'Inter',
                      fontFamilyFallback: ['system-ui', 'sans-serif'],
                      fontSize: 13.5,
                      letterSpacing: -0.0675,
                      height: 1.7,
                      color: kCueInk,
                    ),
                  ),
          ),
        ),
      ),
    );
  }

  Widget _threadListInline() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: const BoxDecoration(
        border: Border(
          top: BorderSide(color: kCueBorder, width: 0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Text(
              'Earlier threads',
              style: CueTypeV3.dataEyebrow(color: kCueInkTertiary)
                  .copyWith(fontSize: 9.5, letterSpacing: 9.5 * 0.16),
            ),
          ),
          for (final t in _threads) _threadRow(t),
        ],
      ),
    );
  }

  Widget _threadRow(ReasoningThread t) {
    final isSelected = t.id == _threadId;
    final isGoalScoped = t.ltgId != null || t.stgId != null;
    final dotColor = isGoalScoped ? kCueAmber : kCueOlive;
    final title = (t.title?.isNotEmpty == true)
        ? t.title!
        : (isGoalScoped ? 'Goal-scoped thread' : 'Client thread');
    return InkWell(
      onTap: () => _switchThread(t),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? kCuePaper : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: dotColor,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                title,
                overflow: TextOverflow.ellipsis,
                style: CueTypeV3.body(color: kCueInk)
                    .copyWith(fontSize: 13, fontWeight: FontWeight.w500),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              _shortDate(t.updatedAt),
              style: CueTypeV3.body(color: kCueInkTertiary)
                  .copyWith(fontSize: 11.5),
            ),
          ],
        ),
      ),
    );
  }

  String _shortDate(DateTime d) {
    const months = [
      '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${d.day} ${months[d.month]}';
  }

  Widget _inputDock() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: const BoxDecoration(
        color: kCueSurfaceWhite,
        border: Border(
          top: BorderSide(color: kCueBorder, width: 0.5),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: kCueSurfaceWhite,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: kCueBorder, width: 0.5),
              ),
              padding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 8),
              child: TextField(
                controller: _inputCtrl,
                focusNode:  _inputFocus,
                minLines:   1,
                maxLines:   6,
                onSubmitted: (_) => _send(),
                style: CueTypeV3.body(color: kCueInk)
                    .copyWith(fontSize: 13.5, height: 1.4),
                decoration: InputDecoration(
                  isCollapsed: true,
                  border:      InputBorder.none,
                  hintText:    'Ask Cue…',
                  hintStyle:   CueTypeV3.body(color: kCueInkTertiary)
                      .copyWith(fontSize: 13.5),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          IconButton(
            tooltip: 'Send',
            onPressed: _streaming ? null : _send,
            icon: Icon(
              Icons.arrow_upward_rounded,
              size: 20,
              color: _streaming ? kCueInkTertiary : kCueAmber,
            ),
          ),
        ],
      ),
    );
  }
}

class _PulseDot extends StatefulWidget {
  final int delayMs;
  const _PulseDot({this.delayMs = 0});
  @override
  State<_PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<_PulseDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    Future<void>.delayed(Duration(milliseconds: widget.delayMs), () {
      if (mounted) _ctrl.repeat(reverse: true);
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween<double>(begin: 0.3, end: 1.0).animate(_ctrl),
      child: Container(
        width: 5,
        height: 5,
        decoration: const BoxDecoration(
          color: kCueInkTertiary,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}
