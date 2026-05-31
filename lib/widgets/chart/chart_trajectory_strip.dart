import 'package:flutter/material.dart';

import '../../models/session.dart';
import '../../models/short_term_goal.dart';
import '../../theme/cue_color_scheme.dart';
import '../../theme/cue_text_styles.dart';
import 'chart_card.dart';
import 'chart_format.dart';

/// Trajectory card — a left summary panel (overall % + outcome pills +
/// descriptor) beside a viz of one track per active STG (session ticks colored
/// by outcome across an 8-week window, today's tick pulsing, empty tracks
/// hatched). Tapping a tick reveals its history row.
class ChartTrajectoryStrip extends StatelessWidget {
  final List<ShortTermGoal> activeStgs;
  final List<Session> sessions;
  final DateTime? earliestSessionDate;
  final Map<String, String> stgNumbers;
  final void Function(int sessionId)? onTickTap;
  final VoidCallback? onExport;

  const ChartTrajectoryStrip({
    super.key,
    required this.activeStgs,
    required this.sessions,
    required this.earliestSessionDate,
    this.stgNumbers = const {},
    this.onTickTap,
    this.onExport,
  });

  static const _windowDays = 56; // 8 weeks

  int get _progress => sessions
      .where((s) => s.outcome?.toDbValue() == 'progress')
      .length;
  int get _revised => sessions
      .where((s) => s.outcome?.toDbValue() == 'plan_revised')
      .length;
  int get _holding =>
      sessions.where((s) => s.outcome?.toDbValue() == 'holding').length;

  int get _weeksSpan {
    if (earliestSessionDate == null || sessions.isEmpty) return 1;
    var latest = earliestSessionDate!;
    for (final s in sessions) {
      final d = s.date ?? s.createdAt;
      if (d.isAfter(latest)) latest = d;
    }
    final w = (latest.difference(earliestSessionDate!).inDays / 7).round();
    return w < 1 ? 1 : w;
  }

