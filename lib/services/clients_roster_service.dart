// lib/services/clients_roster_service.dart
//
// Roster data layer for the /clients screen. Returns a recency-sorted
// list of hydrated entries plus the page-level signals the redesigned
// Clients screen needs (draft-session count for the action line, a
// debug-only fixture-visible count for the dev banner). The screen does
// only filter / search / render.
//
// Query strategy: parallel REST over the canonical schema. Recency calc
// (max(maxSessionDate ?? epoch, updatedAt)) lives in Dart; sorting is
// stable DESC by lastTouchedAt.
//
// Fixture filtering (Phase 4.0.9): in release builds the clients query
// adds `WHERE is_fixture = false`. The is_fixture column ships in
// migration 20260514120000; until that migration is applied the select
// degrades gracefully — see _fetchClients.

import 'package:flutter/foundation.dart' show kReleaseMode;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'name_formatter.dart';

class ClientsRosterService {
  final SupabaseClient _client;

  ClientsRosterService({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  static const String _clientCols =
      'id, name, age, diagnosis, engagement_type, engagement_status, '
      'population_type, primary_concern_verbatim, uses_aac, '
      'created_at, updated_at';

  Future<RosterLoadResult> loadRoster() async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) {
      return const RosterLoadResult(
        entries: [],
        draftSessionCount: 0,
        fixtureVisibleCount: 0,
      );
    }

    final clients = await _fetchClients();
    if (clients.isEmpty) {
      return const RosterLoadResult(
        entries: [],
        draftSessionCount: 0,
        fixtureVisibleCount: 0,
      );
    }

    // Parallel pulls keyed off the clinician — sessions for max-date +
    // count, active short_term_goals for the goal count, AND the full
    // list of draft sessions for the Inbox (the same query whose
    // `.length` is the Clients action-line banner count, per Phase
    // 4.1.7's single-source-of-truth rule).
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
      listDraftSessions(),
    ]);

    final sessionRows =
        (results[0] as List).map((r) => Map<String, dynamic>.from(r as Map));
    final goalRows =
        (results[1] as List).map((r) => Map<String, dynamic>.from(r as Map));
    final draftSessions = results[2] as List<DraftSessionEntry>;
    final draftSessionCount = draftSessions.length;

    final sessionsByClient = <String, List<DateTime>>{};
    for (final s in sessionRows) {
      final cid = s['client_id']?.toString();
      if (cid == null) continue;
      final dt = _parseDate(s['date']);
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
      final lastTouched = _laterOf(maxSession, updatedAt) ??
          DateTime.fromMillisecondsSinceEpoch(0);
      return ClientRosterEntry(
        id: id,
        rawName: (c['name'] as String?) ?? '',
        age: (c['age'] as num?)?.toInt(),
        diagnosis: c['diagnosis'] as String?,
        populationType: c['population_type'] as String?,
        engagementStatus: (c['engagement_status'] as String?) ?? 'active',
        primaryConcern: c['primary_concern_verbatim'] as String?,
        usesAac: (c['uses_aac'] as bool?) ?? false,
        isFixture: (c['is_fixture'] as bool?) ?? false,
        sessionsCount: dates.length,
        activeGoalsCount: activeGoalsByClient[id] ?? 0,
        lastSessionDate: maxSession,
        createdAt: createdAt ?? lastTouched,
        updatedAt: updatedAt ?? lastTouched,
        lastTouchedAt: lastTouched,
        rawRow: Map<String, dynamic>.from(c),
      );
    }).toList()
      ..sort((a, b) => b.lastTouchedAt.compareTo(a.lastTouchedAt));

    // In debug builds fixtures are not filtered out — surface a count so
    // the screen can show a "DEV: N fixture visible" banner.
    final fixtureVisibleCount =
        kReleaseMode ? 0 : entries.where((e) => e.isFixture).length;

    return RosterLoadResult(
      entries: entries,
      draftSessionCount: draftSessionCount,
      fixtureVisibleCount: fixtureVisibleCount,
    );
  }

  /// Phase 4.1.7 — single source of truth for "sessions waiting to be
  /// documented." Returns the full list of draft sessions for the
  /// signed-in clinician; the Clients banner uses `.length` and the
  /// Inbox screen uses the rows. Sort: oldest-waiting first (so the
  /// most overdue session sits at top of the worklist). Predicate:
  ///   sessions.user_id   = current clinician
  ///   sessions.status    = 'draft'
  ///   sessions.deleted_at IS NULL
  /// The client name is embedded via the `sessions.client_id →
  /// clients.id` FK (sessions_client_id_fkey).
  /// Phase 4.1.8 — consequence triage. The ONLY verified consequence
  /// signal in today's data model is `clients.engagement_status =
  /// 'in_assessment'`: a draft session for an assessment-phase client
  /// usually feeds into a report cycle the SLP can't sit on. All five
  /// other candidate signals from the recon (upcoming scheduled
  /// session, report period, pending goal decision, clinic cadence,
  /// next-contact proxy) had no reliable data source and are NOT used.
  ///
  /// Sort: rows with a verified consequence signal sort above
  /// no-signal rows. Within each tier, ascending by waitingSince
  /// (the cadence-NEUTRAL tiebreaker — surfaced in the UI as the
  /// session date, never as judgment language).
  Future<List<DraftSessionEntry>> listDraftSessions() async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) return const <DraftSessionEntry>[];
    final rows = await _client
        .from('sessions')
        .select('id, client_id, date, duration_minutes, '
            'created_at, updated_at, '
            'clients(name, engagement_type, engagement_status)')
        .eq('user_id', uid)
        .eq('status', 'draft')
        .isFilter('deleted_at', null);

    final out = <DraftSessionEntry>[];
    for (final r in rows as List) {
      final m = Map<String, dynamic>.from(r as Map);
      final clientMap = m['clients'] is Map
          ? Map<String, dynamic>.from(m['clients'] as Map)
          : const <String, dynamic>{};
      final rawName = (clientMap['name'] as String?) ?? '';
      final engagementType =
          (clientMap['engagement_type'] as String?)?.trim() ?? '';
      final engagementStatus =
          (clientMap['engagement_status'] as String?)?.trim() ?? '';
      final idRaw = m['id'];
      final id = idRaw is num
          ? idRaw.toInt()
          : int.tryParse((idRaw ?? '').toString()) ?? 0;

      // Apply the ONLY verified consequence rule from Phase 4.1.8
      // recon (Part 0.2). Everything else falls through to
      // ConsequenceSignal.none — including drafts for active therapy
      // clients, which are the bulk of the prototype today.
      final signal = (engagementStatus == 'in_assessment' &&
              engagementType == 'assessment_only')
          ? ConsequenceSignal.inAssessment
          : ConsequenceSignal.none;

      out.add(DraftSessionEntry(
        id: id,
        clientId: (m['client_id'] ?? '').toString(),
        clientName: NameFormatter.displayName(rawName),
        sessionDate: _parseDate(m['date']),
        durationMinutes: (m['duration_minutes'] as num?)?.toInt(),
        createdAt: _parseTimestamp(m['created_at']) ??
            DateTime.fromMillisecondsSinceEpoch(0),
        updatedAt: _parseTimestamp(m['updated_at']) ??
            DateTime.fromMillisecondsSinceEpoch(0),
        consequenceSignal: signal,
      ));
    }

    // Sort: consequence rows above neutral rows (primary key). Within
    // each tier, ascending by waitingSince — the session's own date if
    // present, otherwise updated_at. This is a stable tiebreaker, NOT
    // an urgency claim; the UI renders the date plainly with no
    // overdue / late / urgent language.
    out.sort((a, b) {
      final rankCmp = a.consequenceRank.compareTo(b.consequenceRank);
      if (rankCmp != 0) return rankCmp;
      final aKey = a.sessionDate ?? a.updatedAt;
      final bKey = b.sessionDate ?? b.updatedAt;
      return aKey.compareTo(bKey);
    });
    return out;
  }

  /// Therapy-engagement clients only — assessment-only cases live under
  /// the Assessing sidebar. Soft-deleted rows excluded.
  ///
  /// In release builds, fixtures are excluded at the query level. If the
  /// is_fixture column is not present yet (migration 20260514120000
  /// unapplied) the select throws PostgrestException; we fall back to a
  /// column-free select so the screen keeps working pre-migration.
  Future<List<Map<String, dynamic>>> _fetchClients() async {
    try {
      var query = _client
          .from('clients')
          .select('$_clientCols, is_fixture')
          .isFilter('deleted_at', null)
          .eq('engagement_type', 'therapy');
      if (kReleaseMode) {
        query = query.eq('is_fixture', false);
      }
      final rows = await query;
      return List<Map<String, dynamic>>.from(rows as List);
    } on PostgrestException {
      final rows = await _client
          .from('clients')
          .select(_clientCols)
          .isFilter('deleted_at', null)
          .eq('engagement_type', 'therapy');
      return List<Map<String, dynamic>>.from(rows as List);
    }
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

/// Page-level result of [ClientsRosterService.loadRoster].
class RosterLoadResult {
  final List<ClientRosterEntry> entries;

  /// Sessions with status='draft' for the clinician — drives the
  /// Clients action line's second branch.
  final int draftSessionCount;

  /// Debug-only: how many fixture clients are visible in the list.
  /// Always 0 in release builds (fixtures are filtered out there).
  final int fixtureVisibleCount;

  const RosterLoadResult({
    required this.entries,
    required this.draftSessionCount,
    required this.fixtureVisibleCount,
  });
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
  final bool isFixture;
  final int sessionsCount;
  final int activeGoalsCount;
  final DateTime? lastSessionDate;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime lastTouchedAt;

  /// Original Supabase row, forwarded to ClientProfileScreen so the row
  /// click is single-frame (no re-fetch through the deep-link loader).
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
    required this.isFixture,
    required this.sessionsCount,
    required this.activeGoalsCount,
    required this.lastSessionDate,
    required this.createdAt,
    required this.updatedAt,
    required this.lastTouchedAt,
    required this.rawRow,
  });

  String get displayName => NameFormatter.displayName(rawName);

  bool get isActive => engagementStatus == 'active';
  bool get isDischarged => engagementStatus == 'discharged';
  bool get isNew => sessionsCount == 0;

  /// Inline secondary line next to the name: "30 · stroke" / "5 · AAC".
  /// Null parts dropped, middle-dot joined.
  String get metaLine {
    final parts = <String>[];
    if (age != null) parts.add('$age');
    final dx = diagnosis?.trim();
    if (dx != null && dx.isNotEmpty) parts.add(dx);
    return parts.join(' · ');
  }

  /// Whole days between enrollment (created_at) and now.
  int get daysSinceEnrolled {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final enrolled =
        DateTime(createdAt.year, createdAt.month, createdAt.day);
    final d = today.difference(enrolled).inDays;
    return d < 0 ? 0 : d;
  }

  /// A client is stale when their most recent session is more than 14
  /// days old. Clients with no sessions are not stale — they read as
  /// "baseline pending", a different state.
  bool get isStale14d {
    final s = lastSessionDate;
    if (s == null) return false;
    return _wholeDaysAgo(s) > 14;
  }

  /// Uppercase first segment of the diagnosis, for the clinical state
  /// line's domain word. Null when there is no diagnosis.
  String? get domainWord {
    final dx = diagnosis?.trim();
    if (dx == null || dx.isEmpty) return null;
    return dx.split(RegExp(r'\s+')).first.toUpperCase();
  }

  /// Reference date for "last seen" / recency — the last session, or
  /// enrollment date when there are no sessions yet.
  DateTime get recencyRef => lastSessionDate ?? createdAt;

  /// "today" / "yesterday" / "{n} days ago" / "{n} weeks ago".
  String get recencyLong => _relative(recencyRef, short: false);

  /// "today" / "yesterday" / "{n}d ago" / "{n}w ago".
  String get recencyShort => _relative(recencyRef, short: true);

  static int _wholeDaysAgo(DateTime ref) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final refDay = DateTime(ref.year, ref.month, ref.day);
    return today.difference(refDay).inDays;
  }

  static String _relative(DateTime ref, {required bool short}) {
    final d = _wholeDaysAgo(ref);
    if (d <= 0) return 'today';
    if (d == 1) return 'yesterday';
    if (d < 14) return short ? '${d}d ago' : '$d days ago';
    final w = (d / 7).floor();
    return short ? '${w}w ago' : '$w weeks ago';
  }
}

