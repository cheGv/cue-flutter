// Phase 5.3 Round B — old _buildGoalsSection + its inline LTG/STG editor
// helper widgets are no longer called (the three hero pillars at
// lib/widgets/profile/ replace the goal-card rendering). The code is
// preserved in this file in case the inline-edit surface needs to
// resurface as a popup target; the file-level ignore silences the
// analyzer's transitive unused warnings for that orphaned helper graph.
// ignore_for_file: unused_element

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/timeline_entry.dart';
import '../services/name_formatter.dart';
import '../theme/cue_color_scheme.dart';
import '../theme/cue_theme.dart';
import '../theme/cue_tokens.dart';
import '../theme/cue_typography.dart';
import '../utils/chart_context.dart';
import '../utils/daily_chart_log.dart';
import '../widgets/app_layout.dart';
import '../widgets/brief_thought_view.dart';
// Phase 5.3 Round A.2 — Cue popup architecture. Phase 5.4 Sprint 2
// commit 1 — HUD strip retired; popup floats bottom-right when summoned
// (⌘K, sidebar tap). The Hold in widgets/cue_hold.dart
// is the top-bar surface but does not summon the popup.
import '../widgets/cue_popup.dart';
// Phase 5.3 Round B — hero pillar widgets replacing the goal-card section.
// Phase 5.3 Round B.1 — LtgStrip quiet horizontal band above the pillars.
import '../widgets/profile/active_stgs_pillar.dart';
import '../widgets/profile/last_session_pillar.dart';
import '../widgets/profile/ltg_strip.dart';
import '../widgets/profile/next_session_pillar.dart';
import '../widgets/profile/timeline_strip.dart';
import '../widgets/cue_cuttlefish.dart';
import '../widgets/cue_hold.dart';
import '../widgets/cue_top_band.dart';
import '../widgets/goal_achieved_overlay.dart';
import '../widgets/noticed_moment.dart';
import 'add_session_screen.dart';
import 'add_client_screen.dart';
import 'goal_authoring_screen.dart';
import 'ltg_edit_screen.dart';
import 'pre_therapy_planning_fluency_screen.dart';
import 'timeline_route.dart';

// ── Data classes ──────────────────────────────────────────────────────────────
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

// ── Screen ────────────────────────────────────────────────────────────────────
class ClientProfileScreen extends StatefulWidget {
  final Map<String, dynamic> client;
  const ClientProfileScreen({super.key, required this.client});

  @override
  State<ClientProfileScreen> createState() => _ClientProfileScreenState();
}

class _ClientProfileScreenState extends State<ClientProfileScreen> {
  // Phase 5.3 B.3 — NoticedMomentView temporarily hidden on Profile.
  // The widget's hardcoded templates (e.g. "$firstName is your first")
  // bypass the LLM brief prompt's chitchat ban and caused duplicate-render
  // conflict with BriefThoughtView. Widget remains intact for Phase 5.4
  // re-mount via the Hold's state machine or summoned popup.
  // To re-enable: flip this flag to false.
  static const bool _kHideNoticedMomentB3 = true;

  final _supabase = Supabase.instance.client;

  late Future<_SpineData>                _spineFuture;
  late Future<List<Map<String, dynamic>>> _sessionsFuture;
  late Future<_ReadyData>                _readyFuture;

  // Phase 2: pre-built chart context string fed to BriefThoughtView and any
  // other Cue Study surface that needs it. Cached so we don't re-query
  // Supabase + the brief proxy on every rebuild.
  late Future<String> _chartContextFuture;

  // Phase 2 noticed-moment plumbing. Loaded asynchronously in initState.
  // Real values land via _loadMomentContext.
  int  _todaySessionCount  = 0;
  bool _isFirstClientToday = false;

  // Phase 5.1+5.2 — `_cueStudyKey` removed. Was used for scrolling
  // the Cue Study Brief widget into view; that widget is gone.
  // ignore: unused_field
  String? _csFabActiveLtgDomains;
  // ignore: unused_field
  String? _csFabActiveStgTexts;
  // ignore: unused_field
  String? _csFabRecentSessionsContext;
  // ignore: unused_field
  String? _csFabRegulatoryProfile;
  // ignore: unused_field
  String? _csFabBaselineSummary;

  // Inline edit state
  String? _editingLtgId;
  final TextEditingController _ltgEditCtrl = TextEditingController();

  String? _editingStgId;
  final TextEditingController _stgEditCtrl = TextEditingController();

  String? _addingStgForLtgId;
  final TextEditingController _addStgCtrl = TextEditingController();

  // Phase 3.3.4 — live client metadata. The chart screen receives
  // `widget.client` from the navigator, but that map can go stale if the
  // SLP edits the name (or any other field) via AddClientScreen or any
  // future inline edit. _client is the single source of truth used by
  // every chart render that reads client fields. _refreshClientRow()
  // refetches the row from Supabase; _refreshSpine() invokes it so name
  // changes propagate without manual reload.
  //
  // Phase 3.3.5.1 hotfix: the field defaults to an empty const map rather
  // than `late` so any code path that reads _client before initState
  // completes returns a safe-empty map instead of crashing with
  // LateInitializationError. The empty default is replaced with real data
  // in initState. (The Phase 3.3.4 bulk-rename of widget.client → _client
  // also clobbered the RHS of the initState assignment into a self-
  // reference; that's restored to widget.client below.)
  Map<String, dynamic> _client = const <String, dynamic>{};

  // Phase 5.3 Round A.2 — Cue popup visibility state. Toggled by HUD strip
  // click, ⌘K, or Esc. The popup is mounted in the widget tree only when
  // open; minimization is structural, not opacity-zero.
  bool _cuePopupOpen = false;

  @override
  void initState() {
    super.initState();
    _client             = Map<String, dynamic>.from(widget.client);
    _spineFuture        = _fetchSpine();
    _sessionsFuture     = _fetchSessions();
    _readyFuture        = _makeReadyFuture();
    _chartContextFuture = buildChartContext(
      _client['id'].toString(),
      _client,
    );
    _readyFuture.then(_populateCsFabContext).ignore();
    _loadMomentContext();
  }

