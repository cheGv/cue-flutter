// lib/screens/narrate_session_screen.dart
// Deepgram live transcription narrator — replaces Web Speech API entirely.
// MediaRecorder (webm/opus) → WebSocket proxy → Deepgram nova-2 multi-language.

import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../narrate_web_audio.dart';
import '../widgets/app_layout.dart';
import 'report_screen.dart';

class NarrateSessionScreen extends StatefulWidget {
  final String  clientId;
  final String  clientName;

  /// Pre-created session id (from AddSessionScreen).
  /// When provided the narrator updates that record before navigating.
  final String? sessionId;
  final String? sessionDate;

  const NarrateSessionScreen({
    super.key,
    required this.clientId,
    required this.clientName,
    this.sessionId,
    this.sessionDate,
  });

  @override
  State<NarrateSessionScreen> createState() =>
      _NarrateSessionScreenState();
}

class _NarrateSessionScreenState extends State<NarrateSessionScreen> {
  final _supabase = Supabase.instance.client;

  // ── State ────────────────────────────────────────────────────────────────

  WebSocketChannel? _channel;
  String  _finalTranscript  = '';
  String  _interimText      = '';
  bool    _isRecording      = false;
  bool    _isConnecting     = false;
  String  _detectedLanguage = '';
  String? _micError;

  // ── Recording ─────────────────────────────────────────────────────────────

  Future<void> _startRecording() async {
    setState(() {
      _isConnecting    = true;
      _micError        = null;
      _finalTranscript = '';
      _interimText     = '';
      _detectedLanguage = '';
    });

    try {
      // 1. Connect WebSocket to proxy
      _channel = WebSocketChannel.connect(
        Uri.parse('wss://cue-ai-proxy.onrender.com/transcribe'),
      );

      // 2. Listen for transcript events
      _channel!.stream.listen(
        _onTranscriptReceived,
        onError: _onWebSocketError,
        onDone:  _onWebSocketDone,
      );

      // 3. Request microphone — mono 16 kHz to match Deepgram config
      final constraints = <String, dynamic>{
        'audio': {
          'channelCount':    1,
          'sampleRate':      16000,
          'echoCancellation': true,
          'noiseSuppression': true,
        },
      }.jsify();

      final stream = await getUserMedia(constraints!).toDart;

      // 4. Create MediaRecorder — let browser choose encoding so Deepgram can auto-detect
      final options  = <String, dynamic>{}.jsify();

      final recorder = MediaRecorder(stream!, options!);

      // 5. On each chunk: read Blob → ArrayBuffer → Uint8List → WS sink
      recorder.onDataAvailable = (BlobEvent event) {
        final reader = FileReader();
        reader.onLoadEnd = (JSAny _) {
          // Cast JSAny → JSArrayBuffer for toDart conversion
          final buffer = (reader.result as JSArrayBuffer).toDart;
          final bytes  = Uint8List.view(buffer);
          if (_channel != null && _isRecording && bytes.isNotEmpty) {
            _channel!.sink.add(bytes);
          }
        }.toJS;
        reader.readAsArrayBuffer(event.data);
      }.toJS;

      recorder.start(250); // 250 ms chunks

      setState(() {
        _isRecording  = true;
        _isConnecting = false;
      });

    } catch (e) {
      setState(() {
        _isConnecting = false;
        _micError = e.toString().contains('Permission') ||
                    e.toString().contains('NotAllowed')
            ? 'Microphone access needed. Allow microphone permission in your browser settings.'
            : 'Could not start recording. Check your connection and try again.';
      });
    }
  }

  void _stopRecording() {
    _channel?.sink.close();
    _channel = null;
    setState(() {
      _isRecording = false;
      _interimText = '';
    });
  }

  // ── WebSocket handlers ────────────────────────────────────────────────────

  void _onTranscriptReceived(dynamic message) {
    print('[narrator] received: $message');
    final data = jsonDecode(message as String) as Map<String, dynamic>;

    if (data['type'] == 'transcript') {
      if (data['is_final'] == true) {
        setState(() {
          _finalTranscript += '${data['text'] as String} ';
          _interimText      = '';
          if (data['language'] != null) {
            _detectedLanguage = _languageName(data['language'] as String);
          }
        });
      } else {
        setState(() {
          _interimText = data['text'] as String;
        });
      }
    } else if (data['type'] == 'error') {
      setState(() {
        _micError    = data['message'] as String;
        _isRecording = false;
      });
    }
  }

  void _onWebSocketError(dynamic error) {
    setState(() {
      _micError    = 'Connection lost. Tap to retry.';
      _isRecording = false;
    });
  }

  void _onWebSocketDone() {
    if (_isRecording) {
      setState(() => _isRecording = false);
    }
  }

  // ── Generate & navigate ───────────────────────────────────────────────────

