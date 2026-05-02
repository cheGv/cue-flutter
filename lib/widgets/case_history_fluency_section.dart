// lib/widgets/case_history_fluency_section.dart
//
// Phase 4.0.3 — Layer 02 case history surface for developmental stuttering.
// Captures the structured payload that lands in
// case_history_entries.payload (jsonb) when population_type =
// 'developmental_stuttering'.
//
// Visual language is Cue's locked Phase 4.0 register: paper background,
// white cards, amber accent, lowercase tracked eyebrows, sentence case,
// editorial Playfair italic for the section title. Local tokens — global
// theme refactor is a future polish session (per session brief).
//
// Affirmative-language commitments per CLAUDE.md §13.15:
//   - Variability uses "easier in / harder in" framing only.
//   - Emotional response uses "comfort level"; band labels are low /
//     moderate / high. Never "frustration".
//   - Awareness stays as a clinical construct (none / slight / moderate /
//     marked) — not a deficit framing.
//   - No gendered pronouns anywhere in copy.

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/cue_phase4_tokens.dart';

// Local aliases for the shared tokens that this file uses heavily.
const Color _subtitleInk = kCueSubtitleInk;
const Color _eyebrowInk  = kCueEyebrowInk;

// ── Catalogs ──────────────────────────────────────────────────────────────────

class _ChipOption {
  final String value;
  final String label;
  const _ChipOption(this.value, this.label);
}

const List<_ChipOption> _variabilityContexts = [
  _ChipOption('talking_to_strangers',  'Talking to strangers'),
  _ChipOption('reading_aloud',         'Reading aloud'),
  _ChipOption('classroom',             'Classroom'),
  _ChipOption('phone_speaking',        'Phone calls'),
  _ChipOption('with_siblings',         'With siblings'),
  _ChipOption('at_home',               'At home'),
  _ChipOption('with_friends',          'With friends'),
  _ChipOption('with_unfamiliar_adults','With unfamiliar adults'),
];

const List<_ChipOption> _secondaryBehaviourCatalog = [
  _ChipOption('eye_blink',       'Eye blink'),
  _ChipOption('facial_tension',  'Facial tension'),
  _ChipOption('head_movement',   'Head movement'),
  _ChipOption('limb_movement',   'Limb movement'),
  _ChipOption('audible_tension', 'Audible tension'),
];

enum _ContextState { unmarked, harderIn, easierIn }

// ── Public widget ─────────────────────────────────────────────────────────────

class CaseHistoryFluencySection extends StatefulWidget {
  /// The case_history_entries.payload jsonb to seed the form with.
  /// Empty map for a fresh capture.
  final Map<String, dynamic> initialPayload;

  /// Fired on every change. Parent caches the latest payload and passes it
  /// to the case_history_entries insert/update at save time.
  final ValueChanged<Map<String, dynamic>> onChanged;

  const CaseHistoryFluencySection({
    super.key,
    required this.initialPayload,
    required this.onChanged,
  });

  @override
  State<CaseHistoryFluencySection> createState() =>
      _CaseHistoryFluencySectionState();
}

class _CaseHistoryFluencySectionState extends State<CaseHistoryFluencySection> {
  // Onset & development
  final _ageOfOnsetCtrl  = TextEditingController();
  String? _onsetPattern; // gradual | sudden | unknown

  // Family history
  String? _familyHistoryStuttering; // yes | no | unknown
  final _familyDetailsCtrl = TextEditingController();

  // Variability
  final Map<String, _ContextState> _contextStates = {};

  // Awareness & emotional response
  String? _awarenessLevel; // none | slight | moderate | marked
  String? _comfortLevel;   // low | moderate | high

  // Secondary behaviours
  final Set<String> _secondaryBehaviours = {};

  // Previous intervention
  String? _previousReceived; // yes | no | unknown
  final _prevWhereCtrl    = TextEditingController();
  final _prevWhenCtrl     = TextEditingController();
  final _prevApproachCtrl = TextEditingController();
  final _prevOutcomeCtrl  = TextEditingController();

  @override
  void initState() {
    super.initState();
    _seedFromPayload(widget.initialPayload);
  }

  @override
  void didUpdateWidget(covariant CaseHistoryFluencySection old) {
    super.didUpdateWidget(old);
    if (!identical(old.initialPayload, widget.initialPayload)) {
      _seedFromPayload(widget.initialPayload);
    }
  }

