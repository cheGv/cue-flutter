// lib/widgets/chart/chart_masthead.dart
//
// Phase 4.1.0 — Chart screen masthead. Replaces the old AppLayout-topbar
// name + inline age/diagnosis split.
//
// Row 1: Identity line — Playfair Display name + DM Sans age + olive
//        diagnosis pill + edit pencil at the right edge.
// Row 2: Four meta cards in a responsive grid:
//        LAST SEEN · NEXT SESSION · CADENCE · CAREGIVER
//
// All structural — breathes to chart container width on desktop, 2×2 on
// tablet, single-column on mobile. Driven by LayoutBuilder (not
// MediaQuery, per CLAUDE.md invariant).

import 'package:flutter/material.dart';

import '../../theme/cue_color_scheme.dart';
import '../../theme/cue_text_styles.dart';

class ChartMasthead extends StatelessWidget {
  final Map<String, dynamic> client;
  final List<Map<String, dynamic>> sessions;
  final VoidCallback? onEditClient;
  final VoidCallback? onBuildWithCue;
  final VoidCallback? onAddCaregiverDetails;

  const ChartMasthead({
    super.key,
    required this.client,
    required this.sessions,
    this.onEditClient,
    this.onBuildWithCue,
    this.onAddCaregiverDetails,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile = constraints.maxWidth < 768;
        final isTablet =
            constraints.maxWidth >= 768 && constraints.maxWidth < 1024;
        final t = CueChartTextStyles.of(context, isMobile: isMobile);
        final p = CueChartPalette.of(context);
        final cue = CueColorsResolved.of(context);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _identityRow(t, p, cue, isMobile: isMobile),
            const SizedBox(height: 20),
            _metaGrid(constraints, isMobile: isMobile, isTablet: isTablet),
          ],
        );
      },
    );
  }

  // ── Row 1: name + age + diagnosis pill + edit pencil ─────────────────────

  Widget _identityRow(
    CueChartTextStyles t,
    CueChartPalette p,
    CueColorsResolved cue, {
    required bool isMobile,
  }) {
    final name = (client['name'] as String?)?.trim() ?? '';
    final age = client['age'];
    final diagnosis = (client['diagnosis'] as String?)?.trim();

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Flexible(
          child: Wrap(
            spacing: 16,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(name, style: t.chartName),
              if (age != null)
                Padding(
                  padding: EdgeInsets.only(top: isMobile ? 0 : 8),
                  child: Text('$age years', style: t.chartAge),
                ),
              if (diagnosis != null && diagnosis.isNotEmpty)
                Padding(
                  padding: EdgeInsets.only(top: isMobile ? 0 : 10),
                  child: _diagnosisPill(diagnosis, t, p),
                ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        InkWell(
          onTap: onEditClient,
          borderRadius: BorderRadius.circular(6),
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: Icon(
              Icons.edit_outlined,
              size: 14,
              color: cue.textSecondary,
            ),
          ),
        ),
      ],
    );
  }

  Widget _diagnosisPill(
    String diagnosis,
    CueChartTextStyles t,
    CueChartPalette p,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: p.diagnosisPillBg,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: p.diagnosisPillBorder, width: 0.5),
      ),
      child: Text(
        diagnosis.toUpperCase(),
        style: t.diagnosisPill,
      ),
    );
  }

  // ── Row 2: four meta cards in responsive grid ────────────────────────────

  Widget _metaGrid(
    BoxConstraints constraints, {
    required bool isMobile,
    required bool isTablet,
  }) {
    final cards = <Widget>[
      _LastSeenCard(sessions: sessions, client: client),
      _NextSessionCard(
        sessions: sessions,
        onBuildWithCue: onBuildWithCue,
      ),
      _CadenceCard(sessions: sessions),
      _CaregiverCard(
        client: client,
        onAddCaregiverDetails: onAddCaregiverDetails,
      ),
    ];

    if (isMobile) {
      return Column(
        children: [
          for (int i = 0; i < cards.length; i++) ...[
            if (i > 0) const SizedBox(height: 14),
            cards[i],
          ],
        ],
      );
    }

    if (isTablet) {
      // 2×2 grid
      return Column(
        children: [
          Row(
            children: [
              Expanded(child: cards[0]),
              const SizedBox(width: 14),
              Expanded(child: cards[1]),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(child: cards[2]),
              const SizedBox(width: 14),
              Expanded(child: cards[3]),
            ],
          ),
        ],
      );
    }

    // Desktop — single row of four equal columns
    return Row(
      children: [
        Expanded(child: cards[0]),
        const SizedBox(width: 14),
        Expanded(child: cards[1]),
        const SizedBox(width: 14),
        Expanded(child: cards[2]),
        const SizedBox(width: 14),
        Expanded(child: cards[3]),
      ],
    );
  }
}

// ── Meta card frame ──────────────────────────────────────────────────────────

