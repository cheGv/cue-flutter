// lib/screens/recall_resolver_test_screen.dart
//
// THROWAWAY debug harness — live end-to-end verification of the recall
// resolver against the launched Supabase environment. Reachable ONLY via
// the kDebugMode-gated route '/debug/recall-test' (see main.dart). Not
// wired into any production surface (Cue Hold pill, Today, ClientProfile).
// Safe to delete in one commit.
//
// What it proves: RecallResolver(source: DirectTableCardSource()) against
// the live sandbox Supabase produces a working roundtrip, and the
// Stopwatch around the resolver call captures the direct-table latency
// (target ~0.5 s warm, the curl-measured number) — NOT the recall-card
// edge function (~1.8 s warm, deliberately avoided here).
//
// GUARDRAIL: the env switch in main.dart is the real protection. This
// screen additionally reads the compile-time target (app_config) and:
//   • shows a red/green/amber banner of the active Supabase URL,
//   • DISABLES the Resolve + 5-sample buttons unless the target is the
//     sandbox ref.
// So even if launched with no --dart-define (i.e. pointed at production),
// the harness refuses to run.

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/app_config.dart';
import '../services/recall_card_source.dart';
import '../services/recall_resolver.dart';

enum _EnvKind { production, sandbox, unknown }

class RecallResolverTestScreen extends StatefulWidget {
  const RecallResolverTestScreen({super.key});

  @override
  State<RecallResolverTestScreen> createState() =>
      _RecallResolverTestScreenState();
}

class _RecallResolverTestScreenState extends State<RecallResolverTestScreen> {
  final TextEditingController _questionCtrl = TextEditingController(
    text: 'what was the last goal for ZZ Latency Test Child',
  );

  // The resolver depends only on the RecallCardSource seam.
  // DirectTableCardSource internally uses Supabase.instance.client, which
  // targets whichever environment main.dart initialized — sandbox when
  // launched with the --dart-define overrides.
  final RecallResolver _resolver =
      RecallResolver(source: DirectTableCardSource());

  List<Map<String, dynamic>> _roster = const [];
  bool _rosterLoading = false;
  String? _rosterError;

  RecallAnswer? _answer;
  int? _lastMs;

  List<int> _sampleMs = const [];
  bool _running = false;

  _EnvKind get _env {
    if (kSupabaseUrl.contains(kProdProjectRef)) return _EnvKind.production;
    if (kSupabaseUrl.contains(kSandboxProjectRef)) return _EnvKind.sandbox;
    return _EnvKind.unknown;
  }

  bool get _isSandbox => _env == _EnvKind.sandbox;

  @override
  void initState() {
    super.initState();
    if (_isSandbox) _loadRoster();
  }

  @override
  void dispose() {
    _questionCtrl.dispose();
    super.dispose();
  }

  // Roster load mirrors _TodayScreenState._load (today_screen.dart:216) —
  // direct clients select, RLS-scoped, no manual user_id filter.
  Future<void> _loadRoster() async {
    setState(() {
      _rosterLoading = true;
      _rosterError = null;
    });
    try {
      final rows = await Supabase.instance.client
          .from('clients')
          .select()
          .isFilter('deleted_at', null)
          .order('name', ascending: true);
      if (!mounted) return;
      setState(() {
        _roster = (rows as List)
            .map((r) => Map<String, dynamic>.from(r as Map))
            .toList();
        _rosterLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _rosterError = '$e';
        _rosterLoading = false;
      });
    }
  }

  Future<void> _resolveOnce() async {
    if (!_isSandbox || _running) return;
    setState(() {
      _running = true;
      _answer = null;
      _lastMs = null;
    });
    final sw = Stopwatch()..start();
    final answer = await _resolver.resolve(
      question: _questionCtrl.text,
      clientRoster: _roster,
    );
    sw.stop();
    if (!mounted) return;
    setState(() {
      _answer = answer;
      _lastMs = sw.elapsedMilliseconds;
      _running = false;
    });
  }

