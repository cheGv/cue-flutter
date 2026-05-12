import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../animation/cue_motion.dart';
import '../services/day_state_service.dart';
import '../services/name_formatter.dart';
import '../services/today_widgets_service.dart';
import '../theme/cue_color_scheme.dart';
import '../theme/cue_phase4_tokens.dart';
import '../theme/cue_theme.dart';
import '../theme/cue_tokens.dart';
import '../theme/cue_type_v3.dart';
import '../theme/cue_typography.dart';
import '../widgets/app_layout.dart';
import '../widgets/cue_amber_link.dart';
import '../widgets/cue_animated_entrance.dart';
import '../widgets/cue_cuttlefish.dart';
import '../widgets/cue_glance_target.dart';
import '../widgets/today_brief_card.dart';
import '../widgets/today_glance_widgets.dart';
import 'client_profile_screen.dart';

// ── Phase 4.0.8-step-B-surface-1 ────────────────────────────────────────────
// The pre-spine local palette (_paper / _ink / _ghost / _amber / _border) was
// removed. Every color reference on the rendered Today surface now resolves
// to a kCue* token from cue_phase4_tokens.dart. CueColors.* references in
// dead-code paths (_buildSessionBriefCard, _buildWeekPulse) are left intact
// per phase scope; those methods carry `// ignore: unused_element` and
// sunset alongside the legacy proxy endpoint cleanup.
//
// Pre-spine `_paper` was #FAFAF7 (a near-spine drift); spine kCuePaper is
// #FAF7F0. The handful of pixels of warmth shift is intentional: the spine
// commits to the warmer paper tone across every surface, not just Today.

// ── Proxy (§4 — plain http.post, never functions.invoke) ───────────────────────
const String _proxyBase = 'https://cue-ai-proxy.onrender.com';

// ── Anti-hallucination system prompt (§9.1) ────────────────────────────────────
const String _systemPrompt =
    'You are Cue, a clinical co-pilot for Speech-Language Pathologists. '
    'Generate a pre-session brief using only the data provided. '
    'Never invent observations, scores, or recommendations not grounded '
    'in the data. If a field is missing, say "not documented". '
    'Be precise, brief, and clinically accurate. '
    'Respond in plain text only. No markdown formatting whatsoever. '
    'No asterisks, no bold, no headers, no bullet points, no dashes. '
    'Use plain sentences only. '
    'Maximum 8 lines total.';

// ── Date helpers ───────────────────────────────────────────────────────────────
String _todayStr() => DateTime.now().toIso8601String().split('T').first;
String _yesterdayStr() =>
    DateTime.now().subtract(const Duration(days: 1)).toIso8601String().split('T').first;

// ── Widget ─────────────────────────────────────────────────────────────────────

class TodayScreen extends StatefulWidget {
  const TodayScreen({super.key});

  @override
  State<TodayScreen> createState() => _TodayScreenState();
}

class _TodayScreenState extends State<TodayScreen> {
  final _supabase = Supabase.instance.client;

  bool _loading = true;
  List<Map<String, dynamic>> _rosterRows      = []; // daily_roster + clients(*)
  List<Map<String, dynamic>> _yesterdayMissed = []; // undocumented yesterday rows
  List<Map<String, dynamic>> _allClients      = []; // full caseload for picker
  bool _expandYesterday = false;

  // ── Phase 3.1: greeting + last-session + week-pulse data ────────────────
  /// SLP first name resolved from auth metadata (best-effort — falls back
  /// to null which collapses the greeting comma-name suffix).
  String? _slpFirstName;
  /// Most-recent session per client_id, used by the "Last session: …" line.
  /// null entry = no session ever recorded for that client.
  final Map<String, Map<String, dynamic>?> _lastSessionByClient = {};
  /// Counts for the "this week" pulse strip.
  int _weekSessionCount     = 0;
  int _weekDocumentedCount  = 0;
  int _weekGoalsAchieved    = 0;

  // ── Phase 4.0.7.5: SLP-controlled day state ─────────────────────────────
  // Loaded on init and after any close/reopen. Default open until the row
  // is loaded so the screen never flashes the closed surface for SLPs who
  // have never tapped Good night Cue.
  DayStateRecord _dayState = DayStateRecord.open;

  // ── Phase 4.2: cuttlefish glance target ─────────────────────────────────
  // Set by CueGlanceTarget callbacks on yesterday rows + first brief card.
  // Read by the TweenAnimationBuilder around the cuttlefish in the
  // greeting block. Down-right convention (positive = look down-right).
  double _glanceAngle = 0.0;
  void _setGlance(double v) {
    if (v != _glanceAngle && mounted) setState(() => _glanceAngle = v);
  }

  // ── Phase 4.0.8-step-B-surface-1.2: At a glance widget data ─────────────
  // Independent of the brief-card load path so the page renders fast and
  // widgets fill in as queries return. Each defaulting to its empty/null
  // state so the widgets render zero-state on first paint.
  List<DailyPulse>     _weekPulse    = const [];
  List<PendingSession> _pendingNotes = const [];
  List<ActiveGoal>     _activeGoals  = const [];
  TomorrowSummary      _tomorrow     = const TomorrowSummary(sessionCount: 0);
  CueInsight?          _noticed;

  @override
  void initState() {
    super.initState();
    _slpFirstName = _resolveSlpFirstName();
    _load();
    _loadDayState();
    _loadGlanceWidgets();
  }

  /// Fires the four widget queries in parallel. Defensive — service
  /// methods return empty/null on failure rather than throwing, so a
  /// network blip leaves widgets in zero-state instead of breaking
  /// the page.
  Future<void> _loadGlanceWidgets() async {
    final results = await Future.wait([
      TodayWidgetsService.getThisWeekPulse(),
      TodayWidgetsService.getPendingNotes(),
      TodayWidgetsService.getActiveGoals(),
      TodayWidgetsService.getTomorrowSummary(),
      TodayWidgetsService.getNoticedInsight(),
    ]);
    if (!mounted) return;
    setState(() {
      _weekPulse    = results[0] as List<DailyPulse>;
      _pendingNotes = results[1] as List<PendingSession>;
      _activeGoals  = results[2] as List<ActiveGoal>;
      _tomorrow     = results[3] as TomorrowSummary;
      _noticed      = results[4] as CueInsight?;
    });
  }

  Future<void> _loadDayState() async {
    final s = await DayStateService.instance.loadToday();
    if (mounted) setState(() => _dayState = s);
  }

  Future<void> _closeDay() async {
    final s = await DayStateService.instance.closeToday();
    if (mounted) setState(() => _dayState = s);
  }

  Future<void> _reopenDay() async {
    final s = await DayStateService.instance.reopenToday();
    if (mounted) setState(() => _dayState = s);
  }

  /// Read the SLP's first name from Supabase auth metadata. Tries common
  /// metadata keys, then falls back to splitting an email local-part on
  /// dots/underscores. Returns null if nothing usable is found.
  String? _resolveSlpFirstName() {
    final user = _supabase.auth.currentUser;
    if (user == null) return null;
    final md = user.userMetadata;
    for (final key in const ['first_name', 'firstName', 'name', 'full_name']) {
      final v = md?[key];
      if (v is String && v.trim().isNotEmpty) {
        final first = v.trim().split(RegExp(r'\s+')).first;
        return _capitalise(first);
      }
    }
    // Last-ditch fallback: derive from email local-part.
    final email = user.email;
    if (email != null && email.contains('@')) {
      final local = email.split('@').first;
      final first = local.split(RegExp(r'[._]')).first;
      if (first.isNotEmpty) return _capitalise(first);
    }
    return null;
  }

  String _capitalise(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1).toLowerCase();

  // ── Data orchestration ──────────────────────────────────────────────────────

