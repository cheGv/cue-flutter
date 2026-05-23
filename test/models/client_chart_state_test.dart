import 'package:flutter_test/flutter_test.dart';
import 'package:cue/models/client_chart_state.dart';

void main() {
  // Mirrors a real row from the client_chart_state view (Aarav, the
  // substrate-only fixture: 18 cells, no goals, no sessions).
  final baseJson = <String, dynamic>{
    'client_id': '25f4d2e8-e0e5-4a5c-981b-132d40db77ca',
    'client_name': 'Aarav',
    'age': 3,
    'date_of_birth': null,
    'diagnosis': null,
    'ltg_count': 0,
    'active_stg_count': 0,
    'total_session_count': 0,
    'last_session_date': null,
    'undocumented_session_count': 0,
    'last_next_session_focus': null,
    'caregiver_present': false,
    'substrate_cell_count': 18,
  };

  group('ClientChartState.fromJson', () {
    test('parses an empty (substrate-only) client row', () {
      final s = ClientChartState.fromJson(baseJson);
      expect(s.clientId, startsWith('25f4d2e8'));
      expect(s.clientName, 'Aarav');
      expect(s.age, 3);
      expect(s.dateOfBirth, isNull);
      expect(s.diagnosis, isNull);
      expect(s.ltgCount, 0);
      expect(s.activeStgCount, 0);
      expect(s.totalSessionCount, 0);
      expect(s.lastSessionDate, isNull);
      expect(s.undocumentedSessionCount, 0);
      expect(s.lastNextSessionFocus, isNull);
      expect(s.caregiverPresent, isFalse);
      expect(s.substrateCellCount, 18);
    });

    test('parses a populated client row', () {
      final json = Map<String, dynamic>.from(baseJson)
        ..['client_name'] = 'Dina'
        ..['age'] = 19
        ..['diagnosis'] = 'Autism'
        ..['total_session_count'] = 3
        ..['undocumented_session_count'] = 2
        ..['last_session_date'] = '2026-05-21'
        ..['last_next_session_focus'] = 'Introduce core board at snack time'
        ..['caregiver_present'] = true;
      final s = ClientChartState.fromJson(json);
      expect(s.diagnosis, 'Autism');
      expect(s.totalSessionCount, 3);
      expect(s.undocumentedSessionCount, 2);
      expect(s.lastSessionDate, DateTime.parse('2026-05-21'));
      expect(s.lastNextSessionFocus, 'Introduce core board at snack time');
      expect(s.caregiverPresent, isTrue);
    });

    test('counts coerce num (bigint) to int', () {
      final json = Map<String, dynamic>.from(baseJson)
        ..['ltg_count'] = 2.0
        ..['substrate_cell_count'] = 18.0;
      final s = ClientChartState.fromJson(json);
      expect(s.ltgCount, 2);
      expect(s.substrateCellCount, 18);
    });

    test('missing counts default to 0; missing caregiver_present to false', () {
      final s = ClientChartState.fromJson(
          <String, dynamic>{'client_id': 'c-1', 'client_name': 'X'});
      expect(s.age, 0);
      expect(s.ltgCount, 0);
      expect(s.totalSessionCount, 0);
      expect(s.caregiverPresent, isFalse);
    });
  });

  group('ClientChartState.toJson', () {
    test('uses view column names; omits null optionals', () {
      final json = ClientChartState.fromJson(baseJson).toJson();
      expect(json['client_id'], startsWith('25f4d2e8'));
      expect(json['substrate_cell_count'], 18);
      expect(json['caregiver_present'], isFalse);
      expect(json.containsKey('date_of_birth'), isFalse); // null -> omitted
      expect(json.containsKey('last_session_date'), isFalse);
      expect(json.containsKey('clientId'), isFalse);
    });
  });
}
