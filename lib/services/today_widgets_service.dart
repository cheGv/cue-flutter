// lib/services/today_widgets_service.dart
//
// Phase 4.0.8-step-B-surface-1.2 — Today's "At a glance" widget data
// orchestration. Four query methods, one per widget, each defensive
// (returns empty list / null on failure rather than throwing to UI).
//
// Schema conventions (canonical, mirrored from existing surfaces):
//   • sessions table   — uses `user_id` (NOT clinician_id), `date`
//                        (string YYYY-MM-DD), `created_at` (ts).
//   • short_term_goals — uses `user_id`, `client_id`, `status` enum
//                        ('active' / 'mastered' / 'archived' /
//                        'pending_attestation'), `target_behavior`,
//                        `current_accuracy`, `mastery_criterion` jsonb,
//                        `updated_at`.
//   • daily_roster     — uses `clinician_id`, `client_id`,
//                        `session_date` (string YYYY-MM-DD),
//                        `session_documented` (bool).
//   • clients          — joined for display name.
//
// Pulse semantics mirrored from today_screen.dart `_loadWeekPulse`:
// "documented" = `soap_note` non-empty OR `notes` non-empty. Not just
// soap_note; the 4.0.7.31-unified-save-flow stores prose in `notes`
// for typed-flow sessions.

import 'package:supabase_flutter/supabase_flutter.dart';

// ── Data models ──────────────────────────────────────────────────────────────

/// One day's session counts for the week-pulse bar chart.
class DailyPulse {
  /// 1=Mon … 7=Sun (matches DateTime.weekday).
  final int weekday;
  final int sessionCount;
  final int documentedCount;
  const DailyPulse({
    required this.weekday,
    required this.sessionCount,
    required this.documentedCount,
  });
}

/// One pending session (no soap_note + no notes) for the pending-notes
/// widget label. Day label rendered Inter sentence-case; time rendered
/// JetBrains Mono via the widget's Text.rich split.
class PendingSession {
  final String clientName;
  final String dayLabel;   // "Yesterday", "Wed", "Mon", etc.
  final String timeLabel;  // "14:30" — mono span
  const PendingSession({
    required this.clientName,
    required this.dayLabel,
    required this.timeLabel,
  });
}

/// One STG row for the Active Goals widget. Top-N by recency.
class ActiveGoal {
  final String clientName;
  final String goalText;        // target_behavior trimmed
  final double? currentAccuracy; // 0..100, may be null
  final int? targetAccuracy;     // from mastery_criterion.accuracy_pct
  const ActiveGoal({
    required this.clientName,
    required this.goalText,
    this.currentAccuracy,
    this.targetAccuracy,
  });
}

/// Tomorrow's preview — count + first session details.
class TomorrowSummary {
  final int sessionCount;
  /// Display string for the first session, e.g. "Aarav · 09:00".
  /// null when no sessions scheduled.
  final String? firstClientName;
  final String? firstTimeLabel;
  const TomorrowSummary({
    required this.sessionCount,
    this.firstClientName,
    this.firstTimeLabel,
  });
}

/// Cue Noticed insight. Hardcoded template for v1.2 — sourced from
/// the longest-stagnant active STG. Returns null when no stagnant goal
/// exists; widget hides itself entirely in that case (no empty state).
class CueInsight {
  final String goalText;
  final String clientName;
  final int sessionCount; // sessions since the goal's last documented
                          // attempt (proxy: total sessions since
                          // updated_at — coarse but works for v1.2).
  final String renderedBody;
  const CueInsight({
    required this.goalText,
    required this.clientName,
    required this.sessionCount,
    required this.renderedBody,
  });
}

// ── Service ──────────────────────────────────────────────────────────────────

class TodayWidgetsService {
  TodayWidgetsService._();

  static final SupabaseClient _sb = Supabase.instance.client;

  /// Mon-Fri pulse for the current week. Returns 5 rows (Mon-Fri),
  /// zero-counts for days with no sessions. Empty list on auth failure.
  static Future<List<DailyPulse>> getThisWeekPulse() async {
    final uid = _sb.auth.currentUser?.id;
    if (uid == null) return const [];

    final now = DateTime.now();
    final monday = now.subtract(Duration(days: now.weekday - 1));
    final friday = monday.add(const Duration(days: 4));
    final mondayIso = _isoDate(monday);
    final fridayIso = _isoDate(friday);

    try {
      final rows = await _sb
          .from('sessions')
          .select('date, soap_note, notes')
          .eq('user_id', uid)
          .gte('date', mondayIso)
          .lte('date', fridayIso)
          .isFilter('deleted_at', null);

      // Initialize Mon-Fri buckets.
      final buckets = <int, _PulseAccumulator>{
        for (var i = 1; i <= 5; i++) i: _PulseAccumulator(),
      };

      for (final raw in rows) {
        final r = Map<String, dynamic>.from(raw as Map);
        final dateStr = r['date'] as String?;
        if (dateStr == null) continue;
        final dt = DateTime.tryParse(dateStr);
        if (dt == null) continue;
        final wd = dt.weekday;
        if (wd < 1 || wd > 5) continue; // weekend — out of pulse scope

        final acc = buckets[wd]!;
        acc.sessions++;
        final soap  = (r['soap_note'] as String?)?.trim();
        final notes = (r['notes']     as String?)?.trim();
        if ((soap != null && soap.isNotEmpty) ||
            (notes != null && notes.isNotEmpty)) {
          acc.documented++;
        }
      }

      return [
        for (var i = 1; i <= 5; i++)
          DailyPulse(
            weekday:         i,
            sessionCount:    buckets[i]!.sessions,
            documentedCount: buckets[i]!.documented,
          ),
      ];
    } catch (e) {
      // Non-fatal — return empty pulse, widget renders zero-state bars.
      return const [];
    }
  }

