// lib/widgets/clients_roster_empty_state.dart
//
// Two empty-state variants for /clients. The global-empty state (zero
// clients) renders only the hero line, the idle cuttlefish, an
// invitation, and the new-client button — no search, tabs, action
// line, or list. The filter-empty state (zero matches in the current
// filter) is just quiet centered copy.

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/cue_text_styles.dart';
import 'cue_cuttlefish.dart';

class ClientsRosterEmptyState extends StatelessWidget {
  final bool isMobile;
  final VoidCallback onNewClient;

  const ClientsRosterEmptyState({
    super.key,
    required this.isMobile,
    required this.onNewClient,
  });

  @override
  Widget build(BuildContext context) {
    final text = CueTextStyles.of(context, isMobile: isMobile);
    final palette = CueClientsPalette.of(context);

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Everyone in your care.', style: text.hero),
          const SizedBox(height: 32),
          const Opacity(
            opacity: 0.7,
            child: SizedBox(
              width: 32,
              height: 32,
              child: CueCuttlefish(size: 32, state: CueState.idle),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Add your first client to begin.',
            style: GoogleFonts.dmSans(
              fontSize: 14,
              color: palette.textSecondary,
            ),
          ),
          const SizedBox(height: 24),
          _newClientButton(palette),
        ],
      ),
    );
  }

  Widget _newClientButton(CueClientsPalette palette) {
    final fg = palette.isDark
        ? const Color(0xFF181715)
        : const Color(0xFFFAF7F0);
    return Semantics(
      button: true,
      label: 'New client',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onNewClient,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            decoration: BoxDecoration(
              color: palette.amber,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '+ New client',
              style: GoogleFonts.dmSans(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: fg,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Filter-empty variant — no cuttlefish theatrics, just quiet copy for
/// when a filter or search yields nothing.
class ClientsRosterFilterEmptyState extends StatelessWidget {
  final String message;
  const ClientsRosterFilterEmptyState({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    final palette = CueClientsPalette.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
      child: Center(
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: GoogleFonts.dmSans(
            fontSize: 14,
            color: palette.textTertiary,
          ),
        ),
      ),
    );
  }
}
