// lib/screens/client_profile_screen.dart
//
// Phase B chart rebuild — "Reading Room" register (design locked 2026-05-22).
// Replaces the Phase 4.1 masthead/meta-card chart with a single scrollable
// surface composed from lib/widgets/chart/* sub-widgets.
//
// Read-only: this prompt (2 of 3) renders + binds data. Action chips, the
// recall surface, and write flows are placeholders; routing + state land in
// prompt 3. Stub points are marked `STUB (prompt 3)`.
//
// The class name stays [ClientProfileScreen] (and the file path is unchanged)
// so the /clients/:clientId route wiring and the deep-link loader keep working.

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
// supabase_flutter re-exports gotrue's Session; hide it so `Session` here means
// our sessions-table model.
import 'package:supabase_flutter/supabase_flutter.dart' hide Session;

import '../models/citation.dart';
import '../models/client_chart_state.dart';
import '../models/session.dart';
import '../models/short_term_goal.dart';
import '../models/stg_session_metric.dart';
import '../repositories/cas_session_progress_repository.dart';
import '../repositories/citations_repository.dart';
import '../repositories/client_chart_state_repository.dart';
import '../repositories/client_view_log_repository.dart';
import '../repositories/format_templates_repository.dart';
import '../repositories/ltg_repository.dart';
import '../repositories/sessions_repository.dart';
import '../repositories/stg_metrics_repository.dart';
import '../repositories/stg_repository.dart';
import '../services/session_headline_service.dart';
import '../theme/cue_color_scheme.dart';
import '../theme/cue_text_styles.dart';
import '../utils/chart_navigation.dart';
import '../models/client_brief_signals.dart';
import '../models/long_term_goal.dart';
import '../utils/client_brief_phrasing.dart';
import '../utils/stg_numbering.dart';
import '../widgets/app_layout.dart';
import '../widgets/archive_dialog.dart';
import '../widgets/chart/chart_action_chips.dart';
import '../widgets/chart/chart_card.dart';
import '../widgets/chart/chart_footer_meta.dart';
import '../widgets/chart/chart_format.dart';
import '../widgets/chart/chart_header.dart';
import '../widgets/chart/chart_lifecycle_goals.dart';
import '../widgets/chart/chart_ltg_anchor.dart';
import '../widgets/chart/chart_narrator.dart';
import '../widgets/chart/chart_session_history.dart';
import '../widgets/chart/chart_stg_compact.dart';
import '../widgets/chart/chart_stg_focus.dart';
import '../widgets/chart/chart_stg_section.dart';
import '../widgets/chart/chart_substrate_link_strip.dart';
import '../widgets/chart/chart_trajectory_strip.dart';
import '../widgets/chart/goal_lifecycle_menu.dart';
import '../widgets/recall_assistant/recall_assistant_controller.dart';
import 'archived_goals_screen.dart';

// ── Aggregated chart data ──────────────────────────────────────────────────

class _ChartData {
  final ClientChartState state;
  final List<ShortTermGoal> activeStgs;
  // Non-active but non-archived STGs, preserved for clinical history.
  final List<ShortTermGoal> completedStgs; // status achieved/mastered
  final List<ShortTermGoal> closedStgs; // status discontinued
  // Every non-archived STG (active + completed + closed) — drives the
  // trajectory tracks + the shared number map, so closed/completed history
  // doesn't vanish from the viz.
  final List<ShortTermGoal> visibleStgs;
  final Map<String, List<Citation>> citationsByStg;
  final Map<String, List<StgSessionMetric>> metricsByStg;
  final Map<String, String> stgNumbers;
  final String? initialFocusId;
  final List<Session> sessions;
  // CAS dial data (cas_session_progress) keyed by session id → STG ids.
  // Merge input for the trajectory strip: dial-only sessions carry no
  // sessions.outcome, so without this they'd read as "never logged
  // progress". Empty for non-CAS clients (and on read failure — additive,
  // never blocks the chart load).
  final Map<int, Set<String>> casStgIdsBySession;
  final DateTime? earliestSessionDate;
  final DateTime? firstSessionDate;
  final bool sessionToday;
  final String? ltgText;
  final int? ltgSeq;
  final int? ltgMonthsTotal;
  final int? ltgCurrentMonth;
  final DateTime? ltgAuthoredDate;
  // LTG lifecycle (primary LTG). Null id ⇒ no LTG yet (controls hidden).
  final String? ltgId;
  final LtgStatus ltgStatus;
  // Client briefing — Layer 1's PRIOR last-viewed timestamp (before this open),
  // folded into the load so Layer 2/3 compute the brief from one consistent
  // snapshot. Null ⇒ first visit.
  final DateTime? priorViewedAt;