  void _seedFromPayload(Map<String, dynamic> p) {
    final onset = (p['onset'] as Map?) ?? const {};
    _ageOfOnsetCtrl.text = (onset['age_of_onset_text'] as String?) ?? '';
    _onsetPattern = (onset['onset_pattern'] as String?);

    final fam = (p['family_history'] as Map?) ?? const {};
    _familyHistoryStuttering = (fam['stuttering_present'] as String?);
    _familyDetailsCtrl.text  = (fam['details'] as String?) ?? '';

    _contextStates.clear();
    final variability = (p['variability_across_contexts'] as Map?) ?? const {};
    for (final k in (variability['harder_in'] as List? ?? const [])) {
      _contextStates[k.toString()] = _ContextState.harderIn;
    }
    for (final k in (variability['easier_in'] as List? ?? const [])) {
      _contextStates[k.toString()] = _ContextState.easierIn;
    }

    _awarenessLevel = ((p['awareness'] as Map?) ?? const {})['level'] as String?;
    _comfortLevel   = ((p['comfort_level'] as Map?) ?? const {})['level'] as String?;

    _secondaryBehaviours
      ..clear()
      ..addAll(((p['secondary_behaviours'] as List?) ?? const [])
          .map((e) => e.toString()));

    final prev = (p['previous_intervention'] as Map?) ?? const {};
    _previousReceived         = prev['received'] as String?;
    _prevWhereCtrl.text       = (prev['where']    as String?) ?? '';
    _prevWhenCtrl.text        = (prev['when']     as String?) ?? '';
    _prevApproachCtrl.text    = (prev['approach'] as String?) ?? '';
    _prevOutcomeCtrl.text     = (prev['outcome']  as String?) ?? '';
  }

  Map<String, dynamic> _buildPayload() {
    final harderIn = <String>[];
    final easierIn = <String>[];
    _contextStates.forEach((k, v) {
      if (v == _ContextState.harderIn) harderIn.add(k);
      if (v == _ContextState.easierIn) easierIn.add(k);
    });

    final payload = <String, dynamic>{
      'onset': {
        if (_ageOfOnsetCtrl.text.trim().isNotEmpty)
          'age_of_onset_text': _ageOfOnsetCtrl.text.trim(),
        if (_onsetPattern != null) 'onset_pattern': _onsetPattern,
      },
      'family_history': {
        if (_familyHistoryStuttering != null)
          'stuttering_present': _familyHistoryStuttering,
        if (_familyDetailsCtrl.text.trim().isNotEmpty)
          'details': _familyDetailsCtrl.text.trim(),
      },
      'variability_across_contexts': {
        'harder_in': harderIn,
        'easier_in': easierIn,
      },
      if (_awarenessLevel != null) 'awareness': {'level': _awarenessLevel},
      if (_comfortLevel != null)   'comfort_level': {'level': _comfortLevel},
      'secondary_behaviours': _secondaryBehaviours.toList()..sort(),
      'previous_intervention': {
        if (_previousReceived != null) 'received': _previousReceived,
        if (_prevWhereCtrl.text.trim().isNotEmpty)    'where':    _prevWhereCtrl.text.trim(),
        if (_prevWhenCtrl.text.trim().isNotEmpty)     'when':     _prevWhenCtrl.text.trim(),
        if (_prevApproachCtrl.text.trim().isNotEmpty) 'approach': _prevApproachCtrl.text.trim(),
        if (_prevOutcomeCtrl.text.trim().isNotEmpty)  'outcome':  _prevOutcomeCtrl.text.trim(),
      },
    };
    return payload;
  }

  void _emit() => widget.onChanged(_buildPayload());

  @override
  void dispose() {
    _ageOfOnsetCtrl.dispose();
    _familyDetailsCtrl.dispose();
    _prevWhereCtrl.dispose();
    _prevWhenCtrl.dispose();
    _prevApproachCtrl.dispose();
    _prevOutcomeCtrl.dispose();
    super.dispose();
  }

