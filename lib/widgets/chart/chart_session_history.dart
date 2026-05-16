// lib/widgets/chart/chart_session_history.dart
//
// Phase 4.1.0 — session history section. Replaces the old "Last Session"
// hero pillar and the separate TimelineStrip.
//
// Layout:
//   • Header — "SESSION HISTORY · {count}" + legend (progress · revised)
//   • Timeline strip — horizontal row of colored bars (one per session),
//     date labels under each tick, tappable to highlight a row.
//   • Session rows — newest first, collapsible. Most recent expanded by
//     default; older rows collapsed. Persists per-row via ChartUiState.
//   • "Show all sessions →" link at the bottom routes to the full
//     history view.
//
// Schema notes:
//   • session.duration_minutes — used for tick height. Defaults to a
//     mid-range when missing.
//   • session.outcome_type — drives tick color (olive=progress,
//     amber=revised). When field is absent (Phase 4.1.0 schema reality)
//     all ticks render olive.

import 'dart:convert';
import 'package:flutter/material.dart';

import '../../theme/cue_color_scheme.dart';
import '../../theme/cue_text_styles.dart';
import '../../utils/chart_ui_state.dart';

class ChartSessionHistory extends StatefulWidget {
  final String clientId;
  final String clientName;
  final List<Map<String, dynamic>> sessions;
  final int initialVisibleRows;
  final VoidCallback? onShowAll;

  const ChartSessionHistory({
    super.key,
    required this.clientId,
    required this.clientName,
    required this.sessions,
    this.initialVisibleRows = 5,
    this.onShowAll,
  });

  @override
  State<ChartSessionHistory> createState() => _ChartSessionHistoryState();
}

class _ChartSessionHistoryState extends State<ChartSessionHistory> {
  final Map<String, bool> _expanded = <String, bool>{};
  int? _highlightedIdx;

  @override
  void initState() {
    super.initState();
    _loadState();
  }

  @override
  void didUpdateWidget(covariant ChartSessionHistory oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.clientId != widget.clientId ||
        oldWidget.sessions.length != widget.sessions.length) {
      _loadState();
    }
  }

  Future<void> _loadState() async {
    final visible = widget.sessions.take(widget.initialVisibleRows).toList();
    final futures = <Future<MapEntry<String, bool>>>[
      for (int i = 0; i < visible.length; i++)
        ChartUiState.isExpanded(
          scope: ChartUiScope.session,
          clientId: widget.clientId,
          rowId: visible[i]['id'].toString(),
          // Most recent expanded by default; older collapsed.
          defaultExpanded: i == 0,
        ).then((v) => MapEntry(visible[i]['id'].toString(), v)),
    ];
    final results = await Future.wait(futures);
    if (!mounted) return;
    setState(() {
      _expanded
        ..clear()
        ..addEntries(results);
    });
  }

  bool _isOpen(String id, int idx) =>
      _expanded[id] ?? (idx == 0);

  void _toggle(String id) {
    final next = !(_expanded[id] ?? false);
    setState(() => _expanded[id] = next);
    ChartUiState.setExpanded(
      scope: ChartUiScope.session,
      clientId: widget.clientId,
      rowId: id,
      expanded: next,
    );
  }

  void _onTickTap(int idx) {
    setState(() {
      _highlightedIdx = idx;
      final id = widget.sessions[idx]['id'].toString();
      _expanded[id] = true;
    });
    ChartUiState.setExpanded(
      scope: ChartUiScope.session,
      clientId: widget.clientId,
      rowId: widget.sessions[idx]['id'].toString(),
      expanded: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = CueChartTextStyles.of(context, isMobile: false);
    final p = CueChartPalette.of(context);

    if (widget.sessions.isEmpty) {
      return _emptyState(context);
    }

    final visible =
        widget.sessions.take(widget.initialVisibleRows).toList();
    final hasMore = widget.sessions.length > widget.initialVisibleRows;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _headerRow(t, p),
        const SizedBox(height: 18),
        _TimelineTickStrip(
          sessions: widget.sessions,
          onTickTap: _onTickTap,
          highlightedIdx: _highlightedIdx,
        ),
        const SizedBox(height: 18),
        for (int i = 0; i < visible.length; i++)
          _SessionRow(
            session: visible[i],
            expanded: _isOpen(visible[i]['id'].toString(), i),
            onToggle: () => _toggle(visible[i]['id'].toString()),
            highlighted: _highlightedIdx == i,
          ),
        if (hasMore && widget.onShowAll != null) ...[
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerLeft,
            child: InkWell(
              onTap: widget.onShowAll,
              borderRadius: BorderRadius.circular(4),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
                child: Text(
                  'Show all ${widget.sessions.length} sessions →',
                  style: const TextStyle(
                    fontFamily: 'DM Sans',
                    fontSize: 12,
                    fontWeight: FontWeight.w400,
                    color: Color(0xFFF5C778),
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _headerRow(CueChartTextStyles t, CueChartPalette p) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          'SESSION HISTORY · ${widget.sessions.length}',
          style: t.historyHeader,
        ),
        const Spacer(),
        _LegendItem(color: p.tickProgress, label: 'progress'),
        const SizedBox(width: 16),
        _LegendItem(color: p.tickRevised, label: 'plan revised'),
      ],
    );
  }

  Widget _emptyState(BuildContext context) {
    final t = CueChartTextStyles.of(context, isMobile: false);
    final p = CueChartPalette.of(context);
    return Container(
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: p.sectionDivider, width: 0.5),
          bottom: BorderSide(color: p.sectionDivider, width: 0.5),
        ),
      ),
      padding: const EdgeInsets.symmetric(vertical: 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('SESSION HISTORY · 0', style: t.historyHeader),
          const SizedBox(height: 14),
          Text(
            'No sessions yet. When you log your first session with '
            '${_firstName(widget.clientName)}, it appears here.',
            style: t.ladderBody.copyWith(
              color: CueColorsResolved.of(context).textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  static String _firstName(String full) {
    final parts = full.trim().split(RegExp(r'\s+'));
    return parts.isEmpty ? full : parts.first;
  }
}

class _LegendItem extends StatelessWidget {
  final Color color;
  final String label;
  const _LegendItem({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    final cue = CueColorsResolved.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 8, height: 8, color: color),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            fontFamily: 'DM Sans',
            fontSize: 10,
            fontWeight: FontWeight.w400,
            color: cue.textSecondary,
          ),
        ),
      ],
    );
  }
}

