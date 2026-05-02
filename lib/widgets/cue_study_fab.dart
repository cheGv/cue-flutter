// lib/widgets/cue_study_fab.dart
//
// Global Cue Study FAB — amber radiant button, bottom-left.
// Tap opens a DraggableScrollableSheet with a free-text query field,
// multilingual mic, and Claude response card.

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:speech_to_text/speech_to_text.dart';
import 'cue_study_icon.dart';

const _proxyUrl     = 'https://cue-ai-proxy.onrender.com/pre-session-brief';
const _navy         = Color(0xFF0A1A2F);
const _csAmber      = Color(0xFFF59E0B);
const _csAmberDark  = Color(0xFFD97706);
const _redRecord    = Color(0xFFEF4444);

const String _globalCueStudyPrompt =
    'You are Cue Study, a clinical reasoning companion '
    'for speech-language pathologists. The SLP may ask '
    'anything about clinical practice — evidence base, '
    'therapy approaches, goal writing, session planning, '
    'child profiles, regulatory strategies, AAC, motor '
    'speech, or any other SLP domain.\n\n'
    'Respond in 3-4 short paragraphs. Be specific, '
    'evidence-grounded, and neurodiversity-affirming. '
    "Use the child's name if the SLP mentions one.\n\n"
    'The SLP may write in any Indian language including '
    'Hindi, Telugu, Tamil, Kannada, Malayalam, Marathi, '
    'Gujarati, Bengali, Punjabi, or English. '
    'Understand input in any of these languages. '
    'Always respond in English only, as clinical '
    'documentation is in English.\n\n'
    'When clinical context is provided at the start of the '
    'message, ground every response in that specific child\'s data. '
    'Reference the child by name. Notice patterns in the provided data. '
    'Ask questions that will sharpen the SLP\'s clinical reasoning '
    'about this specific child. '
    'Never give generic advice when specific context is available.\n\n'
    'Output plain text only. No asterisks, no dashes, '
    'no bullet points, no bold, no headers, '
    'no markdown of any kind.\n\n'
    'Never mention Claude, Anthropic, or any underlying AI technology. '
    'You are Cue Study — a clinical reasoning companion built into Cue, '
    "India's first Clinical OS for SLPs. That is your complete identity "
    'in this context. '
    'Never introduce yourself. Never explain what you are or how you work. '
    'Just think alongside the SLP. '
    'If asked who built you or what technology powers you, say only: '
    "'I'm Cue Study — part of the Cue platform. "
    "What are you working through clinically?' "
    "Never start a response with 'I'm built on' or 'As an AI' or any variation.\n\n"
    'Anti-hallucination rules — follow without exception: '
    'Never cite specific statistics, percentages, or numerical research findings '
    'unless you are certain they are accurate. If uncertain, say "research suggests" '
    'or "evidence indicates" without numbers. '
    'Never fabricate paper titles, author names, or journal citations. '
    'If you want to reference research, name the framework or approach only, not a specific paper. '
    'Never make specific predictions about a child\'s progress timeline or outcome. '
    'When you don\'t know something, say so directly: '
    '"I don\'t have enough information to answer that confidently" — '
    'then ask the SLP a clarifying question. '
    'Express appropriate uncertainty with phrases like "one possibility is", '
    '"it may be worth considering", "this could suggest" — '
    'never state clinical interpretations as facts.';

// ── FAB button (stateless — sheet owns its own state) ─────────────────────────

class CueStudyFab extends StatelessWidget {
  final String? clientName;
  final String? clientAge;
  final String? clientDiagnosis;
  final String? activeLtgDomains;       // "Language · Cognition · AAC"
  final String? activeStgTexts;         // newline-joined active STG texts
  final String? recentSessionsContext;  // pre-formatted last-3-sessions block
  final String? regulatoryProfile;
  final String? baselineSummary;

