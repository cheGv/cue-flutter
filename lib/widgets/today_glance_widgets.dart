// lib/widgets/today_glance_widgets.dart
//
// Phase 4.0.8-step-B-surface-1.2 — five "At a glance" widgets for the
// Today screen, each self-contained and consuming its own data type
// from TodayWidgetsService.
//
// Widgets:
//   • ThisWeekWidget        — Mon-Fri pulse bar chart + session/doc stats.
//                             Today's bar in amber; other days olive.
//                             Day labels Mon/Tue/Wed/Thu/Fri sentence-case
//                             Inter (NOT M T W T F mono).
//   • PendingNotesWidget    — big Iowan numeric in amber + Text.rich label
//                             with sentence-case day words and mono times.
//                             Amber CTA "Catch up →".
//   • CueNoticedWidget      — full-width row with 32px softWave cuttlefish
//                             + Iowan body + 3 action links. Hidden by
//                             caller when CueInsight is null.
//   • ActiveGoalsWidget     — top 4 goals, name + progress mono in olive.
//   • TomorrowWidget        — big Iowan numeric in olive + first-session
//                             preview.
//
// Layout: each widget is a self-sufficient Container (white surface,
// kCueBorder hairline, padding 16-18, min-height 130). The parent
// (today_screen.dart) decides Row vs. Column composition by viewport
// width.

import 'package:flutter/material.dart';

import '../services/today_widgets_service.dart';
import '../theme/cue_phase4_tokens.dart';
import '../theme/cue_type_v3.dart';
import 'cue_cuttlefish.dart';

const double _kWidgetRadius   = 14.0; // editorial register, between cards (6)
                                      // and pills (20)
const double _kWidgetMinHeight = 130;

BoxDecoration _widgetSurface() => BoxDecoration(
      color:        kCueSurfaceWhite,
      borderRadius: BorderRadius.circular(_kWidgetRadius),
      border:       Border.all(color: kCueBorder, width: kCueCardBorderW),
    );

// ── This week pulse ──────────────────────────────────────────────────────────

class ThisWeekWidget extends StatelessWidget {
  final List<DailyPulse> weekData;

  const ThisWeekWidget({super.key, required this.weekData});

