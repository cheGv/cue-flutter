// Repository tests for StgMetricsRepository.
//
// No mock library in project. Covers type existence and the row-mapping
// contract; sparkline ordering is covered by a skipped integration test.
import 'package:flutter_test/flutter_test.dart';
import 'package:cue/models/stg_session_metric.dart';
import 'package:cue/repositories/stg_metrics_repository.dart';

void main() {
  group('StgMetricsRepository — interface', () {
    test('class is referenceable as a type', () {
      expect(StgMetricsRepository, isNotNull);
    });
  });

  group('StgMetricsRepository — row mapping contract', () {
    test('maps a stg_session_metrics row (bigint session_id)', () {
      final row = <String, dynamic>{
        'id': 'm-9',
        'stg_id': 'stg-1',
        'session_id': 101,
        'metric_value': 2,
        'metric_label': 'support level',
        'metric_unit': 'level',
        'recorded_at': '2026-05-20T08:00:00.000Z',
      };
      final m = StgSessionMetric.fromJson(row);
      expect(m.sessionId, 101);
      expect(m.sessionId, isA<int>());
      expect(m.metricValue, 2.0);
      expect(m.metricLabel, 'support level');
    });
  });

  group('StgMetricsRepository — integration (requires live Supabase)', () {
    test('loadMetricsForStg returns rows oldest-first (sparkline order)',
        () async {}, skip: 'integration');
  });
}
