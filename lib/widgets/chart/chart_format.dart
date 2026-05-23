// Pure helpers for the Phase B chart (Reading Room rebuild).
//
// Date/relative formatting + the contextual primary-action resolver. The
// resolver here only decides which chip reads as PRIMARY (visual weight);
// routing each chip to a real action is prompt 3.
import '../../models/client_chart_state.dart';

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];
const _days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

/// True if [d] falls on the local calendar today.
bool isToday(DateTime? d) {
  if (d == null) return false;
  final n = DateTime.now();
  return d.year == n.year && d.month == n.month && d.day == n.day;
}

/// "May 21"
String monthDay(DateTime d) => '${_months[d.month - 1]} ${d.day}';

/// "Thu"
String dayAbbr(DateTime d) => _days[(d.weekday - 1) % 7];

/// Coarse human duration since [from] — "today", "3 days", "2 weeks",
/// "4 months", "1 year". Used for the eyebrow + footer "last seen".
String durationSince(DateTime from) {
  final days = DateTime.now().difference(from).inDays;
  if (days <= 0) return 'today';
  if (days == 1) return 'yesterday';
  if (days < 14) return '$days days';
  if (days < 60) return '${(days / 7).round()} weeks';
  if (days < 365) return '${(days / 30).round()} months';
  final years = (days / 365).floor();
  return years == 1 ? '1 year' : '$years years';
}

/// "last seen" register — "today", "yesterday", else durationSince + " ago".
String relativeLastSeen(DateTime? d) {
  if (d == null) return 'never';
  final s = durationSince(d);
  if (s == 'today' || s == 'yesterday') return s;
  return '$s ago';
}

// ── Contextual primary action (visual only — routing is prompt 3) ────────────

enum ChartPrimaryAction {
  authorLtg,
  documentLastSession,
  planTodaySession,
  planNextSession,
}

/// Resolve which chip reads as primary, per the locked precedence:
/// no LTG → Author; undocumented sessions → Document; session today → Plan
/// today; otherwise → Plan next.
ChartPrimaryAction resolvePrimaryAction(
  ClientChartState s, {
  required bool sessionToday,
}) {
  if (s.ltgCount == 0) return ChartPrimaryAction.authorLtg;
  if (s.undocumentedSessionCount > 0) {
    return ChartPrimaryAction.documentLastSession;
  }
  if (sessionToday) return ChartPrimaryAction.planTodaySession;
  return ChartPrimaryAction.planNextSession;
}

String primaryActionLabel(ChartPrimaryAction a, String clientName) =>
    switch (a) {
      ChartPrimaryAction.authorLtg => "Author $clientName's long-term goal",
      ChartPrimaryAction.documentLastSession => 'Document last session',
      ChartPrimaryAction.planTodaySession => "Plan today's session",
      ChartPrimaryAction.planNextSession => 'Plan next session',
    };

/// "early" (<3 sessions) / "stable" (3–10) / "mature" (>10).
String sessionTrend(int total) {
  if (total < 3) return 'early';
  if (total <= 10) return 'stable';
  return 'mature';
}
