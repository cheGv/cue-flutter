// lib/widgets/recall_assistant/recall_assistant_card.dart
//
// The recall assistant card content: focused-client chip (when set),
// input row (search · field · mic), scrollable recent-list of query
// blocks (newest at top), and a footer (status · Clear). Dark surface.
//
// Voice is INLINE — the mic on the card drives speech_to_text directly
// (the same package VoiceNoteSheet uses), transcribing into the field in
// real time and AUTO-SUBMITTING when speech ends (natural pause) or the
// SLP taps the mic again to stop. No separate bottom sheet.
//
// SEAM: depends on the controller + query block + speech_to_text only.
// No Supabase.

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:speech_to_text/speech_to_text.dart';

import 'recall_assistant_controller.dart';
import 'recall_assistant_query_block.dart';

class RecallAssistantCard extends StatefulWidget {
  final RecallAssistantController controller;

  /// Reserved. Inline voice no longer needs the root navigator (the old
  /// VoiceNoteSheet modal did); kept so the overlay/main wiring is
  /// unchanged and a future modal affordance can reuse it.
  final GlobalKey<NavigatorState> navigatorKey;

  const RecallAssistantCard({
    super.key,
    required this.controller,
    required this.navigatorKey,
  });

  @override
  State<RecallAssistantCard> createState() => _RecallAssistantCardState();
}

class _RecallAssistantCardState extends State<RecallAssistantCard> {
  final TextEditingController _input = TextEditingController();
  final FocusNode _focus = FocusNode();

  // Inline voice (speech_to_text).
  final SpeechToText _speech = SpeechToText();
  bool _speechReady = false;
  bool _listening = false;
  String _voiceBase = ''; // text already in the field before listening

  static const Color _surface = Color(0xFF242422);
  static const Color _border = Color(0x14FFFFFF); // white @ ~0.08
  static const Color _bodyStrong = Color(0xEBFFFFFF);
  static const Color _muted = Color(0x8CFFFFFF);
  static const Color _label = Color(0x66FFFFFF);
  static const Color _amber = Color(0xFFF5C778);
  static const Color _listenRed = Color(0xFFEF4444);

  // Focused-client chip palette (spec).
  static const Color _chipBg = Color(0xFFBA7517);
  static const Color _chipText = Color(0xFFFAEEDA);

