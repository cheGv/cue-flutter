// lib/widgets/cas_session_dials.dart
//
// CAS per-session dial capture — the WRITE half of the resumption loop.
// (The read half is ProgressBrief, fed by assemble_cas_progress_brief.)
// One row per complexity level worked: accuracy (accurate | partial |
// inaccurate) × cue (independent → hand_over_hand), persisted to
// cas_session_progress via CasSessionProgressRepository.upsertLevels at
// the session's final save.
//
// Laws:
//   • An untouched level writes NO row. The dials record only what the
//     SLP marks; absence of a mark is absence of data — never
//     'inaccurate', never a default. Tapping a selected pill again
//     deselects it, so a mis-tap can always return a level to untouched.
//   • The widget owns its state via CasSessionDialsController. It does
//     NOT join session_capture_screen's _fieldCtrls /
//     population_payload — dials write to their own table.
//   • The rung list arrives from kCasComplexityLevels
//     (constants/cas_levels.dart) — never declared here. Which levels an
//     STG *spans* is not yet data anywhere (no complexity range on
//     short_term_goals), so all rungs render; untouched-writes-nothing
//     makes the full ladder safe.
//
// Visual grammar mirrors the Add-details panel register (kCueSurface
// card, kCueBorder hairline, kCueCardRadius, DM Sans 11 w600 tracked
// labels) so capture reads native to the screen. Selection is
// typographic — ink border + w600 label — no accent color: the
// dual-accent doctrine reserves amber for the urgent register and olive
// for its named sites; steady data capture earns neither.

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../constants/cas_levels.dart';
import '../models/cas_session_progress.dart';
import '../theme/cue_phase4_tokens.dart';

// Wire values match the DB CHECK on cas_session_progress.accuracy.
// Glyphs mirror the assessment surface's length-gradient scale (✓ ~ ✗).
const List<({String value, String glyph, String word})> _kAccuracyOptions = [
  (value: 'accurate', glyph: '✓', word: 'accurate'),
  (value: 'partial', glyph: '~', word: 'partial'),
  (value: 'inaccurate', glyph: '✗', word: 'inaccurate'),
];

// Wire values are CueLevel wire strings — CasSessionProgress.draft parses
// them, and canonical values keep cue_level_used_raw null. Short forms
// are standard SLP documentation shorthand (min/mod/max cues, HOH); the
// full label rides on a Tooltip.
const List<({String value, String short, String full})> _kCueOptions = [
  (value: 'independent', short: 'Ind', full: 'Independent'),
  (value: 'minimal', short: 'Min', full: 'Minimal cues'),
  (value: 'moderate', short: 'Mod', full: 'Moderate cues'),
  (value: 'maximal', short: 'Max', full: 'Maximal cues'),
  (value: 'hand_over_hand', short: 'HOH', full: 'Hand-over-hand'),
];

/// Dial selections keyed by level_order. Owned by the screen (not the
/// widget) so the save path reads touched rows independently of the
/// widget tree.
class CasSessionDialsController extends ChangeNotifier {
  final Map<int, String> _accuracy = {}; // level_order → accuracy wire value
  final Map<int, String> _cue = {}; // level_order → CueLevel wire string

  String? accuracyFor(int order) => _accuracy[order];
  String? cueFor(int order) => _cue[order];

  void setAccuracy(int order, String? value) {
    if (value == null) {
      _accuracy.remove(order);
    } else {
      _accuracy[order] = value;
    }
    notifyListeners();
  }

  void setCue(int order, String? value) {
    if (value == null) {
      _cue.remove(order);
    } else {
      _cue[order] = value;
    }
    notifyListeners();
  }

  /// A level is touched when either dial is set. Touched ⇒ one row;
  /// untouched ⇒ no row, structurally.
  bool isTouched(int order) =>
      _accuracy.containsKey(order) || _cue.containsKey(order);

  bool get hasAnyTouched => _accuracy.isNotEmpty || _cue.isNotEmpty;

  /// Insert-ready rows for the TOUCHED levels only. A row may carry
  /// accuracy without cue (or vice versa) — both columns are nullable and
  /// half-marked is still real data.
  List<CasSessionProgress> buildDraftRows({
    required String stgId,
    required int sessionId,
    required String clientId,
    List<CasComplexityLevel> levels = kCasComplexityLevels,
  }) =>
      [
        for (final lvl in levels)
          if (isTouched(lvl.order))
            CasSessionProgress.draft(
              stgId: stgId,
              sessionId: sessionId,
              clientId: clientId,
              levelLabel: lvl.label,
              levelOrder: lvl.order,
              accuracy: _accuracy[lvl.order],
              cueRaw: _cue[lvl.order],
            ),
      ];
}

class CasSessionDials extends StatelessWidget {
  final CasSessionDialsController controller;
  final List<CasComplexityLevel> levels;

  const CasSessionDials({
    super.key,
    required this.controller,
    this.levels = kCasComplexityLevels,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) => Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        decoration: BoxDecoration(
          color: kCueSurface,
          border: Border.all(color: kCueBorder, width: kCueCardBorderW),
          borderRadius: BorderRadius.circular(kCueCardRadius),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Levels worked',
              style: GoogleFonts.dmSans(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: kCueEyebrowInk,
                letterSpacing: kCueEyebrowLetterSpacing(11),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              'Only levels you mark are recorded.',
              style: GoogleFonts.dmSans(
                fontSize: 12,
                color: kCueSubtitleInk,
                height: 1.4,
              ),
            ),
            for (final lvl in levels) ...[
              const SizedBox(height: 14),
              _levelRow(lvl),
            ],
          ],
        ),
      ),
    );
  }

  Widget _levelRow(CasComplexityLevel lvl) {
    final acc = controller.accuracyFor(lvl.order);
    final cue = controller.cueFor(lvl.order);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          lvl.display,
          style: GoogleFonts.dmSans(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: kCueInk,
          ),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            for (final o in _kAccuracyOptions)
              _pill(
                label: '${o.glyph} ${o.word}',
                selected: acc == o.value,
                onTap: () => controller.setAccuracy(
                    lvl.order, acc == o.value ? null : o.value),
              ),
            _dialDivider(),
            for (final o in _kCueOptions)
              Tooltip(
                message: o.full,
                child: _pill(
                  label: o.short,
                  selected: cue == o.value,
                  onTap: () => controller.setCue(
                      lvl.order, cue == o.value ? null : o.value),
                ),
              ),
          ],
        ),
      ],
    );
  }

  // Hairline separator between the accuracy dial and the cue dial.
  Widget _dialDivider() => Container(
        width: 1,
        height: 18,
        margin: const EdgeInsets.symmetric(horizontal: 4),
        color: kCueBorder,
      );

  Widget _pill({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: kCueSurface,
          border: Border.all(
            color: selected ? kCueInk : kCueBorder,
            width: selected ? 1.0 : kCueCardBorderW,
          ),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          style: GoogleFonts.dmSans(
            fontSize: 12,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            color: selected ? kCueInk : kCueMutedInk,
          ),
        ),
      ),
    );
  }
}
