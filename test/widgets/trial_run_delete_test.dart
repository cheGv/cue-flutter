// test/widgets/trial_run_delete_test.dart
//
// Delete affordances, Step 2 — trial-run hard delete. Covers the gate, the
// confirm/cancel branches, and the 23503 path, none of which need a
// Supabase seam:
//   - the gate as the widget the clinician sees (AssessmentCaseCard),
//   - the dialog's copy and its two exits,
//   - runTrialRunDelete's branches through plain closures,
//   - describeTrialRunDeleteBlock against the exact Postgres wording
//     captured live on sandbox 2026-09-06.
// NOT covered (no seam, by decision): the Assessing screen's own wiring of
// kebab → _deleteTrial → service, and the service's Supabase calls.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:cue/screens/assessing_screen.dart';
import 'package:cue/services/trial_run_delete_service.dart';
import 'package:cue/widgets/trial_run_delete_dialog.dart';

Widget host(Widget child) => MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );

Map<String, dynamic> trialRow({String id = 't-1'}) => {
      'id': id,
      'name': 'TRIAL RUN — Pediatric Language · 12:42',
      'clinical_area': 'pediatric-language',
      'age': 0,
      'primary_concern_verbatim': 'Trial run — exploring the surface.',
      'engagement_type': 'assessment_only',
      'engagement_status': 'in_assessment',
      'is_trial_case': true,
    };

Map<String, dynamic> realRow({String id = 'r-1'}) => {
      ...trialRow(id: id),
      'name': 'Kabir M.',
      'age': 4,
      'is_trial_case': false,
    };

