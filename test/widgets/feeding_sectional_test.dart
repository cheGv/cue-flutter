// test/widgets/feeding_sectional_test.dart
//
// Step 3 of the SectionalCapture extraction — the GENERALISATION test:
// feeding adopts the queue + seed core with NO completion semantics.
// Driven through the REAL feedingSectionalConfig + the REAL
// kFeedingLadderBands, with a core-only fake store. Proves the halves
// stand alone: per-key ladder reconciliation, per-field-group dirty
// units with retained-closure retry, and LOUD refusal of the
// completion API feeding never wired.


import 'package:flutter_test/flutter_test.dart';
import 'package:cue/constants/feeding_ladder_content.dart';
import 'package:cue/services/feeding_assessment_service.dart';
import 'package:cue/widgets/assessment/sectional_capture.dart';

/// Core-only fake: load + seed, no completion capability — exactly the
/// open-ended store shape FeedingLadderSectionalStore has.
class FakeLadderStore implements SectionalCaptureStore<Map<String, dynamic>> {
  final List<Map<String, dynamic>> serverRows = [];
  Set<Object>? lastSeedKeys;
  int _nextId = 0;

  @override
  Future<SectionalSnapshot<Map<String, dynamic>>> load() async =>
      SectionalSnapshot(
        rows: List.of(serverRows),
        completedAt: const {'ladder': null},
      );

  @override
  Future<void> insertSeedRows(Set<Object> missingSeedKeys) async {
    lastSeedKeys = missingSeedKeys;
    for (final band in kFeedingLadderBands) {
      if (!missingSeedKeys.contains(band.key)) continue;
      serverRows.add({
        'id': 'b${_nextId++}',
        ...FeedingAssessmentService.seedRowFor(band),
      });
    }
  }
}

void main() {
  Future<(SectionalCaptureController<Map<String, dynamic>>, FakeLadderStore)>
      boot({Iterable<String> preSeeded = const []}) async {
    final store = FakeLadderStore();
    if (preSeeded.isNotEmpty) {
      await store.insertSeedRows(preSeeded.toSet());
      store.lastSeedKeys = null;
    }
    final c = SectionalCaptureController<Map<String, dynamic>>(
      config: feedingSectionalConfig(),
      store: store,
    );
    await c.bootstrap();
    return (c, store);
  }

  group('per-key ladder seed reconciliation (real band constants)', () {
    test('empty store seeds all seven bands by band_key', () async {
      final (c, store) = await boot();
      expect(store.lastSeedKeys, {for (final b in kFeedingLadderBands) b.key});
      expect(c.rowsIn('ladder').length, kFeedingLadderBands.length);
      expect(kFeedingLadderBands.length, 7);
    });

    test('a PARTIAL seed heals — only the missing band keys are inserted',
        () async {
      final first3 = kFeedingLadderBands.take(3).map((b) => b.key).toList();
      final (c, store) = await boot(preSeeded: first3);
      expect(store.lastSeedKeys,
          {for (final b in kFeedingLadderBands.skip(3)) b.key});
      expect(c.rowsIn('ladder').length, 7);
    });

    test('a complete ladder inserts nothing', () async {
      final (_, store) =
          await boot(preSeeded: kFeedingLadderBands.map((b) => b.key));
      expect(store.lastSeedKeys, isNull);
    });
  });

  group('queue + dirty with per-field-group units', () {
    test('two field-group failures on ONE row are independent dirty '
        'units — an earlier failed field is never lost to a later one',
        () async {
      final (c, _) = await boot();
      final rowId = c.rowsIn('ladder').first['id'] as String;
      final markingUnit = feedingSaveUnitId(rowId, {'clinician_marking': 'x'});
      final notesUnit = feedingSaveUnitId(rowId, {'notes': 'x'});

      await expectLater(
          c.trackRowSave(markingUnit, () async => throw StateError('offline')),
          throwsA(isA<StateError>()));
      await expectLater(
          c.trackRowSave(notesUnit, () async => throw StateError('offline')),
          throwsA(isA<StateError>()));
      expect(c.dirtyRowIds, {markingUnit, notesUnit});

      // Retry replays BOTH retained closures.
      var online = false;
      // Re-register with shared-flag closures so the retry can succeed.
      await expectLater(
          c.trackRowSave(markingUnit, () async {
            if (!online) throw StateError('offline');
          }),
          throwsA(isA<StateError>()));
      await expectLater(
          c.trackRowSave(notesUnit, () async {
            if (!online) throw StateError('offline');
          }),
          throwsA(isA<StateError>()));
      online = true;
      expect(await c.retryDirty(), isEmpty);
      expect(c.dirtyRowIds, isEmpty);
    });

    test('a success on one unit leaves the other unit dirty', () async {
      final (c, _) = await boot();
      final rowId = c.rowsIn('ladder').first['id'] as String;
      final unitA = feedingSaveUnitId(rowId, {'clinician_marking': 'x'});
      final unitB = feedingSaveUnitId(rowId, {'notes': 'x'});

      await expectLater(
          c.trackRowSave(unitA, () async => throw StateError('offline')),
          throwsA(isA<StateError>()));
      await expectLater(
          c.trackRowSave(unitB, () async => throw StateError('offline')),
          throwsA(isA<StateError>()));
      await c.trackRowSave(unitA, () async {});
      expect(c.dirtyRowIds, {unitB});
    });
  });

  group('completion stays un-wired and LOUD', () {
    test('the real feeding config carries no completion spec', () {
      expect(feedingSectionalConfig().completion, isNull);
    });

    test('complete() through the real feeding wiring throws StateError',
        () async {
      final (c, _) = await boot();
      expect(() => c.complete('ladder'), throwsStateError);
    });

    test('markedCount() likewise', () async {
      final (c, _) = await boot();
      expect(() => c.markedCount('ladder'), throwsStateError);
    });
  });

  group('pure unit-id helpers', () {
    test('feedingSaveUnitId is field-order-stable', () {
      expect(feedingSaveUnitId('r1', {'b': 1, 'a': 2}),
          feedingSaveUnitId('r1', {'a': 9, 'b': 8}));
      expect(feedingSaveUnitId('parent', {'jaw_stability': 'x'}),
          'parent::jaw_stability');
    });

    test('feedingUnsavedUnitMatchesOwner matches its owner exactly — '
        'no prefix false-positives across owners', () {
      final unit = feedingSaveUnitId('parent', {'jaw_stability': 'x'});
      expect(feedingUnsavedUnitMatchesOwner(unit, 'parent'), isTrue);
      expect(feedingUnsavedUnitMatchesOwner(unit, 'par'), isFalse);
      final rowUnit = feedingSaveUnitId('row-12', {'notes': 'x'});
      expect(feedingUnsavedUnitMatchesOwner(rowUnit, 'row-12'), isTrue);
      expect(feedingUnsavedUnitMatchesOwner(rowUnit, 'row-1'), isFalse);
    });
  });
}
