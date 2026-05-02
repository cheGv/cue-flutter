// lib/widgets/noticed_moment.dart
//
// Phase 2 companion noticed moments — gap detection, stuck-goal detection,
// Monday-first detection, returning-soft detection. Returns null if nothing
// is worth noticing; otherwise produces a NoticedMoment that the chart
// renders ABOVE the regular brief.
//
// =====================================================================
// LANGUAGE DISCIPLINE — see CLAUDE.md §13. Audited Phase 3.2.2 (current
// strings pass; this comment block locks the rule for future edits).
//
// Cue surfaces observations, never characterizes a child / family / goal
// as deficient. FORBIDDEN here and in any future companion-register copy:
//   stuck, overdue, behind, no progress, plateau, struggling, failing,
//   regressing, slow learner, low-functioning, non-progressing, falling
//   behind, lagging, despite, intervention timing, developmental
//   trajectory, critical window, critical period, missed opportunity,
//   falling further, gap widening, behind peers, age-appropriate,
//   age-typical, developmental delay (as a Cue-authored verdict).
//
// REQUIRED reframings:
//   - Long-active goal  → "Active for N sessions — review when you have
//                          a moment." (goal owns time; SLP owns review)
//   - Documentation gap → "Note pending from {date}." (SLP owns the
//                          pending work, not the child)
//   - Absence / duration → state the number; let the SLP interpret.
//
// Code-identifier exception (CLAUDE.md §13.4): the enum value
// `NoticedTrigger.stuck` is a code symbol — never user-visible — so it
// stays. Its user-facing line1/line2 ("Same step for four sessions." /
// "Worth thinking through.") locate the observation in time, not in a
// verdict, and pass §13.
// =====================================================================

import 'package:flutter/material.dart';
import '../theme/cue_theme.dart';
import '../theme/cue_tokens.dart';
import '../theme/cue_typography.dart';
import 'cue_cuttlefish.dart';

enum NoticedTrigger { gap, stuck, monday, soft }

class NoticedMoment {
  final NoticedTrigger trigger;
  final CueState       state;
  final String         line1;
  final String         line2;

  const NoticedMoment({
    required this.trigger,
    required this.state,
    required this.line1,
    required this.line2,
  });
}

/// Detection rules — first match wins. Returns null when no special moment.
///
/// Inputs:
///   [client] — the chart's client row (for first name)
///   [sessions] — newest-first list of session rows for this client
///   [goals] — STG rows (each row has a `step_level` or `current_cue_level`)
///   [todaySessionCount] — total sessions scheduled today across the
///     clinician's roster (Monday-first calc)
///   [isFirstClientToday] — caller passes true if this client is the first
///     one opened today
///   [now] — injectable for testing; defaults to DateTime.now().
NoticedMoment? detectNoticedMoment({
  required Map<String, dynamic>             client,
  required List<Map<String, dynamic>>       sessions,
  required List<Map<String, dynamic>>       goals,
  required int                              todaySessionCount,
  required bool                             isFirstClientToday,
  DateTime?                                 now,
}) {
  final reference = now ?? DateTime.now();
  final firstName = _firstName(client);

  // ── 1. GAP — last session > 14 days ago ────────────────────────────────
  if (sessions.isNotEmpty) {
    final last = _parseDate(
        sessions.first['date'] as String? ??
        sessions.first['created_at'] as String?);
    if (last != null) {
      final days = reference.difference(last).inDays;
      if (days > 14) {
        return NoticedMoment(
          trigger: NoticedTrigger.gap,
          state:   CueState.steadyNod,
          line1:   "It's been a while since $firstName.",
          line2:   "Take a minute first.",
        );
      }
    }
  }

  // ── 2. STUCK — any active goal at same step level for 4+ sessions ─────
  // We scan the last 4 sessions for the same goal's step / cue level.
  for (final g in goals.where(_isActive)) {
    final goalLevel = (g['current_cue_level'] as String?) ??
                      (g['initial_cue_level'] as String?);
    if (goalLevel == null || goalLevel.isEmpty) continue;
    int consecutive = 0;
    for (final s in sessions.take(8)) {
      final sLevel = (s['prompt_approach'] as String?) ??
                     (s['client_affect']   as String?);
      if (sLevel != null && sLevel.isNotEmpty && sLevel == goalLevel) {
        consecutive++;
        if (consecutive >= 4) break;
      } else {
        consecutive = 0;
      }
    }
    if (consecutive >= 4) {
      return const NoticedMoment(
        trigger: NoticedTrigger.stuck,
        state:   CueState.thinking,
        line1:   "Same step for four sessions.",
        line2:   "Worth thinking through.",
      );
    }
  }

  // ── 3. MONDAY FIRST — Monday + first client opened today ──────────────
  if (reference.weekday == DateTime.monday && isFirstClientToday) {
    final n = todaySessionCount.clamp(1, 999);
    return NoticedMoment(
      trigger: NoticedTrigger.monday,
      state:   CueState.softWave,
      line1:   "$n session${n == 1 ? "" : "s"} today.",
      line2:   "$firstName is your first.",
    );
  }

  // ── 4. RETURNING SOFT — last 3 sessions hit goal targets ──────────────
  if (sessions.length >= 3) {
    final last3 = sessions.take(3);
    final allHit = last3.every((s) {
      final met = (s['goal_met'] as String?)?.toLowerCase();
      return met == 'yes' || met == 'met';
    });
    if (allHit) {
      return NoticedMoment(
        trigger: NoticedTrigger.soft,
        state:   CueState.softWave,
        line1:   "$firstName is on a roll.",
        line2:   "Last three sessions hit target.",
      );
    }
  }

  return null;
}