// The exact strings Postgres produced on sandbox for a trial client with a
// live session (captured 2026-09-06; PostgREST forwards them unchanged).
PostgrestException fkBlock(String table) => PostgrestException(
      code: '23503',
      message: 'update or delete on table "clients" violates foreign key '
          'constraint "${table}_client_id_fkey" on table "$table"',
      details: 'Key (id)=(bd2a12d6-2cfc-4b6c-bc34-485d902a9e64) is still '
          'referenced from table "$table".',
    );

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  group('gate — the kebab exists only for trial rows', () {
    testWidgets('a trial row with onDeleteTrial grows the kebab, and its '
        'one item calls back', (tester) async {
      var called = 0;
      await tester.pumpWidget(host(AssessmentCaseCard(
        client: trialRow(),
        onTap: () {},
        onDeleteTrial: () => called++,
      )));
      expect(find.byIcon(Icons.more_horiz), findsOneWidget);

      await tester.tap(find.byIcon(Icons.more_horiz));
      await tester.pumpAndSettle();
      expect(find.text('Delete permanently'), findsOneWidget);
      // The menu offers nothing else.
      expect(find.byType(PopupMenuItem<String>), findsOneWidget);

      await tester.tap(find.text('Delete permanently'));
      await tester.pumpAndSettle();
      expect(called, 1);
    });

    testWidgets('a real row gets NO kebab even when onDeleteTrial is passed',
        (tester) async {
      await tester.pumpWidget(host(AssessmentCaseCard(
        client: realRow(),
        onTap: () {},
        onDeleteTrial: () => fail('must never be reachable for a real row'),
      )));
      expect(find.byIcon(Icons.more_horiz), findsNothing);
      expect(find.byType(PopupMenuButton<String>), findsNothing);
    });

    testWidgets('a trial row without onDeleteTrial gets no kebab either '
        '(the real list never passes one)', (tester) async {
      await tester.pumpWidget(host(AssessmentCaseCard(
        client: trialRow(),
        onTap: () {},
      )));
      expect(find.byIcon(Icons.more_horiz), findsNothing);
    });

    test('isTrialRun is the shared predicate: only an explicit true passes',
        () {
      expect(isTrialRun(trialRow()), isTrue);
      expect(isTrialRun(realRow()), isFalse);
      expect(isTrialRun({'id': 'x'}), isFalse); // flag absent
      expect(isTrialRun({'id': 'x', 'is_trial_case': null}), isFalse);
      expect(isTrialRun({'id': 'x', 'is_trial_case': 'true'}), isFalse);
    });
  });

  group('dialog — permanent vocabulary, two exits, no barrier dismiss', () {
    Future<bool?> open(WidgetTester tester) async {
      bool? result;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (ctx) => ElevatedButton(
              onPressed: () async {
                result = await showTrialRunDeleteDialog(
                  context: ctx,
                  name: 'TRIAL RUN — AAC · 18:53',
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      return result;
    }

    testWidgets('copy says permanent and never borrows archive/undo words',
        (tester) async {
      await open(tester);
      final texts = tester
          .widgetList<Text>(find.descendant(
              of: find.byType(AlertDialog), matching: find.byType(Text)))
          .map((t) => t.data ?? '')
          .join('\n');
      expect(texts, contains('TRIAL RUN — AAC · 18:53'));
      expect(texts.toLowerCase(), contains('permanent'));
      expect(texts.toLowerCase(), contains('no way to get it back'));
      expect(texts.toLowerCase(), isNot(contains('archiv')));
      expect(texts.toLowerCase(), isNot(contains('undo')));
      expect(texts.toLowerCase(), isNot(contains('restore')));
      expect(find.widgetWithText(TextButton, 'Cancel'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Delete permanently'),
          findsOneWidget);
    });

    testWidgets('tapping outside does not dismiss (barrierDismissible false)',
        (tester) async {
      await open(tester);
      await tester.tapAt(const Offset(2, 2));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
    });

    testWidgets('Cancel → false, Delete permanently → true', (tester) async {
      final results = <bool>[];
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (ctx) => ElevatedButton(
              onPressed: () async {
                results.add(await showTrialRunDeleteDialog(
                    context: ctx, name: 'x'));
              },
              child: const Text('open'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(results, [false]);

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete permanently'));
      await tester.pumpAndSettle();
      expect(results, [false, true]);
    });
  });

  group('runTrialRunDelete — branches', () {
    test('a real row is refused before confirm is ever shown', () async {
      var confirms = 0, executes = 0;
      final out = await runTrialRunDelete(
        client: realRow(),
        confirm: () async {
          confirms++;
          return true;
        },
        execute: (_) async => executes++,
      );
      expect(out.kind, TrialRunDeleteOutcomeKind.refusedNotTrial);
      expect(out.message, contains('Only a trial run'));
      expect(confirms, 0);
      expect(executes, 0);
    });

    test('cancel never reaches execute', () async {
      var executes = 0;
      final out = await runTrialRunDelete(
        client: trialRow(),
        confirm: () async => false,
        execute: (_) async => executes++,
      );
      expect(out.kind, TrialRunDeleteOutcomeKind.cancelled);
      expect(out.message, isNull);
      expect(executes, 0);
    });

    test('confirm runs execute once with the row id', () async {
      final ids = <String>[];
      final out = await runTrialRunDelete(
        client: trialRow(id: 'abc-123'),
        confirm: () async => true,
        execute: (id) async => ids.add(id),
      );
      expect(out.kind, TrialRunDeleteOutcomeKind.deleted);
      expect(ids, ['abc-123']);
    });

    test('a missing id fails in words, without confirm or execute', () async {
      var touched = 0;
      final out = await runTrialRunDelete(
        client: {'is_trial_case': true},
        confirm: () async {
          touched++;
          return true;
        },
        execute: (_) async => touched++,
      );
      expect(out.kind, TrialRunDeleteOutcomeKind.failed);
      expect(out.message, contains('no id'));
      expect(touched, 0);
    });

    test('23503 from execute comes back as words, not as an exception',
        () async {
      final out = await runTrialRunDelete(
        client: trialRow(),
        confirm: () async => true,
        execute: (_) async => throw fkBlock('sessions'),
      );
      expect(out.kind, TrialRunDeleteOutcomeKind.failed);
      expect(out.message, contains('session notes'));
      expect(out.message, contains('still in your trial runs'));
      expect(out.message, isNot(contains('23503')));
      expect(out.message, isNot(contains('violates')));
      expect(out.message, isNot(contains('foreign key')));
    });

    test("the service's own refusal is passed through verbatim", () async {
      final out = await runTrialRunDelete(
        client: trialRow(),
        confirm: () async => true,
        execute: (_) async =>
            throw const TrialRunDeleteRefused('already gone'),
      );
      expect(out.kind, TrialRunDeleteOutcomeKind.failed);
      expect(out.message, 'already gone');
    });

    test('any other error is reported, not swallowed', () async {
      final out = await runTrialRunDelete(
        client: trialRow(),
        confirm: () async => true,
        execute: (_) async => throw StateError('network down'),
      );
      expect(out.kind, TrialRunDeleteOutcomeKind.failed);
      expect(out.message, contains('network down'));
    });
  });

  group('describeTrialRunDeleteBlock — plain words per blocking table', () {
    test('sessions → session notes', () {
      expect(describeTrialRunDeleteBlock(fkBlock('sessions')),
          contains('session notes'));
    });

    test('every goal table → goals', () {
      for (final t in [
        'goals',
        'long_term_goals',
        'short_term_goals',
        'goal_plans'
      ]) {
        expect(describeTrialRunDeleteBlock(fkBlock(t)), contains('has goals'),
            reason: t);
      }
    });

    test('reasoning_threads → reasoning threads', () {
      expect(describeTrialRunDeleteBlock(fkBlock('reasoning_threads')),
          contains('reasoning threads'));
    });

    test('an unknown table is humanised, never shown raw', () {
      final msg = describeTrialRunDeleteBlock(fkBlock('some_future_table'));
      expect(msg, contains('some future table'));
      expect(msg, isNot(contains('some_future_table')));
    });

    test('message-only wording picks the LAST "on table", not "clients"',
        () {
      final e = PostgrestException(
        code: '23503',
        message: 'update or delete on table "clients" violates foreign key '
            'constraint "sessions_client_id_fkey" on table "sessions"',
      );
      final msg = describeTrialRunDeleteBlock(e);
      expect(msg, contains('session notes'));
      expect(msg, isNot(contains('clients')));
    });

    test('no table found still yields words', () {
      final e = PostgrestException(code: '23503', message: 'blocked');
      expect(describeTrialRunDeleteBlock(e), contains('other records'));
    });

    test('anything that is not a 23503 returns null', () {
      expect(
          describeTrialRunDeleteBlock(
              PostgrestException(code: '42501', message: 'denied')),
          isNull);
      expect(describeTrialRunDeleteBlock(StateError('x')), isNull);
      expect(
          describeTrialRunDeleteBlock(PostgrestException(message: 'no code')),
          isNull);
    });
  });
}