  const _ChartData({
    required this.state,
    required this.activeStgs,
    required this.completedStgs,
    required this.closedStgs,
    required this.visibleStgs,
    required this.citationsByStg,
    required this.metricsByStg,
    required this.stgNumbers,
    required this.initialFocusId,
    required this.sessions,
    required this.casStgIdsBySession,
    required this.earliestSessionDate,
    required this.firstSessionDate,
    required this.sessionToday,
    required this.ltgText,
    required this.ltgSeq,
    required this.ltgMonthsTotal,
    required this.ltgCurrentMonth,
    required this.ltgAuthoredDate,
    required this.ltgId,
    required this.ltgStatus,
    required this.priorViewedAt,
  });
}

// ── Screen ──────────────────────────────────────────────────────────────────

class ClientProfileScreen extends StatefulWidget {
  final Map<String, dynamic> client;
  const ClientProfileScreen({super.key, required this.client});

  @override
  State<ClientProfileScreen> createState() => _ClientProfileScreenState();
}

class _ClientProfileScreenState extends State<ClientProfileScreen> {
  final _historyKey = GlobalKey<ChartSessionHistoryState>();

  late final String _clientId = widget.client['id'].toString();
  late final String _clientName =
      (widget.client['name'] as String?)?.trim().isNotEmpty == true
          ? (widget.client['name'] as String).trim()
          : 'Client';

  late Future<_ChartData> _future;

  // Phase C — Cue Mirror, Component Two. Whether the SLP has ≥1 confirmed
  // format template; gates the "Generate report" chip (disabled with a hint
  // when none exist). Loaded once; never blocks the chart's own load.
  Future<bool> _hasConfirmedTemplate = Future<bool>.value(false);

  // Client briefing — Layer 1: the PRIOR "last viewed" timestamp for this
  // (clinician, client), captured on open BEFORE we stamp now(). Held in
  // memory this session; the brief (later layers) consumes it to compute
  // "since your last visit". null = first-ever visit by this clinician.
  Future<DateTime?> _priorViewedAt = Future<DateTime?>.value(null);

  // Locally-held in-focus STG. Null until the first compact-row tap, after
  // which it overrides the loaded initialFocusId. Reset on retry/reload.
  String? _focusedStgId;

  // Lazily-generated session headlines (the status-band brief is deterministic).
  final Map<int, String> _headlineOverrides = {};

