// lib/protocols/draft_gate.dart
//
// THE DRAFT GATE — one pure function deciding whether "Draft in my format"
// can run, and if not, which of the FOUR distinct refusals applies and in
// what words.
//
// Pure and top-level so the decision is testable without a widget, and so
// there is exactly ONE place the answer is computed. The screen renders
// this; it never re-derives any part of it.
//
// The four reasons are deliberately NOT collapsible into each other. They
// differ in who can act and on what:
//
//   recordAnomaly    — the record is defective (a section stamped complete
//                      whose rows are still unmarked). SHE can repair it,
//                      in the capture surface, now. Checked FIRST precisely
//                      because it is the actionable one: a defect in the
//                      record matters whether or not this protocol drafts.
//   noReader         — this build has no assessment reader for the
//                      protocol. Not her problem and not fixable by her;
//                      known at build time from the protocol manifest.
//   noFormat         — she has no CONFIRMED report format. Fixable by her
//                      in about two minutes. Never folded into noReader:
//                      telling her "not available for this assessment type"
//                      when the truth is "add a format" wastes her time on
//                      the wrong problem.
//   nothingCaptured  — the protocol CAN draft and she has a format, but
//                      this client has no capture row. Nothing is missing
//                      from the app; something is missing from the record.
//
// noFormat and nothingCaptured need reads the case screen does not do at
// build time, so they stay post-tap. recordAnomaly and noReader are both
// known before the tap and disable the button.

import 'protocol_manifest.dart';
import '../constants/clinical_areas.dart';
import '../widgets/assessment/sectional_capture.dart';

enum DraftRefusal {
  /// A section is stamped complete but still holds unmarked rows.
  recordAnomaly,

  /// No clinical area on the case at all.
  noArea,

  /// No protocol for this area in this build.
  noProtocol,

  /// Protocol(s) exist but none has an assessment reader.
  noReader,
}

class DraftGateDecision {
  final bool canDraft;

  /// Null when [canDraft]. Otherwise which refusal applies.
  final DraftRefusal? refusal;

  /// Null when [canDraft]. A plain sentence — states the fact, offers the
  /// repair where one exists. No apology, no narrating the tool's own
  /// restraint.
  final String? reason;

  /// The protocol to draft with, set only when [canDraft].
  final ProtocolManifestEntry? entry;

  const DraftGateDecision._({
    required this.canDraft,
    this.refusal,
    this.reason,
    this.entry,
  });
}

/// Decides pre-tap draftability for a case.
///
/// [anomalies] comes from the capture surface's SectionalCaptureController —
/// the ONE place anomalies are computed. The gate never recomputes them.
/// [sectionLabels] maps a section id to its SLP-facing name so the refusal
/// can name the affected section rather than print an internal key.
DraftGateDecision evaluateDraftGate({
  required String? clinicalArea,
  required List<SectionalCompletionAnomaly> anomalies,
  Map<String, String> sectionLabels = const {},
}) {
  // REASON: record anomaly. First, because it is the one she can act on,
  // and because a defective record matters whether or not this protocol
  // can draft.
  if (anomalies.isNotEmpty) {
    final a = anomalies.first;
    final label = sectionLabels[a.sectionId] ?? a.sectionId;
    final n = a.unmarkedRowIds.length;
    final more = anomalies.length > 1
        ? ' (and ${anomalies.length - 1} other '
            'section${anomalies.length - 1 == 1 ? '' : 's'})'
        : '';
    return DraftGateDecision._(
      canDraft: false,
      refusal: DraftRefusal.recordAnomaly,
      reason: '$label is marked done but $n '
          'item${n == 1 ? '' : 's'} in it never saved$more. '
          'Repair it above, then draft.',
    );
  }

  final area = clinicalArea ?? '';
  if (area.isEmpty) {
    return const DraftGateDecision._(
      canDraft: false,
      refusal: DraftRefusal.noArea,
      reason: 'No clinical area set for this case.',
    );
  }

  final protocols = protocolsForArea(area);
  if (protocols.isEmpty) {
    return DraftGateDecision._(
      canDraft: false,
      refusal: DraftRefusal.noProtocol,
      reason: 'No capture protocol for ${clinicalAreaLabel(area)} in this '
          'build.',
    );
  }

  final draftable = protocols.where((p) => p.isDraftable).toList();
  if (draftable.isEmpty) {
    return const DraftGateDecision._(
      canDraft: false,
      refusal: DraftRefusal.noReader,
      reason: 'This protocol captures to the record; it does not draft a '
          'report yet.',
    );
  }

  return DraftGateDecision._(canDraft: true, entry: draftable.first);
}
