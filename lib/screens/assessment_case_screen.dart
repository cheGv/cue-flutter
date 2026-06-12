// lib/screens/assessment_case_screen.dart
//
// Phase 4.0.7.24 — assessment case workflow surface. Opens when the
// SLP taps a card on AssessingScreen. Renders client header + visit
// timeline + collapsible body sections (case history, captures,
// diagnostic synthesis, report composer) + footer affordances
// ("Mark assessment complete" / "Convert to therapy").
//
// V1 is intentionally rough scaffolding. Clinical instrument content
// inside the capture sections lands in 4.0.7.24a (voice) / 24b (SSD)
// / 24c (other 12 areas). Diagnostic synthesis is a textarea + codes
// field with no AI; the SLP makes the diagnostic call. Report
// composer is a button that creates an assessment_reports row in
// 'draft' status — full template surface lands in 4.0.7.24d.

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../constants/clinical_areas.dart';
import '../models/format_template.dart';
import '../repositories/format_templates_repository.dart';
import '../services/cas_assessment_service.dart';
import '../services/feeding_assessment_service.dart';
import '../services/format_drafter_service.dart';
import '../services/voice_assessment_service.dart';
import '../theme/cue_color_scheme.dart';
import '../widgets/app_layout.dart';
import '../widgets/assessment/ald_capture_section.dart';
import '../widgets/assessment/cas_assessment_surface.dart';
import '../widgets/assessment/feeding_assessment_surface.dart';
import '../widgets/assessment/ped_dysarthria_capture_section.dart';
import '../widgets/assessment/ssd_capture_section.dart';
import '../widgets/assessment/voice_capture_section.dart';
import '../widgets/trial_run_banner.dart';

const Color _ink        = Color(0xFF0E1C36);
const Color _inkGhost   = Color(0xFF6B7690);
const Color _paper      = Color(0xFFFAF6EE);
const Color _amber      = Color(0xFFD68A2B);
const Color _amberSoft  = Color(0xFFF4E4C4);
const Color _teal       = Color(0xFF2A8F84);
const Color _tealSoft   = Color(0xFFD6E8E5);
const Color _line       = Color(0xFFE6DDCA);
const Color _coral      = Color(0xFFC25450);

class AssessmentCaseScreen extends StatefulWidget {
  final Map<String, dynamic> client;
  const AssessmentCaseScreen({super.key, required this.client});

  @override
  State<AssessmentCaseScreen> createState() => _AssessmentCaseScreenState();
}

class _AssessmentCaseScreenState extends State<AssessmentCaseScreen> {
  final _supabase = Supabase.instance.client;

  late Map<String, dynamic> _client;
  List<Map<String, dynamic>> _visits = [];
  bool _loadingVisits = true;

  // V1 diagnostic synthesis — pure text fields, no AI. SLP attests.
  final _diagnosisCtrl = TextEditingController();
  final _diagCodesCtrl = TextEditingController();

  // Step 3 (Piece 2) — "Draft in my format". protocol == clinical_area. Only
  // these areas have an assessment reader wired today, so only they can produce
  // a grounded draft; other areas show a "not available yet" message.
  static const _draftableProtocols = {'voice', 'pediatric-cas'};
  bool _drafting = false;

  @override
  void initState() {
    super.initState();
    _client = Map<String, dynamic>.from(widget.client);
    _loadVisits();
  }

