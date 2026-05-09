// lib/screens/client_roster_screen.dart
//
// Phase 4.0.9-step-B-roster-surface-2 — full replacement of the Phase 3.2
// CRM-style + "needs you" roster. Surface 2 is a clean breathing
// recency-sorted list with search, prominent numerics, and a quiet
// new-client signal.
//
// Founder direction (locked in step B spec, revised in amend #3):
//   • Single recency-sorted list (no sectional grouping). "Assessment
//     is an event, not a state" → no In-assessment filter.
//   • No cuttlefish on the main surface (amend #3). Identity-mark
//     consistency across surfaces was a design value, but Roster is
//     a working library — different job from Today's ritual surface,
//     and the cuttlefish kept competing with the page header for
//     attention. She earns her place on Today; future surfaces decide
//     independently whether she belongs. The empty-state still keeps
//     the 96px softWave cuttlefish — that screen IS a quasi-ritual
//     moment ("welcome to your case file") with no content to fight.
//   • Page identity: italic Iowan H1 "Everyone in your care." at 44px.
//   • Summary plaque: 3 numerics (Total / Active goals / Sessions).
//   • Search-first row with ⌘K hint + dark-navy "New client" CTA.
//   • Filter chips: All / Active / Discharged. Counts in Inter.
//   • Each row: olive stripe + Iowan name + Inter focus strip + Inter
//     weight 700 numerics + Inter recency stack + Inter sentence-case
//     state pill. Conditional italic "Just enrolled" when sessions=0.
//   • "Today" recency in amber — single amber moment per surface.
//   • Numerics are LOAD-BEARING. Tabular figures across data tokens
//     and summary plaque so columns align when stacked.
//
// Navigation: row click forwards the pre-loaded client row to
// ClientProfileScreen via MaterialPageRoute with
// RouteSettings(name: '/clients/:id'). URL bar still reflects the
// path (deep-link refresh works via main.dart's loader); the
// pre-loaded row avoids a second DB fetch on the happy path.
//
// Data layer lives in services/clients_roster_service.dart. This
// screen does load → filter → search → render only.

import 'package:flutter/material.dart';

import '../services/clients_roster_service.dart';
import '../theme/cue_phase4_tokens.dart';
import '../theme/cue_type_v3.dart';
import '../widgets/app_layout.dart';
import '../widgets/clients_roster_empty_state.dart';
import '../widgets/clients_roster_filter_chips.dart';
import '../widgets/clients_roster_row.dart';
import '../widgets/clients_roster_search_bar.dart';
import '../widgets/clients_roster_summary_plaque.dart';
import 'add_client_screen.dart';
import 'client_profile_screen.dart';

class ClientRosterScreen extends StatefulWidget {
  const ClientRosterScreen({super.key});

  @override
  State<ClientRosterScreen> createState() => _ClientRosterScreenState();
}

class _ClientRosterScreenState extends State<ClientRosterScreen> {
  final _service = ClientsRosterService();
  final _searchCtrl = TextEditingController();

