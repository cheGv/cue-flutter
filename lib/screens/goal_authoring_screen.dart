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
import '../constants/clinical_areas.dart';
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

// Phase 4.0.7.23-completion — kClinicalAreas + clinicalAreaLabel
// extracted to lib/constants/clinical_areas.dart so add_client and
// future screens share one source. See that file for the canonical
// list and ordering rationale.

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

  // Phase 4.0.7.23 — primary clinical area dropdown selection. Replaces
  // the four-lens chip picker (gestalt/analytic/aac/regulation). Read
  // from clients.clinical_area on init; persisted back on change.
  String? _clinicalArea;

  // Phase 4.0.7.23 — legacy clarifying-answers state retained at module
  // default values so the existing /api/generate-goals proxy still
  // receives the four legacy fields it expects. Server-side switchover
  // to consume `clinical_area` is 4.0.7.23a; this state cleanup is
  // 4.0.7.23b. Not surfaced in UI any more.
  // ignore: unused_field
  final String _processorType  = 'unknown';
  // ignore: unused_field
  final bool   _aacPrimary     = false;
  // ignore: unused_field
  final bool   _regulationFirst = false;

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

  // Phase 4.0.7.23c-deploy — v2 contract surface state. Populated by
  // _generatePlan() after a successful response. Drives the three new
  // render states (safeguarding halt, clarifying-question, goals).
  // Three fields are populated for future render surfaces (domain badge,
  // confidence indicator, plan-level priority chip strip) but not read
  // by V1 UI; flagged ignore to keep the analyzer quiet.
  String? _safeguardingFlag;
  String? _clarifyingQuestion;
  String? _childNameUsed;
  String? _familyQuoteHeld;
  // ignore: unused_field
  num?    _domainConfidence;
  // ignore: unused_field
  List<String> _domains = [];
  // ignore: unused_field
  List<Map<String, dynamic>> _priorityChips = [];
  bool _parseFailed = false;
  final TextEditingController _clarifyingResponseController =
      TextEditingController();

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
    _loadClinicalArea();
  }

  /// Phase 4.0.7.23 — pull the client's existing clinical_area to
  /// pre-select the dropdown. New clients (or clients whose row was
  /// migrated without a backfill) have null → dropdown shows the
  /// hint text and the SLP picks before generating.
  Future<void> _loadClinicalArea() async {
    try {
      final row = await _supabase
          .from('clients')
          .select('clinical_area')
          .eq('id', widget.clientId)
          .maybeSingle();
      final v = (row?['clinical_area'] as String?)?.trim();
      if (mounted && v != null && v.isNotEmpty) {
        setState(() => _clinicalArea = v);
      }
    } catch (_) {/* leave null — SLP picks manually */}
  }

  /// Persist a new clinical_area selection to clients. Failure is
  /// non-fatal — the in-memory state still drives the goal-generation
  /// request, and the next save attempt will retry implicitly.
  Future<void> _persistClinicalArea(String code) async {
    try {
      await _supabase
          .from('clients')
          .update({'clinical_area': code})
          .eq('id', widget.clientId);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save clinical area: $e')),
        );
      }
    }
  }

  @override
  void dispose() {
    _hypothesisController.dispose();
    _scrollController.dispose();
    _clarifyingResponseController.dispose();
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

  Future<void> _generatePlan({String? clarifyingResponse}) async {
    // Phase 4.0.7.23c-deploy — clarifyingResponse is the SLP's answer to
    // a prior clarifying question, threaded into the next call. The
    // previous question rides as previous_clarifying_question so the
    // proxy can format the round-trip into the user message.
    final priorQuestion = _clarifyingQuestion;

    setState(() {
      _isGenerating = true;
      _errorMessage = null;
      _plan = null;
      _goals = [];
      _attested = false;
      _loadingMessage = _loadingMessages[0];
      // v2 surface state — clear before each call.
      _safeguardingFlag = null;
      _clarifyingQuestion = null;
      _childNameUsed = null;
      _familyQuoteHeld = null;
      _domainConfidence = null;
      _domains = [];
      _priorityChips = [];
      _parseFailed = false;
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
          // Phase 4.0.7.23 — new fields the server-side 4.0.7.23a will
          // consume. The legacy clarifying_answers block stays in the
          // payload for back-compat until 23a switches over.
          if (_clinicalArea != null) 'clinical_area': _clinicalArea,
          if (_clinicalArea != null)
            'clinical_area_label': clinicalAreaLabel(_clinicalArea),
          'clarifying_answers': {
            'processor_type':   _processorType,
            'aac_primary':      _aacPrimary,
            'regulation_first': _regulationFirst,
          },
          if (_hypothesisController.text.trim().isNotEmpty)
            'clinician_hypothesis': _hypothesisController.text.trim(),
          // Phase 4.0.7.23c-deploy — clarifying-question round-trip
          // fields. Both are optional; proxy threads them into the v2
          // user message when both are present.
          if (clarifyingResponse != null && clarifyingResponse.trim().isNotEmpty)
            'clarifying_response': clarifyingResponse.trim(),
          if (clarifyingResponse != null && priorQuestion != null)
            'previous_clarifying_question': priorQuestion,
        }),
      ).timeout(const Duration(seconds: 90));

      Map<String, dynamic> body;
      try {
        body = jsonDecode(response.body) as Map<String, dynamic>;
      } catch (_) {
        // Non-JSON body — treat as parse failure.
        setState(() {
          _isGenerating = false;
          _parseFailed = true;
        });
        return;
      }

      // Server returns 200 for safeguarding/clarifying-only branches and
      // 201 for happy-path persistence. Anything else is an error.
      if (response.statusCode != 200 && response.statusCode != 201) {
        throw Exception(body['error'] ?? 'Server error ${response.statusCode}');
      }

      // v2 contract parsing — wrapped in try so any malformed shape lands
      // on the soft fallback rather than the red error card.
      try {
        final goalsList = (body['goals'] as List?) ?? [];
        final priorityChipsRaw = (body['priority_chips'] as List?) ?? [];
        final domainsRaw = (body['domain'] as List?) ?? [];

        setState(() {
          _planId = body['plan_id'] as String?;
          _plan = body;
          _goals = List<Map<String, dynamic>>.from(
            goalsList.map((g) => Map<String, dynamic>.from(g as Map)),
          );
          _safeguardingFlag = body['safeguarding_flag'] as String?;
          _clarifyingQuestion = body['clarifying_question'] as String?;
          _childNameUsed = body['child_name_used'] as String?;
          _familyQuoteHeld = body['family_quote_held'] as String?;
          _domainConfidence = body['domain_confidence'] as num?;
          _domains = domainsRaw
              .map((d) => d?.toString() ?? '')
              .where((d) => d.isNotEmpty)
              .toList();
          _priorityChips = priorityChipsRaw
              .map((c) => Map<String, dynamic>.from(c as Map))
              .toList();
          _isGenerating = false;
          // Clear the response field so the next clarifying turn starts fresh.
          _clarifyingResponseController.clear();
        });

        // Fallback trigger — no goals AND no clarifying question AND
        // no safeguarding flag means the response is effectively empty.
        final hasGoals = _goals.isNotEmpty;
        final hasClarifying = (_clarifyingQuestion ?? '').isNotEmpty;
        final hasSafeguarding = (_safeguardingFlag ?? '').isNotEmpty;
        if (!hasGoals && !hasClarifying && !hasSafeguarding) {
          setState(() => _parseFailed = true);
          return;
        }
      } catch (e) {
        debugPrint('[generate-goals] parse failure: $e');
        setState(() {
          _isGenerating = false;
          _parseFailed = true;
        });
        return;
      }

      // Scroll down to show the results
      await Future.delayed(const Duration(milliseconds: 300));
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 600),
          curve: Curves.easeOut,
        );
      }
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
            // Phase 4.0.7.23-completion — pass clinical_area through
            // so the deep editor's CueReasoningPanel auto-prefills
            // its domain chips on first open.
            if (_clinicalArea != null) 'clinical_area': _clinicalArea,
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
            _buildClinicalAreaPicker(),
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

            // Phase 4.0.7.23c-deploy — soft fallback when v2 returns a
            // shape we can't make sense of. Distinct from _errorMessage,
            // which surfaces transport / 4xx errors in the red card.
            if (_parseFailed)
              _buildParseFallbackCard(),

            // Results — branched on v2 return shape:
            //   1. safeguarding_flag set → halt card, suppress goals
            //   2. clarifying_question set + no goals → ask card
            //   3. goals present → reasoning trace + goal cards + attest
            if (_plan != null && !_parseFailed) ...[
              if (_safeguardingFlag != null) ...[
                const SizedBox(height: 8),
                _buildSafeguardingCard(),
                const SizedBox(height: 40),
              ] else if ((_clarifyingQuestion ?? '').isNotEmpty &&
                  _goals.isEmpty) ...[
                const SizedBox(height: 8),
                _buildClarifyingCard(),
                const SizedBox(height: 40),
              ] else if (_goals.isNotEmpty) ...[
                // Phase 4.0.7.23c-deploy — reasoning trace panel only
                // renders when v2 emitted a non-empty trace. v2 typically
                // returns null; v1 plans (legacy) still render the panel.
                if (((_plan?['reasoning_trace'] as String?) ?? '').isNotEmpty) ...[
                  const SizedBox(height: 8),
                  _buildLayerHeader('LAYER 02', 'Reasoning trace'),
                  const SizedBox(height: 14),
                  _buildReasoningTrace(),
                  const SizedBox(height: 32),
                ],

                _buildLayerHeader('LAYER 03', 'Goal draft'),
                const SizedBox(height: 14),
                if ((_childNameUsed ?? '').isNotEmpty ||
                    (_familyQuoteHeld ?? '').isNotEmpty) ...[
                  _buildAnchorLine(),
                  const SizedBox(height: 12),
                ],
                ..._goals
                    .asMap()
                    .entries
                    .map((e) => _buildGoalCard(e.key, e.value)),

                const SizedBox(height: 40),
                _buildAttestationSection(),
                const SizedBox(height: 40),
              ],
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

  /// Phase 4.0.7.23 — primary clinical area dropdown. Replaces the
  /// four-lens chip picker that was authored when Cue was an
  /// autism-and-AAC-only product. The 14 areas mirror the framework
  /// library taxonomy and the clients.clinical_area schema CHECK
  /// constraint. Selection is persisted to the clients row immediately.
  Widget _buildClinicalAreaPicker() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Primary clinical area',
          style: TextStyle(
              fontSize:    11,
              letterSpacing: 0.4,
              color:       _inkGhost,
              fontWeight:  FontWeight.w500),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color:        Colors.white,
            border:       Border.all(color: _line),
            borderRadius: BorderRadius.circular(10),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              isExpanded: true,
              value: _clinicalArea,
              hint: const Text(
                'Pick the area that best frames this client',
                style: TextStyle(
                    fontSize: 13, color: _inkGhost,
                    fontStyle: FontStyle.italic),
              ),
              icon: const Icon(Icons.keyboard_arrow_down_rounded,
                  color: _inkGhost),
              style: const TextStyle(
                  fontSize: 14, color: _ink, height: 1.55),
              dropdownColor: Colors.white,
              borderRadius: BorderRadius.circular(10),
              items: [
                for (final a in kClinicalAreas)
                  DropdownMenuItem<String>(
                    value: a.code,
                    child: Text(a.label),
                  ),
              ],
              onChanged: (code) {
                if (code == null) return;
                setState(() => _clinicalArea = code);
                _persistClinicalArea(code);
              },
            ),
          ),
        ),
      ],
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
                      // Phase 4.0.7.31f — suppress hint while the Deepgram
                      // interim overlay is rendering. Hint paints at 13px,
                      // overlay text paints at 14px → mismatched baselines
                      // produce a visible double-text-stream during the
                      // interim window. Once a final lands and
                      // _interimPreview resets, hint behavior returns to
                      // normal (Flutter clears it on first controller
                      // character). Manual-typing path is unaffected.
                      hintText: _interimPreview.isEmpty
                          ? 'What\'s your current working hypothesis about this child?'
                          : null,
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

    // Phase 4.0.7.23c-deploy — priority_chips_json is denormalized onto
    // every LTG by the proxy (V1 simplification; refactor flagged for
    // 23c-fix1). Tolerant of three on-the-wire shapes: List (Supabase
    // JSONB → List), String (re-encoded JSON), or null/absent.
    final dynamic chipsRaw = goal['priority_chips_json'];
    List<Map<String, dynamic>> chips = [];
    try {
      if (chipsRaw is List) {
        chips = chipsRaw
            .whereType<Map>()
            .map((c) => Map<String, dynamic>.from(c))
            .toList();
      } else if (chipsRaw is String && chipsRaw.isNotEmpty) {
        final parsed = jsonDecode(chipsRaw);
        if (parsed is List) {
          chips = parsed
              .whereType<Map>()
              .map((c) => Map<String, dynamic>.from(c))
              .toList();
        }
      }
    } catch (_) {/* leave chips empty */}

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
                const SizedBox(height: 10),
                // Phase 4.0.7.23c-deploy — render v2's ltg_candidates[].text
                // directly. v1's title/notes synthesis is gone; goal_text
                // is now the single canonical surface for the LTG.
                Text(
                  goal['goal_text'] as String? ?? '',
                  style: const TextStyle(
                      fontFamily: 'SF Pro Display',
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: _ink,
                      height: 1.4),
                ),
              ],
            ),
          ),

          // Phase 4.0.7.23c-deploy — priority chips strip. Visual register
          // matches the evidence tag chip footer: bordered tokens with
          // monospace label. Long-press surfaces the rationale in a
          // SnackBar. Suppressed entirely when chips is empty.
          if (chips.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  const Text('PRIORITY',
                      style: TextStyle(
                          fontSize: 9,
                          letterSpacing: 0.8,
                          fontFamily: 'monospace',
                          color: _inkGhost,
                          fontWeight: FontWeight.w600)),
                  ...chips.map((chip) {
                    final label = (chip['label'] as String?) ?? '';
                    final rationale = (chip['rationale'] as String?) ?? '';
                    return GestureDetector(
                      onLongPress: rationale.isEmpty
                          ? null
                          : () {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(rationale),
                                  backgroundColor: _ink,
                                  behavior: SnackBarBehavior.floating,
                                ),
                              );
                            },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: _tealSoft,
                          border: Border.all(color: _teal),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          label,
                          style: const TextStyle(
                              fontSize: 10,
                              fontFamily: 'monospace',
                              color: _ink),
                        ),
                      ),
                    );
                  }),
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
                        // Phase 4.0.7.23c-deploy — v2's stg_candidates[].text
                        // lands in `specific`. `measurable` is no longer
                        // emitted (mastery captured in mastery_criterion);
                        // empty-string fallback covers v1 rows.
                        child: Text(
                          (sto['specific'] as String?) ?? '',
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

  // Phase 4.0.7.23c-deploy — v2 surface state cards. ───────────────────────

  /// Anchor line shown above the goal cards when v2 surfaced the child's
  /// name and/or the family quote it built the plan around. Render-only
  /// transparency about what v2 grounded on; no SLP labour.
  Widget _buildAnchorLine() {
    final name = _childNameUsed?.trim() ?? '';
    final quote = _familyQuoteHeld?.trim() ?? '';
    final parts = <String>[];
    if (name.isNotEmpty) parts.add(name);
    if (quote.isNotEmpty) parts.add('"$quote"');
    if (parts.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Text(
        'Cue used: ${parts.join(' / ')}',
        style: const TextStyle(
          fontFamily: 'SF Pro Display',
          fontSize: 12,
          fontStyle: FontStyle.italic,
          color: _inkGhost,
          height: 1.5,
        ),
      ),
    );
  }

  /// Safeguarding halt card — v2 returned a safeguarding_flag. The goals
  /// list, reasoning trace, and attestation section are all suppressed.
  /// The SLP can write a clarifying note that re-fires _generatePlan().
  Widget _buildSafeguardingCard() {
    return Container(
      padding: const EdgeInsets.fromLTRB(22, 22, 22, 22),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBF1),
        border: Border.all(color: _amber),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _ArcLogo(),
              const SizedBox(width: 10),
              const Text(
                'A concern worth pausing on',
                style: TextStyle(
                  fontFamily: 'SF Pro Display',
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: _ink,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            _safeguardingFlag ?? '',
            style: const TextStyle(
              fontSize: 15,
              height: 1.6,
              color: _ink,
              fontWeight: FontWeight.w300,
            ),
          ),
          if ((_clarifyingQuestion ?? '').isNotEmpty) ...[
            const SizedBox(height: 18),
            Divider(color: _amber.withValues(alpha: 0.4), height: 1),
            const SizedBox(height: 18),
            Text(
              _clarifyingQuestion!,
              style: const TextStyle(
                fontSize: 14,
                fontStyle: FontStyle.italic,
                color: _inkSoft,
                height: 1.55,
              ),
            ),
            const SizedBox(height: 14),
            _buildClarifyingResponseField(),
            const SizedBox(height: 14),
            _buildContinueButton(),
          ],
        ],
      ),
    );
  }

  /// Clarifying-question card — v2 returned a clarifying_question with no
  /// goals (WHEN UNCERTAIN return shape). Lighter visual register than
  /// safeguarding; same input + Continue affordance.
  Widget _buildClarifyingCard() {
    return Container(
      padding: const EdgeInsets.fromLTRB(22, 22, 22, 22),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: _line),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _ArcLogo(),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _clarifyingQuestion ?? '',
                  style: const TextStyle(
                    fontFamily: 'SF Pro Display',
                    fontSize: 16,
                    fontWeight: FontWeight.w400,
                    color: _ink,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          _buildClarifyingResponseField(),
          const SizedBox(height: 14),
          _buildContinueButton(),
        ],
      ),
    );
  }

  Widget _buildClarifyingResponseField() {
    return TextField(
      controller: _clarifyingResponseController,
      maxLines: 4,
      minLines: 3,
      style: const TextStyle(fontSize: 14, color: _ink, height: 1.5),
      decoration: InputDecoration(
        hintText: 'Your note',
        hintStyle: const TextStyle(color: _inkGhost, fontSize: 14),
        filled: true,
        fillColor: _paper,
        contentPadding: const EdgeInsets.all(14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: _line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: _line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: _teal),
        ),
      ),
    );
  }

  Widget _buildContinueButton() {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: _ink,
          foregroundColor: _paper,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          elevation: 0,
        ),
        onPressed: _isGenerating
            ? null
            : () {
                final answer = _clarifyingResponseController.text.trim();
                if (answer.isEmpty) return;
                _generatePlan(clarifyingResponse: answer);
              },
        child: const Text(
          'Continue',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
        ),
      ),
    );
  }

  /// Soft fallback when v2 returns a shape we can't make sense of —
  /// no goals, no clarifying question, no safeguarding flag. Distinct
  /// from the red _buildErrorCard which surfaces transport / 4xx errors.
  Widget _buildParseFallbackCard() {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 12),
      padding: const EdgeInsets.fromLTRB(22, 22, 22, 22),
      decoration: BoxDecoration(
        color: _paper2,
        border: Border.all(color: _line),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _ArcLogo(),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Cue is having trouble drafting goals right now. '
                  'Try again in a moment, or capture the goals manually.',
                  style: TextStyle(
                    fontFamily: 'SF Pro Display',
                    fontSize: 14,
                    color: _ink,
                    height: 1.55,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _ink,
                    side: const BorderSide(color: _ink),
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: _isGenerating ? null : () => _generatePlan(),
                  child: const Text('Try again'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _ink,
                    foregroundColor: _paper,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                    elevation: 0,
                  ),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => LtgEditScreen(
                          goal: {'client_id': widget.clientId},
                          clientName: widget.clientName,
                          onSaved: (_) {},
                        ),
                      ),
                    );
                  },
                  child: const Text('Capture manually'),
                ),
              ),
            ],
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

// Phase 4.0.7.23 — _ClarifyChip retained as the visual register for
// the four-lens picker that was replaced by the clinical-area
// dropdown. Kept dormant so 4.0.7.23b cleanup has a reference; remove
// when that commit lands.
// ignore: unused_element
class _ClarifyChip extends StatelessWidget {
  final String label;
  final bool selected;
  // ignore: unused_element_parameter
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
