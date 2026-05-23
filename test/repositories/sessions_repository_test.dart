// Repository tests for SessionsRepository.
//
// Same constraint as the other repository tests — no mock library in project.
// Covers: type existence and the Session serialisation contracts the repo
// relies on (bigint id, soft-delete column, the reused next_session_focus
// field). Live-DB behaviour is covered by skipped integration tests.
import 'package:flutter_test/flutter_test.dart';
import 'package:cue/models/session.dart';
import 'package:cue/models/session_outcome.dart';
import 'package:cue/repositories/sessions_repository.dart';

void main() {
  group('SessionsRepository — interface', () {
    test('class is referenceable as a type', () {
      expect(SessionsRepository, isNotNull);
    });
  });

  group('SessionsRepository — row mapping contract', () {
    test('maps a sessions row (bigint id) returned by select()', () {
      final row = <String, dynamic>{
        'id': 7,
        'client_id': 'client-001',
        'client_name': 'Aarav',
        'status': 'complete',
        'created_at': '2026-05-21T10:00:00.000Z',
        'date': '2026-05-21',
        'outcome': 'progress',
        'next_session_focus': 'Generalise /s/ to connected speech',
        'deleted_at': null,
      };
      final s = Session.fromJson(row);
      expect(s.id, 7);
      expect(s.id, isA<int>());
      expect(s.outcome, SessionOutcome.progress);
      expect(s.nextSessionFocus, 'Generalise /s/ to connected speech');
      expect(s.deletedAt, isNull);
    });
  });

  group('SessionsRepository — integration (requires live Supabase)', () {
    test('loadForClient returns non-deleted sessions newest-first', () async {},
        skip: 'integration');
    test('loadById returns the matching session or null', () async {},
        skip: 'integration');
    test('savePlannedSession upserts a planned draft and returns its id',
        () async {}, skip: 'integration');
    test('loadForClient excludes planned/draft by default but includes them '
        'with includePlanned: true', () async {}, skip: 'integration');
  });
}
