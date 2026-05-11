// lib/widgets/cue_popup.dart
//
// Phase 5.3 Round A.2 — floating Cue popup, summoned via ⌘K, the
// HUD strip click, or the sidebar pulse tap. The popup is the unified
// chat surface (briefing + chat + threads + input), housed in a
// ~360×540 floating panel anchored at the bottom-right of the
// workspace. Minimizable; Esc + click-outside close.
//
// Derives the state machine + AskCueService interactions from the
// retired AskCuePanel (Phase 5.1+5.2); the popup is its post-retirement
// home. Typography + sizing tightened for the smaller surface: briefing
// headline 22→17 Iowan italic, thread list capped at 3.
//
// Theme: all surfaces resolve via CueColorsResolved.of(context) so the
// popup renders correctly in the Phase 5.3 dark default (and survives
// the toggle to light). Edge polish per spec: inset highlight gradient
// at top, ring-shadowed pulse, accent glow on the send button.

import 'dart:async';

import 'package:flutter/material.dart';

import '../models/reasoning_message.dart';
import '../models/reasoning_thread.dart';
import '../services/ask_cue_service.dart';
import '../theme/cue_color_scheme.dart';

/// Dimensions of the floating popup. Caller positions the popup; these
/// are exported so the caller can compute placement constraints.
const double kCuePopupWidth  = 360;
const double kCuePopupHeight = 540;

class CuePopup extends StatefulWidget {
  final String clientId;
  final String clientName;

  /// Optional goal anchor. Non-null = goal-scoped citations (Phase 5.4+
  /// migration of Edit Goal). v1 of Phase 5.3 only Profile calls with
  /// null (client-scoped).
  final String? ltgId;
  final String? stgId;

  /// Fires when the SLP minimizes the popup (header X, Esc, click-outside).
  final VoidCallback onMinimize;

  /// When true, the input gets focus on first build — used when ⌘K
  /// triggers the popup open. False when the popup auto-opens on a
  /// fresh signal (focus would steal from the SLP's current task).
  final bool autoFocusInput;

  const CuePopup({
    super.key,
    required this.clientId,
    required this.clientName,
    required this.onMinimize,
    this.ltgId,
    this.stgId,
    this.autoFocusInput = true,
  });

  @override
  State<CuePopup> createState() => _CuePopupState();
}

