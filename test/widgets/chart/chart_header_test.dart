import 'package:cue/models/client_chart_state.dart';
import 'package:cue/widgets/chart/chart_header.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pump(WidgetTester t, Widget child) async {
  await t.pumpWidget(MaterialApp(
    theme: ThemeData(brightness: Brightness.dark),
    home: Scaffold(body: SingleChildScrollView(child: child)),
  ));
  await t.pump(const Duration(milliseconds: 50));
}

void main() {
  testWidgets('renders the name and the meta line (sentence case, not upper)',
      (t) async {
    const s = ClientChartState(
      clientId: 'c1',
      clientName: 'Dina',
      age: 19,
      diagnosis: 'Autism',
      totalSessionCount: 3,
    );
    await _pump(
      t,
      ChartHeader(
        state: s,
        firstSessionDate: DateTime(2026, 2, 1),
        sessionToday: false,
        isCompact: false,
      ),
    );

    expect(find.text('Dina'), findsOneWidget);
    expect(find.textContaining('19 years'), findsOneWidget);
    expect(find.textContaining('Autism'), findsOneWidget);
    expect(find.textContaining('3 sessions'), findsOneWidget);
  });

  testWidgets('eyebrow empty + zero/plural meta when no sessions', (t) async {
    const s = ClientChartState(clientId: 'c1', clientName: 'Aarav', age: 3);
    await _pump(
      t,
      ChartHeader(
        state: s,
        firstSessionDate: null,
        sessionToday: false,
        isCompact: false,
      ),
    );

    expect(find.text('Aarav'), findsOneWidget);
    expect(find.textContaining('In care since'), findsNothing);
    expect(find.textContaining('Session today'), findsNothing);
    expect(find.textContaining('0 sessions'), findsOneWidget);
  });

  testWidgets('eyebrow shows In care + Session today when applicable',
      (t) async {
    const s = ClientChartState(
      clientId: 'c1',
      clientName: 'Dina',
      age: 19,
      totalSessionCount: 5,
    );
    await _pump(
      t,
      ChartHeader(
        state: s,
        firstSessionDate: DateTime(2026, 1, 1),
        sessionToday: true,
        isCompact: false,
      ),
    );
    expect(find.textContaining('In care since'), findsOneWidget);
    expect(find.textContaining('Session today'), findsOneWidget);
  });

  testWidgets('header does not render its own Ask Cue button '
      '(recall is the global launcher)', (t) async {
    const s = ClientChartState(clientId: 'c1', clientName: 'Dina', age: 19);
    await _pump(
      t,
      ChartHeader(
        state: s,
        firstSessionDate: null,
        sessionToday: false,
        isCompact: false,
      ),
    );
    expect(find.text('Ask Cue'), findsNothing);
  });
}
