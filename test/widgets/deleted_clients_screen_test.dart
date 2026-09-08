// test/widgets/deleted_clients_screen_test.dart
//
// Delete affordances, Step 4 — the restore list. Covers, through the
// screen's own construction-time seam (loader + restorer closures):
//   - the row model: what was deleted, when, and the reason if given,
//   - rendering: name, kind, detail line, one Restore per row,
//   - Restore calls the injected restorer with the id, reloads, and says so,
//   - a failed restore is said, not swallowed,
//   - the empty and error states.
// The default restorer IS ClientDeleteService.restore (no second restore
// exists); that binding is read, not executed, here.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:cue/screens/deleted_clients_screen.dart';

DeletedClientRow row({
  String id = 'c-1',
  String name = 'Kabir M.',
  bool isCase = true,
  DateTime? deletedAt,
  String? reason,
}) =>
    DeletedClientRow(
      id: id,
      name: name,
      isAssessmentCase: isCase,
      deletedAt: deletedAt,
      reason: reason,
    );

/// AppLayout's chrome animates continuously (the cuttlefish wave), so
/// pumpAndSettle never settles. Pump the frames the screen actually needs:
/// the FutureBuilder's microtasks, then the SnackBar's entrance.
Future<void> settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  group('DeletedClientRow — what, when, why', () {
    test('fromRow reads the five columns and normalises blanks', () {
      final r = DeletedClientRow.fromRow({
        'id': 'abc',
        'name': '  Asha R. ',
        'engagement_type': 'therapy',
        'deleted_at': '2026-09-06T10:00:00+00:00',
        'delete_reason': '   ',
      });
      expect(r.id, 'abc');
      expect(r.name, 'Asha R.');
      expect(r.isAssessmentCase, isFalse);
      expect(r.kindLabel, 'Client');
      expect(r.deletedAt, isNotNull);
      expect(r.reason, isNull);

      final c = DeletedClientRow.fromRow({
        'id': 'x',
        'name': null,
        'engagement_type': 'assessment_only',
        'deleted_at': null,
        'delete_reason': 'Wrong client',
      });
      expect(c.name, 'Unnamed');
      expect(c.kindLabel, 'Assessment case');
      expect(c.deletedAt, isNull);
      expect(c.reason, 'Wrong client');
    });

    test('detailLine: when, then the reason if any', () {
      final now = DateTime(2026, 9, 8, 12);
      expect(row(deletedAt: DateTime(2026, 9, 8, 9)).detailLine(now: now),
          'Deleted today');
      expect(
          row(deletedAt: DateTime(2026, 9, 6), reason: 'Wrong client')
              .detailLine(now: now),
          startsWith('Deleted '));
      expect(
          row(deletedAt: DateTime(2026, 9, 6), reason: 'Wrong client')
              .detailLine(now: now),
          endsWith(' · Wrong client'));
      expect(row(deletedAt: null).detailLine(now: now), 'Deleted');
      expect(row(deletedAt: null, reason: 'Test entry').detailLine(now: now),
          'Deleted · Test entry');
    });
  });

  group('DeletedClientsScreen — list + restore', () {
    Widget host(Widget child) => MaterialApp(home: child);

    testWidgets('renders every row with name, kind, detail and Restore',
        (tester) async {
      final rows = [
        row(id: 'a', name: 'Kabir M.', reason: 'Duplicate record'),
        row(id: 'b', name: 'Asha R.', isCase: false),
      ];
      await tester.pumpWidget(host(DeletedClientsScreen(
        loader: () async => rows,
        restorer: (_) async {},
      )));
      await settle(tester);
      expect(find.text('Kabir M.'), findsOneWidget);
      expect(find.text('Assessment case'), findsOneWidget);
      expect(find.textContaining('Duplicate record'), findsOneWidget);
      expect(find.text('Asha R.'), findsOneWidget);
      expect(find.text('Client'), findsOneWidget);
      expect(find.text('Restore'), findsNWidgets(2));
      expect(find.text('Nothing deleted'), findsNothing);
    });

    testWidgets('Restore calls the restorer with the id, reloads, and says so',
        (tester) async {
      final restored = <String>[];
      var loads = 0;
      var notified = 0;
      final data = [row(id: 'a', name: 'Kabir M.'), row(id: 'b', name: 'Asha R.')];
      await tester.pumpWidget(host(DeletedClientsScreen(
        loader: () async {
          loads++;
          return data.where((r) => !restored.contains(r.id)).toList();
        },
        restorer: (id) async => restored.add(id),
        onRestored: () => notified++,
      )));
      await settle(tester);
      expect(loads, 1);

      await tester.tap(find.text('Restore').first);
      await settle(tester);
      expect(restored, ['a']);
      expect(loads, 2);
      expect(notified, 1);
      expect(find.text('Kabir M. is back in your lists.'), findsOneWidget);
      expect(find.text('Kabir M.'), findsNothing);
      expect(find.text('Asha R.'), findsOneWidget);
    });

    testWidgets('a failed restore is said, the row stays', (tester) async {
      await tester.pumpWidget(host(DeletedClientsScreen(
        loader: () async => [row(name: 'Kabir M.')],
        restorer: (_) async => throw StateError('offline'),
      )));
      await settle(tester);
      await tester.tap(find.text('Restore'));
      await settle(tester);
      expect(find.textContaining("Couldn't restore"), findsOneWidget);
      expect(find.textContaining('offline'), findsOneWidget);
      expect(find.text('Kabir M.'), findsOneWidget);
    });

    testWidgets('empty state says nothing is erased', (tester) async {
      await tester.pumpWidget(host(DeletedClientsScreen(
        loader: () async => const [],
        restorer: (_) async {},
      )));
      await settle(tester);
      expect(find.text('Nothing deleted'), findsOneWidget);
      expect(find.textContaining('Nothing is erased'), findsOneWidget);
      expect(find.text('Restore'), findsNothing);
    });

    testWidgets('a failed load shows the error and Try again reloads',
        (tester) async {
      var attempts = 0;
      await tester.pumpWidget(host(DeletedClientsScreen(
        loader: () async {
          attempts++;
          if (attempts == 1) throw StateError('offline');
          return [row(name: 'Kabir M.')];
        },
        restorer: (_) async {},
      )));
      await settle(tester);
      expect(find.textContaining("Couldn't load"), findsOneWidget);
      await tester.tap(find.text('Try again'));
      await settle(tester);
      expect(attempts, 2);
      expect(find.text('Kabir M.'), findsOneWidget);
    });
  });
}
