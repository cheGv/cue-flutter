// lib/screens/ltg_edit_screen.dart
//
// Full-screen structured editor for a Long-Term Goal.
// Includes all five Cue Study interaction modes (Mode 5 is a TODO — see report_screen.dart).

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

// ── design tokens ─────────────────────────────────────────────────────────────
const Color _ink        = Color(0xFF0E1C36);
const Color _inkSoft    = Color(0xFF2A3754);
const Color _ghost      = Color(0xFF6B7690);
const Color _paper      = Color(0xFFFAF6EE);
const Color _teal       = Color(0xFF2A8F84);
const Color _signalTeal = Color(0xFF14B8A6);
const Color _tealFill   = Color(0xFFF0FDF9);
const Color _tealFill2  = Color(0xFFE6FAF5);
const Color _navyDark   = Color(0xFF0A1A2F);
const Color _line       = Color(0xFFE6DDCA);
const Color _red        = Color(0xFFDC2626);

const String _proxyBase = 'https://cue-ai-proxy.onrender.com';

const List<String> _timelineOptions = [
  '4 weeks', '6 weeks', '8 weeks', '12 weeks', '16 weeks', '24 weeks', 'custom',
];

/// Cue Study Mode 5 system prompt.
/// Entry point lives in report_screen.dart (post-session observation panel).
/// Exported at module level so report_screen.dart can import it directly.
const String kCsProgressPrompt =
    "You are Cue Study, the clinical reasoning companion inside Cue. "
    "The SLP has described a session observation. Help her interpret it through an evidence-based lens. "
    "Respond in 3 short paragraphs: "
    "Para 1: what the observation likely reflects developmentally or neurologically — name the mechanism. "
    "Para 2: what it suggests about where the child is in their trajectory — is this consolidation, "
    "generalization, emergence, or plateau? "
    "Para 3: one question for the SLP to hold going into next session — start with "
    "'Something to notice next session:'. "
    "Rules: use the child's name. Never evaluate the SLP's technique. Never say 'you should'. "
    "Neurodiversity-affirming throughout. Plain text only. 80-110 words.";

// ── screen ────────────────────────────────────────────────────────────────────

class LtgEditScreen extends StatefulWidget {
  final Map<String, dynamic> goal;
  final String clientName;
  final void Function(Map<String, dynamic> updatedGoal) onSaved;

  const LtgEditScreen({
    super.key,
    required this.goal,
    required this.clientName,
    required this.onSaved,
  });

  @override
  State<LtgEditScreen> createState() => _LtgEditScreenState();
}

class _LtgEditScreenState extends State<LtgEditScreen> {
  final _supabase = Supabase.instance.client;

  // ── Cue Study system prompts (Modes 1–5) ─────────────────────────────────

  static const String _csFrameworkPrompt =
      "You are Cue Study, the clinical reasoning companion inside Cue — India's first Clinical OS for SLPs. "
      "You are a loyal, well-read intern: you have absorbed the evidence base deeply, but you never supervise, "
      "never prescribe, never override the clinician's judgment. You support her thinking. "
      "When given a therapeutic framework and a written goal, explain in exactly 3 short paragraphs: "
      "Para 1: What this framework proposes — one or two sentences, in precise but accessible clinical language. "
      "Para 2: Why this framework directly justifies this specific goal — connect the framework's core mechanism "
      "to what the goal is targeting. Be specific to the goal text provided. Never give a generic answer. "
      "Para 3: One concrete implication for session design — start with 'One thing to consider:'. "
      "Tone: warm, precise, never condescending. Length: 80-100 words. Plain paragraphs only. No bullets. No headers. No markdown.";

