// lib/widgets/cue_hold/cue_hold_whisper.dart
//
// Phase 4.1.3 — WHISPER state. The Hold expands from ~180px to ~260px
// and displays a proactive insight in italic Playfair Display 12px
// alongside the cuttlefish mark.
//
// Width animates via AnimatedSize on the parent. Auto-dismiss after 8s
// is handled by CueHoldController (see toWhisper). Tap fires onTap —
// the caller transitions the controller to EXPANDED, seeding the
// conversation with the whisper text as the opening Cue message.

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../theme/cue_text_styles.dart' show CueChartPalette;

class CueHoldWhisper extends StatelessWidget {
  final String text;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final VoidCallback? onMicTap;
  const CueHoldWhisper({
    super.key,
    required this.text,
    this.onTap,
    this.onLongPress,
    this.onMicTap,
  });

  static const Color _amber = Color(0xFFF5C778);

  @override
  Widget build(BuildContext context) {
    final p = CueChartPalette.of(context);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 360),
          padding: const EdgeInsets.fromLTRB(10, 8, 16, 8),
          decoration: BoxDecoration(
            color: p.holdSurface,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: p.holdBorder, width: 0.5),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: _amber.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: SvgPicture.asset(
                  'assets/brand/cue_mark.svg',
                  width: 14,
                  height: 14,
                  colorFilter:
                      const ColorFilter.mode(_amber, BlendMode.srcIn),
                ),
              ),
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.playfairDisplay(
                    fontStyle: FontStyle.italic,
                    fontWeight: FontWeight.w500,
                    fontSize: 12,
                    color: _amber,
                    height: 1.2,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Container(width: 0.5, height: 12, color: p.holdBorder),
              const SizedBox(width: 10),
              GestureDetector(
                onTap: onMicTap,
                behavior: HitTestBehavior.opaque,
                child: const Icon(
                  Icons.mic_none_rounded,
                  size: 13,
                  color: _amber,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
