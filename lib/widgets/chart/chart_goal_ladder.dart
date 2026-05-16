// lib/widgets/chart/chart_goal_ladder.dart
//
// Phase 4.1.2 — Chart goal ladder with the STG-in-focus model.
//
// Build order (top to bottom):
//   1. Section header: "ACTIVE SHORT-TERM GOAL[S] · {N}"
//   2. The focused STG (full detail: body + active steps + structured
//      Evidence + "Think with Cue" pill).
//   3. Other active STGs as compact rows below (tap to swap focus).
//   4. 24px gap.
//   5. Section header: "LONG-TERM GOAL[S]" (count appended when N > 1).
//   6. Each LTG as a compact reference row (tap to expand body inline,
//      no Evidence on LTGs).
//
// Persistence:
//   • Focused STG id: `chart_ui_state:focused_stg:<client_id>` —
//     default = most recently updated active STG.
//   • LTG expanded state: `chart_ui_state:ltg:<client_id>:<ltg_id>`.
//
// Evidence prose is not yet sourced. Until Phase 1.5 ships per-goal
// citations, every STG renders the empty-state placeholder inside the
// Evidence section. The structured citation row layout is ready for
// drop-in once the data arrives.

import 'package:flutter/material.dart';

import '../../theme/cue_color_scheme.dart';
import '../../theme/cue_text_styles.dart';
import '../../utils/chart_ui_state.dart';

class ChartGoalLadder extends StatefulWidget {
  final String clientId;
  final List<Map<String, dynamic>> ltgs;
  final List<Map<String, dynamic>> stgs;

  /// Fired when the SLP taps the "Think with Cue" pill inside the
  /// focused STG header. Parent (ClientProfileScreen) opens the
  /// CuePopup scoped to the supplied STG.
  final void Function(Map<String, dynamic> stg)? onThinkWithCue;

  const ChartGoalLadder({
    super.key,
    required this.clientId,
    required this.ltgs,
    required this.stgs,
    this.onThinkWithCue,
  });

  @override
  State<ChartGoalLadder> createState() => _ChartGoalLadderState();
}

class _ChartGoalLadderState extends State<ChartGoalLadder> {
  String? _focusedStgId;
  final Map<String, bool> _ltgExpanded = <String, bool>{};

  @override
  void initState() {
    super.initState();
    _loadState();
  }

