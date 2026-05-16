// lib/widgets/clients_roster_search_bar.dart
//
// /clients search row: full-width search input (with a ⌘K hint badge)
// and a small ghost-square "+" button for the new-client flow. The
// cmd-K hint is a soft affordance — no keyboard listener is wired yet.

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/cue_text_styles.dart';

class ClientsRosterSearchBar extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onNewClient;

  const ClientsRosterSearchBar({
    super.key,
    required this.controller,
    required this.onNewClient,
  });

  @override
  Widget build(BuildContext context) {
    final palette = CueClientsPalette.of(context);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(child: _searchInput(palette)),
        const SizedBox(width: 10),
        _newClientButton(palette),
      ],
    );
  }

  Widget _searchInput(CueClientsPalette palette) {
    return Container(
      height: 40,
      decoration: BoxDecoration(
        color: palette.searchBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: palette.controlBorder, width: 0.5),
      ),
      padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 14),
      child: Row(
        children: [
          Icon(Icons.search_rounded, size: 18, color: palette.textTertiary),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: controller,
              style: GoogleFonts.dmSans(
                fontSize: 14,
                color: palette.textPrimary,
              ),
              decoration: InputDecoration(
                isCollapsed: true,
                contentPadding: EdgeInsets.zero,
                border: InputBorder.none,
                hintText: 'Search by name, diagnosis, concern',
                hintStyle: GoogleFonts.dmSans(
                  fontSize: 14,
                  color: palette.textTertiary,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          _cmdKHint(palette),
        ],
      ),
    );
  }

  Widget _cmdKHint(CueClientsPalette palette) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: palette.controlBorder, width: 0.5),
      ),
      child: Text(
        '⌘K',
        style: GoogleFonts.dmSans(
          fontSize: 11,
          color: palette.textTertiary,
        ),
      ),
    );
  }

  Widget _newClientButton(CueClientsPalette palette) {
    return Semantics(
      button: true,
      label: 'New client',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onNewClient,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: palette.controlBorder, width: 0.5),
            ),
            alignment: Alignment.center,
            child: Text(
              '+',
              style: GoogleFonts.dmSans(
                fontSize: 18,
                color: palette.ghostPlus,
                height: 1.0,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
