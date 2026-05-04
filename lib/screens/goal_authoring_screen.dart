// lib/screens/goal_authoring_screen.dart
//
// Usage — navigate from client profile:
//   Navigator.push(context, MaterialPageRoute(
//     builder: (_) => GoalAuthoringScreen(
//       clientId: client['id'],
//       clientName: client['name'],
//       sessionCount: client['total_sessions'] ?? 0,
//     ),
//   ));

import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../narrate_web_audio.dart';
import 'ltg_edit_screen.dart';

// ── constants ──────────────────────────────────────────────────────────────────
const String _proxyBase = 'https://cue-ai-proxy.onrender.com';
const Color _ink       = Color(0xFF0E1C36);
const Color _inkSoft   = Color(0xFF2A3754);
const Color _inkGhost  = Color(0xFF6B7690);
const Color _paper     = Color(0xFFFAF6EE);
const Color _paper2    = Color(0xFFF3ECDE);
const Color _teal      = Color(0xFF2A8F84);
const Color _tealSoft  = Color(0xFFD6E8E5);
const Color _amber     = Color(0xFFD68A2B);
const Color _amberSoft = Color(0xFFF4E4C4);
const Color _line      = Color(0xFFE6DDCA);

// ── main screen ───────────────────────────────────────────────────────────────
class GoalAuthoringScreen extends StatefulWidget {
  final String clientId;
  final String clientName;
  final int sessionCount;

  const GoalAuthoringScreen({
    super.key,
    required this.clientId,
    required this.clientName,
    required this.sessionCount,
  });

  @override
  State<GoalAuthoringScreen> createState() => _GoalAuthoringScreenState();
}

class _GoalAuthoringScreenState extends State<GoalAuthoringScreen> {
  final _supabase = Supabase.instance.client;
  final _hypothesisController = TextEditingController();

  /// Phase 4.0.7.17b — current Deepgram partial transcript (replaces on
  /// every is_final=false push, clears on is_final=true / stop / error).
  /// Rendered as ghost-italic suffix layered on top of the textarea.
  /// NOT written into _hypothesisController — the canonical field stays
  /// clean; only finals land in the controller.
  String _interimPreview = '';
  final _scrollController = ScrollController();

  // Clarifying answers
  String _processorType  = 'gestalt';
  bool   _aacPrimary     = false;
  bool   _regulationFirst = true;

  // UI state
  bool   _isGenerating = false;
  String _loadingMessage = 'Reading the chart...';
  String? _errorMessage;

  // Plan data
  Map<String, dynamic>? _plan;
  List<Map<String, dynamic>> _goals = [];
  String? _planId;
  String? _rciNumber;

  // Attestation
  bool _attesting = false;
  bool _attested  = false;

  static const List<String> _loadingMessages = [
    'Reading the chart...',
    'Assessing regulatory profile...',
    'Mapping communicative intent...',
    'Drafting goals...',
    'Checking evidence base...',
    'Almost there...',
  ];

  @override
  void initState() {
    super.initState();
    _fetchRciNumber();
  }

