import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme/cue_theme.dart';

class AddSessionScreen extends StatefulWidget {
  final String clientId;
  final String clientName;
  final Map<String, dynamic>? prefillData;

  const AddSessionScreen({
    super.key,
    required this.clientId,
    required this.clientName,
    this.prefillData,
  });

  @override
  State<AddSessionScreen> createState() => _AddSessionScreenState();
}

class _AddSessionScreenState extends State<AddSessionScreen> {
  final _supabase = Supabase.instance.client;

  late DateTime _selectedDate;
  late final TextEditingController _goalController;
  late final TextEditingController _activityController;
  late final TextEditingController _attemptsController;
  late final TextEditingController _independentController;
  late final TextEditingController _promptedController;
  late final TextEditingController _nextFocusController;

  late bool _goalMet;
  late String _clientAffect;
  bool _isSaving = false;
  bool _isSavingRecord = false;
  bool _isPrefilled = false;

  static const _affectOptions = ['Regulated', 'Mixed', 'Dysregulated'];

  @override
  void initState() {
    super.initState();
    final p = widget.prefillData;
    _isPrefilled = p != null;

    _selectedDate = _parseDate(p?['date']) ?? DateTime.now();
    _goalController = TextEditingController(
        text: p?['target_behaviour']?.toString() ?? '');
    _activityController =
        TextEditingController(text: p?['activity_name']?.toString() ?? '');
    _attemptsController = TextEditingController(
        text: p?['attempts'] != null ? '${p!['attempts']}' : '');
    _independentController = TextEditingController(
        text: p?['independent_responses'] != null
            ? '${p!['independent_responses']}'
            : '');
    _promptedController = TextEditingController(
        text: p?['prompted_responses'] != null
            ? '${p!['prompted_responses']}'
            : '');
    _nextFocusController = TextEditingController(
        text: p?['next_session_focus']?.toString() ?? '');

    final gm = p?['goal_met'];
    _goalMet = gm == true || gm == 'yes';

    final affect = p?['client_affect']?.toString() ?? 'Regulated';
    final normalised = affect.isNotEmpty
        ? affect[0].toUpperCase() + affect.substring(1)
        : 'Regulated';
    _clientAffect =
        _affectOptions.contains(normalised) ? normalised : 'Regulated';
  }

  @override
  void dispose() {
    _goalController.dispose();
    _activityController.dispose();
    _attemptsController.dispose();
    _independentController.dispose();
    _promptedController.dispose();
    _nextFocusController.dispose();
    super.dispose();
  }

  DateTime? _parseDate(dynamic raw) {
    if (raw == null) return null;
    return DateTime.tryParse(raw.toString());
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.light(
            primary: CueColors.accent,
            onPrimary: Colors.white,
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) setState(() => _selectedDate = picked);
  }

  Map<String, dynamic>? _parsedSoap() {
    final raw = widget.prefillData?['soap_note'];
    if (raw == null) return null;
    if (raw is Map<String, dynamic>) return raw;
    if (raw is String) {
      try {
        return jsonDecode(raw) as Map<String, dynamic>;
      } catch (_) {}
    }
    return null;
  }

