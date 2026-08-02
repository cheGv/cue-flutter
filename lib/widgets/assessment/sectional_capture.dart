// lib/widgets/assessment/sectional_capture.dart
//
// SectionalCapture — the shared completion-lifecycle primitive for
// sectional capture surfaces. Extracted 2026-07-29 from the pediatric
// language surface, whose adversarial review earned four findings that
// were one bug in different clothes: a double-tap completing the NEXT
// unreviewed section, an orphaned parent row after a network drop
// mid-seed, Done racing in-flight card saves, and a failed Done leaving
// the UI claiming "on record". This controller owns those four
// behaviours — and only those — so no future surface re-earns them:
//
//   1. In-flight save queue: every row persist goes through
//      trackRowSave; complete() drains the queue before deciding
//      anything, so the declared record matches the screen.
//   2. Idempotent completion KEYED ON THE SECTION ID ARGUMENT — the
//      section whose button was actually pressed — never on whatever
//      the current index is at tap time. Re-taps and stale taps land in
//      named no-op outcomes, structurally unable to touch a different
//      section.
//   3. Seed self-heal: bootstrap reconciles the expected seed-key set
//      against loaded rows PER KEY (the SSD/feeding ensure-shape,
//      strictly stronger than an empty-only check) and inserts exactly
//      the missing rows. The store must make duplicate seeding loud.
//   4. Rollback on failed completion: the optimistic fill, stamp, and
//      section advance are fully reverted when the store throws, so a
//      section never reads "on record" when the DB never recorded it —
//      and the Done affordance returns.
//
// Plus one contract hardening (2026-07-29 veto on the original design):
//   5. Dirty set: a row whose save FAILED stays tracked. Toast-and-keep
//      remains the point-of-failure convention, but complete() is not
//      blind to it — it refuses with the affected row ids
//      (refusedDirty) so the surface can offer retry. A section never
//      completes while a row the clinician can see is not on record.
//      Scope: rows of the section being completed — that is what is on
//      her screen.
//
//      Exit paths (the dirty rule, decided 2026-07-29): a dirty mark
//      clears ONLY on a successful persist round-trip of that row —
//      never by value comparison. The controller does not own clinical
//      values, so it cannot verify that a screen state "returned to"
//      what the DB holds; and after a failed transport, the row's
//      on-record state is unverified even when the values would match.
//      In every surface, reverting a row on screen fires another save
//      anyway, so the revert path clears itself the honest way — by
//      succeeding. Against the offline dead end, the controller
//      retains each row's latest persist closure and exposes
//      retryDirty(): the surface can offer an explicit Retry on the
//      refusedDirty outcome without reconstructing anything. Retry is
//      always clinician-visible and explicit — the controller never
//      auto-retries in the background.
//
// What this controller is NOT (approved contract decisions):
//   - It never touches SQL, table names, or columns — the store does.
//   - It never judges clinical state and renders nothing; surfaces keep
//     their visual identity (design law) and their own row models.
//   - It has no BuildContext and never toasts — save errors rethrow to
//     the caller, which owns the toast (the feeding-controller
//     convention).
//   - Surface gate states (noAge, invalidDob, …) live OUTSIDE: the
//     controller is only ever constructed in the ready world.
//   - Open-ended surfaces (feeding, SSD today) adopt the queue + seed
//     core WITHOUT completion semantics: completion is an optional
//     capability (SectionalCompletionSpec + a
//     SectionalCompletionCapableStore), split out 2026-07-29 when the
//     feeding retrofit showed a completion-less adopter would
//     otherwise have to stub a lifecycle it does not have. Without the
//     spec, complete()/markedCount() throw StateError — a wiring bug,
//     never a runtime state.
//
// R is the surface's own mutable row type. The controller never mutates
// R except through the two completion-fill callbacks the surface
// supplies.

import 'dart:async';

import 'package:flutter/foundation.dart';

/// The completion half, as an OPTIONAL capability (split 2026-07-29,
/// forced by the feeding retrofit — the queue + seed core must be
/// adoptable by open-ended surfaces without stubbing a lifecycle they
/// do not have). A surface without a spec can never complete anything:
/// complete() and markedCount() throw StateError, loudly, because
/// calling them is a wiring bug, not a runtime condition.
class SectionalCompletionSpec<R> {
  /// Rows completion turns into an explicit record ("unmarked").
  final bool Function(R) isUnmarked;

  /// Applied optimistically to every unmarked row at completion
  /// (ped_language: status = 'absent') …
  final void Function(R) applyCompletionFill;

