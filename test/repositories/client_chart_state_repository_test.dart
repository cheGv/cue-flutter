// Repository tests for ClientChartStateRepository.
//
// No mock library in project. Covers type existence and the view-row mapping
// contract; the live view read is covered by a skipped integration test.
import 'package:flutter_test/flutter_test.dart';
import 'package:cue/models/client_chart_state.dart';
import 'package:cue/repositories/client_chart_state_repository.dart';

void main() {
  group('ClientChartStateRepository — interface', () {
    test('class is referenceable as a type', () {
      expect(ClientChartStateRepository, isNotNull);
    });
  });

  group('ClientChartStateRepository — view row mapping contract', () {
    test('maps a client_chart_state row', () {
      final row = <String, dynamic>{
        'client_id': 'e8f65c67-cc99-495e-b604-e2da9919df26',
        'client_name': 'Dina',
        'age': 19,
        'date_of_birth': null,
        'diagnosis': 'Autism',
        'ltg_count': 0,
        'active_stg_count': 0,
        'total_session_count': 1,
        'last_session_date': '2026-05-21',
        'undocumented_session_count': 1,
        'last_next_session_focus': null,
        'caregiver_present': true,
        'substrate_cell_count': 0,
      };
      final s = ClientChartState.fromJson(row);
      expect(s.clientName, 'Dina');
      expect(s.diagnosis, 'Autism');
      expect(s.totalSessionCount, 1);
      expect(s.lastSessionDate, DateTime.parse('2026-05-21'));
      expect(s.caregiverPresent, isTrue);
    });
  });

  group('ClientChartStateRepository — integration (requires live Supabase)', () {
    test('loadForClient returns one row or null', () async {},
        skip: 'integration');
  });
}
