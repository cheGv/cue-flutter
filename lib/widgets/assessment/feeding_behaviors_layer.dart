// lib/widgets/assessment/feeding_behaviors_layer.dart
//
// part of the feeding layer-module library (see feeding_assessment_surface.dart
// for the library doc + the off-ramp binding contract).
//
// Layer 3 — feeding behaviours. Clinician-added rows from a starter set or
// free-typed; present / absent (absent is a real negative finding); airway
// rows tagged; capture notes at the foot of the layer.
//
// THE BINDING: behaviour content can show airway-sign rows, so the PUBLIC
// wrapper below includes FeedingOffRampCard unconditionally — no opt-out
// parameter exists. The bare body is library-private. The [filter] knob can
// hide airway rows from DISPLAY, but the card stays bound and its trigger
// reads the controller (ALL rows), so filtering can never silence the
// caution.

part of 'feeding_assessment_surface.dart';

/// Public, independently mountable Layer 3 — WITH the off-ramp card bound in.
///
/// Assembly knobs: [filter] limits which behaviour rows DISPLAY (e.g.
/// `(b) => b['airway_sign'] == true`); [showStarterSet] hides the quick-add
/// chips for read-focused mounts. Neither affects the off-ramp trigger,
/// which reads the controller's full row set.
class FeedingBehaviorsLayer extends StatelessWidget {
  final FeedingAssessmentController controller;
  final bool Function(Map<String, dynamic> row)? filter;
  final bool showStarterSet;
  final VoidCallback? onOpenSwallow;

  const FeedingBehaviorsLayer({
    super.key,
    required this.controller,
    this.filter,
    this.showStarterSet = true,
    this.onOpenSwallow,
  });

  @override
  Widget build(BuildContext context) {
    return _controllerGated(
      controller,
      () => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _FeedingBehaviorsBody(
            controller: controller,
            filter: filter,
            showStarterSet: showStarterSet,
          ),
          // STRUCTURALLY BOUND — the safety caution ships with the content
          // that can trigger it. Self-gating: renders nothing while inactive.
          FeedingOffRampCard(
              controller: controller, onOpenSwallow: onOpenSwallow),
        ],
      ),
    );
  }
}

/// Library-private body — the composer mounts this directly inside its
/// accordion section and provides the single composed off-ramp card itself.
class _FeedingBehaviorsBody extends StatefulWidget {
  final FeedingAssessmentController controller;
  final bool Function(Map<String, dynamic> row)? filter;
  final bool showStarterSet;

  const _FeedingBehaviorsBody({
    required this.controller,
    this.filter,
    this.showStarterSet = true,
  });

  @override
  State<_FeedingBehaviorsBody> createState() => _FeedingBehaviorsBodyState();
}

class _FeedingBehaviorsBodyState extends State<_FeedingBehaviorsBody> {
  late final TextEditingController _captureNotesCtrl;

  // Per-row text controllers, keyed '$rowId::$field'. Rows can be added by
  // the controller while we're mounted, so _rc creates lazily; controllers
  // for removed rows are disposed with the body (harmless to retain).
  final Map<String, TextEditingController> _rowCtrls = {};

  @override
  void initState() {
    super.initState();
    _captureNotesCtrl = TextEditingController(
        text: (widget.controller.parent['capture_notes'] as String?) ?? '');
  }