  @override
  Widget build(BuildContext context) {
    final t = CueChartTokens.of(context);
    final ty = CueChartType.of(context);
    final total = sessions.length;
    final weeks = _weeksSpan;

    return CueChartCard(
      head: CueChartCardHead(
        label: 'Trajectory',
        count: '· $total ${total == 1 ? 'session' : 'sessions'} over '
            '$weeks ${weeks == 1 ? 'week' : 'weeks'}',
        actions: [
          CueChartButton(
            style: CueChartButtonStyle.ghost,
            small: true,
            label: 'Export',
            onTap: onExport,
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
      child: activeStgs.isEmpty
          ? Text(
              'Trajectory will appear once short-term goals are authored and '
              'sessions are documented.',
              style: ty.trajSummaryDesc.copyWith(color: t.textMuted),
            )
          : LayoutBuilder(
              builder: (context, c) {
                final stack = c.maxWidth < 540;
                final summary = _summary(t, ty, total);
                final viz = _viz(context, t, ty);
                if (stack) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [summary, const SizedBox(height: 20), viz],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(width: 220, child: summary),
                    const SizedBox(width: 28),
                    Expanded(child: viz),
                  ],
                );
              },
            ),
    );
  }

  // ── Summary panel ──────────────────────────────────────────────────────────
  Widget _summary(CueChartTokens t, CueChartType ty, int total) {
    final pct = total > 0 ? ((_progress / total) * 100).round() : 0;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: t.bgInset,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: t.borderInset),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'OVERALL · $total ${total == 1 ? 'SESSION' : 'SESSIONS'}',
            style: ty.trajSummaryLabel,
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text('$pct%', style: ty.trajStatBig),
              const SizedBox(width: 8),
              Flexible(child: Text('progress sessions', style: ty.trajStatSmall)),
            ],
          ),
          const SizedBox(height: 10),
          _outcomePills(t, ty),
          Container(
            margin: const EdgeInsets.only(top: 10),
            padding: const EdgeInsets.only(top: 10),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: t.borderInset)),
            ),
            child: Text(_descriptor(), style: ty.trajSummaryDesc),
          ),
        ],
      ),
    );
  }

  Widget _outcomePills(CueChartTokens t, CueChartType ty) {
    final pills = <Widget>[];
    void add(String db, int count, String label) {
      if (count <= 0) return;
      pills.add(Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: t.outcomeBg(db),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: t.outcomeMark(db),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 6),
            Text('$count $label', style: ty.outcomePill(t.outcomeText(db))),
          ],
        ),
      ));
    }

    add('progress', _progress, 'progress');
    add('plan_revised', _revised, 'revised');
    add('holding', _holding, 'holding');
    return Wrap(spacing: 8, runSpacing: 8, children: pills);
  }

  // Factual, §language-discipline-safe one-liner derived from the distribution
  // + most-recent session. No projection.
  String _descriptor() {
    final total = sessions.length;
    if (total == 0) return 'No sessions on record yet.';
    final latest = sessions.first; // newest-first
    final label = switch (latest.outcome?.toDbValue()) {
      'progress' => 'progress',
      'plan_revised' => 'plan revised',
      'holding' => 'holding',
      _ => 'logged',
    };
    final when = monthDay(latest.date ?? latest.createdAt);
    return '$_progress of $total ${total == 1 ? 'session' : 'sessions'} '
        'logged progress. Most recent: $label ($when).';
  }

  // ── Viz ──────────────────────────────────────────────────────────────────
  Widget _viz(BuildContext context, CueChartTokens t, CueChartType ty) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final stg in activeStgs)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SizedBox(width: 80, child: _rowLabel(t, ty, stg)),
                const SizedBox(width: 16),
                Expanded(child: _track(t, stg)),
              ],
            ),
          ),
        const SizedBox(height: 4),
        Row(
          children: [
            const SizedBox(width: 80),
            const SizedBox(width: 16),
            Expanded(child: _weeksAxis(ty)),
          ],
        ),
      ],
    );
  }

  Widget _rowLabel(CueChartTokens t, CueChartType ty, ShortTermGoal stg) {
    final num = stgNumbers[stg.id] ?? 'STG ${stg.sequenceNum ?? '—'}';
    // Falls back to the raw DB string when the enum is `unknown` so even an
    // unrecognised domain token surfaces under the STG label.
    final domain = stg.domainDisplay;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          num.startsWith('STG') ? num : 'STG $num',
          style: ty.trajStgLabel,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        if (domain != null && domain.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(
            domain,
            style: ty.trajStgSub,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ],
    );
  }

  Widget _track(CueChartTokens t, ShortTermGoal stg) {
    final ticks = <_TickSpec>[];
    final start = earliestSessionDate;
    for (final s in sessions) {
      if (s.shortTermGoalId != stg.id) continue;
      final date = s.date ?? s.createdAt;
      double pct = 0;
      if (start != null) {
        pct = (date.difference(start).inDays / _windowDays).clamp(0.0, 1.0);
      }
      ticks.add(_TickSpec(
        sessionId: s.id,
        pct: pct,
        db: s.outcome?.toDbValue(),
        hollow: s.outcome == null,
        isToday: isToday(s.date),
      ));
    }
    return _Track(
      ticks: ticks,
      tokens: t,
      onTickTap: onTickTap,
    );
  }

  Widget _weeksAxis(CueChartType ty) {
    return Row(
      children: [
        for (var i = 1; i <= 8; i++)
          Expanded(
            child: Text(
              'Week $i',
              style: ty.trajWeek,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
    );
  }
}

class _TickSpec {
  final int sessionId;
  final double pct;
  final String? db;
  final bool hollow;
  final bool isToday;
  const _TickSpec({
    required this.sessionId,
    required this.pct,
    required this.db,
    required this.hollow,
    required this.isToday,
  });
}

class _Track extends StatefulWidget {
  final List<_TickSpec> ticks;
  final CueChartTokens tokens;
  final void Function(int sessionId)? onTickTap;
  const _Track({required this.ticks, required this.tokens, this.onTickTap});

  @override
  State<_Track> createState() => _TrackState();
}

class _TrackState extends State<_Track> with TickerProviderStateMixin {
  static const _h = 36.0;
  static const _tickW = 14.0;

  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    // Eager init (not a lazy `late` initializer): a today-tick may never read
    // `_pulse`, and a lazy init firing inside dispose() would do an illegal
    // inherited-widget (TickerMode) lookup on a deactivated element. Only spin
    // the pulse when there is actually a today-tick to animate.
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    );
    if (widget.ticks.any((t) => t.isToday)) {
      _pulse.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.tokens;
    final empty = widget.ticks.isEmpty;

    return SizedBox(
      height: _h,
      child: empty
          ? CustomPaint(
              painter: _HatchPainter(from: t.hatchFrom, to: t.hatchTo),
              child: _trackBorder(t),
            )
          : DecoratedBox(
              decoration: BoxDecoration(
                color: t.bgInset,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: t.borderInset),
              ),
              child: LayoutBuilder(
                builder: (context, c) {
                  final w = c.maxWidth;
                  return Stack(
                    clipBehavior: Clip.none,
                    children: [
                      // gridlines at week boundaries (1/8 .. 7/8)
                      for (var k = 1; k < 8; k++)
                        Positioned(
                          left: (k / 8) * w,
                          top: 0,
                          bottom: 0,
                          child: Container(width: 1, color: t.borderInset),
                        ),
                      for (final spec in widget.ticks)
                        _positioned(spec, w, t),
                    ],
                  );
                },
              ),
            ),
    );
  }

  Widget _trackBorder(CueChartTokens t) => DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: t.borderInset),
        ),
      );

  Widget _positioned(_TickSpec spec, double w, CueChartTokens t) {
    final left = (spec.pct * (w - _tickW)).clamp(0.0, w - _tickW);
    return Positioned(
      left: left,
      top: 6,
      child: _Tick(
        // State-encoded key for widget-test assertions (NULL→hollow, today).
        key: ValueKey(
          'traj-tick-${spec.sessionId}-${spec.hollow ? 'hollow' : 'solid'}'
          '-${spec.isToday ? 'today' : 'past'}',
        ),
        spec: spec,
        tokens: t,
        pulse: spec.isToday ? _pulse : null,
        onTap: widget.onTickTap == null
            ? null
            : () => widget.onTickTap!(spec.sessionId),
      ),
    );
  }
}