  @override
  void dispose() {
    _hypothesisController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _fetchRciNumber() async {
    final res = await _supabase
        .from('clinic_profile')
        .select('rci_number')
        .eq('id', _supabase.auth.currentUser!.id)
        .maybeSingle();
    if (res != null && mounted) {
      setState(() => _rciNumber = res['rci_number'] as String?);
    }
  }

  Future<void> _generatePlan() async {
    setState(() {
      _isGenerating = true;
      _errorMessage = null;
      _plan = null;
      _goals = [];
      _attested = false;
      _loadingMessage = _loadingMessages[0];
    });

    // Cycle loading messages every 6 seconds
    int msgIdx = 0;
    final msgTimer = Stream.periodic(const Duration(seconds: 6), (i) => i)
        .take(_loadingMessages.length - 1)
        .listen((_) {
      if (!mounted) return;
      msgIdx = (msgIdx + 1).clamp(0, _loadingMessages.length - 1);
      setState(() => _loadingMessage = _loadingMessages[msgIdx]);
    });

    try {
      final token = _supabase.auth.currentSession!.accessToken;
      final response = await http.post(
        Uri.parse('$_proxyBase/api/generate-goals'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'client_id': widget.clientId,
          'clarifying_answers': {
            'processor_type':   _processorType,
            'aac_primary':      _aacPrimary,
            'regulation_first': _regulationFirst,
          },
          if (_hypothesisController.text.trim().isNotEmpty)
            'clinician_hypothesis': _hypothesisController.text.trim(),
        }),
      ).timeout(const Duration(seconds: 90));

      final body = jsonDecode(response.body) as Map<String, dynamic>;

      if (response.statusCode != 201) {
        throw Exception(body['error'] ?? 'Server error ${response.statusCode}');
      }

      setState(() {
        _planId = body['plan_id'] as String;
        _plan   = body;
        print('PLAN KEYS: ${body.keys.toList()}');
        print('TRACE VALUE: ${body['reasoning_trace']}');
        _goals  = List<Map<String, dynamic>>.from(
          (body['goals'] as List).map((g) => Map<String, dynamic>.from(g as Map)),
        );
        _isGenerating = false;
      });

      // Scroll down to show the results
      await Future.delayed(const Duration(milliseconds: 300));
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 600),
        curve: Curves.easeOut,
      );
    } catch (e) {
      setState(() {
        _isGenerating = false;
        _errorMessage = e.toString().replaceAll('Exception: ', '');
      });
    } finally {
      await msgTimer.cancel();
    }
  }

  Future<void> _attestPlan() async {
    if (_planId == null) return;
    final rci = _rciNumber ?? 'RCI-NOT-SET';
    setState(() => _attesting = true);

    try {
      final token = _supabase.auth.currentSession!.accessToken;
      final response = await http.post(
        Uri.parse('$_proxyBase/api/attest-goals'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'plan_id':    _planId,
          'rci_number': rci,
        }),
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode != 201) {
        final body = jsonDecode(response.body);
        throw Exception(body['error'] ?? 'Attestation failed');
      }

      setState(() {
        _attested  = true;
        _attesting = false;
      });

      HapticFeedback.mediumImpact();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Plan signed and activated.'),
            backgroundColor: _teal,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      setState(() => _attesting = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString().replaceAll('Exception: ', '')),
            backgroundColor: Colors.red.shade700,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  void _editGoal(int index) {
    // Phase 4.0.7.20j — inject client_id into the draft goal map
    // because the proxy's /api/generate-goals response doesn't include
    // it on each goal. The new CueReasoningPanel inside LtgEditScreen
    // needs client_id to call the reasoning-respond edge function.
    // Note: ltg_id is intentionally absent here — these are drafts
    // pre-attestation, so the panel will create a thread anchored to
    // the client only and the "Cite in rationale" affordance routes
    // to a SnackBar (see ltg_edit_screen.dart's onCiteInRationale).
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => LtgEditScreen(
          goal: {
            'client_id': widget.clientId,
            ..._goals[index],
          },
          clientName: widget.clientName,
          onSaved: (updatedGoal) {
            if (mounted) {
              setState(() => _goals[index] = updatedGoal);
            }
          },
        ),
      ),
    );
  }

  // ── build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _paper,
      appBar: AppBar(
        backgroundColor: _paper,
        elevation: 0,
        centerTitle: false,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: _ink),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(
          children: [
            _ArcLogo(),
            const SizedBox(width: 8),
            const Text('Cue',
                style: TextStyle(
                    fontFamily: 'SF Pro Display',
                    fontSize: 17,
                    fontWeight: FontWeight.w500,
                    color: _ink)),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Text(
              '${widget.clientName} / Goals',
              style: const TextStyle(fontSize: 11, color: _inkGhost, letterSpacing: 0.5),
            ),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Divider(color: _line, height: 1),
        ),
      ),
      body: SingleChildScrollView(
        controller: _scrollController,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Hero
            _buildHero(),
            const SizedBox(height: 28),

            // Patient card
            _buildPatientCard(),
            const SizedBox(height: 12),

            // Data sources strip
            _buildSourcesStrip(),
            const SizedBox(height: 32),

            // Layer 01 — Clarifying
            _buildLayerHeader('LAYER 01', 'Clinical framing'),
            const SizedBox(height: 14),
            _buildClarifyingChips(),
            const SizedBox(height: 24),

            // Optional hypothesis
            _buildHypothesisField(),
            const SizedBox(height: 28),

            // Generate button
            if (!_isGenerating && _plan == null)
              _buildGenerateButton(),

            // Loading state
            if (_isGenerating)
              _buildLoadingState(),

            // Error
            if (_errorMessage != null)
              _buildErrorCard(),

            // Results
            if (_plan != null) ...[
              const SizedBox(height: 8),
              _buildLayerHeader('LAYER 02', 'Reasoning trace'),
              const SizedBox(height: 14),
              _buildReasoningTrace(),
              const SizedBox(height: 32),

              _buildLayerHeader('LAYER 03', 'Goal draft'),
              const SizedBox(height: 14),
              ..._goals.asMap().entries.map((e) => _buildGoalCard(e.key, e.value)),

              const SizedBox(height: 40),
              _buildAttestationSection(),
              const SizedBox(height: 40),
            ],
          ],
        ),
      ),
    );
  }

  // ── section builders ───────────────────────────────────────────────────────

  Widget _buildHero() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('GOAL AUTHORING — DRAFT',
            style: TextStyle(
                fontSize: 10,
                letterSpacing: 1.6,
                fontWeight: FontWeight.w600,
                color: _teal)),
        const SizedBox(height: 10),
        RichText(
          text: const TextSpan(
            style: TextStyle(
                fontFamily: 'SF Pro Display',
                fontSize: 30,
                fontWeight: FontWeight.w400,
                color: _ink,
                height: 1.1),
            children: [
              TextSpan(text: 'A treatment plan, '),
              TextSpan(
                  text: 'co-authored.',
                  style: TextStyle(
                      fontStyle: FontStyle.italic, color: _teal)),
            ],
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'Cue has read the chart. You make the call.',
          style: TextStyle(
              fontFamily: 'SF Pro Display',
              fontStyle: FontStyle.italic,
              fontSize: 14,
              color: _inkGhost),
        ),
      ],
    );
  }

  Widget _buildPatientCard() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: _paper2,
        border: Border.all(color: _line),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: _ink,
            child: Text(
              widget.clientName.isNotEmpty
                  ? widget.clientName.substring(0, 1).toUpperCase()
                  : '?',
              style: const TextStyle(
                  color: _paper,
                  fontSize: 16,
                  fontFamily: 'SF Pro Display',
                  fontWeight: FontWeight.w500),
            ),
          ),
          const SizedBox(width: 14),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.clientName,
                  style: const TextStyle(
                      fontFamily: 'SF Pro Display',
                      fontSize: 17,
                      fontWeight: FontWeight.w500,
                      color: _ink)),
              const SizedBox(height: 2),
              Text(
                '${widget.sessionCount} session${widget.sessionCount == 1 ? '' : 's'} on record',
                style: const TextStyle(fontSize: 12, color: _inkGhost),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSourcesStrip() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: RichText(
        text: TextSpan(
          style: const TextStyle(
              fontSize: 10,
              letterSpacing: 0.6,
              fontFamily: 'monospace',
              color: _inkGhost),
          children: [
            const TextSpan(
                text: 'DRAWING FROM  ',
                style: TextStyle(
                    color: _ink, fontWeight: FontWeight.w600)),
            TextSpan(text: '${widget.sessionCount} clinical sessions'),
            const TextSpan(
                text: '  +  ',
                style: TextStyle(color: _teal)),
            const TextSpan(text: 'Client profile'),
            const TextSpan(
                text: '  +  ',
                style: TextStyle(color: _teal)),
            const TextSpan(text: 'Active goals'),
          ],
        ),
      ),
    );
  }

  Widget _buildLayerHeader(String num, String title) {
    return Row(
      children: [
        Text(num,
            style: const TextStyle(
                fontSize: 10,
                letterSpacing: 1.6,
                fontFamily: 'monospace',
                color: _inkGhost,
                fontWeight: FontWeight.w500)),
        const SizedBox(width: 12),
        Text(title,
            style: const TextStyle(
                fontFamily: 'SF Pro Display',
                fontSize: 19,
                fontWeight: FontWeight.w500,
                color: _ink)),
        const SizedBox(width: 10),
        Expanded(child: Divider(color: _line, height: 1)),
      ],
    );
  }

  Widget _buildClarifyingChips() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        border: Border.all(color: _line, style: BorderStyle.solid),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          const Text(
            'Primary clinical lens —',
            style: TextStyle(
                fontFamily: 'SF Pro Display',
                fontStyle: FontStyle.italic,
                fontSize: 13,
                color: _inkGhost),
          ),
          _ClarifyChip(
            label: 'Gestalt processor',
            selected: _processorType == 'gestalt',
            onTap: () => setState(() => _processorType =
                _processorType == 'gestalt' ? 'unknown' : 'gestalt'),
          ),
          _ClarifyChip(
            label: 'Analytic processor',
            selected: _processorType == 'analytic',
            onTap: () => setState(() => _processorType =
                _processorType == 'analytic' ? 'unknown' : 'analytic'),
          ),
          _ClarifyChip(
            label: 'AAC primary',
            selected: _aacPrimary,
            onTap: () => setState(() => _aacPrimary = !_aacPrimary),
          ),
          _ClarifyChip(
            label: 'Regulation-first',
            selected: _regulationFirst,
            amber: true,
            onTap: () =>
                setState(() => _regulationFirst = !_regulationFirst),
          ),
        ],
      ),
    );
  }

  Widget _buildHypothesisField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Your clinical hypothesis (optional)',
          style: TextStyle(
              fontSize: 11,
              letterSpacing: 0.4,
              color: _inkGhost,
              fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              // 4.0.7.17b — Stack lets us overlay the ghost-italic
              // interim suffix on top of the TextField without writing
              // it into the controller. Field text goes transparent
              // ONLY while an interim is active; the overlay then
              // renders both the existing committed text and the ghost
              // suffix as one Text.rich. When _interimPreview is empty,
              // the field renders normally — no overlay, no perf cost.
              child: Stack(
                children: [
                  TextField(
                    controller: _hypothesisController,
                    maxLines: 3,
                    style: TextStyle(
                      fontSize: 14,
                      color: _interimPreview.isEmpty
                          ? _ink
                          : Colors.transparent,
                      height: 1.55,
                    ),
                    decoration: InputDecoration(
                      hintText:
                          'What\'s your current working hypothesis about this child?',
                      hintStyle:
                          const TextStyle(fontSize: 13, color: _inkGhost),
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: _line),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide:
                            const BorderSide(color: _teal, width: 1.5),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: _line),
                      ),
                    ),
                  ),
                  if (_interimPreview.isNotEmpty)
                    Positioned.fill(
                      child: IgnorePointer(
                        child: Padding(
                          // Matches Material's outlined-TextField default
                          // content padding (12px each side).
                          padding: const EdgeInsets.fromLTRB(
                              12, 12, 12, 12),
                          child: Text.rich(
                            TextSpan(
                              children: [
                                TextSpan(
                                  text: _hypothesisController.text,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    color: _ink,
                                    height: 1.55,
                                  ),
                                ),
                                TextSpan(
                                  text:
                                      _hypothesisController.text.isEmpty
                                          ? _interimPreview
                                          : ' $_interimPreview',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: _ink.withValues(alpha: 0.5),
                                    fontStyle: FontStyle.italic,
                                    height: 1.55,
                                  ),
                                ),
                              ],
                            ),
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            _MicButton(
              onTranscribed: (text) {
                setState(() {
                  final existing = _hypothesisController.text.trim();
                  _hypothesisController.text =
                      existing.isEmpty ? text : '$existing $text';
                  // Final landed and got committed to the controller —
                  // drop the ghost suffix so the SLP sees a clean field.
                  _interimPreview = '';
                });
              },
              onInterim: (text) {
                setState(() => _interimPreview = text);
              },
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildGenerateButton() {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: _ink,
          foregroundColor: _paper,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          elevation: 0,
        ),
        onPressed: _generatePlan,
        child: const Text(
          'Generate goal plan  →',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
        ),
      ),
    );
  }

  Widget _buildLoadingState() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 36),
      child: Column(
        children: [
          const SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(_teal),
            ),
          ),
          const SizedBox(height: 18),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 400),
            child: Text(
              _loadingMessage,
              key: ValueKey(_loadingMessage),
              style: const TextStyle(
                  fontFamily: 'SF Pro Display',
                  fontStyle: FontStyle.italic,
                  fontSize: 14,
                  color: _inkGhost),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'This takes 20–40 seconds. The chart is being read in full.',
            style: TextStyle(fontSize: 11, color: _inkGhost),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildErrorCard() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF0F0),
        border: Border.all(color: Colors.red.shade200),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Something went wrong',
              style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: Color(0xFFC0392B),
                  fontSize: 14)),
          const SizedBox(height: 6),
          Text(_errorMessage ?? '',
              style: const TextStyle(fontSize: 13, color: _inkSoft)),
          const SizedBox(height: 14),
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: _ink,
              backgroundColor: _paper2,
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6)),
            ),
            onPressed: _generatePlan,
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  Widget _buildReasoningTrace() {
    final trace = _plan?['reasoning_trace'] as String? ?? '';
    final sources = (_plan?['data_sources'] as List?)?.cast<String>() ?? [];
    final confidence = _plan?['router_confidence'] as String? ?? 'high';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(
          left: BorderSide(color: Color(0xFF2A8F84), width: 3),
          top: BorderSide(color: Color(0xFFE6DDCA)),
          right: BorderSide(color: Color(0xFFE6DDCA)),
          bottom: BorderSide(color: Color(0xFFE6DDCA)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (confidence == 'low')
            Container(
              margin: const EdgeInsets.only(bottom: 14),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFFF4E4C4),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Text(
                '⚠ Limited confidence — insufficient data for full plan. Review carefully.',
                style: TextStyle(fontSize: 12, color: Color(0xFFD68A2B)),
              ),
            ),
          Text(
            trace.isEmpty ? 'Reasoning trace not available.' : trace,
            style: const TextStyle(
              fontSize: 15,
              height: 1.65,
              color: Color(0xFF0E1C36),
              fontWeight: FontWeight.w300,
            ),
          ),
          const SizedBox(height: 16),
          const Divider(color: Color(0xFFE6DDCA), height: 1),
          const SizedBox(height: 12),
          Row(
            children: [
              Text(
                'From ${sources.length} source${sources.length == 1 ? '' : 's'}',
                style: const TextStyle(
                  fontSize: 10,
                  letterSpacing: 0.6,
                  fontFamily: 'monospace',
                  color: Color(0xFF6B7690),
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: () => _showSourcesSheet(sources),
                child: const Text(
                  'Show sources ↗',
                  style: TextStyle(
                    fontSize: 11,
                    color: Color(0xFF2A8F84),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildGoalCard(int index, Map<String, dynamic> goal) {
    final stos = (goal['short_term_goals'] as List?)
            ?.map((s) => Map<String, dynamic>.from(s as Map))
            .toList() ??
        [];
    final tags = (goal['goal_evidence_tags'] as List?)
            ?.map((t) => Map<String, dynamic>.from(t as Map))
            .toList() ??
        (goal['evidence_tags'] as List?)
            ?.map((t) => Map<String, dynamic>.from(t as Map))
            .toList() ??
        [];
    final isEdited = goal['is_edited'] == true;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFDF7),
        border: Border.all(color: _line),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Goal header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'LTG ${index + 1}  —  ${(goal['domain'] as String? ?? '').toUpperCase()}',
                      style: const TextStyle(
                          fontSize: 10,
                          letterSpacing: 0.8,
                          fontFamily: 'monospace',
                          color: _teal,
                          fontWeight: FontWeight.w600),
                    ),
                    const Spacer(),
                    if (isEdited)
                      Container(
                        margin: const EdgeInsets.only(right: 8),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: _amberSoft,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text('edited',
                            style: TextStyle(
                                fontSize: 9,
                                color: _amber,
                                fontWeight: FontWeight.w600)),
                      ),
                    GestureDetector(
                      onTap: _attested ? null : () => _editGoal(index),
                      child: Text(
                        _attested ? '' : '✎ edit',
                        style: const TextStyle(
                            fontSize: 11,
                            color: _inkGhost,
                            fontFamily: 'monospace',
                            letterSpacing: 0.3),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  goal['notes'] as String? ??
                      goal['title'] as String? ?? '',
                  style: const TextStyle(
                      fontFamily: 'SF Pro Display',
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: _ink,
                      height: 1.3),
                ),
                const SizedBox(height: 8),
                Text(
                  goal['goal_text'] as String? ?? '',
                  style: const TextStyle(
                      fontSize: 13,
                      color: _inkSoft,
                      height: 1.55),
                ),
              ],
            ),
          ),

          Divider(color: _line.withOpacity(0.5), height: 1),

          // STOs
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
            child: Column(
              children: stos.asMap().entries.map((e) {
                final i = e.key;
                final sto = e.value;
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 28,
                        child: Text(
                          '${index + 1}.${i + 1}',
                          style: const TextStyle(
                              fontSize: 10,
                              fontFamily: 'monospace',
                              color: _teal,
                              fontWeight: FontWeight.w600),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          '${sto['specific'] ?? ''} — ${sto['measurable'] ?? ''}',
                          style: const TextStyle(
                              fontSize: 13,
                              color: _inkSoft,
                              height: 1.5),
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),

          // Evidence tags footer
          if (tags.isNotEmpty)
            Container(
              padding:
                  const EdgeInsets.fromLTRB(16, 10, 16, 12),
              decoration: BoxDecoration(
                color: _paper2,
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(10),
                  bottomRight: Radius.circular(10),
                ),
              ),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  const Text('EV',
                      style: TextStyle(
                          fontSize: 9,
                          letterSpacing: 0.8,
                          fontFamily: 'monospace',
                          color: _inkGhost,
                          fontWeight: FontWeight.w600)),
                  ...tags.map((tag) => Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          border: Border.all(color: _line),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          tag['framework_name'] as String? ?? '',
                          style: const TextStyle(
                              fontSize: 10,
                              fontFamily: 'monospace',
                              color: _inkSoft),
                        ),
                      )),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildAttestationSection() {
    if (_attested) {
      return Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: const Color(0xFFE8F5E9),
          border: Border.all(color: const Color(0xFF81C784)),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            const Icon(Icons.check_circle_outline,
                color: Color(0xFF388E3C), size: 28),
            const SizedBox(width: 14),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Text('Plan signed and activated.',
                    style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF2E7D32),
                        fontSize: 15)),
                SizedBox(height: 2),
                Text('This plan is now the active treatment record.',
                    style: TextStyle(
                        fontSize: 12, color: Color(0xFF388E3C))),
              ],
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(22, 24, 22, 24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFFFFBF1), _amberSoft],
        ),
        border: Border.all(color: _amber),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'CLINICAL ATTESTATION',
            style: TextStyle(
                fontSize: 10,
                letterSpacing: 1.6,
                fontFamily: 'monospace',
                color: _amber,
                fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          const Text(
            'I have clinically reviewed and approved these goals. '
            'I take professional responsibility for this treatment plan, '
            'and acknowledge that Cue served as an authoring assistant, '
            'not a clinical decision-maker.',
            style: TextStyle(
                fontFamily: 'SF Pro Display',
                fontStyle: FontStyle.italic,
                fontSize: 14,
                color: _ink,
                height: 1.6,
                fontWeight: FontWeight.w300),
          ),
          const SizedBox(height: 20),
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Divider(color: _ink),
                const SizedBox(height: 4),
                Text(
                  'RCI ${_rciNumber ?? 'Not set'}  ·  ${_today()}',
                  style: const TextStyle(fontSize: 12, color: _inkGhost, letterSpacing: 0.3),
                ),
              ],
            ),
          ),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: _ink,
                foregroundColor: _paper,
                padding: const EdgeInsets.symmetric(vertical: 15),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
                elevation: 0,
              ),
              onPressed: _attesting ? null : _attestPlan,
              child: _attesting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor:
                              AlwaysStoppedAnimation<Color>(_paper)))
                  : const Text(
                      'Sign & Activate Plan  →',
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  // ── helpers ────────────────────────────────────────────────────────────────

  String _today() {
    final now = DateTime.now();
    const months = [
      'Jan','Feb','Mar','Apr','May','Jun',
      'Jul','Aug','Sep','Oct','Nov','Dec'
    ];
    return '${now.day} ${months[now.month - 1]} ${now.year}';
  }

  void _showSourcesSheet(List<String> sources) {
    showModalBottomSheet(
      context: context,
      backgroundColor: _paper,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Sources used',
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: _ink)),
            const SizedBox(height: 16),
            ...sources.map((s) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    children: [
                      const Icon(Icons.check, size: 14, color: _teal),
                      const SizedBox(width: 10),
                      Expanded(
                          child: Text(s,
                              style: const TextStyle(
                                  fontSize: 13, color: _inkSoft))),
                    ],
                  ),
                )),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

