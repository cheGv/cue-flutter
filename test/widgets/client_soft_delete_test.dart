// test/widgets/client_soft_delete_test.dart
//
// Delete affordances, Step 3 — the RECOVERABLE client / assessment-case
// delete and the by-id liveness gate. Covers, without any Supabase seam:
//   - ClientsQuery.livenessOf (the decision requireLiveClient makes) and
//     the two refusal exceptions' words,
//   - the dialog: archive_dialog shape, DELETE label, recoverable copy,
//     reason travels with the confirm, barrier does not dismiss,
//   - runClientSoftDelete's branches through closures,
//   - the kebab gate on AssessmentCaseCard (recoverable item for a real
//     row, permanent item for a trial row, never both) and on
//     ClientsRosterRow,
//   - the Undo snackbar's action.
// NOT covered (no seam, by decision): the two screens' own wiring and the
// service's live UPDATEs — those are proven on sandbox in SQL.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:cue/screens/assessing_screen.dart';
import 'package:cue/services/client_delete_service.dart';
import 'package:cue/services/clients_query.dart';
import 'package:cue/services/clients_roster_service.dart';
import 'package:cue/widgets/archive_dialog.dart';
import 'package:cue/widgets/clients_roster_row.dart';

Widget host(Widget child) => MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );

Map<String, dynamic> caseRow({String id = 'c-1'}) => {
      'id': id,
      'name': 'Kabir M.',
      'clinical_area': 'pediatric-language',
      'age': 4,
      'primary_concern_verbatim': 'Not combining words yet.',
      'engagement_type': 'assessment_only',
      'engagement_status': 'in_assessment',
      'is_trial_case': false,
    };

Map<String, dynamic> therapyRow({String id = 't-1'}) => {
      ...caseRow(id: id),
      'name': 'Asha R.',
      'engagement_type': 'therapy',
      'engagement_status': 'active',
    };

Map<String, dynamic> trialRow({String id = 'x-1'}) => {
      ...caseRow(id: id),
      'name': 'TRIAL RUN — AAC · 18:53',
      'is_trial_case': true,
    };

