import 'package:flutter/material.dart';

import '../../models/session.dart';
import '../../theme/cue_color_scheme.dart';
import '../../theme/cue_text_styles.dart';
import 'chart_card.dart';
import 'chart_format.dart';

const _weekdays = [
  'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday',
];
String _weekday(DateTime d) => _weekdays[(d.weekday - 1) % 7];

/// Session-history card — card-head ("Session history · N" + "Open all
/// sessions →") over rows. Each row: date block (day + "Weekday · NN min", both
/// Inter sans), AI/fallback headline, outcome tag, chevron. Tapping a row
/// expands it inline. [revealSession] expands + scrolls a row (tick-tap entry).
class ChartSessionHistory extends StatefulWidget {
  final List<Session> sessions; // most-recent first
  final String clientName;
  final VoidCallback? onShowAll;
  final Map<int, String> headlineOverrides;

  const ChartSessionHistory({
    super.key,
    required this.sessions,
    required this.clientName,
    this.onShowAll,
    this.headlineOverrides = const {},
  });

  @override
  ChartSessionHistoryState createState() => ChartSessionHistoryState();
}

class ChartSessionHistoryState extends State<ChartSessionHistory> {
  final Map<int, bool> _expanded = {};
  final Map<int, GlobalKey> _rowKeys = {};

  @override
  void initState() {
    super.initState();
    if (widget.sessions.isNotEmpty) {
      final today = widget.sessions.where((s) => isToday(s.date));
      final open = today.isNotEmpty ? today.first : widget.sessions.first;
      _expanded[open.id] = true;
    }
  }

  GlobalKey _keyFor(int id) => _rowKeys.putIfAbsent(id, () => GlobalKey());

  /// Expand session [id] and scroll it into view (from a trajectory tick tap).
  void revealSession(int id) {
    setState(() => _expanded[id] = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _keyFor(id).currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(ctx,
            duration: const Duration(milliseconds: 300), alignment: 0.1);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final n = widget.sessions.length;
    return CueChartCard(
      padding: EdgeInsets.zero,
      head: CueChartCardHead(
        label: 'Session history',
        count: '· $n',
        actions: [
          if (widget.sessions.isNotEmpty)
            CueChartButton(
              small: true,
              label: 'Open all sessions →',
              onTap: widget.onShowAll,
            ),
        ],
      ),
      child: widget.sessions.isEmpty
          ? Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
              child: Text(
                'No sessions on record yet.',
                style: CueChartType.of(context)
                    .sessionHeadline
                    .copyWith(color: CueChartTokens.of(context).textMuted),
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < widget.sessions.length; i++)
                  _HistoryRow(
                    key: _keyFor(widget.sessions[i].id),
                    session: widget.sessions[i],
                    headlineOverride:
                        widget.headlineOverrides[widget.sessions[i].id],
                    expanded: _expanded[widget.sessions[i].id] ?? false,
                    isLast: i == widget.sessions.length - 1,
                    onToggle: () => setState(() => _expanded[widget.sessions[i].id] =
                        !(_expanded[widget.sessions[i].id] ?? false)),
                  ),
              ],
            ),
    );
  }
}

class _HistoryRow extends StatefulWidget {
  final Session session;
  final String? headlineOverride;
  final bool expanded;
  final bool isLast;
  final VoidCallback onToggle;
  const _HistoryRow({
    super.key,
    required this.session,
    required this.headlineOverride,
    required this.expanded,
    required this.isLast,
    required this.onToggle,
  });

  @override
  State<_HistoryRow> createState() => _HistoryRowState();
}

