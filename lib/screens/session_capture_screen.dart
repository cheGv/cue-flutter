// lib/screens/session_capture_screen.dart
//
// Phase 4.0.7.28-session-capture-v1 — Prose-first session capture screen.
// Replaces the 6-step SessionNoteScreen wizard as the destination of
// AddSessionScreen's "Type session notes" button. SessionNoteScreen is
// kept in the repo as orphan code for the Phase 2 multi-domain rebuild;
// this screen owns every clinical_area uniformly.
//
// Architectural locks (don't deviate without a phase note):
//   1. Domain awareness reads `clients.clinical_area` (16-code taxonomy
//      from lib/constants/clinical_areas.dart), NOT `population_type`.
//   2. Auto-save every 30s while the prose textarea is non-empty.
//   3. Prose stays editable forever — no lock state.
//   4. Single textarea — voice (VoiceNoteSheet, Web Speech API) and
//      typed text interleave in the same controller.
//   5. Soft-delete via session_archive_service (deleted_at/by/reason).
//
// Sessions table contract (verified against live schema):
//   - INSERT shape on first save: client_id, client_name, date, notes,
//     status, user_id (six columns). All other columns rely on schema
//     defaults.
//   - status enum: 'draft' | 'complete' | 'error'. Auto-save writes
//     'draft'; final save writes 'complete'. The legacy 'captured' value
//     would have failed a CHECK constraint.
//   - Optional structured fields (Add details panel) write to
//     population_payload (jsonb) via UPDATE on subsequent auto-saves and
//     on final save. Never on the initial INSERT — preserves the locked
//     six-column shape.
//
// Auto-save failure UX (per Phase 4.0.7.28 amendment 4):
//   - Tick 1 fail   → silent retry next tick.
//   - Tick 2 fail   → snackbar "Auto-save couldn't reach the server".
//   - Tick 3+ fail  → persistent dismissable amber banner at top of body.
//   - On any successful save: reset both the failure counter and the
//     dismiss state.

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/session_archive_service.dart';
import '../theme/cue_phase4_tokens.dart';
import '../widgets/app_layout.dart';
import '../widgets/voice_note_sheet.dart';
import 'report_screen.dart';

class SessionCaptureScreen extends StatefulWidget {
  final String    clientId;
  final String    clientName;
  final DateTime? selectedDate;
  /// Phase 4.0.7.31c — when non-null, the screen mounts in edit mode:
  /// loads notes + population_payload + date from the existing row,
  /// pre-populates the controllers, and sets `_draftSessionId` so the
  /// auto-save tick takes the UPDATE branch from frame 1. Default null
  /// preserves the create flow used by AddSessionScreen.
  ///
  /// Type rationale: `int?` (not `String?`) because this is the *target
  /// row* of UPDATE statements, not a forward-passed reference. The
  /// Supabase Dart client returns `bigint` PK as `int`, and `.eq('id',
  /// existingSessionId!)` accepts it directly with no parse round-trip.
  /// String? would force a `?.toString()` coercion at every save site.
  /// ReportScreen's tap handler defensively coerces from any shape via
  /// `int.tryParse(sid?.toString() ?? '')` before constructing the route.
  final int? existingSessionId;

  const SessionCaptureScreen({
    super.key,
    required this.clientId,
    required this.clientName,
    this.selectedDate,
    this.existingSessionId,
  });

  @override
  State<SessionCaptureScreen> createState() => _SessionCaptureScreenState();
}

// ── Domain-aware optional fields ─────────────────────────────────────────────
//
// Field IDs are stable JSONB keys for population_payload — do not rename
// after they ship. Labels are SLP-facing; placeholder uses the same copy
// rendered in muted ink.
//
// Six clinical_area codes get bespoke field sets; the remaining ten fall
// through to the generic _kAllOthersFields default. Phase 4.0.7.29 will
// route `aac` to the autism-developmental field set.

class _CaptureField {
  final String id;
  final String label;
  final bool   multiline; // 2-line for "what was tried", else 1-line.
  const _CaptureField({
    required this.id,
    required this.label,
    this.multiline = false,
  });
}

