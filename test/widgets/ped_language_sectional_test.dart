// test/widgets/ped_language_sectional_test.dart
//
// Step 2 of the SectionalCapture extraction: explicit re-verification
// of the four async adversarial findings against the NEW plumbing —
// the REAL pedLanguageSectionalConfig + the REAL shipped ASHA dataset,
// driven through SectionalCaptureController with a fake persistence
// layer. Each finding has its own named test.

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:cue/models/asha_milestone_library.dart';
import 'package:cue/services/ped_language_assessment_service.dart';
import 'package:cue/widgets/assessment/sectional_capture.dart';

AshaMilestoneLibrary realLibrary() => AshaMilestoneLibrary.fromJsonString(
    File('assets/data/asha_language_milestones_0_5.json').readAsStringSync());

/// Fake ped persistence: same contract as PedLanguageSectionalStore,
/// no Supabase. Seeds real band content via the service's own pure
/// seedRowsForKeys, so the marks carry the genuine dataset rows.
class FakePedStore implements SectionalCompletionCapableStore<PedLanguageMark> {
  final AshaAgeBand band;
  final AshaMilestoneLibrary library;
  final List<PedLanguageMark> serverRows = [];
  final Map<String, DateTime?> completedAt = {
    for (final s in kAshaSections) s: null,
  };
  final List<String> calls = [];
  Set<Object>? lastSeedKeys;
  List<String>? lastUnmarkedRowIds;
  bool failCompletion = false;
  Completer<void>? holdCompletion;
  int _nextId = 0;

  FakePedStore(this.band, this.library);

  @override
  Future<SectionalSnapshot<PedLanguageMark>> load() async {
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
    for (final row in PedLanguageAssessmentService.seedRowsForKeys(
        'fake-assessment', band, library, missingSeedKeys)) {
      serverRows.add(PedLanguageMark(
        id: 'm${_nextId++}',
        section: row['section'] as String,
        order: row['milestone_order'] as int,
        text: row['milestone_text'] as String,
        example: row['example_text'] as String?,
        status: null,
        evidence: null,
      ));
    }
  }

  @override
  Future<DateTime?> persistCompletion({
    required String sectionId,
    required List<String> unmarkedRowIds,
  }) async {
    calls.add('complete($sectionId)');
    if (holdCompletion != null) await holdCompletion!.future;
    if (failCompletion) throw StateError('completion write failed');
    lastUnmarkedRowIds = unmarkedRowIds;
    // The "server" stamp the write recorded, handed back like the real
    // store does (it re-reads the parent after the atomic RPC).
    final stamp = DateTime.now();
    completedAt[sectionId] = stamp;
    return stamp;
  }
}

