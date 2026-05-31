import 'package:cue/models/client_brief_signals.dart';
import 'package:cue/models/session.dart';
import 'package:cue/models/short_term_goal.dart';
import 'package:flutter_test/flutter_test.dart';

// Layer 2 — signal computation. Pure function, so fully unit-testable.

final _now = DateTime(2026, 5, 29, 12);
DateTime _ago(int days) => _now.subtract(Duration(days: days));

Session _sess({int id = 1, DateTime? date, DateTime? createdAt, String? stgId}) =>
    Session(
      id: id,
      clientId: 'c1',
      date: date,
      shortTermGoalId: stgId,
      createdAt: createdAt ?? DateTime(2026, 1, 1),
    );

ShortTermGoal _stg(String id, {int? seq}) => ShortTermGoal(
      id: id,
      longTermGoalId: 'l1',
      clientId: 'c1',
      userId: 'u1',
      sequenceNum: seq,
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
    );

const _codes = {'a': '1.A', 'b': '1.B', 'c': '1.C'};

ClientBriefSignals _compute({
  DateTime? prior,
  List<Session> sessions = const [],
  List<ShortTermGoal> active = const [],
  Map<String, String> codes = _codes,
}) =>
    ClientBriefSignals.compute(
      priorViewedAt: prior,
      sessions: sessions,
      activeStgs: active,
      stgCodes: codes,
      now: _now,
    );

void main() {
  group('first visit', () {
    test('null prior, nothing else → firstVisit floor', () {
      final s = _compute(prior: null);
      expect(s.isFirstVisit, isTrue);
      expect(s.lead, BriefLead.firstVisit);
      expect(s.sessionsSinceLastVisit, 0);
      expect(s.pendingGoalCodes, isEmpty);
      expect(s.daysSinceLastSeen, 0);
    });

    test('first visit never reports new_activity (no baseline)', () {
      // Sessions exist but there is no prior to count "since" — must be 0.
      final s = _compute(
        prior: null,
        sessions: [_sess(date: _ago(1)), _sess(date: _ago(2))],
      );
      expect(s.isFirstVisit, isTrue);
      expect(s.sessionsSinceLastVisit, 0);
      expect(s.lead, isNot(BriefLead.newActivity));
    });

    test('pending outranks firstVisit', () {
      final s = _compute(
        prior: null,
        active: [_stg('a', seq: 1), _stg('b', seq: 2)],
      );
      expect(s.isFirstVisit, isTrue);
      expect(s.lead, BriefLead.pending);
      expect(s.pendingGoalCodes, ['1.A', '1.B']);
    });
  });

  group('new_activity', () {
    test('counts only sessions dated after prior_viewed_at', () {
      final s = _compute(
        prior: _ago(5),
        sessions: [
          _sess(id: 1, date: _ago(2)), // after prior → counts
          _sess(id: 2, date: _ago(3)), // after prior → counts
          _sess(id: 3, date: _ago(10)), // before prior → no
        ],
      );
      expect(s.sessionsSinceLastVisit, 2);
      expect(s.lead, BriefLead.newActivity);
    });

    test('new_activity outranks pending AND long_gap', () {
      final s = _compute(
        prior: _ago(30),
        sessions: [_sess(date: _ago(1), stgId: 'a')], // new + recent
        active: [_stg('a'), _stg('b')], // b is unworked (pending exists)
      );
      expect(s.sessionsSinceLastVisit, 1);
      expect(s.lead, BriefLead.newActivity);
    });

    test('falls back to createdAt when date is null', () {
      final s = _compute(
        prior: _ago(5),
        sessions: [_sess(date: null, createdAt: _ago(2))], // createdAt counts
      );
      expect(s.sessionsSinceLastVisit, 1);
    });
  });

  group('pending_goals', () {
    test('active STGs with zero sessions are pending; worked ones excluded', () {
      final s = _compute(
        prior: _ago(5),
        sessions: [_sess(date: _ago(10), stgId: 'b')], // b worked, before prior
        active: [_stg('a'), _stg('b'), _stg('c')],
      );
      expect(s.sessionsSinceLastVisit, 0); // session predates prior
      expect(s.pendingGoalCodes, ['1.A', '1.C']); // sorted, b excluded
      expect(s.lead, BriefLead.pending);
    });

    test('codes are sorted regardless of STG order', () {
      final s = _compute(
        prior: _ago(5),
        active: [_stg('c'), _stg('a'), _stg('b')],
      );
      expect(s.pendingGoalCodes, ['1.A', '1.B', '1.C']);
    });

    test('falls back to STG seq when no code is mapped', () {
      final s = _compute(
        prior: _ago(5),
        active: [_stg('x', seq: 7)],
        codes: const {}, // no code for x
      );
      expect(s.pendingGoalCodes, ['STG 7']);
    });
  });

  group('time_gap + leads', () {
    test('long_gap leads when gap exceeds threshold and nothing higher fires',
        () {
      final s = _compute(
        prior: _ago(19),
        sessions: [_sess(date: _ago(20), stgId: 'a')], // before prior, all worked
        active: [_stg('a')],
      );
      expect(s.sessionsSinceLastVisit, 0);
      expect(s.pendingGoalCodes, isEmpty);
      expect(s.daysSinceLastSeen, 20);
      expect(s.lead, BriefLead.longGap);
    });

    test('nothing_new floor: no new, no pending, recent enough', () {
      final s = _compute(
        prior: _ago(5),
        sessions: [_sess(date: _ago(10), stgId: 'a')],
        active: [_stg('a')],
      );
      expect(s.daysSinceLastSeen, 10);
      expect(s.lead, BriefLead.nothingNew);
    });

    test('daysSinceLastSeen falls back to prior when no sessions', () {
      final s = _compute(prior: _ago(7));
      expect(s.daysSinceLastSeen, 7);
    });

    test('future-dated session never yields a negative gap', () {
      final s = _compute(prior: null, sessions: [_sess(date: _now.add(const Duration(days: 3)))]);
      expect(s.daysSinceLastSeen, 0);
    });
  });

  test('toMap exposes only factual fields (no prose, no evaluation)', () {
    final s = _compute(prior: _ago(5), active: [_stg('a')]);
    expect(s.toMap().keys.toSet(), {
      'lead',
      'sessionsSinceLastVisit',
      'pendingGoalCodes',
      'daysSinceLastSeen',
      'isFirstVisit',
      'activeGoalCount',
    });
  });
}
