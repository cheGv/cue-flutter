import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme/cue_typography.dart';
import '../widgets/app_layout.dart';

// ── Design tokens ──────────────────────────────────────────────────────────────
const _ink   = Color(0xFF1B2B4B);
const _paper = Color(0xFFFAFAF7);
const _line  = Color(0xFFE8E4DC);
const _ghost = Color(0xFF6B7690);
const _teal  = Color(0xFF2A8F84);

// ── Option lists ───────────────────────────────────────────────────────────────
const _kSettings = [
  'School', 'Hospital', 'Private Practice',
  'Early Intervention', 'Rehabilitation', 'Telehealth',
];
const _kSpecializations = [
  'Articulation', 'Fluency', 'Voice', 'Language', 'AAC',
  'Feeding & Swallowing', 'Cognitive Communication',
  'Social Communication', 'Literacy',
];
const _kCertifications = [
  'ASHA CCC-SLP', 'RCI (India)', 'HPCSA (SA)',
  'AHPRA (AU)', 'CSHBC (CA)', 'IALP', 'PROMPT',
];
const _kAgeGroups = [
  'Birth–2', 'Toddlers (2–5)', 'School Age (6–12)',
  'Adolescents (13–17)', 'Adults', 'Geriatric',
];
const _kLanguages = [
  'English', 'Hindi', 'Tamil', 'Telugu', 'Kannada',
  'Marathi', 'Bengali', 'Punjabi', 'Malayalam', 'Other',
];
const _kNoteFormats    = ['SOAP', 'DAP', 'BIRP', 'Narrative'];
const _kReportFormats  = ['SOAP', 'DAR', 'COAST', 'Narrative'];
const _kNoteTones   = ['Clinical', 'Plain Language', 'Mixed'];
const _kNoteDetails = ['Brief', 'Standard', 'Detailed'];
const _kOrientations = [
  'Behavioral', 'Naturalistic', 'Eclectic',
  'Developmental', 'Social Pragmatic', 'Motor Learning',
];
const _kFamilyInvolvement = ['Minimal', 'Moderate', 'High', 'Family-Led'];

// ── Screen ─────────────────────────────────────────────────────────────────────
class SlpProfileScreen extends StatefulWidget {
  const SlpProfileScreen({super.key});

  @override
  State<SlpProfileScreen> createState() => _SlpProfileScreenState();
}

class _SlpProfileScreenState extends State<SlpProfileScreen> {
  final _supabase = Supabase.instance.client;

  final _nameCtrl  = TextEditingController();
  final _yearsCtrl = TextEditingController();

  String?      _primarySetting;
  Set<String>  _therapyLanguages   = {};
  Set<String>  _specializations    = {};
  Set<String>  _certifications     = {};
  Set<String>  _ageGroups          = {};
  String?      _noteFormat         = 'SOAP';
  String?      _reportFormat       = 'SOAP';
  String?      _noteTone           = 'clinical';
  String?      _noteDetail         = 'standard';
  bool         _includesHomeProgram = true;
  Set<String>  _orientation        = {};
  String?      _familyInvolvement  = 'moderate';

  bool _loading = true;
  bool _saving  = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _yearsCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final uid = _supabase.auth.currentUser!.id;
      final row = await _supabase
          .from('slp_profiles')
          .select()
          .eq('clinician_id', uid)
          .maybeSingle();