bool _isActive(Map<String, dynamic> g) {
  final s = (g['status'] as String?)?.toLowerCase();
  return s == null || s.isEmpty || s == 'active';
}

DateTime? _parseDate(String? s) {
  if (s == null || s.isEmpty) return null;
  try { return DateTime.parse(s); } catch (_) { return null; }
}

String _firstName(Map<String, dynamic> client) {
  final full = (client['name'] as String?)?.trim() ?? '';
  if (full.isEmpty) return 'this child';
  return full.split(RegExp(r'\s+')).first;
}

// ── Render widget ────────────────────────────────────────────────────────────

/// Renders a NoticedMoment inline above the chart's regular brief. Two-line
/// thought + soft action buttons. Layout matches the new "Cue noticed"
/// architectural register (no card chrome, just the eyebrow + thought).
class NoticedMomentView extends StatelessWidget {
  final NoticedMoment moment;
  final VoidCallback? onPrimary;
  final VoidCallback? onSecondary;
  final String        primaryLabel;
  final String        secondaryLabel;

  const NoticedMomentView({
    super.key,
    required this.moment,
    this.onPrimary,
    this.onSecondary,
    this.primaryLabel   = 'Open chart',
    this.secondaryLabel = 'Later',
  });

  @override
  Widget build(BuildContext context) {
    final isNight = Theme.of(context).brightness == Brightness.dark;
    final ink     = isNight ? CueColors.inkDark        : CueColors.inkPrimary;
    final amberLn = isNight ? CueColors.amber          : CueColors.amberDark;
    final divider = isNight ? CueColors.dividerDark    : CueColors.divider;

    return Padding(
      padding: const EdgeInsets.fromLTRB(0, CueGap.s24, 0, CueGap.s32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Eyebrow row: small Cue + "CUE NOTICED" + hairline filler
          Row(
            children: [
              SizedBox(
                width:  CueSize.cuttlefishEyebrow,
                height: CueSize.cuttlefishEyebrowSlot,
                child: CueCuttlefish(
                    size: CueSize.cuttlefishEyebrow, state: moment.state),
              ),
              const SizedBox(width: CueGap.s8),
              Text(
                'CUE NOTICED',
                style: CueType.labelSmall.copyWith(color: amberLn),
              ),
              const SizedBox(width: CueGap.s12),
              Expanded(
                child: Container(
                    height: CueSize.hairline, color: divider)),
            ],
          ),
          const SizedBox(height: CueGap.s14),
          Text(
            moment.line1,
            style: CueType.displayMedium.copyWith(color: ink),
          ),
          Text(
            moment.line2,
            style: CueType.displayMedium.copyWith(color: amberLn),
          ),
          if (onPrimary != null || onSecondary != null) ...[
            const SizedBox(height: CueGap.s24),
            Row(
              children: [
                if (onPrimary != null)
                  _SoftButton(
                    label:   primaryLabel,
                    onTap:   onPrimary!,
                    primary: true,
                  ),
                if (onPrimary != null && onSecondary != null)
                  const SizedBox(width: CueGap.s8),
                if (onSecondary != null)
                  _SoftButton(
                    label:   secondaryLabel,
                    onTap:   onSecondary!,
                    primary: false,
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _SoftButton extends StatelessWidget {
  final String       label;
  final VoidCallback onTap;
  final bool         primary;
  const _SoftButton({
    required this.label,
    required this.onTap,
    required this.primary,
  });

  @override
  Widget build(BuildContext context) {
    final isNight = Theme.of(context).brightness == Brightness.dark;
    final amber   = CueColors.amber;
    final ink     = isNight ? CueColors.inkDark : CueColors.inkPrimary;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: CueGap.s16, vertical: CueGap.s9),
        decoration: BoxDecoration(
          color: primary
              ? amber.withValues(alpha: CueAlpha.softTint)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(CueRadius.s20),
        ),
        child: Text(
          label,
          style: CueType.labelLarge.copyWith(
            color: primary
                ? amber
                : ink.withValues(alpha: CueAlpha.softInactiveText),
          ),
        ),
      ),
    );
  }
}