  @override
  Widget build(BuildContext context) {
    final todayWeekday = DateTime.now().weekday; // 1..7

    int sessionsTotal   = 0;
    int documentedTotal = 0;
    int maxBar          = 1;
    for (final d in weekData) {
      sessionsTotal   += d.sessionCount;
      documentedTotal += d.documentedCount;
      if (d.sessionCount > maxBar) maxBar = d.sessionCount;
    }

    return Container(
      padding:   const EdgeInsets.fromLTRB(18, 16, 18, 16),
      constraints: const BoxConstraints(minHeight: _kWidgetMinHeight),
      decoration: _widgetSurface(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('This week', style: CueTypeV3.widgetTitle()),
          const SizedBox(height: 14),
          // Bar chart row.
          SizedBox(
            height: 56,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (var i = 0; i < weekData.length; i++) ...[
                  Expanded(child: _bar(weekData[i], todayWeekday, maxBar)),
                  if (i < weekData.length - 1) const SizedBox(width: 6),
                ],
              ],
            ),
          ),
          const SizedBox(height: 6),
          // Day labels row (Inter sentence-case per eyebrow doctrine).
          Row(
            children: [
              for (var i = 0; i < weekData.length; i++) ...[
                Expanded(
                  child: Center(
                    child: Text(
                      _dayName(weekData[i].weekday),
                      style: CueTypeV3.widgetLabel(
                        color: weekData[i].weekday == todayWeekday
                            ? kCueAmber
                            : kCueInkTertiary,
                      ),
                    ),
                  ),
                ),
                if (i < weekData.length - 1) const SizedBox(width: 6),
              ],
            ],
          ),
          const SizedBox(height: 14),
          // Stat row.
          Row(
            children: [
              Expanded(
                child: _stat(
                  number: '$sessionsTotal',
                  label:  'Sessions',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _stat(
                  number: '$documentedTotal',
                  label:  'Documented',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _bar(DailyPulse d, int todayWeekday, int maxBar) {
    final pct = maxBar == 0 ? 0.0 : d.sessionCount / maxBar;
    final isToday = d.weekday == todayWeekday;
    final color = isToday ? kCueAmber : kCueOlive;
    return Align(
      alignment: Alignment.bottomCenter,
      child: Container(
        height: 8 + (40 * pct), // min 8px stub, max 48px
        decoration: BoxDecoration(
          color:        color.withValues(alpha: d.sessionCount == 0 ? 0.18 : 0.85),
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }

  Widget _stat({required String number, required String label}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(number, style: CueTypeV3.numericDisplay(size: 22)),
        const SizedBox(height: 2),
        Text(label, style: CueTypeV3.widgetLabel()),
      ],
    );
  }

  String _dayName(int weekday) {
    const names = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return names[weekday - 1];
  }
}

// ── Pending notes ────────────────────────────────────────────────────────────

class PendingNotesWidget extends StatelessWidget {
  final List<PendingSession> pending;
  final VoidCallback? onCatchUp;

  const PendingNotesWidget({
    super.key,
    required this.pending,
    this.onCatchUp,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding:   const EdgeInsets.fromLTRB(18, 16, 18, 16),
      constraints: const BoxConstraints(minHeight: _kWidgetMinHeight),
      decoration: _widgetSurface(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Pending notes', style: CueTypeV3.widgetTitle()),
          const SizedBox(height: 12),
          // Big amber numeric — Iowan editorial register.
          Text(
            '${pending.length}',
            style: CueTypeV3.numericDisplay(size: 38, color: kCueAmber),
          ),
          const SizedBox(height: 6),
          // Date + time specifics — Inter sentence-case for date words,
          // mono for times. Text.rich.
          if (pending.isNotEmpty)
            Text.rich(
              _buildLabelSpans(pending),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            )
          else
            Text('All caught up.', style: CueTypeV3.widgetLabel()),
          const Spacer(),
          if (pending.isNotEmpty && onCatchUp != null)
            GestureDetector(
              onTap: onCatchUp,
              child: Text(
                'Catch up →',
                style: CueTypeV3.clinicalLabel(
                  emphasis: 'strong',
                  color:    kCueAmber,
                ),
              ),
            ),
        ],
      ),
    );
  }

  TextSpan _buildLabelSpans(List<PendingSession> pending) {
    final spans = <InlineSpan>[];
    for (var i = 0; i < pending.length; i++) {
      if (i > 0) {
        spans.add(TextSpan(
          text:  ' · ',
          style: CueTypeV3.widgetLabel(color: kCueInkTertiary),
        ));
      }
      final p = pending[i];
      spans.add(TextSpan(
        text:  '${p.dayLabel} ',
        style: CueTypeV3.widgetLabel(),
      ));
      spans.add(TextSpan(
        text:  p.timeLabel,
        style: CueTypeV3.dataMono(color: kCueInkSecondary),
      ));
      spans.add(TextSpan(
        text:  ' · ${p.clientName}',
        style: CueTypeV3.widgetLabel(),
      ));
    }
    return TextSpan(children: spans);
  }
}

// ── Cue noticed (full-width) ─────────────────────────────────────────────────

class CueNoticedWidget extends StatelessWidget {
  final CueInsight insight;
  final VoidCallback? onShareWithFamily;
  final VoidCallback? onAddToNextSession;
  final VoidCallback? onDismiss;

  const CueNoticedWidget({
    super.key,
    required this.insight,
    this.onShareWithFamily,
    this.onAddToNextSession,
    this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding:   const EdgeInsets.fromLTRB(18, 18, 18, 16),
      constraints: const BoxConstraints(minHeight: _kWidgetMinHeight),
      decoration: _widgetSurface(),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 32px cuttlefish, softWave — companion presence.
          const SizedBox(
            width:  32,
            height: 32,
            child: CueCuttlefish(size: 32, state: CueState.softWave),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Cue noticed',
                  style: CueTypeV3.clinicalLabel(emphasis: 'strong'),
                ),
                const SizedBox(height: 6),
                // Iowan body — editorial moment per Rule 2 carve-out.
                // Family-facing-style register applied to a clinical
                // observation; the cuttlefish + serif body together
                // signal "Cue's reflective voice."
                Text(
                  insight.renderedBody,
                  style: TextStyle(
                    fontFamily:         'Iowan Old Style',
                    fontFamilyFallback: const ['Georgia', 'Charter', 'serif'],
                    fontSize:           15.5,
                    fontWeight:         FontWeight.w400,
                    letterSpacing:      -0.0775, // -0.005em × 15.5
                    height:             1.45,
                    color:              kCueInkSecondary,
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing:   16,
                  runSpacing: 6,
                  children: [
                    if (onShareWithFamily != null)
                      _action('Share with family', onShareWithFamily!),
                    if (onAddToNextSession != null)
                      _action('Add to next session', onAddToNextSession!),
                    if (onDismiss != null)
                      _action('Dismiss', onDismiss!,
                          color: kCueInkTertiary),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _action(String label, VoidCallback onTap, {Color? color}) {
    return GestureDetector(
      onTap: onTap,
      child: Text(
        label,
        style: CueTypeV3.clinicalLabel(
          emphasis: 'strong',
          color:    color ?? kCueOlive,
        ).copyWith(
          decoration:          TextDecoration.underline,
          decorationColor:     (color ?? kCueOlive).withValues(alpha: 0.45),
          decorationThickness: 0.5,
        ),
      ),
    );
  }
}

// ── Active goals (top 4) ─────────────────────────────────────────────────────

class ActiveGoalsWidget extends StatelessWidget {
  final List<ActiveGoal> goals;

  const ActiveGoalsWidget({super.key, required this.goals});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding:   const EdgeInsets.fromLTRB(18, 16, 18, 16),
      constraints: const BoxConstraints(minHeight: _kWidgetMinHeight),
      decoration: _widgetSurface(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Active goals', style: CueTypeV3.widgetTitle()),
          const SizedBox(height: 10),
          if (goals.isEmpty)
            Text('No active goals.', style: CueTypeV3.widgetLabel())
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < goals.length; i++) ...[
                  _goalRow(goals[i]),
                  if (i < goals.length - 1) const SizedBox(height: 8),
                ],
              ],
            ),
        ],
      ),
    );
  }

  Widget _goalRow(ActiveGoal g) {
    final progress = _formatProgress(g);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline:       TextBaseline.alphabetic,
      children: [
        Expanded(
          child: Text(
            g.clientName,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily:         'Inter',
              fontFamilyFallback: const ['system-ui', 'sans-serif'],
              fontSize:           12.5,
              fontWeight:         FontWeight.w500,
              letterSpacing:      -0.0625,
              color:              kCueInk,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(progress, style: CueTypeV3.dataMono(color: kCueOlive)),
      ],
    );
  }

  String _formatProgress(ActiveGoal g) {
    final cur = g.currentAccuracy;
    final tgt = g.targetAccuracy;
    if (cur == null && tgt == null) return '—';
    if (cur != null && tgt != null) {
      return '${cur.toStringAsFixed(0)}/$tgt%';
    }
    if (cur != null) return '${cur.toStringAsFixed(0)}%';
    return '$tgt%';
  }
}

// ── Tomorrow ─────────────────────────────────────────────────────────────────

class TomorrowWidget extends StatelessWidget {
  final TomorrowSummary tomorrow;

  const TomorrowWidget({super.key, required this.tomorrow});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding:   const EdgeInsets.fromLTRB(18, 16, 18, 16),
      constraints: const BoxConstraints(minHeight: _kWidgetMinHeight),
      decoration: _widgetSurface(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Tomorrow', style: CueTypeV3.widgetTitle()),
          const SizedBox(height: 10),
          // Iowan numeric in olive — calm forward-looking register.
          Text(
            '${tomorrow.sessionCount}',
            style: CueTypeV3.numericDisplay(size: 36, color: kCueOlive),
          ),
          const SizedBox(height: 4),
          Text(
            tomorrow.sessionCount == 1 ? 'Session' : 'Sessions',
            style: CueTypeV3.widgetLabel(),
          ),
          const Spacer(),
          if (tomorrow.firstClientName != null)
            _firstSessionPreview()
          else if (tomorrow.sessionCount == 0)
            Text('No sessions on the calendar.',
                style: CueTypeV3.widgetLabel(color: kCueInkTertiary)),
        ],
      ),
    );
  }

  Widget _firstSessionPreview() {
    final time = tomorrow.firstTimeLabel;
    final spans = <InlineSpan>[
      TextSpan(text: 'Starts ', style: CueTypeV3.widgetLabel()),
    ];
    if (time != null && time.isNotEmpty) {
      spans.add(TextSpan(
        text:  time,
        style: CueTypeV3.dataMono(color: kCueInkSecondary),
      ));
      spans.add(TextSpan(
        text:  ' — ${tomorrow.firstClientName}',
        style: CueTypeV3.widgetLabel(),
      ));
    } else {
      spans.add(TextSpan(
        text:  tomorrow.firstClientName,
        style: CueTypeV3.widgetLabel(),
      ));
    }
    return Text.rich(TextSpan(children: spans),
        maxLines: 2, overflow: TextOverflow.ellipsis);
  }
}
