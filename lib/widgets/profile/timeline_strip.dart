// lib/widgets/profile/timeline_strip.dart
//
// Phase 5.3 B.3 — compressed timeline pattern surface for the client
// profile. Replaces the vertical SliverList of event cards (~3000px for
// 21 sessions) with a ~240px chip-card showing:
//   • header row (purple icon + "Timeline" label + "last 30 days" pill +
//     "See all N events →" amber link)
//   • horizontal session strip (28px height, max 14 dots distributed
//     across the time axis, semantic dot colors per type + attestation)
//   • 5 evenly-spaced date labels (JBM mono uppercase tracked)
//   • "Last 3 events" compact list (3 rows: date column + type pill +
//     body text; SOAP S quoted excerpts render in Iowan italic)
//
// The full vertical timeline lives behind the "See all N →" link, in
// timeline_route.dart. TimelineStrip is pure display — no archive popup,
// no per-row navigation, no state mutation. Read-only pattern surface.
//
// TimelineEvent / TimelineEventType are defined inline here (not in
// lib/models/) because they're TimelineStrip-internal: the brief
// simplifies entry types from session/goalSet/goalAchieved/etc. down to
// session/parent/goal at the strip's dot-level grain. Profile maps
// TimelineEntry → TimelineEvent at the mount call site. Phase 5.4 may
// promote TimelineEvent into models/ when parent comms surface lands.
//
// Dashed row separators ("border-bottom 0.5 dashed cue.borderMuted" in
// the spec): Flutter's BorderSide doesn't support BorderStyle.dashed
// natively. Shipped solid 0.5; CustomPainter dashed banked for Phase 5.4
// (same discipline as Fix 3's LinkedEvidence dotted underline).
//
// Strip dot distribution branches on N: small-N (<8) packs the dots
// left with explicit 24px gaps so 2 sessions reads as "chart is early,
// here are the events so far" rather than two dots at strip extremes
// with a huge empty middle. Large-N (≥8) uses spaceBetween across the
// full strip width. The date labels below always spread across the
// actual time range — time axis ≠ dot layout, by design.

import 'package:flutter/material.dart';

import '../../theme/cue_color_scheme.dart';
import '../../theme/cue_tokens.dart';

enum TimelineEventType { session, parent, goal }

class TimelineEvent {
  final DateTime date;
  final TimelineEventType type;
  /// Display text for the "Last 3 events" body. SOAP S quoted excerpts
  /// (`.startsWith('"') && .endsWith('"')`) render in Iowan italic 13.
  final String content;
  /// Session attested → filled olive dot. Pending → hollow olive ring.
  /// Only meaningful for session-typed events.
  final bool isAttested;
  /// Today's event with an unread signal → wrap dot with amber ring.
  final bool hasUnread;
  /// Optional pointer to source row (session id, comm id, goal id).
  /// Phase 5.4 wires onTap navigation; B.3 leaves null.
  final String? sourceId;

  const TimelineEvent({
    required this.date,
    required this.type,
    required this.content,
    this.isAttested = false,
    this.hasUnread  = false,
    this.sourceId,
  });
}

class TimelineStrip extends StatelessWidget {
  /// Ordered newest-first (matching TimelineEntry convention).
  final List<TimelineEvent> events;
  /// Total event count across the chart (drives "See all N events →").
  /// May exceed events.length when caller pre-truncates.
  final int totalEventCount;
  /// "See all N events →" link tap. Profile wires Navigator.push to
  /// TimelineRoute.
  final VoidCallback? onSeeAll;

  const TimelineStrip({
    super.key,
    required this.events,
    required this.totalEventCount,
    this.onSeeAll,
  });

