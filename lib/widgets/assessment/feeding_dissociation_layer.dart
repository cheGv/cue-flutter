// lib/widgets/assessment/feeding_dissociation_layer.dart
//
// part of the feeding layer-module library (see feeding_assessment_surface.dart
// for the library doc + the off-ramp binding contract).
//
// Layer 1 — oral-motor dissociation. Five fixed functions, observable sign
// PRIMARY / clinical term secondary, present–emerging–absent colour-coded
// chips + per-function notes. Carries NO off-ramp card: dissociation content
// alone cannot trigger the off-ramp, so this is the one layer a router may
// mount bare.

part of 'feeding_assessment_surface.dart';

/// Public, independently mountable Layer 1. Renders through the controller
/// gate so standalone mounting is bootstrap-safe.
class FeedingDissociationLayer extends StatelessWidget {
  final FeedingAssessmentController controller;

  const FeedingDissociationLayer({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return _controllerGated(
        controller, () => _FeedingDissociationBody(controller: controller));
  }
}

/// Library-private body — the composer mounts this directly inside its
/// accordion section (already gated there).
class _FeedingDissociationBody extends StatefulWidget {
  final FeedingAssessmentController controller;

  const _FeedingDissociationBody({required this.controller});

  @override
  State<_FeedingDissociationBody> createState() =>
      _FeedingDissociationBodyState();
}

class _FeedingDissociationBodyState extends State<_FeedingDissociationBody> {
  final Map<String, TextEditingController> _notesCtrls = {};

  @override
  void initState() {
    super.initState();
    for (final f in kFeedingDissociationFunctions) {
      _notesCtrls[f.column] = TextEditingController(
          text: (widget.controller.parent['${f.column}_notes'] as String?) ??
              '');
    }
  }

  @override
  void dispose() {
    for (final c in _notesCtrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _saveCols(Map<String, dynamic> data) async {
    try {
      await widget.controller.saveParentColumns(data);
    } catch (e) {
      if (mounted) _toast(context, 'Could not save: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _subText('Watch a few bites and sips, then mark each function. '
            'Unmarked stays unmarked — nothing here defaults.'),
        const SizedBox(height: 8),
        for (var i = 0; i < kFeedingDissociationFunctions.length; i++) ...[
          _dissociationBlock(kFeedingDissociationFunctions[i]),
          if (i < kFeedingDissociationFunctions.length - 1)
            const Divider(height: 20, color: _line),
        ],
      ],
    );
  }

  Widget _dissociationBlock(FeedingDissociationFunction f) {
    final status = widget.controller.parent[f.column] as String?;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Observable sign PRIMARY, clinical term secondary — the report needs
        // the term; the mealtime observation needs the plain question.
        Text(f.observableSign,
            style: GoogleFonts.inter(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: _ink,
                height: 1.45)),
        const SizedBox(height: 2),
        Text(f.term,
            style: GoogleFonts.inter(
                fontSize: 11, fontWeight: FontWeight.w500, color: _inkTertiary)),
        const SizedBox(height: 8),
        _codedChips(status, (v) => _saveCols({f.column: v})),
        const SizedBox(height: 8),
        _rowText('Notes', _notesCtrls[f.column]!,
            hint: 'optional',
            onSave: () => _saveCols(
                {'${f.column}_notes': _notesCtrls[f.column]!.text.trim()})),
      ],
    );
  }
}
