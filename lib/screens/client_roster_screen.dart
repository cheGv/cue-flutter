// lib/screens/client_roster_screen.dart
//
// The /clients screen — redesigned to the locked visual spec.
//
// Structure (top to bottom):
//   • Hero: a single italic Playfair line, "Everyone in your care."
//   • Action line (conditional): stale-client nudge, else draft-session
//     nudge, else nothing. Replaces the old three-column stat strip.
//   • Search row: search input + ⌘K hint + ghost-square "+" button.
//   • Tab row: All / Active / Discharged — zero-count tabs hidden, no
//     sort control.
//   • Client list: flat rows with hairline dividers (not cards).
//
// Tokens live in lib/theme/cue_text_styles.dart (CueTextStyles +
// CueClientsPalette). The data layer is clients_roster_service.dart;
// this screen does load → filter → search → render only.

import 'package:flutter/material.dart';

import '../animation/cue_motion.dart';
import '../constants/app_routes.dart';
import '../services/clients_roster_service.dart';
import '../theme/cue_text_styles.dart';
import '../widgets/app_layout.dart';
import '../widgets/clients_roster_empty_state.dart';
import '../widgets/clients_roster_filter_chips.dart';
import '../widgets/clients_roster_row.dart';
import '../widgets/clients_roster_search_bar.dart';
import '../widgets/cue_animated_entrance.dart';
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
  int _draftSessionCount = 0;
  int _fixtureVisibleCount = 0;
  String _query = '';

  /// 'all' | 'active' | 'discharged' | 'stale'. 'stale' is not a tab —
  /// it's set by tapping the action line and cleared by tapping a tab.
  String _filter = 'all';

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
      final result = await _service.loadRoster();
      if (mounted) {
        setState(() {
          _entries = result.entries;
          _draftSessionCount = result.draftSessionCount;
          _fixtureVisibleCount = result.fixtureVisibleCount;
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

  // ── Filtering / search / sort ───────────────────────────────────────

  List<ClientRosterEntry> get _visible {
    Iterable<ClientRosterEntry> seq = _entries;
    switch (_filter) {
      case 'active':
        seq = seq.where((e) => e.isActive);
        break;
      case 'discharged':
        seq = seq.where((e) => e.isDischarged);
        break;
      case 'stale':
        seq = seq.where((e) => e.isStale14d);
        break;
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
    // Default sort: most-recently-active.
    return seq.toList()
      ..sort((a, b) => b.lastTouchedAt.compareTo(a.lastTouchedAt));
  }

  int get _activeCount => _entries.where((e) => e.isActive).length;
  int get _dischargedCount => _entries.where((e) => e.isDischarged).length;
  int get _staleCount => _entries.where((e) => e.isStale14d).length;

  // ── Navigation ──────────────────────────────────────────────────────

  Future<void> _openClient(ClientRosterEntry e) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        settings: RouteSettings(name: '/clients/${e.id}'),
        builder: (_) => ClientProfileScreen(client: e.rawRow),
      ),
    );
    if (mounted) _load();
  }

  Future<void> _openAddClient() async {
    final added = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const AddClientScreen()),
    );
    if (added == true && mounted) _load();
  }

  // ── Build ───────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return AppLayout(
      title: '',
      activeRoute: 'roster',
      // Cap the content width on wide monitors; stays fluid below 1040.
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1040),
          child: _buildContent(),
        ),
      ),
    );
  }

  Widget _buildContent() {
    final isMobile = MediaQuery.of(context).size.width < 768;

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_loadError != null) {
      final palette = CueClientsPalette.of(context);
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            "Couldn't load your case file. $_loadError",
            textAlign: TextAlign.center,
            style: TextStyle(color: palette.textSecondary),
          ),
        ),
      );
    }
    if (_entries.isEmpty) {
      return ClientsRosterEmptyState(
        isMobile: isMobile,
        onNewClient: _openAddClient,
      );
    }

    final text = CueTextStyles.of(context, isMobile: isMobile);
    final action = _actionLineData(isMobile);

    final padding = isMobile
        ? const EdgeInsets.fromLTRB(20, 28, 20, 40)
        : const EdgeInsets.fromLTRB(80, 50, 56, 56);

    return ListView(
      padding: padding,
      children: [
        if (_fixtureVisibleCount > 0) ...[
          _devFixtureBanner(text),
          const SizedBox(height: 16),
        ],
        // Hero — one italic line, nothing else.
        CueAnimatedEntrance(
          child: Text('Everyone in your care.', style: text.hero),
        ),
        const SizedBox(height: 24),
        if (action != null) ...[
          CueAnimatedEntrance(
            delay: const Duration(milliseconds: 80),
            child: _actionLine(text, action),
          ),
          const SizedBox(height: 24),
        ],
        CueAnimatedEntrance(
          delay: const Duration(milliseconds: 160),
          child: ClientsRosterSearchBar(
            controller: _searchCtrl,
            onNewClient: _openAddClient,
          ),
        ),
        const SizedBox(height: 16),
        CueAnimatedEntrance(
          delay: const Duration(milliseconds: 240),
          child: ClientsRosterTabs(
            activeFilter: _filter,
            onFilter: (v) => setState(() => _filter = v),
            allCount: _entries.length,
            activeCount: _activeCount,
            dischargedCount: _dischargedCount,
          ),
        ),
        const SizedBox(height: 24),
        ..._buildList(isMobile),
        const SizedBox(height: 40),
      ],
    );
  }

  // ── Action line ─────────────────────────────────────────────────────

  /// Resolves the conditional action line. Priority: stale clients,
  /// then draft sessions, then nothing.
  _ActionLineData? _actionLineData(bool isMobile) {
    if (_staleCount > 0) {
      final text = isMobile
          ? '$_staleCount clients need a check-in'
          : "$_staleCount clients haven't been seen in 14+ days";
      return _ActionLineData(text, () => setState(() => _filter = 'stale'));
    }
    if (_draftSessionCount > 0) {
      return _ActionLineData(
        '$_draftSessionCount sessions waiting to be documented',
        () => Navigator.pushNamed(context, AppRoutes.inbox),
      );
    }
    return null;
  }

  Widget _actionLine(CueTextStyles text, _ActionLineData data) {
    final palette = CueClientsPalette.of(context);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: data.onTap,
        child: Container(
          padding:
              const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
          decoration: BoxDecoration(
            color: palette.actionBg,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: palette.actionBorder, width: 0.5),
          ),
          child: Row(
            children: [
              Expanded(child: Text(data.text, style: text.action)),
              const SizedBox(width: 8),
              Icon(
                Icons.chevron_right_rounded,
                size: 14,
                color: palette.amber,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── List ────────────────────────────────────────────────────────────

  List<Widget> _buildList(bool isMobile) {
    final rows = _visible;
    if (rows.isEmpty) {
      String msg;
      if (_query.isNotEmpty) {
        msg = 'No clients match "$_query".';
      } else if (_filter == 'discharged') {
        msg = 'No discharged clients yet.';
      } else if (_filter == 'active') {
        msg = 'No active clients in this view.';
      } else if (_filter == 'stale') {
        msg = 'No clients need a check-in.';
      } else {
        msg = 'No clients to show.';
      }
      return [ClientsRosterFilterEmptyState(message: msg)];
    }
    return [
      for (var i = 0; i < rows.length; i++)
        CueAnimatedEntrance(
          delay: Duration(
            milliseconds: 320 +
                (i <= kMotionStaggerMaxIndex ? i : kMotionStaggerMaxIndex) *
                    60,
          ),
          child: ClientsRosterRow(
            entry: rows[i],
            isMobile: isMobile,
            isLast: i == rows.length - 1,
            onTap: () => _openClient(rows[i]),
          ),
        ),
    ];
  }

  // ── Dev affordance ──────────────────────────────────────────────────

  /// Debug-only banner so a developer never forgets a fixture client is
  /// in the list. Never renders in release builds (the service reports
  /// fixtureVisibleCount as 0 there).
  Widget _devFixtureBanner(CueTextStyles text) {
    final palette = CueClientsPalette.of(context);
    final label = _fixtureVisibleCount == 1
        ? 'DEV · 1 FIXTURE VISIBLE'
        : 'DEV · $_fixtureVisibleCount FIXTURES VISIBLE';
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: palette.controlBorder, width: 0.5),
      ),
      child: Text(label, style: text.sectionLabel),
    );
  }
}

class _ActionLineData {
  final String text;
  final VoidCallback onTap;
  const _ActionLineData(this.text, this.onTap);
}
