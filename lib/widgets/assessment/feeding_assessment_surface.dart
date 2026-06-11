// lib/widgets/assessment/feeding_assessment_surface.dart
//
// Childhood Feeding — Phase 1 (capture). Wired on clinical_area
// 'pediatric-feeding'. A FEEDING-SKILLS surface: three capture layers
// (oral-motor dissociation, the developmental feeding ladder, mealtime
// behaviours) + the swallow off-ramp caution. It is NOT a swallowing /
// dysphagia surface — airway safety is a separate later surface; this one
// only FLAGS toward it.
//
// ── ARCHITECTURE — the feeding LAYER-MODULE pattern (2026-06-11) ─────────
// Proof-of-shape for adaptive assembly, FEEDING-LOCAL by design (no
// cross-surface registry; SSD/CAS/voice stay monolithic until their own
// per-surface migrations — the CueSurfaceScope playbook). This file is the
// LIBRARY ROOT; the modules live in `part` files sharing one library scope:
//
//   feeding_assessment_controller.dart  (separate library) — the data spine
//   feeding_primitives.dart        (part) — palette/registers/primitives,
//                                           library-private so they cannot
//                                           leak into other surfaces
//   feeding_dissociation_layer.dart (part) — FeedingDissociationLayer
//   feeding_ladder_layer.dart       (part) — FeedingLadderLayer
//   feeding_behaviors_layer.dart    (part) — FeedingBehaviorsLayer
//   feeding_off_ramp_card.dart      (part) — FeedingOffRampCard
//
// Assembly knobs (public wrapper params): FeedingLadderLayer.openBandKey /
// highlightAgeMatch; FeedingBehaviorsLayer.filter / showStarterSet.
//
// ── THE OFF-RAMP BINDING CONTRACT (structural, non-negotiable) ───────────
// The safety caution is bound to the content that triggers it, NOT to a
// router's discretion:
//   * The bare layer BODIES (_FeedingLadderBody, _FeedingBehaviorsBody) are
//     LIBRARY-PRIVATE. Outside this library they are unconstructible.
//   * The ONLY public ways to mount ladder or behaviour content are
//     FeedingLadderLayer / FeedingBehaviorsLayer, whose build() includes
//     FeedingOffRampCard unconditionally. There is no includeOffRamp
//     parameter; the card cannot be opted out of.
//   * The card gates its own visibility on controller.offRampActive —
//     SIGN-TRIGGERED (clinician sign-off 2026-06-11): ONLY an airway-sign
//     behaviour marked present fires it, at any age; age alone never does.
//     A router cannot dodge it by mounting "while inactive": the card is in
//     the tree and reacts live the moment a sign is marked.
//   * The composer below uses the private bodies and mounts ONE card after
//     the sections — the pre-refactor position, exactly. A router mounting
//     BOTH public wrappers side by side gets two cards when active; that
//     duplication is the safe direction and is accepted until a future
//     multi-layer host dedups it.
//   * FeedingDissociationLayer carries no card — dissociation content alone
//     cannot trigger the off-ramp.
//
// SAFETY (stricter than SSD — airway-adjacent scope):
//   * Cue NEVER judges feeding adequacy, developmental status, or swallow
//     safety. There is no derived metric and no computed verdict anywhere on
//     this surface. The ladder SURFACES what is expected at an age; the
//     clinician marks the child against it (at level / emerging / below
//     level / not tested). The gap stays visible, never computed or labelled.
//   * Red-flag text renders as a WATCH-FOR observation prompt, never a
//     verdict. The clinician decides whether a sign is present and what it
//     means.
//   * Empty stays empty — untouched fields stay NULL and render unmarked.
//   * The onOpenSwallow seam is DORMANT in Phase 1 — null renders caution
//     text only; the handoff button appears only when a host screen wires
//     the callback (exactly SSD's onOpenCas pattern).
//
// CONTENT: lib/constants/feeding_ladder_content.dart (brand-neutral,
// literature-grounded). Clinician sign-off 2026-06-11: red-flag prompts
// (content v2) + the sign-only off-ramp trigger + the starter set are
// SIGNED OFF; the Western-norm caveat and off-ramp caution WORDING stay v1,
// to be refined in real clinician testing.
//
// TYPOGRAPHY & PALETTE — the SSD surface's locked spine registers verbatim:
// JetBrains Mono eyebrows for data tags, Inter for everything read, no
// italic on a clinical-action surface, olive calm / amber urgent, ink
// #1B2B4B, hairline #E8E4DC, radius 8/6, 4/8/12/16 rhythm. Layer-1 status
// chips are colour-coded per spec (present green / emerging amber / absent
// coral); ladder markings and behaviour statuses stay in the calm olive
// selection register — the clinician's mark is hers, the surface does not
// editorialise it. Urgency belongs to the off-ramp alone.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../constants/feeding_ladder_content.dart';
import '../../services/feeding_assessment_service.dart';
import 'feeding_assessment_controller.dart';

