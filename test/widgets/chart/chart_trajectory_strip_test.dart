import 'package:cue/models/session.dart';
import 'package:cue/models/session_outcome.dart';
import 'package:cue/models/short_term_goal.dart';
import 'package:cue/widgets/chart/chart_trajectory_strip.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pump(WidgetTester t, Widget child) async {
  await t.pumpWidget(MaterialApp(
    theme: ThemeData(brightness: Brightness.dark),
    home: Scaffold(body: SingleChildScrollView(child: child)),
  ));
  await t.pump(const Duration(milliseconds: 50));
}

ShortTermGoal _stg() => ShortTermGoal(
      id: 'stg-1',
      longTermGoalId: 'ltg-1',
      clientId: 'c-1',
      userId: 'u-1',
      specific: 'Produce /s/ in initial position',
      sequenceNum: 1,
      domain: StgDomain.articulation,
      createdAt: DateTime(2026, 5, 1),
      updatedAt: DateTime(2026, 5, 1),
    );

Session _sess(int id, DateTime date, SessionOutcome? outcome) => Session(
      id: id,
      clientId: 'c-1',
      createdAt: date,
      date: date,
      outcome: outcome,
      shortTermGoalId: 'stg-1',
      durationMinutes: 45,
      soapNote: 'note',
    );

void main() {
  testWidgets('empty state when no active STGs', (t) async {
    await _pump(
      t,
      const ChartTrajectoryStrip(
        activeStgs: [],
        sessions: [],
        earliestSessionDate: null,
      ),
    );
    expect(
      find.textContaining('Trajectory will appear once short-term goals'),
      findsOneWidget,
    );
  });

  testWidgets('renders one tick per session; NULL outcome is hollow; today '
      'tick is marked', (t) async {
    final now = DateTime.now();
    final s1 = _sess(1, now.subtract(const Duration(days: 20)), null);
    final s2 =
        _sess(2, now.subtract(const Duration(days: 10)), SessionOutcome.progress);
    final s3 = _sess(3, now, SessionOutcome.holding);

    await _pump(
      t,
      ChartTrajectoryStrip(
        activeStgs: [_stg()],
        sessions: [s3, s2, s1],
        earliestSessionDate: now.subtract(const Duration(days: 20)),
      ),
    );

    // Three ticks total.
    expect(
      find.byWidgetPredicate((w) =>
          w.key is ValueKey &&
          (w.key as ValueKey).value.toString().startsWith('traj-tick-')),
      findsNWidgets(3),
    );
    // NULL-outcome session renders hollow.
    expect(
      find.byKey(const ValueKey('traj-tick-1-hollow-past')),
      findsOneWidget,
    );
    // Today's session renders as a today tick.
    expect(
      find.byKey(const ValueKey('traj-tick-3-solid-today')),
      findsOneWidget,
    );
  });
}
