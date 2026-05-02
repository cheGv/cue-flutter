// lib/screens/cue_study_screen.dart
//
// Phase 2.5 register shift: Cue Study is now part of the same companion
// language as the chart screen. Pure white day, near-black night, amber as
// Cue's only voice, geometric-sans throughout.
//
// Phase 2.6 token extraction: every spacing/radius/duration/size/alpha now
// flows from lib/theme/cue_tokens.dart. Visual values are unchanged — this
// pass is rename-only.
//
// Persistence + scoping behaviour from Phase 1 is unchanged: one thread per
// (user_id, client_id), full chart context built fresh each turn, non-
// streaming POST to /cue-study, scope refusal handled by the system prompt.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../theme/cue_theme.dart';
import '../theme/cue_tokens.dart';
import '../theme/cue_typography.dart';
import '../utils/chart_context.dart';
import '../widgets/cue_cuttlefish.dart';

const _proxyUrl = 'https://cue-ai-proxy.onrender.com/cue-study';

// Three opening prompts for the empty welcome state. Tapping one pre-fills
// the input and sends immediately.
//
// Phase 3.3.4 — pronoun + deficit-framing audit:
//  - "slow" is a §13.1 forbidden word; replaced with "need scaffolding".
//  - Gendered pronouns removed from chip 3 ("her", "for her age") — the
//    chart may not have gender data, and "for her age" was its own subtle
//    deficit lens. "Well-calibrated" is the clinical concept the SLP is
//    actually evaluating.
// Future chips added to this list MUST: (a) use no gendered pronoun,
// (b) avoid §13.1 forbidden words, (c) center the work or the SLP's
// decision rather than the child as subject of analysis (§13.8).
const _welcomeSuggestions = <String>[
  'Where might progress need scaffolding?',
  'What should I try next session?',
  'Are the goals well-calibrated?',
];

class CueStudyScreen extends StatefulWidget {
  final String              clientId;
  final Map<String, dynamic> clientData;
  final String?             initialMessage;

  const CueStudyScreen({
    super.key,
    required this.clientId,
    required this.clientData,
    this.initialMessage,
  });

  @override
  State<CueStudyScreen> createState() => _CueStudyScreenState();
}

class _CueStudyScreenState extends State<CueStudyScreen> {
  final _supabase   = Supabase.instance.client;
  final _scrollCtrl = ScrollController();
  final _inputCtrl  = TextEditingController();

  String?                     _threadId;
  SignatureVariant            _variant = SignatureVariant.she;
  List<Map<String, dynamic>>  _messages = [];
  bool                        _loading  = true;
  bool                        _isSending = false;
  String?                     _loadError;

  // Drives the send-button amber/dim toggle. Set from the input controller's
  // listener so the button rebuilds on text change without a full setState
  // chain through the message list.
  bool _hasInputText = false;

  // Per-assistant-message cuttlefish state cache. Keyed by message id so we
  // only derive once per message, not on every paint.
  final Map<String, CueState> _bubbleStateCache = {};

