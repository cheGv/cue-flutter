// lib/screens/narrate_session_screen.dart
//
// Phase 4.0.7.9d — Whisper batch transcription via Supabase edge function.
//
// Replaces the prior Deepgram WebSocket streaming pipeline. Whisper handles
// Indian-English loanwords ("abbu", "amma", "dhido") that Deepgram nova-3
// mistranscribed (and that nova-3 multi rendered in Devanagari).
//
// Pipeline:
//   record (record pkg) → blob: URL → fetch bytes →
//   Supabase functions.invoke('narrator', body: bytes) →
//   { transcript, language, duration } → populate controller →
//   PATCH sessions.transcript → user taps Generate Report
//
// SOAP / parent-summary generation is unchanged (still hits the Render
// Anthropic proxy). This file owns audio capture + transcription only.
//
// Diagnostic instrumentation pattern from 4.0.7.7 is preserved with
// adapted layer tags. The print() calls are intentional diagnostics.
//
// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:record/record.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../widgets/app_layout.dart';
import 'report_screen.dart';

// State machine — kept minimal and explicit. No "connecting" intermediate
// since Whisper is batch (no socket open phase). `transcribing` covers the
// 2–5s window between Done tap and transcript arrival.
enum _NarrateStage { idle, recording, paused, transcribing, stopped }

class NarrateSessionScreen extends StatefulWidget {
  final String  clientId;
  final String  clientName;

  /// Pre-created session id (from AddSessionScreen). When provided the
  /// narrator updates that record before navigating.
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
  State<NarrateSessionScreen> createState() => _NarrateSessionScreenState();
}

class _NarrateSessionScreenState extends State<NarrateSessionScreen> {
  final _supabase = Supabase.instance.client;
  final AudioRecorder _recorder = AudioRecorder();

  String  _finalTranscript  = '';
  String  _detectedLanguage = '';
  String? _micError;
  _NarrateStage _stage      = _NarrateStage.idle;

  /// Cumulative wall-clock recording duration across pause/resume cycles.
  /// `_recordingStart` is set at the moment of each (re)start; on pause
  /// we add the delta to `_accumulatedSeconds` and reset.
  DateTime? _recordingStart;
  int _accumulatedSeconds = 0;
  Timer? _elapsedTicker;

  bool get _isRecording   => _stage == _NarrateStage.recording;
  bool get _isPaused      => _stage == _NarrateStage.paused;
  bool get _isTranscribing => _stage == _NarrateStage.transcribing;
  bool get _isStopped     => _stage == _NarrateStage.stopped;

  // ── Phase 4.0.7.7 diagnostic state — adapted layer tags ────────────────
  // L1 = mic + recorder, L2 = audio bytes capture, L3 = edge function
  // POST, L6 = transcript rendering, STATE = stage transitions, ERROR =
  // user-facing error UI triggers.
  final Map<String, String> _lastLogs = <String, String>{
    'L1':    '(no L1 events yet)',
    'L2':    '(no L2 events yet)',
    'L3':    '(no L3 events yet)',
    'L6':    '(no L6 events yet)',
    'STATE': '(no stage transitions yet)',
    'ERROR': '(no error events yet)',
  };
  bool _showDiagnostics = false;

  @override
  void initState() {
    super.initState();
    // Phase 4.0.7.9d task 5 — hydrate transcript from sessions row if
    // the SLP backed out and returned to this screen. The screen only
    // receives sessionId in its constructor, so we fetch the row.
    if (widget.sessionId != null) {
      _hydrateFromSession();
    }
  }

  Future<void> _hydrateFromSession() async {
    try {
      final row = await _supabase
          .from('sessions')
          .select('transcript')
          .eq('id', widget.sessionId!)
          .maybeSingle();
      final saved = (row?['transcript'] as String?)?.trim();
      if (saved != null && saved.isNotEmpty && mounted) {
        setState(() {
          _finalTranscript = saved;
          _setStage(_NarrateStage.stopped, 'hydrated from sessions.transcript');
        });
        _log('L6',
            'hydrated transcript from session row, length=${saved.length}');
      }
    } catch (e) {
      _log('L3', 'hydration query failed: $e');
    }
  }