  @override
  void didUpdateWidget(covariant ChartGoalLadder oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.clientId != widget.clientId ||
        oldWidget.ltgs.length != widget.ltgs.length ||
        oldWidget.stgs.length != widget.stgs.length) {
      _loadState();
    }
  }

  Future<void> _loadState() async {
    final persistedFocus = await ChartUiState.getFocusedStgId(widget.clientId);
    final activeStgs = widget.stgs.where(_isStgActive).toList();
    String? focused;
    if (persistedFocus != null &&
        activeStgs.any((s) => s['id'].toString() == persistedFocus)) {
      focused = persistedFocus;
    } else if (activeStgs.isNotEmpty) {
      focused = _mostRecentActiveStgId(activeStgs);
    }

    final ltgFutures = <Future<MapEntry<String, bool>>>[
      for (final l in widget.ltgs)
        ChartUiState.isExpanded(
          scope: ChartUiScope.ltg,
          clientId: widget.clientId,
          rowId: l['id'].toString(),
          defaultExpanded: false,
        ).then((v) => MapEntry(l['id'].toString(), v)),
    ];
    final ltgResults = await Future.wait(ltgFutures);

    if (!mounted) return;
    setState(() {
      _focusedStgId = focused;
      _ltgExpanded
        ..clear()
        ..addEntries(ltgResults);
    });
  }

  String? _mostRecentActiveStgId(List<Map<String, dynamic>> actives) {
    final sorted = List<Map<String, dynamic>>.from(actives);
    sorted.sort((a, b) {
      final ad = DateTime.tryParse((a['updated_at'] as String?) ?? '');
      final bd = DateTime.tryParse((b['updated_at'] as String?) ?? '');
      if (ad == null && bd == null) return 0;
      if (ad == null) return 1;
      if (bd == null) return -1;
      return bd.compareTo(ad);
    });
    return sorted.first['id'].toString();
  }

  void _swapFocus(String nextStgId) {
    if (nextStgId == _focusedStgId) return;
    setState(() => _focusedStgId = nextStgId);
    ChartUiState.setFocusedStgId(widget.clientId, nextStgId);
  }

  /// Chevron-on-focused-card behavior: if there's a sibling active STG,
  /// move focus to the next-most-recent one. Otherwise it's a no-op —
  /// "never zero focus" per spec.
  void _cycleFocus(List<Map<String, dynamic>> activeStgs) {
    if (activeStgs.length < 2) return;
    final currentIdx = activeStgs
        .indexWhere((s) => s['id'].toString() == _focusedStgId);
    final nextIdx = currentIdx < 0 ? 0 : (currentIdx + 1) % activeStgs.length;
    _swapFocus(activeStgs[nextIdx]['id'].toString());
  }

  void _toggleLtg(String id) {
    final next = !(_ltgExpanded[id] ?? false);
    setState(() => _ltgExpanded[id] = next);
    ChartUiState.setExpanded(
      scope: ChartUiScope.ltg,
      clientId: widget.clientId,
      rowId: id,
      expanded: next,
    );
  }

  @override
  Widget build(BuildContext context) {
    final activeLtgs = widget.ltgs.where(_isLtgActive).toList();
    final activeStgs = widget.stgs.where(_isStgActive).toList();

    if (activeLtgs.isEmpty && activeStgs.isEmpty) return _emptyLadder(context);

    // Resolve which STG is in focus right now.
    Map<String, dynamic>? focusedStg;
    if (_focusedStgId != null) {
      for (final s in activeStgs) {
        if (s['id'].toString() == _focusedStgId) {
          focusedStg = s;
          break;
        }
      }
    }
    focusedStg ??= activeStgs.isNotEmpty ? activeStgs.first : null;

    final compactStgs = activeStgs
        .where((s) => s['id'].toString() != focusedStg?['id'].toString())
        .toList();

    final stgCount = activeStgs.length;
    final ltgCount = activeLtgs.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── 1. STG section header ──────────────────────────────────────
        if (stgCount > 0)
          _SectionHeader(
            label: stgCount == 1
                ? 'ACTIVE SHORT-TERM GOAL'
                : 'ACTIVE SHORT-TERM GOALS · $stgCount',
          ),
        if (stgCount > 0) const SizedBox(height: 10),

        // ── 2. Focused STG ─────────────────────────────────────────────
        if (focusedStg != null)
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeOutCubic,
            transitionBuilder: (child, anim) =>
                FadeTransition(opacity: anim, child: child),
            child: _FocusedStgCard(
              key: ValueKey('focused-${focusedStg['id']}'),
              stg: focusedStg,
              hasSiblings: activeStgs.length > 1,
              onCycleFocus: () => _cycleFocus(activeStgs),
              onThinkWithCue: widget.onThinkWithCue == null
                  ? null
                  : () => widget.onThinkWithCue!(focusedStg!),
            ),
          ),

        // ── 3. Compact STGs — grouped by domain, horizontal on desktop ─
        if (compactStgs.isNotEmpty)
          _CompactStgGroupedList(
            compactStgs: compactStgs,
            onTapCompact: (s) => _swapFocus(s['id'].toString()),
          ),

        // ── 4. Gap between STG and LTG sections ────────────────────────
        if (stgCount > 0 && ltgCount > 0) const SizedBox(height: 24),

        // ── 5. LTG section header ──────────────────────────────────────
        if (ltgCount > 0)
          _SectionHeader(
            label: ltgCount == 1
                ? 'LONG-TERM GOAL'
                : 'LONG-TERM GOALS · $ltgCount',
          ),
        if (ltgCount > 0) const SizedBox(height: 10),

        // ── 6. Compact LTG rows ────────────────────────────────────────
        for (final ltg in activeLtgs)
          _CompactLtgRow(
            key: ValueKey('ltg-${ltg['id']}'),
            ltg: ltg,
            expanded: _ltgExpanded[ltg['id'].toString()] ?? false,
            onToggle: () => _toggleLtg(ltg['id'].toString()),
          ),
      ],
    );
  }

  Widget _emptyLadder(BuildContext context) {
    final t = CueChartTextStyles.of(context, isMobile: false);
    final cue = CueColorsResolved.of(context);
    final p = CueChartPalette.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 28),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: p.sectionDivider, width: 0.5),
          bottom: BorderSide(color: p.sectionDivider, width: 0.5),
        ),
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('No goals yet.', style: t.ladderBody),
              const SizedBox(height: 6),
              Text(
                'Build a plan with Cue to start tracking long-term goals and active steps.',
                style: t.ladderBody.copyWith(color: cue.textSecondary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

bool _isLtgActive(Map<String, dynamic> ltg) {
  final status = (ltg['status'] as String?)?.toLowerCase();
  if (status == null || status.isEmpty) return true;
  return status == 'active' || status == 'in_progress';
}

bool _isStgActive(Map<String, dynamic> stg) {
  final status = (stg['status'] as String?)?.toLowerCase();
  return status == null || status.isEmpty || status == 'active';
}

String _stgBodyText(Map<String, dynamic> stg) {
  return ((stg['target_behavior'] as String?) ??
          (stg['specific'] as String?) ??
          (stg['goal_text'] as String?) ??
          (stg['target'] as String?) ??
          '')
      .trim();
}

String? _stgDurationLabel(Map<String, dynamic> stg) {
  final raw = stg['time_bound_sessions'];
  final weeks = raw is int ? raw : (raw is num ? raw.toInt() : null);
  if (weeks == null || weeks <= 0) return null;
  return weeks == 1 ? '1 week' : '$weeks weeks';
}

String? _ltgDurationLabel(Map<String, dynamic> ltg) {
  final targetStr = ltg['target_date'] as String?;
  if (targetStr == null || targetStr.isEmpty) return null;
  final target = DateTime.tryParse(targetStr);
  if (target == null) return null;
  final months = ((target.difference(DateTime.now()).inDays) / 30).round();
  if (months <= 0) return 'overdue';
  if (months == 1) return '1 month';
  return '$months months';
}

// ── Section header ───────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String label;
  const _SectionHeader({required this.label});

  @override
  Widget build(BuildContext context) {
    final t = CueChartTextStyles.of(context, isMobile: false);
    final p = CueChartPalette.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(label, style: t.ladderEyebrow),
          const SizedBox(width: 12),
          Expanded(child: Container(height: 0.5, color: p.sectionDivider)),
        ],
      ),
    );
  }
}