const _CaptureField _fTriedToday = _CaptureField(
  id: 'tried_today',
  label: 'What was tried today?',
  multiline: true,
);
const _CaptureField _fRegulatoryState = _CaptureField(
  id: 'regulatory_state',
  label: 'Regulatory state observed',
);
const _CaptureField _fFamilyObservation = _CaptureField(
  id: 'family_observation',
  label: 'Family / caregiver observation',
);
const _CaptureField _fNextSessionNote = _CaptureField(
  id: 'next_session_note',
  label: 'Anything to remember for next session',
);
const _CaptureField _fStutteringQualitative = _CaptureField(
  id: 'stuttering_qualitative',
  label: 'Stuttering observed (qualitative)',
);
const _CaptureField _fStrategiesTried = _CaptureField(
  id: 'strategies_tried',
  label: 'Strategies tried',
);
const _CaptureField _fAvoidance = _CaptureField(
  id: 'avoidance_noticed',
  label: 'Avoidance noticed',
);
const _CaptureField _fVocalQuality = _CaptureField(
  id: 'vocal_quality',
  label: 'Vocal quality observed',
);
const _CaptureField _fCommunicationStrategies = _CaptureField(
  id: 'communication_strategies',
  label: 'Communication strategies used',
);
const _CaptureField _fFamilyOrPartner = _CaptureField(
  id: 'family_or_partner_observation',
  label: 'Family / partner observation',
);
const _CaptureField _fSpeechProduction = _CaptureField(
  id: 'speech_production',
  label: 'Speech production observed',
);

const List<_CaptureField> _kAutismFields = [
  _fTriedToday, _fRegulatoryState, _fFamilyObservation, _fNextSessionNote,
];
const List<_CaptureField> _kFluencyFields = [
  _fStutteringQualitative, _fStrategiesTried, _fAvoidance, _fNextSessionNote,
];
const List<_CaptureField> _kVoiceFields = [
  _fVocalQuality, _fStrategiesTried, _fFamilyObservation, _fNextSessionNote,
];
const List<_CaptureField> _kAdultLanguageFields = [
  _fTriedToday, _fCommunicationStrategies, _fFamilyOrPartner, _fNextSessionNote,
];
const List<_CaptureField> _kPediatricDysarthriaFields = [
  _fSpeechProduction, _fStrategiesTried, _fFamilyObservation, _fNextSessionNote,
];
const List<_CaptureField> _kDysphagiaFields = [
  _fTriedToday, _fFamilyObservation, _fNextSessionNote,
];
const List<_CaptureField> _kAllOthersFields = [
  _fTriedToday, _fFamilyObservation, _fNextSessionNote,
];

List<_CaptureField> _fieldsFor(String? clinicalArea) {
  switch (clinicalArea) {
    case 'autism-developmental':     return _kAutismFields;
    case 'fluency':                  return _kFluencyFields;
    case 'voice':                    return _kVoiceFields;
    case 'adult-language-cognitive': return _kAdultLanguageFields;
    case 'pediatric-dysarthria':     return _kPediatricDysarthriaFields;
    case 'dysphagia':                return _kDysphagiaFields;
    default:                         return _kAllOthersFields;
  }
}

// ── Date formatting ──────────────────────────────────────────────────────────
const List<String> _kMonthNames = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December',
];

String _formatDateLong(DateTime d) =>
    '${d.day} ${_kMonthNames[d.month - 1]} ${d.year}';

String _formatDateIso(DateTime d) =>
    d.toIso8601String().substring(0, 10);

// ── State ────────────────────────────────────────────────────────────────────

class _SessionCaptureScreenState extends State<SessionCaptureScreen> {
  final _supabase = Supabase.instance.client;
  final _proseCtrl = TextEditingController();

  // Optional-field controllers, keyed by field id. Lazily populated as
  // the SLP expands the Add details panel.
  final Map<String, TextEditingController> _fieldCtrls = {};

