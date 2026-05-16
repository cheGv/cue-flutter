// lib/widgets/clients_roster_row.dart
//
// A single client row on the /clients screen. Flat row with a hairline
// divider (NOT a card): name + age/diagnosis on the top line, one
// computed clinical-state line below, status pill + last-interaction
// date on the right. No accent stripe, no icons, no internal labels.

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/clients_roster_service.dart';
import '../theme/cue_text_styles.dart';

class ClientsRosterRow extends StatelessWidget {
  final ClientRosterEntry entry;
  final bool isMobile;

  /// The last row in the list draws no bottom border.
  final bool isLast;
  final VoidCallback onTap;

  const ClientsRosterRow({
    super.key,
    required this.entry,
    required this.isMobile,
    required this.isLast,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final text = CueTextStyles.of(context, isMobile: isMobile);
    final palette = CueClientsPalette.of(context);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 4),
          decoration: BoxDecoration(
            border: isLast
                ? null
                : Border(
                    bottom: BorderSide(color: palette.rowDivider, width: 0.5),
                  ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(child: _left(text, palette)),
              const SizedBox(width: 16),
              SizedBox(width: 100, child: _right(text, palette)),
            ],
          ),
        ),
      ),
    );
  }

  // ── Left: name + meta, then the computed clinical-state line ─────────
  Widget _left(CueTextStyles text, CueClientsPalette palette) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Flexible(
              child: Text(
                entry.displayName,
                overflow: TextOverflow.ellipsis,
                style: text.name,
              ),
            ),
            if (entry.metaLine.isNotEmpty) ...[
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  entry.metaLine,
                  overflow: TextOverflow.ellipsis,
                  style: text.meta,
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 4),
        _clinicalState(text, palette),
      ],
    );
  }

  /// Computed — not stored. Generated from session count, enrollment
  /// age, active-step count, domain, and recency.
  Widget _clinicalState(CueTextStyles text, CueClientsPalette palette) {
    final prose = text.prose;

    if (entry.isNew) {
      final line = entry.daysSinceEnrolled < 7
          ? 'Just enrolled · baseline pending'
          : 'Enrolled ${entry.daysSinceEnrolled}d ago · baseline pending';
      return Text(line, style: prose, overflow: TextOverflow.ellipsis);
    }

    final steps = entry.activeGoalsCount;
    final domain = entry.domainWord;
    final domainStyle =
        prose.copyWith(color: palette.domain, fontWeight: FontWeight.w500);

    return Text.rich(
      TextSpan(
        style: prose,
        children: [
          TextSpan(text: '$steps active steps'),
          if (domain != null) ...[
            const TextSpan(text: ' in '),
            TextSpan(text: domain, style: domainStyle),
          ],
          TextSpan(text: ' · last seen ${entry.recencyLong}'),
        ],
      ),
      overflow: TextOverflow.ellipsis,
    );
  }

  // ── Right: status pill above the last-interaction date ──────────────
  Widget _right(CueTextStyles text, CueClientsPalette palette) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        _statusPill(palette),
        const SizedBox(height: 6),
        Text(
          entry.recencyShort,
          style: GoogleFonts.dmSans(
            fontSize: 11,
            fontWeight: FontWeight.w400,
            color: const Color(0xFF888780),
          ),
        ),
      ],
    );
  }

  Widget _statusPill(CueClientsPalette palette) {
    final discharged = entry.isDischarged;
    final label = discharged ? 'Discharged' : 'Active';
    final borderColor =
        discharged ? palette.dischargedPillBorder : palette.activePillBorder;
    final textColor =
        discharged ? palette.dischargedPillText : palette.activePillText;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 9),
      decoration: BoxDecoration(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor, width: 0.5),
      ),
      child: Text(
        label,
        style: GoogleFonts.dmSans(
          fontSize: 11,
          fontWeight: FontWeight.w400,
          color: textColor,
        ),
      ),
    );
  }
}
