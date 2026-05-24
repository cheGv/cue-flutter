import 'package:cue/models/client_chart_state.dart';
import 'package:cue/widgets/chart/chart_action_chips.dart';
import 'package:cue/widgets/chart/chart_format.dart';
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
  group('resolvePrimaryAction precedence (pure)', () {
    test('no LTG → authorLtg', () {
      const s = ClientChartState(clientId: 'c', clientName: 'A', ltgCount: 0);
      expect(resolvePrimaryAction(s, sessionToday: true),
          ChartPrimaryAction.authorLtg);
    });

    test('LTG + undocumented sessions → documentLastSession', () {
      const s = ClientChartState(
          clientId: 'c',
          clientName: 'A',
          ltgCount: 1,
          undocumentedSessionCount: 2);
      expect(resolvePrimaryAction(s, sessionToday: true),
          ChartPrimaryAction.documentLastSession);
    });

    test('LTG, none undocumented, session today → planTodaySession', () {
      const s = ClientChartState(clientId: 'c', clientName: 'A', ltgCount: 1);
      expect(resolvePrimaryAction(s, sessionToday: true),
          ChartPrimaryAction.planTodaySession);
    });

    test('LTG, none undocumented, no session today → planNextSession', () {
      const s = ClientChartState(clientId: 'c', clientName: 'A', ltgCount: 1);
      expect(resolvePrimaryAction(s, sessionToday: false),
          ChartPrimaryAction.planNextSession);
    });
  });

  testWidgets('case 1 — no LTG renders the Author primary', (t) async {
    const s = ClientChartState(clientId: 'c', clientName: 'Aarav', ltgCount: 0);
    await _pump(
      t,
      const ChartActionChips(
          state: s, sessionToday: false, clientName: 'Aarav'),
    );
    expect(find.text("Author Aarav's long-term goal"), findsOneWidget);
  });

  testWidgets('case 2 — LTG + session today renders Plan today', (t) async {
    const s = ClientChartState(clientId: 'c', clientName: 'Dina', ltgCount: 1);
    await _pump(
      t,
      const ChartActionChips(state: s, sessionToday: true, clientName: 'Dina'),
    );
    expect(find.text("Plan today's session"), findsOneWidget);
  });

  testWidgets('case 3 — LTG + no session today renders Plan next', (t) async {
    const s = ClientChartState(clientId: 'c', clientName: 'Dina', ltgCount: 1);
    await _pump(
      t,
      const ChartActionChips(
          state: s, sessionToday: false, clientName: 'Dina'),
    );
    expect(find.text('Plan next session'), findsOneWidget);
  });

  testWidgets('the three fixed secondary chips always render', (t) async {
    const s = ClientChartState(clientId: 'c', clientName: 'Aarav', ltgCount: 0);
    await _pump(
      t,
      const ChartActionChips(
          state: s, sessionToday: false, clientName: 'Aarav'),
    );
    expect(find.text('Substrate'), findsOneWidget);
    expect(find.text('Review last session'), findsOneWidget);
    expect(find.text('New STG'), findsOneWidget);
  });

  testWidgets('Capture session chip is always present (not gated)', (t) async {
    const s = ClientChartState(
        clientId: 'c', clientName: 'Aarav', ltgCount: 0, totalSessionCount: 0);
    await _pump(
      t,
      const ChartActionChips(
          state: s, sessionToday: false, clientName: 'Aarav'),
    );
    expect(find.text('Capture session'), findsOneWidget);
  });

  testWidgets('New STG + Review are disabled (opacity 0.4) for an empty client',
      (t) async {
    const s = ClientChartState(
        clientId: 'c',
        clientName: 'Aarav',
        ltgCount: 0,
        totalSessionCount: 0);
    await _pump(
      t,
      const ChartActionChips(
          state: s, sessionToday: false, clientName: 'Aarav'),
    );
    final newStgOpacity = t.widget<Opacity>(
      find.ancestor(of: find.text('New STG'), matching: find.byType(Opacity)),
    );
    expect(newStgOpacity.opacity, 0.4);
    final reviewOpacity = t.widget<Opacity>(
      find.ancestor(
          of: find.text('Review last session'),
          matching: find.byType(Opacity)),
    );
    expect(reviewOpacity.opacity, 0.4);
  });

  testWidgets('onChipTap fires the correct id for each chip', (t) async {
    final taps = <String>[];
    const s = ClientChartState(
        clientId: 'c', clientName: 'Dina', ltgCount: 1, totalSessionCount: 3);
    await _pump(
      t,
      ChartActionChips(
        state: s,
        sessionToday: false,
        clientName: 'Dina',
        onChipTap: taps.add,
      ),
    );
    await t.tap(find.text('Capture session')); // always-present first chip
    await t.tap(find.text('Plan next session')); // contextual primary
    await t.tap(find.text('Substrate'));
    await t.tap(find.text('Review last session'));
    await t.tap(find.text('New STG'));
    await t.pump();
    expect(taps, [
      'capture_session',
      'primary',
      'open_substrate',
      'review_last_session',
      'new_stg',
    ]);
  });
}
