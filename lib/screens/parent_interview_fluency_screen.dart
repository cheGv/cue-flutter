// lib/screens/parent_interview_fluency_screen.dart
//
// Phase 4.0.6 — Layer 03c parent interview surface for developmental
// stuttering.
//
// Recurrent capture across the assessment phase. Each capture is its
// own assessment_entries row with mode='parent_interview'. Per
// PHASE_4_SPEC.md Section 2 the schema's session_id FK is nullable
// precisely because parent-interview can pre-date a session, follow a
// session, or stand alone.
//
// Architecture (b): standalone screen with optional session attachment.
// SLP toggles "attach to today's session" at the top of the form;
// default is attached when a recent session row exists, otherwise
// standalone. session_id on assessment_entries is null for standalone
// captures.
//
// Affirmative language per §13.15 — "easier in / harder in" framing
// only, never "better / worse"; sentence case; no pronouns.
// §13.6 — the family's own words are preserved; Cue does not paraphrase.

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../theme/cue_phase4_tokens.dart';
import '../widgets/voice_note_sheet.dart';

// ── Catalogs ──────────────────────────────────────────────────────────────────

class _CtxOption {
  final String key;
  final String label;
  const _CtxOption(this.key, this.label);
}

const List<_CtxOption> _variabilityContexts = [
  _CtxOption('talking_to_strangers',          'talking to strangers'),
  _CtxOption('reading_aloud',                 'reading aloud'),
  _CtxOption('classroom',                     'classroom'),
  _CtxOption('phone_speaking',                'phone speaking'),
  _CtxOption('with_siblings',                 'with siblings'),
  _CtxOption('at_home',                       'at home'),
  _CtxOption('with_friends',                  'with friends'),
  _CtxOption('with_unfamiliar_adults',        'with unfamiliar adults'),
  // Phase 4.0.6 additions specific to parent observation.
  _CtxOption('when_excited',                  'when excited'),
  _CtxOption('when_tired',                    'when tired'),
  _CtxOption('uncertain_question',            'when asked a question they\'re not sure of'),
];

const List<({String value, String label})> _conversationModes = [
  (value: 'in_person', label: 'in person'),
  (value: 'phone',     label: 'phone'),
  (value: 'video',     label: 'video'),
];

// ─────────────────────────────────────────────────────────────────────────────

class ParentInterviewFluencyScreen extends StatefulWidget {
  final String clientId;
  final String clientName;

  /// Optional: when navigated from a flow that already has a session
  /// row in mind, the caller can prime the screen with it. Otherwise
  /// the screen looks up the most recent session for "attach" default.
  final int? primedSessionId;

  /// Optional: when editing an existing parent_interview row, pass its
  /// id and payload to seed the form.
  final String? editingEntryId;
  final Map<String, dynamic>? editingPayload;

  const ParentInterviewFluencyScreen({
    super.key,
    required this.clientId,
    required this.clientName,
    this.primedSessionId,
    this.editingEntryId,
    this.editingPayload,
  });

  @override
  State<ParentInterviewFluencyScreen> createState() =>
      _ParentInterviewFluencyScreenState();
}