      if (row != null && mounted) {
        _nameCtrl.text  = row['full_name'] as String? ?? '';
        _yearsCtrl.text = row['years_experience']?.toString() ?? '';

        _primarySetting = row['primary_setting'] as String?;
        _noteFormat     = row['note_format']     as String? ?? 'SOAP';
        _reportFormat   = row['report_format']   as String? ?? 'SOAP';
        _noteTone       = row['note_tone']       as String? ?? 'clinical';
        _noteDetail     = row['note_detail']     as String? ?? 'standard';
        _familyInvolvement = row['family_involvement'] as String? ?? 'moderate';
        _includesHomeProgram =
            (row['includes_home_program'] as bool?) ?? true;

        _therapyLanguages = _toSet(row['therapy_languages']);
        _specializations  = _toSet(row['specializations']);
        _certifications   = _toSet(row['certifications']);
        _orientation      = _toSet(row['theoretical_orientation']);

        final pop = row['primary_population'];
        if (pop is Map) {
          _ageGroups = _toSet(pop['age_range']);
        }
      }
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Set<String> _toSet(dynamic v) {
    if (v == null) return {};
    if (v is List) return v.cast<String>().toSet();
    return {};
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final uid = _supabase.auth.currentUser!.id;
      final data = {
        'clinician_id':            uid,
        'full_name':               _nameCtrl.text.trim().isEmpty ? null : _nameCtrl.text.trim(),
        'years_experience':        int.tryParse(_yearsCtrl.text.trim()),
        'primary_setting':         _primarySetting,
        'therapy_languages':       _therapyLanguages.toList(),
        'specializations':         _specializations.toList(),
        'certifications':          _certifications.toList(),
        'primary_population':      {'age_range': _ageGroups.toList()},
        'note_format':             _noteFormat,
        'report_format':           _reportFormat,
        'note_tone':               _noteTone,
        'note_detail':             _noteDetail,
        'includes_home_program':   _includesHomeProgram,
        'theoretical_orientation': _orientation.toList(),
        'family_involvement':      _familyInvolvement,
      };
      debugPrint('[SlpProfile] saving: $data');
      await _supabase.from('slp_profiles').upsert(
        data,
        onConflict: 'clinician_id',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Profile saved',
                style: GoogleFonts.dmSans(fontSize: 13, color: Colors.white)),
            backgroundColor: _ink,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      debugPrint('[SlpProfile] save error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Save failed — $e',
                style: GoogleFonts.dmSans(fontSize: 13, color: Colors.white)),
            backgroundColor: Colors.red.shade800,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppLayout(
      title: 'My Profile',
      activeRoute: 'settings',
      actions: [
        TextButton(
          onPressed: _saving ? null : _save,
          style: TextButton.styleFrom(
            backgroundColor: _teal,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
          child: _saving
              ? const SizedBox(
                  width: 14, height: 14,
                  child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white)),
                )
              : Text('Save', style: GoogleFonts.dmSans(fontSize: 13, fontWeight: FontWeight.w600)),
        ),
      ],
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : LayoutBuilder(
              builder: (context, constraints) {
                return SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 32),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 600),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _Section(
                          title: 'Who you are',
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(child: _textField('Full name', _nameCtrl, hint: 'e.g. Dr. Priya Sharma')),
                                  const SizedBox(width: 16),
                                  SizedBox(
                                    width: 140,
                                    child: _textField('Years of experience', _yearsCtrl, hint: 'e.g. 8', numeric: true),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 20),
                              _fieldLabel('Primary setting'),
                              const SizedBox(height: 8),
                              _ChipSelector(
                                options: _kSettings,
                                selected: _primarySetting != null ? {_primarySetting!} : {},
                                multi: false,
                                onChanged: (v) => setState(() => _primarySetting = v.isEmpty ? null : v.first),
                              ),
                              const SizedBox(height: 20),
                              _fieldLabel('Languages you work in'),
                              const SizedBox(height: 8),
                              _ChipSelector(
                                options: _kLanguages,
                                selected: _therapyLanguages,
                                multi: true,
                                onChanged: (v) => setState(() => _therapyLanguages = v),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 32),

                        _Section(
                          title: 'Clinical focus',
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _fieldLabel('Specializations'),
                              const SizedBox(height: 8),
                              _ChipSelector(
                                options: _kSpecializations,
                                selected: _specializations,
                                multi: true,
                                onChanged: (v) => setState(() => _specializations = v),
                              ),
                              const SizedBox(height: 20),
                              _fieldLabel('Certifications'),
                              const SizedBox(height: 8),
                              _ChipSelector(
                                options: _kCertifications,
                                selected: _certifications,
                                multi: true,
                                onChanged: (v) => setState(() => _certifications = v),
                              ),
                              const SizedBox(height: 20),
                              _fieldLabel('Age groups you primarily serve'),
                              const SizedBox(height: 8),
                              _ChipSelector(
                                options: _kAgeGroups,
                                selected: _ageGroups,
                                multi: true,
                                onChanged: (v) => setState(() => _ageGroups = v),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 32),

                        _Section(
                          title: 'How you write session notes',
                          subtitle: 'The format Cue uses when generating your clinical notes',
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _ChipSelector(
                                options: _kReportFormats,
                                selected: _reportFormat != null ? {_reportFormat!} : {'SOAP'},
                                multi: false,
                                onChanged: (v) => setState(() => _reportFormat = v.isEmpty ? 'SOAP' : v.first),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'DAR — Data, Action, Response  ·  COAST — Context, Observation, Assessment, Strategy, Target',
                                style: GoogleFonts.dmSans(fontSize: 11, color: _ghost, height: 1.5),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 32),

                        _Section(
                          title: 'How you write notes',
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _fieldLabel('Note format'),
                              const SizedBox(height: 8),
                              _ChipSelector(
                                options: _kNoteFormats,
                                selected: _noteFormat != null ? {_noteFormat!} : {},
                                multi: false,
                                onChanged: (v) => setState(() => _noteFormat = v.isEmpty ? null : v.first),
                              ),
                              const SizedBox(height: 20),
                              _fieldLabel('Tone'),
                              const SizedBox(height: 8),
                              _ChipSelector(
                                options: _kNoteTones,
                                selected: _noteTone != null ? {_noteTone!} : {},
                                multi: false,
                                onChanged: (v) => setState(() => _noteTone = v.isEmpty ? null : v.first),
                              ),
                              const SizedBox(height: 20),
                              _fieldLabel('Detail level'),
                              const SizedBox(height: 8),
                              _ChipSelector(
                                options: _kNoteDetails,
                                selected: _noteDetail != null ? {_noteDetail!} : {},
                                multi: false,
                                onChanged: (v) => setState(() => _noteDetail = v.isEmpty ? null : v.first),
                              ),
                              const SizedBox(height: 20),
                              _fieldLabel('Theoretical orientation'),
                              const SizedBox(height: 8),
                              _ChipSelector(
                                options: _kOrientations,
                                selected: _orientation,
                                multi: true,
                                onChanged: (v) => setState(() => _orientation = v),
                              ),
                              const SizedBox(height: 20),
                              GestureDetector(
                                onTap: () => setState(() => _includesHomeProgram = !_includesHomeProgram),
                                behavior: HitTestBehavior.opaque,
                                child: Row(
                                  children: [
                                    Container(
                                      width: 18, height: 18,
                                      decoration: BoxDecoration(
                                        color: _includesHomeProgram ? _ink : Colors.transparent,
                                        border: Border.all(
                                          color: _includesHomeProgram ? _ink : _ghost,
                                          width: 1.5,
                                        ),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: _includesHomeProgram
                                          ? const Icon(Icons.check, color: Colors.white, size: 12)
                                          : null,
                                    ),
                                    const SizedBox(width: 10),
                                    Text(
                                      'Include home program in notes',
                                      style: GoogleFonts.dmSans(fontSize: 13, color: _ink),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 32),

                        _Section(
                          title: 'Family involvement',
                          subtitle: 'How much do you involve families in day-to-day therapy?',
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _ChipSelector(
                                options: _kFamilyInvolvement,
                                selected: _familyInvolvement != null ? {_familyInvolvement!} : {},
                                multi: false,
                                onChanged: (v) => setState(() => _familyInvolvement = v.isEmpty ? null : v.first),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 80),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }

  Widget _textField(String label, TextEditingController ctrl,
      {String? hint, bool numeric = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _fieldLabel(label),
        const SizedBox(height: 8),
        TextFormField(
          controller: ctrl,
          keyboardType: numeric ? TextInputType.number : TextInputType.text,
          style: GoogleFonts.dmSans(fontSize: 14, color: _ink),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: GoogleFonts.dmSans(fontSize: 14, color: _ghost),
            filled: true,
            fillColor: Colors.white,
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: _line)),
            enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: _line)),
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: _teal, width: 1.5)),
          ),
        ),
      ],
    );
  }
}

Widget _fieldLabel(String text) => Text(
      text,
      style: GoogleFonts.dmSans(
          fontSize: 13, fontWeight: FontWeight.w600, color: _ink),
    );

// ── Section wrapper ────────────────────────────────────────────────────────────
class _Section extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget child;