  @override
  void dispose() {
    _diagnosisCtrl.dispose();
    _diagCodesCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadVisits() async {
    try {
      final rows = await _supabase
          .from('assessment_visits')
          .select()
          .eq('client_id', _client['id'].toString())
          .order('visit_number', ascending: true);
      if (!mounted) return;
      setState(() {
        _visits = List<Map<String, dynamic>>.from(rows);
        _loadingVisits = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingVisits = false);
    }
  }

  /// Phase 4.0.7.24a-fix8 — domain-aware gate on parent-present
  /// expectations. Pediatric clinical areas keep parent_present = true
  /// as the sensible default (parent typically attends a child's
  /// assessment); adult areas write parent_present = false on insert.
  /// The visit form has no toggle UI today — there's only a single-tap
  /// "Add visit" card — so this gate runs at insert time. When the
  /// per-visit detail form ships (4.0.7.24c+), expose the toggle only
  /// when this returns true.
  bool _isPediatricAssessment() {
    final area = _client['clinical_area'] as String?;
    if (area == null) return false;
    const pediatric = {
      'pediatric-language',
      'autism-developmental',
      'speech-sound-disorders',
      'pediatric-motor-speech',
      'literacy',
    };
    return pediatric.contains(area);
  }

  Future<void> _addVisit() async {
    try {
      final next = (_visits.isNotEmpty
              ? (_visits.last['visit_number'] as num?)?.toInt() ?? _visits.length
              : 0) +
          1;
      // 4.0.7.24a-fix8 — column is 'visit_date' (Postgres DATE,
      // yyyy-MM-dd), not 'date'. parent_present routes through the
      // pediatric gate; primary_capture_focus stays null until the
      // per-visit form lands.
      await _supabase.from('assessment_visits').insert({
        'client_id':             _client['id'].toString(),
        'visit_number':          next,
        'visit_date':            DateTime.now().toIso8601String().substring(0, 10),
        'visit_status':          'in_progress',
        'parent_present':        _isPediatricAssessment(),
        'primary_capture_focus': null,
      });
      await _loadVisits();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Visit $next added.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not add visit: $e')),
        );
      }
    }
  }

