// lib/widgets/profile/next_session_pillar.dart
//
// Phase 5.3 Round B — Next Session hero pillar. Scaffold-only for
// Round B; real Cue-drafted plan generation lands in Phase 5.4.
//
// Round B renders an empty-state with an "Ask Cue to draft" CTA
// that opens the popup. The widget structure anticipates the
// Phase 5.4 drafted-state branch (review activities, accept/edit
// pills) by keeping a single body builder that switches on a
// future `draftActivities` prop.

import 'package:flutter/material.dart';

import '../../theme/cue_color_scheme.dart';
import '_hero_pillar_frame.dart';

class NextSessionPillar extends StatelessWidget {
  /// Client's display name — used in the empty-state copy.
  final String clientName;

  /// Optional tap handler — opens CuePopup with draft-next-session
  /// intent. Round B passes Profile's _toggleCuePopup; Round G
  /// refines to scope='draft-next-session' for the command palette.
  final VoidCallback? onAskCue;

  const NextSessionPillar({
    super.key,
    required this.clientName,
    this.onAskCue,
  });

  @override
  Widget build(BuildContext context) {
    final cue = CueColorsResolved.of(context);
    final firstName = _firstName();
    return HeroPillarFrame(
      icon:    Icons.event_outlined,
      accent:  cue.amber,
      tag:     'Next session',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'No plan drafted yet.',
            style: TextStyle(
              fontFamily: 'Inter',
              fontFamilyFallback: const ['system-ui', 'sans-serif'],
              fontSize: 15,
              fontWeight: FontWeight.w500,
              letterSpacing: -0.16,
              color: cue.textPrimary,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Ask Cue to draft activities for $firstName\'s next session — '
            'tied to active steps, calibrated to the last few sessions.',
            style: TextStyle(
              fontFamily: 'Inter',
              fontFamilyFallback: const ['system-ui', 'sans-serif'],
              fontSize: 13,
              height: 1.5,
              color: cue.textBody,
            ),
          ),
        ],
      ),
      footer: onAskCue == null
          ? null
          : _DraftPill(
              label: 'Draft with Cue →',
              onTap: onAskCue!,
              accent: cue.amber,
            ),
    );
  }

  String _firstName() {
    final parts = clientName.trim().split(RegExp(r'\s+'));
    return parts.isEmpty ? clientName : parts.first;
  }
}

class _DraftPill extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final Color accent;
  const _DraftPill({
    required this.label,
    required this.onTap,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final cue = CueColorsResolved.of(context);
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: accent.withValues(alpha: cue.isDark ? 0.15 : 0.1),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: accent.withValues(alpha: 0.45),
            width: 0.5,
          ),
          // Glow on primary CTA (Phase 5.3 edge polish — dark only).
          boxShadow: cue.isDark
              ? [
                  BoxShadow(
                    color: accent.withValues(alpha: 0.25),
                    blurRadius: 4,
                  ),
                ]
              : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: 'Inter',
            fontFamilyFallback: const ['system-ui', 'sans-serif'],
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: accent,
          ),
        ),
      ),
    );
  }
}
