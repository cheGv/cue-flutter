import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme/cue_phase4_tokens.dart';
import '../widgets/app_layout.dart';

class SessionNoteScreen extends StatefulWidget {
  final String clientId;
  final String clientName;

  const SessionNoteScreen({
    super.key,
    required this.clientId,
    required this.clientName,
  });

  @override
  State<SessionNoteScreen> createState() => _SessionNoteScreenState();
}

class _SessionNoteScreenState extends State<SessionNoteScreen> {
  final _supabase = Supabase.instance.client;
  int _currentStep = 0;
  bool _isSaving = false;

  // Phase 4.0.4 — population routing.
  String? _populationType;
  bool    _populationLoading = true;
  Map<String, dynamic>? _latestLiveEntryPayload;

  @override
  void initState() {
    super.initState();
    _loadPopulationAndLatestLiveEntry();
  }

  Future<void> _loadPopulationAndLatestLiveEntry() async {
    try {
      final clientRow = await _supabase
          .from('clients')
          .select('population_type')
          .eq('id', widget.clientId)
          .maybeSingle();
      final pop =
          (clientRow?['population_type'] as String?) ?? 'asd_aac';

      Map<String, dynamic>? latest;
      if (pop == 'developmental_stuttering') {
        final row = await _supabase
            .from('sessions')
            .select('population_payload, date')
            .eq('client_id', widget.clientId)
            .not('population_payload', 'is', null)
            .order('date', ascending: false)
            .order('id', ascending: false)
            .limit(1)
            .maybeSingle();
        final p = row?['population_payload'];
        if (p is Map) {
          latest = Map<String, dynamic>.from(p);
        }
      }

      if (!mounted) return;
      setState(() {
        _populationType = pop;
        _latestLiveEntryPayload = latest;
        _populationLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _populationType = 'asd_aac';
        _populationLoading = false;
      });
    }
  }

  // Step 1 – Barrier Analysis
  bool _barrierMotor = false;
  bool _barrierLinguistic = false;
  bool _barrierCognitive = false;
  bool _barrierSensory = false;
  bool _barrierEnvironmental = false;
  bool _barrierMotivational = false;
  bool _barrierDeviceAccess = false;

  // Step 2 – Session Goal
  final _targetBehaviourController = TextEditingController();
  final _conditionController = TextEditingController();
  final _criterionController = TextEditingController();

  // Step 3 – Activity
  final _activityNameController = TextEditingController();
  final _activityRationaleController = TextEditingController();

  // Step 4 – Prompt Hierarchy
  String _promptApproach = 'most_to_least';
  int _promptLevelUsed = 1;

  // Step 5 – During Session
  final _attemptsController = TextEditingController();
  final _independentResponsesController = TextEditingController();
  final _promptedResponsesController = TextEditingController();
  String _clientAffect = 'regulated';

  // Step 6 – Post Session
  String _goalMet = 'yes';
  final _homeProgrammeController = TextEditingController();
  final _nextSessionFocusController = TextEditingController();

  static const _stepLabels = [
    'Barriers',
    'Goal',
    'Activity',
    'Prompts',
    'Session',
    'Post',
  ];

  static const _promptDescriptions = {
    1: 'Independent',
    2: 'Gesture / Visual',
    3: 'Verbal',
    4: 'Model',
    5: 'Partial Physical',
    6: 'Full Physical',
  };