Future<void> pump([int turns = 5]) async {
  for (var i = 0; i < turns; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  final lib = realLibrary();
  final band = lib.bandById('2_to_3y')!; // real counts: 3 / 8 / 1

  Future<(SectionalCaptureController<PedLanguageMark>, FakePedStore)>
      boot({List<Object> preSeeded = const []}) async {
    final store = FakePedStore(band, lib);
    if (preSeeded.isNotEmpty) {
      await store.insertSeedRows(preSeeded.toSet());
      store.calls.clear();
      store.lastSeedKeys = null;
    }
    final c = SectionalCaptureController<PedLanguageMark>(
      config: pedLanguageSectionalConfig(band),
      store: store,
    );
    await c.bootstrap();
    return (c, store);
  }

  group('the four async findings, re-verified on the new plumbing', () {
    test(
        'FINDING 1: double-tap on Done cannot complete the next, '
        'unreviewed section', () async {
      final (c, store) = await boot();

      // Tap 1 in flight, tap 2 lands 150 ms later on the same button.
      store.holdCompletion = Completer<void>();
      final first = c.complete('speech');
      await pump();
      final second = await c.complete('speech');
      expect(second.outcome, SectionalCompletionOutcome.refusedBusy);
      store.holdCompletion!.complete();
      expect((await first).outcome, SectionalCompletionOutcome.completed);

      // The state has advanced to 'language' — the classic double-tap
      // window. A stale tap still belongs to speech's button and is
      // keyed on it: a named no-op that cannot touch language.
      final stale = await c.complete('speech');
      expect(stale.outcome, SectionalCompletionOutcome.alreadyCompleted);
      expect(c.isCompleted('language'), isFalse);
      expect(store.calls.where((x) => x.startsWith('complete(')).toList(),
          ['complete(speech)']);
      // No path from this surface ever completed an unreviewed section.
    });

    test(
        'FINDING 2: network drop between parent-insert and milestone-seed '
        'self-heals — no permanent "0 of 0"', () async {
      // The exact bricking scenario: parent exists, ZERO rows.
      final (empty, emptyStore) = await boot();
      expect(emptyStore.lastSeedKeys!.length, 12); // full 2_to_3y set
      expect(empty.rowsIn('speech').length, 3);
      expect(empty.rowsIn('language').length, 8);
      expect(empty.rowsIn('literacy').length, 1);

      // And the harder case the old rows.isEmpty check could NOT heal:
      // a PARTIAL seed (speech landed, the drop hit before the rest).
      final (partial, partialStore) = await boot(preSeeded: [
        ('speech', 1), ('speech', 2), ('speech', 3),
      ]);
      expect(partialStore.lastSeedKeys,
          {for (final k in const [1, 2, 3, 4, 5, 6, 7, 8]) ('language', k),
              ('literacy', 1)});
      expect(partial.rowsIn('speech').length, 3);
      expect(partial.rowsIn('language').length, 8);
      expect(partial.rowsIn('literacy').length, 1);
    });

    test(
        'FINDING 3: Done cannot race in-flight card saves — the record '
        'cannot diverge from the screen', () async {
      final (c, store) = await boot();

      // The clinician marks a speech milestone; its save is in flight
      // on a slow link when she taps Done.
      final mark = c.rowsIn('speech').first;
      mark.status = 'present';
      mark.evidence = 'observed';
      final gate = Completer<void>();
      unawaited(c.trackRowSave(mark.id, () => gate.future));

      final completion = c.complete('speech');
      await pump();
      expect(store.calls.where((x) => x.startsWith('complete(')), isEmpty,
          reason: 'the completion write must wait for the in-flight save');

      gate.complete();
      final result = await completion;
      expect(result.outcome, SectionalCompletionOutcome.completed);
      // The unmarked list was computed AFTER the drain, from the same
      // screen state she saw: the freshly marked row is NOT in it.
      expect(store.lastUnmarkedRowIds, isNot(contains(mark.id)));
      expect(store.lastUnmarkedRowIds!.length,
          c.rowsIn('speech').length - 1);

      // And when the in-flight save FAILS instead of landing, the
      // record still cannot diverge: completion refuses, naming the row.
      final (c2, store2) = await boot();
      final mark2 = c2.rowsIn('speech').first;
      mark2.status = 'present';
      final gate2 = Completer<void>();
      final save2 = c2.trackRowSave(mark2.id, () async {
        await gate2.future;
        throw StateError('failed mid-drain');
      });
      final completion2 = c2.complete('speech');
      await pump();
      gate2.complete();
      final refused = await completion2;
      expect(refused.outcome, SectionalCompletionOutcome.refusedDirty);
      expect(refused.dirtyRowIds, [mark2.id]);
      expect(store2.calls.where((x) => x.startsWith('complete(')), isEmpty);
      await expectLater(save2, throwsA(isA<StateError>()));
    });

    test(
        'FINDING 4: a failed Done rolls back cleanly and never claims '
        '"on record"', () async {
      final (c, store) = await boot();
      store.failCompletion = true;

      final unmarkedBefore =
          c.rowsIn('speech').where((m) => m.status == null).toList();
      final result = await c.complete('speech');
      expect(result.outcome, SectionalCompletionOutcome.rolledBack);
      expect(result.error, isA<StateError>());
      for (final m in unmarkedBefore) {
        expect(m.status, isNull, reason: 'fill reverted');
      }
      expect(c.isCompleted('speech'), isFalse, reason: 'no "on record"');
      expect(c.currentSectionId, 'speech', reason: 'position reverted');
      expect(c.completing, isFalse, reason: 'Done affordance is back');

      // The retry path the rollback preserves:
      store.failCompletion = false;
      expect((await c.complete('speech')).outcome,
          SectionalCompletionOutcome.completed);
    });
  });

  group('real config wiring', () {
    test('expectedSeedKeys for the real 2_to_3y band are exactly its '
        '(section, order) pairs', () {
      final keys = pedLanguageSectionalConfig(band).expectedSeedKeys;
      expect(keys.length, 12);
      expect(keys, contains(('speech', 3)));
      expect(keys, contains(('language', 8)));
      expect(keys, contains(('literacy', 1)));
      expect(keys, isNot(contains(('speech', 4))));
    });

    test('completion fill and revert are absent ↔ null and always clear '
        'evidence', () {
      final spec = pedLanguageSectionalConfig(band).completion!;
      final m = PedLanguageMark(
          id: 'x',
          section: 'speech',
          order: 1,
          text: 't',
          example: null,
          status: null,
          evidence: null);
      expect(spec.isUnmarked(m), isTrue);
      spec.applyCompletionFill(m);
      expect(m.status, 'absent');
      spec.revertCompletionFill(m);
      expect(m.status, isNull);
      expect(m.evidence, isNull);
    });

    test('seedRowsForKeys filters the pure full-seed to exactly the '
        'missing keys, provenance intact', () {
      final rows = PedLanguageAssessmentService.seedRowsForKeys(
          'a1', band, lib, {('language', 2), ('literacy', 1)});
      expect(rows.length, 2);
      for (final r in rows) {
        expect(r['norm_reference'], lib.source);
        expect(r['library_version'], lib.version);
      }
      expect(rows.map((r) => (r['section'], r['milestone_order'])).toSet(),
          {('language', 2), ('literacy', 1)});
    });
  });
}
