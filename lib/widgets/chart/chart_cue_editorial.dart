// lib/widgets/chart/chart_cue_editorial.dart
//
// Phase 4.1.0 — Cue's "what's in the chart" rendered as inline editorial
// prose. No card container, no hard border, no equal-weight pillar
// treatment. The prose is the design.
//
// Data source: existing /generate-brief proxy endpoint (same as the
// retired BriefThoughtView card). Reads `{thought, highlight}` from
// the response and renders the highlight phrase with a citation-style
// tint inline in the prose. The highlight is currently a no-op tap;
// linked citation routing is Phase 1.5.
//
// Loading state: two skeleton bars at 70% opacity. Never an empty card.

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../theme/cue_color_scheme.dart';
import '../../theme/cue_text_styles.dart';
import '../cue_cuttlefish.dart';

const _briefUrl = 'https://cue-ai-proxy.onrender.com/generate-brief';

class ChartCueEditorial extends StatefulWidget {
  /// Pre-built chart context (use buildChartContext). The widget POSTs
  /// this verbatim to the brief proxy.
  final String chartContext;

  /// Optional override prose — when set, the widget skips the network
  /// fetch and renders the supplied prose. Used by the chart's empty-
  /// chart short-circuit (templated story-starts-here copy).
  final String? overrideThought;
  final String? overrideHighlight;

  const ChartCueEditorial({
    super.key,
    required this.chartContext,
    this.overrideThought,
    this.overrideHighlight,
  });

  @override
  State<ChartCueEditorial> createState() => _ChartCueEditorialState();
}

class _ChartCueEditorialState extends State<ChartCueEditorial> {
  bool _loading = true;
  String? _thought;
  String? _highlight;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.overrideThought != null && widget.overrideThought!.isNotEmpty) {
      _thought = widget.overrideThought;
      _highlight = widget.overrideHighlight;
      _loading = false;
    } else {
      _fetch();
    }
  }

  @override
  void didUpdateWidget(covariant ChartCueEditorial oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Refetch when the chart context changes (e.g., after a session was
    // logged or a goal was added). The parent rebuilds with a fresh
    // chartContext string; we kick off a new request and clear stale
    // copy in the meantime.
    if (widget.chartContext != oldWidget.chartContext &&
        widget.overrideThought == null) {
      setState(() {
        _loading = true;
        _thought = null;
        _highlight = null;
        _error = null;
      });
      _fetch();
    } else if (widget.overrideThought != oldWidget.overrideThought) {
      setState(() {
        _thought = widget.overrideThought;
        _highlight = widget.overrideHighlight;
        _loading = widget.overrideThought == null;
        _error = null;
      });
      if (widget.overrideThought == null) {
        _fetch();
      }
    }
  }

  Future<void> _fetch() async {
    try {
      final res = await http.post(
        Uri.parse(_briefUrl),
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode({'chart_context': widget.chartContext}),
      );
      if (res.statusCode != 200) {
        throw Exception('proxy ${res.statusCode}');
      }
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      if (mounted) {
        setState(() {
          _thought = (body['thought'] as String?)?.trim();
          _highlight = (body['highlight'] as String?)?.trim();
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'Could not load brief.';
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = CueChartTextStyles.of(context, isMobile: false);
    final cue = CueColorsResolved.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header row: cuttlefish + label "Cue · what's in the chart"
        Row(
          children: [
            const SizedBox(
              width: 32,
              height: 38,
              child: CueCuttlefish(
                size: 32,
                state: CueState.thinking,
              ),
            ),
            const SizedBox(width: 14),
            Text(
              "Cue · what's in the chart",
              style: t.cueEditorialEyebrow,
            ),
          ],
        ),
        const SizedBox(height: 18),

        if (_loading)
          _Skeleton(color: cue.borderHover)
        else if (_error != null && (_thought == null || _thought!.isEmpty))
          Text(
            _error!,
            style: TextStyle(
              fontFamily: 'DM Sans',
              fontSize: 13,
              color: cue.coral,
            ),
          )
        else if (_thought != null && _thought!.isNotEmpty)
          _renderThought(t)
        else
          const SizedBox.shrink(),
      ],
    );
  }

  Widget _renderThought(CueChartTextStyles t) {
    final p = CueChartPalette.of(context);
    final thought = _thought!;
    final hl = (_highlight ?? '').trim();

    if (hl.isEmpty) {
      return Text(thought, style: t.cueEditorialProse);
    }

    final lowerHl = hl.toLowerCase();
    final idx = thought.toLowerCase().indexOf(lowerHl);
    if (idx < 0) {
      return Text(thought, style: t.cueEditorialProse);
    }

    final before = thought.substring(0, idx);
    final hlSlice = thought.substring(idx, idx + lowerHl.length);
    final after = thought.substring(idx + lowerHl.length);

    return RichText(
      text: TextSpan(
        style: t.cueEditorialProse,
        children: [
          TextSpan(text: before),
          WidgetSpan(
            alignment: PlaceholderAlignment.baseline,
            baseline: TextBaseline.alphabetic,
            child: _CitationHighlight(
              text: hlSlice,
              style: t.cueEditorialProse,
              bg: p.citationBg,
              borderColor: p.citationBorder,
              borderWidth: p.citationBorderWidth,
            ),
          ),
          TextSpan(text: after),
        ],
      ),
    );
  }
}

class _CitationHighlight extends StatelessWidget {
  final String text;
  final TextStyle style;
  final Color bg;
  final Color borderColor;
  final double borderWidth;

  const _CitationHighlight({
    required this.text,
    required this.style,
    required this.bg,
    required this.borderColor,
    this.borderWidth = 1.0,
  });

  @override
  Widget build(BuildContext context) {
    // Phase 4.1.1 font audit — WidgetSpan boundaries don't inherit
    // TextStyle from the surrounding RichText, so we re-assert italic +
    // tabular figures here. Without this, digits inside the highlight
    // can flash system serif while Google Fonts fetches Playfair.
    final hardenedStyle = style.copyWith(
      fontStyle: FontStyle.italic,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: bg,
          border: Border(
              bottom: BorderSide(color: borderColor, width: borderWidth)),
        ),
        child: Text(text, style: hardenedStyle),
      ),
    );
  }
}

class _Skeleton extends StatelessWidget {
  final Color color;
  const _Skeleton({required this.color});

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: 0.7,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 480,
            height: 28,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(height: 12),
          Container(
            width: 360,
            height: 28,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        ],
      ),
    );
  }
}
