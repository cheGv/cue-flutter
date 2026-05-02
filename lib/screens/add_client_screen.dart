import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:speech_to_text/speech_to_text.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../widgets/app_layout.dart';

// ── Design tokens (§5 palette) ────────────────────────────────────────────────
const Color _ink      = Color(0xFF1B2B4B);
const Color _ghost    = Color(0xFF6B7690);
const Color _teal     = Color(0xFF2A8F84);
const Color _aiAccent = Color(0xFF1D9E75); // AI-fill highlight border
const Color _aiFill   = Color(0xFFEAF6F3); // AI-fill field background

// ── Proxy ─────────────────────────────────────────────────────────────────────
const String _proxyBase = 'https://cue-ai-proxy.onrender.com';

// ── AI extraction system prompts ─────────────────────────────────────────────
// Phase 4.0.2: extract prompts now include Layer-01 language fields and the
// parent's-concern verbatim. population_type is intentionally excluded — it is
// a clinician routing decision, not a parseable field (§13.16).
const String _brainDumpSystem =
    'You are a clinical intake assistant for a speech-language pathologist. '
    'Extract client information from the spoken description and return ONLY a '
    'JSON object with these exact keys (omit keys where information is not '
    'found): name, age, date_of_birth (YYYY-MM-DD), diagnosis, '
    'secondary_diagnosis, primary_communication_modality, uses_aac (true/false), '
    'guardian_name, school_setting, referral_source, previous_therapy (true/false), '
    'previous_therapy_duration, regulatory_profile, baseline_summary, '
    'primary_language, additional_languages (array of strings), '
    'primary_concern_verbatim (the parent\'s words about why they came, quoted as closely as possible). '
    'Return valid JSON only, no markdown, no explanation.';

const String _extractSystem =
    'You are a clinical data extraction assistant. Extract client information '
    'from the uploaded diagnostic report and return ONLY a JSON object with '
    'these exact keys (omit keys where information is not found): '
    'name, age, date_of_birth (YYYY-MM-DD), diagnosis, secondary_diagnosis, '
    'primary_communication_modality, uses_aac (true/false), guardian_name, '
    'school_setting, referral_source, previous_therapy (true/false), '
    'previous_therapy_duration, regulatory_profile, baseline_summary, '
    'primary_language, additional_languages (array of strings), '
    'primary_concern_verbatim (the parent\'s or referrer\'s words about the reason for referral, quoted closely). '
    'Return valid JSON only, no markdown, no explanation.';

// Population types selectable in V1. V1.x adds others (acquired_stuttering,
// cluttering, ssd, voice, language, etc.) as those populations ship.
const List<({String value, String label})> _populationOptions = [
  (value: 'developmental_stuttering', label: 'Developmental stuttering'),
  (value: 'asd_aac',                  label: 'ASD / AAC'),
];

// ─────────────────────────────────────────────────────────────────────────────

class AddClientScreen extends StatefulWidget {
  final Map<String, dynamic>? existingClient;

  const AddClientScreen({super.key, this.existingClient});

  @override
  State<AddClientScreen> createState() => _AddClientScreenState();
}

class _AddClientScreenState extends State<AddClientScreen> {
  final _supabase = Supabase.instance.client;

  // ── Existing fields ─────────────────────────────────────────────────────────
  final _nameCtrl     = TextEditingController();
  final _ageCtrl      = TextEditingController();
  final _diagCtrl     = TextEditingController();
  final _modalityCtrl = TextEditingController();
  final _notesCtrl    = TextEditingController();
  bool _usesAac  = false;
  bool _isSaving = false;

  // ── Basic new fields ────────────────────────────────────────────────────────
  DateTime? _dateOfBirth;
  final _guardianNameCtrl     = TextEditingController();
  final _guardianWaCtrl       = TextEditingController(); // WhatsApp
  final _schoolCtrl           = TextEditingController();

  // ── Layer-01 Phase 4.0.2 fields ────────────────────────────────────────────
  String _populationType = 'developmental_stuttering'; // default for new clients
  final _primaryLangCtrl      = TextEditingController();
  final _additionalLangsCtrl  = TextEditingController(); // comma-separated
  final _concernVerbatimCtrl  = TextEditingController();

  // ── Clinical intake fields ──────────────────────────────────────────────────
  final _secDiagCtrl          = TextEditingController();
  final _referralCtrl         = TextEditingController();
  bool _prevTherapy           = false;
  final _prevDurationCtrl     = TextEditingController();
  final _regulatoryCtrl       = TextEditingController();
  final _baselineCtrl         = TextEditingController();

  // ── AI import state ─────────────────────────────────────────────────────────
  PlatformFile?   _pickedFile;
  bool            _isExtracting = false;
  String?         _extractError;
  Set<String>     _aiFields = {}; // keys of fields populated by AI

  // ── Edit mode helper ─────────────────────────────────────────────────────────
  bool get _isEditMode => widget.existingClient != null;