  const CueStudyFab({
    super.key,
    this.clientName,
    this.clientAge,
    this.clientDiagnosis,
    this.activeLtgDomains,
    this.activeStgTexts,
    this.recentSessionsContext,
    this.regulatoryProfile,
    this.baselineSummary,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        // Phase 1: Cue Study is per-client only. From any screen that does
        // NOT have a client chart open (today screen, roster, etc.), the
        // global FAB tells the SLP to open a chart first.
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                "Open a client's Chart to start a Cue Study thread."),
            duration: Duration(seconds: 3),
          ),
        );
      },
      child: Container(
        width:  52,
        height: 52,
        decoration: BoxDecoration(
          color: _navy,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color:      Colors.black.withValues(alpha: 0.15),
              blurRadius: 12,
              offset:     const Offset(0, 4),
            ),
          ],
        ),
        child: const Center(child: CueStudyIcon()),
      ),
    );
  }

  /// Legacy: opens the one-shot Cue Study sheet without rendering the FAB.
  /// Phase 1 routes Cue Study through the persistent CueStudyScreen instead;
  /// this method remains as dead code for reference.
  // ignore: unused_element
  void openSheet(BuildContext context) {
    showModalBottomSheet(
      context:             context,
      isScrollControlled:  true,
      backgroundColor:     Colors.transparent,
      builder: (_) => _CueStudySheet(
        clientName:             clientName,
        clientAge:              clientAge,
        clientDiagnosis:        clientDiagnosis,
        activeLtgDomains:       activeLtgDomains,
        activeStgTexts:         activeStgTexts,
        recentSessionsContext:  recentSessionsContext,
        regulatoryProfile:      regulatoryProfile,
        baselineSummary:        baselineSummary,
      ),
    );
  }
}

// ── Bottom sheet ───────────────────────────────────────────────────────────────

class _CueStudySheet extends StatefulWidget {
  final String? clientName;
  final String? clientAge;
  final String? clientDiagnosis;
  final String? activeLtgDomains;
  final String? activeStgTexts;
  final String? recentSessionsContext;
  final String? regulatoryProfile;
  final String? baselineSummary;

  const _CueStudySheet({
    this.clientName,
    this.clientAge,
    this.clientDiagnosis,
    this.activeLtgDomains,
    this.activeStgTexts,
    this.recentSessionsContext,
    this.regulatoryProfile,
    this.baselineSummary,
  });

  @override
  State<_CueStudySheet> createState() => _CueStudySheetState();
}

