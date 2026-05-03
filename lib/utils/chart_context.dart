// lib/utils/chart_context.dart
//
// Builds the system-context block that gets prepended to every Cue Study
// turn. The format is consumed verbatim by the Render proxy and concatenated
// onto CUE_STUDY_SYSTEM_PROMPT before being sent to Anthropic.
//
// Sections (always in this order):
//   === CLIENT CHART ===
//   === ACTIVE GOALS ===
//   === RECENT SESSIONS (last 20, newest first) ===
//   === TIMELINE EVENTS ===
//
// Section bodies that have no rows write "(none yet)" so Cue knows the
// absence is real, not a missing field.

import 'package:supabase_flutter/supabase_flutter.dart';

/// Build the chart-context string for [clientId].
///
/// [clientData] is the in-memory client row already loaded by the caller
/// (avoids a redundant round trip). Goals, sessions and timeline events are
/// queried fresh from Supabase.
Future<String> buildChartContext(
  String clientId,
  Map<String, dynamic> clientData,
) async {
  final supabase = Supabase.instance.client;

  // ── Identity ────────────────────────────────────────────────────────────
  final name      = (clientData['name']      as String?) ?? 'Unknown';
  final age       =  clientData['age'];
  final diagnosis = (clientData['diagnosis'] as String?)?.trim();

  // ── Sessions (need these for cadence + RECENT SESSIONS) ─────────────────
  // Fetch enough for both the cadence calculation and the last-20 block.
  // Phase 4.0.7.10 — exclude soft-deleted sessions from cadence + history.
  final sessionsRaw = await supabase
      .from('sessions')
      .select()
      .eq('client_id', clientId)
      .isFilter('deleted_at', null)
      .order('created_at', ascending: false)
      .limit(40);
  final sessions = List<Map<String, dynamic>>.from(sessionsRaw);

  // Cadence: count, weeks span (oldest→newest), last-seen date
  final cadence = _computeCadence(sessions);

  // ── Goals ───────────────────────────────────────────────────────────────
  final ltgsRaw = await supabase
      .from('long_term_goals')
      .select()
      .eq('client_id', clientId)
      .order('sequence_num', ascending: true);
  final ltgs = List<Map<String, dynamic>>.from(ltgsRaw);

  final stgsRaw = await supabase
      .from('short_term_goals')
      .select()
      .eq('client_id', clientId)
      .order('sequence_num', ascending: true);
  final stgs = List<Map<String, dynamic>>.from(stgsRaw);

  // ── Compose ─────────────────────────────────────────────────────────────
  final buf = StringBuffer();

  // CLIENT CHART
  buf.writeln('=== CLIENT CHART ===');
  buf.writeln('Name: $name');
  buf.writeln('Age: ${age ?? "unknown"} · ${diagnosis?.isNotEmpty == true ? diagnosis : "diagnosis not specified"}');
  buf.writeln('Cadence: ${cadence.formatLine()}');
  buf.writeln();

  // ACTIVE GOALS
  buf.writeln('=== ACTIVE GOALS ===');
  final activeLtgs = ltgs.where((l) {
    final s = (l['status'] as String?)?.toLowerCase();
    return s == null || s.isEmpty || s == 'active';
  }).toList();
  if (activeLtgs.isEmpty) {
    buf.writeln('(none yet)');
  } else {
    for (final ltg in activeLtgs) {
      final ltgId  = ltg['id']?.toString() ?? '';
      final domain = (ltg['domain'] as String?) ??
                     (ltg['category'] as String?) ?? 'general';
      final ltgText = (ltg['goal_text'] as String?) ??
                      (ltg['original_text'] as String?) ??
                      '(no goal text)';
      buf.writeln('GOAL ($domain): $ltgText');

      final ltgStgs = stgs.where((s) {
        final sLtg = s['long_term_goal_id']?.toString();
        if (sLtg != ltgId) return false;
        final st = (s['status'] as String?)?.toLowerCase();
        return st == null || st.isEmpty || st == 'active';
      }).toList();

      if (ltgStgs.isNotEmpty) {
        buf.writeln('  Active steps:');
        for (final stg in ltgStgs) {
          final t = (stg['specific'] as String?) ??
                    (stg['goal_text'] as String?) ??
                    (stg['target_behavior'] as String?) ??
                    '';
          if (t.trim().isEmpty) continue;
          buf.writeln('  - ${t.trim()}');
        }
      }
    }
  }
  buf.writeln();

  // RECENT SESSIONS (last 20 newest first)
  buf.writeln('=== RECENT SESSIONS (last 20, newest first) ===');
  final last20 = sessions.take(20).toList();
  if (last20.isEmpty) {
    buf.writeln('(none yet)');
  } else {
    for (final s in last20) {
      final dateStr = (s['date'] as String?) ??
                      (s['created_at'] as String?)?.substring(0, 10) ??
                      'unknown date';
      final summary = _summariseSession(s);
      buf.writeln('Session on $dateStr: $summary');
    }
  }
  buf.writeln();

  // TIMELINE EVENTS — synthesised from goal status changes (no dedicated
  // table yet). Phase 2 will introduce a first-class events table.
  buf.writeln('=== TIMELINE EVENTS ===');
  final timeline = _buildTimeline(ltgs);
  if (timeline.isEmpty) {
    buf.writeln('(none yet)');
  } else {
    for (final e in timeline.take(10)) {
      buf.writeln('${e.dateStr}: ${e.type} · ${e.description}');
    }
  }

  return buf.toString();
}

