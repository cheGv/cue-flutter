// lib/widgets/linked_evidence.dart
//
// Phase 5.3 B.3 — semantic emphasis primitive for inline evidence references.
//
// Replaces the pre-B.3 "highlight = amber inline prose" treatment in the
// briefing card. The highlight phrase from the LLM brief response now
// renders with a quiet 1px semantic-color underline + faint tinted chip
// ground; text color stays cue.textBody so the highlight reads continuously
// with the surrounding prose. The underline + tint cue "this is cited
// evidence" without shouting it.
//
// Three semantic types are wired (light/dark color pair per type):
//   • data       (B.3 active)  — observation pulled from chart sessions,
//                                goals, or notes. Olive underline.
//   • artifact   (Phase 5.4)   — reference to a specific note, report, or
//                                document. Sky-blue underline.
//   • framework  (Phase 5.4)   — reference to a clinical framework or
//                                approach tag (DIR, AAC, fluency, etc.).
//                                Amber underline.
//
// For B.3 the LLM prompt emits a single undifferentiated `highlight` string
// and every highlight routes to type.data. Phase 5.4 will extend the prompt
// schema to tag highlight type and route the right LinkedEvidenceType per
// highlight.
//
// Dotted underline: Flutter's Border.bottom only supports BorderStyle.solid
// (and none). A true dotted underline requires a CustomPainter. For B.3 we
// ship a 1px solid underline; the semantic color + chip-shaped tint carry
// the meaning at the reading distance the brief is consumed at.
// CustomPainter dotted is banked for Phase 5.4 polish.
//
// Tap target: GestureDetector for B.3 since onTap is null at all call sites.
// Phase 5.4 wires evidence-source navigation here — at that point decide
// whether to wrap the briefing in Material + swap to InkWell for ripple, or
// stay with GestureDetector + custom tap feedback.

import 'package:flutter/material.dart';

import '../theme/cue_color_scheme.dart';

enum LinkedEvidenceType {
  /// Observation pulled from chart data (sessions, goals, notes).
  /// B.3 default — every highlight currently routes here.
  data,
  /// Reference to a specific note, report, or document. Phase 5.4.
  artifact,
  /// Reference to a clinical framework or approach tag. Phase 5.4.
  framework,
}

class LinkedEvidence extends StatelessWidget {
  /// The phrase to render with semantic-color underline + faint background.
  final String text;

  /// Semantic category — drives the underline color and background tint.
  /// B.3 always passes [LinkedEvidenceType.data].
  final LinkedEvidenceType type;

  /// Optional tap target — Phase 5.4 wires evidence-source navigation.
  /// B.3 leaves null.
  final VoidCallback? onTap;

  /// Caller-supplied TextStyle (typically the surrounding headline style).
  /// LinkedEvidence overrides color to cue.textBody internally — semantic
  /// carry is via underline + tint, NOT text color. Pass null only when
  /// the widget is used outside a styled context.
  final TextStyle? textStyle;

  const LinkedEvidence({
    super.key,
    required this.text,
    this.type = LinkedEvidenceType.data,
    this.onTap,
    this.textStyle,
  });

  @override
  Widget build(BuildContext context) {
    final cue    = CueColorsResolved.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final (Color underline, Color tint) = switch (type) {
      LinkedEvidenceType.data => (
        // B.3 active — olive matches the LTG strip dotted chips and the
        // active-STG pillar accent.
        isDark ? const Color(0xFF97C459) : const Color(0xFF5C6E3B),
        const Color(0x0D97C459), // ~5% olive
      ),
      LinkedEvidenceType.artifact => (
        // Phase 5.4 — sky/ink-blue for note/report/document references.
        isDark ? const Color(0xFF85B7EB) : const Color(0xFF4A6580),
        const Color(0x0D55BBFF), // ~5% sky
      ),
      LinkedEvidenceType.framework => (
        // Phase 5.4 — amber for clinical framework / approach tags.
        isDark ? const Color(0xFFEF9F27) : const Color(0xFF854F0B),
        const Color(0x0FBA7517), // ~6% amber (denser since amber hue mass
                                 // is lower at the same alpha)
      ),
    };

    final innerStyle = (textStyle ?? const TextStyle())
        .copyWith(color: cue.textBody);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 1),
        decoration: BoxDecoration(
          color:        tint,
          borderRadius: BorderRadius.circular(2), // gentle chip softening
          border: Border(
            bottom: BorderSide(
              color: underline,
              width: 1,
              style: BorderStyle.solid, // Phase 5.4 CustomPainter dotted
            ),
          ),
        ),
        child: Text(text, style: innerStyle),
      ),
    );
  }
}
