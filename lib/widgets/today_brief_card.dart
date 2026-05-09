// lib/widgets/today_brief_card.dart
//
// Phase 4.0.8-step-B-surface-1.2 — Today's brief card refactored to
// the dual-accent + eyebrow doctrine.
//
// Card structure (locked 2026-05-09):
//   Row 1 (header):  client name (Inter 20/600) + age/lens metadata
//                    (mono) + state pill (top-right, mono uppercase
//                    tracked — the one carve-out from "sans uppercase
//                    forbidden" because state pills are data tags)
//   Row 2:           "Today's move" — clinicalLabel(strong, olive) +
//                    move-text body (Inter 14/500 / kCueInk)
//   Row 3:           "Where we left off" (clinicalLabel strong) OR
//                    "Context" (clinicalLabel light) — depends on
//                    baselinePhase. Body text body() with inline
//                    trial counts in dataMono(olive) via Text.rich.
//
// Card chrome:
//   • Paper-white surface, kCueCardRadius (6) corners.
//   • Hairline border (kCueBorder) on top/right/bottom.
//   • LEFT STRIPE: kCueOlive at 2px (default) or kCueAmber at 3px
//     (when `isUpNext: true`) — dual-accent system. Olive = calm
//     clinical state; amber = urgent "this is the next session."
//
// State pill semantics:
//   Active     → olive surface ground + olive deep text (default for
//                ongoing engagements)
//   Up next    → amber surface ground + amber deep text (urgent —
//                synced with the amber left stripe)
//   Baseline   → ink-on-paper subtle pill
//   Phase 1 / Follow-up → reserved; mapped to olive ground for v1.2

import 'package:flutter/material.dart';

import '../theme/cue_phase4_tokens.dart';
import '../theme/cue_type_v3.dart';

/// Pure-data shape derived from the daily_roster + sessions join. The
/// TodayScreen state class assembles this from its existing loaders.
class TodayBrief {
  final String  clientName;
  final int?    clientAge;
  final String? clientLensSubtitle;

  /// Most-recent session date in display form (e.g. "3 May" or "today").
  final String? lastSessionDateLabel;
  final String? lastTargetBehavior;
  final String? lastActivity;
  final String? lastNarrative; // SOAP-S/notes etc. — concise summary
  final String? lastAccuracy;  // pre-formatted "3 of 8 (38%)" string
  final String? nextSessionFocus;

  /// Today's planned session start time (e.g. "9:00 AM"). Optional.
  final String? todayTimeLabel;

  /// True when the SLP has no history with this client at all — ie
  /// no prior session. Renders the baseline-phase Context body.
  final bool baselinePhase;

  const TodayBrief({
    required this.clientName,
    this.clientAge,
    this.clientLensSubtitle,
    this.lastSessionDateLabel,
    this.lastTargetBehavior,
    this.lastActivity,
    this.lastNarrative,
    this.lastAccuracy,
    this.nextSessionFocus,
    this.todayTimeLabel,
    this.baselinePhase = false,
  });
}

class TodayBriefCard extends StatelessWidget {
  final TodayBrief brief;
  final VoidCallback? onTap;

  /// True when this card represents the next-up session for the SLP.
  /// Drives the amber left-stripe + amber state pill. Caller decides
  /// (TodayScreen sets it on the first card that hasn't been started).
  final bool isUpNext;

  /// Optional state label override. Falls through to a derived value
  /// based on baselinePhase + isUpNext when null.
  final String? stateLabel;

  const TodayBriefCard({
    super.key,
    required this.brief,
    this.onTap,
    this.isUpNext = false,
    this.stateLabel,
  });

  String get _resolvedStateLabel {
    if (stateLabel != null && stateLabel!.isNotEmpty) return stateLabel!;
    if (isUpNext) return 'Up next';
    if (brief.baselinePhase) return 'Baseline';
    return 'Active';
  }