  /// Pending sessions in the last 7 days. Returns up to 5 rows ordered
  /// most-recent-first, suitable for the label string.
  static Future<List<PendingSession>> getPendingNotes({int limit = 5}) async {
    final uid = _sb.auth.currentUser?.id;
    if (uid == null) return const [];

    final sevenDaysAgo = DateTime.now()
        .toUtc()
        .subtract(const Duration(days: 7));
    final sevenDaysAgoIso = _isoDate(sevenDaysAgo);

    try {
      final rows = await _sb
          .from('sessions')
          .select('id, date, created_at, soap_note, notes, client_id, '
                  'clients(name)')
          .eq('user_id', uid)
          .gte('date', sevenDaysAgoIso)
          .isFilter('deleted_at', null)
          .order('date', ascending: false);

      final result = <PendingSession>[];
      for (final raw in rows) {
        final r = Map<String, dynamic>.from(raw as Map);
        final soap  = (r['soap_note'] as String?)?.trim();
        final notes = (r['notes']     as String?)?.trim();
        final isDocumented = (soap != null && soap.isNotEmpty) ||
                             (notes != null && notes.isNotEmpty);
        if (isDocumented) continue;

        final client = r['clients'] as Map?;
        final clientName = client?['name']?.toString() ?? 'Unknown';

        final dateStr = r['date'] as String?;
        final dt = dateStr != null ? DateTime.tryParse(dateStr) : null;
        final dayLabel  = _relativeDayLabel(dt);
        final timeLabel = _timeFromCreatedAt(r['created_at'] as String?);

        result.add(PendingSession(
          clientName: clientName,
          dayLabel:   dayLabel,
          timeLabel:  timeLabel,
        ));
        if (result.length >= limit) break;
      }
      return result;
    } catch (e) {
      return const [];
    }
  }

  /// Top-N active STGs by recency for the current SLP.
  ///
  /// Phase 4.0.8-step-B-surface-1.2 hotfix — query selects canonical
  /// prototype columns (`specific`, `target_behavior` legacy fallback,
  /// `target_accuracy` direct, `current_accuracy`). The pre-hotfix
  /// query selected `mastery_criterion` (the deprecated target's
  /// jsonb column) which doesn't exist on the prototype DB; the
  /// PGRST204 "column not found" was silently caught and returned
  /// an empty list — the bug founder verification caught.
  static Future<List<ActiveGoal>> getActiveGoals({int limit = 4}) async {
    final uid = _sb.auth.currentUser?.id;
    if (uid == null) return const [];

    try {
      final rows = await _sb
          .from('short_term_goals')
          .select('specific, target_behavior, current_accuracy, '
                  'target_accuracy, client_id, clients(name)')
          .eq('user_id', uid)
          .eq('status', 'active')
          .order('updated_at', ascending: false)
          .limit(limit);

      return [
        for (final raw in rows)
          _activeGoalFrom(Map<String, dynamic>.from(raw as Map)),
      ];
    } catch (e) {
      // ignore: avoid_print
      print('[TodayWidgets] getActiveGoals failed: $e');
      return const [];
    }
  }

  /// Tomorrow's scheduled session count + first-session preview, sourced
  /// from `daily_roster` (the canonical planning table). Falls back to
  /// zero-state TomorrowSummary on any failure.
  static Future<TomorrowSummary> getTomorrowSummary() async {
    final uid = _sb.auth.currentUser?.id;
    if (uid == null) {
      return const TomorrowSummary(sessionCount: 0);
    }

    final tomorrow = DateTime.now().add(const Duration(days: 1));
    final tomorrowIso = _isoDate(tomorrow);

    try {
      final rows = await _sb
          .from('daily_roster')
          .select('id, client_id, session_date, clients(name)')
          .eq('clinician_id', uid)
          .eq('session_date', tomorrowIso)
          .order('id', ascending: true);

      final list = (rows as List)
          .map((r) => Map<String, dynamic>.from(r as Map))
          .toList();
      if (list.isEmpty) {
        return const TomorrowSummary(sessionCount: 0);
      }
      final firstClient = list.first['clients'] as Map?;
      // daily_roster has no scheduled time column in this prototype
      // schema — pass null timeLabel so the widget renders just the
      // client name. Once a session_time column lands the time goes
      // mono inline.
      return TomorrowSummary(
        sessionCount:    list.length,
        firstClientName: firstClient?['name']?.toString(),
        firstTimeLabel:  null,
      );
    } catch (e) {
      return const TomorrowSummary(sessionCount: 0);
    }
  }

