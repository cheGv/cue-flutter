// lib/widgets/substrate/substrate_view.dart
//
// Phase A — Substrate view. Six fixed-order layers (regulation first),
// collapsible cells, threading, and search. Pure presentation — the host
// (lib/screens/substrate_route.dart) owns the load and passes cells +
// relations in.
//
// COLLAPSE. Cells render collapsed by default: humanized question title +
// small indicators (tag count, an italic "empty" mark when content is null, a
// sienna dot when safety_flag is set). Tap a cell to expand in place (content,
// attribute pills, tags, source attribution, and the reasoning reveal when
// it's a related cell); tap again to collapse. Expansions are per-cell and
// accumulate — tapping one cell never collapses another. Expand/collapse is a
// 300ms ease-out height+fade (AnimatedCrossFade).
//
// THREADING. A tap also sets the cell active (amber border + tint) and
// recomputes related cells: for each active-cell tag, a source_tag match
// collects target_tag; for `mutual` edges a target_tag match also collects
// source_tag. Other cells carrying a collected tag become related (sienna
// border + tint) and, when expanded, reveal the connecting relation's
// one-line reasoning. Active and expansion are independent. Background tap
// clears threading (expansions persist). Traversal logic unchanged.
//
// SEARCH. A field below the title filters cells live (case-insensitive
// substring) against the humanized sub_category, content, source excerpts,
// and tag values. Matches show auto-expanded; non-matches are hidden (a layer
// header shows only if it has a match). Empty search returns the chart to the
// default collapsed state. Matched substrings highlight in amber within
// evidence + excerpts (not in titles or tags — would be noisy).
//
// ACTIVE / highlight COLOUR = cue.amber (theme colorScheme.primary). One cell
// active at a time, so the amber-once-per-surface lock holds; related = sienna,
// tags = olive.
//
// Theme-aware via CueColorsResolved (app default register is dark). WARM
// SIENNA (taxonomy mandate, no token yet) lives locally in _SubstrateWarm.
//
// CUE PRODUCT LAW: assembles evidence; the clinician reasons. No ranking,
// scoring, or gap nudges.

import 'package:flutter/material.dart';

import '../../models/substrate.dart';
import '../../theme/cue_color_scheme.dart';
import '../../theme/cue_tokens.dart';
import '../../theme/cue_type_v3.dart';
import '../cue_cuttlefish.dart';

class SubstrateView extends StatefulWidget {
  /// All cells for the client, sources + tags embedded. Layer grouping and
  /// ordering happen here, not in the query.
  final List<SubstrateCell> cells;

  /// The global threading graph — traversed on tap to find related cells.
  final List<SubstrateRelation> relations;

  /// Page-identity name (the child). Falls back to "Substrate" when absent.
  final String? clientName;

  const SubstrateView({
    super.key,
    required this.cells,
    this.relations = const [],
    this.clientName,
  });

  @override
  State<SubstrateView> createState() => _SubstrateViewState();
}

class _SubstrateViewState extends State<SubstrateView> {
  /// id of the active (threading-source) cell, or null when none.
  String? _activeCellId;

  /// ids of cells threaded to the active cell via substrate_relations.
  Set<String> _relatedCellIds = <String>{};

  /// related cell id → the connecting relation's one-line reasoning.
  Map<String, String> _reasonByCellId = <String, String>{};

  /// ids of cells the clinician has expanded. Independent of active; multiple
  /// allowed concurrently.
  final Set<String> _expandedCellIds = <String>{};

  /// Live search query. Empty = full chart in its default collapsed state.
  String _searchQuery = '';
  late final TextEditingController _searchController;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  bool get _hasName =>
      widget.clientName != null && widget.clientName!.trim().isNotEmpty;

  bool get _searching => _searchQuery.trim().isNotEmpty;

  String get _query => _searchQuery.trim().toLowerCase();

  // During search, every rendered cell is a match the clinician navigated TO,
  // so it auto-expands. Otherwise expansion follows her taps.
  bool _isExpanded(SubstrateCell cell) =>
      _searching ? true : _expandedCellIds.contains(cell.id);

  bool _cellMatches(SubstrateCell cell) {
    final q = _query;
    if (q.isEmpty) return true;
    if (_humanize(cell.subCategory).toLowerCase().contains(q)) return true;
    if ((cell.content ?? '').toLowerCase().contains(q)) return true;
    for (final s in cell.sources) {
      if ((s.excerpt ?? '').toLowerCase().contains(q)) return true;
    }
    for (final t in cell.tags) {
      if (t.tag.toLowerCase().contains(q)) return true;
    }
    return false;
  }

  // ── Interaction ─────────────────────────────────────────────────────────────