  late DateTime _selectedDate;
  String? _clinicalArea;
  bool    _detailsExpanded = false;
  int?    _draftSessionId;
  Timer?  _autosaveTimer;
  bool    _saving = false;
  int     _consecutiveAutoSaveFailures = 0;
  bool    _offlineBannerDismissed = false;
  // Phase 4.0.7.31-unified-save-flow — empty-save guard. Set true when
  // the SLP taps Save (or Save & Generate) with no prose AND no
  // population_payload entries; renders the inline "Add notes or fill a
  // detail to save." annotation under the action row. Reset on the next
  // input event by _onAnyInputChanged so the annotation disappears the
  // moment the SLP starts typing.
  bool    _emptySaveAttempt = false;
  // Phase 4.0.7.31c — edit-mode load failure recovery. When
  // _loadExistingSession errors out (network/RLS/missing row),
  // _loadFailed flips true AND _draftSessionId is nulled so subsequent
  // saves take the INSERT branch (= a fresh session row), preventing
  // accidental overwrite of a row we couldn't read first. The snackbar
  // delivering this fact fires once via _onAnyInputChanged when the
  // SLP types > 10 chars (gating noise from SLPs who navigate away
  // without typing).
  bool    _loadFailed = false;
  bool    _loadFailedSnackbarShown = false;

  static const Duration _autoSavePeriod = Duration(seconds: 30);

  @override
  void initState() {
    super.initState();
    _selectedDate = widget.selectedDate ?? DateTime.now();
    _loadClinicalArea();
    _autosaveTimer = Timer.periodic(_autoSavePeriod, (_) => _autoSaveTick());
    // Empty-save annotation is dismissed by any input event.
    _proseCtrl.addListener(_onAnyInputChanged);

    // Phase 4.0.7.31c — edit-mode hydration. CRITICAL INVARIANT:
    // _draftSessionId MUST be set SYNCHRONOUSLY here, before any auto-
    // save tick can fire. If a future refactor moves this into the
    // async load callback, the first auto-save tick at second 30 will
    // see _draftSessionId == null AND prose populated (from the load
    // that already returned), take the INSERT branch, and duplicate
    // the row. The auto-save guard `if (prose.isEmpty) return` covers
    // the in-flight window cleanly because prose stays empty until
    // _loadExistingSession's setState lands.
    if (widget.existingSessionId != null) {
      _draftSessionId = widget.existingSessionId;
      _loadExistingSession();
    }
  }

  Future<void> _loadExistingSession() async {
    try {
      final row = await _supabase
          .from('sessions')
          .select('date, notes, population_payload')
          .eq('id', widget.existingSessionId!)
          .isFilter('deleted_at', null)
          .maybeSingle();
      if (!mounted) return;
      if (row == null) {
        // Row not found (deleted between push and load, or RLS-blocked).
        // Treat as load failure — see _handleLoadFailure().
        _handleLoadFailure();
        return;
      }

      final dateStr = row['date'] as String?;
      final notes   = row['notes'] as String?;
      final payload = row['population_payload'];

      setState(() {
        if (dateStr != null) {
          try {
            _selectedDate = DateTime.parse(dateStr);
          } catch (_) { /* keep constructor default */ }
        }
        if (notes != null && notes.isNotEmpty) {
          _proseCtrl.text = notes;
        }
        if (payload is Map) {
          for (final entry in payload.entries) {
            final v = entry.value;
            if (v is String && v.trim().isNotEmpty) {
              // _ctrlFor lazy-creates the controller and wires the
              // empty-save listener; setting text here is consistent
              // with the create-flow data path.
              _ctrlFor(entry.key.toString()).text = v;
            }
          }
          // If any field came in populated, the SLP almost certainly
          // wants the panel expanded so they can see what they wrote.
          if ((payload).isNotEmpty) _detailsExpanded = true;
        }
      });
    } catch (_) {
      _handleLoadFailure();
    }
  }