  @override
  Widget build(BuildContext context) {
    final stripeColor = isUpNext ? kCueAmber : kCueOlive;
    final stripeWidth = isUpNext ? 3.0 : 2.0;

    // Phase 4.0.8-step-B-surface-1.2 hotfix — Flutter's BoxDecoration
    // requires a UNIFORM Border when paired with borderRadius (all
    // four sides same width AND color). The pre-hotfix shape passed
    // a per-side Border (left: stripeWidth, others: kCueCardBorderW)
    // which silently dropped paint in release builds and rendered
    // cards as empty white shapes (the bug founder verification
    // caught). Restructure: outer container has Border.all (uniform)
    // + radius; left stripe lives inside a Row + IntrinsicHeight,
    // clipped to the radius via ClipRRect so the stripe doesn't
    // bleed past the rounded corner.
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap:        onTap,
        borderRadius: BorderRadius.circular(kCueCardRadius),
        child: Container(
          decoration: BoxDecoration(
            color:        kCueSurfaceWhite,
            borderRadius: BorderRadius.circular(kCueCardRadius),
            border:       Border.all(color: kCueBorder, width: kCueCardBorderW),
          ),
          child: ClipRRect(
            // Inner radius = outer radius minus border width so the
            // stripe lands flush inside the perimeter.
            borderRadius: BorderRadius.circular(
                kCueCardRadius - kCueCardBorderW),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(width: stripeWidth, color: stripeColor),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize:       MainAxisSize.min,
                        children: [
                          _header(),
                          const SizedBox(height: 14),
                          _todayMoveRow(),
                          const SizedBox(height: 12),
                          brief.baselinePhase ? _contextRow() : _whereWeLeftOffRow(),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── Row 1: name + metadata + state pill ────────────────────────────────
  Widget _header() {
    final metadataParts = <String>[
      if (brief.todayTimeLabel != null) brief.todayTimeLabel!,
      if (brief.clientAge != null) 'age ${brief.clientAge}',
      if (brief.clientLensSubtitle != null) brief.clientLensSubtitle!,
    ];
    final metadata = metadataParts.join(' · ');

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                brief.clientName,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily:         'Inter',
                  fontFamilyFallback: const ['system-ui', 'sans-serif'],
                  fontSize:           20,
                  fontWeight:         FontWeight.w600,
                  letterSpacing:      -0.2,
                  color:              kCueInk,
                  height:             1.1,
                ),
              ),
              if (metadata.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  metadata,
                  overflow: TextOverflow.ellipsis,
                  style:    CueTypeV3.dataMono(color: kCueInkSecondary).copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(width: 12),
        _statePill(),
      ],
    );
  }

  Widget _statePill() {
    final label = _resolvedStateLabel;
    final isUrgent  = isUpNext;
    final isBaseline = brief.baselinePhase && !isUpNext;

    final bg = isUrgent
        ? const Color(0xFFFBE9D2)
        : (isBaseline ? kCuePaper : kCueOliveSurface);
    final border = isUrgent
        ? const Color(0xFFE8DCB8)
        : (isBaseline ? kCueBorder : kCueOliveSurface);
    final textColor = isUrgent
        ? kCueAmberDeep
        : (isBaseline ? kCueInkTertiary : kCueOliveDeep);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color:        bg,
        border:       Border.all(color: border, width: kCueCardBorderW),
        borderRadius: BorderRadius.circular(4),
      ),
      // State pill — mono uppercase tracked. The ONE carve-out from
      // "sans uppercase tracked forbidden" because state pills are
      // data tags (per eyebrow doctrine).
      child: Text(label.toUpperCase(), style: CueTypeV3.dataEyebrow(color: textColor)),
    );
  }

  // ── Row 2: Today's move (always renders) ───────────────────────────────
  Widget _todayMoveRow() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "Today's move",
          style: CueTypeV3.clinicalLabel(emphasis: 'strong', color: kCueOlive),
        ),
        const SizedBox(height: 4),
        Text(
          _todayMoveBody(),
          style: TextStyle(
            fontFamily:         'Inter',
            fontFamilyFallback: const ['system-ui', 'sans-serif'],
            fontSize:           14,
            fontWeight:         FontWeight.w500,
            letterSpacing:      -0.07, // -0.005em × 14
            color:              kCueInk,
            height:             1.45,
          ),
        ),
      ],
    );
  }

  // ── Row 3a: Where we left off (when baselinePhase = false) ─────────────
  Widget _whereWeLeftOffRow() {
    final narrative = brief.lastNarrative?.trim();
    final accuracy  = brief.lastAccuracy?.trim();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Where we left off',
          style: CueTypeV3.clinicalLabel(emphasis: 'strong'),
        ),
        const SizedBox(height: 4),
        _whereWeLeftOffBody(narrative, accuracy),
      ],
    );
  }

  /// Body for "Where we left off" — Text.rich pattern. Prose in body();
  /// trial-count spans in dataMono(olive) inline.
  Widget _whereWeLeftOffBody(String? narrative, String? accuracy) {
    final fallback = brief.lastTargetBehavior?.trim().isNotEmpty == true
        ? 'Target was: ${brief.lastTargetBehavior}.'
        : 'Session not yet documented.';

    if ((narrative == null || narrative.isEmpty) &&
        (accuracy == null || accuracy.isEmpty)) {
      return Text(fallback, style: CueTypeV3.body(color: kCueInkSecondary));
    }

    final spans = <InlineSpan>[];
    if (narrative != null && narrative.isNotEmpty) {
      spans.add(TextSpan(text: narrative.trimRight()));
    }
    if (accuracy != null && accuracy.isNotEmpty) {
      if (spans.isNotEmpty) {
        spans.add(const TextSpan(text: ' · '));
      }
      spans.add(TextSpan(
        text:  'Accuracy: ',
        style: CueTypeV3.body(color: kCueInkSecondary),
      ));
      spans.add(TextSpan(
        text:  accuracy,
        style: CueTypeV3.dataMono(color: kCueOlive),
      ));
    }

    return Text.rich(
      TextSpan(
        style:    CueTypeV3.body(color: kCueInkSecondary),
        children: spans,
      ),
    );
  }

  // ── Row 3b: Context (when baselinePhase = true) ────────────────────────
  Widget _contextRow() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Context', style: CueTypeV3.clinicalLabel(emphasis: 'light')),
        const SizedBox(height: 4),
        Text(
          'Baseline phase — no sessions on record. '
          'Begin baseline observation today.',
          style: CueTypeV3.body(color: kCueInkSecondary),
        ),
      ],
    );
  }

  // ── Body content assembler — Today's move ──────────────────────────────
  String _todayMoveBody() {
    if (brief.baselinePhase) return 'Begin baseline observation.';
    final next = brief.nextSessionFocus?.trim();
    if (next != null && next.isNotEmpty) return next;
    final stg = brief.lastTargetBehavior?.trim();
    if (stg != null && stg.isNotEmpty) {
      return 'Continue: $stg.';
    }
    return 'No move on file — set the next focus during today\'s session.';
  }
}
