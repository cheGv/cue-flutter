import 'package:cue/models/stg_session_metric.dart';
import 'package:cue/utils/sparkline_readout.dart';
import 'package:flutter_test/flutter_test.dart';

StgSessionMetric _m(double v, {String? unit}) => StgSessionMetric(
      id: 'm',
      stgId: 's',
      sessionId: 1,
      metricValue: v,
      metricLabel: 'x',
      metricUnit: unit,
      recordedAt: DateTime(2026, 5, 1),
    );

void main() {
  test('zero points → first-session prompt', () {
    expect(sparklineReadout([], 'PROMPTING'), 'first session will populate');
  });

  test('prompting levels map to phrases', () {
    expect(sparklineReadout([_m(5), _m(0)], 'PROMPTING'),
        'hand-over-hand → independent');
    expect(sparklineReadout([_m(4), _m(2)], 'SUPPORT LEVEL'),
        'partial physical → verbal cue');
  });

  test('accuracy / % formats with percent each side', () {
    expect(sparklineReadout([_m(40), _m(80)], 'ACCURACY'), '40% → 80%');
    expect(sparklineReadout([_m(50), _m(75)], 'ACCURACY %'), '50% → 75%');
  });

  test('frequency / count formats per session', () {
    expect(sparklineReadout([_m(3), _m(6)], 'FREQUENCY'),
        '3/session → 6/session');
    expect(sparklineReadout([_m(2), _m(5)], 'COUNT'), '2/session → 5/session');
  });

  test('default appends the unit once at the end', () {
    expect(sparklineReadout([_m(2, unit: 'reps'), _m(5, unit: 'reps')], 'REPS'),
        '2 → 5 reps');
    expect(sparklineReadout([_m(2), _m(5)], 'REPS'), '2 → 5');
  });

  test('single point', () {
    expect(sparklineReadout([_m(3)], 'PROMPTING'), 'first point: modeling');
    expect(sparklineReadout([_m(2, unit: 'reps')], 'REPS'),
        'first point: 2 reps');
  });
}
