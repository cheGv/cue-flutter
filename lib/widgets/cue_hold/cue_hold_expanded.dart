// lib/widgets/cue_hold/cue_hold_expanded.dart
//
// Phase 4.1.3 — EXPANDED state. The Hold pill morphs into an inline
// chat surface anchored at the top-right of the viewport.
//
// Surface:
//   • 380px wide on desktop, viewport-width on mobile (<768px)
//   • Max height 480px; flexes shorter when content is short
//   • Header: cuttlefish + "Cue Study" + minimize + close
//   • Body: scrollable chat (system intro at top, prior messages below)
//   • Footer: text input + mic icon + send arrow
//
// Conversation state lives in CueHoldController. The widget reads
// controller.conversation on every rebuild; sends user input to
// AskCueService.sendMessage and appends both turns back to the
// controller. Streaming response renders chunk-by-chunk via the
// service's textStream.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../services/ask_cue_service.dart';
import '../../theme/cue_color_scheme.dart';
import '../../theme/cue_text_styles.dart';
import 'cue_hold_state.dart';

class CueHoldExpanded extends StatefulWidget {
  final CueHoldController controller;
  final bool isMobile;
  const CueHoldExpanded({
    super.key,
    required this.controller,
    required this.isMobile,
  });

  @override
  State<CueHoldExpanded> createState() => _CueHoldExpandedState();
}

class _CueHoldExpandedState extends State<CueHoldExpanded> {
  static const Color _amber = Color(0xFFF5C778);

  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();
  final FocusNode _focus = FocusNode();
  bool _hasText = false;
  bool _sending = false;
  String _streamingAssistant = ''; // chunks accumulate here

