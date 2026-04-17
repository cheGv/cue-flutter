import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../widgets/app_layout.dart';

class AddSessionScreen extends StatefulWidget {
  final String clientId;
  final String clientName;

  /// Optional pre-filled data from voice narration extraction.
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

  static const _affectOptions = ['Regulated', 'Dysregulated', 'Mixed'];

  @override
  void initState() {
    super.initState();
    final p = widget.prefillData;
    _isPrefilled = p != null;

    _selectedDate = _parseDate(p?['date']) ?? DateTime.now();

    _goalController =
        TextEditingController(text: p?['target_behaviour']?.toString() ?? '');
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
    _clientAffect =
        _affectOptions.contains(affect) ? affect : 'Regulated';
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
          colorScheme: ColorScheme.light(
            primary: Colors.teal,
            onPrimary: Colors.white,
            surface: Colors.white,
            onSurface: Colors.black,
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
          const SnackBar(
            content: Text('Saved to records'),
            backgroundColor: Colors.teal,
          ),
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

  Widget _buildSoapNote(Map<String, dynamic> soap) {
    final sections = [
      ['Subjective', 'subjective'],
      ['Objective', 'objective'],
      ['Assessment', 'assessment'],
      ['Plan', 'plan'],
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel('SOAP Note'),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: Colors.teal.shade100),
            borderRadius: BorderRadius.circular(12),
            color: Colors.white,
          ),
          child: Column(
            children: List.generate(sections.length, (i) {
              final label = sections[i][0];
              final key = sections[i][1];
              final text = soap[key]?.toString() ?? '';
              final isLast = i == sections.length - 1;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                    child: Text(
                      label.toUpperCase(),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Colors.teal.shade600,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    child: Text(
                      text.isNotEmpty ? text : '—',
                      style: const TextStyle(fontSize: 14, height: 1.55),
                    ),
                  ),
                  if (!isLast) Divider(height: 1, color: Colors.teal.shade50),
                ],
              );
            }),
          ),
        ),
      ],
    );
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
          const SnackBar(
            content: Text('Session saved'),
            backgroundColor: Colors.teal,
          ),
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

  @override
  Widget build(BuildContext context) {
    final soap = _parsedSoap();
    final summary = _parentSummaryText();

    return AppLayout(
      title: 'New Session — ${widget.clientName}',
      activeRoute: 'roster',
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: SingleChildScrollView(
            padding:
                const EdgeInsets.symmetric(horizontal: 48, vertical: 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Pre-fill banner
                if (_isPrefilled) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.teal.shade50,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.teal.shade200),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.auto_awesome,
                            size: 16, color: Colors.teal.shade700),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Fields pre-filled from your narration — please review before saving.',
                            style: TextStyle(
                                fontSize: 13,
                                color: Colors.teal.shade800),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                ],

                if (_isPrefilled && soap != null) ...[
                  _buildSoapNote(soap),
                  const SizedBox(height: 24),
                ],

                if (_isPrefilled &&
                    summary != null &&
                    summary.isNotEmpty) ...[
                  _sectionLabel('Parent Summary'),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.teal.shade100),
                      borderRadius: BorderRadius.circular(12),
                      color: Colors.white,
                    ),
                    child: Text(
                      summary,
                      style:
                          const TextStyle(fontSize: 14, height: 1.55),
                    ),
                  ),
                  const SizedBox(height: 24),
                ],

                _sectionLabel('Session Date'),
                const SizedBox(height: 10),
                GestureDetector(
                  onTap: _pickDate,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 14),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.calendar_today,
                            size: 18, color: Colors.teal.shade600),
                        const SizedBox(width: 12),
                        Text(
                          '${_selectedDate.day.toString().padLeft(2, '0')} '
                          '${_monthName(_selectedDate.month)} '
                          '${_selectedDate.year}',
                          style: const TextStyle(fontSize: 14),
                        ),
                        const Spacer(),
                        Icon(Icons.edit,
                            size: 16, color: Colors.grey.shade400),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 24),
                _sectionLabel('Goals & Activity'),
                const SizedBox(height: 12),
                _textField(
                  controller: _goalController,
                  label: 'Goal / Target Behaviour',
                  hint: 'e.g. Request items using core vocabulary',
                  maxLines: 2,
                ),
                const SizedBox(height: 16),
                _textField(
                  controller: _activityController,
                  label: 'Activity Name',
                  hint: 'e.g. Snack time, cause & effect toy play',
                ),

                const SizedBox(height: 24),
                _sectionLabel('Trial Data'),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _numberField(
                        controller: _attemptsController,
                        label: 'Total Attempts',
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _numberField(
                        controller: _independentController,
                        label: 'Independent',
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _numberField(
                        controller: _promptedController,
                        label: 'Prompted',
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 24),
                _sectionLabel('Outcomes'),
                const SizedBox(height: 12),

                Container(
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: SwitchListTile(
                    title: const Text('Goal Met'),
                    subtitle: Text(
                      _goalMet ? 'Yes' : 'Not yet',
                      style: TextStyle(
                        color: _goalMet
                            ? Colors.teal
                            : Colors.grey.shade500,
                        fontSize: 13,
                      ),
                    ),
                    value: _goalMet,
                    onChanged: (v) => setState(() => _goalMet = v),
                    activeColor: Colors.teal,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                DropdownButtonFormField<String>(
                  value: _clientAffect,
                  decoration:
                      _inputDecoration('Client Affect / Regulation'),
                  items: _affectOptions
                      .map((o) =>
                          DropdownMenuItem(value: o, child: Text(o)))
                      .toList(),
                  onChanged: (v) =>
                      setState(() => _clientAffect = v!),
                ),

                const SizedBox(height: 24),
                _sectionLabel('Next Steps'),
                const SizedBox(height: 12),
                _textField(
                  controller: _nextFocusController,
                  label: 'Next Session Focus',
                  hint: 'What to prioritise next session',
                  maxLines: 2,
                ),

                const SizedBox(height: 36),
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
                          : const Text(
                              'Save Session',
                              style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600),
                            ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                if (_isPrefilled) ...[
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 480),
                    child: SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed:
                            _isSavingRecord ? null : _saveToRecords,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.teal,
                          side: const BorderSide(color: Colors.teal),
                          padding: const EdgeInsets.symmetric(
                              vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        icon: _isSavingRecord
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.teal),
                              )
                            : const Icon(Icons.save_rounded),
                        label: Text(
                          _isSavingRecord
                              ? 'Saving…'
                              : 'Save to Records',
                          style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _sectionLabel(String label) {
    return Text(
      label.toUpperCase(),
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        color: Colors.teal.shade600,
        letterSpacing: 1.1,
      ),
    );
  }

  Widget _textField({
    required TextEditingController controller,
    required String label,
    String? hint,
    int maxLines = 1,
  }) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      textCapitalization: TextCapitalization.sentences,
      decoration: _inputDecoration(label, hint: hint),
    );
  }

  Widget _numberField({
    required TextEditingController controller,
    required String label,
  }) {
    return TextField(
      controller: controller,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      textAlign: TextAlign.center,
      decoration: _inputDecoration(label),
    );
  }

  InputDecoration _inputDecoration(String label, {String? hint}) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      filled: true,
      fillColor: Colors.grey.shade50,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Colors.teal, width: 2),
      ),
    );
  }

  String _monthName(int month) {
    const months = [
      '',
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec'
    ];
    return months[month];
  }
}
