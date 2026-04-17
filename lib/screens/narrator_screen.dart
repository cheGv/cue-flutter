// lib/screens/narrator_screen.dart
// Cue Narrator — Record audio, transcribe, and generate SOAP notes
// via the Supabase Edge Function.

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
        objective: json['objective'] as String? ?? '',
        assessment: json['assessment'] as String? ?? '',
        plan: json['plan'] as String? ?? '',
      );

  Map<String, dynamic> toJson() => {
        'subjective': subjective,
        'objective': objective,
        'assessment': assessment,
        'plan': plan,
      };
}

class NarratorResult {
  final String transcript;
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
  late Animation<double> _pulseAnimation;

  _NarratorStatus _status = _NarratorStatus.idle;
  String _statusMessage = 'Tap the microphone to begin';
  NarratorResult? _result;
  String? _clientName;
  bool _isSaving = false;
  bool _saved = false;

  String? _recordingPath;
  DateTime? _recordingStart;
  int _durationSeconds = 0;

  SupabaseClient get _supabase => Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.08).animate(
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

  Future<void> _startRecording() async {
    final hasPermission = await _recorder.hasPermission();
    if (!hasPermission) {
      _setError('Microphone permission denied.');
      return;
    }
    try {
      const config = RecordConfig(encoder: AudioEncoder.opus, numChannels: 1);
      _recordingPath =
          'session_${DateTime.now().millisecondsSinceEpoch}.webm';
      await _recorder.start(config, path: _recordingPath!);

      _recordingStart = DateTime.now();
      setState(() {
        _status = _NarratorStatus.recording;
        _statusMessage = 'Recording — tap to stop';
        _result = null;
        _saved = false;
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
      _setError('Recording was too short.');
      return;
    }

    setState(() {
      _status = _NarratorStatus.processing;
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
        Uri.parse(
            'https://cgnjbjbargkxtcnafxaa.supabase.co/functions/v1/narrator'),
        headers: {
          'Content-Type': 'application/octet-stream',
          'Authorization':
              'Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImNnbmpiamJhcmdreHRjbmFmeGFhIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzUyODQyNzcsImV4cCI6MjA5MDg2MDI3N30.AWmyJoSuXUi7X74vBN2E1Jv7mStsjepKqRFyA6iFfmE',
          'apikey':
              'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImNnbmpiamJhcmdreHRjbmFmeGFhIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzUyODQyNzcsImV4cCI6MjA5MDg2MDI3N30.AWmyJoSuXUi7X74vBN2E1Jv7mStsjepKqRFyA6iFfmE',
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
          'No speech detected. Check your microphone and try again.',
        );
        return;
      }
      if (data['error'] != null) throw Exception(data['error']);

      SoapNote? soapNote;
      if (data['soap_note'] is Map) {
        soapNote =
            SoapNote.fromJson(data['soap_note'] as Map<String, dynamic>);
      }

      setState(() {
        _result = NarratorResult(
          transcript: data['transcript'] as String? ?? '',
          soapNote: soapNote,
          parentSummary: data['parent_summary'] as String?,
        );
        _status = _NarratorStatus.done;
        _statusMessage = 'Session note ready';
      });
    } catch (e) {
      _setError('Processing failed: ${e.toString()}');
    }
  }

  void _setError(String message) => setState(() {
        _status = _NarratorStatus.error;
        _statusMessage = message;
      });

  void _reset() => setState(() {
        _status = _NarratorStatus.idle;
        _statusMessage = 'Tap the microphone to begin';
        _result = null;
        _saved = false;
        _clientName = null;
      });

  Future<void> _saveSession() async {
    if (_result == null || _isSaving) return;
    setState(() => _isSaving = true);
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) throw Exception('Not authenticated');

      await _supabase.from('sessions').insert({
        'user_id': userId,
        'client_name': _clientName ??
            'Session ${DateTime.now().toString().substring(0, 10)}',
        'transcript': _result!.transcript,
        'soap_note': _result!.soapNote?.toJson(),
        'parent_summary': _result!.parentSummary,
        'duration_seconds': _durationSeconds,
        'status': 'complete',
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: CueColors.background,
      appBar: AppBar(
        title: const Text('Narrator'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 32, 24, 40),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildRecordingBlock(),
            if (_status == _NarratorStatus.done && _result != null) ...[
              const SizedBox(height: 40),
              _buildClientNameField(),
              if (_result!.soapNote != null) ...[
                const SizedBox(height: 32),
                _buildSoapCards(_result!.soapNote!),
              ],
              if (_result!.parentSummary != null) ...[
                const SizedBox(height: 32),
                _buildParentSummaryCard(_result!.parentSummary!),
              ],
              const SizedBox(height: 32),
              _buildActionRow(),
            ],
            if (_status == _NarratorStatus.error) ...[
              const SizedBox(height: 32),
              _buildErrorCard(),
            ],
          ],
        ),
      ),
    );
  }

  // ── Recording block: just mic + status, no heavy card ────────────────────────
  Widget _buildRecordingBlock() {
    final isRecording = _status == _NarratorStatus.recording;
    final isProcessing = _status == _NarratorStatus.processing;

    final micColor = isRecording
        ? CueColors.coral
        : isProcessing
            ? CueColors.inkTertiary
            : CueColors.accent;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        children: [
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
                width: 88,
                height: 88,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: micColor,
                ),
                child: isProcessing
                    ? const Center(
                        child: SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2),
                        ),
                      )
                    : Icon(
                        isRecording ? Icons.stop_rounded : Icons.mic_rounded,
                        color: Colors.white,
                        size: 36,
                      ),
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            _statusMessage,
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: 15,
              height: 1.5,
              color: CueColors.inkSecondary,
              fontWeight:
                  isRecording ? FontWeight.w500 : FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildClientNameField() {
    return TextField(
      onChanged: (val) => _clientName = val,
      textCapitalization: TextCapitalization.words,
      style: GoogleFonts.inter(fontSize: 16, color: CueColors.inkPrimary),
      decoration: const InputDecoration(
        labelText: 'Client name (optional)',
        hintText: 'e.g. Arjun, Session 12',
      ),
    );
  }

  Widget _buildSoapCards(SoapNote soap) {
    final values = [soap.subjective, soap.objective, soap.assessment, soap.plan];
    final labels = CueTheme.soapLabels;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CueTheme.eyebrow('SOAP Note'),
        const SizedBox(height: 12),
        ...List.generate(values.length, (i) => Container(
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(
                color: CueColors.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: CueColors.divider),
              ),
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    labels[i],
                    style: GoogleFonts.fraunces(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: CueColors.inkPrimary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    values[i].isNotEmpty ? values[i] : '—',
                    style: GoogleFonts.inter(
                      fontSize: 15,
                      height: 1.55,
                      color: CueColors.inkPrimary,
                    ),
                  ),
                ],
              ),
            )),
      ],
    );
  }

  Widget _buildParentSummaryCard(String summary) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CueTheme.eyebrow('Parent Summary'),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: CueColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: CueColors.divider),
          ),
          child: Text(
            summary,
            style: GoogleFonts.inter(
              fontSize: 15,
              height: 1.55,
              color: CueColors.inkPrimary,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildActionRow() {
    return Row(children: [
      Expanded(
        child: SizedBox(
          height: 52,
          child: OutlinedButton.icon(
            onPressed: _reset,
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('New'),
          ),
        ),
      ),
      const SizedBox(width: 12),
      Expanded(
        flex: 2,
        child: SizedBox(
          height: 52,
          child: FilledButton.icon(
            onPressed: _saved || _isSaving ? null : _saveSession,
            icon: _isSaving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2),
                  )
                : Icon(_saved ? Icons.check_rounded : Icons.save_outlined,
                    size: 18, color: Colors.white),
            label: Text(_saved ? 'Saved' : 'Save to Records'),
            style: FilledButton.styleFrom(
              backgroundColor:
                  _saved ? CueColors.success : CueColors.accent,
            ),
          ),
        ),
      ),
    ]);
  }

  Widget _buildErrorCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: CueColors.coral.withOpacity(0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: CueColors.coral.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Unable to process session',
            style: GoogleFonts.fraunces(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: CueColors.coral,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _statusMessage,
            style: GoogleFonts.inter(
              color: CueColors.inkPrimary,
              fontSize: 14,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 16),
          OutlinedButton(
            onPressed: _reset,
            style: OutlinedButton.styleFrom(
              foregroundColor: CueColors.coral,
              side: BorderSide(color: CueColors.coral.withOpacity(0.4)),
            ),
            child: const Text('Try Again'),
          ),
        ],
      ),
    );
  }
}