  @override
  void initState() {
    super.initState();
    _initSpeech();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    _speech.stop();
    _input.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _initSpeech() async {
    try {
      final ready = await _speech.initialize(
        onStatus: (status) {
          // Speech ended (natural pause or stop) → auto-submit. Guarded by
          // `_listening` so a manual stop (which sets it false first)
          // doesn't double-submit, and so init/idle status events are
          // ignored.
          if ((status == 'done' || status == 'notListening') &&
              _listening &&
              mounted) {
            setState(() => _listening = false);
            _submitFromVoice();
          }
        },
        onError: (_) {
          if (mounted) setState(() => _listening = false);
        },
      );
      if (mounted) setState(() => _speechReady = ready);
    } catch (_) {
      if (mounted) setState(() => _speechReady = false);
    }
  }

  Future<void> _toggleMic() async {
    widget.controller.markActivity();
    if (!_speechReady) {
      // Late/retry init (e.g. web permission granted on first gesture).
      await _initSpeech();
      if (!_speechReady) return;
    }

    if (_listening) {
      // Manual stop → submit now. Set the flag false BEFORE stop() so the
      // onStatus callback (which may also fire) sees _listening == false
      // and skips its own submit (single-submit guarantee).
      setState(() => _listening = false);
      await _speech.stop();
      _submitFromVoice();
      return;
    }

    _voiceBase = _input.text.trim();
    setState(() => _listening = true);
    await _speech.listen(
      onResult: (result) {
        // Ignore results that arrive after we've stopped/submitted. The Web
        // Speech API can fire a trailing final result post-stop; without
        // this guard it repopulates the just-cleared field, and the NEXT
        // dictation concatenates onto that leftover.
        if (!mounted || !_listening) return;
        final words = result.recognizedWords;
        final next = _voiceBase.isEmpty ? words : '$_voiceBase $words';
        setState(() {
          _input.text = next;
          _input.selection = TextSelection.fromPosition(
            TextPosition(offset: _input.text.length),
          );
        });
      },
      listenFor: const Duration(seconds: 30),
      pauseFor: const Duration(seconds: 3),
      listenOptions: SpeechListenOptions(partialResults: true),
    );
  }

  // Both submit paths leave the input in identical clean state AND reset the
  // voice accumulator, so the next dictation starts fresh.
  void _clearInput() {
    _input.text = '';
    _voiceBase = '';
    _input.selection = const TextSelection.collapsed(offset: 0);
  }

  void _submitFromVoice() {
    final text = _input.text.trim();
    if (text.isEmpty) return;
    widget.controller.submit(text);
    _clearInput();
    _focus.requestFocus();
  }

  void _submit() {
    if (_listening) {
      // Enter while dictating → stop + submit through the voice path.
      _toggleMic();
      return;
    }
    final text = _input.text.trim();
    if (text.isEmpty) return;
    widget.controller.submit(text);
    _clearInput();
    _focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: _surface,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _border, width: 0.5),
        ),
        child: AnimatedBuilder(
          animation: widget.controller,
          builder: (context, _) {
            final recent = widget.controller.recent;
            final focusedName = widget.controller.focusedClientName;
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (focusedName != null && focusedName.isNotEmpty)
                  _focusChip(focusedName),
                _inputRow(focusedName),
                const Divider(height: 0.5, thickness: 0.5, color: _border),
                Flexible(child: _results(recent)),
                const Divider(height: 0.5, thickness: 0.5, color: _border),
                _footer(recent.length),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _focusChip(String name) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Align(
        alignment: Alignment.centerLeft,
        child: InkWell(
          onTap: widget.controller.clearFocusedClient,
          borderRadius: BorderRadius.circular(999),
          child: Container(
            padding: const EdgeInsets.fromLTRB(10, 4, 8, 4),
            decoration: BoxDecoration(
              color: _chipBg,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Asking about $name',
                  style: GoogleFonts.dmSans(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: _chipText,
                  ),
                ),
                const SizedBox(width: 4),
                const Icon(Icons.close_rounded, size: 13, color: _chipText),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _inputRow(String? focusedName) {
    final hint = (focusedName != null && focusedName.isNotEmpty)
        ? 'Ask about $focusedName…'
        : 'Ask Cue…';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 10, 12),
      child: Row(
        children: [
          const Icon(Icons.search_rounded, size: 18, color: _muted),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: _input,
              focusNode: _focus,
              onSubmitted: (_) => _submit(),
              textInputAction: TextInputAction.search,
              style: GoogleFonts.dmSans(fontSize: 15, color: _bodyStrong),
              cursorColor: _amber,
              decoration: InputDecoration(
                isCollapsed: true,
                border: InputBorder.none,
                hintText: hint,
                hintStyle: GoogleFonts.dmSans(fontSize: 15, color: _muted),
              ),
            ),
          ),
          const SizedBox(width: 8),
          _micButton(),
        ],
      ),
    );
  }

  Widget _micButton() {
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: _listening ? _listenRed.withValues(alpha: 0.16) : null,
      ),
      child: IconButton(
        onPressed: _toggleMic,
        icon: Icon(_listening ? Icons.mic : Icons.mic_none_rounded, size: 18),
        color: _listening ? _listenRed : _muted,
        tooltip: _listening ? 'Stop & send' : 'Voice',
        visualDensity: VisualDensity.compact,
        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
      ),
    );
  }

  Widget _results(List recent) {
    if (recent.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 22, 16, 22),
        child: Text(
          widget.controller.busy
              ? 'Checking…'
              : "Ask about a client's last goal, last session accuracy, "
                  'parent update, or home programme.',
          style: GoogleFonts.dmSans(fontSize: 13, color: _muted, height: 1.5),
        ),
      );
    }
    return ListView.separated(
      shrinkWrap: true,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      itemCount: recent.length + (widget.controller.busy ? 1 : 0),
      separatorBuilder: (_, _) => const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Divider(height: 0.5, thickness: 0.5, color: _border),
      ),
      itemBuilder: (context, i) {
        // While busy, show a "Checking…" row at the very top.
        if (widget.controller.busy && i == 0) {
          return Text(
            'Checking…',
            style: GoogleFonts.dmSans(
              fontSize: 12,
              fontStyle: FontStyle.italic,
              color: _label,
            ),
          );
        }
        final idx = widget.controller.busy ? i - 1 : i;
        final q = recent[idx];
        return RecallAssistantQueryBlock(
          query: q,
          focusedClientName: widget.controller.focusedClientName,
          onPickClient: (name) => widget.controller.disambiguate(q, name),
          onOpenInStudy: () => widget.controller.openInStudy(q),
          onSkipEscalation: () => widget.controller.skipEscalation(q),
          onSuggestion: (phrase) {
            // Submit "<intent phrase> for <focused client>" so the resolver
            // resolves directly to the focused client + that intent.
            final fc = widget.controller.focusedClientName?.trim() ?? '';
            widget.controller.submit(fc.isEmpty ? phrase : '$phrase for $fc');
          },
        );
      },
    );
  }

  Widget _footer(int n) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '$n recent · clears on sign out',
              style: GoogleFonts.dmSans(fontSize: 11, color: _label),
            ),
          ),
          InkWell(
            onTap: widget.controller.clear,
            borderRadius: BorderRadius.circular(6),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Text(
                'Clear',
                style: GoogleFonts.dmSans(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: _muted,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
