// lib/widgets/brief_thought_view.dart
//
// Phase 2 brief widget. Replaces the parchment four-section template with
// ONE architectural thought: small eyebrow ("Cue noticed"), the sentence in
// displayMedium, the key phrase wrapped in amber, optional "Think with Cue"
// pill.
//
// Calls the /generate-brief proxy endpoint that returns
// `{thought, highlight}`. The widget is composable — drop it into any
// scrollable surface where a brief thought is wanted.
//
// Wiring: today the chart screen still calls the legacy _CueStudyBrief.
// Wire this in by replacing _CueStudyBrief's body with a BriefThoughtView
// once you're ready to retire the old four-section card.

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../theme/cue_theme.dart';
import '../theme/cue_tokens.dart';
import '../theme/cue_typography.dart';
import 'cue_cuttlefish.dart';

const _briefUrl = 'https://cue-ai-proxy.onrender.com/generate-brief';

class BriefThoughtView extends StatefulWidget {
  /// Pre-built chart context (use buildChartContext from
  /// lib/utils/chart_context.dart). The widget POSTs this verbatim.
  final String       chartContext;
  /// Optional callback when "Think with Cue" is tapped.
  final VoidCallback? onThinkWithCue;
  /// EdgeInsets — caller controls outer padding/margin.
  final EdgeInsets   padding;

  const BriefThoughtView({
    super.key,
    required this.chartContext,
    this.onThinkWithCue,
    this.padding = const EdgeInsets.symmetric(
        horizontal: CueGap.s24, vertical: CueGap.s24),
  });

  @override
  State<BriefThoughtView> createState() => _BriefThoughtViewState();
}

class _BriefThoughtViewState extends State<BriefThoughtView> {
  bool    _loading   = true;
  String? _thought;
  String? _highlight;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetch();
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
          _thought   = (body['thought']   as String?)?.trim();
          _highlight = (body['highlight'] as String?)?.trim();
          _loading   = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error   = 'Could not load brief.';
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return BriefThoughtCard(
      thought:        _thought,
      highlight:      _highlight,
      loading:        _loading,
      errorText:      _error,
      onThinkWithCue: widget.onThinkWithCue,
      padding:        widget.padding,
    );
  }
}

// ── BriefThoughtCard — pure-presentation render layer ────────────────────────
//
// Used directly by callers that already know the brief copy (e.g. the chart
// screen's empty-chart short-circuit, where the LLM is bypassed entirely
// and a templated thought is rendered instead). Same visual register as the
// LLM-driven path; the only difference is the content source.

class BriefThoughtCard extends StatelessWidget {
  final String?      thought;
  final String?      highlight;
  final bool         loading;
  final String?      errorText;
  final VoidCallback? onThinkWithCue;
  final EdgeInsets   padding;

  const BriefThoughtCard({
    super.key,
    this.thought,
    this.highlight,
    this.loading        = false,
    this.errorText,
    this.onThinkWithCue,
    this.padding = const EdgeInsets.symmetric(
        horizontal: CueGap.s24, vertical: CueGap.s24),
  });

  @override
  Widget build(BuildContext context) {
    final isNight = Theme.of(context).brightness == Brightness.dark;
    final ink     = isNight ? CueColors.inkDark        : CueColors.inkPrimary;
    final amberLn = isNight ? CueColors.amber          : CueColors.amberDark;
    final divider = isNight ? CueColors.dividerDark    : CueColors.divider;

    return Container(
      decoration: BoxDecoration(
        border: Border(
            bottom: BorderSide(color: divider, width: CueSize.hairline)),
      ),
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Cue noticed eyebrow
          Row(
            children: [
              const SizedBox(
                width:  CueSize.cuttlefishEyebrow,
                height: CueSize.cuttlefishEyebrowSlot,
                child: CueCuttlefish(
                    size:  CueSize.cuttlefishEyebrow,
                    state: CueState.thinking),
              ),
              const SizedBox(width: CueGap.s8),
              Text(
                'CUE NOTICED',
                style: CueType.labelSmall.copyWith(color: amberLn),
              ),
              const SizedBox(width: CueGap.s12),
              Expanded(
                child: Container(
                    height: CueSize.hairline, color: divider)),
            ],
          ),
          const SizedBox(height: CueGap.s16),
          if (loading)
            _Skeleton(divider: divider)
          else if (errorText != null)
            Text(
              errorText!,
              style: CueType.bodyMedium
                  .copyWith(color: CueColors.coral),
            )
          else
            _renderThought(ink, amberLn),
          if (!loading &&
              errorText == null &&
              onThinkWithCue != null) ...[
            const SizedBox(height: CueGap.s16),
            _ThinkWithCueButton(onTap: onThinkWithCue!),
          ],
        ],
      ),
    );
  }

  Widget _renderThought(Color ink, Color amberLn) {
    final t  = thought   ?? '';
    final hl = highlight ?? '';
    if (t.isEmpty) return const SizedBox.shrink();

    if (hl.isEmpty || !t.contains(hl)) {
      return Text(t, style: CueType.displayMedium.copyWith(color: ink));
    }

    final idx    = t.indexOf(hl);
    final before = t.substring(0, idx);
    final after  = t.substring(idx + hl.length);
    return RichText(
      text: TextSpan(
        style: CueType.displayMedium.copyWith(color: ink),
        children: [
          TextSpan(text: before),
          TextSpan(
            text:  hl,
            style: CueType.displayMedium.copyWith(color: amberLn),
          ),
          TextSpan(text: after),
        ],
      ),
    );
  }
}

class _Skeleton extends StatelessWidget {
  final Color divider;
  const _Skeleton({required this.divider});
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Skeleton bar widths (280, 200) are intentionally non-token
        // magic numbers — sized to mimic two real lines of brief text.
        Container(
            width: 280, height: 18,
            decoration: BoxDecoration(
                color: divider,
                borderRadius: BorderRadius.circular(CueRadius.s3))),
        const SizedBox(height: CueGap.s8),
        Container(
            width: 200, height: 18,
            decoration: BoxDecoration(
                color: divider,
                borderRadius: BorderRadius.circular(CueRadius.s3))),
      ],
    );
  }
}

class _ThinkWithCueButton extends StatelessWidget {
  final VoidCallback onTap;
  const _ThinkWithCueButton({required this.onTap});
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: CueGap.s14, vertical: CueGap.s7),
        decoration: BoxDecoration(
          color: CueColors.inkPrimary,
          borderRadius: BorderRadius.circular(CueRadius.s20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width:  CueSize.cuttlefishThinkPill,
              height: CueSize.cuttlefishThinkPill,
              child: CueCuttlefish(
                  size:  CueSize.cuttlefishThinkPill,
                  state: CueState.idle),
            ),
            const SizedBox(width: CueGap.s6),
            Text('Think with Cue',
                style: CueType.labelLarge
                    .copyWith(color: CueColors.amber)),
          ],
        ),
      ),
    );
  }
}
