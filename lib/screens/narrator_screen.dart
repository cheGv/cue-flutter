// lib/screens/narrator_screen.dart
// Cue Narrator — Record audio, transcribe, and generate SOAP notes via Supabase Edge Function

import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:record/record.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../widgets/app_layout.dart';

// ── Cue Brand Colors ──────────────────────────────────────────────────────────
class NarratorColors {
  static const inkNavy = Color(0xFF1B2B4B);
  static const signalTeal = Color(0xFF00B4A6);
  static const warmAmber = Color(0xFFF5A623);
  static const softWhite = Color(0xFFF8F9FC);
  static const textMid = Color(0xFF5A6475);
  static const errorRed = Color(0xFFE05252);
}

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
  String _statusMessage = 'Tap the mic to begin recording';
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
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.9, end: 1.1).animate(
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
      _setError(
          'Microphone permission denied. Please allow access and try again.');
      return;
    }

    try {
      const config =
          RecordConfig(encoder: AudioEncoder.opus, numChannels: 1);

      _recordingPath =
          'session_${DateTime.now().millisecondsSinceEpoch}.webm';
      await _recorder.start(config, path: _recordingPath!);

      _recordingStart = DateTime.now();
      setState(() {
        _status = _NarratorStatus.recording;
        _statusMessage = 'Recording session...';
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
      _setError(
          'Recording was too short. Please record at least a few seconds of speech.');
      return;
    }

    setState(() {
      _status = _NarratorStatus.processing;
      _statusMessage = 'Transcribing and analysing...';
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

      final response = await _supabase.functions.invoke(
        'narrator',
        body: audioBytes,
        headers: {
          'Content-Type': 'application/octet-stream',
        },
      );

      final data = response.data as Map<String, dynamic>;

      if (data['error'] == 'no_speech_detected') {
        _setError(
          'No speech was detected in this recording.\n\nMake sure your microphone is working and you\'re speaking clearly during the session.',
        );
        return;
      }

      if (data['error'] != null) {
        throw Exception(data['error']);
      }

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

  void _setError(String message) {
    setState(() {
      _status = _NarratorStatus.error;
      _statusMessage = message;
    });
  }

  void _reset() {
    setState(() {
      _status = _NarratorStatus.idle;
      _statusMessage = 'Tap the mic to begin recording';
      _result = null;
      _saved = false;
      _clientName = null;
    });
  }

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
          SnackBar(
            content: const Text('Session saved to records'),
            backgroundColor: NarratorColors.signalTeal,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Save failed: ${e.toString()}'),
            backgroundColor: NarratorColors.errorRed,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppLayout(
      title: 'Cue Narrator',
      activeRoute: 'narrator',
      body: SingleChildScrollView(
        padding:
            const EdgeInsets.symmetric(horizontal: 48, vertical: 32),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildRecordingCard(),
                if (_status == _NarratorStatus.done &&
                    _result != null) ...[
                  const SizedBox(height: 24),
                  _buildClientNameField(),
                  const SizedBox(height: 24),
                  _buildSoapCards(_result!.soapNote),
                  if (_result!.parentSummary != null) ...[
                    const SizedBox(height: 20),
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
        ),
      ),
    );
  }

  Widget _buildRecordingCard() {
    final isRecording = _status == _NarratorStatus.recording;
    final isProcessing = _status == _NarratorStatus.processing;

    return Container(
      padding: const EdgeInsets.all(40),
      decoration: BoxDecoration(
        color: NarratorColors.inkNavy,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: NarratorColors.inkNavy.withOpacity(0.3),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: Text(
              isRecording
                  ? '● RECORDING'
                  : isProcessing
                      ? '⟳ PROCESSING'
                      : '',
              key: ValueKey(_status),
              style: TextStyle(
                color: isRecording
                    ? NarratorColors.errorRed
                    : NarratorColors.signalTeal,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 2,
              ),
            ),
          ),
          const SizedBox(height: 24),
          GestureDetector(
            onTap: isProcessing
                ? null
                : isRecording
                    ? _stopAndProcess
                    : _startRecording,
            child: AnimatedBuilder(
              animation: _pulseAnimation,
              builder: (context, child) => Transform.scale(
                scale: isRecording ? _pulseAnimation.value : 1.0,
                child: child,
              ),
              child: Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isRecording
                      ? NarratorColors.errorRed
                      : isProcessing
                          ? Colors.white.withOpacity(0.1)
                          : NarratorColors.signalTeal,
                  boxShadow: [
                    BoxShadow(
                      color: (isRecording
                              ? NarratorColors.errorRed
                              : NarratorColors.signalTeal)
                          .withOpacity(0.4),
                      blurRadius: 24,
                      spreadRadius: 4,
                    ),
                  ],
                ),
                child: isProcessing
                    ? const Center(
                        child: SizedBox(
                          width: 28,
                          height: 28,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2.5,
                          ),
                        ),
                      )
                    : Icon(
                        isRecording
                            ? Icons.stop_rounded
                            : Icons.mic_rounded,
                        color: Colors.white,
                        size: 40,
                      ),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            _statusMessage,
            style: TextStyle(
              color: _status == _NarratorStatus.done
                  ? NarratorColors.signalTeal
                  : Colors.white.withOpacity(0.7),
              fontSize: 14,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildClientNameField() {
    return TextField(
      onChanged: (val) => _clientName = val,
      decoration: InputDecoration(
        labelText: 'Client name (optional)',
        hintText: 'e.g. Arjun, Session 12',
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.shade200),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.shade200),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide:
              const BorderSide(color: NarratorColors.signalTeal),
        ),
        prefixIcon: const Icon(Icons.person_outline,
            color: NarratorColors.signalTeal),
      ),
    );
  }

  Widget _buildSoapCards(SoapNote? soap) {
    if (soap == null) return const SizedBox.shrink();

    final sections = [
      _SoapSection('S', 'Subjective', soap.subjective,
          NarratorColors.signalTeal),
      _SoapSection(
          'O', 'Objective', soap.objective, NarratorColors.inkNavy),
      _SoapSection('A', 'Assessment', soap.assessment,
          NarratorColors.warmAmber),
      _SoapSection(
          'P', 'Plan', soap.plan, const Color(0xFF6B7FD4)),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'SOAP Note',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.5,
            color: NarratorColors.textMid,
          ),
        ),
        const SizedBox(height: 12),
        ...sections.map((s) => _buildSoapCard(s)),
      ],
    );
  }

  Widget _buildSoapCard(_SoapSection section) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border(
          left: BorderSide(color: section.accentColor, width: 4),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 12,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: section.accentColor.withOpacity(0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Center(
              child: Text(
                section.letter,
                style: TextStyle(
                  color: section.accentColor,
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  section.title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: NarratorColors.inkNavy,
                    letterSpacing: 0.2,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  section.content.isNotEmpty
                      ? section.content
                      : 'Not documented',
                  style: TextStyle(
                    fontSize: 14,
                    color: section.content.isNotEmpty
                        ? NarratorColors.inkNavy.withOpacity(0.8)
                        : NarratorColors.textMid,
                    height: 1.55,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildParentSummaryCard(String summary) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            NarratorColors.signalTeal.withOpacity(0.08),
            NarratorColors.signalTeal.withOpacity(0.03),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: NarratorColors.signalTeal.withOpacity(0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.family_restroom_rounded,
                color: NarratorColors.signalTeal, size: 18),
            const SizedBox(width: 8),
            const Text(
              'Parent Summary',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: NarratorColors.signalTeal,
                letterSpacing: 0.5,
              ),
            ),
          ]),
          const SizedBox(height: 12),
          Text(
            summary,
            style: const TextStyle(
              fontSize: 14,
              color: NarratorColors.inkNavy,
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionRow() {
    return Row(children: [
      Expanded(
        child: OutlinedButton.icon(
          onPressed: _reset,
          icon: const Icon(Icons.refresh_rounded, size: 18),
          label: const Text('New Session'),
          style: OutlinedButton.styleFrom(
            foregroundColor: NarratorColors.inkNavy,
            side: BorderSide(color: Colors.grey.shade300),
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
          ),
        ),
      ),
      const SizedBox(width: 12),
      Expanded(
        flex: 2,
        child: ElevatedButton.icon(
          onPressed: _saved || _isSaving ? null : _saveSession,
          icon: _isSaving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      color: Colors.white, strokeWidth: 2),
                )
              : Icon(
                  _saved ? Icons.check_rounded : Icons.save_rounded,
                  size: 18),
          label: Text(
              _saved ? 'Saved to Records' : 'Save to Records'),
          style: ElevatedButton.styleFrom(
            backgroundColor: _saved
                ? Colors.green.shade600
                : NarratorColors.signalTeal,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
            elevation: 0,
          ),
        ),
      ),
    ]);
  }

  Widget _buildErrorCard() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: NarratorColors.errorRed.withOpacity(0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: NarratorColors.errorRed.withOpacity(0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.warning_amber_rounded,
                color: NarratorColors.errorRed, size: 18),
            const SizedBox(width: 8),
            Text(
              'Unable to process session',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: NarratorColors.errorRed,
                fontSize: 14,
              ),
            ),
          ]),
          const SizedBox(height: 10),
          Text(
            _statusMessage,
            style: TextStyle(
                color: NarratorColors.errorRed.withOpacity(0.85),
                fontSize: 13,
                height: 1.5),
          ),
          const SizedBox(height: 16),
          OutlinedButton(
            onPressed: _reset,
            style: OutlinedButton.styleFrom(
              foregroundColor: NarratorColors.errorRed,
              side: BorderSide(
                  color: NarratorColors.errorRed.withOpacity(0.4)),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Try Again'),
          ),
        ],
      ),
    );
  }
}

class _SoapSection {
  final String letter;
  final String title;
  final String content;
  final Color accentColor;

  const _SoapSection(
      this.letter, this.title, this.content, this.accentColor);
}
