// lib/screens/client_roster_screen.dart
//
// Phase 3.2 — Clients screen redesign. Brought into the same companion
// register as Today, the chart, and Cue Study. Previous incarnation was a
// CRM-style table with avatar circles, a teal Material FAB, all-caps
// names, and a destructive trash icon in every row's primary tap zone.
// This rewrite replaces that with two stacked sections:
//
//   Section 1 — "needs you"
//     A small attention block. Cue is present here in the role of noticing,
//     not greeting. Each card surfaces a SINGLE highest-priority trigger
//     per client (priority: session today → note pending → new note ready
//     → first session upcoming → long-active goal). When zero attention
//     cards exist, a calm centred resting Cue replaces the eyebrow + cards
//     and reads "Nothing pressing right now." This is the deliberate
//     moment of calm.
//
//   Section 2 — "all clients"
//     Clean vertical list (NOT a table). Title-cased name on top, "Age N ·
//     Diagnosis · last session {date}" subtitle below. Whole row tappable.
//     Search bar above the list, hidden when fewer than six clients.
//
// =====================================================================
// LANGUAGE DISCIPLINE — see CLAUDE.md §13.
//
// Cue surfaces observations, never characterizes a child / family / goal
// as deficient. FORBIDDEN here and in any future companion-register copy:
//   stuck, overdue, behind, no progress, plateau, struggling, failing,
//   regressing, slow learner, low-functioning, non-progressing, falling
//   behind, lagging, caseload health, problem child, difficult case.
//
// REQUIRED reframings:
//   - Long-active goal → "Active for N sessions — review when you have a
//     moment." (the goal owns the duration; the SLP owns the review)
//   - Pending documentation → "Note pending from {date}." (the SLP owns
//     the pending work, not the child)
//   - Absence / duration → state the number, let the SLP interpret.
// =====================================================================
//
// Destructive action moved to ClientProfileScreen's overflow sheet
// (Option A from the spec). The trash icon is gone from this screen.

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/name_formatter.dart';
import '../theme/cue_theme.dart';
import '../theme/cue_tokens.dart';
import '../theme/cue_typography.dart';
import '../widgets/app_layout.dart';
import '../widgets/cue_amber_link.dart';
import '../widgets/cue_cuttlefish.dart';
import 'add_client_screen.dart';
import 'client_profile_screen.dart';

class ClientRosterScreen extends StatefulWidget {
  const ClientRosterScreen({super.key});

  @override
  State<ClientRosterScreen> createState() => _ClientRosterScreenState();
}

// ── Attention card data ──────────────────────────────────────────────────────

enum _AttentionTrigger {
  sessionToday,        // priority 1
  notePending,         // priority 2
  newNoteReady,        // priority 3 — currently dormant (review_status TBD)
  firstSessionUpcoming, // priority 4
  longActiveGoal,      // priority 5
}

int _priorityRank(_AttentionTrigger t) {
  switch (t) {
    case _AttentionTrigger.sessionToday:         return 1;
    case _AttentionTrigger.notePending:          return 2;
    case _AttentionTrigger.newNoteReady:         return 3;
    case _AttentionTrigger.firstSessionUpcoming: return 4;
    case _AttentionTrigger.longActiveGoal:       return 5;
  }
}

class _AttentionCard {
  final String                clientId;
  final Map<String, dynamic>  client;
  final _AttentionTrigger     trigger;
  final String                copy;
  const _AttentionCard({
    required this.clientId,
    required this.client,
    required this.trigger,
    required this.copy,
  });
}

/// Bundle returned by [_buildAttentionCardsAndDates] — attention cards
/// for Section 1 plus per-client maps used by Section 2 (last-session
/// date for the subtitle, active-goal count for the right-side pill).
class _AttentionResult {
  final List<_AttentionCard>     cards;
  final Map<String, DateTime?>   lastSessionDate;
  final Map<String, int>         activeGoalCount;
  const _AttentionResult({
    required this.cards,
    required this.lastSessionDate,
    required this.activeGoalCount,
  });
}

class _ClientRosterScreenState extends State<ClientRosterScreen> {
  final _supabase   = Supabase.instance.client;
  final _searchCtrl = TextEditingController();

