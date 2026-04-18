import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../widgets/app_layout.dart';

const _kDomains = [
  'Regulation',
  'Joint Attention & Engagement',
  'AAC & Augmentative Communication',
  'Functional Communication',
  'Language',
  'Speech Motor',
  'Literacy',
  'Social Communication',
];

class AddGoalScreen extends StatefulWidget {
  final String clientId;
  final Map<String, dynamic>? goal; // non-null = edit mode

  const AddGoalScreen({
    super.key,
    required this.clientId,
    this.goal,
  });

  @override
  State<AddGoalScreen> createState() => _AddGoalScreenState();
}

class _AddGoalScreenState extends State<AddGoalScreen> {
  final _supabase = Supabase.instance.client;
  final _formKey = GlobalKey<FormState>();
  final _goalTextController = TextEditingController();

  String? _domain;
  double _targetAccuracy = 80;
  bool _isSaving = false;

  bool get _isEditMode => widget.goal != null;

  @override
  void initState() {
    super.initState();
    if (_isEditMode) {
      final g = widget.goal!;
      _goalTextController.text = g['goal_text'] as String? ?? '';
      _domain = g['domain'] as String?;
      _targetAccuracy = ((g['target_accuracy'] as num?)?.toDouble() ?? 80)
          .clamp(50, 100);
    }
  }

  @override
  void dispose() {
    _goalTextController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_domain == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a domain.')),
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      final payload = {
        'goal_text': _goalTextController.text.trim(),
        'domain': _domain,
        'target_accuracy': _targetAccuracy.round(),
      };

      if (_isEditMode) {
        await _supabase
            .from('goals')
            .update(payload)
            .eq('id', widget.goal!['id']);
      } else {
        await _supabase.from('goals').insert({
          ...payload,
          'client_id': widget.clientId,
          'status': 'active',
        });
      }

      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Could not save goal. Please try again.')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppLayout(
      title: _isEditMode ? 'Edit Goal' : 'Add Goal',
      activeRoute: 'roster',
      body: SingleChildScrollView(
        padding:
            const EdgeInsets.symmetric(horizontal: 48, vertical: 32),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ── Goal Text ────────────────────────────────────────
                  _sectionLabel('Goal'),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _goalTextController,
                    minLines: 3,
                    maxLines: 6,
                    decoration: _inputDecoration(
                        'Describe the therapy goal'),
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? 'Goal text is required'
                        : null,
                  ),
                  const SizedBox(height: 24),

                  // ── Domain ───────────────────────────────────────────
                  _sectionLabel('Domain'),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    value: _domain,
                    decoration: _inputDecoration('Select a domain'),
                    items: _kDomains
                        .map((d) => DropdownMenuItem(
                              value: d,
                              child: Text(d,
                                  style: const TextStyle(fontSize: 14)),
                            ))
                        .toList(),
                    onChanged: (v) => setState(() => _domain = v),
                    validator: (v) =>
                        v == null ? 'Please select a domain' : null,
                  ),
                  const SizedBox(height: 24),

                  // ── Target Accuracy ──────────────────────────────────
                  _sectionLabel('Target Accuracy'),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Slide to set target',
                        style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey.shade500),
                      ),
                      Text(
                        '${_targetAccuracy.round()}%',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF00897B),
                        ),
                      ),
                    ],
                  ),
                  Slider(
                    value: _targetAccuracy,
                    min: 50,
                    max: 100,
                    divisions: 10,
                    activeColor: const Color(0xFF00897B),
                    label: '${_targetAccuracy.round()}%',
                    onChanged: (v) =>
                        setState(() => _targetAccuracy = v),
                  ),
                  const SizedBox(height: 32),

                  // ── Save button ──────────────────────────────────────
                  ConstrainedBox(
                    constraints:
                        const BoxConstraints(maxWidth: 480),
                    child: SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: FilledButton(
                        onPressed: _isSaving ? null : _save,
                        style: FilledButton.styleFrom(
                          backgroundColor:
                              const Color(0xFF00897B),
                          disabledBackgroundColor:
                              const Color(0xFF00897B)
                                  .withValues(alpha: 0.5),
                          shape: RoundedRectangleBorder(
                            borderRadius:
                                BorderRadius.circular(14),
                          ),
                        ),
                        child: _isSaving
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2),
                              )
                            : Text(
                                _isEditMode
                                    ? 'Save Changes'
                                    : 'Add Goal',
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _sectionLabel(String text) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w700,
        color: Color(0xFF1A1A2E),
        letterSpacing: 0.2,
      ),
    );
  }

  InputDecoration _inputDecoration(String label) {
    return InputDecoration(
      labelText: label,
      filled: true,
      fillColor: Colors.grey.shade50,
      labelStyle:
          TextStyle(color: Colors.grey.shade500, fontSize: 14),
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey.shade200),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey.shade200),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide:
            const BorderSide(color: Color(0xFF00897B), width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.red.shade300),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.red.shade400, width: 2),
      ),
    );
  }
}
