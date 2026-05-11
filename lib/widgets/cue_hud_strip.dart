// lib/widgets/cue_hud_strip.dart
//
// Phase 5.3 Round A.2 — persistent Cue HUD strip at the top of a
// workspace surface. Cue's ambient presence: a green pulse, a
// state label, a detail line, a fresh-signal pill when relevant,
// quick-action pills, and a ⌘K hint.
//
// Click anywhere on the strip → onTap (caller opens CuePopup with
// scope inherited from the current screen). The strip itself owns
// no popup state; that lives in the screen that mounts it.

import 'package:flutter/material.dart';

import '../theme/cue_color_scheme.dart';

/// Cue's mode shown in the HUD strip label.
enum CueHudMode {
  ready,         // idle
  thinking,      // working / streaming
  readingChart,  // ingesting context
  drafting,      // composing a draft
  offline,       // network down
}

String _modeLabel(CueHudMode m) {
  switch (m) {
    case CueHudMode.ready:        return 'ready';
    case CueHudMode.thinking:     return 'thinking';
    case CueHudMode.readingChart: return 'reading chart';
    case CueHudMode.drafting:     return 'drafting';
    case CueHudMode.offline:      return 'offline';
  }
}

class CueHudStrip extends StatefulWidget {
  /// Current Cue state shown in the mono label ("Cue · ready", etc.).
  final CueHudMode mode;

  /// Optional detail line — e.g. "Reading Aarif — 7 active goals,
  /// 0 sessions yet" or "Reading Aarif — 18 sessions, last seen 12d".
  final String? detail;

  /// When true, an amber "FRESH SIGNAL" pill renders to the right of
  /// the detail line. Caller computes the signal (time gap >7d, new
  /// session, drift, parent comm).
  final bool hasFreshSignal;

  /// Optional list of quick-action pill labels (1–2). Each pill is a
  /// silent visual affordance — clicking it routes to [onTap] (same
  /// as clicking anywhere else on the strip). Intent dispatch lands
  /// in a later round.
  final List<String> quickActions;

  /// Fires when the strip is clicked anywhere (including the pills
  /// and ⌘K hint area) — caller opens the popup.
  final VoidCallback onTap;

  const CueHudStrip({
    super.key,
    this.mode = CueHudMode.ready,
    this.detail,
    this.hasFreshSignal = false,
    this.quickActions = const [],
    required this.onTap,
  });

  @override
  State<CueHudStrip> createState() => _CueHudStripState();
}

class _CueHudStripState extends State<CueHudStrip>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    // Reduced-motion gate is read at build time; animation is started
    // unconditionally and the FadeTransition opacity short-circuits to
    // 1.0 when disableAnimations is set.
    _pulse.repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cue           = CueColorsResolved.of(context);
    final reduceMotion  = MediaQuery.of(context).disableAnimations;
    final pulseOpacity  = reduceMotion
        ? const AlwaysStoppedAnimation<double>(1.0)
        : Tween<double>(begin: 0.4, end: 1.0).animate(_pulse);

    final pulseColor = widget.mode == CueHudMode.offline ? cue.red : cue.olive;

    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: widget.onTap,
        hoverColor: cue.bgCardHover.withValues(alpha: 0.5),
        child: Container(
          height: 44,
          decoration: BoxDecoration(
            color: cue.bgCard,
            border: Border(
              bottom: BorderSide(color: cue.border, width: 0.5),
            ),
            // Phase 5.3 edge polish — hairline highlight at the top edge
            // suggests light from above (Logic Pro register). Light mode
            // skips this since the warm-paper register doesn't read with
            // a white-tint top edge.
            gradient: cue.isDark
                ? LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.center,
                    colors: [
                      Colors.white.withValues(alpha: 0.025),
                      cue.bgCard,
                    ],
                    stops: const [0.0, 0.08],
                  )
                : null,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          child: Row(
            children: [
              // ── Pulse dot ─────────────────────────────────────────────
              FadeTransition(
                opacity: pulseOpacity,
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: pulseColor,
                    shape: BoxShape.circle,
                    // Ring-shadowed accent per Phase 5.3 brief.
                    boxShadow: cue.isDark
                        ? [
                            BoxShadow(
                              color: pulseColor.withValues(alpha: 0.2),
                              spreadRadius: 0.5,
                            ),
                          ]
                        : null,
                  ),
                ),
              ),
              const SizedBox(width: 10),

              // ── Mode label — mono uppercase tracked ───────────────────
              Text(
                'CUE · ${_modeLabel(widget.mode).toUpperCase()}',
                style: TextStyle(
                  fontFamily: 'JetBrains Mono',
                  fontFamilyFallback: const ['monospace'],
                  fontSize: 9.5,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 9.5 * 0.18,
                  color: cue.textMuted,
                ),
              ),

              const SizedBox(width: 16),

              // ── Detail line — Inter 12 ────────────────────────────────
              if (widget.detail != null)
                Expanded(
                  child: Text(
                    widget.detail!,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontFamilyFallback: const ['system-ui', 'sans-serif'],
                      fontSize: 12,
                      letterSpacing: -0.06,
                      color: cue.textBody,
                    ),
                  ),
                )
              else
                const Spacer(),

              // ── Fresh signal pill (amber) ─────────────────────────────
              if (widget.hasFreshSignal) ...[
                const SizedBox(width: 12),
                _FreshSignalPill(cue: cue),
              ],

              // ── Quick-action pills (1–2) ──────────────────────────────
              for (final label in widget.quickActions.take(2)) ...[
                const SizedBox(width: 8),
                _QuickActionPill(label: label, cue: cue),
              ],

              const SizedBox(width: 12),

              // ── ⌘K hint ───────────────────────────────────────────────
              _CmdKHint(cue: cue),
            ],
          ),
        ),
      ),
    );
  }
}

class _FreshSignalPill extends StatelessWidget {
  final CueColorsResolved cue;
  const _FreshSignalPill({required this.cue});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: cue.amber.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: cue.amber.withValues(alpha: 0.45),
          width: 0.5,
        ),
      ),
      child: Text(
        '1 FRESH SIGNAL',
        style: TextStyle(
          fontFamily: 'JetBrains Mono',
          fontFamilyFallback: const ['monospace'],
          fontSize: 9,
          fontWeight: FontWeight.w700,
          letterSpacing: 9 * 0.16,
          color: cue.amber,
        ),
      ),
    );
  }
}

class _QuickActionPill extends StatelessWidget {
  final String label;
  final CueColorsResolved cue;
  const _QuickActionPill({required this.label, required this.cue});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: cue.border, width: 0.5),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontFamily: 'Inter',
          fontFamilyFallback: const ['system-ui', 'sans-serif'],
          fontSize: 11.5,
          fontWeight: FontWeight.w500,
          color: cue.textBody,
        ),
      ),
    );
  }
}

class _CmdKHint extends StatelessWidget {
  final CueColorsResolved cue;
  const _CmdKHint({required this.cue});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: cue.bgInput,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: cue.border, width: 0.5),
      ),
      child: Text(
        '⌘K',
        style: TextStyle(
          fontFamily: 'JetBrains Mono',
          fontFamilyFallback: const ['monospace'],
          fontSize: 10,
          fontWeight: FontWeight.w500,
          color: cue.textMuted,
        ),
      ),
    );
  }
}