// ── Focused STG card ─────────────────────────────────────────────────────────

class _FocusedStgCard extends StatelessWidget {
  final Map<String, dynamic> stg;
  final bool hasSiblings;
  final VoidCallback onCycleFocus;
  final VoidCallback? onThinkWithCue;

  const _FocusedStgCard({
    super.key,
    required this.stg,
    required this.hasSiblings,
    required this.onCycleFocus,
    required this.onThinkWithCue,
  });

  @override
  Widget build(BuildContext context) {
    final t = CueChartTextStyles.of(context, isMobile: false);
    final p = CueChartPalette.of(context);
    final cue = CueColorsResolved.of(context);
    final amber = cue.amber;

    final body = _stgBodyText(stg);
    final domain = (stg['domain'] as String?)?.trim();
    final duration = _stgDurationLabel(stg);

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
      decoration: BoxDecoration(
        color: p.focusedSurface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: p.amberAccentBorder, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              MouseRegion(
                cursor: hasSiblings
                    ? SystemMouseCursors.click
                    : SystemMouseCursors.basic,
                child: GestureDetector(
                  onTap: hasSiblings ? onCycleFocus : null,
                  child: Icon(
                    Icons.keyboard_arrow_down_rounded,
                    size: 18,
                    color: amber,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'SHORT-TERM GOAL · IN FOCUS',
                style: t.ladderEyebrow.copyWith(color: amber),
              ),
              if (domain != null && domain.isNotEmpty) ...[
                const SizedBox(width: 12),
                Text(domain.toUpperCase(), style: t.domainPill),
              ],
              const Spacer(),
              if (onThinkWithCue != null) ...[
                _ThinkWithCuePill(onTap: onThinkWithCue!),
                const SizedBox(width: 12),
              ],
              if (duration != null) Text(duration, style: t.ladderDuration),
            ],
          ),
          const SizedBox(height: 14),

          // Body
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Text(
              body.isEmpty ? 'No step text captured.' : body,
              style: t.ladderBody,
            ),
          ),
          const SizedBox(height: 16),

          // Active steps
          _ActiveStepsGrid(stg: stg),

          // Evidence section
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.only(top: 14),
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(color: cue.border, width: 0.5),
              ),
            ),
            child: const _EvidenceSection(citations: <_Citation>[]),
          ),
        ],
      ),
    );
  }
}