// ── small widgets ─────────────────────────────────────────────────────────────

class _ArcLogo extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 18,
      height: 18,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: _teal, width: 2),
      ),
      // Simple arc approximation using a clipped circle
      child: ClipOval(
        child: Container(
          decoration: const BoxDecoration(
            gradient: SweepGradient(
              colors: [_teal, Colors.transparent],
              stops: [0.65, 0.65],
            ),
          ),
        ),
      ),
    );
  }
}

class _ClarifyChip extends StatelessWidget {
  final String label;
  final bool selected;
  final bool amber;
  final VoidCallback onTap;

  const _ClarifyChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.amber = false,
  });

  @override
  Widget build(BuildContext context) {
    final bg     = selected ? (amber ? _amberSoft : _tealSoft) : Colors.white;
    final border = selected ? (amber ? _amber : _teal)         : _line;
    final dot    = amber ? _amber : _teal;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: bg,
          border: Border.all(color: border),
          borderRadius: BorderRadius.circular(99),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (selected) ...[
              Container(
                width: 5,
                height: 5,
                decoration:
                    BoxDecoration(color: dot, shape: BoxShape.circle),
              ),
              const SizedBox(width: 6),
            ],
            Text(label,
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: selected ? _ink : _inkGhost)),
          ],
        ),
      ),
    );
  }
}

