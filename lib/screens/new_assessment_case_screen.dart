// lib/screens/new_assessment_case_screen.dart
//
// Phase 4.0.7.27c-split — slim assessment-case intake. Distinct from
// the heavyweight therapy intake (AddClientScreen) because the SLP
// needs to start a diagnostic engagement quickly; the full case
// history is captured in Section 1 of the assessment surface, not
// here. ~10 fields, no language list builder, no developmental
// milestones, no comm profile.
//
// Entry points:
//   - AssessingScreen "+ New assessment case" CTA
//   - Named route '/new-assessment' (registered in main.dart)
//
// On submit:
//   - INSERT a clients row with engagement_type='assessment_only',
//     engagement_status='in_assessment', clinical_area=<picked>.
//   - Optional metadata (referral source, visit date, fee,
//     deliverables) stashes onto additional_notes as a small
//     structured chunk for V1; column-ifies in a future migration
//     once the assessment_engagements surface is authored.
//   - Push the named route '/assessing/:clientId' so the SLP lands
//     directly in the appropriate capture surface (voice / ALD /
//     pediatric-dysarthria / SSD).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../constants/clinical_areas.dart';
import '../widgets/app_layout.dart';

const Color _ink       = Color(0xFF0E1C36);
const Color _inkGhost  = Color(0xFF6B7690);
const Color _paper     = Color(0xFFFAF6EE);
const Color _amber     = Color(0xFFD68A2B);
const Color _amberSoft = Color(0xFFF4E4C4);
const Color _line      = Color(0xFFE6DDCA);

class NewAssessmentCaseScreen extends StatefulWidget {
  const NewAssessmentCaseScreen({super.key});

  @override
  State<NewAssessmentCaseScreen> createState() =>
      _NewAssessmentCaseScreenState();
}

class _NewAssessmentCaseScreenState extends State<NewAssessmentCaseScreen> {
  final _supabase = Supabase.instance.client;

  final _nameCtrl     = TextEditingController();
  final _ageCtrl      = TextEditingController();
  final _caregiverNameCtrl = TextEditingController();
  final _caregiverWaCtrl   = TextEditingController();
  final _languageCtrl      = TextEditingController();
  final _concernCtrl       = TextEditingController();
  final _feeCtrl           = TextEditingController();

  String? _clinicalArea;
  String? _referralSource;
  DateTime _visitDate = DateTime.now();
  final Set<String> _deliverables = {};

  bool _saving = false;

  static const _kReferralSources = [
    'Self-referred',
    'Pediatrician',
    'ENT',
    'Neurologist',
    'School',
    'Family member',
    'Another SLP',
    'Other',
  ];

  static const _kDeliverables = [
    'Diagnostic report',
    'Therapy recommendation',
    'Insurance documentation',
    'School documentation',
    'Second opinion',
  ];

  @override
  void dispose() {
    _nameCtrl.dispose();
    _ageCtrl.dispose();
    _caregiverNameCtrl.dispose();
    _caregiverWaCtrl.dispose();
    _languageCtrl.dispose();
    _concernCtrl.dispose();
    _feeCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickVisitDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _visitDate,
      firstDate:   now.subtract(const Duration(days: 365)),
      lastDate:    now.add(const Duration(days: 90)),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.light(
            primary: _amber,
            onPrimary: Colors.white,
            surface: Colors.white,
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) setState(() => _visitDate = picked);
  }

