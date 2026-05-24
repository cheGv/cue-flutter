// Phase B-revised (cards-on-canvas) structural tests — the card-head wrappers,
// the STG section composition, the trajectory summary panel + week axis, the
// Inter-sans session dates (no monospace), and light/dark token resolution.
import 'package:cue/models/session.dart';
import 'package:cue/models/session_outcome.dart';
import 'package:cue/models/short_term_goal.dart';
import 'package:cue/theme/cue_color_scheme.dart';
import 'package:cue/widgets/chart/chart_ltg_anchor.dart';
import 'package:cue/widgets/chart/chart_session_history.dart';
import 'package:cue/widgets/chart/chart_stg_section.dart';
import 'package:cue/widgets/chart/chart_trajectory_strip.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pump(WidgetTester t, Widget child,
    {Brightness b = Brightness.dark}) async {
  await t.pumpWidget(MaterialApp(
    theme: ThemeData(brightness: b),
    home: Scaffold(body: SingleChildScrollView(child: child)),
  ));
  await t.pump(const Duration(milliseconds: 50));
}

ShortTermGoal _stg(String id, int seq) => ShortTermGoal(
      id: id,
      longTermGoalId: 'l1',
      clientId: 'c1',
      userId: 'u1',
      specific: 'Produce /s/ in initial position',
      sequenceNum: seq,
      domain: StgDomain.articulation,
      timeBoundSessions: 4,
      totalSessionsWorked: 1,
      createdAt: DateTime(2026, 5, seq),
      updatedAt: DateTime(2026, 5, seq),
    );

Session _sess(int id, DateTime date, SessionOutcome outcome) => Session(
      id: id,
      clientId: 'c1',
      createdAt: date,
      date: date,
      outcome: outcome,
      shortTermGoalId: 's1',
      durationMinutes: 45,
      soapNote: 'note',
    );

void main() {
  testWidgets('ChartLtgAnchor renders the card-head + body + meta', (t) async {
    await _pump(
      t,
      const ChartLtgAnchor(
        ltgText: 'Aarav will use a multimodal communication system.',
        ltgSeq: 1,
        monthsTotal: 12,
        currentMonth: 1,
        substrateCellCount: 18,
      ),
    );
    expect(find.textContaining('LONG-TERM GOAL'), findsOneWidget); // card-head
    expect(find.text('Edit LTG'), findsOneWidget);
    expect(find.textContaining('multimodal communication'), findsOneWidget);
    expect(find.textContaining('Month 1 of 12'), findsOneWidget);
    expect(find.text('12 months'), findsOneWidget); // info badge
  });

  testWidgets('ChartStgSection wraps focus + compact under its card-head',
      (t) async {
    await _pump(
      t,
      const ChartStgSection(
        activeCount: 3,
        focus: Text('FOCUS-MARKER'),
        compact: Text('COMPACT-MARKER'),
      ),
    );
    expect(find.textContaining('SHORT-TERM GOALS'), findsOneWidget);
    expect(find.textContaining('3 ACTIVE'), findsOneWidget);
    expect(find.text('New STG'), findsOneWidget);
    expect(find.text('FOCUS-MARKER'), findsOneWidget);
    expect(find.text('COMPACT-MARKER'), findsOneWidget);
  });

  testWidgets('ChartTrajectoryStrip renders the summary panel + week axis',
      (t) async {
    final sessions = [
      _sess(1, DateTime(2026, 4, 30), SessionOutcome.progress),
      _sess(2, DateTime(2026, 5, 21), SessionOutcome.holding),
    ];
    await _pump(
      t,
      ChartTrajectoryStrip(
        activeStgs: [_stg('s1', 1)],
        sessions: sessions,
        earliestSessionDate: DateTime(2026, 4, 30),
        stgNumbers: const {'s1': '1.A'},
      ),
    );
    expect(find.textContaining('OVERALL'), findsOneWidget); // summary label
    expect(find.text('50%'), findsOneWidget); // 1 of 2 progress
    expect(find.textContaining('progress sessions'), findsOneWidget);
    expect(find.textContaining('1 progress'), findsOneWidget); // outcome pill
    expect(find.text('Week 1'), findsOneWidget); // sans, full word
    expect(find.text('Week 8'), findsOneWidget);
  });

  testWidgets('session-row date sub-line uses Inter sans, not monospace',
      (t) async {
    final s = _sess(1, DateTime(2026, 5, 21), SessionOutcome.progress);
    await _pump(t, ChartSessionHistory(sessions: [s], clientName: 'Dina'));
    final sub = t.widget<Text>(find.textContaining('45 min'));
    expect(sub.style?.fontFamily, isNot(contains('Plex'))); // not IBM Plex Mono
    expect(sub.style?.fontFamily, contains('Inter'));
  });

  testWidgets('CueChartTokens resolves distinct light vs dark canvases',
      (t) async {
    CueChartTokens? cap;
    Widget probe() => Builder(builder: (c) {
          cap = CueChartTokens.of(c);
          return const SizedBox();
        });

    // pumpAndSettle past MaterialApp's AnimatedTheme lerp so brightness is the
    // settled value, not a mid-animation frame.
    await t.pumpWidget(MaterialApp(
      theme: ThemeData(brightness: Brightness.light),
      home: probe(),
    ));
    await t.pumpAndSettle();
    final lightT = cap!;

    await t.pumpWidget(MaterialApp(
      theme: ThemeData(brightness: Brightness.dark),
      home: probe(),
    ));
    await t.pumpAndSettle();
    final darkT = cap!;

    expect(lightT.isDark, isFalse);
    expect(darkT.isDark, isTrue);
    expect(lightT.bgCanvas, isNot(darkT.bgCanvas));
  });
}