  @override
  void dispose() {
    _captureNotesCtrl.dispose();
    for (final c in _rowCtrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  TextEditingController _rc(Map<String, dynamic> row, String field) {
    final key = '${row['id']}::$field';
    return _rowCtrls.putIfAbsent(key,
        () => TextEditingController(text: '${row[field] ?? ''}'));
  }

  Future<void> _saveCols(Map<String, dynamic> data) async {
    try {
      await widget.controller.saveParentColumns(data);
    } catch (e) {
      if (mounted) _toast(context, 'Could not save: $e');
    }
  }

  Future<void> _saveBehavior(String rowId, Map<String, dynamic> data) async {
    try {
      await widget.controller.saveBehaviorRow(rowId, data);
    } catch (e) {
      if (mounted) _toast(context, 'Could not save row: $e');
    }
  }

  Future<void> _addBehavior(Map<String, dynamic> seed) async {
    try {
      await widget.controller.addBehavior(seed);
    } catch (e) {
      if (mounted) _toast(context, 'Could not add behaviour: $e');
    }
  }

  Future<void> _removeBehavior(Map<String, dynamic> row) async {
    try {
      await widget.controller.removeBehavior(row);
    } catch (e) {
      if (mounted) _toast(context, 'Could not remove behaviour: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final all = widget.controller.behaviors;
    final addedKeys = all.map((b) => b['behavior_key']).toSet();
    final filter = widget.filter;
    final visible = filter == null ? all : all.where(filter).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _subText('Tap a starter to add it, or add your own in your words. '
            'Mark each present or absent — "absent" is a real finding '
            '(checked, not observed).'),
        const SizedBox(height: 8),
        if (widget.showStarterSet)
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final s in kFeedingStarterBehaviors)
              _starterChip(s, alreadyAdded: addedKeys.contains(s.key)),
          ]),
        const SizedBox(height: 12),
        for (final row in visible) _behaviorRow(row),
        _addButton(
            'Add behaviour in your words',
            () => _addBehavior({
                  'behavior_key': null,
                  'behavior_label': '',
                  'airway_sign': false, // explicit, never a DB default
                })),
        const SizedBox(height: 12),
        _textField('Capture notes', _captureNotesCtrl,
            multi: true,
            hint: 'Optional',
            onSave: () =>
                _saveCols({'capture_notes': _captureNotesCtrl.text.trim()})),
      ],
    );
  }

  Widget _starterChip(FeedingStarterBehavior s, {required bool alreadyAdded}) {
    return GestureDetector(
      onTap: alreadyAdded
          ? null
          : () => _addBehavior({
                'behavior_key': s.key,
                'behavior_label': s.label,
                'airway_sign': s.airwaySign, // explicit, never a DB default
              }),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
        decoration: BoxDecoration(
          color:
              alreadyAdded ? _oliveSoft.withValues(alpha: 0.4) : Colors.white,
          border: Border.all(color: alreadyAdded ? _oliveSoft : _line),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(alreadyAdded ? Icons.check_rounded : Icons.add_rounded,
              size: 13, color: alreadyAdded ? _inkTertiary : _olive),
          const SizedBox(width: 4),
          Text(s.chipLabel,
              style: GoogleFonts.inter(
                  fontSize: 12,
                  color: alreadyAdded ? _inkTertiary : _ink,
                  fontWeight: FontWeight.w500)),
        ]),
      ),
    );
  }

  Widget _behaviorRow(Map<String, dynamic> row) {
    final id = row['id'] as String;
    final freeTyped = row['behavior_key'] == null;
    final airway = row['airway_sign'] == true;
    return _rowCard(
      onRemove: () => _removeBehavior(row),
      children: [
        if (widget.controller.ownerUnsaved(id))
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text('not saved',
                style: GoogleFonts.inter(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: _coral)),
          ),
        if (freeTyped)
          _rowText('Behaviour', _rc(row, 'behavior_label'),
              hint: 'what you observed, in your words',
              onSave: () => _saveBehavior(id, {
                    'behavior_label': _rc(row, 'behavior_label').text.trim()
                  }))
        else
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${row['behavior_label']}',
                  style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: _ink,
                      height: 1.4)),
              if (airway) ...[
                const SizedBox(height: 4),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: _amberSoft.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text('AIRWAY SIGN',
                      style: _eyebrow(color: _amber, size: 9)),
                ),
              ],
            ]),
          ),
        _oliveChips('Status', const ['present', 'absent'],
            row['status'] as String?, (v) => _saveBehavior(id, {'status': v})),
        _rowText('Notes', _rc(row, 'notes'),
            hint: 'optional',
            onSave: () =>
                _saveBehavior(id, {'notes': _rc(row, 'notes').text.trim()})),
      ],
    );
  }
}
