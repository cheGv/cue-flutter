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

import 'dart:convert';
import 'dart:js' as js;
import 'dart:js_interop';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

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
    final goal = _goals[index];
    final controller = TextEditingController(text: goal['goal_text'] as String? ?? '');

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: _paper,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 24, right: 24, top: 24,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Edit LTG ${index + 1}',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: _ink)),
            const SizedBox(height: 4),
            Text('Changes are saved locally until you attest.',
                style: TextStyle(fontSize: 12, color: _inkGhost)),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              maxLines: 6,
              style: const TextStyle(fontSize: 14, color: _ink, height: 1.55),
              decoration: InputDecoration(
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: _line),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: _teal, width: 1.5),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancel', style: TextStyle(color: _inkGhost)),
                ),
                const Spacer(),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _ink,
                    foregroundColor: _paper,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  ),
                  onPressed: () {
                    setState(() {
                      _goals[index] = {
                        ..._goals[index],
                        'goal_text': controller.text.trim(),
                        'is_edited': true,
                      };
                    });
                    Navigator.pop(ctx);
                  },
                  child: const Text('Save edit'),
                ),
              ],
            ),
          ],
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
                    fontFamily: 'Georgia',
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
                fontFamily: 'Georgia',
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
              fontFamily: 'Georgia',
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
                  fontFamily: 'Georgia',
                  fontWeight: FontWeight.w500),
            ),
          ),
          const SizedBox(width: 14),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.clientName,
                  style: const TextStyle(
                      fontFamily: 'Georgia',
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
                fontFamily: 'Georgia',
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
                fontFamily: 'Georgia',
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
              child: TextField(
                controller: _hypothesisController,
                maxLines: 3,
                style: const TextStyle(
                    fontSize: 14, color: _ink, height: 1.55),
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
            ),
            const SizedBox(width: 10),
            _MicButton(onTranscribed: (text) {
              setState(() {
                final existing = _hypothesisController.text.trim();
                _hypothesisController.text =
                    existing.isEmpty ? text : '$existing $text';
              });
            }),
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
                  fontFamily: 'Georgia',
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
                      fontFamily: 'Georgia',
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
                fontFamily: 'Georgia',
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

class _MicButton extends StatefulWidget {
  final ValueChanged<String> onTranscribed;
  const _MicButton({required this.onTranscribed});
  @override
  State<_MicButton> createState() => _MicButtonState();
}

class _MicButtonState extends State<_MicButton> {
  bool _isListening = false;

  void _toggle() {
    if (_isListening) {
      js.context.callMethod('stopSpeechRecognition', []);
      setState(() => _isListening = false);
      return;
    }
    setState(() => _isListening = true);
    js.context.callMethod('startSpeechRecognition', [
      ((JSString jsTranscript) {
        widget.onTranscribed(jsTranscript.toDart);
        if (mounted) setState(() => _isListening = false);
      }).toJS,
      (() {
        if (mounted) setState(() => _isListening = false);
      }).toJS,
    ]);
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
