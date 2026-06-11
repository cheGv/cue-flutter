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
// SAFETY (unchanged by the refactor): the controller exposes the off-ramp
// trigger state (offRampActive — 18mo+ age band OR an airway-sign behaviour
// marked present; trigger conditions DRAFT, clinician sign-off pending).
// The off-ramp CARD's presence is bound to the ladder / behaviours layer
// WRAPPERS structurally — see the library doc in
// feeding_assessment_surface.dart for the binding contract. The controller
// never judges anything: every getter here is display state, not a verdict.

import 'package:flutter/foundation.dart';

import '../../constants/feeding_ladder_content.dart';
import '../../services/feeding_assessment_service.dart';

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

  bool get loading => _loading;
  String? get error => _error;
  String? get assessmentId => _assessmentId;

  /// Raw caches — the same row maps the layers render. Mutate ONLY through
  /// the controller methods so every listening layer repaints.
  Map<String, dynamic> get parent => _parent;
  List<Map<String, dynamic>> get ladderBands => _ladderBands;
  List<Map<String, dynamic>> get behaviors => _behaviors;

  /// The off-ramp age threshold derives from the first off-ramp band — one
  /// source of truth with the seeded content. (Trigger DRAFT, sign-off
  /// pending.)
  static final int offRampAgeMinMonths =
      kFeedingLadderBands.firstWhere((b) => b.offRampBand).ageMinMonths;

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

  /// DRAFT trigger (sign-off pending): age in an off-ramp band (18mo+) OR an
  /// airway-sign behaviour marked present.
  bool get offRampActive =>
      ((ageMonths ?? -1) >= offRampAgeMinMonths) || airwayBehaviorMarked;

  // ── Bootstrap ────────────────────────────────────────────────────────

  Future<void> bootstrap() async {
    try {
      final a = await _service.loadOrCreate(clientId: clientId);
      _assessmentId = a['id'] as String;
      _parent = a;
      _ladderBands = await _service.ensureLadderBands(_assessmentId!);
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

  // ── Mutations (optimistic cache + notify, then persist) ──────────────

  Future<void> saveParentColumns(Map<String, dynamic> data) {
    _parent.addAll(data);
    _notify();
    return _service.saveAssessmentColumns(
        assessmentId: _requireId(), data: data);
  }

  Future<void> saveBandRow(String rowId, Map<String, dynamic> data) {
    _ladderBands.firstWhere((r) => r['id'] == rowId).addAll(data);
    _notify();
    return _service.updateRow(
        table: 'feeding_ladder_bands', rowId: rowId, data: data);
  }

  Future<void> saveBehaviorRow(String rowId, Map<String, dynamic> data) {
    _behaviors.firstWhere((r) => r['id'] == rowId).addAll(data);
    _notify();
    return _service.updateRow(
        table: 'feeding_behaviors', rowId: rowId, data: data);
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

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