  @override
  void initState() {
    super.initState();
    // Auth-null guard — mirror of the deep-link loaders in main.dart.
    if (Supabase.instance.client.auth.currentUser == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final ret = Uri.encodeQueryComponent('/clients/$_clientId');
        Navigator.pushReplacementNamed(context, '/login?return=$ret');
      });
    } else {
      // Scope the global recall surface (⌘K + "ask Cue" pill) to this client,
      // so an unnamed recall query resolves against this client. Deferred to a
      // post-frame to avoid notifyListeners() during the overlay's build.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        recallAssistantController.setFocusedClient(_clientId, _clientName);
      });
      // Phase C — does this clinician have a confirmed format to draft in?
      _hasConfirmedTemplate = FormatTemplatesRepository()
          .listForUser()
          .then((all) => all.any((t) => t.isConfirmed))
          .catchError((Object _) => false);

      // Client briefing — Layer 1: read-then-write the last-viewed anchor.
      // Fetch the PRIOR timestamp (what the brief consumes) THEN stamp now().
      // CRITICAL: read before write, or "since last visit" is always "now".
      // Best-effort; never blocks the chart's own load.
      _priorViewedAt = ClientViewLogRepository()
          .readPriorThenRecord(_clientId)
          .catchError((Object _) => null);
      // Layer 1 only — confirm capture in debug; no brief UI yet.
      _priorViewedAt.then((prior) {
        if (!mounted) return;
        if (kDebugMode) {
          debugPrint('[brief L1] $_clientId prior last-viewed: '
              '${prior?.toIso8601String() ?? 'first visit'}');
        }
      });
    }
    _startLoad();
  }

  void _startLoad() {
    _future = _load();
    _future.then((d) {
      if (mounted) _kickAi(d);
    }).catchError((Object _) {});
  }

  /// Fire this load's lazy session-headline generation for the top sessions.
  /// The status-band brief is now computed DETERMINISTICALLY in [_body] from
  /// the Layer 2 signals (no narrator AI call — the facts are structured).
  void _kickAi(_ChartData d) {
    setState(() => _headlineOverrides.clear());

    final headlines = SessionHeadlineService();
    for (final s in d.sessions.take(8)) {
      if (s.aiHeadline?.trim().isNotEmpty ?? false) continue;
      headlines.headlineFor(s).then((text) {
        if (!mounted || text == null) return;
        setState(() => _headlineOverrides[s.id] = text);
      });
    }
  }

  void _retry() => setState(() {
        _focusedStgId = null;
        _startLoad();
      });

  Future<_ChartData> _load() async {
    final results = await Future.wait([
      ClientChartStateRepository().loadForClient(_clientId),
      StgRepository().listForClient(_clientId),
      SessionsRepository().loadForClient(_clientId),
      LtgRepository().listForClient(_clientId),
      CitationsRepository().loadCitationsForClient(_clientId),
      StgRepository().loadFocusedStgForClient(_clientId),
      // CAS dial-data merge input. Best-effort: a failure yields an empty
      // map (chart falls back to outcome-only counting) rather than
      // failing the whole profile load.
      CasSessionProgressRepository()
          .stgIdsBySessionForClient(_clientId)
          .catchError((Object _) => <int, Set<String>>{}),
    ]);

    final state = (results[0] as ClientChartState?) ?? _fallbackState();
    final allStgs = results[1] as List<ShortTermGoal>;
    final sessions = results[2] as List<Session>;
    final ltgs = results[3] as List<Map<String, dynamic>>;
    final citations = results[4] as List<Citation>;
    final focused = results[5] as ShortTermGoal?;
    final casStgIdsBySession = results[6] as Map<int, Set<String>>;

    // allStgs already excludes archived (StgRepository filters deleted_at).
    // Split the remainder by clinical status into the active working set and
    // the history sections. Completed = achieved/mastered; Closed =
    // discontinued; everything else (active/on-hold/modified) stays active.
    int bySeq(ShortTermGoal a, ShortTermGoal b) =>
        (a.sequenceNum ?? 1 << 30).compareTo(b.sequenceNum ?? 1 << 30);
    final activeStgs = allStgs
        .where((s) => !s.status.isCompleted && !s.status.isClosed)
        .toList()
      ..sort(bySeq);
    final completedStgs =
        allStgs.where((s) => s.status.isCompleted).toList()..sort(bySeq);
    final closedStgs =
        allStgs.where((s) => s.status.isClosed).toList()..sort(bySeq);
    // Trajectory + number map cover all visible (non-archived) STGs so closed/
    // completed history persists in the viz.
    final visibleStgs = [...activeStgs, ...completedStgs, ...closedStgs];

    // Group citations by STG (compact-row counts + the focus card's ladder).
    final citationsByStg = <String, List<Citation>>{};
    for (final c in citations) {
      (citationsByStg[c.stgId] ??= <Citation>[]).add(c);
    }

    // Display numbers ("1.A") for every visible STG.
    final stgNumbers = {
      for (final s in visibleStgs) s.id: stgNumber(s, allStgs, ltgs),
    };

    // Preload sparkline metrics for every active STG so focus shifts are
    // synchronous (active STG counts are small in practice).
    final metricsByStg = <String, List<StgSessionMetric>>{};
    if (activeStgs.isNotEmpty) {
      final lists = await Future.wait(
        activeStgs.map((s) => StgMetricsRepository().loadMetricsForStg(s.id)),
      );
      for (var i = 0; i < activeStgs.length; i++) {
        metricsByStg[activeStgs[i].id] = lists[i];
      }
    }

    // Initial focus: the recency-based STG when it's active, else first active.
    String? initialFocusId;
    if (focused != null && activeStgs.any((s) => s.id == focused.id)) {
      initialFocusId = focused.id;
    } else if (activeStgs.isNotEmpty) {
      initialFocusId = activeStgs.first.id;
    }

    // Earliest session date drives the trajectory window + the eyebrow.
    DateTime? earliest;
    for (final s in sessions) {
      final d = s.date ?? s.createdAt;
      if (earliest == null || d.isBefore(earliest)) earliest = d;
    }
    final sessionToday = sessions.any((s) => isToday(s.date));

    // Primary LTG display fields (anchor). Horizon is approximate.
    final ltg = ltgs.isNotEmpty ? ltgs.first : null;
    final ltgId = ltg?['id']?.toString();
    final ltgStatus = LtgStatus.fromString(ltg?['status'] as String?);
    final ltgText = (ltg?['goal_text'] as String?) ??
        (ltg?['original_text'] as String?);
    final ltgSeq = (ltg?['sequence_num'] as num?)?.toInt();
    int? monthsTotal;
    int? currentMonth;
    final weeks = (ltg?['time_frame_weeks'] as num?)?.toInt();
    if (weeks != null && weeks > 0) {
      monthsTotal = (weeks / 4.345).round();
      final created = DateTime.tryParse(ltg?['created_at']?.toString() ?? '');
      if (created != null && monthsTotal > 0) {
        final elapsed =
            (DateTime.now().difference(created).inDays / 30.44).floor() + 1;
        currentMonth = elapsed.clamp(1, monthsTotal);
      }
    }

    // Fold in Layer 1's prior last-viewed value (the read-then-write was
    // kicked off in initState; awaiting it here resolves the brief from one
    // consistent snapshot). Tolerant: a failure already mapped to null.
    final priorViewedAt = await _priorViewedAt;

    return _ChartData(
      state: state,
      activeStgs: activeStgs,
      completedStgs: completedStgs,
      closedStgs: closedStgs,
      visibleStgs: visibleStgs,
      citationsByStg: citationsByStg,
      metricsByStg: metricsByStg,
      stgNumbers: stgNumbers,
      initialFocusId: initialFocusId,
      sessions: sessions,
      casStgIdsBySession: casStgIdsBySession,
      earliestSessionDate: earliest,
      firstSessionDate: earliest,
      sessionToday: sessionToday,
      ltgText: ltgText,
      ltgSeq: ltgSeq,
      ltgMonthsTotal: monthsTotal,
      ltgCurrentMonth: currentMonth,
      ltgAuthoredDate:
          DateTime.tryParse(ltg?['created_at']?.toString() ?? ''),
      ltgId: ltgId,
      ltgStatus: ltgStatus,
      priorViewedAt: priorViewedAt,
    );
  }

  ClientChartState _fallbackState() => ClientChartState(
        clientId: _clientId,
        clientName: _clientName,
        age: (widget.client['age'] as num?)?.toInt() ?? 0,
        diagnosis: widget.client['diagnosis'] as String?,
      );

  String get _firstName {
    final cleaned = _clientName.replaceAll(RegExp(r'\(.*\)'), '').trim();
    return cleaned.split(RegExp(r'\s+')).first;
  }

  void _openSubstrate() =>
      ChartNavigation.openSubstrate(context, clientId: _clientId);

  void _reload() {
    if (mounted) setState(_startLoad);
  }

  // ── Goal lifecycle handlers ───────────────────────────────────────────────
  //
  // All SOFT. Status changes keep goals visible (Completed/Closed); archive
  // hides them with an Undo. Sessions/evidence are never touched. Each refreshes
  // the chart on completion.

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _snackUndo(String message, Future<void> Function() onUndo) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 6),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () async {
            try {
              await onUndo();
            } finally {
              _reload();
            }
          },
        ),
      ));
  }

  Future<void> _setStgStatus(ShortTermGoal stg, StgStatus status) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await StgRepository().setStatus(stg.id, status);
    } catch (e) {
      messenger
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text("Couldn't update goal: $e")));
      return;
    }
    _reload();
    _snack('Marked “${stg.specific.trim().isEmpty ? 'goal' : stg.specific.trim()}” ${status.displayLabel().toLowerCase()}.');
  }

  Future<void> _archiveStg(ShortTermGoal stg) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await StgRepository().archive(stg.id);
    } catch (e) {
      messenger
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text("Couldn't archive goal: $e")));
      return;
    }
    _reload();
    _snackUndo('Short-term goal archived.',
        () => StgRepository().restore(stg.id));
  }

  Future<void> _setLtgStatus(String ltgId, LtgStatus status) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await LtgRepository().setStatus(ltgId, status);
    } catch (e) {
      messenger
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text("Couldn't update goal: $e")));
      return;
    }
    _reload();
    _snack('Long-term goal marked ${status.displayLabel().toLowerCase()}.');
  }

  Future<void> _archiveLtg(String ltgId) async {
    final messenger = ScaffoldMessenger.of(context);
    // Confirmation required when the LTG has live child STGs — warn they go too.
    final childCount = await StgRepository().activeChildCount(ltgId);
    if (!mounted) return;
    if (childCount > 0) {
      final res = await showArchiveDialog(
        context: context,
        title: 'Archive long-term goal?',
        body: 'This long-term goal has $childCount short-term '
            '${childCount == 1 ? 'goal' : 'goals'}. Archiving it will archive '
            '${childCount == 1 ? 'that goal' : 'those goals'} too. Nothing is '
            'deleted — you can undo this.',
        reasons: const [],
      );
      if (!res.confirmed) return;
    }
    try {
      await LtgRepository().archiveCascade(ltgId);
    } catch (e) {
      messenger
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text("Couldn't archive goal: $e")));
      return;
    }
    _reload();
    _snackUndo(
      childCount > 0
          ? 'Long-term goal and its $childCount short-term '
              '${childCount == 1 ? 'goal' : 'goals'} archived.'
          : 'Long-term goal archived.',
      () => LtgRepository().restoreCascade(ltgId),
    );
  }

  void _onChip(String id, _ChartData d) {
    switch (id) {
      case 'capture_session':
        ChartNavigation.captureSession(
          context,
          clientId: _clientId,
          clientName: _clientName,
        ).then((_) => _reload());
        return;
      case 'primary':
        _onPrimary(d);
        return;
      case 'open_substrate':
        _openSubstrate();
        return;
      case 'review_last_session':
        if (d.sessions.isNotEmpty) {
          _historyKey.currentState?.revealSession(d.sessions.first.id);
        }
        return;
      case 'new_stg':
        ChartNavigation.newStg(
          context,
          clientId: _clientId,
          clientName: _clientName,
          sessionCount: d.state.totalSessionCount,
        ).then((_) => _reload());
        return;
    }
  }

  void _onPrimary(_ChartData d) {
    switch (resolvePrimaryAction(d.state, sessionToday: d.sessionToday)) {
      case ChartPrimaryAction.authorLtg:
        ChartNavigation.authorLtg(
          context,
          clientId: _clientId,
          clientName: _clientName,
          sessionCount: d.state.totalSessionCount,
        ).then((_) => _reload());
        return;
      case ChartPrimaryAction.documentLastSession:
        _documentLastSession(d);
        return;
      case ChartPrimaryAction.planTodaySession:
      case ChartPrimaryAction.planNextSession:
        ChartNavigation.planSession(
          context,
          clientId: _clientId,
          clientName: _clientName,
          seedFocus: d.state.lastNextSessionFocus,
        ).then((_) => _reload());
        return;
    }
  }

  void _documentLastSession(_ChartData d) {
    Session? target;
    for (final s in d.sessions) {
      // sessions are newest-first; first un-attested = most recent undocumented.
      if (s.clinicianAttested != true) {
        target = s;
        break;
      }
    }
    if (target == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('All sessions documented.')),
      );
      return;
    }
    ChartNavigation.documentSession(
      context,
      clientId: _clientId,
      sessionId: target.id,
    ).then((_) => _reload());
  }

  @override
  Widget build(BuildContext context) {
    return AppLayout(
      title: _clientName,
      activeRoute: 'roster',
      body: LayoutBuilder(
        builder: (context, constraints) {
          final tokens = CueChartTokens.of(context);
          final isCompact = constraints.maxWidth < 768;
          return ColoredBox(
            color: tokens.bgCanvas,
            child: FutureBuilder<_ChartData>(
              future: _future,
              builder: (context, snap) {
                if (snap.hasError) {
                  return _ChartError(
                    message: '${snap.error}',
                    onRetry: _retry,
                  );
                }
                if (!snap.hasData) {
                  return _ChartSkeleton(isCompact: isCompact);
                }
                return _body(snap.data!, isCompact);
              },
            ),
          );
        },
      ),
    );
  }

  Widget _body(_ChartData d, bool isCompact) {
    final hPad = isCompact ? 16.0 : 24.0;
    final s = d.state;

    // Derive the in-focus STG from local tap state (falls back to the loaded
    // initialFocusId, then to the first active STG).
    final focusId = _focusedStgId ?? d.initialFocusId;
    final ShortTermGoal? focus = d.activeStgs.isEmpty
        ? null
        : d.activeStgs.firstWhere((stg) => stg.id == focusId,
            orElse: () => d.activeStgs.first);
    final compact = focus == null
        ? const <ShortTermGoal>[]
        : d.activeStgs.where((stg) => stg.id != focus.id).toList();
    final focusCitations = focus == null
        ? const <Citation>[]
        : (List<Citation>.from(d.citationsByStg[focus.id] ?? const <Citation>[])
          ..sort((a, b) => a.displayOrder.compareTo(b.displayOrder)));
    final focusMetrics = focus == null
        ? const <StgSessionMetric>[]
        : (d.metricsByStg[focus.id] ?? const <StgSessionMetric>[]);
    final focusHasToday = focus != null &&
        d.sessions
            .any((x) => x.shortTermGoalId == focus.id && isToday(x.date));
    final evidenceCount = {
      for (final e in d.citationsByStg.entries) e.key: e.value.length,
    };
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;

    // Client briefing (Layers 2 + 3): compute the factual signals from this
    // load's snapshot, then phrase them deterministically (no AI) for the
    // status band.
    final briefSignals = ClientBriefSignals.compute(
      priorViewedAt: d.priorViewedAt,
      sessions: d.sessions,
      activeStgs: d.activeStgs,
      stgCodes: d.stgNumbers,
      now: DateTime.now(),
    );
    final briefText = phraseClientBrief(briefSignals, clientName: _firstName);

    return SingleChildScrollView(
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1080),
          child: Padding(
            padding: EdgeInsets.fromLTRB(hPad, 12, hPad, 96),
            // Cards on canvas — 16px between every card.
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Breadcrumb(),
                const SizedBox(height: 12),
                ChartHeader(
                  state: s,
                  firstSessionDate: d.firstSessionDate,
                  sessionToday: d.sessionToday,
                  isCompact: isCompact,
                ),
                const SizedBox(height: 16),
                ChartNarrator(
                  state: s,
                  clientName: _firstName,
                  // Deterministic Layer 3 brief replaces the old AI narrator
                  // text as the band's content source (same band + styling).
                  aiText: briefText,
                  loading: false,
                ),
                const SizedBox(height: 16),
                ChartActionChips(
                  state: s,
                  sessionToday: d.sessionToday,
                  clientName: _firstName,
                  onChipTap: (id) => _onChip(id, d),
                ),
                const SizedBox(height: 16),
                _GenerateReportChip(
                  hasConfirmedTemplate: _hasConfirmedTemplate,
                  onTap: () => Navigator.pushNamed(
                    context,
                    '/clients/$_clientId/draft-report',
                  ),
                ),
                const SizedBox(height: 16),
                ChartLtgAnchor(
                  ltgText: d.ltgText,
                  ltgSeq: d.ltgSeq,
                  monthsTotal: d.ltgMonthsTotal,
                  currentMonth: d.ltgCurrentMonth,
                  substrateCellCount: s.substrateCellCount,
                  authoredDate: d.ltgAuthoredDate,
                  onEditLtg: d.ltgText == null
                      ? null
                      : () => ChartNavigation.authorLtg(
                            context,
                            clientId: _clientId,
                            clientName: _clientName,
                            sessionCount: s.totalSessionCount,
                          ).then((_) => _reload()),
                  // Lifecycle controls only when a real LTG exists.
                  phase: (d.ltgText == null || d.ltgId == null)
                      ? null
                      : (d.ltgStatus.isCompleted
                          ? GoalLifecyclePhase.completed
                          : d.ltgStatus.isClosed
                              ? GoalLifecyclePhase.closed
                              : GoalLifecyclePhase.active),
                  statusLabel: d.ltgStatus.isActiveLifecycle
                      ? null
                      : d.ltgStatus.displayLabel(),
                  onMarkAchieved: d.ltgId == null
                      ? null
                      : () => _setLtgStatus(d.ltgId!, LtgStatus.achieved),
                  onMarkDiscontinued: d.ltgId == null
                      ? null
                      : () => _setLtgStatus(d.ltgId!, LtgStatus.discontinued),
                  onReactivate: d.ltgId == null
                      ? null
                      : () => _setLtgStatus(d.ltgId!, LtgStatus.active),
                  onArchive:
                      d.ltgId == null ? null : () => _archiveLtg(d.ltgId!),
                ),
                if (d.activeStgs.isNotEmpty && focus != null) ...[
                  const SizedBox(height: 16),
                  ChartStgSection(
                    activeCount: d.activeStgs.length,
                    onNewStg: () => _onChip('new_stg', d),
                    focus: AnimatedSwitcher(
                      duration: Duration(milliseconds: reduceMotion ? 0 : 200),
                      child: ChartStgFocus(
                        key: ValueKey(focus.id),
                        stg: focus,
                        stgNumber: d.stgNumbers[focus.id] ??
                            'STG ${focus.sequenceNum ?? '—'}',
                        metrics: focusMetrics,
                        citations: focusCitations,
                        hasSessionToday: focusHasToday,
                        isCompact: isCompact,
                        onMarkAchieved: () =>
                            _setStgStatus(focus, StgStatus.achieved),
                        onMarkDiscontinued: () =>
                            _setStgStatus(focus, StgStatus.discontinued),
                        onArchive: () => _archiveStg(focus),
                      ),
                    ),
                    compact: compact.isEmpty
                        ? null
                        : ChartStgCompact(
                            stgs: compact,
                            evidenceCountByStg: evidenceCount,
                            stgNumbers: d.stgNumbers,
                            onTapStg: (id) =>
                                setState(() => _focusedStgId = id),
                          ),
                  ),
                ],
                // Completed / Closed history — visible but out of the active
                // set, never in focus. Each renders only when non-empty.
                if (d.completedStgs.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  ChartLifecycleGoals(
                    title: 'Completed',
                    phase: GoalLifecyclePhase.completed,
                    stgs: d.completedStgs,
                    stgNumbers: d.stgNumbers,
                    onReactivate: (stg) =>
                        _setStgStatus(stg, StgStatus.active),
                    onArchive: _archiveStg,
                  ),
                ],
                if (d.closedStgs.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  ChartLifecycleGoals(
                    title: 'Closed',
                    phase: GoalLifecyclePhase.closed,
                    stgs: d.closedStgs,
                    stgNumbers: d.stgNumbers,
                    onReactivate: (stg) =>
                        _setStgStatus(stg, StgStatus.active),
                    onArchive: _archiveStg,
                  ),
                ],
                const SizedBox(height: 16),
                ChartTrajectoryStrip(
                  // All non-archived STGs so completed/closed history persists.
                  activeStgs: d.visibleStgs,
                  sessions: d.sessions,
                  casStgIdsBySession: d.casStgIdsBySession,
                  earliestSessionDate: d.earliestSessionDate,
                  stgNumbers: d.stgNumbers,
                  onTickTap: (id) =>
                      _historyKey.currentState?.revealSession(id),
                ),
                const SizedBox(height: 16),
                ChartSessionHistory(
                  key: _historyKey,
                  sessions: d.sessions,
                  clientName: _clientName,
                  headlineOverrides: _headlineOverrides,
                  onShowAll: () => ChartNavigation.openAllSessions(
                    context,
                    clientId: _clientId,
                    clientName: _clientName,
                  ),
                ),
                const SizedBox(height: 16),
                ChartSubstrateLinkStrip(
                  substrateCellCount: s.substrateCellCount,
                  onOpenSubstrate: _openSubstrate,
                ),
                const SizedBox(height: 16),
                ChartFooterMeta(state: s, sessionToday: d.sessionToday),
                const SizedBox(height: 16),
                // Thread A — quiet, persistent way back to archived goals. The
                // Undo snackbar is transient; this is the durable route to
                // restore a goal the clinician archived earlier. Scoped to this
                // client; the screen itself handles the empty state.
                Center(
                  child: CueChartButton(
                    label: 'View archived goals',
                    icon: Icons.inventory_2_outlined,
                    style: CueChartButtonStyle.ghost,
                    small: true,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => ArchivedGoalsScreen(
                          clientId: _clientId,
                          clientName: _clientName,
                          onRestored: _reload,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Generate report chip (Phase C — Cue Mirror, Component Two) ───────────────
//
// A single action chip living on the chart, between the action-chips card and
// the LTG anchor. Enabled only when the clinician has ≥1 confirmed format to
// draft in; otherwise it renders disabled with a subtle hint. It does not alter
// anything else on the chart.

class _GenerateReportChip extends StatelessWidget {
  final Future<bool> hasConfirmedTemplate;
  final VoidCallback onTap;

  const _GenerateReportChip({
    required this.hasConfirmedTemplate,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = CueChartTokens.of(context);
    final ty = CueChartType.of(context);
    return FutureBuilder<bool>(
      future: hasConfirmedTemplate,
      builder: (context, snap) {
        final ready = snap.data ?? false;
        return CueChartCard(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          child: Row(
            children: [
              CueChartButton(
                icon: Icons.description_outlined,
                label: 'Generate report',
                enabled: ready,
                onTap: ready ? onTap : null,
              ),
              const SizedBox(width: 12),
              if (!ready)
                Expanded(
                  child: Text(
                    'Add a confirmed format to draft reports in your style.',
                    style: ty.sessionHeadline.copyWith(color: t.textTertiary),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

// ── Breadcrumb ───────────────────────────────────────────────────────────────

class _Breadcrumb extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final t = CueChartTokens.of(context);
    final ty = CueChartType.of(context);
    return Align(
      alignment: Alignment.centerLeft,
      child: InkWell(
        onTap: () => Navigator.pushNamedAndRemoveUntil(
          context,
          '/clients',
          (route) => false,
        ),
        borderRadius: BorderRadius.circular(6),
        child: Container(
          constraints: const BoxConstraints(minHeight: 40),
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.arrow_back_rounded, size: 15, color: t.textSecondary),
              const SizedBox(width: 6),
              Text('All clients', style: ty.button(t.textSecondary)),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Loading + error states ───────────────────────────────────────────────────

class _ChartSkeleton extends StatelessWidget {
  final bool isCompact;
  const _ChartSkeleton({required this.isCompact});

  @override
  Widget build(BuildContext context) {
    final t = CueChartTokens.of(context);
    final hPad = isCompact ? 16.0 : 24.0;
    Widget bar(double w, double h) => Container(
          width: w,
          height: h,
          margin: const EdgeInsets.only(bottom: 14),
          decoration: BoxDecoration(
            color: t.borderInset,
            borderRadius: BorderRadius.circular(6),
          ),
        );
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: Padding(
          padding: EdgeInsets.fromLTRB(hPad, 32, hPad, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              bar(220, 40),
              bar(160, 14),
              const SizedBox(height: 16),
              bar(420, 14),
              bar(360, 14),
              const SizedBox(height: 16),
              bar(double.infinity, 44),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChartError extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ChartError({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final t = CueChartTokens.of(context);
    final ty = CueChartType.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_outlined, size: 28, color: t.textSecondary),
            const SizedBox(height: 12),
            Text(
              "This chart didn't load.",
              style: ty.stgBody,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              message,
              style: ty.sessionHeadline.copyWith(color: t.textTertiary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: onRetry,
              style: OutlinedButton.styleFrom(
                foregroundColor: t.accent,
                side: BorderSide(color: t.borderCard),
              ),
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