  @override
  void initState() {
    super.initState();
    _input.addListener(_onInputChange);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    _input.removeListener(_onInputChange);
    _input.dispose();
    _scroll.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onInputChange() {
    final next = _input.text.trim().isNotEmpty;
    if (next != _hasText) setState(() => _hasText = next);
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _sending) return;

    final controller = widget.controller;
    if (controller.clientId.isEmpty) return;

    setState(() {
      _sending = true;
      _streamingAssistant = '';
    });
    // Phase 4.1.4 — flip the Hold pill (visible at the top of the
    // screen) to THINKING while the response is in flight. The chat
    // overlay stays mounted because `state` isn't changed; only the
    // independent thinking flag is toggled.
    controller.setThinkingInExpanded(true);

    // Optimistically append the user's message.
    controller.appendChatMessage(
      CueHoldChatMessage(text: text, fromUser: true),
    );
    _input.clear();
    _scrollToBottom();

    try {
      final result = AskCueService.instance.sendMessage(
        clientId: controller.clientId,
        ltgId: controller.ltgAnchorId,
        stgId: controller.stgAnchorId,
        userMessage: text,
      );

      result.textStream.listen((chunk) {
        if (!mounted) return;
        setState(() => _streamingAssistant += chunk);
        _scrollToBottom();
      });

      final completion = await result.completion;
      if (!mounted) return;
      controller.appendChatMessage(
        CueHoldChatMessage(
          text: completion.assistantMessage.content,
          fromUser: false,
        ),
      );
      controller.setThinkingInExpanded(false);
      setState(() {
        _sending = false;
        _streamingAssistant = '';
      });
      _scrollToBottom();
    } catch (e) {
      if (!mounted) return;
      controller.appendChatMessage(
        CueHoldChatMessage(
          text: 'Cue couldn\'t respond just now. Try again in a moment.',
          fromUser: false,
        ),
      );
      controller.setThinkingInExpanded(false);
      setState(() {
        _sending = false;
        _streamingAssistant = '';
      });
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = CueChartPalette.of(context);
    final cue = CueColorsResolved.of(context);

    final width = widget.isMobile
        ? MediaQuery.of(context).size.width - 24
        : 380.0;

    return Material(
      color: Colors.transparent,
      child: Container(
        width: width,
        constraints: const BoxConstraints(maxHeight: 480),
        decoration: BoxDecoration(
          color: p.holdSurface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: p.holdBorder, width: 0.5),
          boxShadow: [
            BoxShadow(
              color: cue.isDark
                  ? const Color(0x66000000)
                  : const Color(0x26000000),
              offset: const Offset(0, 12),
              blurRadius: 48,
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _header(p, cue),
            Flexible(child: _body(cue)),
            _inputBar(p, cue),
          ],
        ),
      ),
    );
  }

  Widget _header(CueChartPalette p, CueColorsResolved cue) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: p.holdBorder, width: 0.5)),
      ),
      child: Row(
        children: [
          Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              color: _amber.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: SvgPicture.asset(
              'assets/brand/cue_mark.svg',
              width: 14,
              height: 14,
              colorFilter:
                  const ColorFilter.mode(_amber, BlendMode.srcIn),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            'Cue Study',
            style: GoogleFonts.dmSans(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: cue.textPrimary,
            ),
          ),
          const Spacer(),
          IconButton(
            onPressed: widget.controller.minimizeExpanded,
            icon: const Icon(Icons.minimize_rounded, size: 16),
            color: cue.textSecondary,
            tooltip: 'Minimize',
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.all(4),
            constraints: const BoxConstraints(
              minWidth: 28,
              minHeight: 28,
            ),
          ),
          IconButton(
            onPressed: widget.controller.closeExpanded,
            icon: const Icon(Icons.close_rounded, size: 16),
            color: cue.textSecondary,
            tooltip: 'Close',
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.all(4),
            constraints: const BoxConstraints(
              minWidth: 28,
              minHeight: 28,
            ),
          ),
        ],
      ),
    );
  }

  Widget _body(CueColorsResolved cue) {
    final messages = widget.controller.conversation;
    final intro = _resolveIntro(widget.controller);

    return ListView(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 6),
      children: [
        _systemMessage(intro.headline, intro.subtext, cue),
        for (final m in messages) ...[
          const SizedBox(height: 12),
          _chatBubble(m, cue),
        ],
        if (_sending && _streamingAssistant.isNotEmpty) ...[
          const SizedBox(height: 12),
          _chatBubble(
            CueHoldChatMessage(text: _streamingAssistant, fromUser: false),
            cue,
          ),
        ] else if (_sending) ...[
          const SizedBox(height: 12),
          _streamingPlaceholder(cue),
        ],
      ],
    );
  }

  /// Phase 4.1.4 B.6 — three-tier intro copy. The tier depends on what
  /// the controller knows: no context (Today / Clients / Settings),
  /// client-only (chart with no STG anchor), or STG (Think with Cue tap
  /// or open-while-focused). Tier 3 includes the STG body truncated to
  /// 80 chars.
  _IntroCopy _resolveIntro(CueHoldController c) {
    final clientName = c.clientName.trim();
    final firstName = clientName.isEmpty
        ? ''
        : clientName.split(RegExp(r'\s+')).first;

    if (clientName.isEmpty) {
      return const _IntroCopy(
        headline: "Hi — what's on your mind?",
        subtext:
            "I'm here to help you think through cases, plans, or anything clinical.",
      );
    }

    final hasStg = c.stgAnchorId != null && c.stgAnchorId!.isNotEmpty;
    if (!hasStg) {
      return _IntroCopy(
        headline:
            "Looking at $firstName's chart. What would you like to think through?",
        subtext:
            "I know the case anchor. Ask about goals, sessions, or treatment direction.",
      );
    }

    final bodyRaw = (c.stgBodyText ?? '').trim();
    final bodyTrunc = bodyRaw.length > 80
        ? '${bodyRaw.substring(0, 77)}…'
        : bodyRaw;
    final stgFragment =
        bodyTrunc.isEmpty ? "short-term goal" : "short-term goal — $bodyTrunc";
    return _IntroCopy(
      headline:
          "Looking at $firstName's $stgFragment. What would you like to think through?",
      subtext:
          "Cue knows the goal anchor. Ask about framework fit, calibration, or how to apply this STG in a session.",
    );
  }

  Widget _systemMessage(String headline, String subtext, CueColorsResolved cue) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: _amber.withValues(alpha: cue.isDark ? 0.08 : 0.06),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: _amber.withValues(alpha: 0.2),
          width: 0.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            headline,
            style: GoogleFonts.playfairDisplay(
              fontStyle: FontStyle.italic,
              fontWeight: FontWeight.w500,
              fontSize: 13,
              color: cue.textPrimary,
              height: 1.4,
            ),
          ),
          if (subtext.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              subtext,
              style: GoogleFonts.dmSans(
                fontSize: 11,
                color: cue.textSecondary,
                height: 1.45,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _chatBubble(CueHoldChatMessage m, CueColorsResolved cue) {
    final isUser = m.fromUser;
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: (widget.isMobile
                  ? MediaQuery.of(context).size.width - 48
                  : 320)
              .toDouble(),
        ),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: isUser
                ? cue.amber.withValues(alpha: cue.isDark ? 0.15 : 0.10)
                : cue.bgCard,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isUser
                  ? cue.amber.withValues(alpha: 0.3)
                  : cue.border,
              width: 0.5,
            ),
          ),
          child: Text(
            m.text,
            style: GoogleFonts.dmSans(
              fontSize: 13,
              height: 1.45,
              color: cue.textPrimary,
            ),
          ),
        ),
      ),
    );
  }

  Widget _streamingPlaceholder(CueColorsResolved cue) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Text(
          'Cue is thinking…',
          style: GoogleFonts.dmSans(
            fontSize: 12,
            fontStyle: FontStyle.italic,
            color: cue.textSecondary,
          ),
        ),
      ),
    );
  }

  Widget _inputBar(CueChartPalette p, CueColorsResolved cue) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 12),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: p.holdBorder, width: 0.5)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Container(
              constraints: const BoxConstraints(minHeight: 36),
              decoration: BoxDecoration(
                color: cue.bgCard,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: cue.border, width: 0.5),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: TextField(
                  controller: _input,
                  focusNode: _focus,
                  onSubmitted: (_) => _send(),
                  textInputAction: TextInputAction.send,
                  enabled: !_sending,
                  style: GoogleFonts.dmSans(
                    fontSize: 13,
                    color: cue.textPrimary,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Ask Cue…',
                    hintStyle: GoogleFonts.dmSans(
                      fontSize: 13,
                      color: cue.textSecondary,
                    ),
                    border: InputBorder.none,
                    isCollapsed: true,
                    contentPadding:
                        const EdgeInsets.symmetric(vertical: 9),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          IconButton(
            onPressed: () {},
            icon: const Icon(Icons.mic_none_rounded, size: 16),
            color: cue.textSecondary,
            tooltip: 'Voice (Phase 4.1.4)',
            padding: const EdgeInsets.all(6),
            constraints: const BoxConstraints(
              minWidth: 32,
              minHeight: 32,
            ),
          ),
          AnimatedOpacity(
            opacity: _hasText && !_sending ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 160),
            child: IgnorePointer(
              ignoring: !_hasText || _sending,
              child: IconButton(
                onPressed: _send,
                icon: const Icon(Icons.arrow_upward_rounded, size: 16),
                color: _amber,
                tooltip: 'Send',
                padding: const EdgeInsets.all(6),
                constraints: const BoxConstraints(
                  minWidth: 32,
                  minHeight: 32,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _IntroCopy {
  final String headline;
  final String subtext;
  const _IntroCopy({required this.headline, required this.subtext});
}
