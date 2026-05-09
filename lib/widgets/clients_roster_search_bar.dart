// lib/widgets/clients_roster_search_bar.dart
//
// Phase 4.0.9-step-B-roster-surface-2 — search input + ⌘K hint +
// "New client" CTA. The cmd-K hint is a soft affordance; no actual
// keyboard listener is wired in v1 (deferred until a global shortcut
// system exists).

import 'package:flutter/material.dart';

import '../theme/cue_phase4_tokens.dart';
import '../theme/cue_type_v3.dart';

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
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Container(
            height: 44,
            decoration: BoxDecoration(
              color: kCueSurfaceWhite,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: kCueBorder, width: 0.5),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                const Icon(
                  Icons.search_rounded,
                  size: 18,
                  color: kCueInkTertiary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: controller,
                    style: CueTypeV3.body(color: kCueInk)
                        .copyWith(fontSize: 14),
                    decoration: InputDecoration(
                      isCollapsed: true,
                      contentPadding: EdgeInsets.zero,
                      border: InputBorder.none,
                      hintText: 'Search by name, diagnosis, concern',
                      hintStyle:
                          CueTypeV3.body(color: kCueInkTertiary)
                              .copyWith(fontSize: 14),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: kCuePaper,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: kCueBorder, width: 0.5),
                  ),
                  child: Text(
                    '⌘ K',
                    style: CueTypeV3.dataMono(color: kCueInkTertiary)
                        .copyWith(fontSize: 11),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 12),
        SizedBox(
          height: 44,
          child: ElevatedButton.icon(
            onPressed: onNewClient,
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('New client'),
            style: ElevatedButton.styleFrom(
              backgroundColor: kCueInk,
              foregroundColor: kCueSurfaceWhite,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              textStyle: const TextStyle(
                fontFamily: 'Inter',
                fontSize: 14,
                fontWeight: FontWeight.w500,
                letterSpacing: -0.07,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
