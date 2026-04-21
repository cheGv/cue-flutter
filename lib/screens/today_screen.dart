import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../widgets/app_layout.dart';
import 'client_profile_screen.dart';

// ── Design tokens (§5 palette) ─────────────────────────────────────────────────
const Color _paper    = Color(0xFFFAFAF7);
const Color _ink      = Color(0xFF1B2B4B);
const Color _ghost    = Color(0xFF6B7690);
const Color _amber    = Color(0xFFB45309);
const Color _border   = Color(0xFFE8E4DC);
const Color _skeleton = Color(0xFF9CA3AF);

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

String _formatDate(DateTime d) {
  const days = [
    'Monday', 'Tuesday', 'Wednesday', 'Thursday',
    'Friday', 'Saturday', 'Sunday'
  ];
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];
  return '${days[d.weekday - 1]}, ${d.day} ${months[d.month - 1]}';
}

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

  @override
  void initState() {
    super.initState();
    _load();
  }

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
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
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
                style: GoogleFonts.playfairDisplay(
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

  @override
  Widget build(BuildContext context) {
    return AppLayout(
      title:       'Today',
      activeRoute: 'today',
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(
                strokeWidth: 1.5,
                color: Color(0xFF1B2B4B),
              ),
            )
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
            ),
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

  // ── Zone 2: Today's roster ──────────────────────────────────────────────────

  Widget _buildTodayZone() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header row: date + add button
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Text(
                'Today · ${_formatDate(DateTime.now())}',
                style: GoogleFonts.playfairDisplay(
                  fontSize:   18,
                  fontWeight: FontWeight.w700,
                  color:      _ink,
                ),
              ),
            ),
            GestureDetector(
              onTap: _showAddSheet,
              child: Container(
                width:  32,
                height: 32,
                decoration: BoxDecoration(
                  border:       Border.all(color: _border),
                  borderRadius: BorderRadius.circular(8),
                  color:        Colors.white,
                ),
                child: Icon(Icons.add_rounded, size: 18, color: _ink),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),

        // Empty state
        if (_rosterRows.isEmpty) ...[
          Text(
            'Who are you seeing today?',
            style: GoogleFonts.dmSans(fontSize: 15, color: _ghost),
          ),
          const SizedBox(height: 12),
          GestureDetector(
            onTap: _showAddSheet,
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                border:       Border.all(color: _border),
                borderRadius: BorderRadius.circular(10),
                color:        Colors.white,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.add_rounded, size: 16, color: _ink),
                  const SizedBox(width: 8),
                  Text(
                    'Add clients to today',
                    style: GoogleFonts.dmSans(
                      fontSize:   14,
                      color:      _ink,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],

        // Roster cards (swipe-to-remove via Dismissible)
        ..._rosterRows.map(_buildRosterCard),
      ],
    );
  }

  Widget _buildRosterCard(Map<String, dynamic> row) {
    final cl       = Map<String, dynamic>.from(row['clients'] as Map? ?? {});
    final rosterId = row['id'].toString();
    final briefText = row['brief_text'] as String?;

    // First non-empty line of the AI brief, truncated to 100 chars
    String? previewLine;
    if (briefText != null) {
      final lines = briefText
          .split('\n')
          .where((l) => l.trim().isNotEmpty)
          .toList();
      if (lines.isNotEmpty) {
        final first = lines.first.trim();
        previewLine =
            first.length > 100 ? '${first.substring(0, 100)}…' : first;
      }
    }
    final hasPreview = previewLine != null && previewLine.isNotEmpty;

    final metaLine = [
      if (cl['age'] != null) 'Age ${cl['age']}',
      if ((cl['diagnosis'] as String?)?.isNotEmpty == true)
        cl['diagnosis'] as String,
    ].join(' · ');

    return Dismissible(
      key:       Key(rosterId),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding:   const EdgeInsets.only(right: 20),
        margin:    const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color:        const Color(0xFFFFEEEE),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(
          Icons.remove_circle_outline_rounded,
          color: Colors.red.shade300,
          size:  20,
        ),
      ),
      onDismissed: (_) => _removeFromRoster(rosterId),
      child: Container(
        margin:  const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color:        Colors.white,
          border:       Border.all(color: _border),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Name
            Text(
              cl['name']?.toString() ?? 'Unknown',
              style: GoogleFonts.playfairDisplay(
                fontSize:   16,
                fontWeight: FontWeight.w700,
                color:      _ink,
              ),
            ),
            if (metaLine.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                metaLine,
                style: GoogleFonts.dmSans(fontSize: 12, color: _ghost),
              ),
            ],

            // Brief preview or placeholder
            const SizedBox(height: 10),
            Text(
              hasPreview ? previewLine : 'Generating brief...',
              style: GoogleFonts.dmSans(
                fontSize: 13,
                color:    hasPreview ? _ink : _skeleton,
                height:   1.4,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),

            // Start Session
            const SizedBox(height: 14),
            Align(
              alignment: Alignment.centerRight,
              child: GestureDetector(
                onTap: () async {
                  _markDocumented(rosterId); // fire-and-forget
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ClientProfileScreen(client: cl),
                    ),
                  );
                  // Refresh roster on return (brief may have been generated)
                  _load();
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color:        _ink,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'Start Session →',
                    style: GoogleFonts.dmSans(
                      fontSize:   13,
                      color:      Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
