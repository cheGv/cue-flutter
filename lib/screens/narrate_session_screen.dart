import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:speech_to_text/speech_to_text.dart';
import 'add_session_screen.dart';
import 'narrator_screen.dart';

class NarrateSessionScreen extends StatefulWidget {
  final String clientId;
  final String clientName;

  const NarrateSessionScreen({
    super.key,
    required this.clientId,
    required this.clientName,
  });

  @override
  State<NarrateSessionScreen> createState() => _NarrateSessionScreenState();
}

class _NarrateSessionScreenState extends State<NarrateSessionScreen>
    with SingleTickerProviderStateMixin {
  static const _narrateUrl =
      'https://cue-ai-proxy.onrender.com/narrate-session';

  final SpeechToText _speech = SpeechToText();

  bool _speechAvailable = false;
  bool _isListening = false;
  bool _isGenerating = false;
  String _transcript = '';
  String _statusMessage = 'Initialising microphone…';

  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.14).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _initSpeech();
  }

  Future<void> _initSpeech() async {
    final available = await _speech.initialize(
      onStatus: _onStatus,
      onError: (e) {
        if (mounted) {
          setState(() {
            _isListening = false;
            _statusMessage =
                'Microphone error — check browser permissions and try again.';
          });
        }
      },
    );
    if (mounted) {
      setState(() {
        _speechAvailable = available;
        _statusMessage = available
            ? 'Tap the microphone and speak your session notes'
            : 'Speech recognition is not available in this browser.\nTry Chrome or Edge.';
      });
    }
  }

  void _onStatus(String status) {
    if (!mounted) return;
    setState(() {
      _isListening = _speech.isListening;
      if (status == 'done' || status == 'notListening') {
        if (_transcript.isNotEmpty) {
          _statusMessage = 'Recording complete — review transcript below.';
        } else {
          _statusMessage = 'Tap the microphone and speak your session notes';
        }
      }
    });
  }

  Future<void> _toggleListening() async {
    if (!_speechAvailable) return;

    if (_isListening) {
      await _speech.stop();
      setState(() {
        _isListening = false;
        _statusMessage = _transcript.isNotEmpty
            ? 'Recording complete — review transcript below.'
            : 'Tap the microphone and speak your session notes';
      });
      return;
    }

    // Start fresh recording
    setState(() {
      _transcript = '';
      _isListening = true;
      _statusMessage = 'Listening… speak clearly';
    });

    await _speech.listen(
      onResult: (result) {
        if (mounted) {
          setState(() => _transcript = result.recognizedWords);
        }
      },
      listenFor: const Duration(minutes: 5),
      pauseFor: const Duration(seconds: 6),
      partialResults: true,
      localeId: 'en_IN',
      listenMode: ListenMode.dictation,
      cancelOnError: false,
    );
  }

  Future<void> _generateFromNarration() async {
    final transcript = _transcript.trim();
    if (transcript.isEmpty) return;

    setState(() => _isGenerating = true);
    try {
      final response = await http.post(
        Uri.parse(_narrateUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'transcript': transcript,
          'clientName': widget.clientName,
        }),
      );

      if (!mounted) return;

      if (response.statusCode == 200) {
        final apiData = jsonDecode(response.body);
        final rawText =
            (apiData['content']?[0]?['text'] ?? '').toString().trim();

        // Strip any accidental markdown fences Claude might add
        final jsonText = rawText
            .replaceAll(RegExp(r'^```json\s*', multiLine: false), '')
            .replaceAll(RegExp(r'^```\s*', multiLine: false), '')
            .replaceAll(RegExp(r'\s*```$', multiLine: false), '')
            .trim();

        Map<String, dynamic> sessionData;
        try {
          sessionData = jsonDecode(jsonText) as Map<String, dynamic>;
        } on FormatException {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                  'Could not parse session data — please try narrating again.'),
            ),
          );
          return;
        }

        final saved = await Navigator.push<bool>(
          context,
          MaterialPageRoute(
            builder: (_) => AddSessionScreen(
              clientId: widget.clientId,
              clientName: widget.clientName,
              prefillData: {
                ...sessionData,
                'transcript': transcript,
              },
            ),
          ),
        );

        if (saved == true && mounted) {
          Navigator.pop(context, true);
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
                  'Server error ${response.statusCode}: ${response.body}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to connect to AI service: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isGenerating = false);
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _speech.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasTranscript = _transcript.isNotEmpty;
    final showGenerateButton = hasTranscript && !_isListening;

    return Scaffold(
      appBar: AppBar(
        title: Text('Narrate Session — ${widget.clientName}'),
        backgroundColor: const Color(0xFF00897B),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.graphic_eq_rounded),
            tooltip: 'Narrator',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const NarratorScreen()),
              );
            },
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          children: [
            const SizedBox(height: 36),

            // ── Status message ─────────────────────────────────────────
            Text(
              _statusMessage,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                height: 1.5,
                color: _isListening
                    ? const Color(0xFF00897B)
                    : Colors.grey.shade600,
                fontWeight:
                    _isListening ? FontWeight.w600 : FontWeight.normal,
              ),
            ),

            const SizedBox(height: 40),

            // ── Microphone button ──────────────────────────────────────
            ScaleTransition(
              scale: _isListening
                  ? _pulseAnimation
                  : const AlwaysStoppedAnimation(1.0),
              child: GestureDetector(
                onTap: _speechAvailable ? _toggleListening : null,
                child: Container(
                  width: 104,
                  height: 104,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: !_speechAvailable
                        ? Colors.grey.shade300
                        : _isListening
                            ? Colors.red.shade400
                            : const Color(0xFF00897B),
                    boxShadow: [
                      BoxShadow(
                        color: (!_speechAvailable
                                ? Colors.grey
                                : _isListening
                                    ? Colors.red
                                    : const Color(0xFF00897B))
                            .withOpacity(0.30),
                        blurRadius: _isListening ? 24 : 14,
                        spreadRadius: _isListening ? 6 : 2,
                      ),
                    ],
                  ),
                  child: Icon(
                    _isListening
                        ? Icons.stop_rounded
                        : Icons.mic_rounded,
                    size: 46,
                    color: Colors.white,
                  ),
                ),
              ),
            ),

            const SizedBox(height: 14),

            Text(
              _isListening
                  ? 'Tap to stop recording'
                  : hasTranscript
                      ? 'Tap to re-record'
                      : '',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
            ),

            const SizedBox(height: 28),

            // ── Transcript card ────────────────────────────────────────
            if (hasTranscript)
              Expanded(
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.teal.shade100),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.record_voice_over_rounded,
                              size: 15, color: Colors.teal.shade600),
                          const SizedBox(width: 6),
                          Text(
                            'TRANSCRIPT',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: Colors.teal.shade600,
                              letterSpacing: 1.0,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Expanded(
                        child: SingleChildScrollView(
                          child: Text(
                            _transcript,
                            style: const TextStyle(
                              fontSize: 15,
                              height: 1.65,
                              color: Color(0xFF212121),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else
              const Spacer(),

            // ── Generate button ────────────────────────────────────────
            if (showGenerateButton) ...[
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 54,
                child: FilledButton.icon(
                  onPressed: _isGenerating ? null : _generateFromNarration,
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF00897B),
                    disabledBackgroundColor:
                        const Color(0xFF00897B).withOpacity(0.5),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  icon: _isGenerating
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2),
                        )
                      : const Icon(Icons.auto_awesome_rounded),
                  label: Text(
                    _isGenerating
                        ? 'Extracting session data…'
                        : 'Generate from Narration',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],

            const SizedBox(height: 28),
          ],
        ),
      ),
    );
  }
}