/// Phase 4.0.7.17 — rewired to the same Deepgram WebSocket pipeline that
/// narrate_session_screen.dart uses. The legacy Web Speech API path
/// (`window.startSpeechRecognition` / `stopSpeechRecognition`) is gone —
/// those JS functions don't ship with the Netlify build, so the prior
/// implementation never produced a transcript. Now we open a WS to the
/// proxy with `language_mode` set from the SLP's profile, capture audio
/// via MediaRecorder, accumulate is_final chunks into a buffer, and
/// fire `onTranscribed` once with the joined text on stop.
///
/// Mic-leak hardening from 4.0.7.9j is preserved here:
///   - `_released` flag is set FIRST in any teardown path so any
///     in-flight `dataavailable` callbacks short-circuit.
///   - `_onWebSocketDone` releases media handles on unexpected close.
///   - 30-second auto-stop covers SLPs forgetting the mic is hot.
class _MicButton extends StatefulWidget {
  final ValueChanged<String> onTranscribed;
  /// Phase 4.0.7.17b — fired on every Deepgram is_final=false chunk
  /// while the user is speaking. Optional; backwards-compatible. The
  /// emitted text is the proxy's current partial guess and replaces
  /// (not appends to) any prior interim. Caller is expected to keep
  /// it as a separate visual preview, NOT to write it into the
  /// canonical text controller.
  final ValueChanged<String>? onInterim;
  const _MicButton({required this.onTranscribed, this.onInterim});
  @override
  State<_MicButton> createState() => _MicButtonState();
}

