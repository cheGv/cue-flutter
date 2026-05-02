// lib/screens/debrief_fluency_screen.dart
//
// Phase 4.0.5 — Layer 03b debrief surface for developmental stuttering.
//
// Post-session reflective capture. The SLP arrives here AFTER a session
// has finished; the screen attaches its assessment_entries row to the
// most recent sessions row for this client.
//
// Severity rating applies the §13.9 instrument-menu pattern — Cue does
// not score copyrighted instruments (§13.14). The §13.9 helper text
// renders verbatim, listing the free option first, then named
// instruments alphabetically, then the observational fallback.
//
// Affirmative language per §13.15: comfort framing not frustration; no
// pronouns; sentence case; "observed / unmarked" framing for avoidance
// behaviours rather than "present / absent".

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../theme/cue_phase4_tokens.dart';
import '../widgets/voice_note_sheet.dart';

// ── Catalogs ──────────────────────────────────────────────────────────────────

const List<({String value, String label})> _severityBands = [
  (value: 'very_mild',   label: 'very mild'),
  (value: 'mild',        label: 'mild'),
  (value: 'moderate',    label: 'moderate'),
  (value: 'severe',      label: 'severe'),
  (value: 'very_severe', label: 'very severe'),
];

const List<({String value, String label})> _comfortBands = [
  (value: 'low',                label: 'low comfort'),
  (value: 'moderate',           label: 'moderate'),
  (value: 'high',               label: 'high comfort'),
  (value: 'unable_to_assess',   label: 'unable to assess'),
];

const List<({String value, String label})> _participationBands = [
  (value: 'limited',          label: 'limited'),
  (value: 'partial',          label: 'partial'),
  (value: 'full',             label: 'full'),
  (value: 'unable_to_assess', label: 'unable to assess'),
];

const List<({String value, String label})> _emotionalResponseBands = [
  (value: 'subdued',          label: 'subdued'),
  (value: 'neutral',          label: 'neutral'),
  (value: 'engaged',          label: 'engaged'),
  (value: 'unable_to_assess', label: 'unable to assess'),
];

const List<({String key, String label})> _avoidanceBehaviours = [
  (key: 'word_substitution',     label: 'word substitution'),
  (key: 'circumlocution',        label: 'circumlocution'),
  (key: 'deferred_speaking_turn',label: 'deferred speaking turn'),
  (key: 'eye_contact_reduction', label: 'eye contact reduction'),
  (key: 'topic_change',          label: 'topic change to avoid stuttering moment'),
  (key: 'silence',               label: 'silence / non-response'),
];

// ── §13.9 instrument-menu helper text — locked verbatim ──────────────────────
const String _kSeverityMenuText =
    "Suitable instruments include — selection at clinician's discretion "
    "based on clinic toolkit: informal observational rating, SSI-4 if "
    "available, KiddyCAT (preschool) if available, OASES if available, or "
    "clinician's preferred alternative.\n\n"
    "Final severity reflects clinician's clinical judgment based on the "
    "chosen instrument or observational rating.";

// ─────────────────────────────────────────────────────────────────────────────

class DebriefFluencyScreen extends StatefulWidget {
  final String clientId;
  final String clientName;

  const DebriefFluencyScreen({
    super.key,
    required this.clientId,
    required this.clientName,
  });

  @override
  State<DebriefFluencyScreen> createState() => _DebriefFluencyScreenState();
}

class _DebriefFluencyScreenState extends State<DebriefFluencyScreen> {
  final _supabase = Supabase.instance.client;

  // Form state
  String? _severityBand;
  final _instrumentUsedCtrl = TextEditingController();
  String? _comfortToday;
  String? _participationToday;
  String? _emotionalResponse;
  final Set<String> _avoidance = {};
  final _clinicalNotesCtrl = TextEditingController();

  // Anchor + persistence state
  int?    _sessionId;
  String? _sessionDate;
  int     _sessionNumber = 0;
  String? _existingDebriefId;
  bool    _loading = true;
  bool    _saving  = false;

  @override
  void initState() {
    super.initState();
    _loadAnchor();
  }

