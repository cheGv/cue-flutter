import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/name_formatter.dart';
import '../theme/cue_theme.dart';
import '../theme/cue_tokens.dart';
import '../theme/cue_typography.dart';
import '../utils/chart_context.dart';
import '../utils/daily_chart_log.dart';
import '../widgets/app_layout.dart';
import '../widgets/brief_thought_view.dart';
import '../widgets/cue_cuttlefish.dart';
import '../widgets/cue_study_icon.dart';
import '../widgets/goal_achieved_overlay.dart';
import '../widgets/noticed_moment.dart';
import 'report_screen.dart';
import 'add_session_screen.dart';
import 'add_client_screen.dart';
import 'cue_study_screen.dart';
import 'goal_authoring_screen.dart';
import 'ltg_edit_screen.dart';
import 'pre_therapy_planning_fluency_screen.dart';

// ── Theme-aware colour swatch ─────────────────────────────────────────────────
class _C {
  final bool   isDark;
  final Color  bg, surface, ink, ghost, muted, line, teal, tealBg, tealFaded, amber;

  const _C({
    required this.isDark,
    required this.bg,
    required this.surface,
    required this.ink,
    required this.ghost,
    required this.muted,
    required this.line,
    required this.teal,
    required this.tealBg,
    required this.tealFaded,
    required this.amber,
  });

  static _C of(BuildContext ctx) {
    final dark = Theme.of(ctx).brightness == Brightness.dark;
    return dark ? _night : _day;
  }

  static const _day = _C(
    isDark:    false,
    bg:        Color(0xFFFAF7F0),
    surface:   Color(0xFFFFFFFF),
    ink:       Color(0xFF0D1B2A),
    ghost:     Color(0xFF6B7280),
    muted:     Color(0xFF9CA3AF),
    line:      Color(0xFFE5E1D8),
    teal:      Color(0xFF2A8F72),
    tealBg:    Color(0xFFE8F5F0),
    tealFaded: Color(0x4D2A8F72),
    amber:     Color(0xFFD97706),
  );

  static const _night = _C(
    isDark:    true,
    bg:        Color(0xFF0F1923),
    surface:   Color(0xFF162230),
    ink:       Color(0xFFF0EBE1),
    ghost:     Color(0xFF8A9BB0),
    muted:     Color(0xFF4A5A70),
    line:      Color(0xFF243040),
    teal:      Color(0xFF34D399),
    tealBg:    Color(0xFF0A2A1A),
    tealFaded: Color(0x4D34D399),
    amber:     Color(0xFFF59E0B),
  );
}

// ── Timeline data model ───────────────────────────────────────────────────────
enum TimelineEntryType { session, goalSet, goalAchieved, assessment, upload, milestone }

class TimelineEntry {
  final DateTime date;
  final TimelineEntryType type;
  final String title;
  final String? subtitle;
  final String? referenceId;
  final Map<String, dynamic>? rawData;