part 'feeding_primitives.dart';
part 'feeding_dissociation_layer.dart';
part 'feeding_ladder_layer.dart';
part 'feeding_behaviors_layer.dart';
part 'feeding_off_ramp_card.dart';

/// The thin composer — the IDENTICAL pre-refactor public API and static
/// experience: bootstraps one controller, arranges the three layers in the
/// accordion, mounts ONE off-ramp card after the sections, footer, breathing
/// room. Host screens keep using exactly this; routers use the layer
/// widgets + a controller directly.
class FeedingAssessmentSurface extends StatefulWidget {
  final String clientId;

  /// DORMANT handoff seam (Phase 1): invoked by the swallow off-ramp's
  /// "Open swallow assessment" action once a swallow surface exists for a
  /// host screen to route to. While null (all of Phase 1), the off-ramp
  /// renders caution text only — no dead button. Mirrors SSD's onOpenCas.
  final VoidCallback? onOpenSwallow;

  /// Test seam: inject a service (e.g. an in-memory fake). Defaults to the
  /// shared singleton in production.
  final FeedingAssessmentService? service;

  const FeedingAssessmentSurface({
    super.key,
    required this.clientId,
    this.onOpenSwallow,
    this.service,
  });

  @override
  State<FeedingAssessmentSurface> createState() =>
      _FeedingAssessmentSurfaceState();
}

class _FeedingAssessmentSurfaceState extends State<FeedingAssessmentSurface> {
  late final FeedingAssessmentController _controller;

  String _expanded = 'oralmotor';

  @override
  void initState() {
    super.initState();
    _controller = FeedingAssessmentController(
        clientId: widget.clientId, service: widget.service);
    _controller.bootstrap();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Widget _accordion({
    required String id,
    required int number,
    required String title,
    required String tagline,
    required Widget child,
  }) {
    return _section(
      open: _expanded == id,
      onToggle: () => setState(() => _expanded = _expanded == id ? '' : id),
      number: number,
      title: title,
      tagline: tagline,
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    return _controllerGated(_controller, () {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ghostNote(
              'Feeding-SKILLS capture: oral-motor dissociation, the developmental '
              'feeding ladder, and mealtime behaviours. This is not a swallowing / '
              'dysphagia assessment — airway safety has its own boundary and its '
              'own (separate) assessment. Expectations and watch-for prompts come '
              'from the developmental-feeding literature (Arvedson; Delaney & '
              'Goday; the New York State Early Intervention guideline; ASHA '
              'practice guidance; the Goday et al. pediatric feeding disorder '
              'consensus). Every judgement — adequacy, developmental status, what '
              'a sign means — is yours; Cue computes nothing here.'),
          const SizedBox(height: 16),
          _accordion(
              id: 'oralmotor',
              number: 1,
              title: 'Oral-motor dissociation',
              tagline:
                  'Five functions — the observable sign first, the term second. You mark.',
              child: _FeedingDissociationBody(controller: _controller)),
          const SizedBox(height: 12),
          _accordion(
              id: 'ladder',
              number: 2,
              title: 'Developmental feeding ladder',
              tagline:
                  'Age in → the expected band surfaces. You mark the child against it.',
              child: _FeedingLadderBody(controller: _controller)),
          const SizedBox(height: 12),
          _accordion(
              id: 'behaviors',
              number: 3,
              title: 'Feeding behaviours',
              tagline:
                  'Add what you observed — starter set or your own words. Present / absent.',
              child: _FeedingBehaviorsBody(controller: _controller)),
          // ONE off-ramp card for the whole composed surface — self-gating
          // (renders nothing while inactive), pre-refactor position.
          FeedingOffRampCard(
              controller: _controller, onOpenSwallow: widget.onOpenSwallow),
          const SizedBox(height: 16),
          _footerLink(),
          // Bottom breathing room — the off-ramp / caveat must never sit
          // clipped at the viewport edge (SSD convention).
          const SizedBox(height: 32),
        ],
      );
    });
  }

  Widget _footerLink() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Icon(Icons.south_rounded, size: 14, color: _olive),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
              'Feeds Diagnostic synthesis — the feeding-skills statement is '
              'yours to write; swallow safety is a separate assessment.',
              style: GoogleFonts.inter(
                  fontSize: 12, color: _olive, fontWeight: FontWeight.w500)),
        ),
      ]),
    );
  }
}