// ── Compact STG grouped list (Phase 4.1.3 items B.3 + B.4) ───────────────────
//
// Groups compact STGs by their `domain` field. Within each group, sorts by
// `updated_at` descending. On desktop (>1024px viewport) renders each
// group as a horizontal scroll row of 320px-wide preview cards; on mobile
// stacks them vertically as full-width rows.
//
// If only one domain is present, the group header is omitted and a single
// horizontal scroll / vertical stack renders without a label.

class _DomainGroup {
  final String domain;
  final List<Map<String, dynamic>> stgs;
  _DomainGroup(this.domain, this.stgs);
}

List<_DomainGroup> _groupByDomain(List<Map<String, dynamic>> stgs) {
  final buckets = <String, List<Map<String, dynamic>>>{};
  for (final s in stgs) {
    final d = ((s['domain'] as String?) ?? '').trim();
    final key = d.isEmpty ? '—' : d.toUpperCase();
    buckets.putIfAbsent(key, () => <Map<String, dynamic>>[]).add(s);
  }
  for (final list in buckets.values) {
    list.sort((a, b) {
      final ad = DateTime.tryParse((a['updated_at'] as String?) ?? '');
      final bd = DateTime.tryParse((b['updated_at'] as String?) ?? '');
      if (ad == null && bd == null) return 0;
      if (ad == null) return 1;
      if (bd == null) return -1;
      return bd.compareTo(ad);
    });
  }
  final out = buckets.entries
      .map((e) => _DomainGroup(e.key, e.value))
      .toList();
  out.sort((a, b) => b.stgs.length.compareTo(a.stgs.length));
  return out;
}

class _CompactStgGroupedList extends StatelessWidget {
  final List<Map<String, dynamic>> compactStgs;
  final void Function(Map<String, dynamic>) onTapCompact;

  const _CompactStgGroupedList({
    required this.compactStgs,
    required this.onTapCompact,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktop = constraints.maxWidth > 1024;
        final groups = _groupByDomain(compactStgs);
        final multiDomain = groups.length > 1;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (int i = 0; i < groups.length; i++) ...[
              if (i > 0) const SizedBox(height: 16),
              if (multiDomain) ...[
                _DomainGroupHeader(
                  domain: groups[i].domain,
                  count: groups[i].stgs.length,
                ),
                const SizedBox(height: 8),
              ],
              _CompactStgRail(
                stgs: groups[i].stgs,
                isDesktop: isDesktop,
                onTap: onTapCompact,
              ),
            ],
          ],
        );
      },
    );
  }
}

