import 'package:flutter/material.dart';

import '../../models/client_chart_state.dart';
import '../../theme/cue_color_scheme.dart';
import '../../theme/cue_text_styles.dart';
import 'chart_card.dart';
import 'chart_format.dart';

/// Header card — eyebrow (regular sans, not uppercase), hero name (Inter
/// 30/700), and meta line with separator dots + bold values. Read-only.
/// Recall is owned by the global bottom-right launcher (⌘K).
class ChartHeader extends StatelessWidget {
  final ClientChartState state;
  final DateTime? firstSessionDate;
  final bool sessionToday;
  final bool isCompact;

  const ChartHeader({
    super.key,
    required this.state,
    required this.firstSessionDate,
    required this.sessionToday,
    required this.isCompact,
  });

  @override
  Widget build(BuildContext context) {
    final t = CueChartTokens.of(context);
    final ty = CueChartType.of(context);

    return CueChartCard(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _eyebrow(t, ty),
          Text(state.clientName, style: ty.hero),
          const SizedBox(height: 10),
          _meta(t, ty),
        ],
      ),
    );
  }

  Widget _eyebrow(CueChartTokens t, CueChartType ty) {
    final segs = <String>[];
    if (state.totalSessionCount > 0 && firstSessionDate != null) {
      segs.add('In care since ${durationSince(firstSessionDate!)}');
    }
    if (state.lastSessionDate != null) {
      segs.add('Last seen ${relativeLastSeen(state.lastSessionDate)}');
    } else if (sessionToday) {
      segs.add('Session today');
    }
    if (segs.isEmpty) return const SizedBox(height: 2);
    final sep = TextSpan(text: '   ·   ', style: ty.eyebrow.copyWith(color: t.textFaint));
    final spans = <InlineSpan>[];
    for (var i = 0; i < segs.length; i++) {
      if (i > 0) spans.add(sep);
      spans.add(TextSpan(text: segs[i], style: ty.eyebrow));
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text.rich(TextSpan(children: spans)),
    );
  }

  Widget _meta(CueChartTokens t, CueChartType ty) {
    final sep = TextSpan(text: '   ·   ', style: ty.meta.copyWith(color: t.textFaint));
    final spans = <InlineSpan>[
      TextSpan(text: '${state.age} years', style: ty.metaStrong),
    ];
    final dx = state.diagnosis?.trim();
    if (dx != null && dx.isNotEmpty) {
      spans.add(TextSpan(text: ' · $dx', style: ty.meta));
    }
    spans.add(sep);
    final n = state.totalSessionCount;
    spans
      ..add(TextSpan(text: '$n', style: ty.metaStrong))
      ..add(TextSpan(text: n == 1 ? ' session' : ' sessions', style: ty.meta));
    if (state.substrateCellCount > 0) {
      spans
        ..add(sep)
        ..add(TextSpan(text: '${state.substrateCellCount}', style: ty.metaStrong))
        ..add(TextSpan(text: ' substrate cells', style: ty.meta));
    }
    return Text.rich(TextSpan(children: spans));
  }
}
