import 'package:cue/models/client_chart_state.dart';
import 'package:cue/widgets/chart/chart_narrator.dart';
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
  testWidgets('no LTG and no STGs → substrate-ready line', (t) async {
    const s = ClientChartState(
        clientId: 'c', clientName: 'Aarav', ltgCount: 0, activeStgCount: 0);
    await _pump(t, const ChartNarrator(state: s, clientName: 'Aarav'));
    expect(
      find.textContaining(
          "Aarav's long-term goal is not yet authored"),
      findsOneWidget,
    );
    expect(find.textContaining('Substrate is ready beneath'), findsOneWidget);
  });

  testWidgets('active STGs → STGs in motion line', (t) async {
    const s = ClientChartState(
        clientId: 'c', clientName: 'Dina', ltgCount: 1, activeStgCount: 3);
    await _pump(t, const ChartNarrator(state: s, clientName: 'Dina'));
    expect(find.textContaining('3 STGs in motion'), findsOneWidget);
  });

  testWidgets('LTG set but no active STGs → STGs not yet authored', (t) async {
    const s = ClientChartState(
        clientId: 'c', clientName: 'Ravi', ltgCount: 1, activeStgCount: 0);
    await _pump(t, const ChartNarrator(state: s, clientName: 'Ravi'));
    expect(
      find.textContaining('long-term goal is set'),
      findsOneWidget,
    );
    expect(
      find.textContaining('short-term goals not yet authored'),
      findsOneWidget,
    );
  });
}
