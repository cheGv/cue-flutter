import 'package:flutter/material.dart';

import '../../models/short_term_goal.dart';
import '../../theme/cue_color_scheme.dart';
import '../../theme/cue_text_styles.dart';

/// Compact STG rows beneath the focused card — one small card per STG. Five
/// columns: mono number / domain pill / body / "N cited" / chevron. Hover
/// lightens; tap refocuses (wired by the screen).
class ChartStgCompact extends StatelessWidget {
  final List<ShortTermGoal> stgs;
  final Map<String, int> evidenceCountByStg;

  /// STG id → "1.A" display number (from stg_numbering).
  final Map<String, String> stgNumbers;

  final void Function(String stgId)? onTapStg;

  const ChartStgCompact({
    super.key,
    required this.stgs,
    required this.evidenceCountByStg,
    this.stgNumbers = const {},
    this.onTapStg,
  });

  @override
  Widget build(BuildContext context) {
    if (stgs.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 12),
        for (final stg in stgs)
          _CompactCard(
            stg: stg,
            number: stgNumbers[stg.id] ?? 'STG ${stg.sequenceNum ?? '—'}',
            evidenceCount: evidenceCountByStg[stg.id] ?? 0,
            onTap: onTapStg == null ? null : () => onTapStg!(stg.id),
          ),
      ],
    );
  }
}

class _CompactCard extends StatefulWidget {
  final ShortTermGoal stg;
  final String number;
  final int evidenceCount;
  final VoidCallback? onTap;
  const _CompactCard({
    required this.stg,
    required this.number,
    required this.evidenceCount,
    this.onTap,
  });

  @override
  State<_CompactCard> createState() => _CompactCardState();
}

class _CompactCardState extends State<_CompactCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final t = CueChartTokens.of(context);
    final ty = CueChartType.of(context);
    final stg = widget.stg;
    final body = stg.specific.trim().isNotEmpty
        ? stg.specific.trim()
        : (stg.targetBehavior ?? stg.measurable);
    // Domain pill: prefer the raw string when the enum is `unknown` (so
    // "RVT"-like clinical tokens surface), else the canonical DB identifier.
    final domain = stg.domainDisplay;
    final n = widget.evidenceCount;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          decoration: BoxDecoration(
            color: _hover ? t.bgCardHead : t.bgCard,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: t.borderCard),
            boxShadow: t.shadowCard,
          ),
          child: Row(
            children: [
              SizedBox(width: 56, child: Text(widget.number, style: ty.compactNum)),
              const SizedBox(width: 14),
              SizedBox(
                width: 80,
                child: domain == null
                    ? const SizedBox.shrink()
                    : Align(
                        alignment: Alignment.centerLeft,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: t.bgInset,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            domain.toUpperCase(),
                            style: ty.compactDomain,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  body,
                  style: ty.compactBody,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 14),
              SizedBox(
                width: 64,
                child: Text(
                  '$n cited',
                  style: ty.compactCites,
                  textAlign: TextAlign.right,
                ),
              ),
              const SizedBox(width: 10),
              Icon(Icons.chevron_right, size: 18, color: t.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}