  /// Phase 4.0.7.31c — silent failure recovery for edit-mode load.
  /// Nulling _draftSessionId forces subsequent saves to take the INSERT
  /// branch, preventing the SLP's typing from overwriting a row we
  /// couldn't read first (which would risk corrupting state we don't
  /// understand). Snackbar delivery is gated to fire once after the
  /// SLP types meaningfully (>10 chars) so SLPs who navigated here and
  /// then bounced don't see noise.
  void _handleLoadFailure() {
    if (!mounted) return;
    setState(() {
      _loadFailed     = true;
      _draftSessionId = null;
    });
  }

  void _onAnyInputChanged() {
    if (_emptySaveAttempt) {
      setState(() => _emptySaveAttempt = false);
    }
    // Phase 4.0.7.31c — gated snackbar for edit-mode load failure.
    // Fires once when the SLP has typed >10 chars (signal of intent to
    // continue working) so they're informed before they assume their
    // edits will land in the original row. _draftSessionId was already
    // nulled in _handleLoadFailure, so the subsequent save will INSERT
    // a fresh row regardless.
    if (_loadFailed &&
        !_loadFailedSnackbarShown &&
        _proseCtrl.text.trim().length > 10) {
      _loadFailedSnackbarShown = true;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            "Couldn't load existing notes — your new typing will save "
            'as a new session.',
          ),
          duration: Duration(seconds: 4),
        ),
      );
    }
  }

  bool get _hasSaveContent {
    if (_proseCtrl.text.trim().isNotEmpty) return true;
    for (final c in _fieldCtrls.values) {
      if (c.text.trim().isNotEmpty) return true;
    }
    return false;
  }

  @override
  void dispose() {
    _autosaveTimer?.cancel();
    _proseCtrl.dispose();
    for (final c in _fieldCtrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _loadClinicalArea() async {
    try {
      final row = await _supabase
          .from('clients')
          .select('clinical_area')
          .eq('id', widget.clientId)
          .isFilter('deleted_at', null)
          .maybeSingle();
      if (!mounted) return;
      setState(() => _clinicalArea = row?['clinical_area'] as String?);
    } catch (_) {
      if (!mounted) return;
      setState(() => _clinicalArea = null); // falls through to ALL OTHERS
    }
  }

  TextEditingController _ctrlFor(String fieldId) =>
      _fieldCtrls.putIfAbsent(fieldId, () {
        final c = TextEditingController();
        c.addListener(_onAnyInputChanged);
        return c;
      });

  // Builds the population_payload map from any non-empty optional fields.
  // Returns null when nothing is filled, so we don't write `{}` and waste
  // the JSONB slot.
  Map<String, String>? _buildPopulationPayload() {
    final out = <String, String>{};
    for (final entry in _fieldCtrls.entries) {
      final v = entry.value.text.trim();
      if (v.isNotEmpty) out[entry.key] = v;
    }
    return out.isEmpty ? null : out;
  }

  // ── Auto-save ──────────────────────────────────────────────────────────────

  Future<void> _autoSaveTick() async {
    if (!mounted) return;
    final prose = _proseCtrl.text.trim();
    // Empty textarea — pause. Don't create a draft row for nothing, and
    // don't blank out an existing draft (the SLP may erase momentarily
    // between thoughts).
    if (prose.isEmpty) return;

    try {
      if (_draftSessionId == null) {
        // First persistence — INSERT the locked six-column shape with
        // status='draft'. population_payload (if any) follows in a
        // subsequent UPDATE so the INSERT shape stays canonical.
        final uid = _supabase.auth.currentUser?.id;
        final inserted = await _supabase
            .from('sessions')
            .insert({
              'client_id':   widget.clientId,
              'client_name': widget.clientName,
              'date':        _formatDateIso(_selectedDate),
              'notes':       prose,
              'status':      'draft',
              'user_id':     ?uid,
            })
            .select()
            .single();
        if (!mounted) return;
        setState(() {
          _draftSessionId = (inserted['id'] as num?)?.toInt();
        });
        // If the SLP filled optional fields before the first tick fired,
        // flush them now so the draft row carries them too.
        final payload = _buildPopulationPayload();
        if (payload != null && _draftSessionId != null) {
          await _supabase
              .from('sessions')
              .update({'population_payload': payload})
              .eq('id', _draftSessionId!);
        }
      } else {
        // Subsequent ticks — UPDATE prose + population_payload on the
        // existing draft row. status stays 'draft' until final save.
        final payload = _buildPopulationPayload();
        await _supabase
            .from('sessions')
            .update({
              'notes':              prose,
              'population_payload': ?payload,
            })
            .eq('id', _draftSessionId!);
      }
      _onAutoSaveSuccess();
    } catch (_) {
      _onAutoSaveFailure();
    }
  }

  void _onAutoSaveSuccess() {
    if (!mounted) return;
    if (_consecutiveAutoSaveFailures != 0 || _offlineBannerDismissed) {
      setState(() {
        _consecutiveAutoSaveFailures = 0;
        _offlineBannerDismissed = false;
      });
    }
  }

  void _onAutoSaveFailure() {
    if (!mounted) return;
    setState(() => _consecutiveAutoSaveFailures += 1);
    // Tick 1: silent. Tick 2: snackbar. Tick 3+: persistent banner.
    if (_consecutiveAutoSaveFailures == 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Auto-save couldn't reach the server. We'll keep trying."),
          duration: Duration(seconds: 3),
        ),
      );
    }
    // Banner visibility is computed in build() — no separate toggle.
  }

  // ── Final save ─────────────────────────────────────────────────────────────
  //
  // Phase 4.0.7.31-unified-save-flow — _save() and _saveAndGenerate()
  // share the same persistence path via _persistComplete(). The split
  // lets Save snackbar+pop to the chart, while Save & Generate
  // pushReplacement to ReportScreen with autoGenerate: true. Failure
  // handling is identical: snackbar, no navigation, no state loss.

  /// Writes (or flips) the session row to status='complete'. Returns
  /// the session id on success, throws on failure. Auto-save banner /
  /// counter is reset on success. Does not touch UI navigation — that's
  /// the caller's responsibility.
  Future<int> _persistComplete() async {
    final prose   = _proseCtrl.text.trim();
    final payload = _buildPopulationPayload();
    int? sessionId = _draftSessionId;

    if (sessionId == null) {
      final uid = _supabase.auth.currentUser?.id;
      final inserted = await _supabase
          .from('sessions')
          .insert({
            'client_id':   widget.clientId,
            'client_name': widget.clientName,
            'date':        _formatDateIso(_selectedDate),
            'notes':       prose,
            'status':      'complete',
            'user_id':     ?uid,
          })
          .select()
          .single();
      sessionId = (inserted['id'] as num?)?.toInt();
      if (payload != null && sessionId != null) {
        await _supabase
            .from('sessions')
            .update({'population_payload': payload})
            .eq('id', sessionId);
      }
      _draftSessionId = sessionId;
    } else {
      await _supabase
          .from('sessions')
          .update({
            'notes':              prose,
            'status':             'complete',
            'population_payload': ?payload,
          })
          .eq('id', sessionId);
    }

    _onAutoSaveSuccess();
    if (sessionId == null) {
      throw StateError('Insert returned no id');
    }
    return sessionId;
  }

  Future<void> _save() async {
    if (_saving) return;
    if (!_hasSaveContent) {
      setState(() => _emptySaveAttempt = true);
      return;
    }
    setState(() => _saving = true);
    try {
      await _persistComplete();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Saved.'),
          duration: Duration(milliseconds: 1200),
        ),
      );
      await Future.delayed(const Duration(milliseconds: 1000));
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Save failed — your text is safe. Try again.')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _saveAndGenerate() async {
    if (_saving) return;
    if (!_hasSaveContent) {
      setState(() => _emptySaveAttempt = true);
      return;
    }
    setState(() => _saving = true);
    int? sessionId;
    try {
      sessionId = await _persistComplete();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Save failed — your text is safe. Try again.'),
        ),
      );
      setState(() => _saving = false);
      return;
    }

    if (!mounted) return;
    // In-memory session map mirrors the row we just persisted. No
    // re-fetch round trip — values match what _persistComplete wrote.
    final sessionMap = <String, dynamic>{
      'id':          sessionId,
      'client_id':   widget.clientId,
      'client_name': widget.clientName,
      'date':        _formatDateIso(_selectedDate),
      'notes':       _proseCtrl.text.trim(),
      'status':      'complete',
    };

    // pushReplacement so the back-button from ReportScreen returns to
    // the client profile (AddSessionScreen also pops on the result=true
    // path, which percolates upward), not to a stale capture screen.
    //
    // Phase 4.0.7.39 — RouteSettings.name lets the URL bar reflect
    // /sessions/:id while the imperative push preserves
    // `autoGenerate: true` (the Save & Generate one-shot trigger).
    // Hard refresh of the same URL resolves through the deep-link
    // loader, which hardcodes autoGenerate=false per the founder
    // safety lock — preventing accidental LLM regen on refresh.
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        settings: RouteSettings(name: '/sessions/$sessionId'),
        builder: (_) => ReportScreen(
          session:      sessionMap,
          clientName:   widget.clientName,
          clientId:     widget.clientId,
          autoGenerate: true,
        ),
      ),
      result: true,
    );
  }

  // ── Delete (soft) ──────────────────────────────────────────────────────────

  Future<void> _delete() async {
    // No draft persisted yet → simple confirm-and-pop. Nothing to archive.
    if (_draftSessionId == null) {
      final discard = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Discard this session?'),
          content: const Text(
            "You haven't saved anything yet. Anything you've typed will be lost.",
          ),
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
      if (discard == true && mounted) Navigator.pop(context, true);
      return;
    }

    // Draft exists → soft-delete via the shared archive service. The
    // service owns the confirm dialog + reason picker + PATCH.
    final archived = await archiveSession(
      context: context,
      session: {'id': _draftSessionId},
    );
    if (archived && mounted) Navigator.pop(context, true);
  }

  // ── Date picker ────────────────────────────────────────────────────────────

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate:   DateTime(2020),
      lastDate:    DateTime.now(),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.light(
            primary:   kCueAmber,
            onPrimary: Colors.white,
            surface:   Colors.white,
            onSurface: kCueInk,
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null && mounted) {
      setState(() => _selectedDate = picked);
    }
  }

  // ── Voice dictation ────────────────────────────────────────────────────────

  Future<void> _openDictate() async {
    final transcript = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const VoiceNoteSheet(
        eyebrow:  'voice note',
        subtitle: 'Speak freely. Transcript appends to your notes.',
      ),
    );
    if (transcript == null || transcript.trim().isEmpty || !mounted) return;
    // Append (don't overwrite). Two newlines as a paragraph separator
    // when the existing prose isn't empty.
    final existing = _proseCtrl.text;
    final separator = existing.trim().isEmpty ? '' : '\n\n';
    _proseCtrl.text = '$existing$separator${transcript.trim()}';
    _proseCtrl.selection = TextSelection.collapsed(
      offset: _proseCtrl.text.length,
    );
    setState(() {});
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  bool get _showOfflineBanner =>
      _consecutiveAutoSaveFailures >= 3 && !_offlineBannerDismissed;

  @override
  Widget build(BuildContext context) {
    final fields = _fieldsFor(_clinicalArea);
    // Phase 4.0.7.31c — prefix-swap based on edit vs create mode.
    // Mirrors the prior 'Session — Vignesh' shape; only the lead verb
    // changes. Sentence case (lowercase second word), em-dash separator.
    final titlePrefix =
        widget.existingSessionId != null ? 'Edit session' : 'New session';
    return AppLayout(
      title: '$titlePrefix — ${widget.clientName}',
      activeRoute: 'roster',
      body: Column(
        children: [
          if (_showOfflineBanner) _buildOfflineBanner(),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 720),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildDateRow(),
                      const SizedBox(height: 28),
                      _buildProseSection(),
                      const SizedBox(height: 12),
                      _buildDictateAndDetailsRow(),
                      if (_detailsExpanded) ...[
                        const SizedBox(height: 16),
                        _buildDetailsPanel(fields),
                      ],
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ),
            ),
          ),
          _buildActionRow(),
        ],
      ),
    );
  }

  Widget _buildOfflineBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      decoration: const BoxDecoration(
        color: kCueAmberSurface,
        border: Border(
          bottom: BorderSide(color: kCueBorder, width: kCueCardBorderW),
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.cloud_off, size: 18, color: kCueAmberDeeper),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              "Auto-save offline — your text is safe locally until you tap Save.",
              style: GoogleFonts.dmSans(
                fontSize:   13,
                color:      kCueAmberText,
                height:     1.4,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 18),
            color: kCueAmberDeeper,
            tooltip: 'Dismiss',
            onPressed: () =>
                setState(() => _offlineBannerDismissed = true),
          ),
        ],
      ),
    );
  }

  Widget _buildDateRow() {
    return InkWell(
      onTap: _pickDate,
      borderRadius: BorderRadius.circular(kCueCardRadius),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            const Icon(Icons.event, size: 18, color: kCueMutedInk),
            const SizedBox(width: 10),
            Text(
              _formatDateLong(_selectedDate),
              style: GoogleFonts.dmSans(
                fontSize:   16,
                fontWeight: FontWeight.w500,
                color:      kCueInk,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '· tap to change',
              style: GoogleFonts.dmSans(
                fontSize: 13,
                color:    kCueSubtitleInk,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProseSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'What happened today?',
          style: GoogleFonts.dmSans(
            fontSize:   22,
            fontWeight: FontWeight.w500,
            color:      kCueInk,
            height:     1.3,
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _proseCtrl,
          minLines: 8,
          maxLines: null,
          keyboardType: TextInputType.multiline,
          style: GoogleFonts.dmSans(
            fontSize: 15,
            color:    kCueInk,
            height:   1.55,
          ),
          decoration: InputDecoration(
            hintText: 'Type or speak — write it however you remember it.',
            hintStyle: GoogleFonts.dmSans(
              fontSize:  15,
              color:     kCueSubtitleInk,
              height:    1.55,
              fontStyle: FontStyle.italic,
            ),
            filled: true,
            fillColor: kCueSurface,
            contentPadding: const EdgeInsets.all(16),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(kCueCardRadius),
              borderSide: const BorderSide(
                color: kCueBorder,
                width: kCueCardBorderW,
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(kCueCardRadius),
              borderSide: const BorderSide(
                color: kCueBorder,
                width: kCueCardBorderW,
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(kCueCardRadius),
              borderSide: const BorderSide(
                color: kCueAmber,
                width: 1.0,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDictateAndDetailsRow() {
    return Row(
      children: [
        TextButton.icon(
          onPressed: _openDictate,
          icon: const Icon(Icons.mic_none, size: 18, color: kCueAmberDeep),
          label: Text(
            'Dictate',
            style: GoogleFonts.dmSans(
              fontSize:   14,
              fontWeight: FontWeight.w500,
              color:      kCueAmberDeep,
            ),
          ),
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          ),
        ),
        const Spacer(),
        TextButton.icon(
          onPressed: () =>
              setState(() => _detailsExpanded = !_detailsExpanded),
          icon: Icon(
            _detailsExpanded
                ? Icons.keyboard_arrow_up
                : Icons.keyboard_arrow_down,
            size: 18,
            color: kCueMutedInk,
          ),
          label: Text(
            _detailsExpanded ? 'Hide details' : 'Add details',
            style: GoogleFonts.dmSans(
              fontSize:   14,
              fontWeight: FontWeight.w500,
              color:      kCueMutedInk,
            ),
          ),
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          ),
        ),
      ],
    );
  }

  Widget _buildDetailsPanel(List<_CaptureField> fields) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      decoration: BoxDecoration(
        color: kCueSurface,
        border: Border.all(color: kCueBorder, width: kCueCardBorderW),
        borderRadius: BorderRadius.circular(kCueCardRadius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < fields.length; i++) ...[
            _buildOptionalField(fields[i]),
            if (i != fields.length - 1) const SizedBox(height: 12),
          ],
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _buildOptionalField(_CaptureField f) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          f.label,
          style: GoogleFonts.dmSans(
            fontSize:      11,
            fontWeight:    FontWeight.w600,
            color:         kCueEyebrowInk,
            letterSpacing: kCueEyebrowLetterSpacing(11),
          ),
        ),
        const SizedBox(height: 4),
        TextField(
          controller: _ctrlFor(f.id),
          minLines: f.multiline ? 2 : 1,
          maxLines: f.multiline ? 3 : 1,
          style: GoogleFonts.dmSans(
            fontSize: 14,
            color:    kCueInk,
            height:   1.5,
          ),
          decoration: InputDecoration(
            hintText: f.label,
            hintStyle: GoogleFonts.dmSans(
              fontSize: 14,
              color:    kCueSubtitleInk,
              height:   1.5,
            ),
            isDense: true,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 0, vertical: 8),
            border: const UnderlineInputBorder(
              borderSide: BorderSide(color: kCueBorder),
            ),
            enabledBorder: const UnderlineInputBorder(
              borderSide: BorderSide(color: kCueBorder),
            ),
            focusedBorder: const UnderlineInputBorder(
              borderSide: BorderSide(color: kCueAmber, width: 1.0),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildActionRow() {
    // Dynamic destructive label: "Discard" before any auto-save tick
    // has fired (no DB row yet, no soft-delete needed); "Delete session"
    // once a draft row exists (archive_dialog runs the soft-delete).
    final destructiveLabel =
        _draftSessionId == null ? 'Discard' : 'Delete session';
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
      decoration: const BoxDecoration(
        color: kCueSurface,
        border: Border(
          top: BorderSide(color: kCueBorder, width: kCueCardBorderW),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              // Tertiary: Discard / Delete session — muted, no border.
              TextButton.icon(
                onPressed: _saving ? null : _delete,
                icon: const Icon(
                    Icons.delete_outline, size: 18, color: kCueMutedInk),
                label: Text(
                  destructiveLabel,
                  style: GoogleFonts.dmSans(
                    fontSize:   14,
                    fontWeight: FontWeight.w500,
                    color:      kCueMutedInk,
                  ),
                ),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 12),
                ),
              ),
              const Spacer(),
              // Secondary: Save — outlined ink, no fill.
              OutlinedButton(
                onPressed: _saving ? null : _save,
                style: OutlinedButton.styleFrom(
                  foregroundColor: kCueInk,
                  side: const BorderSide(color: kCueBorder),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 18, vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(kCueCardRadius),
                  ),
                ),
                child: Text(
                  'Save',
                  style: GoogleFonts.dmSans(
                    fontSize:   14,
                    fontWeight: FontWeight.w500,
                    color:      kCueInk,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Primary: Save & Generate — filled amber + sparkle. The
              // encouraged path; absorbs the AI-generation work the SLP
              // would otherwise have to trigger separately on
              // ReportScreen.
              FilledButton.icon(
                onPressed: _saving ? null : _saveAndGenerate,
                style: FilledButton.styleFrom(
                  backgroundColor: kCueAmber,
                  disabledBackgroundColor:
                      kCueAmber.withValues(alpha: 0.5),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 18, vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(kCueCardRadius),
                  ),
                ),
                icon: _saving
                    ? const SizedBox(
                        width:  16,
                        height: 16,
                        child: CircularProgressIndicator(
                          color:       Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : const Icon(Icons.auto_awesome, size: 16),
                label: Text(
                  'Save & Generate',
                  style: GoogleFonts.dmSans(
                    fontSize:   14,
                    fontWeight: FontWeight.w600,
                    color:      Colors.white,
                  ),
                ),
              ),
            ],
          ),
          // Empty-save annotation — quiet, polite, dismissed by next
          // input event. Subtitle ink, 13px, 8px above its container's
          // bottom edge (matches spec amendment 4 in the unified flow).
          if (_emptySaveAttempt) ...[
            const SizedBox(height: 8),
            Semantics(
              liveRegion: true,
              child: Text(
                'Add notes or fill a detail to save.',
                style: GoogleFonts.dmSans(
                  fontSize: 13,
                  color:    kCueSubtitleInk,
                  height:   1.4,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
