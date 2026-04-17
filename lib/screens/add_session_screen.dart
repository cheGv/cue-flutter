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

  late bool   _goalMet;
  late String _clientAffect;
  bool _isSaving       = false;
  bool _isSavingRecord = false;
  bool _isPrefilled    = false;

  // Affect options: value → label/colour
  static const _affectOptions = ['Regulated', 'Mixed', 'Dysregulated'];

  @override
  void initState() {
    super.initState();
    final p = widget.prefillData;
    _isPrefilled = p != null;

    _selectedDate       = _parseDate(p?['date']) ?? DateTime.now();
    _goalController     = TextEditingController(text: p?['target_behaviour']?.toString() ?? '');
    _activityController = TextEditingController(text: p?['activity_name']?.toString() ?? '');
    _attemptsController = TextEditingController(
        text: p?['attempts'] != null ? '${p!['attempts']}' : '');
    _independentController = TextEditingController(
        text: p?['independent_responses'] != null ? '${p!['independent_responses']}' : '');
    _promptedController = TextEditingController(
        text: p?['prompted_responses'] != null ? '${p!['prompted_responses']}' : '');
    _nextFocusController =
        TextEditingController(text: p?['next_session_focus']?.toString() ?? '');

    final gm = p?['goal_met'];
    _goalMet = gm == true || gm == 'yes';

    final affect = p?['client_affect']?.toString() ?? 'Regulated';
    final normalised = affect[0].toUpperCase() + affect.substring(1);
    _clientAffect = _affectOptions.contains(normalised) ? normalised : 'Regulated';
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
            primary: CueColors.inkNavy,
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
      try { return jsonDecode(raw) as Map<String, dynamic>; } catch (_) {}
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
        'independent_responses': int.tryParse(_independentController.text.trim()) ?? 0,
        'prompted_responses': int.tryParse(_promptedController.text.trim()) ?? 0,
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
      final p       = widget.prefillData;
      final userId  = _supabase.auth.currentUser?.id;
      final soap    = _parsedSoap();
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

  // ── Build ────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final soap    = _parsedSoap();
    final summary = _parentSummaryText();

    return Scaffold(
      backgroundColor: CueColors.softWhite,
      appBar: AppBar(
        title: Text(
          'New Session — ${widget.clientName}',
          style: GoogleFonts.dmSans(
              color: Colors.white, fontSize: 17, fontWeight: FontWeight.w600),
        ),
        backgroundColor: CueColors.inkNavy,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [

            // ── Pre-fill banner ─────────────────────────────────────────
            if (_isPrefilled) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: CueColors.signalTeal.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: CueColors.signalTeal.withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.auto_awesome,
                        size: 16, color: CueColors.signalTeal),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Fields pre-filled from your narration — please review before saving.',
                        style: GoogleFonts.dmSans(
                            fontSize: 13, color: CueColors.inkNavy),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
            ],

            // ── SOAP note (pre-fill) ────────────────────────────────────
            if (_isPrefilled && soap != null) ...[
              _buildSoapNote(soap),
              const SizedBox(height: 24),
            ],

            // ── Parent summary (pre-fill) ──────────────────────────────
            if (_isPrefilled && summary != null && summary.isNotEmpty) ...[
              CueTheme.sectionLabel('Parent Summary'),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: CueColors.surfaceWhite,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: CueColors.inkNavy.withOpacity(0.15)),
                ),
                child: Text(summary,
                    style: GoogleFonts.dmSans(
                        fontSize: 14, height: 1.55, color: CueColors.inkNavy)),
              ),
              const SizedBox(height: 24),
            ],

            // ── Date ───────────────────────────────────────────────────
            CueTheme.sectionLabel('Session Date'),
            const SizedBox(height: 10),
            GestureDetector(
              onTap: _pickDate,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: CueColors.surfaceWhite,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: CueColors.inkNavy.withOpacity(0.2)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.calendar_today,
                        size: 18, color: CueColors.signalTeal),
                    const SizedBox(width: 12),
                    Text(
                      '${_selectedDate.day.toString().padLeft(2, '0')} '
                      '${_monthName(_selectedDate.month)} '
                      '${_selectedDate.year}',
                      style: GoogleFonts.dmSans(
                          fontSize: 15, color: CueColors.inkNavy),
                    ),
                    const Spacer(),
                    Icon(Icons.edit, size: 16, color: CueColors.textMid),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),
            CueTheme.sectionLabel('Goals & Activity'),
            const SizedBox(height: 12),
            _textField(_goalController, 'Goal / Target Behaviour',
                hint: 'e.g. Request items using core vocabulary', maxLines: 2),
            const SizedBox(height: 16),
            _textField(_activityController, 'Activity Name',
                hint: 'e.g. Snack time, cause & effect toy play'),

            // ── Trial data cards ────────────────────────────────────────
            const SizedBox(height: 24),
            CueTheme.sectionLabel('Trial Data'),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _TrialCard(
                    controller: _attemptsController,
                    label: 'Attempts',
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _TrialCard(
                    controller: _independentController,
                    label: 'Independent',
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _TrialCard(
                    controller: _promptedController,
                    label: 'Prompted',
                  ),
                ),
              ],
            ),

            // ── Outcomes ───────────────────────────────────────────────
            const SizedBox(height: 24),
            CueTheme.sectionLabel('Outcomes'),
            const SizedBox(height: 12),

            // Goal met toggle
            Container(
              decoration: BoxDecoration(
                color: CueColors.surfaceWhite,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: CueColors.inkNavy.withOpacity(0.2)),
              ),
              child: SwitchListTile(
                title: Text('Goal Met',
                    style: GoogleFonts.dmSans(
                        fontSize: 15, color: CueColors.inkNavy)),
                subtitle: Text(
                  _goalMet ? 'Yes' : 'Not yet',
                  style: GoogleFonts.dmSans(
                    fontSize: 13,
                    color: _goalMet ? CueColors.warmAmber : CueColors.textMid,
                    fontWeight: _goalMet ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
                value: _goalMet,
                onChanged: (v) => setState(() => _goalMet = v),
                activeColor: CueColors.warmAmber,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 16),

            // Affect — segmented buttons
            Text('Client Affect',
                style: GoogleFonts.dmSans(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: CueColors.textMid)),
            const SizedBox(height: 8),
            _AffectSelector(
              selected: _clientAffect,
              onChanged: (v) => setState(() => _clientAffect = v),
            ),

            const SizedBox(height: 24),
            CueTheme.sectionLabel('Next Steps'),
            const SizedBox(height: 12),
            _textField(_nextFocusController, 'Next Session Focus',
                hint: 'What to prioritise next session', maxLines: 2),

            const SizedBox(height: 36),

            // ── Save button ─────────────────────────────────────────────
            SizedBox(
              width: double.infinity,
              height: 52,
              child: FilledButton(
                onPressed: _isSaving ? null : _save,
                style: FilledButton.styleFrom(
                  backgroundColor: CueColors.inkNavy,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                child: _isSaving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2),
                      )
                    : Text(
                        'Save Session',
                        style: GoogleFonts.dmSans(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: Colors.white),
                      ),
              ),
            ),
            const SizedBox(height: 16),

            // Save to Records (narrated sessions only)
            if (_isPrefilled) ...[
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _isSavingRecord ? null : _saveToRecords,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: CueColors.inkNavy,
                    side: BorderSide(
                        color: CueColors.inkNavy.withOpacity(0.4)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  icon: _isSavingRecord
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: CueColors.inkNavy),
                        )
                      : const Icon(Icons.save_rounded, size: 18),
                  label: Text(
                    _isSavingRecord ? 'Saving…' : 'Save to Records',
                    style: GoogleFonts.dmSans(
                        fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              const SizedBox(height: 24),
            ],
          ],
        ),
      ),
    );
  }

  // ── SOAP note display (for pre-filled narrated sessions) ─────────────────────
  Widget _buildSoapNote(Map<String, dynamic> soap) {
    final sections = [
      ('SUBJECTIVE', soap['subjective']?.toString() ?? ''),
      ('OBJECTIVE',  soap['objective']?.toString() ?? ''),
      ('ASSESSMENT', soap['assessment']?.toString() ?? ''),
      ('PLAN',       soap['plan']?.toString() ?? ''),
    ];
    final colors = CueTheme.soapColors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CueTheme.sectionLabel('SOAP Note'),
        const SizedBox(height: 12),
        ...List.generate(sections.length, (i) {
          final label = sections[i].$1;
          final text  = sections[i].$2;
          return Container(
            margin: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(
              color: CueColors.surfaceWhite,
              borderRadius: BorderRadius.circular(12),
              border: Border(left: BorderSide(color: colors[i], width: 4)),
              boxShadow: [
                BoxShadow(
                  color: CueColors.inkNavy.withOpacity(0.04),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: GoogleFonts.dmSans(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: colors[i],
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  text.isNotEmpty ? text : '—',
                  style: GoogleFonts.dmSans(
                      fontSize: 14,
                      height: 1.55,
                      color: CueColors.inkNavy),
                ),
              ],
            ),
          );
        }),
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
      style: GoogleFonts.dmSans(fontSize: 15, color: CueColors.inkNavy),
      decoration: CueTheme.inputDecoration(label, hint: hint),
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

// ── Trial data card ────────────────────────────────────────────────────────────
class _TrialCard extends StatefulWidget {
  final TextEditingController controller;
  final String label;

  const _TrialCard({required this.controller, required this.label});

  @override
  State<_TrialCard> createState() => _TrialCardState();
}

class _TrialCardState extends State<_TrialCard> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(() => setState(() {}));
  }

  @override
  Widget build(BuildContext context) {
    final value = widget.controller.text;
    return Container(
      decoration: BoxDecoration(
        color: CueColors.surfaceWhite,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: CueColors.inkNavy.withOpacity(0.2)),
      ),
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
      child: Column(
        children: [
          // Large editable number
          TextField(
            controller: widget.controller,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            textAlign: TextAlign.center,
            style: GoogleFonts.dmSans(
              fontSize: 28,
              fontWeight: FontWeight.w700,
              color: CueColors.inkNavy,
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
          const SizedBox(height: 4),
          Text(
            widget.label,
            style: GoogleFonts.dmSans(
              fontSize: 11,
              color: CueColors.textMid,
              fontWeight: FontWeight.w500,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

// ── Affect segmented selector ──────────────────────────────────────────────────
class _AffectSelector extends StatelessWidget {
  final String selected;
  final ValueChanged<String> onChanged;

  static const _options = [
    ('Regulated',    CueColors.signalTeal),
    ('Mixed',        CueColors.warmAmber),
    ('Dysregulated', CueColors.errorRed),
  ];

  const _AffectSelector({required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(_options.length, (i) {
        final label   = _options[i].$1;
        final color   = _options[i].$2;
        final isSelected = selected == label;
        final isLast  = i == _options.length - 1;

        return Expanded(
          child: GestureDetector(
            onTap: () => onChanged(label),
            child: Container(
              margin: EdgeInsets.only(right: isLast ? 0 : 8),
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: isSelected ? color : CueColors.surfaceWhite,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: isSelected ? color : CueColors.inkNavy.withOpacity(0.2),
                ),
              ),
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: GoogleFonts.dmSans(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: isSelected ? Colors.white : CueColors.textMid,
                ),
              ),
            ),
          ),
        );
      }),
    );
  }
}
