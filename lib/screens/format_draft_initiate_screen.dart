// lib/screens/format_draft_initiate_screen.dart
//
// Phase C — Cue Mirror, Component Two (Format Drafter).
// Route: /clients/{clientId}/draft-report. The clinician picks (a) a confirmed
// format template and (b) a date range (a preset, optionally narrowed by a
// custom start/end). "Continue" routes either to the once-per-template lexicon
// step (E3) — when she has not yet set her swap/keep decisions for a template
// whose format uses deficit-style vocabulary — or straight to the draft view
// (E4) in generate mode. Reuses the Phase B chart primitives so light + dark
// both render through CueChartTokens. §language-discipline: every Cue string
// here is neutral.

import 'package:flutter/material.dart';

import '../models/format_template.dart';
import '../repositories/format_template_lexicon_defaults_repository.dart';
import '../repositories/format_templates_repository.dart';
import '../theme/cue_color_scheme.dart';
import '../theme/cue_text_styles.dart';
import '../widgets/app_layout.dart';
import '../widgets/chart/chart_card.dart';

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];
String _fmtDate(DateTime d) => '${_months[d.month - 1]} ${d.day}, ${d.year}';

// preset value → human label. 'custom' is implied by picking custom dates and
// is not offered as a button.
const _presets = <(String, String)>[
  ('weekly', 'Weekly'),
  ('monthly', 'Monthly'),
  ('quarterly', 'Quarterly'),
  ('all_sessions', 'All sessions'),
];

class FormatDraftInitiateScreen extends StatefulWidget {
  final String clientId;
  const FormatDraftInitiateScreen({super.key, required this.clientId});

  @override
  State<FormatDraftInitiateScreen> createState() =>
      _FormatDraftInitiateScreenState();
}

class _FormatDraftInitiateScreenState extends State<FormatDraftInitiateScreen> {
  final _templatesRepo = FormatTemplatesRepository();
  final _lexiconRepo = FormatTemplateLexiconDefaultsRepository();

  late Future<List<FormatTemplate>> _future;

