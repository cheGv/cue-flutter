import 'package:flutter_test/flutter_test.dart';
import 'package:cue/models/session.dart';
import 'package:cue/models/session_outcome.dart';

void main() {
  Map<String, dynamic> baseJson() => <String, dynamic>{
        'id': 42,
        'client_id': 'client-001',
        'client_name': 'Aarav',
        'status': 'complete',
        'date': '2026-05-21',
        'created_at': '2026-05-21T10:00:00.000Z',
        'outcome': 'plan_revised',
        'next_session_focus': 'Introduce core board at snack time',
        'clinician_attested': false,
      };

  group('Session.fromJson', () {
    test('parses identity and bigint id as int', () {
      final s = Session.fromJson(baseJson());
      expect(s.id, 42);
      expect(s.id, isA<int>());
      expect(s.clientId, 'client-001');
      expect(s.clientName, 'Aarav');
      expect(s.status, 'complete');
    });

    test('id coerces num (bigint) to int', () {
      expect(Session.fromJson(baseJson()..['id'] = 42.0).id, 42);
    });

    test('parses the outcome enum', () {
      expect(Session.fromJson(baseJson()).outcome, SessionOutcome.planRevised);
    });

    test('unknown outcome -> null', () {
      expect(Session.fromJson(baseJson()..['outcome'] = 'setback').outcome,
          isNull);
    });

    test('reads next_session_focus (the plan-forward seed)', () {
      expect(Session.fromJson(baseJson()).nextSessionFocus,
          'Introduce core board at snack time');
    });

    test('parses the session date', () {
      expect(Session.fromJson(baseJson()).date, DateTime.parse('2026-05-21'));
    });

    test('barriers default to false when absent', () {
      final s = Session.fromJson(baseJson());
      expect(s.barrierMotor, isFalse);
      expect(s.barrierDeviceAccess, isFalse);
    });

    test('barriers parse when present', () {
      final s = Session.fromJson(
          baseJson()..['barrier_motor'] = true..['barrier_sensory'] = true);
      expect(s.barrierMotor, isTrue);
      expect(s.barrierSensory, isTrue);
      expect(s.barrierCognitive, isFalse);
    });

    test('handles null date and absent outcome', () {
      final s = Session.fromJson(baseJson()
        ..['date'] = null
        ..remove('outcome'));
      expect(s.date, isNull);
      expect(s.outcome, isNull);
    });

    test('nullable clinician_attested preserved', () {
      expect(
          Session.fromJson(baseJson()..['clinician_attested'] = null)
              .clinicianAttested,
          isNull);
      expect(Session.fromJson(baseJson()).clinicianAttested, isFalse);
    });
  });

  group('Session.toJson', () {
    test('uses DB column names and serialises outcome', () {
      final json = Session.fromJson(baseJson()).toJson();
      expect(json['client_id'], 'client-001');
      expect(json['outcome'], 'plan_revised');
      expect(json['next_session_focus'], 'Introduce core board at snack time');
      expect(json.containsKey('clientId'), isFalse);
    });

    test('formats the date column as yyyy-MM-dd (not a timestamp)', () {
      expect(Session.fromJson(baseJson()).toJson()['date'], '2026-05-21');
    });

    test('omits outcome when null', () {
      final json = Session.fromJson(baseJson()..remove('outcome')).toJson();
      expect(json.containsKey('outcome'), isFalse);
    });

    test('always includes the NOT NULL barrier booleans', () {
      final json = Session.fromJson(baseJson()).toJson();
      expect(json['barrier_motor'], isFalse);
      expect(json.containsKey('barrier_device_access'), isTrue);
    });
  });
}