class _Tick extends StatefulWidget {
  final _TickSpec spec;
  final CueChartTokens tokens;
  final Animation<double>? pulse;
  final VoidCallback? onTap;
  const _Tick({
    super.key,
    required this.spec,
    required this.tokens,
    required this.pulse,
    this.onTap,
  });

  @override
  State<_Tick> createState() => _TickState();
}

class _TickState extends State<_Tick> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final t = widget.tokens;
    final spec = widget.spec;
    final mark = t.outcomeMark(spec.db);

    Widget tick = Container(
      width: 14,
      height: 24,
      decoration: BoxDecoration(
        color: spec.hollow ? Colors.transparent : mark,
        borderRadius: BorderRadius.circular(3),
        border: spec.hollow ? Border.all(color: mark, width: 2) : null,
        boxShadow: spec.hollow
            ? null
            : const [
                BoxShadow(color: Color(0x33000000), offset: Offset(0, 1), blurRadius: 2),
              ],
      ),
    );

    if (widget.pulse != null) {
      tick = AnimatedBuilder(
        animation: widget.pulse!,
        builder: (context, child) {
          final v = widget.pulse!.value; // 0..1
          return Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(3),
              boxShadow: [
                BoxShadow(
                  color: t.accentPulse,
                  spreadRadius: 3 + 3 * v,
                ),
              ],
            ),
            child: child,
          );
        },
        child: tick,
      );
    }

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _hover ? 1.1 : 1.0,
          duration: const Duration(milliseconds: 150),
          child: tick,
        ),
      ),
    );
  }
}

class _HatchPainter extends CustomPainter {
  final Color from;
  final Color to;
  _HatchPainter({required this.from, required this.to});

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(4),
    );
    canvas.save();
    canvas.clipRRect(rrect);
    canvas.drawRect(Offset.zero & size, Paint()..color = from);
    final stripe = Paint()
      ..color = to
      ..strokeWidth = 6;
    // 45° diagonal stripes, 12px period (6px on / 6px off).
    for (double x = -size.height; x < size.width + size.height; x += 12) {
      canvas.drawLine(
        Offset(x, 0),
        Offset(x + size.height, size.height),
        stripe,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_HatchPainter old) => old.from != from || old.to != to;
}
