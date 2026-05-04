// lib/widgets/cue_reasoning_panel.dart
//
// Phase 4.0.7.20d — Cue Reasoning V1 slide-over panel.
//
// Three zones, top to bottom:
//   1. Context strip — eyebrow, subtitle, scrollable domain chips.
//   2. Conversation thread — user + assistant message bubbles, citation
//      chips, "Cite in rationale" / "Apply revision" / "Show frameworks"
//      affordances on assistant messages.
//   3. Input area — three quick-prompt chips + multi-line textarea +
//      send button.
//
// Clinical reasoning partner — calls the reasoning-respond edge function
// via CueReasoningService, surfaces evidence-grounded responses with
// EBP framework citations.

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../models/reasoning_message.dart';
import '../models/reasoning_thread.dart';
import '../services/cue_reasoning_service.dart';

// ── Tokens (local — match the existing CueStudy navy-dark register) ─────
const Color _navyDark   = Color(0xFF0E1B2C);
const Color _csAmber    = Color(0xFFF5C16E);
const Color _csAmberHi  = Color(0xFFD9982E);
const Color _parchment  = Color(0xFFF3ECDE);
const Color _ink        = Color(0xFF0B1B33);
const Color _inkGhost   = Color(0xFF6B7690);
const Color _teal       = Color(0xFF1F8870);

/// The 14 domains supported by the reasoning_threads schema enum, in
/// the order specified by the 4.0.7.20d task.
const List<String> kReasoningDomains = [
  'pediatric-language',
  'autism-developmental',
  'speech-sound-disorders',
  'pediatric-motor-speech',
  'fluency',
  'voice',
  'adult-language-cognitive',
  'adult-motor-speech',
  'dysphagia',
  'aac',
  'social-pragmatic',
  'hearing-aural-rehab',
  'literacy',
  'multilingual',
];

String _domainLabel(String code) {
  final parts = code.split('-');
  return parts
      .map((p) => p.isEmpty ? '' : '${p[0].toUpperCase()}${p.substring(1)}')
      .join(' ');
}

class CueReasoningPanel extends StatefulWidget {
  final String  clientId;
  final String? ltgId;
  final String? stgId;
  final List<String> initialDomains;
  final ValueChanged<String>? onApplyRevision;
  final ValueChanged<String>? onCiteInRationale;

  const CueReasoningPanel({
    super.key,
    required this.clientId,
    this.ltgId,
    this.stgId,
    this.initialDomains = const [],
    this.onApplyRevision,
    this.onCiteInRationale,
  });

  @override
  State<CueReasoningPanel> createState() => _CueReasoningPanelState();
}

class _CueReasoningPanelState extends State<CueReasoningPanel> {
  final _service          = CueReasoningService.instance;
  final _inputController  = TextEditingController();
  final _scrollController = ScrollController();

  String? _threadId;
  late List<String> _domainsActive;
  final List<ReasoningMessage> _messages   = [];
  final Map<String, FrameworkCitation> _frameworkCache = {};
  String?  _suggestedRevision;
  bool     _sending      = false;
  String?  _errorMessage;