class _HistoryRowState extends State<_HistoryRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final t = CueChartTokens.of(context);
    final ty = CueChartType.of(context);
    final s = widget.session;
    final date = s.date ?? s.createdAt;
    final db = s.outcome?.toDbValue();

    return DecoratedBox(
      decoration: BoxDecoration(
        border: widget.isLast
            ? null
            : Border(bottom: BorderSide(color: t.borderDivider)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          MouseRegion(
            cursor: SystemMouseCursors.click,
            onEnter: (_) => setState(() => _hover = true),
            onExit: (_) => setState(() => _hover = false),
            child: GestureDetector(
              onTap: widget.onToggle,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                color: _hover ? t.bgCardHead : Colors.transparent,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 96,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(monthDay(date), style: ty.sessionDay),
                          const SizedBox(height: 3),
                          Text(
                            '${_weekday(date)} · ${s.durationMinutes ?? '—'} min',
                            style: ty.sessionSub,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 20),
                    Expanded(
                      child: Text(
                        _headline(),
                        style: ty.sessionHeadline,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 16),
                    if (db != null)
                      Container(
                        padding:
                            const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: t.outcomeBg(db),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          t.outcomeLabel(db).toUpperCase(),
                          style: ty.outcomeTag(t.outcomeText(db)),
                        ),
                      ),
                    const SizedBox(width: 12),
                    Icon(
                      widget.expanded ? Icons.expand_more : Icons.chevron_right,
                      size: 18,
                      color: t.textMuted,
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (widget.expanded) _expandedBody(t, ty),
        ],
      ),
    );
  }

  Widget _expandedBody(CueChartTokens t, CueChartType ty) {
    return Container(
      margin: const EdgeInsets.fromLTRB(24, 0, 24, 16),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        color: t.bgInset,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: t.borderInset),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _block(t, ty, 'OBSERVATION', body: _observation()),
          const SizedBox(height: 14),
          _block(t, ty, 'CLINICAL READ',
              placeholder: 'Clinical read not yet captured.'),
          const SizedBox(height: 14),
          _nextSessionBlock(t, ty),
        ],
      ),
    );
  }

  Widget _block(CueChartTokens t, CueChartType ty, String label,
      {String? body, String? placeholder}) {
    final hasBody = body != null && body.trim().isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: ty.sparklineLabel),
        const SizedBox(height: 6),
        Text(
          hasBody ? body.trim() : (placeholder ?? 'Not captured.'),
          style: hasBody
              ? ty.evidenceFinding
              : ty.evidenceFinding.copyWith(color: t.textMuted),
        ),
      ],
    );
  }

  Widget _nextSessionBlock(CueChartTokens t, CueChartType ty) {
    final next = widget.session.nextSessionFocus?.trim();
    final has = next != null && next.isNotEmpty;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: t.accentSoftBg,
        border: Border(left: BorderSide(color: t.accent, width: 2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('NEXT SESSION', style: ty.sparklineLabel.copyWith(color: t.accent)),
          const SizedBox(height: 6),
          Text(
            has ? next : 'Next-session focus not yet captured.',
            style: has
                ? ty.evidenceFinding
                : ty.evidenceFinding.copyWith(color: t.textMuted),
          ),
        ],
      ),
    );
  }

  String _headline() {
    final ai = (widget.headlineOverride ?? widget.session.aiHeadline)?.trim();
    if (ai != null && ai.isNotEmpty) return _flatten(ai);
    final s = widget.session;
    final raw = (s.soapNote?.trim().isNotEmpty ?? false)
        ? s.soapNote!.trim()
        : (s.notes?.trim().isNotEmpty ?? false)
            ? s.notes!.trim()
            : (s.activityName?.trim().isNotEmpty ?? false)
                ? s.activityName!.trim()
                : 'Session on ${monthDay(s.date ?? s.createdAt)}';
    return _flatten(raw);
  }

  String _flatten(String s) {
    final flat = s.replaceAll(RegExp(r'\s+'), ' ');
    return flat.length > 120 ? '${flat.substring(0, 120)}…' : flat;
  }

  String _observation() {
    final s = widget.session;
    if (s.soapNote?.trim().isNotEmpty ?? false) return s.soapNote!.trim();
    if (s.notes?.trim().isNotEmpty ?? false) return s.notes!.trim();
    final parts = <String>[];
    void add(String? v) {
      if (v != null && v.trim().isNotEmpty) parts.add(v.trim());
    }

    add(s.targetBehaviour);
    add(s.activityName);
    add(s.clientAffect);
    return parts.join(' · ');
  }
}