  Future<void> _save() async {
    final name    = _nameCtrl.text.trim();
    final ageText = _ageCtrl.text.trim();
    final concern = _concernCtrl.text.trim();

    if (name.isEmpty) return _toast('Client name is required');
    if (ageText.isEmpty) return _toast('Age is required');
    if (_clinicalArea == null || _clinicalArea!.isEmpty) {
      return _toast('Pick a clinical area');
    }
    if (concern.isEmpty) return _toast('Chief concern is required');

    setState(() => _saving = true);
    try {
      // Build a small structured note for V1 — assessment fee +
      // deliverables + referral source + visit date land here until
      // the assessment_engagements surface lands.
      final notesParts = <String>[];
      notesParts.add(
          'Visit date: ${_visitDate.toIso8601String().substring(0, 10)}');
      if (_referralSource != null && _referralSource!.isNotEmpty) {
        notesParts.add('Referral: $_referralSource');
      }
      final fee = _feeCtrl.text.trim();
      if (fee.isNotEmpty) {
        notesParts.add('Assessment fee agreed: ₹$fee');
      }
      if (_deliverables.isNotEmpty) {
        notesParts.add('Deliverables: ${_deliverables.join(', ')}');
      }

      final userId = _supabase.auth.currentUser?.id;
      // Phase 4.0.7.27c-split — assessment cases land with
      // engagement_type='assessment_only' and engagement_status
      // ='in_assessment'. Conversion to therapy uses the existing
      // engagement_status='converted' flow on AssessmentCaseScreen.
      final inserted = await _supabase
          .from('clients')
          .insert({
            'name':                       name,
            'age':                        int.tryParse(ageText) ?? 0,
            'clinical_area':              _clinicalArea,
            'population_type':
                legacyPopulationTypeFor(_clinicalArea!),
            'guardian_name':              _caregiverNameCtrl.text.trim(),
            'guardian_whatsapp':          _caregiverWaCtrl.text.trim(),
            'primary_language':           _languageCtrl.text.trim(),
            'primary_concern_verbatim':   concern,
            'referral_source':            _referralSource ?? '',
            'additional_notes':           notesParts.join(' · '),
            'total_sessions':             0,
            'clinician_id':               userId,
            'engagement_type':            'assessment_only',
            'engagement_status':          'in_assessment',
          })
          .select('id')
          .single();
      final clientId = inserted['id'] as String;

      if (!mounted) return;
      // Land directly in the assessment capture surface. The deep-link
      // route resolves to the right area-specific capture section.
      await Navigator.pushReplacementNamed(
          context, '/assessing/$clientId');
    } catch (e) {
      _toast('Could not create assessment case: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return AppLayout(
      title:       'New assessment case',
      activeRoute: 'assessing',
      body: Container(
        color: _paper,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: SingleChildScrollView(
              padding:
                  const EdgeInsets.symmetric(horizontal: 32, vertical: 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _eyebrow('ASSESSMENT INTAKE'),
                  const SizedBox(height: 6),
                  Text(
                    'Start a diagnostic engagement',
                    style: GoogleFonts.playfairDisplay(
                      fontSize:   26,
                      fontWeight: FontWeight.w400,
                      fontStyle:  FontStyle.italic,
                      color:      _ink,
                      height:     1.05,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Slim intake — just enough to open the case. '
                    'Full case history lives in Section 1 of the '
                    'assessment surface.',
                    style: GoogleFonts.dmSans(
                        fontSize: 13, color: _inkGhost, height: 1.45),
                  ),
                  const SizedBox(height: 28),

                  _eyebrow('client'),
                  const SizedBox(height: 10),
                  _textField('Client name *', _nameCtrl,
                      capitalize: true),
                  _textField('Age (years) *', _ageCtrl,
                      numeric: true, hint: 'e.g. 4, 28, 67'),

                  const SizedBox(height: 18),
                  _eyebrow('caregiver / contact'),
                  const SizedBox(height: 10),
                  _textField('Caregiver name (optional)',
                      _caregiverNameCtrl, capitalize: true),
                  _textField('Caregiver WhatsApp', _caregiverWaCtrl,
                      hint: '+91 98765 43210'),
                  _textField('Primary language', _languageCtrl,
                      capitalize: true,
                      hint: 'e.g. Telugu, English, Kannada'),

                  const SizedBox(height: 18),
                  _eyebrow('clinical area *'),
                  const SizedBox(height: 10),
                  _clinicalAreaPicker(),

                  const SizedBox(height: 18),
                  _eyebrow('chief concern *'),
                  const SizedBox(height: 6),
                  _ghostNote(
                      "What brought them in? You'll capture the full "
                      "case history in Section 1 of the assessment."),
                  _textField('In 1–2 sentences', _concernCtrl,
                      multi: true, capitalize: true),

                  const SizedBox(height: 18),
                  _eyebrow('referral'),
                  const SizedBox(height: 10),
                  _singleChips('Referral source', _kReferralSources,
                      _referralSource,
                      (v) => setState(() => _referralSource = v)),

                  const SizedBox(height: 18),
                  _eyebrow('visit + commercial'),
                  const SizedBox(height: 10),
                  _datePickerRow('Visit date', _visitDate, _pickVisitDate),
                  _textField('Assessment fee agreed (₹)', _feeCtrl,
                      numeric: true, hint: 'optional'),

                  const SizedBox(height: 18),
                  _eyebrow('deliverable expected'),
                  const SizedBox(height: 10),
                  _multiChips(_kDeliverables, _deliverables, (v, sel) {
                    setState(() {
                      if (sel) {
                        _deliverables.add(v);
                      } else {
                        _deliverables.remove(v);
                      }
                    });
                  }),

                  const SizedBox(height: 28),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _saving ? null : _save,
                      style: FilledButton.styleFrom(
                        backgroundColor: _amber,
                        foregroundColor: Colors.white,
                        padding:
                            const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                      child: _saving
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                  color: Colors.white, strokeWidth: 2),
                            )
                          : Text(
                              'Open assessment',
                              style: GoogleFonts.dmSans(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600),
                            ),
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── UI primitives ────────────────────────────────────────────────────

  Widget _eyebrow(String text) => Text(text.toUpperCase(),
      style: GoogleFonts.syne(
          fontSize:      10,
          fontWeight:    FontWeight.w600,
          color:         _amber,
          letterSpacing: 1.6));

  Widget _ghostNote(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          decoration: BoxDecoration(
            color:        _amberSoft.withValues(alpha: 0.30),
            borderRadius: BorderRadius.circular(8),
            border:       Border.all(color: _amberSoft),
          ),
          child: Text(text,
              style: GoogleFonts.dmSans(
                  fontSize:   12,
                  color:      _ink,
                  fontStyle:  FontStyle.italic,
                  height:     1.5)),
        ),
      );

  Widget _textField(
    String label,
    TextEditingController ctrl, {
    bool numeric    = false,
    bool multi      = false,
    bool capitalize = false,
    String? hint,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: GoogleFonts.dmSans(
                  fontSize:   12,
                  color:      _inkGhost,
                  fontWeight: FontWeight.w500)),
          const SizedBox(height: 4),
          TextField(
            controller: ctrl,
            maxLines: multi ? 3 : 1,
            keyboardType:
                numeric ? TextInputType.number : TextInputType.text,
            inputFormatters: numeric
                ? [FilteringTextInputFormatter.digitsOnly]
                : null,
            textCapitalization: capitalize
                ? TextCapitalization.words
                : TextCapitalization.sentences,
            style: GoogleFonts.dmSans(fontSize: 13, color: _ink),
            decoration: InputDecoration(
              filled: true,
              fillColor: Colors.white,
              hintText: hint,
              hintStyle: GoogleFonts.dmSans(
                  fontSize: 12,
                  color: _inkGhost.withValues(alpha: 0.6)),
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
                borderSide: const BorderSide(color: _amber, width: 1.2),
              ),
              contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 10),
            ),
          ),
        ],
      ),
    );
  }