  static const String _csStuckPrompt =
      "You are Cue Study, the clinical reasoning companion inside Cue. "
      "The SLP has described a rough therapy direction in plain language. "
      "Translate her clinical intuition into 2-3 evidence-grounded goal directions she can choose from. "
      "For each: write one complete measurable LTG in participation-based format: "
      "'[Name] will [functional skill] [participation context] [evidence of mastery], within [timeframe].' "
      "Follow with one sentence explaining the evidence base. "
      "Tag with 1-2 relevant frameworks from: Polyvagal Theory (Porges), SCERTS Model, PROMPT, "
      "Core Vocabulary Approach, Participation Model (Beukelman & Mirenda), "
      "Interoception Curriculum (Kelly Mahler), Aided Language Stimulation, "
      "Dynamic Systems Theory, OPT Level 1. "
      "Rules: use the child's name, never 'the child'. "
      "Goals must be neurodiversity-affirming — frame around participation, never deficits or compliance. "
      "Never use 'appropriate' or 'normal'. "
      "If too vague, ask one clarifying question. "
      "Number each direction. Plain text only.";

  static const String _csCritiquePrompt =
      "You are Cue Study, the clinical reasoning companion inside Cue. "
      "Review the written goal across four dimensions in 4 short bullets: "
      "Measurability: is the evidence of mastery specific and observable? "
      "Participation frame: does the goal target a functional skill in a real context or a drill? "
      "Neurodiversity alignment: does the goal frame strengths and participation or deficits and compliance? "
      "Feasibility: is the timeline and criterion realistic for this diagnosis/profile? "
      "End with one sentence: either 'This goal is clinically sound.' or 'Consider revisiting [specific dimension].' "
      "Tone: honest, collegial, specific. Never vague praise. Never harsh criticism. Plain text only.";

  static const String _csSessionPrompt =
      "You are Cue Study, the clinical reasoning companion inside Cue. "
      "Given a goal and client name, respond in exactly 2 paragraphs: "
      "Para 1: the clinical mechanism this goal is targeting — what is actually happening neurologically "
      "or developmentally when this skill is practiced. "
      "Para 2: three specific practical session strategies that directly serve this goal. "
      "Each strategy in one sentence starting with a verb. "
      "Rules: use the child's name. Never suggest strategies requiring compliance or correction. "
      "Strategies must be embeddable in naturalistic or semi-structured activity. "
      "Never say 'reward' — say 'communicative payoff'. "
      "Format: 2 paragraphs. Plain text only. 80-100 words.";

  // Mode 5 (_csProgressPrompt / kCsProgressPrompt) — see top-level const above.
  // UI entry point belongs in report_screen.dart, not here.

  // ── form controllers ──────────────────────────────────────────────────────

  late final TextEditingController _actionCtrl;
  late final TextEditingController _conditionCtrl;
  late final TextEditingController _criterionCtrl;
  late final TextEditingController _customTimelineCtrl;

  String? _timeline;
  bool _dirty        = false;
  bool _saving       = false;
  bool _previewPulse = false;

  // Validation
  bool _actionError    = false;
  bool _criterionError = false;
  bool _timelineError  = false;

  // Cue Study — Mode 1: Framework chips
  List<Map<String, dynamic>> _tags = [];
  String? _openTagName;
  bool    _tagLoading = false;
  String? _tagText;
  String? _tagError;

  // Cue Study — Mode 3: Review this goal
  bool    _reviewLoading = false;
  String? _reviewText;
  String? _reviewError;

  // Cue Study — Mode 4: Session strategies
  bool    _sessionLoading = false;
  String? _sessionText;
  String? _sessionError;

  // ── lifecycle ─────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();

    // Debug: surface which evidence tag key the goal map actually uses
    // ignore: avoid_print
    print('[LtgEditScreen] goal keys: ${widget.goal.keys.toList()}');
    // ignore: avoid_print
    print('[LtgEditScreen] goal_evidence_tags: ${widget.goal['goal_evidence_tags']}');
    // ignore: avoid_print
    print('[LtgEditScreen] evidence_tags: ${widget.goal['evidence_tags']}');
    // ignore: avoid_print
    print('[LtgEditScreen] ev_tags: ${widget.goal['ev_tags']}');

    _tags = _parseTags(widget.goal);
    // ignore: avoid_print
    print('[LtgEditScreen] parsed ${_tags.length} tags: $_tags');

    final parsed = _parseGoalText(widget.goal['goal_text'] as String? ?? '');

