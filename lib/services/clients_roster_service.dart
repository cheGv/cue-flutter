// lib/services/clients_roster_service.dart
//
// Phase 4.0.9-step-B-roster-surface-2 — Roster data layer. Replaces the
// inline _fetchClients + _buildAttentionCardsAndDates batch that lived in
// the old ClientRosterScreen. Returns a recency-sorted list of
// hydrated entries; the screen does only filter / search / render.
//
// Query strategy (decided in step-A recon): parallel REST over the same
// canonical schema the old roster used. No DB migration. Recency calc
// (max(maxSessionDate ?? epoch, updatedAt)) lives in Dart; sorting is
// stable DESC by lastTouchedAt.

import 'package:supabase_flutter/supabase_flutter.dart';

import 'name_formatter.dart';

class ClientsRosterService {
  final SupabaseClient _client;

  ClientsRosterService({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  Future<List<ClientRosterEntry>> loadRoster() async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) return const [];

    // Therapy-engagement clients only — assessment-only cases live under
    // the Assessing sidebar. Soft-deleted rows excluded.
    final clientRows = await _client
        .from('clients')
        .select(
          'id, name, age, diagnosis, engagement_type, engagement_status, '
          'population_type, primary_concern_verbatim, uses_aac, '
          'created_at, updated_at',
        )
        .isFilter('deleted_at', null)
        .eq('engagement_type', 'therapy');

    final clients =
        List<Map<String, dynamic>>.from(clientRows as List);
    if (clients.isEmpty) return const [];

    // Two parallel pulls keyed off the clinician — sessions for max-date
    // + count, active short_term_goals for the goal count.
    final results = await Future.wait<dynamic>([
      _client
          .from('sessions')
          .select('client_id, date')
          .eq('user_id', uid)
          .isFilter('deleted_at', null),
      _client
          .from('short_term_goals')
          .select('client_id, status')
          .eq('user_id', uid)
          .eq('status', 'active'),
    ]);

    final sessionRows =
        (results[0] as List).map((r) => Map<String, dynamic>.from(r as Map));
    final goalRows =
        (results[1] as List).map((r) => Map<String, dynamic>.from(r as Map));

    // Aggregate per client_id. Both joins are text-on-text in Dart so
    // the text/uuid mismatch from raw SQL (see surface 1.2 audit) does
    // not surface here.
    final sessionsByClient = <String, List<DateTime>>{};
    for (final s in sessionRows) {
      final cid = s['client_id']?.toString();
      if (cid == null) continue;
      final raw = s['date'];
      final dt = _parseDate(raw);
      sessionsByClient.putIfAbsent(cid, () => []);
      if (dt != null) sessionsByClient[cid]!.add(dt);
    }

    final activeGoalsByClient = <String, int>{};
    for (final g in goalRows) {
      final cid = g['client_id']?.toString();
      if (cid == null) continue;
      activeGoalsByClient.update(cid, (v) => v + 1, ifAbsent: () => 1);
    }

    final entries = clients.map((c) {
      final id = c['id'].toString();
      final dates = sessionsByClient[id] ?? const <DateTime>[];
      DateTime? maxSession;
      for (final d in dates) {
        if (maxSession == null || d.isAfter(maxSession)) maxSession = d;
      }
      final updatedAt = _parseTimestamp(c['updated_at']);
      final createdAt = _parseTimestamp(c['created_at']);
      // Recency = the more recent of (last session, updated_at). Both
      // null falls back to epoch so the entry sinks to the bottom.
      final lastTouched = _laterOf(maxSession, updatedAt) ??
          DateTime.fromMillisecondsSinceEpoch(0);
      return ClientRosterEntry(
        id:                  id,
        rawName:             (c['name'] as String?) ?? '',
        age:                 (c['age'] as num?)?.toInt(),
        diagnosis:           c['diagnosis'] as String?,
        populationType:      c['population_type'] as String?,
        engagementStatus:    (c['engagement_status'] as String?) ?? 'active',
        primaryConcern:      c['primary_concern_verbatim'] as String?,
        usesAac:             (c['uses_aac'] as bool?) ?? false,
        sessionsCount:       dates.length,
        activeGoalsCount:    activeGoalsByClient[id] ?? 0,
        lastSessionDate:     maxSession,
        createdAt:           createdAt ?? lastTouched,
        updatedAt:           updatedAt ?? lastTouched,
        lastTouchedAt:       lastTouched,
        // Forwarded so the row's onTap can hand the row off to
        // ClientProfileScreen without a second DB fetch (matches the
        // pre-loaded MaterialPageRoute pattern from the old roster).
        rawRow:              Map<String, dynamic>.from(c),
      );
    }).toList()
      ..sort((a, b) => b.lastTouchedAt.compareTo(a.lastTouchedAt));

    return entries;
  }

