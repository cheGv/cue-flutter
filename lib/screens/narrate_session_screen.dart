// lib/screens/narrate_session_screen.dart
// Deepgram live transcription narrator — replaces Web Speech API entirely.
// MediaRecorder (webm/opus) → WebSocket proxy → Deepgram nova-2 multi-language.
//
// Phase 4.0.7.7 — structured diagnostic logging at every layer.
// Layer tags: [L1] mic + MediaStream, [L2] MediaRecorder, [L3] WebSocket,
// [L6] transcript rendering, [STATE] stage transitions, [ERROR] user-facing
// error UI triggers. The print() calls here are intentional diagnostic
// instrumentation; the avoid_print info is suppressed file-wide.

// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../narrate_web_audio.dart';
import '../widgets/app_layout.dart';
import 'report_screen.dart';

// Phase 4.0.7.6 — explicit narrator lifecycle.
//   idle       → no active recording, no transcript yet.
//   recording  → mic streaming bytes to the proxy.
//   paused     → mic paused, transcript preserved, can resume from same UI.
//                The mic toggle moves between recording ↔ paused.
//   stopped    → terminal. Media + WebSocket fully released. Generate
//                Report is the only forward action. Mic button is hidden.
enum _NarrateStage { idle, recording, paused, stopped }

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
  MediaRecorder?    _recorder;
  MediaStream?      _mediaStream;
  String  _finalTranscript  = '';
  String  _interimText      = '';
  _NarrateStage _stage      = _NarrateStage.idle;
  bool    _isConnecting     = false;
  String  _detectedLanguage = '';
  String? _micError;

  bool get _isRecording => _stage == _NarrateStage.recording;
  bool get _isStopped   => _stage == _NarrateStage.stopped;

  // ── Phase 4.0.7.7 diagnostic state ─────────────────────────────────────
  // Last log per layer is shown in the on-screen diagnostic panel when the
  // error UI surfaces, so the SLP can screenshot it without opening
  // devtools. Every entry is also printed to console with the same prefix.
  final Map<String, String> _lastLogs = <String, String>{
    'L1':    '(no L1 events yet)',
    'L2':    '(no L2 events yet)',
    'L3':    '(no L3 events yet)',
    'L6':    '(no L6 events yet)',
    'STATE': '(no stage transitions yet)',
    'ERROR': '(no error events yet)',
  };
  DateTime? _lastChunkAt;
  bool _showDiagnostics = false;
  int _wsSendCount = 0;
  int _wsRecvCount = 0;
  int _l2ChunkCount = 0;

  /// Structured diagnostic log. Goes to console with the prefix
  /// `[narrator][LAYER] msg` and is captured per-layer for the on-screen
  /// panel.
  void _log(String layer, String msg) {
    final stamp = DateTime.now().toIso8601String().substring(11, 23);
    final line = '$stamp $msg';
    print('[narrator][$layer] $msg');
    _lastLogs[layer] = line;
  }

  /// Wrapper for stage transitions so every transition is logged with its
  /// trigger. Setter, not method, so the call site stays tight.
  void _setStage(_NarrateStage next, String trigger) {
    if (_stage == next) return;
    _log('STATE', 'transition ${_stage.name} -> ${next.name}, trigger=$trigger');
    _stage = next;
  }

  /// Single funnel for setting `_micError`. Logs the trigger reason and
  /// captures the diagnostic snapshot at the moment the error UI surfaces.
  /// THIS IS THE LOG that names *why* the SLP saw "Transcription error".
  void _setError(String userMessage, String triggerCondition) {
    _log(
      'ERROR',
      "showing user-facing error UI, message=\"$userMessage\", "
      'trigger=$triggerCondition, stage=${_stage.name}, '
      'word_count=$_wordCount, '
      'wsSendCount=$_wsSendCount, wsRecvCount=$_wsRecvCount, '
      'l2ChunkCount=$_l2ChunkCount, '
      'last_chunk_age=${_secondsSinceLastChunk()}s',
    );
    _micError = userMessage;
  }

  String _secondsSinceLastChunk() {
    if (_lastChunkAt == null) return 'never';
    final delta = DateTime.now().difference(_lastChunkAt!).inMilliseconds;
    return (delta / 1000).toStringAsFixed(1);
  }

  // ── Recording ─────────────────────────────────────────────────────────────

  Future<void> _startRecording() async {
    // Resume from a paused state preserves the existing transcript.
    final isResume = _stage == _NarrateStage.paused;
    _log('STATE',
        '_startRecording invoked, isResume=$isResume, current=${_stage.name}');
    setState(() {
      _isConnecting     = true;
      _micError         = null;
      if (!isResume) {
        _finalTranscript  = '';
        _detectedLanguage = '';
      }
      _interimText      = '';
    });

    try {
      // ── Layer 3: WebSocket to proxy ───────────────────────────────────
      const wsUrl = 'wss://cue-ai-proxy.onrender.com/transcribe';
      _log('L3', 'opening WebSocket to $wsUrl');
      _channel = WebSocketChannel.connect(Uri.parse(wsUrl));
      _wsSendCount = 0;
      _wsRecvCount = 0;

      _channel!.stream.listen(
        _onTranscriptReceived,
        onError: _onWebSocketError,
        onDone:  _onWebSocketDone,
      );
      // web_socket_channel does not surface a discrete OPEN event; the
      // connection is OPEN by the time the first send/recv succeeds. We
      // log the intent-to-open above; the next L3 lines on send/recv
      // confirm the channel is actually live.

      // ── Layer 1: microphone ───────────────────────────────────────────
      _log('L1', 'requesting microphone permission, '
          'constraints=channelCount=1,sampleRate=16000,echoCancel,noiseSup');

      final constraints = <String, dynamic>{
        'audio': {
          'channelCount':    1,
          'sampleRate':      16000,
          'echoCancellation': true,
          'noiseSuppression': true,
        },
      }.jsify();

      final stream =
          (await getUserMedia(constraints!).toDart) as MediaStream?;

      if (stream == null) {
        _log('L1', 'getUserMedia resolved with null stream — aborting');
        throw StateError('getUserMedia returned null');
      }

      final tracks = stream.getTracks().toDart;
      _log('L1', 'microphone permission GRANTED, '
          'MediaStream id=${stream.id}, tracks=${tracks.length}');
      for (var i = 0; i < tracks.length; i++) {
        final t = tracks[i];
        _log('L1', 'MediaStream track[$i]: '
            'kind=${t.kind}, label="${t.label}", readyState=${t.readyState}');
      }

      // ── Layer 2: MediaRecorder ────────────────────────────────────────
      final options  = <String, dynamic>{}.jsify();
      final recorder = MediaRecorder(stream, options!);
      _log('L2',
          'MediaRecorder created, mimeType="${recorder.mimeType}", '
          'state=${recorder.state}');

      recorder.onDataAvailable = (BlobEvent event) {
        final blob = event.data as Blob;
        final blobSize = blob.size;
        final blobType = blob.type;

        final reader = FileReader();
        reader.onLoadEnd = (JSAny _) {
          final buffer = (reader.result as JSArrayBuffer).toDart;
          final bytes  = Uint8List.view(buffer);
          _l2ChunkCount++;
          // L2 log on every Nth chunk only — at 250ms timeslices we'd flood
          // the console. First 5 chunks, then every 20th.
          if (_l2ChunkCount <= 5 || _l2ChunkCount % 20 == 0) {
            _log('L2', 'dataavailable chunk #$_l2ChunkCount, '
                'size=$blobSize, type="$blobType"');
          }
          if (_channel != null && _isRecording && bytes.isNotEmpty) {
            try {
              _channel!.sink.add(bytes);
              _wsSendCount++;
              _lastChunkAt = DateTime.now();
              if (_wsSendCount <= 5 || _wsSendCount % 20 == 0) {
                _log('L3', 'sent audio chunk #$_wsSendCount, '
                    'size=${bytes.length}');
              }
            } catch (e) {
              _log('L3', 'sink.add threw: $e');
            }
          } else if (bytes.isNotEmpty) {
            _log('L3', 'dropped chunk #$_l2ChunkCount '
                '(channel=${_channel != null}, isRecording=$_isRecording)');
          }
        }.toJS;
        reader.readAsArrayBuffer(blob);
      }.toJS;

      recorder.onError = (JSAny event) {
        try {
          final err = event as ErrorEvent;
          _log('L2',
              'MediaRecorder ERROR event, error="${err.error}", '
              'message="${err.message}"');
        } catch (_) {
          _log('L2', 'MediaRecorder ERROR event (uncastable): $event');
        }
      }.toJS;

      recorder.onStop = (JSAny _) {
        _log('L2', 'MediaRecorder onstop fired, '
            'final state=${_recorder?.state ?? "(null)"}');
      }.toJS;

      recorder.start(250);
      _log('L2', 'MediaRecorder started, timeslice=250ms, '
          'state=${recorder.state}');

      _recorder    = recorder;
      _mediaStream = stream;

      setState(() {
        _isConnecting = false;
      });
      _setStage(_NarrateStage.recording, 'startRecording success');
      setState(() {});

    } catch (e, st) {
      _log('L1', 'startRecording threw: $e');
      _log('L1', 'stack: ${st.toString().split("\n").take(3).join(" | ")}');
      final isPermission = e.toString().contains('Permission') ||
          e.toString().contains('NotAllowed');
      if (isPermission) {
        _log('L1', 'microphone permission DENIED, reason="$e"');
      }
      setState(() {
        _isConnecting = false;
        _setError(
          isPermission
              ? 'Microphone access needed. Allow microphone permission in your browser settings.'
              : 'Could not start recording. Check your connection and try again.',
          isPermission ? 'getUserMedia permission denied' : 'startRecording exception: $e',
        );
      });
    }
  }

  /// Phase 4.0.7.6 — release every media handle the start path acquired.
  /// MediaRecorder.stop() flushes pending dataavailable events. Each track
  /// must be stop()ed independently or the browser keeps the mic indicator
  /// on. WebSocket sink is closed last so any final bytes flushed by the
  /// recorder still reach the proxy.
  void _releaseMediaResources() {
    try {
      final r = _recorder;
      if (r != null) {
        _log('L2', 'releasing MediaRecorder, state=${r.state}');
        if (r.state != 'inactive') r.stop();
      }
    } catch (e) {
      _log('L2', 'recorder.stop() threw: $e');
    }
    _recorder = null;

    try {
      final s = _mediaStream;
      if (s != null) {
        final tracks = s.getTracks().toDart;
        _log('L1', 'releasing MediaStream id=${s.id}, '
            'stopping ${tracks.length} track(s)');
        for (final t in tracks) {
          try { t.stop(); } catch (e) { _log('L1', 'track.stop threw: $e'); }
        }
      }
    } catch (e) {
      _log('L1', 'mediaStream release threw: $e');
    }
    _mediaStream = null;

    try {
      if (_channel != null) {
        _log('L3', 'closing WebSocket sink (client-initiated)');
        _channel!.sink.close();
      }
    } catch (e) {
      _log('L3', 'sink.close threw: $e');
    }
    _channel = null;
  }

  /// Pause — preserve transcript, free media, allow Resume to restart.
  /// Called by the mic button while recording.
  void _pauseRecording() {
    _releaseMediaResources();
    setState(() {
      _setStage(_NarrateStage.paused, 'user tapped pause');
      _interimText = '';
    });
  }

  /// Terminal stop — Done button. Generate Report becomes the only forward
  /// action. Mic button is hidden.
  void _finishRecording() {
    _releaseMediaResources();
    setState(() {
      _setStage(_NarrateStage.stopped, 'user tapped Done');
      _interimText = '';
    });
  }

  // ── WebSocket handlers ────────────────────────────────────────────────────

  void _onTranscriptReceived(dynamic message) {
    _wsRecvCount++;
    final raw = message is String ? message : message.toString();
    final size = raw.length;

    Map<String, dynamic>? data;
    try {
      data = jsonDecode(raw) as Map<String, dynamic>;
    } catch (e) {
      _log('L3', 'received unparsable message #$_wsRecvCount, '
          'size=$size, decode error="$e", raw_first_120="${raw.substring(0, raw.length < 120 ? raw.length : 120)}"');
      return;
    }
    if (_wsRecvCount <= 5 || _wsRecvCount % 20 == 0) {
      _log('L3', 'received message #$_wsRecvCount, size=$size, '
          'top_keys=${data.keys.toList()}');
    }

    if (data['type'] == 'transcript') {
      final isFinal = data['is_final'] == true;
      final text    = (data['text'] as String?) ?? '';
      final preview = text.length > 60 ? '${text.substring(0, 60)}...' : text;
      _log('L6',
          'transcript chunk parsed, isFinal=$isFinal, text="$preview"');

      if (isFinal) {
        setState(() {
          _finalTranscript += '$text ';
          _interimText      = '';
          if (data!['language'] != null) {
            _detectedLanguage = _languageName(data['language'] as String);
          }
        });
        _log('L6',
            '_finalTranscript appended, total length=${_finalTranscript.length}, '
            'word count=$_wordCount');
      } else {
        setState(() => _interimText = text);
        _log('L6', 'interim transcript updated, length=${text.length}');
      }
    } else if (data['type'] == 'error') {
      final dgMsg = (data['message'] as String?) ?? '(no message)';
      _log('L3', 'proxy reported error type, message="$dgMsg"');
      _releaseMediaResources();
      setState(() {
        _setError(
          dgMsg,
          'proxy emitted {type:"error"} message',
        );
        _setStage(
          _stage == _NarrateStage.stopped
              ? _NarrateStage.stopped
              : _NarrateStage.paused,
          'proxy error message received',
        );
      });
    } else {
      _log('L3', 'received message with unknown type="${data['type']}"');
    }
  }

  void _onWebSocketError(dynamic error) {
    _log('L3', 'WebSocket ERROR event, error="$error", '
        'sendCount=$_wsSendCount, recvCount=$_wsRecvCount');
    _releaseMediaResources();
    setState(() {
      _setError(
        'Connection lost. Tap to retry.',
        'WebSocket onError fired: $error',
      );
      if (_stage != _NarrateStage.stopped) {
        _setStage(
          _finalTranscript.isEmpty
              ? _NarrateStage.idle
              : _NarrateStage.paused,
          'websocket error fallback',
        );
      }
    });
  }

  void _onWebSocketDone() {
    final code   = _channel?.closeCode;
    final reason = _channel?.closeReason;
    _log('L3',
        'WebSocket CLOSE, code=$code, reason="$reason", '
        'sendCount=$_wsSendCount, recvCount=$_wsRecvCount, '
        'stage=${_stage.name}');
    if (_isRecording) {
      // Server-initiated close while we thought we were live — fall back to
      // paused so the user can retry without losing transcript.
      _log('L3',
          'unexpected close while recording — falling back to paused/idle');
      setState(() {
        _setStage(
          _finalTranscript.isEmpty
              ? _NarrateStage.idle
              : _NarrateStage.paused,
          'websocket closed mid-recording',
        );
      });
    }
  }

  // ── Generate & navigate ───────────────────────────────────────────────────

  Future<void> _generateAndNavigate() async {
    // Phase 4.0.7.8a — single transactional PATCH with every column the
    // narrator stage owns. Column is `transcript` (not narrator_transcript
    // — that name killed every Generate Report attempt with PGRST204).
    // ai_generated is left false here; ReportScreen flips it true after
    // the AI proxy returns a SOAP note. `status` intentionally omitted —
    // valid enum values for that column are not known to this layer; the
    // SOAP-save / attestation paths in report_screen own status writes.
    if (widget.sessionId != null) {
      await _supabase
          .from('sessions')
          .update({
            'transcript':   _finalTranscript.trim(),
            'ai_generated': false,
          })
          .eq('id', widget.sessionId!);
    }

    if (!mounted) return;

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

  // ── Phase 4.0.7.7 diagnostic panel ─────────────────────────────────────
  // Collapsed by default. Expands to show the most recent log line from
  // each pipeline layer so the SLP can screenshot the panel and send it
  // back without opening browser devtools. Phase 4.0 visual register —
  // hairline border, neutral ink, no decoration.
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
                    Text('last_chunk_age:  ${_secondsSinceLastChunk()}s'),
                    Text('ws_send_count:   $_wsSendCount'),
                    Text('ws_recv_count:   $_wsRecvCount'),
                    Text('l2_chunk_count:  $_l2ChunkCount'),
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

  @override
  void dispose() {
    _releaseMediaResources();
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
                    const SizedBox(height: 12),
                    _buildDiagnosticPanel(ink: ink),
                    const SizedBox(height: 32),
                  ],

                  // ── Mic button (hidden in terminal stopped state) ───────
                  if (_micError == null && !_isStopped) ...[
                    GestureDetector(
                      onTap: _isConnecting
                          ? null
                          : _isRecording
                              ? _pauseRecording
                              : _startRecording,
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
                                    ? Icons.pause_rounded
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
                        : _isStopped
                            ? 'Recording stopped. Generate the report below.'
                            : _isRecording
                                ? 'Tap to pause'
                                : _finalTranscript.isEmpty
                                    ? 'Tap the microphone and speak'
                                    : 'Paused — tap to resume, or Done to finish',
                    style: TextStyle(
                      fontSize: 13,
                      color:    ink.withValues(alpha: 0.55),
                    ),
                    textAlign: TextAlign.center,
                  ),

                  // ── Done button — visible once any transcript exists,
                  // until the SLP commits to terminal stop. Closes the
                  // WebSocket and releases the mic stream cleanly.
                  if (!_isStopped &&
                      !_isConnecting &&
                      _finalTranscript.trim().isNotEmpty) ...[
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

                  // ── Generate report button ──────────────────────────────
                  // Surfaces once the SLP has committed (Done) to the
                  // transcript, OR when she has dictated a substantive
                  // amount mid-session and might want to ship without
                  // tapping Done first. The Done path is the canonical
                  // flow — the >20 word path is a safety net.
                  if ((_isStopped && _finalTranscript.trim().isNotEmpty) ||
                      _wordCount > 20) ...[
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
