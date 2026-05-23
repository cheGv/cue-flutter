import 'package:flutter/material.dart';

import '../../theme/cue_color_scheme.dart';
import '../../theme/cue_text_styles.dart';

// Shared chrome for the Phase B-revised cards-on-canvas chart (locked
// 2026-05-23). CueChartCard = the `.card` primitive; CueChartCardHead = the
// `.card-head` strip; CueChartButton = `.btn` (primary / normal / ghost,
// + small / icon-only, with hover). All trace to
// docs/decisions/phase-b-chart-visual.html.

/// The `.card` primitive: white-on-canvas surface, 1px border, 10px radius,
/// soft shadow, clipped. Pass [head] for a card-head + body layout; otherwise
/// the whole card uses [padding].
class CueChartCard extends StatelessWidget {
  final Widget child;
  final Widget? head;
  final EdgeInsetsGeometry padding;
  final Color? background;
  final List<BoxShadow>? shadow;
  final Border? border;

  const CueChartCard({
    super.key,
    required this.child,
    this.head,
    this.padding = const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
    this.background,
    this.shadow,
    this.border,
  });

  @override
  Widget build(BuildContext context) {
    final t = CueChartTokens.of(context);
    final radius = BorderRadius.circular(10);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: background ?? t.bgCard,
        borderRadius: radius,
        border: border ?? Border.all(color: t.borderCard),
        boxShadow: shadow ?? t.shadowCard,
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: head == null
            ? Padding(padding: padding, child: child)
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [head!, Padding(padding: padding, child: child)],
              ),
      ),
    );
  }
}

/// The `.card-head` strip: bg-card-head ground, bottom hairline, uppercase
/// tracked section label (+ subordinate count) on the left, action buttons
/// on the right.
class CueChartCardHead extends StatelessWidget {
  final String label;

  /// Subordinate count, e.g. "· LTG 1" or "· 3 active" (leading dot included
  /// by the caller). Rendered in the muted count register.
  final String? count;
  final List<Widget> actions;

  const CueChartCardHead({
    super.key,
    required this.label,
    this.count,
    this.actions = const [],
  });

  @override
  Widget build(BuildContext context) {
    final t = CueChartTokens.of(context);
    final ty = CueChartType.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      decoration: BoxDecoration(
        color: t.bgCardHead,
        border: Border(bottom: BorderSide(color: t.borderCard)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text.rich(
              TextSpan(children: [
                TextSpan(text: label.toUpperCase(), style: ty.sectionLabel),
                if (count != null && count!.trim().isNotEmpty)
                  TextSpan(
                    text: ' ${count!.toUpperCase()}',
                    style: ty.sectionCount,
                  ),
              ]),
            ),
          ),
          if (actions.isNotEmpty) ...[
            const SizedBox(width: 12),
            Row(mainAxisSize: MainAxisSize.min, children: _spaced(actions)),
          ],
        ],
      ),
    );
  }

  List<Widget> _spaced(List<Widget> items) {
    final out = <Widget>[];
    for (var i = 0; i < items.length; i++) {
      if (i > 0) out.add(const SizedBox(width: 8));
      out.add(items[i]);
    }
    return out;
  }
}

enum CueChartButtonStyle { primary, normal, ghost }

/// The `.btn` primitive with hover. `iconOnly` renders a 28×28 square (the
/// evidence open-source affordance). `kbdHint` renders a trailing ⌘K pill.
class CueChartButton extends StatefulWidget {
  final String? label;
  final IconData? icon;
  final VoidCallback? onTap;
  final CueChartButtonStyle style;
  final bool small;
  final bool iconOnly;
  final bool enabled;
  final String? kbdHint;
  final String? tooltip;

  const CueChartButton({
    super.key,
    this.label,
    this.icon,
    this.onTap,
    this.style = CueChartButtonStyle.normal,
    this.small = false,
    this.iconOnly = false,
    this.enabled = true,
    this.kbdHint,
    this.tooltip,
  });

  @override
  State<CueChartButton> createState() => _CueChartButtonState();
}

class _CueChartButtonState extends State<CueChartButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final t = CueChartTokens.of(context);
    final ty = CueChartType.of(context);

    final Color bg;
    final Color fg;
    final Color borderColor;
    switch (widget.style) {
      case CueChartButtonStyle.primary:
        bg = _hover ? t.btnPrimaryHover : t.btnPrimaryBg;
        fg = t.btnPrimaryText;
        borderColor = bg;
      case CueChartButtonStyle.ghost:
        bg = _hover ? t.bgCardHead : Colors.transparent;
        fg = _hover ? t.textPrimary : t.textSecondary;
        borderColor = Colors.transparent;
      case CueChartButtonStyle.normal:
        bg = _hover ? t.bgCardHead : t.bgCard;
        fg = widget.iconOnly
            ? (_hover ? t.textPrimary : t.textTertiary)
            : t.textBody;
        borderColor = t.borderCard;
    }

    final EdgeInsets pad = widget.iconOnly
        ? EdgeInsets.zero
        : (widget.small
            ? const EdgeInsets.symmetric(horizontal: 10, vertical: 6)
            : const EdgeInsets.symmetric(horizontal: 14, vertical: 9));

    final Widget content;
    if (widget.iconOnly) {
      content = SizedBox(
        width: 28,
        height: 28,
        child: Icon(widget.icon, size: 15, color: fg),
      );
    } else {
      content = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.icon != null) ...[
            Icon(widget.icon, size: 14, color: fg),
            const SizedBox(width: 6),
          ],
          if (widget.label != null)
            Text(widget.label!,
                style: widget.small ? ty.buttonSmall(fg) : ty.button(fg)),
          if (widget.kbdHint != null) ...[
            const SizedBox(width: 8),
            _Kbd(text: widget.kbdHint!, isDark: t.isDark),
          ],
        ],
      );
    }

    Widget btn = AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      padding: pad,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: borderColor),
      ),
      child: content,
    );

    if (!widget.enabled) return Opacity(opacity: 0.4, child: btn);

    btn = MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(onTap: widget.onTap, child: btn),
    );
    if (widget.tooltip != null) {
      btn = Tooltip(message: widget.tooltip!, child: btn);
    }
    return btn;
  }
}

class _Kbd extends StatelessWidget {
  final String text;
  final bool isDark;
  const _Kbd({required this.text, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final ty = CueChartType.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: isDark ? const Color(0x33000000) : const Color(0x1FFFFFFF),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(text, style: ty.kbd),
    );
  }
}
