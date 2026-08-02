// test/widgets/sectional_capture_controller_test.dart
//
// Headless coverage for SectionalCaptureController against a fake
// store: all five completion outcomes (completed, alreadyCompleted,
// refusedBusy, refusedDirty, rolledBack), the in-flight queue drain,
// per-key seed reconciliation, and full rollback on failed completion.
// These pin the four extracted adversarial findings plus the
// refusedDirty contract hardening (2026-07-29).

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:cue/widgets/assessment/sectional_capture.dart';

class TestRow {
  final String id;
  final String section;
  final int order;
  String? status; // null = unmarked (not yet captured)

  TestRow(this.id, this.section, this.order, [this.status]);
}

typedef SeedKey = (String, int);

class FakeStore implements SectionalCaptureStore<TestRow> {
  final List<TestRow> serverRows = [];
  final Map<String, DateTime?> completedAt = {
    'speech': null,
    'language': null,
  };

  /// Ordered call log — ordering assertions read this.
  final List<String> calls = [];

  Set<Object>? lastSeedKeys;
  String? lastCompletedSection;
  List<String>? lastUnmarkedRowIds;

  bool failCompletion = false;

  /// When set, persistCompletion blocks until released.
  Completer<void>? holdCompletion;

  int _nextId = 100;

  @override
  Future<SectionalSnapshot<TestRow>> load() async {
    calls.add('load');
    return SectionalSnapshot(
      rows: List.of(serverRows),
      completedAt: Map.of(completedAt),
    );
  }

  @override
  Future<void> insertSeedRows(Set<Object> missingSeedKeys) async {
    calls.add('seed(${missingSeedKeys.length})');
    lastSeedKeys = missingSeedKeys;
    for (final k in missingSeedKeys) {
      final key = k as SeedKey;
      serverRows.add(TestRow('r${_nextId++}', key.$1, key.$2));
    }
  }

  @override
  Future<void> persistCompletion({
    required String sectionId,
    required List<String> unmarkedRowIds,
  }) async {
    calls.add('complete($sectionId)');
    if (holdCompletion != null) await holdCompletion!.future;
    if (failCompletion) throw StateError('completion write failed');
    lastCompletedSection = sectionId;
    lastUnmarkedRowIds = unmarkedRowIds;
    completedAt[sectionId] = DateTime.now();
  }
}

SectionalCaptureConfig<TestRow> config() => SectionalCaptureConfig<TestRow>(
      sectionIds: const ['speech', 'language'],
      rowId: (r) => r.id,
      sectionOf: (r) => r.section,
      seedKey: (r) => (r.section, r.order),
      expectedSeedKeys: const {
        ('speech', 1),
        ('speech', 2),
        ('language', 1),
      },
      isUnmarked: (r) => r.status == null,
      applyCompletionFill: (r) => r.status = 'absent',
      revertCompletionFill: (r) => r.status = null,
    );

