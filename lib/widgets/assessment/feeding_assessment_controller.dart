// lib/widgets/assessment/feeding_assessment_controller.dart
//
// Childhood Feeding — layer-module refactor (2026-06-11, proof-of-shape).
// The data spine shared by the feeding layer widgets: ONE controller per
// assessment owns bootstrap, the parent / ladder-band / behaviour caches,
// and the save plumbing. Layers render from it and mutate through it; UI
// concerns (toasts, TextEditingControllers, accordion state) stay in the
// widgets. A future routing layer constructs one of these and hands it to
// whichever public feeding layer widgets it mounts.
//
// Mutation methods apply the cache + notify FIRST (optimistic — preserving
// the pre-refactor setState-then-save behaviour), then return the service
// future; persistence errors propagate to the calling layer, which owns the
// toast (it has the BuildContext). Bootstrap failures land in [error]
// instead — there is no layer mounted to toast yet. Row-creating /
// row-deleting methods await the service first (a row needs its server id;
// a delete must not lie), matching the pre-refactor behaviour exactly.
//
// SAFETY: the controller exposes the off-ramp trigger state (offRampActive),
// which is SIGN-TRIGGERED (clinician sign-off 2026-06-11): it fires ONLY
// when an airway-sign behaviour is marked present — at ANY age. Age alone
// never fires it. The off-ramp CARD's presence is bound to the ladder /
// behaviours layer WRAPPERS structurally — see the library doc in
// feeding_assessment_surface.dart for the binding contract. The controller
// never judges anything: every getter here is display state, not a verdict.

import 'package:flutter/foundation.dart';

import '../../services/feeding_assessment_service.dart';
import 'sectional_capture.dart';

class FeedingAssessmentController extends ChangeNotifier {
  FeedingAssessmentController({
    required this.clientId,
    FeedingAssessmentService? service,
  }) : _service = service ?? FeedingAssessmentService.instance;

  final String clientId;
  final FeedingAssessmentService _service;

  bool _loading = true;
  String? _error;
  String? _assessmentId;
  Map<String, dynamic> _parent = {};
  List<Map<String, dynamic>> _ladderBands = [];
  final List<Map<String, dynamic>> _behaviors = [];
  bool _disposed = false;

  /// The queue + seed core (2026-08-02 retrofit): in-flight save
  /// tracking, the dirty set with retained-closure retry, and per-key
  /// ladder seed reconciliation. NO completion spec — feeding stays
  /// open-ended (no Done, no stamps, no rollback). Behaviour rows are
  /// clinician-added after bootstrap and therefore live outside the
  /// controller's (bootstrap-static) registry; their saves still ride
  /// the queue and dirty set, which are id-based.
  SectionalCaptureController<Map<String, dynamic>>? _sectional;

  bool get loading => _loading;
  String? get error => _error;
  String? get assessmentId => _assessmentId;

  /// Raw caches — the same row maps the layers render. Mutate ONLY through
  /// the controller methods so every listening layer repaints.
  Map<String, dynamic> get parent => _parent;
  List<Map<String, dynamic>> get ladderBands => _ladderBands;
  List<Map<String, dynamic>> get behaviors => _behaviors;

  int? get ageMonths {
    final a = _parent['age_months'];
    return a is int ? a : null;
  }

  /// The DB band row matching the entered age (display highlight only —
  /// never a judgement).
  Map<String, dynamic>? get matchedBandRow {
    final age = ageMonths;
    if (age == null || age < 0) return null;
    for (final r in _ladderBands) {
      final min = r['age_min_months'];
      final max = r['age_max_months'];
      if (min is! int) continue;
      if (age >= min && (max == null || age < (max as int))) return r;
    }
    return null;
  }

  bool get airwayBehaviorMarked => _behaviors
      .any((b) => b['airway_sign'] == true && b['status'] == 'present');

  /// SIGN-TRIGGERED (clinician sign-off 2026-06-11): fires ONLY when an
  /// airway-sign behaviour is marked present — at ANY age. Age alone never
  /// fires it: an age-based alarm cries wolf on every typically developing
  /// toddler past 18 months and trains the safety channel to be dismissed.
  /// The 18mo+ bands keep their in-band airway GUIDANCE text; the card is
  /// the true signal, raised by the actual marked sign.
  bool get offRampActive => airwayBehaviorMarked;

  // ── Bootstrap ────────────────────────────────────────────────────────