  Future<void> _generateAndNavigate() async {
    // Save transcript to session record if we have an id
    if (widget.sessionId != null) {
      await _supabase
          .from('sessions')
          .update({'narrator_transcript': _finalTranscript.trim()})
          .eq('id', widget.sessionId!);
    }

    if (!mounted) return;

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => ReportScreen(
          session: {
            'id':                  widget.sessionId,
            'narrator_transcript': _finalTranscript.trim(),
          },
          clientName: widget.clientName,
          clientId:   widget.clientId,
        ),
      ),
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  String _languageName(String code) {
    const map = <String, String>{
      'te':    'Telugu',
      'hi':    'Hindi',
      'ta':    'Tamil',
      'kn':    'Kannada',
      'ml':    'Malayalam',
      'mr':    'Marathi',
      'gu':    'Gujarati',
      'bn':    'Bengali',
      'pa':    'Punjabi',
      'en':    'English',
      'en-IN': 'English',
      'multi': 'Auto-detecting',
    };
    return map[code] ?? code.toUpperCase();
  }

  int get _wordCount => _finalTranscript.isEmpty
      ? 0
      : _finalTranscript.trim().split(' ').where((w) => w.isNotEmpty).length;

  @override
  void dispose() {
    _channel?.sink.close();
    super.dispose();
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final cs   = Theme.of(context).colorScheme;
    final teal = cs.primary;
    final ink  = cs.onSurface;

    return AppLayout(
      title:       'Narrate — ${widget.clientName}',
      activeRoute: 'roster',
      body: LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            padding: EdgeInsets.symmetric(
              horizontal: constraints.maxWidth < 600 ? 24 : 80,
              vertical:   40,
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [

                  // ── Language detection chip ─────────────────────────────
                  if (_detectedLanguage.isNotEmpty) ...[
                    Chip(
                      label: Text(
                        _detectedLanguage,
                        style: TextStyle(
                          fontSize:   11,
                          fontWeight: FontWeight.w600,
                          color:      teal,
                        ),
                      ),
                      backgroundColor: teal.withValues(alpha: 0.08),
                      side:            BorderSide.none,
                      padding:         const EdgeInsets.symmetric(
                                          horizontal: 4),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // ── Error state ─────────────────────────────────────────
                  if (_micError != null) ...[
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 320),
                      child: Text(
                        _micError!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 13,
                          color:    Color(0xFFEF4444),
                          height:   1.5,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    OutlinedButton(
                      onPressed: _startRecording,
                      child:     const Text('Retry'),
                    ),
                    const SizedBox(height: 32),
                  ],

                  // ── Mic button ──────────────────────────────────────────
                  if (_micError == null) ...[
                    GestureDetector(
                      onTap: _isConnecting
                          ? null
                          : _isRecording ? _stopRecording : _startRecording,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        width:  _isRecording ? 80 : 72,
                        height: _isRecording ? 80 : 72,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _isConnecting
                              ? Colors.grey
                              : _isRecording
                                  ? const Color(0xFFEF4444)
                                  : const Color(0xFF1D9E75),
                        ),
                        child: _isConnecting
                            ? const Center(
                                child: SizedBox(
                                  width:  28,
                                  height: 28,
                                  child:  CircularProgressIndicator(
                                    color:       Colors.white,
                                    strokeWidth: 2.5,
                                  ),
                                ),
                              )
                            : Icon(
                                _isRecording
                                    ? Icons.stop_rounded
                                    : Icons.mic_rounded,
                                color: Colors.white,
                                size:  32,
                              ),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],

                  // ── Status label ────────────────────────────────────────
                  Text(
                    _isConnecting
                        ? 'Connecting…'
                        : _isRecording
                            ? 'Tap to stop'
                            : _finalTranscript.isEmpty
                                ? 'Tap the microphone and speak'
                                : 'Tap to continue recording',
                    style: TextStyle(
                      fontSize: 13,
                      color:    ink.withValues(alpha: 0.55),
                    ),
                  ),

                  // ── Live transcript ─────────────────────────────────────
                  if (_finalTranscript.isNotEmpty ||
                      _interimText.isNotEmpty) ...[
                    const SizedBox(height: 32),
                    Container(
                      width:   double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color:        Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: const Color(0xFFE5E7EB),
                          width: 0.5,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (_finalTranscript.isNotEmpty)
                            Text(
                              _finalTranscript,
                              style: const TextStyle(
                                fontSize: 15,
                                color:    Color(0xFF0A0A0A),
                                height:   1.7,
                              ),
                            ),
                          if (_interimText.isNotEmpty)
                            Text(
                              _interimText,
                              style: TextStyle(
                                fontSize:  15,
                                fontStyle: FontStyle.italic,
                                color:     const Color(0xFF0A0A0A)
                                    .withValues(alpha: 0.60),
                                height:    1.7,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],

                  // ── Word count ──────────────────────────────────────────
                  if (_finalTranscript.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      '$_wordCount words',
                      style: TextStyle(
                        fontSize: 11,
                        color:    ink.withValues(alpha: 0.45),
                      ),
                    ),
                  ],

                  // ── Generate report button (>20 words) ──────────────────
                  if (_wordCount > 20) ...[
                    const SizedBox(height: 32),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: _generateAndNavigate,
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF1D9E75),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                        child: const Text(
                          'Generate Report →',
                          style: TextStyle(
                            fontSize:   15,
                            fontWeight: FontWeight.w500,
                            color:      Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ],

                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