/// Pump the microtask/timer queue a few turns.
Future<void> pump([int turns = 5]) async {
  for (var i = 0; i < turns; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  group('bootstrap — per-key seed reconciliation', () {
    test('empty store seeds the full expected key set', () async {
      final store = FakeStore();
      final c = SectionalCaptureController(config: config(), store: store);
      await c.bootstrap();
      expect(store.lastSeedKeys, {('speech', 1), ('speech', 2), ('language', 1)});
      expect(c.rowsIn('speech').length, 2);
      expect(c.rowsIn('language').length, 1);
      expect(store.calls, ['load', 'seed(3)', 'load']);
    });

    test('PARTIAL seed heals — only the missing keys are inserted', () async {
      final store = FakeStore()
        ..serverRows.add(TestRow('a', 'speech', 1)); // interrupted seed
      final c = SectionalCaptureController(config: config(), store: store);
      await c.bootstrap();
      expect(store.lastSeedKeys, {('speech', 2), ('language', 1)});
      expect(c.rowsIn('speech').length, 2);
      expect(c.rowsIn('language').length, 1);
    });

    test('complete row set inserts nothing and loads once', () async {
      final store = FakeStore()
        ..serverRows.addAll([
          TestRow('a', 'speech', 1),
          TestRow('b', 'speech', 2),
          TestRow('c', 'language', 1),
        ]);
      final c = SectionalCaptureController(config: config(), store: store);
      await c.bootstrap();
      expect(store.lastSeedKeys, isNull);
      expect(store.calls, ['load']);
    });

    test('clinician-added rows outside the expected set are kept, never '
        'treated as missing', () async {
      final store = FakeStore()
        ..serverRows.addAll([
          TestRow('a', 'speech', 1),
          TestRow('b', 'speech', 2),
          TestRow('c', 'language', 1),
          TestRow('x', 'speech', 99), // clinician-added
        ]);
      final c = SectionalCaptureController(config: config(), store: store);
      await c.bootstrap();
      expect(store.lastSeedKeys, isNull);
      expect(c.rowsIn('speech').length, 3);
    });

    test('opens on the first incomplete section; all-done opens on the '
        'first', () async {
      final store = FakeStore()
        ..serverRows.addAll([
          TestRow('a', 'speech', 1),
          TestRow('b', 'speech', 2),
          TestRow('c', 'language', 1),
        ])
        ..completedAt['speech'] = DateTime(2026);
      final c = SectionalCaptureController(config: config(), store: store);
      await c.bootstrap();
      expect(c.currentSectionId, 'language');

      store.completedAt['language'] = DateTime(2026);
      final c2 = SectionalCaptureController(config: config(), store: store);
      await c2.bootstrap();
      expect(c2.currentSectionId, 'speech');
      expect(c2.allCompleted, isTrue);
    });
  });

  group('in-flight save queue + dirty set', () {
    late FakeStore store;
    late SectionalCaptureController<TestRow> c;

    setUp(() async {
      store = FakeStore();
      c = SectionalCaptureController(config: config(), store: store);
      await c.bootstrap();
    });

    test('successful save: tracked while in flight, then cleared, never '
        'dirty', () async {
      final gate = Completer<void>();
      final fut = c.trackRowSave('a', () => gate.future);
      expect(c.pendingSaveCount, 1);
      gate.complete();
      await fut;
      await pump();
      expect(c.pendingSaveCount, 0);
      expect(c.dirtyRowIds, isEmpty);
    });

    test('failed save: rethrows to the caller AND marks the row dirty',
        () async {
      final fut =
          c.trackRowSave('a', () async => throw StateError('save failed'));
      await expectLater(fut, throwsA(isA<StateError>()));
      expect(c.dirtyRowIds, {'a'});
      expect(c.pendingSaveCount, 0);
    });

    test('a later successful save of the same row clears its dirty mark',
        () async {
      await expectLater(
          c.trackRowSave('a', () async => throw StateError('boom')),
          throwsA(isA<StateError>()));
      expect(c.dirtyRowIds, {'a'});
      await c.trackRowSave('a', () async {});
      expect(c.dirtyRowIds, isEmpty);
    });

    test('drainPendingSaves waits for every tracked save', () async {
      final gate1 = Completer<void>();
      final gate2 = Completer<void>();
      unawaited(c.trackRowSave('a', () => gate1.future));
      unawaited(c.trackRowSave('b', () => gate2.future));
      var drained = false;
      final drain = c.drainPendingSaves().then((_) => drained = true);
      await pump();
      expect(drained, isFalse);
      gate1.complete();
      await pump();
      expect(drained, isFalse);
      gate2.complete();
      await drain;
      expect(drained, isTrue);
    });
  });

  group('complete() — the five outcomes', () {
    late FakeStore store;
    late SectionalCaptureController<TestRow> c;

    setUp(() async {
      store = FakeStore();
      c = SectionalCaptureController(config: config(), store: store);
      await c.bootstrap();
    });

    test('completed: fills unmarked rows, passes the EXPLICIT id list, '
        'stamps, advances', () async {
      final speechRows = c.rowsIn('speech');
      speechRows.first.status = 'present'; // marked by the clinician
      final unmarked = speechRows.last;

      final result = await c.complete('speech');
      expect(result.outcome, SectionalCompletionOutcome.completed);
      expect(store.lastCompletedSection, 'speech');
      expect(store.lastUnmarkedRowIds, [unmarked.id]);
      expect(unmarked.status, 'absent'); // optimistic fill applied
      expect(c.isCompleted('speech'), isTrue);
      expect(c.currentSectionId, 'language'); // advanced
    });

    test('alreadyCompleted: a re-tap (or stale button) is a no-op and '
        'NEVER touches the next section', () async {
      await c.complete('speech');
      final callsAfterFirst = List.of(store.calls);

      // The double-tap scenario from the original finding: the state
      // has advanced to 'language', but the tap belonged to speech's
      // button. Keyed on the argument, it cannot complete language.
      final result = await c.complete('speech');
      expect(result.outcome, SectionalCompletionOutcome.alreadyCompleted);
      expect(store.calls, callsAfterFirst); // zero further store calls
      expect(c.isCompleted('language'), isFalse);
    });

    test('refusedBusy: a second tap while the first completion is in '
        'flight is absorbed', () async {
      store.holdCompletion = Completer<void>();
      final first = c.complete('speech');
      await pump();
      final second = await c.complete('speech');
      expect(second.outcome, SectionalCompletionOutcome.refusedBusy);
      // Also structurally unable to hit the next section mid-flight:
      final other = await c.complete('language');
      expect(other.outcome, SectionalCompletionOutcome.refusedBusy);
      store.holdCompletion!.complete();
      final firstResult = await first;
      expect(firstResult.outcome, SectionalCompletionOutcome.completed);
      expect(store.calls.where((x) => x.startsWith('complete(')).length, 1);
    });

    test('refusedDirty: a failed row save blocks completion of ITS '
        'section, naming the row; retry then completes', () async {
      final row = c.rowsIn('speech').first;
      await expectLater(
          c.trackRowSave(row.id, () async => throw StateError('boom')),
          throwsA(isA<StateError>()));

      final refused = await c.complete('speech');
      expect(refused.outcome, SectionalCompletionOutcome.refusedDirty);
      expect(refused.dirtyRowIds, [row.id]);
      expect(c.isCompleted('speech'), isFalse);
      expect(store.calls.where((x) => x.startsWith('complete(')), isEmpty);

      // Retry lands → dirty clears → completion proceeds.
      await c.trackRowSave(row.id, () async {});
      final ok = await c.complete('speech');
      expect(ok.outcome, SectionalCompletionOutcome.completed);
    });

    test('refusedDirty scope: a dirty row in ANOTHER section does not '
        'block this one', () async {
      final langRow = c.rowsIn('language').first;
      await expectLater(
          c.trackRowSave(langRow.id, () async => throw StateError('boom')),
          throwsA(isA<StateError>()));

      final result = await c.complete('speech');
      expect(result.outcome, SectionalCompletionOutcome.completed);
      expect(c.dirtyRowIds, {langRow.id}); // still tracked for language
    });

    test('a save that FAILS during the drain is caught by the dirty '
        'check — completion refuses instead of declaring', () async {
      final row = c.rowsIn('speech').first;
      final gate = Completer<void>();
      // In flight when Done is tapped; will fail while complete() drains.
      final saveFut = c.trackRowSave(row.id, () async {
        await gate.future;
        throw StateError('failed mid-drain');
      });
      final completion = c.complete('speech');
      await pump();
      gate.complete();
      final result = await completion;
      expect(result.outcome, SectionalCompletionOutcome.refusedDirty);
      expect(result.dirtyRowIds, [row.id]);
      await expectLater(saveFut, throwsA(isA<StateError>()));
    });

    test('rolledBack: store failure reverts fill, stamp, and position — '
        'and a retry can then succeed', () async {
      store.failCompletion = true;
      final unmarked =
          c.rowsIn('speech').where((r) => r.status == null).toList();
      final result = await c.complete('speech');
      expect(result.outcome, SectionalCompletionOutcome.rolledBack);
      expect(result.error, isA<StateError>());
      for (final r in unmarked) {
        expect(r.status, isNull); // fill reverted
      }
      expect(c.isCompleted('speech'), isFalse); // stamp reverted
      expect(c.currentSectionId, 'speech'); // position reverted
      expect(c.completing, isFalse); // Done affordance is back

      store.failCompletion = false;
      final retry = await c.complete('speech');
      expect(retry.outcome, SectionalCompletionOutcome.completed);
    });

    test('unknown section id is a wiring bug and throws', () {
      expect(() => c.complete('nope'), throwsArgumentError);
    });
  });

  group('complete() drains the queue before deciding', () {
    test('persistCompletion is NOT called until in-flight saves land',
        () async {
      final store = FakeStore();
      final c = SectionalCaptureController(config: config(), store: store);
      await c.bootstrap();

      final gate = Completer<void>();
      unawaited(c.trackRowSave('a', () => gate.future));

      final completion = c.complete('speech');
      await pump();
      expect(store.calls.where((x) => x.startsWith('complete(')), isEmpty,
          reason: 'completion must wait for the in-flight save');

      gate.complete();
      final result = await completion;
      expect(result.outcome, SectionalCompletionOutcome.completed);
      expect(store.calls.where((x) => x.startsWith('complete(')).length, 1);
    });
  });

  group('dirty-set exit paths (rule decided 2026-07-29)', () {
    late FakeStore store;
    late SectionalCaptureController<TestRow> c;
    late String rowId;

    setUp(() async {
      store = FakeStore();
      c = SectionalCaptureController(config: config(), store: store);
      await c.bootstrap();
      rowId = c.rowsIn('speech').first.id;
    });

    test('THE RULE: dirty clears only on a successful persist round-trip '
        '— a failed save of the reverted value keeps the row dirty',
        () async {
      // Save of the new value fails → dirty.
      await expectLater(
          c.trackRowSave(rowId, () async => throw StateError('offline')),
          throwsA(isA<StateError>()));
      expect(c.dirtyRowIds, {rowId});

      // The clinician reverts the row on screen; the revert fires its
      // own save (as every surface does) — and it ALSO fails. The
      // screen may now equal the DB by value, but the round-trip never
      // confirmed it: still dirty.
      await expectLater(
          c.trackRowSave(rowId, () async => throw StateError('offline')),
          throwsA(isA<StateError>()));
      expect(c.dirtyRowIds, {rowId});

      // Only a successful round-trip clears it.
      await c.trackRowSave(rowId, () async {});
      expect(c.dirtyRowIds, isEmpty);
    });

    test('retryDirty re-runs the RETAINED closure — the surface supplies '
        'nothing new — and completion then proceeds', () async {
      var attempts = 0;
      persist() async {
        attempts += 1;
        if (attempts == 1) throw StateError('offline');
      }

      await expectLater(
          c.trackRowSave(rowId, persist), throwsA(isA<StateError>()));
      expect(c.dirtyRowIds, {rowId});
      expect((await c.complete('speech')).outcome,
          SectionalCompletionOutcome.refusedDirty);

      final stillDirty = await c.retryDirty();
      expect(stillDirty, isEmpty);
      expect(attempts, 2); // the retained closure ran again
      expect(c.dirtyRowIds, isEmpty);
      expect((await c.complete('speech')).outcome,
          SectionalCompletionOutcome.completed);
    });

    test('offline dead end is NOT a dead end: retryDirty reports the '
        'still-dirty ids, never throws, and stays repeatable until '
        'connectivity returns', () async {
      var online = false;
      persist() async {
        if (!online) throw StateError('offline');
      }

      await expectLater(
          c.trackRowSave(rowId, persist), throwsA(isA<StateError>()));

      // Offline retry: reports the row, keeps the refusal honest.
      expect(await c.retryDirty(), {rowId});
      expect(c.dirtyRowIds, {rowId});
      final refused = await c.complete('speech');
      expect(refused.outcome, SectionalCompletionOutcome.refusedDirty);
      expect(refused.dirtyRowIds, [rowId]);

      // Second offline retry — repeatable, still no exception storm.
      expect(await c.retryDirty(), {rowId});

      // Connectivity returns → same affordance now clears the path.
      online = true;
      expect(await c.retryDirty(), isEmpty);
      expect((await c.complete('speech')).outcome,
          SectionalCompletionOutcome.completed);
    });

    test('retryDirty re-runs the LATEST closure for a row, so the retry '
        'persists the current screen state (v2, never v1)', () async {
      var online = false;
      final persisted = <String>[];
      Future<void> Function() persistOf(String value) => () async {
            if (!online) throw StateError('offline');
            persisted.add(value);
          };

      await expectLater(
          c.trackRowSave(rowId, persistOf('v1')),
          throwsA(isA<StateError>()));
      // The clinician edits the row again while offline; v2 also fails
      // and becomes the retained closure.
      await expectLater(
          c.trackRowSave(rowId, persistOf('v2')),
          throwsA(isA<StateError>()));

      online = true;
      expect(await c.retryDirty(), isEmpty);
      expect(persisted, ['v2']); // the retry ran v2's closure, never v1's
      expect(c.dirtyRowIds, isEmpty);
    });
  });
}
