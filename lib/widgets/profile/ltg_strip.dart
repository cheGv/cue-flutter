// lib/widgets/profile/ltg_strip.dart
//
// Phase 5.3 Round B.1 — quiet horizontal band listing the client's
// active long-term goals. Sits below the identity block, above the
// three hero pillars. Demoted register on purpose: small text, olive
// accent dots, no card chrome, no border. The strip's job is to put
// the LTGs in the SLP's peripheral vision while the pillars get the
// foreground.
//
// Empty state: a single line of muted prose pointing at the popup CTA.
// Populated state: a Wrap of per-LTG chips that flow onto multiple
// lines at narrow widths.
//
// Typography: mono uppercase tracked for the eyebrow ("WORKING TOWARD")
// and per-LTG domain tag. Inter 12.5 for the LTG body text. Olive dot
// (3.5px) marks each chip. No projection language anywhere — the strip
// states what IS, never what's expected.

import 'package:flutter/material.dart';

import '../../theme/cue_color_scheme.dart';

class LtgStrip extends StatelessWidget {
  /// Active long-term goals (filter applied by caller). Empty list →
  /// empty-state copy + Build-plan CTA.
  final List<Map<String, dynamic>> activeLtgs;

  /// Client's display name — surfaced in the empty-state copy only.
  final String clientName;

  /// Optional tap handler — opens CuePopup with goal-authoring intent
  /// (Round B.1 passes Profile's _toggleCuePopup; Round G refines).
  final VoidCallback? onAskCue;

  const LtgStrip({
    super.key,
    required this.activeLtgs,
    required this.clientName,
    this.onAskCue,
  });

  @override
  Widget build(BuildContext context) {
    final cue = CueColorsResolved.of(context);
    if (activeLtgs.isEmpty) {
      return _emptyState(cue);
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Wrap(
        spacing: 18,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          _eyebrow(cue),
          for (final ltg in activeLtgs) _ltgChip(ltg, cue),
        ],
      ),
    );
  }

  Widget _eyebrow(CueColorsResolved cue) {
    return Text(
      'WORKING TOWARD',
      style: TextStyle(
        fontFamily: 'JetBrains Mono',
        fontFamilyFallback: const ['monospace'],
        fontSize: 9.5,
        fontWeight: FontWeight.w600,
        letterSpacing: 9.5 * 0.16,
        color: cue.textMuted,
      ),
    );
  }

  Widget _ltgChip(Map<String, dynamic> ltg, CueColorsResolved cue) {
    final domain = ((ltg['domain'] as String?) ??
                    (ltg['category'] as String?) ?? '')
                  .trim();
    final text = ((ltg['goal_text'] as String?) ??
                  (ltg['original_text'] as String?) ?? '')
                .trim();
    if (text.isEmpty && domain.isEmpty) {
      return const SizedBox.shrink();
    }
    final short = text.length > 56 ? '${text.substring(0, 53)}…' : text;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 320),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 5,
            height: 5,
            decoration: BoxDecoration(
              color: cue.olive,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          if (domain.isNotEmpty) ...[
            Text(
              domain.toUpperCase().replaceAll('_', ' '),
              style: TextStyle(
                fontFamily: 'JetBrains Mono',
                fontFamilyFallback: const ['monospace'],
                fontSize: 9.5,
                fontWeight: FontWeight.w600,
                letterSpacing: 9.5 * 0.16,
                color: cue.olive,
              ),
            ),
            const SizedBox(width: 6),
          ],
          if (short.isNotEmpty)
            Flexible(
              child: Text(
                short,
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontFamilyFallback: const ['system-ui', 'sans-serif'],
                  fontSize: 12.5,
                  fontWeight: FontWeight.w400,
                  letterSpacing: -0.06,
                  color: cue.textBody,
                ),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ),
        ],
      ),
    );
  }

  Widget _emptyState(CueColorsResolved cue) {
    final firstName = _firstName();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 4,
        children: [
          Text(
            'No long-term goals for $firstName yet —',
            style: TextStyle(
              fontFamily: 'Inter',
              fontFamilyFallback: const ['system-ui', 'sans-serif'],
              fontSize: 12.5,
              color: cue.textMuted,
            ),
          ),
          if (onAskCue != null)
            GestureDetector(
              onTap: onAskCue,
              behavior: HitTestBehavior.opaque,
              child: Text(
                'build a plan with Cue →',
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontFamilyFallback: const ['system-ui', 'sans-serif'],
                  fontSize: 12.5,
                  fontWeight: FontWeight.w500,
                  color: cue.amber,
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _firstName() {
    final parts = clientName.trim().split(RegExp(r'\s+'));
    return parts.isEmpty ? clientName : parts.first;
  }
}
