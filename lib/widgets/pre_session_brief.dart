import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

// ── Design tokens (§5 palette) ─────────────────────────────────────────────────
const Color _ink      = Color(0xFF1B2B4B);
const Color _ghost    = Color(0xFF6B7690);
const Color _amber    = Color(0xFFB45309);     // pattern flag — task spec
const Color _briefBg  = Color(0xFFF0EDE8);    // slightly warmer than _paper
const Color _skeleton = Color(0xFF9CA3AF);

// ── Proxy ──────────────────────────────────────────────────────────────────────
// §4: plain http.post to Render, never functions.invoke().
// Backend endpoint /pre-session-brief must accept:
//   { model, system, user_message, client_id }
// and return an Anthropic Messages API response body.
const String _proxyBase = 'https://cue-ai-proxy.onrender.com';

// ── Anti-hallucination system prompt (§9.1) ────────────────────────────────────
const String _systemPrompt =
    'You are Cue, a clinical co-pilot for Speech-Language Pathologists. '
    'Generate a pre-session brief using only the data provided. '
    'Never invent observations, scores, or recommendations not grounded '
    'in the data. If a field is missing, say "not documented". '
    'Be precise, brief, and clinically accurate. '
    'Respond in plain text only. No markdown. No bullet points. '
    'Maximum 8 lines total.';

// ── State machine ──────────────────────────────────────────────────────────────
enum _Phase { loading, notScheduled, noSessions, loaded, error }

// ── Widget ─────────────────────────────────────────────────────────────────────

class PreSessionBrief extends StatefulWidget {
  final Map<String, dynamic> client;
  const PreSessionBrief({super.key, required this.client});

  @override
  State<PreSessionBrief> createState() => _PreSessionBriefState();
}

class _PreSessionBriefState extends State<PreSessionBrief> {
  final _supabase = Supabase.instance.client;

  _Phase _phase = _Phase.loading;
  String _briefText = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  // ── Data + AI orchestration ─────────────────────────────────────────────────