  @override
  void dispose() {
    _elapsedTicker?.cancel();
    _recorder.dispose();
    super.dispose();
  }

  // ── Diagnostic helpers ─────────────────────────────────────────────────
  void _log(String layer, String msg) {
    final stamp = DateTime.now().toIso8601String().substring(11, 23);
    print('[narrator][$layer] $msg');
    _lastLogs[layer] = '$stamp $msg';
  }

  void _setStage(_NarrateStage next, String trigger) {
    if (_stage == next) return;
    _log('STATE', 'transition ${_stage.name} -> ${next.name}, trigger=$trigger');
    _stage = next;
  }

  void _setError(String userMessage, String triggerCondition) {
    _log(
      'ERROR',
      'showing user-facing error UI, message="$userMessage", '
      'trigger=$triggerCondition, stage=${_stage.name}, '
      'word_count=$_wordCount, '
      'accumulated_seconds=$_accumulatedSeconds',
    );
    _micError = userMessage;
  }

  // ── Recording lifecycle ────────────────────────────────────────────────

  Future<void> _startRecording() async {
    _log('STATE', '_startRecording invoked, current=${_stage.name}');
    setState(() {
      _micError = null;
    });

    // Permission gate. AudioRecorder.hasPermission() returns the actual
    // OS / browser state (web triggers the prompt if not yet granted).
    bool granted;
    try {
      _log('L1', 'requesting microphone permission via record pkg');
      granted = await _recorder.hasPermission();
    } catch (e) {
      _log('L1', 'hasPermission threw: $e');
      setState(() => _setError(
        'Could not access microphone. Check browser permission and try again.',
        'recorder.hasPermission threw: $e',
      ));
      return;
    }
    if (!granted) {
      _log('L1', 'microphone permission DENIED');
      setState(() => _setError(
        'Microphone access needed. Allow microphone permission in your browser settings.',
        'recorder.hasPermission returned false',
      ));
      return;
    }
    _log('L1', 'microphone permission GRANTED');

    try {
      const config = RecordConfig(
        encoder:     AudioEncoder.opus,
        numChannels: 1,
        sampleRate:  16000,
      );
      // Path is a logical name — the record pkg writes to a blob: URL on
      // web; on native it's a file path. stop() returns the URL or path.
      final path = 'session_${DateTime.now().millisecondsSinceEpoch}.webm';
      _log('L1', 'starting recorder, encoder=opus, sampleRate=16000, '
          'channels=1, path="$path"');

      // Reset cumulative timer for a fresh take. Resume goes through
      // _resumeRecording, not this path.
      _accumulatedSeconds = 0;
      _finalTranscript    = '';
      _detectedLanguage   = '';

      await _recorder.start(config, path: path);
      _recordingStart = DateTime.now();
      _startElapsedTicker();

      setState(() {
        _setStage(_NarrateStage.recording, 'recorder.start success');
      });
    } catch (e) {
      _log('L1', 'recorder.start threw: $e');
      setState(() => _setError(
        'Could not start recording. Check your connection and try again.',
        'recorder.start exception: $e',
      ));
    }
  }

  Future<void> _pauseRecording() async {
    try {
      _log('L1', 'pausing recorder, state=${_stage.name}');
      await _recorder.pause();
      _accumulateElapsed();
      _stopElapsedTicker();
      setState(() => _setStage(_NarrateStage.paused, 'user tapped pause'));
    } catch (e) {
      _log('L1', 'recorder.pause threw: $e');
    }
  }

  Future<void> _resumeRecording() async {
    try {
      _log('L1', 'resuming recorder, state=${_stage.name}');
      await _recorder.resume();
      _recordingStart = DateTime.now();
      _startElapsedTicker();
      setState(() =>
          _setStage(_NarrateStage.recording, 'user tapped resume'));
    } catch (e) {
      _log('L1', 'recorder.resume threw: $e');
      setState(() => _setError(
        'Could not resume recording. Tap to start a new recording.',
        'recorder.resume exception: $e',
      ));
    }
  }