  bool                          _loading      = true;
  String?                       _loadError;
  List<Map<String, dynamic>>    _clients      = [];
  List<_AttentionCard>          _attention    = [];
  /// Most recent session date per client_id, derived in [_load] from the
  /// same all-sessions query used by the long-active-goal trigger. Null
  /// when no session has ever been recorded for that client.
  Map<String, DateTime?>        _lastSessionDate = const {};
  /// Active-goal count per client_id — drives the amber "{N} active" pill
  /// on each all-clients row card.
  Map<String, int>              _activeGoalCount = const {};
  String                        _query        = '';

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(() {
      final q = _searchCtrl.text.trim().toLowerCase();
      if (q != _query) setState(() => _query = q);
    });
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  // ── Load ──────────────────────────────────────────────────────────────────

  Future<void> _load() async {
    final uid = _supabase.auth.currentUser?.id;
    if (uid == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    if (mounted) {
      setState(() {
        _loading   = true;
        _loadError = null;
      });
    }

    try {
      final clients = await _fetchClients();
      // Normalise display names at the data-access layer per spec — every
      // downstream render sees a clean name.
      for (final c in clients) {
        c['name'] = NameFormatter.displayName(c['name'] as String?);
      }

      // Issue all queries in parallel here in _load(). The all-sessions
      // pull (used by long-active-goal trigger) doubles as the source for
      // last-session-date in the all-clients list — one query, two outputs.
      final attention =
          await _buildAttentionCardsAndDates(uid: uid, clients: clients);

      if (mounted) {
        setState(() {
          _clients         = clients;
          _attention       = attention.cards;
          _lastSessionDate = attention.lastSessionDate;
          _activeGoalCount = attention.activeGoalCount;
          _loading         = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadError = '$e';
          _loading   = false;
        });
      }
    }
  }

  Future<List<Map<String, dynamic>>> _fetchClients() async {
    final response = await _supabase
        .from('clients')
        .select()
        .isFilter('deleted_at', null)
        .order('name', ascending: true);
    return List<Map<String, dynamic>>.from(response);
  }

  // ── Attention card pipeline ──────────────────────────────────────────────

  Future<_AttentionResult> _buildAttentionCardsAndDates({
    required String uid,
    required List<Map<String, dynamic>> clients,
  }) async {
    final clientById = <String, Map<String, dynamic>>{
      for (final c in clients) c['id'].toString(): c,
    };
    final clientIds = clientById.keys.toList();
    if (clientIds.isEmpty) {
      return const _AttentionResult(
        cards: [], lastSessionDate: {}, activeGoalCount: {});
    }

    final today      = DateTime.now();
    final todayStr   = _ymd(today);
    final threeDays  = _ymd(today.subtract(const Duration(days: 3)));
    final nextWeek   = _ymd(today.add(const Duration(days: 7)));

    // Five queries in parallel. review_status (Trigger 3) requires schema
    // we don't have — see CLAUDE.md §12; that branch is dormant for now.
    final results = await Future.wait<dynamic>([
      // (a) Sessions in last 3 days with no documentation — Trigger 2
      _supabase
          .from('sessions')
          .select('id, client_id, date, soap_note, notes, created_at')
          .eq('user_id', uid)
          .gte('date', threeDays)
          .lte('date', todayStr)
          .order('date', ascending: false),
      // (b) Today's daily_roster — Trigger 1
      _supabase
          .from('daily_roster')
          .select('id, client_id, session_date, session_documented')
          .eq('clinician_id', uid)
          .eq('session_date', todayStr),
      // (c) Daily_roster within next 7 days — Trigger 4 (filtered against
      // total_sessions = 0 in memory below).
      _supabase
          .from('daily_roster')
          .select('id, client_id, session_date')
          .eq('clinician_id', uid)
          .gte('session_date', todayStr)
          .lte('session_date', nextWeek),
      // (d) Active long-term goals — Trigger 5. We fetch all and pair them
      // with a session-count query in memory.
      _supabase
          .from('long_term_goals')
          .select('id, client_id, status, created_at')
          .eq('user_id', uid)
          .eq('status', 'active'),
      // (e) Sessions ordered by date for long-active count — bounded by
      // any active goal's earliest created_at, so we don't overscan.
      _supabase
          .from('sessions')
          .select('id, client_id, date')
          .eq('user_id', uid),
    ]);

    final undocumentedRows =
        (results[0] as List).map((r) => Map<String, dynamic>.from(r as Map)).toList();
    final todayRosterRows =
        (results[1] as List).map((r) => Map<String, dynamic>.from(r as Map)).toList();
    final upcomingRosterRows =
        (results[2] as List).map((r) => Map<String, dynamic>.from(r as Map)).toList();
    final activeGoalRows =
        (results[3] as List).map((r) => Map<String, dynamic>.from(r as Map)).toList();
    final allSessionRows =
        (results[4] as List).map((r) => Map<String, dynamic>.from(r as Map)).toList();

    // Per-client triggers go into a map; the highest-priority wins per
    // client when multiple fire.
    final byClient = <String, _AttentionCard>{};

    void offer(_AttentionCard card) {
      final existing = byClient[card.clientId];
      if (existing == null ||
          _priorityRank(card.trigger) < _priorityRank(existing.trigger)) {
        byClient[card.clientId] = card;
      }
    }

    // Trigger 1 — Session today.
    for (final r in todayRosterRows) {
      final cid = r['client_id']?.toString();
      if (cid == null) continue;
      final c = clientById[cid];
      if (c == null) continue;
      // session_time isn't part of the schema — the conditional sits ready
      // for a later schema addition.
      final timeStr = r['session_time'] as String?;
      final tail    = (timeStr != null && timeStr.isNotEmpty)
          ? ' at $timeStr'
          : '';
      offer(_AttentionCard(
        clientId: cid,
        client:   c,
        trigger:  _AttentionTrigger.sessionToday,
        copy:     'Session today$tail.',
      ));
    }

    // Trigger 2 — Note pending. Group by client_id, take the most recent.
    final mostRecentUndoc = <String, Map<String, dynamic>>{};
    for (final s in undocumentedRows) {
      final soap  = (s['soap_note'] as String?)?.trim();
      final notes = (s['notes']     as String?)?.trim();
      final hasNote = (soap != null && soap.isNotEmpty) ||
                      (notes != null && notes.isNotEmpty);
      if (hasNote) continue;
      final cid = s['client_id']?.toString();
      if (cid == null) continue;
      mostRecentUndoc.putIfAbsent(cid, () => s);
    }
    for (final entry in mostRecentUndoc.entries) {
      final c = clientById[entry.key];
      if (c == null) continue;
      final dateStr = (entry.value['date'] as String?) ??
          (entry.value['created_at'] as String?)?.substring(0, 10);
      final dt = _safeParseDate(dateStr);
      if (dt == null) continue;
      offer(_AttentionCard(
        clientId: entry.key,
        client:   c,
        trigger:  _AttentionTrigger.notePending,
        copy:     'Note pending from ${_relativePast(dt, today)}.',
      ));
    }

    // Trigger 3 — New note ready (review_status). Dormant until schema.
    // see CLAUDE.md §12 — Phase 3.2-review-status-trigger.

    // Trigger 4 — First session upcoming.
    for (final r in upcomingRosterRows) {
      final cid = r['client_id']?.toString();
      if (cid == null) continue;
      final c = clientById[cid];
      if (c == null) continue;
      // Only fires if the client has had zero sessions ever.
      final totalRaw = c['total_sessions'];
      final total = totalRaw is int
          ? totalRaw
          : (totalRaw is String ? int.tryParse(totalRaw) : null);
      if (total == null || total > 0) continue;
      final whenStr = r['session_date'] as String?;
      final when = _safeParseDate(whenStr);
      if (when == null) continue;
      offer(_AttentionCard(
        clientId: cid,
        client:   c,
        trigger:  _AttentionTrigger.firstSessionUpcoming,
        copy:     'First session ${_relativeFuture(when, today)}.',
      ));
    }

    // Trigger 5 — Long-active goal.
    final sessionsByClient = <String, List<DateTime>>{};
    for (final s in allSessionRows) {
      final cid = s['client_id']?.toString();
      if (cid == null) continue;
      final dt = _safeParseDate(s['date'] as String?);
      if (dt == null) continue;
      (sessionsByClient[cid] ??= []).add(dt);
    }
    // Track max session count per client across active goals — one card
    // per client, whichever active goal has the highest count wins.
    final longActiveByClient = <String, int>{};
    for (final g in activeGoalRows) {
      final cid     = g['client_id']?.toString();
      final created = _safeParseDate(g['created_at'] as String?);
      if (cid == null || created == null) continue;
      final list = sessionsByClient[cid] ?? const <DateTime>[];
      final n = list.where((d) => !d.isBefore(created)).length;
      if (n <= 15) continue;
      longActiveByClient[cid] =
          (longActiveByClient[cid] ?? 0) > n ? longActiveByClient[cid]! : n;
    }
    for (final entry in longActiveByClient.entries) {
      final c = clientById[entry.key];
      if (c == null) continue;
      offer(_AttentionCard(
        clientId: entry.key,
        client:   c,
        trigger:  _AttentionTrigger.longActiveGoal,
        copy: 'Active for ${entry.value} sessions — '
              'review when you have a moment.',
      ));
    }

    // Stable order: priority asc, then client name.
    final list = byClient.values.toList()
      ..sort((a, b) {
        final p = _priorityRank(a.trigger).compareTo(_priorityRank(b.trigger));
        if (p != 0) return p;
        return ((a.client['name'] as String?) ?? '')
            .compareTo((b.client['name'] as String?) ?? '');
      });

    // Derive last-session-date per client from sessionsByClient (same data
    // we already have for the long-active-goal trigger).
    final lastDate = <String, DateTime?>{
      for (final cid in clientIds) cid: null,
    };
    sessionsByClient.forEach((cid, dates) {
      if (dates.isEmpty) return;
      DateTime newest = dates.first;
      for (final d in dates) {
        if (d.isAfter(newest)) newest = d;
      }
      lastDate[cid] = newest;
    });

    // Active-goal count per client — derived from the same activeGoalRows
    // query already issued above. No extra round-trip.
    final activeCount = <String, int>{};
    for (final g in activeGoalRows) {
      final cid = g['client_id']?.toString();
      if (cid == null) continue;
      activeCount[cid] = (activeCount[cid] ?? 0) + 1;
    }

    return _AttentionResult(
      cards:           list,
      lastSessionDate: lastDate,
      activeGoalCount: activeCount,
    );
  }

  // ── Date helpers ─────────────────────────────────────────────────────────

  String _ymd(DateTime d) =>
      '${d.year.toString().padLeft(4, "0")}-'
      '${d.month.toString().padLeft(2, "0")}-'
      '${d.day.toString().padLeft(2, "0")}';

  DateTime? _safeParseDate(String? s) {
    if (s == null || s.isEmpty) return null;
    try { return DateTime.parse(s); } catch (_) { return null; }
  }

  bool _isSameDate(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  /// Past: "yesterday" / "2 days ago" / weekday name within 7d / "12 Aug".
  String _relativePast(DateTime d, DateTime ref) {
    if (_isSameDate(d, ref)) return 'today';
    final yesterday = ref.subtract(const Duration(days: 1));
    if (_isSameDate(d, yesterday)) return 'yesterday';
    final delta = ref.difference(d).inDays;
    if (delta > 1 && delta < 7) return _weekdayName(d.weekday);
    return _shortDate(d);
  }

  /// Future: "tomorrow" / "this Friday" (within 7d) / "in N days".
  String _relativeFuture(DateTime d, DateTime ref) {
    if (_isSameDate(d, ref)) return 'today';
    final tomorrow = ref.add(const Duration(days: 1));
    if (_isSameDate(d, tomorrow)) return 'tomorrow';
    final delta = d.difference(ref).inDays;
    if (delta > 1 && delta <= 6) return 'this ${_weekdayName(d.weekday)}';
    return 'in $delta days';
  }

  String _weekdayName(int weekday) {
    const names = [
      '', 'Monday', 'Tuesday', 'Wednesday', 'Thursday',
      'Friday', 'Saturday', 'Sunday',
    ];
    return names[weekday];
  }

  String _shortDate(DateTime d) {
    const months = [
      '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${d.day} ${months[d.month]}';
  }

  // ── Navigation ───────────────────────────────────────────────────────────

  Future<void> _openAddClient() async {
    final added = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const AddClientScreen()),
    );
    if (added == true) _load();
  }

  Future<void> _openClient(Map<String, dynamic> client) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ClientProfileScreen(client: client),
      ),
    );
    // ClientProfileScreen may pop after a delete and may have edited the
    // client. Refresh either way — the cost is one query batch.
    _load();
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    // The "+ Add client" pill rides in the AppLayout TopBar only when
    // the attention block is in calm-empty state — there's no eyebrow row
    // to host it. When attention cards exist, the pill is inline with the
    // "needs you" eyebrow row (mirrors Today's "+ add session" affordance).
    final pillInTopBar = !_loading && _loadError == null && _attention.isEmpty;

    return AppLayout(
      title:       'Clients',
      activeRoute: 'roster',
      actions: pillInTopBar
          ? [_buildAddPill(), const SizedBox(width: CueGap.s12)]
          : const <Widget>[],
      body: _loading
          ? Center(
              child: CircularProgressIndicator(
                  strokeWidth: CueSize.spinnerStroke,
                  color:       CueColors.amber),
            )
          : _loadError != null
              ? _buildError()
              : LayoutBuilder(
                  builder: (ctx, constraints) {
                    final hPad = constraints.maxWidth > 700 ? 48.0 : 24.0;
                    return ListView(
                      padding: EdgeInsets.fromLTRB(hPad, CueGap.s32, hPad, 96),
                      children: [
                        _buildAttentionSection(),
                        const SizedBox(height: CueGap.cardToEyebrow),
                        _buildAllClientsSection(),
                      ],
                    );
                  },
                ),
    );
  }

  Widget _buildError() {
    return Padding(
      padding: const EdgeInsets.all(CueGap.s24),
      child: Center(
        child: Text(
          'Could not load clients: $_loadError',
          textAlign: TextAlign.center,
          style: CueType.bodyMedium
              .copyWith(color: CueColors.inkPrimary),
        ),
      ),
    );
  }

  // ── + Add client pill (used in two placements: TopBar action when calm,
  //    inline with "needs you" eyebrow when cards exist). Same dark-ink
  //    CTA register as Today's "Start session →".
  Widget _buildAddPill() {
    return GestureDetector(
      onTap: _openAddClient,
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: CueGap.s16, vertical: CueGap.s8),
        decoration: BoxDecoration(
          color:        CueColors.inkPrimary,
          borderRadius: BorderRadius.circular(CueRadius.s8),
        ),
        child: Text(
          '+ Add client',
          style: CueType.custom(
            fontSize: 13,
            weight:   FontWeight.w600,
            color:    Colors.white,
          ),
        ),
      ),
    );
  }

  // ── Section 1 — needs you ────────────────────────────────────────────────

  Widget _buildAttentionSection() {
    if (_attention.isEmpty) return _buildCalmMoment();

    // crossAxisAlignment.stretch makes attention cards span the full
    // content width (matches Today's session card / chart's brief card).
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Eyebrow row: 20px companion cuttlefish + lowercase "needs you" +
        // trailing "+ Add client" pill, mirroring Today's pattern.
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const SizedBox(
              width:  CueSize.cuttlefishAttention,
              height: CueSize.cuttlefishAttentionSlot,
              child: CueCuttlefish(
                  size: CueSize.cuttlefishAttention, state: CueState.idle),
            ),
            const SizedBox(width: CueGap.s12),
            Expanded(
              child: Text(
                'needs you',
                style: CueType.bodySmall.copyWith(
                  color: CueColors.inkPrimary
                      .withValues(alpha: CueAlpha.eyebrowText),
                ),
              ),
            ),
            _buildAddPill(),
          ],
        ),
        const SizedBox(height: CueGap.eyebrowToCard),
        ..._attention.asMap().entries.map((e) => Padding(
              padding: EdgeInsets.only(
                bottom: e.key == _attention.length - 1
                    ? 0
                    : CueGap.sessionCardGap,
              ),
              child: _buildAttentionCardWidget(e.value),
            )),
      ],
    );
  }

  Widget _buildCalmMoment() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: CueGap.s32),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CueCuttlefish(
                size: 64, state: CueState.resting),
            const SizedBox(height: CueGap.s16),
            Text(
              'Nothing pressing right now.',
              textAlign: TextAlign.center,
              style: CueType.custom(
                fontSize: 14,
                weight:   FontWeight.w400,
                color: CueColors.inkPrimary
                    .withValues(alpha: CueAlpha.bodyText),
                height: 1.45,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAttentionCardWidget(_AttentionCard card) {
    final clientName = (card.client['name'] as String?) ?? 'Unknown';

    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: CueGap.s16, vertical: CueGap.s20),
      decoration: BoxDecoration(
        color:        Colors.white,
        border:       Border.all(
            color: CueColors.divider, width: CueSize.hairline),
        borderRadius: BorderRadius.circular(CueRadius.s16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            clientName,
            style: CueType.custom(
              fontSize:      18,
              weight:        FontWeight.w500,
              color:         CueColors.inkPrimary,
              letterSpacing: -0.3,
              height:        1.3,
            ),
          ),
          const SizedBox(height: CueGap.s8),
          Text(
            card.copy,
            style: CueType.custom(
              fontSize: 14,
              weight:   FontWeight.w400,
              color: CueColors.inkPrimary
                  .withValues(alpha: CueAlpha.bodyText),
              height:   1.45,
            ),
          ),
          const SizedBox(height: CueGap.s12),
          CueAmberLink(
            label: 'open chart',
            onTap: () => _openClient(card.client),
          ),
        ],
      ),
    );
  }

  // ── Section 2 — all clients ──────────────────────────────────────────────

  Widget _buildAllClientsSection() {
    final filtered = _query.isEmpty
        ? _clients
        : _clients
            .where((c) => ((c['name'] as String?) ?? '')
                .toLowerCase()
                .contains(_query))
            .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'all clients',
          style: CueType.bodySmall.copyWith(
            color: CueColors.inkPrimary
                .withValues(alpha: CueAlpha.eyebrowText),
          ),
        ),
        const SizedBox(height: CueGap.eyebrowToCard),
        if (_clients.length >= 6) ...[
          _buildSearchInput(),
          const SizedBox(height: CueGap.searchBarToList),
        ],
        if (_clients.isEmpty)
          _buildEmptyAllClients()
        else if (filtered.isEmpty)
          _buildNoMatches()
        else
          _AllClientsList(
            clients:         filtered,
            lastSessionDate: _lastSessionDate,
            activeGoalCount: _activeGoalCount,
            onTap:           _openClient,
            shortDate:       _shortDate,
          ),
      ],
    );
  }

  Widget _buildSearchInput() {
    return Container(
      decoration: BoxDecoration(
        border:       Border.all(
            color: CueColors.divider, width: CueSize.hairline),
        borderRadius: BorderRadius.circular(CueRadius.s8),
        color:        Colors.white,
      ),
      padding: const EdgeInsets.symmetric(
          horizontal: CueGap.s12, vertical: CueGap.s8),
      child: TextField(
        controller: _searchCtrl,
        style: CueType.bodyMedium
            .copyWith(color: CueColors.inkPrimary),
        decoration: InputDecoration(
          hintText: 'Search clients...',
          hintStyle: CueType.bodyMedium.copyWith(
            color: CueColors.inkPrimary
                .withValues(alpha: CueAlpha.subtitleText),
          ),
          border:        InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          isDense:       true,
          contentPadding: EdgeInsets.zero,
        ),
      ),
    );
  }

  Widget _buildEmptyAllClients() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: CueGap.s24),
      child: Text(
        'No clients yet — tap “+ Add client” to start your roster.',
        textAlign: TextAlign.center,
        style: CueType.bodyMedium.copyWith(
          color: CueColors.inkPrimary
              .withValues(alpha: CueAlpha.bodyText),
        ),
      ),
    );
  }

  Widget _buildNoMatches() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: CueGap.s16),
      child: Text(
        'No clients match “${_searchCtrl.text}”.',
        style: CueType.bodyMedium.copyWith(
          color: CueColors.inkPrimary
              .withValues(alpha: CueAlpha.bodyText),
        ),
      ),
    );
  }
}

