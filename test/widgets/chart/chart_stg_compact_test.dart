import 'package:cue/models/short_term_goal.dart';
import 'package:cue/widgets/chart/chart_stg_compact.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

ShortTermGoal _stg(String id, int seq, String text) => ShortTermGoal(
      id: id,
      longTermGoalId: 'l1',
      clientId: 'c1',
      userId: 'u1',
      specific: text,
      sequenceNum: seq,
      domain: StgDomain.articulation,
      createdAt: DateTime(2026, 5, seq),
      updatedAt: DateTime(2026, 5, seq),
    );

Future<void> _pump(WidgetTester t, Widget child) async {
  await t.pumpWidget(MaterialApp(
    theme: ThemeData(brightness: Brightness.dark),
    home: Scaffold(body: SingleChildScrollView(child: child)),
  ));
  await t.pump(const Duration(milliseconds: 50));
}

void main() {
  testWidgets('renders the display number and fires onTapStg with the id',
      (t) async {
    String? tapped;
    final stgs = [_stg('s1', 1, 'Produce /s/'), _stg('s2', 2, 'Produce /r/')];
    await _pump(
      t,
      ChartStgCompact(
        stgs: stgs,
        evidenceCountByStg: const {'s1': 2, 's2': 0},
        stgNumbers: const {'s1': '1.A', 's2': '1.B'},
        onTapStg: (id) => tapped = id,
      ),
    );

    expect(find.text('1.A'), findsOneWidget);
    expect(find.text('1.B'), findsOneWidget);
    expect(find.text('2 cited'), findsOneWidget);

    await t.tap(find.text('Produce /r/'));
    await t.pump();
    expect(tapped, 's2');
  });
}