  Widget _clinicalAreaPicker() {
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color:        Colors.white,
        borderRadius: BorderRadius.circular(8),
        border:       Border.all(color: _line),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButtonFormField<String>(
          initialValue: _clinicalArea,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'Pick the clinical area for this assessment',
            labelStyle: TextStyle(color: _inkGhost, fontSize: 13),
            border: InputBorder.none,
          ),
          style: GoogleFonts.dmSans(fontSize: 13, color: _ink),
          items: [
            for (final a in kClinicalAreas)
              DropdownMenuItem<String>(
                value: a.code,
                child: a.code == 'pediatric-motor-speech'
                    ? Text(
                        'Pediatric Motor Speech — differential pending',
                        style: GoogleFonts.dmSans(
                            fontSize: 13,
                            color: _inkGhost,
                            fontStyle: FontStyle.italic),
                      )
                    : Text(a.label,
                        style: GoogleFonts.dmSans(
                            fontSize: 13, color: _ink)),
              ),
          ],
          onChanged: (v) {
            if (v != null) setState(() => _clinicalArea = v);
          },
        ),
      ),
    );
  }

  Widget _datePickerRow(
      String label, DateTime value, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: GoogleFonts.dmSans(
                  fontSize:   12,
                  color:      _inkGhost,
                  fontWeight: FontWeight.w500)),
          const SizedBox(height: 4),
          InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 12),
              decoration: BoxDecoration(
                color:        Colors.white,
                borderRadius: BorderRadius.circular(8),
                border:       Border.all(color: _line),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      value.toIso8601String().substring(0, 10),
                      style: GoogleFonts.dmSans(
                          fontSize: 13, color: _ink),
                    ),
                  ),
                  const Icon(Icons.calendar_today_outlined,
                      size: 16, color: _inkGhost),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _singleChips(String label, List<String> options,
      String? value, ValueChanged<String> onPick) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: GoogleFonts.dmSans(
                  fontSize:   12,
                  color:      _inkGhost,
                  fontWeight: FontWeight.w500)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6, runSpacing: 6,
            children: [
              for (final o in options)
                _chip(o, value == o, () => onPick(o)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _multiChips(List<String> options, Set<String> selected,
      void Function(String, bool) onToggle) {
    return Wrap(
      spacing: 6, runSpacing: 6,
      children: [
        for (final o in options)
          _chip(o, selected.contains(o),
              () => onToggle(o, !selected.contains(o))),
      ],
    );
  }

  Widget _chip(String label, bool selected, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: selected
              ? _amber.withValues(alpha: 0.18)
              : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? _amber : _line,
            width: selected ? 1.2 : 1,
          ),
        ),
        child: Text(
          label,
          style: GoogleFonts.dmSans(
              fontSize:   12,
              color:      selected ? _amber : _ink,
              fontWeight:
                  selected ? FontWeight.w600 : FontWeight.w400),
        ),
      ),
    );
  }
}
