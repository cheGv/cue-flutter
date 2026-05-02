// lib/screens/pre_therapy_planning_fluency_screen.dart
//
// Phase 4.0.7 — Layer 04 pre-therapy planning surface for developmental
// stuttering. Captures family goals verbatim, priority focus
// (drag-to-reorder), child's readiness, and family involvement.
// Persists to goal_plans.clarifying_answers as a draft row.
//
// Persistence architecture (a): the latest draft goal_plans row for the
// client carries Layer-04 input keys plus a `_layer04_locked: true`
// marker once saved. Generate Plan (4.0.8) reads from this row and
// transitions it to status='active' when goals are produced.
//
// §13.6 — family's verbatim words preserved. §13.15 — affirmative
// language. §13.16 — voice transcript fills only when the field is
// empty.

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../theme/cue_phase4_tokens.dart';
import '../widgets/voice_note_sheet.dart';
import 'goal_authoring_screen.dart';

// ── Default priority catalog ──────────────────────────────────────────────────

class _PriorityItem {
  final String id;
  final String label;
  final bool   isCustom;
  const _PriorityItem({
    required this.id,
    required this.label,
    required this.isCustom,
  });

  Map<String, dynamic> toJson() => {
        'id':        id,
        'label':     label,
        'is_custom': isCustom,
      };

  factory _PriorityItem.fromJson(Map<String, dynamic> j) => _PriorityItem(
        id:       j['id'] as String,
        label:    j['label'] as String,
        isCustom: (j['is_custom'] as bool?) ?? false,
      );
}

const List<_PriorityItem> _defaultPriorities = [
  _PriorityItem(
    id: 'school_participation',
    label:
        'school participation — reading aloud, classroom answers',
    isCustom: false,
  ),
  _PriorityItem(
    id: 'confidence_with_teachers',
    label:
        'confidence speaking with teachers and unfamiliar adults',
    isCustom: false,
  ),
  _PriorityItem(
    id: 'reduce_secondary_behaviours',
    label:
        'reduction of secondary behaviours (eye blink, facial tension)',
    isCustom: false,
  ),
  _PriorityItem(
    id: 'home_conversation_fluency',
    label:
        'overall fluency in conversation at home',
    isCustom: false,
  ),
  _PriorityItem(
    id: 'awareness_acceptance',
    label:
        'awareness and acceptance of stuttering moments',
    isCustom: false,
  ),
];

// ── Bands ─────────────────────────────────────────────────────────────────────

const List<({String value, String label})> _readinessBands = [
  (value: 'low',                label: 'low'),
  (value: 'moderate',           label: 'moderate'),
  (value: 'high',               label: 'high'),
  (value: 'unable_to_assess',   label: 'unable to assess'),
];

const List<({String value, String label})> _involvementBands = [
  (value: 'limited',  label: 'limited'),
  (value: 'moderate', label: 'moderate'),
  (value: 'high',     label: 'high'),
];

// ─────────────────────────────────────────────────────────────────────────────

class PreTherapyPlanningFluencyScreen extends StatefulWidget {
  final String clientId;
  final String clientName;
  final int    sessionCount;

  /// When true (default), the "lock plan inputs · proceed to plan"
  /// button replaces this screen with GoalAuthoringScreen on success.
  /// When false, save just pops back to the caller — used when entering
  /// from the chart's "Plan inputs" pill (the SLP is editing inputs,
  /// not building a plan right now).
  final bool proceedToAuthoringOnLock;

  const PreTherapyPlanningFluencyScreen({
    super.key,
    required this.clientId,
    required this.clientName,
    required this.sessionCount,
    this.proceedToAuthoringOnLock = true,
  });

  @override
  State<PreTherapyPlanningFluencyScreen> createState() =>
      _PreTherapyPlanningFluencyScreenState();
}

