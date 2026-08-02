// lib/widgets/assessment/feeding_ladder_layer.dart
//
// part of the feeding layer-module library (see feeding_assessment_surface.dart
// for the library doc + the off-ramp binding contract).
//
// Layer 2 — the developmental feeding ladder. Age in → the matched band
// auto-surfaces (highlight only, never a judgement); expected texture /
// self-feeding / oral-motor per band; red flags as WATCH-FOR observation
// prompts; at-level / emerging / below-level / not-tested marking in the
// calm olive register; the Western-norm caveat travels with every band body.
//
// THE BINDING: ladder content can show the 18mo+ off-ramp bands, so the
// PUBLIC wrapper below includes FeedingOffRampCard unconditionally — no
// opt-out parameter exists. The bare body is library-private.

part of 'feeding_assessment_surface.dart';

/// Public, independently mountable Layer 2 — WITH the off-ramp card bound in.
///
/// Assembly knobs: [openBandKey] opens a specific band initially (e.g.
/// '18_24mo'; the clinician can still toggle freely afterwards);
/// [highlightAgeMatch] = false suppresses the age-match auto-open + pill
/// (the knob a router uses when IT chose the band to open).
class FeedingLadderLayer extends StatelessWidget {
  final FeedingAssessmentController controller;
  final String? openBandKey;
  final bool highlightAgeMatch;
  final VoidCallback? onOpenSwallow;

  const FeedingLadderLayer({
    super.key,
    required this.controller,
    this.openBandKey,
    this.highlightAgeMatch = true,
    this.onOpenSwallow,
  });