  @override
  Widget build(BuildContext context) {
    final cue    = CueColorsResolved.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color:        cue.bgCard,
        border:       Border.all(color: cue.border, width: CueSize.hairline),
        borderRadius: BorderRadius.circular(10), // no CueRadius.s10 token
      ),
      padding: const EdgeInsets.fromLTRB(
          CueGap.s18, CueGap.s14, CueGap.s18, CueGap.s16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(cue, isDark),
          if (events.isNotEmpty) ...[
            const SizedBox(height: CueGap.s14),
            Container(height: CueSize.hairline, color: cue.border),
            const SizedBox(height: CueGap.s8),
            _buildStrip(cue),
            const SizedBox(height: CueGap.s4),
            _buildDateLabels(cue),
            // Only show "Last 3 events" section if at least one event has
            // content. _buildLastThreeEvents returns SizedBox.shrink when
            // the filtered list is empty, but the CueGap.s14 spacing must
            // also collapse to avoid orphan whitespace below date labels.
            if (events.any((e) => e.content.isNotEmpty)) ...[
              const SizedBox(height: CueGap.s14),
              _buildLastThreeEvents(cue),
            ],
          ] else ...[
            const SizedBox(height: CueGap.s14),
            Container(height: CueSize.hairline, color: cue.border),
            const SizedBox(height: CueGap.s14),
            Text(
              'No events yet.',
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize:   12,
                fontStyle:  FontStyle.italic,
                color:      cue.textMuted,
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── Header ────────────────────────────────────────────────────────────────

  Widget _buildHeader(CueColorsResolved cue, bool isDark) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Purple icon container — 22x22, br 5, ~15% purple ground.
        Container(
          width:  22, // local chrome size; not a CueGap (gap-token)
          height: 22,
          decoration: BoxDecoration(
            color:        const Color(0x267F77DD), // ~15% alpha purple
            borderRadius: BorderRadius.circular(5), // no CueRadius.s5 token
          ),
          child: Icon(
            Icons.history,
            size:  12,
            color: isDark
                ? const Color(0xFFAFA9EC)
                : const Color(0xFF5C56C7),
          ),
        ),
        const SizedBox(width: CueGap.s10),
        Text(
          'Timeline',
          style: TextStyle(
            fontFamily: 'Inter',
            fontSize:   12.5, // no token; spec value
            fontWeight: FontWeight.w400,
            color:      cue.textSecondary,
          ),
        ),
        const Spacer(),
        // "last 30 days" pill
        Container(
          padding: const EdgeInsets.symmetric(
              horizontal: CueGap.s7, vertical: CueGap.s2),
          decoration: BoxDecoration(
            color:        cue.bgMuted,
            borderRadius: BorderRadius.circular(CueRadius.s3),
          ),
          child: Text(
            'last 30 days',
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize:   11,
              fontWeight: FontWeight.w400,
              color:      cue.textMuted,
            ),
          ),
        ),
        const SizedBox(width: CueGap.s10),
        // "See all N events →" amber link.
        GestureDetector(
          onTap: onSeeAll,
          child: Text(
            'See all $totalEventCount events →',
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize:   11,
              fontWeight: FontWeight.w500,
              color:      cue.amber,
            ),
          ),
        ),
      ],
    );
  }

  // ── Horizontal session strip ──────────────────────────────────────────────

  Widget _buildStrip(CueColorsResolved cue) {
    // Take most-recent 14, then reverse so strip reads oldest → newest L→R.
    final visible    = events.length <= 14 ? events : events.sublist(0, 14);
    final stripOrder = visible.reversed.toList();

    // Distribution branch: small-N (<8) packs dots left with explicit
    // 24px gaps; large-N (≥8) uses spaceBetween across full strip width.
    // See header doc for rationale.
    final useSpaceBetween = stripOrder.length >= 8;

    return SizedBox(
      height: 28, // strip height; not a CueGap (visual chrome, not spacing)
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Continuous horizontal line through the dot midpoints.
          Positioned.fill(
            child: Center(
              child: Container(height: 1, color: cue.border),
            ),
          ),
          // Dots — distribution depends on N (see useSpaceBetween above).
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: CueGap.s4),
            child: useSpaceBetween
                ? Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children:
                        stripOrder.map((e) => _buildDot(cue, e)).toList(),
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.start,
                    children: [
                      for (int i = 0; i < stripOrder.length; i++) ...[
                        if (i > 0) const SizedBox(width: 24),
                        _buildDot(cue, stripOrder[i]),
                      ],
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildDot(CueColorsResolved cue, TimelineEvent e) {
    Color fill;
    Color stroke;
    switch (e.type) {
      case TimelineEventType.session:
        fill   = e.isAttested ? cue.olive : cue.bgCanvas;
        stroke = cue.olive;
        break;
      case TimelineEventType.parent:
        fill   = cue.bgCanvas;
        stroke = cue.amber;
        break;
      case TimelineEventType.goal:
        fill   = cue.bgCanvas;
        stroke = cue.purple;
        break;
    }

    final dot = Container(
      width:  9,
      height: 9,
      decoration: BoxDecoration(
        shape:  BoxShape.circle,
        color:  fill,
        border: Border.all(color: stroke, width: 1.5),
      ),
    );

    // Today's-with-unread → wrap with 2px amber ring.
    if (e.hasUnread) {
      return Container(
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          shape:  BoxShape.circle,
          border: Border.all(color: cue.amber, width: 2),
        ),
        child: dot,
      );
    }
    return dot;
  }

  // ── Date labels ───────────────────────────────────────────────────────────

  Widget _buildDateLabels(CueColorsResolved cue) {
    final visible    = events.length <= 14 ? events : events.sublist(0, 14);
    final stripOrder = visible.reversed.toList();
    final oldest     = stripOrder.first.date;
    final newest     = stripOrder.last.date;
    final spanMs     = newest.difference(oldest).inMilliseconds;

    // 5 labels at 0%, 25%, 50%, 75%, 100% across the visible time range.
    // Degenerate case (1 event or all events same day): all 5 labels show
    // the same date. Cosmetic edge case banked for Phase 5.4 polish.
    final labels = List.generate(5, (i) {
      final fraction = i / 4.0;
      final ms = oldest.millisecondsSinceEpoch +
                 (spanMs * fraction).round();
      return _fmtMonthDayUpper(DateTime.fromMillisecondsSinceEpoch(ms));
    });

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: labels.map((s) => Text(
        s,
        style: TextStyle(
          fontFamily:    'JetBrains Mono',
          fontSize:      8.5,
          fontWeight:    FontWeight.w600,
          letterSpacing: 0.06,
          color:         cue.textMuted,
        ),
      )).toList(),
    );
  }

  // ── Last 3 events ─────────────────────────────────────────────────────────

  Widget _buildLastThreeEvents(CueColorsResolved cue) {
    // Filter empty content (empty-SOAP sessions emit content: '' from
    // Profile's _entryToEvent so they appear as hollow dots on the strip
    // but don't burn "Last 3 events" list real estate with redundant
    // dates). Take first 3 from the filtered list — may surface older
    // events when recent activity is documentation gaps; that's correct
    // behavior (two signals serving two needs).
    final lastThree = events
        .where((e) => e.content.isNotEmpty)
        .take(3)
        .toList();
    final now = DateTime.now();

    if (lastThree.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Last 3 events',
          style: TextStyle(
            fontFamily: 'Inter',
            fontSize:   11,
            fontWeight: FontWeight.w400,
            color:      cue.textMuted,
          ),
        ),
        const SizedBox(height: CueGap.s8),
        for (int i = 0; i < lastThree.length; i++)
          _buildEventRow(
            cue,
            lastThree[i],
            now,
            isLast: i == lastThree.length - 1,
          ),
      ],
    );
  }

  Widget _buildEventRow(
    CueColorsResolved cue,
    TimelineEvent e,
    DateTime now, {
    required bool isLast,
  }) {
    final isQuoted = e.content.startsWith('"') && e.content.endsWith('"');

    return Container(
      padding: const EdgeInsets.symmetric(vertical: CueGap.s7),
      decoration: isLast
          ? null
          : BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: cue.borderMuted,
                  width: CueSize.hairline,
                  style: BorderStyle.solid, // Phase 5.4 CustomPainter dashed
                ),
              ),
            ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Date column — fixed 52px, relative-time string.
          SizedBox(
            width: 52, // local layout value; no CueSize token
            child: Text(
              _relativeDate(e.date, now),
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize:   11,
                fontWeight: FontWeight.w400,
                color:      cue.textMuted,
              ),
            ),
          ),
          const SizedBox(width: CueGap.s12),
          _buildTypePill(cue, e.type),
          const SizedBox(width: CueGap.s12),
          Expanded(
            child: isQuoted
                ? Text(
                    e.content,
                    style: TextStyle(
                      fontFamily:         'Iowan Old Style',
                      fontFamilyFallback: const ['Georgia', 'Charter', 'serif'],
                      fontSize:           13,
                      fontStyle:          FontStyle.italic,
                      color:              cue.textPrimary,
                      height:             1.4,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  )
                : Text(
                    e.content,
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize:   12,
                      fontWeight: FontWeight.w400,
                      color:      cue.textBody,
                      height:     1.4,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildTypePill(CueColorsResolved cue, TimelineEventType type) {
    // Pill colors are mode-aware via CueColorsResolved accessors so the
    // text/bg shifts correctly between dark bgCard (#111112) and light
    // warm-paper bgCard. Mode-uniform pills would fail the same contrast
    // test that drove Fix 3's LinkedEvidence light-vs-dark olive split.
    // Alpha values (12% / 15% / 15%) are spec; hue-mass calibration
    // discipline across types banked for Phase 5.4.
    String label;
    Color  textColor;
    Color  bgColor;
    switch (type) {
      case TimelineEventType.session:
        label     = 'SESSION';
        textColor = cue.olive;
        bgColor   = cue.olive.withValues(alpha: 0.12);
        break;
      case TimelineEventType.parent:
        label     = 'PARENT';
        textColor = cue.amber;
        bgColor   = cue.amber.withValues(alpha: 0.15);
        break;
      case TimelineEventType.goal:
        label     = 'GOAL';
        textColor = cue.purple;
        bgColor   = cue.purple.withValues(alpha: 0.15);
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: CueGap.s6, vertical: CueGap.s2),
      decoration: BoxDecoration(
        color:        bgColor,
        borderRadius: BorderRadius.circular(CueRadius.s3),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontFamily:    'JetBrains Mono',
          fontSize:      8.5,
          fontWeight:    FontWeight.w600,
          letterSpacing: 0.06,
          color:         textColor,
        ),
      ),
    );
  }

  // ── Date helpers ──────────────────────────────────────────────────────────

  static String _fmtMonthDayUpper(DateTime d) {
    const months = [
      'JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN',
      'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC',
    ];
    return '${months[d.month - 1]} ${d.day.toString().padLeft(2, '0')}';
  }

  static String _fmtMonthDayTitle(DateTime d) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[d.month - 1]} ${d.day.toString().padLeft(2, '0')}';
  }

  static String _relativeDate(DateTime eventDate, DateTime now) {
    final eventDay = DateTime(eventDate.year, eventDate.month, eventDate.day);
    final today    = DateTime(now.year, now.month, now.day);
    final daysAgo  = today.difference(eventDay).inDays;

    if (daysAgo == 0) return 'Today';
    if (daysAgo == 1) return 'Yesterday';
    if (daysAgo < 7)  return '$daysAgo days';
    if (daysAgo == 7) return '1 week';
    if (daysAgo < 14) {
      const dayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      return dayNames[eventDate.weekday - 1];
    }
    if (daysAgo < 21) return '2 weeks';
    if (daysAgo < 28) return '3 weeks';
    if (daysAgo < 60) return '1 month';
    return _fmtMonthDayTitle(eventDate);
  }
}