class _PreTherapyPlanningFluencyScreenState
    extends State<PreTherapyPlanningFluencyScreen> {
  final _supabase = Supabase.instance.client;

  // Section 1 — family goals verbatim
  final _familyGoalsCtrl = TextEditingController();

  // Section 2 — priority focus
  late List<_PriorityItem> _priorities;

  // Section 3 — readiness
  String? _childReadiness;
  String? _familyInvolvement;

  // Persistence state
  String? _existingDraftPlanId;
  bool    _loading = true;
  bool    _saving  = false;

  @override
  void initState() {
    super.initState();
    _priorities = List.of(_defaultPriorities);
    _bootstrap();
  }

  @override
  void dispose() {
    _familyGoalsCtrl.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    try {
      // Find the most-recent draft goal_plans row for the client.
      final row = await _supabase
          .from('goal_plans')
          .select('id, clarifying_answers')
          .eq('client_id', widget.clientId)
          .eq('status', 'draft')
          .order('updated_at', ascending: false)
          .limit(1)
          .maybeSingle();
      if (row != null) {
        _existingDraftPlanId = row['id'] as String?;
        final clarifying =
            (row['clarifying_answers'] as Map?)?.cast<String, dynamic>();
        if (clarifying != null) _seedFromPayload(clarifying);
      }
      if (!mounted) return;
      setState(() => _loading = false);
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  void _seedFromPayload(Map<String, dynamic> p) {
    _familyGoalsCtrl.text =
        (p['family_goals_verbatim'] as String?) ?? '';

    final priorities = p['priority_focus'];
    if (priorities is List && priorities.isNotEmpty) {
      _priorities = priorities
          .map((e) => _PriorityItem.fromJson(
              (e as Map).cast<String, dynamic>()))
          .toList();
    }

    final readiness = (p['readiness'] as Map?) ?? const {};
    _childReadiness    = readiness['child_readiness_for_direct_work'] as String?;
    _familyInvolvement = readiness['family_involvement_available']    as String?;
  }

  Map<String, dynamic> _buildPayload({required bool locked}) {
    return {
      if (_familyGoalsCtrl.text.trim().isNotEmpty)
        'family_goals_verbatim': _familyGoalsCtrl.text.trim(),
      'priority_focus':
          _priorities.map((p) => p.toJson()).toList(),
      'readiness': {
        if (_childReadiness != null)
          'child_readiness_for_direct_work': _childReadiness,
        if (_familyInvolvement != null)
          'family_involvement_available': _familyInvolvement,
      },
      '_layer04_locked': locked,
    };
  }

  // ── Save ───────────────────────────────────────────────────────────────────

  Future<void> _save({required bool lock}) async {
    if (_saving) return;
    setState(() => _saving = true);

    final payload = _buildPayload(locked: lock);
    final uid = _supabase.auth.currentUser?.id;

    try {
      if (_existingDraftPlanId != null) {
        await _supabase
            .from('goal_plans')
            .update({'clarifying_answers': payload})
            .eq('id', _existingDraftPlanId!);
      } else {
        final inserted = await _supabase
            .from('goal_plans')
            .insert({
              'client_id':          widget.clientId,
              'user_id':            ?uid,
              'status':             'draft',
              'clarifying_answers': payload,
              // framework_router defaults to 'regulatory_asd' on the
              // table; Generate Plan (4.0.8) will overwrite when the
              // fluency branch ships and the check constraint widens.
            })
            .select('id')
            .single();
        _existingDraftPlanId = inserted['id'] as String?;
      }

      if (!mounted) return;

      if (lock && widget.proceedToAuthoringOnLock) {
        // Replace ourselves with Goal Authoring so back from authoring
        // returns to the chart, not to plan inputs.
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => GoalAuthoringScreen(
              clientId:     widget.clientId,
              clientName:   widget.clientName,
              sessionCount: widget.sessionCount,
            ),
          ),
        );
      } else {
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Could not save plan inputs: $e'),
        ));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ── Voice note ─────────────────────────────────────────────────────────────

  Future<void> _voiceFillFamilyGoals() async {
    final transcript = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const VoiceNoteSheet(
        eyebrow: 'voice note · family goals',
        subtitle:
            "Capture the family's hopes in their own words.",
      ),
    );
    if (transcript == null || transcript.trim().isEmpty || !mounted) return;
    if (_familyGoalsCtrl.text.trim().isEmpty) {
      setState(() => _familyGoalsCtrl.text = transcript.trim());
      return;
    }
    final replace = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Replace existing text?'),
        content: const Text(
            "There's already text in family goals. Replace it with the transcribed voice note?"),
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
      setState(() => _familyGoalsCtrl.text = transcript.trim());
    }
  }

  // ── Priority list mutations ────────────────────────────────────────────────

  void _reorder(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) newIndex -= 1;
      final item = _priorities.removeAt(oldIndex);
      _priorities.insert(newIndex, item);
    });
  }

  void _removePriority(String id) {
    setState(() => _priorities.removeWhere((p) => p.id == id));
  }

  Future<void> _addCustomPriority() async {
    final text = await showDialog<String>(
      context: context,
      builder: (ctx) {
        final ctrl = TextEditingController();
        return AlertDialog(
          title: const Text('Add a priority'),
          content: TextField(
            controller: ctrl,
            autofocus: true,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              hintText: 'e.g. confidence in birthday parties',
            ),
            onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
              child: const Text('Add'),
            ),
          ],
        );
      },
    );
    if (text == null || text.isEmpty || !mounted) return;
    setState(() {
      _priorities.add(_PriorityItem(
        id: 'custom_${DateTime.now().millisecondsSinceEpoch}',
        label: text,
        isCustom: true,
      ));
    });
  }

  void _restoreDefaults() {
    setState(() {
      final existingIds = _priorities.map((p) => p.id).toSet();
      for (final d in _defaultPriorities) {
        if (!existingIds.contains(d.id)) _priorities.add(d);
      }
    });
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
                  _familyGoalsCard(),
                  const SizedBox(height: 16),
                  _prioritiesCard(),
                  const SizedBox(height: 16),
                  _readinessCard(),
                  const SizedBox(height: 22),
                  Container(
                    decoration: const BoxDecoration(
                      border: Border(
                        top: BorderSide(color: kCueBorder, width: 0.5),
                      ),
                    ),
                    padding: const EdgeInsets.only(top: 16),
                    child: _bottomActions(),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _header() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'pre-therapy planning',
          style: TextStyle(
            fontSize: 11,
            color: kCueEyebrowInk,
            letterSpacing: kCueEyebrowLetterSpacing(11),
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 4),
        RichText(
          text: TextSpan(
            children: [
              TextSpan(
                text: widget.clientName,
                style: GoogleFonts.playfairDisplay(
                  fontSize: 24,
                  fontStyle: FontStyle.italic,
                  fontWeight: FontWeight.w600,
                  color: kCueInk,
                  height: 1.1,
                ),
              ),
              TextSpan(
                text: ' · what does the family want?',
                style: GoogleFonts.playfairDisplay(
                  fontSize: 24,
                  fontStyle: FontStyle.italic,
                  fontWeight: FontWeight.w400,
                  color: kCueSubtitleInk,
                  height: 1.1,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Captured before plan generation · informs goal selection',
          style: TextStyle(fontSize: 13, color: kCueSubtitleInk),
        ),
      ],
    );
  }

  // ── Section 1 ──────────────────────────────────────────────────────────────

  Widget _familyGoalsCard() {
    return _card(
      eyebrow: "family goals · in their words",
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Quote the family as closely as possible. The longer-form intake captured the parent\'s first concern — this is where their fuller hopes live.',
            style: TextStyle(
                fontSize: 13, color: kCueSubtitleInk, height: 1.45),
          ),
          const SizedBox(height: 12),
          // Editorial input — left amber border, paper background,
          // Playfair italic in the field itself.
          Container(
            decoration: BoxDecoration(
              color: kCuePaper,
              borderRadius: const BorderRadius.only(
                topRight:    Radius.circular(8),
                bottomRight: Radius.circular(8),
              ),
              border: const Border(
                left: BorderSide(color: kCueAmber, width: 2),
              ),
            ),
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            child: TextField(
              controller: _familyGoalsCtrl,
              maxLines: 6,
              minLines: 4,
              textCapitalization: TextCapitalization.sentences,
              onChanged: (_) => setState(() {}),
              style: GoogleFonts.playfairDisplay(
                fontSize: 15,
                fontStyle: FontStyle.italic,
                color: kCueInk,
                height: 1.55,
              ),
              decoration: InputDecoration(
                isCollapsed: true,
                border: InputBorder.none,
                hintText:
                    "Type or speak the family's hopes here…",
                hintStyle: GoogleFonts.playfairDisplay(
                  fontSize: 15,
                  fontStyle: FontStyle.italic,
                  color: kCueEyebrowInk,
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _voiceFillFamilyGoals,
            icon: const Icon(Icons.mic_rounded, size: 16, color: kCueAmber),
            label: const Text('+ voice note',
                style: TextStyle(fontSize: 13, color: kCueAmberText)),
            style: OutlinedButton.styleFrom(
              backgroundColor: kCueAmberSurface,
              side: const BorderSide(color: kCueAmber, width: 1.2),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(kCueChipRadius)),
            ),
          ),
        ],
      ),
    );
  }

  // ── Section 2 ──────────────────────────────────────────────────────────────

  Widget _prioritiesCard() {
    return _card(
      eyebrow: 'priority focus · drag to reorder',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'What matters most right now? Higher priority shapes goal sequencing.',
            style: TextStyle(
                fontSize: 13, color: kCueSubtitleInk, height: 1.45),
          ),
          const SizedBox(height: 14),
          ReorderableListView.builder(
            buildDefaultDragHandles: false,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _priorities.length,
            onReorder: _reorder,
            proxyDecorator: (child, index, anim) {
              // Keep the tile's amber/white treatment from its current
              // position; suppress the Material lift shadow.
              return Material(
                color: Colors.transparent,
                elevation: 0,
                child: child,
              );
            },
            itemBuilder: (context, i) {
              final p = _priorities[i];
              final isLeading = i < 2;
              return Padding(
                key: ValueKey(p.id),
                padding: const EdgeInsets.only(bottom: 8),
                child: _priorityTile(p, position: i, leading: isLeading),
              );
            },
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              GestureDetector(
                onTap: _addCustomPriority,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: kCueAmberSurface,
                    borderRadius: BorderRadius.circular(kCueChipRadius),
                    border: Border.all(color: kCueAmber, width: 1.2),
                  ),
                  child: Text(
                    '+ add custom priority',
                    style: TextStyle(
                      fontSize: 12,
                      color: kCueAmberText,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              if (_priorities.length < _defaultPriorities.length)
                GestureDetector(
                  onTap: _restoreDefaults,
                  child: Text(
                    '+ restore defaults',
                    style: TextStyle(
                      fontSize: 12,
                      color: kCueSubtitleInk,
                      fontWeight: FontWeight.w500,
                      decoration: TextDecoration.underline,
                      decorationColor: kCueSubtitleInk,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Drag the handle to reorder · top two are amber-marked as the family\'s leading priorities · everything below is captured but lower in goal sequencing weight.',
            style: TextStyle(
                fontSize: 12, color: kCueEyebrowInk, height: 1.45),
          ),
        ],
      ),
    );
  }

  Widget _priorityTile(_PriorityItem p,
      {required int position, required bool leading}) {
    final bg          = leading ? kCueAmberSurface : kCueSurface;
    final textColor   = leading ? kCueAmberText    : kCueMutedInk;
    final handleColor = leading ? kCueAmberDeeper  : const Color(0x591A1A1A);
    final borderColor = leading ? kCueAmber        : kCueBorderStrong;
    return Container(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(kCueTileRadius),
        border: Border.all(
          color: borderColor,
          width: leading ? 1.2 : kCueCardBorderW,
        ),
      ),
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
      child: Row(
        children: [
          ReorderableDragStartListener(
            index: position,
            child: MouseRegion(
              cursor: SystemMouseCursors.grab,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Icon(
                  Icons.drag_indicator,
                  size: 16,
                  color: handleColor,
                ),
              ),
            ),
          ),
          const SizedBox(width: 4),
          Container(
            width: 22,
            height: 22,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: leading ? kCueAmber : Colors.transparent,
              shape: BoxShape.circle,
              border: leading
                  ? null
                  : Border.all(color: kCueBorderStrong, width: 0.5),
            ),
            child: Text(
              (position + 1).toString(),
              style: TextStyle(
                fontSize: 11,
                color: leading ? Colors.white : kCueMutedInk,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              p.label,
              style: TextStyle(
                fontSize: 13,
                color: textColor,
                fontWeight:
                    leading ? FontWeight.w500 : FontWeight.w400,
                height: 1.5,
              ),
            ),
          ),
          GestureDetector(
            onTap: () => _removePriority(p.id),
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Icon(
                Icons.close_rounded,
                size: 16,
                color: leading ? kCueAmberDeeper : kCueEyebrowInk,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Section 3 ──────────────────────────────────────────────────────────────

  Widget _readinessCard() {
    return _card(
      eyebrow: 'readiness & support',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _fieldLabel("Child's readiness for direct work"),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _readinessBands
                .map((b) => _bandPill(
                      label: b.label,
                      selected: _childReadiness == b.value,
                      onTap: () => setState(() {
                        _childReadiness =
                            _childReadiness == b.value ? null : b.value;
                      }),
                    ))
                .toList(),
          ),
          const SizedBox(height: 6),
          Text(
            'Low readiness signals the child needs environmental scaffolding before direct fluency work.',
            style: TextStyle(fontSize: 12, color: kCueSubtitleInk),
          ),
          const SizedBox(height: 16),
          _fieldLabel('Family involvement available'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _involvementBands
                .map((b) => _bandPill(
                      label: b.label,
                      selected: _familyInvolvement == b.value,
                      onTap: () => setState(() {
                        _familyInvolvement = _familyInvolvement == b.value
                            ? null
                            : b.value;
                      }),
                    ))
                .toList(),
          ),
          const SizedBox(height: 6),
          Text(
            'What the family can realistically provide as support outside sessions.',
            style: TextStyle(fontSize: 12, color: kCueSubtitleInk),
          ),
        ],
      ),
    );
  }

  // ── Bottom actions ─────────────────────────────────────────────────────────

  Widget _bottomActions() {
    return Row(
      children: [
        Expanded(
          flex: 1,
          child: GestureDetector(
            onTap: _saving ? null : () => _save(lock: false),
            child: Container(
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(kCueTileRadius),
                border:
                    Border.all(color: kCueBorder, width: kCueCardBorderW),
              ),
              child: Text(
                'save as draft',
                style: TextStyle(
                  fontSize: 14,
                  color: kCueMutedInk,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          flex: 2,
          child: GestureDetector(
            onTap: _saving ? null : () => _save(lock: true),
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
                  : Text(
                      widget.proceedToAuthoringOnLock
                          ? 'lock plan inputs · proceed to plan'
                          : 'lock plan inputs',
                      style: const TextStyle(
                        fontSize: 14,
                        color: Colors.white,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
            ),
          ),
        ),
      ],
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
}

// ── Top-level helper for the chart's Build-plan gate ─────────────────────────

/// Reads the latest draft goal_plans row for the client and reports
/// whether plan_inputs have been locked. Used by client_profile_screen
/// to decide whether to route Build-plan-with-Cue through the Layer 04
/// surface first.
Future<bool> isPlanInputsLocked({
  required SupabaseClient supabase,
  required String clientId,
}) async {
  try {
    final row = await supabase
        .from('goal_plans')
        .select('clarifying_answers')
        .eq('client_id', clientId)
        .eq('status', 'draft')
        .order('updated_at', ascending: false)
        .limit(1)
        .maybeSingle();
    if (row == null) return false;
    final clarifying =
        (row['clarifying_answers'] as Map?)?.cast<String, dynamic>();
    return clarifying?['_layer04_locked'] == true;
  } catch (_) {
    return false;
  }
}