class _DomainGroupHeader extends StatelessWidget {
  final String domain;
  final int count;
  const _DomainGroupHeader({required this.domain, required this.count});

  @override
  Widget build(BuildContext context) {
    final t = CueChartTextStyles.of(context, isMobile: false);
    return Text('$domain · $count', style: t.ladderEyebrow);
  }
}

class _CompactStgRail extends StatefulWidget {
  final List<Map<String, dynamic>> stgs;
  final bool isDesktop;
  final void Function(Map<String, dynamic>) onTap;

  const _CompactStgRail({
    required this.stgs,
    required this.isDesktop,
    required this.onTap,
  });

  @override
  State<_CompactStgRail> createState() => _CompactStgRailState();
}

class _CompactStgRailState extends State<_CompactStgRail> {
  final ScrollController _scroll = ScrollController();
  bool _hover = false;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _scrollBy(double delta) {
    if (!_scroll.hasClients) return;
    final target =
        (_scroll.offset + delta).clamp(0.0, _scroll.position.maxScrollExtent);
    _scroll.animateTo(
      target,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isDesktop) {
      // Mobile / tablet — vertical stack of full-width row cards.
      //
      // Phase 4.1.6 — each card is wrapped in SizedBox(height: 120) to
      // match the desktop rail's bounded height. Without this, when the
      // ladder is hosted inside a SliverToBoxAdapter (the chart screen's
      // actual layout) the parent Column inherits unbounded vertical and
      // _CompactStgCard's inner Column (mainAxisAlignment.spaceBetween +
      // Expanded(body)) throws "RenderFlex children have non-zero flex
      // but incoming height constraints are unbounded".
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final s in widget.stgs)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: SizedBox(
                height: 120,
                child: _CompactStgCard(
                  stg: s,
                  fixedWidth: null,
                  onTap: () => widget.onTap(s),
                ),
              ),
            ),
        ],
      );
    }

    // Desktop — horizontal scroll, hover-reveal arrow buttons.
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: SizedBox(
        height: 120,
        child: Stack(
          children: [
            SingleChildScrollView(
              controller: _scroll,
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final s in widget.stgs)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: _CompactStgCard(
                        stg: s,
                        fixedWidth: 320,
                        onTap: () => widget.onTap(s),
                      ),
                    ),
                ],
              ),
            ),
            if (_hover && widget.stgs.length > 3) ...[
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                child: _ScrollArrow(
                  icon: Icons.chevron_left_rounded,
                  onTap: () => _scrollBy(-320 - 8),
                ),
              ),
              Positioned(
                right: 0,
                top: 0,
                bottom: 0,
                child: _ScrollArrow(
                  icon: Icons.chevron_right_rounded,
                  onTap: () => _scrollBy(320 + 8),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CompactStgCard extends StatelessWidget {
  final Map<String, dynamic> stg;
  final double? fixedWidth;
  final VoidCallback onTap;

  const _CompactStgCard({
    required this.stg,
    required this.fixedWidth,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = CueChartTextStyles.of(context, isMobile: false);
    final p = CueChartPalette.of(context);
    final cue = CueColorsResolved.of(context);

    final body = _stgBodyText(stg);
    final domain = (stg['domain'] as String?)?.trim();
    final stepCount = body.isEmpty ? 0 : 1;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: fixedWidth,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: p.compactSurface,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: p.sectionDivider, width: 0.5),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  if (domain != null && domain.isNotEmpty)
                    Text(domain.toUpperCase(), style: t.domainPill),
                  const Spacer(),
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 16,
                    color: cue.textSecondary,
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Expanded(
                child: Text(
                  body.isEmpty ? 'No step text captured.' : body,
                  style: t.ladderBody.copyWith(color: cue.textSecondary),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '$stepCount step${stepCount == 1 ? '' : 's'}',
                style: t.ladderDuration,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ScrollArrow extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _ScrollArrow({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = CueChartPalette.of(context);
    final cue = CueColorsResolved.of(context);
    return Center(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: p.holdSurface,
              shape: BoxShape.circle,
              border: Border.all(color: p.holdBorder, width: 0.5),
            ),
            alignment: Alignment.center,
            child: Icon(icon, size: 18, color: cue.textPrimary),
          ),
        ),
      ),
    );
  }
}

// ── Compact LTG row ──────────────────────────────────────────────────────────

class _CompactLtgRow extends StatelessWidget {
  final Map<String, dynamic> ltg;
  final bool expanded;
  final VoidCallback onToggle;

  const _CompactLtgRow({
    super.key,
    required this.ltg,
    required this.expanded,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final t = CueChartTextStyles.of(context, isMobile: false);
    final p = CueChartPalette.of(context);
    final cue = CueColorsResolved.of(context);

    final body = (ltg['goal_text'] as String?)?.trim() ?? '';
    final domain = (ltg['domain'] as String?)?.trim();
    final duration = _ltgDurationLabel(ltg);

    final truncated = !expanded && body.length > 120
        ? '${body.substring(0, 117)}…'
        : body;

    return InkWell(
      onTap: onToggle,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: p.sectionDivider, width: 0.5)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Icon(
                  expanded
                      ? Icons.keyboard_arrow_down_rounded
                      : Icons.keyboard_arrow_right_rounded,
                  size: 18,
                  color: cue.textSecondary,
                ),
                const SizedBox(width: 8),
                Text(
                  'LONG-TERM GOAL',
                  style: t.ladderEyebrow.copyWith(color: cue.textSecondary),
                ),
                if (domain != null && domain.isNotEmpty) ...[
                  const SizedBox(width: 12),
                  Text(domain.toUpperCase(), style: t.domainPill),
                ],
                const Spacer(),
                if (duration != null) Text(duration, style: t.ladderDuration),
              ],
            ),
            if (body.isNotEmpty) ...[
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.only(left: 26),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 760),
                  child: Text(
                    truncated,
                    style: t.ladderBody.copyWith(color: cue.textSecondary),
                    maxLines: expanded ? null : 1,
                    overflow: expanded
                        ? TextOverflow.clip
                        : TextOverflow.ellipsis,
                  ),
                ),
              ),
            ],
            // Phase 4.1.4 item B.5 — when the LTG is expanded, append the
            // shared structured Evidence section below the body. Collapsed
            // LTGs render no evidence. Reuses the same _EvidenceSection
            // widget the focused STG uses (DRY citation rendering).
            if (expanded)
              Padding(
                padding: const EdgeInsets.only(left: 26, top: 16),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 760),
                  child: const _EvidenceSection(citations: <_Citation>[]),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ── Think with Cue pill ──────────────────────────────────────────────────────

