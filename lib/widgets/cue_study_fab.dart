// lib/widgets/cue_study_fab.dart
//
// Global floating Cue Study button — sits at bottom-left of every AppLayout
// screen (hidden on add_client and login via showCueStudyFab: false).
// Tap → DraggableScrollableSheet with free-text query + multilingual mic.

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:speech_to_text/speech_to_text.dart';

import 'cue_study_icon.dart';

// ── design tokens (mirror ltg_edit_screen) ────────────────────────────────────
const Color _navyDark    = Color(0xFF0A1A2F);
const Color _csAmber     = Color(0xFFF59E0B);
const Color _csAmberDark = Color(0xFFD97706);
const Color _red         = Color(0xFFDC2626);
const String _proxyBase  = 'https://cue-ai-proxy.onrender.com';

const String _kGlobalPrompt =
    'You are Cue Study, a clinical reasoning companion for speech-language pathologists. '
    'The SLP may ask anything about clinical practice, evidence base, therapy approaches, '
    'goal writing, session planning, or child profiles. Answer in 3-4 short paragraphs. '
    'Be specific, evidence-grounded, and neurodiversity-affirming. '
    "Use the child's name if provided. "
    'The SLP may write in any Indian language — always respond in English. '
    'Output plain text only. No markdown.';

// ── FAB button ────────────────────────────────────────────────────────────────

class CueStudyFab extends StatelessWidget {
  const CueStudyFab({super.key});

  void _open(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.55,
        minChildSize: 0.35,
        maxChildSize: 0.92,
        expand: false,
        builder: (ctx, scrollCtrl) =>
            _CueStudySheet(scrollController: scrollCtrl),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _open(context),
      child: Container(
        width: 52,
        height: 52,
        decoration: const BoxDecoration(
          color: _navyDark,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Color(0x40000000),
              blurRadius: 10,
              offset: Offset(0, 3),
            ),
          ],
        ),
        child: const Center(child: CueStudyIcon()),
      ),
    );
  }
}

// ── Sheet ─────────────────────────────────────────────────────────────────────

class _CueStudySheet extends StatefulWidget {
  final ScrollController scrollController;
  const _CueStudySheet({required this.scrollController});

  @override
  State<_CueStudySheet> createState() => _CueStudySheetState();
}

class _CueStudySheetState extends State<_CueStudySheet> {
  final _ctrl = TextEditingController();

  // Mic / speech
  final _speech        = SpeechToText();
  bool    _speechAvailable = false;
  bool    _micRecording    = false; // SLP intends to record (drives auto-restart)
  bool    _micListening    = false; // mic is actively capturing right now
  String  _micText         = '';   // accumulated transcript
  String  _micPrevText     = '';   // snapshot before each listen segment
  String? _bestLocale;             // first available from priority list

  // AI
  bool    _loading  = false;
  String? _response;
  String? _error;

  @override
  void initState() {
    super.initState();
    _initSpeech();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _speech.stop();
    super.dispose();
  }

  // ── Speech ──────────────────────────────────────────────────────────────────

  Future<void> _initSpeech() async {
    final available = await _speech.initialize(
      onStatus: (status) async {
        // Web Speech API fires 'done' at ~60 s. Auto-restart while recording.
        if (status == 'done' && _micRecording && mounted) {
          _micPrevText = _micText;
          await _startListening();
          return;
        }
        if ((status == 'done' || status == 'notListening') &&
            !_micRecording &&
            mounted) {
          setState(() => _micListening = false);
        }
      },
      onError: (e) {
        if (mounted) {
          setState(() { _micListening = false; _micRecording = false; });
        }
      },
    );
    if (available) {
      // Cache best locale from priority list; null → device default
      final locales   = await _speech.locales();
      final localeIds = locales.map((l) => l.localeId).toSet();
      for (final pref in ['ta_IN', 'te_IN', 'kn_IN', 'ml_IN', 'hi_IN', 'en_IN']) {
        if (localeIds.contains(pref)) { _bestLocale = pref; break; }
      }
    }
    if (mounted) setState(() => _speechAvailable = available);
  }

  Future<void> _startListening() async {
    await _speech.listen(
      onResult: (result) {
        if (mounted) {
          setState(() {
            _micText = ('$_micPrevText ${result.recognizedWords}').trim();
            _ctrl.text = _micText;
            _ctrl.selection = TextSelection.fromPosition(
              TextPosition(offset: _ctrl.text.length),
            );
          });
        }
      },
      listenFor: const Duration(minutes: 10),
      pauseFor: const Duration(minutes: 10),
      localeId: _bestLocale,
      listenOptions: SpeechListenOptions(partialResults: true),
    );
    if (mounted) setState(() => _micListening = true);
  }

  Future<void> _toggleMic() async {
    if (!_speechAvailable) return;
    if (_micListening) {
      _micRecording = false;
      await _speech.stop();
      if (mounted) setState(() => _micListening = false);
    } else {
      setState(() => _error = null);
      _micPrevText  = _micText;
      _micRecording = true;
      await _startListening();
    }
  }

