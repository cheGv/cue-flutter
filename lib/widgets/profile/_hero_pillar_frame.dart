// lib/widgets/profile/_hero_pillar_frame.dart
//
// Phase 5.3 Round B — shared frame for the three hero pillars on
// Profile (Active STGs, Next Session, Last Session). Provides the
// common card container, header layout, edge polish, hover state,
// and optional Cue whisper rendering. The three pillars compose
// their own body/footer content into this frame.
//
// Edge polish per spec:
//   • Inset highlight on top edge (dark register only — gradient
//     suggesting light from above).
//   • Ring-shadowed accent icon container.
//   • Subtle outer shadow for elevation in dark mode.
//   • Hover: border + bg shift, no transform (kept simple here;
//     full hover-rise tween is in cue_motion's animation layer,
//     not duplicated for the pillars).
//
// File name leads with underscore by convention (signals "internal
// to the profile/ folder"); the class itself is public so the
// three pillar widgets that sit beside it can import cleanly.

import 'package:flutter/material.dart';

import '../../theme/cue_color_scheme.dart';
import '../cue_cuttlefish.dart';

class HeroPillarFrame extends StatefulWidget {
  /// Header icon. Rendered inside a ring-shadowed circular accent
  /// container at the start of the header row.
  final IconData icon;

  /// Accent color for the icon ring + header tag. Callers pick from
  /// cue.olive (STG), cue.amber (next session), cue.blue (last
  /// session), etc.
  final Color accent;

  /// Header tag — mono uppercase tracked, sits next to the icon.
  final String tag;

  /// Optional count chip — sits at the far right of the header
  /// (e.g., "3" for active goal count).
  final String? count;

  /// Main pillar body. Caller renders the headline + body text +
  /// stat row using the pillar's own typography choices.
  final Widget body;

  /// Optional footer (action pills, link, etc.). Sits at the
  /// bottom of the pillar, below any whisper.
  final Widget? footer;

  /// Optional Cue whisper — factual or interrogative ONLY (Pattern 6).
  /// Rendered with the small cuttlefish prefix + italic Iowan +
  /// cue.amber. Null = no whisper (most pillars will be quiet most
  /// of the time; that's the design).
  final String? whisper;

  /// Optional fixed minimum height. Defaults to 300 for the desktop
  /// pillar grid.
  final double minHeight;

  /// Optional onTap — entire pillar acts as a clickable surface.
  final VoidCallback? onTap;

  const HeroPillarFrame({
    super.key,
    required this.icon,
    required this.accent,
    required this.tag,
    this.count,
    required this.body,
    this.footer,
    this.whisper,
    this.minHeight = 300,
    this.onTap,
  });

  @override
  State<HeroPillarFrame> createState() => _HeroPillarFrameState();
}

class _HeroPillarFrameState extends State<HeroPillarFrame> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final cue = CueColorsResolved.of(context);
    final card = Container(
      constraints: BoxConstraints(minHeight: widget.minHeight),
      decoration: BoxDecoration(
        color: _hovered ? cue.bgCardHover : cue.bgCard,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: _hovered ? cue.borderHover : cue.border,
          width: 0.5,
        ),
        gradient: cue.isDark
            ? LinearGradient(
                begin: Alignment.topCenter,
                end:   Alignment.center,
                colors: [
                  Colors.white.withValues(alpha: 0.025),
                  _hovered ? cue.bgCardHover : cue.bgCard,
                ],
                stops: const [0.0, 0.05],
              )
            : null,
        boxShadow: cue.isDark
            ? const [
                BoxShadow(
                  color: Color(0x33000000),
                  blurRadius: 8,
                  offset: Offset(0, 2),
                ),
              ]
            : const [
                BoxShadow(
                  color: Color(0x0A000000),
                  blurRadius: 12,
                  offset: Offset(0, 2),
                ),
              ],
      ),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _header(cue),
          const SizedBox(height: 12),
          Expanded(child: widget.body),
          if (widget.whisper != null) ...[
            const SizedBox(height: 10),
            _whisperLine(cue),
          ],
          if (widget.footer != null) ...[
            const SizedBox(height: 10),
            widget.footer!,
          ],
        ],
      ),
    );

    final hoverable = MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit:  (_) => setState(() => _hovered = false),
      child: card,
    );

    if (widget.onTap == null) return hoverable;
    return GestureDetector(
      onTap: widget.onTap,
      behavior: HitTestBehavior.opaque,
      child: hoverable,
    );
  }

  Widget _header(CueColorsResolved cue) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Ring-shadowed accent icon container (Phase 5.3 edge polish).
        Container(
          width: 26,
          height: 26,
          decoration: BoxDecoration(
            color: widget.accent.withValues(alpha: cue.isDark ? 0.18 : 0.12),
            shape: BoxShape.circle,
            boxShadow: cue.isDark
                ? [
                    BoxShadow(
                      color: widget.accent.withValues(alpha: 0.20),
                      spreadRadius: 0.5,
                    ),
                  ]
                : null,
          ),
          child: Icon(widget.icon, size: 14, color: widget.accent),
        ),
        const SizedBox(width: 10),
        Text(
          widget.tag.toUpperCase(),
          style: TextStyle(
            fontFamily: 'JetBrains Mono',
            fontFamilyFallback: const ['monospace'],
            fontSize: 9.5,
            fontWeight: FontWeight.w600,
            letterSpacing: 9.5 * 0.18,
            color: widget.accent,
          ),
        ),
        const Spacer(),
        if (widget.count != null)
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: cue.bgInput,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: cue.border, width: 0.5),
            ),
            child: Text(
              widget.count!,
              style: TextStyle(
                fontFamily: 'Inter',
                fontFamilyFallback: const ['system-ui', 'sans-serif'],
                fontSize: 11,
                fontWeight: FontWeight.w700,
                fontFeatures: const [FontFeature.tabularFigures()],
                color: cue.textPrimary,
              ),
            ),
          ),
      ],
    );
  }

  Widget _whisperLine(CueColorsResolved cue) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(
          width: 14,
          height: 14,
          child: CueCuttlefish(size: 14, state: CueState.thinking),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            widget.whisper!,
            style: TextStyle(
              fontFamily: 'Iowan Old Style',
              fontFamilyFallback: const ['Georgia', 'Charter', 'serif'],
              fontSize: 12,
              fontStyle: FontStyle.italic,
              fontWeight: FontWeight.w400,
              height: 1.4,
              color: cue.amber,
            ),
          ),
        ),
      ],
    );
  }
}
