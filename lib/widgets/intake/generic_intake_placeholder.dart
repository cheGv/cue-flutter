// lib/widgets/intake/generic_intake_placeholder.dart
//
// Phase 4.0.7.24a-fix2 — placeholder card shown by the
// add_client_screen intake router when the SLP picks a clinical_area
// for which the per-domain intake widget hasn't shipped yet (anything
// other than 'fluency' as of this commit).
//
// Visual register matches the amber stub blocks used in
// widgets/assessment/voice_capture_section.dart so the SLP recognizes
// this as "intentionally not built yet" rather than a broken screen.
// Per-domain authoring lands in 4.0.7.24c–l; this card retires once
// every clinical_area has its own intake section.

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/cue_phase4_tokens.dart';

const Color _amberStubBg     = Color(0xFFF4E4C4);
const Color _amberStubBorder = Color(0xFFD68A2B);
const Color _amberStubInk    = Color(0xFF7A4A0F);

class GenericIntakePlaceholder extends StatelessWidget {
  /// Canonical clinical_area code (e.g. 'voice', 'dysphagia') — used
  /// only for analytics / debug. Display copy reads from
  /// [clinicalAreaLabel].
  final String clinicalArea;

  /// SLP-facing label for the clinical area, resolved by the parent
  /// via clinicalAreaLabel(code). Drives the eyebrow and body copy.
  final String clinicalAreaLabel;

  /// Phase 4.0.7.27c-prep — optional override for the eyebrow suffix
  /// that follows the area label (e.g. '— NOW SHIPPED',
  /// '— DIFFERENTIAL PENDING'). Defaults to '— COMING SOON' when null.
  final String? headerSuffix;

  /// Phase 4.0.7.27c-prep — optional override for the body copy.
  /// When provided, replaces the generic "We're building…" text with
  /// area-specific roadmap context so stale references are never shown.
  final String? bodyText;

  const GenericIntakePlaceholder({
    super.key,
    required this.clinicalArea,
    required this.clinicalAreaLabel,
    this.headerSuffix,
    this.bodyText,
  });

  @override
  Widget build(BuildContext context) {
    final suffix = headerSuffix ?? '— COMING SOON';
    final body = bodyText ??
        "We're building domain-specific intake fields for "
        '$clinicalAreaLabel. For now, the basic information and '
        'concern field above are sufficient.';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
      decoration: BoxDecoration(
        color: _amberStubBg,
        borderRadius: BorderRadius.circular(kCueCardRadius),
        border: Border.all(color: _amberStubBorder, width: kCueCardBorderW),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${clinicalAreaLabel.toUpperCase()} INTAKE $suffix',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: _amberStubInk,
              letterSpacing: kCueEyebrowLetterSpacing(11),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            body,
            style: GoogleFonts.dmSans(
              fontSize: 13,
              color: _amberStubInk,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}
