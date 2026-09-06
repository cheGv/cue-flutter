// lib/screens/assessing_screen.dart
//
// Phase 4.0.7.24 — assessment-only engagements live in their own
// sidebar surface, parallel to (not phased within) the Clients flow.
// Layout intentionally mirrors ClientRosterScreen so the SLP's mental
// model is "two lists side by side, same shape, different intent."
//
// V1 minimum: list of active assessment cases + Add CTA. The clinical
// content (visit timeline, capture sections, diagnostic synthesis)
// lives on AssessmentCaseScreen and gets authored in 4.0.7.24a-e.

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../constants/clinical_areas.dart';
import '../services/clients_roster_service.dart' show cueRelativeDayLabel;
import '../theme/cue_color_scheme.dart';
import '../widgets/app_layout.dart';
import '../services/client_delete_service.dart';
import '../services/clients_query.dart';
import '../services/trial_run_delete_service.dart';
import '../widgets/clients_roster_filter_chips.dart';
import '../widgets/clients_roster_search_bar.dart';
import '../widgets/trial_run_delete_dialog.dart';
// 4.0.7.27c-split — assessment intake split out of AddClientScreen
// (which is now therapy-only). NewAssessmentCaseScreen is the slim
// 10-field intake; control reaches it via the '/new-assessment' named
// route (Phase 4.0.7.39). AssessmentCaseScreen is reached via
// '/assessing/:clientId'. Neither is imported here — both resolve
// through main.dart's onGenerateRoute.

// Polarity migration (2026-05-21): rendered surface colors now resolve
// via CueColorsResolved.of(context). These two light-register consts
// survive only for _errorBanner(), which is flagged for the deliberate
// batch — its amber-surface fill has no resolver equivalent (the
// resolver exposes the amber accent, not an amber surface tint).
const Color _ink       = Color(0xFF0E1C36);
const Color _amberSoft = Color(0xFFF4E4C4);

class AssessingScreen extends StatefulWidget {
  const AssessingScreen({super.key});

  @override
  State<AssessingScreen> createState() => _AssessingScreenState();
}

