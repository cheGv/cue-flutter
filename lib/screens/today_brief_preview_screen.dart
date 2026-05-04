// lib/screens/today_brief_preview_screen.dart
//
// Phase 4.0.7.21 — throwaway preview screen. Renders all five
// TodayBriefVariant widgets vertically with the same mock case so the
// SLP can scroll through and pick a register. The chosen variant gets
// re-implemented for production in 4.0.7.21b. Delete this file after.
//
// Reachable from Settings → Today Brief Preview (dev) — not exposed
// in any user-facing nav.

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../widgets/today_brief_variants.dart';

const Color _paper    = Color(0xFFFAF6EE);
const Color _ink      = Color(0xFF0E1C36);
const Color _inkGhost = Color(0xFF6B7690);

class TodayBriefPreviewScreen extends StatelessWidget {
  const TodayBriefPreviewScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final brief = BriefCase.aaravMock();

    return Scaffold(
      backgroundColor: _paper,
      appBar: AppBar(
        backgroundColor: _paper,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: _ink),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Text(
          'Design exploration',
          style: GoogleFonts.dmSans(
              fontSize: 14, color: _inkGhost, fontWeight: FontWeight.w500),
        ),
        centerTitle: false,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 60),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Title ─────────────────────────────────────────────
            Text(
              "Today's Brief",
              style: GoogleFonts.playfairDisplay(
                fontSize: 36,
                fontWeight: FontWeight.w400,
                fontStyle: FontStyle.italic,
                color: _ink,
                height: 1.05,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'design exploration · five variants, same mock case',
              style: GoogleFonts.dmSans(
                fontSize: 13,
                color: _inkGhost,
                fontStyle: FontStyle.italic,
              ),
            ),
            const SizedBox(height: 28),

            _label('VARIANT A — EDITORIAL BRIEFING'),
            TodayBriefVariantA(brief: brief),
            const SizedBox(height: 36),

            _label('VARIANT B — CLINICAL HANDOFF'),
            TodayBriefVariantB(brief: brief),
            const SizedBox(height: 36),

            _label('VARIANT C — CONTINUUM'),
            TodayBriefVariantC(brief: brief),
            const SizedBox(height: 36),

            _label('VARIANT D — QUESTION-DRIVEN'),
            TodayBriefVariantD(brief: brief),
            const SizedBox(height: 36),

            _label('VARIANT E — COMPACT STACK'),
            TodayBriefVariantE(brief: brief),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _label(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        text,
        style: GoogleFonts.syne(
          fontSize:      10,
          fontWeight:    FontWeight.w600,
          color:         _ink,
          letterSpacing: 1.6,
        ),
      ),
    );
  }
}
