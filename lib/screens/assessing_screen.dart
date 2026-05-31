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
import '../theme/cue_color_scheme.dart';
import '../widgets/app_layout.dart';
import '../services/clients_query.dart';
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

  @override
  void initState() {
    super.initState();
    _load();
    _loadTrials();
  }

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

  @override
  Widget build(BuildContext context) {
    return AppLayout(
      title:       'Assessing',
      activeRoute: 'assessing',
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 60),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _header(),
              const SizedBox(height: 20),
              _addButton(),
              const SizedBox(height: 10),
              _trialRunButton(),
              const SizedBox(height: 28),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 32),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_error != null)
                _errorBanner()
              else if (_cases.isEmpty)
                _emptyState()
              else
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < _cases.length; i++) ...[
                      _AssessmentCaseCard(
                        client: _cases[i],
                        onTap: () => _openCase(_cases[i]),
                      ),
                      if (i != _cases.length - 1)
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

  Widget _header() {
    final cue = CueColorsResolved.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'ASSESSMENT CASES',
          style: GoogleFonts.syne(
            fontSize:      10,
            fontWeight:    FontWeight.w600,
            color:         cue.amber,
            letterSpacing: 1.6,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Diagnostic engagements',
          style: GoogleFonts.playfairDisplay(
            fontSize:    28,
            fontWeight:  FontWeight.w400,
            fontStyle:   FontStyle.italic,
            color:       cue.textPrimary,
            height:      1.05,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Cases here run on the assessment workflow until you '
          'discharge them or convert to therapy.',
          style: GoogleFonts.dmSans(
              fontSize: 13, color: cue.textSecondary, height: 1.45),
        ),
      ],
    );
  }

  Widget _addButton() {
    final cue = CueColorsResolved.of(context);
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: _openAdd,
        icon: Icon(Icons.add_rounded, size: 18, color: cue.amber),
        label: Text(
          'New assessment case',
          style: GoogleFonts.dmSans(
              fontSize: 14, color: cue.amber, fontWeight: FontWeight.w500),
        ),
        style: OutlinedButton.styleFrom(
          foregroundColor: cue.amber,
          side: BorderSide(color: cue.amber.withValues(alpha: 0.45)),
          padding: const EdgeInsets.symmetric(vertical: 12),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10)),
        ),
      ),
    );
  }

  // Stage 2B — secondary, visually-muted CTA (distinct from the amber primary
  // "New assessment case"). Opens an area picker, then creates + opens a trial.
  Widget _trialRunButton() {
    final cue = CueColorsResolved.of(context);
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: _creatingTrial ? null : _startTrialRun,
        icon: Icon(Icons.science_outlined,
            size: 18, color: cue.textSecondary),
        label: Text(
          _creatingTrial ? 'Starting trial run…' : 'Start a trial run',
          style: GoogleFonts.dmSans(
              fontSize: 14,
              color: cue.textSecondary,
              fontWeight: FontWeight.w500),
        ),
        style: OutlinedButton.styleFrom(
          foregroundColor: cue.textSecondary,
          side: BorderSide(color: cue.border),
          padding: const EdgeInsets.symmetric(vertical: 12),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10)),
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
        const SizedBox(height: 16),
        if (_trialCases.isEmpty)
          Text(
            'No trial runs yet — tap "Start a trial run" above to explore one.',
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
                _AssessmentCaseCard(
                  client: _trialCases[i],
                  onTap: () => _openTrial(_trialCases[i]),
                ),
                if (i != _trialCases.length - 1)
                  const SizedBox(height: 10),
              ],
            ],
          ),
      ],
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

class _AssessmentCaseCard extends StatelessWidget {
  final Map<String, dynamic> client;
  final VoidCallback onTap;

  const _AssessmentCaseCard({required this.client, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final name   = (client['name'] as String?)?.trim() ?? 'Unknown';
    final area   = (client['clinical_area'] as String?) ?? '';
    final status =
        (client['engagement_status'] as String?) ?? 'awaiting_intake';
    final ageRaw = client['age'];
    final age    = ageRaw is int
        ? ageRaw
        : (ageRaw is String ? int.tryParse(ageRaw) : null);
    final cue = CueColorsResolved.of(context);

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
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        if (area.isNotEmpty)
                          _badge(clinicalAreaLabel(area), color: cue.amber),
                        _badge(_humanStatus(status), color: cue.textSecondary),
                        if (age != null && age > 0)
                          _badge('age $age', color: cue.textSecondary),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.chevron_right_rounded,
                  color: cue.textSecondary.withValues(alpha: 0.7)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _badge(String text, {required Color color}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color:        color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: GoogleFonts.dmSans(
            fontSize: 11, color: color, fontWeight: FontWeight.w500),
      ),
    );
  }

  String _humanStatus(String code) {
    switch (code) {
      case 'awaiting_intake':  return 'awaiting intake';
      case 'in_assessment':    return 'in assessment';
      case 'in_progress':      return 'in progress';
      case 'report_pending':   return 'report pending';
      case 'report_delivered': return 'report delivered';
      case 'converted':        return 'converted to therapy';
      case 'discharged':       return 'discharged';
      default:                 return code.replaceAll('_', ' ');
    }
  }
}