  /// … and reverted on a failed completion (ped_language: status = null).
  final void Function(R) revertCompletionFill;

  const SectionalCompletionSpec({
    required this.isUnmarked,
    required this.applyCompletionFill,
    required this.revertCompletionFill,
  });
}

/// What a surface tells the controller about its rows and sections.
class SectionalCaptureConfig<R> {
  /// Ordered section ids; drives navigation, progress, and (when a
  /// completion spec is present) completion.
  final List<String> sectionIds;

  /// Server row id — the update-by-id key and the dirty-set key.
  final String Function(R) rowId;

  final String Function(R) sectionOf;

  /// Row identity for seed reconciliation, e.g. (section, order).
  /// Must be stable across reloads and equal-by-value (records are).
  final Object Function(R) seedKey;

  /// The full canonical seed-key set. bootstrap() inserts rows for
  /// exactly the missing keys. Rows whose key is NOT in this set are
  /// clinician-added and simply kept — reconciliation only inserts,
  /// never deletes.
  final Set<Object> expectedSeedKeys;

  /// The completion lifecycle — null for open-ended adopters (feeding),
  /// which get the queue, dirty set, retry, and seed reconciliation
  /// with no Done, no stamps, no rollback.
  final SectionalCompletionSpec<R>? completion;

  const SectionalCaptureConfig({
    required this.sectionIds,
    required this.rowId,
    required this.sectionOf,
    required this.seedKey,
    required this.expectedSeedKeys,
    this.completion,
  });
}

/// Parent-load result the store hands the controller.
class SectionalSnapshot<R> {
  final List<R> rows;

  /// sectionId → completion stamp (null / absent = not declared done).
  final Map<String, DateTime?> completedAt;

  const SectionalSnapshot({required this.rows, required this.completedAt});
}

/// Persistence adapter the surface's service implements — the CORE
/// contract every adopter needs. The store owns every table name and
/// column; the controller owns lifecycle only.
abstract interface class SectionalCaptureStore<R> {
  /// Rows + per-section completion stamps (all-null for open-ended
  /// adopters). Surface gate states are resolved BEFORE the controller
  /// exists — load() only ever runs in the ready world.
  Future<SectionalSnapshot<R>> load();

  /// Self-heal: insert rows for exactly these missing seed keys. MUST
  /// be loud on duplicates (unique constraint), never silent.
  Future<void> insertSeedRows(Set<Object> missingSeedKeys);
}

/// The completion-capable store — implemented only by surfaces that
/// carry a SectionalCompletionSpec. complete() requires BOTH.
abstract interface class SectionalCompletionCapableStore<R>
    implements SectionalCaptureStore<R> {
  /// The completion write. unmarkedRowIds is the EXPLICIT id list
  /// computed from screen state — a store must never substitute a
  /// server-side status-IS-NULL filter for it.
  Future<void> persistCompletion({
    required String sectionId,
    required List<String> unmarkedRowIds,
  });
}

enum SectionalCompletionOutcome {
  /// Persisted; the current section advanced.
  completed,

  /// Idempotent no-op — the section was already declared done
  /// (re-tap, or a stale button from before an advance).
  alreadyCompleted,

  /// Another completion is in flight — the double-tap, absorbed.
  refusedBusy,

  /// One or more rows of this section have a failed save on record.
  /// dirtyRowIds names them so the surface can offer retry.
  refusedDirty,

  /// The store threw; fill, stamp, and section index were fully
  /// reverted. The Done affordance is back; error carries the cause.
  rolledBack,
}

class SectionalCompletionResult {
  final SectionalCompletionOutcome outcome;

  /// Non-empty exactly when outcome == refusedDirty.
  final List<String> dirtyRowIds;

  /// Set exactly when outcome == rolledBack.
  final Object? error;

  const SectionalCompletionResult._(this.outcome,
      {this.dirtyRowIds = const [], this.error});
}

class SectionalCaptureController<R> extends ChangeNotifier {
  final SectionalCaptureConfig<R> config;
  final SectionalCaptureStore<R> store;

  SectionalCaptureController({required this.config, required this.store});

  final Map<String, List<R>> _rowsBySection = {};
  final Map<String, DateTime?> _completedAt = {};
  final Set<Future<void>> _pending = {};
  final Set<String> _dirtyRowIds = {};