  String? _parentSummaryText() {
    final raw = widget.prefillData?['parent_summary'];
    if (raw == null) return null;
    if (raw is String) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is String) return decoded;
      } catch (_) {}
      return raw;
    }
    return raw.toString();
  }

  Future<void> _save() async {
    setState(() => _isSaving = true);
    try {
      await _supabase.from('sessions').insert({
        'client_id': widget.clientId,
        'date': _selectedDate.toIso8601String().substring(0, 10),
        'target_behaviour': _goalController.text.trim(),
        'activity_name': _activityController.text.trim(),
        'attempts': int.tryParse(_attemptsController.text.trim()) ?? 0,
        'independent_responses':
            int.tryParse(_independentController.text.trim()) ?? 0,
        'prompted_responses':
            int.tryParse(_promptedController.text.trim()) ?? 0,
        'goal_met': _goalMet ? 'yes' : 'not_yet',
        'client_affect': _clientAffect.toLowerCase(),
        'next_session_focus': _nextFocusController.text.trim(),
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Session saved')),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving session: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _saveToRecords() async {
    setState(() => _isSavingRecord = true);
    try {
      final p = widget.prefillData;
      final userId = _supabase.auth.currentUser?.id;
      final soap = _parsedSoap();
      final soapJson = soap != null ? jsonEncode(soap) : null;

      await _supabase.from('sessions').insert({
        if (userId != null) 'user_id': userId,
        'client_id': widget.clientId,
        'date': _selectedDate.toIso8601String().substring(0, 10),
        'transcript': p?['transcript']?.toString() ?? '',
        if (soapJson != null) 'soap_note': soapJson,
        'parent_summary': _parentSummaryText() ?? '',
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Saved to records')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving record: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSavingRecord = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final soap = _parsedSoap();
    final summary = _parentSummaryText();

    return Scaffold(
      backgroundColor: CueColors.background,
      appBar: AppBar(
        title: const Text('New Session'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.clientName,
              style: GoogleFonts.inter(
                fontSize: 13,
                color: CueColors.inkSecondary,
                letterSpacing: 0.3,
              ),
            ),
            const SizedBox(height: 8),

            if (_isPrefilled) ...[
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: CueColors.accent.withOpacity(0.04),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: CueColors.divider),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.auto_awesome_outlined,
                        size: 16, color: CueColors.accent),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Fields pre-filled from narration — please review.',
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          color: CueColors.inkPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
            ],

            if (_isPrefilled && soap != null) ...[
              _buildSoapNote(soap),
              const SizedBox(height: 32),
            ],

            if (_isPrefilled && summary != null && summary.isNotEmpty) ...[
              CueTheme.eyebrow('Parent Summary'),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: CueColors.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: CueColors.divider),
                ),
                child: Text(
                  summary,
                  style: GoogleFonts.inter(
                      fontSize: 15, height: 1.55, color: CueColors.inkPrimary),
                ),
              ),
              const SizedBox(height: 32),
            ],

            // ── Session Date ──────────────────────────────────────────────
            _dateRow(),

            const SizedBox(height: 40),

            // ── Goals ─────────────────────────────────────────────────────
            CueTheme.sectionTitle('Goals'),
            const SizedBox(height: 20),
            _textField(_goalController, 'Goal / target behaviour',
                hint: 'e.g. Request items using core vocabulary', maxLines: 2),
            const SizedBox(height: 20),
            _textField(_activityController, 'Activity name',
                hint: 'e.g. Snack time, cause & effect toy play'),

            const SizedBox(height: 40),

            // ── Trial data ────────────────────────────────────────────────
            CueTheme.sectionTitle('Trial data'),
            const SizedBox(height: 20),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _TrialNumber(
                    controller: _attemptsController,
                    label: 'Attempts',
                  ),
                ),
                Expanded(
                  child: _TrialNumber(
                    controller: _independentController,
                    label: 'Independent',
                  ),
                ),
                Expanded(
                  child: _TrialNumber(
                    controller: _promptedController,
                    label: 'Prompted',
                  ),
                ),
              ],
            ),

            const SizedBox(height: 40),

            // ── Outcomes ──────────────────────────────────────────────────
            CueTheme.sectionTitle('Outcomes'),
            const SizedBox(height: 20),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Goal met',
                          style: GoogleFonts.inter(
                            fontSize: 15,
                            color: CueColors.inkPrimary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _goalMet ? 'Yes' : 'Not yet',
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            color: CueColors.inkSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    value: _goalMet,
                    onChanged: (v) => setState(() => _goalMet = v),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            Text(
              'Client affect',
              style: GoogleFonts.inter(
                fontSize: 13,
                color: CueColors.inkSecondary,
                letterSpacing: 0.2,
              ),
            ),
            const SizedBox(height: 12),
            _AffectSelector(
              selected: _clientAffect,
              onChanged: (v) => setState(() => _clientAffect = v),
            ),

            const SizedBox(height: 40),

            // ── Next steps ────────────────────────────────────────────────
            CueTheme.sectionTitle('Next steps'),
            const SizedBox(height: 20),
            _textField(_nextFocusController, 'Next session focus',
                hint: 'What to prioritise next session', maxLines: 2),

            const SizedBox(height: 48),

            SizedBox(
              height: 52,
              child: FilledButton(
                onPressed: _isSaving ? null : _save,
                child: _isSaving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2),
                      )
                    : const Text('Save Session'),
              ),
            ),

            if (_isPrefilled) ...[
              const SizedBox(height: 12),
              SizedBox(
                height: 52,
                child: OutlinedButton.icon(
                  onPressed: _isSavingRecord ? null : _saveToRecords,
                  icon: _isSavingRecord
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: CueColors.inkPrimary),
                        )
                      : const Icon(Icons.save_outlined, size: 18),
                  label: Text(_isSavingRecord ? 'Saving…' : 'Save to Records'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _dateRow() {
    return InkWell(
      onTap: _pickDate,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: const BoxDecoration(
          border: Border(
            bottom: BorderSide(color: CueColors.divider, width: 1),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Session date',
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      color: CueColors.inkSecondary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${_selectedDate.day.toString().padLeft(2, '0')} '
                    '${_monthName(_selectedDate.month)} '
                    '${_selectedDate.year}',
                    style: GoogleFonts.inter(
                      fontSize: 16,
                      color: CueColors.inkPrimary,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.calendar_today_outlined,
                size: 18, color: CueColors.inkTertiary),
          ],
        ),
      ),
    );
  }

  Widget _buildSoapNote(Map<String, dynamic> soap) {
    final sections = [
      ('Subjective', soap['subjective']?.toString() ?? ''),
      ('Objective', soap['objective']?.toString() ?? ''),
      ('Assessment', soap['assessment']?.toString() ?? ''),
      ('Plan', soap['plan']?.toString() ?? ''),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CueTheme.eyebrow('SOAP Note'),
        const SizedBox(height: 12),
        ...sections.map((s) => Container(
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(
                color: CueColors.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: CueColors.divider),
              ),
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    s.$1,
                    style: GoogleFonts.fraunces(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: CueColors.inkPrimary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    s.$2.isNotEmpty ? s.$2 : '—',
                    style: GoogleFonts.inter(
                      fontSize: 15,
                      height: 1.55,
                      color: CueColors.inkPrimary,
                    ),
                  ),
                ],
              ),
            )),
      ],
    );
  }

  Widget _textField(
    TextEditingController controller,
    String label, {
    String? hint,
    int maxLines = 1,
  }) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      textCapitalization: TextCapitalization.sentences,
      style: GoogleFonts.inter(fontSize: 16, color: CueColors.inkPrimary),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
      ),
    );
  }

  String _monthName(int month) {
    const months = [
      '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return months[month];
  }
}

