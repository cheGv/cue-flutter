// lib/widgets/chart/chart_action_bar.dart
//
// Phase 4.1.0 — floating action bar pinned to the chart viewport. Pill
// shape, two visible actions + overflow.
//
// Actions:
//   + Session  →  open new session capture
//   Reports    →  reports module (Phase 1.5 placeholder)
//   ⋯           →  Edit client / Archive / Share / Export / Delete
//
// Build with Cue does NOT appear here — it lives only inside the Next
// Session meta card on the masthead.

import 'package:flutter/material.dart';

import '../../theme/cue_color_scheme.dart';
import '../../theme/cue_text_styles.dart';

class ChartActionBar extends StatelessWidget {
  final VoidCallback? onAddSession;
  final VoidCallback? onReports;
  final VoidCallback? onEditClient;
  final VoidCallback? onArchive;
  final VoidCallback? onShareWithCaregiver;
  final VoidCallback? onExportPdf;
  final VoidCallback? onDelete;

  const ChartActionBar({
    super.key,
    this.onAddSession,
    this.onReports,
    this.onEditClient,
    this.onArchive,
    this.onShareWithCaregiver,
    this.onExportPdf,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final t = CueChartTextStyles.of(context, isMobile: false);
    final p = CueChartPalette.of(context);
    final cue = CueColorsResolved.of(context);

    return Material(
      color: Colors.transparent,
      child: Container(
        decoration: BoxDecoration(
          color: p.actionBarSurface,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: p.actionBarBorder, width: 0.5),
          boxShadow: [
            BoxShadow(
              color: p.actionBarShadow,
              offset: const Offset(0, 6),
              blurRadius: 32,
            ),
          ],
        ),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _ActionItem(
              icon: Icons.add_rounded,
              label: 'Session',
              color: const Color(0xFF97C459),
              labelStyle: t.actionBarLabel.copyWith(
                color: const Color(0xFF97C459),
              ),
              onTap: onAddSession,
            ),
            _Divider(color: p.actionBarDivider),
            _ActionItem(
              icon: Icons.description_outlined,
              label: 'Reports',
              color: cue.textPrimary,
              labelStyle: t.actionBarLabel,
              onTap: onReports ?? () => _reportsComingSoon(context),
            ),
            _Divider(color: p.actionBarDivider),
            _OverflowMenu(
              onEditClient: onEditClient,
              onArchive: onArchive,
              onShareWithCaregiver: onShareWithCaregiver,
              onExportPdf: onExportPdf,
              onDelete: onDelete,
            ),
          ],
        ),
      ),
    );
  }

  static void _reportsComingSoon(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) {
        final cue = CueColorsResolved.of(ctx);
        return AlertDialog(
          backgroundColor: cue.bgCard,
          title: const Text('Reports'),
          content: const Text('Reports — coming in Phase 1.5.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }
}

class _ActionItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final TextStyle labelStyle;
  final VoidCallback? onTap;

  const _ActionItem({
    required this.icon,
    required this.label,
    required this.color,
    required this.labelStyle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: color),
            const SizedBox(width: 6),
            Text(label, style: labelStyle),
          ],
        ),
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  final Color color;
  const _Divider({required this.color});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Container(width: 0.5, height: 14, color: color),
    );
  }
}

class _OverflowMenu extends StatelessWidget {
  final VoidCallback? onEditClient;
  final VoidCallback? onArchive;
  final VoidCallback? onShareWithCaregiver;
  final VoidCallback? onExportPdf;
  final VoidCallback? onDelete;

  const _OverflowMenu({
    this.onEditClient,
    this.onArchive,
    this.onShareWithCaregiver,
    this.onExportPdf,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final cue = CueColorsResolved.of(context);
    return PopupMenuButton<String>(
      tooltip: 'More',
      icon: Icon(Icons.more_horiz_rounded, size: 16, color: cue.textSecondary),
      color: cue.bgCard,
      onSelected: (key) {
        switch (key) {
          case 'edit':
            onEditClient?.call();
            break;
          case 'archive':
            onArchive?.call();
            break;
          case 'share':
            _comingSoon(context, 'Share with caregiver — coming in Phase 1.5.');
            break;
          case 'export':
            _comingSoon(context, 'Export PDF — coming in Phase 1.5.');
            break;
          case 'delete':
            onDelete?.call();
            break;
        }
      },
      itemBuilder: (ctx) => [
        const PopupMenuItem<String>(value: 'edit', child: Text('Edit client')),
        const PopupMenuItem<String>(value: 'archive', child: Text('Archive client')),
        const PopupMenuItem<String>(
          value: 'share',
          child: Text('Share with caregiver'),
        ),
        const PopupMenuItem<String>(
          value: 'export',
          child: Text('Export PDF'),
        ),
        const PopupMenuDivider(),
        PopupMenuItem<String>(
          value: 'delete',
          child: Text(
            'Delete client',
            style: TextStyle(color: cue.red),
          ),
        ),
      ],
    );
  }

  static void _comingSoon(BuildContext context, String msg) {
    showDialog<void>(
      context: context,
      builder: (ctx) {
        final cue = CueColorsResolved.of(ctx);
        return AlertDialog(
          backgroundColor: cue.bgCard,
          content: Text(msg),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }
}