  // ── Lifecycle ────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _inputCtrl.addListener(_onInputChanged);
    _bootstrap();
  }

  @override
  void dispose() {
    _inputCtrl.removeListener(_onInputChanged);
    _scrollCtrl.dispose();
    _inputCtrl.dispose();
    super.dispose();
  }

  void _onInputChanged() {
    final has = _inputCtrl.text.trim().isNotEmpty;
    if (has != _hasInputText) setState(() => _hasInputText = has);
  }

  String get _clientFirstName {
    final full = (widget.clientData['name'] as String?)?.trim() ?? '';
    if (full.isEmpty) return 'this child';
    return full.split(RegExp(r'\s+')).first;
  }

  // ── Bootstrap: profile + thread + history ────────────────────────────────

  Future<void> _bootstrap() async {
    try {
      final uid = _supabase.auth.currentUser?.id;
      if (uid == null) throw Exception('Not signed in');

      // 1. Signature variant
      final profileRows = await _supabase
          .from('user_profiles')
          .select('signature_variant')
          .eq('id', uid)
          .limit(1);
      if (profileRows.isEmpty) {
        await _supabase.from('user_profiles').insert({'id': uid});
      } else {
        _variant = _variantFromString(
            profileRows.first['signature_variant'] as String?);
      }

      // 2. Thread for (uid, clientId)
      final threadRows = await _supabase
          .from('cue_study_threads')
          .select('id')
          .eq('user_id',   uid)
          .eq('client_id', widget.clientId)
          .limit(1);
      String threadId;
      if (threadRows.isEmpty) {
        final inserted = await _supabase
            .from('cue_study_threads')
            .insert({'user_id': uid, 'client_id': widget.clientId})
            .select('id')
            .single();
        threadId = inserted['id'].toString();
      } else {
        threadId = threadRows.first['id'].toString();
      }
      _threadId = threadId;

      // 3. Message history
      final msgRows = await _supabase
          .from('cue_study_messages')
          .select('id, role, content, created_at')
          .eq('thread_id', threadId)
          .order('created_at', ascending: true);
      _messages = List<Map<String, dynamic>>.from(msgRows);
      _seedBubbleStateCache();

      if (mounted) {
        setState(() => _loading = false);
        _scrollToBottomSoon();
      }

      // 4. Auto-send initialMessage if present and thread empty
      if (widget.initialMessage != null &&
          widget.initialMessage!.trim().isNotEmpty &&
          _messages.isEmpty &&
          mounted) {
        await _sendMessage(widget.initialMessage!.trim());
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading   = false;
          _loadError = 'Could not open Cue Study: $e';
        });
      }
    }
  }

  SignatureVariant _variantFromString(String? s) {
    switch (s) {
      case 'he':      return SignatureVariant.he;
      case 'neutral': return SignatureVariant.neutral;
      case 'she':
      default:        return SignatureVariant.she;
    }
  }

  void _seedBubbleStateCache() {
    for (final m in _messages) {
      if (m['role'] != 'assistant') continue;
      final id = m['id']?.toString();
      if (id == null) continue;
      _bubbleStateCache[id] =
          _deriveBubbleState((m['content'] as String?) ?? '');
    }
  }

  void _scrollToBottomSoon() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollCtrl.hasClients) return;
      _scrollCtrl.animateTo(
        _scrollCtrl.position.maxScrollExtent,
        duration: CueDuration.scrollSnap,
        curve:    Curves.easeOut,
      );
    });
  }

  // State derivation for assistant cuttlefish — see Phase 2.5 spec Step 6.
  // Confused on hard scope refusal (exact phrase from system prompt),
  // waving on substantive responses with date + session references,
  // idle otherwise.
  static final RegExp _datePattern = RegExp(
    r'\b(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)[a-z]*\s+\d{1,2}|\b\d{4}-\d{2}-\d{2}\b',
  );

  CueState _deriveBubbleState(String content) {
    if (content.startsWith("That's outside what I'm built for")) {
      return CueState.confused;
    }
    final hasDate    = _datePattern.hasMatch(content);
    final hasSession = content.toLowerCase().contains('session');
    if (content.length > 400 && hasDate && hasSession) {
      return CueState.waving;
    }
    return CueState.idle;
  }

  // ── Send ─────────────────────────────────────────────────────────────────

  Future<void> _onSendPressed() async {
    final text = _inputCtrl.text.trim();
    if (text.isEmpty || _isSending || _threadId == null) return;
    _inputCtrl.clear();
    await _sendMessage(text);
  }

  /// Pre-fills input from a welcome suggestion chip and sends immediately.
  Future<void> _sendSuggestion(String text) async {
    if (_isSending || _threadId == null) return;
    _inputCtrl.text = text;
    await _sendMessage(text);
    _inputCtrl.clear();
  }

  Future<void> _sendMessage(String text) async {
    if (_threadId == null) return;
    setState(() => _isSending = true);

    Map<String, dynamic>? userRow;
    try {
      userRow = await _supabase
          .from('cue_study_messages')
          .insert({
            'thread_id': _threadId,
            'role':      'user',
            'content':   text,
          })
          .select('id, role, content, created_at')
          .single();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save message: $e')),
        );
        setState(() => _isSending = false);
      }
      return;
    }

    if (!mounted) return;
    setState(() {
      _messages = [..._messages, userRow!];
    });
    _scrollToBottomSoon();

    String chartContextStr;
    try {
      chartContextStr =
          await buildChartContext(widget.clientId, widget.clientData);
    } catch (e) {
      chartContextStr = '=== CLIENT CHART ===\n(could not load chart: $e)';
    }

    Map<String, dynamic>? response;
    try {
      final res = await http.post(
        Uri.parse(_proxyUrl),
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode({
          'chart_context': chartContextStr,
          'messages': _messages
              .map((m) => {
                    'role':    m['role'],
                    'content': m['content'],
                  })
              .toList(),
        }),
      );
      if (res.statusCode != 200) {
        throw Exception('proxy ${res.statusCode}: ${res.body}');
      }
      response = jsonDecode(res.body) as Map<String, dynamic>;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Cue Study request failed: $e')),
        );
        setState(() => _isSending = false);
      }
      return;
    }

    String assistantText = '';
    final content = response['content'];
    if (content is List && content.isNotEmpty) {
      final first = content.first;
      if (first is Map && first['text'] is String) {
        assistantText = (first['text'] as String).trim();
      }
    }
    if (assistantText.isEmpty) {
      assistantText =
          'I couldn\'t generate a response. Try rephrasing or check your connection.';
    }

    Map<String, dynamic>? assistantRow;
    try {
      assistantRow = await _supabase
          .from('cue_study_messages')
          .insert({
            'thread_id': _threadId,
            'role':      'assistant',
            'content':   assistantText,
          })
          .select('id, role, content, created_at')
          .single();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save reply: $e')),
        );
        setState(() => _isSending = false);
      }
      return;
    }

    if (!mounted) return;
    final aid = assistantRow['id']?.toString();
    if (aid != null) {
      _bubbleStateCache[aid] = _deriveBubbleState(assistantText);
    }
    setState(() {
      _messages  = [..._messages, assistantRow!];
      _isSending = false;
    });
    _scrollToBottomSoon();
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isNight = Theme.of(context).brightness == Brightness.dark;
    final bg      = isNight ? CueColors.backgroundDark : CueColors.background;
    final ink     = isNight ? CueColors.inkDark        : CueColors.inkPrimary;
    final ink2    = isNight ? CueColors.inkSecondaryDark
                            : CueColors.inkSecondary;
    final divider = isNight ? CueColors.dividerDark    : CueColors.divider;

    return Scaffold(
      backgroundColor: bg,
      appBar: _buildAppBar(bg: bg, ink: ink, ink2: ink2, divider: divider),
      body: SafeArea(
        top:    false,
        child: _loading
            ? Center(
                child: CircularProgressIndicator(
                    strokeWidth: CueSize.spinnerStroke,
                    color:       CueColors.amber),
              )
            : _loadError != null
                ? _buildError(ink: ink)
                : _buildChat(isNight: isNight, ink: ink, ink2: ink2),
      ),
    );
  }

  // ── AppBar ────────────────────────────────────────────────────────────────

  PreferredSizeWidget _buildAppBar({
    required Color bg,
    required Color ink,
    required Color ink2,
    required Color divider,
  }) {
    return AppBar(
      backgroundColor: bg,
      elevation:       0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      leading: IconButton(
        icon: Icon(Icons.arrow_back, color: ink2),
        onPressed: () => Navigator.pop(context),
      ),
      titleSpacing: 0,
      title: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width:  CueSize.cuttlefishAppBar,
            height: CueSize.cuttlefishAppBarSlot,
            child: CueCuttlefish(
                size:    CueSize.cuttlefishAppBar,
                state:   CueState.idle,
                variant: _variant),
          ),
          const SizedBox(width: CueGap.s10),
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment:  MainAxisAlignment.center,
            children: [
              Text('Cue Study',
                  style: CueType.displaySmall.copyWith(color: ink)),
              Text(_clientFirstName,
                  style: CueType.bodySmall.copyWith(color: ink2)),
            ],
          ),
        ],
      ),
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(CueSize.hairline),
        child: Container(height: CueSize.hairline, color: divider),
      ),
    );
  }

  // ── Error ─────────────────────────────────────────────────────────────────

  Widget _buildError({required Color ink}) {
    return Padding(
      padding: const EdgeInsets.all(CueGap.s24),
      child: Center(
        child: Text(
          _loadError!,
          style: CueType.bodyMedium.copyWith(color: ink),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }

  // ── Chat layout ───────────────────────────────────────────────────────────

  Widget _buildChat({
    required bool  isNight,
    required Color ink,
    required Color ink2,
  }) {
    return Column(
      children: [
        Expanded(
          child: _messages.isEmpty && !_isSending
              ? _buildWelcome(isNight: isNight, ink: ink, ink2: ink2)
              : ListView.builder(
                  controller: _scrollCtrl,
                  padding: const EdgeInsets.fromLTRB(
                      0, CueGap.s16, 0, CueGap.s8),
                  itemCount: _messages.length + (_isSending ? 1 : 0),
                  itemBuilder: (ctx, i) {
                    if (i == _messages.length && _isSending) {
                      return _buildTypingIndicator(ink2: ink2);
                    }
                    final m = _messages[i];
                    return m['role'] == 'user'
                        ? _buildUserBubble(m, isNight: isNight)
                        : _buildAssistantBubble(
                            m, isNight: isNight, ink: ink, ink2: ink2);
                  },
                ),
        ),
        _buildInputBar(isNight: isNight, ink: ink, ink2: ink2),
      ],
    );
  }

  // ── Welcome state ─────────────────────────────────────────────────────────

  Widget _buildWelcome({
    required bool  isNight,
    required Color ink,
    required Color ink2,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: CueGap.s32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const SizedBox(height: CueGap.welcomeTopGap),
          CueCuttlefish(
            size:    CueSize.cuttlefishWelcome,
            state:   CueState.signature,
            variant: _variant,
          ),
          const SizedBox(height: CueGap.s28),
          Text(
            "I've been thinking about $_clientFirstName.",
            textAlign: TextAlign.center,
            style: CueType.displayMedium.copyWith(color: ink),
          ),
          const SizedBox(height: CueGap.s10),
          Text(
            'Ask me anything — the chart is open.',
            textAlign: TextAlign.center,
            style: CueType.bodyLarge.copyWith(color: ink2),
          ),
          const SizedBox(height: CueGap.s32),
          ..._welcomeSuggestions.map((s) => Padding(
                padding: const EdgeInsets.only(bottom: CueGap.s10),
                child: _SuggestionChip(
                  label:   s,
                  onTap:   () => _sendSuggestion(s),
                  isNight: isNight,
                ),
              )),
        ],
      ),
    );
  }

  // ── User bubble ──────────────────────────────────────────────────────────

  Widget _buildUserBubble(Map<String, dynamic> m,
      {required bool isNight}) {
    final content = (m['content'] as String?) ?? '';
    final tsStr   = _formatTimestamp(m['created_at']?.toString());
    final bubbleColor =
        isNight ? CueBubbleColors.userNight : CueBubbleColors.userDay;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
          CueGap.bubbleUserLeftPad, CueGap.s4, CueGap.s16, CueGap.s4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: CueGap.s16, vertical: CueGap.s11),
            decoration: BoxDecoration(
              color: bubbleColor,
              borderRadius: const BorderRadius.only(
                topLeft:     Radius.circular(CueRadius.s16),
                topRight:    Radius.circular(CueRadius.s16),
                bottomLeft:  Radius.circular(CueRadius.s16),
                bottomRight: Radius.circular(CueRadius.s4),
              ),
            ),
            child: Text(
              content,
              style: CueType.bodyMedium.copyWith(color: Colors.white),
            ),
          ),
          if (tsStr != null) ...[
            const SizedBox(height: CueGap.s6),
            Text(
              tsStr.toUpperCase(),
              style: CueType.labelSmall.copyWith(
                  color: isNight
                      ? CueColors.inkTertiaryDark
                      : CueColors.inkTertiary),
            ),
          ],
        ],
      ),
    );
  }

  // ── Assistant bubble + state-aware cuttlefish ────────────────────────────

  Widget _buildAssistantBubble(
    Map<String, dynamic> m, {
    required bool  isNight,
    required Color ink,
    required Color ink2,
  }) {
    final id      = m['id']?.toString();
    final content = (m['content'] as String?) ?? '';
    final tsStr   = _formatTimestamp(m['created_at']?.toString());
    final state   = (id != null ? _bubbleStateCache[id] : null) ?? CueState.idle;

    final surface = isNight ? CueColors.surfaceDark : CueColors.surface;
    final border  =
        CueColors.amber.withValues(alpha: CueAlpha.assistantBubbleBorder);

    return Padding(
      padding: const EdgeInsets.fromLTRB(
          CueGap.s16, CueGap.s4, CueGap.bubbleAssistantRightPad, CueGap.s4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width:  CueSize.cuttlefishBubble,
            height: CueSize.cuttlefishBubbleSlot,
            child: CueCuttlefish(
                size:    CueSize.cuttlefishBubble,
                state:   state,
                variant: _variant),
          ),
          const SizedBox(width: CueGap.s12),
          Expanded(
            child: Container(
              padding: const EdgeInsets.fromLTRB(
                  CueGap.s18, CueGap.s14, CueGap.s18, CueGap.s14),
              decoration: BoxDecoration(
                color:        surface,
                border:       Border.all(color: border, width: CueSize.hairline),
                borderRadius: const BorderRadius.only(
                  topLeft:     Radius.circular(CueRadius.s4),
                  topRight:    Radius.circular(CueRadius.s16),
                  bottomLeft:  Radius.circular(CueRadius.s16),
                  bottomRight: Radius.circular(CueRadius.s16),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    content,
                    style: CueType.bodyMedium.copyWith(
                        color: ink, height: 1.65),
                  ),
                  const SizedBox(height: CueGap.s8),
                  Text(
                    'CUE${tsStr != null ? " · $tsStr" : ""}',
                    style: CueType.labelSmall.copyWith(
                        color: isNight
                            ? CueColors.inkTertiaryDark
                            : CueColors.inkTertiary),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Typing indicator ──────────────────────────────────────────────────────

  Widget _buildTypingIndicator({required Color ink2}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          CueGap.s16, CueGap.s12, CueGap.s16, CueGap.s8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width:  CueSize.cuttlefishEyebrow,
            height: CueSize.cuttlefishEyebrowSlot,
            child: CueCuttlefish(
                size:    CueSize.cuttlefishEyebrow,
                state:   CueState.thinking,
                variant: _variant),
          ),
          const SizedBox(width: CueGap.s8),
          AnimatedOpacity(
            opacity:  CueAlpha.typingIndicator,
            duration: CueDuration.typingFade,
            child: Text(
              'Cue is thinking...',
              style: CueType.bodySmall.copyWith(
                color:     ink2,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Input bar + send button ──────────────────────────────────────────────

  Widget _buildInputBar({
    required bool  isNight,
    required Color ink,
    required Color ink2,
  }) {
    final containerBg     = isNight ? CueColors.surfaceDark : CueColors.surface;
    final containerBorder = isNight
        ? CueColors.amber.withValues(alpha: CueAlpha.inputBorderNight)
        : CueColors.divider;
    final sendActive      = _hasInputText && !_isSending;
    final sendBg          = sendActive
        ? CueColors.amber
        : CueColors.amber.withValues(alpha: CueAlpha.sendButtonDim);

    return Padding(
      padding: const EdgeInsets.fromLTRB(
          CueGap.s16, 0, CueGap.s16, CueGap.s16),
      child: Container(
        decoration: BoxDecoration(
          color:        containerBg,
          border:       Border.all(
              color: containerBorder, width: CueSize.hairline),
          borderRadius: BorderRadius.circular(CueRadius.s26),
        ),
        padding: const EdgeInsets.all(CueGap.s5),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            const SizedBox(width: CueGap.s10),
            Expanded(
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(vertical: CueGap.s9),
                child: TextField(
                  controller:  _inputCtrl,
                  minLines:    1,
                  maxLines:    5,
                  enabled:     !_isSending,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _onSendPressed(),
                  style: CueType.bodyMedium.copyWith(color: ink),
                  decoration: InputDecoration(
                    hintText:
                        'Think with Cue about $_clientFirstName...',
                    hintStyle: CueType.bodyMedium.copyWith(
                        color: isNight
                            ? CueColors.inkTertiaryDark
                            : CueColors.inkTertiary),
                    border:          InputBorder.none,
                    enabledBorder:   InputBorder.none,
                    focusedBorder:   InputBorder.none,
                    isDense:         true,
                    contentPadding:  EdgeInsets.zero,
                  ),
                ),
              ),
            ),
            const SizedBox(width: CueGap.s6),
            // Amber circle send button — paper-plane glyph in near-black.
            Material(
              color:        Colors.transparent,
              shape:        const CircleBorder(),
              clipBehavior: Clip.antiAlias,
              child: Container(
                width:  CueSize.sendButton,
                height: CueSize.sendButton,
                decoration: BoxDecoration(
                  color: sendBg,
                  shape: BoxShape.circle,
                ),
                child: IconButton(
                  icon: const Icon(Icons.send_rounded,
                      size:  CueSize.sendGlyph,
                      color: CueBubbleColors.sendGlyph),
                  onPressed:    sendActive ? _onSendPressed : null,
                  padding:      EdgeInsets.zero,
                  splashRadius: 18,
                  tooltip:      'Send',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String? _formatTimestamp(String? iso) {
    if (iso == null) return null;
    try {
      final dt = DateTime.parse(iso).toLocal();
      final h  = dt.hour.toString().padLeft(2, '0');
      final m  = dt.minute.toString().padLeft(2, '0');
      return '$h:$m';
    } catch (_) {
      return null;
    }
  }
}

// ── Welcome suggestion chip ──────────────────────────────────────────────────

class _SuggestionChip extends StatelessWidget {
  final String       label;
  final VoidCallback onTap;
  final bool         isNight;

  const _SuggestionChip({
    required this.label,
    required this.onTap,
    required this.isNight,
  });

  @override
  Widget build(BuildContext context) {
    final surface = isNight ? CueColors.surfaceDark : CueColors.surface;
    final border  = isNight ? CueColors.dividerDark : CueColors.divider;
    final text    = isNight
        ? CueColors.inkSecondaryDark
        : CueColors.inkSecondary;

    return Material(
      color:        Colors.transparent,
      borderRadius: BorderRadius.circular(CueRadius.s22),
      child: InkWell(
        onTap:        onTap,
        borderRadius: BorderRadius.circular(CueRadius.s22),
        child: Container(
          padding: const EdgeInsets.symmetric(
              horizontal: CueGap.s18, vertical: CueGap.s10),
          decoration: BoxDecoration(
            color:        surface,
            border:       Border.all(color: border, width: CueSize.hairline),
            borderRadius: BorderRadius.circular(CueRadius.s22),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: CueType.labelLarge.copyWith(color: text),
          ),
        ),
      ),
    );
  }
}
