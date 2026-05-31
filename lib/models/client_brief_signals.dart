import 'package:flutter/foundation.dart';

import 'session.dart';
import 'short_term_goal.dart';

// Client briefing — Layer 2: the SIGNAL COMPUTATION.
//
// Computes the FACTS the brief will report, as structured data — NOT prose.
// Layer 3 (phrasing) consumes this; this layer must never produce a sentence.
//
// LAW BOUNDARY: every field is a count, a date-derived number, a list of
// codes, or a boolean. Nothing here evaluates progress, judges a goal as
// failing/succeeding, computes proximity-to-mastery, or forecasts. The three
// signals are purely factual:
//   1. new_activity  — sessions logged since the SLP last opened the file
//   2. pending_goals — active STGs with ZERO sessions logged against them
//   3. time_gap      — days since the most recent session (or last visit)

/// The single ranked headline signal. Ranking (fixed priority):
///   newActivity → pending → longGap → firstVisit → nothingNew (floor).
/// `firstVisit` sits just above the `nothingNew` floor: when it's the first
/// time this clinician opens the file and nothing more specific fires, that
/// fact leads. `newActivity` can only fire on a return visit (a first visit
/// has no "since last visit" baseline).
enum BriefLead {
  newActivity,
  pending,
  longGap,
  firstVisit,
  nothingNew,
}

@immutable
class ClientBriefSignals {
  /// The ranked headline fact (see [BriefLead]).
  final BriefLead lead;

  /// Count of sessions whose date is after [ClientBriefSignals.compute]'s
  /// priorViewedAt. 0 on a first visit (no baseline to count against).
  final int sessionsSinceLastVisit;

  /// Display codes ("1.B", "1.C") of active STGs with zero sessions logged
  /// against them — "still to be taken up". Sorted for stable output.
  final List<String> pendingGoalCodes;

  /// Whole days between "now" and the most recent session date; falls back to
  /// days since prior_viewed_at when there are no sessions; 0 when neither
  /// reference exists. Never negative.
  final int daysSinceLastSeen;

  /// True when this clinician has never opened this client before (Layer 1's
  /// prior_viewed_at was null).
  final bool isFirstVisit;

  /// Total active STGs on the plan (status='active', deleted_at IS NULL). A
  /// plain count — used by the first-visit phrasing ("N short-term goals on
  /// the plan"). Not one of the three signals; a context count for Layer 3.
  final int activeGoalCount;

  const ClientBriefSignals({
    required this.lead,
    required this.sessionsSinceLastVisit,
    required this.pendingGoalCodes,
    required this.daysSinceLastSeen,
    required this.isFirstVisit,
    required this.activeGoalCount,
  });

  /// Pure computation over already-loaded chart data. No I/O, no clock read
  /// (pass [now]) — fully deterministic + unit-testable. Layer 3 / the chart
  /// feed it the data they already hold.
  ///
  ///  • [priorViewedAt] — Layer 1's PRIOR last-viewed timestamp (null = first
  ///    visit). This is the value from BEFORE this open.
  ///  • [sessions] — the client's real sessions (non-deleted, non-draft).
  ///  • [activeStgs] — active, non-archived STGs (status='active', deleted_at
  ///    IS NULL).
  ///  • [stgCodes] — stgId → display code ("1.B"); from stg_numbering.
  ///  • [longGapThresholdDays] — gap above which `longGap` may lead (default 14).
  factory ClientBriefSignals.compute({
    required DateTime? priorViewedAt,
    required List<Session> sessions,
    required List<ShortTermGoal> activeStgs,
    required Map<String, String> stgCodes,
    required DateTime now,
    int longGapThresholdDays = 14,
  }) {
    final isFirstVisit = priorViewedAt == null;

    DateTime dateOf(Session s) => s.date ?? s.createdAt;

    // ── 1. new_activity ──────────────────────────────────────────────────
    // Sessions logged since the last open. Undefined on a first visit (no
    // baseline) → 0; isFirstVisit carries that case for Layer 3.
    var sessionsSinceLastVisit = 0;
    if (!isFirstVisit) {
      for (final s in sessions) {
        if (dateOf(s).isAfter(priorViewedAt)) sessionsSinceLastVisit++;
      }
    }

    // ── 2. pending_goals ─────────────────────────────────────────────────
    // Active STGs with zero sessions referencing them ("still to be taken
    // up"). Purely a set-membership fact — no progress evaluation.
    final workedStgIds = <String>{
      for (final s in sessions)
        if (s.shortTermGoalId != null) s.shortTermGoalId!,
    };
    final pendingGoalCodes = <String>[
      for (final stg in activeStgs)
        if (!workedStgIds.contains(stg.id))
          stgCodes[stg.id] ?? 'STG ${stg.sequenceNum ?? '?'}',
    ]..sort();

    // ── 3. time_gap ──────────────────────────────────────────────────────
    DateTime? mostRecent;
    for (final s in sessions) {
      final d = dateOf(s);
      if (mostRecent == null || d.isAfter(mostRecent)) mostRecent = d;
    }
    int daysSinceLastSeen;
    if (mostRecent != null) {
      daysSinceLastSeen = now.difference(mostRecent).inDays;
    } else if (priorViewedAt != null) {
      daysSinceLastSeen = now.difference(priorViewedAt).inDays;
    } else {
      daysSinceLastSeen = 0; // never seen, never opened — no reference point
    }
    if (daysSinceLastSeen < 0) daysSinceLastSeen = 0; // guard future-dated rows

    // ── Rank the lead (fixed priority) ───────────────────────────────────
    final BriefLead lead;
    if (sessionsSinceLastVisit > 0) {
      lead = BriefLead.newActivity;
    } else if (pendingGoalCodes.isNotEmpty) {
      lead = BriefLead.pending;
    } else if (daysSinceLastSeen > longGapThresholdDays) {
      lead = BriefLead.longGap;
    } else if (isFirstVisit) {
      lead = BriefLead.firstVisit;
    } else {
      lead = BriefLead.nothingNew;
    }

    return ClientBriefSignals(
      lead: lead,
      sessionsSinceLastVisit: sessionsSinceLastVisit,
      pendingGoalCodes: pendingGoalCodes,
      daysSinceLastSeen: daysSinceLastSeen,
      isFirstVisit: isFirstVisit,
      activeGoalCount: activeStgs.length,
    );
  }

  /// Structured snapshot for debugging / eyeballing the raw facts. NOT prose.
  Map<String, Object?> toMap() => {
        'lead': lead.name,
        'sessionsSinceLastVisit': sessionsSinceLastVisit,
        'pendingGoalCodes': pendingGoalCodes,
        'daysSinceLastSeen': daysSinceLastSeen,
        'isFirstVisit': isFirstVisit,
        'activeGoalCount': activeGoalCount,
      };

  @override
  String toString() => 'ClientBriefSignals(${toMap()})';
}