  static DateTime? _parseDate(dynamic raw) {
    if (raw is String && raw.isNotEmpty) return DateTime.tryParse(raw);
    return null;
  }

  static DateTime? _parseTimestamp(dynamic raw) {
    if (raw is String && raw.isNotEmpty) return DateTime.tryParse(raw);
    return null;
  }

  static DateTime? _laterOf(DateTime? a, DateTime? b) {
    if (a == null) return b;
    if (b == null) return a;
    return a.isAfter(b) ? a : b;
  }
}

/// Hydrated entry consumed by ClientRosterScreen + ClientsRosterRow.
/// Keeps display logic close to the data so widgets stay rendering-only.
class ClientRosterEntry {
  final String id;
  final String rawName;
  final int? age;
  final String? diagnosis;
  final String? populationType;
  final String engagementStatus;
  final String? primaryConcern;
  final bool usesAac;
  final int sessionsCount;
  final int activeGoalsCount;
  final DateTime? lastSessionDate;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime lastTouchedAt;
  /// Original Supabase row, forwarded to ClientProfileScreen so the
  /// row click is single-frame (no re-fetch through the deep-link loader).
  final Map<String, dynamic> rawRow;

  const ClientRosterEntry({
    required this.id,
    required this.rawName,
    required this.age,
    required this.diagnosis,
    required this.populationType,
    required this.engagementStatus,
    required this.primaryConcern,
    required this.usesAac,
    required this.sessionsCount,
    required this.activeGoalsCount,
    required this.lastSessionDate,
    required this.createdAt,
    required this.updatedAt,
    required this.lastTouchedAt,
    required this.rawRow,
  });

  String get displayName => NameFormatter.displayName(rawName);

  /// "Age N · Diagnosis · AAC" — null parts dropped, dot-joined.
  String get focusStrip {
    final parts = <String>[];
    if (age != null) parts.add('Age $age');
    final dx = diagnosis?.trim();
    if (dx != null && dx.isNotEmpty) parts.add(dx);
    if (usesAac) parts.add('AAC');
    return parts.join(' · ');
  }

  bool get isActive => engagementStatus == 'active';
  bool get isDischarged => engagementStatus == 'discharged';
  bool get isNew => sessionsCount == 0;
  bool get hadSessionToday {
    final s = lastSessionDate;
    if (s == null) return false;
    final now = DateTime.now();
    return s.year == now.year && s.month == now.month && s.day == now.day;
  }

  /// "Today" / "Yesterday" / "{N} days ago" / "{DD MMM}".
  /// Uses lastSessionDate when present; otherwise falls back to
  /// createdAt so the recency cell still scans for new clients.
  String get recencyRelative {
    final ref = lastSessionDate ?? createdAt;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final refDay = DateTime(ref.year, ref.month, ref.day);
    final delta = today.difference(refDay).inDays;
    if (delta <= 0) return 'Today';
    if (delta == 1) return 'Yesterday';
    if (delta <= 30) return '$delta days ago';
    return _shortDate(refDay);
  }

  String get recencyContext =>
      sessionsCount > 0 ? 'last session' : 'enrolled';

  static String _shortDate(DateTime d) {
    const months = [
      '',
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final dd = d.day.toString().padLeft(2, '0');
    return '$dd ${months[d.month]}';
  }
}