  void _onTapCell(String cellId) {
    setState(() {
      // Expansion toggles independently of threading.
      if (_expandedCellIds.contains(cellId)) {
        _expandedCellIds.remove(cellId);
      } else {
        _expandedCellIds.add(cellId);
      }
      // A tap also makes this the active threading source (trigger unchanged).
      _applyActive(cellId);
    });
  }

  void _onTapBackground() {
    if (_activeCellId == null) return;
    setState(_resetThreads);
  }

  void _resetThreads() {
    _activeCellId = null;
    _relatedCellIds = <String>{};
    _reasonByCellId = <String, String>{};
  }

  void _onSearchChanged(String value) {
    setState(() {
      _searchQuery = value;
      // Empty search → full chart returns to the default collapsed state.
      if (value.trim().isEmpty) _expandedCellIds.clear();
    });
  }

  void _clearSearch() {
    _searchController.clear();
    FocusScope.of(context).unfocus();
    setState(() {
      _searchQuery = '';
      _expandedCellIds.clear();
    });
  }

  /// Walk the relation graph from the active cell's tags. A source_tag match
  /// makes target reachable; for `mutual` edges a target_tag match also makes
  /// source reachable. Each connected tag carries the reasoning of the
  /// relation that produced it.
  void _applyActive(String cellId) {
    _activeCellId = cellId;

    final active = widget.cells.firstWhere((c) => c.id == cellId);
    final activeTags = active.tags.map((t) => t.tag).toSet();

    final connectedTagToReason = <String, String?>{};
    for (final rel in widget.relations) {
      if (activeTags.contains(rel.sourceTag)) {
        connectedTagToReason.putIfAbsent(rel.targetTag, () => rel.reasoning);
      }
      if (rel.direction == SubstrateRelationDirection.mutual &&
          activeTags.contains(rel.targetTag)) {
        connectedTagToReason.putIfAbsent(rel.sourceTag, () => rel.reasoning);
      }
    }
    final connectedTags = connectedTagToReason.keys.toSet();

    final related = <String>{};
    final reasons = <String, String>{};
    for (final cell in widget.cells) {
      if (cell.id == cellId) continue;
      for (final t in cell.tags) {
        if (connectedTags.contains(t.tag)) {
          related.add(cell.id);
          final r = connectedTagToReason[t.tag];
          if (r != null && r.trim().isNotEmpty) {
            reasons.putIfAbsent(cell.id, () => r);
          }
        }
      }
    }
    _relatedCellIds = related;
    _reasonByCellId = reasons;
  }