// ── All-clients list widget ─────────────────────────────────────────────────

typedef _DateFormatter = String Function(DateTime d);

/// Phase 3.2.1 — each all-clients row is now its own white card.
/// Left column: name + subtitle. Right side: amber "{N} active" pill,
/// suppressed when N is zero. Whole card tappable. Hover state on web
/// shifts the surface to a paper tone via [CueColors.surface].
class _AllClientsList extends StatefulWidget {
  final List<Map<String, dynamic>>         clients;
  final Map<String, DateTime?>             lastSessionDate;
  final Map<String, int>                   activeGoalCount;
  final ValueChanged<Map<String, dynamic>> onTap;
  final _DateFormatter                     shortDate;

  const _AllClientsList({
    required this.clients,
    required this.lastSessionDate,
    required this.activeGoalCount,
    required this.onTap,
    required this.shortDate,
  });

  @override
  State<_AllClientsList> createState() => _AllClientsListState();
}

class _AllClientsListState extends State<_AllClientsList> {
  String? _hoverId;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < widget.clients.length; i++) ...[
          _buildRowCard(widget.clients[i]),
          if (i != widget.clients.length - 1)
            const SizedBox(height: CueGap.s8),
        ],
      ],
    );
  }

  Widget _buildRowCard(Map<String, dynamic> client) {
    final id   = client['id']?.toString() ?? '';
    final name = (client['name'] as String?) ?? 'Unknown';

    final ageRaw   = client['age'];
    final age      = ageRaw is int
        ? ageRaw
        : (ageRaw is String ? int.tryParse(ageRaw) : null);
    final dxRaw    = (client['diagnosis'] as String?)?.trim();
    final lastDate = widget.lastSessionDate[id];

    final goalN = widget.activeGoalCount[id] ?? 0;

    // Hover treatment: white surface stays. Border darkens (ink @ 0.12)
    // and a quiet shadow (ink @ 0.04, blur 8, offset 0,2) lifts the row.
    // No surface flip — the row reads as pickup-able without going loud.
    final isHovering = _hoverId == id;
    final borderColor = isHovering
        ? CueColors.inkPrimary.withValues(alpha: CueAlpha.hoverBorder)
        : CueColors.divider;
    final shadow = isHovering
        ? <BoxShadow>[
            BoxShadow(
              color: CueColors.inkPrimary
                  .withValues(alpha: CueAlpha.hoverFill),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ]
        : const <BoxShadow>[];

    return MouseRegion(
      onEnter: (_) => setState(() => _hoverId = id),
      onExit:  (_) {
        if (_hoverId == id) setState(() => _hoverId = null);
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => widget.onTap(client),
        child: Container(
          decoration: BoxDecoration(
            color:        Colors.white,
            border:       Border.all(
                color: borderColor, width: CueSize.hairline),
            borderRadius: BorderRadius.circular(CueRadius.s16),
            boxShadow:    shadow,
          ),
          padding: const EdgeInsets.symmetric(
              horizontal: CueGap.s16, vertical: CueGap.s12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Name row — recency dot + gap + name. The Row's
                    // CrossAxisAlignment.center lines the dot up with the
                    // name's text height (the spec asks for vertical
                    // centering with the FIRST line, not the whole row).
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        _RecencyDot(lastSession: lastDate),
                        const SizedBox(width: CueGap.dotToName),
                        Expanded(
                          child: Text(
                            name,
                            style: CueType.custom(
                              fontSize:      16,
                              weight:        FontWeight.w500,
                              color:         CueColors.inkPrimary,
                              letterSpacing: -0.2,
                              height:        1.3,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (age != null && age > 0 ||
                        (dxRaw != null && dxRaw.isNotEmpty) ||
                        lastDate != null) ...[
                      const SizedBox(height: CueGap.s4),
                      // Subtitle indented to align under the name (past
                      // the dot gutter + dotToName gap).
                      Padding(
                        padding: const EdgeInsets.only(
                            left: CueSize.recencyDot + CueGap.dotToName),
                        child: _buildSubtitleRich(
                          age:      age,
                          dx:       dxRaw,
                          lastDate: lastDate,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (goalN > 0) ...[
                const SizedBox(width: CueGap.s12),
                _ActiveGoalPill(count: goalN),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// Phase 3.2.2 — subtitle as rich text. Age + Diagnosis sit at the
  /// universal subtitle muting (0.55); the date — the segment that earns
  /// a glance — bumps to bodyText (0.78). Middots stay at 0.55 so they
  /// recede. Builds segments dynamically and gracefully drops empty ones.
  Widget _buildSubtitleRich({
    required int? age,
    required String? dx,
    required DateTime? lastDate,
  }) {
    final ink = CueColors.inkPrimary;
    final s55 = CueType.custom(
      fontSize: 13,
      weight:   FontWeight.w400,
      color:    ink.withValues(alpha: CueAlpha.subtitleText),
      height:   1.4,
    );
    final s78 = s55.copyWith(
      color: ink.withValues(alpha: CueAlpha.bodyText),
    );

    final spans = <InlineSpan>[];
    void addMiddot() {
      if (spans.isEmpty) return;
      spans.add(TextSpan(text: ' · ', style: s55));
    }

    if (age != null && age > 0) {
      spans.add(TextSpan(text: 'Age $age', style: s55));
    }
    if (dx != null && dx.isNotEmpty) {
      addMiddot();
      spans.add(TextSpan(text: dx, style: s55));
    }
    if (lastDate != null) {
      addMiddot();
      spans.add(TextSpan(text: widget.shortDate(lastDate), style: s78));
    }
    if (spans.isEmpty) return const SizedBox.shrink();

    return Text.rich(TextSpan(children: spans));
  }
}

// ── Active-goal pill on each row card ────────────────────────────────────────

class _ActiveGoalPill extends StatelessWidget {
  final int count;
  const _ActiveGoalPill({required this.count});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: CueGap.s8, vertical: CueGap.s4),
      decoration: BoxDecoration(
        color: CueColors.amber.withValues(alpha: CueAlpha.softTint),
        borderRadius: BorderRadius.circular(CueRadius.s8),
      ),
      child: Text(
        '$count active',
        style: CueType.custom(
          fontSize: 12,
          weight:   FontWeight.w500,
          color:    CueColors.amber,
        ),
      ),
    );
  }
}

// ── Recency dot on each row card ─────────────────────────────────────────────
//
// Phase 3.2.2 — left-edge presence indicator. Always renders, even for
// never-seen clients (faintest tone). Color + alpha derive from days
// since [lastSession]:
//   today          → amber, alpha 1.00
//   1–7 days ago   → amber, alpha 0.50
//   8–30 days ago  → ink,   alpha 0.25
//   30+ or never   → ink,   alpha 0.10
//
// The dot is presence, not progress. It does not characterise the child;
// it tells the SLP at a glance which charts she's been near recently.

class _RecencyDot extends StatelessWidget {
  final DateTime? lastSession;
  const _RecencyDot({required this.lastSession});

  @override
  Widget build(BuildContext context) {
    final color = _resolveColor(lastSession);
    return Container(
      width:  CueSize.recencyDot,
      height: CueSize.recencyDot,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
      ),
    );
  }

  static Color _resolveColor(DateTime? last) {
    if (last == null) {
      return CueColors.inkPrimary
          .withValues(alpha: CueAlpha.recencyDormant);
    }
    final now = DateTime.now();
    final daysSince = DateTime(now.year, now.month, now.day)
        .difference(DateTime(last.year, last.month, last.day))
        .inDays;
    if (daysSince <= 0) {
      return CueColors.amber.withValues(alpha: CueAlpha.recencyToday);
    }
    if (daysSince <= 7) {
      return CueColors.amber.withValues(alpha: CueAlpha.recencyWeek);
    }
    if (daysSince <= 30) {
      return CueColors.inkPrimary
          .withValues(alpha: CueAlpha.recencyMonth);
    }
    return CueColors.inkPrimary
        .withValues(alpha: CueAlpha.recencyDormant);
  }
}