class _MetaCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final String primaryValue;
  final Widget meta;

  const _MetaCard({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.primaryValue,
    required this.meta,
  });

  @override
  Widget build(BuildContext context) {
    final t = CueChartTextStyles.of(context, isMobile: false);
    final p = CueChartPalette.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      decoration: BoxDecoration(
        color: p.metaCardSurface,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: p.metaCardBorder, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(icon, size: 11, color: iconColor),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label.toUpperCase(),
                  style: t.metaLabel,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            primaryValue,
            style: t.metaValue,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          meta,
        ],
      ),
    );
  }
}

// ── Card 1: LAST SEEN ────────────────────────────────────────────────────────

class _LastSeenCard extends StatelessWidget {
  final List<Map<String, dynamic>> sessions;
  final Map<String, dynamic> client;

  const _LastSeenCard({required this.sessions, required this.client});

  @override
  Widget build(BuildContext context) {
    final t = CueChartTextStyles.of(context, isMobile: false);

    if (sessions.isEmpty) {
      // Empty — show intake date if available, else just "Not seen yet"
      final createdAt = client['created_at'] as String?;
      final intakeDays = _daysAgo(createdAt);
      final metaText = intakeDays == null
          ? ''
          : intakeDays == 0
              ? 'Intake captured today'
              : intakeDays == 1
                  ? 'Intake captured yesterday'
                  : 'Intake captured $intakeDays days ago';
      return _MetaCard(
        icon: Icons.access_time_outlined,
        iconColor: const Color(0xFF97C459),
        label: 'Last seen',
        primaryValue: 'Not seen yet',
        meta: metaText.isEmpty
            ? const SizedBox.shrink()
            : Text(metaText, style: t.metaContext),
      );
    }

    final last = sessions.first;
    final dateStr = last['date'] as String?;
    final dt = dateStr == null ? null : DateTime.tryParse(dateStr);
    final relative = _relativeTime(dt);
    final formatted = _formatLongDate(dt);

    return _MetaCard(
      icon: Icons.access_time_outlined,
      iconColor: const Color(0xFF97C459),
      label: 'Last seen',
      primaryValue: relative ?? 'Recently',
      meta: Text(formatted ?? '', style: t.metaContext),
    );
  }

  static int? _daysAgo(String? iso) {
    if (iso == null) return null;
    final dt = DateTime.tryParse(iso);
    if (dt == null) return null;
    return DateTime.now().difference(dt).inDays;
  }

  static String? _relativeTime(DateTime? dt) {
    if (dt == null) return null;
    final days = DateTime.now().difference(dt).inDays;
    if (days == 0) return 'today';
    if (days == 1) return 'yesterday';
    if (days < 7) return '$days days ago';
    if (days < 14) return '1 week ago';
    if (days < 30) return '${(days / 7).floor()} weeks ago';
    if (days < 60) return '1 month ago';
    return '${(days / 30).floor()} months ago';
  }

  static String? _formatLongDate(DateTime? dt) {
    if (dt == null) return null;
    const months = [
      '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    const weekdays = ['', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final hour = dt.hour;
    final h12 = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);
    final mm = dt.minute.toString().padLeft(2, '0');
    final ampm = hour < 12 ? 'am' : 'pm';
    return '${months[dt.month]} ${dt.day} · ${weekdays[dt.weekday]} · $h12:$mm$ampm';
  }
}

// ── Card 2: NEXT SESSION ─────────────────────────────────────────────────────

class _NextSessionCard extends StatelessWidget {
  final List<Map<String, dynamic>> sessions;
  final VoidCallback? onBuildWithCue;

  const _NextSessionCard({
    required this.sessions,
    this.onBuildWithCue,
  });

  @override
  Widget build(BuildContext context) {
    // Find the next future-dated session, if any. Sessions are usually
    // historical (notes-after-the-fact), but if a row has a future
    // `date` we treat it as scheduled.
    Map<String, dynamic>? upcoming;
    final now = DateTime.now();
    for (final s in sessions) {
      final dateStr = s['date'] as String?;
      if (dateStr == null) continue;
      final dt = DateTime.tryParse(dateStr);
      if (dt == null) continue;
      if (dt.isAfter(now)) {
        if (upcoming == null) {
          upcoming = s;
        } else {
          final existing =
              DateTime.tryParse((upcoming['date'] as String?) ?? '');
          if (existing == null || dt.isBefore(existing)) {
            upcoming = s;
          }
        }
      }
    }

    final primary = upcoming == null
        ? 'Not scheduled'
        : _relativeFuture(DateTime.parse(upcoming['date'] as String));

    return _MetaCard(
      icon: Icons.calendar_today_outlined,
      iconColor: const Color(0xFFF5C778),
      label: 'Next session',
      primaryValue: primary,
      meta: _BuildWithCueLink(onTap: onBuildWithCue),
    );
  }

  static String _relativeFuture(DateTime dt) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final that = DateTime(dt.year, dt.month, dt.day);
    final dayDiff = that.difference(today).inDays;
    const weekdays = ['', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final hour = dt.hour;
    final h12 = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);
    final ampm = hour < 12 ? 'am' : 'pm';
    final mm = dt.minute;
    final timePart = mm == 0 ? '$h12$ampm' : '$h12:${mm.toString().padLeft(2, '0')}$ampm';
    if (dayDiff == 0) return 'Today · $timePart';
    if (dayDiff == 1) return 'Tomorrow · $timePart';
    if (dayDiff < 7) return '${weekdays[that.weekday]} · $timePart';
    return '${that.day}/${that.month} · $timePart';
  }
}

