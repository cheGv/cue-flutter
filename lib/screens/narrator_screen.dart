// lib/screens/narrator_screen.dart
// Cue Narrator — Record audio, transcribe, and generate SOAP notes via Supabase Edge Function

import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:record/record.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:http/http.dart' as http;
import '../theme/cue_theme.dart';

// ── Data Models ───────────────────────────────────────────────────────────────
class SoapNote {
  final String subjective;
  final String objective;
  final String assessment;
  final String plan;

  const SoapNote({
    required this.subjective,
    required this.objective,
    required this.assessment,
    required this.plan,
  });

  factory SoapNote.fromJson(Map<String, dynamic> json) => SoapNote(
        subjective: json['subjective'] as String? ?? '',
        objective:  json['objective']  as String? ?? '',
        assessment: json['assessment'] as String? ?? '',
        plan:       json['plan']       as String? ?? '',
      );

  Map<String, dynamic> toJson() => {
        'subjective': subjective,
        'objective':  objective,
        'assessment': assessment,
        'plan':       plan,
      };
}

class NarratorResult {
  final String  transcript;
  final SoapNote? soapNote;
  final String? parentSummary;

  const NarratorResult({
    required this.transcript,
    this.soapNote,
    this.parentSummary,
  });
}

// ── Narrator Screen ────────────────────────────────────────────────────────────
class NarratorScreen extends StatefulWidget {
  const NarratorScreen({super.key});

  @override
  State<NarratorScreen> createState() => _NarratorScreenState();
}

enum _NarratorStatus { idle, recording, processing, done, error }