/// Phase 4.1.8 — consequence signal applied to a draft session. The
/// recon (Part 0) verified exactly one signal in today's data model:
/// the draft's client is in active assessment (`engagement_status =
/// 'in_assessment'`). Five other candidate signals (upcoming session,
/// report cycle, pending goal decision, clinic cadence, next-contact
/// proxy) had no reliable data source and are NOT represented here.
/// Adding more enum values without a verified data source is the
/// exact failure mode this phase is designed against — only extend
/// when a new data path is proven real.
enum ConsequenceSignal { inAssessment, none }

extension ConsequenceSignalX on ConsequenceSignal {
  /// Sort order — lower rank sorts FIRST. Consequence rows are 0;
  /// neutral rows are 1.
  int get rank {
    switch (this) {
      case ConsequenceSignal.inAssessment:
        return 0;
      case ConsequenceSignal.none:
        return 1;
    }
  }

  /// Short neutral phrase shown as a chip on the row. Plain factual
  /// label — no urgency adjectives, no alarm color. Returns null when
  /// no chip should render (routine drafts).
  String? get chipLabel {
    switch (this) {
      case ConsequenceSignal.inAssessment:
        return 'Assessment case';
      case ConsequenceSignal.none:
        return null;
    }
  }
}

/// Phase 4.1.7 — row shape for the Inbox worklist. One entry per draft
/// session belonging to the signed-in clinician (the same query whose
/// `.length` drives the Clients action-line banner count).
///
/// Phase 4.1.8 — carries the verified [consequenceSignal] used by the
/// Inbox sort + chip render.
class DraftSessionEntry {
  /// `sessions.id` — primary key. The Inbox row tap routes to
  /// `/sessions/<id>/edit`, which resolves to the existing
  /// SessionCaptureScreen in edit mode via main.dart's onGenerateRoute.
  final int id;
  final String clientId;
  /// Already passed through NameFormatter.displayName so the screen can
  /// render it directly.
  final String clientName;
  /// `sessions.date` — the date the session occurred (nullable).
  final DateTime? sessionDate;
  final int? durationMinutes;
  /// `sessions.created_at` — when the draft row was inserted.
  final DateTime createdAt;
  /// `sessions.updated_at` — last auto-save tick.
  final DateTime updatedAt;
  /// Phase 4.1.8 — verified consequence tier. Currently has two values
  /// (inAssessment / none) backed by Part 0.2 recon.
  final ConsequenceSignal consequenceSignal;

  const DraftSessionEntry({
    required this.id,
    required this.clientId,
    required this.clientName,
    required this.sessionDate,
    required this.durationMinutes,
    required this.createdAt,
    required this.updatedAt,
    this.consequenceSignal = ConsequenceSignal.none,
  });

  /// Cadence-neutral tiebreaker — the session's own date if present,
  /// otherwise updated_at. The UI renders this date plainly and never
  /// dresses it as overdue / late / urgent.
  DateTime get waitingSince => sessionDate ?? updatedAt;

  int get consequenceRank => consequenceSignal.rank;
}
