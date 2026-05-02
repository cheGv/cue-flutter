// lib/widgets/voice_note_sheet.dart
//
// Shared voice-note bottom sheet for the Layer-03 capture surfaces.
//
// speech_to_text accumulating into a transcript that the caller drops
// into a text field. No /extract round-trip — plain transcription, not
// JSON parsing. Auto-restart on browser Web Speech API's ~60s session
// limit while `_wantListening` is true (matches the pattern used in
// add_client_screen.dart's brain-dump flow).
//
// Caller usage:
//
//   final transcript = await showModalBottomSheet<String>(
//     context: context,
//     isScrollControlled: true,
//     backgroundColor: Colors.transparent,
//     builder: (_) => const VoiceNoteSheet(eyebrow: 'voice note · X', subtitle: '…'),
//   );
//
// Returns the trimmed transcript or null if cancelled. The caller is
// responsible for the §13.16 no-overwrite check before applying it.

import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../theme/cue_phase4_tokens.dart';

class VoiceNoteSheet extends StatefulWidget {
  /// Lowercase tracked eyebrow shown at the top of the sheet.
  final String eyebrow;

  /// Subtitle copy under the eyebrow that orients the SLP.
  final String subtitle;

  const VoiceNoteSheet({
    super.key,
    this.eyebrow = 'voice note',
    this.subtitle = 'Speak freely. Transcript fills the field below.',
  });

  @override
  State<VoiceNoteSheet> createState() => _VoiceNoteSheetState();
}

class _VoiceNoteSheetState extends State<VoiceNoteSheet> {
  final _speech = SpeechToText();

  bool _speechAvailable = false;
  bool _isListening     = false;
  bool _wantListening   = false;
  String _accumulated   = '';
  String _previousText  = '';
  String? _error;

  @override
  void initState() {
    super.initState();
    _initSpeech();
  }

  @override
  void dispose() {
    _speech.stop();
    super.dispose();
  }

  Future<void> _initSpeech() async {
    final available = await _speech.initialize(
      onStatus: (status) async {
        if (status == 'done' && _wantListening && mounted) {
          _previousText = _accumulated;
          await _startListening();
          return;
        }
        if ((status == 'done' || status == 'notListening') &&
            !_wantListening &&
            mounted) {
          setState(() => _isListening = false);
        }
      },
      onError: (e) {
        if (mounted) {
          setState(() {
            _error = 'Microphone error: ${e.errorMsg}';
            _isListening = false;
            _wantListening = false;
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
          setState(() {
            _accumulated =
                ('$_previousText ${result.recognizedWords}').trim();
          });
        }
      },
      listenFor: const Duration(minutes: 10),
      pauseFor: const Duration(minutes: 10),
      localeId: 'en_IN',
      listenOptions: SpeechListenOptions(partialResults: true),
    );
    if (mounted) setState(() => _isListening = true);
  }

  Future<void> _toggleRecording() async {
    if (_isListening) {
      _wantListening = false;
      await _speech.stop();
      if (mounted) setState(() => _isListening = false);
    } else {
      setState(() => _error = null);
      _previousText = _accumulated;
      _wantListening = true;
      await _startListening();
    }
  }

  void _clear() {
    _speech.stop();
    setState(() {
      _accumulated   = '';
      _previousText  = '';
      _isListening   = false;
      _wantListening = false;
      _error         = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.55,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, scrollController) => Container(
        decoration: const BoxDecoration(
          color: kCueSurface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SingleChildScrollView(
          controller: scrollController,
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 36),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: kCueBorder,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                widget.eyebrow,
                style: TextStyle(
                  fontSize: 11,
                  color: kCueEyebrowInk,
                  letterSpacing: kCueEyebrowLetterSpacing(11),
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                widget.subtitle,
                style: TextStyle(fontSize: 13, color: kCueSubtitleInk),
              ),
              const SizedBox(height: 24),
              if (!_speechAvailable && _error == null)
                Center(
                  child: Text('Initialising microphone…',
                      style: TextStyle(
                          fontSize: 13, color: kCueSubtitleInk)),
                )
              else ...[
                Center(
                  child: GestureDetector(
                    onTap: _toggleRecording,
                    child: Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        color: _isListening ? kCueInk : kCueAmber,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        _isListening
                            ? Icons.stop_rounded
                            : Icons.mic_rounded,
                        color: Colors.white,
                        size: 28,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Center(
                  child: Text(
                    _isListening
                        ? 'Tap to stop'
                        : (_accumulated.isEmpty
                            ? 'Tap to speak'
                            : 'Tap to continue'),
                    style: TextStyle(
                        fontSize: 12, color: kCueSubtitleInk),
                  ),
                ),
              ],
              if (_accumulated.isNotEmpty) ...[
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'transcript',
                      style: TextStyle(
                        fontSize: 11,
                        color: kCueEyebrowInk,
                        letterSpacing: kCueEyebrowLetterSpacing(11),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    GestureDetector(
                      onTap: _clear,
                      child: Text(
                        'clear',
                        style: TextStyle(
                            fontSize: 12,
                            color: kCueAmberText,
                            fontWeight: FontWeight.w500),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: kCuePaper,
                    borderRadius: BorderRadius.circular(kCueTileRadius),
                  ),
                  child: Text(
                    _accumulated,
                    style: const TextStyle(
                        fontSize: 13, color: kCueInk, height: 1.5),
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: GestureDetector(
                    onTap: _isListening
                        ? null
                        : () => Navigator.pop(context, _accumulated),
                    child: Container(
                      alignment: Alignment.center,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      decoration: BoxDecoration(
                        color: _isListening ? kCueBorder : kCueInk,
                        borderRadius: BorderRadius.circular(kCueTileRadius),
                      ),
                      child: const Text(
                        'use this transcript',
                        style: TextStyle(
                            fontSize: 14,
                            color: Colors.white,
                            fontWeight: FontWeight.w500),
                      ),
                    ),
                  ),
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!,
                    style: const TextStyle(
                        fontSize: 13, color: Colors.red)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