class _ThinkWithCuePill extends StatefulWidget {
  final VoidCallback onTap;
  const _ThinkWithCuePill({required this.onTap});

  @override
  State<_ThinkWithCuePill> createState() => _ThinkWithCuePillState();
}

class _ThinkWithCuePillState extends State<_ThinkWithCuePill> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final p = CueChartPalette.of(context);
    final cue = CueColorsResolved.of(context);
    final amber = cue.amber;
    final fillAlpha = _hover ? 0x1F : 0x0F; // 12% on hover, 6% rest
    final fillColor = amber.withValues(alpha: fillAlpha / 255);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: _hover ? fillColor : p.amberAccentSurface,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: p.amberAccentBorder, width: 0.5),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(Icons.chat_bubble_outline_rounded, size: 11, color: amber),
              const SizedBox(width: 6),
              Text(
                'Think with Cue',
                style: TextStyle(
                  fontFamily: 'DM Sans',
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 10 * 0.04,
                  color: amber,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Evidence section (structured citation list) ──────────────────────────────

class _Citation {
  final String tier; // "I" | "II" | "III" | "IV"
  final String finding;
  final String author;
  final int year;
  const _Citation({
    required this.tier,
    required this.finding,
    required this.author,
    required this.year,
  });
}

class _EvidenceSection extends StatelessWidget {
  final List<_Citation> citations;
  const _EvidenceSection({required this.citations});

  @override
  Widget build(BuildContext context) {
    final t = CueChartTextStyles.of(context, isMobile: false);
    final cue = CueColorsResolved.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.menu_book_outlined, size: 12, color: cue.textSecondary),
            const SizedBox(width: 8),
            Text(
              citations.isEmpty
                  ? 'EVIDENCE'
                  : 'EVIDENCE · ${citations.length} '
                      'SOURCE${citations.length == 1 ? '' : 'S'}',
              style: t.ladderEyebrow,
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (citations.isEmpty)
          Text(
            'Evidence sources will appear here as Cue indexes the literature for this goal.',
            style: t.ladderBody.copyWith(
              fontStyle: FontStyle.italic,
              fontSize: 12,
              color: cue.textMuted,
            ),
          )
        else
          ...List<Widget>.generate(citations.length, (i) {
            final citation = citations[i];
            return Padding(
              padding: EdgeInsets.only(top: i == 0 ? 0 : 6),
              child: _CitationRow(citation: citation),
            );
          }),
      ],
    );
  }
}