  const TimelineEntry({
    required this.date,
    required this.type,
    required this.title,
    this.subtitle,
    this.referenceId,
    this.rawData,
  });
}

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

  // Key for scrolling Zone 2 (Cue Study Brief) into view
  final _cueStudyKey = GlobalKey();

  // Context data for the legacy Cue Study FAB sheet — populated by
  // _populateCsFabContext but no longer read in Phase 1, since the action bar
  // pill now navigates directly to CueStudyScreen and chart_context.dart
  // rebuilds context per turn. Preserved as dead code per spec.
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
                .eq('date', todayStr);
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

  // ── Navigation ────────────────────────────────────────────────────────────

  Future<void> _openGoalAuthoring() async {
    final population = _client['population_type'] as String? ?? 'asd_aac';
    final clientId = _client['id'].toString();
    final clientName = _client['name'] as String? ?? '';
    final sessionCount = _client['total_sessions'] as int? ?? 0;

    // Phase 4.0.7 — for developmental_stuttering clients, gate Build-plan
    // on Layer-04 plan_inputs being locked. If they aren't yet, route
    // through the pre-therapy planning surface first; that screen calls
    // pushReplacement → GoalAuthoringScreen on lock+proceed.
    if (population == 'developmental_stuttering') {
      final locked = await isPlanInputsLocked(
        supabase: _supabase,
        clientId: clientId,
      );
      if (!locked) {
        if (!mounted) return;
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => PreTherapyPlanningFluencyScreen(
              clientId:     clientId,
              clientName:   clientName,
              sessionCount: sessionCount,
            ),
          ),
        );
        if (mounted) _refreshSpine();
        return;
      }
    }

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
    if (added == true && mounted) {
      setState(() {
        _sessionsFuture = _fetchSessions();
        _spineFuture    = _fetchSpine();
        _readyFuture    = _makeReadyFuture();
      });
    }
  }

  // Legacy LTG editor route — replaced in Phase 1 by _openCueStudyForGoal.
  // Preserved as dead code per spec ("we may reference it").
  // ignore: unused_element
  void _openLtgEdit(Map<String, dynamic> ltg) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => LtgEditScreen(
          goal:       ltg,
          clientName: _client['name'] as String? ?? '',
          onSaved:    (_) { if (mounted) _refreshSpine(); },
        ),
      ),
    );
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
    final c = _C.of(context);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: c.surface,
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
                color: c.line,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 12),
            ListTile(
              leading: Icon(Icons.edit_outlined, color: c.teal, size: 20),
              title: Text(
                'Edit client details',
                style: GoogleFonts.dmSans(fontSize: 15, color: c.ink),
              ),
              onTap: () {
                Navigator.pop(sheetCtx);
                _openEditClient();
              },
            ),
            ListTile(
              leading: Icon(Icons.download_outlined, color: c.ghost, size: 20),
              title: Text(
                'Export chart',
                style: GoogleFonts.dmSans(fontSize: 15, color: c.ghost),
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

  // Navigates to the persistent Cue Study chat thread for this client. The
  // legacy one-shot sheet (CueStudyFab.openSheet) is kept as dead code in
  // case we want to reference it; Phase 1 routes through CueStudyScreen.
  void _openCueStudySheet() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CueStudyScreen(
          clientId:   _client['id'].toString(),
          clientData: _client,
        ),
      ),
    );
  }

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
      await _supabase
          .from('long_term_goals')
          .update({'status': 'achieved', 'updated_at': updatedAt})
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
      ...ltg, 'status': 'achieved', 'updated_at': updatedAt,
    };

    // Full-screen overlay; auto-dismisses after 3s.
    await showDialog<void>(
      context: context,
      barrierColor: Colors.black54,
      builder: (_) => GoalAchievedOverlay(goal: updatedGoal),
    );

    if (mounted) _refreshSpine();
  }

  void _openCueStudyForGoal(Map<String, dynamic> ltg) {
    final goalText = ((ltg['goal_text']     as String?) ??
                      (ltg['original_text'] as String?) ?? '').trim();
    final initial = goalText.isEmpty
        ? 'Help me think about this goal.'
        : 'Help me think about this goal: $goalText';
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CueStudyScreen(
          clientId:       _client['id'].toString(),
          clientData:     _client,
          initialMessage: initial,
        ),
      ),
    );
  }

  // Placeholder Ask sheet — Phase 3.3 removed the magnifying-glass
  // affordance from the action bar. Per CLAUDE.md §14.3 natural-language
  // retrieval is the Phase 4 "Practice" sidebar surface, not a chart-
  // scoped action. This handler stays as dead code so the intent-
  // classifier prototype can be referenced when Practice is built.
  // ignore: unused_element
  void _openAskSheet() {
    final c          = _C.of(context);
    final clientName = (_client['name'] as String?) ?? 'this child';
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: c.surface,
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
                  color:        c.line,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),
              TextField(
                autofocus: true,
                maxLines:  null,
                style: GoogleFonts.dmSans(fontSize: 16, color: c.ink),
                decoration: InputDecoration(
                  hintText: 'Ask about $clientName...',
                  hintStyle: GoogleFonts.dmSans(
                      fontSize: 16, color: c.ghost),
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
      // The floating action bar covers Cue Study on this screen — suppress
      // the global FAB so we don't render two surfaces for the same action.
      cueStudyFab: const SizedBox.shrink(),
      body: LayoutBuilder(
        builder: (ctx, constraints) {
          final hPad     = constraints.maxWidth > 500 ? 24.0 : 16.0;
          final isMobile = constraints.maxWidth < 600;
          final lc       = _C.of(ctx);
          return Stack(
            fit: StackFit.expand,
            children: [
              // Scroll view fills the body via Positioned.fill — guarantees
              // it is a SIBLING of the floating bar (never a child), so the
              // bar is fixed to the viewport, not the scroll extent.
              Positioned.fill(
                child: ColoredBox(
                  color: lc.bg,
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 680),
                      child: CustomScrollView(
                        slivers: [
                          // ── Zone 1: Identity ────────────────────────────
                          SliverToBoxAdapter(
                            child: _buildClientHeader(lc, hPad),
                          ),

                          // ── Cue noticed (Phase 2) ───────────────────────
                          // Detection runs over the loaded chart data;
                          // shows nothing if no special moment matches.
                          SliverToBoxAdapter(
                            child: FutureBuilder<_ReadyData>(
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
                            ),
                          ),

                          // ── Zone 2: Brief thought (Phase 2 + 3.2.2) ─────
                          // Outer FutureBuilder gates on _readyFuture so we
                          // can detect empty-chart state (no sessions AND no
                          // active LTGs) and short-circuit with a templated
                          // brief — never asking the LLM to speculate about
                          // a chart it has no data for. Charts with data go
                          // through BriefThoughtView's proxy fetch path.
                          SliverToBoxAdapter(
                            child: SizedBox(
                              key: _cueStudyKey,
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
                                      onThinkWithCue: _openCueStudySheet,
                                      padding: EdgeInsets.fromLTRB(
                                          hPad,
                                          CueGap.s24,
                                          hPad,
                                          CueGap.s24),
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
                                        onThinkWithCue: _openCueStudySheet,
                                        padding: EdgeInsets.fromLTRB(
                                            hPad,
                                            CueGap.s24,
                                            hPad,
                                            CueGap.s24),
                                      );
                                    },
                                  );
                                },
                              ),
                            ),
                          ),

                          // ── Zone 3: Goals ───────────────────────────────
                          SliverToBoxAdapter(
                            child: _buildGoalsSection(
                                lc, hPad, isMobile: isMobile),
                          ),

                          // ── Zone 4: Timeline ────────────────────────────
                          SliverToBoxAdapter(
                            child: FutureBuilder<_ReadyData>(
                              future: _readyFuture,
                              builder: (ctx2, snap) {
                                final lc2 = _C.of(ctx2);
                                if (snap.connectionState ==
                                    ConnectionState.waiting) {
                                  return _buildTimelineLoading(lc2, hPad);
                                }
                                return _buildTimeline(
                                  snap.data?.timeline ?? [],
                                  lc2, hPad,
                                  clientId, clientName,
                                );
                              },
                            ),
                          ),

                          // ── Zone 5: Documents ───────────────────────────
                          SliverToBoxAdapter(
                            child: _buildDocumentsSection(lc, hPad),
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
            ],
          );
        },
      ),
    );
  }

  // ── Zone 1: Identity header ───────────────────────────────────────────────

  Widget _buildClientHeader(_C c, double hPad) {
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
      color:   c.bg,
      padding: EdgeInsets.fromLTRB(hPad, 28, hPad, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            name,
            style: CueType.serif(
              fontSize:    38,
              fontWeight:  FontWeight.w700,
              color:       c.ink,
              letterSpacing: -1.0,
              height:      1.1,
            ),
          ),
          if (metaParts.isNotEmpty) ...[
            const SizedBox(height: 5),
            Text(
              metaParts.join(' · '),
              style: GoogleFonts.dmSans(fontSize: 14, color: c.ghost),
            ),
          ],
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
                    color: c.ghost,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCadenceRow(_C c) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _sessionsFuture,
      builder: (ctx, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return Container(
            width: 140, height: 10,
            decoration: BoxDecoration(
              color:        c.line,
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
              Container(width: 1, height: 12, color: c.line),
              const SizedBox(width: 10),
              Text(
                spanLabel,
                style: GoogleFonts.dmSans(fontSize: 12, color: c.muted),
              ),
            ],
          ],
        );
      },
    );
  }

  // ── Floating action bar ───────────────────────────────────────────────────

  Widget _buildFloatingActionBar(_C c, {required bool isMobile}) {
    final divider = _FabBarDivider(c: c);

    // Phase 3.3.1: pills are variable-width (no Expanded wrappers).
    // Equal-width pills with Expanded forced "Build plan with Cue" to
    // truncate at the desktop ConstrainedBox(max: 560) cap. Now each pill
    // takes its natural width; the bar shrink-wraps on desktop and
    // scrolls horizontally on mobile when content exceeds viewport.
    // Phase 4.0.7 — show a "Plan inputs" pill between Session and Build
    // plan for developmental_stuttering clients. asd_aac sees the bar
    // unchanged.
    final population = _client['population_type'] as String? ?? 'asd_aac';
    final showPlanInputs = population == 'developmental_stuttering';

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
        if (showPlanInputs) ...[
          _FabBarItem(
            icon:      Icon(Icons.tune, size: 14, color: c.amber),
            label:     'Plan inputs',
            labelColor: c.amber,
            onTap:     _openPlanInputs,
          ),
          divider,
        ],
        _FabBarItem(
          // Cue Study — the conversational clinical reasoning surface.
          // Phase 3.3: renamed from "Ask Cue" for codebase-vocabulary
          // consistency.
          icon:      const CueCuttlefish(
              size:  CueSize.cuttlefishActionPill,
              state: CueState.idle),
          label:     'Cue Study',
          labelColor: c.amber,
          onTap:     _openCueStudySheet,
        ),
        divider,
        _FabBarItem(
          // Phase 3.3: primary chart-scoped clinical action. Per §14.3
          // natural-language retrieval moves to the Phase 4 Practice
          // sidebar entry — this is not "Ask".
          icon:      const CueCuttlefish(
              size:  CueSize.cuttlefishActionPill,
              state: CueState.idle),
          label:     'Build plan with Cue',
          labelColor: c.ink,
          onTap:     _openGoalAuthoring,
        ),
        divider,
        _FabBarItem(
          icon:      Icon(Icons.more_horiz, size: 16, color: c.ghost),
          label:     null,
          labelColor: c.ghost,
          onTap:     _openMoreSheet,
        ),
      ],
    );

    return Container(
      decoration: BoxDecoration(
        color: c.isDark
            ? const Color(0x0DFFFFFF)
            : c.surface,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: c.line, width: 0.5),
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

  Widget _buildGoalsSection(_C c, double hPad, {bool isMobile = false}) {
    final clientName = _client['name'] as String? ?? '';

    return Padding(
      padding: EdgeInsets.fromLTRB(hPad, 32, hPad, 0),
      child: FutureBuilder<_SpineData>(
        future: _spineFuture,
        builder: (ctx, snapshot) {
          final allLtgs      = snapshot.data?.ltgs ?? [];
          final stgs         = snapshot.data?.stgs ?? [];
          final achievedLtgs = allLtgs.where(_isLtgAchieved).toList();
          final activeLtgs   = allLtgs
              .where((l) => _isLtgActive(l) && !_isLtgAchieved(l))
              .toList();
          final inactiveLtgs = allLtgs
              .where((l) => !_isLtgActive(l) && !_isLtgAchieved(l))
              .toList();

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
                  color:       c.ghost,
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
                      color:     c.ghost,
                      fontStyle: FontStyle.italic,
                      height:    1.6,
                    ),
                  ),
                )
              else ...[
                // ── Achieved goals (Phase 2) — celebrating cards on top ──
                ...achievedLtgs.map((ltg) {
                  final achievedDate = _formatAchievedDate(
                      ltg['updated_at'] as String?);
                  return Padding(
                    padding: const EdgeInsets.only(bottom: CueGap.s16),
                    child: CelebratingGoalCard(
                      goal:         ltg,
                      achievedDate: achievedDate,
                    ),
                  );
                }),
                if (achievedLtgs.isNotEmpty &&
                    (activeLtgs.isNotEmpty || inactiveLtgs.isNotEmpty))
                  const SizedBox(height: CueGap.achievedToActiveGap),

                // ── Active + inactive (legacy LTG block) ─────────────────
                ...[...activeLtgs, ...inactiveLtgs].map((ltg) {
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
  List<Widget> _buildConditionsBlock(_C c, Map<String, dynamic> ltg) {
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
          color:      c.ink.withValues(alpha: CueAlpha.subtitleText),
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
  Widget _buildStructuredConditions(_C c, Map<String, dynamic> data) {
    final activities = (data['queued_activities'] as List?)
            ?.whereType<String>()
            .where((s) => s.trim().isNotEmpty)
            .toList() ??
        const <String>[];

    if (activities.isEmpty) return const SizedBox.shrink();

    final bodyStyle = GoogleFonts.dmSans(
      fontSize:   14,
      fontWeight: FontWeight.w400,
      color:      c.ink.withValues(alpha: CueAlpha.bodyText),
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
    _C c,
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
          color:        c.surface,
          borderRadius: BorderRadius.circular(16),
          border: c.isDark
              ? Border.all(color: c.line, width: 0.5)
              : null,
          boxShadow: c.isDark
              ? null
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
                                    fontSize: 12, color: c.ghost),
                              ),
                            ),
                            const SizedBox(width: CueGap.s14),
                            GestureDetector(
                              onTap: () => _openCueStudyForGoal(ltg),
                              child: Text(
                                'Open with Cue →',
                                style: GoogleFonts.dmSans(
                                    fontSize: 12, color: c.teal),
                              ),
                            ),
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
                                      color:      c.ink,
                                      height:     1.65,
                                    )
                                  : CueType.serif(
                                      fontSize:   16,
                                      fontWeight: FontWeight.w400,
                                      color:      c.ink,
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
                              color:     c.muted,
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
                                fontSize: 11, color: c.ghost),
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

  // ── Zone 4: Timeline ──────────────────────────────────────────────────────

  Widget _buildTimelineLoading(_C c, double hPad) {
    return Padding(
      padding: EdgeInsets.fromLTRB(hPad, 48, hPad, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(height: 0.5, color: c.line),
          const SizedBox(height: 20),
          Text(
            'TIMELINE',
            style: GoogleFonts.dmSans(
              fontSize:    10,
              fontWeight:  FontWeight.w600,
              color:       c.ghost,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 24),
          Center(
            child: CircularProgressIndicator(
                strokeWidth: 1.5, color: c.teal),
          ),
        ],
      ),
    );
  }

  Widget _buildTimeline(
    List<TimelineEntry> entries,
    _C c,
    double hPad,
    String clientId,
    String clientName,
  ) {
    return Padding(
      padding: EdgeInsets.fromLTRB(hPad, 48, hPad, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(height: 0.5, color: c.line),
          const SizedBox(height: 20),
          Text(
            'TIMELINE',
            style: GoogleFonts.dmSans(
              fontSize:    10,
              fontWeight:  FontWeight.w600,
              color:       c.ghost,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 20),

          if (entries.isEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                'Sessions and goals will appear here as you document them.',
                style: GoogleFonts.dmSans(
                  fontSize:  14,
                  color:     c.ghost,
                  fontStyle: FontStyle.italic,
                  height:    1.6,
                ),
              ),
            )
          else
            // Stack: teal line (Positioned) behind entry Column
            Stack(
              children: [
                // Continuous teal line at x=83 (center of 24px spine, after 72px date col)
                Positioned(
                  left:  83,
                  top:   0,
                  bottom: 0,
                  child: Container(width: 2, color: c.tealFaded),
                ),
                Column(
                  children: entries
                      .map((e) => _buildTimelineEntry(
                            e, c, clientId, clientName))
                      .toList(),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildTimelineEntry(
    TimelineEntry entry,
    _C c,
    String clientId,
    String clientName,
  ) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final dayStr = entry.date.day.toString();
    final monStr = months[entry.date.month - 1];

    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Date column — 72px, right-aligned
          SizedBox(
            width: 72,
            child: Padding(
              padding: const EdgeInsets.only(top: 1, right: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    dayStr,
                    style: GoogleFonts.dmSans(
                      fontSize:   13,
                      fontWeight: FontWeight.w600,
                      color:      c.ghost,
                    ),
                  ),
                  Text(
                    monStr,
                    style: GoogleFonts.dmSans(fontSize: 10, color: c.muted),
                  ),
                ],
              ),
            ),
          ),
          // Spine — 24px; dot centered on the Positioned teal line
          SizedBox(
            width: 24,
            child: Align(
              alignment: Alignment.topCenter,
              child: Container(
                width:  10,
                height: 10,
                margin: const EdgeInsets.only(top: 3),
                decoration: BoxDecoration(
                  shape:  BoxShape.circle,
                  color:  c.surface,
                  border: Border.all(color: c.teal, width: 2),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Content card — expanded
          Expanded(
            child: _buildEntryCard(entry, c, clientId, clientName),
          ),
        ],
      ),
    );
  }

  Widget _buildEntryCard(
    TimelineEntry entry,
    _C c,
    String clientId,
    String clientName,
  ) {
    switch (entry.type) {
      case TimelineEntryType.session:
        return _buildSessionCard(entry, c, clientId, clientName);
      case TimelineEntryType.goalSet:
        return _buildGoalSetCard(entry, c);
      case TimelineEntryType.goalAchieved:
        return _buildGoalAchievedCard(entry, c);
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildSessionCard(
    TimelineEntry entry,
    _C c,
    String clientId,
    String clientName,
  ) {
    final hasNote = entry.rawData?['soap_note'] != null;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color:        c.surface,
        borderRadius: BorderRadius.circular(12),
        border: c.isDark ? Border.all(color: c.line, width: 0.5) : null,
        boxShadow: c.isDark
            ? null
            : const [
                BoxShadow(
                  color:      Color(0x08000000),
                  blurRadius: 8,
                  offset:     Offset(0, 2),
                ),
              ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Session · ${entry.title}',
            style: GoogleFonts.dmSans(
              fontSize:    10,
              fontWeight:  FontWeight.w600,
              color:       c.teal,
              letterSpacing: 0.5,
            ),
          ),
          if (entry.subtitle != null && entry.subtitle!.isNotEmpty) ...[
            const SizedBox(height: 5),
            Text(
              entry.subtitle!,
              style: GoogleFonts.dmSans(
                fontSize:  13,
                color:     c.ghost,
                fontStyle: FontStyle.italic,
                height:    1.5,
              ),
              maxLines:  2,
              overflow:  TextOverflow.ellipsis,
            ),
          ],
          const SizedBox(height: 8),
          GestureDetector(
            onTap: hasNote && entry.rawData != null
                ? () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ReportScreen(
                          session:    entry.rawData!,
                          clientName: clientName,
                          clientId:   clientId,
                        ),
                      ),
                    )
                : null,
            child: hasNote
                ? Text(
                    'View note →',
                    style: GoogleFonts.dmSans(
                      fontSize:   12,
                      color:      c.teal,
                      fontWeight: FontWeight.w600,
                    ),
                  )
                : Text(
                    'Pending documentation',
                    style: GoogleFonts.dmSans(
                      fontSize:   12,
                      color:      c.amber,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildGoalSetCard(TimelineEntry entry, _C c) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color:        c.tealBg,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            entry.title,
            style: GoogleFonts.dmSans(
              fontSize:   11,
              fontWeight: FontWeight.w600,
              color:      c.teal,
            ),
          ),
        ),
        if (entry.subtitle != null && entry.subtitle!.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            entry.subtitle!,
            style: GoogleFonts.dmSans(
                fontSize: 13, color: c.ink, height: 1.5),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
        const SizedBox(height: 4),
      ],
    );
  }

  Widget _buildGoalAchievedCard(TimelineEntry entry, _C c) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color:        c.amber.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            '✓ ${entry.title}',
            style: GoogleFonts.dmSans(
              fontSize:   11,
              fontWeight: FontWeight.w600,
              color:      c.amber,
            ),
          ),
        ),
        if (entry.subtitle != null && entry.subtitle!.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            entry.subtitle!,
            style: GoogleFonts.dmSans(
                fontSize: 13, color: c.ink, height: 1.5),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
        const SizedBox(height: 4),
      ],
    );
  }

  // ── Zone 5: Documents ─────────────────────────────────────────────────────

  Widget _buildDocumentsSection(_C c, double hPad) {
    return Padding(
      padding: EdgeInsets.fromLTRB(hPad, 48, hPad, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(height: 0.5, color: c.line),
          const SizedBox(height: 20),
          Text(
            'DOCUMENTS',
            style: GoogleFonts.dmSans(
              fontSize:    10,
              fontWeight:  FontWeight.w600,
              color:       c.ghost,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'No documents uploaded yet.',
            style: GoogleFonts.dmSans(
              fontSize:  14,
              color:     c.ghost,
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
  final _C c;
  const _FabBarDivider({required this.c});

  @override
  Widget build(BuildContext context) => Container(
        width:  1,
        height: 24,
        color:  c.line,
      );
}

// ── _LtgInlineEditor ──────────────────────────────────────────────────────────

class _LtgInlineEditor extends StatelessWidget {
  final TextEditingController controller;
  final String       domain;
  final VoidCallback onCancel;
  final VoidCallback onSave;

  const _LtgInlineEditor({
    required this.controller,
    required this.domain,
    required this.onCancel,
    required this.onSave,
  });

  @override
  Widget build(BuildContext context) {
    final c = _C.of(context);
    return Container(
      decoration: BoxDecoration(
        color:        c.surface,
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
                  style: GoogleFonts.dmSans(fontSize: 13, color: c.ghost),
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
              color:       c.ink,
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
                  foregroundColor: c.ghost,
                  side:            BorderSide(color: c.line),
                  padding:         const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 8),
                  minimumSize:    Size.zero,
                  tapTargetSize:  MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text('Cancel',
                    style: GoogleFonts.dmSans(fontSize: 13)),
              ),
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
    final c = _C.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: widget.isActive
          ? _buildActiveRow(c)
          : Opacity(opacity: 0.45, child: _buildInactiveRow(c)),
    );
  }

  Widget _buildActiveRow(_C c) {
    return Container(
      decoration: BoxDecoration(
        color:        c.tealBg,
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
                      fontSize: 13, color: c.ink, height: 1.5),
                ),
              ],
            ),
          ),
          _editButton(c),
        ],
      ),
    );
  }

  Widget _buildInactiveRow(_C c) {
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
                  fontSize: 13, color: c.ink, height: 1.5),
            ),
          ),
          _editButton(c),
        ],
      ),
    );
  }

  Widget _editButton(_C c) {
    if (widget.isMobile) {
      return SizedBox(
        width: 44, height: 44,
        child: InkWell(
          onTap:         widget.onEditTap,
          borderRadius:  BorderRadius.circular(8),
          child: Center(
            child: Icon(Icons.edit_outlined, size: 16, color: c.ghost),
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
                color:    _editHovered ? c.teal : c.line,
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
    final c = _C.of(context);
    return Padding(
      padding: const EdgeInsets.only(left: 14, bottom: 8),
      child: Container(
        // Vertical padding bumped to clear the 8px overflow that occurred
        // inside the LTG block's IntrinsicHeight Row when this card was open.
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 18),
        decoration: BoxDecoration(
          color:        c.surface,
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
                  fontSize: 13, color: c.ink, height: 1.5),
              decoration: InputDecoration(
                hintText:      placeholder,
                hintStyle:
                    GoogleFonts.dmSans(fontSize: 13, color: c.ghost),
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
                    foregroundColor: c.ghost,
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

// ── _CueStudyBrief ────────────────────────────────────────────────────────────

class _CueStudyBrief extends StatefulWidget {
  final Map<String, dynamic> client;
  final Future<_ReadyData>   readyFuture;
  final double               hPad;

  const _CueStudyBrief({
    required this.client,
    required this.readyFuture,
    required this.hPad,
  });

  @override
  State<_CueStudyBrief> createState() => _CueStudyBriefState();
}

class _CueStudyBriefState extends State<_CueStudyBrief>
    with TickerProviderStateMixin {
  static const _proxyBase  = 'https://cue-ai-proxy.onrender.com';
  static const _system =
      'You are Cue, a clinical co-pilot for Speech-Language Pathologists. '
      'Generate a concise pre-session brief using only the data provided — '
      'never invent observations, scores, or recommendations not grounded in the data. '
      'Respond in plain text only, no markdown, no bullet points, maximum 8 lines.';

  static const _csAmber     = Color(0xFFF59E0B);
  static const _csAmberDark = Color(0xFFD97706);

  late final AnimationController _orbitController;
  late final AnimationController _pulseController;
  late final Animation<double>   _pulseAnim;

  bool    _loading = true;
  String? _text;
  double  _opacity = 0.0;

  @override
  void initState() {
    super.initState();
    _orbitController = AnimationController(
      vsync:    this,
      duration: const Duration(milliseconds: 3000),
    )..repeat();
    _pulseController = AnimationController(
      vsync:    this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);
    _pulseAnim =
        Tween<double>(begin: 0.4, end: 1.0).animate(_pulseController);

    widget.readyFuture.then(_generateBrief).catchError((_) {
      if (mounted) setState(() => _loading = false);
    });
  }

  @override
  void dispose() {
    _orbitController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _generateBrief(_ReadyData data) async {
    try {
      final text = await _callProxy(data);
      if (mounted) {
        setState(() {
          _text    = text;
          _loading = false;
        });
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() => _opacity = 1.0);
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<String> _callProxy(_ReadyData data) async {
    // Legacy _CueStudyBrief has its own `client` field; the chart-screen
    // bulk-rename to `_client` (Phase 3.3.4) doesn't apply here.
    final cl = widget.client;
    final sb = StringBuffer();

    sb.writeln('CLIENT: ${cl['name'] ?? 'not documented'}'
        ', Age ${cl['age'] ?? 'not documented'}');
    sb.writeln('Diagnosis: ${cl['diagnosis'] ?? 'not documented'}');
    sb.writeln();

    final ltgs = data.spine.ltgs;
    if (ltgs.isNotEmpty) {
      sb.writeln('LONG-TERM GOALS:');
      for (final ltg in ltgs) {
        final domain =
            ltg['domain'] != null ? ' (${ltg['domain']})' : '';
        sb.writeln('- ${ltg['goal_text'] ?? 'not documented'}$domain');
      }
      sb.writeln();
    }

    final activeStgs = data.spine.stgs
        .where((s) => (s['status'] as String?) == 'active')
        .toList();
    if (activeStgs.isNotEmpty) {
      sb.writeln('ACTIVE SHORT-TERM GOALS:');
      for (final stg in activeStgs) {
        final goalText = stg['specific'] ??
            stg['goal_text'] ??
            stg['target_behavior'] ??
            'not documented';
        final level = stg['current_cue_level'];
        sb.writeln('- $goalText');
        if (level != null) sb.writeln('  Support level: $level');
      }
      sb.writeln();
    }

    final lastSession =
        data.sessions.isNotEmpty ? data.sessions.first : null;
    if (lastSession != null) {
      sb.writeln(
          'LAST SESSION DATE: ${lastSession['date'] ?? 'not documented'}');
      final soap  = lastSession['soap_note'];
      final notes = lastSession['notes'] as String?;
      if (soap is Map && soap.isNotEmpty) {
        if (soap['s'] != null) sb.writeln('S: ${soap['s']}');
        if (soap['o'] != null) sb.writeln('O: ${soap['o']}');
        if (soap['a'] != null) sb.writeln('A: ${soap['a']}');
        if (soap['p'] != null) sb.writeln('P: ${soap['p']}');
      } else if (notes != null && notes.isNotEmpty) {
        sb.writeln('Notes: $notes');
      } else {
        sb.writeln('SOAP note: not documented');
      }
      sb.writeln();
    }

    sb.writeln('Generate a pre-session brief with these sections in order:');
    sb.writeln(
        'LAST SESSION: one-line snapshot of what was worked on and overall accuracy');
    sb.writeln(
        "TODAY'S FOCUS: active STGs, current support level, push vs consolidate recommendation based on accuracy trend");
    sb.writeln(
        'PATTERN FLAG: ONLY include this line if accuracy has dropped or plateaued across 3 or more consecutive evidence rows. If no pattern, omit entirely.');
    sb.writeln(
        'SUGGESTED MOVE: one sentence clinical recommendation for today');

    final supabase = Supabase.instance.client;
    final token    = supabase.auth.currentSession?.accessToken;

    final response = await http
        .post(
          Uri.parse('$_proxyBase/pre-session-brief'),
          headers: {
            'Content-Type': 'application/json',
            if (token != null) 'Authorization': 'Bearer $token',
          },
          body: jsonEncode({
            'model':        'claude-sonnet-4-20250514',
            'system':       _system,
            'user_message': sb.toString(),
            'client_id':    widget.client['id'].toString(),
          }),
        )
        .timeout(const Duration(seconds: 30));

    if (response.statusCode != 200) {
      throw Exception('proxy ${response.statusCode}');
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final text = body['content']?[0]?['text'] ??
        body['brief'] ??
        body['text'] ??
        response.body;
    return text.toString().trim();
  }

  @override
  Widget build(BuildContext context) {
    final c = _C.of(context);

    return Padding(
      padding: EdgeInsets.fromLTRB(widget.hPad, 20, widget.hPad, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            decoration: BoxDecoration(
              gradient: c.isDark
                  ? null
                  : const LinearGradient(
                      begin: Alignment.topLeft,
                      end:   Alignment.bottomRight,
                      colors: [
                        Color(0xFFFEF5DF),
                        Color(0xFFF9E9B8),
                        Color(0xFFF5E0A0),
                      ],
                    ),
              color:        c.isDark ? const Color(0x0FD97706) : null,
              borderRadius: BorderRadius.circular(18),
              border: c.isDark
                  ? Border.all(
                      color: const Color(0x20D97706), width: 0.5)
                  : null,
              boxShadow: c.isDark
                  ? null
                  : const [
                      BoxShadow(
                        color:      Color(0x10000000),
                        blurRadius: 16,
                        offset:     Offset(0, 4),
                      ),
                    ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: Stack(
                children: [
                  if (!c.isDark)
                    const Positioned(
                      top: -30, right: -30,
                      child: SizedBox(
                        width: 100, height: 100,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: RadialGradient(
                              colors: [
                                Color(0x30D97706),
                                Colors.transparent,
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 18, 24, 18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            SizedBox(
                              width: 18, height: 18,
                              child: FittedBox(
                                fit:   BoxFit.contain,
                                child: CueStudyIcon(),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              "CUE STUDY · today's brief",
                              style: GoogleFonts.dmSans(
                                fontSize:    10,
                                fontWeight:  FontWeight.w600,
                                color:       _csAmberDark,
                                letterSpacing: 0.8,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        if (_loading)
                          _buildLoading()
                        else if (_text == null || _text!.trim().isEmpty)
                          _buildEmpty(c)
                        else
                          _buildLoaded(c),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          Container(
            margin: const EdgeInsets.only(top: 20),
            height: 0.5,
            color:  c.line,
          ),
        ],
      ),
    );
  }

  Widget _buildLoading() {
    return SizedBox(
      height: 32,
      child: Stack(
        alignment: Alignment.center,
        children: [
          RotationTransition(
            turns: _orbitController,
            child: SizedBox(
              width: 32, height: 32,
              child: Align(
                alignment: const Alignment(0.625, 0),
                child: Container(
                  width: 5, height: 5,
                  decoration: const BoxDecoration(
                    color: _csAmberDark, shape: BoxShape.circle,
                  ),
                ),
              ),
            ),
          ),
          AnimatedBuilder(
            animation: _pulseAnim,
            builder: (ctx, child) => Opacity(
              opacity: _pulseAnim.value,
              child: Container(
                width: 7, height: 7,
                decoration: const BoxDecoration(
                  color: _csAmber, shape: BoxShape.circle,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty(_C c) {
    return Text(
      'No session data yet. This will populate after the first documented session.',
      style: GoogleFonts.dmSans(
        fontSize:  13,
        color:     c.ghost,
        fontStyle: FontStyle.italic,
        height:    1.5,
      ),
    );
  }

  Widget _buildLoaded(_C c) {
    return AnimatedOpacity(
      opacity:  _opacity,
      duration: const Duration(milliseconds: 800),
      child: c.isDark
          ? Text(
              _text!,
              style: GoogleFonts.dmSans(
                fontSize: 14, color: c.ink, height: 1.7,
              ),
            )
          : Text(
              _text!,
              style: CueType.serif(
                fontSize:   22,
                fontWeight: FontWeight.w400,
                color:      const Color(0xFF0D1B2A),
                height:     1.6,
              ),
            ),
    );
  }
}

// ── _GoalsSkeleton ────────────────────────────────────────────────────────────

class _GoalsSkeleton extends StatelessWidget {
  final _C c;
  const _GoalsSkeleton({required this.c});

  Widget _bar(double width) => Container(
        width:  width,
        height: 11,
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color:        c.isDark ? c.line : const Color(0xFFE8E4DC),
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
  return status != 'discontinued' && status != 'met' && status != 'achieved';
}

bool _isLtgAchieved(Map<String, dynamic> ltg) {
  final status = (ltg['status'] as String?)?.toLowerCase();
  return status == 'achieved';
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
  final note = session['soap_note'];
  if (note == null) return 'Session documented';
  try {
    final map = note is String
        ? jsonDecode(note) as Map<String, dynamic>
        : note as Map<String, dynamic>;
    final observation = (map['observation'] as String?) ??
        (map['O'] as String?) ??
        (map['o'] as String?) ??
        '';
    if (observation.trim().isNotEmpty) {
      return observation.length > 100
          ? '${observation.substring(0, 100)}...'
          : observation;
    }
  } catch (_) {}
  return 'Session documented';
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
