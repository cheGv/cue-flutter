import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/name_formatter.dart';
import '../theme/cue_theme.dart';
import '../theme/cue_tokens.dart';
import '../theme/cue_typography.dart';
import '../widgets/app_layout.dart';
import '../widgets/cue_amber_link.dart';
import '../widgets/cue_cuttlefish.dart';
import 'client_profile_screen.dart';

// ── Legacy local palette ─────────────────────────────────────────────────────
// Pre-Phase-3.1 yesterday-reminder code (further down) still references
// these. Phase 3.1 brief / pulse / greeting blocks all flow from CueColors
// + CueAlpha + cue_tokens directly.
const Color _paper  = Color(0xFFFAFAF7);
const Color _ink    = Color(0xFF1B2B4B);
const Color _ghost  = Color(0xFF6B7690);
const Color _amber  = Color(0xFFB45309);
const Color _border = Color(0xFFE8E4DC);

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

  @override
  void initState() {
    super.initState();
    _slpFirstName = _resolveSlpFirstName();
    _load();
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
      final rows = await _supabase
          .from('sessions')
          .select('id, client_id, date, soap_note, notes, created_at')
          .eq('user_id', uid)
          .inFilter('client_id', clientIds)
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
            .gte('date', sevenDaysAgo),
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
              .eq('client_id', clientId),
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
      backgroundColor: _paper,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
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
                    color: _border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Who are you seeing today?',
                style: CueType.serif(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: _ink,
                ),
              ),
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
                        style: GoogleFonts.dmSans(
                          fontSize: 14,
                          color:
                              alreadyOn ? _ghost : _ink,
                          fontWeight: alreadyOn
                              ? FontWeight.normal
                              : FontWeight.w500,
                        ),
                      ),
                      subtitle: Text(
                        [
                          if (cl['age'] != null) 'Age ${cl['age']}',
                          if ((cl['diagnosis'] as String?)?.isNotEmpty == true)
                            cl['diagnosis'] as String,
                        ].join(' · '),
                        style: GoogleFonts.dmSans(fontSize: 12, color: _ghost),
                      ),
                      activeColor:     _ink,
                      checkColor:      Colors.white,
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
                      style: GoogleFonts.dmSans(color: _ghost, fontSize: 14),
                    ),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _ink,
                      foregroundColor: Colors.white,
                      elevation:       0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
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
                      style: GoogleFonts.dmSans(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
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

  // ── End-of-day detection ────────────────────────────────────────────────
  // True when every roster row for today has session_documented = true AND
  // there is at least one row. This is the "good work today" moment.
  bool get _isEndOfDay {
    if (_rosterRows.isEmpty) return false;
    return _rosterRows.every((r) => (r['session_documented'] as bool?) == true);
  }

  @override
  Widget build(BuildContext context) {
    return AppLayout(
      title:       'Today',
      activeRoute: 'today',
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(
                strokeWidth: 1.5,
                color: CueColors.amber,
              ),
            )
          : (_isEndOfDay
              ? _buildEndOfDayResting()
              : LayoutBuilder(
                  builder: (context, constraints) {
                    final hPad = constraints.maxWidth > 700 ? 48.0 : 24.0;
                    return ColoredBox(
                      color: _paper,
                      child: ListView(
                        padding: EdgeInsets.fromLTRB(hPad, 32, hPad, 96),
                        children: [
                          if (_yesterdayMissed.isNotEmpty)
                            _buildYesterdayReminder(),
                          _buildTodayZone(),
                        ],
                      ),
                    );
                  },
                )),
    );
  }

  // ── End-of-day resting moment ──────────────────────────────────────────
  // Forces night-mode visual regardless of user setting — end of day IS
  // night. Centered Cue resting + stat pill + "Cue will prepare tomorrow's
  // briefs overnight." footnote.
  Widget _buildEndOfDayResting() {
    // Counts
    final sessionsDone = _rosterRows.length;
    int goalsHit = 0;
    int pending  = 0;
    for (final r in _rosterRows) {
      final goalMet = (r['goal_met'] as String?)?.toLowerCase();
      if (goalMet == 'yes' || goalMet == 'met') goalsHit++;
      // "Pending" = anything flagged for tomorrow follow-up. Without a
      // dedicated column we infer from next_session_focus presence.
      final next = (r['next_session_focus'] as String?)?.trim();
      if (next != null && next.isNotEmpty) pending++;
    }

    return Stack(
      children: [
        // Forced near-black background — end of day IS night.
        const Positioned.fill(
          child: ColoredBox(color: CueColors.backgroundDark),
        ),
        // Soft amber halo beneath the cuttlefish.
        Positioned.fill(
          child: Center(
            child: Container(
              width:  220,
              height: 220,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    CueColors.amber.withValues(alpha: 0.10),
                    CueColors.amber.withValues(alpha: 0.0),
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
              const CueCuttlefish(size: 96, state: CueState.resting),
              const SizedBox(height: 24),
              Text(
                'Good work today.',
                style: CueType.displayMedium
                    .copyWith(color: CueColors.inkDark),
              ),
              const SizedBox(height: 6),
              Text(
                'See you tomorrow.',
                style: CueType.bodyLarge
                    .copyWith(color: CueColors.inkSecondaryDark),
              ),
              const SizedBox(height: 28),
              _StatPill(
                sessions: sessionsDone,
                goalsHit: goalsHit,
                pending:  pending,
              ),
              const SizedBox(height: 14),
              Text(
                'Cue will prepare tomorrow\'s briefs overnight.',
                style: CueType.bodySmall.copyWith(
                  color:     CueColors.inkTertiaryDark,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── Zone 1: Yesterday reminder ──────────────────────────────────────────────

  Widget _buildYesterdayReminder() {
    final n     = _yesterdayMissed.length;
    final names = _yesterdayMissed.map((r) {
      final cl = r['clients'] as Map?;
      return (cl != null ? cl['name']?.toString() : null) ?? 'Unknown';
    }).join(', ');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: () => setState(() => _expandYesterday = !_expandYesterday),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color:  _amber.withOpacity(0.07),
              border: Border.all(color: _amber.withOpacity(0.22)),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(Icons.history_rounded, size: 15, color: _amber),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '$n ${n == 1 ? 'session' : 'sessions'} from yesterday not documented — $names',
                    style: GoogleFonts.dmSans(
                      fontSize: 13,
                      color:      _amber,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines:  1,
                    overflow:  TextOverflow.ellipsis,
                  ),
                ),
                Icon(
                  _expandYesterday
                      ? Icons.expand_less_rounded
                      : Icons.expand_more_rounded,
                  size:  16,
                  color: _amber,
                ),
              ],
            ),
          ),
        ),
        if (_expandYesterday) ...[
          const SizedBox(height: 8),
          ..._yesterdayMissed.map((row) {
            final cl = (row['clients'] as Map?) ?? {};
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
              child: Row(
                children: [
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      cl['name']?.toString() ?? 'Unknown',
                      style: GoogleFonts.dmSans(
                        fontSize:   13,
                        color:      _ink,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ClientProfileScreen(
                          client: Map<String, dynamic>.from(cl),
                        ),
                      ),
                    ),
                    style: TextButton.styleFrom(
                      foregroundColor: _ink,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      minimumSize:   Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: Text(
                      'Document →',
                      style: GoogleFonts.dmSans(
                        fontSize: 12, fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
        const SizedBox(height: 28),
      ],
    );
  }

  // ── Phase 3.1: Today screen content blocks ──────────────────────────────

  Widget _buildTodayZone() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildGreetingBlock(),
        const SizedBox(height: CueGap.greetingToEyebrow),

        // Today's session(s) section — eyebrow row keeps the "+" affordance
        // for adding clients to the roster (legacy behaviour preserved,
        // visually demoted from the prior big header).
        _buildEyebrowRow(
          label: "today's session",
          trailing: _buildAddRosterButton(),
        ),
        const SizedBox(height: CueGap.eyebrowToCard),
        if (_rosterRows.isEmpty)
          _buildEmptyTodayHint()
        else
          ..._rosterRows.asMap().entries.map((e) => Padding(
                padding: EdgeInsets.only(
                  bottom: e.key == _rosterRows.length - 1
                      ? 0
                      : CueGap.sessionCardGap,
                ),
                child: _buildSessionBriefCard(e.value),
              )),

        const SizedBox(height: CueGap.cardToEyebrow),

        _buildEyebrowRow(label: 'this week'),
        const SizedBox(height: CueGap.eyebrowToCard),
        _buildWeekPulse(),
      ],
    );
  }

  // ── Greeting block ──────────────────────────────────────────────────────

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
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const SizedBox(
          width:  CueSize.cuttlefishWelcome,
          height: CueSize.cuttlefishWelcome,
          child: CueCuttlefish(
              size: CueSize.cuttlefishWelcome, state: CueState.softWave),
        ),
        const SizedBox(width: CueGap.greetingFishToText),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                headline,
                style: CueType.custom(
                  fontSize:      20,
                  weight:        FontWeight.w500,
                  color:         CueColors.amber,
                  letterSpacing: -0.3,
                  height:        1.25,
                ),
              ),
              const SizedBox(height: CueGap.s4),
              Text(
                subline,
                style: CueType.bodyLarge.copyWith(
                  color: CueColors.amber
                      .withValues(alpha: CueAlpha.amberSubline),
                ),
              ),
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

  Widget _buildEyebrowRow({required String label, Widget? trailing}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Text(
            label,
            style: CueType.bodySmall.copyWith(
              color: CueColors.inkPrimary
                  .withValues(alpha: CueAlpha.eyebrowText),
            ),
          ),
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
              color: CueColors.divider, width: CueSize.hairline),
          borderRadius: BorderRadius.circular(CueRadius.s8),
          color:        Colors.white,
        ),
        child: Icon(Icons.add_rounded,
            size: CueGap.s18, color: CueColors.inkPrimary),
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
              color: CueColors.divider, width: CueSize.hairline),
          borderRadius: BorderRadius.circular(CueRadius.s8),
          color:        Colors.white,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.add_rounded,
                size: CueGap.s16, color: CueColors.inkPrimary),
            const SizedBox(width: CueGap.s8),
            Text(
              'Add clients to today',
              style: CueType.bodyMedium.copyWith(
                color:      CueColors.inkPrimary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Session brief card ──────────────────────────────────────────────────

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
        builder: (_) => ClientProfileScreen(client: client),
      ),
    );
    _load();
  }

  // ── This-week pulse ─────────────────────────────────────────────────────

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

