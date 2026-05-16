// lib/screens/settings/settings_card.dart
//
// Phase 5 Settings — collapsible card shell.
//
// Header always visible; body animates open/closed via AnimatedSize +
// AnimatedCrossFade per CLAUDE.md ("AnimatedSize + AnimatedCrossFade for
// collapse/expand. No BackdropFilter — kills Flutter Web perf.").

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../theme/cue_color_scheme.dart';

class SettingsCard extends StatefulWidget {
  final String title;
  final String? subtitle;
  final Widget? body;
  final bool initiallyExpanded;

  const SettingsCard({
    super.key,
    required this.title,
    this.subtitle,
    this.body,
    this.initiallyExpanded = false,
  });

  @override
  State<SettingsCard> createState() => _SettingsCardState();
}

class _SettingsCardState extends State<SettingsCard> {
  late bool _expanded;

  @override
  void initState() {
    super.initState();
    _expanded = widget.initiallyExpanded;
  }

  @override
  Widget build(BuildContext context) {
    final cue = CueColorsResolved.of(context);
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: cue.bgCard,
        border: Border.all(color: cue.border, width: 0.5),
        borderRadius: BorderRadius.circular(8),
      ),
      clipBehavior: Clip.antiAlias,
      child: AnimatedSize(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        alignment: Alignment.topCenter,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InkWell(
              onTap: () => setState(() => _expanded = !_expanded),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 14, 14),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.title,
                            style: GoogleFonts.syne(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: cue.textPrimary,
                              letterSpacing: 0.1,
                            ),
                          ),
                          if (widget.subtitle != null) ...[
                            const SizedBox(height: 4),
                            Text(
                              widget.subtitle!,
                              style: GoogleFonts.dmSans(
                                fontSize: 12.5,
                                height: 1.5,
                                color: cue.textMuted,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    AnimatedRotation(
                      turns: _expanded ? 0.5 : 0,
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOutCubic,
                      child: Icon(
                        Icons.expand_more_rounded,
                        size: 20,
                        color: cue.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            AnimatedCrossFade(
              firstChild: const SizedBox(width: double.infinity, height: 0),
              secondChild: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
                child: widget.body ?? _placeholderBody(cue),
              ),
              crossFadeState: _expanded
                  ? CrossFadeState.showSecond
                  : CrossFadeState.showFirst,
              duration: const Duration(milliseconds: 220),
              sizeCurve: Curves.easeOutCubic,
              alignment: Alignment.topCenter,
            ),
          ],
        ),
      ),
    );
  }

  Widget _placeholderBody(CueColorsResolved cue) {
    return Text(
      'Coming soon.',
      style: GoogleFonts.dmSans(
        fontSize: 13,
        height: 1.55,
        color: cue.textMuted,
        fontStyle: FontStyle.italic,
      ),
    );
  }
}