// ── Helpers ──────────────────────────────────────────────────────────────────

class _Cadence {
  final int     sessionsCount;
  final int     weeksSpan;
  final String? lastSessionDate;
  const _Cadence({
    required this.sessionsCount,
    required this.weeksSpan,
    required this.lastSessionDate,
  });

  String formatLine() {
    final last = lastSessionDate ?? 'no sessions yet';
    final span = sessionsCount == 0
        ? '0 sessions'
        : '$sessionsCount session${sessionsCount == 1 ? "" : "s"} over $weeksSpan week${weeksSpan == 1 ? "" : "s"}';
    return '$span · last seen $last';
  }
}

_Cadence _computeCadence(List<Map<String, dynamic>> sessions) {
  if (sessions.isEmpty) {
    return const _Cadence(
      sessionsCount: 0, weeksSpan: 0, lastSessionDate: null);
  }
  // sessions are newest-first
  final newest = _parseSessionDate(sessions.first);
  final oldest = _parseSessionDate(sessions.last);
  int weeks = 1;
  if (newest != null && oldest != null) {
    final days = newest.difference(oldest).inDays;
    weeks = ((days / 7).ceil()).clamp(1, 9999);
  }
  return _Cadence(
    sessionsCount:    sessions.length,
    weeksSpan:        weeks,
    lastSessionDate:  newest != null
        ? '${newest.year.toString().padLeft(4, "0")}-'
          '${newest.month.toString().padLeft(2, "0")}-'
          '${newest.day.toString().padLeft(2, "0")}'
        : null,
  );
}

DateTime? _parseSessionDate(Map<String, dynamic> s) {
  final d = (s['date'] as String?) ??
            (s['created_at'] as String?);
  if (d == null) return null;
  try {
    return DateTime.parse(d);
  } catch (_) {
    return null;
  }
}

String _summariseSession(Map<String, dynamic> s) {
  final note = (s['soap_note'] as String?)?.trim();
  if (note != null && note.isNotEmpty) {
    return _truncate(note, 400);
  }
  // Fallback: concatenate available fields (subjective/objective/assessment/plan
  // do not exist as separate columns in this schema, so we use the closest
  // narrative fields — activity, target, observation surrogates).
  final parts = <String>[];
  void add(String? v) {
    if (v != null && v.trim().isNotEmpty) parts.add(v.trim());
  }
  add(s['target_behaviour']    as String?);
  add(s['activity_name']       as String?);
  add(s['client_affect']       as String?);
  add(s['next_session_focus']  as String?);
  add(s['notes']               as String?);
  if (parts.isEmpty) return 'session documented (no narrative captured)';
  return _truncate(parts.join(' · '), 400);
}

String _truncate(String s, int max) {
  final t = s.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (t.length <= max) return t;
  return '${t.substring(0, max)}…';
}

class _TimelineEvent {
  final String dateStr;
  final DateTime date;
  final String type;
  final String description;
  const _TimelineEvent({
    required this.dateStr,
    required this.date,
    required this.type,
    required this.description,
  });
}

List<_TimelineEvent> _buildTimeline(List<Map<String, dynamic>> ltgs) {
  final events = <_TimelineEvent>[];
  for (final l in ltgs) {
    final domain = (l['domain'] as String?) ?? 'general';
    final text   = ((l['goal_text'] as String?) ?? '').trim();

    final created = _safeParse(l['created_at'] as String?);
    if (created != null) {
      events.add(_TimelineEvent(
        dateStr:     _fmt(created),
        date:        created,
        type:        'milestone',
        description: 'goal set in $domain'
                     '${text.isNotEmpty ? " — ${_truncate(text, 80)}" : ""}',
      ));
    }

    final status = (l['status'] as String?)?.toLowerCase();
    if (status == 'mastered' || status == 'met' || status == 'achieved') {
      final updated = _safeParse(l['updated_at'] as String?) ?? created;
      if (updated != null) {
        events.add(_TimelineEvent(
          dateStr:     _fmt(updated),
          date:        updated,
          type:        'goal_achieved',
          description: '$domain goal'
                       '${text.isNotEmpty ? " — ${_truncate(text, 80)}" : ""}',
        ));
      }
    }
  }
  events.sort((a, b) => b.date.compareTo(a.date));
  return events;
}

DateTime? _safeParse(String? s) {
  if (s == null) return null;
  try { return DateTime.parse(s); } catch (_) { return null; }
}

String _fmt(DateTime d) =>
    '${d.year.toString().padLeft(4, "0")}-'
    '${d.month.toString().padLeft(2, "0")}-'
    '${d.day.toString().padLeft(2, "0")}';
