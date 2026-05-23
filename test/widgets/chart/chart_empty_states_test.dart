// Aarav fixture (the substrate-only client) renders every empty state cleanly.
//
// The full ClientProfileScreen can't be pumped in a widget test (its
// repositories call Supabase.instance, which isn't initialized in tests and
// there's no mock library). So the chart's empty-state surfaces are verified by
// composing the data-bound sub-widgets with Aarav's empty ClientChartState —
// the same states the screen shows for Aarav.
import 'package:cue/models/client_chart_state.dart';
import 'package:cue/widgets/chart/chart_action_chips.dart';
import 'package:cue/widgets/chart/chart_ltg_anchor.dart';
import 'package:cue/widgets/chart/chart_narrator.dart';
import 'package:cue/widgets/chart/chart_session_history.dart';
import 'package:cue/widgets/chart/chart_substrate_link_strip.dart';
import 'package:cue/widgets/chart/chart_trajectory_strip.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _aarav = ClientChartState(
  clientId: '25f4d2e8-e0e5-4a5c-981b-132d40db77ca',
  clientName: 'Aarav',
  age: 3,
  substrateCellCount: 18,
);

Future<void> _pump(WidgetTester t, Widget child) async {
  await t.pumpWidget(MaterialApp(
    theme: ThemeData(brightness: Brightness.dark),
    home: Scaffold(body: SingleChildScrollView(child: child)),
  ));
  await t.pump(const Duration(milliseconds: 50));
}

void main() {
  testWidgets('Aarav renders all empty states (dark)', (t) async {
    await _pump(
      t,
      const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ChartNarrator(state: _aarav, clientName: 'Aarav'),
          ChartLtgAnchor(ltgText: null, substrateCellCount: 18),
          ChartActionChips(
              state: _aarav, sessionToday: false, clientName: 'Aarav'),
          ChartSubstrateLinkStrip(substrateCellCount: 18),
          ChartSessionHistory(sessions: [], clientName: 'Aarav'),
          ChartTrajectoryStrip(
              activeStgs: [], sessions: [], earliestSessionDate: null),
        ],
      ),
    );

    // Narrator empty branch.
    expect(find.textContaining('long-term goal is not yet authored'),
        findsOneWidget);
    // LTG anchor empty line with the substrate count.
    expect(find.textContaining('No long-term goal authored yet'),
        findsOneWidget);
    // Action chips primary = Author.
    expect(find.text("Author Aarav's long-term goal"), findsOneWidget);
    // Substrate link strip names the cell count.
    expect(find.textContaining('18 cells across six layers'), findsOneWidget);
    // Session history empty.
    expect(find.textContaining('No sessions on record yet'), findsOneWidget);
    // Trajectory empty.
    expect(find.textContaining('Trajectory will appear once'), findsOneWidget);
  });

  testWidgets('Aarav empty states also render in light mode', (t) async {
    await t.pumpWidget(MaterialApp(
      theme: ThemeData(brightness: Brightness.light),
      home: const Scaffold(
        body: SingleChildScrollView(
          child: ChartNarrator(state: _aarav, clientName: 'Aarav'),
        ),
      ),
    ));
    await t.pump(const Duration(milliseconds: 50));
    expect(find.textContaining('Substrate is ready beneath'), findsOneWidget);
  });
}
