// lib/widgets/clients_roster_empty_state.dart
//
// Phase 4.0.9-step-B-roster-surface-2 — two empty-state variants. The
// global-empty state (zero clients) gets the 96px softWave cuttlefish
// + invitation copy + CTA. The filter-empty state (zero matches in
// the current filter) is just italic copy in tertiary ink.

import 'package:flutter/material.dart';

import '../theme/cue_phase4_tokens.dart';
import '../theme/cue_type_v3.dart';
import 'cue_cuttlefish.dart';

class ClientsRosterEmptyState extends StatelessWidget {
  final VoidCallback onNewClient;
  const ClientsRosterEmptyState({super.key, required this.onNewClient});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width:  96,
            height: 96,
            child: CueCuttlefish(size: 96, state: CueState.softWave),
          ),
          const SizedBox(height: 24),
          Text(
            'Your case file is empty.',
            style: CueTypeV3.h1(color: kCueInk).copyWith(
              fontStyle: FontStyle.italic,
              fontSize: 28,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Add your first client to begin.',
            style: CueTypeV3.body(color: kCueInkSecondary)
                .copyWith(fontSize: 14),
          ),
          const SizedBox(height: 24),
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
                padding: const EdgeInsets.symmetric(horizontal: 18),
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
      ),
    );
  }
}

/// Filter-empty variant — no cuttlefish theatrics.
class ClientsRosterFilterEmptyState extends StatelessWidget {
  final String message;
  const ClientsRosterFilterEmptyState({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
      child: Center(
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: CueTypeV3.editorialItalic(color: kCueInkTertiary)
              .copyWith(fontSize: 14),
        ),
      ),
    );
  }
}
