import 'package:flutter/material.dart';

import '../../models/client_chart_state.dart';
import '../../theme/cue_color_scheme.dart';
import '../../theme/cue_text_styles.dart';
import '../../utils/markdown_strip.dart';
import 'chart_card.dart';

/// Narrator card — Cue's state-voice line on the bg-narrator ground with a 4px
/// left rail. Renders the brief sentence on its own (no "Status —" label); the
/// text is the deterministic brief passed as [aiText], or the computed
/// fallback. The widget stays pure; the screen owns the brief computation.
class ChartNarrator extends StatelessWidget {
  final ClientChartState state;
  final String clientName;

  /// AI-authored override (ChartNarratorService). When null and [loading] is
  /// true, an em-dash placeholder shows; otherwise the computed template.
  final String? aiText;
  final bool loading;

  const ChartNarrator({
    super.key,
    required this.state,
    required this.clientName,
    this.aiText,
    this.loading = false,
  });

  @override
  Widget build(BuildContext context) {
    final t = CueChartTokens.of(context);
    final ty = CueChartType.of(context);

    return CueChartCard(
      padding: EdgeInsets.zero,
      background: t.bgNarrator,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(width: 4, color: t.bgNarratorRail),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(21, 16, 24, 16),
                // The brief sentence stands on its own — no "Status —" label.
                child: Text.rich(
                  TextSpan(children: [
                    TextSpan(text: _displayText(), style: ty.narratorBody),
                  ]),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _displayText() {
    final ai = aiText?.trim();
    // The model occasionally emits inline markdown (*italics*, **bold**). This
    // band renders as plain text, so strip the markers rather than show them
    // literally. The computed fallback is plain prose — no stripping needed.
    if (ai != null && ai.isNotEmpty) return stripInlineMarkdown(ai);
    if (loading) return '—';
    return _computed();
  }

  String _computed() {
    if (state.activeStgCount == 0 && state.ltgCount == 0) {
      return "$clientName's long-term goal is not yet authored. "
          'Substrate is ready beneath.';
    }
    if (state.activeStgCount > 0) {
      return "$clientName's last session worked on the active care plan — "
          '${state.activeStgCount} STGs in motion.';
    }
    return "$clientName's long-term goal is set — "
        'short-term goals not yet authored.';
  }
}