// ── Timeline tick strip ──────────────────────────────────────────────────────

class _TimelineTickStrip extends StatelessWidget {
  final List<Map<String, dynamic>> sessions;
  final ValueChanged<int>? onTickTap;
  final int? highlightedIdx;

  const _TimelineTickStrip({
    required this.sessions,
    this.onTickTap,
    this.highlightedIdx,
  });

  @override
  Widget build(BuildContext context) {
    final p = CueChartPalette.of(context);
    final t = CueChartTextStyles.of(context, isMobile: false);

    // Sessions arrive newest-first; render oldest-first so the timeline
    // reads left-to-right as time moves forward.
    final ordered = List<Map<String, dynamic>>.from(sessions).reversed.toList();

    return Container(
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: p.sectionDivider, width: 0.5),
          bottom: BorderSide(color: p.sectionDivider, width: 0.5),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(0, 16, 0, 20),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (int i = 0; i < ordered.length; i++) ...[
              if (i > 0) const SizedBox(width: 8),
              _Tick(
                session: ordered[i],
                isHighlighted: highlightedIdx == sessions.length - 1 - i,
                onTap: onTickTap == null
                    ? null
                    : () => onTickTap!(sessions.length - 1 - i),
                tickProgress: p.tickProgress,
                tickRevised: p.tickRevised,
                labelStyle: t.historyMeta,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Tick extends StatelessWidget {
  final Map<String, dynamic> session;
  final bool isHighlighted;
  final VoidCallback? onTap;
  final Color tickProgress;
  final Color tickRevised;
  final TextStyle labelStyle;

  const _Tick({
    required this.session,
    required this.isHighlighted,
    required this.onTap,
    required this.tickProgress,
    required this.tickRevised,
    required this.labelStyle,
  });

  @override
  Widget build(BuildContext context) {
    final dateStr = session['date'] as String?;
    final dt = dateStr == null ? null : DateTime.tryParse(dateStr);
    final dateLabel = _shortDate(dt);
    final duration = _durationMinutes(session);
    final height = _heightFor(duration);
    final outcome = (session['outcome_type'] as String?)?.toLowerCase();
    final color = outcome == 'revised' ? tickRevised : tickProgress;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 8,
              height: height,
              decoration: BoxDecoration(
                color: color,
                border: isHighlighted
                    ? Border.all(color: const Color(0xFFF5C778), width: 1)
                    : null,
              ),
            ),
            const SizedBox(height: 6),
            Text(dateLabel, style: labelStyle),
          ],
        ),
      ),
    );
  }

  static int? _durationMinutes(Map<String, dynamic> s) {
    final v = s['duration_minutes'];
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v);
    return null;
  }

  static double _heightFor(int? minutes) {
    if (minutes == null) return 18;
    // Map 15→12, 30→18, 45→24, 60→32
    final clamped = minutes.clamp(15, 90);
    return 12 + ((clamped - 15) / 75) * 20;
  }

  static String _shortDate(DateTime? dt) {
    if (dt == null) return '';
    const months = [
      '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[dt.month]} ${dt.day}';
  }
}