  /// Refetch this client's row and propagate to [_client]. Called from
  /// [_refreshSpine] so any data-mutation path (edit, delete, goal add,
  /// session add) also refreshes the displayed client metadata. The
  /// underlying client_id never changes; we re-read everything else.
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
    } catch (_) {
      // Keep stale data on transient failure — better than blanking.
    }
  }

  // Load real Monday-first inputs:
  //   - today's session count for the current SLP
  //   - whether THIS client is the first chart opened today
  // Marks this client as opened AFTER reading first-status, so that
  // subsequently-opened charts correctly see this one in front of them.
  Future<void> _loadMomentContext() async {
    final clientId = _client['id'].toString();
    try {
      final isFirst = await DailyChartLog.isFirstClientToday(clientId);
      final today   = DateTime.now();
      final todayStr =
          '${today.year.toString().padLeft(4, "0")}-'
          '${today.month.toString().padLeft(2, "0")}-'
          '${today.day.toString().padLeft(2, "0")}';

      final uid = _supabase.auth.currentUser?.id;
      int sessionCount = 0;
      if (uid != null) {
        // Count sessions on the SLP's roster scheduled for today.
        // Falls back gracefully on any schema variance — if a count fails
        // we just stay at 0 and the Monday-first moment won't fire.
        try {
          final rows = await _supabase
              .from('daily_roster')
              .select('id')
              .eq('clinician_id', uid)
              .eq('session_date', todayStr);
          sessionCount = (rows as List).length;
        } catch (_) {
          // Try the alternate `sessions.user_id` shape if `daily_roster`
          // is unavailable for this account.
          try {
            final rows = await _supabase
                .from('sessions')
                .select('id')
                .eq('user_id', uid)
                .eq('date', todayStr)
                .isFilter('deleted_at', null);
            sessionCount = (rows as List).length;
          } catch (_) {/* leave 0 */}
        }
      }

      // Persist this client as opened today (after the first-status read).
      await DailyChartLog.markOpened(clientId);

      if (mounted) {
        setState(() {
          _isFirstClientToday = isFirst;
          _todaySessionCount  = sessionCount;
        });
      }
    } catch (_) {
      // Detection rules tolerate the defaults (0 / false).
    }
  }

  void _populateCsFabContext(_ReadyData data) {
    if (!mounted) return;

    final activeLtgs = data.spine.ltgs.where(_isLtgActive).toList();
    final domains = activeLtgs
        .map((l) => ((l['domain'] as String?) ?? '').trim())
        .where((d) => d.isNotEmpty)
        .toSet()
        .toList();

    final stgTexts = data.spine.stgs
        .where((s) => (s['status'] as String?) == 'active')
        .map((s) => ((s['specific'] as String?) ??
                     (s['goal_text'] as String?) ??
                     (s['target_behavior'] as String?) ?? '').trim())
        .where((t) => t.isNotEmpty)
        .toList();

    final sessionLines = <String>[];
    for (final s in data.sessions.take(3)) {
      final date     = (s['date'] as String?) ?? '';
      final soapJson = s['soap_note'] as String?;
      String? observed;
      String? plan;
      if (soapJson != null && soapJson.isNotEmpty) {
        try {
          final soap = jsonDecode(soapJson) as Map<String, dynamic>;
          observed = (soap['o'] as String?)?.trim();
          plan     = (soap['p'] as String?)?.trim();
        } catch (_) {}
      }
      final parts = <String>[if (date.isNotEmpty) date];
      if (observed?.isNotEmpty ?? false) parts.add('Observed: $observed');
      if (plan?.isNotEmpty ?? false)     parts.add('Plan: $plan');
      if (parts.length > 1)             sessionLines.add(parts.join(' | '));
    }

    String? strField(String key) {
      final v = (_client[key] as String?)?.trim();
      return (v?.isEmpty ?? true) ? null : v;
    }

    setState(() {
      _csFabActiveLtgDomains      = domains.isNotEmpty ? domains.join(' · ') : null;
      _csFabActiveStgTexts        = stgTexts.isNotEmpty ? stgTexts.join('\n') : null;
      _csFabRecentSessionsContext = sessionLines.isNotEmpty ? sessionLines.join('\n') : null;
      _csFabRegulatoryProfile     = strField('regulatory_profile');
      _csFabBaselineSummary       = strField('baseline_summary');
    });
  }

  @override
  void dispose() {
    _ltgEditCtrl.dispose();
    _stgEditCtrl.dispose();
    _addStgCtrl.dispose();
    super.dispose();
  }

  // ── Phase 5.3 Round A.2 — Cue popup helpers ──────────────────────────────

  void _toggleCuePopup() {
    setState(() => _cuePopupOpen = !_cuePopupOpen);
  }

  void _closeCuePopupIfOpen() {
    if (!_cuePopupOpen) return;
    setState(() => _cuePopupOpen = false);
  }

  /// Phase 5.3 Round B.1 — per-sliver width cap. Profile body's outer
  /// ConstrainedBox stretches to 1024 (was 680) so the hero pillars row
  /// can breathe; text-content slivers (identity, brief, timeline,
  /// documents, LTG strip) wrap their child in `_capped(child, 680)` to
  /// hold the readable column width.
  Widget _capped(Widget child, double maxWidth) {
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    );
  }

  // ── Data fetchers ─────────────────────────────────────────────────────────

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
        final spine    = r[0] as _SpineData;
        final sessions = r[1] as List<Map<String, dynamic>>;
        final entries  = <TimelineEntry>[];

        // Sessions → timeline
        for (final s in sessions) {
          final dateStr = s['date'] as String?;
          if (dateStr == null) continue;
          DateTime? dt;
          try { dt = DateTime.parse(dateStr); } catch (_) { continue; }
          entries.add(TimelineEntry(
            date:        dt,
            type:        TimelineEntryType.session,
            title:       _formatTargetDate(dateStr),
            subtitle:    _extractSoapPreview(s),
            referenceId: s['id']?.toString(),
            rawData:     s,
          ));
        }

        // LTGs → goal_set and goal_achieved events
        for (final ltg in spine.ltgs) {
          final createdAt = ltg['created_at'] as String?;
          if (createdAt != null) {
            DateTime? dt;
            try { dt = DateTime.parse(createdAt); } catch (_) {}
            if (dt != null) {
              entries.add(TimelineEntry(
                date:        dt,
                type:        TimelineEntryType.goalSet,
                title:       'Goal set · ${(ltg['domain'] as String?) ?? 'General'}',
                subtitle:    ltg['goal_text'] as String?,
                referenceId: ltg['id']?.toString(),
              ));
            }
          }

          final achievedAt = ltg['achieved_at'] as String?;
          if (achievedAt != null) {
            DateTime? dt;
            try { dt = DateTime.parse(achievedAt); } catch (_) {}
            if (dt != null) {
              entries.add(TimelineEntry(
                date:        dt,
                type:        TimelineEntryType.goalAchieved,
                title:       'Goal achieved · ${(ltg['domain'] as String?) ?? 'General'}',
                subtitle:    ltg['goal_text'] as String?,
                referenceId: ltg['id']?.toString(),
              ));
            }
          }
        }

        entries.sort((a, b) => b.date.compareTo(a.date));
        return _ReadyData(spine: spine, sessions: sessions, timeline: entries);
      });

  void _refreshSpine() {
    setState(() {
      // Phase 4.0.7.36 — _sessionsFuture rebuild added so this method is
      // the canonical "refresh everything mutation-relevant" entry. Prior
      // to this, callers like _openAddSession had to inline a separate
      // setState that re-created _sessionsFuture, and any call site that
      // routed through _refreshSpine() alone (e.g. timeline View note
      // edit) saw stale session lists. _readyFuture wraps both
      // _spineFuture AND _sessionsFuture (see _makeReadyFuture); both
      // must be re-created together for the chained future to refresh.
      _sessionsFuture     = _fetchSessions();
      _spineFuture        = _fetchSpine();
      _readyFuture        = _makeReadyFuture();
      // Phase 3.3: chart_context feeds the /generate-brief proxy. Goal /
      // session mutations bust the cached context so the brief sliver's
      // FutureBuilder<_ReadyData> re-runs the empty-chart bypass check
      // and (when goals exist again) the LLM brief regenerates from
      // fresh context. Without this rebuild, the brief stayed on
      // "{firstName}'s story starts here." after Generate Plan completed.
      _chartContextFuture = buildChartContext(
        _client['id'].toString(),
        _client,
      );
    });
    // Phase 3.3.4 — refetch the client row in parallel so name / age /
    // diagnosis edits propagate to header, brief, Cue Study welcome,
    // and chips without manual reload.
    _refreshClientRow();
  }

  // ── Timeline mapping ─────────────────────────────────────────────────────

  // ── B.3 — TimelineEntry → TimelineEvent mapping for TimelineStrip ────────
  // Strip simplifies entry types to session/parent/goal at the dot-level
  // grain. Constructed types are session/goalSet/goalAchieved (per
  // _makeReadyFuture); the other enum values are never instantiated.
  // Phase 5.4: when parent comms join the timeline, add a parent-typed
  // entry source and route it to TimelineEventType.parent here.
  // Empty-SOAP sessions emit content: '' so they appear as hollow dots on
  // the strip but don't burn "Last 3 events" list real estate (filter +
  // empty guards in TimelineStrip handle the rest).
  TimelineEvent _entryToEvent(TimelineEntry entry) => TimelineEvent(
        date: entry.date,
        type: entry.type == TimelineEntryType.session
            ? TimelineEventType.session
            : TimelineEventType.goal,
        content: switch (entry.type) {
          TimelineEntryType.session =>
              (entry.subtitle?.isNotEmpty ?? false) ? entry.subtitle! : '',
          _ =>
              (entry.subtitle?.isNotEmpty ?? false)
                  ? entry.subtitle!
                  : entry.title,
        },
        isAttested: entry.type == TimelineEntryType.session &&
            ((entry.rawData?['clinician_attested'] as bool?) ?? false),
        sourceId: entry.referenceId,
      );

  // ── Navigation ────────────────────────────────────────────────────────────

  Future<void> _openGoalAuthoring() async {
    final clientId = _client['id'].toString();
    final clientName = _client['name'] as String? ?? '';
    final sessionCount = _client['total_sessions'] as int? ?? 0;

    // Phase 4.0.7.27d-population-router-removal — Build with Cue now
    // routes every client straight to GoalAuthoringScreen (the v2-wired
    // surface) regardless of population_type. The previous fluency
    // detour through PreTherapyPlanningFluencyScreen has been removed;
    // that screen + isPlanInputsLocked stay in the repo as orphan code
    // for the Phase 2 multi-domain rebuild.
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => GoalAuthoringScreen(
          clientId:     clientId,
          clientName:   clientName,
          sessionCount: sessionCount,
        ),
      ),
    );
    // Phase 3.3 — when GoalAuthoringScreen pops we cannot assume the
    // SLP saved a plan, but if any goals were inserted the cached
    // _readyFuture and _chartContextFuture must invalidate so the brief
    // sliver's empty-chart bypass re-evaluates. _refreshSpine handles
    // both. The cost is one extra round-trip when the SLP cancels —
    // small price for guaranteed reactivity.
    if (mounted) _refreshSpine();
  }

  // Phase 4.0.7 — chart-side entry point for editing plan inputs without
  // proceeding to authoring. Used by the "Plan inputs" pill on the bar.
  // Phase 4.0.7.27d-population-router-removal — caller pill removed; this
  // method is currently unreachable. Kept in place for the Phase 2
  // multi-domain rebuild to resurface a domain-aware version.
  Future<void> _openPlanInputs() async {
    await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => PreTherapyPlanningFluencyScreen(
          clientId:                _client['id'].toString(),
          clientName:              _client['name'] as String? ?? '',
          sessionCount:            _client['total_sessions'] as int? ?? 0,
          proceedToAuthoringOnLock: false,
        ),
      ),
    );
    if (mounted) _refreshSpine();
  }

  Future<void> _openAddSession() async {
    final added = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => AddSessionScreen(
          clientId:   _client['id'].toString(),
          clientName: _client['name'].toString(),
        ),
      ),
    );
    // Phase 4.0.7.36 — single canonical refresh entry (was a 3-future
    // inline setState that missed _chartContextFuture; the brief sliver
    // could stay on stale "story starts here." copy after a session
    // landed). _refreshSpine now covers sessions, spine, ready, chart
    // context, and client row in one call.
    if (added == true && mounted) _refreshSpine();
  }

  /// Phase 4.0.7.20j — deep-reasoning navigation from the inline editor.
  /// Saves any pending text changes first, then pushes LtgEditScreen
  /// with full context (client_id is injected because draft-goal call
  /// sites elsewhere cannot guarantee it on the goal map). On return,
  /// the spine is refreshed so any rationale / structured edits the
  /// SLP committed inside the deep editor land on the chart.
  Future<void> _openLtgInDeepReasoning(
      Map<String, dynamic> ltg, String ltgId) async {
    // Persist whatever the SLP has typed in the inline editor before
    // we navigate — the deep editor reads from the database, not from
    // the inline controller.
    if (_editingLtgId == ltgId) {
      await _saveLtg(ltgId);
    }
    if (!mounted) return;

    // Phase 4.0.7.23-completion — pass the client's clinical_area
    // through so the deep editor's CueReasoningPanel auto-prefills
    // its domain chips. _client is fetched via select() (full row),
    // so clinical_area is already available without query change.
    final goalMap = <String, dynamic>{
      'client_id': _client['id'].toString(),
      if (_client['clinical_area'] != null)
        'clinical_area': _client['clinical_area'] as String,
      ...ltg,
    };

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => LtgEditScreen(
          goal:       goalMap,
          clientName: _client['name'] as String? ?? '',
          onSaved:    (_) {/* spine refresh happens on pop below */},
        ),
      ),
    );
    if (mounted) _refreshSpine();
  }

  Future<void> _openEditClient() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AddClientScreen(existingClient: _client),
      ),
    );
    // Phase 3.3.4 — when the SLP returns from the edit screen, refresh
    // the chart so name / age / diagnosis updates propagate everywhere.
    if (mounted) _refreshSpine();
  }

  void _openMoreSheet() {
    final c = CueColorsResolved.of(context);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: c.bgCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 36, height: 4,
              decoration: BoxDecoration(
                color: c.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 12),
            ListTile(
              leading: Icon(Icons.edit_outlined, color: c.teal, size: 20),
              title: Text(
                'Edit client details',
                style: GoogleFonts.dmSans(fontSize: 15, color: c.textPrimary),
              ),
              onTap: () {
                Navigator.pop(sheetCtx);
                _openEditClient();
              },
            ),
            ListTile(
              leading: Icon(Icons.download_outlined, color: c.textBody, size: 20),
              title: Text(
                'Export chart',
                style: GoogleFonts.dmSans(fontSize: 15, color: c.textBody),
              ),
              onTap: () => Navigator.pop(sheetCtx),
            ),
            // Phase 3.2 (Option A): destructive delete moved here from the
            // Clients screen's per-row trash icon. Confirmation dialog
            // gates the action so it's never one-tap.
            ListTile(
              leading: const Icon(Icons.delete_outline,
                  color: CueColors.coral, size: 20),
              title: Text(
                'Delete client',
                style: GoogleFonts.dmSans(
                    fontSize: 15, color: CueColors.coral),
              ),
              onTap: () {
                Navigator.pop(sheetCtx);
                _confirmDeleteClient();
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  /// Confirm + soft-delete the current client (sets clients.deleted_at)
  /// and pops the chart with `true` so the caller can refresh.
  Future<void> _confirmDeleteClient() async {
    final clientName = (_client['name'] as String?)?.trim() ?? 'this client';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title:   const Text('Delete this client?'),
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

  // Phase 5.1+5.2 — _openCueStudySheet removed. Cue Study is retired;
  // Ask Cue lives inline on this surface (right panel on desktop /
  // drawer on narrow viewports). The brief-thought card's
  // "think with Cue" button now resolves to null (button hides) since
  // the chat is already open in the right panel.

  // ── Mark goal achieved (Phase 2) ────────────────────────────────────────
  // Confirm → UPDATE long_term_goals.status='achieved' → fire the 3s
  // celebrating overlay → refresh the goals list so the inline
  // CelebratingGoalCard takes over.
  Future<void> _markGoalAchieved(Map<String, dynamic> ltg) async {
    final id = ltg['id']?.toString();
    if (id == null || id.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title:   const Text('Mark this goal as achieved?'),
        content: const Text('This action stays on the timeline.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Mark achieved'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final updatedAt = DateTime.now().toUtc().toIso8601String();
    try {
      // Phase 4.0.7.27c-goals-archive — write achieved_at alongside
      // status. The timestamp drives the "celebrating until next
      // session" cutoff; the legacy updated_at is preserved as the
      // generic mutation marker. If a future flow flips status back to
      // 'active', that path should null achieved_at.
      await _supabase
          .from('long_term_goals')
          .update({
            'status':       'achieved',
            'updated_at':   updatedAt,
            'achieved_at':  updatedAt,
          })
          .eq('id', id);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not mark achieved: $e')),
        );
      }
      return;
    }

    if (!mounted) return;
    final updatedGoal = {
      ...ltg,
      'status':       'achieved',
      'updated_at':   updatedAt,
      'achieved_at':  updatedAt,
    };

    // Full-screen overlay; auto-dismisses after 3s.
    await showDialog<void>(
      context: context,
      barrierColor: Colors.black54,
      builder: (_) => GoalAchievedOverlay(goal: updatedGoal),
    );

    if (mounted) _refreshSpine();
  }

  // Phase 5.1+5.2 — _openCueStudyForGoal removed. Goal-scoped Ask Cue
  // is reachable through the Edit Goal screen's embedded AskCuePanel
  // (scope='ltg'). The "Open with Cue →" link in the LTG card is gone;
  // the SLP opens the goal and finds the chat panel inside.

  // Placeholder Ask sheet — Phase 3.3 removed the magnifying-glass
  // affordance from the action bar. Per CLAUDE.md §14.3 natural-language
  // retrieval is the Phase 4 "Practice" sidebar surface, not a chart-
  // scoped action. This handler stays as dead code so the intent-
  // classifier prototype can be referenced when Practice is built.
  void _openAskSheet() {
    final c          = CueColorsResolved.of(context);
    final clientName = (_client['name'] as String?) ?? 'this child';
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: c.bgCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 36, height: 4,
                decoration: BoxDecoration(
                  color:        c.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),
              TextField(
                autofocus: true,
                maxLines:  null,
                style: GoogleFonts.dmSans(fontSize: 16, color: c.textPrimary),
                decoration: InputDecoration(
                  hintText: 'Ask about $clientName...',
                  hintStyle: GoogleFonts.dmSans(
                      fontSize: 16, color: c.textBody),
                  border: InputBorder.none,
                ),
                // TODO: route to intent classifier — STG update,
                // session question, generic Cue Study, or chart action.
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }

  // ── Inline edit actions ───────────────────────────────────────────────────

  void _startEditLtg(Map<String, dynamic> ltg) {
    final text = ltg['goal_text'] as String? ?? '';
    setState(() {
      _editingLtgId      = ltg['id'].toString();
      _editingStgId      = null;
      _addingStgForLtgId = null;
      _ltgEditCtrl.text  = text;
      _ltgEditCtrl.selection =
          TextSelection.collapsed(offset: text.length);
    });
  }

  Future<void> _saveLtg(String ltgId) async {
    final text = _ltgEditCtrl.text.trim();
    if (text.isEmpty) return;
    try {
      await _supabase
          .from('long_term_goals')
          .update({'goal_text': text})
          .eq('id', ltgId);
      setState(() => _editingLtgId = null);
      _refreshSpine();
    } catch (_) {}
  }

  void _startEditStg(Map<String, dynamic> stg) {
    final text = stg['specific'] as String? ??
        stg['goal_text'] as String? ??
        stg['target_behavior'] as String? ?? '';
    setState(() {
      _editingStgId      = stg['id'].toString();
      _editingLtgId      = null;
      _addingStgForLtgId = null;
      _stgEditCtrl.text  = text;
      _stgEditCtrl.selection =
          TextSelection.collapsed(offset: text.length);
    });
  }

  Future<void> _saveStg(String stgId) async {
    final text = _stgEditCtrl.text.trim();
    if (text.isEmpty) return;
    try {
      await _supabase
          .from('short_term_goals')
          .update({'specific': text})
          .eq('id', stgId);
      setState(() => _editingStgId = null);
      _refreshSpine();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save edit: $e')),
        );
      }
    }
  }

  void _startAddStg(String ltgId) {
    setState(() {
      _addingStgForLtgId = ltgId;
      _editingLtgId      = null;
      _editingStgId      = null;
      _addStgCtrl.clear();
    });
  }

  Future<void> _submitAddStg(String ltgId) async {
    final text = _addStgCtrl.text.trim();
    if (text.isEmpty) return;
    final uid = _supabase.auth.currentUser?.id;
    if (uid == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Sign in required to add a step.')),
        );
      }
      return;
    }
    try {
      await _supabase.from('short_term_goals').insert({
        'client_id':         _client['id'].toString(),
        'long_term_goal_id': ltgId,
        'user_id':           uid,
        'specific':          text,
        'measurable':        '',
        'status':            'active',
      });
      setState(() => _addingStgForLtgId = null);
      _addStgCtrl.clear();
      _refreshSpine();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save step: $e')),
        );
      }
    }
  }

  void _closeAllEdits() {
    setState(() {
      _editingLtgId      = null;
      _editingStgId      = null;
      _addingStgForLtgId = null;
    });
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final clientId   = _client['id'].toString();
    final clientName = (_client['name'] as String?) ?? '';

    return AppLayout(
      title:       clientName,
      activeRoute: 'roster',
      // Phase 5.4 Sprint 2 commit 1 — Client Profile owns its own
      // chrome via CueTopBand inside the body Column below. Skip the
      // shell _TopBar so the band doesn't stack under a duplicate bar.
      skipTopBar:  true,
      // Phase 5.3 Round A.2 — popup summon affordances wired: ⌘K (or
      // Ctrl+K on non-mac) toggles, Esc closes. Phase 5.4 Sprint 2
      // commit 1 — HUD strip retired (Path A); the Hold is the
      // top-bar surface but does NOT summon the popup (architectural
      // commitment: one surface, not two — popup remains summoned via
      // ⌘K shortcut or Cue Study FAB). CuePopup is a Positioned child
      // of the inner Stack (added near the bottom of mainContent below).
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Phase 5.4 Sprint 2 commit 1 — The Hold — top-bar surface ──
              // Path A landed: HUD retired, the Hold becomes the sole
              // top-bar surface inside CueTopBand. The band absorbs nav
              // chrome on desktop (back arrow + client name); mobile
              // keeps the hero title in _buildClientHeader below.
              // ⌘K shortcut binding stays at workspace level (above this
              // builder); the visual ⌘K hint that lived in HUD is dropped
              // pending intentional redesign. Green dot indicator retired
              // with HUD; will return as Thinking-state indicator inside
              // the Hold in a later commit. See widgets/cue_top_band.dart
              // and widgets/cue_hold.dart.
              //
              // LayoutBuilder wraps the FutureBuilder so we can compute
              // bandHPad locally — the workspace's hPad lives inside the
              // Expanded > LayoutBuilder below and isn't in scope here.
              // The formula matches the workspace's hPad so the band's
              // leading edge aligns with chart content's leading edge.
              LayoutBuilder(
                builder: (ctx, constraints) {
                  final bandHPad =
                      constraints.maxWidth > 500 ? 24.0 : 16.0;
                  return FutureBuilder<_ReadyData>(
                    future: _readyFuture,
                    builder: (ctx2, snap) {
                      // Inline STG-active filter — no _isStgActive helper
                      // exists (only _isLtgActive).
                      final activeStepsCount = snap.data?.spine.stgs
                              .where((s) =>
                                  (s['status'] as String?)?.toLowerCase() ==
                                  'active')
                              .length ??
                          0;
                      final sessionCount = snap.data?.sessions.length ?? 0;
                      return CueTopBand(
                        leading:           const BackButton(),
                        title:             clientName,
                        horizontalPadding: bandHPad,
                        holdBuilder: (ctx3, isDesktop) =>
                            CueHold(
                          clientName:       clientName,
                          activeStepsCount: activeStepsCount,
                          sessionCount:     sessionCount,
                          whisperMaxWidth:  isDesktop ? 720.0 : 360.0,
                        ),
                      );
                    },
                  );
                },
              ),
              Expanded(
                child: LayoutBuilder(
                  builder: (ctx, constraints) {
          final hPad     = constraints.maxWidth > 500 ? 24.0 : 16.0;
          final isMobile = constraints.maxWidth < 600;
          // Phase 5.4 Sprint 2 commit 1 — 720 breakpoint matches
          // CueTopBand. On desktop the band absorbs the hero client
          // name; _buildClientHeader gates its name Text on this flag.
          final isDesktop = constraints.maxWidth >= 720;
          // Phase 5.3 Round A.1 — persistent right column retired; Profile
          // renders single-column at every viewport. The 680px reading-
          // width cap stays for the existing chart content; Round B's
          // pillar rewrite will redesign for the full-width canvas.
          final lc       = CueColorsResolved.of(ctx);
          final mainContent = Stack(
            fit: StackFit.expand,
            children: [
              // Scroll view fills the body via Positioned.fill — guarantees
              // it is a SIBLING of the floating bar (never a child), so the
              // bar is fixed to the viewport, not the scroll extent.
              Positioned.fill(
                child: ColoredBox(
                  color: lc.bgCanvas,
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: ConstrainedBox(
                      // Phase 5.3 Round B.1 — outer cap lifted 680 → 1024
                      // so the hero pillars row can breach the reading-
                      // width cap. Text-content slivers below wrap their
                      // child in _capped(680) to hold the readable column.
                      constraints: const BoxConstraints(maxWidth: 1024),
                      child: CustomScrollView(
                        slivers: [
                          // ── Zone 1: Identity ────────────────────────────
                          SliverToBoxAdapter(
                            child: _capped(
                                _buildClientHeader(lc, hPad, isDesktop), 680),
                          ),

                          // ── Phase 5.3 Round B.1 — LTG strip ───────────────
                          // Quiet horizontal band of active LTGs (or empty-
                          // state CTA) below identity, above Cue Noticed.
                          SliverToBoxAdapter(
                            child: _capped(
                              FutureBuilder<_ReadyData>(
                                future: _readyFuture,
                                builder: (ctx, snap) {
                                  final ltgs = (snap.data?.spine.ltgs ??
                                          const <Map<String, dynamic>>[])
                                      .where(_isLtgActive)
                                      .toList();
                                  return Padding(
                                    padding: EdgeInsets.fromLTRB(
                                        hPad, 14, hPad, 0),
                                    child: LtgStrip(
                                      activeLtgs: ltgs,
                                      clientName: clientName,
                                      onAskCue:   _toggleCuePopup,
                                    ),
                                  );
                                },
                              ),
                              680,
                            ),
                          ),

                          // ── Cue noticed (Phase 2) ───────────────────────
                          // HIDDEN B.3: NoticedMomentView duplicate-render
                          // conflict with BriefThoughtView. Hardcoded templates
                          // (gap, stuck, monday-first, returning-soft,
                          // multiple-sessions-today) bypass the LLM ban list
                          // shipped in the proxy prompt merge (1f48d23 on
                          // cue-ai-proxy main). Phase 5.4 may re-mount via
                          // different surface (the Hold's state machine or
                          // summoned popup) once the dual-system reconciliation
                          // is designed. Widget remains intact at lib/widgets/
                          // noticed_moment.dart; the import above stays.
                          // `if (!_kHideNoticedMomentB3)` gate keeps the symbols
                          // referenced — NoticedMomentView and detectNoticedMoment
                          // stay in the compilation graph so Phase 5.4 re-mount
                          // is a one-character flag flip.
                          if (!_kHideNoticedMomentB3)
                          SliverToBoxAdapter(
                            child: _capped(FutureBuilder<_ReadyData>(
                              future: _readyFuture,
                              builder: (ctx, snap) {
                                if (!snap.hasData) return const SizedBox.shrink();
                                final moment = detectNoticedMoment(
                                  client:    _client,
                                  sessions:  snap.data!.sessions,
                                  goals:     snap.data!.spine.stgs,
                                  todaySessionCount:  _todaySessionCount,
                                  isFirstClientToday: _isFirstClientToday,
                                );
                                if (moment == null) return const SizedBox.shrink();
                                return Padding(
                                  padding: EdgeInsets.symmetric(horizontal: hPad),
                                  child: NoticedMomentView(moment: moment),
                                );
                              },
                            ), 680),
                          ),

                          // ── Zone 2: Brief thought (Phase 2 + 3.2.2) ─────
                          // Outer FutureBuilder gates on _readyFuture so we
                          // can detect empty-chart state (no sessions AND no
                          // active LTGs) and short-circuit with a templated
                          // brief — never asking the LLM to speculate about
                          // a chart it has no data for. Charts with data go
                          // through BriefThoughtView's proxy fetch path.
                          SliverToBoxAdapter(
                            // Phase 5.1+5.2 — `key: _cueStudyKey`
                            // removed; the scroll target it served
                            // (the Cue Study Brief widget) is gone.
                            child: _capped(SizedBox(
                              child: FutureBuilder<_ReadyData>(
                                future: _readyFuture,
                                builder: (ctx, readySnap) {
                                  if (!readySnap.hasData) {
                                    return Padding(
                                      padding: EdgeInsets.symmetric(
                                          horizontal: hPad, vertical: 24),
                                      child: const SizedBox(height: 1),
                                    );
                                  }
                                  final hasSessions =
                                      readySnap.data!.sessions.isNotEmpty;
                                  final hasActiveLtgs = readySnap.data!.spine
                                      .ltgs
                                      .where(_isLtgActive)
                                      .isNotEmpty;
                                  final isEmptyChart =
                                      !hasSessions && !hasActiveLtgs;

                                  // Phase 4.0.7.27e-cue-noticed-draft-aware
                                  // — when the chart's only signal is
                                  // pending_attestation drafts (no
                                  // sessions, no active LTGs), Cue HAS
                                  // noticed something — it authored
                                  // those drafts. Render attestation-
                                  // aware copy here instead of falling
                                  // through to the generic "story
                                  // starts here" empty-state. Templated
                                  // (no LLM fetch) so chart_context
                                  // shape and proxy availability don't
                                  // gate the message.
                                  final draftLtgs = readySnap.data!.spine.ltgs
                                      .where((l) =>
                                          (l['status'] as String?) ==
                                          'pending_attestation')
                                      .toList();
                                  final hasDraftLtgs = draftLtgs.isNotEmpty;

                                  if (!hasSessions &&
                                      !hasActiveLtgs &&
                                      hasDraftLtgs) {
                                    // Domain word from the dominant
                                    // domain across drafts. Mixed-domain
                                    // or unrecognized → drop the word
                                    // ("3 goals waiting for Girish.").
                                    final domains = draftLtgs
                                        .map((l) => (l['domain'] as String?)
                                            ?.toUpperCase())
                                        .where((d) =>
                                            d != null && d.isNotEmpty)
                                        .toSet();
                                    String domainWord = '';
                                    if (domains.length == 1) {
                                      final d = domains.first!;
                                      domainWord = const {
                                        'AUT':   'autism',
                                        'FLU':   'fluency',
                                        'VOI':   'voice',
                                        'ALD':   'language and cognitive',
                                        'CAS':   'speech-motor',
                                        'DYS':   'dysarthria',
                                        'AAC':   'AAC',
                                        'SSD':   'speech-sound',
                                        'LIT':   'literacy',
                                        'HEAR':  'hearing-aural',
                                        'DYSPH': 'dysphagia',
                                      }[d] ?? '';
                                    }
                                    final n          = draftLtgs.length;
                                    final pluralS    = n == 1 ? '' : 's';
                                    final domainPart = domainWord.isNotEmpty
                                        ? '$domainWord '
                                        : '';
                                    // Phase 4.0.7.27e-cue-noticed-copy
                                    // -revise — Indian English clinical
                                    // register. firstName mirrors the
                                    // pattern used in the isEmptyChart
                                    // branch below; drops the "for X"
                                    // tail gracefully when name absent.
                                    final firstName = NameFormatter
                                        .firstNameForGreeting(clientName);
                                    final waitingFor = (firstName != null &&
                                            firstName.isNotEmpty)
                                        ? ' for $firstName'
                                        : '';
                                    return BriefThoughtCard(
                                      thought:
                                          '$n $domainPart'
                                          'goal$pluralS waiting$waitingFor.'
                                          ' Have a look when you can.',
                                      highlight:
                                          'Have a look when you can',
                                      // Phase 5.1+5.2 — Ask Cue lives
                                      // in the persistent right panel
                                      // (or drawer on narrow viewports);
                                      // the redundant "think with Cue"
                                      // button on the brief card is
                                      // suppressed by passing null.
                                      onThinkWithCue: null,
                                      outerMargin: EdgeInsets.fromLTRB(
                                          hPad,
                                          CueGap.s24,
                                          hPad,
                                          CueGap.s18),
                                    );
                                  }

                                  if (isEmptyChart) {
                                    // Phase 3.2.3 — name carries the
                                    // warmth, no gendered pronoun. The
                                    // fallback "Their story starts here."
                                    // should be unreachable given the
                                    // existing name resolution but is
                                    // kept as a safety net.
                                    final firstName = NameFormatter
                                        .firstNameForGreeting(clientName);
                                    final emptyThought = firstName != null &&
                                            firstName.isNotEmpty
                                        ? "$firstName's story starts here."
                                        : 'Their story starts here.';
                                    return BriefThoughtCard(
                                      thought:        emptyThought,
                                      highlight:      'story starts here',
                                      // Phase 5.1+5.2 — Ask Cue lives
                                      // in the persistent right panel
                                      // (or drawer on narrow viewports);
                                      // the redundant "think with Cue"
                                      // button on the brief card is
                                      // suppressed by passing null.
                                      onThinkWithCue: null,
                                      outerMargin: EdgeInsets.fromLTRB(
                                          hPad,
                                          CueGap.s24,
                                          hPad,
                                          CueGap.s18),
                                    );
                                  }

                                  return FutureBuilder<String>(
                                    future: _chartContextFuture,
                                    builder: (ctx2, ctxSnap) {
                                      if (!ctxSnap.hasData) {
                                        return Padding(
                                          padding: EdgeInsets.symmetric(
                                              horizontal: hPad,
                                              vertical:   24),
                                          child:
                                              const SizedBox(height: 1),
                                        );
                                      }
                                      return BriefThoughtView(
                                        chartContext:   ctxSnap.data!,
                                        // Phase 5.1+5.2 — Ask Cue lives
                                      // in the persistent right panel
                                      // (or drawer on narrow viewports);
                                      // the redundant "think with Cue"
                                      // button on the brief card is
                                      // suppressed by passing null.
                                      onThinkWithCue: null,
                                        outerMargin: EdgeInsets.fromLTRB(
                                            hPad,
                                            CueGap.s24,
                                            hPad,
                                            CueGap.s18),
                                      );
                                    },
                                  );
                                },
                              ),
                            ), 680),
                          ),

                          // ── Phase 5.3 Round B — three hero pillars ────────
                          // ActiveStgsPillar | NextSessionPillar (scaffold)
                          // | LastSessionPillar. Replaces the old goal-card
                          // section. Wrapped in FutureBuilder<_ReadyData> so
                          // the pillars get the resolved data they need
                          // without re-querying.
                          // Phase 5.3 Round B.1 — pillars breach the 680 cap
                          // to 1024 max so each pillar gets ≈333 px at full
                          // desktop viewport (vs ≈213 px under the old cap).
                          // Text-content slivers retain their 680 cap via
                          // _capped(child, 680).
                          SliverToBoxAdapter(
                            child: _capped(
                              FutureBuilder<_ReadyData>(
                                future: _readyFuture,
                                builder: (ctx, snap) =>
                                    _buildHeroPillarsRow(
                                  snap.data,
                                  hPad,
                                  isMobile: isMobile,
                                ),
                              ),
                              1024,
                            ),
                          ),

                          // ── Zone 4: Timeline (B.3 — TimelineStrip) ──────
                          // Compressed strip replaces the vertical SliverList
                          // (~3000px → ~240px). Full vertical view lives at
                          // /clients/<id>/timeline via TimelineRoute, reached
                          // through the "See all N events →" link.
                          SliverToBoxAdapter(
                            child: _capped(FutureBuilder<_ReadyData>(
                              future: _readyFuture,
                              builder: (ctx2, snap) {
                                // Three-state branch: while loading, show a
                                // small inline spinner so charts with 21
                                // sessions don't flash the TimelineStrip
                                // empty-state during the brief data fetch.
                                if (snap.connectionState ==
                                    ConnectionState.waiting) {
                                  return Padding(
                                    padding: EdgeInsets.fromLTRB(
                                        hPad, CueGap.s24, hPad, CueGap.s18),
                                    child: SizedBox(
                                      height: 80,
                                      child: Center(
                                        child: SizedBox(
                                          width:  20,
                                          height: 20,
                                          child: CircularProgressIndicator(
                                              strokeWidth: 1.5,
                                              color: CueColorsResolved.of(ctx2).teal),
                                        ),
                                      ),
                                    ),
                                  );
                                }
                                final entries = snap.data?.timeline ??
                                    const <TimelineEntry>[];
                                final events = entries
                                    .map(_entryToEvent)
                                    .toList();
                                return Padding(
                                  padding: EdgeInsets.fromLTRB(
                                      hPad, CueGap.s24, hPad, CueGap.s18),
                                  child: TimelineStrip(
                                    events:          events,
                                    totalEventCount: entries.length,
                                    onSeeAll: entries.isEmpty
                                        ? null
                                        : () => Navigator.push(
                                              ctx2,
                                              MaterialPageRoute(
                                                builder: (_) => TimelineRoute(
                                                  clientId:   clientId,
                                                  clientName: clientName,
                                                  entries:    entries,
                                                ),
                                              ),
                                            ),
                                  ),
                                );
                              },
                            ), 680),
                          ),

                          // ── Zone 5: Documents ───────────────────────────
                          SliverToBoxAdapter(
                            child: _capped(_buildDocumentsSection(lc, hPad), 680),
                          ),

                          // Bottom padding so the floating bar never
                          // covers the last timeline entry.
                          const SliverToBoxAdapter(
                            child: SizedBox(height: 100),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

              // ── Floating action bar ─────────────────────────────────────
              // Sibling of the scroll view above. Pinned to the viewport.
              if (isMobile)
                Positioned(
                  left:   16,
                  right:  16,
                  bottom: 24,
                  child:  _buildFloatingActionBar(lc, isMobile: true),
                )
              else
                Positioned(
                  left:   0,
                  right:  0,
                  bottom: 24,
                  // Phase 3.3.1: bar shrink-wraps to natural content
                  // width. The ConstrainedBox is now a safety ceiling
                  // only (maxWidth 720) so a future absurdly-long pill
                  // can't stretch the bar past readable bounds.
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 720),
                      child: _buildFloatingActionBar(lc, isMobile: false),
                    ),
                  ),
                ),
              // ── Phase 5.3 Round A.2 — floating Cue popup ─────────────────
              // Anchored right-bottom with bottom: 100 to clear the action
              // bar (sits at bottom: 24, ~50 px tall + shadow). Mounted
              // only when _cuePopupOpen; minimize (header X, Esc) returns
              // to the ambient HUD-strip-only state. Click-outside-to-close
              // not wired in A.2 — Esc + minimize suffice; revisit in
              // Round G with the command palette work.
              if (_cuePopupOpen)
                Positioned(
                  right: 24,
                  bottom: 100,
                  child: CuePopup(
                    clientId:   clientId,
                    clientName: clientName,
                    onMinimize: _closeCuePopupIfOpen,
                  ),
                ),
            ],
          );
          // Phase 5.3 Round A.2 — chart content lives inside the Expanded
          // below the HUD strip. The popup is a conditional Positioned
          // child of mainContent's Stack (see the if (_cuePopupOpen)
          // branch further up).
          return mainContent;
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Zone 1: Identity header ───────────────────────────────────────────────

  Widget _buildClientHeader(
      CueColorsResolved c, double hPad, bool isDesktop) {
    final client    = _client;
    final name      = client['name'] as String? ?? '';
    final age       = client['age'];
    final diagnosis = client['diagnosis'] as String?;

    final metaParts = <String>[
      if (age != null) 'Age $age',
      if (diagnosis != null && diagnosis.isNotEmpty) diagnosis,
    ];

    return Container(
      width:   double.infinity,
      color:   c.bgCanvas,
      // Phase 5.4 Sprint 2 commit 1 — top padding tightens to 12 on
      // desktop where CueTopBand absorbs the hero name; mobile keeps
      // the original 28 since the hero title still renders here.
      padding: EdgeInsets.fromLTRB(hPad, isDesktop ? 12 : 28, hPad, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Phase 5.4 Sprint 2 commit 1 — hero name + its 5px breather
          // are paired and both gated on !isDesktop. On desktop the band
          // absorbs the name; on mobile the Playfair hero renders here.
          if (!isDesktop) ...[
            Text(
              name,
              style: CueType.serif(
                fontSize:    38,
                fontWeight:  FontWeight.w700,
                color:       c.textPrimary,
                letterSpacing: -1.0,
                height:      1.1,
              ),
            ),
            const SizedBox(height: 5),
          ],
          if (metaParts.isNotEmpty)
            Text(
              metaParts.join(' · '),
              style: GoogleFonts.dmSans(fontSize: 14, color: c.textBody),
            ),
          const SizedBox(height: 12),
          // Cadence row + small pencil-edit icon (far right) for editing
          // client details. Discoverable but quiet.
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(child: _buildCadenceRow(c)),
              GestureDetector(
                onTap: _openEditClient,
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Icon(
                    Icons.edit_outlined,
                    size:  16,
                    color: c.textBody,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCadenceRow(CueColorsResolved c) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _sessionsFuture,
      builder: (ctx, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return Container(
            width: 140, height: 10,
            decoration: BoxDecoration(
              color:        c.border,
              borderRadius: BorderRadius.circular(4),
            ),
          );
        }

        final sessions = snap.data ?? [];

        String lastLabel = 'no sessions yet';
        if (sessions.isNotEmpty) {
          final dateStr = sessions.first['date'] as String?;
          if (dateStr != null) {
            final dt = DateTime.tryParse(dateStr);
            if (dt != null) {
              final days = DateTime.now().difference(dt).inDays;
              lastLabel = days == 0
                  ? 'seen today'
                  : days == 1
                      ? 'seen 1 day ago'
                      : 'seen $days days ago';
            }
          }
        }

        String spanLabel = '';
        if (sessions.length > 1) {
          final oldest =
              DateTime.tryParse((sessions.last['date'] as String?) ?? '');
          final newest =
              DateTime.tryParse((sessions.first['date'] as String?) ?? '');
          if (oldest != null && newest != null) {
            final weeks = ((newest.difference(oldest).inDays) / 7)
                .ceil()
                .clamp(1, 9999);
            spanLabel =
                '${sessions.length} sessions over $weeks '
                '${weeks == 1 ? 'week' : 'weeks'}';
          }
        } else if (sessions.length == 1) {
          spanLabel = '1 session';
        }

        return Row(
          children: [
            Container(
              width: 7, height: 7,
              decoration: BoxDecoration(color: c.teal, shape: BoxShape.circle),
            ),
            const SizedBox(width: 7),
            Text(
              lastLabel,
              style: GoogleFonts.dmSans(
                fontSize:   12,
                fontWeight: FontWeight.w600,
                color:      c.teal,
              ),
            ),
            if (spanLabel.isNotEmpty) ...[
              const SizedBox(width: 10),
              Container(width: 1, height: 12, color: c.border),
              const SizedBox(width: 10),
              Text(
                spanLabel,
                style: GoogleFonts.dmSans(fontSize: 12, color: c.textMuted),
              ),
            ],
          ],
        );
      },
    );
  }

  // ── Phase 5.3 Round B — Hero pillars row ──────────────────────────────────
  //
  // Replaces the legacy _buildGoalsSection rendering. Three pillars at
  // desktop (Row + Expanded), stacked at narrow (< 600 px). Each pillar
  // is its own widget under lib/widgets/profile/ and uses CueColorsResolved
  // throughout. ~300px min height per pillar (set in HeroPillarFrame).

  Widget _buildHeroPillarsRow(
    _ReadyData? data,
    double hPad, {
    required bool isMobile,
  }) {
    final allStgs = data?.spine.stgs ?? const <Map<String, dynamic>>[];
    final activeStgs = allStgs.where((s) {
      final st = (s['status'] as String?)?.toLowerCase();
      return st == null || st.isEmpty || st == 'active';
    }).toList();
    final sessions   = data?.sessions ?? const <Map<String, dynamic>>[];
    final clientName = (_client['name'] as String?) ?? '';

    final activePillar = ActiveStgsPillar(
      activeStgs: activeStgs,
      sessions:   sessions,
      clientName: clientName,
      onAskCue:   _toggleCuePopup,
    );
    final nextPillar = NextSessionPillar(
      clientName: clientName,
      onAskCue:   _toggleCuePopup,
    );
    final lastPillar = LastSessionPillar(
      sessions:   sessions,
      clientName: clientName,
      onAskCue:   _toggleCuePopup,
    );

    return Padding(
      padding: EdgeInsets.fromLTRB(hPad, 24, hPad, 8),
      // Phase 5.3 Round B.2 hotfix — IntrinsicHeight wrap on the desktop
      // Row. Without it, Row(crossAxisAlignment: stretch) inside an
      // unbounded-height sliver context (post-B.1 _capped wrap adds a
      // Center which shrinkWraps height) propagates infinity to children
      // via BoxConstraints.tightFor(height: maxHeight). The pillars then
      // try to render at infinity height, blowing out the CustomScrollView's
      // layout and rendering everything below as empty space. IntrinsicHeight
      // forces a finite tight-height context derived from children's
      // intrinsics (each pillar's HeroPillarFrame minHeight: 300 floors it).
      child: isMobile
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                activePillar,
                const SizedBox(height: 16),
                nextPillar,
                const SizedBox(height: 16),
                lastPillar,
              ],
            )
          : IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: activePillar),
                  const SizedBox(width: 16),
                  Expanded(child: nextPillar),
                  const SizedBox(width: 16),
                  Expanded(child: lastPillar),
                ],
              ),
            ),
    );
  }

  // ── Floating action bar ───────────────────────────────────────────────────

  Widget _buildFloatingActionBar(CueColorsResolved c, {required bool isMobile}) {
    final divider = _FabBarDivider(c: c);

    // Phase 3.3.1: pills are variable-width (no Expanded wrappers).
    // Equal-width pills with Expanded forced "Build plan with Cue" to
    // truncate at the desktop ConstrainedBox(max: 560) cap. Now each pill
    // takes its natural width; the bar shrink-wraps on desktop and
    // scrolls horizontally on mobile when content exceeds viewport.
    // Phase 4.0.7.27d-population-router-removal — the fluency-only
    // "Plan inputs" pill (which routed to PreTherapyPlanningFluencyScreen)
    // has been removed. The bar is now identical for every client; Phase
    // 2 multi-domain will resurface a domain-aware plan-inputs affordance.
    final pillRow = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _FabBarItem(
          icon:      Icon(Icons.add, size: 14, color: c.teal),
          label:     'Session',
          labelColor: c.teal,
          onTap:     _openAddSession,
        ),
        divider,
        // Phase 5.1+5.2 — "Cue Study" pill REMOVED. Ask Cue lives in
        // the persistent right panel (or drawer on narrow viewports)
        // on this surface, so a duplicate floating-bar entry would be
        // noise. Build plan with Cue stays — it's a separate flow
        // (goal authoring wizard).
        _FabBarItem(
          icon:      const CueCuttlefish(
              size:  CueSize.cuttlefishActionPill,
              state: CueState.idle),
          label:     'Build plan with Cue',
          labelColor: c.textPrimary,
          onTap:     _openGoalAuthoring,
        ),
        divider,
        _FabBarItem(
          icon:      Icon(Icons.more_horiz, size: 16, color: c.textBody),
          label:     null,
          labelColor: c.textBody,
          onTap:     _openMoreSheet,
        ),
      ],
    );

    return Container(
      decoration: BoxDecoration(
        // Phase 5.3 Round A.1.1 — solid bg in both modes. Dark mode's
        // prior 5% white overlay (Color(0x0DFFFFFF)) rendered as nearly
        // invisible against the new neutral #0A0A0B canvas, letting goal
        // text bleed through the bar at scroll boundary.
        color: c.bgCard,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: c.border, width: 0.5),
        boxShadow: [
          BoxShadow(
            color: c.isDark
                ? Colors.black.withValues(alpha: 0.40)
                : Colors.black.withValues(alpha: 0.08),
            blurRadius: 20,
            offset:     const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(6),
      // Mobile wraps the pill row in a horizontal scroll view so labels
      // never truncate even on narrow viewports. Desktop renders the row
      // directly — the bar shrink-wraps to natural content width and is
      // centred by the outer Center widget.
      child: isMobile
          ? SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: pillRow,
            )
          : pillRow,
    );
  }

  // ── Zone 3: Goals ─────────────────────────────────────────────────────────

  Widget _buildGoalsSection(CueColorsResolved c, double hPad, {bool isMobile = false}) {
    final clientName = _client['name'] as String? ?? '';

    // Phase 4.0.7.27c-goals-archive — switched from _spineFuture to
    // _readyFuture so the goals area can read the sessions list and
    // compute the celebrating-vs-archived split. Both futures are
    // already kicked off in initState; reading _readyFuture here costs
    // nothing extra.
    return Padding(
      padding: EdgeInsets.fromLTRB(hPad, 32, hPad, 0),
      child: FutureBuilder<_ReadyData>(
        future: _readyFuture,
        builder: (ctx, snapshot) {
          final allLtgs      = snapshot.data?.spine.ltgs ?? const [];
          final stgs         = snapshot.data?.spine.stgs ?? const [];
          final sessions     = snapshot.data?.sessions   ?? const [];
          final achievedLtgs = allLtgs.where(_isLtgAchieved).toList();
          final activeLtgs   = allLtgs
              .where((l) => _isLtgActive(l) && !_isLtgAchieved(l))
              .toList();
          final inactiveLtgs = allLtgs
              .where((l) => !_isLtgActive(l) && !_isLtgAchieved(l))
              .toList();

          // 27c-goals-archive — celebrating LTGs are achieved goals
          // with no session post-dating their achievement timestamp;
          // archived LTGs are the rest. Sort archive newest-first so
          // the most recent achievement sits at the top when the
          // section expands.
          final celebratingLtgs = <Map<String, dynamic>>[];
          final archivedLtgs    = <Map<String, dynamic>>[];
          for (final ltg in achievedLtgs) {
            if (_hasSessionSinceAchievement(ltg, sessions)) {
              archivedLtgs.add(ltg);
            } else {
              celebratingLtgs.add(ltg);
            }
          }
          archivedLtgs.sort((a, b) {
            final ad = _ltgAchievementCutoff(a);
            final bd = _ltgAchievementCutoff(b);
            if (ad == null && bd == null) return 0;
            if (ad == null) return 1;
            if (bd == null) return -1;
            return bd.compareTo(ad); // DESC
          });

          final activeAndInactive = [...activeLtgs, ...inactiveLtgs];

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Phase 3.3 — corner "+ Generate Plan" pill removed. The
              // action lives in the chart action bar now ("Build plan with
              // Cue") and duplicating it here as a corner pill produced
              // two entry points to the same flow with different visual
              // weights, which was confusing.
              Text(
                'Goals $clientName is working toward'.toUpperCase(),
                style: GoogleFonts.dmSans(
                  fontSize:    10,
                  fontWeight:  FontWeight.w600,
                  color:       c.textBody,
                  letterSpacing: 1.3,
                ),
              ),
              const SizedBox(height: 16),

              if (snapshot.connectionState == ConnectionState.waiting)
                _GoalsSkeleton(c: c)
              else if (achievedLtgs.isEmpty &&
                       activeLtgs.isEmpty &&
                       inactiveLtgs.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    // Phase 3.3 — pointer to the action bar instead of a
                    // corner pill. Wording avoids naming a button position
                    // so the bar can shift in future builds without
                    // stranding this copy.
                    'No goals yet. Build the plan with Cue '
                    'from the action bar below.',
                    style: GoogleFonts.dmSans(
                      fontSize:  14,
                      color:     c.textBody,
                      fontStyle: FontStyle.italic,
                      height:    1.6,
                    ),
                  ),
                )
              else ...[
                // ── SECTION 1: Active (+ inactive) goals ─────────────────
                // 27c-goals-archive: active block now leads. Achieved
                // LTGs no longer occupy the top of the goals area; they
                // either sit in the celebrating section below (until
                // the next session is logged) or in the archive.
                ...activeAndInactive.map((ltg) {
                  final ltgId   = ltg['id'].toString();
                  final ltgStgs = stgs
                      .where((s) =>
                          s['long_term_goal_id']?.toString() == ltgId)
                      .toList();
                  return Opacity(
                    opacity: _isLtgActive(ltg) ? 1.0 : 0.6,
                    child: _buildLtgBlock(c, ltg, ltgId, ltgStgs,
                        isMobile: isMobile),
                  );
                }),

                // ── SECTION 2: Celebrating ──────────────────────────────
                // Pride-of-place treatment held verbatim from the prior
                // build (CelebratingGoalCard with cuttlefish + GOAL
                // ACHIEVED · Mastered eyebrow). Multiple celebrating
                // goals stack vertically; achievement timestamp now
                // sources from achieved_at (falling back to updated_at).
                if (celebratingLtgs.isNotEmpty) ...[
                  if (activeAndInactive.isNotEmpty)
                    const SizedBox(height: CueGap.achievedToActiveGap),
                  ...celebratingLtgs.map((ltg) {
                    final cutoff = _ltgAchievementCutoff(ltg);
                    final achievedDate = cutoff == null
                        ? null
                        : _formatAchievedDate(
                            cutoff.toUtc().toIso8601String());
                    return Padding(
                      padding: const EdgeInsets.only(bottom: CueGap.s16),
                      child: CelebratingGoalCard(
                        goal:         ltg,
                        achievedDate: achievedDate,
                      ),
                    );
                  }),
                ],

                // ── SECTION 3: Achievements archive ─────────────────────
                if (archivedLtgs.isNotEmpty) ...[
                  if (activeAndInactive.isNotEmpty ||
                      celebratingLtgs.isNotEmpty)
                    const SizedBox(height: CueGap.achievedToActiveGap),
                  _AchievementsArchive(
                    c:          c,
                    ltgs:       archivedLtgs,
                    clientName: clientName,
                    onChanged:  _refreshSpine,
                  ),
                ],
              ],
            ],
          );
        },
      ),
    );
  }

  // ── Phase 3.3.7b — Structured conditions render ──────────────────────────
  //
  // Phase 3.3.7a started persisting conditions_text as a JSON-stringified
  // {queued_activities, suitable_instruments, discretion_close} object inside
  // the existing long_term_goals.notes TEXT column. Legacy plans persist the
  // same column as `${title}\n\nConditions: ${plain prose}`. This helper
  // detects the shape and renders accordingly. Backwards compatibility is
  // load-bearing: legacy and structured plans coexist on production charts.
  //
  // Returns a list of widgets (possibly empty) inserted into the LTG card
  // body between the goal_text and the short-term-goals section.
  List<Widget> _buildConditionsBlock(CueColorsResolved c, Map<String, dynamic> ltg) {
    final notes = ltg['notes'] as String?;
    if (notes == null || notes.isEmpty) return const [];

    // notes layout (both shapes): "${title}\n\nConditions: ${payload}".
    // If no "Conditions: " marker exists, there is nothing to render.
    const marker = '\n\nConditions: ';
    final markerAt = notes.indexOf(marker);
    if (markerAt < 0) return const [];
    final raw = notes.substring(markerAt + marker.length).trim();
    if (raw.isEmpty) return const [];

    Map<String, dynamic>? structured;
    try {
      final parsed = jsonDecode(raw);
      if (parsed is Map &&
          parsed.containsKey('queued_activities') &&
          parsed.containsKey('suitable_instruments') &&
          parsed.containsKey('discretion_close')) {
        structured = Map<String, dynamic>.from(parsed);
      }
    } catch (_) {
      // Fall through to legacy render.
    }

    if (structured != null) {
      return [
        const SizedBox(height: CueGap.s16),
        _buildStructuredConditions(c, structured),
      ];
    }

    // Legacy plain-prose render — keeps the "Conditions:" label so older
    // plans continue to read the way clinicians have been reading them.
    return [
      const SizedBox(height: CueGap.s12),
      Text(
        'Conditions: $raw',
        style: GoogleFonts.dmSans(
          fontSize:   13,
          fontWeight: FontWeight.w400,
          color:      c.textPrimary.withValues(alpha: CueAlpha.subtitleText),
          height:     1.6,
        ),
      ),
    ];
  }

  // Phase 3.3.7c — chart consumes only queued_activities. The structured
  // shape from Phase 3.3.7a still carries suitable_instruments and
  // discretion_close; both persist for Goal Authoring's plan-review surface
  // (Phase 3.3.1) and other future contexts. They do not surface here.
  // See CLAUDE.md §13.14 (reasoning-on-tap) and §13.13 (data contract).
  Widget _buildStructuredConditions(CueColorsResolved c, Map<String, dynamic> data) {
    final activities = (data['queued_activities'] as List?)
            ?.whereType<String>()
            .where((s) => s.trim().isNotEmpty)
            .toList() ??
        const <String>[];

    if (activities.isEmpty) return const SizedBox.shrink();

    final bodyStyle = GoogleFonts.dmSans(
      fontSize:   14,
      fontWeight: FontWeight.w400,
      color:      c.textPrimary.withValues(alpha: CueAlpha.bodyText),
      height:     1.55,
    );

    final rows = <Widget>[];
    for (var i = 0; i < activities.length; i++) {
      if (i > 0) {
        rows.add(const SizedBox(height: CueGap.activityListItemGap));
      }
      rows.add(Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              '·',
              style: GoogleFonts.dmSans(
                fontSize:   14,
                fontWeight: FontWeight.w700,
                color:      c.amber.withValues(alpha: 0.5),
                height:     1.55,
              ),
            ),
          ),
          const SizedBox(width: CueGap.s8),
          Expanded(child: Text(activities[i], style: bodyStyle)),
        ],
      ));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: rows,
    );
  }

  Widget _buildLtgBlock(
    CueColorsResolved c,
    Map<String, dynamic> ltg,
    String ltgId,
    List<Map<String, dynamic>> ltgStgs, {
    bool isMobile = false,
  }) {
    final domain       = ltg['domain'] as String? ??
        ltg['category'] as String? ?? '';
    final goalText     = ltg['goal_text'] as String? ?? '';
    final targetDate   = ltg['target_date'] as String?;
    final isEditingLtg = _editingLtgId == ltgId;

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Container(
        decoration: BoxDecoration(
          color:        c.bgCard,
          borderRadius: BorderRadius.circular(16),
          border: c.isDark
              ? Border.all(color: c.border, width: 0.5)
              : null,
          // Phase 5.3 Round A.1.2 — dark register gets a subtle outer
          // elevation shadow where the light-mode card has none. Inset
          // highlight + ring shadows defer to Round B's pillar widgets
          // where the Stack-overlay pattern can be implemented natively.
          boxShadow: c.isDark
              ? const [
                  BoxShadow(
                    color:      Color(0x40000000),
                    blurRadius: 8,
                    offset:     Offset(0, 2),
                  ),
                ]
              : const [
                  BoxShadow(
                    color:      Color(0x0A000000),
                    blurRadius: 12,
                    offset:     Offset(0, 2),
                  ),
                ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          // Stack lets the content size naturally — no IntrinsicHeight pass,
          // so the inline STG editor's multiline TextField can grow without
          // overflowing. The teal gradient bar fills the left edge via
          // Positioned, regardless of how tall the content becomes.
          child: Stack(
            children: [
                Padding(
                  padding:
                      const EdgeInsets.fromLTRB(2.5 + 16, 14, 16, 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Domain + Cue Study link
                        Row(
                          children: [
                            if (domain.isNotEmpty)
                              Text(
                                domain.toUpperCase().replaceAll('_', ' '),
                                style: GoogleFonts.dmSans(
                                  fontSize:    10,
                                  fontWeight:  FontWeight.w700,
                                  color:       c.teal,
                                  letterSpacing: 0.8,
                                ),
                              ),
                            const Spacer(),
                            GestureDetector(
                              onTap: () => _markGoalAchieved(ltg),
                              child: Text(
                                'Mark achieved',
                                style: GoogleFonts.dmSans(
                                    fontSize: 12, color: c.textBody),
                              ),
                            ),
                            // Phase 5.1+5.2 — "Open with Cue →" link
                            // removed. Goal-scoped Ask Cue is reachable
                            // through the embedded AskCuePanel inside
                            // Edit Goal (scope='ltg'); no separate
                            // entry point needed here.
                          ],
                        ),
                        const SizedBox(height: CueGap.s10),

                        // Goal text / inline editor
                        if (isEditingLtg)
                          _LtgInlineEditor(
                            controller: _ltgEditCtrl,
                            domain:     domain,
                            onCancel:   _closeAllEdits,
                            onSave:     () => _saveLtg(ltgId),
                            // Phase 4.0.7.20j — only surface the
                            // "Open with Cue Reasoning" affordance
                            // when the LTG has a real id (which is
                            // always true on this surface — drafts
                            // live on goal_authoring, not here).
                            onOpenWithReasoning: ltgId.isEmpty
                                ? null
                                : () => _openLtgInDeepReasoning(ltg, ltgId),
                          )
                        else
                          GestureDetector(
                            onTap: () => _startEditLtg(ltg),
                            child: Text(
                              goalText,
                              style: c.isDark
                                  ? GoogleFonts.dmSans(
                                      fontSize:   15,
                                      fontWeight: FontWeight.w400,
                                      color:      c.textPrimary,
                                      height:     1.65,
                                    )
                                  : CueType.serif(
                                      fontSize:   16,
                                      fontWeight: FontWeight.w400,
                                      color:      c.textPrimary,
                                      height:     1.7,
                                    ),
                            ),
                          ),

                        // Phase 3.3.7b — structured (or legacy) conditions
                        // block, parsed out of the `notes` column. Renders
                        // nothing if the LTG has no conditions content.
                        ..._buildConditionsBlock(c, ltg),

                        const SizedBox(height: 12),

                        // STG rows
                        if (ltgStgs.isEmpty)
                          Text(
                            'No short-term steps yet.',
                            style: GoogleFonts.dmSans(
                              fontSize:  13,
                              color:     c.textMuted,
                              fontStyle: FontStyle.italic,
                            ),
                          )
                        else
                          ...ltgStgs.where((stg) {
                            final t = stg['specific'] as String? ??
                                stg['goal_text'] as String? ??
                                stg['target_behavior'] as String? ?? '';
                            return t.trim().isNotEmpty;
                          }).map((stg) {
                            final stgId   = stg['id'].toString();
                            final stgText = stg['specific'] as String? ??
                                stg['goal_text'] as String? ??
                                stg['target_behavior'] as String? ?? '';
                            final isActive =
                                (stg['status'] as String?) == 'active';
                            final isEditing = _editingStgId == stgId;

                            if (isEditing) {
                              return _StgInlineEditor(
                                controller: _stgEditCtrl,
                                onCancel:   _closeAllEdits,
                                onSave:     () => _saveStg(stgId),
                              );
                            }
                            return _StgRow(
                              text:      stgText,
                              isActive:  isActive,
                              onEditTap: () => _startEditStg(stg),
                              isMobile:  isMobile,
                            );
                          }),

                        // Add STG
                        if (_addingStgForLtgId == ltgId)
                          Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: _StgInlineEditor(
                              controller:  _addStgCtrl,
                              placeholder:
                                  'Describe the next step toward this goal...',
                              saveLabel: 'Add step',
                              onCancel:  _closeAllEdits,
                              onSave:    () => _submitAddStg(ltgId),
                            ),
                          )
                        else
                          Padding(
                            padding: const EdgeInsets.only(top: 10),
                            child: GestureDetector(
                              onTap: () => _startAddStg(ltgId),
                              child: Text(
                                '+ Add short-term step',
                                style: GoogleFonts.dmSans(
                                    fontSize: 12, color: c.teal),
                              ),
                            ),
                          ),

                        // Target date footer
                        if (targetDate != null) ...[
                          const SizedBox(height: 8),
                          Text(
                            'Target — ${_formatTargetDate(targetDate)}',
                            style: GoogleFonts.dmSans(
                                fontSize: 11, color: c.textBody),
                          ),
                        ],
                      ],
                    ),
                  ),
              // Teal gradient left bar — fills the full content height.
              Positioned(
                left: 0, top: 0, bottom: 0,
                child: Container(
                  width: 2.5,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin:  Alignment.topCenter,
                      end:    Alignment.bottomCenter,
                      colors: [c.teal, c.tealFaded],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Zone 5: Documents ─────────────────────────────────────────────────────

  Widget _buildDocumentsSection(CueColorsResolved c, double hPad) {
    return Padding(
      padding: EdgeInsets.fromLTRB(hPad, 48, hPad, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(height: 0.5, color: c.border),
          const SizedBox(height: 20),
          Text(
            'DOCUMENTS',
            style: GoogleFonts.dmSans(
              fontSize:    10,
              fontWeight:  FontWeight.w600,
              color:       c.textBody,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'No documents uploaded yet.',
            style: GoogleFonts.dmSans(
              fontSize:  14,
              color:     c.textBody,
              fontStyle: FontStyle.italic,
            ),
          ),
          const SizedBox(height: 12),
          GestureDetector(
            onTap: () {},
            child: Text(
              '+ Upload document',
              style: GoogleFonts.dmSans(
                fontSize:   13,
                color:      c.teal,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Floating action bar pieces ────────────────────────────────────────────────

class _FabBarItem extends StatelessWidget {
  final Widget       icon;
  final String?      label;       // null = icon-only (e.g. ⋯ More)
  final Color        labelColor;
  final VoidCallback onTap;

  const _FabBarItem({
    required this.icon,
    required this.label,
    required this.labelColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // Hover/active overlays as opacity tints over the bar's surface tone.
    final overlay = isDark ? Colors.white : Colors.black;

    return Material(
      type: MaterialType.transparency,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        onTap:        onTap,
        borderRadius: BorderRadius.circular(22),
        hoverColor:     overlay.withValues(alpha: 0.05),
        highlightColor: overlay.withValues(alpha: 0.10),
        splashColor:    overlay.withValues(alpha: 0.10),
        child: Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize:      MainAxisSize.min,
            children: [
              icon,
              if (label != null) ...[
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    label!,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.dmSans(
                      fontSize:   13,
                      fontWeight: FontWeight.w500,
                      color:      labelColor,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _FabBarDivider extends StatelessWidget {
  final CueColorsResolved c;
  const _FabBarDivider({required this.c});

  @override
  Widget build(BuildContext context) => Container(
        width:  1,
        height: 24,
        color:  c.border,
      );
}

// ── _LtgInlineEditor ──────────────────────────────────────────────────────────

class _LtgInlineEditor extends StatelessWidget {
  final TextEditingController controller;
  final String       domain;
  final VoidCallback onCancel;
  final VoidCallback onSave;
  /// Phase 4.0.7.20j — optional deep-reasoning escape hatch. When
  /// non-null, an "Open with Cue Reasoning" button renders between
  /// Cancel and Save goal. Tapping saves the inline edit, then pushes
  /// LtgEditScreen with the structured editor + CueReasoningPanel.
  /// Hidden (null) for drafts and any goal without a real id.
  final VoidCallback? onOpenWithReasoning;

  const _LtgInlineEditor({
    required this.controller,
    required this.domain,
    required this.onCancel,
    required this.onSave,
    this.onOpenWithReasoning,
  });

  @override
  Widget build(BuildContext context) {
    final c = CueColorsResolved.of(context);
    return Container(
      decoration: BoxDecoration(
        color:        c.bgCard,
        borderRadius: BorderRadius.circular(14),
        border:       Border.all(color: c.teal),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (domain.isNotEmpty)
                Text(
                  domain.toUpperCase().replaceAll('_', ' '),
                  style: GoogleFonts.dmSans(
                    fontSize:    10,
                    fontWeight:  FontWeight.w700,
                    color:       c.teal,
                    letterSpacing: 0.8,
                  ),
                ),
              const Spacer(),
              GestureDetector(
                onTap: onCancel,
                child: Text(
                  'Cancel',
                  style: GoogleFonts.dmSans(fontSize: 13, color: c.textBody),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          TextField(
            controller: controller,
            maxLines:   null,
            autofocus:  true,
            style: GoogleFonts.dmSans(
              fontSize:    15,
              fontWeight:  FontWeight.w400,
              color:       c.textPrimary,
              letterSpacing: -0.2,
              height:      1.65,
            ),
            decoration: const InputDecoration(
              border:         InputBorder.none,
              isDense:        true,
              contentPadding: EdgeInsets.zero,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              OutlinedButton(
                onPressed: onCancel,
                style: OutlinedButton.styleFrom(
                  foregroundColor: c.textBody,
                  side:            BorderSide(color: c.border),
                  padding:         const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 8),
                  minimumSize:    Size.zero,
                  tapTargetSize:  MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text('Cancel',
                    style: GoogleFonts.dmSans(fontSize: 13)),
              ),
              if (onOpenWithReasoning != null) ...[
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: onOpenWithReasoning,
                  icon: Icon(Icons.subdirectory_arrow_right_rounded,
                      size: 14, color: c.teal),
                  label: Text('Open with Cue Reasoning',
                      style: GoogleFonts.dmSans(
                          fontSize: 12, color: c.teal)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: c.teal,
                    side: BorderSide(
                        color: c.teal.withValues(alpha: 0.45)),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    minimumSize:   Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              ],
              const SizedBox(width: 8),
              FilledButton(
                onPressed: onSave,
                style: FilledButton.styleFrom(
                  backgroundColor: c.teal,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 8),
                  minimumSize:    Size.zero,
                  tapTargetSize:  MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text('Save goal',
                    style: GoogleFonts.dmSans(
                        fontSize: 13, color: Colors.white)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── _StgRow ───────────────────────────────────────────────────────────────────

class _StgRow extends StatefulWidget {
  final String       text;
  final bool         isActive;
  final VoidCallback onEditTap;
  final bool         isMobile;

  const _StgRow({
    required this.text,
    required this.isActive,
    required this.onEditTap,
    this.isMobile = false,
  });

  @override
  State<_StgRow> createState() => _StgRowState();
}

class _StgRowState extends State<_StgRow> {
  bool _editHovered = false;

  @override
  Widget build(BuildContext context) {
    final c = CueColorsResolved.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: widget.isActive
          ? _buildActiveRow(c)
          : Opacity(opacity: 0.45, child: _buildInactiveRow(c)),
    );
  }

  Widget _buildActiveRow(CueColorsResolved c) {
    return Container(
      decoration: BoxDecoration(
        color:        c.tealSurface,
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'ACTIVE STEP',
                  style: GoogleFonts.dmSans(
                    fontSize:    9,
                    fontWeight:  FontWeight.w700,
                    color:       c.teal,
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  widget.text,
                  style: GoogleFonts.dmSans(
                      fontSize: 13, color: c.textPrimary, height: 1.5),
                ),
              ],
            ),
          ),
          _editButton(c),
        ],
      ),
    );
  }

  Widget _buildInactiveRow(CueColorsResolved c) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            width:  1.5,
            color:  c.teal,
            margin: const EdgeInsets.only(right: 12),
          ),
          Expanded(
            child: Text(
              widget.text,
              style: GoogleFonts.dmSans(
                  fontSize: 13, color: c.textPrimary, height: 1.5),
            ),
          ),
          _editButton(c),
        ],
      ),
    );
  }

  Widget _editButton(CueColorsResolved c) {
    if (widget.isMobile) {
      return SizedBox(
        width: 44, height: 44,
        child: InkWell(
          onTap:         widget.onEditTap,
          borderRadius:  BorderRadius.circular(8),
          child: Center(
            child: Icon(Icons.edit_outlined, size: 16, color: c.textBody),
          ),
        ),
      );
    }
    return MouseRegion(
      onEnter: (_) => setState(() => _editHovered = true),
      onExit:  (_) => setState(() => _editHovered = false),
      child: GestureDetector(
        onTap: widget.onEditTap,
        child: Padding(
          padding: const EdgeInsets.only(left: 12),
          child: Align(
            alignment: Alignment.centerRight,
            child: Text(
              'edit',
              style: GoogleFonts.dmSans(
                fontSize: 11,
                color:    _editHovered ? c.teal : c.border,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── _StgInlineEditor ──────────────────────────────────────────────────────────

class _StgInlineEditor extends StatelessWidget {
  final TextEditingController controller;
  final String?      placeholder;
  final String       saveLabel;
  final VoidCallback onCancel;
  final VoidCallback onSave;

  const _StgInlineEditor({
    required this.controller,
    this.placeholder,
    this.saveLabel = 'Save',
    required this.onCancel,
    required this.onSave,
  });

  @override
  Widget build(BuildContext context) {
    final c = CueColorsResolved.of(context);
    return Padding(
      padding: const EdgeInsets.only(left: 14, bottom: 8),
      child: Container(
        // Vertical padding bumped to clear the 8px overflow that occurred
        // inside the LTG block's IntrinsicHeight Row when this card was open.
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 18),
        decoration: BoxDecoration(
          color:        c.bgCard,
          borderRadius: BorderRadius.circular(8),
          border:       Border.all(color: c.teal, width: 0.5),
        ),
        child: Column(
          mainAxisSize:       MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: controller,
              maxLines:   null,
              autofocus:  true,
              style: GoogleFonts.dmSans(
                  fontSize: 13, color: c.textPrimary, height: 1.5),
              decoration: InputDecoration(
                hintText:      placeholder,
                hintStyle:
                    GoogleFonts.dmSans(fontSize: 13, color: c.textBody),
                border:        InputBorder.none,
                isDense:       true,
                contentPadding: EdgeInsets.zero,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                TextButton(
                  onPressed: onCancel,
                  style: TextButton.styleFrom(
                    foregroundColor: c.textBody,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                    minimumSize:   Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text('Cancel',
                      style: GoogleFonts.dmSans(fontSize: 12)),
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: onSave,
                  style: TextButton.styleFrom(
                    foregroundColor: c.teal,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                    minimumSize:   Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text(
                    saveLabel,
                    style: GoogleFonts.dmSans(
                        fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}


// ── _AchievementsArchive ──────────────────────────────────────────────────────
//
// Phase 4.0.7.27c-goals-archive — collapsed-by-default section that
// holds previously-celebrated LTGs once at least one session has been
// logged after their achievement. Smaller cards, no cuttlefish,
// "Mastered · {date}" eyebrow + plain goal text. The section preserves
// the dignity of past achievements without consuming pride-of-place.
class _AchievementsArchive extends StatefulWidget {
  final CueColorsResolved c;
  final List<Map<String, dynamic>> ltgs;
  final String clientName;
  final VoidCallback onChanged;
  const _AchievementsArchive({
    required this.c,
    required this.ltgs,
    required this.clientName,
    required this.onChanged,
  });

  @override
  State<_AchievementsArchive> createState() => _AchievementsArchiveState();
}

class _AchievementsArchiveState extends State<_AchievementsArchive> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    final n = widget.ltgs.length;
    return Container(
      decoration: BoxDecoration(
        color: c.bgCard,
        border: Border.all(color: c.border, width: CueSize.hairline),
        borderRadius: BorderRadius.circular(CueRadius.s16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Toggle row
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: BorderRadius.circular(CueRadius.s16),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: CueGap.s16, vertical: CueGap.s14),
              child: Row(
                children: [
                  Text(
                    'Achievements',
                    style: GoogleFonts.dmSans(
                      fontSize:   14,
                      color:      c.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    _expanded
                        ? '$n ${n == 1 ? 'goal' : 'goals'}'
                        : '$n ${n == 1 ? 'goal achieved' : 'goals achieved'}',
                    style: GoogleFonts.dmSans(
                      fontSize: 12,
                      color:    c.textBody,
                    ),
                  ),
                  const Spacer(),
                  Icon(
                    _expanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    size:  20,
                    color: c.textBody,
                  ),
                ],
              ),
            ),
          ),

          // Expanded list — smaller, dignified entries
          if (_expanded) ...[
            Container(height: CueSize.hairline, color: c.border),
            for (var i = 0; i < widget.ltgs.length; i++) ...[
              _ArchivedLtgRow(
                c:          c,
                ltg:        widget.ltgs[i],
                clientName: widget.clientName,
                onChanged:  widget.onChanged,
              ),
              if (i != widget.ltgs.length - 1)
                Container(height: CueSize.hairline, color: c.border),
            ],
          ],
        ],
      ),
    );
  }
}

class _ArchivedLtgRow extends StatelessWidget {
  final CueColorsResolved c;
  final Map<String, dynamic> ltg;
  final String clientName;
  final VoidCallback onChanged;
  const _ArchivedLtgRow({
    required this.c,
    required this.ltg,
    required this.clientName,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final goalText = ((ltg['goal_text']     as String?) ??
                      (ltg['original_text'] as String?) ??
                      '').trim();
    final cutoff = _ltgAchievementCutoff(ltg);
    final dateLabel = cutoff == null
        ? null
        : _formatAchievedDate(cutoff.toUtc().toIso8601String());

    return InkWell(
      onTap: () async {
        // Reuse the existing LTG detail view. onSaved is a no-op here;
        // we trigger the parent's spine refresh on pop so the archive
        // re-renders if the SLP edited anything inside.
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => LtgEditScreen(
              goal:       ltg,
              clientName: clientName,
              onSaved:    (_) {},
            ),
          ),
        );
        onChanged();
      },
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
            CueGap.s16, CueGap.s12, CueGap.s16, CueGap.s12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              dateLabel == null
                  ? 'MASTERED'
                  : 'MASTERED · ${dateLabel.toUpperCase()}',
              style: GoogleFonts.dmSans(
                fontSize:      10,
                fontWeight:    FontWeight.w600,
                color:         c.teal,
                letterSpacing: 1.3,
              ),
            ),
            if (goalText.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                goalText,
                style: GoogleFonts.dmSans(
                  fontSize: 13,
                  color:    c.textPrimary,
                  height:   1.5,
                ),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── _GoalsSkeleton ────────────────────────────────────────────────────────────

class _GoalsSkeleton extends StatelessWidget {
  final CueColorsResolved c;
  const _GoalsSkeleton({required this.c});

  Widget _bar(double width) => Container(
        width:  width,
        height: 11,
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color:        c.isDark ? c.border : const Color(0xFFE8E4DC),
          borderRadius: BorderRadius.circular(4),
        ),
      );

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _bar(80),
          _bar(double.infinity),
          _bar(double.infinity),
          _bar(160),
        ],
      );
}

// ── Top-level helpers ─────────────────────────────────────────────────────────

bool _isLtgActive(Map<String, dynamic> ltg) {
  final status = ltg['status'] as String?;
  // Phase 4.0.7.23c-deploy — pending_attestation LTGs are v2 drafts that
  // live in Build with Cue until the SLP signs the plan. They are not
  // active clinical goals and must not appear on the client profile's
  // active list, the chip strip, or any "active goals" surface.
  return status != 'discontinued' &&
      status != 'met' &&
      status != 'achieved' &&
      status != 'pending_attestation';
}

bool _isLtgAchieved(Map<String, dynamic> ltg) {
  final status = (ltg['status'] as String?)?.toLowerCase();
  return status == 'achieved';
}

/// Phase 4.0.7.27c-goals-archive — returns the achievement cutoff
/// timestamp for an LTG, preferring the typed `achieved_at` column and
/// falling back to `updated_at` for legacy rows that pre-date the
/// 27c migration. Null only when both are missing.
DateTime? _ltgAchievementCutoff(Map<String, dynamic> ltg) {
  final raw = (ltg['achieved_at'] as String?) ??
      (ltg['updated_at'] as String?);
  if (raw == null || raw.isEmpty) return null;
  try {
    return DateTime.parse(raw).toLocal();
  } catch (_) {
    return null;
  }
}

/// Phase 4.0.7.27c-goals-archive — true iff at least one session row
/// has a date on or after the LTG's achievement cutoff. Drives the
/// celebrating-vs-archived split: while no session has been logged
/// since achievement, the LTG sits in pride-of-place; once a session
/// post-dates the cutoff, it collapses into the achievements archive.
///
/// Sessions are matched on the `date` column (YYYY-MM-DD). The cutoff
/// timestamp is reduced to its local calendar day before comparison so
/// a same-day post-achievement session moves the LTG into the archive
/// (matching the spec's `.gte('date', achievedAt)` semantics).
bool _hasSessionSinceAchievement(
    Map<String, dynamic> ltg, List<Map<String, dynamic>> sessions) {
  final cutoff = _ltgAchievementCutoff(ltg);
  if (cutoff == null) return false;
  final cutoffDate = DateTime(cutoff.year, cutoff.month, cutoff.day);
  for (final s in sessions) {
    final dateStr = s['date'] as String?;
    if (dateStr == null) continue;
    final d = DateTime.tryParse(dateStr);
    if (d == null) continue;
    final sessionDate = DateTime(d.year, d.month, d.day);
    if (sessionDate.isAfter(cutoffDate)) return true;
  }
  return false;
}

String? _formatAchievedDate(String? iso) {
  if (iso == null || iso.isEmpty) return null;
  try {
    final d = DateTime.parse(iso).toLocal();
    const months = [
      '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${d.day} ${months[d.month]} ${d.year}';
  } catch (_) {
    return null;
  }
}

String _extractSoapPreview(Map<String, dynamic> session) {
  // Phase 4.0.7.27c-cleanup2 / 4.0.7.31c — three-tier fallback. Order:
  // soap_note (clinical observation) → parent_summary (proxy-generated
  // parent message) → notes (SLP's own prose from SessionCaptureScreen
  // 4.0.7.28). Returns empty when nothing matches; the timeline card's
  // subtitle render guard suppresses an empty subtitle row, and the
  // footer pill carries the documentation-status signal alone.
  String truncate(String s) =>
      s.length > 100 ? '${s.substring(0, 100)}...' : s;

  final note = session['soap_note'];
  if (note != null) {
    try {
      final map = note is String
          ? jsonDecode(note) as Map<String, dynamic>
          : note as Map<String, dynamic>;
      final observation = (map['observation'] as String?) ??
          (map['O'] as String?) ??
          (map['o'] as String?) ??
          '';
      if (observation.trim().isNotEmpty) {
        return truncate(observation);
      }
    } catch (_) {}
  }
  final parentSummary = (session['parent_summary'] as String?)?.trim();
  if (parentSummary != null && parentSummary.isNotEmpty) {
    return truncate(parentSummary);
  }
  final notes = (session['notes'] as String?)?.trim();
  if (notes != null && notes.isNotEmpty) {
    return truncate(notes);
  }
  return '';
}

String _formatTargetDate(String dateStr) {
  final dt = DateTime.tryParse(dateStr);
  if (dt == null) return dateStr;
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  return '${dt.day.toString().padLeft(2, '0')} '
      '${months[dt.month - 1]} ${dt.year}';
}
