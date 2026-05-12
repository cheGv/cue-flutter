// lib/widgets/cue_hold.dart
//
// Phase 5.4 Sprint 2 — The Hold. Minimal two-state surface
// to land shape + typography + position + morph so we can react to the
// thing rather than spec it forward. NO business logic, no Supabase,
// no LLM — just the visual register.
//
// States (local State<bool>, toggle on tap):
//   • Idle    — ~140px pill, arc-and-dot mark + "Cue · ready"
//   • Whisper — content-fit pill (capped 360 mobile / 720 desktop),
//                arc-and-dot mark + observation string built from
//                passed counts
//
// Animations:
//   • Width morph via AnimatedSize, 200ms, Curves.easeOutCubic
//   • Content swap via AnimatedSwitcher, 180ms cross-fade
//
// Phase 5.4 Sprint 2 commit 1: HUD strip retired (Path A). The Hold is
// now the sole top-bar surface, mounted inside CueTopBand. The Whisper
// string reads structurally as a "Reading {name} — …" line; the content
// register was inherited from the now-deleted HUD strip's _buildHudDetail.
//
// Future states (thinking active, streaming, expanded, ask, multi-
// activity, dismissed) are explicitly NOT designed yet. Sprint 2 ships
// shape only; subsequent sprints add states incrementally based on
// what this preview teaches us.
//
// Pill height: not explicitly set. Content-driven by the 18×18
// arc-and-dot mark + vertical padding (CueGap.s6 × 2 = 12)
// → ~32-34px natural height. Mark sized to 18px after 14px read
// too small in visual review; pill grows slightly to accommodate.
// Iowan italic text (13 × 1.4 ≈ 18) centers vertically alongside
// the mark via Row's CrossAxisAlignment.center.

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../theme/cue_color_scheme.dart';
import '../theme/cue_tokens.dart';

class CueHold extends StatefulWidget {
  final String clientName;
  final int    activeStepsCount;
  final int    sessionCount;
  /// Max width of the Whisper-state pill. Default 360 (mobile). On
  /// desktop, CueTopBand passes 720 via its holdBuilder callback
  /// (see widgets/cue_top_band.dart).
  final double whisperMaxWidth;

  const CueHold({
    super.key,
    required this.clientName,
    required this.activeStepsCount,
    required this.sessionCount,
    this.whisperMaxWidth = 360,
  });

  @override
  State<CueHold> createState() => _CueHoldState();
}

class _CueHoldState extends State<CueHold> {
  bool _isWhisper = false;

  @override
  Widget build(BuildContext context) {
    final cue = CueColorsResolved.of(context);

    // Iowan Old Style 13 / italic / w500 — shared base style. Color
    // differs by state: textSecondary for idle (calmer), textBody for
    // whisper (slightly more present).
    const baseStyle = TextStyle(
      fontFamily:         'Iowan Old Style',
      fontFamilyFallback: ['Georgia', 'Charter', 'serif'],
      fontStyle:          FontStyle.italic,
      fontSize:           13,
      fontWeight:         FontWeight.w500,
    );

    return Center(
      child: GestureDetector(
        onTap: () => setState(() => _isWhisper = !_isWhisper),
        child: AnimatedSize(
          duration:  const Duration(milliseconds: 200),
          curve:     Curves.easeOutCubic,
          alignment: Alignment.center,
          child: Container(
            constraints: BoxConstraints(
              // Idle: fixed at 140px. Whisper: content-fit, capped by
              // widget.whisperMaxWidth (default 360 mobile; CueTopBand
              // passes 720 on desktop). Long text ellipses on overflow.
              minWidth: _isWhisper ? 0 : 140,
              maxWidth: _isWhisper ? widget.whisperMaxWidth : 140,
            ),
            padding: const EdgeInsets.symmetric(
                horizontal: 14, vertical: CueGap.s6),
            decoration: BoxDecoration(
              color:        cue.bgCard,
              border:       Border.all(
                  color: cue.border, width: CueSize.hairline),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              mainAxisSize:       MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Arc-and-dot primary mark. Sized to 18 for clear identity at
                // the Hold's scale (14 read too small in visual review). Pill height
                // grows from ~30 to ~32-34px as a consequence. Static across
                // Idle/Whisper for this commit; per-state mark behavior deferred.
                SvgPicture.asset(
                  'assets/brand/cue_mark.svg',
                  width:  18,
                  height: 18,
                ),
                const SizedBox(width: CueGap.s8),
                // Content text — cross-fades on state toggle. Flexible
                // so the Row's natural width comes from the text content,
                // letting AnimatedSize observe and animate the size change.
                Flexible(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 180),
                    child: _isWhisper
                        ? Text(
                            _whisperText(),
                            key: const ValueKey('whisper'),
                            style: baseStyle.copyWith(color: cue.textBody),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          )
                        : Text(
                            'Cue · ready',
                            key: const ValueKey('idle'),
                            style:
                                baseStyle.copyWith(color: cue.textSecondary),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _whisperText() {
    final stepsLabel = widget.activeStepsCount == 1
        ? 'active step'
        : 'active steps';
    // "yet" reads naturally only with zero count ("haven't started yet").
    // For non-zero counts, "so far" is the natural register ("you've begun"
    // / "ongoing work"). Matches the existing HUD's descriptive tone, not
    // pending-implying.
    final sessionsPhrase = widget.sessionCount == 0
        ? '0 sessions yet'
        : widget.sessionCount == 1
            ? '1 session so far'
            : '${widget.sessionCount} sessions so far';
    return 'Reading ${widget.clientName} — '
           '${widget.activeStepsCount} $stepsLabel, '
           '$sessionsPhrase';
  }
}
