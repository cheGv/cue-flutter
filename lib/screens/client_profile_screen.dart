// lib/screens/client_profile_screen.dart
//
// Phase 4.1.0 — Chart screen visual rebuild. The chart screen renders a
// single client's chart: identity masthead with 4 meta cards, Cue's
// editorial "what's in the chart" prose, the LTG/STG ladder with inline
// reasoning, a session-history timeline with expandable rows, and a
// floating action bar.
//
// The class name remains [ClientProfileScreen] (and the file remains
// `client_profile_screen.dart`) to keep import sites stable across the
// app. The chart screen, conceptually, is everything composed below.
//
// Data fetched once in initState:
//   • _spineFuture     — LTGs + STGs from Supabase.
//   • _sessionsFuture  — sessions for this client, newest-first.
//   • _readyFuture     — wraps both + a derived TimelineEntry list.
//   • _chartContextFuture — pre-built context string for the Cue brief.
//
// All visible cards are composed from lib/widgets/chart/* widgets so the
// chart screen itself stays a thin composition layer.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/timeline_entry.dart';
import '../services/name_formatter.dart';
import '../theme/cue_color_scheme.dart';
import '../theme/cue_theme.dart';
import '../utils/chart_context.dart';
import '../widgets/app_layout.dart';
import '../widgets/chart/chart_action_bar.dart';
import '../widgets/chart/chart_cue_editorial.dart';
import '../widgets/chart/chart_goal_ladder.dart';
import '../widgets/chart/chart_masthead.dart';
import '../widgets/chart/chart_session_history.dart';
import '../widgets/cue_hold/cue_hold_state.dart';
import '../widgets/cue_popup.dart';
import 'add_client_screen.dart';
import 'add_session_screen.dart';
import 'goal_authoring_screen.dart';
import 'timeline_route.dart';

// ── Data classes ─────────────────────────────────────────────────────────────

class _SpineData {
  final List<Map<String, dynamic>> ltgs;
  final List<Map<String, dynamic>> stgs;
  const _SpineData({required this.ltgs, required this.stgs});
}

class _ReadyData {
  final _SpineData spine;
  final List<Map<String, dynamic>> sessions;
  final List<TimelineEntry> timeline;
  const _ReadyData({
    required this.spine,
    required this.sessions,
    required this.timeline,
  });
}

// ── Screen ───────────────────────────────────────────────────────────────────

class ClientProfileScreen extends StatefulWidget {
  final Map<String, dynamic> client;
  const ClientProfileScreen({super.key, required this.client});

  @override
  State<ClientProfileScreen> createState() => _ClientProfileScreenState();
}

class _ClientProfileScreenState extends State<ClientProfileScreen> {
  final _supabase = Supabase.instance.client;

  late Future<_SpineData> _spineFuture;
  late Future<List<Map<String, dynamic>>> _sessionsFuture;
  late Future<_ReadyData> _readyFuture;
  late Future<String> _chartContextFuture;

  Map<String, dynamic> _client = const <String, dynamic>{};

  // Cue popup (⌘K) — floating reasoning panel. Not removed in 4.1.0; the
  // rebuild scope explicitly leaves the popup in place.
  bool _cuePopupOpen = false;

  // Phase 4.1.2 — when the SLP fires the "Think with Cue" pill inside a
  // focused STG, the popup opens scoped to that STG. ⌘K still opens the
  // popup with this id null (client-scoped chat).
  String? _cuePopupStgId;
  String? _cuePopupLtgId;

  // Phase 4.1.4 — chart mount fires a COMPACT Hold transition with the
  // client's first name. The label sticks for 3 seconds then reverts to
  // IDLE. Rapid chart-to-chart navigation cancels the pending revert so
  // the label updates in place without cycling through IDLE.
  Timer? _holdCompactTimer;