class _MicButtonState extends State<_MicButton> {
  static const _wsUrlBase = 'wss://cue-ai-proxy.onrender.com/transcribe';
  static const _autoStop  = Duration(seconds: 30);

  bool _isListening = false;
  bool _released    = false;

  WebSocketChannel? _channel;
  MediaRecorder?    _recorder;
  MediaStream?      _mediaStream;
  Timer?            _autoStopTimer;

  /// Accumulated final transcript chunks for the current recording. Joined
  /// with single spaces and fired through `widget.onTranscribed` once on
  /// stop, so the parent textarea sees one append per mic session.
  final StringBuffer _final = StringBuffer();

  /// Cached after first fetch. Defaults to 'en' on miss/failure to match
  /// the proxy's safer fallback.
  String? _languageMode;

  @override
  void initState() {
    super.initState();
    _ensureLanguageMode();
  }

  @override
  void dispose() {
    _release();
    super.dispose();
  }

  Future<void> _ensureLanguageMode() async {
    if (_languageMode != null) return;
    try {
      final uid = Supabase.instance.client.auth.currentUser?.id;
      if (uid == null) {
        _languageMode = 'en';
        return;
      }
      final row = await Supabase.instance.client
          .from('slp_profiles')
          .select('transcription_language_mode')
          .eq('clinician_id', uid)
          .maybeSingle();
      final v = row?['transcription_language_mode'] as String?;
      _languageMode = (v != null && v.isNotEmpty) ? v : 'en';
    } catch (_) {
      _languageMode = 'en';
    }
  }