  /// rowId → the latest persist closure seen for that row. Retained so
  /// retryDirty() can re-run it (closures read the row's CURRENT state
  /// at execution time); dropped once a save of the row succeeds.
  final Map<String, Future<void> Function()> _lastPersist = {};
  int _currentIndex = 0;
  bool _completing = false;
  bool _bootstrapped = false;
  bool _disposed = false;

  // ── State (read by the surface's build) ───────────────────────────

  bool get bootstrapped => _bootstrapped;
  bool get completing => _completing;
  int get pendingSaveCount => _pending.length;
  Set<String> get dirtyRowIds => Set.unmodifiable(_dirtyRowIds);

  List<R> rowsIn(String sectionId) =>
      List.unmodifiable(_rowsBySection[sectionId] ?? const []);

  bool isCompleted(String sectionId) => _completedAt[sectionId] != null;

  bool get allCompleted =>
      config.sectionIds.isNotEmpty && config.sectionIds.every(isCompleted);

  String get currentSectionId => config.sectionIds[_currentIndex];
  int get currentIndex => _currentIndex;

  /// Progress against the completion lifecycle — meaningless without
  /// one, so a completion-less adopter calling it is a wiring bug.
  int markedCount(String sectionId) {
    final spec = config.completion;
    if (spec == null) {
      throw StateError(
          'markedCount() needs a SectionalCompletionSpec — this adopter is '
          'open-ended (queue + seed only)');
    }
    return rowsIn(sectionId).where((r) => !spec.isUnmarked(r)).length;
  }

  void goTo(String sectionId) {
    final i = config.sectionIds.indexOf(sectionId);
    if (i < 0 || i == _currentIndex) return;
    _currentIndex = i;
    _notify();
  }

  // ── Bootstrap: load → per-key seed reconciliation → hydrate ───────

  /// Throws on unrecoverable load/seed failure — the surface owns the
  /// error UI, exactly as it owns its gate states.
  Future<void> bootstrap() async {
    var snapshot = await store.load();
    final present = snapshot.rows.map(config.seedKey).toSet();
    final missing = config.expectedSeedKeys.difference(present);
    if (missing.isNotEmpty) {
      // Self-heal: a parent whose seed was interrupted (network drop,
      // app kill) repairs here — per key, so PARTIAL seeds heal too,
      // not only the empty case. The store's unique constraint makes a
      // concurrent double-seed loud rather than silent duplication.
      await store.insertSeedRows(missing);
      snapshot = await store.load();
    }

    _rowsBySection.clear();
    for (final section in config.sectionIds) {
      _rowsBySection[section] = [];
    }
    for (final r in snapshot.rows) {
      (_rowsBySection[config.sectionOf(r)] ??= []).add(r);
    }
    _completedAt
      ..clear()
      ..addAll(snapshot.completedAt);

    // Open on the first section not yet declared done; all-done (or no
    // sections at all) opens on the first.
    if (config.sectionIds.isNotEmpty) {
      final firstOpen = config.sectionIds.indexWhere((s) => !isCompleted(s));
      _currentIndex = firstOpen < 0 ? 0 : firstOpen;
    }

    _bootstrapped = true;
    _notify();
  }

  // ── The in-flight save queue + dirty set ──────────────────────────

  /// The surface mutates its row optimistically, then hands the persist
  /// here. The returned future rethrows the store's error — the CALLER
  /// must catch and toast (fire-and-forget without a catch is an
  /// unhandled async error by design: silence is not an option).
  ///
  /// On failure the row id joins the dirty set and blocks completion of
  /// its section (refusedDirty). The dirty mark clears ONLY on a
  /// successful persist round-trip of the row — never by value
  /// comparison (the controller does not own clinical values, and after
  /// a failed transport the row's on-record state is unverified even if
  /// the values would match). When two saves for one row overlap, a
  /// failure recorded after a success wins — the conservative
  /// direction: dirty until proven clean.
  Future<void> trackRowSave(String rowId, Future<void> Function() persist) {
    _lastPersist[rowId] = persist;
    final caller = Completer<void>();
    late final Future<void> tracked;
    tracked = () async {
      try {
        await persist();
        _lastPersist.remove(rowId);
        if (_dirtyRowIds.remove(rowId)) _notify();
        caller.complete();
      } catch (e, st) {
        if (_dirtyRowIds.add(rowId)) _notify();
        caller.completeError(e, st);
      } finally {
        _pending.remove(tracked);
      }
    }();
    _pending.add(tracked);
    return caller.future;
  }