  Future<void> _load() async {
    try {
      final uid = _supabase.auth.currentUser?.id;
      if (uid == null) {
        if (mounted) setState(() => _loading = false);
        return;
      }

      // Clear stale in-memory rows before fetch so UI shows fresh state
      if (mounted) setState(() => _rosterRows = []);

      final today     = _todayStr();
      final yesterday = _yesterdayStr();

      final results = await Future.wait([
        // Today's roster — join clients so we have the full client map
        _supabase
            .from('daily_roster')
            .select('*, clients(*)')
            .eq('clinician_id', uid)
            .eq('session_date', today),
        // Yesterday undocumented
        _supabase
            .from('daily_roster')
            .select('*, clients(*)')
            .eq('clinician_id', uid)
            .eq('session_date', yesterday)
            .eq('session_documented', false),
        // Full active caseload for bottom-sheet picker
        _supabase
            .from('clients')
            .select()
            .isFilter('deleted_at', null)
            .order('name', ascending: true),
      ]);

      final rosterRows = (results[0] as List)
          .map((r) => Map<String, dynamic>.from(r as Map))
          .toList();
      final missed = (results[1] as List)
          .map((r) => Map<String, dynamic>.from(r as Map))
          .toList();
      final allClients = (results[2] as List)
          .map((r) => Map<String, dynamic>.from(r as Map))
          .toList();

      if (mounted) {
        setState(() {
          _rosterRows      = rosterRows;
          _yesterdayMissed = missed;
          _allClients      = allClients;
          _loading         = false;
        });
      }

      // Fire brief generation for rows that have no cached brief,
      // or that have stale/malformed data (raw JSON blob, prompt echo).
      for (final row in rosterRows) {
        if (_needsBriefGeneration(row['brief_text'] as String?)) {
          _generateBrief(row); // intentionally un-awaited — runs in parallel
        }
      }

      // Phase 3.1 secondary fetches — last session per client + week pulse.
      // Run un-awaited so the screen renders fast even if these are slow.
      _loadLastSessionPerClient(uid: uid, rosterRows: rosterRows);
      _loadWeekPulse(uid: uid);
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Pulls the most-recent session for every client on today's roster in
  /// ONE query, then groups in memory. Populates [_lastSessionByClient].
  Future<void> _loadLastSessionPerClient({
    required String uid,
    required List<Map<String, dynamic>> rosterRows,
  }) async {
    if (rosterRows.isEmpty) return;
    final clientIds = rosterRows
        .map((r) {
          final cl = r['clients'] as Map?;
          return cl?['id']?.toString();
        })
        .where((id) => id != null && id.isNotEmpty)
        .map((id) => id!)
        .toSet()
        .toList();
    if (clientIds.isEmpty) return;
    try {
      // sessions.client_id is text in this schema; pass strings.
      // Phase 4.0.7.22a — extended select for the Today's Brief card.
      // The card needs target_behaviour, activity_name, accuracy
      // counts, next_session_focus, and client_affect on top of the
      // legacy soap_note/notes/date columns.
      final rows = await _supabase
          .from('sessions')
          .select(
              'id, client_id, date, soap_note, notes, created_at, '
              'target_behaviour, activity_name, next_session_focus, '
              'client_affect, attempts, independent_responses, '
              'prompted_responses, goal_met')
          .eq('user_id', uid)
          .inFilter('client_id', clientIds)
          .isFilter('deleted_at', null)
          .order('date', ascending: false);

      final byClient = <String, Map<String, dynamic>?>{
        for (final id in clientIds) id: null,
      };
      for (final raw in rows) {
        final r = Map<String, dynamic>.from(raw as Map);
        final cid = r['client_id']?.toString();
        if (cid == null) continue;
        // First row wins (already date-desc).
        byClient[cid] ??= r;
      }
      if (mounted) {
        setState(() {
          _lastSessionByClient
            ..clear()
            ..addAll(byClient);
        });
      }
    } catch (_) {/* leave map empty — UI shows "not yet documented" */}
  }

  /// Sessions in last 7d, of which N have a note attached, plus goals
  /// achieved in the same window. Three counters; one query per metric.
  Future<void> _loadWeekPulse({required String uid}) async {
    final sevenDaysAgo = DateTime.now()
        .toUtc()
        .subtract(const Duration(days: 7))
        .toIso8601String()
        .split('T')
        .first;
    try {
      final results = await Future.wait<dynamic>([
        _supabase
            .from('sessions')
            .select('id, soap_note, notes')
            .eq('user_id', uid)
            .gte('date', sevenDaysAgo)
            .isFilter('deleted_at', null),
        _supabase
            .from('long_term_goals')
            .select('id')
            .eq('user_id', uid)
            .eq('status', 'achieved')
            .gte('updated_at', sevenDaysAgo),
      ]);
      final sessionRows = (results[0] as List)
          .map((r) => Map<String, dynamic>.from(r as Map))
          .toList();
      final goalRows = (results[1] as List).length;

      final documented = sessionRows.where((s) {
        final soap  = (s['soap_note'] as String?)?.trim();
        final notes = (s['notes']     as String?)?.trim();
        return (soap != null && soap.isNotEmpty) ||
               (notes != null && notes.isNotEmpty);
      }).length;

      if (mounted) {
        setState(() {
          _weekSessionCount    = sessionRows.length;
          _weekDocumentedCount = documented;
          _weekGoalsAchieved   = goalRows;
        });
      }
    } catch (_) {/* leave at zero */}
  }

  // Returns true if the stored brief_text is absent or malformed
  // (raw Anthropic JSON blob or prompt context echo from earlier bug).
  bool _needsBriefGeneration(String? stored) {
    if (stored == null || stored.isEmpty) return true;
    final t = stored.trimLeft();
    // Raw API response JSON starts with '{'
    if (t.startsWith('{')) return true;
    // Prompt echo starts with the client context header
    if (t.startsWith('CLIENT:')) return true;
    return false;
  }

  // ── Brief generation ────────────────────────────────────────────────────────
  // Identical data-assembly pattern to lib/widgets/pre_session_brief.dart.
  // Result is stored in daily_roster.brief_text (cache).

  Future<void> _generateBrief(Map<String, dynamic> rosterRow) async {
    final rosterId = rosterRow['id'].toString();
    final client   = Map<String, dynamic>.from(rosterRow['clients'] as Map);
    final clientId = client['id'].toString();

    try {
      // Step 1: last session — isolated query (§ schema drift: uses 'date' column)
      final sessions = await _supabase
          .from('sessions')
          .select()
          .eq('client_id', clientId)
          .isFilter('deleted_at', null)
          .order('date', ascending: false)
          .limit(1);
      if (sessions.isEmpty) return;
      final lastSession = Map<String, dynamic>.from(sessions.first as Map);

      // Step 2: active STGs + LTGs — non-fatal
      List stgRows = [];
      List ltgRows = [];
      try {
        final goalResults = await Future.wait([
          _supabase
              .from('short_term_goals')
              .select()
              .eq('client_id', clientId)
              .eq('status', 'active')
              .order('created_at', ascending: true),
          _supabase
              .from('long_term_goals')
              .select()
              .eq('client_id', clientId)
              // Phase 4.0.7.23c-deploy — exclude pending_attestation v2
              // drafts from today-screen brief generation. Same rationale
              // as pre_session_brief: unattested candidates must not feed
              // the brief LLM context.
              .eq('status', 'active'),
        ]);
        stgRows = goalResults[0] as List;
        ltgRows = goalResults[1] as List;
      } catch (_) {}

      // Step 3: evidence per STG — non-fatal
      List<List<dynamic>> evidenceLists = [];
      if (stgRows.isNotEmpty) {
        try {
          evidenceLists = await Future.wait(
            stgRows.map((stg) => _supabase
                .from('stg_evidence')
                .select('created_at, accuracy_pct, cue_level_used')
                .eq('stg_id', (stg as Map)['id'].toString())
                .order('created_at', ascending: false)
                .limit(5)),
          );
        } catch (_) {}
      }

      final stgsWithEvidence = List.generate(stgRows.length, (i) {
        final stg = Map<String, dynamic>.from(stgRows[i] as Map);
        stg['_evidence'] = i < evidenceLists.length ? evidenceLists[i] : [];
        return stg;
      });

      // Step 4: assemble prompt + call proxy
      final prompt = _assemblePrompt(
        client:     client,
        lastSession: lastSession,
        activeStgs: stgsWithEvidence,
        ltgs: ltgRows.map((l) => Map<String, dynamic>.from(l as Map)).toList(),
      );

      final token = _supabase.auth.currentSession?.accessToken;
      final response = await http.post(
        Uri.parse('$_proxyBase/pre-session-brief'),
        headers: {
          'Content-Type':  'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'model':        'claude-sonnet-4-20250514',
          'system':       _systemPrompt,
          'user_message': prompt,
          'client_id':    clientId,
        }),
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode != 200) return;

      final data = jsonDecode(response.body) as Map<String, dynamic>;

      // Explicit extraction — never store raw JSON or fallback blobs.
      // Mirrors the canonical path: response.content[0].text
      String briefText = '';
      try {
        final content = data['content'];
        if (content is List && content.isNotEmpty) {
          final first = content.first;
          if (first is Map) {
            briefText = (first['text'] ?? '').toString().trim();
          }
        }
      } catch (_) {}
      // Secondary fallbacks for alternate proxy shapes
      if (briefText.isEmpty) {
        briefText = (data['brief'] ?? data['text'] ?? '').toString().trim();
      }
      if (briefText.isEmpty) return;

      // Strip markdown the model occasionally emits despite instructions.
      // replaceAllMapped handles **bold** → bold; subsequent passes remove
      // any stray *, #, or leading-dash list markers.
      briefText = briefText
          .replaceAllMapped(
            RegExp(r'\*\*(.*?)\*\*', dotAll: true),
            (m) => m.group(1) ?? '',
          )
          .replaceAll('**', '')
          .replaceAll('*', '')
          .replaceAll(RegExp(r'^#+\s*', multiLine: true), '')
          .trim();
      if (briefText.isEmpty) return;

      // Step 5: persist to daily_roster cache
      await _supabase.from('daily_roster').update({
        'brief_text':         briefText,
        'brief_generated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', rosterId);

      // Step 6: update local row so UI reflects immediately
      if (mounted) {
        setState(() {
          final idx = _rosterRows.indexWhere(
              (r) => r['id'].toString() == rosterId);
          if (idx != -1) {
            _rosterRows[idx] =
                Map<String, dynamic>.from(_rosterRows[idx])
                  ..['brief_text'] = briefText;
          }
        });
      }
    } catch (_) {
      // Non-fatal — brief stays null, card shows "Generating brief..."
    }
  }

  // Prompt assembly — mirrors pre_session_brief.dart exactly
  String _assemblePrompt({
    required Map<String, dynamic> client,
    required Map<String, dynamic> lastSession,
    required List<Map<String, dynamic>> activeStgs,
    required List<Map<String, dynamic>> ltgs,
  }) {
    final sb = StringBuffer();

    sb.writeln('CLIENT: ${client['name'] ?? 'not documented'}'
        ', Age ${client['age'] ?? 'not documented'}');
    sb.writeln('Diagnosis: ${client['diagnosis'] ?? 'not documented'}');
    sb.writeln('Primary language: ${client['primary_language'] ?? 'not documented'}');
    sb.writeln();

    if (ltgs.isNotEmpty) {
      sb.writeln('LONG-TERM GOALS:');
      for (final ltg in ltgs) {
        final domain = ltg['domain'] != null ? ' (${ltg['domain']})' : '';
        sb.writeln('- ${ltg['goal_text'] ?? 'not documented'}$domain');
      }
      sb.writeln();
    }

    sb.writeln('ACTIVE SHORT-TERM GOALS:');
    for (final stg in activeStgs) {
      sb.writeln('STG: ${stg['target_behavior'] ?? 'not documented'}');
      sb.writeln('  Support level: ${stg['current_cue_level'] ?? 'not documented'}');
      final acc = stg['current_accuracy'];
      sb.writeln('  Current accuracy: '
          '${acc != null ? '${(acc as num).toStringAsFixed(1)}%' : 'not documented'}');
      final mc = stg['mastery_criterion'];
      if (mc is Map) {
        sb.writeln('  Criterion: ${mc['accuracy_pct']}% for '
            '${mc['consecutive_sessions']} consecutive sessions');
      }
      sb.writeln('  Sessions at criterion: ${stg['sessions_at_criterion'] ?? 0}');
      final evidence = stg['_evidence'] as List? ?? [];
      if (evidence.isNotEmpty) {
        sb.writeln('  Recent evidence (newest first):');
        for (final ev in evidence) {
          final evMap = ev as Map;
          final date  = evMap['created_at']?.toString().split('T').first ?? 'no date';
          final pct   = evMap['accuracy_pct'];
          final cue   = evMap['cue_level_used'] ?? 'not documented';
          sb.writeln('    $date: '
              '${pct != null ? '${(pct as num).toStringAsFixed(1)}%' : 'not documented'}'
              ', cue: $cue');
        }
      }
      sb.writeln();
    }

    sb.writeln('LAST SESSION DATE: ${lastSession['date'] ?? 'not documented'}');
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
    sb.writeln('Generate a pre-session brief with these sections in order:');
    sb.writeln('LAST SESSION: one-line snapshot of what was worked on and overall accuracy');
    sb.writeln("TODAY'S FOCUS: active STGs, current support level, push vs consolidate recommendation based on accuracy trend");
    sb.writeln('PATTERN FLAG: ONLY include this line if accuracy has dropped or plateaued across 3 or more consecutive evidence rows. If no pattern, omit this section entirely.');
    sb.writeln('SUGGESTED MOVE: one sentence clinical recommendation for today');
    return sb.toString();
  }

  // ── Roster mutations ────────────────────────────────────────────────────────

  Future<void> _addToRoster(List<String> clientIds) async {
    final uid = _supabase.auth.currentUser?.id;
    if (uid == null) return;

    // Only insert IDs not already on today's roster
    final existingIds = _rosterRows
        .map((r) => (r['clients'] as Map)['id'].toString())
        .toSet();
    final newIds = clientIds.where((id) => !existingIds.contains(id)).toList();
    if (newIds.isEmpty) return;

    await _supabase.from('daily_roster').insert(
      newIds.map((cid) => {
        'clinician_id': uid,
        'client_id':    cid,
        'session_date': _todayStr(),
      }).toList(),
    );

    // Reload — will fire brief generation for new rows automatically
    await _load();
  }

  Future<void> _removeFromRoster(String rosterId) async {
    try {
      await _supabase.from('daily_roster').delete().eq('id', rosterId);
    } catch (_) {}
    if (mounted) {
      setState(() {
        _rosterRows.removeWhere((r) => r['id'].toString() == rosterId);
      });
    }
  }

  // Called when SLP taps "Start Session" — marks the slot as documented
  // per spec: "set to true when the SLP navigates to a session report from
  // this screen — not automatically"
  Future<void> _markDocumented(String rosterId) async {
    try {
      await _supabase
          .from('daily_roster')
          .update({'session_documented': true})
          .eq('id', rosterId);
    } catch (_) {}
  }

  // ── Bottom sheet: client picker ─────────────────────────────────────────────

  void _showAddSheet() {
    final existingIds = _rosterRows
        .map((r) => (r['clients'] as Map)['id'].toString())
        .toSet();
    final selected = <String>{...existingIds};

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: kCuePaper,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(kCueMediumRadius)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Drag handle
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color:        kCueBorder,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              // Picker title — H2 (sans), not the screen's H1 serif moment.
              Text('Who are you seeing today?', style: CueTypeV3.h2()),
              const SizedBox(height: 16),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 380),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _allClients.length,
                  itemBuilder: (_, i) {
                    final cl        = _allClients[i];
                    final id        = cl['id'].toString();
                    final alreadyOn = existingIds.contains(id);
                    final isChecked = selected.contains(id);
                    return CheckboxListTile(
                      value:     isChecked,
                      onChanged: alreadyOn
                          ? null
                          : (v) => setSheet(() {
                                if (v == true) {
                                  selected.add(id);
                                } else {
                                  selected.remove(id);
                                }
                              }),
                      title: Text(
                        cl['name'] ?? '',
                        style: CueTypeV3.h2(
                          color: alreadyOn ? kCueInkTertiary : kCueInk,
                        ),
                      ),
                      subtitle: Text(
                        [
                          if (cl['age'] != null) 'Age ${cl['age']}',
                          if ((cl['diagnosis'] as String?)?.isNotEmpty == true)
                            cl['diagnosis'] as String,
                        ].join(' · '),
                        style: CueTypeV3.body(color: kCueInkTertiary),
                      ),
                      activeColor:     kCueInk,
                      checkColor:      kCueSurfaceWhite,
                      dense:           true,
                      controlAffinity: ListTileControlAffinity.leading,
                    );
                  },
                ),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: Text(
                      'Cancel',
                      style: CueTypeV3.body(color: kCueInkTertiary),
                    ),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: kCueInk,
                      foregroundColor: kCueSurfaceWhite,
                      elevation:       0,
                      // Picker confirm pill — editorial register (matches
                      // Good night Cue / reopen pills); radius 20 is
                      // explicit per spine carve-out.
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 12),
                    ),
                    onPressed: () async {
                      Navigator.pop(ctx);
                      final newIds = selected
                          .where((id) => !existingIds.contains(id))
                          .toList();
                      if (newIds.isNotEmpty) await _addToRoster(newIds);
                    },
                    child: Text(
                      'Confirm',
                      style: CueTypeV3.h2(color: kCueSurfaceWhite),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return AppLayout(
      // Phase 5.4 Sprint 2 commit 1 — Today owns its own chrome via
      // the greeting H1 below. `skipTopBar: true` is the explicit
      // suppression mechanism (previously the empty-title short-
      // circuit in AppLayout's _TopBar did this implicitly). Title
      // stays empty; the H1 below is the page identity (the spine's
      // "one serif moment per screen" rule).
      title:       '',
      activeRoute: 'today',
      skipTopBar:  true,
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(
                strokeWidth: 1.5,
                color: CueColors.amber,
              ),
            )
          : (_dayState.state == CueDayState.closed
              ? _buildEndOfDayResting()
              : LayoutBuilder(
                  builder: (context, constraints) {
                    final hPad = constraints.maxWidth > 700 ? 48.0 : 24.0;
                    final isNight =
                        Theme.of(context).brightness == Brightness.dark;
                    final cue = CueColorsResolved.of(context);
                    final pageBg = cue.bgCanvas;
                    // Phase 4.0.8-step-B-surface-1.2 — page order
                    // restructured: greeting block now leads the page;
                    // yesterday-reminder and reopened-pill moved into
                    // _buildTodayZone where they belong contextually
                    // (yesterday-reminder appears below the greeting;
                    // reopened-pill renders inline in the greeting
                    // block at less prominent register).
                    return ColoredBox(
                      color: pageBg,
                      child: ListView(
                        padding: EdgeInsets.fromLTRB(hPad, 32, hPad, 32),
                        children: [
                          _buildTodayZone(),
                          const SizedBox(height: 32),
                          _buildGoodNightFooter(isNight: isNight),
                          const SizedBox(height: 32),
                        ],
                      ),
                    );
                  },
                )),
    );
  }

  // ── Good night Cue footer (open + reopened states) ─────────────────────
  Widget _buildGoodNightFooter({required bool isNight}) {
    final dividerColor = isNight
        ? const Color(0x14FFFFFF)
        : const Color(0x14000000);
    final borderColor = isNight
        ? const Color(0x2EFFFFFF) // rgba(255,255,255,0.18)
        : kCueBorder;
    final textColor = CueColorsResolved.of(context).textPrimary;

    final helperText = _dayState.state == CueDayState.reopened
        ? 'close again when you\'re really done'
        : 'tap when you\'re done for today · you can reopen anytime';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(height: 0.5, color: dividerColor),
        const SizedBox(height: 18),
        // Good night Cue pill — editorial register (radius 20 per spine
        // carve-out). Outline-only, transparent fill.
        InkWell(
          onTap:        _closeDay,
          borderRadius: BorderRadius.circular(20),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            decoration: BoxDecoration(
              color:        Colors.transparent,
              border:       Border.all(color: borderColor, width: kCueCardBorderW),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              'Good night Cue',
              style: CueTypeV3.body(color: textColor),
            ),
          ),
        ),
        const SizedBox(height: 8),
        // Helper microcopy — italic editorial register, family-facing
        // warmth (Rule 3 carve-out — this is end-of-day, not clinical
        // action). Iowan italic via CueTypeV3.editorialItalic.
        Text(
          helperText,
          style:     CueTypeV3.editorialItalic(),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  // ── End-of-day resting moment (closed state) ───────────────────────────
  //
  // Phase 4.0.8-step-B-surface-1 — state-conditional H1: this surface's
  // serif moment lives here when the day is closed. Greeting block (default
  // state) and end-of-day (closed state) never co-render, so Rule 2's
  // "serif appears at most once per screen" is honored.
  //
  // The cuttlefish render at size 96 / state: CueState.resting is preserved
  // unchanged per founder instinct call: end-of-day cuttlefish protects
  // against typography fatigue at day-close. Will be re-evaluated with
  // friend tester signal in 4.0.8.1 if needed.
  Widget _buildEndOfDayResting() {
    final isNight = Theme.of(context).brightness == Brightness.dark;

    final sessionsDone = _rosterRows.length;
    int goalsHit = 0;
    int pending  = 0;
    for (final r in _rosterRows) {
      final goalMet = (r['goal_met'] as String?)?.toLowerCase();
      if (goalMet == 'yes' || goalMet == 'met') goalsHit++;
      final next = (r['next_session_focus'] as String?)?.trim();
      if (next != null && next.isNotEmpty) pending++;
    }

    final cue           = CueColorsResolved.of(context);
    final pageBg        = cue.bgCanvas;
    final headlineColor = cue.textPrimary;
    final tertiaryColor = cue.textMuted;
    final pillBorder    = isNight ? const Color(0x2EFFFFFF)  : kCueBorder;

    return Stack(
      children: [
        Positioned.fill(child: ColoredBox(color: pageBg)),
        Positioned.fill(
          child: Center(
            child: Container(
              width:  220,
              height: 220,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    kCueAmber.withValues(alpha: 0.08),
                    kCueAmber.withValues(alpha: 0.0),
                  ],
                ),
              ),
            ),
          ),
        ),
        Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Cuttlefish PRESERVED — founder lock 4.0.8-step-B-surface-1.
              // Literal `96` retained intentionally (matches CueSize
              // .cuttlefishWelcome but the literal stays per founder
              // direction "leave the inconsistency alone, founder's
              // instruction is unchanged").
              const CueCuttlefish(size: 96, state: CueState.resting),
              const SizedBox(height: 24),
              // State-conditional H1 — Iowan serif, kCueInk. Greeting H1
              // does not co-render in this state.
              Text('Good work today.', style: CueTypeV3.h1(color: headlineColor)),
              const SizedBox(height: 6),
              Text(
                'See you tomorrow.',
                style: CueTypeV3.body(color: tertiaryColor),
              ),
              const SizedBox(height: 28),
              Opacity(
                opacity: 0.65,
                child: _StatPill(
                  sessions: sessionsDone,
                  goalsHit: goalsHit,
                  pending:  pending,
                  inkColor: tertiaryColor,
                ),
              ),
              const SizedBox(height: 14),
              // Italic editorial close — Iowan italic per Rule 3 carve-out.
              Text(
                'Cue will prepare tomorrow\'s briefs overnight.',
                style: CueTypeV3.editorialItalic(color: tertiaryColor),
              ),
              const SizedBox(height: 20),
              InkWell(
                onTap:        _reopenDay,
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 7),
                  decoration: BoxDecoration(
                    color:        Colors.transparent,
                    border:       Border.all(
                        color: pillBorder, width: kCueCardBorderW),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '↺ Reopen — there\'s more',
                    style: CueTypeV3.body(color: headlineColor),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── Zone 1: Yesterday reminder ──────────────────────────────────────────────

  // Phase 4.0.8-step-B-surface-1.2 — yesterday-reminder visual register
  // shifted again. Surface 1's "no amber fill, paper bg" choice is
  // superseded: friend-tester signal said the urgent intent didn't
  // read at all on a paper-on-paper bar. 1.2 locks an amber-surface
  // fill (#FBE9D2 / #E8DCB8 border / kCueAmberDeep text) per dual-
  // accent system: amber = urgent register; this bar is "yesterday's
  // sessions still need attention" → urgent.
  //
  // Inline #FBE9D2 / #E8DCB8 are amber-surface variants tighter than
  // kCueAmberSurface (#FAEEDA). Inline kept here to preserve the
  // exact spec; if these recur, factor to tokens in a later phase.
  Widget _buildYesterdayReminder() {
    final n     = _yesterdayMissed.length;
    // Names piped through NameFormatter.displayName so lowercase data
    // ("krish") renders title-cased ("Krish"). Project doesn't have a
    // Client model class — clients flow as Map<String, dynamic> from
    // Supabase; NameFormatter is the canonical title-case helper used
    // across surfaces (greeting, roster, chart). Founder's "Client.
    // displayName getter" intent is honored via this helper.
    final names = _yesterdayMissed.map((r) {
      final cl = r['clients'] as Map?;
      return NameFormatter.displayName(
          cl != null ? cl['name']?.toString() : null);
    }).where((s) => s.isNotEmpty).join(', ');

    // Phase 4.0.8-step-B-surface-1.2 hotfix #2 — visual restructure to
    // give the widget two registers:
    //
    //   • Header (urgent / amber) — kCueAmberSurface ground, kCueAmberDeep
    //     text, Inter 12.5px with the count portion bolded via Text.rich.
    //     "2 sessions from yesterday not documented — Krish, Girish"
    //   • Rows (clinical / olive) — white ground, olive stripe (2px ×
    //     18px), kCueOliveDeep name in Inter 14/600, kCueAmberDeep
    //     "Document →" with subtle underline.
    //
    // Two registers visible. Header carries urgency; rows carry the
    // calm clinical work. Single rounded-card container clips both.
    //
    // Pre-fix the entire card was amber — read as a single shouty
    // surface, no widget feel. The dual-register layout is the
    // friend-tester signal applied: "olive greenish for rich visual."
    return Material(
      color:         kCueSurfaceWhite,
      borderRadius:  BorderRadius.circular(kCueMediumRadius),
      clipBehavior:  Clip.antiAlias,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(kCueMediumRadius),
          border:       Border.all(color: kCueBorder, width: kCueCardBorderW),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize:       MainAxisSize.min,
          children: [
            // ── Header (amber, urgent) ────────────────────────────────
            InkWell(
              onTap: () => setState(
                  () => _expandYesterday = !_expandYesterday),
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 11),
                decoration: const BoxDecoration(
                  color: Color(0xFFFBE9D2),
                  border: Border(
                    bottom: BorderSide(
                        color: Color(0xFFE8DCB8), width: 0.5),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.history_rounded,
                        size: 14, color: kCueAmberDeep),
                    const SizedBox(width: 8),
                    Expanded(child: _yesterdayHeadline(n, names)),
                    Icon(
                      _expandYesterday
                          ? Icons.expand_less_rounded
                          : Icons.expand_more_rounded,
                      size:  16,
                      color: kCueAmberDeep,
                    ),
                  ],
                ),
              ),
            ),
            // ── Rows (white, clinical, olive accent) ──────────────────
            //
            // Phase 4.2 — each row wrapped in CueGlanceTarget so the
            // cuttlefish in the greeting block tilts toward the
            // hovered row. Hover-out returns glance to neutral.
            if (_expandYesterday)
              for (var i = 0; i < _yesterdayMissed.length; i++)
                CueGlanceTarget(
                  glanceAngle:    CueGlanceTargets.yesterdayRow,
                  onGlanceChange: _setGlance,
                  child: _yesterdayRow(
                    _yesterdayMissed[i],
                    isLast: i == _yesterdayMissed.length - 1,
                  ),
                ),
          ],
        ),
      ),
    );
  }

  /// Headline of the yesterday-reminder header. The leading count
  /// ("2 sessions") gets weight 600 to anchor the eye; the rest of
  /// the sentence stays at 500. Inter 12.5 / kCueAmberDeep throughout.
  Widget _yesterdayHeadline(int n, String names) {
    final countLabel = '$n ${n == 1 ? 'session' : 'sessions'}';
    return Text.rich(
      TextSpan(
        style: const TextStyle(
          fontFamily:         'Inter',
          fontFamilyFallback: ['system-ui', 'sans-serif'],
          fontSize:           12.5,
          fontWeight:         FontWeight.w500,
          letterSpacing:      -0.0625,
          color:              kCueAmberDeep,
          height:             1.3,
        ),
        children: [
          TextSpan(
            text:  countLabel,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          const TextSpan(text: ' from yesterday not documented'),
          if (names.isNotEmpty) TextSpan(text: ' — $names'),
        ],
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }

  /// One row in the expanded yesterday-reminder. White surface with
  /// an olive stripe + olive-deep name + amber-deep "Document →"
  /// action. The dual-register intent: header reads urgent (amber);
  /// rows read calm-clinical (olive on white) so the SLP feels
  /// invited to act, not nagged.
  ///
  /// Navigation: ClientProfileScreen for the row's client. The
  /// chart's session-create flow is the canonical path to record
  /// the missed session. (A direct session-capture deep-link would
  /// need a session_id, which daily_roster rows don't carry.)
  Widget _yesterdayRow(Map<String, dynamic> row, {required bool isLast}) {
    final cl   = (row['clients'] as Map?) ?? const {};
    // NameFormatter.displayName: "krish" → "Krish".
    final name = NameFormatter.displayName(cl['name']?.toString());
    final displayedName = name.isNotEmpty ? name : 'Unknown';

    return InkWell(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          // Phase 4.0.7.39 — URL bar reflects /clients/:id.
          settings: RouteSettings(name: '/clients/${cl['id']}'),
          builder: (_) => ClientProfileScreen(
            client: Map<String, dynamic>.from(cl),
          ),
        ),
      ),
      child: Container(
        decoration: BoxDecoration(
          color: kCueSurfaceWhite,
          // Hairline below every row except the last — keeps the
          // bottom edge of the card clean.
          border: isLast
              ? null
              : const Border(
                  bottom: BorderSide(
                      color: Color(0xFFF0EBE0), width: 0.5),
                ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Olive stripe — 2px wide × 18px tall pill. Reads as a
            // calm clinical-state indicator inside the urgent-header
            // card. Dual-accent system in miniature.
            Container(
              width:  2,
              height: 18,
              decoration: BoxDecoration(
                color:        kCueOlive,
                borderRadius: BorderRadius.circular(1),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                displayedName,
                // Inter 14 / 600 / kCueOliveDeep, -0.01em. Anchor eye
                // weight on the row. Inline TextStyle — this size+weight
                // combo doesn't map cleanly to a CueTypeV3 builder.
                style: const TextStyle(
                  fontFamily:         'Inter',
                  fontFamilyFallback: ['system-ui', 'sans-serif'],
                  fontSize:           14,
                  fontWeight:         FontWeight.w600,
                  letterSpacing:      -0.14, // -0.01em × 14
                  color:              kCueOliveDeep,
                ),
              ),
            ),
            const SizedBox(width: 12),
            // Action link — Inter 12.5/500/kCueAmberDeep + underline
            // at #BA7517 0.5px. Amber on the action keeps the urgent
            // register's call-to-act paired with the row's calm name.
            const Text(
              'Document →',
              style: TextStyle(
                fontFamily:         'Inter',
                fontFamilyFallback: ['system-ui', 'sans-serif'],
                fontSize:           12.5,
                fontWeight:         FontWeight.w500,
                letterSpacing:      -0.0625,
                color:              kCueAmberDeep,
                decoration:          TextDecoration.underline,
                decorationColor:     Color(0xFFBA7517),
                decorationThickness: 0.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Phase 3.1: Today screen content blocks ──────────────────────────────

  Widget _buildTodayZone() {
    // Phase 4.0.8-step-B-surface-1.2 — page order restructured.
    // Greeting block leads. Yesterday-reminder follows greeting (the
    // urgent-amber bar belongs after the orientation, not before
    // it). Then "Today's sessions" header + brief stack + At-a-glance.
    //
    // Phase 4.2 page-entrance choreography (locked in cue_motion.dart):
    //   • Greeting:                        0 ms
    //   • Yesterday-reminder (if present):  80 ms
    //   • "Today's sessions" eyebrow:      160 ms
    //   • Brief cards (capped staggered):  from 240 ms (per
    //     _wrapBriefCardEntrance — internal stagger 60 ms each,
    //     capped at index 11 so a 30-session day doesn't pop in)
    //   • "At a glance" section:           480 ms
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CueAnimatedEntrance(
          // delay defaults to Duration.zero — greeting is the first
          // beat of the page-entrance choreography.
          child: _buildGreetingBlock(),
        ),
        const SizedBox(height: CueGap.greetingToEyebrow),

        // Yesterday-reminder rendered here, below the greeting. Only
        // appears when there are undocumented sessions from yesterday.
        if (_yesterdayMissed.isNotEmpty) ...[
          CueAnimatedEntrance(
            delay: const Duration(milliseconds: 80),
            child: _buildYesterdayReminder(),
          ),
          const SizedBox(height: CueGap.s24),
        ],

        CueAnimatedEntrance(
          delay: const Duration(milliseconds: 160),
          child: _buildEyebrowRow(
            label: "Today's sessions",
            trailing: _buildAddRosterButton(),
          ),
        ),
        const SizedBox(height: CueGap.eyebrowToCard),
        if (_rosterRows.isEmpty)
          CueAnimatedEntrance(
            delay: const Duration(milliseconds: 240),
            child: _buildEmptyTodayHint(),
          )
        else
          // Brief cards carry their own per-card entrance via
          // _wrapBriefCardEntrance — no outer wrapper here, otherwise
          // the cards would double-fade.
          _buildTodayBriefStack(),

        // ── At a glance section (Phase 4.0.8-step-B-surface-1.2) ───────
        const SizedBox(height: CueGap.s32),
        CueAnimatedEntrance(
          delay: const Duration(milliseconds: 480),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildEyebrowRow(label: 'At a glance'),
              const SizedBox(height: CueGap.eyebrowToCard),
              _buildAtAGlanceSection(),
            ],
          ),
        ),
      ],
    );
  }

  /// Phase 4.0.7.22a — vertical stack of TodayBriefCard, one per
  /// roster client. The first card carries `isUpNext: true` so its
  /// stripe goes amber (urgent register) per dual-accent system;
  /// subsequent cards use olive (calm) by default.
  ///
  /// Phase 4.2 — first card wrapped in CueGlanceTarget so the
  /// cuttlefish glances toward it on hover. Subsequent cards do not
  /// trigger glance (they sit further down the page, often below
  /// fold; cuttlefish would be tilting at off-screen targets). Each
  /// card wrapped in CueAnimatedEntrance, capped at 12 cards (per
  /// kMotionStaggerMaxIndex) so an SLP with 30 sessions doesn't
  /// watch every row pop in.
  Widget _buildTodayBriefStack() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < _rosterRows.length; i++) ...[
          _wrapBriefCardEntrance(
            index: i,
            child: i == 0
                ? CueGlanceTarget(
                    glanceAngle:    CueGlanceTargets.firstBriefCard,
                    onGlanceChange: _setGlance,
                    child: _buildTodayBriefCardForRoster(
                        _rosterRows[i], isUpNext: true),
                  )
                : _buildTodayBriefCardForRoster(
                    _rosterRows[i], isUpNext: false),
          ),
          if (i != _rosterRows.length - 1)
            const SizedBox(height: CueGap.sessionCardGap),
        ],
      ],
    );
  }

  /// Phase 4.2 — staggered entrance for brief cards, capped at index
  /// 11 (kMotionStaggerMaxIndex). The cap stops the stagger; cards
  /// beyond render via the same wrapper but with a delay clamped to
  /// the cap's value, so they enter on the same frame as card #11.
  Widget _wrapBriefCardEntrance({required int index, required Widget child}) {
    // Brief stack starts entering at 240ms (greeting=0ms, yesterday=80ms,
    // session-header=160ms, first card=240ms, subsequent cards stagger
    // 60ms each from there). Per spec: stagger 60ms per card from 240.
    final clamped = index <= kMotionStaggerMaxIndex
        ? index
        : kMotionStaggerMaxIndex;
    final delayMs = 240 + clamped * 60;
    return CueAnimatedEntrance(
      delay: Duration(milliseconds: delayMs),
      child: child,
    );
  }

  /// Phase 4.0.8-step-B-surface-1.2 — 5-widget glance section.
  /// On wide viewports (>700px content): two 2-up rows with CueNoticed
  /// stretching full-width between them. On narrow: all five stack
  /// single-column. CueNoticed hides itself entirely when no stagnant
  /// goal exists (no empty state).
  Widget _buildAtAGlanceSection() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth <= 700;
        final pulse    = ThisWeekWidget(weekData: _weekPulse);
        final pending  = PendingNotesWidget(pending: _pendingNotes);
        final goals    = ActiveGoalsWidget(goals: _activeGoals);
        final tomorrow = TomorrowWidget(tomorrow: _tomorrow);
        final noticed  = _noticed != null
            ? CueNoticedWidget(insight: _noticed!)
            : null;

        if (narrow) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              pulse,
              const SizedBox(height: CueGap.s12),
              pending,
              if (noticed != null) ...[
                const SizedBox(height: CueGap.s12),
                noticed,
              ],
              const SizedBox(height: CueGap.s12),
              goals,
              const SizedBox(height: CueGap.s12),
              tomorrow,
            ],
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: pulse),
                  const SizedBox(width: CueGap.s12),
                  Expanded(child: pending),
                ],
              ),
            ),
            if (noticed != null) ...[
              const SizedBox(height: CueGap.s12),
              noticed,
            ],
            const SizedBox(height: CueGap.s12),
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: goals),
                  const SizedBox(width: CueGap.s12),
                  Expanded(child: tomorrow),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildTodayBriefCardForRoster(
    Map<String, dynamic> row, {
    bool isUpNext = false,
  }) {
    final cl       = Map<String, dynamic>.from(row['clients'] as Map? ?? {});
    final clientId = cl['id']?.toString() ?? '';
    final clientName = _toTitleCase(
        (cl['name'] as String?)?.trim() ?? 'Unknown');
    final ageRaw    = cl['age'];
    final age       = ageRaw is int
        ? ageRaw
        : (ageRaw is String ? int.tryParse(ageRaw) : null);
    final diagnosis = (cl['diagnosis'] as String?)?.trim();

    final last = _lastSessionByClient[clientId];
    final brief = TodayBrief(
      clientName: clientName,
      clientAge: age != null && age > 0 ? age : null,
      clientLensSubtitle:
          diagnosis != null && diagnosis.isNotEmpty ? diagnosis : null,
      baselinePhase: last == null,
      lastSessionDateLabel: _formatLastDate(last),
      lastTargetBehavior: last == null
          ? null
          : (last['target_behaviour'] as String?)?.trim(),
      lastActivity: last == null
          ? null
          : (last['activity_name'] as String?)?.trim(),
      lastNarrative: last == null ? null : _briefNarrativeFromSession(last),
      lastAccuracy:  last == null ? null : _formatAccuracy(last),
      nextSessionFocus: last == null
          ? null
          : (last['next_session_focus'] as String?)?.trim(),
      todayTimeLabel: null,
    );
    return TodayBriefCard(
      brief:    brief,
      isUpNext: isUpNext,
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          // Phase 4.0.7.39 — URL bar reflects /clients/:id.
          settings: RouteSettings(name: '/clients/${cl['id']}'),
          builder: (_) => ClientProfileScreen(client: cl),
        ),
      ).then((_) => _load()),
    );
  }

  String? _formatLastDate(Map<String, dynamic>? row) {
    if (row == null) return null;
    final dateStr = (row['date'] as String?) ??
        (row['created_at'] as String?)?.substring(0, 10);
    final dt = _safeParseDate(dateStr);
    if (dt == null) return null;
    return _formatRelativeDate(dt);
  }

  String? _briefNarrativeFromSession(Map<String, dynamic> row) {
    // Pull a one-glance narrative: prefer SOAP S, then notes, then
    // client_affect summary. Trim to ~140 chars so the card stays
    // single-glance-readable.
    String? text;
    final soap = row['soap_note'];
    if (soap is String && soap.trim().isNotEmpty) {
      try {
        final m = jsonDecode(soap) as Map<String, dynamic>;
        final s = (m['s'] as String?)?.trim();
        if (s != null && s.isNotEmpty) text = s;
      } catch (_) {/* not JSON — fall through */}
      text ??= soap.trim();
    }
    if (text == null) {
      final notes = (row['notes'] as String?)?.trim();
      if (notes != null && notes.isNotEmpty) text = notes;
    }
    if (text == null) {
      final affect = (row['client_affect'] as String?)?.trim();
      if (affect != null && affect.isNotEmpty) {
        text = 'Client affect: $affect.';
      }
    }
    if (text == null) return null;
    if (text.length > 140) text = '${text.substring(0, 137)}…';
    return text;
  }

  String? _formatAccuracy(Map<String, dynamic> row) {
    final attempts = _toIntOrNull(row['attempts']);
    if (attempts == null || attempts <= 0) return null;
    final indep = _toIntOrNull(row['independent_responses']) ?? 0;
    final pct = ((indep / attempts) * 100).round();
    return '$indep of $attempts ($pct%)';
  }

  int? _toIntOrNull(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v);
    return null;
  }

  // ── Greeting block ──────────────────────────────────────────────────────

  // Phase 4.0.8-step-B-surface-1.2 — greeting block restored to a
  // Row(cuttlefish-column + Expanded(content)). Surface 1's pure-
  // typography variant lost the soul carrier; 1.2 brings the
  // cuttlefish back at 64px softWave (down from 96px pre-1) anchored
  // in her own 80px column.
  //
  // Founder direction: "left margin but leave it" — 80px column slot
  // sits between the dark sidebar's right edge and the content
  // padding. Cuttlefish reads as a parallel companion, not inline
  // with the greeting text.
  //
  // Sizing lock per spine Revision 2026-05-09 (cuttlefish placement
  // learning): 64px is in the small-anchored band; the 24-60 middle
  // ground is the failure zone we explicitly avoid.
  //
  // Rule 2 amber once-per-surface lock holds: amber lives ONLY on
  // the greeting subline ("3 sessions today — Aarav is your first.").
  // Headline is kCueInk. Action links use kCueInk + subtle underline.
  Widget _buildGreetingBlock() {
    final hour = DateTime.now().hour;
    final greetingPrefix = hour < 12
        ? 'Good morning'
        : (hour < 17 ? 'Good afternoon' : 'Good evening');
    final headline = _slpFirstName != null
        ? '$greetingPrefix, $_slpFirstName.'
        : '$greetingPrefix.';

    final subline = _greetingSubline();

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Phase 4.2 — cuttlefish wrapped in TweenAnimationBuilder so
        // glanceAngle changes (driven by hover on yesterday rows +
        // first brief card) interpolate smoothly toward the target
        // value. CueCuttlefish itself reads the static value passed
        // in each frame; the tween mechanism lives at this site.
        SizedBox(
          width: 80,
          child: Center(
            child: SizedBox(
              width:  64,
              height: 64,
              child: TweenAnimationBuilder<double>(
                // Begin starts neutral on first build; on subsequent
                // builds where _glanceAngle changes, TweenAnimationBuilder
                // replaces begin with the current animated value of
                // the previous tween — so the cuttlefish smoothly
                // interpolates from her current pose to the new target.
                tween: Tween<double>(begin: 0.0, end: _glanceAngle),
                duration: kMotionGlanceDuration,
                curve:    kMotionGlanceCurve,
                builder: (_, value, _) => CueCuttlefish(
                  size:        64,
                  state:       CueState.softWave,
                  glanceAngle: value,
                ),
              ),
            ),
          ),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize:       MainAxisSize.min,
            children: [
              // H1 row — state-conditional Iowan serif. Reopened pill
              // sits inline at the right edge when day state is
              // reopened (Phase 4.0.8-step-B-surface-1.2: less
              // prominent position than the pre-1.2 top-of-page slot
              // — the pill is a hint, not a banner).
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(child: Text(headline, style: CueTypeV3.h1())),
                  if (_dayState.state == CueDayState.reopened) ...[
                    const SizedBox(width: 12),
                    _ReopenedPill(),
                  ],
                ],
              ),
              const SizedBox(height: CueGap.s4),
              // Greeting subline — single amber site on this surface state.
              Text(subline, style: CueTypeV3.body(color: kCueAmber)),
            ],
          ),
        ),
      ],
    );
  }

  String _greetingSubline() {
    final n = _rosterRows.length;
    if (n == 0) return 'No sessions on the calendar today.';
    final firstClient = _rosterRows.first['clients'] as Map?;
    final firstName   = _firstNameOf(firstClient?['name'] as String?);
    final word        = n == 1 ? 'session' : 'sessions';
    if (firstName == null) return '$n $word today.';
    // session_time isn't part of this schema — render the no-time variant.
    return '$n $word today — $firstName is your first.';
  }

  // ── Eyebrow row + add-roster button ─────────────────────────────────────

  // Phase 4.0.8-step-B-surface-1.2 — section row uses sectionTitle
  // (Inter 13/600 sentence-case), NOT mono uppercase tracked. Per
  // the eyebrow doctrine, page-level section headers are human
  // content labels, not data — they get the sans sentence-case
  // treatment. The pre-1.2 toUpperCase() at the call site is dropped.
  Widget _buildEyebrowRow({required String label, Widget? trailing}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Text(label, style: CueTypeV3.sectionTitle()),
        ),
        if (trailing != null) trailing,
      ],
    );
  }

  Widget _buildAddRosterButton() {
    return GestureDetector(
      onTap: _showAddSheet,
      child: Container(
        width:  CueSize.sendButton,    // 36
        height: CueSize.sendButton,    // 36
        decoration: BoxDecoration(
          border:       Border.all(
              color: kCueBorder, width: kCueCardBorderW),
          borderRadius: BorderRadius.circular(kCueMediumRadius),
          color:        kCueSurfaceWhite,
        ),
        child: const Icon(Icons.add_rounded,
            size: CueGap.s18, color: kCueInk),
      ),
    );
  }

  Widget _buildEmptyTodayHint() {
    // Lightweight inline empty state — the headline subline already says
    // "No sessions on the calendar today.", so this is just an affordance.
    return GestureDetector(
      onTap: _showAddSheet,
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: CueGap.s16, vertical: CueGap.s12),
        decoration: BoxDecoration(
          border:       Border.all(
              color: kCueBorder, width: kCueCardBorderW),
          borderRadius: BorderRadius.circular(kCueMediumRadius),
          color:        kCueSurfaceWhite,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.add_rounded, size: CueGap.s16, color: kCueInk),
            const SizedBox(width: CueGap.s8),
            Text('Add clients to today', style: CueTypeV3.h2()),
          ],
        ),
      ),
    );
  }

  // ── Session brief card ──────────────────────────────────────────────────

  // Phase 4.0.7.22a — replaced by TodayBriefCard. Kept for the
  // recovery path documented in MOBILE_AUDIT.md.
  // ignore: unused_element
  Widget _buildSessionBriefCard(Map<String, dynamic> row) {
    final cl       = Map<String, dynamic>.from(row['clients'] as Map? ?? {});
    final rosterId = row['id'].toString();
    final clientId = cl['id']?.toString() ?? '';

    final clientName = _toTitleCase(
        (cl['name'] as String?)?.trim() ?? 'Unknown');
    final ageRaw    = cl['age'];
    final age       = ageRaw is int
        ? ageRaw
        : (ageRaw is String ? int.tryParse(ageRaw) : null);
    final diagnosis = (cl['diagnosis'] as String?)?.trim();

    // "Age 0" reads as data noise (placeholder rows, unborn DOBs); drop it
    // and just show the diagnosis when age isn't a usable positive int.
    final subtitle = [
      if (age != null && age > 0) 'Age $age',
      if (diagnosis != null && diagnosis.isNotEmpty) diagnosis,
    ].join(' · ');

    return Dismissible(
      key:       Key(rosterId),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding:   const EdgeInsets.only(right: CueGap.s20),
        decoration: BoxDecoration(
          color:        const Color(0xFFFFEEEE),
          borderRadius: BorderRadius.circular(CueRadius.s20),
        ),
        child: Icon(
          Icons.remove_circle_outline_rounded,
          color: Colors.red.shade300,
          size:  CueGap.s20,
        ),
      ),
      onDismissed: (_) => _removeFromRoster(rosterId),
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: CueGap.s20, vertical: CueGap.s16),
        decoration: BoxDecoration(
          color:        Colors.white,
          border:       Border.all(
              color: CueColors.divider, width: CueSize.hairline),
          borderRadius: BorderRadius.circular(CueRadius.s20),
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
            if (subtitle.isNotEmpty) ...[
              const SizedBox(height: CueGap.s4),
              Text(
                subtitle,
                style: CueType.bodyMedium.copyWith(
                  color: CueColors.inkPrimary
                      .withValues(alpha: CueAlpha.subtitleText),
                ),
              ),
            ],
            const SizedBox(height: CueGap.s12),
            Text(
              'Last session: ${_lastSessionState(clientId, rosterId)}.',
              style: CueType.custom(
                fontSize: 14,
                weight:   FontWeight.w400,
                color: CueColors.inkPrimary
                    .withValues(alpha: CueAlpha.bodyText),
                height:   1.45,
              ),
            ),
            const SizedBox(height: CueGap.s14),
            _buildSessionActionRow(rosterId: rosterId, clientMap: cl),
          ],
        ),
      ),
    );
  }

  // ignore: unused_element
  Widget _buildSessionActionRow({
    required String rosterId,
    required Map<String, dynamic> clientMap,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Primary CTA — dark-ink rectangle, CueRadius.s8.
        GestureDetector(
          onTap: () async {
            _markDocumented(rosterId);
            await Navigator.push(
              context,
              MaterialPageRoute(
                // Phase 4.0.7.39 — URL bar reflects /clients/:id.
                settings: RouteSettings(name: '/clients/${clientMap['id']}'),
                builder: (_) => ClientProfileScreen(client: clientMap),
              ),
            );
            _load();
          },
          child: Container(
            padding: const EdgeInsets.symmetric(
                horizontal: CueGap.s16, vertical: CueGap.s8),
            decoration: BoxDecoration(
              color:        CueColors.inkPrimary,
              borderRadius: BorderRadius.circular(CueRadius.s8),
            ),
            child: Text(
              'Start session →',
              style: CueType.custom(
                fontSize: 13,
                weight:   FontWeight.w600,
                color:    Colors.white,
              ),
            ),
          ),
        ),
        const SizedBox(width: CueGap.s12),
        // Secondary amber text-links separated by a 0.25-alpha middot.
        // Both targets are the chart screen (timeline holds past notes;
        // goals section holds the goals view).
        Flexible(
          child: Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              CueAmberLink(
                label: 'open last note',
                onTap: () => _openClient(clientMap),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: CueGap.s8),
                child: Text(
                  '·',
                  style: CueType.bodyMedium.copyWith(
                    color: CueColors.inkPrimary
                        .withValues(alpha: CueAlpha.middotDivider),
                  ),
                ),
              ),
              CueAmberLink(
                label: 'review goals',
                onTap: () => _openClient(clientMap),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _openClient(Map<String, dynamic> client) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        // Phase 4.0.7.39 — URL bar reflects /clients/:id.
        settings: RouteSettings(name: '/clients/${client['id']}'),
        builder: (_) => ClientProfileScreen(client: client),
      ),
    );
    _load();
  }

  // ── This-week pulse ─────────────────────────────────────────────────────

  // Phase 4.0.7.22a — week pulse zone removed from the Today body
  // when Variant B brief stack shipped. Kept here for the recovery
  // path documented in MOBILE_AUDIT.md.
  // ignore: unused_element
  Widget _buildWeekPulse() {
    final cards = [
      _PulseCardData(
        number: _weekSessionCount,
        label:  'sessions',
      ),
      _PulseCardData(
        number: _weekDocumentedCount,
        label:  'documented',
      ),
      _PulseCardData(
        number: _weekGoalsAchieved,
        label:  _weekGoalsAchieved == 1 ? 'goal achieved' : 'goals achieved',
      ),
    ];
    // IntrinsicHeight gives the Row a finite "tallest child" height so the
    // CrossAxisAlignment.stretch below has something to stretch *to*.
    // Without it, the Row's height is unbounded (we're inside a vertical
    // ListView) and `stretch` cascades infinity to each Expanded child →
    // RenderBox layout crash. The IntrinsicHeight wrap is the canonical
    // pattern for "make these cards visually equal in height".
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < cards.length; i++) ...[
            Expanded(child: _WeekPulseCard(data: cards[i])),
            if (i != cards.length - 1)
              const SizedBox(width: CueGap.weekPulseGap),
          ],
        ],
      ),
    );
  }

  // ── Helpers ─────────────────────────────────────────────────────────────

  /// Phase 3.2: title-case display name routed through [NameFormatter]
  /// so all-upper / all-lower data is normalised, mixed case is left alone.
  String _toTitleCase(String name) => NameFormatter.displayName(name);

  /// Phase 3.2: honorific stripping + first-name resolution lives in
  /// the shared [NameFormatter] so Today, Clients, and the chart all
  /// agree on how "Ch. Ranadir" becomes "Ranadir."
  String? _firstNameOf(String? fullName) =>
      NameFormatter.firstNameForGreeting(fullName);

  /// Returns the sentence fragment that follows "Last session: " — three
  /// states per spec: "in progress" / "documented {relativeDate}" /
  /// "not yet documented". Falls back to the third when unknown.
  String _lastSessionState(String clientId, String todayRosterId) {
    // If today's roster is documented = true, treat today's note as the
    // current "last session".
    final todayRow = _rosterRows.firstWhere(
      (r) => r['id'].toString() == todayRosterId,
      orElse: () => const {},
    );
    final todayDocumented =
        (todayRow['session_documented'] as bool?) == true;

    final last = _lastSessionByClient[clientId];
    if (last == null) {
      return todayDocumented ? 'documented today' : 'not yet documented';
    }

    final dateStr = (last['date'] as String?) ??
        (last['created_at'] as String?)?.substring(0, 10);
    final dt = _safeParseDate(dateStr);
    if (dt == null) return 'not yet documented';

    // "In progress" = a session row exists for today, but it has no note.
    final isToday = _isSameDate(dt, DateTime.now());
    final hasNote =
        ((last['soap_note'] as String?)?.trim().isNotEmpty ?? false) ||
        ((last['notes']     as String?)?.trim().isNotEmpty ?? false);
    if (isToday && !hasNote) return 'in progress';
    if (!hasNote) return 'not yet documented';

    return 'documented ${_formatRelativeDate(dt)}';
  }

  bool _isSameDate(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  DateTime? _safeParseDate(String? s) {
    if (s == null) return null;
    try { return DateTime.parse(s); } catch (_) { return null; }
  }

  /// "today" / "yesterday" / "12 Aug" / "12 Aug 2025" depending on distance.
  String _formatRelativeDate(DateTime d) {
    final now = DateTime.now();
    if (_isSameDate(d, now)) return 'today';
    final yesterday = now.subtract(const Duration(days: 1));
    if (_isSameDate(d, yesterday)) return 'yesterday';
    const months = [
      '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final base = '${d.day} ${months[d.month]}';
    return d.year == now.year ? base : '$base ${d.year}';
  }
}

// ── End-of-day stat pill ─────────────────────────────────────────────────────

// Phase 4.0.8-step-B-surface-1 — _StatPill stripped of amber fill +
// border. Numbers in JetBrains Mono (data is mono per Rule 1); labels
// in eyebrow register. The cuttlefish above carries the visual rest;
// this row is pure quantitative scan-target. Founder direction:
// "Cuttlefish carries visual rest" + "no new stats card in this commit"
// — keeping the existing pill but quieting it to spine register.
class _StatPill extends StatelessWidget {
  final int sessions, goalsHit, pending;
  final Color? inkColor;
  const _StatPill({
    required this.sessions,
    required this.goalsHit,
    required this.pending,
    this.inkColor,
  });

  @override
  Widget build(BuildContext context) {
    final labelColor = inkColor ?? kCueInkTertiary;
    return Container(
      decoration: BoxDecoration(
        color:        kCuePaper,
        border:       Border.all(color: kCueBorder, width: kCueCardBorderW),
        // Editorial register pill — radius 20 per spine carve-out
        // (matches Good night Cue / reopen pills).
        borderRadius: BorderRadius.circular(20),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _stat('$sessions', sessions == 1 ? 'Session' : 'Sessions', labelColor),
          _divider(),
          _stat('$goalsHit', goalsHit == 1 ? 'Goal hit' : 'Goals hit', labelColor),
          _divider(),
          _stat('$pending', 'Pending', labelColor),
        ],
      ),
    );
  }

  Widget _stat(String n, String label, Color labelColor) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Number — mono with tabular figures (data is the data language).
          Text(n, style: CueTypeV3.dataMono(color: kCueInk)),
          const SizedBox(height: 2),
          // Stat-pill data label — mono uppercase tracked (data tag,
          // the one carve-out where sans uppercase tracked would be
          // forbidden but mono uppercase tracked is the correct
          // eyebrow doctrine treatment).
          Text(label.toUpperCase(), style: CueTypeV3.dataEyebrow(color: labelColor)),
        ],
      ),
    );
  }

  Widget _divider() => Container(
        width:  0.5,
        height: 24,
        color:  kCueBorder,
      );
}