    _actionCtrl         = TextEditingController(text: parsed['action']);
    _conditionCtrl      = TextEditingController(text: parsed['condition']);
    _criterionCtrl      = TextEditingController(text: parsed['criterion']);
    _customTimelineCtrl = TextEditingController();

    final extracted = (parsed['timeline'] ?? '').trim();
    if (_timelineOptions.contains(extracted)) {
      _timeline = extracted;
    } else if (extracted.isNotEmpty) {
      _timeline = 'custom';
      _customTimelineCtrl.text = extracted;
    }

    for (final c in [_actionCtrl, _conditionCtrl, _criterionCtrl, _customTimelineCtrl]) {
      c.addListener(_onFieldChanged);
    }
  }

  @override
  void dispose() {
    _actionCtrl.dispose();
    _conditionCtrl.dispose();
    _criterionCtrl.dispose();
    _customTimelineCtrl.dispose();
    super.dispose();
  }

  void _onFieldChanged() => setState(() {
    _dirty        = true;
    _previewPulse = !_previewPulse;
  });

  bool get _hasContent =>
      _actionCtrl.text.trim().isNotEmpty ||
      _conditionCtrl.text.trim().isNotEmpty ||
      _criterionCtrl.text.trim().isNotEmpty;

  // ── parsing ───────────────────────────────────────────────────────────────

  /// Tries 'goal_evidence_tags' first, then 'evidence_tags', then 'ev_tags'.
  static List<Map<String, dynamic>> _parseTags(Map<String, dynamic> goal) {
    final raw =
        (goal['goal_evidence_tags'] as List?) ??
        (goal['evidence_tags']      as List?) ??
        (goal['ev_tags']            as List?) ??
        [];
    return raw.map((t) => Map<String, dynamic>.from(t as Map)).toList();
  }

  static Map<String, String> _parseGoalText(String text) {
    final result = <String, String>{
      'action': '', 'condition': '', 'criterion': '', 'timeline': '',
    };
    if (text.trim().isEmpty) return result;

    try {
      var remaining = text.trim();

      final willIdx = remaining.indexOf(' will ');
      if (willIdx >= 0) remaining = remaining.substring(willIdx + 6).trim();

      final timelineRe = RegExp(
        r',?\s*within\s+([\w\s]+?(?:weeks?|months?))\s*\.?\s*$',
        caseSensitive: false,
      );
      final tMatch = timelineRe.firstMatch(remaining);
      if (tMatch != null) {
        result['timeline'] = tMatch.group(1)!.trim();
        remaining = remaining.substring(0, tMatch.start).trim();
      }

      final condRe = RegExp(r'\b(in\s|across\s|during\s|when\s)', caseSensitive: false);
      final cMatch = condRe.firstMatch(remaining);

      if (cMatch != null) {
        result['action'] = remaining.substring(0, cMatch.start).trim();
        final afterCond  = remaining.substring(cMatch.start).trim();

        final critRe = RegExp(
          r'(?:with\s+)?\d+\s*(?:%|out\s+of|\/|trials?|opportunities?)',
          caseSensitive: false,
        );
        final critMatch = critRe.firstMatch(afterCond);
        if (critMatch != null) {
          result['condition'] = afterCond
              .substring(0, critMatch.start)
              .trim()
              .replaceAll(RegExp(r',\s*$'), '');
          result['criterion'] = afterCond.substring(critMatch.start).trim();
        } else {
          result['condition'] = afterCond;
        }
      } else {
        result['action'] = remaining;
      }
    } catch (_) {
      result['action'] = text;
    }

    return result;
  }

  // ── assembly ──────────────────────────────────────────────────────────────

  String _assembled() {
    final action    = _actionCtrl.text.trim();
    final condition = _conditionCtrl.text.trim();
    final criterion = _criterionCtrl.text.trim();
    final timeline  = _timeline == 'custom'
        ? _customTimelineCtrl.text.trim()
        : (_timeline ?? '');

    final parts = <String>[
      '${widget.clientName} will',
      if (action.isNotEmpty)    action,
      if (condition.isNotEmpty) condition,
      if (criterion.isNotEmpty) criterion,
    ];
    final base = parts.join(' ');
    return timeline.isNotEmpty ? '$base, within $timeline.' : '$base.';
  }

  // ── target date ───────────────────────────────────────────────────────────

  String? _targetDateLabel() {
    final tl = _timeline == 'custom'
        ? _customTimelineCtrl.text.trim()
        : (_timeline ?? '');
    if (tl.isEmpty || tl == 'custom') return null;

    final weeksMatch  = RegExp(r'(\d+)\s*weeks?',  caseSensitive: false).firstMatch(tl);
    final monthsMatch = RegExp(r'(\d+)\s*months?', caseSensitive: false).firstMatch(tl);

    DateTime? target;
    if (weeksMatch != null) {
      final weeks = int.tryParse(weeksMatch.group(1)!) ?? 0;
      target = DateTime.now().add(Duration(days: weeks * 7));
    } else if (monthsMatch != null) {
      final months = int.tryParse(monthsMatch.group(1)!) ?? 0;
      final now = DateTime.now();
      target = DateTime(now.year, now.month + months, now.day);
    }
    if (target == null) return null;

    const monthNames = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return 'Target: ${target.day} ${monthNames[target.month - 1]} ${target.year}';
  }

  // ── validation & save ─────────────────────────────────────────────────────

  bool _validate() {
    final action    = _actionCtrl.text.trim();
    final criterion = _criterionCtrl.text.trim();
    final timeline  = _timeline == 'custom'
        ? _customTimelineCtrl.text.trim()
        : _timeline;

    setState(() {
      _actionError    = action.isEmpty;
      _criterionError = criterion.isEmpty;
      _timelineError  = (timeline == null || timeline.isEmpty);
    });
    return !_actionError && !_criterionError && !_timelineError;
  }

  Future<void> _save() async {
    if (!_validate()) return;
    setState(() => _saving = true);

    final goalText = _assembled();
    final id = widget.goal['id'] as String?;
    if (id != null && id.isNotEmpty) {
      try {
        await _supabase
            .from('long_term_goals')
            .update({'goal_text': goalText})
            .eq('id', id);
      } catch (_) {}
    }

    if (mounted) {
      widget.onSaved({...widget.goal, 'goal_text': goalText, 'is_edited': true});
      Navigator.pop(context);
    }
  }

  // ── Cue Study shared API helper ───────────────────────────────────────────

  Future<String?> _callCueStudy({
    required String systemPrompt,
    required String userMessage,
  }) async {
    final response = await http.post(
      Uri.parse('$_proxyBase/pre-session-brief'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'model': 'claude-opus-4-5',
        'system': systemPrompt,
        'user_message': userMessage,
      }),
    ).timeout(const Duration(seconds: 30));

    if (response.statusCode != 200) throw Exception('HTTP ${response.statusCode}');

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return data['content']?[0]?['text'] as String? ?? '';
  }

  // ── Cue Study — Mode 1: Framework chip tap ────────────────────────────────

  Future<void> _fetchTagExplanation(String tagName) async {
    // Toggle off if already open
    if (_openTagName == tagName) {
      setState(() { _openTagName = null; _tagText = null; _tagError = null; });
      return;
    }
    setState(() {
      _openTagName = tagName;
      _tagLoading  = true;
      _tagText     = null;
      _tagError    = null;
    });

    try {
      final text = await _callCueStudy(
        systemPrompt: _csFrameworkPrompt,
        userMessage: 'Framework: $tagName\nGoal: ${_assembled()}',
      );
      if (mounted) { setState(() { _tagText = text; _tagLoading = false; }); }
    } catch (_) {
      if (mounted) {
        setState(() {
          _tagError   = 'Cue Study is unavailable. Try again.';
          _tagLoading = false;
        });
      }
    }
  }

  // ── Cue Study — Mode 3: Review this goal ─────────────────────────────────

  Future<void> _fetchReview() async {
    setState(() { _reviewLoading = true; _reviewText = null; _reviewError = null; });
    try {
      final text = await _callCueStudy(
        systemPrompt: _csCritiquePrompt,
        userMessage: 'Goal: ${_assembled()}',
      );
      if (mounted) { setState(() { _reviewText = text; _reviewLoading = false; }); }
    } catch (_) {
      if (mounted) {
        setState(() {
          _reviewError   = 'Cue Study is unavailable. Try again.';
          _reviewLoading = false;
        });
      }
    }
  }

  // ── Cue Study — Mode 4: Session strategies ────────────────────────────────

  Future<void> _fetchSession() async {
    setState(() { _sessionLoading = true; _sessionText = null; _sessionError = null; });
    try {
      final text = await _callCueStudy(
        systemPrompt: _csSessionPrompt,
        userMessage: 'Client name: ${widget.clientName}\nGoal: ${_assembled()}',
      );
      if (mounted) { setState(() { _sessionText = text; _sessionLoading = false; }); }
    } catch (_) {
      if (mounted) {
        setState(() {
          _sessionError   = 'Cue Study is unavailable. Try again.';
          _sessionLoading = false;
        });
      }
    }
  }

  // ── Cue Study — Mode 2: I'm stuck — bottom sheet ─────────────────────────

  void _showStuckSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _StuckSheet(
        clientName: widget.clientName,
        systemPrompt: _csStuckPrompt,
        proxyBase: _proxyBase,
      ),
    );
  }

  // ── sub-widgets ───────────────────────────────────────────────────────────

  Widget _sectionLabel(String label) => Text(
        label,
        style: GoogleFonts.dmSans(
          fontSize: 11, fontWeight: FontWeight.w600,
          color: _ghost, letterSpacing: 0.6,
        ),
      );

  Widget _textField({
    required String label,
    required TextEditingController ctrl,
    required String hint,
    bool multiline = true,
    bool hasError  = false,
  }) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionLabel(label),
          const SizedBox(height: 6),
          TextField(
            controller: ctrl,
            maxLines: multiline ? null : 1,
            minLines: multiline ? 2 : 1,
            style: GoogleFonts.dmSans(fontSize: 14, color: _ink, height: 1.5),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: GoogleFonts.dmSans(fontSize: 14, color: _ghost.withValues(alpha: 0.55)),
              filled: true,
              fillColor: Colors.white,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: hasError ? _red : _line),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: hasError ? _red : _line),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: hasError ? _red : _teal, width: 1.5),
              ),
            ),
          ),
          if (hasError) ...[
            const SizedBox(height: 4),
            Text('Required', style: GoogleFonts.dmSans(fontSize: 11, color: _red)),
          ],
        ],
      );

  Widget _timelineField() {
    final targetLabel = _targetDateLabel();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel('GOAL PERIOD'),
        const SizedBox(height: 6),
        DropdownButtonFormField<String>(
          initialValue: _timeline,
          hint: Text(
            'Select a period',
            style: GoogleFonts.dmSans(fontSize: 14, color: _ghost.withValues(alpha: 0.55)),
          ),
          style: GoogleFonts.dmSans(fontSize: 14, color: _ink),
          decoration: InputDecoration(
            filled: true,
            fillColor: Colors.white,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: _timelineError ? _red : _line),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: _timelineError ? _red : _line),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: _timelineError ? _red : _teal, width: 1.5),
            ),
          ),
          items: _timelineOptions
              .map((o) => DropdownMenuItem(
                    value: o,
                    child: Text(o, style: GoogleFonts.dmSans(fontSize: 14)),
                  ))
              .toList(),
          onChanged: (v) => setState(() {
            _timeline      = v;
            _dirty         = true;
            _timelineError = false;
          }),
        ),
        if (_timelineError) ...[
          const SizedBox(height: 4),
          Text('Required', style: GoogleFonts.dmSans(fontSize: 11, color: _red)),
        ],
        if (targetLabel != null) ...[
          const SizedBox(height: 6),
          Text(targetLabel, style: GoogleFonts.dmSans(fontSize: 11, color: _ghost)),
        ],
        if (_timeline == 'custom') ...[
          const SizedBox(height: 10),
          _textField(
            label: 'CUSTOM PERIOD',
            ctrl: _customTimelineCtrl,
            hint: 'e.g. 10 weeks',
            multiline: false,
            hasError: _timelineError,
          ),
        ],
      ],
    );
  }

  Widget _previewCard() {
    final hasContent = _hasContent;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'GOAL AS WRITTEN',
              style: GoogleFonts.dmSans(
                fontSize: 10, fontWeight: FontWeight.w600,
                color: _ghost, letterSpacing: 0.8,
              ),
            ),
            if (hasContent) ...[
              const SizedBox(width: 8),
              Text(
                'Updating as you write',
                style: GoogleFonts.dmSans(
                  fontSize: 11, color: _signalTeal,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Container(
            decoration: BoxDecoration(border: Border.all(color: _line)),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(width: 2, color: _teal),
                  Expanded(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 400),
                      curve: Curves.easeInOut,
                      color: _previewPulse ? _tealFill2 : _tealFill,
                      padding: const EdgeInsets.all(14),
                      child: Text(
                        _assembled(),
                        style: GoogleFonts.dmSans(fontSize: 13, color: _ink, height: 1.65),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// Generic Cue Study response card — shared by all four in-screen modes.
  Widget _csCard({
    required String modeName,
    required bool loading,
    String? text,
    String? error,
  }) {
    return Container(
      decoration: const BoxDecoration(
        color: _navyDark,
        borderRadius: BorderRadius.all(Radius.circular(10)),
        border: Border(bottom: BorderSide(color: _signalTeal, width: 2)),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'CUE STUDY',
            style: GoogleFonts.dmSans(
              fontSize: 10, fontWeight: FontWeight.w600,
              color: _signalTeal, letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            modeName,
            style: GoogleFonts.dmSans(
              fontSize: 12,
              color: Colors.white.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: 12),
          if (loading)
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: CircularProgressIndicator(strokeWidth: 2, color: _signalTeal),
              ),
            )
          else if (error != null)
            Text(error, style: GoogleFonts.dmSans(fontSize: 12, color: _red))
          else if (text != null && text.isNotEmpty)
            Text(
              text,
              style: GoogleFonts.dmSans(fontSize: 13, color: Colors.white, height: 1.6),
            ),
        ],
      ),
    );
  }

  /// Text button styled in Signal Teal with underline.
  Widget _csTextButton({required String label, required VoidCallback? onPressed}) {
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: _signalTeal,
        padding: EdgeInsets.zero,
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: Text(
        label,
        style: GoogleFonts.dmSans(
          fontSize: 13,
          color: onPressed != null ? _signalTeal : _signalTeal.withValues(alpha: 0.4),
          decoration: TextDecoration.underline,
          decorationColor: onPressed != null ? _signalTeal : _signalTeal.withValues(alpha: 0.4),
        ),
      ),
    );
  }

  Widget _cueStudySection() {
    final tagCardVisible     = _openTagName != null;
    final reviewCardVisible  = _reviewLoading  || _reviewText  != null || _reviewError  != null;
    final sessionCardVisible = _sessionLoading || _sessionText != null || _sessionError != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Section header
        Text(
          'CUE STUDY',
          style: GoogleFonts.dmSans(
            fontSize: 10, fontWeight: FontWeight.w600,
            color: _ghost, letterSpacing: 0.8,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Explore the evidence behind this goal, get direction when stuck, '
          'or translate it into session strategies.',
          style: GoogleFonts.dmSans(fontSize: 12, color: _ghost, height: 1.4),
        ),

        // ── Mode 1: Framework chips (only when tags exist)
        if (_tags.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(
            'Tap a framework to understand why it grounds this goal.',
            style: GoogleFonts.dmSans(fontSize: 12, color: _ghost, height: 1.4),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _tags.map((tag) {
              final name   = tag['framework_name'] as String? ?? '';
              final isOpen = _openTagName == name;
              return GestureDetector(
                onTap: () => _fetchTagExplanation(name),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: isOpen ? _teal : Colors.white,
                    border: Border.all(color: isOpen ? _teal : _line),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    name,
                    style: GoogleFonts.dmSans(
                      fontSize: 12, fontWeight: FontWeight.w500,
                      color: isOpen ? Colors.white : _inkSoft,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          // AnimatedSize so the card expands smoothly below the chips
          AnimatedSize(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
            alignment: Alignment.topCenter,
            child: tagCardVisible
                ? Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: _csCard(
                      modeName: _openTagName ?? '',
                      loading: _tagLoading,
                      text: _tagText,
                      error: _tagError,
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ],

        // ── Divider
        const SizedBox(height: 16),
        Container(height: 1, color: _line),
        const SizedBox(height: 16),

        // ── Mode 2: I'm stuck on this goal
        SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            onPressed: _showStuckSheet,
            style: OutlinedButton.styleFrom(
              foregroundColor: _teal,
              side: const BorderSide(color: _teal),
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: Text(
              "I'm stuck on this goal",
              style: GoogleFonts.dmSans(fontSize: 14, fontWeight: FontWeight.w500, color: _teal),
            ),
          ),
        ),
        const SizedBox(height: 16),

        // ── Mode 3: Review this goal
        _csTextButton(
          label: 'Review this goal',
          onPressed: _reviewLoading ? null : _fetchReview,
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
          alignment: Alignment.topCenter,
          child: reviewCardVisible
              ? Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: _csCard(
                    modeName: 'Review this goal',
                    loading: _reviewLoading,
                    text: _reviewText,
                    error: _reviewError,
                  ),
                )
              : const SizedBox.shrink(),
        ),
        const SizedBox(height: 12),

        // ── Mode 4: What does this mean for my session?
        _csTextButton(
          label: 'What does this mean for my session?',
          onPressed: _sessionLoading ? null : _fetchSession,
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
          alignment: Alignment.topCenter,
          child: sessionCardVisible
              ? Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: _csCard(
                    modeName: 'Session strategies',
                    loading: _sessionLoading,
                    text: _sessionText,
                    error: _sessionError,
                  ),
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }

  // ── build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final saveEnabled = _dirty && !_saving;

    return Scaffold(
      backgroundColor: _paper,
      appBar: AppBar(
        backgroundColor: _paper,
        elevation: 0,
        automaticallyImplyLeading: false,
        leading: TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('Cancel', style: GoogleFonts.dmSans(fontSize: 14, color: _ghost)),
        ),
        leadingWidth: 80,
        title: Text(
          'Edit Goal',
          style: GoogleFonts.dmSans(fontSize: 16, fontWeight: FontWeight.w600, color: _ink),
        ),
        centerTitle: true,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: TextButton(
              onPressed: saveEnabled ? _save : null,
              style: TextButton.styleFrom(
                backgroundColor: saveEnabled ? _teal : _teal.withValues(alpha: 0.3),
                foregroundColor: Colors.white,
                disabledForegroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: _saving
                  ? const SizedBox(
                      width: 16, height: 16,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                    )
                  : Text('Save', style: GoogleFonts.dmSans(fontSize: 14, fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 60),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _textField(
                label: 'FUNCTIONAL SKILL TARGET',
                ctrl: _actionCtrl,
                hint: 'What will the child do?',
                hasError: _actionError,
              ),
              const SizedBox(height: 16),

              _textField(
                label: 'PARTICIPATION CONTEXT',
                ctrl: _conditionCtrl,
                hint: 'In what context or setting?',
              ),
              const SizedBox(height: 16),

              _textField(
                label: 'EVIDENCE OF MASTERY',
                ctrl: _criterionCtrl,
                hint: 'How will success be measured? (e.g. 80% across 3 sessions)',
                hasError: _criterionError,
              ),
              const SizedBox(height: 16),

              _timelineField(),
              const SizedBox(height: 28),

              _previewCard(),
              const SizedBox(height: 28),

              _cueStudySection(),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Mode 2: "I'm stuck" bottom sheet ─────────────────────────────────────────

class _StuckSheet extends StatefulWidget {
  final String clientName;
  final String systemPrompt;
  final String proxyBase;

  const _StuckSheet({
    required this.clientName,
    required this.systemPrompt,
    required this.proxyBase,
  });

  @override
  State<_StuckSheet> createState() => _StuckSheetState();
}

class _StuckSheetState extends State<_StuckSheet> {
  final _ctrl = TextEditingController();
  bool    _loading = false;
  String? _text;
  String? _error;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final input = _ctrl.text.trim();
    if (input.isEmpty) { return; }
    setState(() { _loading = true; _text = null; _error = null; });

    try {
      final response = await http.post(
        Uri.parse('${widget.proxyBase}/pre-session-brief'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'model': 'claude-opus-4-5',
          'system': widget.systemPrompt,
          'user_message':
              'Client name: ${widget.clientName}\nTherapy direction: $input',
        }),
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode != 200) throw Exception('HTTP ${response.statusCode}');

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final text = data['content']?[0]?['text'] as String? ?? '';
      if (mounted) { setState(() { _text = text; _loading = false; }); }
    } catch (_) {
      if (mounted) {
        setState(() {
          _error   = 'Cue Study is unavailable. Try again.';
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final keyboardInset = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      decoration: const BoxDecoration(
        color: _paper,
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + keyboardInset),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Drag handle
            Center(
              child: Container(
                width: 40, height: 4,
                decoration: BoxDecoration(
                  color: _line, borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),

            Text(
              'Think with Cue',
              style: GoogleFonts.dmSans(
                fontSize: 18, fontWeight: FontWeight.w600, color: _ink,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Describe your clinical intuition — Cue will translate it into goal directions.',
              style: GoogleFonts.dmSans(fontSize: 13, color: _ghost, height: 1.4),
            ),
            const SizedBox(height: 16),

            // Free-text input
            TextField(
              controller: _ctrl,
              maxLines: 4,
              style: GoogleFonts.dmSans(fontSize: 14, color: _ink, height: 1.5),
              decoration: InputDecoration(
                hintText:
                    'Describe what you want to work on with ${widget.clientName}...',
                hintStyle: GoogleFonts.dmSans(
                  fontSize: 14, color: _ghost.withValues(alpha: 0.55),
                ),
                filled: true,
                fillColor: Colors.white,
                contentPadding: const EdgeInsets.all(12),
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
                  borderSide: const BorderSide(color: _teal, width: 1.5),
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Submit button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _loading ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _teal,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: _teal.withValues(alpha: 0.4),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  elevation: 0,
                ),
                child: _loading
                    ? const SizedBox(
                        width: 18, height: 18,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                      )
                    : Text(
                        'Think with Cue →',
                        style: GoogleFonts.dmSans(
                          fontSize: 14, fontWeight: FontWeight.w600,
                        ),
                      ),
              ),
            ),

            // Response card — animates in below the button
            AnimatedSize(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOut,
              alignment: Alignment.topCenter,
              child: (_loading || _text != null || _error != null)
                  ? Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: Container(
                        decoration: const BoxDecoration(
                          color: _navyDark,
                          borderRadius: BorderRadius.all(Radius.circular(10)),
                          border: Border(
                            bottom: BorderSide(color: _signalTeal, width: 2),
                          ),
                        ),
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'CUE STUDY',
                              style: GoogleFonts.dmSans(
                                fontSize: 10, fontWeight: FontWeight.w600,
                                color: _signalTeal, letterSpacing: 1.2,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Goal directions',
                              style: GoogleFonts.dmSans(
                                fontSize: 12,
                                color: Colors.white.withValues(alpha: 0.6),
                              ),
                            ),
                            const SizedBox(height: 12),
                            if (_loading)
                              Center(
                                child: CircularProgressIndicator(
                                  strokeWidth: 2, color: _signalTeal,
                                ),
                              )
                            else if (_error != null)
                              Text(
                                _error!,
                                style: GoogleFonts.dmSans(fontSize: 12, color: _red),
                              )
                            else if (_text != null && _text!.isNotEmpty)
                              Text(
                                _text!,
                                style: GoogleFonts.dmSans(
                                  fontSize: 13, color: Colors.white, height: 1.6,
                                ),
                              ),
                          ],
                        ),
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