class _ParentInterviewFluencyScreenState
    extends State<ParentInterviewFluencyScreen> {
  final _supabase = Supabase.instance.client;

  // Section 1 — context
  DateTime _date = DateTime.now();
  String   _conversationMode = 'in_person';
  bool     _attachToTodaySession = true; // default per architecture (b)
  int?     _candidateSessionId;          // most-recent session id for the client

  // Section 2 — family priorities
  final _familyPrioritiesCtrl = TextEditingController();

  // Section 3 — variability (chip in two columns: easier_in / harder_in)
  // Each context can be in one column, the other, or neither.
  final Map<String, String> _variability = {}; // key -> 'easier_in' | 'harder_in'

  // Section 4 — recent changes
  final _recentChangesCtrl = TextEditingController();

  // Section 5 — family questions
  final _familyQuestionsCtrl = TextEditingController();

  // Persistence state
  String? _existingEntryId;
  bool    _loading = true;
  bool    _saving  = false;
  bool    _captureCount = false; // placeholder if we want to show count later
  int     _priorCaptures = 0;
  late Map<String, dynamic> _initialSnapshot;

  @override
  void initState() {
    super.initState();
    _initialSnapshot = {};
    _bootstrap();
  }

  @override
  void dispose() {
    _familyPrioritiesCtrl.dispose();
    _recentChangesCtrl.dispose();
    _familyQuestionsCtrl.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    try {
      // Count of prior parent_interview captures for the eyebrow.
      final priorRows = await _supabase
          .from('assessment_entries')
          .select('id')
          .eq('client_id', widget.clientId)
          .eq('mode', 'parent_interview')
          .eq('population_type', 'developmental_stuttering');
      _priorCaptures = (priorRows as List).length;

      // Most-recent session (drives the "attach to today's session" default).
      if (widget.primedSessionId != null) {
        _candidateSessionId = widget.primedSessionId;
      } else {
        final session = await _supabase
            .from('sessions')
            .select('id')
            .eq('client_id', widget.clientId)
            .isFilter('deleted_at', null)
            .order('date', ascending: false)
            .order('id', ascending: false)
            .limit(1)
            .maybeSingle();
        _candidateSessionId = (session?['id'] as num?)?.toInt();
      }

      // If no session exists yet for this client, default to standalone.
      if (_candidateSessionId == null) _attachToTodaySession = false;

      // Editing path?
      if (widget.editingEntryId != null && widget.editingPayload != null) {
        _existingEntryId = widget.editingEntryId;
        _seedFromPayload(widget.editingPayload!);
      }

      _initialSnapshot = _buildPayload();

      if (!mounted) return;
      setState(() {
        _captureCount = true;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  void _seedFromPayload(Map<String, dynamic> p) {
    final ctx = (p['context'] as Map?) ?? const {};
    final dateStr = ctx['date'] as String?;
    if (dateStr != null) {
      _date = DateTime.tryParse(dateStr) ?? DateTime.now();
    }
    final mode = ctx['mode'] as String?;
    if (mode != null && _conversationModes.any((m) => m.value == mode)) {
      _conversationMode = mode;
    }

    _familyPrioritiesCtrl.text = (p['family_priorities'] as String?) ?? '';
    _recentChangesCtrl.text    = (p['recent_changes']    as String?) ?? '';
    _familyQuestionsCtrl.text  = (p['family_questions']  as String?) ?? '';

    final variability = (p['variability_observed_by_family'] as Map?) ?? const {};
    _variability.clear();
    for (final k in (variability['easier_in'] as List? ?? const [])) {
      _variability[k.toString()] = 'easier_in';
    }
    for (final k in (variability['harder_in'] as List? ?? const [])) {
      _variability[k.toString()] = 'harder_in';
    }
  }

  Map<String, dynamic> _buildPayload() {
    final easierIn = <String>[];
    final harderIn = <String>[];
    _variability.forEach((k, v) {
      if (v == 'easier_in') easierIn.add(k);
      if (v == 'harder_in') harderIn.add(k);
    });
    return {
      'context': {
        'date': _date.toIso8601String().substring(0, 10),
        'mode': _conversationMode,
      },
      if (_familyPrioritiesCtrl.text.trim().isNotEmpty)
        'family_priorities': _familyPrioritiesCtrl.text.trim(),
      'variability_observed_by_family': {
        'easier_in': easierIn,
        'harder_in': harderIn,
      },
      if (_recentChangesCtrl.text.trim().isNotEmpty)
        'recent_changes': _recentChangesCtrl.text.trim(),
      if (_familyQuestionsCtrl.text.trim().isNotEmpty)
        'family_questions': _familyQuestionsCtrl.text.trim(),
    };
  }

  bool _isDirty() {
    final current = _buildPayload();
    return current.toString() != _initialSnapshot.toString();
  }

  // ── Save / discard ─────────────────────────────────────────────────────────

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);

    final payload = _buildPayload();
    final uid = _supabase.auth.currentUser?.id;
    final attachedSessionId =
        _attachToTodaySession ? _candidateSessionId : null;

    try {
      if (_existingEntryId != null) {
        await _supabase
            .from('assessment_entries')
            .update({
              'payload':    payload,
              'session_id': attachedSessionId,
            })
            .eq('id', _existingEntryId!);
      } else {
        await _supabase.from('assessment_entries').insert({
          'client_id':       widget.clientId,
          'session_id':      attachedSessionId,
          'mode':            'parent_interview',
          'population_type': 'developmental_stuttering',
          'payload':         payload,
          'created_by':      ?uid,
        });
      }

      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Could not save interview: $e'),
        ));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _discardChanges() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Discard changes?'),
        content: const Text(
            'This interview will not be saved. Any text or pills marked since you opened the screen will be lost.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep editing'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    if (ok == true && mounted) Navigator.pop(context);
  }

  // ── Voice notes ────────────────────────────────────────────────────────────

  Future<void> _voiceFill(TextEditingController ctrl, {required String eyebrow, required String subtitle}) async {
    final transcript = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => VoiceNoteSheet(eyebrow: eyebrow, subtitle: subtitle),
    );
    if (transcript == null || transcript.trim().isEmpty || !mounted) return;
    if (ctrl.text.trim().isEmpty) {
      setState(() => ctrl.text = transcript.trim());
      return;
    }
    final replace = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Replace existing text?'),
        content: const Text(
            'There\'s already text in this field. Replace it with the transcribed voice note?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep existing'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Replace'),
          ),
        ],
      ),
    );
    if (replace == true && mounted) {
      setState(() => ctrl.text = transcript.trim());
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: kCuePaper,
        body: SafeArea(child: Center(child: CircularProgressIndicator())),
      );
    }
    return Scaffold(
      backgroundColor: kCuePaper,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _header(),
                  const SizedBox(height: 22),
                  _contextCard(),
                  const SizedBox(height: 16),
                  _familyPrioritiesCard(),
                  const SizedBox(height: 16),
                  _variabilityCard(),
                  const SizedBox(height: 16),
                  _recentChangesCard(),
                  const SizedBox(height: 16),
                  _familyQuestionsCard(),
                  const SizedBox(height: 22),
                  Container(
                    decoration: const BoxDecoration(
                      border: Border(
                        top: BorderSide(color: kCueBorder, width: 0.5),
                      ),
                    ),
                    padding: const EdgeInsets.only(top: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        _saveButton(),
                        if (_isDirty()) ...[
                          const SizedBox(height: 8),
                          TextButton(
                            onPressed: _discardChanges,
                            child: Text(
                              'discard changes',
                              style: TextStyle(
                                fontSize: 12,
                                color: kCueSubtitleInk,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── Header ──────────────────────────────────────────────────────────────────

  Widget _header() {
    final captureNumber =
        (_existingEntryId != null) ? _priorCaptures : _priorCaptures + 1;
    final ordinal = _ordinal(captureNumber);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _captureCount
              ? 'parent interview · $ordinal capture'
              : 'parent interview',
          style: TextStyle(
            fontSize: 11,
            color: kCueEyebrowInk,
            letterSpacing: kCueEyebrowLetterSpacing(11),
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          widget.clientName,
          style: GoogleFonts.playfairDisplay(
            fontSize: 22,
            fontStyle: FontStyle.italic,
            fontWeight: FontWeight.w600,
            color: kCueInk,
            height: 1.1,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          _formatDate(DateTime.now()),
          style: TextStyle(fontSize: 13, color: kCueSubtitleInk),
        ),
      ],
    );
  }

  String _ordinal(int n) {
    if (n <= 0) return '1st';
    if (n % 100 >= 11 && n % 100 <= 13) return '${n}th';
    switch (n % 10) {
      case 1: return '${n}st';
      case 2: return '${n}nd';
      case 3: return '${n}rd';
      default: return '${n}th';
    }
  }

  // ── Section 1 — Context ────────────────────────────────────────────────────

  Widget _contextCard() {
    return _card(
      eyebrow: 'context',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _fieldLabel('Date of conversation'),
          const SizedBox(height: 6),
          GestureDetector(
            onTap: _pickDate,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              decoration: BoxDecoration(
                color: kCueSurface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: kCueBorder, width: 0.5),
              ),
              child: Row(
                children: [
                  const Icon(Icons.calendar_today_outlined,
                      size: 16, color: kCueEyebrowInk),
                  const SizedBox(width: 10),
                  Text(
                    _formatDate(_date),
                    style: const TextStyle(fontSize: 14, color: kCueInk),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          _fieldLabel('Mode of conversation'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _conversationModes
                .map((m) => _bandPill(
                      label: m.label,
                      selected: _conversationMode == m.value,
                      onTap: () => setState(() => _conversationMode = m.value),
                    ))
                .toList(),
          ),
          const SizedBox(height: 16),
          // Attach to today's session (architecture choice b).
          GestureDetector(
            onTap: _candidateSessionId == null
                ? null
                : () => setState(
                    () => _attachToTodaySession = !_attachToTodaySession),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: kCuePaper,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: kCueBorder, width: 0.5),
              ),
              child: Row(
                children: [
                  Icon(
                    _attachToTodaySession
                        ? Icons.check_box_rounded
                        : Icons.check_box_outline_blank_rounded,
                    color:
                        _attachToTodaySession ? kCueAmber : kCueEyebrowInk,
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _candidateSessionId == null
                          ? 'No prior session yet — saving as a standalone capture.'
                          : (_attachToTodaySession
                              ? 'Attached to the most recent session.'
                              : 'Standalone capture (no session attached).'),
                      style: const TextStyle(fontSize: 13, color: kCueInk),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked != null && mounted) setState(() => _date = picked);
  }

  // ── Section 2 — Family priorities ──────────────────────────────────────────

  Widget _familyPrioritiesCard() {
    return _card(
      eyebrow: 'what matters most to the family right now',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "What does the family want their child to be able to do? "
            "What's the most urgent concern this week?",
            style: TextStyle(fontSize: 13, color: kCueSubtitleInk),
          ),
          const SizedBox(height: 10),
          _textField(_familyPrioritiesCtrl, maxLines: 5),
          const SizedBox(height: 10),
          _voiceNoteButton(
            onTap: () => _voiceFill(
              _familyPrioritiesCtrl,
              eyebrow: 'voice note · family priorities',
              subtitle:
                  "Capture the family's words about what they want most.",
            ),
          ),
        ],
      ),
    );
  }

  // ── Section 3 — Variability ────────────────────────────────────────────────

  Widget _variabilityCard() {
    return _card(
      eyebrow: 'variability — situations where speech feels different',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Tap a context under the column the family observed.',
            style: TextStyle(fontSize: 13, color: kCueSubtitleInk),
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 560;
              if (wide) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: _variabilityColumn('easier_in')),
                    const SizedBox(width: 16),
                    Expanded(child: _variabilityColumn('harder_in')),
                  ],
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _variabilityColumn('easier_in'),
                  const SizedBox(height: 14),
                  _variabilityColumn('harder_in'),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _variabilityColumn(String column) {
    final header = column == 'easier_in' ? 'easier in' : 'harder in';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          header,
          style: TextStyle(
            fontSize: 11,
            color: kCueEyebrowInk,
            letterSpacing: kCueEyebrowLetterSpacing(11),
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _variabilityContexts.map((c) {
            final state = _variability[c.key];
            final inThisColumn = state == column;
            final inOtherColumn = state != null && !inThisColumn;
            return GestureDetector(
              onTap: () => setState(() {
                if (inThisColumn) {
                  _variability.remove(c.key);
                } else {
                  _variability[c.key] = column;
                }
              }),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: inThisColumn
                      ? kCueAmberSurface
                      : (inOtherColumn ? kCuePaper : kCueSurface),
                  borderRadius: BorderRadius.circular(kCueChipRadius),
                  border: Border.all(
                    color: inThisColumn ? kCueAmber : kCueBorder,
                    width: inThisColumn ? 1.2 : kCueCardBorderW,
                  ),
                ),
                child: Text(
                  c.label,
                  style: TextStyle(
                    fontSize: 13,
                    color: inThisColumn
                        ? kCueAmberText
                        : (inOtherColumn ? kCueEyebrowInk : kCueInk),
                    fontWeight:
                        inThisColumn ? FontWeight.w500 : FontWeight.w400,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  // ── Section 4 — Recent changes ─────────────────────────────────────────────

  Widget _recentChangesCard() {
    return _card(
      eyebrow: "what's changed recently",
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Has the parent noticed any change in the last few weeks? '
            'In school context, at home, with peers?',
            style: TextStyle(fontSize: 13, color: kCueSubtitleInk),
          ),
          const SizedBox(height: 10),
          _textField(_recentChangesCtrl, maxLines: 4),
          const SizedBox(height: 10),
          _voiceNoteButton(
            onTap: () => _voiceFill(
              _recentChangesCtrl,
              eyebrow: 'voice note · recent changes',
              subtitle:
                  "Note what's shifted, in the parent's words.",
            ),
          ),
        ],
      ),
    );
  }

  // ── Section 5 — Family questions ───────────────────────────────────────────

  Widget _familyQuestionsCard() {
    return _card(
      eyebrow: 'questions the family is sitting with',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'What is the family asking? What worries them? '
            'What do they hope to understand?',
            style: TextStyle(fontSize: 13, color: kCueSubtitleInk),
          ),
          const SizedBox(height: 10),
          _textField(_familyQuestionsCtrl, maxLines: 4),
          const SizedBox(height: 10),
          _voiceNoteButton(
            onTap: () => _voiceFill(
              _familyQuestionsCtrl,
              eyebrow: 'voice note · family questions',
              subtitle:
                  "Capture the questions exactly as the family asked them.",
            ),
          ),
        ],
      ),
    );
  }

  // ── Save button ────────────────────────────────────────────────────────────

  Widget _saveButton() {
    return SizedBox(
      width: double.infinity,
      child: GestureDetector(
        onTap: _saving ? null : _save,
        child: Container(
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: kCueInk,
            borderRadius: BorderRadius.circular(kCueTileRadius),
          ),
          child: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      color: Colors.white, strokeWidth: 2),
                )
              : const Text(
                  'save interview',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.white,
                    fontWeight: FontWeight.w500,
                  ),
                ),
        ),
      ),
    );
  }

  // ── Primitives ─────────────────────────────────────────────────────────────

  Widget _card({required String eyebrow, required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
      decoration: BoxDecoration(
        color: kCueSurface,
        borderRadius: BorderRadius.circular(kCueCardRadius),
        border: Border.all(color: kCueBorder, width: kCueCardBorderW),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            eyebrow,
            style: TextStyle(
              fontSize: 11,
              color: kCueEyebrowInk,
              letterSpacing: kCueEyebrowLetterSpacing(11),
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  Widget _fieldLabel(String text) => Text(
        text,
        style: const TextStyle(
            fontSize: 13, color: kCueInk, fontWeight: FontWeight.w500),
      );

  Widget _bandPill({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? kCueAmberSurface : kCueSurface,
          borderRadius: BorderRadius.circular(kCueChipRadius),
          border: Border.all(
            color: selected ? kCueAmber : kCueBorder,
            width: selected ? 1.2 : kCueCardBorderW,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            color: selected ? kCueAmberText : kCueInk,
            fontWeight: selected ? FontWeight.w500 : FontWeight.w400,
          ),
        ),
      ),
    );
  }

  Widget _textField(TextEditingController ctrl, {int maxLines = 1}) {
    return TextField(
      controller: ctrl,
      maxLines: maxLines,
      onChanged: (_) => setState(() {}), // refresh discard affordance
      textCapitalization: TextCapitalization.sentences,
      style: const TextStyle(fontSize: 14, color: kCueInk),
      decoration: InputDecoration(
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: kCueBorder, width: 0.5),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: kCueBorder, width: 0.5),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: kCueAmber, width: 1.2),
        ),
      ),
    );
  }

  Widget _voiceNoteButton({required VoidCallback onTap}) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: const Icon(Icons.mic_rounded, size: 16, color: kCueAmber),
      label: const Text('voice note',
          style: TextStyle(fontSize: 13, color: kCueAmberText)),
      style: OutlinedButton.styleFrom(
        backgroundColor: kCueAmberSurface,
        side: const BorderSide(color: kCueAmber, width: 1.2),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(kCueChipRadius)),
      ),
    );
  }

  String _formatDate(DateTime d) {
    const months = [
      '', 'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December',
    ];
    return '${d.day} ${months[d.month]} ${d.year}';
  }
}