  // ── Build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final cue = CueColorsResolved.of(context);
    final warm = _SubstrateWarm.of(context);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _onTapBackground,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 48),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _header(cue),
            const SizedBox(height: 20),
            _searchField(cue),
            const SizedBox(height: 20),
            Container(height: CueSize.hairline, color: cue.border),
            const SizedBox(height: 28),
            for (final layer in SubstrateLayer.values)
              _layerSection(cue, warm, layer),
          ],
        ),
      ),
    );
  }

  // ── Header — cuttlefish companion column + page identity ────────────────────

  Widget _header(CueColorsResolved cue) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 80,
          child: Center(
            child: SizedBox(
              width: 64,
              height: 64,
              child: CueCuttlefish(size: 64, state: CueState.softWave),
            ),
          ),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_hasName) ...[
                Text(
                  'Substrate',
                  style: CueTypeV3.clinicalLabel(
                      emphasis: 'strong', color: cue.olive),
                ),
                const SizedBox(height: 4),
              ],
              Text(
                _hasName ? widget.clientName!.trim() : 'Substrate',
                style: CueTypeV3.h1(color: cue.textPrimary),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── Search field ────────────────────────────────────────────────────────────

  Widget _searchField(CueColorsResolved cue) {
    return Container(
      height: 40,
      decoration: BoxDecoration(
        color: cue.bgInput,
        border: Border.all(color: cue.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const SizedBox(width: 12),
          Icon(Icons.search, size: 18, color: cue.textMuted),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _searchController,
              onChanged: _onSearchChanged,
              style: CueTypeV3.body(color: cue.textPrimary),
              cursorColor: cue.amber,
              decoration: InputDecoration(
                isCollapsed: true,
                border: InputBorder.none,
                hintText: 'Search evidence, tags…',
                hintStyle: CueTypeV3.body(color: cue.textMuted),
              ),
            ),
          ),
          if (_searchQuery.isNotEmpty)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _clearSearch,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Icon(Icons.close, size: 18, color: cue.textMuted),
              ),
            )
          else
            const SizedBox(width: 12),
        ],
      ),
    );
  }

  // ── Layer section ───────────────────────────────────────────────────────────

  Widget _layerSection(
      CueColorsResolved cue, _SubstrateWarm warm, SubstrateLayer layer) {
    final all = widget.cells.where((c) => c.layer == layer).toList();
    final shown = _searching ? all.where(_cellMatches).toList() : all;

    // During search, a layer with no matches is hidden entirely (header too).
    if (_searching && shown.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(layer.title, style: CueTypeV3.sectionTitle(color: cue.textPrimary)),
        const SizedBox(height: 14),
        if (shown.isEmpty)
          Padding(
            padding: const EdgeInsets.only(left: 14, bottom: 8),
            child: Text(
              '— not yet on file —',
              style: CueTypeV3.editorialItalic(color: warm.sienna),
            ),
          )
        else
          for (final cell in shown) _cell(cue, warm, cell),
        const SizedBox(height: 30),
      ],
    );
  }

  // ── Cell ──────────────────────────────────────────────────────────────────

  Widget _cell(CueColorsResolved cue, _SubstrateWarm warm, SubstrateCell cell) {
    final isActive = cell.id == _activeCellId;
    final isRelated = _relatedCellIds.contains(cell.id);
    final safety = cell.hasSafetyFlag;
    final expanded = _isExpanded(cell);

    // Border priority: active (amber) > related/safety (sienna) > none. The
    // SAFETY pill / collapsed dot still marks safety when active takes over.
    final Color borderColor = isActive
        ? cue.amber
        : (isRelated || safety ? warm.sienna : Colors.transparent);
    final Color tintColor = isActive
        ? cue.amber.withValues(alpha: 0.09)
        : (isRelated ? warm.sienna.withValues(alpha: 0.09) : Colors.transparent);

    final reason = isRelated ? _reasonByCellId[cell.id] : null;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _onTapCell(cell.id),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
        margin: const EdgeInsets.only(bottom: 18),
        padding: const EdgeInsets.fromLTRB(14, 8, 12, 8),
        decoration: BoxDecoration(
          color: tintColor,
          border: Border(left: BorderSide(color: borderColor, width: 3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _titleRow(cue, warm, cell, expanded),
            AnimatedCrossFade(
              duration: const Duration(milliseconds: 300),
              sizeCurve: Curves.easeOut,
              firstCurve: Curves.easeOut,
              secondCurve: Curves.easeOut,
              crossFadeState: expanded
                  ? CrossFadeState.showSecond
                  : CrossFadeState.showFirst,
              firstChild: const SizedBox(width: double.infinity, height: 0),
              secondChild: _expandedBody(cue, warm, cell, reason),
            ),
          ],
        ),
      ),
    );
  }

  // Collapsed/expanded both show the humanized title; collapsed adds the small
  // indicator cluster on the right.
  Widget _titleRow(CueColorsResolved cue, _SubstrateWarm warm,
      SubstrateCell cell, bool expanded) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Text(
            _humanize(cell.subCategory),
            style:
                CueTypeV3.clinicalLabel(emphasis: 'strong', color: cue.textPrimary),
          ),
        ),
        if (!expanded) _collapsedIndicators(cue, warm, cell),
      ],
    );
  }

  Widget _collapsedIndicators(
      CueColorsResolved cue, _SubstrateWarm warm, SubstrateCell cell) {
    final items = <Widget>[];
    if (cell.isEmpty) {
      items.add(Text(
        'empty',
        style: CueTypeV3.editorialItalic(color: warm.sienna)
            .copyWith(fontSize: 12),
      ));
    }
    if (cell.tags.isNotEmpty) {
      // Inline count → Inter 700 tabular (numbers-as-game-changers register),
      // olive to tie it to the tag chips.
      items.add(Text(
        '${cell.tags.length}',
        style: CueTypeV3.rosterDataNum(size: 13, color: cue.olive),
      ));
    }
    if (cell.hasSafetyFlag) {
      items.add(Container(
        width: 7,
        height: 7,
        decoration: BoxDecoration(shape: BoxShape.circle, color: warm.sienna),
      ));
    }
    if (items.isEmpty) return const SizedBox.shrink();

    final spaced = <Widget>[];
    for (var i = 0; i < items.length; i++) {
      if (i > 0) spaced.add(const SizedBox(width: 10));
      spaced.add(items[i]);
    }
    return Padding(
      padding: const EdgeInsets.only(left: 10),
      child: Row(mainAxisSize: MainAxisSize.min, children: spaced),
    );
  }

  Widget _expandedBody(CueColorsResolved cue, _SubstrateWarm warm,
      SubstrateCell cell, String? reason) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        if (cell.attributes.isNotEmpty) ...[
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final attr in cell.attributes) _attributePill(cue, warm, attr),
            ],
          ),
          const SizedBox(height: 8),
        ],
        if (cell.isEmpty)
          Text(
            '— not yet on file —',
            style: CueTypeV3.editorialItalic(color: warm.sienna),
          )
        else
          _highlight(
            cell.content!,
            CueTypeV3.body(color: cue.textBody),
            cue.amber,
          ),
        if (cell.tags.isNotEmpty) ...[
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [for (final t in cell.tags) _tagChip(cue, t.tag)],
          ),
        ],
        if (cell.sources.isNotEmpty) ...[
          const SizedBox(height: 10),
          for (final s in cell.sources) _sourceLine(cue, s),
        ],
        if (reason != null && reason.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            reason,
            style: CueTypeV3.body(color: warm.sienna).copyWith(
              fontStyle: FontStyle.italic,
              fontSize: 12.5,
              height: 1.4,
            ),
          ),
        ],
      ],
    );
  }

  // ── Pieces ──────────────────────────────────────────────────────────────────

  Widget _attributePill(
      CueColorsResolved cue, _SubstrateWarm warm, SubstrateAttribute attr) {
    final isSafety = attr == SubstrateAttribute.safetyFlag;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: isSafety ? warm.siennaGround : cue.bgMuted,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        attr.label.toUpperCase(),
        style:
            CueTypeV3.dataEyebrow(color: isSafety ? warm.sienna : cue.textMuted),
      ),
    );
  }

  Widget _tagChip(CueColorsResolved cue, String tag) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: cue.olive.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        tag,
        style: CueTypeV3.clinicalLabel(emphasis: 'light', color: cue.olive),
      ),
    );
  }

  Widget _sourceLine(CueColorsResolved cue, SubstrateSource s) {
    final label = s.sourceType?.label ?? 'Source';
    final dated = s.date != null ? '$label · ${_fmtDate(s.date!)}' : label;
    final excerpt = s.excerpt?.trim();

    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            dated,
            style:
                CueTypeV3.clinicalLabel(emphasis: 'light', color: cue.textMuted),
          ),
          if (excerpt != null && excerpt.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: _highlight(
                '“$excerpt”',
                CueTypeV3.body(color: cue.textBody)
                    .copyWith(fontStyle: FontStyle.italic),
                cue.amber,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
      ),
    );
  }

  // Renders [text] in [base], with every case-insensitive occurrence of the
  // active query painted [highlight]. Plain Text when not searching or no
  // match. Used for evidence + excerpts only (not titles or tags).
  Widget _highlight(
    String text,
    TextStyle base,
    Color highlight, {
    int? maxLines,
    TextOverflow? overflow,
  }) {
    final q = _query;
    final lower = text.toLowerCase();
    if (q.isEmpty || !lower.contains(q)) {
      return Text(text, style: base, maxLines: maxLines, overflow: overflow);
    }
    final spans = <InlineSpan>[];
    var start = 0;
    while (true) {
      final idx = lower.indexOf(q, start);
      if (idx < 0) {
        spans.add(TextSpan(text: text.substring(start)));
        break;
      }
      if (idx > start) spans.add(TextSpan(text: text.substring(start, idx)));
      spans.add(TextSpan(
        text: text.substring(idx, idx + q.length),
        style: base.copyWith(color: highlight, fontWeight: FontWeight.w600),
      ));
      start = idx + q.length;
    }
    return Text.rich(
      TextSpan(style: base, children: spans),
      maxLines: maxLines,
      overflow: overflow,
    );
  }

  // snake_case → "Sentence case" for the question title + search matching.
  String _humanize(String raw) {
    if (raw.isEmpty) return raw;
    final spaced = raw.replaceAll('_', ' ').trim();
    if (spaced.isEmpty) return spaced;
    return spaced[0].toUpperCase() + spaced.substring(1);
  }

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  String _fmtDate(DateTime d) => '${d.day} ${_months[d.month - 1]} ${d.year}';
}

// ── Local warm-sienna pair (taxonomy mandate; see file header) ──────────────
class _SubstrateWarm {
  /// Safety border/dot, empty marks, related border/tint, reasoning reveal.
  final Color sienna;

  /// Safety pill background (alpha-tinted sienna).
  final Color siennaGround;

  const _SubstrateWarm({required this.sienna, required this.siennaGround});

  factory _SubstrateWarm.of(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return isDark
        ? const _SubstrateWarm(
            sienna: Color(0xFFD98E63), // lighter, reads on near-black
            siennaGround: Color(0x24D98E63), // ~14% alpha
          )
        : const _SubstrateWarm(
            sienna: Color(0xFFA0522D), // classic warm sienna on near-white
            siennaGround: Color(0x1FA0522D), // ~12% alpha
          );
  }
}
