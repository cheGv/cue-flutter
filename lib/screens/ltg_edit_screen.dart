// lib/screens/ltg_edit_screen.dart
//
// Full-screen structured editor for a Long-Term Goal.
// Includes all five Cue Study interaction modes (Mode 5 is a TODO — see report_screen.dart).

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:speech_to_text/speech_to_text.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../widgets/cue_reasoning_panel.dart';
import '../widgets/cue_study_icon.dart';
import '../widgets/goal_achieved_overlay.dart';

// ── design tokens ─────────────────────────────────────────────────────────────
const Color _ink        = Color(0xFF0E1C36);
const Color _ghost      = Color(0xFF6B7690);
const Color _paper      = Color(0xFFFAF6EE);
const Color _teal       = Color(0xFF2A8F84);
const Color _signalTeal = Color(0xFF14B8A6);
const Color _tealFill   = Color(0xFFF0FDF9);
const Color _tealFill2  = Color(0xFFE6FAF5);
const Color _navyDark   = Color(0xFF0A1A2F);
const Color _line       = Color(0xFFE6DDCA);
const Color _red        = Color(0xFFDC2626);

// ── Cue Study amber tokens — own the AI panel, teal owns the form ─────────────
const Color _csAmber     = Color(0xFFF59E0B); // label, outlined text
const Color _csAmberDark = Color(0xFFD97706); // filled button bg, borders, mic

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
    "Neurodiversity-affirming throughout. Plain text only. 80-110 words. "
    "Output plain text only. No asterisks, no dashes, no bullet points, no bold, no headers, no markdown of any kind.";

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