class _CitationRow extends StatelessWidget {
  final _Citation citation;
  const _CitationRow({required this.citation});

  @override
  Widget build(BuildContext context) {
    final cue = CueColorsResolved.of(context);
    final p = CueChartPalette.of(context);
    Color tierColor;
    switch (citation.tier.toUpperCase()) {
      case 'I':
        tierColor = p.evidenceLevelI;
        break;
      case 'II':
        tierColor = p.evidenceLevelII;
        break;
      case 'III':
      case 'IV':
      default:
        tierColor = p.evidenceLevelIIIIV;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 56,
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: Text(
                'LEVEL ${citation.tier.toUpperCase()}',
                style: TextStyle(
                  fontFamily: 'Syne',
                  fontSize: 9,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 9 * 0.08,
                  color: tierColor,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              citation.finding,
              style: TextStyle(
                fontFamily: 'DM Sans',
                fontSize: 12,
                height: 1.4,
                color: cue.textPrimary,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 12),
          MouseRegion(
            cursor: SystemMouseCursors.click,
            child: Text(
              '${citation.author} ${citation.year} ↗',
              style: TextStyle(
                fontFamily: 'DM Sans',
                fontSize: 10,
                color: cue.textMuted,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Active steps grid (carried over from Phase 4.1.0) ────────────────────────

class _ActiveStepsGrid extends StatelessWidget {
  final Map<String, dynamic> stg;
  const _ActiveStepsGrid({required this.stg});

  @override
  Widget build(BuildContext context) {
    final t = CueChartTextStyles.of(context, isMobile: false);

    final stepText = _stgBodyText(stg);
    final totalSessions = _intField(stg, 'time_bound_sessions');
    final workedSessions = _intField(stg, 'total_sessions_worked');
    String? weekProgress;
    if (totalSessions != null && totalSessions > 0) {
      final worked = workedSessions ?? 0;
      final current = worked < totalSessions ? worked + 1 : totalSessions;
      weekProgress = '(week $current of $totalSessions)';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('ACTIVE STEPS · 1', style: t.ladderEyebrow),
        const SizedBox(height: 10),
        Padding(
          padding: const EdgeInsets.only(left: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                margin: const EdgeInsets.only(top: 6),
                width: 10,
                height: 10,
                decoration: const BoxDecoration(
                  color: Color(0xFF97C459),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 8,
                  children: [
                    Text(
                      stepText.isEmpty ? 'No active step.' : stepText,
                      style: t.stepText,
                    ),
                    if (weekProgress != null)
                      Text(weekProgress, style: t.stepWeek),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  static int? _intField(Map<String, dynamic> m, String key) {
    final v = m[key];
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v);
    return null;
  }
}
