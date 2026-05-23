import 'package:cue/models/session.dart';
import 'package:cue/models/session_outcome.dart';
import 'package:cue/widgets/chart/chart_session_history.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pump(WidgetTester t, Widget child) async {
  await t.pumpWidget(MaterialApp(
    theme: ThemeData(brightness: Brightness.dark),
    home: Scaffold(body: SingleChildScrollView(child: child)),
  ));
  await t.pump(const Duration(milliseconds: 50));
}

Session _sess(int id, DateTime date, SessionOutcome outcome) => Session(
      id: id,
      clientId: 'c-1',
      createdAt: date,
      date: date,
      outcome: outcome,
      durationMinutes: 45,
      soapNote: 'Worked on /s/ blends in structured drill.',
      nextSessionFocus: 'Generalise to connected speech.',
    );

void main() {
  testWidgets('empty state when there are no sessions', (t) async {
    await _pump(
      t,
      const ChartSessionHistory(sessions: [], clientName: 'Aarav'),
    );
    expect(find.textContaining('No sessions on record yet'), findsOneWidget);
  });

  testWidgets('most-recent row is expanded by default; others collapsed',
      (t) async {
    final recent = _sess(1, DateTime(2026, 5, 21), SessionOutcome.progress);
    final older = _sess(2, DateTime(2026, 5, 18), SessionOutcome.holding);

    await _pump(
      t,
      ChartSessionHistory(sessions: [recent, older], clientName: 'Dina'),
    );

    // Only the most-recent (May 21) row is expanded → one OBSERVATION block.
    expect(find.text('OBSERVATION'), findsOneWidget);
    expect(find.text('NEXT SESSION'), findsOneWidget);
    expect(find.text('May 18'), findsOneWidget);
  });

  testWidgets('tapping a collapsed row expands it', (t) async {
    final recent = _sess(1, DateTime(2026, 5, 21), SessionOutcome.progress);
    final older = _sess(2, DateTime(2026, 5, 18), SessionOutcome.holding);

    await _pump(
      t,
      ChartSessionHistory(sessions: [recent, older], clientName: 'Dina'),
    );
    expect(find.text('OBSERVATION'), findsOneWidget);

    await t.tap(find.text('May 18'));
    await t.pump(const Duration(milliseconds: 50));

    // Both rows now expanded.
    expect(find.text('OBSERVATION'), findsNWidgets(2));
  });
}