class _CuePopupState extends State<CuePopup>
    with SingleTickerProviderStateMixin {
  final _service    = AskCueService.instance;
  final _inputCtrl  = TextEditingController();
  final _scrollCtrl = ScrollController();
  final _inputFocus = FocusNode();

  String? _threadId;
  List<ReasoningThread> _threads = const [];
  final List<ReasoningMessage> _messages = [];
  bool _loadingHistory = true;
  bool _sending        = false;
  bool _showAllThreads = false;
  String? _error;

  // Streaming buffer for in-flight assistant response.
  String _streamingText = '';
  bool   _streaming     = false;
  StreamSubscription<String>? _streamSub;

  bool get _isClientScoped =>
      widget.ltgId == null && widget.stgId == null;

  @override
  void initState() {
    super.initState();
    _bootstrap();
    if (widget.autoFocusInput) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _inputFocus.requestFocus();
      });
    }
  }

  @override
  void dispose() {
    _streamSub?.cancel();
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    _inputFocus.dispose();
    super.dispose();
  }

  // ── Service interaction ──────────────────────────────────────────────

  Future<void> _bootstrap() async {
    try {
      final threads =
          await _service.listThreads(clientId: widget.clientId);
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

    final tempUser = ReasoningMessage(
      id:            'temp-${DateTime.now().microsecondsSinceEpoch}',
      threadId:      _threadId ?? '',
      role:          'user',
      content:       text,
      citations:     const [],
      frameworkIds:  const [],
      appliedToGoal: false,
      createdAt:     DateTime.now(),
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

  // ── Build ────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final cue = CueColorsResolved.of(context);
    return Material(
      type: MaterialType.transparency,
      child: Container(
        width:  kCuePopupWidth,
        height: kCuePopupHeight,
        decoration: BoxDecoration(
          color: cue.bgCard,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: cue.borderEmphasis, width: 0.5),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(
                  alpha: cue.isDark ? 0.55 : 0.20),
              blurRadius: 28,
              offset: const Offset(0, 12),
            ),
          ],
          // Edge polish — hairline highlight on top edge suggests light
          // from above. Dark register only; light register has its own
          // warm-paper register that doesn't read with a top highlight.
          gradient: cue.isDark
              ? LinearGradient(
                  begin: Alignment.topCenter,
                  end:   Alignment.center,
                  colors: [
                    Colors.white.withValues(alpha: 0.025),
                    cue.bgCard,
                  ],
                  stops: const [0.0, 0.05],
                )
              : null,
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _popupHeader(cue),
            Expanded(child: _conversation(cue)),
            _inputDock(cue),
          ],
        ),
      ),
    );
  }

  Widget _popupHeader(CueColorsResolved cue) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 4, 10),
      decoration: BoxDecoration(
        color: cue.bgCard,
        border: Border(
          bottom: BorderSide(color: cue.border, width: 0.5),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: _streaming ? cue.amber : cue.olive,
              shape: BoxShape.circle,
              boxShadow: cue.isDark
                  ? [
                      BoxShadow(
                        color: (_streaming ? cue.amber : cue.olive)
                            .withValues(alpha: 0.2),
                        spreadRadius: 0.5,
                      ),
                    ]
                  : null,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            _streaming ? 'CUE · THINKING' : 'CUE · READY',
            style: TextStyle(
              fontFamily: 'JetBrains Mono',
              fontFamilyFallback: const ['monospace'],
              fontSize: 9.5,
              fontWeight: FontWeight.w600,
              letterSpacing: 9.5 * 0.18,
              color: cue.amber,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _isClientScoped
                  ? 'Ask Cue · ${widget.clientName}'
                  : 'Ask Cue · this goal',
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: 'Inter',
                fontFamilyFallback: const ['system-ui', 'sans-serif'],
                fontSize: 12,
                color: cue.textBody,
              ),
            ),
          ),
          IconButton(
            tooltip: 'New thread',
            onPressed: _streaming ? null : _newThread,
            icon: Icon(Icons.add_comment_outlined,
                size: 17, color: cue.textMuted),
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
          IconButton(
            tooltip: 'Minimize',
            onPressed: widget.onMinimize,
            icon: Icon(Icons.remove_rounded,
                size: 18, color: cue.textMuted),
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
        ],
      ),
    );
  }

  Widget _conversation(CueColorsResolved cue) {
    if (_loadingHistory) {
      return Center(
        child: SizedBox(
          width: 24, height: 24,
          child: CircularProgressIndicator(
            strokeWidth: 1.5,
            color: cue.amber,
          ),
        ),
      );
    }
    final isEmpty = _messages.isEmpty && !_streaming;
    final visibleThreads = _showAllThreads
        ? _threads
        : _threads.take(3).toList();
    final hiddenCount = _threads.length - visibleThreads.length;

    return ListView(
      controller: _scrollCtrl,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      children: [
        if (isEmpty) _emptyBriefing(cue),
        for (final m in _messages) _messageBubble(m, cue),
        if (_streaming) _streamingBubble(cue),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(
            _error!,
            style: TextStyle(
              fontFamily: 'Inter',
              fontFamilyFallback: const ['system-ui', 'sans-serif'],
              fontSize: 12,
              color: cue.red,
            ),
          ),
        ],
        if (_threads.isNotEmpty) ...[
          const SizedBox(height: 20),
          _threadListInline(cue, visibleThreads, hiddenCount),
        ],
      ],
    );
  }

  Widget _emptyBriefing(CueColorsResolved cue) {
    final greeting = _isClientScoped
        ? "What's on your mind about ${widget.clientName}?"
        : 'What would you like to think through on this goal?';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Briefing headline — Iowan italic 17px (popup-resized from
          // panel's 22px). Cue's voice register.
          Text(
            greeting,
            style: TextStyle(
              fontFamily: 'Iowan Old Style',
              fontFamilyFallback: const ['Georgia', 'Charter', 'serif'],
              fontSize: 17,
              fontStyle: FontStyle.italic,
              letterSpacing: -0.085,
              color: cue.textPrimary,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            _isClientScoped
                ? 'Cue knows the chart. Ask about patterns across '
                    'sessions, where to focus next, parent communication, '
                    'evidence to cite.'
                : 'Cue knows the goal anchor. Ask about framework fit, '
                    'calibration, or how to apply this STG in a session.',
            style: TextStyle(
              fontFamily: 'Inter',
              fontFamilyFallback: const ['system-ui', 'sans-serif'],
              fontSize: 12.5,
              height: 1.55,
              color: cue.textBody,
            ),
          ),
        ],
      ),
    );
  }

  Widget _messageBubble(ReasoningMessage m, CueColorsResolved cue) {
    final isUser = m.role == 'user';
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Align(
        alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 300),
          child: Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: isUser
                  ? cue.amber.withValues(alpha: cue.isDark ? 0.22 : 0.15)
                  : cue.bgCardHover,
              borderRadius: BorderRadius.circular(10),
              border: isUser
                  ? Border.all(
                      color: cue.amber.withValues(alpha: 0.4), width: 0.5)
                  : Border.all(
                      color: cue.border, width: 0.5),
            ),
            child: SelectableText(
              m.content,
              style: TextStyle(
                fontFamily: 'Inter',
                fontFamilyFallback: const ['system-ui', 'sans-serif'],
                fontSize: 13,
                fontWeight: FontWeight.w400,
                letterSpacing: -0.065,
                height: 1.55,
                color: cue.textPrimary,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _streamingBubble(CueColorsResolved cue) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Align(
        alignment: Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 300),
          child: Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: cue.bgCardHover,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: cue.border, width: 0.5),
            ),
            child: _streamingText.isEmpty
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _PulseDot(color: cue.textMuted),
                      const SizedBox(width: 4),
                      _PulseDot(color: cue.textMuted, delayMs: 160),
                      const SizedBox(width: 4),
                      _PulseDot(color: cue.textMuted, delayMs: 320),
                    ],
                  )
                : Text(
                    _streamingText,
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontFamilyFallback: const ['system-ui', 'sans-serif'],
                      fontSize: 13,
                      letterSpacing: -0.065,
                      height: 1.55,
                      color: cue.textPrimary,
                    ),
                  ),
          ),
        ),
      ),
    );
  }

  Widget _threadListInline(
    CueColorsResolved cue,
    List<ReasoningThread> visible,
    int hiddenCount,
  ) {
    return Container(
      padding: const EdgeInsets.only(top: 10),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: cue.border, width: 0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Text(
              'EARLIER THREADS',
              style: TextStyle(
                fontFamily: 'JetBrains Mono',
                fontFamilyFallback: const ['monospace'],
                fontSize: 9.5,
                fontWeight: FontWeight.w600,
                letterSpacing: 9.5 * 0.16,
                color: cue.textMuted,
              ),
            ),
          ),
          for (final t in visible) _threadRow(t, cue),
          if (hiddenCount > 0)
            Padding(
              padding: const EdgeInsets.only(top: 4, left: 6),
              child: InkWell(
                onTap: () => setState(() => _showAllThreads = true),
                child: Text(
                  'See $hiddenCount more →',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontFamilyFallback: const ['system-ui', 'sans-serif'],
                    fontSize: 11.5,
                    color: cue.amber,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _threadRow(ReasoningThread t, CueColorsResolved cue) {
    final isSelected   = t.id == _threadId;
    final isGoalScoped = t.ltgId != null || t.stgId != null;
    final dotColor     = isGoalScoped ? cue.amber : cue.olive;
    final title = (t.title?.isNotEmpty == true)
        ? t.title!
        : (isGoalScoped ? 'Goal-scoped thread' : 'Client thread');
    return InkWell(
      onTap: () => _switchThread(t),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? cue.bgCardHover : Colors.transparent,
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
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontFamilyFallback: const ['system-ui', 'sans-serif'],
                  fontSize: 12.5,
                  fontWeight: FontWeight.w500,
                  color: cue.textPrimary,
                ),
              ),
            ),
            const SizedBox(width: 6),
            Text(
              _shortDate(t.updatedAt),
              style: TextStyle(
                fontFamily: 'Inter',
                fontFamilyFallback: const ['system-ui', 'sans-serif'],
                fontSize: 11,
                color: cue.textMuted,
              ),
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

  Widget _inputDock(CueColorsResolved cue) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 12),
      decoration: BoxDecoration(
        color: cue.bgCard,
        border: Border(
          top: BorderSide(color: cue.border, width: 0.5),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: cue.bgInput,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: cue.border, width: 0.5),
              ),
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: TextField(
                controller: _inputCtrl,
                focusNode:  _inputFocus,
                minLines:   1,
                maxLines:   5,
                onSubmitted: (_) => _send(),
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontFamilyFallback: const ['system-ui', 'sans-serif'],
                  fontSize: 13,
                  height: 1.35,
                  color: cue.textPrimary,
                ),
                decoration: InputDecoration(
                  isCollapsed: true,
                  border:      InputBorder.none,
                  hintText:    'Ask Cue…',
                  hintStyle: TextStyle(
                    fontFamily: 'Inter',
                    fontFamilyFallback: const ['system-ui', 'sans-serif'],
                    fontSize: 13,
                    color: cue.textMuted,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          // Send button — accent glow on dark per edge polish spec.
          Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: !_streaming && cue.isDark
                  ? [
                      BoxShadow(
                        color: cue.amber.withValues(alpha: 0.3),
                        blurRadius: 4,
                      ),
                    ]
                  : null,
            ),
            child: IconButton(
              tooltip: 'Send',
              onPressed: _streaming ? null : _send,
              icon: Icon(
                Icons.arrow_upward_rounded,
                size: 19,
                color: _streaming ? cue.textMuted : cue.amber,
              ),
              padding: EdgeInsets.zero,
              constraints:
                  const BoxConstraints(minWidth: 36, minHeight: 36),
            ),
          ),
        ],
      ),
    );
  }
}

class _PulseDot extends StatefulWidget {
  final int   delayMs;
  final Color color;
  const _PulseDot({this.delayMs = 0, required this.color});

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
        decoration: BoxDecoration(
          color: widget.color,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}