// ── Phase 4.0.7.5 reopened indicator ────────────────────────────────────────
// Small pill rendered top-right of the Today content when day state is
// reopened. Visual weight is intentionally low — it's a hint, not a banner.
//
// Phase 4.0.8-step-B-surface-1 — pre-spine blue (#85B7EB) replaced with
// kCueInkTertiary text on transparent paper, kCueBorder hairline. Single-
// accent rule keeps amber off this pill; "reopened" is a state hint, not
// a clinical action.
class _ReopenedPill extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color:        Colors.transparent,
        border:       Border.all(color: kCueBorder, width: kCueCardBorderW),
        borderRadius: BorderRadius.circular(20),
      ),
      // State-pill data tag — mono uppercase tracked per eyebrow doctrine.
      child: Text('REOPENED', style: CueTypeV3.dataEyebrow()),
    );
  }
}

// ── This-week pulse card ─────────────────────────────────────────────────────
// Phase 4.0.7.22a removed week pulse from the Today body when Variant B
// brief stack shipped. The classes below remain in repo for the recovery
// path documented in MOBILE_AUDIT.md and are referenced only by the
// dead-code _buildWeekPulse method. Both carry `unused_element` ignores.

// ignore: unused_element
class _PulseCardData {
  final int    number;
  final String label;
  const _PulseCardData({required this.number, required this.label});
}

// ignore: unused_element
class _WeekPulseCard extends StatelessWidget {
  final _PulseCardData data;
  const _WeekPulseCard({required this.data});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: CueGap.s16, vertical: CueGap.s12),
      decoration: BoxDecoration(
        color:        Colors.white,
        border:       Border.all(
            color: CueColors.divider, width: CueSize.hairline),
        borderRadius: BorderRadius.circular(CueRadius.s8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize:       MainAxisSize.min,
        children: [
          Text(
            '${data.number}',
            style: CueType.custom(
              fontSize:      26,
              weight:        FontWeight.w500,
              color:         CueColors.inkPrimary,
              letterSpacing: -0.6,
              height:        1.1,
            ),
          ),
          const SizedBox(height: CueGap.s8),
          Text(
            data.label,
            style: CueType.bodySmall.copyWith(
              color: CueColors.inkPrimary
                  .withValues(alpha: CueAlpha.subtitleText),
            ),
          ),
        ],
      ),
    );
  }
}
