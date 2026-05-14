// lib/widgets/domain_pill.dart
//
// Domain Detector Evening 3 — display-only render of the clinical-domain
// classification pill. Three host surfaces (Clients Roster, Today brief
// card, Session capture header), two registers (library-browse +
// clinical-task). Logic, triggers, override popover, and live data
// wiring all land in Evening 3.5.
//
// Tokens: kCue* from cue_phase4_tokens.dart. Typography: CueTypeV3.
// Spec lineage: v1.3.1 Task 5 + Evening 3 decisions D1-D5.
//
// Tooltip audit (Evening 3 recon): neither clients_roster_row.dart nor
// today_brief_card.dart use Tooltip. The only Tooltip use in
// lib/widgets/** is voice_capture_section.dart (lines 1443, 1487), using
// the default Material Tooltip with just message+child — no custom
// styling. DomainPill matches that precedent.
//
// D-decisions from the v1.3.1 Evening 3 plan, baked in here:
//   D1: surface A mounts the pill in a vertical stack below the existing
//       state pill within the same 90w column.
//   D2: surface B mounts the pill below the existing state pill in
//       _header()'s top-right Column.
//   D3: surface B locks to clinicalTask register (mono uppercase tracked)
//       to match the existing TodayBriefCard state pill — no visual
//       review needed.
//   D4: borderless on detected pills. Neutral/placeholder pills carry a
//       1px solid kCueInkSecondary border to indicate tappable.
//   D5: belowThreshold and failed render identically (kCueGraySurface
//       ground, 1px border). Only the tooltip text differs. The dotted-
//       border variant from the v1.3.1 spec is deferred to v1.4.

import 'package:flutter/material.dart';

import '../theme/cue_phase4_tokens.dart';
import '../theme/cue_type_v3.dart';

// ── Domain enum (matches DB controlled vocabulary) ────────────────────
enum ClinicalDomain {
  dysphagia,
  aac,
  motorSpeech,
  language,
  fluency,
  voice,
  aphasia,
  asdRegulatory,
  cognitiveCommunication,
}

// ── Bucket enum (basis for two-color spine mapping) ───────────────────
enum DomainBucket {
  acuteClinical,  // amber accent
  developmental,  // olive accent
}

// ── Canonical bucket mapping ──────────────────────────────────────────
//
// Source of truth: prompts/reviews/domain_detector_v1.3.2.md in the
// proxy repo, plus the CLAUDE.md §12 backlog item "Domain Detector
// v1.3.2 — CLAUDE.md doctrine backlog". Adding a domain requires
// updating this map AND the proxy's VALID_CLINICAL_DOMAINS AND the
// migration's CHECK constraint — see CLAUDE.md §12 backlog item for
// the full six-place rule (migration, prompt, bucket assignment, chip
// vocabulary, report template, Cue Study query weighting).
const Map<ClinicalDomain, DomainBucket> kDomainBucket = {
  ClinicalDomain.dysphagia:              DomainBucket.acuteClinical,
  ClinicalDomain.aphasia:                DomainBucket.acuteClinical,
  ClinicalDomain.voice:                  DomainBucket.acuteClinical,
  ClinicalDomain.cognitiveCommunication: DomainBucket.acuteClinical,
  ClinicalDomain.language:               DomainBucket.developmental,
  ClinicalDomain.motorSpeech:            DomainBucket.developmental,
  ClinicalDomain.aac:                    DomainBucket.developmental,
  ClinicalDomain.asdRegulatory:          DomainBucket.developmental,
  ClinicalDomain.fluency:                DomainBucket.developmental,
};

// ── Display labels (sentence-case canonical; clinicalTask register
//    applies .toUpperCase() at render time) ─────────────────────────────
const Map<ClinicalDomain, String> _kDomainLabel = {
  ClinicalDomain.dysphagia:              'Dysphagia',
  ClinicalDomain.aac:                    'AAC',
  ClinicalDomain.motorSpeech:            'Motor speech',
  ClinicalDomain.language:               'Language',
  ClinicalDomain.fluency:                'Fluency',
  ClinicalDomain.voice:                  'Voice',
  ClinicalDomain.aphasia:                'Aphasia',
  ClinicalDomain.asdRegulatory:          'ASD regulatory',
  ClinicalDomain.cognitiveCommunication: 'Cognitive comm',
};