  @override
  void dispose() {
    _instrumentUsedCtrl.dispose();
    _clinicalNotesCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadAnchor() async {
    try {
      // Most recent session for this client. The debrief attaches here.
      final session = await _supabase
          .from('sessions')
          .select('id, date')
          .eq('client_id', widget.clientId)
          .order('date', ascending: false)
          .order('id', ascending: false)
          .limit(1)
          .maybeSingle();

      // Total session count for the eyebrow.
      final allRows = await _supabase
          .from('sessions')
          .select('id')
          .eq('client_id', widget.clientId);
      final number = (allRows as List).length;

      int?    sessionId;
      String? sessionDate;
      if (session != null) {
        sessionId   = (session['id'] as num?)?.toInt();
        sessionDate = session['date'] as String?;
      }

      // Existing debrief for this session?
      Map<String, dynamic>? debriefRow;
      if (sessionId != null) {
        debriefRow = await _supabase
            .from('assessment_entries')
            .select('id, payload')
            .eq('session_id', sessionId)
            .eq('mode', 'debrief')
            .eq('population_type', 'developmental_stuttering')
            .maybeSingle();
      }

      if (!mounted) return;
      setState(() {
        _sessionId      = sessionId;
        _sessionDate    = sessionDate;
        _sessionNumber  = number;
        _loading        = false;
        if (debriefRow != null) {
          _existingDebriefId = debriefRow['id'] as String?;
          _seedFromPayload(
            (debriefRow['payload'] as Map?)?.cast<String, dynamic>() ??
                const {},
          );
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  void _seedFromPayload(Map<String, dynamic> p) {
    final sev = (p['severity'] as Map?) ?? const {};
    _severityBand           = sev['band'] as String?;
    _instrumentUsedCtrl.text = (sev['instrument_used'] as String?) ?? '';

    final impact = (p['impact_for_child'] as Map?) ?? const {};
    _comfortToday        = impact['comfort_today']        as String?;
    _participationToday  = impact['participation_today']  as String?;
    _emotionalResponse   = impact['emotional_response']   as String?;

    _avoidance
      ..clear()
      ..addAll(((p['avoidance_behaviours_today'] as List?) ?? const [])
          .map((e) => e.toString()));

    _clinicalNotesCtrl.text = (p['clinical_notes'] as String?) ?? '';
  }

  Map<String, dynamic> _buildPayload() {
    return {
      'severity': {
        if (_severityBand != null) 'band': _severityBand,
        if (_instrumentUsedCtrl.text.trim().isNotEmpty)
          'instrument_used': _instrumentUsedCtrl.text.trim(),
      },
      'impact_for_child': {
        if (_comfortToday != null)       'comfort_today':       _comfortToday,
        if (_participationToday != null) 'participation_today': _participationToday,
        if (_emotionalResponse != null)  'emotional_response':  _emotionalResponse,
      },
      'avoidance_behaviours_today': _avoidance.toList()..sort(),
      if (_clinicalNotesCtrl.text.trim().isNotEmpty)
        'clinical_notes': _clinicalNotesCtrl.text.trim(),
    };
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);

    final payload = _buildPayload();
    final uid = _supabase.auth.currentUser?.id;

    try {
      // If somehow no session exists yet (SLP opened debrief before any
      // live-entry / session row), create a minimal session row to anchor
      // the debrief. Same client_id, today's date.
      var sessionId = _sessionId;
      if (sessionId == null) {
        final dateStr = DateTime.now().toIso8601String().substring(0, 10);
        final inserted = await _supabase
            .from('sessions')
            .insert({
              'client_id': widget.clientId,
              'date':      dateStr,
              'user_id':   ?uid,
            })
            .select('id')
            .single();
        sessionId = (inserted['id'] as num).toInt();
        _sessionId = sessionId;
      }

      if (_existingDebriefId != null) {
        await _supabase
            .from('assessment_entries')
            .update({'payload': payload})
            .eq('id', _existingDebriefId!);
      } else {
        await _supabase.from('assessment_entries').insert({
          'client_id':       widget.clientId,
          'session_id':      sessionId,
          'mode':            'debrief',
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
          content: Text('Could not save debrief: $e'),
        ));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ── Voice transcription ────────────────────────────────────────────────────

  Future<void> _openVoiceNote() async {
    final transcript = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const VoiceNoteSheet(
        eyebrow: 'voice note · clinical impressions',
        subtitle:
            'Speak freely about what stood out. Transcript fills the field below.',
      ),
    );
    if (transcript == null || transcript.trim().isEmpty) return;
    if (!mounted) return;
    // §13.16 — never silently overwrite clinician-entered text.
    if (_clinicalNotesCtrl.text.trim().isEmpty) {
      setState(() => _clinicalNotesCtrl.text = transcript.trim());
      return;
    }
    final replace = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Replace existing notes?'),
        content: const Text(
            'There\'s already text in clinical impressions. Replace it with the transcribed voice note?'),
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
      setState(() => _clinicalNotesCtrl.text = transcript.trim());
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
                  _severityCard(),
                  const SizedBox(height: 16),
                  _impactCard(),
                  const SizedBox(height: 16),
                  _avoidanceCard(),
                  const SizedBox(height: 16),
                  _clinicalNotesCard(),
                  const SizedBox(height: 22),
                  Container(
                    decoration: const BoxDecoration(
                      border: Border(
                        top: BorderSide(color: kCueBorder, width: 0.5),
                      ),
                    ),
                    padding: const EdgeInsets.only(top: 16),
                    child: _saveButton(),
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
          _sessionNumber > 0
              ? 'debrief · session ${_sessionNumber.toString()}'
              : 'debrief',
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
        if (_sessionDate != null) ...[
          const SizedBox(height: 4),
          Text(
            _sessionDate!,
            style: TextStyle(fontSize: 13, color: kCueSubtitleInk),
          ),
        ],
      ],
    );
  }

  // ── Section 1 — Severity ────────────────────────────────────────────────────

  Widget _severityCard() {
    return _card(
      eyebrow: "severity for today's session",
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _severityBands
                .map((b) => _bandPill(
                      label: b.label,
                      selected: _severityBand == b.value,
                      onTap: () => setState(() {
                        _severityBand =
                            _severityBand == b.value ? null : b.value;
                      }),
                    ))
                .toList(),
          ),
          const SizedBox(height: 14),
          // §13.9 instrument-menu helper text — locked verbatim. Quiet
          // reference, not a call-to-action.
          Text(
            _kSeverityMenuText,
            style: TextStyle(
              fontSize: 13,
              color: kCueSubtitleInk,
              height: 1.6,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'Instrument used (optional)',
            style: const TextStyle(
                fontSize: 13, color: kCueInk, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 6),
          _textField(
            _instrumentUsedCtrl,
            hint: 'e.g. "informal observational" · "SSI-4 = 22 (severe)" · "OASES-S = 65/100"',
          ),
        ],
      ),
    );
  }

  // ── Section 2 — Impact for the child today ─────────────────────────────────

  Widget _impactCard() {
    return _card(
      eyebrow: 'impact for the child today',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _fieldLabel('Comfort during today\'s session'),
          const SizedBox(height: 6),
          _bandRow(
            options: _comfortBands,
            value: _comfortToday,
            onChanged: (v) => setState(() => _comfortToday = v),
          ),
          const SizedBox(height: 6),
          Text(
            'Low comfort warrants clinical attention.',
            style: TextStyle(fontSize: 12, color: kCueSubtitleInk),
          ),
          const SizedBox(height: 16),
          _fieldLabel('Participation in today\'s activities'),
          const SizedBox(height: 6),
          _bandRow(
            options: _participationBands,
            value: _participationToday,
            onChanged: (v) => setState(() => _participationToday = v),
          ),
          const SizedBox(height: 16),
          _fieldLabel('Emotional response observed'),
          const SizedBox(height: 6),
          _bandRow(
            options: _emotionalResponseBands,
            value: _emotionalResponse,
            onChanged: (v) => setState(() => _emotionalResponse = v),
          ),
        ],
      ),
    );
  }

  // ── Section 3 — Avoidance behaviours ───────────────────────────────────────

  Widget _avoidanceCard() {
    return _card(
      eyebrow: 'avoidance behaviours observed today',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _avoidanceBehaviours.map((opt) {
              final selected = _avoidance.contains(opt.key);
              return GestureDetector(
                onTap: () => setState(() {
                  if (selected) {
                    _avoidance.remove(opt.key);
                  } else {
                    _avoidance.add(opt.key);
                  }
                }),
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
                    opt.label,
                    style: TextStyle(
                      fontSize: 13,
                      color: selected ? kCueAmberText : kCueInk,
                      fontWeight:
                          selected ? FontWeight.w500 : FontWeight.w400,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 10),
          Text(
            'Tap each behaviour you observed during the session. Leave unmarked if not observed.',
            style: TextStyle(fontSize: 12, color: kCueSubtitleInk),
          ),
        ],
      ),
    );
  }

  // ── Section 4 — Clinical notes ─────────────────────────────────────────────

  Widget _clinicalNotesCard() {
    return _card(
      eyebrow: 'clinical impressions',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "What stood out today? What's worth probing next session?",
            style: TextStyle(fontSize: 13, color: kCueSubtitleInk),
          ),
          const SizedBox(height: 10),
          _textField(_clinicalNotesCtrl, maxLines: 6),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _openVoiceNote,
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
                  'save debrief',
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

  Widget _bandRow({
    required List<({String value, String label})> options,
    required String? value,
    required ValueChanged<String?> onChanged,
  }) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: options
          .map((b) => _bandPill(
                label: b.label,
                selected: value == b.value,
                onTap: () => onChanged(value == b.value ? null : b.value),
              ))
          .toList(),
    );
  }

  Widget _textField(
    TextEditingController ctrl, {
    String? hint,
    int maxLines = 1,
  }) {
    return TextField(
      controller: ctrl,
      maxLines: maxLines,
      textCapitalization: TextCapitalization.sentences,
      style: const TextStyle(fontSize: 14, color: kCueInk),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(fontSize: 13, color: kCueEyebrowInk),
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
}