  /// Done — stop the recorder, fetch the captured bytes, POST to the
  /// Supabase narrator edge function, populate the transcript, persist
  /// to sessions.transcript, terminal stopped state.
  Future<void> _finishRecording() async {
    _accumulateElapsed();
    _stopElapsedTicker();

    String? path;
    try {
      _log('L1', 'stopping recorder, state=${_stage.name}, '
          'accumulated_seconds=$_accumulatedSeconds');
      path = await _recorder.stop();
    } catch (e) {
      _log('L1', 'recorder.stop threw: $e');
      setState(() => _setError(
        'Recording could not be saved. Try again.',
        'recorder.stop exception: $e',
      ));
      return;
    }

    if (path == null) {
      _log('L2', 'recorder.stop returned null path — no audio captured');
      setState(() => _setError(
        'No audio captured. Tap to start recording again.',
        'recorder.stop returned null path',
      ));
      return;
    }

    // Guard against a too-short take — Whisper rejects it with
    // no_speech_detected anyway, but a local check gives a faster error.
    if (_accumulatedSeconds < 2) {
      _log('L2', 'recording too short, accumulated_seconds=$_accumulatedSeconds');
      setState(() => _setError(
        'Recording was too short. Hold the mic and speak for a few seconds.',
        'accumulated_seconds < 2',
      ));
      return;
    }

    setState(() {
      _setStage(_NarrateStage.transcribing, 'user tapped Done');
    });

    // ── Layer 2: pull bytes off the blob URL / file path ────────────
    Uint8List audioBytes;
    try {
      _log('L2', 'fetching recorded bytes from path="$path"');
      final res = await http.get(Uri.parse(path));
      audioBytes = res.bodyBytes;
      _log('L2', 'audio bytes captured, size=${audioBytes.length}, '
          'http_status=${res.statusCode}');
      if (audioBytes.isEmpty) {
        throw StateError('blob fetch returned 0 bytes');
      }
    } catch (e) {
      _log('L2', 'blob fetch threw: $e');
      setState(() => _setError(
        'Could not read the recording. Try again.',
        'blob fetch exception: $e',
      ));
      return;
    }

    // ── Layer 3: POST to Supabase narrator edge function ─────────────
    // Equivalent to a raw POST against
    //   $SUPABASE_URL/functions/v1/narrator
    // with headers { apikey, Authorization: Bearer <anon>,
    // Content-Type: application/octet-stream } and body = audioBytes.
    // functions.invoke wires apikey + bearer automatically.
    Map<String, dynamic> data;
    try {
      _log('L3', 'POST narrator edge function, body_size=${audioBytes.length}');
      final response = await _supabase.functions.invoke(
        'narrator',
        body: audioBytes,
        headers: const {'Content-Type': 'application/octet-stream'},
      );
      final raw = response.data;
      _log('L3', 'edge function returned, '
          'status=${response.status}, '
          'data_type=${raw.runtimeType}');
      if (raw is Map<String, dynamic>) {
        data = raw;
      } else if (raw is Map) {
        data = Map<String, dynamic>.from(raw);
      } else {
        throw StateError(
            'unexpected response shape: ${raw.runtimeType}');
      }
    } catch (e) {
      _log('L3', 'edge function call threw: $e');
      setState(() {
        _setError(
          'Transcription failed. Check your connection and try again.',
          'functions.invoke exception: $e',
        );
        _setStage(_NarrateStage.paused, 'transcription error fallback');
      });
      return;
    }

    final errCode = data['error'] as String?;
    if (errCode != null) {
      final humanMsg = errCode == 'no_speech_detected'
          ? 'No speech detected. Make sure your mic is working and speak clearly.'
          : 'Transcription failed: $errCode. Try again.';
      _log('L3', 'edge function returned error="$errCode"');
      setState(() {
        _setError(humanMsg, 'edge function returned error="$errCode"');
        _setStage(_NarrateStage.paused, 'edge function error response');
      });
      return;
    }

    final transcript = (data['transcript'] as String?)?.trim() ?? '';
    final language   = (data['language']   as String?) ?? '';
    if (transcript.isEmpty) {
      _log('L6', 'edge function returned empty transcript');
      setState(() {
        _setError(
          'Whisper returned no text. Try again.',
          'transcript empty in 200 response',
        );
        _setStage(_NarrateStage.paused, 'empty transcript fallback');
      });
      return;
    }
    _log('L6', 'transcript received, length=${transcript.length}, '
        'language="$language", duration=${data['duration']}');

    setState(() {
      _finalTranscript  = transcript;
      _detectedLanguage = language;
      _setStage(_NarrateStage.stopped, 'transcription succeeded');
    });

    // ── Persist transcript to sessions row ─────────────────────────────
    // Single PATCH; runs after stage flip so the UI shows the transcript
    // immediately even if the network is slow. Failure is logged and
    // surfaces a SnackBar; the in-memory transcript is still usable for
    // Generate Report (the report screen will re-persist via 4.0.7.9a).
    if (widget.sessionId != null) {
      try {
        _log('L3', 'persisting transcript to sessions row, '
            'id=${widget.sessionId}');
        await _supabase
            .from('sessions')
            .update({
              'transcript':   transcript,
              'ai_generated': false,
            })
            .eq('id', widget.sessionId!);
      } catch (e) {
        _log('L3', 'sessions.transcript PATCH failed: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                  "Couldn't save transcript — Generate Report will retry."),
            ),
          );
        }
      }
    }
  }

  // ── Elapsed-time helpers ───────────────────────────────────────────────
  void _startElapsedTicker() {
    _elapsedTicker?.cancel();
    _elapsedTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {});
    });
  }

  void _stopElapsedTicker() {
    _elapsedTicker?.cancel();
    _elapsedTicker = null;
  }

  void _accumulateElapsed() {
    if (_recordingStart != null) {
      _accumulatedSeconds +=
          DateTime.now().difference(_recordingStart!).inSeconds;
      _recordingStart = null;
    }
  }

  int get _liveSeconds {
    if (_recordingStart == null) return _accumulatedSeconds;
    return _accumulatedSeconds +
        DateTime.now().difference(_recordingStart!).inSeconds;
  }

  String _formatElapsed(int seconds) {
    final m = (seconds ~/ 60).toString().padLeft(2, '0');
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  int get _wordCount => _finalTranscript.isEmpty
      ? 0
      : _finalTranscript.trim().split(' ').where((w) => w.isNotEmpty).length;

  // ── Generate & navigate ─────────────────────────────────────────────────
  // Unchanged contract: hand the transcript to ReportScreen which owns
  // the Anthropic /generate-report flow + persistence (4.0.7.9a).
  void _generateAndNavigate() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => ReportScreen(
          session: {
            'id':         widget.sessionId,
            'transcript': _finalTranscript.trim(),
          },
          clientName: widget.clientName,
          clientId:   widget.clientId,
        ),
      ),
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────
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
                  // ── Detected-language label (Whisper returns one) ─────
                  if (_detectedLanguage.isNotEmpty &&
                      !_isRecording && !_isPaused) ...[
                    Text(
                      'Detected: $_detectedLanguage',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: teal,
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // ── Error state + retry + diagnostic panel ─────────────
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
                    const SizedBox(height: 12),
                    _buildDiagnosticPanel(ink: ink),
                    const SizedBox(height: 32),
                  ],

                  // ── Mic button ────────────────────────────────────────
                  if (_micError == null && !_isStopped && !_isTranscribing) ...[
                    GestureDetector(
                      onTap: _isRecording
                          ? _pauseRecording
                          : (_isPaused ? _resumeRecording : _startRecording),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        width:  _isRecording ? 80 : 72,
                        height: _isRecording ? 80 : 72,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _isRecording
                              ? const Color(0xFFEF4444)
                              : const Color(0xFF1D9E75),
                        ),
                        child: Icon(
                          _isRecording
                              ? Icons.pause_rounded
                              : Icons.mic_rounded,
                          color: Colors.white,
                          size:  32,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],

                  // ── Transcribing spinner ──────────────────────────────
                  if (_isTranscribing) ...[
                    const SizedBox(
                      width:  56,
                      height: 56,
                      child: CircularProgressIndicator(
                        color:       Color(0xFF1D9E75),
                        strokeWidth: 2.5,
                      ),
                    ),
                    const SizedBox(height: 18),
                    const Text(
                      'Transcribing… this usually takes 2–5 seconds.',
                      style: TextStyle(fontSize: 13, color: Color(0xFF6B6B6B)),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                  ],

                  // ── Status label + elapsed time ───────────────────────
                  if (!_isTranscribing) ...[
                    Text(
                      _isStopped
                          ? 'Recording transcribed. Generate the report below.'
                          : _isRecording
                              ? 'Tap to pause · ${_formatElapsed(_liveSeconds)}'
                              : _isPaused
                                  ? 'Paused at ${_formatElapsed(_liveSeconds)} — tap to resume, or Done to transcribe'
                                  : _finalTranscript.isEmpty
                                      ? 'Tap the microphone and speak'
                                      : 'Recording transcribed. Generate the report below.',
                      style: TextStyle(
                        fontSize: 13,
                        color:    ink.withValues(alpha: 0.55),
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],

                  // ── Done button — visible while recording or paused
                  // with at least 2 seconds of audio captured. Triggers
                  // batch transcription.
                  if ((_isRecording || _isPaused) && _liveSeconds >= 2) ...[
                    const SizedBox(height: 16),
                    OutlinedButton.icon(
                      onPressed: _finishRecording,
                      icon: const Icon(Icons.check_rounded, size: 18),
                      label: const Text('Done'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF1D9E75),
                        side: const BorderSide(
                            color: Color(0xFF1D9E75), width: 1),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 10),
                        minimumSize: Size.zero,
                      ),
                    ),
                  ],

                  // ── Final transcript ──────────────────────────────────
                  if (_finalTranscript.isNotEmpty) ...[
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
                      child: Text(
                        _finalTranscript,
                        style: const TextStyle(
                          fontSize: 15,
                          color:    Color(0xFF0A0A0A),
                          height:   1.7,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '$_wordCount words',
                      style: TextStyle(
                        fontSize: 11,
                        color:    ink.withValues(alpha: 0.45),
                      ),
                    ),
                  ],

                  // ── Generate report button ────────────────────────────
                  // Surfaces once we have a transcript that's been
                  // committed to terminal stopped state.
                  if (_isStopped && _finalTranscript.trim().isNotEmpty) ...[
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

  // ── Diagnostic panel (4.0.7.7 pattern, adapted layer set) ──────────────
  Widget _buildDiagnosticPanel({required Color ink}) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 480),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: TextButton(
              onPressed: () =>
                  setState(() => _showDiagnostics = !_showDiagnostics),
              style: TextButton.styleFrom(
                foregroundColor: ink.withValues(alpha: 0.55),
                textStyle: const TextStyle(fontSize: 11),
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 4),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(
                _showDiagnostics
                    ? 'Hide diagnostic details'
                    : 'Show diagnostic details',
              ),
            ),
          ),
          if (_showDiagnostics) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color:        const Color(0xFFFAFAFA),
                border:       Border.all(
                    color: const Color(0xFFE5E7EB), width: 0.5),
                borderRadius: BorderRadius.circular(8),
              ),
              child: DefaultTextStyle(
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize:   10.5,
                  height:     1.5,
                  color:      ink.withValues(alpha: 0.80),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('stage:           ${_stage.name}'),
                    Text('word_count:      $_wordCount'),
                    Text('elapsed_seconds: $_accumulatedSeconds'),
                    Text('detected_lang:   $_detectedLanguage'),
                    const SizedBox(height: 8),
                    Text('[L1]    ${_lastLogs['L1']}'),
                    const SizedBox(height: 4),
                    Text('[L2]    ${_lastLogs['L2']}'),
                    const SizedBox(height: 4),
                    Text('[L3]    ${_lastLogs['L3']}'),
                    const SizedBox(height: 4),
                    Text('[L6]    ${_lastLogs['L6']}'),
                    const SizedBox(height: 4),
                    Text('[STATE] ${_lastLogs['STATE']}'),
                    const SizedBox(height: 4),
                    Text('[ERROR] ${_lastLogs['ERROR']}'),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
