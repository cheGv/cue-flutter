import 'package:cue/models/short_term_goal.dart';
import 'package:cue/utils/stg_numbering.dart';
import 'package:flutter_test/flutter_test.dart';

ShortTermGoal _stg(String id, String ltgId, DateTime created) => ShortTermGoal(
      id: id,
      longTermGoalId: ltgId,
      clientId: 'c-1',
      userId: 'u-1',
      specific: 'x',
      createdAt: created,
      updatedAt: created,
    );

Map<String, dynamic> _ltg(String id, DateTime created) =>
    {'id': id, 'created_at': created.toIso8601String()};

void main() {
  test('single LTG, single STG → 1.A', () {
    final stg = _stg('s1', 'l1', DateTime(2026, 5, 1));
    final n = stgNumber(stg, [stg], [_ltg('l1', DateTime(2026, 4, 1))]);
    expect(n, '1.A');
  });

  test('LTG order by created_at: STG under newer LTG → 2.A', () {
    final l1 = _ltg('l1', DateTime(2026, 1, 1));
    final l2 = _ltg('l2', DateTime(2026, 3, 1));
    final s = _stg('s1', 'l2', DateTime(2026, 3, 2));
    expect(stgNumber(s, [s], [l1, l2]), '2.A');
  });

  test('STG letter by created_at within parent LTG', () {
    final l1 = _ltg('l1', DateTime(2026, 1, 1));
    final a = _stg('sa', 'l1', DateTime(2026, 1, 2));
    final b = _stg('sb', 'l1', DateTime(2026, 1, 9));
    final all = [b, a]; // unordered input
    expect(stgNumber(a, all, [l1]), '1.A');
    expect(stgNumber(b, all, [l1]), '1.B');
  });

  test('orphan STG (parent LTG absent) → letter only, no prefix', () {
    final s = _stg('s1', 'missing', DateTime(2026, 5, 1));
    expect(stgNumber(s, [s], [_ltg('l1', DateTime(2026, 4, 1))]), 'A');
  });

  test('beyond Z falls back to a number', () {
    final l1 = _ltg('l1', DateTime(2026, 1, 1));
    final all = <ShortTermGoal>[];
    for (var i = 0; i < 28; i++) {
      all.add(_stg('s$i', 'l1', DateTime(2026, 1, 1).add(Duration(days: i))));
    }
    // 27th STG (index 26) → "27".
    expect(stgNumber(all[26], all, [l1]), '1.27');
  });
}
