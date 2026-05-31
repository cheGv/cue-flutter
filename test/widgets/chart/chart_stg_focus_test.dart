import 'package:cue/models/citation.dart';
import 'package:cue/models/short_term_goal.dart';
import 'package:cue/models/stg_session_metric.dart';
import 'package:cue/widgets/chart/chart_stg_focus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

ShortTermGoal _stg() => ShortTermGoal(
      id: 's1',
      longTermGoalId: 'l1',
      clientId: 'c1',
      userId: 'u1',
      specific: 'Produce /s/ in initial position',
      sequenceNum: 1,
      timeBoundSessions: 4,
      totalSessionsWorked: 1,
      domain: StgDomain.articulation,
      createdAt: DateTime(2026, 5, 1),
      updatedAt: DateTime(2026, 5, 1),
    );

StgSessionMetric _m(double v) => StgSessionMetric(
      id: 'm$v',
      stgId: 's1',
      sessionId: 1,
      metricValue: v,
      metricLabel: 'prompting level',
      metricUnit: 'level',
      recordedAt: DateTime(2026, 5, 1),
    );

Citation _c(EvidenceTier t, String author, {String? url}) => Citation(
      id: 'c-$author',
      stgId: 's1',
      tier: t,
      finding: 'Finding text for $author',
      authorYear: author,
      sourceUrl: url,
      displayOrder: 1,
    );

Future<void> _pump(WidgetTester t, Widget child) async {
  await t.pumpWidget(MaterialApp(
    theme: ThemeData(brightness: Brightness.dark),
    home: Scaffold(body: SingleChildScrollView(child: child)),
  ));
  await t.pump(const Duration(milliseconds: 50));
}

void main() {
  testWidgets('renders the STG number pill + IN FOCUS, sparkline phrase, '
      'citation, and source link', (t) async {
    await _pump(
      t,
      ChartStgFocus(
        stg: _stg(),
        stgNumber: '1.A',
        metrics: [_m(5), _m(0)],
        citations: [
          _c(EvidenceTier.level1, 'Porges · 2011', url: 'https://doi.org/x'),
        ],
        hasSessionToday: false,
        isCompact: false,
      ),
    );
    expect(find.text('1.A'), findsOneWidget);
    expect(find.text('IN FOCUS'), findsOneWidget);
    expect(find.textContaining('hand-over-hand → independent'), findsOneWidget);
    expect(find.text('Porges · 2011'), findsOneWidget);
    // A non-null source_url makes the evidence link interactive (north-east ↗).
    expect(find.byIcon(Icons.north_east), findsOneWidget);
  });

  testWidgets('null source_url → link disabled; empty metrics show the '
      'empty readout', (t) async {
    await _pump(
      t,
      ChartStgFocus(
        stg: _stg(),
        stgNumber: '1.A',
        metrics: const [],
        citations: [_c(EvidenceTier.practice, 'Patel · 2024', url: null)],
        hasSessionToday: false,
        isCompact: false,
      ),
    );
    expect(find.byIcon(Icons.north_east), findsOneWidget);
    // The disabled (null-url) source button is the only thing wrapped in
    // Opacity(0.4).
    expect(find.byType(Opacity), findsOneWidget);
    expect(t.widget<Opacity>(find.byType(Opacity)).opacity, 0.4);
    expect(find.textContaining('first session will populate'), findsOneWidget);
  });

  // ── Mastery-criterion line ────────────────────────────────────────────────

  testWidgets('quantified mastery criterion renders the composed line',
      (t) async {
    final stg = _stg().copyWith(
      masteryCriterion: const MasteryCriterion(
        accuracyPct: 80,
        consecutiveSessions: 3,
        trialsPerSession: 10,
      ),
    );
    await _pump(
      t,
      ChartStgFocus(
        stg: stg,
        stgNumber: '1.A',
        metrics: const [],
        citations: const [],
        hasSessionToday: false,
        isCompact: false,
      ),
    );
    expect(find.text('CRITERION'), findsOneWidget);
    expect(find.text('80% across 3 consecutive sessions of 10 trials each'),
        findsOneWidget);
  });

  testWidgets('hint-only mastery criterion renders the hint verbatim '
      '(voice / qualitative goals)', (t) async {
    final stg = _stg().copyWith(
      domain: StgDomain.voice,
      masteryCriterion: const MasteryCriterion(
        hint: '80% phonation continuity across 3 consecutive sessions',
      ),
    );
    await _pump(
      t,
      ChartStgFocus(
        stg: stg,
        stgNumber: '2.A',
        metrics: const [],
        citations: const [],
        hasSessionToday: false,
        isCompact: false,
      ),
    );
    expect(find.text('CRITERION'), findsOneWidget);
    expect(find.text('80% phonation continuity across 3 consecutive sessions'),
        findsOneWidget);
  });

  testWidgets('no criterion blob → no CRITERION row rendered', (t) async {
    // _stg() has no masteryCriterion. The row must be absent — never blank.
    await _pump(
      t,
      ChartStgFocus(
        stg: _stg(),
        stgNumber: '1.A',
        metrics: const [],
        citations: const [],
        hasSessionToday: false,
        isCompact: false,
      ),
    );
    expect(find.text('CRITERION'), findsNothing);
  });
}