  const _Section({required this.title, this.subtitle, required this.child});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: CueType.serif(
              fontSize: 18, fontWeight: FontWeight.w600, color: _ink),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 4),
          Text(subtitle!,
              style: GoogleFonts.dmSans(fontSize: 13, color: _ghost)),
        ],
        const SizedBox(height: 4),
        Container(height: 1, color: _line),
        const SizedBox(height: 16),
        child,
      ],
    );
  }
}

// ── Chip selector ──────────────────────────────────────────────────────────────
class _ChipSelector extends StatelessWidget {
  final List<String> options;
  final Set<String> selected;
  final bool multi;
  final ValueChanged<Set<String>> onChanged;

  const _ChipSelector({
    required this.options,
    required this.selected,
    required this.multi,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: options.map((opt) {
        final active = selected.contains(opt);
        return GestureDetector(
          onTap: () {
            final next = Set<String>.from(selected);
            if (active) {
              next.remove(opt);
            } else {
              if (!multi) next.clear();
              next.add(opt);
            }
            onChanged(next);
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            decoration: BoxDecoration(
              color: active ? _ink : _paper,
              border: Border.all(color: active ? _ink : _line),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              opt,
              style: GoogleFonts.dmSans(
                fontSize: 13,
                color: active ? Colors.white : _ink,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}