  Future<void> _markComplete() async {
    try {
      await _supabase.from('clients').update({
        'engagement_status': 'report_pending',
      }).eq('id', _client['id']);
      setState(() => _client['engagement_status'] = 'report_pending');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Assessment marked complete — report pending.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not mark complete: $e')),
        );
      }
    }
  }

  Future<void> _convertToTherapy() async {
    // Phase 4.0.7.29 Stage 2A — SAFETY WALL #2: a trial case must NEVER cross
    // into the real therapy world. There is no trial->real path; refuse here
    // regardless of any UI affordance that surfaced this action. (The flag is
    // never cleared — real cases are created fresh, not promoted from trials.)
    if (_client['is_trial_case'] == true) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Trial runs cannot be converted to a real client. '
                'Create a real case from scratch instead.'),
          ),
        );
      }
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Convert to therapy?'),
        content: const Text(
            "This client moves to the Clients sidebar. Their assessment "
            'history stays linked to the record.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Convert')),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await _supabase.from('clients').update({
        'engagement_type':              'therapy',
        'engagement_status':            'converted',
        'converted_from_assessment_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', _client['id']);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Converted to therapy.')),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not convert: $e')),
        );
      }
    }
  }

  /// Step 3 (Piece 2) — "Draft in my format". Replaces the V1 stub that wrote a
  /// bare assessment_reports row (removed — nothing read it). Real flow: pick a
  /// confirmed format -> requestAssessmentDraft (the proxy builds the grounded
  /// draft from this client's structured assessment data) -> open it in the
  /// editable surface (Piece 3, verified). App code only; no proxy/DB changes.
  Future<void> _draftInMyFormat() async {
    final clientId = _client['id'].toString();
    final protocol = (_client['clinical_area'] as String?) ?? '';

    // Guard: only voice + pediatric-cas have assessment readers today. Other
    // areas (dysarthria / ALD / SSD / …) can't be drafted yet — say so plainly
    // rather than crash or call the drafter with no reader behind it.
    if (!_draftableProtocols.contains(protocol)) {
      _toast("Report drafting isn't available for this assessment type yet.");
      return;
    }

    final template = await _pickFormat();
    if (template == null) return; // cancelled, or no confirmed formats

    if (!mounted) return;
    setState(() => _drafting = true);
    try {
      final assessmentId = await _resolveAssessmentId(protocol, clientId);
      if (assessmentId == null) {
        _toast("Report drafting isn't available for this assessment type yet.");
        return;
      }
      final draft = await FormatDrafterService().requestAssessmentDraft(
        templateId: template.id,
        clientId: clientId,
        protocol: protocol,
        assessmentId: assessmentId,
      );
      if (!mounted) return;
      // The editable surface in LOAD mode — the proven Piece 3 render path.
      Navigator.of(context)
          .pushNamed('/clients/$clientId/draft-report/view/${draft.id}');
    } catch (e) {
      if (mounted) _toast('Could not draft the report: $e');
    } finally {
      if (mounted) setState(() => _drafting = false);
    }
  }

  /// Modal bottom sheet of the clinician's CONFIRMED formats (same source as the
  /// therapy initiate screen). Returns the chosen template, or null if she
  /// cancels / has no confirmed formats. No date range — assessments are
  /// point-in-time.
  Future<FormatTemplate?> _pickFormat() async {
    List<FormatTemplate> formats;
    try {
      formats = (await FormatTemplatesRepository().listForUser())
          .where((t) => t.isConfirmed)
          .toList();
    } catch (e) {
      if (mounted) _toast('Could not load your formats: $e');
      return null;
    }
    if (!mounted) return null;
    if (formats.isEmpty) {
      _toast('Add and confirm a report format first, then draft this report.');
      return null;
    }
    return showModalBottomSheet<FormatTemplate>(
      context: context,
      backgroundColor: _paper,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 6),
              child: Text('DRAFT IN THIS FORMAT',
                  style: GoogleFonts.syne(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: _inkGhost,
                      letterSpacing: 1.6)),
            ),
            for (final t in formats)
              ListTile(
                leading:
                    const Icon(Icons.description_outlined, size: 18, color: _teal),
                title: Text(
                  t.name.trim().isEmpty ? 'Untitled format' : t.name,
                  style: GoogleFonts.dmSans(
                      fontSize: 14, color: _ink, fontWeight: FontWeight.w500),
                ),
                onTap: () => Navigator.pop(ctx, t),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  /// Resolves the assessment-row id for this client under its protocol, reusing
  /// the same service the capture surface uses. Returns null for protocols with
  /// no reader. By report time the row exists (she's filled the capture
  /// surface), so loadOrCreate loads it rather than creating an empty one.
  Future<String?> _resolveAssessmentId(String protocol, String clientId) async {
    switch (protocol) {
      case 'voice':
        final a = await VoiceAssessmentService.instance
            .loadOrCreate(clientId: clientId);
        return a.id;
      case 'pediatric-cas':
        final a = await CasAssessmentService.instance
            .loadOrCreate(clientId: clientId);
        return a['id'] as String?;
      // 'pediatric-feeding' — identity: the area slug IS the reader protocol.
      // Reachable from the UI only once 'pediatric-feeding' joins
      // _draftableProtocols (the flip — the LAST graduation step); until
      // then the guard above toasts not-available and this case is dormant.
      case 'pediatric-feeding':
        final a = await FeedingAssessmentService.instance
            .loadOrCreate(clientId: clientId);
        return a['id'] as String?;
      default:
        return null;
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final clientId = _client['id'].toString();
    final area     = _client['clinical_area'] as String? ?? '';
    return AppLayout(
      title:       'Assessment — ${_client['name'] ?? 'Case'}',
      activeRoute: 'assessing',
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 80),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Stage 2B — persistent trial-run marking on the assessment
              // surface. Quiet register by default; flip to
              // TrialRunBanner(loud: true) to escalate. The case name also
              // carries a "TRIAL RUN" prefix and the header eyebrow flips below.
              if (_client['is_trial_case'] == true) ...[
                const TrialRunBanner(),
                const SizedBox(height: 16),
              ],
              _clientHeader(),
              const SizedBox(height: 20),
              _visitTimeline(),
              const SizedBox(height: 24),
              _section(
                title: 'CAPTURES',
                child: _captureForArea(area, clientId),
              ),
              const SizedBox(height: 20),
              _section(
                title: 'DIAGNOSTIC SYNTHESIS',
                child: _diagnosticSynthesis(),
              ),
              const SizedBox(height: 20),
              _section(
                title: 'REPORT COMPOSER',
                child: _reportComposer(),
              ),
              const SizedBox(height: 28),
              _footerAffordances(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _clientHeader() {
    final name   = _client['name'] as String? ?? 'Unknown';
    final area   = _client['clinical_area'] as String? ?? '';
    final status =
        _client['engagement_status'] as String? ?? 'awaiting_intake';
    final ageRaw = _client['age'];
    final age    = ageRaw is int
        ? ageRaw
        : (ageRaw is String ? int.tryParse(ageRaw) : null);
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      decoration: BoxDecoration(
        color:        _paper,
        borderRadius: BorderRadius.circular(12),
        border:       Border.all(color: _line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_client['is_trial_case'] == true ? 'TRIAL RUN' : 'ASSESSMENT CASE',
              style: GoogleFonts.syne(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: _amber,
                  letterSpacing: 1.6)),
          const SizedBox(height: 4),
          Text(name,
              style: GoogleFonts.playfairDisplay(
                  fontSize: 24,
                  fontWeight: FontWeight.w400,
                  fontStyle: FontStyle.italic,
                  color: _ink,
                  height: 1.05)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              if (area.isNotEmpty) _badge(clinicalAreaLabel(area), _amber),
              _badge(_humanStatus(status), _inkGhost),
              if (age != null && age > 0) _badge('age $age', _inkGhost),
            ],
          ),
        ],
      ),
    );
  }

  Widget _visitTimeline() {
    if (_loadingVisits) {
      return const SizedBox(
          height: 80, child: Center(child: CircularProgressIndicator()));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('VISIT TIMELINE',
            style: GoogleFonts.syne(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: _inkGhost,
                letterSpacing: 1.6)),
        const SizedBox(height: 10),
        SizedBox(
          height: 96,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              for (final v in _visits) ...[
                _visitCard(v),
                const SizedBox(width: 8),
              ],
              _addVisitCard(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _visitCard(Map<String, dynamic> v) {
    final n        = (v['visit_number'] as num?)?.toInt() ?? 0;
    final date     = (v['visit_date'] as String?) ?? '';
    final duration =
        (v['visit_duration_minutes'] as num?)?.toInt();
    final status   = (v['visit_status'] as String?) ?? 'in_progress';
    final cue      = CueColorsResolved.of(context);
    return Container(
      width: 150,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        // Phase 5.3 Round A.1.1 — fixed visible white-on-dark bug.
        color:        cue.bgCard,
        borderRadius: BorderRadius.circular(10),
        border:       Border.all(color: _line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Visit $n',
              style: GoogleFonts.dmSans(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: _ink)),
          const SizedBox(height: 4),
          Text(date,
              style: GoogleFonts.dmSans(
                  fontSize: 11, color: _inkGhost)),
          if (duration != null) ...[
            const SizedBox(height: 2),
            Text('$duration min',
                style: GoogleFonts.dmSans(
                    fontSize: 11, color: _inkGhost)),
          ],
          const Spacer(),
          _badge(status.replaceAll('_', ' '), _teal),
        ],
      ),
    );
  }

  Widget _addVisitCard() {
    return GestureDetector(
      onTap: _addVisit,
      child: Container(
        width: 130,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color:        _amberSoft.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(10),
          border:       Border.all(color: _amber.withValues(alpha: 0.55)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.add_rounded, color: _amber, size: 22),
            const SizedBox(height: 6),
            Text('Add visit',
                style: GoogleFonts.dmSans(
                    fontSize: 12,
                    color: _amber,
                    fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }

  Widget _section({required String title, required Widget child}) {
    final cue = CueColorsResolved.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        // Phase 5.3 Round A.1.1 — fixed visible white-on-dark bug
        // (CAPTURES + DIAGNOSTIC SYNTHESIS cards bleeding white on dark).
        color:        cue.bgCard,
        borderRadius: BorderRadius.circular(12),
        border:       Border.all(color: _line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: GoogleFonts.syne(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: _inkGhost,
                  letterSpacing: 1.6)),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  /// Phase 4.0.7.24 — capture surface routes by clinical_area. Voice
  /// and SSD have stub widgets shipped this commit; the other 12
  /// areas show a "coming soon" placeholder until 4.0.7.24c onward.
  Widget _captureForArea(String area, String clientId) {
    if (area == 'voice') return VoiceCaptureSection(clientId: clientId);
    if (area == 'speech-sound-disorders') {
      return SsdCaptureSection(clientId: clientId);
    }
    // 4.0.7.25a — Adult Language & Cognitive surface lands here.
    if (area == 'adult-language-cognitive') {
      return AldCaptureSection(clientId: clientId);
    }
    // 4.0.7.27a — Pediatric Dysarthria surface.
    if (area == 'pediatric-dysarthria') {
      return PedDysarthriaCaptureSection(clientId: clientId);
    }
    // 4.0.7.28 — Pediatric CAS surface (dysarthria's closest differential).
    if (area == 'pediatric-cas') {
      return CasAssessmentSurface(clientId: clientId);
    }
    // Childhood Feeding — Phase 1 capture (2026-06-11). Feeding-SKILLS scope;
    // the onOpenSwallow seam stays dormant (the surface renders its off-ramp
    // as caution text only) until the swallow surface ships and a host route
    // exists to wire here — the SSD↔CAS handoff pattern, held in reserve.
    if (area == 'pediatric-feeding') {
      return FeedingAssessmentSurface(clientId: clientId);
    }
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color:        _tealSoft.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        area.isEmpty
            ? 'No clinical area set — pick one to load the capture surface.'
            : 'Capture surface coming for ${clinicalAreaLabel(area)}.',
        style: GoogleFonts.dmSans(
            fontSize: 13, color: _inkGhost, fontStyle: FontStyle.italic),
      ),
    );
  }

  Widget _diagnosticSynthesis() {
    // NOTE (Step 3, Piece 2): these diagnosis / diag-codes fields are no longer
    // persisted — their only prior save was the removed assessment_reports stub.
    // The format draft is built from structured assessment data, not these text
    // boxes, so they are intentionally inert for now. Wire their own save as a
    // separate task if diagnosis capture is needed here.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _diagnosisCtrl,
          maxLines: 4,
          style: GoogleFonts.dmSans(fontSize: 13, color: _ink),
          decoration: const InputDecoration(
            labelText: 'Diagnostic statement',
            border: OutlineInputBorder(),
            isDense: true,
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _diagCodesCtrl,
          style: GoogleFonts.dmSans(fontSize: 13, color: _ink),
          decoration: const InputDecoration(
            labelText: 'Diagnostic codes (ICD-11 / DSM)',
            hintText: 'e.g. 6A01.20, 6A02',
            border: OutlineInputBorder(),
            isDense: true,
          ),
        ),
      ],
    );
  }

  Widget _reportComposer() {
    // Generating state — the LLM round-trip takes ~30-60s. Visible, and it
    // replaces the button so a second tap can't fire mid-draft.
    if (_drafting) {
      return Row(
        children: [
          const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2, color: _teal),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Drafting your report in your format… (~30–60 seconds)',
              style: GoogleFonts.dmSans(
                  fontSize: 13, color: _ink, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: _draftInMyFormat,
            icon: const Icon(Icons.auto_awesome, size: 16, color: _teal),
            label: Text('Draft in my format',
                style: GoogleFonts.dmSans(
                    fontSize: 13,
                    color: _teal,
                    fontWeight: FontWeight.w500)),
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: _teal.withValues(alpha: 0.45)),
              padding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 8),
            ),
          ),
        ),
      ],
    );
  }

  Widget _footerAffordances() {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        OutlinedButton.icon(
          onPressed: _markComplete,
          icon: const Icon(Icons.check_circle_outline_rounded,
              size: 16, color: _teal),
          label: Text('Mark assessment complete',
              style: GoogleFonts.dmSans(
                  fontSize: 13,
                  color: _teal,
                  fontWeight: FontWeight.w500)),
          style: OutlinedButton.styleFrom(
            side: BorderSide(color: _teal.withValues(alpha: 0.45)),
            padding: const EdgeInsets.symmetric(
                horizontal: 14, vertical: 10),
          ),
        ),
        // Phase 4.0.7.29 Stage 2A: hide convert-to-therapy for trial runs
        // (safety wall #2 — no trial->real path). _convertToTherapy also
        // refuses defensively if ever invoked.
        if (_client['is_trial_case'] != true)
          OutlinedButton.icon(
            onPressed: _convertToTherapy,
            icon: const Icon(Icons.swap_horiz_rounded,
                size: 16, color: _coral),
            label: Text('Convert to therapy',
                style: GoogleFonts.dmSans(
                    fontSize: 13,
                    color: _coral,
                    fontWeight: FontWeight.w500)),
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: _coral.withValues(alpha: 0.45)),
              padding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 10),
            ),
          ),
      ],
    );
  }

  Widget _badge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color:        color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(text,
          style: GoogleFonts.dmSans(
              fontSize: 11,
              color: color,
              fontWeight: FontWeight.w500)),
    );
  }

  String _humanStatus(String code) {
    switch (code) {
      case 'awaiting_intake':  return 'awaiting intake';
      case 'in_progress':      return 'in progress';
      case 'report_pending':   return 'report pending';
      case 'report_delivered': return 'report delivered';
      case 'converted':        return 'converted to therapy';
      case 'discharged':       return 'discharged';
      default:                 return code.replaceAll('_', ' ');
    }
  }
}