  bool _loading = true;
  String? _loadError;
  List<ClientRosterEntry> _entries = const [];
  String _query = '';
  String _filter = 'all'; // all | active | discharged
  String _sortBy = 'recent';

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

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _loadError = null;
      });
    }
    try {
      final entries = await _service.loadRoster();
      if (mounted) {
        setState(() {
          _entries = entries;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadError = '$e';
          _loading = false;
        });
      }
    }
  }

  // ── Filtering / sorting / search ────────────────────────────────────────

  List<ClientRosterEntry> get _visible {
    Iterable<ClientRosterEntry> seq = _entries;
    if (_filter == 'active') {
      seq = seq.where((e) => e.isActive);
    } else if (_filter == 'discharged') {
      seq = seq.where((e) => e.isDischarged);
    }
    if (_query.isNotEmpty) {
      seq = seq.where((e) {
        final hay = [
          e.displayName,
          e.diagnosis ?? '',
          e.primaryConcern ?? '',
        ].join(' ').toLowerCase();
        return hay.contains(_query);
      });
    }
    final list = seq.toList();
    // Sort plumbing scaffolded for future alphabetical / other sorts;
    // 'recent' is the only option in v1 and matches the service's
    // pre-sorted order — kept explicit so a re-sort after filtering
    // remains deterministic.
    if (_sortBy == 'recent') {
      list.sort((a, b) => b.lastTouchedAt.compareTo(a.lastTouchedAt));
    }
    return list;
  }

  // ── Counts for filter chips ─────────────────────────────────────────────

  int get _activeCount => _entries.where((e) => e.isActive).length;
  int get _dischargedCount =>
      _entries.where((e) => e.isDischarged).length;
  int get _totalActiveGoals =>
      _entries.fold<int>(0, (sum, e) => sum + e.activeGoalsCount);
  int get _totalSessions =>
      _entries.fold<int>(0, (sum, e) => sum + e.sessionsCount);

  // ── Navigation ──────────────────────────────────────────────────────────

  Future<void> _openClient(ClientRosterEntry e) async {
    // Pre-loaded MaterialPageRoute pattern. URL bar reflects /clients/:id
    // via RouteSettings.name; main.dart's loader handles hard refresh.
    await Navigator.push(
      context,
      MaterialPageRoute(
        settings: RouteSettings(name: '/clients/${e.id}'),
        builder: (_) => ClientProfileScreen(client: e.rawRow),
      ),
    );
    // Profile may have edited or archived the row — refresh either way.
    if (mounted) _load();
  }

  Future<void> _openAddClient() async {
    final added = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const AddClientScreen()),
    );
    if (added == true && mounted) _load();
  }

  // ── Build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    // Amend #3: cuttlefish removed from the main surface. The Stack
    // wrapper that hosted her viewport-anchor is gone; body is the
    // scrollable content directly. Empty state retains the 96px
    // softWave cuttlefish — see ClientsRosterEmptyState.
    return AppLayout(
      title: '',
      activeRoute: 'roster',
      body: _buildContent(),
    );
  }

  Widget _buildContent() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_loadError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Couldn\'t load your case file. $_loadError',
            style: CueTypeV3.body(color: kCueInkSecondary),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    if (_entries.isEmpty) {
      return ClientsRosterEmptyState(onNewClient: _openAddClient);
    }
    return ListView(
      // Page padding. Left 80 originally cleared the cuttlefish
      // column (removed in amend #3); the value is preserved as the
      // page's editorial left margin so the content doesn't drift
      // toward the sidebar. Right 56 / vertical 50/56 carry from the
      // original layout.
      padding: const EdgeInsets.fromLTRB(80, 50, 56, 56),
      children: [
        _pageHeader(),
        const SizedBox(height: 32),
        ClientsRosterSummaryPlaque(
          totalClients:   _entries.length,
          activeGoals:    _totalActiveGoals,
          sessionsLogged: _totalSessions,
        ),
        const SizedBox(height: 24),
        ClientsRosterSearchBar(
          controller: _searchCtrl,
          onNewClient: _openAddClient,
        ),
        const SizedBox(height: 16),
        ClientsRosterFilterChips(
          activeFilter:    _filter,
          onFilter:        (v) => setState(() => _filter = v),
          allCount:        _entries.length,
          activeCount:     _activeCount,
          dischargedCount: _dischargedCount,
          sortBy:          _sortBy,
          onSort:          (v) => setState(() => _sortBy = v),
        ),
        const SizedBox(height: 12),
        ..._buildList(),
        const SizedBox(height: 56),
      ],
    );
  }

  // Page header: eyebrow + italic Iowan H1 + count + tagline.
  Widget _pageHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Eyebrow — mono uppercase tracked is the data-tag carve-out;
        // page locator counts as a data tag here. Bumped twice:
        // amend #2 (10.5/500/InkTertiary → 12/600/InkSecondary) and
        // amend #4 (12/600/InkSecondary → 13.5/700/kCueInk, +0.14em
        // → +0.16em). With the cuttlefish removed in amend #3, this
        // row carries the brand identity by itself — eyebrow needs
        // to read as "this is Cue, you're in the Clients surface,"
        // not as a whisper above the H1.
        Text(
          'CUE · CLIENTS',
          style: CueTypeV3.dataEyebrow(color: kCueInk).copyWith(
            fontSize:      13.5,
            fontWeight:    FontWeight.w700,
            letterSpacing: 13.5 * 0.16,
          ),
        ),
        const SizedBox(height: 14),
        // H1 text swap in amend #2: "Your case file." →
        // "Everyone in your care." — option (e) from founder
        // brainstorm. Same Iowan italic 44/500/kCueInk register;
        // content swap only.
        Text(
          'Everyone in your care.',
          style: CueTypeV3.rosterPageTitle(),
        ),
        const SizedBox(height: 14),
        // Page count "{N} in your care" — bumped in amend #2
        // (14/400 → 16/500) so the count reads at a glance, not
        // as a throwaway line below the H1.
        Text(
          _entries.length == 1
              ? '1 in your care'
              : '${_entries.length} in your care',
          style: CueTypeV3.body(color: kCueInkSecondary).copyWith(
            fontSize:   16,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Every person, every story, in one place.',
          style: CueTypeV3.rosterPageTagline(),
        ),
      ],
    );
  }

  List<Widget> _buildList() {
    final rows = _visible;
    if (rows.isEmpty) {
      // Filter-empty messaging is filter-aware so the SLP knows whether
      // it's a search miss, an empty Active bucket, etc.
      String msg;
      if (_query.isNotEmpty) {
        msg = 'No clients match "$_query".';
      } else if (_filter == 'discharged') {
        msg = 'No discharged clients yet.';
      } else if (_filter == 'active') {
        msg = 'No active clients in this view.';
      } else {
        msg = 'No clients to show.';
      }
      return [ClientsRosterFilterEmptyState(message: msg)];
    }
    return [
      Container(
        decoration: BoxDecoration(
          color: kCueSurfaceWhite,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: kCueBorder, width: 0.5),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            for (final e in rows)
              ClientsRosterRow(
                entry: e,
                onTap: () => _openClient(e),
              ),
          ],
        ),
      ),
    ];
  }
}
