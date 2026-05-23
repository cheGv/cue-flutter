import 'package:flutter_test/flutter_test.dart';
import 'package:cue/models/stg_session_metric.dart';

void main() {
  final baseJson = <String, dynamic>{
    'id': 'm-001',
    'stg_id': 'stg-001',
    'session_id': 42, // bigint — matches sessions.id type
    'metric_value': 3,
    'metric_label': 'prompting level',
    'metric_unit': 'level',
    'recorded_at': '2026-05-21T09:30:00.000Z',
  };

  group('StgSessionMetric.fromJson', () {
    test('parses all fields', () {
      final m = StgSessionMetric.fromJson(baseJson);
      expect(m.id, 'm-001');
      expect(m.stgId, 'stg-001');
      expect(m.sessionId, 42);
      expect(m.sessionId, isA<int>());
      expect(m.metricValue, 3.0);
      expect(m.metricValue, isA<double>());
      expect(m.metricLabel, 'prompting level');
      expect(m.metricUnit, 'level');
      expect(m.recordedAt, DateTime.parse('2026-05-21T09:30:00.000Z'));
    });

    test('session_id coerces num (bigint) to int', () {
      final json = Map<String, dynamic>.from(baseJson)..['session_id'] = 42.0;
      final m = StgSessionMetric.fromJson(json);
      expect(m.sessionId, 42);
      expect(m.sessionId, isA<int>());
    });

    test('metric_value coerces int to double', () {
      final json = Map<String, dynamic>.from(baseJson)..['metric_value'] = 80;
      final m = StgSessionMetric.fromJson(json);
      expect(m.metricValue, 80.0);
      expect(m.metricValue, isA<double>());
    });

    test('null metric_unit allowed', () {
      final json = Map<String, dynamic>.from(baseJson)..['metric_unit'] = null;
      expect(StgSessionMetric.fromJson(json).metricUnit, isNull);
    });
  });

  group('StgSessionMetric.toJson', () {
    test('uses DB column names', () {
      final json = StgSessionMetric.fromJson(baseJson).toJson();
      expect(json['stg_id'], 'stg-001');
      expect(json['session_id'], 42);
      expect(json['metric_value'], 3.0);
      expect(json['metric_label'], 'prompting level');
      expect(json.containsKey('sessionId'), isFalse);
      expect(json.containsKey('metricValue'), isFalse);
    });

    test('omits null metric_unit', () {
      final m = StgSessionMetric.fromJson(
          Map<String, dynamic>.from(baseJson)..['metric_unit'] = null);
      expect(m.toJson().containsKey('metric_unit'), isFalse);
    });

    test('round-trips fromJson -> toJson -> fromJson', () {
      final m = StgSessionMetric.fromJson(baseJson);
      final r = StgSessionMetric.fromJson(m.toJson());
      expect(r.sessionId, m.sessionId);
      expect(r.metricValue, m.metricValue);
      expect(r.metricLabel, m.metricLabel);
      expect(r.recordedAt, m.recordedAt);
    });
  });
}