class _LtgEditScreenState extends State<LtgEditScreen>
    with TickerProviderStateMixin {
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
      "Tone: warm, precise, never condescending. Length: 80-100 words. Plain paragraphs only. No bullets. No headers. No markdown. "
      "Output plain text only. No asterisks, no dashes, no bullet points, no bold, no headers, no markdown of any kind. "
      "Never mention Claude, Anthropic, or any underlying AI technology. "
      "You are Cue Study — a clinical reasoning companion built into Cue, India's first Clinical OS for SLPs. That is your complete identity in this context. "
      "Never introduce yourself. Never explain what you are or how you work. Just think alongside the SLP. "
      "If asked who built you or what technology powers you, say only: 'I'm Cue Study — part of the Cue platform. What are you working through clinically?' "
      "Never start a response with 'I'm built on' or 'As an AI' or any variation.\n\n"
      "Anti-hallucination rules — follow without exception: "
      "Never cite specific statistics, percentages, or numerical research findings "
      "unless you are certain they are accurate. If uncertain, say 'research suggests' "
      "or 'evidence indicates' without numbers. "
      "Never fabricate paper titles, author names, or journal citations. "
      "If you want to reference research, name the framework or approach only, not a specific paper. "
      "Never make specific predictions about a child's progress timeline or outcome. "
      "When you don't know something, say so directly: "
      "'I don't have enough information to answer that confidently' — "
      "then ask the SLP a clarifying question. "
      "Express appropriate uncertainty with phrases like 'one possibility is', "
      "'it may be worth considering', 'this could suggest' — "
      "never state clinical interpretations as facts.";

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
      "Number each direction. Plain text only. "
      "Output plain text only. No asterisks, no dashes, no bullet points, no bold, no headers, no markdown of any kind. "
      "Never mention Claude, Anthropic, or any underlying AI technology. "
      "You are Cue Study — a clinical reasoning companion built into Cue, India's first Clinical OS for SLPs. That is your complete identity in this context. "
      "Never introduce yourself. Never explain what you are or how you work. Just think alongside the SLP. "
      "If asked who built you or what technology powers you, say only: 'I'm Cue Study — part of the Cue platform. What are you working through clinically?' "
      "Never start a response with 'I'm built on' or 'As an AI' or any variation.\n\n"
      "Anti-hallucination rules — follow without exception: "
      "Never cite specific statistics, percentages, or numerical research findings "
      "unless you are certain they are accurate. If uncertain, say 'research suggests' "
      "or 'evidence indicates' without numbers. "
      "Never fabricate paper titles, author names, or journal citations. "
      "If you want to reference research, name the framework or approach only, not a specific paper. "
      "Never make specific predictions about a child's progress timeline or outcome. "
      "When you don't know something, say so directly: "
      "'I don't have enough information to answer that confidently' — "
      "then ask the SLP a clarifying question. "
      "Express appropriate uncertainty with phrases like 'one possibility is', "
      "'it may be worth considering', 'this could suggest' — "
      "never state clinical interpretations as facts.";

  static const String _csCritiquePrompt =
      "You are Cue Study, the clinical reasoning companion inside Cue. "
      "Review the written goal across four dimensions in 4 short bullets: "
      "Measurability: is the evidence of mastery specific and observable? "
      "Participation frame: does the goal target a functional skill in a real context or a drill? "
      "Neurodiversity alignment: does the goal frame strengths and participation or deficits and compliance? "
      "Feasibility: is the timeline and criterion realistic for this diagnosis/profile? "
      "End with one sentence: either 'This goal is clinically sound.' or 'Consider revisiting [specific dimension].' "
      "Tone: honest, collegial, specific. Never vague praise. Never harsh criticism. Plain text only. "
      "Output plain text only. No asterisks, no dashes, no bullet points, no bold, no headers, no markdown of any kind. "
      "Never mention Claude, Anthropic, or any underlying AI technology. "
      "You are Cue Study — a clinical reasoning companion built into Cue, India's first Clinical OS for SLPs. That is your complete identity in this context. "
      "Never introduce yourself. Never explain what you are or how you work. Just think alongside the SLP. "
      "If asked who built you or what technology powers you, say only: 'I'm Cue Study — part of the Cue platform. What are you working through clinically?' "
      "Never start a response with 'I'm built on' or 'As an AI' or any variation.\n\n"
      "Anti-hallucination rules — follow without exception: "
      "Never cite specific statistics, percentages, or numerical research findings "
      "unless you are certain they are accurate. If uncertain, say 'research suggests' "
      "or 'evidence indicates' without numbers. "
      "Never fabricate paper titles, author names, or journal citations. "
      "If you want to reference research, name the framework or approach only, not a specific paper. "
      "Never make specific predictions about a child's progress timeline or outcome. "
      "When you don't know something, say so directly: "
      "'I don't have enough information to answer that confidently' — "
      "then ask the SLP a clarifying question. "
      "Express appropriate uncertainty with phrases like 'one possibility is', "
      "'it may be worth considering', 'this could suggest' — "
      "never state clinical interpretations as facts.";

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
      "Format: 2 paragraphs. Plain text only. 80-100 words. "
      "Output plain text only. No asterisks, no dashes, no bullet points, no bold, no headers, no markdown of any kind. "
      "Never mention Claude, Anthropic, or any underlying AI technology. "
      "You are Cue Study — a clinical reasoning companion built into Cue, India's first Clinical OS for SLPs. That is your complete identity in this context. "
      "Never introduce yourself. Never explain what you are or how you work. Just think alongside the SLP. "
      "If asked who built you or what technology powers you, say only: 'I'm Cue Study — part of the Cue platform. What are you working through clinically?' "
      "Never start a response with 'I'm built on' or 'As an AI' or any variation.\n\n"
      "Anti-hallucination rules — follow without exception: "
      "Never cite specific statistics, percentages, or numerical research findings "
      "unless you are certain they are accurate. If uncertain, say 'research suggests' "
      "or 'evidence indicates' without numbers. "
      "Never fabricate paper titles, author names, or journal citations. "
      "If you want to reference research, name the framework or approach only, not a specific paper. "
      "Never make specific predictions about a child's progress timeline or outcome. "
      "When you don't know something, say so directly: "
      "'I don't have enough information to answer that confidently' — "
      "then ask the SLP a clarifying question. "
      "Express appropriate uncertainty with phrases like 'one possibility is', "
      "'it may be worth considering', 'this could suggest' — "
      "never state clinical interpretations as facts.";

  // Multilingual suffix — appended to _csFrameworkPrompt for the voice narrator only.
  static const String _csMultilingualSuffix =
      'The SLP may speak in any Indian language including '
      'Hindi, Telugu, Tamil, Kannada, Malayalam, Marathi, '
      'Bengali, or English. Understand input in any of these '
      'languages. Always respond in English only, as clinical '
      'documentation is in English.';

  // Mode 5 (_csProgressPrompt / kCsProgressPrompt) — see top-level const above.
  // UI entry point belongs in report_screen.dart, not here.

  // ── form controllers ──────────────────────────────────────────────────────

  late final TextEditingController _actionCtrl;
  late final TextEditingController _conditionCtrl;
  late final TextEditingController _criterionCtrl;
  late final TextEditingController _customTimelineCtrl;

  /// Phase 4.0.7.20e — buffered rationale from CueReasoningPanel's
  /// "Cite in rationale" action, written into long_term_goals on the
  /// next save when the goal row has no id at the moment of citation.
  /// In practice this screen is always opened with a saved LTG (the
  /// kebab on the chart's goal card pushes it), so this stays null
  /// most of the time. Defensive — covers the new-goal flow if the
  /// editor is ever reused for a creation path.
  String? _pendingEvidenceRationale;

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

  // Cue Study — Mode 0: Passive auto-insight (fires on open, silent fail)
  String _passiveInsight = '';
  bool   _passiveLoading = true;
  bool   _insightVisible = false;
  late final AnimationController _pulseController;
  late final Animation<double>   _pulseAnim;
  late final AnimationController _orbitController;

  // Cue Study — Voice narrator (multilingual mic in CUE STUDY header)
  final SpeechToText _narratorSpeech   = SpeechToText();
  bool   _narratorSpeechAvailable      = false;
  bool   _narratorRecording            = false; // SLP intends to record (drives web auto-restart)
  bool   _narratorListening            = false; // mic is actively capturing right now
  String _narratorText                 = '';    // accumulated transcript
  String _narratorPrevText             = '';    // snapshot before each listen segment
  bool   _narratorLoading              = false;
  String? _narratorError;
  String _narratorResponse             = '';

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

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.4, end: 1.0).animate(_pulseController);

    _orbitController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3000),
    )..repeat();

    // Fire passive insight immediately — silent fail, no loading indicator on error
    _fetchPassiveInsight();

    // Init narrator mic (non-blocking — updates _narratorSpeechAvailable)
    _initNarratorSpeech();

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
    _pulseController.dispose();
    _orbitController.dispose();
    _narratorSpeech.stop();
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
        // Phase 4.0.7.20e — fold any pending evidence_rationale buffered
        // from the CueReasoningPanel's "Cite in rationale" action.
        final updates = <String, dynamic>{'goal_text': goalText};
        if (_pendingEvidenceRationale != null &&
            _pendingEvidenceRationale!.isNotEmpty) {
          updates['evidence_rationale'] = _pendingEvidenceRationale;
        }
        await _supabase
            .from('long_term_goals')
            .update(updates)
            .eq('id', id);
        _pendingEvidenceRationale = null;
      } catch (_) {}
    }

    if (mounted) {
      widget.onSaved({...widget.goal, 'goal_text': goalText, 'is_edited': true});
      Navigator.pop(context);
    }
  }

  // ── Mark achieved button widget ─────────────────────────────────────────
  Widget _markAchievedButton() {
    return SizedBox(
      width: double.infinity,
      child: FilledButton(
        onPressed: _markGoalAchieved,
        style: FilledButton.styleFrom(
          backgroundColor: _teal.withValues(alpha: 0.12),
          foregroundColor: _teal,
          minimumSize: const Size(0, 52),
          textStyle: GoogleFonts.dmSans(
              fontSize: 14, fontWeight: FontWeight.w600),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10)),
          elevation: 0,
        ),
        child: const Text('Mark goal achieved'),
      ),
    );
  }

  // ── Mark achieved (Phase 2) ─────────────────────────────────────────────
  // Confirm → UPDATE status='achieved' → fire 3s celebrating overlay → pop
  // back to chart with the updated goal so the inline CelebratingGoalCard
  // takes over.
  Future<void> _markGoalAchieved() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Mark this goal as achieved?'),
        content: const Text(
            'This action stays on the timeline.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Mark achieved'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final id = widget.goal['id'] as String?;
    if (id == null || id.isEmpty) return;

    final updatedAt = DateTime.now().toUtc().toIso8601String();
    try {
      await _supabase
          .from('long_term_goals')
          .update({'status': 'achieved', 'updated_at': updatedAt})
          .eq('id', id);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not mark achieved: $e')),
        );
      }
      return;
    }

    if (!mounted) return;
    final updatedGoal = {
      ...widget.goal,
      'status':     'achieved',
      'updated_at': updatedAt,
    };

    // Fire the 3s overlay; it auto-dismisses via Navigator.maybePop.
    await showDialog<void>(
      context: context,
      barrierColor: Colors.black54,
      builder: (_) => GoalAchievedOverlay(goal: updatedGoal),
    );

    if (!mounted) return;
    widget.onSaved(updatedGoal);
    Navigator.pop(context);
  }

  // ── Cue Study — Mode 0: Passive auto-insight ─────────────────────────────

  Future<void> _fetchPassiveInsight() async {
    final frameworks = _tags
        .map((t) => t['framework_name'] as String? ?? '')
        .where((n) => n.isNotEmpty)
        .join(', ');
    try {
      final text = await _callCueStudy(
        systemPrompt: _csFrameworkPrompt,
        userMessage:
            'Goal: ${_assembled()}\n'
            'Child: ${widget.clientName}\n'
            'Frameworks: ${frameworks.isNotEmpty ? frameworks : 'not specified'}',
      );
      if (!mounted) return;
      setState(() {
        _passiveInsight = text ?? '';
        _passiveLoading = false;
        _insightVisible = false;
      });
      // Two-frame trick: render at opacity 0, then flip to 1 so AnimatedOpacity
      // actually transitions rather than snapping directly to visible.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _insightVisible = true);
      });
    } catch (_) {
      // Silent fail — just stop the pulsing dot
      if (mounted) setState(() => _passiveLoading = false);
    }
  }

  Widget _passiveInsightWidget() {
    if (_passiveLoading) {
      return Padding(
        padding: const EdgeInsets.only(top: 10),
        child: SizedBox(
          width: 32,
          height: 32,
          child: Center(
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Orbiting dot — rotates around the stack center
                RotationTransition(
                  turns: _orbitController,
                  child: SizedBox(
                    width: 32,
                    height: 32,
                    child: Align(
                      alignment: const Alignment(0.625, 0), // 10px right in 32px box
                      child: Container(
                        width: 5,
                        height: 5,
                        decoration: const BoxDecoration(
                          color: _csAmberDark,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  ),
                ),
                // Center dot — pulses opacity
                AnimatedBuilder(
                  animation: _pulseAnim,
                  builder: (context2, child2) => Opacity(
                    opacity: _pulseAnim.value,
                    child: Container(
                      width: 7,
                      height: 7,
                      decoration: const BoxDecoration(
                        color: _csAmber,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }
    if (_passiveInsight.isEmpty) return const SizedBox.shrink();
    return AnimatedOpacity(
      opacity: _insightVisible ? 1.0 : 0.0,
      duration: const Duration(milliseconds: 600),
      child: Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Text(
          _passiveInsight,
          style: GoogleFonts.dmSans(
            fontSize: 13,
            color: _csAmberDark,
            fontStyle: FontStyle.italic,
            height: 1.55,
          ),
        ),
      ),
    );
  }

  // ── Cue Study — Voice narrator (multilingual mic) ────────────────────────

  Future<void> _initNarratorSpeech() async {
    final available = await _narratorSpeech.initialize(
      onStatus: (status) async {
        // Web Speech API has a hard ~60 s session cap and fires 'done' when
        // it hits it. If the SLP is still recording, silently restart so she
        // gets a continuous session — same pattern as add_client_screen.dart.
        if (status == 'done' && _narratorRecording && mounted) {
          _narratorPrevText = _narratorText;
          await _startNarratorListening();
          return;
        }
        if ((status == 'done' || status == 'notListening') &&
            !_narratorRecording &&
            mounted) {
          setState(() => _narratorListening = false);
        }
      },
      onError: (e) {
        if (mounted) {
          setState(() {
            _narratorListening  = false;
            _narratorRecording  = false;
            _narratorError = 'Microphone error — check browser permissions.';
          });
        }
      },
    );
    if (mounted) setState(() => _narratorSpeechAvailable = available);
  }

  Future<void> _startNarratorListening() async {
    await _narratorSpeech.listen(
      onResult: (result) {
        if (mounted) {
          setState(() {
            _narratorText =
                ('$_narratorPrevText ${result.recognizedWords}').trim();
          });
        }
      },
      listenFor: const Duration(minutes: 10),
      pauseFor: const Duration(minutes: 10),
      localeId: 'en_IN',
      listenOptions: SpeechListenOptions(partialResults: true),
    );
    if (mounted) setState(() => _narratorListening = true);
  }

  Future<void> _toggleNarratorMic() async {
    if (!_narratorSpeechAvailable) return;

    if (_narratorListening) {
      // Tap to stop — keep transcript, submit automatically
      _narratorRecording = false;
      await _narratorSpeech.stop();
      if (mounted) setState(() => _narratorListening = false);
      if (_narratorText.isNotEmpty) await _submitNarrator();
    } else {
      // Tap to start
      setState(() {
        _narratorError    = null;
        _narratorResponse = '';
      });
      _narratorPrevText  = _narratorText;
      _narratorRecording = true;
      await _startNarratorListening();
    }
  }

  Future<void> _submitNarrator() async {
    final spoken = _narratorText.trim();
    if (spoken.isEmpty) return;

    setState(() { _narratorLoading = true; _narratorError = null; });

    try {
      final text = await _callCueStudy(
        systemPrompt: '$_csFrameworkPrompt $_csMultilingualSuffix',
        userMessage:
            'Goal: ${_assembled()}\n'
            'Child: ${widget.clientName}\n'
            'SLP said: $spoken',
      );
      if (mounted) {
        setState(() {
          _narratorResponse = text ?? '';
          _narratorLoading  = false;
          _narratorText     = ''; // clear transcript after successful response
          _narratorPrevText = '';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _narratorError   = 'Cue Study is unavailable. Try again.';
          _narratorLoading = false;
        });
      }
    }
  }

  // ── Cue Study shared API helper ───────────────────────────────────────────

  @Deprecated(
      'Replaced by CueReasoningService in 4.0.7.20e. The mode helpers '
      'below (_fetchPassiveInsight, _fetchTagExplanation, _fetchReview, '
      '_fetchSession) all routed through this. With the new panel '
      'rendered in place of _cueStudyScrollContent, those helpers no '
      'longer have UI buttons binding them. Will be removed in '
      '4.0.7.20f after the new panel proves out.')
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

  /// Generic Cue Study response card — amber-themed, shared by all in-screen modes.
  Widget _csCard({
    required String modeName,
    required bool loading,
    String? text,
    String? error,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: _navyDark,
        borderRadius: const BorderRadius.all(Radius.circular(10)),
        border: Border(left: BorderSide(color: _csAmberDark, width: 2)),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'CUE STUDY',
            style: GoogleFonts.dmSans(
              fontSize: 10, fontWeight: FontWeight.w600,
              color: _csAmber, letterSpacing: 1.2,
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
                child: CircularProgressIndicator(strokeWidth: 2, color: _csAmberDark),
              ),
            )
          else if (error != null)
            Text(error, style: GoogleFonts.dmSans(fontSize: 12, color: _red))
          else if (text != null && text.isNotEmpty) ...[
            TweenAnimationBuilder<double>(
              key: ValueKey(text),
              tween: Tween<double>(begin: 0.0, end: 1.0),
              duration: const Duration(milliseconds: 400),
              curve: Curves.easeIn,
              builder: (context2, value, child2) => Opacity(
                opacity: value,
                child: Transform.translate(
                  offset: Offset(0, (1.0 - value) * 8),
                  child: child2,
                ),
              ),
              child: Text(
                text,
                style: GoogleFonts.dmSans(
                  fontSize: 13,
                  color: Colors.white.withValues(alpha: 0.82),
                  height: 1.75,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Container(height: 0.5, color: Colors.white.withValues(alpha: 0.1)),
            const SizedBox(height: 8),
            Text(
              'Cue Study supports your reasoning. Clinical judgment is always yours.',
              style: GoogleFonts.dmSans(
                fontSize:  11,
                fontStyle: FontStyle.italic,
                color:     Colors.white.withValues(alpha: 0.35),
                height:    1.5,
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── Phase 4.0.7.20e — CueReasoningPanel integration ─────────────────────
  // Replaces the cramped CUE STUDY sidebar (_cueStudyPanel +
  // _cueStudyScrollContent) at both the wide-layout and narrow-layout
  // render sites. The old methods stay alive (deprecated) for one
  // commit cycle so the cleanup pass in 4.0.7.20f has a reference.

  /// V1: empty list — the SLP picks domains via chips inside the panel.
  /// Smarter inference (population_type → domain map, clinical_lens →
  /// domain map) is 4.0.7.20g work.
  List<String> _inferInitialDomains() => const [];

  Widget _buildCueReasoningPanel() {
    final clientId = (widget.goal['client_id'] as String?) ?? '';
    final ltgId    = widget.goal['id'] as String?;
    return CueReasoningPanel(
      clientId:        clientId,
      ltgId:           ltgId,
      stgId:           null,
      initialDomains:  _inferInitialDomains(),
      onApplyRevision: (revisionText) {
        // The LTG editor decomposes goal_text into action / condition /
        // criterion / timeline. A model "suggested revision" arrives as
        // a single complete goal sentence. Drop it into _actionCtrl and
        // clear the structured fields so the SLP can re-decompose if
        // she wants. This is honest — pretending we can re-parse the
        // sentence into the four slots would silently corrupt structure.
        setState(() {
          _actionCtrl.text    = revisionText;
          _conditionCtrl.text = '';
          _criterionCtrl.text = '';
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                  'Revision applied to the action field — review and split the structured parts.'),
            ),
          );
        }
      },
      onCiteInRationale: (rationaleText) async {
        if (ltgId != null && ltgId.isNotEmpty) {
          try {
            await Supabase.instance.client
                .from('long_term_goals')
                .update({'evidence_rationale': rationaleText})
                .eq('id', ltgId);
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Rationale cited and saved.')),
              );
            }
          } catch (e) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Could not save rationale: $e')),
              );
            }
          }
        } else {
          // No id yet — buffer the rationale for the next save.
          setState(() => _pendingEvidenceRationale = rationaleText);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                    'Rationale queued — will save when you save the goal.'),
              ),
            );
          }
        }
      },
    );
  }

  // ── Cue Study: intelligence panel (fixed header in wide layout) ──────────────

  @Deprecated(
      'Replaced by CueReasoningPanel in 4.0.7.20e. Will be removed in '
      '4.0.7.20f after the new panel proves out.')
  Widget _cueStudyPanel() {
    return Container(
      decoration: BoxDecoration(
        color: _navyDark,
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header row: icon + CUE STUDY label + mic button
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const CueStudyIcon(),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'CUE STUDY',
                  style: GoogleFonts.dmSans(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: _csAmber,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
              GestureDetector(
                onTap: _toggleNarratorMic,
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: _narratorListening
                        ? const Color(0xFFEF4444)
                        : _csAmberDark,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    _narratorListening ? Icons.stop : Icons.mic,
                    color: Colors.white,
                    size: 16,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),

          // ── Description
          Text(
            'A clinical reasoning companion grounded in evidence.',
            style: GoogleFonts.dmSans(
              fontSize: 12,
              color: Colors.white.withValues(alpha: 0.38),
              height: 1.4,
            ),
          ),

          // ── Live transcript while mic is active
          if (_narratorListening && _narratorText.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              _narratorText,
              style: GoogleFonts.dmSans(
                fontSize: 12,
                color: _csAmber,
                fontStyle: FontStyle.italic,
                height: 1.4,
              ),
            ),
          ],

          const SizedBox(height: 12),

          // ── Mode 2: Explore goal directions — filled amber
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _showStuckSheet,
              style: ElevatedButton.styleFrom(
                backgroundColor: _csAmberDark,
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: Text(
                'Explore goal directions',
                style: GoogleFonts.dmSans(
                  fontSize: 14, fontWeight: FontWeight.w500, color: Colors.white,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),

          // ── Mode 3: Check against EBP — outlined amber
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: _reviewLoading ? null : _fetchReview,
              style: OutlinedButton.styleFrom(
                foregroundColor: _csAmber,
                side: BorderSide(color: _csAmber.withValues(alpha: 0.4)),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: Text(
                'Check against EBP',
                style: GoogleFonts.dmSans(
                  fontSize: 14, fontWeight: FontWeight.w500, color: _csAmber,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),

          // ── Mode 4: Session strategies — outlined amber
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: _sessionLoading ? null : _fetchSession,
              style: OutlinedButton.styleFrom(
                foregroundColor: _csAmber,
                side: BorderSide(color: _csAmber.withValues(alpha: 0.4)),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: Text(
                'What does this mean for my session?',
                style: GoogleFonts.dmSans(
                  fontSize: 14, fontWeight: FontWeight.w500, color: _csAmber,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Cue Study: scrollable response cards + frameworks ─────────────────────

  @Deprecated(
      'Replaced by CueReasoningPanel in 4.0.7.20e. Will be removed in '
      '4.0.7.20f after the new panel proves out.')
  Widget _cueStudyScrollContent() {
    final tagCardVisible      = _openTagName != null;
    final reviewCardVisible   = _reviewLoading  || _reviewText  != null || _reviewError  != null;
    final sessionCardVisible  = _sessionLoading || _sessionText != null || _sessionError != null;
    final narratorCardVisible = _narratorLoading || _narratorResponse.isNotEmpty || _narratorError != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Narrator response
        AnimatedSize(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
          alignment: Alignment.topCenter,
          child: narratorCardVisible
              ? Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: _csCard(
                    modeName: 'Voice reasoning',
                    loading: _narratorLoading,
                    text: _narratorResponse.isNotEmpty ? _narratorResponse : null,
                    error: _narratorError,
                  ),
                )
              : const SizedBox.shrink(),
        ),

        // ── EBP review response
        AnimatedSize(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
          alignment: Alignment.topCenter,
          child: reviewCardVisible
              ? Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: _csCard(
                    modeName: 'Check against EBP',
                    loading: _reviewLoading,
                    text: _reviewText,
                    error: _reviewError,
                  ),
                )
              : const SizedBox.shrink(),
        ),

        // ── Session strategies response
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

        // ── Frameworks — separate, outside the intelligence panel
        if (_tags.isNotEmpty) ...[
          const SizedBox(height: 20),
          Container(height: 1, color: _line),
          const SizedBox(height: 16),
          _sectionLabel('FRAMEWORKS LINKED TO THIS GOAL'),
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
                    color: isOpen
                        ? _csAmberDark
                        : _csAmber.withValues(alpha: 0.08),
                    border: Border.all(
                      color: isOpen
                          ? _csAmberDark
                          : _csAmber.withValues(alpha: 0.2),
                    ),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    name,
                    style: GoogleFonts.dmSans(
                      fontSize: 12, fontWeight: FontWeight.w500,
                      color: isOpen ? Colors.white : _csAmber,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
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
      ],
    );
  }

  // ── Narrow-mode: panel + scroll content stacked ───────────────────────────

  @Deprecated(
      'Replaced by inline CueReasoningPanel render in 4.0.7.20e. Will '
      'be removed in 4.0.7.20f.')
  // ignore: deprecated_member_use_from_same_package, unused_element
  Widget _cueStudySection() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ignore: deprecated_member_use_from_same_package
          _cueStudyPanel(),
          // ignore: deprecated_member_use_from_same_package
          _cueStudyScrollContent(),
        ],
      );

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
        builder: (context, constraints) {
          final isWide = constraints.maxWidth >= 700;

          // ── Form fields — shared by both layouts ─────────────────
          final isAchieved =
              (widget.goal['status'] as String?)?.toLowerCase() == 'achieved';
          Widget formContent = Column(
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
              _passiveInsightWidget(),
              if (!isAchieved) ...[
                const SizedBox(height: 32),
                _markAchievedButton(),
              ],
            ],
          );

          if (isWide) {
            // ── Wide (>= 700px): left form | right Cue Study ──────
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Left: scrollable form
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(24, 16, 16, 60),
                    child: formContent,
                  ),
                ),
                // Right: Cue Reasoning panel (520px, full-height,
                // self-managing scroll). Replaces the prior 360px
                // narrow CUE STUDY column shipped pre-4.0.7.20e.
                SizedBox(
                  width: 520,
                  child: _buildCueReasoningPanel(),
                ),
              ],
            );
          }

          // ── Narrow (< 700px): single scrolling column ──────────
          // The reasoning panel manages its own internal scrolling
          // (conversation thread Expanded-flexible); we constrain its
          // outer height so it fits inside the page-level scroll
          // without consuming an unbounded viewport.
          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 60),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                formContent,
                const SizedBox(height: 28),
                SizedBox(
                  height: 560,
                  child: _buildCueReasoningPanel(),
                ),
                const SizedBox(height: 40),
              ],
            ),
          );
        },
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
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      padding: EdgeInsets.fromLTRB(20, 16, 20, 20 + keyboardInset),
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
                  color: const Color(0xFFD3D1C7),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Title row: icon + "Cue Study" + "Goal directions"
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const CueStudyIcon(),
                const SizedBox(width: 8),
                Text(
                  'Cue Study',
                  style: GoogleFonts.dmSans(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: _csAmberDark,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  'Goal directions',
                  style: GoogleFonts.dmSans(
                    fontSize: 13,
                    color: const Color(0xFF9CA3AF),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // Subtitle
            Text(
              'Describe what you want to work on with ${widget.clientName}. '
              'Any language — Hindi, Telugu, English, anything.',
              style: GoogleFonts.dmSans(
                fontSize: 13,
                color: const Color(0xFF6B7280),
                height: 1.5,
              ),
            ),
            const SizedBox(height: 16),

            // Field label
            Text(
              'YOUR CLINICAL THINKING',
              style: GoogleFonts.dmSans(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF9CA3AF),
                letterSpacing: 0.6,
              ),
            ),
            const SizedBox(height: 6),

            // Free-text input
            TextField(
              controller: _ctrl,
              maxLines: 4,
              style: GoogleFonts.dmSans(fontSize: 14, color: _ink, height: 1.5),
              decoration: InputDecoration(
                hintText: 'Type or speak freely...',
                hintStyle: GoogleFonts.dmSans(
                  fontSize: 14,
                  color: const Color(0xFF9CA3AF),
                ),
                filled: true,
                fillColor: Colors.white,
                contentPadding: const EdgeInsets.all(12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Color(0xFFD3D1C7)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Color(0xFFD3D1C7)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: _csAmberDark, width: 1.5),
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Submit button — amber bg, white text
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _loading ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _csAmberDark,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: _csAmberDark.withValues(alpha: 0.4),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  elevation: 0,
                ),
                child: _loading
                    ? const SizedBox(
                        width: 18, height: 18,
                        child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2,
                        ),
                      )
                    : Text(
                        'Get goal directions →',
                        style: GoogleFonts.dmSans(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
              ),
            ),

            // Response card — light amber bg, left amber border
            AnimatedSize(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOut,
              alignment: Alignment.topCenter,
              child: (_loading || _text != null || _error != null)
                  ? Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFFBEB),
                          borderRadius: const BorderRadius.all(Radius.circular(10)),
                          border: Border(
                            left: const BorderSide(color: _csAmberDark, width: 2),
                            top: BorderSide(color: const Color(0xFFD97706).withValues(alpha: 0.15)),
                            right: BorderSide(color: const Color(0xFFD97706).withValues(alpha: 0.15)),
                            bottom: BorderSide(color: const Color(0xFFD97706).withValues(alpha: 0.15)),
                          ),
                        ),
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'CUE STUDY',
                              style: GoogleFonts.dmSans(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: _csAmberDark,
                                letterSpacing: 1.2,
                              ),
                            ),
                            const SizedBox(height: 12),
                            if (_loading)
                              Center(
                                child: CircularProgressIndicator(
                                  strokeWidth: 2, color: _csAmberDark,
                                ),
                              )
                            else if (_error != null)
                              Text(
                                _error!,
                                style: GoogleFonts.dmSans(fontSize: 12, color: _red),
                              )
                            else if (_text != null && _text!.isNotEmpty)
                              TweenAnimationBuilder<double>(
                                key: ValueKey(_text),
                                tween: Tween<double>(begin: 0.0, end: 1.0),
                                duration: const Duration(milliseconds: 400),
                                curve: Curves.easeIn,
                                builder: (context2, value, child2) => Opacity(
                                  opacity: value,
                                  child: Transform.translate(
                                    offset: Offset(0, (1.0 - value) * 8),
                                    child: child2,
                                  ),
                                ),
                                child: Text(
                                  _text!,
                                  style: GoogleFonts.dmSans(
                                    fontSize: 13,
                                    color: _navyDark,
                                    height: 1.7,
                                  ),
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

// CueStudyIcon is imported from ../widgets/cue_study_icon.dart