  // ── Lifecycle ────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    if (_isEditMode) _populateFromExistingClient(widget.existingClient!);
  }

  void _populateFromExistingClient(Map<String, dynamic> c) {
    _nameCtrl.text     = (c['name']                   as String?) ?? '';
    _ageCtrl.text      = c['age'] != null ? c['age'].toString() : '';
    _diagCtrl.text     = (c['diagnosis']               as String?) ?? '';
    _modalityCtrl.text = (c['communication_modality']  as String?) ?? '';
    _notesCtrl.text    = (c['additional_notes']        as String?) ?? '';
    _usesAac           = (c['uses_aac']  as bool?)     ?? false;

    // Basic new fields
    final dobStr = c['date_of_birth'] as String?;
    if (dobStr != null) _dateOfBirth = DateTime.tryParse(dobStr);
    _guardianNameCtrl.text = (c['guardian_name']      as String?) ?? '';
    _guardianWaCtrl.text   = (c['guardian_whatsapp']  as String?) ?? '';
    _schoolCtrl.text       = (c['school_setting']     as String?) ?? '';

    // Clinical intake
    _secDiagCtrl.text      = (c['secondary_diagnosis']         as String?) ?? '';
    _referralCtrl.text     = (c['referral_source']             as String?) ?? '';
    _prevTherapy           = (c['previous_therapy'] as bool?)  ?? false;
    _prevDurationCtrl.text = (c['previous_therapy_duration']   as String?) ?? '';
    _regulatoryCtrl.text   = (c['regulatory_profile']          as String?) ?? '';
    _baselineCtrl.text     = (c['baseline_summary']            as String?) ?? '';

    // Layer-01 Phase 4.0.2 fields
    final pop = (c['population_type'] as String?)?.trim();
    if (pop != null && pop.isNotEmpty) {
      // Show whatever is on the row even if not in the V1 dropdown set, so
      // legacy values render and can be re-saved. Unknown values fall back to
      // 'asd_aac' (the §11 backfill default) so the dropdown has something
      // valid to show.
      final known = _populationOptions.any((o) => o.value == pop);
      _populationType = known ? pop : 'asd_aac';
    }
    _primaryLangCtrl.text     = (c['primary_language'] as String?) ?? '';
    final addLangs = c['additional_languages'];
    if (addLangs is List) {
      _additionalLangsCtrl.text = addLangs.map((e) => e.toString()).join(', ');
    }
    _concernVerbatimCtrl.text = (c['primary_concern_verbatim'] as String?) ?? '';
  }

  @override
  void dispose() {
    _nameCtrl.dispose();     _ageCtrl.dispose();
    _diagCtrl.dispose();     _modalityCtrl.dispose();
    _notesCtrl.dispose();
    _guardianNameCtrl.dispose(); _guardianWaCtrl.dispose();
    _schoolCtrl.dispose();
    _secDiagCtrl.dispose();  _referralCtrl.dispose();
    _prevDurationCtrl.dispose();
    _regulatoryCtrl.dispose(); _baselineCtrl.dispose();
    _primaryLangCtrl.dispose(); _additionalLangsCtrl.dispose();
    _concernVerbatimCtrl.dispose();
    super.dispose();
  }

  // ── File picker ──────────────────────────────────────────────────────────────

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'docx', 'jpg', 'jpeg', 'png'],
      withData: true, // required on Flutter Web to receive bytes
    );
    if (result != null && result.files.isNotEmpty) {
      setState(() {
        _pickedFile   = result.files.first;
        _extractError = null;
      });
    }
  }

  // ── Brain Dump (voice intake) ─────────────────────────────────────────────────

  void _openBrainDump() {
    final token = _supabase.auth.currentSession?.accessToken;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _BrainDumpSheet(
        token: token,
        onPopulated: (data) => _populateFromAi(data, sourceLabel: 'voice'),
      ),
    );
  }

  // ── AI extraction ────────────────────────────────────────────────────────────

  Future<void> _extractFromFile() async {
    final file = _pickedFile;
    if (file == null) return;
    final bytes = file.bytes;
    if (bytes == null || bytes.isEmpty) {
      setState(() => _extractError = 'Could not read document. Fill manually.');
      return;
    }

    setState(() { _isExtracting = true; _extractError = null; });

    try {
      final base64Data = base64Encode(bytes);
      final mimeType   = _mimeType(file.extension ?? '');
      final token      = _supabase.auth.currentSession?.accessToken;

      final response = await http.post(
        Uri.parse('$_proxyBase/extract'),
        headers: {
          'Content-Type': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'model':        'claude-opus-4-5',
          'system':       _extractSystem,
          'user_message': 'Extract clinical information from this document.',
          'file_base64':  base64Data,
          'file_type':    mimeType,
        }),
      ).timeout(const Duration(seconds: 60));

      if (response.statusCode != 200) {
        throw Exception('proxy ${response.statusCode}');
      }

      final respData = jsonDecode(response.body) as Map<String, dynamic>;

      // /extract returns { "result": "<json text>" }
      // Strip markdown code fences if Claude adds them despite the instruction
      var rawText = (respData['result'] ?? '').toString().trim();
      if (rawText.startsWith('```')) {
        rawText = rawText
            .replaceFirst(RegExp(r'^```[a-z]*\n?'), '')
            .replaceFirst(RegExp(r'```$'), '')
            .trim();
      }

      final extracted = jsonDecode(rawText) as Map<String, dynamic>;
      _populateFromAi(extracted);

    } catch (_) {
      if (mounted) setState(() => _extractError = 'Could not read document. Fill manually.');
    } finally {
      if (mounted) setState(() => _isExtracting = false);
    }
  }

  void _populateFromAi(Map<String, dynamic> data, {String sourceLabel = 'report'}) {
    final filled = <String>{};

    // Helper — fills a text controller and records the key
    void fillText(String key, TextEditingController ctrl) {
      final v = data[key];
      if (v != null && v.toString().trim().isNotEmpty) {
        ctrl.text = v.toString().trim();
        filled.add(key);
      }
    }

    // Per §13.16, AI extraction is a draft layer — only fill when the
    // clinician hasn't already entered a value. The clinician's own input
    // is never silently overwritten by the extract path.
    void fillTextIfEmpty(String key, TextEditingController ctrl) {
      if (ctrl.text.trim().isEmpty) fillText(key, ctrl);
    }

    fillText('name',                          _nameCtrl);
    fillText('diagnosis',                     _diagCtrl);
    fillText('secondary_diagnosis',           _secDiagCtrl);
    fillText('primary_communication_modality',_modalityCtrl);
    fillText('guardian_name',                 _guardianNameCtrl);
    fillText('school_setting',                _schoolCtrl);
    fillText('referral_source',               _referralCtrl);
    fillText('previous_therapy_duration',     _prevDurationCtrl);
    fillText('regulatory_profile',            _regulatoryCtrl);
    fillText('baseline_summary',              _baselineCtrl);

    // Layer-01 Phase 4.0.2 — never overwrite clinician-entered values (§13.16)
    fillTextIfEmpty('primary_language',         _primaryLangCtrl);
    fillTextIfEmpty('primary_concern_verbatim', _concernVerbatimCtrl);

    // additional_languages: array → comma-separated, only if SLP hasn't typed
    final addLangs = data['additional_languages'];
    if (addLangs is List &&
        addLangs.isNotEmpty &&
        _additionalLangsCtrl.text.trim().isEmpty) {
      _additionalLangsCtrl.text =
          addLangs.map((e) => e.toString().trim()).where((s) => s.isNotEmpty).join(', ');
      filled.add('additional_languages');
    }

    // Age (numeric)
    if (data['age'] != null) {
      _ageCtrl.text = data['age'].toString();
      filled.add('age');
    }

    // Date of birth → also auto-computes age if not already set
    if (data['date_of_birth'] != null) {
      final dob = DateTime.tryParse(data['date_of_birth'].toString());
      if (dob != null) {
        _dateOfBirth = dob;
        filled.add('date_of_birth');
        if (!filled.contains('age')) {
          _ageCtrl.text = _computeAge(dob).toString();
          filled.add('age');
        }
      }
    }

    // Boolean toggles
    if (data['uses_aac'] != null) {
      _usesAac = data['uses_aac'] == true;
      filled.add('uses_aac');
    }
    if (data['previous_therapy'] != null) {
      _prevTherapy = data['previous_therapy'] == true;
      filled.add('previous_therapy');
    }

    setState(() => _aiFields = filled);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${filled.length} fields filled from $sourceLabel')),
      );
    }
  }

  // Removes a field from the AI-filled set — called from onChanged so the
  // highlight disappears the moment the SLP makes a manual edit.
  void _clearAi(String key) {
    if (_aiFields.contains(key)) setState(() => _aiFields.remove(key));
  }

  // ── Date of birth helpers ─────────────────────────────────────────────────────

  Future<void> _pickDob() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _dateOfBirth ?? DateTime(now.year - 5),
      firstDate: DateTime(now.year - 30),
      lastDate: now,
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.light(
            primary: _teal,
            onPrimary: Colors.white,
            surface: Colors.white,
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() {
        _dateOfBirth = picked;
        _aiFields.remove('date_of_birth'); // manual selection clears AI highlight
        _ageCtrl.text = _computeAge(picked).toString();
        _aiFields.remove('age');
      });
    }
  }

  int _computeAge(DateTime dob) {
    final now = DateTime.now();
    int age = now.year - dob.year;
    if (now.month < dob.month ||
        (now.month == dob.month && now.day < dob.day)) {
      age--;
    }
    return age < 0 ? 0 : age;
  }

  static String _mimeType(String ext) => switch (ext.toLowerCase()) {
        'pdf'            => 'application/pdf',
        'docx'           => 'application/vnd.openxmlformats-officedocument'
                            '.wordprocessingml.document',
        'jpg' || 'jpeg'  => 'image/jpeg',
        'png'            => 'image/png',
        _                => 'application/octet-stream',
      };

  // ── Save ─────────────────────────────────────────────────────────────────────

  Future<void> _save() async {
    final name    = _nameCtrl.text.trim();
    final ageText = _ageCtrl.text.trim();

    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Full name is required')),
      );
      return;
    }
    if (ageText.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Age is required')),
      );
      return;
    }

    final userId = _supabase.auth.currentUser?.id;
    setState(() => _isSaving = true);

    // Layer-01 Phase 4.0.2: parse comma-separated languages → text[]
    final additionalLangs = _additionalLangsCtrl.text
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();

    // Build the shared field map (used by both insert and update)
    final data = <String, dynamic>{
      'name':                   name,
      'age':                    int.tryParse(ageText) ?? 0,
      'diagnosis':              _diagCtrl.text.trim(),
      'uses_aac':               _usesAac,
      'communication_modality': _modalityCtrl.text.trim(),
      'additional_notes':       _notesCtrl.text.trim(),
      // Layer-01 Phase 4.0.2 — population routing + parent's words + languages
      'population_type':            _populationType,
      'primary_language':           _primaryLangCtrl.text.trim(),
      'additional_languages':       additionalLangs,
      'primary_concern_verbatim':   _concernVerbatimCtrl.text.trim(),
      // Basic new
      if (_dateOfBirth != null)
        'date_of_birth': _dateOfBirth!.toIso8601String().split('T').first,
      'guardian_name':    _guardianNameCtrl.text.trim(),
      'guardian_whatsapp': _guardianWaCtrl.text.trim(),
      'school_setting':   _schoolCtrl.text.trim(),
      // Clinical intake
      'secondary_diagnosis':       _secDiagCtrl.text.trim(),
      'referral_source':           _referralCtrl.text.trim(),
      'previous_therapy':          _prevTherapy,
      if (_prevTherapy)
        'previous_therapy_duration': _prevDurationCtrl.text.trim(),
      'regulatory_profile': _regulatoryCtrl.text.trim(),
      'baseline_summary':   _baselineCtrl.text.trim(),
    };

    try {
      if (_isEditMode) {
        final id = widget.existingClient!['id'];
        await _supabase.from('clients').update(data).eq('id', id);
      } else {
        await _supabase.from('clients').insert({
          ...data,
          'total_sessions': 0,
          'clinician_id':   userId,
        });
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(
              _isEditMode ? 'Error updating client: $e' : 'Error adding client: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return AppLayout(
      title: _isEditMode ? 'Edit Client' : 'Add Client',
      activeRoute: 'roster',
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Import from Report ─────────────────────────────────────
                _buildImportZone(),
                const SizedBox(height: 32),

                // ── Required ───────────────────────────────────────────────
                _sectionLabel('Required'),
                const SizedBox(height: 12),
                _buildPopulationDropdown(),
                const SizedBox(height: 16),
                TextField(
                  controller: _nameCtrl,
                  decoration: _dec('Full name *', aiKey: 'name'),
                  textCapitalization: TextCapitalization.words,
                  onChanged: (_) => _clearAi('name'),
                ),
                const SizedBox(height: 16),
                _buildDobField(),
                const SizedBox(height: 16),
                TextField(
                  controller: _ageCtrl,
                  decoration: _dec('Age *', aiKey: 'age'),
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  onChanged: (_) => _clearAi('age'),
                ),
                const SizedBox(height: 32),

                // ── Parent's concern ───────────────────────────────────────
                _buildConcernSection(),
                const SizedBox(height: 32),

                // ── Basic ──────────────────────────────────────────────────
                _sectionLabel('Basic'),
                const SizedBox(height: 12),
                TextField(
                  controller: _guardianNameCtrl,
                  decoration: _dec('Parent / guardian name',
                      aiKey: 'guardian_name'),
                  textCapitalization: TextCapitalization.words,
                  onChanged: (_) => _clearAi('guardian_name'),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _guardianWaCtrl,
                  decoration: _dec('Parent WhatsApp number',
                      hint: '+91 98765 43210'),
                  keyboardType: TextInputType.phone,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _schoolCtrl,
                  decoration: _dec('School / setting',
                      aiKey: 'school_setting'),
                  textCapitalization: TextCapitalization.words,
                  onChanged: (_) => _clearAi('school_setting'),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _primaryLangCtrl,
                  decoration: _dec('Primary language',
                      hint: 'e.g. Telugu, English, Kannada',
                      aiKey: 'primary_language'),
                  textCapitalization: TextCapitalization.words,
                  onChanged: (_) => _clearAi('primary_language'),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _additionalLangsCtrl,
                  decoration: _dec('Additional languages',
                      hint: 'comma-separated, e.g. Hindi, English',
                      aiKey: 'additional_languages'),
                  textCapitalization: TextCapitalization.words,
                  onChanged: (_) => _clearAi('additional_languages'),
                ),
                const SizedBox(height: 32),

                // ── Clinical Details ────────────────────────────────────────
                _sectionLabel('Clinical Details'),
                const SizedBox(height: 12),
                TextField(
                  controller: _diagCtrl,
                  decoration: _dec('Diagnosis', aiKey: 'diagnosis'),
                  textCapitalization: TextCapitalization.sentences,
                  onChanged: (_) => _clearAi('diagnosis'),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _modalityCtrl,
                  decoration: _dec(
                    'Primary Communication Modality',
                    hint: 'e.g. Verbal, AAC device, PECS, Sign',
                    aiKey: 'primary_communication_modality',
                  ),
                  onChanged: (_) =>
                      _clearAi('primary_communication_modality'),
                ),
                const SizedBox(height: 12),
                _buildAacToggle(),
                const SizedBox(height: 32),

                // ── Clinical Intake ─────────────────────────────────────────
                _sectionLabel('Clinical Intake'),
                const SizedBox(height: 12),
                TextField(
                  controller: _secDiagCtrl,
                  decoration: _dec('Secondary Diagnosis (optional)',
                      aiKey: 'secondary_diagnosis'),
                  textCapitalization: TextCapitalization.sentences,
                  onChanged: (_) => _clearAi('secondary_diagnosis'),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _referralCtrl,
                  decoration: _dec('Referral Source (optional)',
                      aiKey: 'referral_source'),
                  textCapitalization: TextCapitalization.sentences,
                  onChanged: (_) => _clearAi('referral_source'),
                ),
                const SizedBox(height: 16),
                _buildPrevTherapySection(),
                const SizedBox(height: 16),
                TextField(
                  controller: _regulatoryCtrl,
                  decoration: _dec(
                    'Regulatory / Sensory Profile',
                    hint: 'Brief description of sensory and regulatory patterns',
                    aiKey: 'regulatory_profile',
                  ),
                  maxLines: 3,
                  textCapitalization: TextCapitalization.sentences,
                  onChanged: (_) => _clearAi('regulatory_profile'),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _baselineCtrl,
                  decoration: _dec(
                    'Baseline Summary',
                    hint: 'As of [date], [name] demonstrates...',
                    aiKey: 'baseline_summary',
                  ),
                  maxLines: 4,
                  textCapitalization: TextCapitalization.sentences,
                  onChanged: (_) => _clearAi('baseline_summary'),
                ),
                const SizedBox(height: 32),

                // ── Additional Notes ────────────────────────────────────────
                _sectionLabel('Additional Notes'),
                const SizedBox(height: 12),
                TextField(
                  controller: _notesCtrl,
                  decoration: _dec('Notes'),
                  maxLines: 4,
                  textCapitalization: TextCapitalization.sentences,
                ),
                const SizedBox(height: 36),

                // ── Save ────────────────────────────────────────────────────
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 480),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _isSaving ? null : _save,
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.teal,
                        padding:
                            const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: _isSaving
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                  color: Colors.white, strokeWidth: 2),
                            )
                          : Text(
                              _isEditMode ? 'Update Client' : 'Save Client',
                              style: const TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.w600),
                            ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Section widgets ───────────────────────────────────────────────────────────

  Widget _buildImportZone() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel('Import from Report'),
        const SizedBox(height: 12),

        // Voice intake button
        OutlinedButton.icon(
          onPressed: _openBrainDump,
          icon: const Icon(Icons.mic_rounded, size: 18),
          label: const Text('Tell Cue about this child'),
          style: OutlinedButton.styleFrom(
            foregroundColor: _teal,
            side: const BorderSide(color: _teal),
            backgroundColor: Colors.white,
            minimumSize: const Size(double.infinity, 48),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10)),
            textStyle: const TextStyle(fontSize: 14),
          ),
        ),
        const SizedBox(height: 12),

        // Upload zone — always visible
        GestureDetector(
          onTap: _isExtracting ? null : _pickFile,
          child: CustomPaint(
            painter: _DashedBorderPainter(
              color: _pickedFile != null ? _aiAccent : _ghost,
            ),
            child: SizedBox(
              height: 80,
              width: double.infinity,
              child: Center(
                child: _pickedFile != null
                    ? Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.description_outlined,
                              size: 18, color: _ghost),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              _pickedFile!.name,
                              style: const TextStyle(
                                  fontSize: 13, color: _ink),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      )
                    : const Text(
                        'Upload diagnostic report — PDF, Word, or image',
                        style: TextStyle(fontSize: 13, color: _ghost),
                      ),
              ),
            ),
          ),
        ),

        // Actions row — only when a file is selected
        if (_pickedFile != null) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              FilledButton(
                onPressed: _isExtracting ? null : _extractFromFile,
                style: FilledButton.styleFrom(
                  backgroundColor: _teal,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 20, vertical: 10),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
                child: _isExtracting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2),
                      )
                    : const Text('Extract with Cue AI',
                        style: TextStyle(fontSize: 13)),
              ),
              const SizedBox(width: 12),
              TextButton(
                onPressed: () => setState(() {
                  _pickedFile   = null;
                  _extractError = null;
                }),
                child: const Text('Remove',
                    style: TextStyle(color: _ghost, fontSize: 13)),
              ),
            ],
          ),
        ],

        // Inline error
        if (_extractError != null) ...[
          const SizedBox(height: 8),
          Text(
            _extractError!,
            style: const TextStyle(color: Colors.red, fontSize: 13),
          ),
        ],
      ],
    );
  }

  Widget _buildDobField() {
    final ai = _aiFields.contains('date_of_birth');
    return GestureDetector(
      onTap: _pickDob,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 15),
        decoration: BoxDecoration(
          color: ai ? _aiFill : Colors.grey.shade50,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: ai ? _aiAccent : Colors.grey.shade300,
            width: ai ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                _dateOfBirth != null
                    ? '${_dateOfBirth!.day.toString().padLeft(2, '0')} / '
                      '${_dateOfBirth!.month.toString().padLeft(2, '0')} / '
                      '${_dateOfBirth!.year}'
                    : 'Date of Birth',
                style: TextStyle(
                  fontSize: 16,
                  color: _dateOfBirth != null
                      ? Colors.black87
                      : Colors.grey.shade600,
                ),
              ),
            ),
            Icon(Icons.calendar_today_outlined,
                size: 18, color: Colors.grey.shade500),
          ],
        ),
      ),
    );
  }

  Widget _buildAacToggle() {
    final ai = _aiFields.contains('uses_aac');
    return Container(
      decoration: BoxDecoration(
        color: ai ? _aiFill : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: ai ? _aiAccent : Colors.grey.shade300,
          width: ai ? 2 : 1,
        ),
      ),
      child: SwitchListTile(
        title: const Text('Uses AAC Device'),
        subtitle: Text(
          _usesAac ? 'Yes' : 'No',
          style: TextStyle(
            color: _usesAac ? Colors.teal : Colors.grey.shade500,
            fontSize: 13,
          ),
        ),
        value: _usesAac,
        onChanged: (v) => setState(() {
          _usesAac = v;
          _clearAi('uses_aac');
        }),
        activeThumbColor: Colors.teal,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  Widget _buildPrevTherapySection() {
    final ai = _aiFields.contains('previous_therapy');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          decoration: BoxDecoration(
            color: ai ? _aiFill : Colors.grey.shade50,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: ai ? _aiAccent : Colors.grey.shade300,
              width: ai ? 2 : 1,
            ),
          ),
          child: SwitchListTile(
            title: const Text('Previous therapy history'),
            subtitle: Text(
              _prevTherapy ? 'Yes' : 'No',
              style: TextStyle(
                color: _prevTherapy ? Colors.teal : Colors.grey.shade500,
                fontSize: 13,
              ),
            ),
            value: _prevTherapy,
            onChanged: (v) => setState(() {
              _prevTherapy = v;
              _clearAi('previous_therapy');
            }),
            activeThumbColor: Colors.teal,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
        if (_prevTherapy) ...[
          const SizedBox(height: 12),
          TextField(
            controller: _prevDurationCtrl,
            decoration: _dec(
              'Duration',
              hint: 'e.g. 6 months, 2 years',
              aiKey: 'previous_therapy_duration',
            ),
            textCapitalization: TextCapitalization.sentences,
            onChanged: (_) => _clearAi('previous_therapy_duration'),
          ),
        ],
      ],
    );
  }

  // ── Phase 4.0.2 builders ──────────────────────────────────────────────────────

  Widget _buildPopulationDropdown() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButtonFormField<String>(
          initialValue: _populationType,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'Population *',
            border: InputBorder.none,
          ),
          items: _populationOptions
              .map((o) => DropdownMenuItem<String>(
                    value: o.value,
                    child: Text(o.label, style: const TextStyle(color: _ink)),
                  ))
              .toList(),
          onChanged: (v) {
            if (v != null) setState(() => _populationType = v);
          },
        ),
      ),
    );
  }

  Widget _buildConcernSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Editorial Playfair label — this is a primary clinical artifact (the
        // family's own framing), so it earns a serif voice. §13.15 / §13.8.
        Text(
          "Parent's concern",
          style: GoogleFonts.playfairDisplay(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: _ink,
            fontStyle: FontStyle.italic,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'In their words — quote the family as closely as possible.',
          style: TextStyle(fontSize: 12, color: _ghost),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _concernVerbatimCtrl,
          decoration: _dec(
            "What brought you in today?",
            hint: '"He gets stuck on the first sound when he\'s excited…"',
            aiKey: 'primary_concern_verbatim',
          ),
          maxLines: 4,
          textCapitalization: TextCapitalization.sentences,
          onChanged: (_) => _clearAi('primary_concern_verbatim'),
        ),
      ],
    );
  }

  // ── Form helpers ──────────────────────────────────────────────────────────────

  Widget _sectionLabel(String label) => Text(
        label.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: Colors.teal.shade600,
          letterSpacing: 1.1,
        ),
      );

  InputDecoration _dec(String label, {String? hint, String? aiKey}) {
    final ai = aiKey != null && _aiFields.contains(aiKey);
    return InputDecoration(
      labelText: label,
      hintText: hint,
      filled: true,
      fillColor: ai ? _aiFill : Colors.grey.shade50,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: ai
            ? const BorderSide(color: _aiAccent, width: 2)
            : BorderSide(color: Colors.grey.shade300),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Colors.teal, width: 2),
      ),
    );
  }
}

