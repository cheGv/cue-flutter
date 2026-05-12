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

import '../theme/cue_color_scheme.dart';
import '../theme/cue_theme.dart';
import '../theme/cue_tokens.dart';
import '../theme/cue_typography.dart';
import 'cue_cuttlefish.dart';
import 'linked_evidence.dart';

const _briefUrl = 'https://cue-ai-proxy.onrender.com/generate-brief';

class BriefThoughtView extends StatefulWidget {
  /// Pre-built chart context (use buildChartContext from
  /// lib/utils/chart_context.dart). The widget POSTs this verbatim.
  final String       chartContext;
  /// Optional callback when "Think with Cue" is tapped.
  final VoidCallback? onThinkWithCue;
  /// Phase 5.3 B.3 — outer margin around the card chrome. Internal content
  /// padding is fixed inside BriefThoughtCard at (20, 16). Default applies
  /// only the spec'd bottom: 18; callers pass full EdgeInsets when they need
  /// horizontal margin or top spacing.
  final EdgeInsets   outerMargin;

  const BriefThoughtView({
    super.key,
    required this.chartContext,
    this.onThinkWithCue,
    this.outerMargin = const EdgeInsets.only(bottom: 18),
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
      outerMargin:    widget.outerMargin,
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
  // Phase 5.3 B.3 — see BriefThoughtView for semantics.
  final EdgeInsets   outerMargin;

  const BriefThoughtCard({
    super.key,
    this.thought,
    this.highlight,
    this.loading        = false,
    this.errorText,
    this.onThinkWithCue,
    this.outerMargin = const EdgeInsets.only(bottom: 18),
  });

  @override
  Widget build(BuildContext context) {
    final cue     = CueColorsResolved.of(context);
    final ink     = cue.textPrimary;
    final amberLn = cue.amber;
    // skeletonFill computed inline at _Skeleton call site below — uses
    // cue.borderHover for visible loading bars on neutral canvas.

    return Container(
      margin: outerMargin,
      decoration: BoxDecoration(
        color:        cue.bgCard,
        border:       Border.all(width: CueSize.hairline, color: cue.border),
        borderRadius: BorderRadius.circular(10),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
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
                'Cue · what\'s in the chart',
                style: TextStyle(
                  fontFamily:         'Iowan Old Style',
                  fontFamilyFallback: const ['Georgia', 'Charter', 'serif'],
                  fontStyle:          FontStyle.italic,
                  fontSize:           14,
                  fontWeight:         FontWeight.w500,
                  color:              amberLn,
                ),
              ),
              // Optional right-aligned timestamp via Spacer() + Text per spec
              // ("Inter regular 11px textMuted, 'just now' relative string").
              // Omitted for B.3 since the data isn't threaded through —
              // wire when timestamp source lands.
            ],
          ),
          const SizedBox(height: CueGap.s16),
          if (loading)
            // Phase 5.3 Round A.1.1 — skeleton fill uses borderHover (~37 RGB
            // levels above canvas) instead of border (~21 levels). Loading
            // bars were near-invisible against the neutral #0A0A0B canvas.
            _Skeleton(divider: cue.borderHover)
          else if (errorText != null)
            Text(
              errorText!,
              style: CueType.bodyMedium
                  .copyWith(color: CueColors.coral),
            )
          else
            _renderThought(ink),
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

  Widget _renderThought(Color ink) {
    final t  = thought   ?? '';
    final hl = highlight ?? '';
    if (t.isEmpty) return const SizedBox.shrink();

    // Phase 5.3 B.3 — Iowan Old Style italic 18/500 with -0.005em tracking.
    // Fallback chain mirrors _hero_pillar_frame.dart (the locked pattern).
    // Highlight phrase is split out and rendered via LinkedEvidence so the
    // semantic emphasis (olive underline + faint tint) replaces the pre-B.3
    // bright-amber TextSpan treatment. Match is case-insensitive; the
    // displayed substring is sliced from `t` so casing matches the prose.
    final headlineStyle = TextStyle(
      fontFamily:         'Iowan Old Style',
      fontFamilyFallback: const ['Georgia', 'Charter', 'serif'],
      fontStyle:          FontStyle.italic,
      fontSize:           18,
      fontWeight:         FontWeight.w500,
      height:             1.35,
      letterSpacing:      -0.09,  // -0.005em × 18
      color:              ink,
    );

    if (hl.isEmpty) {
      return ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child:       Text(t, style: headlineStyle),
      );
    }

    // Case-insensitive locate so highlight matches even when LLM returns a
    // casing that differs from the thought string. For ASCII clinical text
    // (the current and foreseeable case) lowerHl.length == hl.length and
    // the slice from `t` lines up correctly. For hypothetical future Unicode
    // cases (Indic script briefings, accented chars), toLowerCase() can
    // change string length — accept the limitation for B.3, proper
    // grapheme-cluster handling banked for i18n work.
    final lowerHl = hl.toLowerCase();
    final idx     = t.toLowerCase().indexOf(lowerHl);
    if (idx < 0) {
      return ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child:       Text(t, style: headlineStyle),
      );
    }
    final before     = t.substring(0, idx);
    final hlFromText = t.substring(idx, idx + lowerHl.length);
    final after      = t.substring(idx + lowerHl.length);
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 760),
      child: RichText(
        text: TextSpan(
          style: headlineStyle,
          children: [
            TextSpan(text: before),
            WidgetSpan(
              alignment: PlaceholderAlignment.baseline,
              baseline:  TextBaseline.alphabetic,
              child: LinkedEvidence(
                text:      hlFromText,
                type:      LinkedEvidenceType.data,
                textStyle: headlineStyle,
              ),
            ),
            TextSpan(text: after),
          ],
        ),
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
