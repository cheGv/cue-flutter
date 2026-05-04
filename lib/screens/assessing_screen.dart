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
import '../widgets/app_layout.dart';
import 'add_client_screen.dart';
import 'assessment_case_screen.dart';

const Color _ink       = Color(0xFF0E1C36);
const Color _inkGhost  = Color(0xFF6B7690);
const Color _paper     = Color(0xFFFAF6EE);
const Color _amber     = Color(0xFFD68A2B);
const Color _amberSoft = Color(0xFFF4E4C4);
const Color _line      = Color(0xFFE6DDCA);

class AssessingScreen extends StatefulWidget {
  const AssessingScreen({super.key});

  @override
  State<AssessingScreen> createState() => _AssessingScreenState();
}

class _AssessingScreenState extends State<AssessingScreen> {
  final _supabase = Supabase.instance.client;

  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _cases = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error   = null;
    });
    try {
      final rows = await _supabase
          .from('clients')
          .select()
          .eq('engagement_type', 'assessment_only')
          .isFilter('deleted_at', null)
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
    final added = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) =>
            const AddClientScreen(engagementType: 'assessment_only'),
      ),
    );
    if (added == true || mounted) await _load();
  }

  Future<void> _openCase(Map<String, dynamic> client) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AssessmentCaseScreen(client: client),
      ),
    );
    if (mounted) await _load();
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
            ],
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
          'ASSESSMENT CASES',
          style: GoogleFonts.syne(
            fontSize:      10,
            fontWeight:    FontWeight.w600,
            color:         _amber,
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
            color:       _ink,
            height:      1.05,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Cases here run on the assessment workflow until you '
          'discharge them or convert to therapy.',
          style: GoogleFonts.dmSans(
              fontSize: 13, color: _inkGhost, height: 1.45),
        ),
      ],
    );
  }

  Widget _addButton() {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: _openAdd,
        icon: const Icon(Icons.add_rounded, size: 18, color: _amber),
        label: Text(
          'Add new assessment case',
          style: GoogleFonts.dmSans(
              fontSize: 14, color: _amber, fontWeight: FontWeight.w500),
        ),
        style: OutlinedButton.styleFrom(
          foregroundColor: _amber,
          side: BorderSide(color: _amber.withValues(alpha: 0.45)),
          padding: const EdgeInsets.symmetric(vertical: 12),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10)),
        ),
      ),
    );
  }

  Widget _emptyState() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 24),
      decoration: BoxDecoration(
        color:        _paper,
        borderRadius: BorderRadius.circular(12),
        border:       Border.all(color: _line),
      ),
      child: Column(
        children: [
          Text(
            'No active assessments.',
            style: GoogleFonts.dmSans(
                fontSize: 15, color: _ink, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 4),
          Text(
            "Tap 'Add new assessment case' to start one.",
            style: GoogleFonts.dmSans(fontSize: 13, color: _inkGhost),
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

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          decoration: BoxDecoration(
            color:        Colors.white,
            borderRadius: BorderRadius.circular(12),
            border:       Border.all(color: _line),
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
                          color: _ink),
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        if (area.isNotEmpty)
                          _badge(clinicalAreaLabel(area), color: _amber),
                        _badge(_humanStatus(status), color: _inkGhost),
                        if (age != null && age > 0)
                          _badge('age $age', color: _inkGhost),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.chevron_right_rounded,
                  color: _inkGhost.withValues(alpha: 0.7)),
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
      case 'in_progress':      return 'in progress';
      case 'report_pending':   return 'report pending';
      case 'report_delivered': return 'report delivered';
      case 'converted':        return 'converted to therapy';
      case 'discharged':       return 'discharged';
      default:                 return code.replaceAll('_', ' ');
    }
  }
}