// ── Brain Dump bottom sheet ───────────────────────────────────────────────────

class _BrainDumpSheet extends StatefulWidget {
  final String? token;
  final void Function(Map<String, dynamic> data) onPopulated;

  const _BrainDumpSheet({required this.token, required this.onPopulated});

  @override
  State<_BrainDumpSheet> createState() => _BrainDumpSheetState();
}

class _BrainDumpSheetState extends State<_BrainDumpSheet> {
  final _speech = SpeechToText();

  bool   _speechAvailable = false;
  bool   _isListening     = false;  // mic is actively recording right now
  bool   _wantListening   = false;  // SLP intends to record (drives auto-restart)
  bool   _isExtracting    = false;
  String _accumulated     = '';     // full text built across all mic sessions
  String _previousText    = '';     // snapshot of _accumulated when mic starts
  String? _error;

  @override
  void initState() {
    super.initState();
    _initSpeech();
  }

  @override
  void dispose() {
    _speech.stop();
    super.dispose();
  }

  Future<void> _initSpeech() async {
    final available = await _speech.initialize(
      onStatus: (status) async {
        // Browser Web Speech API has a hard ~60 s session limit and fires
        // 'done' when it hits it. If the SLP is still recording, silently
        // restart — this creates an infinite listen loop that only breaks
        // when the SLP taps stop (_wantListening = false).
        if (status == 'done' && _wantListening && mounted) {
          _previousText = _accumulated;
          await _startListening();
          // _isListening stays true — no setState needed
          return;
        }
        // Any other terminal status while NOT wanting to record → update UI
        if ((status == 'done' || status == 'notListening') &&
            !_wantListening &&
            mounted) {
          setState(() => _isListening = false);
        }
      },
      onError: (e) {
        if (mounted) {
          setState(() {
            _error = 'Microphone error: ${e.errorMsg}';
            _isListening = false;
            _wantListening = false;
          });
        }
      },
    );
    if (mounted) setState(() => _speechAvailable = available);
  }

