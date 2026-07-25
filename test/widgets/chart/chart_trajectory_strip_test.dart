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

  // ── CAS dial-data merge (cas_session_progress as second progress source) ──

  Session casSess(int id, DateTime date) => Session(
        id: id,
        clientId: 'c-1',
        createdAt: date,
        date: date,
        // The CAS capture path stamps neither outcome nor shortTermGoalId —
        // dial rows in cas_session_progress are the only progress record.
        outcome: null,
        shortTermGoalId: null,
        durationMinutes: 45,
        soapNote: 'note',
      );

  testWidgets('dial-only session (no outcome, no FK) counts as logged '
      'progress and renders a solid tick on its CAS-linked track', (t) async {
    final past = DateTime.now().subtract(const Duration(days: 10));
    await _pump(
      t,
      ChartTrajectoryStrip(
        activeStgs: [_stg()],
        sessions: [casSess(7, past)],
        casStgIdsBySession: const {
          7: {'stg-1'},
        },
        earliestSessionDate: past,
      ),
    );

    // Counted: "1 of 1 sessions logged progress", not 0.
    expect(find.textContaining('1 of 1 session'), findsOneWidget);
    // On the track (would previously be skipped — no shortTermGoalId), and
    // solid, not hollow (dial data is logged progress).
    expect(
      find.byKey(const ValueKey('traj-tick-7-solid-past')),
      findsOneWidget,
    );
  });

  testWidgets('explicit outcome is never overridden by dial data', (t) async {
    final past = DateTime.now().subtract(const Duration(days: 10));
    final s = Session(
      id: 8,
      clientId: 'c-1',
      createdAt: past,
      date: past,
      outcome: SessionOutcome.holding,
      shortTermGoalId: 'stg-1',
      durationMinutes: 45,
      soapNote: 'note',
    );
    await _pump(
      t,
      ChartTrajectoryStrip(
        activeStgs: [_stg()],
        sessions: [s],
        casStgIdsBySession: const {
          8: {'stg-1'},
        },
        earliestSessionDate: past,
      ),
    );

    // The clinician's explicit 'holding' call wins over the dial rows.
    expect(find.textContaining('0 of 1 session'), findsOneWidget);
  });
}