  /// The explicit path out of the offline dead end: re-runs the
  /// retained persist closure of every (targeted) dirty row through the
  /// same tracked path, sequentially, and returns the row ids STILL
  /// dirty afterwards — empty means all clean and complete() can
  /// proceed. Never throws: per-row failures land back in the dirty
  /// set, which is the report. Safe to call repeatedly; the surface
  /// wires it to a visible Retry affordance, never a background loop.
  Future<Set<String>> retryDirty({Iterable<String>? rowIds}) async {
    final targets = (rowIds ?? _dirtyRowIds.toList())
        .where(_dirtyRowIds.contains)
        .toList();
    for (final id in targets) {
      final persist = _lastPersist[id];
      if (persist == null) continue; // defensive: no closure → stays dirty
      try {
        await trackRowSave(id, persist);
      } catch (_) {
        // Already re-recorded in the dirty set — the returned set is
        // the report; a retry must not become an exception storm.
      }
    }
    return Set.unmodifiable(
        _dirtyRowIds.intersection(targets.toSet()));
  }

  /// Waits until every tracked save has settled (loop, because new
  /// saves may be enqueued while awaiting). The tracked futures never
  /// throw — errors travel on the caller futures and the dirty set.
  Future<void> drainPendingSaves() async {
    while (_pending.isNotEmpty) {
      await Future.wait(_pending.toList());
    }
  }

  // ── Completion ────────────────────────────────────────────────────

  /// Keyed on [sectionId] — the section whose Done button was actually
  /// pressed. Guard order: unknown section throws (a wiring bug);
  /// a completion in flight → refusedBusy — checked BEFORE the
  /// completed guard, because the in-flight section is optimistically
  /// stamped and could still roll back: while the outcome is undecided,
  /// alreadyCompleted would be a claim ahead of the DB. Then:
  /// already-completed → alreadyCompleted; drain the queue; refuse if
  /// any row of THIS section is dirty (naming the ids); apply the
  /// optimistic fill + stamp + advance; persist with the explicit
  /// unmarked-id list; and on a store failure revert all three and
  /// report rolledBack.
  Future<SectionalCompletionResult> complete(String sectionId) async {
    final spec = config.completion;
    final completionStore = store;
    if (spec == null || completionStore is! SectionalCompletionCapableStore<R>) {
      throw StateError(
          'complete() called on a completion-less SectionalCapture — this '
          'adopter has no SectionalCompletionSpec and/or its store does not '
          'implement SectionalCompletionCapableStore');
    }
    if (!config.sectionIds.contains(sectionId)) {
      throw ArgumentError.value(
          sectionId, 'sectionId', 'not a configured section');
    }
    if (_completing) {
      return const SectionalCompletionResult._(
          SectionalCompletionOutcome.refusedBusy);
    }
    if (isCompleted(sectionId)) {
      return const SectionalCompletionResult._(
          SectionalCompletionOutcome.alreadyCompleted);
    }
    _completing = true;
    _notify();
    try {
      // Let in-flight saves land first — a save that FAILS during this
      // drain joins the dirty set and is caught by the check below.
      await drainPendingSaves();

      final dirtyHere = rowsIn(sectionId)
          .map(config.rowId)
          .where(_dirtyRowIds.contains)
          .toList();
      if (dirtyHere.isNotEmpty) {
        return SectionalCompletionResult._(
            SectionalCompletionOutcome.refusedDirty,
            dirtyRowIds: dirtyHere);
      }

      final flipped = rowsIn(sectionId).where(spec.isUnmarked).toList();
      final indexBefore = _currentIndex;
      for (final r in flipped) {
        spec.applyCompletionFill(r);
      }
      _completedAt[sectionId] = DateTime.now();
      if (_currentIndex < config.sectionIds.length - 1) {
        _currentIndex += 1;
      }
      _notify();
      try {
        await completionStore.persistCompletion(
          sectionId: sectionId,
          unmarkedRowIds: [for (final r in flipped) config.rowId(r)],
        );
        return const SectionalCompletionResult._(
            SectionalCompletionOutcome.completed);
      } catch (e) {
        // A section must never read "on record" when the DB never
        // recorded it — revert fill, stamp, and position so the Done
        // affordance returns.
        for (final r in flipped) {
          spec.revertCompletionFill(r);
        }
        _completedAt[sectionId] = null;
        _currentIndex = indexBefore;
        _notify();
        return SectionalCompletionResult._(
            SectionalCompletionOutcome.rolledBack,
            error: e);
      }
    } finally {
      _completing = false;
      _notify();
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _lastPersist.clear();
    super.dispose();
  }
}