  Future<void> _startListening() async {
    await _speech.listen(
      onResult: (result) {
        if (mounted) {
          setState(() {
            _accumulated =
                ('$_previousText ${result.recognizedWords}').trim();
          });
        }
      },
      listenFor: const Duration(minutes: 10),
      pauseFor: const Duration(minutes: 10),
      localeId: 'en_IN',
      listenOptions: SpeechListenOptions(partialResults: true),
    );
    if (mounted) setState(() => _isListening = true);
  }

  Future<void> _toggleRecording() async {
    if (_isListening) {
      // Stop — keep _accumulated intact
      _wantListening = false;
      await _speech.stop();
      if (mounted) setState(() => _isListening = false);
    } else {
      // Start — snapshot current accumulated so partials don't double-count
      setState(() => _error = null);
      _previousText   = _accumulated;
      _wantListening  = true;
      await _startListening();
    }
  }

  void _clearTranscript() {
    _speech.stop();
    setState(() {
      _accumulated   = '';
      _previousText  = '';
      _isListening   = false;
      _wantListening = false;
      _error         = null;
    });
  }

  Future<void> _extract() async {
    final text = _accumulated.trim();
    if (text.isEmpty) return;
    setState(() { _isExtracting = true; _error = null; });

    try {
      // ignore: avoid_print
      print('[BrainDump] POST /extract — text length: ${text.length}');

      final response = await http.post(
        Uri.parse('https://cue-ai-proxy.onrender.com/extract'),
        headers: {
          'Content-Type': 'application/json',
          if (widget.token != null) 'Authorization': 'Bearer ${widget.token}',
        },
        body: jsonEncode({
          'model':        'claude-opus-4-5',
          'system':       _brainDumpSystem,
          'user_message': text,
        }),
      ).timeout(const Duration(seconds: 60));

      // ignore: avoid_print
      print('[BrainDump] response status: ${response.statusCode}');
      // ignore: avoid_print
      print('[BrainDump] response body: ${response.body}');

      if (response.statusCode != 200) {
        throw Exception('Proxy returned ${response.statusCode}: ${response.body}');
      }

      final Map<String, dynamic> respData;
      try {
        respData = jsonDecode(response.body) as Map<String, dynamic>;
      } catch (e) {
        // ignore: avoid_print
        print('[BrainDump] JSON decode of response failed: $e');
        throw Exception('Bad JSON from proxy: ${response.body}');
      }

      var rawText = (respData['result'] ?? '').toString().trim();
      // ignore: avoid_print
      print('[BrainDump] result field: $rawText');

      if (rawText.startsWith('```')) {
        rawText = rawText
            .replaceFirst(RegExp(r'^```[a-z]*\n?'), '')
            .replaceFirst(RegExp(r'```$'), '')
            .trim();
      }

      final Map<String, dynamic> data;
      try {
        data = jsonDecode(rawText) as Map<String, dynamic>;
      } catch (e) {
        // ignore: avoid_print
        print('[BrainDump] JSON decode of result failed: $e\nRaw: $rawText');
        throw Exception('Model returned non-JSON: $rawText');
      }

      if (mounted) Navigator.pop(context);
      widget.onPopulated(data);

    } catch (e, st) {
      // ignore: avoid_print
      print('[BrainDump] extraction error: $e\n$st');
      if (mounted) {
        setState(() => _error = 'Extract failed: $e');
      }
    } finally {
      if (mounted) setState(() => _isExtracting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.55,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, scrollController) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SingleChildScrollView(
          controller: scrollController,
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 36),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Drag handle
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // Title
              Text(
                'Tell me about this child',
                style: GoogleFonts.dmSans(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF0A1A2F),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Speak freely — diagnosis, history, AAC system, '
                'family context, anything you know.',
                style: GoogleFonts.dmSans(
                  fontSize: 13,
                  color: const Color(0xFF9CA3AF),
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 32),

              // Record button
              if (!_speechAvailable && _error == null)
                Center(
                  child: Text(
                    'Initialising microphone…',
                    style: GoogleFonts.dmSans(
                        fontSize: 13, color: const Color(0xFF9CA3AF)),
                  ),
                )
              else ...[
                Center(
                  child: GestureDetector(
                    onTap: _isExtracting ? null : _toggleRecording,
                    child: Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        color: _isListening
                            ? const Color(0xFFEF4444)
                            : const Color(0xFF1D9E75),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        _isListening
                            ? Icons.stop_rounded
                            : Icons.mic_rounded,
                        color: Colors.white,
                        size: 28,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Center(
                  child: Text(
                    _isListening
                        ? 'Tap to stop'
                        : (_accumulated.isEmpty
                            ? 'Tap to speak'
                            : 'Tap to continue'),
                    style: GoogleFonts.dmSans(
                        fontSize: 12, color: const Color(0xFF9CA3AF)),
                  ),
                ),
              ],

              // Live transcript + Clear button
              if (_accumulated.isNotEmpty) ...[
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Transcript',
                      style: GoogleFonts.dmSans(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF6B7690),
                      ),
                    ),
                    GestureDetector(
                      onTap: _clearTranscript,
                      child: Text(
                        'Clear',
                        style: GoogleFonts.dmSans(
                          fontSize: 12,
                          color: const Color(0xFFEF4444),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF5F5F0),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    _accumulated,
                    style: GoogleFonts.dmSans(
                      fontSize: 13,
                      color: const Color(0xFF1B2B4B),
                      height: 1.5,
                    ),
                  ),
                ),
              ],

              // Extract button — shown when recording stopped and transcript exists
              if (_accumulated.isNotEmpty && !_isListening) ...[
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _isExtracting ? null : _extract,
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF1D9E75),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    child: _isExtracting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2),
                          )
                        : Text(
                            'Extract with Cue AI',
                            style: GoogleFonts.dmSans(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                  ),
                ),
              ],

              // Error
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: GoogleFonts.dmSans(
                      fontSize: 13, color: Colors.red),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ── Dashed border painter for the upload zone ─────────────────────────────────

class _DashedBorderPainter extends CustomPainter {
  final Color color;
  const _DashedBorderPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    const dash = 6.0;
    const gap  = 4.0;
    _line(canvas, paint, Offset.zero, Offset(size.width, 0), dash, gap);
    _line(canvas, paint, Offset(size.width, 0),
        Offset(size.width, size.height), dash, gap);
    _line(canvas, paint, Offset(size.width, size.height),
        Offset(0, size.height), dash, gap);
    _line(canvas, paint, Offset(0, size.height), Offset.zero, dash, gap);
  }

  void _line(Canvas c, Paint p, Offset a, Offset b, double dash, double gap) {
    final dist = (b - a).distance;
    final dir  = (b - a) / dist;
    double d   = 0;
    while (d < dist) {
      final end = d + dash;
      c.drawLine(a + dir * d, a + dir * (end < dist ? end : dist), p);
      d += dash + gap;
    }
  }

  @override
  bool shouldRepaint(covariant _DashedBorderPainter old) =>
      old.color != color;
}