  Future<void> bootstrap() async {
    try {
      final a = await _service.loadOrCreate(clientId: clientId);
      _assessmentId = a['id'] as String;
      _parent = a;
      // Ladder rows load + PER-KEY seed reconciliation (partial seeds
      // heal, not only the empty case) — the one and only seed path.
      final sectional = SectionalCaptureController<Map<String, dynamic>>(
        config: feedingSectionalConfig(),
        store: FeedingLadderSectionalStore(
            assessmentId: _assessmentId!, service: _service),
      );
      await sectional.bootstrap();
      sectional.addListener(_notify); // dirty-set changes repaint layers
      _sectional = sectional;
      _ladderBands = List.of(sectional.rowsIn('ladder'));
      _behaviors
        ..clear()
        ..addAll(await _service.loadRows('feeding_behaviors', _assessmentId!));
      _loading = false;
    } catch (e) {
      _error = '$e';
      _loading = false;
    }
    _notify();
  }

  // ── Unsaved state (the dirty set, surfaced) ──────────────────────────

  /// Dirty persist units — one unit per (owner, field-group), see
  /// feedingSaveUnitId. Empty when everything on screen is on record.
  Set<String> get unsavedUnits => _sectional?.dirtyRowIds ?? const {};

  bool get hasUnsaved => unsavedUnits.isNotEmpty;

  /// Whether any failed save belongs to [ownerId] (a row id, or
  /// 'parent' for the oral-motor parent columns).
  bool ownerUnsaved(String ownerId) => unsavedUnits
      .any((u) => feedingUnsavedUnitMatchesOwner(u, ownerId));

  /// The explicit path out of a failed save: re-runs every retained
  /// persist closure; returns the units STILL dirty (empty = clean).
  /// Never throws — the calling layer owns any toast.
  Future<Set<String>> retryUnsaved() async =>
      _sectional == null ? const {} : await _sectional!.retryDirty();

  // ── Mutations (optimistic cache + notify, then tracked persist) ──────

  /// Optimistic cache + notify first, then the persist rides the
  /// sectional queue: tracked (so any future completion-style drain
  /// sees it), dirty-marked on failure, retryable via retryUnsaved().
  /// The returned future still rethrows to the calling layer, which
  /// owns the toast — the pre-refactor contract, unchanged.
  Future<void> saveParentColumns(Map<String, dynamic> data) {
    _parent.addAll(data);
    _notify();
    final id = _requireId();
    return _requireSectional().trackRowSave(
        feedingSaveUnitId('parent', data),
        () => _service.saveAssessmentColumns(assessmentId: id, data: data));
  }

  Future<void> saveBandRow(String rowId, Map<String, dynamic> data) {
    _ladderBands.firstWhere((r) => r['id'] == rowId).addAll(data);
    _notify();
    return _requireSectional().trackRowSave(
        feedingSaveUnitId(rowId, data),
        () => _service.updateRow(
            table: 'feeding_ladder_bands', rowId: rowId, data: data));
  }

  Future<void> saveBehaviorRow(String rowId, Map<String, dynamic> data) {
    _behaviors.firstWhere((r) => r['id'] == rowId).addAll(data);
    _notify();
    return _requireSectional().trackRowSave(
        feedingSaveUnitId(rowId, data),
        () => _service.updateRow(
            table: 'feeding_behaviors', rowId: rowId, data: data));
  }

  /// Awaits the insert (the row needs its server id), then appends + notifies.
  Future<Map<String, dynamic>> addBehavior(Map<String, dynamic> data) async {
    final id = await _service.insertRow(
        table: 'feeding_behaviors', assessmentId: _requireId(), data: data);
    final row = {'id': id, ...data};
    _behaviors.add(row);
    _notify();
    return row;
  }

  /// Awaits the delete (must not lie about removal), then removes + notifies.
  Future<void> removeBehavior(Map<String, dynamic> row) async {
    await _service.deleteRow(
        table: 'feeding_behaviors', rowId: row['id'] as String);
    _behaviors.remove(row);
    _notify();
  }

  // ── Internals ────────────────────────────────────────────────────────

  String _requireId() {
    final id = _assessmentId;
    if (id == null) {
      throw StateError(
          'FeedingAssessmentController used before bootstrap() completed');
    }
    return id;
  }

  SectionalCaptureController<Map<String, dynamic>> _requireSectional() {
    final s = _sectional;
    if (s == null) {
      throw StateError(
          'FeedingAssessmentController used before bootstrap() completed');
    }
    return s;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _sectional?.removeListener(_notify);
    _sectional?.dispose();
    super.dispose();
  }
}