  Future<void> _runFiveWarm() async {
    if (!_isSandbox || _running) return;
    setState(() {
      _running = true;
      _sampleMs = const [];
    });
    final samples = <int>[];
    for (var i = 0; i < 5; i++) {
      final sw = Stopwatch()..start();
      await _resolver.resolve(
        question: _questionCtrl.text,
        clientRoster: _roster,
      );
      sw.stop();
      samples.add(sw.elapsedMilliseconds);
    }
    if (!mounted) return;
    setState(() {
      _sampleMs = samples;
      _running = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final user = Supabase.instance.client.auth.currentUser;
    final canRun = _isSandbox && !_running && _roster.isNotEmpty;

    return Scaffold(
      appBar: AppBar(title: const Text('Recall resolver — live verify (debug)')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _envBanner(),
            const SizedBox(height: 12),
            _authLine(user),
            const SizedBox(height: 4),
            _rosterLine(),
            const Divider(height: 28),
            TextField(
              controller: _questionCtrl,
              decoration: const InputDecoration(
                labelText: 'Question',
                border: OutlineInputBorder(),
              ),
              minLines: 1,
              maxLines: 3,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                FilledButton(
                  onPressed: canRun ? _resolveOnce : null,
                  child: const Text('Resolve'),
                ),
                const SizedBox(width: 12),
                OutlinedButton(
                  onPressed: canRun ? _runFiveWarm : null,
                  child: const Text('Run 5 warm samples'),
                ),
                const SizedBox(width: 12),
                if (_running)
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            _resultArea(),
            const SizedBox(height: 16),
            _sampleArea(),
          ],
        ),
      ),
    );
  }

  Widget _envBanner() {
    final Color bg;
    final String label;
    switch (_env) {
      case _EnvKind.production:
        bg = Colors.red.shade700;
        label = 'PRODUCTION TARGET — Resolve disabled';
        break;
      case _EnvKind.sandbox:
        bg = Colors.green.shade700;
        label = 'SANDBOX TARGET — safe to run';
        break;
      case _EnvKind.unknown:
        bg = Colors.amber.shade800;
        label = 'UNKNOWN TARGET — Resolve disabled';
        break;
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            kSupabaseUrl,
            style: const TextStyle(
              color: Colors.white,
              fontFamily: 'monospace',
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _authLine(User? user) {
    if (user == null) {
      return const Text(
        'NOT SIGNED IN — sign in via the login screen first '
        '(recall reads are RLS-scoped to the signed-in clinician).',
        style: TextStyle(color: Colors.red, fontWeight: FontWeight.w600),
      );
    }
    return Text(
      'Signed in: ${user.email ?? "(no email)"}\nuid: ${user.id}',
      style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
    );
  }

  Widget _rosterLine() {
    if (!_isSandbox) {
      return const Text('Roster not loaded (non-sandbox target).');
    }
    if (_rosterLoading) return const Text('Loading roster…');
    if (_rosterError != null) {
      return Text('Roster error: $_rosterError',
          style: const TextStyle(color: Colors.red));
    }
    return Text('Roster: ${_roster.length} client(s) loaded.');
  }

  Widget _resultArea() {
    final a = _answer;
    if (a == null) {
      return const Text('No result yet.',
          style: TextStyle(color: Colors.grey));
    }
    final rows = <(String, String)>[
      ('Roundtrip', _lastMs == null ? '—' : '$_lastMs ms'),
      ('Intent', a.intent.name),
      ('Answer kind', a.kind.name),
      ('Client', a.clientName == null
          ? '(none)'
          : '${a.clientName}  [${a.clientId ?? "-"}]'),
      ('Verbatim', a.verbatim.toString()),
      ('Text', a.text ?? '—'),
      ('Slow-path note', a.note ?? '—'),
    ];
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade400),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final (k, v) in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: RichText(
                text: TextSpan(
                  style: const TextStyle(
                      color: Colors.black87, fontSize: 13, height: 1.4),
                  children: [
                    TextSpan(
                      text: '$k: ',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    TextSpan(text: v),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _sampleArea() {
    if (_sampleMs.isEmpty) return const SizedBox.shrink();
    final sorted = [..._sampleMs]..sort();
    final sum = _sampleMs.fold<int>(0, (a, b) => a + b);
    final avg = (sum / _sampleMs.length).round();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('5 warm samples (ms):',
              style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(_sampleMs.join('  ·  '),
              style: const TextStyle(fontFamily: 'monospace')),
          const SizedBox(height: 4),
          Text(
            'min ${sorted.first}  ·  max ${sorted.last}  ·  avg $avg',
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
          ),
        ],
      ),
    );
  }
}
