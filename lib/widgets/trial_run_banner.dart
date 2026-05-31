// lib/widgets/trial_run_banner.dart
//
// Phase 4.0.7.29 Stage 2B — persistent "this is a trial run" marking shown on
// every trial-case surface. Pairs with the "TRIAL RUN" prefix baked into the
// trial case's name and the header-eyebrow flip on AssessmentCaseScreen.
//
// Built so it is trivial to make LOUDER later: pass [loud] = true to switch
// from the quiet register (faint amber tint + amber border + amber text) to a
// filled register (solid amber ground + white text + heavier border). The
// founder judges whether to escalate after seeing it live; escalation is a
// one-arg flip, no refactor.

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/cue_phase4_tokens.dart';

class TrialRunBanner extends StatelessWidget {
  /// Quiet (default) vs. filled/loud register. See file header.
  final bool loud;
  const TrialRunBanner({super.key, this.loud = false});

  @override
  Widget build(BuildContext context) {
    final Color bg = loud ? kCueAmber : kCueAmberSurface;
    final Color fg = loud ? Colors.white : kCueAmberText;
    final Color borderColor = loud ? kCueAmber : kCueAmber.withValues(alpha: 0.45);

    return Semantics(
      label: 'Trial run banner — exploration only, not a real client record',
      container: true,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: borderColor, width: loud ? 1.5 : 1),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.science_outlined, size: 18, color: fg),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'TRIAL RUN',
                    style: GoogleFonts.syne(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: fg,
                      letterSpacing: 1.6,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Exploration only — not a real client record.',
                    style: GoogleFonts.dmSans(
                      fontSize: 13,
                      color: fg,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