// ── Session row ──────────────────────────────────────────────────────────────

class _SessionRow extends StatelessWidget {
  final Map<String, dynamic> session;
  final bool expanded;
  final VoidCallback onToggle;
  final bool highlighted;

  const _SessionRow({
    required this.session,
    required this.expanded,
    required this.onToggle,
    required this.highlighted,
  });

  @override
  Widget build(BuildContext context) {
    final t = CueChartTextStyles.of(context, isMobile: false);
    final p = CueChartPalette.of(context);
    final cue = CueColorsResolved.of(context);

    final quote = _pullQuote(session);
    final dateStr = session['date'] as String?;
    final dt = dateStr == null ? null : DateTime.tryParse(dateStr);
    final dateLine = _dateLine(dt, _durationMinutes(session));
    final fullBody = _fullBody(session);

    return Container(
      decoration: BoxDecoration(
        color: highlighted
            ? cue.amber.withValues(alpha: 0.06)
            : null,
        border: Border(
          bottom: BorderSide(color: p.sectionDivider, width: 0.5),
        ),
      ),
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: onToggle,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Icon(
                    expanded
                        ? Icons.keyboard_arrow_down_rounded
                        : Icons.keyboard_arrow_right_rounded,
                    size: 18,
                    color:
                        expanded ? cue.amber : cue.textSecondary,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        quote,
                        style: t.historyQuote,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(dateLine, style: t.historyMeta),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (expanded && fullBody.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 46, top: 12, right: 8),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: Text(fullBody, style: t.historyBody),
              ),
            ),
        ],
      ),
    );
  }

  static String _pullQuote(Map<String, dynamic> s) {
    final body = _fullBody(s);
    if (body.isEmpty) return 'Documentation pending.';
    if (body.length <= 120) return body;
    return '${body.substring(0, 117)}…';
  }

  static String _fullBody(Map<String, dynamic> s) {
    final raw = s['soap_note'] as String?;
    if (raw != null && raw.isNotEmpty) {
      try {
        final map = jsonDecode(raw) as Map<String, dynamic>;
        final parts = <String>[];
        for (final key in const ['s', 'o', 'a', 'p', 'S', 'O', 'A', 'P']) {
          final v = (map[key] as String?)?.trim();
          if (v != null && v.isNotEmpty) parts.add(v);
        }
        if (parts.isNotEmpty) return parts.join(' · ');
      } catch (_) {/* fall through */}
    }
    return ((s['notes'] as String?) ?? (s['parent_update'] as String?) ?? '').trim();
  }

  static String _dateLine(DateTime? dt, int? minutes) {
    if (dt == null) {
      if (minutes == null) return '';
      return '$minutes min';
    }
    const months = [
      '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    const weekdays = ['', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final hour = dt.hour;
    final h12 = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);
    final ampm = hour < 12 ? 'am' : 'pm';
    final mm = dt.minute;
    final timePart = mm == 0
        ? '$h12$ampm'
        : '$h12:${mm.toString().padLeft(2, '0')}$ampm';
    final parts = <String>[
      '${months[dt.month]} ${dt.day}',
      weekdays[dt.weekday],
      timePart,
      if (minutes != null) '$minutes min',
    ];
    return parts.join(' · ');
  }

  static int? _durationMinutes(Map<String, dynamic> s) {
    final v = s['duration_minutes'];
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v);
    return null;
  }
}