  String? _templateId;
  String _preset = 'monthly';
  DateTime? _customStart;
  DateTime? _customEnd;
  bool _checking = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _future = _loadConfirmed();
  }

  Future<List<FormatTemplate>> _loadConfirmed() async {
    final all = await _templatesRepo.listForUser();
    return all.where((t) => t.isConfirmed).toList();
  }

  bool get _hasCustomRange => _customStart != null && _customEnd != null;

  // The effective preset Cue sends: 'custom' once both custom dates are set.
  String get _effectivePreset => _hasCustomRange ? 'custom' : _preset;

  Future<void> _pickCustomRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 5),
      lastDate: now,
      initialDateRange: _hasCustomRange
          ? DateTimeRange(start: _customStart!, end: _customEnd!)
          : null,
    );
    if (picked == null) return;
    setState(() {
      _customStart = picked.start;
      _customEnd = picked.end;
    });
  }

  void _clearCustomRange() => setState(() {
        _customStart = null;
        _customEnd = null;
      });

  Future<void> _continue(List<FormatTemplate> templates) async {
    final id = _templateId;
    if (id == null) {
      setState(() => _error = 'Choose a format to draft in.');
      return;
    }
    final template = templates.firstWhere((t) => t.id == id);
    setState(() {
      _checking = true;
      _error = null;
    });

    try {
      final defaults = await _lexiconRepo.listForTemplate(id);
      if (!mounted) return;

      final args = <String, dynamic>{
        'templateId': id,
        'clientId': widget.clientId,
        'preset': _effectivePreset,
        'customStart': _hasCustomRange ? _customStart : null,
        'customEnd': _hasCustomRange ? _customEnd : null,
      };

      // First draft for a template whose format uses deficit-style vocabulary →
      // collect her swap/keep decision first. Otherwise straight to the draft.
      final needsLexicon = defaults.isEmpty &&
          template.extractedTemplate.forbiddenVocabularyObserved.isNotEmpty;

      final route = needsLexicon
          ? '/clients/${widget.clientId}/draft-report/lexicon'
          : '/clients/${widget.clientId}/draft-report/view';
      await Navigator.of(context).pushNamed(route, arguments: args);
      if (mounted) setState(() => _checking = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not continue. $e';
        _checking = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppLayout(
      title: 'Generate report',
      activeRoute: 'roster',
      body: LayoutBuilder(
        builder: (context, constraints) {
          final t = CueChartTokens.of(context);
          final hPad = constraints.maxWidth < 768 ? 16.0 : 24.0;
          return ColoredBox(
            color: t.bgCanvas,
            child: SingleChildScrollView(
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 760),
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(hPad, 20, hPad, 96),
                    child: FutureBuilder<List<FormatTemplate>>(
                      future: _future,
                      builder: (context, snap) {
                        if (snap.hasError) {
                          return CueChartCard(
                            child: Text(
                              'This page could not load. ${snap.error}',
                              style: CueChartType.of(context).sessionHeadline,
                            ),
                          );
                        }
                        if (!snap.hasData) {
                          return const Padding(
                            padding: EdgeInsets.only(top: 48),
                            child: Center(child: CircularProgressIndicator()),
                          );
                        }
                        final templates = snap.data!;
                        if (templates.isEmpty) return _noTemplates(t);
                        return _form(t, templates);
                      },
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _noTemplates(CueChartTokens t) {
    final ty = CueChartType.of(context);
    return CueChartCard(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('No confirmed formats yet', style: ty.stgBody),
          const SizedBox(height: 8),
          Text(
            'Cue drafts in your own report format. Add and confirm a format '
            'first, then come back to draft this report.',
            style: ty.sessionHeadline,
          ),
          const SizedBox(height: 18),
          CueChartButton(
            style: CueChartButtonStyle.primary,
            icon: Icons.description_outlined,
            label: 'Go to report formats',
            onTap: () => Navigator.of(context).pushNamed('/settings/formats'),
          ),
        ],
      ),
    );
  }

  Widget _form(CueChartTokens t, List<FormatTemplate> templates) {
    final ty = CueChartType.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_error != null) ...[
          CueChartCard(
            child: Text(_error!,
                style: ty.sessionHeadline.copyWith(color: t.accent)),
          ),
          const SizedBox(height: 16),
        ],
        // Template selector.
        CueChartCard(
          head: const CueChartCardHead(label: 'Draft in this format'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Cue will write this report in the structure and voice of the '
                'format you choose.',
                style: ty.sessionHeadline.copyWith(color: t.textTertiary),
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<String>(
                initialValue: _templateId,
                isExpanded: true,
                decoration: _inputDecoration(t, 'Choose a format'),
                style: ty.evidenceFinding,
                dropdownColor: t.bgCard,
                items: [
                  for (final tpl in templates)
                    DropdownMenuItem(
                      value: tpl.id,
                      child: Text(
                        tpl.name.trim().isEmpty ? 'Untitled format' : tpl.name,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (v) => setState(() {
                  _templateId = v;
                  _error = null;
                }),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        // Date-range selector.
        CueChartCard(
          head: const CueChartCardHead(label: 'Sessions to draw from'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Pick the window of sessions Cue should read for this report.',
                style: ty.sessionHeadline.copyWith(color: t.textTertiary),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final (value, label) in _presets)
                    _presetChip(t, ty, value, label),
                ],
              ),
              const SizedBox(height: 16),
              Container(height: 1, color: t.borderDivider),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _hasCustomRange
                          ? 'Custom range — ${_fmtDate(_customStart!)} to '
                              '${_fmtDate(_customEnd!)}'
                          : 'Or choose an exact date range.',
                      style: _hasCustomRange
                          ? ty.metaStrong
                          : ty.sessionHeadline.copyWith(color: t.textTertiary),
                    ),
                  ),
                  const SizedBox(width: 12),
                  if (_hasCustomRange)
                    CueChartButton(
                      style: CueChartButtonStyle.ghost,
                      small: true,
                      icon: Icons.close,
                      label: 'Clear',
                      onTap: _clearCustomRange,
                    )
                  else
                    CueChartButton(
                      small: true,
                      icon: Icons.date_range_outlined,
                      label: 'Pick dates',
                      onTap: _pickCustomRange,
                    ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Align(
          alignment: Alignment.centerRight,
          child: CueChartButton(
            style: CueChartButtonStyle.primary,
            icon: Icons.auto_awesome,
            label: _checking ? 'Just a moment…' : 'Continue',
            enabled: !_checking,
            onTap: () => _continue(templates),
          ),
        ),
      ],
    );
  }

  Widget _presetChip(
      CueChartTokens t, CueChartType ty, String value, String label) {
    // A preset is "on" only when no custom range overrides it.
    final on = !_hasCustomRange && _preset == value;
    return GestureDetector(
      onTap: () => setState(() {
        _preset = value;
        _customStart = null;
        _customEnd = null;
      }),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: on ? t.accentSoftBg : t.bgCard,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: on ? t.accent : t.borderCard),
        ),
        child: Text(label,
            style: ty.outcomePill(on ? t.accent : t.textSecondary)),
      ),
    );
  }

  InputDecoration _inputDecoration(CueChartTokens t, String? hint) {
    final ty = CueChartType.of(context);
    return InputDecoration(
      hintText: hint,
      hintStyle: ty.evidenceFinding.copyWith(color: t.textMuted),
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      filled: true,
      fillColor: t.bgCard,
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: BorderSide(color: t.borderCard),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: BorderSide(color: t.accent),
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: BorderSide(color: t.borderCard),
      ),
    );
  }
}
