import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/citation.dart';
import '../../models/short_term_goal.dart';
import '../../models/stg_session_metric.dart';
import '../../theme/cue_color_scheme.dart';
import '../../theme/cue_text_styles.dart';
import '../../utils/sparkline_readout.dart';
import 'chart_card.dart';
import 'goal_lifecycle_menu.dart';

/// The in-focus STG — a nested white card on the STG section ground, with a
/// 4px accent rail, a mono number pill, week indicator, the goal body, an
/// inset sparkline box, and the evidence ladder.
class ChartStgFocus extends StatelessWidget {
  final ShortTermGoal stg;
  final String stgNumber; // "1.A" — from stg_numbering
  final List<StgSessionMetric> metrics; // oldest-first
  final List<Citation> citations; // by display_order
  final bool hasSessionToday;
  final bool isCompact;
  final VoidCallback? onAddEvidence;

  // Lifecycle controls (focus card is always an active STG). When any is
  // provided, an overflow menu appears in the header.
  final VoidCallback? onMarkAchieved;
  final VoidCallback? onMarkDiscontinued;
  final VoidCallback? onArchive;

  const ChartStgFocus({
    super.key,
    required this.stg,
    required this.stgNumber,
    required this.metrics,
    required this.citations,
    required this.hasSessionToday,
    required this.isCompact,
    this.onAddEvidence,
    this.onMarkAchieved,
    this.onMarkDiscontinued,
    this.onArchive,
  });

  @override
  Widget build(BuildContext context) {
    final t = CueChartTokens.of(context);
    final ty = CueChartType.of(context);
    final body = stg.specific.trim().isNotEmpty
        ? stg.specific.trim()
        : (stg.targetBehavior ?? stg.measurable);
    final criterionLine = stg.masteryCriterion?.displayLine;
    final radius = BorderRadius.circular(8);

    return Container(
      decoration: BoxDecoration(
        color: t.bgCard,
        borderRadius: radius,
        border: Border.all(color: t.borderCard),
        boxShadow: t.shadowFocus,
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _header(t, ty),
                  const SizedBox(height: 14),
                  Text(body, style: ty.stgBody),
                  if (criterionLine != null) ...[
                    const SizedBox(height: 14),
                    _CriterionLine(text: criterionLine),
                  ],
                  const SizedBox(height: 20),
                  _SparklineBox(
                    metrics: metrics,
                    hasSessionToday: hasSessionToday,
                  ),
                  const SizedBox(height: 16),
                  _EvidenceBlock(
                    citations: citations,
                    onAddEvidence: onAddEvidence,
                  ),
                ],
              ),
            ),
            // Inset accent rail (top/bottom inset 22, matching the padding).
            Positioned(
              left: 0,
              top: 22,
              bottom: 22,
              width: 4,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: t.accent,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header(CueChartTokens t, CueChartType ty) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: t.accentSoftBg,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(stgNumber, style: ty.stgNum),
        ),
        const SizedBox(width: 10),
        Text('IN FOCUS', style: ty.stgFocusBadge),
        const Spacer(),
        if (stg.timeBoundSessions != null)
          Text.rich(TextSpan(children: [
            TextSpan(text: 'Week ', style: ty.stgWeek),
            TextSpan(text: '${stg.totalSessionsWorked}', style: ty.stgWeekAccent),
            TextSpan(text: ' of ${stg.timeBoundSessions}', style: ty.stgWeek),
          ])),
        if (onMarkAchieved != null ||
            onMarkDiscontinued != null ||
            onArchive != null) ...[
          const SizedBox(width: 4),
          GoalLifecycleMenu(
            phase: GoalLifecyclePhase.active,
            goalKind: 'short-term goal',
            onMarkAchieved: onMarkAchieved,
            onMarkDiscontinued: onMarkDiscontinued,
            onArchive: onArchive,
          ),
        ],
      ],
    );
  }
}

// ── Mastery criterion line ──────────────────────────────────────────────────
//
// The mastery rule rendered as its own row beneath the STG body. Reuses the
// sparkline-eyebrow + evidence-body type registers so it sits inside the same
// "data tag + sentence" vocabulary already on the focus card. Resolved text
// (quantified for trial-based domains, free-text hint for qualitative ones)
// comes from MasteryCriterion.displayLine; this widget never composes it.

class _CriterionLine extends StatelessWidget {
  final String text;
  const _CriterionLine({required this.text});

  @override
  Widget build(BuildContext context) {
    final t = CueChartTokens.of(context);
    final ty = CueChartType.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 90,
          child: Text('CRITERION', style: ty.sparklineLabel),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Text(
            text,
            style: ty.evidenceFinding.copyWith(color: t.textSecondary),
          ),
        ),
      ],
    );
  }
}

// ── Sparkline box ────────────────────────────────────────────────────────────

class _SparklineBox extends StatelessWidget {
  final List<StgSessionMetric> metrics;
  final bool hasSessionToday;
  const _SparklineBox({required this.metrics, required this.hasSessionToday});