class _BuildWithCueLink extends StatelessWidget {
  final VoidCallback? onTap;
  const _BuildWithCueLink({this.onTap});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: _AmberPillButton(label: 'Build with Cue →', onTap: onTap),
    );
  }
}

// ── Card 3: CADENCE ──────────────────────────────────────────────────────────

class _CadenceCard extends StatelessWidget {
  final List<Map<String, dynamic>> sessions;
  const _CadenceCard({required this.sessions});

  @override
  Widget build(BuildContext context) {
    final t = CueChartTextStyles.of(context, isMobile: false);
    final cue = CueColorsResolved.of(context);
    final count = sessions.length;
    final primary = '$count session${count == 1 ? '' : 's'}';
    final context_ = _cadenceContext(sessions);

    return _MetaCard(
      icon: Icons.bar_chart_outlined,
      iconColor: cue.textSecondary,
      label: 'Cadence',
      primaryValue: primary,
      meta: Text(context_, style: t.metaContext),
    );
  }

  static String _cadenceContext(List<Map<String, dynamic>> sessions) {
    if (sessions.length < 3) return 'early — needs more data';

    // Sessions are newest-first; collect parseable dates.
    final dates = <DateTime>[];
    for (final s in sessions) {
      final dateStr = s['date'] as String?;
      if (dateStr == null) continue;
      final dt = DateTime.tryParse(dateStr);
      if (dt != null) dates.add(dt);
    }
    if (dates.length < 3) return 'early — needs more data';

    dates.sort((a, b) => a.compareTo(b)); // oldest-first
    final firstDt = dates.first;
    final lastDt = dates.last;
    final weekSpan = lastDt.difference(firstDt).inDays / 7.0;

    if (weekSpan < 1) return 'this week';
    final perWeek = dates.length / weekSpan;
    if (perWeek >= 1.7) return 'twice/wk';
    if (perWeek >= 0.85) return 'weekly';
    if (perWeek >= 0.4) return 'biweekly';
    if (weekSpan >= 1) return 'over ${weekSpan.round()} weeks';
    return 'over ${(weekSpan * 7).round()} days';
  }
}

// ── Card 4: CAREGIVER ────────────────────────────────────────────────────────

class _CaregiverCard extends StatelessWidget {
  final Map<String, dynamic> client;
  final VoidCallback? onAddCaregiverDetails;

  const _CaregiverCard({
    required this.client,
    this.onAddCaregiverDetails,
  });

  @override
  Widget build(BuildContext context) {
    final t = CueChartTextStyles.of(context, isMobile: false);
    final cue = CueColorsResolved.of(context);

    final relationship =
        (client['caregiver_relationship'] as String?)?.trim();
    final language = (client['caregiver_language'] as String?)?.trim();
    final isPrimary = client['caregiver_is_primary'] == true;

    if (relationship == null || relationship.isEmpty) {
      return _MetaCard(
        icon: Icons.favorite_border_outlined,
        iconColor: cue.textSecondary,
        label: 'Caregiver',
        primaryValue: 'Not captured',
        meta: Align(
          alignment: Alignment.centerLeft,
          child: _AmberPillButton(
            label: 'Add caregiver details →',
            onTap: onAddCaregiverDetails,
          ),
        ),
      );
    }

    final metaParts = <String>[
      if (language != null && language.isNotEmpty) language,
      if (isPrimary) 'primary contact',
    ];

    return _MetaCard(
      icon: Icons.favorite_border_outlined,
      iconColor: cue.textSecondary,
      label: 'Caregiver',
      primaryValue: relationship,
      meta: Text(
        metaParts.isEmpty ? ' ' : metaParts.join(' · '),
        style: t.metaContext,
      ),
    );
  }
}

// ── Shared amber pill button (Phase 4.1.3 item B.1) ──────────────────────────
//
// Replaces the previous amber underlined text links. Used in meta cards
// for "Build with Cue →", "Add caregiver details →", and any other
// future CTA that needs to read as a tap target rather than inline prose.

class _AmberPillButton extends StatefulWidget {
  final String label;
  final VoidCallback? onTap;
  const _AmberPillButton({required this.label, this.onTap});

  @override
  State<_AmberPillButton> createState() => _AmberPillButtonState();
}

class _AmberPillButtonState extends State<_AmberPillButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final p = CueChartPalette.of(context);
    final cue = CueColorsResolved.of(context);
    final amber = cue.amber;
    final fill = _hover
        ? amber.withValues(alpha: 0.12)
        : p.amberAccentSurface;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
          decoration: BoxDecoration(
            color: fill,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: p.amberAccentBorder, width: 0.5),
          ),
          child: Text(
            widget.label,
            style: TextStyle(
              fontFamily: 'DM Sans',
              fontSize: 11,
              fontWeight: FontWeight.w500,
              letterSpacing: 11 * 0.02,
              color: amber,
              height: 1.2,
            ),
          ),
        ),
      ),
    );
  }
}