  // ── Build ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Container(
      // Paper background frames the locked Phase 4.0 region within the
      // surrounding teal-register Layer-01 form.
      color: kCuePaper,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader(),
          const SizedBox(height: 20),
          _onsetCard(),
          const SizedBox(height: 16),
          _familyHistoryCard(),
          const SizedBox(height: 16),
          _variabilityCard(),
          const SizedBox(height: 16),
          _awarenessAndComfortCard(),
          const SizedBox(height: 16),
          _secondaryBehavioursCard(),
          const SizedBox(height: 16),
          _previousInterventionCard(),
        ],
      ),
    );
  }

  // ── Section header ───────────────────────────────────────────────────────────

  Widget _sectionHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Case history',
            style: GoogleFonts.playfairDisplay(
              fontSize: 28,
              fontWeight: FontWeight.w600,
              fontStyle: FontStyle.italic,
              color: kCueInk,
              height: 1.05,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Built around what matters in fluency: onset, variability, awareness, comfort.',
            style: TextStyle(fontSize: 13, color: _subtitleInk, height: 1.45),
          ),
        ],
      ),
    );
  }

  // ── Cards ────────────────────────────────────────────────────────────────────

  Widget _onsetCard() {
    return _card(
      eyebrow: 'onset & development',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _fieldLabel('Age of onset'),
          const SizedBox(height: 6),
          _textField(
            _ageOfOnsetCtrl,
            hint: 'e.g. ~3.5 years, around the time started preschool',
            onChanged: (_) => _emit(),
          ),
          const SizedBox(height: 16),
          _fieldLabel('Onset pattern'),
          const SizedBox(height: 8),
          _segmented(
            options: const [
              ('gradual', 'Gradual'),
              ('sudden',  'Sudden'),
              ('unknown', 'Unknown'),
            ],
            value: _onsetPattern,
            onChanged: (v) => setState(() {
              _onsetPattern = v;
              _emit();
            }),
          ),
        ],
      ),
    );
  }

  Widget _familyHistoryCard() {
    return _card(
      eyebrow: 'family history',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _fieldLabel('Stuttering in the family'),
          const SizedBox(height: 8),
          _segmented(
            options: const [
              ('yes',     'Yes'),
              ('no',      'No'),
              ('unknown', 'Unknown'),
            ],
            value: _familyHistoryStuttering,
            onChanged: (v) => setState(() {
              _familyHistoryStuttering = v;
              _emit();
            }),
          ),
          if (_familyHistoryStuttering == 'yes') ...[
            const SizedBox(height: 16),
            _fieldLabel('Details'),
            const SizedBox(height: 6),
            _textField(
              _familyDetailsCtrl,
              hint: 'e.g. paternal uncle, recovered around age 7',
              maxLines: 2,
              onChanged: (_) => _emit(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _variabilityCard() {
    return _card(
      eyebrow: 'variability',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Easier in / harder in — tap to cycle.',
            style: TextStyle(fontSize: 13, color: _subtitleInk),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _variabilityContexts.map(_variabilityChip).toList(),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _legendSwatch(filled: true),
              const SizedBox(width: 6),
              Text('harder in', style: TextStyle(fontSize: 12, color: _subtitleInk)),
              const SizedBox(width: 16),
              _legendSwatch(filled: false),
              const SizedBox(width: 6),
              Text('easier in', style: TextStyle(fontSize: 12, color: _subtitleInk)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _variabilityChip(_ChipOption opt) {
    final state = _contextStates[opt.value] ?? _ContextState.unmarked;
    Color bg;
    Color border;
    Color textColor;
    switch (state) {
      case _ContextState.harderIn:
        bg = kCueAmber;
        border = kCueAmber;
        textColor = Colors.white;
        break;
      case _ContextState.easierIn:
        bg = kCueSurface;
        border = kCueAmber;
        textColor = kCueAmberText;
        break;
      case _ContextState.unmarked:
        bg = kCueSurface;
        border = kCueBorder;
        textColor = kCueInk;
        break;
    }
    return GestureDetector(
      onTap: () => setState(() {
        _contextStates[opt.value] = switch (state) {
          _ContextState.unmarked => _ContextState.harderIn,
          _ContextState.harderIn => _ContextState.easierIn,
          _ContextState.easierIn => _ContextState.unmarked,
        };
        _emit();
      }),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: border,
            width: state == _ContextState.unmarked ? 0.5 : 1.2,
          ),
        ),
        child: Text(
          opt.label,
          style: TextStyle(
            fontSize: 13,
            color: textColor,
            fontWeight: state == _ContextState.unmarked
                ? FontWeight.w400
                : FontWeight.w500,
          ),
        ),
      ),
    );
  }

  Widget _legendSwatch({required bool filled}) {
    return Container(
      width: 14,
      height: 14,
      decoration: BoxDecoration(
        color: filled ? kCueAmber : kCueSurface,
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: kCueAmber, width: 1.2),
      ),
    );
  }

  Widget _awarenessAndComfortCard() {
    return _card(
      eyebrow: 'awareness & emotional response',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _fieldLabel('Awareness'),
          const SizedBox(height: 8),
          _segmented(
            options: const [
              ('none',     'None'),
              ('slight',   'Slight'),
              ('moderate', 'Moderate'),
              ('marked',   'Marked'),
            ],
            value: _awarenessLevel,
            onChanged: (v) => setState(() {
              _awarenessLevel = v;
              _emit();
            }),
          ),
          const SizedBox(height: 16),
          _fieldLabel('Comfort level'),
          const SizedBox(height: 8),
          _segmented(
            options: const [
              ('low',      'Low'),
              ('moderate', 'Moderate'),
              ('high',     'High'),
            ],
            value: _comfortLevel,
            onChanged: (v) => setState(() {
              _comfortLevel = v;
              _emit();
            }),
          ),
          const SizedBox(height: 8),
          Text(
            'Low comfort warrants clinical attention.',
            style: TextStyle(fontSize: 12, color: _subtitleInk),
          ),
        ],
      ),
    );
  }

  Widget _secondaryBehavioursCard() {
    return _card(
      eyebrow: 'secondary behaviours',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Tap any behaviour observed alongside the disfluency.',
            style: TextStyle(fontSize: 13, color: _subtitleInk),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _secondaryBehaviourCatalog.map((opt) {
              final selected = _secondaryBehaviours.contains(opt.value);
              return GestureDetector(
                onTap: () => setState(() {
                  if (selected) {
                    _secondaryBehaviours.remove(opt.value);
                  } else {
                    _secondaryBehaviours.add(opt.value);
                  }
                  _emit();
                }),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: selected ? kCueAmberSurface : kCueSurface,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: selected ? kCueAmber : kCueBorder,
                      width: selected ? 1.2 : 0.5,
                    ),
                  ),
                  child: Text(
                    opt.label,
                    style: TextStyle(
                      fontSize: 13,
                      color: selected ? kCueAmberText : kCueInk,
                      fontWeight: selected ? FontWeight.w500 : FontWeight.w400,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _previousInterventionCard() {
    return _card(
      eyebrow: 'previous intervention',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _fieldLabel('Received intervention'),
          const SizedBox(height: 8),
          _segmented(
            options: const [
              ('yes',     'Yes'),
              ('no',      'No'),
              ('unknown', 'Unknown'),
            ],
            value: _previousReceived,
            onChanged: (v) => setState(() {
              _previousReceived = v;
              _emit();
            }),
          ),
          if (_previousReceived == 'yes') ...[
            const SizedBox(height: 16),
            _fieldLabel('Where'),
            const SizedBox(height: 6),
            _textField(_prevWhereCtrl,
                hint: 'e.g. private clinic in Hyderabad',
                onChanged: (_) => _emit()),
            const SizedBox(height: 12),
            _fieldLabel('When'),
            const SizedBox(height: 6),
            _textField(_prevWhenCtrl,
                hint: 'e.g. ages 4 to 5, ~6 months',
                onChanged: (_) => _emit()),
            const SizedBox(height: 12),
            _fieldLabel('Approach'),
            const SizedBox(height: 6),
            _textField(_prevApproachCtrl,
                hint: 'e.g. Lidcombe, parent-led, fluency shaping',
                onChanged: (_) => _emit()),
            const SizedBox(height: 12),
            _fieldLabel('Outcome'),
            const SizedBox(height: 6),
            _textField(_prevOutcomeCtrl,
                hint: 'in their words — what improved, what didn\'t',
                maxLines: 2,
                onChanged: (_) => _emit()),
          ],
        ],
      ),
    );
  }

  // ── Primitives ──────────────────────────────────────────────────────────────

  Widget _card({required String eyebrow, required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
      decoration: BoxDecoration(
        color: kCueSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: kCueBorder, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            eyebrow,
            style: TextStyle(
              fontSize: 11,
              color: _eyebrowInk,
              letterSpacing: 0.7, // ≈ 0.06em at 11px
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  Widget _fieldLabel(String text) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 13,
        color: kCueInk,
        fontWeight: FontWeight.w500,
      ),
    );
  }

  Widget _textField(
    TextEditingController ctrl, {
    String? hint,
    int maxLines = 1,
    ValueChanged<String>? onChanged,
  }) {
    return TextField(
      controller: ctrl,
      maxLines: maxLines,
      onChanged: onChanged,
      style: const TextStyle(fontSize: 14, color: kCueInk),
      textCapitalization: TextCapitalization.sentences,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(fontSize: 13, color: _eyebrowInk),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: kCueBorder, width: 0.5),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: kCueBorder, width: 0.5),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: kCueAmber, width: 1.2),
        ),
      ),
    );
  }

  Widget _segmented({
    required List<(String, String)> options,
    required String? value,
    required ValueChanged<String?> onChanged,
  }) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: options.map((opt) {
        final selected = value == opt.$1;
        return GestureDetector(
          onTap: () => onChanged(selected ? null : opt.$1),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: selected ? kCueAmberSurface : kCueSurface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: selected ? kCueAmber : kCueBorder,
                width: selected ? 1.2 : 0.5,
              ),
            ),
            child: Text(
              opt.$2,
              style: TextStyle(
                fontSize: 13,
                color: selected ? kCueAmberText : kCueInk,
                fontWeight: selected ? FontWeight.w500 : FontWeight.w400,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}