  // ── AI ───────────────────────────────────────────────────────────────────────

  Future<void> _submit() async {
    final input = _ctrl.text.trim();
    if (input.isEmpty) return;
    setState(() { _loading = true; _response = null; _error = null; });
    try {
      final res = await http.post(
        Uri.parse('$_proxyBase/pre-session-brief'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'model': 'claude-opus-4-5',
          'system': _kGlobalPrompt,
          'user_message': input,
        }),
      ).timeout(const Duration(seconds: 30));
      if (res.statusCode != 200) throw Exception('HTTP ${res.statusCode}');
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final text = data['content']?[0]?['text'] as String? ?? '';
      if (mounted) setState(() { _response = text; _loading = false; });
    } catch (_) {
      if (mounted) {
        setState(() {
          _error   = 'Cue Study is unavailable. Try again.';
          _loading = false;
        });
      }
    }
  }

  // ── build ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: _navyDark,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: ListView(
        controller: widget.scrollController,
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Header: icon + CUE STUDY + mic button
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const CueStudyIcon(),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'CUE STUDY',
                  style: GoogleFonts.dmSans(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: _csAmber,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
              GestureDetector(
                onTap: _toggleMic,
                child: Container(
                  width: 32, height: 32,
                  decoration: BoxDecoration(
                    color: _micListening
                        ? const Color(0xFFEF4444)
                        : _csAmberDark,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    _micListening ? Icons.stop : Icons.mic,
                    color: Colors.white, size: 16,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),

          Text(
            'Ask Cue anything about your clinical work.',
            style: GoogleFonts.dmSans(
              fontSize: 12,
              color: Colors.white.withValues(alpha: 0.38),
              height: 1.4,
            ),
          ),

          // Live transcript while mic is active
          if (_micListening && _micText.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              _micText,
              style: GoogleFonts.dmSans(
                fontSize: 12,
                color: _csAmber,
                fontStyle: FontStyle.italic,
                height: 1.4,
              ),
            ),
          ],

          const SizedBox(height: 16),

          // Free-text field — white 16pt, no border
          TextField(
            controller: _ctrl,
            maxLines: null,
            minLines: 3,
            style: GoogleFonts.dmSans(
              fontSize: 16,
              color: Colors.white,
              height: 1.55,
            ),
            decoration: InputDecoration(
              hintText: 'Ask Cue anything about your clinical work...',
              hintStyle: GoogleFonts.dmSans(
                fontSize: 16,
                color: Colors.white.withValues(alpha: 0.4),
              ),
              filled: false,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
            ),
          ),
          const SizedBox(height: 12),

          // Submit — amber
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _loading ? null : _submit,
              style: ElevatedButton.styleFrom(
                backgroundColor: _csAmberDark,
                foregroundColor: Colors.white,
                disabledBackgroundColor: _csAmberDark.withValues(alpha: 0.4),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                elevation: 0,
              ),
              child: _loading
                  ? const SizedBox(
                      width: 18, height: 18,
                      child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2,
                      ),
                    )
                  : Text(
                      'Think with Cue →',
                      style: GoogleFonts.dmSans(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
            ),
          ),

          // Response card — amber left-bordered
          AnimatedSize(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
            alignment: Alignment.topCenter,
            child: (_loading || _response != null || _error != null)
                ? Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.06),
                        borderRadius:
                            const BorderRadius.all(Radius.circular(10)),
                        border: Border(
                          left: BorderSide(color: _csAmberDark, width: 2),
                        ),
                      ),
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'CUE STUDY',
                            style: GoogleFonts.dmSans(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: _csAmber,
                              letterSpacing: 1.2,
                            ),
                          ),
                          const SizedBox(height: 12),
                          if (_loading)
                            Center(
                              child: CircularProgressIndicator(
                                strokeWidth: 2, color: _csAmberDark,
                              ),
                            )
                          else if (_error != null)
                            Text(
                              _error!,
                              style: GoogleFonts.dmSans(
                                fontSize: 12, color: _red,
                              ),
                            )
                          else if (_response != null && _response!.isNotEmpty)
                            TweenAnimationBuilder<double>(
                              key: ValueKey(_response),
                              tween: Tween<double>(begin: 0.0, end: 1.0),
                              duration: const Duration(milliseconds: 400),
                              curve: Curves.easeIn,
                              builder: (ctx, value, child) => Opacity(
                                opacity: value,
                                child: Transform.translate(
                                  offset: Offset(0, (1.0 - value) * 8),
                                  child: child,
                                ),
                              ),
                              child: Text(
                                _response!,
                                style: GoogleFonts.dmSans(
                                  fontSize: 13,
                                  color: Colors.white.withValues(alpha: 0.82),
                                  height: 1.75,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}
