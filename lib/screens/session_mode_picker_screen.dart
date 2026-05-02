// lib/screens/session_mode_picker_screen.dart
//
// Phase 4.0.4 — intermediate "what kind of session is this?" picker.
//
// For population_type == 'developmental_stuttering' clients, the existing
// "+ Session" affordance lands here instead of the legacy
// AddSessionScreen body. The SLP picks one of three Layer-03 sub-modes;
// only live entry routes to its destination in 4.0.4. Debrief and
// parent interview surface a "coming soon" toast — they ship in 4.0.5
// and 4.0.6 respectively (see PHASE_4_SPEC.md re-sequencing in §14.8).
//
// Visual register: locked Phase 4.0 — paper background, white cards,
// amber accent, lowercase tracked eyebrow on the section, Playfair
// italic on each card title.

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/cue_phase4_tokens.dart';
import 'live_entry_fluency_screen.dart';

class SessionModePickerView extends StatelessWidget {
  final String clientId;
  final String clientName;

  const SessionModePickerView({
    super.key,
    required this.clientId,
    required this.clientName,
  });

  void _openLiveEntry(BuildContext context) {
    Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => LiveEntryFluencyScreen(
          clientId: clientId,
          clientName: clientName,
        ),
      ),
    ).then((saved) {
      // Bubble up — chart will refresh roster on `true`.
      if (saved == true && context.mounted) {
        Navigator.pop(context, true);
      }
    });
  }

  void _comingSoon(BuildContext context, String mode) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('$mode mode lands in the next build session.'),
      duration: const Duration(seconds: 3),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: kCuePaper,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 32, 24, 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'session',
                  style: TextStyle(
                    fontSize: 11,
                    color: kCueEyebrowInk,
                    letterSpacing: kCueEyebrowLetterSpacing(11),
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'What kind of session is this?',
                  style: GoogleFonts.playfairDisplay(
                    fontSize: 28,
                    fontStyle: FontStyle.italic,
                    fontWeight: FontWeight.w600,
                    color: kCueInk,
                    height: 1.05,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  clientName,
                  style: TextStyle(fontSize: 14, color: kCueSubtitleInk),
                ),
                const SizedBox(height: 24),
                _modeCard(
                  context: context,
                  title: 'Live entry',
                  subtitle: 'Record during the session.',
                  hint: 'Tablet-friendly counters for syllables, disfluencies, '
                      'accessory behaviours. %SS computes live.',
                  enabled: true,
                  onTap: () => _openLiveEntry(context),
                ),
                const SizedBox(height: 12),
                _modeCard(
                  context: context,
                  title: 'Debrief',
                  subtitle: 'Capture after the session.',
                  hint: 'Severity rating, clinical impression, observed '
                      'avoidance — composed once the room is quiet.',
                  enabled: false,
                  onTap: () => _comingSoon(context, 'Debrief'),
                ),
                const SizedBox(height: 12),
                _modeCard(
                  context: context,
                  title: 'Parent interview',
                  subtitle: 'Caregiver conversation.',
                  hint: 'Recurrent surface for caregiver-reported context '
                      'across the assessment phase.',
                  enabled: false,
                  onTap: () => _comingSoon(context, 'Parent interview'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _modeCard({
    required BuildContext context,
    required String title,
    required String subtitle,
    required String hint,
    required bool enabled,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
        decoration: BoxDecoration(
          color: kCueSurface,
          borderRadius: BorderRadius.circular(kCueCardRadius),
          border: Border.all(color: kCueBorder, width: kCueCardBorderW),
        ),
        child: Opacity(
          opacity: enabled ? 1.0 : 0.55,
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          title,
                          style: GoogleFonts.playfairDisplay(
                            fontSize: 20,
                            fontStyle: FontStyle.italic,
                            fontWeight: FontWeight.w600,
                            color: kCueInk,
                            height: 1.1,
                          ),
                        ),
                        if (!enabled) ...[
                          const SizedBox(width: 10),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: kCueAmberSurface,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              'next session',
                              style: TextStyle(
                                fontSize: 10,
                                color: kCueAmberText,
                                letterSpacing: kCueEyebrowLetterSpacing(10),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(fontSize: 14, color: kCueSubtitleInk),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      hint,
                      style: TextStyle(
                        fontSize: 13,
                        color: kCueEyebrowInk,
                        height: 1.45,
                      ),
                    ),
                  ],
                ),
              ),
              if (enabled) ...[
                const SizedBox(width: 12),
                const Icon(Icons.arrow_forward_rounded,
                    color: kCueAmber, size: 22),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