class _CueStudySheetState extends State<_CueStudySheet>
    with TickerProviderStateMixin {

  // ── Animation ──────────────────────────────────────────────────────────────

  late final AnimationController _orbitController;
  late final AnimationController _pulseController;
  late final Animation<double>   _pulseAnim;

  // ── Speech ─────────────────────────────────────────────────────────────────

  final SpeechToText _speech = SpeechToText();
  bool   _speechAvailable = false;
  bool   _recording       = false;
  bool   _listening       = false;
  String _prevText        = '';

  // ── Query / response ───────────────────────────────────────────────────────

  final TextEditingController _queryCtrl = TextEditingController();
  bool    _loading  = false;
  String? _response;
  String? _error;

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();

    _orbitController = AnimationController(
      vsync:    this,
      duration: const Duration(milliseconds: 3000),
    )..repeat();

    _pulseController = AnimationController(
      vsync:    this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);

    _pulseAnim = Tween<double>(begin: 0.4, end: 1.0).animate(_pulseController);

    _initSpeech();
  }

  @override
  void dispose() {
    _orbitController.dispose();
    _pulseController.dispose();
    _speech.stop();
    _queryCtrl.dispose();
    super.dispose();
  }

  // ── Speech ─────────────────────────────────────────────────────────────────

  Future<void> _initSpeech() async {
    final available = await _speech.initialize(
      onStatus: (status) async {
        // Web Speech API has a ~60s session cap; auto-restart if the SLP
        // is still holding the mic button down.
        if (status == 'done' && _recording && mounted) {
          _prevText = _queryCtrl.text;
          await _startListening();
          return;
        }
        if ((status == 'done' || status == 'notListening') &&
            !_recording &&
            mounted) {
          setState(() => _listening = false);
        }
      },
      onError: (_) {
        if (mounted) {
          setState(() {
            _listening = false;
            _recording = false;
          });
        }
      },
    );
    if (mounted) setState(() => _speechAvailable = available);
  }

  Future<void> _startListening() async {
    await _speech.listen(
      onResult: (result) {
        if (mounted) {
          final text =
              ('$_prevText ${result.recognizedWords}').trim();
          setState(() {
            _queryCtrl.text = text;
            _queryCtrl.selection = TextSelection.fromPosition(
              TextPosition(offset: text.length),
            );
          });
        }
      },
      listenFor:     const Duration(minutes: 10),
      pauseFor:      const Duration(minutes: 10),
      listenOptions: SpeechListenOptions(partialResults: true),
    );
    if (mounted) setState(() => _listening = true);
  }

  Future<void> _toggleMic() async {
    if (!_speechAvailable) return;
    if (_listening) {
      _recording = false;
      await _speech.stop();
      if (mounted) setState(() => _listening = false);
    } else {
      setState(() => _error = null);
      _prevText  = _queryCtrl.text;
      _recording = true;
      await _startListening();
    }
  }

  // ── API ────────────────────────────────────────────────────────────────────

  String _buildUserMessage(String query) {
    if (widget.clientName == null) return query;
    final lines = <String>['Clinical context for this conversation:'];
    final agePart  = widget.clientAge != null ? ', Age ${widget.clientAge}' : '';
    final diagPart = (widget.clientDiagnosis?.isNotEmpty ?? false)
        ? ', ${widget.clientDiagnosis}' : '';
    lines.add('Child: ${widget.clientName}$agePart$diagPart');
    if (widget.regulatoryProfile?.isNotEmpty ?? false) {
      lines.add('Regulatory profile: ${widget.regulatoryProfile}');
    }
    if (widget.baselineSummary?.isNotEmpty ?? false) {
      lines.add('Baseline: ${widget.baselineSummary}');
    }
    if (widget.activeLtgDomains?.isNotEmpty ?? false) {
      lines.add('Active goal domains: ${widget.activeLtgDomains}');
    }
    if (widget.activeStgTexts?.isNotEmpty ?? false) {
      lines.add('Active short-term steps:\n${widget.activeStgTexts}');
    }
    if (widget.recentSessionsContext?.isNotEmpty ?? false) {
      lines.add('Recent sessions:\n${widget.recentSessionsContext}');
    }
    lines.add('');
    lines.add("SLP's question: $query");
    return lines.join('\n');
  }

  Future<void> _submit() async {
    final query = _queryCtrl.text.trim();
    if (query.isEmpty) return;
    setState(() {
      _loading  = true;
      _response = null;
      _error    = null;
    });
    try {
      final res = await http.post(
        Uri.parse(_proxyUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'model':        'claude-opus-4-5',
          'system':       _globalCueStudyPrompt,
          'user_message': _buildUserMessage(query),
          'thinking':     {'type': 'enabled', 'budget_tokens': 3000},
        }),
      ).timeout(const Duration(seconds: 60));
      if (!mounted) return;
      if (res.statusCode == 200) {
        final data    = jsonDecode(res.body) as Map<String, dynamic>;
        final content = data['content'] as List? ?? [];
        // With extended thinking the response has thinking + text blocks;
        // find the first text block.
        final textBlock = content.firstWhere(
          (b) => b is Map && b['type'] == 'text',
          orElse: () => <String, dynamic>{},
        );
        final text = (textBlock as Map<String, dynamic>)['text'] as String? ?? '';
        setState(() { _response = text; _loading = false; });
      } else {
        setState(() {
          _error   = 'Server error ${res.statusCode}';
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() { _error = 'Could not connect: $e'; _loading = false; });
      }
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.55,
      minChildSize:     0.35,
      maxChildSize:     0.92,
      builder: (ctx, scrollController) => ClipRRect(
        borderRadius: const BorderRadius.vertical(
            top: Radius.circular(20)),
        child: Container(
          color: _navy,
          child: Column(
            children: [
              _buildHeader(),
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding:    EdgeInsets.zero,
                  children: [
                    _buildQueryField(),
                    _buildSubmitButton(),
                    _buildResponseCard(),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Header (non-scrolling) ─────────────────────────────────────────────────

  Widget _buildHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Drag handle
        Center(
          child: Container(
            width:  32,
            height: 4,
            margin: const EdgeInsets.only(top: 12),
            decoration: BoxDecoration(
              color:        Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
        const SizedBox(height: 12),
        // Title row: icon + label + spacer + mic
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const CueStudyIcon(size: 18),
              const SizedBox(width: 8),
              Text(
                'CUE STUDY',
                style: GoogleFonts.dmSans(
                  fontSize:    11,
                  fontWeight:  FontWeight.w600,
                  color:       _csAmber,
                  letterSpacing: 1.1,
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: _toggleMic,
                child: Container(
                  width:  32,
                  height: 32,
                  decoration: BoxDecoration(
                    color:  _listening ? _redRecord : _csAmberDark,
                    shape:  BoxShape.circle,
                  ),
                  child: Icon(
                    _listening ? Icons.stop : Icons.mic,
                    color: Colors.white,
                    size:  16,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: widget.clientName != null
              ? Text(
                  'Thinking about ${widget.clientName}.',
                  style: GoogleFonts.dmSans(
                    fontSize: 12,
                    color:    _csAmber,
                    height:   1.5,
                  ),
                )
              : Text(
                  'A clinical reasoning companion. '
                  'Ask anything about your clinical work.',
                  style: GoogleFonts.dmSans(
                    fontSize: 12,
                    color:    Colors.white.withValues(alpha: 0.4),
                    height:   1.5,
                  ),
                ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  // ── Query text field ───────────────────────────────────────────────────────

  Widget _buildQueryField() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: TextField(
        controller: _queryCtrl,
        autofocus:  true,
        maxLines:   null,
        style: GoogleFonts.dmSans(
          fontSize: 14,
          color:    Colors.white,
        ),
        cursorColor: _csAmber,
        decoration: InputDecoration(
          hintText:
              'Ask Cue anything — clinical reasoning, goal ideas, '
              'session strategies, evidence base...',
          hintStyle: GoogleFonts.dmSans(
            fontSize:  14,
            fontStyle: FontStyle.italic,
            color:     Colors.white.withValues(alpha: 0.3),
          ),
          border:        InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          fillColor:     Colors.transparent,
          filled:        true,
          contentPadding: const EdgeInsets.all(16),
        ),
      ),
    );
  }

  // ── Submit button ──────────────────────────────────────────────────────────

  Widget _buildSubmitButton() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: SizedBox(
        width: double.infinity,
        child: FilledButton(
          onPressed: _loading ? null : _submit,
          style: FilledButton.styleFrom(
            backgroundColor:         _csAmberDark,
            disabledBackgroundColor: _csAmberDark.withValues(alpha: 0.5),
            padding: const EdgeInsets.symmetric(vertical: 13),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          child: Text(
            'Ask Cue →',
            style: GoogleFonts.dmSans(
              fontSize:   14,
              fontWeight: FontWeight.w500,
              color:      Colors.white,
            ),
          ),
        ),
      ),
    );
  }

  // ── Response card (appears after response) ─────────────────────────────────

  Widget _buildResponseCard() {
    final show = _loading || _response != null || _error != null;
    return AnimatedSize(
      duration:  const Duration(milliseconds: 300),
      curve:     Curves.easeInOut,
      alignment: Alignment.topCenter,
      child: show
          ? Container(
              margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              decoration: BoxDecoration(
                color: _csAmber.withValues(alpha: 0.06),
                border: const Border(
                  left: BorderSide(color: _csAmberDark, width: 2),
                ),
                borderRadius: const BorderRadius.only(
                  topRight:    Radius.circular(12),
                  bottomRight: Radius.circular(12),
                ),
              ),
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'CUE STUDY',
                    style: GoogleFonts.dmSans(
                      fontSize:     10,
                      fontWeight:   FontWeight.w600,
                      color:        _csAmber,
                      letterSpacing: 0.8,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (_loading)
                    _buildOrbit()
                  else if (_error != null)
                    Text(
                      _error!,
                      style: GoogleFonts.dmSans(
                        fontSize: 13,
                        color:    Colors.red.shade400,
                      ),
                    )
                  else if (_response != null && _response!.isNotEmpty) ...[
                    Text(
                      _response!,
                      style: GoogleFonts.dmSans(
                        fontSize: 13,
                        color:    Colors.white.withValues(alpha: 0.85),
                        height:   1.7,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(height: 0.5, color: Colors.white.withValues(alpha: 0.1)),
                    const SizedBox(height: 8),
                    Text(
                      'Cue Study supports your reasoning. Clinical judgment is always yours.',
                      style: GoogleFonts.dmSans(
                        fontSize:  11,
                        fontStyle: FontStyle.italic,
                        color:     Colors.white.withValues(alpha: 0.35),
                        height:    1.5,
                      ),
                    ),
                  ],
                ],
              ),
            )
          : const SizedBox.shrink(),
    );
  }

  // ── Orbit loading animation ────────────────────────────────────────────────

  Widget _buildOrbit() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Center(
        child: SizedBox(
          width:  32,
          height: 32,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Orbiting dot
              RotationTransition(
                turns: _orbitController,
                child: SizedBox(
                  width:  32,
                  height: 32,
                  child: Align(
                    alignment: const Alignment(0.625, 0),
                    child: Container(
                      width:  5,
                      height: 5,
                      decoration: const BoxDecoration(
                        color: _csAmberDark,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                ),
              ),
              // Center pulsing dot
              AnimatedBuilder(
                animation: _pulseAnim,
                builder:   (context, child) => Opacity(
                  opacity: _pulseAnim.value,
                  child: Container(
                    width:  7,
                    height: 7,
                    decoration: const BoxDecoration(
                      color: _csAmber,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
