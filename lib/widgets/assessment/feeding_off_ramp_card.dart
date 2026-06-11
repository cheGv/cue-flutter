// lib/widgets/assessment/feeding_off_ramp_card.dart
//
// part of the feeding layer-module library (see feeding_assessment_surface.dart
// for the library doc + the off-ramp binding contract).
//
// The swallow off-ramp — the SAFETY BOUNDARY of the feeding surface. Public
// and mountable on its own, but never needed alone: the ladder / behaviours
// layer wrappers build it in unconditionally, and the composer mounts the
// single composed instance. SELF-GATING: it listens to the controller and
// renders nothing while the trigger is inactive, so hosts mount it
// unconditionally and can never "forget" it when the trigger state changes.
//
// Trigger — SIGN-TRIGGERED (clinician sign-off 2026-06-11): fires ONLY when
// an airway-sign behaviour is marked present, at ANY age. Age alone never
// fires it (an age-based alarm cries wolf on typically developing toddlers
// and trains the safety channel to be dismissed; the 18mo+ bands keep their
// in-band airway GUIDANCE text instead). Because active now always means a
// sign is marked, the card has ONE register — coral, naming the marked
// sign(s) — the pre-sign-off amber "age band" state is gone.
//
// The onOpenSwallow seam is DORMANT in Phase 1: null renders the caution +
// referral-cue line and NO dead button; the handoff FilledButton appears
// only when a host wires the callback (SSD's onOpenCas pattern).

part of 'feeding_assessment_surface.dart';

class FeedingOffRampCard extends StatelessWidget {
  final FeedingAssessmentController controller;
  final VoidCallback? onOpenSwallow;

  const FeedingOffRampCard({
    super.key,
    required this.controller,
    this.onOpenSwallow,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        if (!controller.offRampActive) return const SizedBox.shrink();
        return Padding(
          // The 16px breathing room above the card travels WITH the card so
          // every mount point (composer, layer wrappers) spaces identically.
          padding: const EdgeInsets.only(top: 16),
          child: Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            decoration: BoxDecoration(
              color: _amberSoft.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(8),
              border:
                  Border.all(color: _coral.withValues(alpha: 0.7), width: 1.2),
            ),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const Icon(Icons.alt_route_rounded, size: 18, color: _coral),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('Airway sign marked — swallow assessment warranted',
                      style: GoogleFonts.inter(
                          fontSize: 14,
                          color: _coral,
                          fontWeight: FontWeight.w700)),
                ),
              ]),
              const SizedBox(height: 8),
              // Wording v1 — refine in real clinician testing.
              Text(kFeedingOffRampCaution,
                  style: GoogleFonts.inter(
                      fontSize: 12.5, color: _ink, height: 1.45)),
              // Active always means at least one marked sign — name them.
              const SizedBox(height: 8),
              for (final b in controller.behaviors.where((b) =>
                  b['airway_sign'] == true && b['status'] == 'present'))
                Text('→ ${b['behavior_label']} — marked present',
                    style: GoogleFonts.inter(
                        fontSize: 12.5,
                        color: _ink,
                        fontWeight: FontWeight.w600,
                        height: 1.45)),
              const SizedBox(height: 10),
              if (onOpenSwallow != null)
                Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton.icon(
                    onPressed: onOpenSwallow,
                    icon: const Icon(Icons.arrow_forward_rounded,
                        size: 16, color: Colors.white),
                    label: Text('Open swallow assessment',
                        style: GoogleFonts.inter(
                            fontSize: 13,
                            color: Colors.white,
                            fontWeight: FontWeight.w600)),
                    style: FilledButton.styleFrom(
                      backgroundColor: _amber,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                )
              else
                // Phase 1: the seam is dormant — caution text, no dead button.
                Text(
                    'The swallow / instrumental assessment surface ships later in '
                    'Cue — treat this flag as the referral cue.',
                    style: GoogleFonts.inter(
                        fontSize: 12, color: _inkSecondary, height: 1.45)),
            ]),
          ),
        );
      },
    );
  }
}