  @override
  Widget build(BuildContext context) {
    return _controllerGated(
      controller,
      () => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _FeedingLadderBody(
            controller: controller,
            initialOpenBandKey: openBandKey,
            highlightAgeMatch: highlightAgeMatch,
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
class _FeedingLadderBody extends StatefulWidget {
  final FeedingAssessmentController controller;
  final String? initialOpenBandKey;
  final bool highlightAgeMatch;

  const _FeedingLadderBody({
    required this.controller,
    this.initialOpenBandKey,
    this.highlightAgeMatch = true,
  });

  @override
  State<_FeedingLadderBody> createState() => _FeedingLadderBodyState();
}

class _FeedingLadderBodyState extends State<_FeedingLadderBody> {
  late final TextEditingController _ageMonthsCtrl;
  final Map<String, TextEditingController> _notesCtrls = {};

  // Band expansion: null = follow the age match; '' = all collapsed;
  // otherwise an explicit band row id. The age-matched band auto-expands so
  // the band the clinician needs is open the moment age is entered.
  String? _expandedBandOverride;

  @override
  void initState() {
    super.initState();
    final c = widget.controller;
    _ageMonthsCtrl =
        TextEditingController(text: c.ageMonths == null ? '' : '${c.ageMonths}');
    for (final r in c.ladderBands) {
      _notesCtrls[r['id'] as String] =
          TextEditingController(text: (r['notes'] as String?) ?? '');
    }
    final key = widget.initialOpenBandKey;
    if (key != null) {
      for (final r in c.ladderBands) {
        if (r['band_key'] == key) {
          _expandedBandOverride = r['id'] as String;
          break;
        }
      }
    }
  }

  @override
  void dispose() {
    _ageMonthsCtrl.dispose();
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

  Future<void> _saveBand(String rowId, Map<String, dynamic> data) async {
    try {
      await widget.controller.saveBandRow(rowId, data);
    } catch (e) {
      if (mounted) _toast(context, 'Could not save row: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final matched =
        widget.highlightAgeMatch ? widget.controller.matchedBandRow : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _numField('Child age', _ageMonthsCtrl, unit: 'mo', onSave: () {
          _saveCols({'age_months': _parseInt(_ageMonthsCtrl.text)});
        }),
        _ghostNote(
            'The ladder shows what is EXPECTED in each age window — it never '
            'says a child is behind. Enter the age to surface the matching '
            'band, read what is expected there, and mark what this child '
            'manages. The gap is yours to see and yours to interpret.'),
        if (matched == null)
          _subText('No age entered yet — open any band below to read it.'),
        const SizedBox(height: 4),
        for (final row in widget.controller.ladderBands)
          _bandTile(row, matched),
      ],
    );
  }

  Widget _bandTile(Map<String, dynamic> row, Map<String, dynamic>? matched) {
    final id = row['id'] as String;
    final isMatched = matched != null && matched['id'] == id;
    final override = _expandedBandOverride;
    final open =
        override == null ? isMatched : (override.isNotEmpty && override == id);
    final marking = row['clinician_marking'] as String?;
    final offRamp = row['off_ramp_band'] == true;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        decoration: BoxDecoration(
          color: isMatched ? _oliveSoft.withValues(alpha: 0.18) : Colors.white,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
              color: isMatched ? _olive : _line, width: isMatched ? 1.3 : 1),
        ),
        child: Column(children: [
          InkWell(
            onTap: () =>
                setState(() => _expandedBandOverride = open ? '' : id),
            borderRadius: BorderRadius.circular(6),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
              child: Row(children: [
                Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Text('${row['band_label']}',
                              style: GoogleFonts.inter(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w600,
                                  color: _ink)),
                          if (widget.controller
                              .ownerUnsaved(row['id'] as String)) ...[
                            const SizedBox(width: 8),
                            Text('not saved',
                                style: GoogleFonts.inter(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: _coral)),
                          ],
                          if (isMatched) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: _oliveSoft,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text("THIS CHILD'S AGE BAND",
                                  style: _eyebrow(color: _olive, size: 9)),
                            ),
                          ],
                        ]),
                        if (marking != null) ...[
                          const SizedBox(height: 2),
                          Text('Marked: ${_humanize(marking)}',
                              style: GoogleFonts.inter(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w500,
                                  color: _olive)),
                        ],
                      ]),
                ),
                Icon(open ? Icons.expand_less : Icons.expand_more,
                    size: 20, color: _inkTertiary),
              ]),
            ),
          ),
          if (open) ...[
            const Divider(height: 1, color: _line),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              child:
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _expectationLine('Texture', '${row['expected_texture'] ?? ''}'),
                _expectationLine(
                    'Self-feeding', '${row['expected_self_feeding'] ?? ''}'),
                _expectationLine(
                    'Oral-motor', '${row['expected_oral_motor'] ?? ''}'),
                const SizedBox(height: 8),
                _watchForBlock('${row['red_flag_prompt'] ?? ''}'),
                if (offRamp)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.alt_route_rounded,
                              size: 14, color: _amber),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                                'Airway signs at this band sit beyond '
                                'feeding-skills scope — see the swallow '
                                'off-ramp below.',
                                style: GoogleFonts.inter(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w500,
                                    color: _amber,
                                    height: 1.4)),
                          ),
                        ]),
                  ),
                // The clinician's call — calm olive register, no colour
                // editorialising on "below level".
                _oliveChips(
                  'This child, against this band',
                  _kMarkingValues,
                  row['clinician_marking'] as String?,
                  (v) => _saveBand(id, {'clinician_marking': v}),
                ),
                _rowText('Notes', _notesCtrls[id]!,
                    hint: 'optional',
                    onSave: () =>
                        _saveBand(id, {'notes': _notesCtrls[id]!.text.trim()})),
                // Western-norm caveat travels with every band the clinician
                // reads (DRAFT wording, founder's version pending).
                _cautionNote(kFeedingWesternNormCaveat),
              ]),
            ),
          ],
        ]),
      ),
    );
  }

  Widget _expectationLine(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(width: 92, child: Text(label, style: _rowLabel)),
        Expanded(
          child: Text(value,
              style:
                  GoogleFonts.inter(fontSize: 12.5, color: _ink, height: 1.45)),
        ),
      ]),
    );
  }

  /// Red-flag content as a WATCH-FOR observation prompt — amber register,
  /// explicitly framed as a prompt, never a verdict. (Prompt text is DRAFT,
  /// clinician sign-off pending before graduation.)
  Widget _watchForBlock(String prompt) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Container(
          color: _amberSoft.withValues(alpha: 0.35),
          child: IntrinsicHeight(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Container(width: 3.5, color: _amber),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('WATCH FOR',
                            style: _eyebrow(color: _amber, size: 9.5)),
                        const SizedBox(height: 4),
                        Text(prompt,
                            style: GoogleFonts.inter(
                                fontSize: 12.5,
                                color: _ink,
                                fontWeight: FontWeight.w500,
                                height: 1.5)),
                        const SizedBox(height: 4),
                        Text(
                            'Observation prompt — you decide whether it is '
                            'present and what it means.',
                            style: GoogleFonts.inter(
                                fontSize: 11, color: _inkTertiary, height: 1.4)),
                      ]),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