  @override
  void initState() {
    super.initState();
    _domainsActive = List<String>.from(widget.initialDomains);
    _hydrateExistingThread();
  }

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _hydrateExistingThread() async {
    if (widget.ltgId == null && widget.stgId == null) return;
    final existing = await _service.findThread(
      clientId: widget.clientId,
      ltgId:    widget.ltgId,
      stgId:    widget.stgId,
    );
    if (existing == null || !mounted) return;
    final history = await _service.loadThreadHistory(existing.id);
    if (!mounted) return;
    setState(() {
      _threadId  = existing.id;
      _messages
        ..clear()
        ..addAll(history);
      if (existing.domainsActive.isNotEmpty) {
        _domainsActive = List<String>.from(existing.domainsActive);
      }
    });
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve:    Curves.easeOut,
      );
    });
  }

  Future<void> _send() async {
    final text = _inputController.text.trim();
    if (text.isEmpty || _sending) return;

    final localUser = ReasoningMessage(
      id:        'local-${DateTime.now().millisecondsSinceEpoch}',
      threadId:  _threadId ?? '',
      role:      'user',
      content:   text,
      citations: const [],
      frameworkIds: const [],
      appliedToGoal: false,
      createdAt: DateTime.now(),
    );

    setState(() {
      _messages.add(localUser);
      _inputController.clear();
      _sending      = true;
      _errorMessage = null;
    });
    _scrollToBottom();

    try {
      final result = await _service.sendMessage(
        threadId:       _threadId,
        clientId:       widget.clientId,
        ltgId:          widget.ltgId,
        stgId:          widget.stgId,
        userMessage:    text,
        domainsActive:  _domainsActive.isEmpty ? null : _domainsActive,
      );
      if (!mounted) return;
      setState(() {
        _threadId = result.threadId;
        _messages.addAll(result.messages);
        _suggestedRevision = result.suggestedRevision;
        for (final f in result.citedFrameworks) {
          _frameworkCache[f.shortCode] = f;
        }
        _sending = false;
      });
      _scrollToBottom();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _errorMessage = e is CueReasoningException
            ? e.toString()
            : 'Cue Reasoning hit an error. Try again.';
      });
    }
  }

  void _toggleDomain(String code) {
    setState(() {
      if (_domainsActive.contains(code)) {
        _domainsActive.remove(code);
      } else {
        _domainsActive.add(code);
      }
    });
  }

  void _setQuickPrompt(String text) {
    _inputController.text = text;
    _inputController.selection = TextSelection.fromPosition(
        TextPosition(offset: text.length));
  }

  // ── Build ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Container(
      color: _navyDark,
      child: Column(
        children: [
          _buildContextStrip(),
          Expanded(child: _buildConversation()),
          _buildInput(),
        ],
      ),
    );
  }

  // ── Zone 1: context strip ──────────────────────────────────────────────
  Widget _buildContextStrip() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0x1AFFFFFF))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'CUE REASONING',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: _csAmber,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'A clinical reasoning partner grounded in evidence',
            style: TextStyle(
              fontSize: 12,
              fontStyle: FontStyle.italic,
              color: Color(0x80FFFFFF),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 28,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: kReasoningDomains.length,
              separatorBuilder: (_, _) => const SizedBox(width: 6),
              itemBuilder: (_, i) {
                final code     = kReasoningDomains[i];
                final selected = _domainsActive.contains(code);
                return GestureDetector(
                  onTap: () => _toggleDomain(code),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: selected
                          ? _teal.withValues(alpha: 0.85)
                          : Colors.transparent,
                      border: Border.all(
                        color: selected
                            ? _teal
                            : const Color(0x33FFFFFF),
                        width: 1,
                      ),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Text(
                      _domainLabel(code),
                      style: TextStyle(
                        fontSize: 11,
                        color: selected
                            ? Colors.white
                            : const Color(0xCCFFFFFF),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // ── Zone 2: conversation ───────────────────────────────────────────────
  Widget _buildConversation() {
    if (_messages.isEmpty && !_sending) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 32),
          child: Text(
            'Ask about your goal — Cue Reasoning grounds in evidence, not opinion.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: Color(0x80FFFFFF),
              fontStyle: FontStyle.italic,
              height: 1.55,
            ),
          ),
        ),
      );
    }
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      itemCount: _messages.length + (_sending ? 1 : 0) + (_errorMessage != null ? 1 : 0),
      itemBuilder: (_, i) {
        if (i < _messages.length) return _buildMessage(_messages[i]);
        if (_sending && i == _messages.length) return _buildTypingIndicator();
        return _buildErrorBanner();
      },
    );
  }

  Widget _buildMessage(ReasoningMessage m) {
    final isUser = m.role == 'user';
    final bubble = Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      constraints: BoxConstraints(
        maxWidth: MediaQuery.of(context).size.width * 0.78,
      ),
      decoration: BoxDecoration(
        color: isUser ? _parchment : const Color(0xFF152436),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _renderContent(m, isUser: isUser),
          // Phase 4.0.7.20k — citation chip wrap below assistant
          // messages. The markdown body renders raw `[framework: …]`
          // tokens as literal text inside the bubble; this chip Wrap
          // surfaces them as clickable affordances right below.
          // Option B per the 4.0.7.20k spec — inline chip-positioning
          // polish is 4.0.7.20l work.
          if (!isUser && m.frameworkIds.isNotEmpty) ...[
            const SizedBox(height: 6),
            _buildCitationChipWrap(m.frameworkIds),
          ],
          if (!isUser) ...[
            const SizedBox(height: 8),
            _buildAssistantActions(m),
          ],
        ],
      ),
    );
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: bubble,
    );
  }

  /// Render the message body. User messages render as plain selectable
  /// rich text (users don't write markdown). Assistant messages render
  /// via flutter_markdown so the model's bold/italic/lists/headers/code
  /// blocks land styled instead of as raw asterisks. Citation chips
  /// surface separately below the bubble — the markdown body shows the
  /// raw `[framework: …]` tokens as plain text.
  Widget _renderContent(ReasoningMessage m, {required bool isUser}) {
    if (isUser) {
      return SelectableText(
        m.content,
        style: const TextStyle(
          fontSize: 13,
          color: _ink,
          height: 1.6,
        ),
      );
    }
    const baseColor = Color(0xEBFFFFFF); // white at ~0.92α
    final styleSheet = MarkdownStyleSheet(
      p: const TextStyle(
        color: baseColor,
        fontSize: 13,
        height: 1.6,
      ),
      strong: const TextStyle(
        color: Colors.white,
        fontWeight: FontWeight.w600,
      ),
      em: const TextStyle(
        color: baseColor,
        fontStyle: FontStyle.italic,
      ),
      listBullet: const TextStyle(
        color: baseColor,
        fontSize: 13,
        height: 1.6,
      ),
      h1: const TextStyle(
          color: Colors.white, fontSize: 17, fontWeight: FontWeight.w700,
          height: 1.4),
      h2: const TextStyle(
          color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700,
          height: 1.4),
      h3: const TextStyle(
          color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600,
          height: 1.4),
      code: TextStyle(
        color: _csAmber,
        fontFamily: 'monospace',
        fontSize: 12,
        backgroundColor: const Color(0xFF0A1422),
      ),
      codeblockDecoration: BoxDecoration(
        color: const Color(0xFF0A1422),
        borderRadius: BorderRadius.circular(6),
      ),
      codeblockPadding: const EdgeInsets.all(10),
      blockquote: TextStyle(
        color: Colors.white.withValues(alpha: 0.65),
        fontStyle: FontStyle.italic,
      ),
      blockquoteDecoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        border: Border(
          left: BorderSide(
              color: _csAmber.withValues(alpha: 0.5), width: 2),
        ),
      ),
      a: const TextStyle(
        color: _csAmber,
        decoration: TextDecoration.underline,
      ),
      // Tighten paragraph spacing so the markdown body sits flush
      // inside the existing bubble padding.
      pPadding: EdgeInsets.zero,
      h1Padding: const EdgeInsets.only(top: 4, bottom: 2),
      h2Padding: const EdgeInsets.only(top: 4, bottom: 2),
      h3Padding: const EdgeInsets.only(top: 4, bottom: 2),
    );
    return MarkdownBody(
      data:           m.content,
      styleSheet:     styleSheet,
      softLineBreak:  true,
      selectable:     true,
      shrinkWrap:     true,
    );
  }

  /// Phase 4.0.7.20k — chip Wrap rendered below an assistant message
  /// for each cited framework short_code. Reuses the existing
  /// _buildCitationChip widget so taps still pop the framework-detail
  /// dialog with the cached metadata.
  Widget _buildCitationChipWrap(List<String> codes) {
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: [
        for (final code in codes) _buildCitationChip(code.toLowerCase()),
      ],
    );
  }

  Widget _buildCitationChip(String code) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: GestureDetector(
        onTap: () => _showFrameworkDialog(code),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
          decoration: BoxDecoration(
            color: _csAmber.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
                color: _csAmber.withValues(alpha: 0.4), width: 0.5),
          ),
          child: Text(
            code,
            style: const TextStyle(
              fontSize: 11,
              color: _csAmber,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }

  void _showFrameworkDialog(String code) {
    final f = _frameworkCache[code];
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(f?.name ?? code),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (f?.description != null)
              Text(f!.description!,
                  style: const TextStyle(fontSize: 13, height: 1.5)),
            if (f?.keyAuthors.isNotEmpty == true) ...[
              const SizedBox(height: 12),
              Text('Authors: ${f!.keyAuthors.join(", ")}',
                  style: const TextStyle(fontSize: 12, color: _inkGhost)),
            ],
            if (f?.evidenceLevel != null) ...[
              const SizedBox(height: 6),
              _buildEvidenceLevel(f!.evidenceLevel!),
            ],
            if (f?.whenToUse != null) ...[
              const SizedBox(height: 12),
              const Text('When to use',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: _inkGhost,
                      letterSpacing: 0.5)),
              const SizedBox(height: 4),
              Text(f!.whenToUse!,
                  style: const TextStyle(fontSize: 13, height: 1.5)),
            ],
            if (f == null) ...[
              const Text(
                'Framework metadata not loaded for this citation. '
                "Send another message to refresh the panel's cache.",
                style: TextStyle(fontSize: 12, color: _inkGhost),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _buildEvidenceLevel(String level) {
    Color color;
    switch (level.toLowerCase()) {
      case 'high':       color = const Color(0xFF1F8870); break;
      case 'moderate':   color = const Color(0xFFD9982E); break;
      case 'emerging':   color = const Color(0xFFE07A4D); break;
      case 'historical': color = const Color(0xFF6B7690); break;
      default:           color = const Color(0xFF6B7690);
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        'Evidence: $level',
        style: TextStyle(
          fontSize: 11,
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildAssistantActions(ReasoningMessage m) {
    final hasRevision = _suggestedRevision != null &&
        _suggestedRevision!.trim().isNotEmpty &&
        _messages.isNotEmpty &&
        _messages.last.id == m.id;
    return Wrap(
      spacing: 6,
      runSpacing: 4,
      children: [
        _actionPill(
          label: 'Cite in rationale',
          onTap: widget.onCiteInRationale == null
              ? null
              : () async {
                  widget.onCiteInRationale!.call(m.content);
                  await _service.applyMessageToGoal(
                    messageId: m.id,
                    goalId:    widget.ltgId ?? widget.stgId ?? '',
                    fieldName: 'evidence_rationale',
                    contentToInject: m.content,
                  );
                },
        ),
        if (hasRevision)
          _actionPill(
            label: 'Apply revision',
            emphasized: true,
            onTap: widget.onApplyRevision == null
                ? null
                : () async {
                    widget.onApplyRevision!.call(_suggestedRevision!);
                    await _service.applyMessageToGoal(
                      messageId: m.id,
                      goalId:    widget.ltgId ?? widget.stgId ?? '',
                      fieldName: 'goal_text',
                      contentToInject: _suggestedRevision!,
                    );
                  },
          ),
        if (m.frameworkIds.isNotEmpty)
          _actionPill(
            label: 'Show frameworks (${m.frameworkIds.length})',
            onTap: () => _showFrameworksList(m),
          ),
      ],
    );
  }

  Widget _actionPill({
    required String label,
    required VoidCallback? onTap,
    bool emphasized = false,
  }) {
    final disabled = onTap == null;
    final bg = emphasized
        ? _csAmber.withValues(alpha: 0.25)
        : const Color(0x1AFFFFFF);
    final fg = emphasized ? _csAmber : Colors.white.withValues(alpha: 0.85);
    return GestureDetector(
      onTap: disabled ? null : onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: disabled ? bg.withValues(alpha: 0.4) : bg,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: disabled ? fg.withValues(alpha: 0.4) : fg,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }

  void _showFrameworksList(ReasoningMessage m) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('FRAMEWORKS CITED',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                    color: _inkGhost,
                  )),
              const SizedBox(height: 12),
              ...m.frameworkIds.map((code) {
                final f = _frameworkCache[code];
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(f?.name ?? code,
                          style: const TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w600)),
                      if (f?.keyAuthors.isNotEmpty == true)
                        Text(f!.keyAuthors.join(', '),
                            style: const TextStyle(
                                fontSize: 12, color: _inkGhost)),
                      if (f?.evidenceLevel != null) ...[
                        const SizedBox(height: 4),
                        _buildEvidenceLevel(f!.evidenceLevel!),
                      ],
                    ],
                  ),
                );
              }),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTypingIndicator() {
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: const Color(0xFF152436),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: const [
              _TypingDot(delay: 0),
              SizedBox(width: 4),
              _TypingDot(delay: 150),
              SizedBox(width: 4),
              _TypingDot(delay: 300),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildErrorBanner() {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFEF4444).withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        _errorMessage ?? '',
        style: const TextStyle(
          fontSize: 12,
          color: Color(0xFFFCA5A5),
        ),
      ),
    );
  }

  // ── Zone 3: input ──────────────────────────────────────────────────────
  Widget _buildInput() {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Color(0x1AFFFFFF))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 28,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                _quickPromptChip('Why this goal?',
                    "Why am I picking this goal? What's the clinical defense?"),
                const SizedBox(width: 6),
                _quickPromptChip('Check against EBP',
                    'Is this goal aligned with the framework I named? What does the evidence say?'),
                const SizedBox(width: 6),
                _quickPromptChip('Stress-test this STG',
                    'Does my STG measure what I think it measures? Stress-test it.'),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: TextField(
                  controller: _inputController,
                  enabled: !_sending,
                  maxLines: 4,
                  minLines: 2,
                  style: const TextStyle(
                      fontSize: 13, color: Colors.white, height: 1.5),
                  decoration: InputDecoration(
                    hintText: 'Ask Cue Reasoning…',
                    hintStyle: const TextStyle(
                        fontSize: 13, color: Color(0x80FFFFFF)),
                    filled: true,
                    fillColor: const Color(0xFF152436),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(
                          color: Colors.white.withValues(alpha: 0.10)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(
                          color: _csAmberHi, width: 1.5),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(
                          color: Colors.white.withValues(alpha: 0.10)),
                    ),
                  ),
                  onSubmitted: (_) => _send(),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: _sending ? null : _send,
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: _sending
                        ? _csAmberHi.withValues(alpha: 0.4)
                        : _csAmberHi,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.send_rounded,
                      color: _navyDark, size: 18),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _quickPromptChip(String label, String prompt) {
    return GestureDetector(
      onTap: _sending ? null : () => _setQuickPrompt(prompt),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: const Color(0x1AFFFFFF),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            color: Color(0xCCFFFFFF),
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

// ── Typing indicator ────────────────────────────────────────────────────
class _TypingDot extends StatefulWidget {
  final int delay;
  const _TypingDot({required this.delay});
  @override
  State<_TypingDot> createState() => _TypingDotState();
}

class _TypingDotState extends State<_TypingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  Timer? _startTimer;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _startTimer = Timer(Duration(milliseconds: widget.delay), () {
      if (mounted) _ctrl.repeat();
    });
  }

  @override
  void dispose() {
    _startTimer?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, _) {
        final t = _ctrl.value;
        final bell = (t < 0.5) ? t * 2 : (1 - t) * 2;
        return Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(
            color: Colors.white.withValues(
                alpha: 0.25 + 0.5 * bell),
            shape: BoxShape.circle,
          ),
        );
      },
    );
  }
}
