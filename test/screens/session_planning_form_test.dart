import 'package:cue/screens/session_planning_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// PlanningForm is pure (no Supabase), so it pumps without an initialized
// client. The SessionPlanningScreen wrapper (auth guard + repo writes) needs a
// live Supabase and isn't widget-testable without a mock, per the codebase's
// existing constraint.
Future<void> _pump(WidgetTester t, Widget child) async {
  await t.pumpWidget(MaterialApp(
    theme: ThemeData(brightness: Brightness.dark),
    home: Scaffold(body: SingleChildScrollView(child: child)),
  ));
  await t.pump(const Duration(milliseconds: 50));
}

void main() {
  testWidgets('pre-populates with seedFocus and shows carry-forward copy',
      (t) async {
    await _pump(
      t,
      PlanningForm(
        seedFocus: 'Introduce the core board at snack time',
        onSaveDraft: (_) {},
        onOpenSession: (_) {},
      ),
    );
    expect(find.text('Introduce the core board at snack time'), findsOneWidget);
    expect(find.textContaining('carries forward from your last session'),
        findsOneWidget);
  });

  testWidgets('null seed shows the alternate copy', (t) async {
    await _pump(
      t,
      PlanningForm(seedFocus: null, onSaveDraft: (_) {}, onOpenSession: (_) {}),
    );
    expect(find.textContaining('no prior intent on file'), findsOneWidget);
  });

  testWidgets('Save as draft and Open session fire with the field text',
      (t) async {
    String? draft;
    String? opened;
    await _pump(
      t,
      PlanningForm(
        seedFocus: 'plan x',
        onSaveDraft: (txt) => draft = txt,
        onOpenSession: (txt) => opened = txt,
      ),
    );
    await t.tap(find.text('Save as draft'));
    await t.pump();
    expect(draft, 'plan x');

    await t.tap(find.text('Open session'));
    await t.pump();
    expect(opened, 'plan x');
  });
}
