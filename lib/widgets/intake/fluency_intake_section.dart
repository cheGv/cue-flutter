// lib/widgets/intake/fluency_intake_section.dart
//
// Phase 4.0.7.24a-fix2 — domain-router-facing wrapper for the fluency
// intake. The actual capture surface (onset, family history,
// variability, awareness, secondary behaviours, previous intervention)
// already lives in widgets/case_history_fluency_section.dart, where it
// was extracted in Phase 4.0.3. This wrapper exists so the
// add_client_screen router can resolve a single uniform widget per
// clinical_area code; future domain widgets (voice, ssd, dysphagia,
// adult-language-cognitive, etc.) will land alongside this one in the
// intake/ folder under the same signature.
//
// Same payload contract as CaseHistoryFluencySection: the parent caches
// the latest emitted payload and writes it into
// case_history_entries.payload.domain_payload at save time.

import 'package:flutter/material.dart';
import '../case_history_fluency_section.dart';

class FluencyIntakeSection extends StatelessWidget {
  /// Seed payload for the fluency capture. Empty map for a fresh case.
  /// Accepted as the case_history_entries.payload.domain_payload value
  /// when re-loading an existing client; pass {} for a new client.
  final Map<String, dynamic>? initialPayload;

  /// Fired on every change with the current fluency-domain payload.
  /// The parent screen merges this into the case_history_entries row
  /// at save time as `payload.domain_payload`.
  final ValueChanged<Map<String, dynamic>> onChanged;

  const FluencyIntakeSection({
    super.key,
    required this.onChanged,
    this.initialPayload,
  });

  @override
  Widget build(BuildContext context) {
    return CaseHistoryFluencySection(
      initialPayload: initialPayload ?? const {},
      onChanged: onChanged,
    );
  }
}