ClientRosterEntry rosterEntry(Map<String, dynamic> row) => ClientRosterEntry(
      id: row['id'] as String,
      rawName: row['name'] as String,
      age: row['age'] as int?,
      diagnosis: null,
      populationType: null,
      engagementStatus: row['engagement_status'] as String,
      primaryConcern: row['primary_concern_verbatim'] as String?,
      usesAac: false,
      isFixture: false,
      sessionsCount: 3,
      activeGoalsCount: 2,
      lastSessionDate: DateTime(2026, 9, 1),
      createdAt: DateTime(2026, 8, 1),
      updatedAt: DateTime(2026, 9, 1),
      lastTouchedAt: DateTime(2026, 9, 1),
      rawRow: row,
    );

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  group('liveness gate — the decision and its words', () {
    test('livenessOf: null → missing, deleted_at set → deleted, else live',
        () {
      expect(ClientsQuery.livenessOf(null), ClientLiveness.missing);
      expect(ClientsQuery.livenessOf({'id': 'c', 'deleted_at': null}),
          ClientLiveness.live);
      expect(ClientsQuery.livenessOf({'id': 'c'}), ClientLiveness.live);
      expect(
          ClientsQuery.livenessOf(
              {'id': 'c', 'deleted_at': '2026-09-06T10:00:00+00:00'}),
          ClientLiveness.deleted);
    });

    test('the refusals read as sentences, not as class names', () {
      expect('${const ClientDeletedException('c')}',
          'This client was deleted. Restore it to open its records.');
      expect('${const ClientNotFoundException('c')}',
          'This client could not be found.');
    });
  });

  group('copy — DELETE, recoverable, never archive', () {
    test('assessment case vs client noun, name quoted', () {
      final c = clientSoftDeleteCopy(caseRow());
      expect(c.title, 'Delete this assessment case?');
      expect(c.body, contains('"Kabir M."'));
      final t = clientSoftDeleteCopy(therapyRow());
      expect(t.title, 'Delete this client?');
      expect(t.body, contains('"Asha R."'));
    });

    test('states recoverable and undo; never borrows archive', () {
      for (final row in [caseRow(), therapyRow()]) {
        final c = clientSoftDeleteCopy(row);
        final all = '${c.title} ${c.body}'.toLowerCase();
        expect(all, contains('recoverable'));
        expect(all, contains('undo'));
        expect(all, contains('nothing is erased'));
        expect(all, isNot(contains('archiv')));
        expect(all, isNot(contains('permanent')));
      }
    });

    test('a nameless row still reads', () {
      final c = clientSoftDeleteCopy({'id': 'c', 'engagement_type': 'therapy'});
      expect(c.body, startsWith('This client disappears'));
    });
  });

  group('dialog — archive_dialog shape with the DELETE label', () {
    Future<List<ArchiveDialogResult>> pumpOpener(
        WidgetTester tester, Map<String, dynamic> row) async {
      final results = <ArchiveDialogResult>[];
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (ctx) => ElevatedButton(
              onPressed: () async {
                results.add(await showClientSoftDeleteDialog(
                    context: ctx, client: row));
              },
              child: const Text('open'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      return results;
    }

    testWidgets('confirm button says Delete, nothing says Archive',
        (tester) async {
      await pumpOpener(tester, caseRow());
      expect(find.widgetWithText(FilledButton, 'Delete'), findsOneWidget);
      expect(find.widgetWithText(TextButton, 'Cancel'), findsOneWidget);
      final texts = tester
          .widgetList<Text>(find.descendant(
              of: find.byType(AlertDialog), matching: find.byType(Text)))
          .map((t) => t.data ?? '')
          .join('\n');
      expect(texts, isNot(contains('Archive')));
      expect(texts, contains('Reason (optional)'));
      for (final r in clientSoftDeleteReasons) {
        expect(texts, contains(r), reason: r);
      }
    });

    testWidgets('tapping outside does not dismiss', (tester) async {
      await pumpOpener(tester, caseRow());
      await tester.tapAt(const Offset(2, 2));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
    });

    testWidgets('Cancel → not confirmed; Delete → confirmed with the '
        'chosen reason', (tester) async {
      final results = await pumpOpener(tester, caseRow());
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(results.single.confirmed, isFalse);

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Wrong client'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();
      expect(results, hasLength(2));
      expect(results.last.confirmed, isTrue);
      expect(results.last.reason, 'Wrong client');
    });
  });

  group('runClientSoftDelete — branches', () {
    test('a trial run is refused before confirm is shown', () async {
      var touched = 0;
      final out = await runClientSoftDelete(
        client: trialRow(),
        confirm: () async {
          touched++;
          return ArchiveDialogResult.cancelled;
        },
        execute: (_, _) async => touched++,
      );
      expect(out.kind, ClientSoftDeleteOutcomeKind.refusedTrial);
      expect(out.message, contains('permanently'));
      expect(touched, 0);
    });

    test('cancel never reaches execute', () async {
      var executes = 0;
      final out = await runClientSoftDelete(
        client: caseRow(),
        confirm: () async => ArchiveDialogResult.cancelled,
        execute: (_, _) async => executes++,
      );
      expect(out.kind, ClientSoftDeleteOutcomeKind.cancelled);
      expect(executes, 0);
    });

    test('confirm runs execute once with the id and the reason', () async {
      final calls = <(String, String?)>[];
      final out = await runClientSoftDelete(
        client: caseRow(id: 'abc'),
        confirm: () async => ArchiveDialogResult.confirmedWith('Test entry'),
        execute: (id, reason) async => calls.add((id, reason)),
      );
      expect(out.kind, ClientSoftDeleteOutcomeKind.deleted);
      expect(out.reason, 'Test entry');
      expect(calls, [('abc', 'Test entry')]);
    });

    test("the service's refusal is passed through verbatim", () async {
      final out = await runClientSoftDelete(
        client: caseRow(),
        confirm: () async => ArchiveDialogResult.confirmedWith(null),
        execute: (_, _) async =>
            throw const ClientSoftDeleteRefused('already deleted'),
      );
      expect(out.kind, ClientSoftDeleteOutcomeKind.failed);
      expect(out.message, 'already deleted');
    });

    test('any other error is reported, not swallowed', () async {
      final out = await runClientSoftDelete(
        client: caseRow(),
        confirm: () async => ArchiveDialogResult.confirmedWith(null),
        execute: (_, _) async => throw StateError('offline'),
      );
      expect(out.kind, ClientSoftDeleteOutcomeKind.failed);
      expect(out.message, contains('offline'));
    });

    test('a missing id fails in words before confirm', () async {
      var touched = 0;
      final out = await runClientSoftDelete(
        client: {'is_trial_case': false},
        confirm: () async {
          touched++;
          return ArchiveDialogResult.confirmedWith(null);
        },
        execute: (_, _) async => touched++,
      );
      expect(out.kind, ClientSoftDeleteOutcomeKind.failed);
      expect(out.message, contains('no id'));
      expect(touched, 0);
    });
  });

  group('AssessmentCaseCard — one kebab, never the same item for both', () {
    Future<void> openMenu(WidgetTester tester) async {
      await tester.tap(find.byIcon(Icons.more_horiz));
      await tester.pumpAndSettle();
    }

    testWidgets('real row + onDelete → "Delete", calls back', (tester) async {
      var called = 0;
      await tester.pumpWidget(host(AssessmentCaseCard(
        client: caseRow(),
        onTap: () {},
        onDelete: () => called++,
      )));
      await openMenu(tester);
      expect(find.text('Delete'), findsOneWidget);
      expect(find.text('Delete permanently'), findsNothing);
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(called, 1);
    });

    testWidgets('trial row + onDelete only → no kebab (a trial run never '
        'gets the recoverable path)', (tester) async {
      await tester.pumpWidget(host(AssessmentCaseCard(
        client: trialRow(),
        onTap: () {},
        onDelete: () => fail('unreachable'),
      )));
      expect(find.byIcon(Icons.more_horiz), findsNothing);
    });

    testWidgets('real row + BOTH callbacks → only "Delete"', (tester) async {
      var soft = 0;
      await tester.pumpWidget(host(AssessmentCaseCard(
        client: caseRow(),
        onTap: () {},
        onDelete: () => soft++,
        onDeleteTrial: () => fail('a real row must never hard-delete'),
      )));
      await openMenu(tester);
      expect(find.byType(PopupMenuItem<String>), findsOneWidget);
      expect(find.text('Delete'), findsOneWidget);
      expect(find.text('Delete permanently'), findsNothing);
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(soft, 1);
    });

    testWidgets('trial row + BOTH callbacks → only "Delete permanently"',
        (tester) async {
      var hard = 0;
      await tester.pumpWidget(host(AssessmentCaseCard(
        client: trialRow(),
        onTap: () {},
        onDelete: () => fail('a trial run must never soft-delete'),
        onDeleteTrial: () => hard++,
      )));
      await openMenu(tester);
      expect(find.byType(PopupMenuItem<String>), findsOneWidget);
      expect(find.text('Delete permanently'), findsOneWidget);
      await tester.tap(find.text('Delete permanently'));
      await tester.pumpAndSettle();
      expect(hard, 1);
    });
  });

  group('ClientsRosterRow — kebab only when onDelete is given', () {
    testWidgets('with onDelete: "Delete" item calls back', (tester) async {
      var called = 0;
      await tester.pumpWidget(host(ClientsRosterRow(
        entry: rosterEntry(therapyRow()),
        isMobile: false,
        isLast: true,
        onTap: () {},
        onDelete: () => called++,
      )));
      expect(find.byIcon(Icons.more_horiz), findsOneWidget);
      await tester.tap(find.byIcon(Icons.more_horiz));
      await tester.pumpAndSettle();
      expect(find.text('Delete'), findsOneWidget);
      expect(find.text('Archive'), findsNothing);
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(called, 1);
    });

    testWidgets('without onDelete: no kebab', (tester) async {
      await tester.pumpWidget(host(ClientsRosterRow(
        entry: rosterEntry(therapyRow()),
        isMobile: false,
        isLast: true,
        onTap: () {},
      )));
      expect(find.byIcon(Icons.more_horiz), findsNothing);
    });
  });

  group('Undo snackbar — reversible, so it says so', () {
    testWidgets('Undo runs the restore, then settles', (tester) async {
      var undone = 0, settled = 0;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (ctx) => ElevatedButton(
              onPressed: () => showClientDeletedUndo(
                ctx,
                message: 'Client deleted. It can be restored.',
                onUndo: () async => undone++,
                onSettled: () => settled++,
              ),
              child: const Text('go'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('go'));
      // Let the bar finish sliding in before tapping its action.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 750));
      expect(find.text('Client deleted. It can be restored.'), findsOneWidget);
      expect(find.widgetWithText(SnackBarAction, 'Undo'), findsOneWidget);
      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect(undone, 1);
      expect(settled, 1);
    });
  });
}