  @override
  Widget build(BuildContext context) {
    final t = CueChartTokens.of(context);
    final ty = CueChartType.of(context);
    final hasData = metrics.isNotEmpty;
    final label = hasData ? metrics.first.metricLabel.toUpperCase() : 'TREND';
    final readout =
        sparklineReadout(metrics, hasData ? metrics.first.metricLabel : '');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: t.bgInset,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: t.borderInset),
      ),
      child: Row(
        children: [
          SizedBox(width: 90, child: Text(label, style: ty.sparklineLabel)),
          const SizedBox(width: 16),
          Expanded(
            child: SizedBox(
              height: 36,
              child: hasData
                  ? CustomPaint(
                      painter: _SparklinePainter(
                        values: metrics.map((m) => m.metricValue).toList(),
                        color: t.accent,
                        hollowLast: hasSessionToday,
                        hollowFill: t.bgCard,
                      ),
                    )
                  : Center(
                      child: Container(
                        height: 1,
                        color: t.accent.withValues(alpha: 0.3),
                      ),
                    ),
            ),
          ),
          const SizedBox(width: 16),
          SizedBox(
            width: 160,
            child: Text(
              readout,
              style: ty.sparklineReadout,
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }
}

class _SparklinePainter extends CustomPainter {
  final List<double> values;
  final Color color;
  final bool hollowLast;
  final Color hollowFill;

  _SparklinePainter({
    required this.values,
    required this.color,
    required this.hollowLast,
    required this.hollowFill,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const r = 4.0;
    const pad = r + 1;
    final h = size.height;
    final w = size.width;
    var min = values.reduce((a, b) => a < b ? a : b);
    var max = values.reduce((a, b) => a > b ? a : b);
    if (max == min) {
      min -= 1;
      max += 1;
    }
    final n = values.length;
    Offset pointAt(int i) {
      final x = n == 1 ? w / 2 : (i / (n - 1)) * w;
      final norm = (values[i] - min) / (max - min);
      final y = (h - pad) - norm * (h - pad * 2);
      return Offset(x.clamp(pad, w - pad), y);
    }

    final line = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    if (n >= 2) {
      final path = Path()..moveTo(pointAt(0).dx, pointAt(0).dy);
      for (var i = 1; i < n; i++) {
        path.lineTo(pointAt(i).dx, pointAt(i).dy);
      }
      canvas.drawPath(path, line);
    }

    for (var i = 0; i < n; i++) {
      final p = pointAt(i);
      final isLast = i == n - 1;
      if (isLast && hollowLast) {
        canvas.drawCircle(p, r, Paint()..color = hollowFill);
        canvas.drawCircle(
          p,
          r,
          Paint()
            ..color = color
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2,
        );
      } else {
        canvas.drawCircle(p, r, Paint()..color = color);
      }
    }
  }

  @override
  bool shouldRepaint(_SparklinePainter old) =>
      old.values != values ||
      old.color != color ||
      old.hollowLast != hollowLast;
}

// ── Evidence ladder ──────────────────────────────────────────────────────────

class _EvidenceBlock extends StatelessWidget {
  final List<Citation> citations;
  final VoidCallback? onAddEvidence;
  const _EvidenceBlock({required this.citations, this.onAddEvidence});

  @override
  Widget build(BuildContext context) {
    final t = CueChartTokens.of(context);
    final ty = CueChartType.of(context);
    final n = citations.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'EVIDENCE BASE · $n ${n == 1 ? 'SOURCE' : 'SOURCES'}',
                style: ty.evidenceHeaderLabel,
              ),
            ),
            CueChartButton(
              style: CueChartButtonStyle.ghost,
              small: true,
              icon: Icons.add,
              label: 'Add evidence',
              onTap: onAddEvidence,
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (citations.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Text(
              'Evidence not yet attached — open substrate to find sources.',
              style: ty.evidenceFinding.copyWith(color: t.textMuted),
            ),
          )
        else
          for (var i = 0; i < citations.length; i++)
            _EvidenceRow(
              citation: citations[i],
              index: i,
              showTopBorder: i > 0,
            ),
      ],
    );
  }
}

class _EvidenceRow extends StatelessWidget {
  final Citation citation;
  final int index;
  final bool showTopBorder;
  const _EvidenceRow({
    required this.citation,
    required this.index,
    required this.showTopBorder,
  });

  @override
  Widget build(BuildContext context) {
    final t = CueChartTokens.of(context);
    final ty = CueChartType.of(context);
    final hasUrl = citation.sourceUrl?.trim().isNotEmpty ?? false;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: showTopBorder
          ? BoxDecoration(
              border: Border(top: BorderSide(color: t.borderDivider)),
            )
          : null,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 32,
            child: Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(_roman(index + 1), style: ty.roman),
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 90,
            child: Align(
              alignment: Alignment.topLeft,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: t.tierBg(citation.tier),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  citation.tier.displayLabel().toUpperCase(),
                  style: ty.tierChip(t.tierText(citation.tier)),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(citation.finding, style: ty.evidenceFinding),
                const SizedBox(height: 4),
                Text(citation.authorYear, style: ty.evidenceCite),
              ],
            ),
          ),
          const SizedBox(width: 12),
          CueChartButton(
            iconOnly: true,
            icon: Icons.north_east,
            enabled: hasUrl,
            tooltip: hasUrl ? 'Open source' : null,
            onTap: hasUrl
                ? () => _launchSource(context, citation.sourceUrl!.trim())
                : null,
          ),
        ],
      ),
    );
  }

  static String _roman(int n) {
    const numerals = [
      [10, 'x'],
      [9, 'ix'],
      [5, 'v'],
      [4, 'iv'],
      [1, 'i'],
    ];
    var v = n;
    final sb = StringBuffer();
    for (final pair in numerals) {
      final value = pair[0] as int;
      final sym = pair[1] as String;
      while (v >= value) {
        sb.write(sym);
        v -= value;
      }
    }
    return sb.toString();
  }
}

Future<void> _launchSource(BuildContext context, String url) async {
  final messenger = ScaffoldMessenger.of(context);
  final uri = Uri.tryParse(url);
  var ok = false;
  if (uri != null) {
    try {
      ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      ok = false;
    }
  }
  if (!ok) {
    messenger.showSnackBar(
      SnackBar(content: Text('Could not open source. URL: $url')),
    );
  }
}
