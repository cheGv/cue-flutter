// Phase B — sparkline readout: maps the first/last metric values to a clinical
// phrase shown to the right of the in-focus STG sparkline.
import '../models/stg_session_metric.dart';

String sparklineReadout(List<StgSessionMetric> metrics, String label) {
  if (metrics.isEmpty) return 'first session will populate';

  final l = label.toUpperCase();
  final first = metrics.first.metricValue;
  final last = metrics.last.metricValue;
  final unit = metrics.first.metricUnit;

  final isLevel = l.contains('PROMPTING') || l.contains('SUPPORT');
  final isPct = l.contains('ACCURACY') || l.contains('%');
  final isFreq = l.contains('FREQUENCY') || l.contains('COUNT');
  final isDefault = !isLevel && !isPct && !isFreq;

  String fmt(double v) {
    if (isLevel) return _promptLevel(v);
    if (isPct) return '${_n(v)}%';
    if (isFreq) return '${_n(v)}/session';
    return _n(v);
  }

  if (metrics.length == 1) {
    final p = fmt(first);
    return isDefault && unit != null ? 'first point: $p $unit' : 'first point: $p';
  }

  final arrow = '${fmt(first)} → ${fmt(last)}';
  return isDefault && unit != null ? '$arrow $unit' : arrow;
}

// Support/prompting hierarchy: 5 (most support) → 0 (independent).
String _promptLevel(double v) => switch (v.round()) {
      5 => 'hand-over-hand',
      4 => 'partial physical',
      3 => 'modeling',
      2 => 'verbal cue',
      1 => 'indirect verbal',
      0 => 'independent',
      _ => _n(v),
    };

String _n(double v) =>
    v == v.roundToDouble() ? v.toInt().toString() : v.toString();
