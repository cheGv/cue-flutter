import 'package:flutter/material.dart';

import '../../models/client_chart_state.dart';
import '../../theme/cue_color_scheme.dart';
import '../../theme/cue_text_styles.dart';
import 'chart_card.dart';
import 'chart_format.dart';

/// Footer card — fine-print meta on the bg-card-head ground: last seen,
/// caregiver status, and the session count + trajectory trend.
class ChartFooterMeta extends StatelessWidget {
  final ClientChartState state;
  final bool sessionToday;

  const ChartFooterMeta({
    super.key,
    required this.state,
    required this.sessionToday,
  });

  @override
  Widget build(BuildContext context) {
    final t = CueChartTokens.of(context);
    final ty = CueChartType.of(context);

    final lastSeen = state.lastSessionDate == null
        ? 'Not yet seen'
        : 'Last seen ${relativeLastSeen(state.lastSessionDate)}';
    final n = state.totalSessionCount;

    final items = <Widget>[
      if (sessionToday) _item(t, ty, Icons.event_outlined, 'Session today'),
      _item(t, ty, Icons.schedule_outlined, lastSeen),
      _item(
        t,
        ty,
        Icons.person_outline,
        'Caregiver ${state.caregiverPresent ? 'present' : 'unverified'}',
      ),
      _item(
        t,
        ty,
        Icons.insights_outlined,
        '$n ${n == 1 ? 'session' : 'sessions'} · ${sessionTrend(n)} trajectory',
      ),
    ];

    return CueChartCard(
      background: t.bgCardHead,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      child: Wrap(spacing: 20, runSpacing: 10, children: items),
    );
  }

  Widget _item(
      CueChartTokens t, CueChartType ty, IconData icon, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: t.textTertiary),
        const SizedBox(width: 6),
        Text(label, style: ty.footerItem),
      ],
    );
  }
}