// ── Pill register (drives typography + label casing) ──────────────────
enum DomainPillRegister {
  libraryBrowse,  // Surface A: Inter 11 / w500 / -0.055ls (sentence-case)
  clinicalTask,   // Surface B + C: CueTypeV3.dataEyebrow (mono uppercase tracked)
}

// ── Pill state (drives ground / label / border / tooltip) ─────────────
enum DomainPillState {
  detected,        // Show domain pill with bucket ground
  detecting,       // Evening 3.5: pulse animation. v1.3.x renders same as
                   // belowThreshold (visual placeholder).
  belowThreshold,  // Neutral gray + 1px border. Tooltip "Tap to set".
  failed,          // Same visual as belowThreshold; tooltip describes the
                   // failure so SLP discovers via hover/tap.
}

class DomainPill extends StatelessWidget {
  /// Detected clinical domain. Must be non-null when [state] == detected
  /// for the pill to render its bucket variant. If null with detected
  /// state, the pill defensively falls through to belowThreshold visuals.
  final ClinicalDomain? domain;

  /// Detection confidence 0.0–1.0. Null when [state] != detected.
  /// confidence < 0.75 is reserved for a v1.4 outline variant (deferred
  /// per Evening 3 D5).
  final double? confidence;

  /// Typography + label casing register.
  final DomainPillRegister register;

  /// Drives ground color, label, border presence, tooltip text.
  final DomainPillState state;

  /// Tap callback. Wired through GestureDetector so the API is ready for
  /// Evening 3.5 — but in v1.3.x the onTap should be a no-op (or null).
  /// Evening 3.5 wires this to open the override popover.
  final VoidCallback? onTap;

  /// Optional reasoning text from the detector. Used as the Tooltip
  /// message on detected pills.
  final String? reasoning;

  const DomainPill({
    super.key,
    required this.register,
    required this.state,
    this.domain,
    this.confidence,
    this.onTap,
    this.reasoning,
  });

  @override
  Widget build(BuildContext context) {
    final isDetected = state == DomainPillState.detected && domain != null;
    final bucket = isDetected ? kDomainBucket[domain!]! : null;

    // Ground + text + border resolution.
    final Color ground;
    final Color textColor;
    final Border? border;
    if (isDetected) {
      // D4: borderless on detected.
      ground    = bucket == DomainBucket.acuteClinical
          ? kCueAmberSurface
          : kCueOliveSurface;
      textColor = bucket == DomainBucket.acuteClinical
          ? kCueAmberText
          : kCueOliveDeep;
      border    = null;
    } else {
      // D5: belowThreshold + failed + detecting all render identically
      // in v1.3.x. D4: 1px solid kCueInkSecondary border indicates
      // tappable.
      ground    = kCueGraySurface;
      textColor = kCueInkSecondary;
      border    = Border.all(color: kCueInkSecondary, width: 1.0);
    }

    // Label resolution (sentence-case canonical; .toUpperCase() for
    // clinicalTask).
    final rawLabel = isDetected ? _kDomainLabel[domain!]! : 'Tap to set';
    final label = register == DomainPillRegister.clinicalTask
        ? rawLabel.toUpperCase()
        : rawLabel;

    // Tooltip text — per-state.
    final String? tooltipText;
    switch (state) {
      case DomainPillState.detected:
        tooltipText = reasoning;
        break;
      case DomainPillState.detecting:
        tooltipText = 'Detecting…';
        break;
      case DomainPillState.belowThreshold:
        tooltipText = 'Tap to set the clinical domain';
        break;
      case DomainPillState.failed:
        tooltipText =
            "Couldn't auto-detect from current case info. Tap to set manually.";
        break;
    }

    // Typography per register.
    final textStyle = register == DomainPillRegister.libraryBrowse
        ? TextStyle(
            fontFamily:         'Inter',
            fontFamilyFallback: const ['system-ui', 'sans-serif'],
            fontSize:           11,
            fontWeight:         FontWeight.w500,
            letterSpacing:      -0.055,
            color:              textColor,
          )
        : CueTypeV3.dataEyebrow(color: textColor);

    final pill = Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color:        ground,
        border:       border,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(label, style: textStyle),
    );

    final tappable = onTap == null
        ? pill
        : MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap:    onTap,
              child:    pill,
            ),
          );

    return (tooltipText == null || tooltipText.isEmpty)
        ? tappable
        : Tooltip(message: tooltipText, child: tappable);
  }
}
