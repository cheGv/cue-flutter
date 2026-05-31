import 'package:cue/models/long_term_goal.dart';
import 'package:cue/models/short_term_goal.dart';
import 'package:flutter_test/flutter_test.dart';

// Goal lifecycle (archive + status change). Verifies the model/filter logic the
// chart relies on:
//   (a) active filter excludes archived AND non-active goals
//   (b) archive sets deleted_at; undo (restore) nulls it  [field semantics]
//   (c) status change keeps the goal visible but out of the active set
//   (d) LTG archive cascades to STGs reversibly (shared-timestamp rule)
//
// The repository's DB writes are exercised against the live sandbox separately;
// here we lock down the deterministic model + selection logic.

ShortTermGoal _stg({
  required String id,
  String ltgId = 'ltg-1',
  StgStatus status = StgStatus.active,
  DateTime? deletedAt,
}) =>
    ShortTermGoal(
      id: id,
      longTermGoalId: ltgId,
      clientId: 'c1',
      userId: 'u1',
      specific: 'Goal $id',
      status: status,
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
      deletedAt: deletedAt,
    );

void main() {
  // ── (a) Active filter excludes archived + non-active ──────────────────────

  group('active filter', () {
    final ts = DateTime(2026, 5, 29, 12);
    final goals = [
      _stg(id: 'active-live'),
      _stg(id: 'achieved-live', status: StgStatus.achieved),
      _stg(id: 'discontinued-live', status: StgStatus.discontinued),
      _stg(id: 'active-archived', deletedAt: ts),
      _stg(id: 'achieved-archived', status: StgStatus.achieved, deletedAt: ts),
    ];

    test('isActive ⇔ status==active AND deleted_at IS NULL', () {
      final active = goals.where((g) => g.isActive).map((g) => g.id).toSet();
      expect(active, {'active-live'});
      // An active-status goal that is archived is NOT active.
      expect(_stg(id: 'x', deletedAt: ts).isActive, isFalse);
      // A live achieved goal is NOT active either.
      expect(_stg(id: 'y', status: StgStatus.achieved).isActive, isFalse);
    });

    test('the chart split buckets are mutually exclusive + exclude archived',
        () {
      // Mirror the screen: allStgs already excludes archived (repo filters
      // deleted_at); split the live remainder by status.
      final live = goals.where((g) => !g.isArchived).toList();
      final active =
          live.where((g) => !g.status.isCompleted && !g.status.isClosed);
      final completed = live.where((g) => g.status.isCompleted);
      final closed = live.where((g) => g.status.isClosed);

      expect(active.map((g) => g.id), ['active-live']);
      expect(completed.map((g) => g.id), ['achieved-live']);
      expect(closed.map((g) => g.id), ['discontinued-live']);
      // Neither archived row appears in any visible bucket.
      final visible = [...active, ...completed, ...closed].map((g) => g.id);
      expect(visible, isNot(contains('active-archived')));
      expect(visible, isNot(contains('achieved-archived')));
    });
  });

  // ── (b) Archive field semantics: deleted_at set ⇄ null ────────────────────

  group('archive field semantics', () {
    test('a row with deleted_at parses as archived (hidden, not active)', () {
      final archived = ShortTermGoal.fromJson({
        'id': 's1',
        'long_term_goal_id': 'l1',
        'client_id': 'c1',
        'user_id': 'u1',
        'status': 'active',
        'created_at': '2026-01-01T00:00:00Z',
        'updated_at': '2026-01-01T00:00:00Z',
        'deleted_at': '2026-05-29T12:00:00Z',
      });
      expect(archived.isArchived, isTrue);
      expect(archived.isActive, isFalse);
      expect(archived.deletedAt, DateTime.parse('2026-05-29T12:00:00Z'));
    });

    test('undo (deleted_at back to null) parses as live + active again', () {
      final restored = ShortTermGoal.fromJson({
        'id': 's1',
        'long_term_goal_id': 'l1',
        'client_id': 'c1',
        'user_id': 'u1',
        'status': 'active',
        'created_at': '2026-01-01T00:00:00Z',
        'updated_at': '2026-01-01T00:00:00Z',
        'deleted_at': null,
      });
      expect(restored.isArchived, isFalse);
      expect(restored.isActive, isTrue);
      expect(restored.deletedAt, isNull);
    });

    test('deleted_at round-trips through toJson when set, omitted when null',
        () {
      final base = {
        'id': 's1',
        'long_term_goal_id': 'l1',
        'client_id': 'c1',
        'user_id': 'u1',
        'status': 'active',
        'created_at': '2026-01-01T00:00:00.000Z',
        'updated_at': '2026-01-01T00:00:00.000Z',
        'deleted_at': '2026-05-29T12:00:00.000Z',
      };
      final out = ShortTermGoal.fromJson(base).toJson();
      expect(out['deleted_at'], '2026-05-29T12:00:00.000Z');

      final live = Map<String, dynamic>.from(base)..['deleted_at'] = null;
      expect(ShortTermGoal.fromJson(live).toJson().containsKey('deleted_at'),
          isFalse);
    });
  });

  // ── (c) Status change keeps goal visible but inactive ─────────────────────

  group('status change keeps goal visible but inactive', () {
    test('marking achieved leaves it visible (not archived), out of active',
        () {
      final active = _stg(id: 's1');
      expect(active.isActive, isTrue);
      final achieved = active.copyWith(status: StgStatus.achieved);
      expect(achieved.isActive, isFalse); // out of active set
      expect(achieved.isArchived, isFalse); // still visible
      expect(achieved.status.isCompleted, isTrue); // → Completed section
    });

    test('marking discontinued routes to Closed, still visible', () {
      final closed = _stg(id: 's1').copyWith(status: StgStatus.discontinued);
      expect(closed.isActive, isFalse);
      expect(closed.isArchived, isFalse);
      expect(closed.status.isClosed, isTrue);
    });

    test("'achieved' and 'discontinued' are first-class (not active fallback)",
        () {
      expect(StgStatus.fromString('achieved'), StgStatus.achieved);
      expect(StgStatus.fromString('discontinued'), StgStatus.discontinued);
      expect(StgStatus.fromString('active'), StgStatus.active);
      // legacy 'mastered' counts as completed
      expect(StgStatus.fromString('mastered').isCompleted, isTrue);
      // genuinely-unknown still degrades to active (never throws)
      expect(StgStatus.fromString('nonsense'), StgStatus.active);
    });
  });

  // ── (d) LTG archive cascade is reversible (shared-timestamp rule) ──────────
  //
  // Models exactly the repo's selection predicates:
  //   archiveForLtg  → stamp `ts` on children WHERE deleted_at IS NULL
  //   restoreForLtg  → null deleted_at on children WHERE deleted_at == ts
  // The invariant: a child archived INDEPENDENTLY (different ts) must survive an
  // LTG restore.

  group('LTG archive cascade reversibility', () {
    test('archive stamps live children; restore re-activates exactly those',
        () {
      final earlier = DateTime(2026, 5, 1); // a child archived on its own
      var children = [
        _stg(id: 'a'),
        _stg(id: 'b'),
        _stg(id: 'c-prearchived', deletedAt: earlier),
      ];

      // archiveForLtg(ltg, ts): stamp ts where deleted_at == null
      final ts = DateTime(2026, 5, 29, 12);
      children = children
          .map((s) => s.deletedAt == null ? s.copyWith(deletedAt: ts) : s)
          .toList();

      // All three are now archived; a & b at ts, c at the earlier ts.
      expect(children.where((s) => s.isArchived).length, 3);
      expect(children.firstWhere((s) => s.id == 'c-prearchived').deletedAt,
          earlier);

      // restoreForLtg(ltg, ts): null deleted_at where deleted_at == ts
      children = children
          .map((s) =>
              s.deletedAt == ts ? _stg(id: s.id, ltgId: s.longTermGoalId) : s)
          .toList();

      final live = children.where((s) => !s.isArchived).map((s) => s.id).toSet();
      // a & b restored; the independently-archived c stays archived.
      expect(live, {'a', 'b'});
      expect(children.firstWhere((s) => s.id == 'c-prearchived').isArchived,
          isTrue);
    });
  });

  // ── LtgStatus + LongTermGoal model ────────────────────────────────────────

  group('LtgStatus', () {
    test('active / achieved / discontinued are first-class', () {
      expect(LtgStatus.fromString('active'), LtgStatus.active);
      expect(LtgStatus.fromString('achieved'), LtgStatus.achieved);
      expect(LtgStatus.fromString('discontinued'), LtgStatus.discontinued);
    });

    test('unknown / null degrade to active (never throws)', () {
      expect(LtgStatus.fromString('garbage'), LtgStatus.active);
      expect(LtgStatus.fromString(null), LtgStatus.active);
    });

    test('all values round-trip through toJson/fromString', () {
      for (final s in LtgStatus.values) {
        expect(LtgStatus.fromString(s.toJson()), s);
      }
    });
  });

  group('LongTermGoal model', () {
    final baseJson = <String, dynamic>{
      'id': 'ltg-1',
      'client_id': 'c1',
      'user_id': 'u1',
      'domain': 'voice',
      'goal_text': 'Improve vocal function across contexts',
      'status': 'active',
      'sequence_num': 1,
      'time_frame_weeks': 24,
      'created_at': '2026-04-01T10:00:00.000Z',
      'updated_at': '2026-04-19T10:00:00.000Z',
    };

    test('parses + round-trips, deleted_at null ⇒ active', () {
      final ltg = LongTermGoal.fromJson(baseJson);
      expect(ltg.status, LtgStatus.active);
      expect(ltg.isActive, isTrue);
      expect(ltg.isArchived, isFalse);
      expect(ltg.toJson().containsKey('deleted_at'), isFalse);
    });

    test('archived LTG: deleted_at set ⇒ not active, round-trips', () {
      final json = Map<String, dynamic>.from(baseJson)
        ..['deleted_at'] = '2026-05-29T12:00:00.000Z';
      final ltg = LongTermGoal.fromJson(json);
      expect(ltg.isArchived, isTrue);
      expect(ltg.isActive, isFalse);
      expect(ltg.toJson()['deleted_at'], '2026-05-29T12:00:00.000Z');
    });

    test('achieved status round-trips and reports completed', () {
      final json = Map<String, dynamic>.from(baseJson)..['status'] = 'achieved';
      final ltg = LongTermGoal.fromJson(json);
      expect(ltg.status, LtgStatus.achieved);
      expect(ltg.status.isCompleted, isTrue);
      expect(ltg.isActive, isFalse);
      expect(ltg.toJson()['status'], 'achieved');
    });
  });
}
