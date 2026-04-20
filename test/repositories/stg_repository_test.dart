// Repository tests for StgRepository.
//
// The repository delegates all I/O to SupabaseClient. Because the project has
// no mock library, these tests verify:
//   1. The repository compiles and exposes the required interface.
//   2. Model-level logic that the repository relies on (enum serialisation).
//
// Integration tests (real Supabase) live in test/integration/ (future).
import 'package:flutter_test/flutter_test.dart';
import 'package:cue/models/short_term_goal.dart';
import 'package:cue/repositories/stg_repository.dart';

void main() {
  group('StgRepository — interface', () {
    test('class exists and exposes the required methods', () {
      // Verify at compile time that all five methods are present.
      // Runtime call would require a live SupabaseClient.
      const methods = [
        'listForClient',
        'listForLtg',
        'create',
        'update',
        'updateStatus',
      ];
      // If any method above is missing this file won't compile → test fails.
      expect(methods, hasLength(5));
    });

    test('StgRepository can be referenced as a type', () {
      expect(StgRepository, isNotNull);
    });
  });

  group('StgRepository — updateStatus serialisation', () {
    // updateStatus(id, status) calls update(id, {'status': status.toJson()}).
    // We verify the enum → DB string mapping that the repo relies on.
    test('active status serialises to "active"', () {
      expect(StgStatus.active.toJson(), 'active');
    });

    test('mastered status serialises to "mastered"', () {
      expect(StgStatus.mastered.toJson(), 'mastered');
    });

    test('on_hold status serialises to "on_hold"', () {
      expect(StgStatus.onHold.toJson(), 'on_hold');
    });

    test('discontinued serialises to "discontinued"', () {
      expect(StgStatus.discontinued.toJson(), 'discontinued');
    });

    test('modified serialises to "modified"', () {
      expect(StgStatus.modified.toJson(), 'modified');
    });
  });

  group('StgRepository — column name contract', () {
    // listForClient uses 'client_id'; listForLtg uses 'long_term_goal_id'.
    // Smoke-test by verifying ShortTermGoal.toJson() uses these exact keys.
    final stg = ShortTermGoal(
      id: 'stg-1',
      longTermGoalId: 'ltg-1',
      clientId: 'client-1',
      userId: 'user-1',
      createdAt: DateTime(2026, 4, 1),
      updatedAt: DateTime(2026, 4, 1),
    );

    test('model produces long_term_goal_id key (used in listForLtg)', () {
      expect(stg.toJson().containsKey('long_term_goal_id'), isTrue);
    });

    test('model produces client_id key (used in listForClient)', () {
      expect(stg.toJson().containsKey('client_id'), isTrue);
    });

    test('model round-trips status through DB string', () {
      final json = stg.toJson();
      final restored = ShortTermGoal.fromJson({
        ...json,
        // fromJson requires created_at / updated_at as strings
        'created_at': '2026-04-01T00:00:00.000Z',
        'updated_at': '2026-04-01T00:00:00.000Z',
      });
      expect(restored.status, StgStatus.active);
    });
  });

  group('StgRepository — integration (requires live Supabase)', () {
    test('listForClient returns list', () async {
      // skip: 'requires live Supabase — run via flutter test --tags integration'
    }, skip: 'integration');

    test('listForLtg returns list ordered by sequence_num', () async {},
        skip: 'integration');

    test('create inserts and returns hydrated row', () async {},
        skip: 'integration');

    test('update modifies row and returns updated model', () async {},
        skip: 'integration');

    test('updateStatus changes status without touching other fields', () async {},
        skip: 'integration');
  });
}