  Future<void> _load() async {
    try {
      // ── Step 0: daily_roster gate ──────────────────────────────────────────
      // Only generate a brief for clients on today's session list.
      // daily_roster.client_id is uuid; widget.client['id'] is also uuid.
      final today = DateTime.now().toIso8601String().split('T').first;
      final rosterRows = await _supabase
          .from('daily_roster')
          .select('id')
          .eq('client_id', widget.client['id'])
          .eq('session_date', today)
          .limit(1);
      if ((rosterRows as List).isEmpty) {
        if (mounted) setState(() => _phase = _Phase.notScheduled);
        return;
      }

      // ── Step 1: sessions existence check ───────────────────────────────────
      // Isolated query — not bundled with other futures so a column-name
      // mismatch or schema difference in other tables can't silently kill it.
      // Uses widget.client['id'] raw (matches _fetchSessions() in profile screen).
      // select() fetches all columns — avoids breaking on prototype vs canonical
      // column names (prototype uses 'notes'; canonical schema uses 'soap_note').
      final sessionRows = await _supabase
          .from('sessions')
          .select()
          .eq('client_id', widget.client['id'])
          .isFilter('deleted_at', null)
          .order('date', ascending: false)
          .limit(1);

      if (sessionRows.isEmpty) {
        if (mounted) setState(() => _phase = _Phase.noSessions);
        return;
      }

      final lastSession = Map<String, dynamic>.from(sessionRows.first as Map);
      final clientId = widget.client['id'].toString();

      // ── Step 2: STGs + LTGs (non-fatal) ────────────────────────────────────
      // Failures here do not kill the brief — it still renders from session data.
      // select() on LTGs avoids errors if 'domain' column not yet migrated.
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
      } catch (_) {
        // Non-fatal — brief still fires with session data only
      }

      // ── Step 3: evidence per active STG (non-fatal) ─────────────────────────
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
        } catch (_) {
          // Non-fatal
        }
      }

      final stgsWithEvidence = List.generate(stgRows.length, (i) {
        final stg = Map<String, dynamic>.from(stgRows[i] as Map);
        stg['_evidence'] = i < evidenceLists.length ? evidenceLists[i] : [];
        return stg;
      });

      final brief = await _callProxy(
        clientId:    clientId,
        lastSession: lastSession,
        activeStgs:  stgsWithEvidence,
        ltgs: ltgRows
            .map((l) => Map<String, dynamic>.from(l as Map))
            .toList(),
      );

      if (mounted) setState(() { _briefText = brief; _phase = _Phase.loaded; });

    } catch (_) {
      if (mounted) setState(() => _phase = _Phase.error);
    }
  }

  // ── Prompt assembly + HTTP call ─────────────────────────────────────────────

  Future<String> _callProxy({
    required String clientId,
    required Map<String, dynamic> lastSession,
    required List<Map<String, dynamic>> activeStgs,
    required List<Map<String, dynamic>> ltgs,
  }) async {
    final cl = widget.client;
    final sb = StringBuffer();

    // Client demographics
    sb.writeln('CLIENT: ${cl['name'] ?? 'not documented'}'
        ', Age ${cl['age'] ?? 'not documented'}');
    sb.writeln('Diagnosis: ${cl['diagnosis'] ?? 'not documented'}');
    sb.writeln('Primary language: ${cl['primary_language'] ?? 'not documented'}');
    sb.writeln();

    // Long-term goals
    if (ltgs.isNotEmpty) {
      sb.writeln('LONG-TERM GOALS:');
      for (final ltg in ltgs) {
        final domain = ltg['domain'] != null ? ' (${ltg['domain']})' : '';
        sb.writeln('- ${ltg['goal_text'] ?? 'not documented'}$domain');
      }
      sb.writeln();
    }

    // Active STGs with evidence
    sb.writeln('ACTIVE SHORT-TERM GOALS:');
    for (final stg in activeStgs) {
      sb.writeln('STG: ${stg['target_behavior'] ?? 'not documented'}');

      final level = stg['current_cue_level'];
      sb.writeln('  Support level: ${level ?? 'not documented'}');

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
          final date = evMap['created_at']?.toString().split('T').first ?? 'no date';
          final pct  = evMap['accuracy_pct'];
          final cue  = evMap['cue_level_used'] ?? 'not documented';
          sb.writeln('    $date: '
              '${pct != null ? '${(pct as num).toStringAsFixed(1)}%' : 'not documented'}'
              ', cue: $cue');
        }
      }
      sb.writeln();
    }

    // Last session — handles both canonical schema (soap_note jsonb) and
    // prototype schema (notes text) so neither throws a null-read error.
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

    final token = _supabase.auth.currentSession?.accessToken;
    final response = await http.post(
      Uri.parse('$_proxyBase/pre-session-brief'),
      headers: {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      },
      body: jsonEncode({
        'model':        'claude-sonnet-4-20250514',
        'system':       _systemPrompt,
        'user_message': sb.toString(),
        'client_id':    clientId,
      }),
    ).timeout(const Duration(seconds: 30));

    if (response.statusCode != 200) {
      throw Exception('proxy error ${response.statusCode}');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final text = data['content']?[0]?['text']
        ?? data['brief']
        ?? data['text']
        ?? response.body;
    return text.toString().trim();
  }

  // ── Build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    // notScheduled: plain muted text, no accent border, no background
    if (_phase == _Phase.notScheduled) {
      final name = widget.client['name'] as String? ?? 'this client';
      return Text(
        'Add $name to today\'s session list to generate a pre-session brief.',
        style: GoogleFonts.dmSans(
          fontSize: 13,
          color: const Color(0xFF9CA3AF),
        ),
      );
    }

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Left accent bar — 3px navy (§5)
          Container(width: 3, color: _ink),

          // Brief content panel
          Expanded(
            child: ColoredBox(
              color: _briefBg,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Section title — Syne 11pt uppercase letterspaced ghost
                    Text(
                      'PRE-SESSION BRIEF',
                      style: GoogleFonts.syne(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: _ghost,
                        letterSpacing: 1.0,
                      ),
                    ),
                    const SizedBox(height: 8),

                    // Content area
                    _buildContent(),

                    // "Ask Cue →" — only when brief is loaded (Phase 1: snackbar)
                    if (_phase == _Phase.loaded) ...[
                      const SizedBox(height: 10),
                      Align(
                        alignment: Alignment.centerRight,
                        child: GestureDetector(
                          onTap: () => ScaffoldMessenger.of(context)
                              .showSnackBar(const SnackBar(
                            content: Text('Chat coming soon'),
                            duration: Duration(seconds: 2),
                          )),
                          child: Text(
                            'Ask Cue →',
                            style: GoogleFonts.dmSans(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: _ink,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    switch (_phase) {
      case _Phase.loading:
        return Text(
          'Preparing brief...',
          style: GoogleFonts.dmSans(fontSize: 13, color: _skeleton),
        );

      case _Phase.notScheduled:
        // Handled by build() — should not reach here
        return const SizedBox.shrink();

      case _Phase.noSessions:
        return Text(
          'No sessions documented yet. Run your first Narrator session'
          ' to activate clinical intelligence.',
          style: GoogleFonts.dmSans(fontSize: 14, color: _ink, height: 1.5),
        );

      case _Phase.error:
        return Text(
          'Brief unavailable — check connection',
          style: GoogleFonts.dmSans(fontSize: 13, color: _skeleton),
        );

      case _Phase.loaded:
        return _buildBriefBody(_briefText);
    }
  }

  // Renders brief lines; highlights PATTERN FLAG lines in amber (§9 / task spec)
  Widget _buildBriefBody(String text) {
    final lines = text
        .split('\n')
        .where((l) => l.trim().isNotEmpty)
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: lines.map((line) {
        final isFlag = line.trimLeft().startsWith('PATTERN FLAG:');
        return Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Text(
            line,
            style: GoogleFonts.dmSans(
              fontSize: 14,
              color: isFlag ? _amber : _ink,
              height: 1.5,
            ),
          ),
        );
      }).toList(),
    );
  }
}