class _AssessingScreenState extends State<AssessingScreen> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _cases = [];
  // Stage 2B — trial runs load separately, via the includeTrial opt-in.
  List<Map<String, dynamic>> _trialCases = [];
  bool _creatingTrial = false;

  // Clients-idiom list controls (2026-08-02): search + status tabs.
  final _searchCtrl = TextEditingController();
  String _query = '';
  String _filter = 'all';

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(() {
      final q = _searchCtrl.text.trim().toLowerCase();
      if (q != _query) setState(() => _query = q);
    });
    _load();
    _loadTrials();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  /// Cases matching the active tab + search box. Both filters run over
  /// rows already in memory — no extra queries.
  List<Map<String, dynamic>> get _visibleCases {
    var out = _cases;
    if (_filter == 'active') {
      out = out
          .where((c) => c['engagement_status'] == 'in_assessment')
          .toList();
    }
    if (_query.isNotEmpty) {
      out = out.where((c) {
        final hay = [
          (c['name'] as String?) ?? '',
          clinicalAreaLabel(c['clinical_area'] as String?),
          (c['primary_concern_verbatim'] as String?) ?? '',
        ].join(' ').toLowerCase();
        return hay.contains(_query);
      }).toList();
    }
    return out;
  }

  int get _inAssessmentCount =>
      _cases.where((c) => c['engagement_status'] == 'in_assessment').length;

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error   = null;
    });
    try {
      // Phase 4.0.7.29 Stage 2A: route through the ClientsQuery gate so
      // soft-deleted AND trial-run cases are excluded by construction
      // (deleted_at IS NULL + is_trial_case = false applied by the gate).
      final rows = await ClientsQuery()
          .read('*')
          .eq('engagement_type', 'assessment_only')
          .not('engagement_status', 'in', '(discharged,converted)')
          .order('updated_at', ascending: false);
      if (!mounted) return;
      setState(() {
        _cases = List<Map<String, dynamic>>.from(rows);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  Future<void> _openAdd() async {
    // 4.0.7.27c-split — slim assessment intake. Pushes the new screen,
    // which on submit replaces itself with the assessment capture
    // surface; control returns here only via the back button.
    // Phase 4.0.7.39 — pushNamed so the URL bar reflects
    // /new-assessment instead of staying on /assessing.
    await Navigator.pushNamed(context, '/new-assessment');
    if (mounted) await _load();
  }

  Future<void> _openCase(Map<String, dynamic> client) async {
    // Phase 4.0.7.24c — push via named route so the URL becomes
    // /assessing/:clientId. A hard refresh on that URL is then
    // resolved by main.dart's _AssessmentCaseDeepLinkLoader and
    // stays on the case screen instead of bouncing to this list.
    final clientId = client['id']?.toString() ?? '';
    await Navigator.pushNamed(context, '/assessing/$clientId');
    if (mounted) await _load();
  }

  // ── Stage 2B: trial runs ──────────────────────────────────────────────────
  //
  // Trial cases are real `clients` rows flagged is_trial_case = true. They are
  // invisible to every real workflow (the Stage 2A gate excludes them by
  // default). This screen is the ONE place that opts in — via
  // ClientsQuery.read(..., includeTrial: true) — so a clinician can find and
  // reopen the trials they started. Creating one mirrors the real
  // new-assessment-case insert (same columns) but flags is_trial_case = true,
  // hard-codes engagement_type = 'assessment_only', and prefixes "TRIAL RUN"
  // into the name. It then opens the SAME assessment surface via /trial/:id.

  Future<void> _loadTrials() async {
    try {
      final rows = await ClientsQuery()
          .read('*', includeTrial: true)
          .eq('engagement_type', 'assessment_only')
          .eq('is_trial_case', true)
          .not('engagement_status', 'in', '(discharged,converted)')
          .order('updated_at', ascending: false);
      if (!mounted) return;
      setState(() => _trialCases = List<Map<String, dynamic>>.from(rows));
    } catch (_) {
      // Non-fatal — the trial section just stays as-is on a load error.
    }
  }

  Future<void> _startTrialRun() async {
    final code = await _pickClinicalArea();
    if (code == null || !mounted) return;
    final label = clinicalAreaLabel(code);
    setState(() => _creatingTrial = true);
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      final now = DateTime.now();
      final stamp = '${now.hour.toString().padLeft(2, '0')}:'
          '${now.minute.toString().padLeft(2, '0')}';
      // Mirrors NewAssessmentCaseScreen._save's column map exactly (so no
      // NOT NULL surprise), with the trial flag + marking layered on.
      final inserted = await Supabase.instance.client
          .from('clients')
          .insert({
            'name':                     'TRIAL RUN — $label · $stamp',
            'age':                      0,
            'clinical_area':            code,
            'population_type':          legacyPopulationTypeFor(code),
            'guardian_name':            '',
            'guardian_whatsapp':        '',
            'primary_language':         '',
            'primary_concern_verbatim':
                'Trial run — exploring the $label assessment surface.',
            'referral_source':          'trial-run',
            'additional_notes':
                'Trial run (exploration only). Not a real client record.',
            'total_sessions':           0,
            'clinician_id':             userId,
            'engagement_type':          'assessment_only',
            'engagement_status':        'in_assessment',
            'is_trial_case':            true,
          })
          .select('id')
          .single();
      final clientId = inserted['id'] as String;
      if (!mounted) return;
      // Opens the SAME assessment surface a real case uses, via the
      // trial-aware /trial/:id route (the includeTrial opt-in lives there).
      await Navigator.pushNamed(context, '/trial/$clientId');
      if (mounted) await _loadTrials();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not start trial run: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _creatingTrial = false);
    }
  }

  Future<String?> _pickClinicalArea() {
    final cue = CueColorsResolved.of(context);
    return showModalBottomSheet<String>(
      context: context,
      backgroundColor: cue.bgCard,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Text(
                'Pick a clinical area to explore',
                style: GoogleFonts.dmSans(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: cue.textPrimary),
              ),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final a in kClinicalAreas)
                    ListTile(
                      title: Text(
                        a.label,
                        style: GoogleFonts.dmSans(
                            fontSize: 14, color: cue.textPrimary),
                      ),
                      onTap: () => Navigator.pop(ctx, a.code),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _openTrial(Map<String, dynamic> client) async {
    final clientId = client['id']?.toString() ?? '';
    await Navigator.pushNamed(context, '/trial/$clientId');
    if (mounted) await _loadTrials();
  }

  // Delete affordances Step 3 — the RECOVERABLE delete for a real case:
  // deleted_at + deleted_by + delete_reason, then an Undo. Never for a
  // trial run (that is the permanent path below); the service refuses
  // one at two layers regardless of what surfaced this.
  Future<void> _deleteCase(Map<String, dynamic> client) async {
    final outcome =
        await deleteClientWithDialog(context: context, client: client);
    if (!mounted) return;
    switch (outcome.kind) {
      case ClientSoftDeleteOutcomeKind.cancelled:
        return;
      case ClientSoftDeleteOutcomeKind.deleted:
        final id = client['id'].toString();
        setState(() => _cases.removeWhere((r) => r['id'] == client['id']));
        showClientDeletedUndo(
          context,
          message: 'Assessment case deleted. It can be restored.',
          onUndo: () => ClientDeleteService().restore(id),
          onSettled: () {
            if (mounted) _load();
          },
        );
      case ClientSoftDeleteOutcomeKind.refusedTrial:
      case ClientSoftDeleteOutcomeKind.failed:
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(outcome.message!)));
    }
  }

  // Delete affordances Step 2 — the one irreversible action in the app.
  // Gated on is_trial_case the way _convertToTherapy gates (refuses in the
  // handler regardless of what surfaced it); the card only grows the kebab
  // for trial rows, and the service refuses again server-side. Permanent
  // copy, no Undo — see trial_run_delete_service.dart for the layering.
  Future<void> _deleteTrial(Map<String, dynamic> client) async {
    final name = (client['name'] as String?)?.trim() ?? 'this trial run';
    final outcome = await runTrialRunDelete(
      client: client,
      confirm: () => showTrialRunDeleteDialog(context: context, name: name),
      execute: (id) => TrialRunDeleteService().delete(id),
    );
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    switch (outcome.kind) {
      case TrialRunDeleteOutcomeKind.cancelled:
        return;
      case TrialRunDeleteOutcomeKind.deleted:
        setState(() =>
            _trialCases.removeWhere((r) => r['id'] == client['id']));
        messenger.showSnackBar(
          const SnackBar(content: Text('Trial run deleted.')),
        );
        await _loadTrials();
      case TrialRunDeleteOutcomeKind.refusedNotTrial:
      case TrialRunDeleteOutcomeKind.failed:
        messenger.showSnackBar(SnackBar(content: Text(outcome.message!)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final visible = _visibleCases;
    return AppLayout(
      // Title intentionally empty — the sidebar names this surface and the
      // hero below carries its identity (Clients idiom).
      title:       '',
      activeRoute: 'assessing',
      body: SafeArea(
        child: SingleChildScrollView(
          // Bottom padding clears the global CueStudyFab (52px orb pinned
          // bottom-left), which otherwise sits over the last row's name.
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 110),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _header(),
              const SizedBox(height: 24),
              if (!_loading && _error == null && _cases.isNotEmpty) ...[
                ClientsRosterSearchBar(
                  controller: _searchCtrl,
                  onNewClient: _openAdd,
                ),
                const SizedBox(height: 16),
                ClientsRosterTabs(
                  activeFilter: _filter,
                  onFilter: (v) => setState(() => _filter = v),
                  allCount: _cases.length,
                  activeCount: _inAssessmentCount,
                  // Discharged/converted cases are excluded by _load()'s
                  // query, so this tab self-hides (the widget drops
                  // zero-count tabs).
                  dischargedCount: 0,
                ),
                const SizedBox(height: 24),
              ],
              if (_loading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 32),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_error != null)
                _errorBanner()
              else if (_cases.isEmpty)
                _emptyState()
              else if (visible.isEmpty)
                _noMatchState()
              else
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < visible.length; i++) ...[
                      // onDelete (recoverable) here, never onDeleteTrial:
                      // a real case has no permanent-delete path.
                      AssessmentCaseCard(
                        client: visible[i],
                        onTap: () => _openCase(visible[i]),
                        onDelete: () => _deleteCase(visible[i]),
                      ),
                      if (i != visible.length - 1)
                        const SizedBox(height: 10),
                    ],
                  ],
                ),
              const SizedBox(height: 28),
              _trialSection(),
            ],
          ),
        ),
      ),
    );
  }

  /// One naming only: the hero. The sidebar already says "Assessing",
  /// AppLayout's title is empty, and the eyebrow + explanatory subtitle
  /// were removed (2026-08-02) — the screen announced itself four times.
  Widget _header() {
    final cue = CueColorsResolved.of(context);
    return Text(
      'Diagnostic engagements',
      style: GoogleFonts.playfairDisplay(
        fontSize:    28,
        fontWeight:  FontWeight.w400,
        fontStyle:   FontStyle.italic,
        color:       cue.textPrimary,
        height:      1.05,
      ),
    );
  }

  // Stage 2B, demoted 2026-08-02 — a quiet text affordance inside the
  // TRIAL RUNS section it belongs to, no longer a full-width bar at
  // near-equal weight to the primary "+" action. Trial runs stay
  // available in every environment (clinicians on the demo build use
  // synthetic data deliberately); only the visual weight changed.
  Widget _trialRunLink() {
    final cue = CueColorsResolved.of(context);
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        onPressed: _creatingTrial ? null : _startTrialRun,
        icon: Icon(Icons.science_outlined,
            size: 15, color: cue.textSecondary),
        label: Text(
          _creatingTrial ? 'Starting trial run…' : 'Start a trial run',
          style: GoogleFonts.dmSans(
              fontSize: 12.5,
              color: cue.textSecondary,
              fontWeight: FontWeight.w500),
        ),
        style: TextButton.styleFrom(
          foregroundColor: cue.textSecondary,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      ),
    );
  }

  // Stage 2B — the saved trial runs, walled off from "Diagnostic engagements"
  // above. This list is fed by _loadTrials() (the only includeTrial reader).
  Widget _trialSection() {
    final cue = CueColorsResolved.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'TRIAL RUNS',
          style: GoogleFonts.syne(
            fontSize:      10,
            fontWeight:    FontWeight.w600,
            color:         cue.textSecondary,
            letterSpacing: 1.6,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Practice & exploration',
          style: GoogleFonts.playfairDisplay(
            fontSize:   28,
            fontWeight: FontWeight.w400,
            fontStyle:  FontStyle.italic,
            color:      cue.textPrimary,
            height:     1.05,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'A safe space to explore an assessment surface. These are not '
          'real client records.',
          style: GoogleFonts.dmSans(
              fontSize: 13, color: cue.textSecondary, height: 1.45),
        ),
        const SizedBox(height: 8),
        _trialRunLink(),
        const SizedBox(height: 12),
        if (_trialCases.isEmpty)
          Text(
            'No trial runs yet — "Start a trial run" opens one.',
            style: GoogleFonts.dmSans(
                fontSize: 13,
                color: cue.textSecondary,
                fontStyle: FontStyle.italic),
          )
        else
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < _trialCases.length; i++) ...[
                AssessmentCaseCard(
                  client: _trialCases[i],
                  onTap: () => _openTrial(_trialCases[i]),
                  onDeleteTrial: () => _deleteTrial(_trialCases[i]),
                ),
                if (i != _trialCases.length - 1)
                  const SizedBox(height: 10),
              ],
            ],
          ),
      ],
    );
  }

  /// Cases exist, but the search box / tab filtered them all out.
  Widget _noMatchState() {
    final cue = CueColorsResolved.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Text(
        _query.isNotEmpty
            ? 'No assessment cases match "$_query".'
            : 'No cases in this view.',
        style: GoogleFonts.dmSans(
            fontSize: 13, color: cue.textSecondary),
      ),
    );
  }

  Widget _emptyState() {
    final cue = CueColorsResolved.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 24),
      decoration: BoxDecoration(
        color:        cue.bgCard,
        borderRadius: BorderRadius.circular(12),
        border:       Border.all(color: cue.border),
      ),
      child: Column(
        children: [
          Text(
            'No active assessments.',
            style: GoogleFonts.dmSans(
                fontSize: 15, color: cue.textPrimary, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 4),
          Text(
            "Tap 'New assessment case' to start one.",
            style: GoogleFonts.dmSans(fontSize: 13, color: cue.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _errorBanner() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color:        _amberSoft.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(10),
        border:       Border.all(color: _amberSoft),
      ),
      child: Text(
        'Could not load assessment cases: $_error',
        style: GoogleFonts.dmSans(fontSize: 13, color: _ink),
      ),
    );
  }
}

/// One row of either list. Public (2026-09-06) so the trial-run delete gate
/// can be tested as the widget the clinician sees, not as a predicate in
/// isolation; it still reads nothing from Supabase.
class AssessmentCaseCard extends StatelessWidget {
  final Map<String, dynamic> client;
  final VoidCallback onTap;

  /// Trial runs only. When set AND [client] is a trial run, the card grows
  /// a kebab whose single item deletes the trial run permanently. The real
  /// list never passes it, and a real row ignores it even if it were passed
  /// — the same predicate the handler and the service refuse on.
  final VoidCallback? onDeleteTrial;

  /// Real cases only: the RECOVERABLE delete (Step 3). A trial run ignores
  /// it even if passed — it only ever gets [onDeleteTrial].
  final VoidCallback? onDelete;

  const AssessmentCaseCard({
    super.key,
    required this.client,
    required this.onTap,
    this.onDeleteTrial,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final name   = (client['name'] as String?)?.trim() ?? 'Unknown';
    final area   = (client['clinical_area'] as String?) ?? '';
    final ageRaw = client['age'];
    final age    = ageRaw is int
        ? ageRaw
        : (ageRaw is String ? int.tryParse(ageRaw) : null);
    // Triage line — the referrer's own words. Already loaded by the
    // screen's read('*'); no extra query.
    final concern =
        (client['primary_concern_verbatim'] as String?)?.trim() ?? '';
    // Last touched — updated_at is already selected AND already the sort
    // key, so this costs nothing.
    final touchedRaw = client['updated_at'];
    final touched = touchedRaw is String ? DateTime.tryParse(touchedRaw) : null;
    final cue = CueColorsResolved.of(context);

    // Two callbacks, one kebab, never the same item for both kinds of row:
    // a trial run only ever gets the permanent delete, a real case only
    // ever gets the recoverable one. The other callback is ignored.
    final trial = isTrialRun(client);
    final VoidCallback? menuAction = trial ? onDeleteTrial : onDelete;
    final menuLabel = trial ? 'Delete permanently' : 'Delete';

    // clinical area · age · touched — the meta line under the concern.
    final meta = <String>[
      if (area.isNotEmpty) clinicalAreaLabel(area),
      if (age != null && age > 0) 'age $age',
      if (touched != null) 'touched ${cueRelativeDayLabel(touched)}',
    ].join('  ·  ');

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          decoration: BoxDecoration(
            color:        cue.bgCard,
            borderRadius: BorderRadius.circular(12),
            border:       Border.all(color: cue.border),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: GoogleFonts.dmSans(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: cue.textPrimary),
                    ),
                    if (concern.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        concern,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.dmSans(
                            fontSize: 13,
                            height: 1.35,
                            color: cue.textPrimary.withValues(alpha: 0.78)),
                      ),
                    ],
                    if (meta.isNotEmpty) ...[
                      const SizedBox(height: 5),
                      Text(
                        meta,
                        style: GoogleFonts.dmSans(
                            fontSize: 12, color: cue.textSecondary),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (menuAction != null)
                SizedBox(
                  width: 28,
                  height: 28,
                  child: PopupMenuButton<String>(
                    tooltip: 'More',
                    iconSize: 18,
                    padding: EdgeInsets.zero,
                    icon: Icon(Icons.more_horiz,
                        size: 18, color: cue.textSecondary),
                    onSelected: (value) {
                      if (value == 'delete') menuAction();
                    },
                    itemBuilder: (_) => [
                      PopupMenuItem<String>(
                        value: 'delete',
                        child: Text(
                          menuLabel,
                          style: TextStyle(color: cue.coral),
                        ),
                      ),
                    ],
                  ),
                ),
              Icon(Icons.chevron_right_rounded,
                  color: cue.textSecondary.withValues(alpha: 0.7)),
            ],
          ),
        ),
      ),
    );
  }

}