  void _toggle() {
    if (_isListening) {
      _stop(fromError: false);
    } else {
      _start();
    }
  }

  Future<void> _start() async {
    await _ensureLanguageMode();
    final lang = _languageMode ?? 'en';

    setState(() {
      _isListening = true;
      _released    = false;
      _final.clear();
    });

    try {
      // Open WS to proxy. No session_id, no keywords (4.0.7.18 work).
      final wsUrl =
          '$_wsUrlBase?language_mode=${Uri.encodeQueryComponent(lang)}';
      _channel = WebSocketChannel.connect(Uri.parse(wsUrl));
      _channel!.stream.listen(
        _onMessage,
        onError: _onWebSocketError,
        onDone:  _onWebSocketDone,
      );

      // Mic — same constraints as the narrator screen. Mono 16k matches
      // Deepgram's expected input.
      final constraints = <String, dynamic>{
        'audio': {
          'channelCount':     1,
          'sampleRate':       16000,
          'echoCancellation': true,
          'noiseSuppression': true,
        },
      }.jsify();
      final stream =
          (await getUserMedia(constraints!).toDart) as MediaStream?;
      if (stream == null) {
        throw StateError('getUserMedia returned null');
      }

      final options  = <String, dynamic>{}.jsify();
      final recorder = MediaRecorder(stream, options!);

      recorder.onDataAvailable = (BlobEvent event) {
        if (_released) return;
        final blob = event.data as Blob;
        final reader = FileReader();
        reader.onLoadEnd = (JSAny _) {
          if (_released) return;
          final buffer = (reader.result as JSArrayBuffer).toDart;
          final bytes  = Uint8List.view(buffer);
          if (_channel != null && _isListening && bytes.isNotEmpty) {
            try {
              _channel!.sink.add(bytes);
            } catch (_) {/* socket dying — ignored, _onWebSocketDone handles */}
          }
        }.toJS;
        reader.readAsArrayBuffer(blob);
      }.toJS;

      recorder.start(250);
      _recorder    = recorder;
      _mediaStream = stream;

      // Auto-stop watchdog — protects against an SLP forgetting the mic
      // is hot during goal authoring.
      _autoStopTimer = Timer(_autoStop, () {
        if (_isListening) _stop(fromError: false);
      });
    } catch (e) {
      _release();
      if (mounted) {
        setState(() => _isListening = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Couldn't transcribe — please try again."),
          ),
        );
      }
    }
  }

  /// Release every media + socket handle. Idempotent. Sets `_released`
  /// FIRST so any in-flight `dataavailable` / `FileReader.onLoadEnd`
  /// callbacks short-circuit on the next microtask — same gate pattern
  /// as `narrate_session_screen.dart` post-4.0.7.9j.
  void _release() {
    if (_released) return;
    _released = true;

    _autoStopTimer?.cancel();
    _autoStopTimer = null;

    try {
      final r = _recorder;
      if (r != null && r.state != 'inactive') r.stop();
    } catch (_) {}
    _recorder = null;

    try {
      final s = _mediaStream;
      if (s != null) {
        for (final t in s.getTracks().toDart) {
          try { t.stop(); } catch (_) {}
        }
      }
    } catch (_) {}
    _mediaStream = null;

    try { _channel?.sink.close(); } catch (_) {}
    _channel = null;
  }

  void _stop({required bool fromError}) {
    final text = _final.toString().trim();
    _release();
    if (mounted) {
      setState(() => _isListening = false);
    }
    // 4.0.7.17b — clear any lingering interim preview when the
    // recording terminates, regardless of error or success path. The
    // parent uses this signal to drop the ghost-italic suffix in the
    // textarea overlay.
    widget.onInterim?.call('');
    if (!fromError && text.isNotEmpty) {
      widget.onTranscribed(text);
    }
  }

  void _onMessage(dynamic message) {
    Map<String, dynamic>? data;
    try {
      data = jsonDecode(message as String) as Map<String, dynamic>;
    } catch (_) {
      return;
    }
    final type = data['type'];
    if (type == 'transcript') {
      final text = (data['text'] as String?)?.trim() ?? '';
      final isFinal = data['is_final'] == true;
      if (isFinal) {
        if (text.isNotEmpty) {
          if (_final.isNotEmpty) _final.write(' ');
          _final.write(text);
        }
        // 4.0.7.17b — a final landed; drop the interim preview so the
        // ghost suffix doesn't double-render alongside the just-
        // committed final on the next interim push.
        widget.onInterim?.call('');
      } else {
        // 4.0.7.17b — partial transcript. Each push REPLACES the
        // current preview (Deepgram's interims are cumulative for the
        // current utterance, not delta).
        widget.onInterim?.call(text);
      }
    } else if (type == 'error') {
      _stop(fromError: true);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Couldn't transcribe — please try again."),
          ),
        );
      }
    }
  }

  void _onWebSocketError(dynamic _) {
    if (!_isListening) return;
    _stop(fromError: true);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Couldn't transcribe — please try again."),
        ),
      );
    }
  }

  void _onWebSocketDone() {
    // Unexpected close while we still hold media handles → release for
    // privacy, fire whatever transcript we accumulated. Mirrors the
    // 4.0.7.9j pattern from narrate_session_screen.dart.
    if (!_released && (_recorder != null || _mediaStream != null)) {
      _stop(fromError: false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _toggle,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: _isListening ? const Color(0xFF2A8F84) : const Color(0xFFF3ECDE),
          border: Border.all(
            color: _isListening ? const Color(0xFF2A8F84) : const Color(0xFFE6DDCA),
            width: 1.5,
          ),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(
          _isListening ? Icons.mic : Icons.mic_none,
          color: _isListening ? Colors.white : const Color(0xFF6B7690),
          size: 22,
        ),
      ),
    );
  }
}