class _StatPill extends StatelessWidget {
  final int sessions, goalsHit, pending;
  const _StatPill({
    required this.sessions,
    required this.goalsHit,
    required this.pending,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: CueColors.amber.withValues(alpha: 0.08),
        border: Border.all(
            color: CueColors.amber.withValues(alpha: 0.20),
            width: 0.5),
        borderRadius: BorderRadius.circular(28),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _stat('$sessions', sessions == 1 ? 'Session' : 'Sessions'),
          _divider(),
          _stat('$goalsHit', goalsHit == 1 ? 'Goal hit' : 'Goals hit'),
          _divider(),
          _stat('$pending', 'Pending'),
        ],
      ),
    );
  }

  Widget _stat(String n, String label) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(n,
              style: CueType.displaySmall.copyWith(color: CueColors.amber)),
          const SizedBox(height: 2),
          Text(label.toUpperCase(),
              style: CueType.labelSmall.copyWith(
                  color: CueColors.inkTertiaryDark)),
        ],
      ),
    );
  }

  Widget _divider() => Container(
        width:  0.5,
        height: 24,
        color:  CueColors.amber.withValues(alpha: 0.20),
      );
}

// ── This-week pulse card ─────────────────────────────────────────────────────

class _PulseCardData {
  final int    number;
  final String label;
  const _PulseCardData({required this.number, required this.label});
}

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
