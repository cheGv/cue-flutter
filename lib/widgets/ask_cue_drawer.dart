// lib/widgets/ask_cue_drawer.dart
//
// Phase 5.1+5.2 — narrow-viewport wrapper for AskCuePanel. Below the
// 1024px threshold (kDesktopBreak), Profile collapses to single
// column and the Ask Cue panel becomes a right-side drawer accessed
// via a header button.

import 'package:flutter/material.dart';

import 'ask_cue_panel.dart';

/// Opens an AskCuePanel as a right-side drawer. Returns when the
/// drawer is dismissed. Caller passes the same client context the
/// panel needs.
Future<void> showAskCueDrawer({
  required BuildContext context,
  required String clientId,
  required String clientName,
}) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Close Ask Cue',
    barrierColor: Colors.black.withAlpha(64),
    transitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (ctx, anim, _) {
      final size = MediaQuery.of(ctx).size;
      final width = size.width < 540 ? size.width : 480.0;
      return Align(
        alignment: Alignment.centerRight,
        child: SafeArea(
          child: SizedBox(
            width: width,
            height: size.height,
            child: AskCuePanel(
              clientId:   clientId,
              clientName: clientName,
            ),
          ),
        ),
      );
    },
    transitionBuilder: (_, anim, _, child) {
      final slide = Tween<Offset>(
        begin: const Offset(1, 0),
        end:   Offset.zero,
      ).animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic));
      return SlideTransition(position: slide, child: child);
    },
  );
}