class _NarratorScreenState extends State<NarratorScreen>
    with SingleTickerProviderStateMixin {
  final AudioRecorder _recorder = AudioRecorder();
  late AnimationController _pulseController;
  late Animation<double>   _pulseAnimation;

  _NarratorStatus _status        = _NarratorStatus.idle;
  String          _statusMessage = 'Tap the microphone to begin recording';
  NarratorResult? _result;
  String?         _clientName;
  bool            _isSaving = false;
  bool            _saved    = false;

  String?   _recordingPath;
  DateTime? _recordingStart;
  int       _durationSeconds = 0;

  SupabaseClient get _supabase => Supabase.instance.client;

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
    _pulseController.stop();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _recorder.dispose();
    super.dispose();
  }

  // ── Recording ───────────────────────────────────────────────────────────────
  Future<void> _startRecording() async {
    final hasPermission = await _recorder.hasPermission();
    if (!hasPermission) {
      _setError('Microphone permission denied. Please allow access and try again.');
      return;
    }
    try {
      const config = RecordConfig(encoder: AudioEncoder.opus, numChannels: 1);
      _recordingPath = 'session_${DateTime.now().millisecondsSinceEpoch}.webm';
      await _recorder.start(config, path: _recordingPath!);

      _recordingStart = DateTime.now();
      setState(() {
        _status        = _NarratorStatus.recording;
        _statusMessage = 'Recording in progress — tap to stop';
        _result        = null;
        _saved         = false;
      });
      _pulseController.repeat(reverse: true);
    } catch (e) {
      _setError('Could not start recording: $e');
    }
  }

  Future<void> _stopAndProcess() async {
    if (_status != _NarratorStatus.recording) return;

    _pulseController.stop();
    _pulseController.reset();

    final path = await _recorder.stop();
    _durationSeconds = _recordingStart != null
        ? DateTime.now().difference(_recordingStart!).inSeconds
        : 0;

    if (_durationSeconds < 3) {
      _setError('Recording was too short. Please record at least a few seconds of speech.');
      return;
    }

    setState(() {
      _status        = _NarratorStatus.processing;
      _statusMessage = 'Transcribing and analysing…';
    });

    try {
      Uint8List audioBytes;
      if (path != null && path.startsWith('http')) {
        final response = await http.get(Uri.parse(path));
        audioBytes = response.bodyBytes;
      } else if (path != null) {
        final bytes = await http.get(Uri.parse(path));
        audioBytes = bytes.bodyBytes;
      } else {
        throw Exception('No recording path available');
      }

      final httpResponse = await http.post(
        Uri.parse('https://cgnjbjbargkxtcnafxaa.supabase.co/functions/v1/narrator'),
        headers: {
          'Content-Type': 'application/octet-stream',
          'Authorization': 'Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImNnbmpiamJhcmdreHRjbmFmeGFhIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzUyODQyNzcsImV4cCI6MjA5MDg2MDI3N30.AWmyJoSuXUi7X74vBN2E1Jv7mStsjepKqRFyA6iFfmE',
          'apikey': 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImNnbmpiamJhcmdreHRjbmFmeGFhIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzUyODQyNzcsImV4cCI6MjA5MDg2MDI3N30.AWmyJoSuXUi7X74vBN2E1Jv7mStsjepKqRFyA6iFfmE',
        },
        body: audioBytes,
      );

      if (httpResponse.statusCode != 200) {
        throw Exception(
            'Edge Function returned ${httpResponse.statusCode}: ${httpResponse.body}');
      }

      final data = jsonDecode(httpResponse.body) as Map<String, dynamic>;

      if (data['error'] == 'no_speech_detected') {
        _setError(
          'No speech detected. Make sure your microphone is working and speak clearly during the session.',
        );
        return;
      }
      if (data['error'] != null) throw Exception(data['error']);

      SoapNote? soapNote;
      if (data['soap_note'] is Map) {
        soapNote = SoapNote.fromJson(data['soap_note'] as Map<String, dynamic>);
      }

      setState(() {
        _result = NarratorResult(
          transcript:    data['transcript'] as String? ?? '',
          soapNote:      soapNote,
          parentSummary: data['parent_summary'] as String?,
        );
        _status        = _NarratorStatus.done;
        _statusMessage = 'Session note ready';
      });
    } catch (e) {
      _setError('Processing failed: ${e.toString()}');
    }
  }

  void _setError(String message) => setState(() {
        _status        = _NarratorStatus.error;
        _statusMessage = message;
      });

  void _reset() => setState(() {
        _status        = _NarratorStatus.idle;
        _statusMessage = 'Tap the microphone to begin recording';
        _result        = null;
        _saved         = false;
        _clientName    = null;
      });

  Future<void> _saveSession() async {
    if (_result == null || _isSaving) return;
    setState(() => _isSaving = true);
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) throw Exception('Not authenticated');

      await _supabase.from('sessions').insert({
        'user_id':     userId,
        'client_name': _clientName ??
            'Session ${DateTime.now().toString().substring(0, 10)}',
        'transcript':      _result!.transcript,
        'soap_note':       _result!.soapNote?.toJson(),
        'parent_summary':  _result!.parentSummary,
        'duration_seconds': _durationSeconds,
        'status':          'complete',
      });
      setState(() => _saved = true);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Session saved to records')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Save failed: ${e.toString()}')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  // ── Build ────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: CueColors.softWhite,
      appBar: AppBar(
        title: Text('Narrator',
            style: GoogleFonts.dmSans(
                color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600)),
        backgroundColor: CueColors.inkNavy,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildRecordingCard(),

            if (_status == _NarratorStatus.done && _result != null) ...[
              const SizedBox(height: 24),
              _buildClientNameField(),
              if (_result!.soapNote != null) ...[
                const SizedBox(height: 24),
                _buildSoapCards(_result!.soapNote!),
              ],
              if (_result!.parentSummary != null) ...[
                const SizedBox(height: 24),
                _buildParentSummaryCard(_result!.parentSummary!),
              ],
              const SizedBox(height: 24),
              _buildActionRow(),
            ],

            if (_status == _NarratorStatus.error) ...[
              const SizedBox(height: 24),
              _buildErrorCard(),
            ],
          ],
        ),
      ),
    );
  }

  // ── Recording card (inkNavy, matching brand) ──────────────────────────────
  Widget _buildRecordingCard() {
    final isRecording  = _status == _NarratorStatus.recording;
    final isProcessing = _status == _NarratorStatus.processing;
    final isDone       = _status == _NarratorStatus.done;

    final micColor = isRecording
        ? CueColors.errorRed
        : isProcessing
            ? Colors.white.withOpacity(0.2)
            : CueColors.signalTeal;

    return Container(
      decoration: BoxDecoration(
        color: CueColors.inkNavy,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: CueColors.inkNavy.withOpacity(0.35),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
      child: Column(
        children: [
          // Status chip
          if (isRecording || isProcessing)
            Container(
              margin: const EdgeInsets.only(bottom: 20),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.08),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: (isRecording ? CueColors.errorRed : CueColors.signalTeal)
                      .withOpacity(0.5),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    isRecording
                        ? Icons.fiber_manual_record
                        : Icons.hourglass_top_rounded,
                    size: 11,
                    color: isRecording
                        ? CueColors.errorRed
                        : CueColors.signalTeal,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    isRecording ? 'Recording' : 'Processing…',
                    style: GoogleFonts.dmSans(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: isRecording ? CueColors.errorRed : CueColors.signalTeal,
                    ),
                  ),
                ],
              ),
            ),

          // Mic button
          ScaleTransition(
            scale: isRecording
                ? _pulseAnimation
                : const AlwaysStoppedAnimation(1.0),
            child: GestureDetector(
              onTap: isProcessing
                  ? null
                  : isRecording
                      ? _stopAndProcess
                      : _startRecording,
              child: Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: micColor,
                  boxShadow: [
                    BoxShadow(
                      color: micColor.withOpacity(0.45),
                      blurRadius: isRecording ? 28 : 16,
                      spreadRadius: isRecording ? 4 : 2,
                    ),
                  ],
                ),
                child: isProcessing
                    ? const Center(
                        child: SizedBox(
                          width: 28,
                          height: 28,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2.5),
                        ),
                      )
                    : Icon(
                        isRecording ? Icons.stop_rounded : Icons.mic_rounded,
                        color: Colors.white,
                        size: 44,
                      ),
              ),
            ),
          ),

          const SizedBox(height: 18),

          Text(
            _statusMessage,
            textAlign: TextAlign.center,
            style: GoogleFonts.dmSans(
              fontSize: 14,
              height: 1.5,
              color: isDone
                  ? CueColors.signalTeal
                  : isRecording
                      ? CueColors.errorRed
                      : Colors.white.withOpacity(0.65),
              fontWeight:
                  isRecording ? FontWeight.w600 : FontWeight.normal,
            ),
          ),

          if (!isRecording && !isProcessing && !isDone) ...[
            const SizedBox(height: 6),
            Text(
              'Session audio is processed by Cue AI',
              style: GoogleFonts.dmSans(
                  fontSize: 12,
                  color: Colors.white.withOpacity(0.35)),
            ),
          ],
        ],
      ),
    );
  }

  // ── Client name field ────────────────────────────────────────────────────────
  Widget _buildClientNameField() {
    return TextField(
      onChanged: (val) => _clientName = val,
      textCapitalization: TextCapitalization.words,
      style: GoogleFonts.dmSans(fontSize: 15, color: CueColors.inkNavy),
      decoration: CueTheme.inputDecoration(
        'Client name (optional)',
        hint: 'e.g. Arjun, Session 12',
        prefixIcon: const Icon(Icons.person_outline,
            color: CueColors.signalTeal, size: 20),
      ),
    );
  }

  // ── SOAP cards (S/O/A/P with coloured left borders) ──────────────────────────
  Widget _buildSoapCards(SoapNote soap) {
    final values = [soap.subjective, soap.objective, soap.assessment, soap.plan];
    final labels = CueTheme.soapLabels;
    final colors = CueTheme.soapColors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CueTheme.sectionLabel('SOAP Note'),
        const SizedBox(height: 12),
        ...List.generate(values.length, (i) => Container(
          margin: const EdgeInsets.only(bottom: 10),
          decoration: BoxDecoration(
            color: CueColors.surfaceWhite,
            borderRadius: BorderRadius.circular(12),
            border: Border(left: BorderSide(color: colors[i], width: 4)),
            boxShadow: [
              BoxShadow(
                color: CueColors.inkNavy.withOpacity(0.05),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                labels[i].toUpperCase(),
                style: GoogleFonts.dmSans(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: colors[i],
                  letterSpacing: 0.8,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                values[i].isNotEmpty ? values[i] : '—',
                style: GoogleFonts.dmSans(
                    fontSize: 14, height: 1.55, color: CueColors.inkNavy),
              ),
            ],
          ),
        )),
      ],
    );
  }

  // ── Parent summary ────────────────────────────────────────────────────────────
  Widget _buildParentSummaryCard(String summary) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CueTheme.sectionLabel('Parent Summary'),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: CueColors.signalTeal.withOpacity(0.07),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: CueColors.signalTeal.withOpacity(0.25)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.family_restroom_rounded,
                  size: 18, color: CueColors.signalTeal),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  summary,
                  style: GoogleFonts.dmSans(
                      fontSize: 14, height: 1.55, color: CueColors.inkNavy),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── Action row ────────────────────────────────────────────────────────────────
  Widget _buildActionRow() {
    return Row(children: [
      Expanded(
        child: OutlinedButton.icon(
          onPressed: _reset,
          icon: const Icon(Icons.refresh_rounded, size: 18),
          label: Text('New Session',
              style: GoogleFonts.dmSans(fontWeight: FontWeight.w600)),
          style: OutlinedButton.styleFrom(
            foregroundColor: CueColors.inkNavy,
            side: BorderSide(color: CueColors.inkNavy.withOpacity(0.35)),
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
          ),
        ),
      ),
      const SizedBox(width: 12),
      Expanded(
        flex: 2,
        child: FilledButton.icon(
          onPressed: _saved || _isSaving ? null : _saveSession,
          icon: _isSaving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      color: Colors.white, strokeWidth: 2),
                )
              : Icon(_saved ? Icons.check_rounded : Icons.save_rounded,
                  size: 18, color: Colors.white),
          label: Text(
            _saved ? 'Saved to Records' : 'Save to Records',
            style: GoogleFonts.dmSans(
                fontSize: 15, fontWeight: FontWeight.w600, color: Colors.white),
          ),
          style: FilledButton.styleFrom(
            backgroundColor:
                _saved ? Colors.green.shade600 : CueColors.inkNavy,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
          ),
        ),
      ),
    ]);
  }

  // ── Error card ────────────────────────────────────────────────────────────────
  Widget _buildErrorCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: CueColors.errorRed.withOpacity(0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: CueColors.errorRed.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.warning_amber_rounded,
                color: CueColors.errorRed, size: 18),
            const SizedBox(width: 8),
            Text(
              'Unable to process session',
              style: GoogleFonts.dmSans(
                  fontWeight: FontWeight.w700,
                  color: CueColors.errorRed,
                  fontSize: 14),
            ),
          ]),
          const SizedBox(height: 8),
          Text(
            _statusMessage,
            style: GoogleFonts.dmSans(
                color: CueColors.errorRed, fontSize: 13, height: 1.5),
          ),
          const SizedBox(height: 14),
          OutlinedButton(
            onPressed: _reset,
            style: OutlinedButton.styleFrom(
              foregroundColor: CueColors.errorRed,
              side: BorderSide(color: CueColors.errorRed.withOpacity(0.4)),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            child: Text('Try Again',
                style: GoogleFonts.dmSans(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}
