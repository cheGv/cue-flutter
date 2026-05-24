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

import 'package:flutter/material.dart';
// supabase_flutter re-exports gotrue's Session; hide it so `Session` here means
// our sessions-table model.
import 'package:supabase_flutter/supabase_flutter.dart' hide Session;

import '../models/citation.dart';
import '../models/client_chart_state.dart';
import '../models/session.dart';
import '../models/short_term_goal.dart';
import '../models/stg_session_metric.dart';
import '../repositories/citations_repository.dart';
import '../repositories/client_chart_state_repository.dart';
import '../repositories/format_templates_repository.dart';
import '../repositories/ltg_repository.dart';
import '../repositories/sessions_repository.dart';
import '../repositories/stg_metrics_repository.dart';
import '../repositories/stg_repository.dart';
import '../services/chart_narrator_service.dart';
import '../services/session_headline_service.dart';
import '../theme/cue_color_scheme.dart';
import '../theme/cue_text_styles.dart';
import '../utils/chart_navigation.dart';
import '../utils/stg_numbering.dart';
import '../widgets/app_layout.dart';
import '../widgets/chart/chart_action_chips.dart';
import '../widgets/chart/chart_card.dart';
import '../widgets/chart/chart_footer_meta.dart';
import '../widgets/chart/chart_format.dart';
import '../widgets/chart/chart_header.dart';
import '../widgets/chart/chart_ltg_anchor.dart';
import '../widgets/chart/chart_narrator.dart';
import '../widgets/chart/chart_session_history.dart';
import '../widgets/chart/chart_stg_compact.dart';
import '../widgets/chart/chart_stg_focus.dart';
import '../widgets/chart/chart_stg_section.dart';
import '../widgets/chart/chart_substrate_link_strip.dart';
import '../widgets/chart/chart_trajectory_strip.dart';
import '../widgets/recall_assistant/recall_assistant_controller.dart';

// ── Aggregated chart data ──────────────────────────────────────────────────

class _ChartData {
  final ClientChartState state;
  final List<ShortTermGoal> activeStgs;
  final Map<String, List<Citation>> citationsByStg;
  final Map<String, List<StgSessionMetric>> metricsByStg;
  final Map<String, String> stgNumbers;
  final String? initialFocusId;
  final List<Session> sessions;
  final DateTime? earliestSessionDate;
  final DateTime? firstSessionDate;
  final bool sessionToday;
  final String? ltgText;
  final int? ltgSeq;
  final int? ltgMonthsTotal;
  final int? ltgCurrentMonth;
  final DateTime? ltgAuthoredDate;

  const _ChartData({
    required this.state,
    required this.activeStgs,
    required this.citationsByStg,
    required this.metricsByStg,
    required this.stgNumbers,
    required this.initialFocusId,
    required this.sessions,
    required this.earliestSessionDate,
    required this.firstSessionDate,
    required this.sessionToday,
    required this.ltgText,
    required this.ltgSeq,
    required this.ltgMonthsTotal,
    required this.ltgCurrentMonth,
    required this.ltgAuthoredDate,
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

  // Locally-held in-focus STG. Null until the first compact-row tap, after
  // which it overrides the loaded initialFocusId. Reset on retry/reload.
  String? _focusedStgId;

  // AI narrator (one call per load) + lazily-generated session headlines.
  String? _narratorText;
  bool _narratorLoading = false;
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
    }
    _startLoad();
  }

  void _startLoad() {
    _future = _load();
    _future.then((d) {
      if (mounted) _kickAi(d);
    }).catchError((Object _) {});
  }

  /// Fire this load's AI calls: one narrator call (using the initial focus) and
  /// lazy headline generation for the top sessions. Both degrade to null until
  /// the proxy endpoints deploy; the widgets fall back.
  void _kickAi(_ChartData d) {
    setState(() {
      _narratorLoading = true;
      _narratorText = null;
      _headlineOverrides.clear();
    });

    ShortTermGoal? focus;
    for (final stg in d.activeStgs) {
      if (stg.id == d.initialFocusId) {
        focus = stg;
        break;
      }
    }
    focus ??= d.activeStgs.isNotEmpty ? d.activeStgs.first : null;

    ChartNarratorService().narrate(
      clientId: _clientId,
      clientName: _clientName,
      clientState: {
        'ltg_count': d.state.ltgCount,
        'active_stg_count': d.state.activeStgCount,
        'total_session_count': d.state.totalSessionCount,
        'last_session_date': d.state.lastSessionDate?.toIso8601String(),
        'undocumented_session_count': d.state.undocumentedSessionCount,
        'last_next_session_focus': d.state.lastNextSessionFocus,
        'caregiver_present': d.state.caregiverPresent,
        'substrate_cell_count': d.state.substrateCellCount,
      },
      focusedStg: focus == null
          ? null
          : {
              'id': focus.id,
              'number': d.stgNumbers[focus.id],
              'body': focus.specific,
              'domain': focus.domain?.toJson(),
              'week': focus.totalSessionsWorked,
              'total_weeks': focus.timeBoundSessions,
            },
    ).then((text) {
      if (!mounted) return;
      setState(() {
        _narratorLoading = false;
        _narratorText = text;
      });
    });

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
    ]);

    final state = (results[0] as ClientChartState?) ?? _fallbackState();
    final allStgs = results[1] as List<ShortTermGoal>;
    final sessions = results[2] as List<Session>;
    final ltgs = results[3] as List<Map<String, dynamic>>;
    final citations = results[4] as List<Citation>;
    final focused = results[5] as ShortTermGoal?;

    // Active STGs, ordered by sequence for display.
    final activeStgs =
        allStgs.where((s) => s.status == StgStatus.active).toList()
          ..sort((a, b) =>
              (a.sequenceNum ?? 1 << 30).compareTo(b.sequenceNum ?? 1 << 30));

    // Group citations by STG (compact-row counts + the focus card's ladder).
    final citationsByStg = <String, List<Citation>>{};
    for (final c in citations) {
      (citationsByStg[c.stgId] ??= <Citation>[]).add(c);
    }

    // Display numbers ("1.A") for every active STG.
    final stgNumbers = {
      for (final s in activeStgs) s.id: stgNumber(s, allStgs, ltgs),
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

    return _ChartData(
      state: state,
      activeStgs: activeStgs,
      citationsByStg: citationsByStg,
      metricsByStg: metricsByStg,
      stgNumbers: stgNumbers,
      initialFocusId: initialFocusId,
      sessions: sessions,
      earliestSessionDate: earliest,
      firstSessionDate: earliest,
      sessionToday: sessionToday,
      ltgText: ltgText,
      ltgSeq: ltgSeq,
      ltgMonthsTotal: monthsTotal,
      ltgCurrentMonth: currentMonth,
      ltgAuthoredDate:
          DateTime.tryParse(ltg?['created_at']?.toString() ?? ''),
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

  void _openRecall() {
    recallAssistantController
      ..setFocusedClient(_clientId, _clientName)
      ..open();
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
                  onRecallTap: _openRecall,
                ),
                const SizedBox(height: 16),
                ChartNarrator(
                  state: s,
                  clientName: _firstName,
                  aiText: _narratorText,
                  loading: _narratorLoading,
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
                const SizedBox(height: 16),
                ChartTrajectoryStrip(
                  activeStgs: d.activeStgs,
                  sessions: d.sessions,
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