  /// Cue Noticed insight — single hardcoded-template observation about
  /// the longest-stagnant active STG. Returns null when no stagnant goal
  /// exists (the widget then hides itself entirely; no empty state).
  ///
  /// Stagnation proxy: `status='active' ORDER BY updated_at ASC LIMIT 1`.
  /// Sessions count proxy: count of sessions for that client_id since
  /// the STG's `updated_at`. Coarse but adequate for v1.2.
  static Future<CueInsight?> getNoticedInsight() async {
    final uid = _sb.auth.currentUser?.id;
    if (uid == null) return null;

    try {
      final stgRows = await _sb
          .from('short_term_goals')
          .select('target_behavior, updated_at, client_id, clients(name)')
          .eq('user_id', uid)
          .eq('status', 'active')
          .order('updated_at', ascending: true)
          .limit(1);

      if (stgRows.isEmpty) return null;
      final stg = Map<String, dynamic>.from(stgRows.first as Map);
      final goalText  = (stg['target_behavior'] as String?)?.trim();
      final clientId  = stg['client_id']?.toString();
      final updatedAtStr = stg['updated_at'] as String?;
      final updatedAt = updatedAtStr != null
          ? DateTime.tryParse(updatedAtStr)
          : null;
      if (goalText == null || goalText.isEmpty || clientId == null) {
        return null;
      }

      final client = stg['clients'] as Map?;
      final clientName = client?['name']?.toString() ?? 'this child';
      final firstName  = clientName.split(RegExp(r'\s+')).first;

      // Sessions since updated_at for this client.
      int sessionCount = 0;
      if (updatedAt != null) {
        try {
          final sinceIso = _isoDate(updatedAt);
          final sessions = await _sb
              .from('sessions')
              .select('id')
              .eq('user_id', uid)
              .eq('client_id', clientId)
              .gte('date', sinceIso)
              .isFilter('deleted_at', null);
          sessionCount = (sessions as List).length;
        } catch (_) {/* leave at 0 */}
      }

      // Hide when no stagnation pressure — fewer than 2 sessions since
      // updated_at means the goal isn't actually stagnant; the SLP just
      // hasn't gotten back to it yet on a normal cadence.
      if (sessionCount < 2) return null;

      final body = '$goalText for $firstName has been active for '
          '$sessionCount sessions without a documented attempt — '
          'worth checking in.';

      return CueInsight(
        goalText:     goalText,
        clientName:   firstName,
        sessionCount: sessionCount,
        renderedBody: body,
      );
    } catch (e) {
      return null;
    }
  }

  // ── Helpers ────────────────────────────────────────────────────────────

  static String _isoDate(DateTime d) =>
      d.toIso8601String().substring(0, 10);

  /// Friendly day label relative to today. "Yesterday" / "Today" /
  /// short weekday name ("Wed", "Mon") / "8 May" for older.
  static String _relativeDayLabel(DateTime? dt) {
    if (dt == null) return '—';
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final d     = DateTime(dt.year, dt.month, dt.day);
    final diff  = today.difference(d).inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    if (diff > 1 && diff <= 6) {
      const names = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      return names[d.weekday - 1];
    }
    const months = ['', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
                    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${d.day} ${months[d.month]}';
  }

  /// "HH:MM" extracted from a timestamp string, or "—" on failure.
  static String _timeFromCreatedAt(String? createdAt) {
    if (createdAt == null) return '—';
    final dt = DateTime.tryParse(createdAt);
    if (dt == null) return '—';
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  static ActiveGoal _activeGoalFrom(Map<String, dynamic> row) {
    final client = row['clients'] as Map?;
    final clientName = client?['name']?.toString() ?? 'Unknown';

    // Phase 4.0.8-step-B-surface-1.2 — prefer canonical `specific`
    // over legacy `target_behavior`. CLAUDE.md §7.1 marks `specific`
    // as the post-Phase-4 step-shape column; `target_behavior` was
    // the deprecated target's name and survives in some legacy rows.
    final specific = (row['specific']        as String?)?.trim();
    final fallback = (row['target_behavior'] as String?)?.trim();
    final goalText = (specific != null && specific.isNotEmpty)
        ? specific
        : (fallback != null && fallback.isNotEmpty ? fallback : '—');

    final currentAcc = (row['current_accuracy'] as num?)?.toDouble();
    final targetAcc  = (row['target_accuracy']  as num?)?.toInt();

    return ActiveGoal(
      clientName:      clientName,
      goalText:        goalText,
      currentAccuracy: currentAcc,
      targetAccuracy:  targetAcc,
    );
  }
}

class _PulseAccumulator {
  int sessions = 0;
  int documented = 0;
}