  @override
  void initState() {
    super.initState();
    _client = Map<String, dynamic>.from(widget.client);
    _spineFuture = _fetchSpine();
    _sessionsFuture = _fetchSessions();
    _readyFuture = _makeReadyFuture();
    _chartContextFuture = buildChartContext(
      _client['id'].toString(),
      _client,
    );
    // Attach client context so a plain Hold pill tap on this chart
    // opens the EXPANDED chat at Tier 2 (client-aware intro). Cleared
    // in dispose() if the chat isn't open.
    //
    // Phase 4.1.6 — must NOT call setClientContext synchronously from
    // initState. It fires `notifyListeners()` on the global
    // cueHoldController; the AnimatedBuilder inside CueHold (mounted
    // in the topbar) is mid-build at this point, and marking it dirty
    // during build throws "setState() called during build" (observed
    // thousands of times in production console). Deferring to the next
    // frame fires the listeners outside any build pass.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      cueHoldController.setClientContext(
        clientId: _client['id'].toString(),
        clientName: (_client['name'] as String?) ?? '',
      );
      _fireCompactHold();
    });
  }

  void _fireCompactHold() {
    // Respect the SLP's active session — don't override EXPANDED or any
    // already-engaged Hold state. IDLE / COMPACT are fair game.
    final c = cueHoldController;
    if (c.state == CueHoldState.expanded ||
        c.state == CueHoldState.fullActivity ||
        c.state == CueHoldState.thinking ||
        c.state == CueHoldState.listening) {
      return;
    }
    final firstName = NameFormatter.firstNameForGreeting(
            (_client['name'] as String?) ?? '') ??
        '';
    final label =
        firstName.isEmpty ? 'Cue · reading chart' : 'Cue · reading $firstName';
    c.toCompact(label);
    _holdCompactTimer?.cancel();
    _holdCompactTimer = Timer(const Duration(seconds: 3), () {
      // Only revert if no one else has changed state since.
      if (cueHoldController.state == CueHoldState.compact &&
          cueHoldController.contextLabel == label) {
        cueHoldController.toIdle();
      }
    });
  }

  @override
  void dispose() {
    _holdCompactTimer?.cancel();
    // If we're still showing this chart's COMPACT label when the screen
    // unmounts (chart→non-chart navigation), revert the Hold so the
    // label doesn't linger on the next screen.
    final c = cueHoldController;
    final firstName = NameFormatter.firstNameForGreeting(
            (_client['name'] as String?) ?? '') ??
        '';
    final ourLabel =
        firstName.isEmpty ? 'Cue · reading chart' : 'Cue · reading $firstName';
    if (c.state == CueHoldState.compact && c.contextLabel == ourLabel) {
      c.toIdle();
    }
    // Clear the chart-attached client context (no-op when the EXPANDED
    // chat is open against this client).
    c.clearClientContext();
    super.dispose();
  }

  // ── Data fetchers ────────────────────────────────────────────────────────

  Future<_SpineData> _fetchSpine() async {
    final clientId = _client['id'].toString();
    final ltgsRaw = await _supabase
        .from('long_term_goals')
        .select()
        .eq('client_id', clientId)
        .order('sequence_num', ascending: true);
    final stgsRaw = await _supabase
        .from('short_term_goals')
        .select()
        .eq('client_id', clientId)
        .order('sequence_num', ascending: true);
    return _SpineData(
      ltgs: List<Map<String, dynamic>>.from(ltgsRaw),
      stgs: List<Map<String, dynamic>>.from(stgsRaw),
    );
  }

  Future<List<Map<String, dynamic>>> _fetchSessions() async {
    final response = await _supabase
        .from('sessions')
        .select()
        .eq('client_id', _client['id'])
        .isFilter('deleted_at', null)
        .order('date', ascending: false);
    return List<Map<String, dynamic>>.from(response);
  }

  Future<_ReadyData> _makeReadyFuture() =>
      Future.wait<dynamic>([_spineFuture, _sessionsFuture]).then((r) {
        final spine = r[0] as _SpineData;
        final sessions = r[1] as List<Map<String, dynamic>>;
        final entries = <TimelineEntry>[];

        for (final s in sessions) {
          final dateStr = s['date'] as String?;
          if (dateStr == null) continue;
          DateTime? dt;
          try {
            dt = DateTime.parse(dateStr);
          } catch (_) {
            continue;
          }
          entries.add(TimelineEntry(
            date: dt,
            type: TimelineEntryType.session,
            title: dateStr,
            subtitle: null,
            referenceId: s['id']?.toString(),
            rawData: s,
          ));
        }

        for (final ltg in spine.ltgs) {
          final createdAt = ltg['created_at'] as String?;
          if (createdAt != null) {
            final dt = DateTime.tryParse(createdAt);
            if (dt != null) {
              entries.add(TimelineEntry(
                date: dt,
                type: TimelineEntryType.goalSet,
                title: 'Goal set · ${(ltg['domain'] as String?) ?? 'General'}',
                subtitle: ltg['goal_text'] as String?,
                referenceId: ltg['id']?.toString(),
              ));
            }
          }
          final achievedAt = ltg['achieved_at'] as String?;
          if (achievedAt != null) {
            final dt = DateTime.tryParse(achievedAt);
            if (dt != null) {
              entries.add(TimelineEntry(
                date: dt,
                type: TimelineEntryType.goalAchieved,
                title: 'Goal achieved · ${(ltg['domain'] as String?) ?? 'General'}',
                subtitle: ltg['goal_text'] as String?,
                referenceId: ltg['id']?.toString(),
              ));
            }
          }
        }

        entries.sort((a, b) => b.date.compareTo(a.date));
        return _ReadyData(spine: spine, sessions: sessions, timeline: entries);
      });

  void _refreshChart() {
    setState(() {
      _spineFuture = _fetchSpine();
      _sessionsFuture = _fetchSessions();
      _readyFuture = _makeReadyFuture();
      _chartContextFuture = buildChartContext(
        _client['id'].toString(),
        _client,
      );
    });
    _refreshClientRow();
  }

  Future<void> _refreshClientRow() async {
    final id = _client['id']?.toString();
    if (id == null || id.isEmpty) return;
    try {
      final row = await _supabase
          .from('clients')
          .select()
          .eq('id', id)
          .isFilter('deleted_at', null)
          .single();
      if (mounted) {
        setState(() => _client = Map<String, dynamic>.from(row));
      }
    } catch (_) {/* keep stale data on transient failure */}
  }

  // ── Navigation ───────────────────────────────────────────────────────────

  Future<void> _openAddSession() async {
    final added = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => AddSessionScreen(
          clientId: _client['id'].toString(),
          clientName: _client['name'].toString(),
        ),
      ),
    );
    if (added == true && mounted) _refreshChart();
  }

  Future<void> _openGoalAuthoring() async {
    final clientId = _client['id'].toString();
    final clientName = _client['name'] as String? ?? '';
    final sessionCount = _client['total_sessions'] as int? ?? 0;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => GoalAuthoringScreen(
          clientId: clientId,
          clientName: clientName,
          sessionCount: sessionCount,
        ),
      ),
    );
    if (mounted) _refreshChart();
  }

  Future<void> _openEditClient() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AddClientScreen(existingClient: _client),
      ),
    );
    if (mounted) _refreshChart();
  }

  Future<void> _openFullTimeline(_ReadyData? data) async {
    if (data == null) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TimelineRoute(
          clientId: _client['id'].toString(),
          clientName: (_client['name'] as String?) ?? '',
          entries: data.timeline,
        ),
      ),
    );
  }

  Future<void> _confirmArchive() async {
    final clientName = (_client['name'] as String?)?.trim() ?? 'this client';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Archive this client?'),
        content: Text(
          '$clientName will be moved to the archive and removed from your '
          "active roster. You can restore them from Settings later.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Archive'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await _supabase
          .from('clients')
          .update({'status': 'archived'})
          .eq('id', _client['id']);
    } catch (_) {/* status column may not exist yet — treat as best-effort */}
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$clientName archived.')),
    );
    Navigator.pop(context, true);
  }

  Future<void> _confirmDeleteClient() async {
    final clientName = (_client['name'] as String?)?.trim() ?? 'this client';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this client?'),
        content: Text(
          '$clientName will be removed from your roster. '
          'You can contact support to recover this record.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: CueColors.coral),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      await _supabase
          .from('clients')
          .update({'deleted_at': DateTime.now().toUtc().toIso8601String()})
          .eq('id', _client['id']);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not delete: $e')),
        );
      }
      return;
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$clientName removed.')),
    );
    Navigator.pop(context, true);
  }

  // ── Popup helpers ────────────────────────────────────────────────────────

  void _toggleCuePopup() {
    setState(() {
      _cuePopupOpen = !_cuePopupOpen;
      if (_cuePopupOpen) {
        // ⌘K opens the popup client-scoped (no goal anchor).
        _cuePopupStgId = null;
        _cuePopupLtgId = null;
      }
    });
  }

  void _closeCuePopupIfOpen() {
    if (!_cuePopupOpen) return;
    setState(() => _cuePopupOpen = false);
  }

  /// Phase 4.1.4 — fires from the focused STG's "Think with Cue" pill.
  /// Opens the global Hold's EXPANDED chat surface (Tier 3 intro copy)
  /// with the STG anchor pre-loaded so AskCueService picks up the
  /// goal-scoped thread. The chart-local CuePopup (bottom-right) is no
  /// longer the destination for this pill — that surface stays available
  /// via ⌘K for backward compat but isn't part of the Phase 4.1.4 flow.
  void _openCueForStg(Map<String, dynamic> stg) {
    final stgId = stg['id']?.toString();
    if (stgId == null || stgId.isEmpty) return;
    final ltgId = stg['long_term_goal_id']?.toString() ??
        stg['ltg_id']?.toString();
    final body = ((stg['target_behavior'] as String?) ??
            (stg['specific'] as String?) ??
            (stg['goal_text'] as String?) ??
            (stg['target'] as String?) ??
            '')
        .trim();
    cueHoldController.expand(
      clientId: _client['id'].toString(),
      clientName: (_client['name'] as String?) ?? '',
      stgId: stgId,
      ltgId: ltgId,
      stgBodyText: body.isEmpty ? null : body,
    );
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final clientId = _client['id'].toString();
    final clientName = (_client['name'] as String?) ?? '';

    return AppLayout(
      title: clientName,
      activeRoute: 'roster',
      body: CallbackShortcuts(
        bindings: <ShortcutActivator, VoidCallback>{
          const SingleActivator(LogicalKeyboardKey.keyK, meta: true):
              _toggleCuePopup,
          const SingleActivator(LogicalKeyboardKey.keyK, control: true):
              _toggleCuePopup,
          const SingleActivator(LogicalKeyboardKey.escape):
              _closeCuePopupIfOpen,
        },
        child: Focus(
          autofocus: true,
          child: LayoutBuilder(
            builder: (ctx, constraints) {
              final lc = CueColorsResolved.of(ctx);
              final hPad = constraints.maxWidth > 500 ? 24.0 : 16.0;
              final isMobile = constraints.maxWidth < 768;
              return Stack(
                fit: StackFit.expand,
                children: [
                  Positioned.fill(
                    child: ColoredBox(
                      color: lc.bgCanvas,
                      child: Align(
                        alignment: Alignment.topCenter,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 1280),
                          child: FutureBuilder<_ReadyData>(
                            future: _readyFuture,
                            builder: (ctx2, snap) {
                              final data = snap.data;
                              final ltgs =
                                  data?.spine.ltgs ?? const <Map<String, dynamic>>[];
                              final stgs =
                                  data?.spine.stgs ?? const <Map<String, dynamic>>[];
                              final sessions =
                                  data?.sessions ?? const <Map<String, dynamic>>[];
                              return _buildScrollBody(
                                clientId: clientId,
                                clientName: clientName,
                                hPad: hPad,
                                isMobile: isMobile,
                                ltgs: ltgs,
                                stgs: stgs,
                                sessions: sessions,
                                readyData: data,
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                  ),
                  // ── Floating action bar ──────────────────────────────────
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 32,
                    child: Center(
                      child: ChartActionBar(
                        onAddSession: _openAddSession,
                        onEditClient: _openEditClient,
                        onArchive: _confirmArchive,
                        onDelete: _confirmDeleteClient,
                      ),
                    ),
                  ),
                  // ── Cue popup (⌘K summon) ────────────────────────────────
                  if (_cuePopupOpen)
                    Positioned(
                      right: 24,
                      bottom: 110,
                      child: CuePopup(
                        clientId: clientId,
                        clientName: clientName,
                        ltgId: _cuePopupLtgId,
                        stgId: _cuePopupStgId,
                        onMinimize: _closeCuePopupIfOpen,
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildScrollBody({
    required String clientId,
    required String clientName,
    required double hPad,
    required bool isMobile,
    required List<Map<String, dynamic>> ltgs,
    required List<Map<String, dynamic>> stgs,
    required List<Map<String, dynamic>> sessions,
    required _ReadyData? readyData,
  }) {
    return CustomScrollView(
      slivers: [
        // ── 1. Masthead ──────────────────────────────────────────────────
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(hPad, 32, hPad, 0),
            child: ChartMasthead(
              client: _client,
              sessions: sessions,
              onEditClient: _openEditClient,
              onBuildWithCue: _openGoalAuthoring,
              onAddCaregiverDetails: _openEditClient,
            ),
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 32)),

        // ── 2. Cue editorial ─────────────────────────────────────────────
        SliverToBoxAdapter(
          child: _capped(
            Padding(
              padding: EdgeInsets.fromLTRB(hPad, 24, hPad, 0),
              child: _buildCueEditorial(clientName, ltgs, sessions),
            ),
            760,
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 56)),

        // ── 3. Goal ladder ───────────────────────────────────────────────
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: hPad),
            child: ChartGoalLadder(
              clientId: clientId,
              ltgs: ltgs,
              stgs: stgs,
              onThinkWithCue: _openCueForStg,
            ),
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 48)),

        // ── 4. Session history ───────────────────────────────────────────
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: hPad),
            child: ChartSessionHistory(
              clientId: clientId,
              clientName: clientName,
              sessions: sessions,
              onShowAll: () => _openFullTimeline(readyData),
            ),
          ),
        ),

        // Tail padding so the floating action bar never occludes content.
        const SliverToBoxAdapter(child: SizedBox(height: 120)),
      ],
    );
  }

  Widget _buildCueEditorial(
    String clientName,
    List<Map<String, dynamic>> ltgs,
    List<Map<String, dynamic>> sessions,
  ) {
    return FutureBuilder<_ReadyData>(
      future: _readyFuture,
      builder: (ctx, readySnap) {
        if (!readySnap.hasData) {
          // Show loading skeleton via empty-context construction — the
          // widget itself renders skeleton bars while _loading.
          return const ChartCueEditorial(chartContext: '');
        }
        final hasSessions = readySnap.data!.sessions.isNotEmpty;
        final hasActiveLtgs =
            readySnap.data!.spine.ltgs.where(_isLtgActive).isNotEmpty;
        if (!hasSessions && !hasActiveLtgs) {
          final firstName =
              NameFormatter.firstNameForGreeting(clientName);
          final emptyThought =
              firstName != null && firstName.isNotEmpty
                  ? "$firstName's story starts here."
                  : 'Their story starts here.';
          return ChartCueEditorial(
            chartContext: '',
            overrideThought: emptyThought,
            overrideHighlight: 'story starts here',
          );
        }
        return FutureBuilder<String>(
          future: _chartContextFuture,
          builder: (ctx2, ctxSnap) {
            if (!ctxSnap.hasData) {
              return const ChartCueEditorial(chartContext: '');
            }
            return ChartCueEditorial(chartContext: ctxSnap.data!);
          },
        );
      },
    );
  }

  Widget _capped(Widget child, double maxWidth) {
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    );
  }
}

// ── Top-level helpers ────────────────────────────────────────────────────────

bool _isLtgActive(Map<String, dynamic> ltg) {
  final status = ltg['status'] as String?;
  // Phase 4.0.7.23c-deploy — pending_attestation LTGs are v2 drafts that
  // live in Build with Cue until the SLP signs the plan; not "active".
  return status != 'discontinued' &&
      status != 'met' &&
      status != 'achieved' &&
      status != 'pending_attestation';
}