// ── Trial data: large Fraunces number + Inter label ────────────────────────────
class _TrialNumber extends StatefulWidget {
  final TextEditingController controller;
  final String label;

  const _TrialNumber({required this.controller, required this.label});

  @override
  State<_TrialNumber> createState() => _TrialNumberState();
}

class _TrialNumberState extends State<_TrialNumber> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(() => setState(() {}));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          height: 48,
          child: TextField(
            controller: widget.controller,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            textAlign: TextAlign.center,
            style: GoogleFonts.fraunces(
              fontSize: 32,
              fontWeight: FontWeight.w500,
              color: CueColors.inkPrimary,
              height: 1,
            ),
            decoration: const InputDecoration(
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              filled: false,
              contentPadding: EdgeInsets.zero,
              isDense: true,
              hintText: '0',
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          widget.label.toUpperCase(),
          style: GoogleFonts.inter(
            fontSize: 11,
            color: CueColors.inkSecondary,
            fontWeight: FontWeight.w500,
            letterSpacing: 1.2,
          ),
        ),
      ],
    );
  }
}

// ── Affect selector: text + underline indicator ────────────────────────────────
class _AffectSelector extends StatelessWidget {
  final String selected;
  final ValueChanged<String> onChanged;

  static const _options = ['Regulated', 'Mixed', 'Dysregulated'];

  const _AffectSelector({required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: _options.map((label) {
        final isSelected = selected == label;
        return Expanded(
          child: InkWell(
            onTap: () => onChanged(label),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: isSelected
                        ? CueColors.accent
                        : CueColors.divider,
                    width: isSelected ? 2 : 1,
                  ),
                ),
              ),
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  fontSize: 14,
                  fontWeight:
                      isSelected ? FontWeight.w600 : FontWeight.w400,
                  color: isSelected
                      ? CueColors.inkPrimary
                      : CueColors.inkSecondary,
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}
