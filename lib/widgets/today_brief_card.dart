// lib/widgets/today_brief_card.dart
//
// Phase 4.0.7.22a — production Today's Brief card. Shipped Variant B
// (CLINICAL HANDOFF) from the 4.0.7.21 design exploration. Rendered
// once per client on today's roster as a vertical stack on the Today
// screen.
//
// Three labeled zones — WHAT HAPPENED / WHERE WE LEFT OFF / TODAY'S
// MOVE — fed by the most recent session row joined client-side with
// the daily roster row. The TODAY zone is teal-tinted to set off the
// forward action from the historical context.
//
// Empty state covers two distinct cases:
//   - No previous session at all (baseline phase) → friendly hint.
//   - Previous session exists but next_session_focus is blank → fall
//     back to "Continue: <yesterday's STG>".

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

const Color _ink        = Color(0xFF0E1C36);
const Color _inkGhost   = Color(0xFF6B7690);
const Color _teal       = Color(0xFF2A8F84);
const Color _tealSoft   = Color(0xFFD6E8E5);
const Color _line       = Color(0xFFE6DDCA);

/// Pure-data shape derived from the daily_roster + sessions join. The
/// TodayScreen state class assembles this from its existing loaders.
class TodayBrief {
  final String  clientName;
  final int?    clientAge;
  final String? clientLensSubtitle;

  /// Most-recent session date in display form (e.g. "3 May" or "today").
  final String? lastSessionDateLabel;
  final String? lastTargetBehavior;
  final String? lastActivity;
  final String? lastNarrative; // SOAP-S/notes etc. — concise summary
  final String? lastAccuracy;  // pre-formatted "3 of 8 (38%)" string
  final String? nextSessionFocus;

  /// Today's planned session start time (e.g. "9:00 AM"). Optional.
  final String? todayTimeLabel;

  /// True when the SLP has no history with this client at all — ie
  /// no prior session. Renders the baseline-phase empty state.
  final bool baselinePhase;

  const TodayBrief({
    required this.clientName,
    this.clientAge,
    this.clientLensSubtitle,
    this.lastSessionDateLabel,
    this.lastTargetBehavior,
    this.lastActivity,
    this.lastNarrative,
    this.lastAccuracy,
    this.nextSessionFocus,
    this.todayTimeLabel,
    this.baselinePhase = false,
  });
}

class TodayBriefCard extends StatelessWidget {
  final TodayBrief brief;
  final VoidCallback? onTap;

  const TodayBriefCard({
    super.key,
    required this.brief,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 18),
          decoration: BoxDecoration(
            color:        Colors.white,
            borderRadius: BorderRadius.circular(14),
            border:       Border.all(color: _line),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _header(),
              const SizedBox(height: 16),
              if (brief.baselinePhase) ...[
                _section(
                  'WHAT HAPPENED',
                  'Baseline phase — no sessions on record.',
                ),
                const SizedBox(height: 14),
                _section(
                  "TODAY'S MOVE",
                  'Begin baseline observation.',
                  tinted: true,
                ),
              ] else ...[
                _section(
                  'WHAT HAPPENED',
                  _whatHappenedBody(),
                ),
                const SizedBox(height: 14),
                _section(
                  'WHERE WE LEFT OFF',
                  _whereWeLeftOffBody(),
                ),
                const SizedBox(height: 14),
                _section(
                  "TODAY'S MOVE",
                  _todayMoveBody(),
                  tinted: true,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // ── Header row: client name + optional time ────────────────────────────
  Widget _header() {
    final subtitleParts = <String>[
      if (brief.todayTimeLabel != null) brief.todayTimeLabel!,
      if (brief.clientAge != null) 'age ${brief.clientAge}',
      if (brief.clientLensSubtitle != null) brief.clientLensSubtitle!,
    ];
    final subtitle = subtitleParts.join(' · ');

    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline:       TextBaseline.alphabetic,
      children: [
        Flexible(
          child: Text(
            brief.clientName,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.dmSans(
              fontSize:    16,
              fontWeight:  FontWeight.w600,
              color:       _ink,
              height:      1.2,
            ),
          ),
        ),
        if (subtitle.isNotEmpty) ...[
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              subtitle,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.dmSans(
                fontSize: 11,
                color:    _inkGhost,
                letterSpacing: 0.3,
              ),
            ),
          ),
        ],
      ],
    );
  }

  // ── Body content assemblers — all defensive against missing fields ────
  String _whatHappenedBody() {
    final date = brief.lastSessionDateLabel;
    final activity = brief.lastActivity;
    if ((date == null || date.isEmpty) && (activity == null || activity.isEmpty)) {
      return 'Last session details not recorded.';
    }
    final parts = <String>[
      if (date != null && date.isNotEmpty) date,
      if (activity != null && activity.isNotEmpty) activity,
    ];
    return '${parts.join(' · ')}.';
  }

  String _whereWeLeftOffBody() {
    final narrative = brief.lastNarrative?.trim();
    final accuracy  = brief.lastAccuracy?.trim();
    if ((narrative == null || narrative.isEmpty) &&
        (accuracy == null || accuracy.isEmpty)) {
      return brief.lastTargetBehavior?.trim().isNotEmpty == true
          ? 'Target was: ${brief.lastTargetBehavior}.'
          : 'Session not yet documented.';
    }
    final body = StringBuffer();
    if (narrative != null && narrative.isNotEmpty) body.write(narrative);
    if (accuracy != null && accuracy.isNotEmpty) {
      if (body.isNotEmpty) body.write(' ');
      body.write('Accuracy: $accuracy.');
    }
    return body.toString();
  }

  String _todayMoveBody() {
    final next = brief.nextSessionFocus?.trim();
    if (next != null && next.isNotEmpty) return next;
    final stg = brief.lastTargetBehavior?.trim();
    if (stg != null && stg.isNotEmpty) {
      return 'Continue: $stg.';
    }
    return 'No move on file — set the next focus during today\'s session.';
  }

  // ── Section primitive ─────────────────────────────────────────────────
  Widget _section(String label, String body, {bool tinted = false}) {
    return Container(
      width: double.infinity,
      padding: tinted
          ? const EdgeInsets.fromLTRB(12, 10, 12, 12)
          : EdgeInsets.zero,
      decoration: tinted
          ? BoxDecoration(
              color:        _tealSoft.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(8),
              border:       Border.all(color: _tealSoft),
            )
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: GoogleFonts.syne(
              fontSize:      10,
              fontWeight:    FontWeight.w600,
              color:         tinted ? _teal : _inkGhost,
              letterSpacing: 1.6,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            body,
            style: GoogleFonts.dmSans(
              fontSize: 13.5,
              color:    _ink,
              height:   1.55,
            ),
          ),
        ],
      ),
    );
  }
}