  @override
  void dispose() {
    _targetBehaviourController.dispose();
    _conditionController.dispose();
    _criterionController.dispose();
    _activityNameController.dispose();
    _activityRationaleController.dispose();
    _attemptsController.dispose();
    _independentResponsesController.dispose();
    _promptedResponsesController.dispose();
    _homeProgrammeController.dispose();
    _nextSessionFocusController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _isSaving = true);
    try {
      await _supabase.from('sessions').insert({
        'client_id': widget.clientId,
        'date': DateTime.now().toIso8601String().substring(0, 10),
        'barrier_motor': _barrierMotor,
        'barrier_linguistic': _barrierLinguistic,
        'barrier_cognitive': _barrierCognitive,
        'barrier_sensory': _barrierSensory,
        'barrier_environmental': _barrierEnvironmental,
        'barrier_motivational': _barrierMotivational,
        'barrier_device_access': _barrierDeviceAccess,
        'target_behaviour': _targetBehaviourController.text.trim(),
        'condition': _conditionController.text.trim(),
        'criterion': _criterionController.text.trim(),
        'activity_name': _activityNameController.text.trim(),
        'activity_rationale': _activityRationaleController.text.trim(),
        'prompt_approach': _promptApproach,
        'prompt_level_used': _promptLevelUsed,
        'attempts': int.tryParse(_attemptsController.text) ?? 0,
        'independent_responses':
            int.tryParse(_independentResponsesController.text) ?? 0,
        'prompted_responses':
            int.tryParse(_promptedResponsesController.text) ?? 0,
        'client_affect': _clientAffect,
        'goal_met': _goalMet,
        'home_programme': _homeProgrammeController.text.trim(),
        'next_session_focus': _nextSessionFocusController.text.trim(),
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Session saved successfully'),
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

  // ── Build ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_populationLoading) {
      return AppLayout(
        title: 'Session — ${widget.clientName}',
        activeRoute: 'roster',
        body: const SizedBox.shrink(),
      );
    }

    if (_populationType == 'developmental_stuttering') {
      return AppLayout(
        title: 'Session — ${widget.clientName}',
        activeRoute: 'roster',
        body: _FluencySessionSummary(
          clientName: widget.clientName,
          payload: _latestLiveEntryPayload,
        ),
      );
    }

    return AppLayout(
      title: 'Session — ${widget.clientName}',
      activeRoute: 'roster',
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: Column(
            children: [
              _buildStepIndicator(),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(48, 28, 48, 8),
                  child: _buildCurrentStep(),
                ),
              ),
              _buildNavBar(),
            ],
          ),
        ),
      ),
    );
  }

  // ── Step Indicator ───────────────────────────────────────────────────────────

  Widget _buildStepIndicator() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 48),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Row(
        children: List.generate(_stepLabels.length * 2 - 1, (i) {
          if (i.isOdd) {
            final stepBefore = i ~/ 2;
            return Expanded(
              child: Container(
                height: 2,
                color: stepBefore < _currentStep
                    ? Colors.teal
                    : Colors.grey.shade200,
              ),
            );
          }
          final idx = i ~/ 2;
          final done = idx < _currentStep;
          final active = idx == _currentStep;
          return Column(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: done || active
                      ? Colors.teal
                      : Colors.grey.shade100,
                  border: Border.all(
                    color: done || active
                        ? Colors.teal
                        : Colors.grey.shade300,
                    width: 1.5,
                  ),
                ),
                child: Center(
                  child: done
                      ? const Icon(Icons.check,
                          color: Colors.white, size: 14)
                      : Text(
                          '${idx + 1}',
                          style: TextStyle(
                            color: active
                                ? Colors.white
                                : Colors.grey.shade400,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _stepLabels[idx],
                style: TextStyle(
                  fontSize: 11,
                  color: done || active
                      ? Colors.teal.shade700
                      : Colors.grey.shade400,
                  fontWeight:
                      active ? FontWeight.w700 : FontWeight.normal,
                ),
              ),
            ],
          );
        }),
      ),
    );
  }

  // ── Step Router ──────────────────────────────────────────────────────────────

  Widget _buildCurrentStep() {
    switch (_currentStep) {
      case 0:
        return _buildStep1();
      case 1:
        return _buildStep2();
      case 2:
        return _buildStep3();
      case 3:
        return _buildStep4();
      case 4:
        return _buildStep5();
      case 5:
        return _buildStep6();
      default:
        return const SizedBox.shrink();
    }
  }

  // ── Step 1 – Barrier Analysis ────────────────────────────────────────────────

  Widget _buildStep1() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _stepHeader(
          'Barrier Analysis',
          'Which barriers are present for this client today?',
        ),
        const SizedBox(height: 16),
        // Desktop: 2-column grid of barrier checkboxes
        Wrap(
          spacing: 0,
          runSpacing: 0,
          children: [
            _barrierTile('Motor', _barrierMotor,
                (v) => setState(() => _barrierMotor = v!)),
            _barrierTile('Linguistic', _barrierLinguistic,
                (v) => setState(() => _barrierLinguistic = v!)),
            _barrierTile('Cognitive', _barrierCognitive,
                (v) => setState(() => _barrierCognitive = v!)),
            _barrierTile('Sensory', _barrierSensory,
                (v) => setState(() => _barrierSensory = v!)),
            _barrierTile('Environmental', _barrierEnvironmental,
                (v) => setState(() => _barrierEnvironmental = v!)),
            _barrierTile('Motivational', _barrierMotivational,
                (v) => setState(() => _barrierMotivational = v!)),
            _barrierTile('Device Access', _barrierDeviceAccess,
                (v) => setState(() => _barrierDeviceAccess = v!)),
          ],
        ),
      ],
    );
  }

  Widget _barrierTile(
      String label, bool value, ValueChanged<bool?> onChanged) {
    return SizedBox(
      width: 280,
      child: CheckboxListTile(
        title: Text(label,
            style: const TextStyle(fontSize: 14)),
        value: value,
        onChanged: onChanged,
        activeColor: Colors.teal,
        controlAffinity: ListTileControlAffinity.leading,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 0),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  // ── Step 2 – Session Goal ────────────────────────────────────────────────────

  Widget _buildStep2() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _stepHeader(
          'Session Goal',
          'Define the measurable goal for this session.',
        ),
        const SizedBox(height: 20),
        _textField(
          controller: _targetBehaviourController,
          label: 'Target Behaviour',
          hint: 'e.g. Request preferred items using core vocabulary',
          maxLines: 2,
        ),
        const SizedBox(height: 16),
        _textField(
          controller: _conditionController,
          label: 'Condition',
          hint: 'e.g. During structured play with 3 objects present',
        ),
        const SizedBox(height: 16),
        _textField(
          controller: _criterionController,
          label: 'Criterion',
          hint: 'e.g. 4 out of 5 trials across 3 sessions',
        ),
      ],
    );
  }

  // ── Step 3 – Activity ────────────────────────────────────────────────────────

  Widget _buildStep3() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _stepHeader(
          'Activity',
          'Describe the activity used in this session.',
        ),
        const SizedBox(height: 20),
        _textField(
          controller: _activityNameController,
          label: 'Activity Name',
          hint: 'e.g. Snack time, cause & effect toy play',
        ),
        const SizedBox(height: 16),
        _textField(
          controller: _activityRationaleController,
          label: 'Rationale',
          hint: 'Why this activity was selected for the client',
          maxLines: 3,
        ),
      ],
    );
  }

  // ── Step 4 – Prompt Hierarchy ────────────────────────────────────────────────

  Widget _buildStep4() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _stepHeader(
          'Prompt Hierarchy',
          'Select the prompting approach and the level used.',
        ),
        const SizedBox(height: 20),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: DropdownButtonFormField<String>(
            value: _promptApproach,
            decoration: _inputDecoration('Prompting Approach'),
            items: const [
              DropdownMenuItem(
                value: 'most_to_least',
                child: Text('Most to Least'),
              ),
              DropdownMenuItem(
                value: 'least_to_most',
                child: Text('Least to Most'),
              ),
            ],
            onChanged: (v) => setState(() => _promptApproach = v!),
          ),
        ),
        const SizedBox(height: 28),
        Text(
          'Prompt Level Used',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Colors.grey.shade700,
          ),
        ),
        const SizedBox(height: 10),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.teal.shade200),
              borderRadius: BorderRadius.circular(12),
              color: Colors.teal.shade50,
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Level $_promptLevelUsed',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.teal,
                      ),
                    ),
                    Text(
                      _promptDescriptions[_promptLevelUsed] ?? '',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.teal.shade700,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
                Slider(
                  value: _promptLevelUsed.toDouble(),
                  min: 1,
                  max: 6,
                  divisions: 5,
                  activeColor: Colors.teal,
                  inactiveColor: Colors.teal.shade100,
                  label: '$_promptLevelUsed',
                  onChanged: (v) =>
                      setState(() => _promptLevelUsed = v.round()),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: List.generate(
                    6,
                    (i) => Text(
                      '${i + 1}',
                      style: TextStyle(
                        fontSize: 11,
                        color: _promptLevelUsed == i + 1
                            ? Colors.teal
                            : Colors.grey.shade400,
                        fontWeight: _promptLevelUsed == i + 1
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        ..._promptDescriptions.entries.map(
          (e) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Container(
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: e.key == _promptLevelUsed
                        ? Colors.teal
                        : Colors.grey.shade100,
                  ),
                  child: Center(
                    child: Text(
                      '${e.key}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: e.key == _promptLevelUsed
                            ? Colors.white
                            : Colors.grey.shade500,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  e.value,
                  style: TextStyle(
                    fontSize: 14,
                    color: e.key == _promptLevelUsed
                        ? Colors.teal.shade800
                        : Colors.grey.shade600,
                    fontWeight: e.key == _promptLevelUsed
                        ? FontWeight.w600
                        : FontWeight.normal,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ── Step 5 – During Session ──────────────────────────────────────────────────

  Widget _buildStep5() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _stepHeader(
          'During Session',
          'Record trial data and client affect.',
        ),
        const SizedBox(height: 20),
        // Three number fields side by side on desktop
        Row(
          children: [
            Expanded(
              child: _numberField(
                controller: _attemptsController,
                label: 'Total Attempts',
                hint: '0',
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _numberField(
                controller: _independentResponsesController,
                label: 'Independent',
                hint: '0',
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _numberField(
                controller: _promptedResponsesController,
                label: 'Prompted',
                hint: '0',
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: DropdownButtonFormField<String>(
            value: _clientAffect,
            decoration: _inputDecoration('Client Affect'),
            items: const [
              DropdownMenuItem(
                  value: 'regulated', child: Text('Regulated')),
              DropdownMenuItem(
                  value: 'dysregulated',
                  child: Text('Dysregulated')),
              DropdownMenuItem(
                  value: 'variable', child: Text('Variable')),
            ],
            onChanged: (v) => setState(() => _clientAffect = v!),
          ),
        ),
      ],
    );
  }

  // ── Step 6 – Post Session ────────────────────────────────────────────────────

  Widget _buildStep6() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _stepHeader(
          'Post Session',
          'Summarise outcomes and plan next steps.',
        ),
        const SizedBox(height: 20),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: DropdownButtonFormField<String>(
            value: _goalMet,
            decoration: _inputDecoration('Goal Met?'),
            items: const [
              DropdownMenuItem(value: 'yes', child: Text('Yes')),
              DropdownMenuItem(
                  value: 'partially', child: Text('Partially')),
              DropdownMenuItem(
                  value: 'not_yet', child: Text('Not Yet')),
            ],
            onChanged: (v) => setState(() => _goalMet = v!),
          ),
        ),
        const SizedBox(height: 16),
        _textField(
          controller: _homeProgrammeController,
          label: 'Home Programme',
          hint: 'Recommendations for carers to carry over at home',
          maxLines: 3,
        ),
        const SizedBox(height: 16),
        _textField(
          controller: _nextSessionFocusController,
          label: 'Next Session Focus',
          hint: 'What to prioritise in the next session',
          maxLines: 2,
        ),
        const SizedBox(height: 32),
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
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : const Text(
                      'Save Session',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
            ),
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  // ── Navigation Bar ───────────────────────────────────────────────────────────

  Widget _buildNavBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(48, 12, 48, 20),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Row(
        children: [
          if (_currentStep > 0)
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 160),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () =>
                      setState(() => _currentStep--),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.teal,
                    side: const BorderSide(color: Colors.teal),
                    padding:
                        const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: const Text('Back'),
                ),
              ),
            ),
          if (_currentStep > 0 && _currentStep < 5)
            const SizedBox(width: 12),
          if (_currentStep < 5)
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 160),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () =>
                      setState(() => _currentStep++),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.teal,
                    padding:
                        const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: const Text(
                    'Next',
                    style: TextStyle(fontSize: 15),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ── Shared Helpers ───────────────────────────────────────────────────────────

  Widget _stepHeader(String title, String subtitle) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
              fontSize: 22, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style:
              TextStyle(fontSize: 14, color: Colors.grey.shade600),
        ),
      ],
    );
  }

  InputDecoration _inputDecoration(String label) {
    return InputDecoration(
      labelText: label,
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
        borderSide:
            const BorderSide(color: Colors.teal, width: 2),
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
      decoration: _inputDecoration(label).copyWith(hintText: hint),
    );
  }

  Widget _numberField({
    required TextEditingController controller,
    required String label,
    String? hint,
  }) {
    return TextField(
      controller: controller,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      textAlign: TextAlign.center,
      decoration: _inputDecoration(label).copyWith(hintText: hint),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Phase 4.0.4 — fluency session summary.
//
// Read-only view of the latest live-entry payload for a developmental
// stuttering client. Editing returns to live-entry mode in 4.0.5.
// ─────────────────────────────────────────────────────────────────────────────

class _FluencySessionSummary extends StatelessWidget {
  final String clientName;
  final Map<String, dynamic>? payload;

  const _FluencySessionSummary({
    required this.clientName,
    required this.payload,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: kCuePaper,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'session summary',
                  style: TextStyle(
                    fontSize: 11,
                    color: kCueEyebrowInk,
                    letterSpacing: kCueEyebrowLetterSpacing(11),
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  clientName,
                  style: GoogleFonts.playfairDisplay(
                    fontSize: 24,
                    fontStyle: FontStyle.italic,
                    fontWeight: FontWeight.w600,
                    color: kCueInk,
                    height: 1.05,
                  ),
                ),
                const SizedBox(height: 22),
                if (payload == null) _emptyState() else _content(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _emptyState() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 22),
      decoration: BoxDecoration(
        color: kCueSurface,
        borderRadius: BorderRadius.circular(kCueCardRadius),
        border: Border.all(color: kCueBorder, width: kCueCardBorderW),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'No live entry yet.',
            style: TextStyle(fontSize: 14, color: kCueInk),
          ),
          const SizedBox(height: 6),
          Text(
            'Start a session in live-entry mode to capture syllable counts, '
            'disfluencies, and accessory behaviours.',
            style: TextStyle(
                fontSize: 13, color: kCueSubtitleInk, height: 1.45),
          ),
        ],
      ),
    );
  }

  Widget _content() {
    final p = payload!;
    final total = (p['total_syllables'] as num?)?.toInt() ?? 0;
    final stuttered = (p['stuttered_syllables'] as num?)?.toInt() ?? 0;
    final percent = (p['percent_ss'] as num?)?.toDouble() ?? 0.0;
    final duration = (p['duration_seconds'] as num?)?.toInt() ?? 0;
    final ctx = (p['sample_context'] as String?)?.trim();
    final disfluency =
        (p['disfluency_counts'] as Map?)?.cast<String, dynamic>() ??
            const <String, dynamic>{};
    final accessories =
        ((p['accessory_behaviours_observed'] as List?) ?? const [])
            .map((e) => e.toString())
            .toList();
    final state = (p['live_entry_state'] as String?) ?? 'complete';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (ctx != null && ctx.isNotEmpty) ...[
          Text(
            ctx,
            style: TextStyle(fontSize: 14, color: kCueSubtitleInk),
          ),
          const SizedBox(height: 8),
        ],
        Text(
          'duration · ${_formatDuration(duration)}'
          '${state == 'in_progress' ? ' · in progress' : ''}',
          style: TextStyle(fontSize: 12, color: kCueEyebrowInk),
        ),
        const SizedBox(height: 16),
        Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: _heroTile('total syllables', total.toString(), false)),
            const SizedBox(width: 10),
            Expanded(child: _heroTile('stuttered', stuttered.toString(), false)),
            const SizedBox(width: 10),
            Expanded(
                flex: 2,
                child: _heroTile('%SS', percent.toStringAsFixed(1), true)),
          ],
        ),
        const SizedBox(height: 18),
        if (disfluency.values.any((v) => ((v as num?)?.toInt() ?? 0) > 0))
          _card(
            eyebrow: 'disfluency counts',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: disfluency.entries
                  .where((e) => ((e.value as num?)?.toInt() ?? 0) > 0)
                  .map((e) => Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                _humanLabel(e.key),
                                style: const TextStyle(
                                    fontSize: 13, color: kCueInk),
                              ),
                            ),
                            Text(
                              ((e.value as num?)?.toInt() ?? 0).toString(),
                              style: GoogleFonts.playfairDisplay(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: kCueInk,
                              ),
                            ),
                          ],
                        ),
                      ))
                  .toList(),
            ),
          ),
        if (accessories.isNotEmpty) ...[
          const SizedBox(height: 14),
          _card(
            eyebrow: 'accessory behaviours observed',
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: accessories
                  .map((k) => Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: kCueAmberSurface,
                          borderRadius:
                              BorderRadius.circular(kCueChipRadius),
                        ),
                        child: Text(
                          _humanLabel(k),
                          style: const TextStyle(
                            fontSize: 12,
                            color: kCueAmberText,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ))
                  .toList(),
            ),
          ),
        ],
        const SizedBox(height: 18),
        Text(
          'Captured in live-entry mode. Edit by reopening the session in live entry.',
          style: TextStyle(
              fontSize: 12, color: kCueEyebrowInk, height: 1.45),
        ),
      ],
    );
  }

  Widget _heroTile(String eyebrow, String value, bool amber) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: amber ? kCueAmberSurface : kCueSurface,
        borderRadius: BorderRadius.circular(kCueTileRadius),
        border: amber
            ? null
            : Border.all(color: kCueBorder, width: kCueCardBorderW),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            eyebrow,
            style: TextStyle(
              fontSize: 11,
              color: amber ? kCueAmberDeeper : kCueEyebrowInk,
              letterSpacing: kCueEyebrowLetterSpacing(11),
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: GoogleFonts.playfairDisplay(
              fontSize: 26,
              fontWeight: FontWeight.w600,
              color: amber ? kCueAmberText : kCueInk,
              height: 1.0,
            ),
          ),
        ],
      ),
    );
  }

  Widget _card({required String eyebrow, required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
      decoration: BoxDecoration(
        color: kCueSurface,
        borderRadius: BorderRadius.circular(kCueCardRadius),
        border: Border.all(color: kCueBorder, width: kCueCardBorderW),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            eyebrow,
            style: TextStyle(
              fontSize: 11,
              color: kCueEyebrowInk,
              letterSpacing: kCueEyebrowLetterSpacing(11),
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }

  String _formatDuration(int seconds) {
    final m = (seconds ~/ 60).toString().padLeft(2, '0');
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  String _humanLabel(String key) {
    switch (key) {
      case 'part_word':    return 'part-word repetition';
      case 'whole_word':   return 'whole-word repetition';
      case 'prolongation': return 'prolongation';
      case 'block':        return 'block';
      case 'interjection': return 'interjection · other';
      case 'revision':     return 'revision · other';
      case 'eye_blink':       return 'eye blink';
      case 'facial_tension':  return 'facial tension';
      case 'head_movement':   return 'head movement';
      case 'limb_movement':   return 'limb movement';
      case 'audible_tension': return 'audible tension';
      default:
        return key.replaceAll('_', ' ');
    }
  }
}
