// lib/screens/format_template_upload_screen.dart
//
// Phase C — Report-format upload + confirmation. Route: /settings/formats/new
// (optionally /settings/formats/new?id=<templateId> to re-open an existing
// template at the confirm step). Three steps: upload → extracting → confirm.
// Reuses the Phase B chart primitives. §13: no prompt in this client — only
// file references go to the proxy.

import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../constants/format_types.dart';
import '../models/format_template.dart';
import '../repositories/format_templates_repository.dart';
import '../services/format_extractor_service.dart';
import '../theme/cue_color_scheme.dart';
import '../theme/cue_text_styles.dart';
import '../widgets/app_layout.dart';
import '../widgets/chart/chart_card.dart';

const _canonicalPrimitives = <String>[
  'observation',
  'clinical_reasoning',
  'intervention',
  'outcome',
  'next_session_intent',
  'metrics',
  'substrate',
  'goals',
  'recommendations',
  'static_clinician_authored',
];

const _lengthOptions = <String>[
  'short prose',
  'bulleted list',
  'table',
  'paragraph',
];

enum _Step { upload, extracting, confirm }

class _Picked {
  final String filename;
  final String fileType; // 'pdf' | 'docx'
  final Uint8List bytes;
  const _Picked(this.filename, this.fileType, this.bytes);
}

class FormatTemplateUploadScreen extends StatefulWidget {
  final String? templateId;
  const FormatTemplateUploadScreen({super.key, this.templateId});

  @override
  State<FormatTemplateUploadScreen> createState() =>
      _FormatTemplateUploadScreenState();
}

class _FormatTemplateUploadScreenState
    extends State<FormatTemplateUploadScreen> {
  final _repo = FormatTemplatesRepository();
  final _service = FormatExtractorService();

  _Step _step = _Step.upload;
  bool _busy = false;
  String? _error;

  // Step 1 inputs.
  final _nameCtrl = TextEditingController();
  String _formatType = 'pt_report';
  final List<_Picked> _picked = [];

  // Resolved template id + the editable confirm-state.
  String? _templateId;
  List<FormatSection> _sections = [];
  List<String> _placeholders = [];
  VoiceRegister _voice = const VoiceRegister();
  List<String> _forbidden = [];
  List<String> _warnings = [];

  @override
  void initState() {
    super.initState();
    if (widget.templateId != null) {
      _templateId = widget.templateId;
      _loadExisting(widget.templateId!);
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadExisting(String id) async {
    setState(() => _busy = true);
    try {
      final tpl = await _repo.get(id);
      if (tpl == null) {
        setState(() {
          _error = 'That format could not be found.';
          _busy = false;
        });
        return;
      }
      _nameCtrl.text = tpl.name;
      _formatType = tpl.formatType;
      _adoptTemplate(tpl.extractedTemplate);
      setState(() {
        _step = _Step.confirm;
        _busy = false;
      });
    } catch (e) {
      setState(() {
        _error = '$e';
        _busy = false;
      });
    }
  }

  void _adoptTemplate(ExtractedTemplate t) {
    _sections = List.of(t.sections);
    _placeholders = List.of(t.placeholders);
    _voice = t.voiceRegister;
    _forbidden = List.of(t.forbiddenVocabularyObserved);
    if (_nameCtrl.text.trim().isEmpty && t.formatName.isNotEmpty) {
      _nameCtrl.text = t.formatName;
    }
  }

  ExtractedTemplate _composeTemplate() => ExtractedTemplate(
        formatName: _nameCtrl.text.trim(),
        formatType: _formatType,
        sections: _sections,
        placeholders: _placeholders,
        voiceRegister: _voice,
        forbiddenVocabularyObserved: _forbidden,
        extractionWarnings: _warnings,
      );

  // ── Step 1 → run extraction ─────────────────────────────────────────────
  Future<void> _pickFiles() async {
    final res = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.custom,
      allowedExtensions: ['pdf', 'docx'],
      withData: true,
    );
    if (res == null) return;
    final next = <_Picked>[];
    for (final f in res.files) {
      final bytes = f.bytes;
      final ext = (f.extension ?? '').toLowerCase();
      if (bytes == null || (ext != 'pdf' && ext != 'docx')) continue;
      next.add(_Picked(f.name, ext, bytes));
    }
    setState(() {
      _picked
        ..clear()
        ..addAll(next.take(5));
      _error = null;
    });
  }

  bool get _canExtract =>
      _picked.isNotEmpty && _nameCtrl.text.trim().isNotEmpty && !_busy;

  Future<void> _runExtraction() async {
    if (!_canExtract) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final tpl = await _repo.create(
        name: _nameCtrl.text.trim(),
        formatType: _formatType,
      );
      _templateId = tpl.id;

      final docs = <SourceDocument>[];
      for (final p in _picked) {
        docs.add(await _service.uploadSourceDocument(
          bytes: p.bytes,
          filename: p.filename,
          fileType: p.fileType,
          templateId: tpl.id,
        ));
      }
      await _repo.update(tpl.id, {
        'source_documents': docs.map((d) => d.toJson()).toList(),
      });

      setState(() => _step = _Step.extracting);

      final result = await _service.requestExtraction(
        templateId: tpl.id,
        sourceDocuments: docs,
      );
      _adoptTemplate(result.template);
      _warnings = result.warnings;
      setState(() {
        _step = _Step.confirm;
        _busy = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Extraction did not complete. $e';
        _step = _Step.upload;
        _busy = false;
      });
    }
  }

  // ── Step 3 → save ───────────────────────────────────────────────────────
  Future<void> _save() async {
    final id = _templateId;
    if (id == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _service.confirmTemplate(
        templateId: id,
        confirmedTemplate: _composeTemplate(),
      );
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      setState(() {
        _error = 'Could not save. $e';
        _busy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppLayout(
      title: _step == _Step.confirm ? 'Confirm your format' : 'Add report format',
      activeRoute: 'settings',
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
                  constraints: const BoxConstraints(maxWidth: 880),
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(hPad, 20, hPad, 96),
                    child: switch (_step) {
                      _Step.upload => _uploadView(t),
                      _Step.extracting => _extractingView(t),
                      _Step.confirm => _confirmView(t),
                    },
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // ── Views ────────────────────────────────────────────────────────────────
  Widget _uploadView(CueChartTokens t) {
    final ty = CueChartType.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_error != null) _errorCard(t, ty),
        CueChartCard(
          head: const CueChartCardHead(label: 'Upload your reports'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Add three to five of the same report type. Cue reads the '
                'structure you follow — sections, ordering, voice — and adapts '
                'to it. .pdf or .docx, up to five files.',
                style: ty.sessionHeadline,
              ),
              const SizedBox(height: 16),
              _field(t, ty, 'Format name',
                  TextField(
                    controller: _nameCtrl,
                    onChanged: (_) => setState(() {}),
                    style: ty.evidenceFinding,
                    decoration: _inputDecoration(t, 'e.g. AIISH PT'),
                  )),
              const SizedBox(height: 14),
              _field(t, ty, 'Format type',
                  DropdownButtonFormField<String>(
                    initialValue: _formatType,
                    decoration: _inputDecoration(t, null),
                    style: ty.evidenceFinding,
                    dropdownColor: t.bgCard,
                    items: [
                      for (final k in kFormatTypeKeys)
                        DropdownMenuItem(value: k, child: Text(formatTypeLabel(k))),
                    ],
                    onChanged: (v) => setState(() => _formatType = v ?? 'other'),
                  )),
              const SizedBox(height: 16),
              CueChartButton(
                icon: Icons.upload_file_outlined,
                label: _picked.isEmpty ? 'Choose files' : 'Choose different files',
                onTap: _pickFiles,
              ),
              if (_picked.isNotEmpty) ...[
                const SizedBox(height: 12),
                for (final p in _picked)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      children: [
                        Icon(Icons.description_outlined,
                            size: 15, color: t.textTertiary),
                        const SizedBox(width: 8),
                        Expanded(child: Text(p.filename, style: ty.footerItem)),
                        Text(p.fileType.toUpperCase(), style: ty.compactCites),
                      ],
                    ),
                  ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
        Align(
          alignment: Alignment.centerRight,
          child: CueChartButton(
            style: CueChartButtonStyle.primary,
            icon: Icons.auto_awesome,
            label: 'Read my format',
            enabled: _canExtract,
            onTap: _runExtraction,
          ),
        ),
      ],
    );
  }

  Widget _extractingView(CueChartTokens t) {
    final ty = CueChartType.of(context);
    return CueChartCard(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 48),
      child: Column(
        children: [
          const Center(child: CircularProgressIndicator()),
          const SizedBox(height: 18),
          Text('Reading your format…', style: ty.stgBody, textAlign: TextAlign.center),
          const SizedBox(height: 6),
          Text(
            'Cue is reading the structure, voice, and section ordering across '
            'your reports. This takes a few moments.',
            style: ty.sessionHeadline.copyWith(color: t.textTertiary),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _confirmView(CueChartTokens t) {
    final ty = CueChartType.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_error != null) _errorCard(t, ty),
        if (_warnings.isNotEmpty) _warningsCard(t, ty),
        CueChartCard(
          head: CueChartCardHead(
            label: 'Sections',
            count: '· ${_sections.length}',
            actions: [
              CueChartButton(
                small: true,
                icon: Icons.add,
                label: 'Section',
                onTap: () => setState(() => _sections = [
                      ..._sections,
                      FormatSection(name: 'New section', order: _sections.length),
                    ]),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_sections.isEmpty)
                Text('No sections extracted.',
                    style: ty.sessionHeadline.copyWith(color: t.textMuted))
              else
                for (var i = 0; i < _sections.length; i++)
                  _sectionEditor(t, ty, i),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _placeholdersCard(t, ty),
        const SizedBox(height: 16),
        _voiceCard(t, ty),
        if (_forbidden.isNotEmpty) ...[
          const SizedBox(height: 16),
          _forbiddenCard(t, ty),
        ],
        const SizedBox(height: 16),
        Align(
          alignment: Alignment.centerRight,
          child: CueChartButton(
            style: CueChartButtonStyle.primary,
            icon: Icons.lock_outline,
            label: _busy ? 'Saving…' : 'Save & lock format',
            enabled: !_busy,
            onTap: _save,
          ),
        ),
      ],
    );
  }

  Widget _sectionEditor(CueChartTokens t, CueChartType ty, int i) {
    final s = _sections[i];
    void replace(FormatSection next) =>
        setState(() => _sections = [..._sections]..[i] = next);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: t.bgInset,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: t.borderInset),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  initialValue: s.name,
                  style: ty.evidenceFinding,
                  decoration: _inputDecoration(t, 'Section name'),
                  onChanged: (v) => replace(s.copyWith(name: v)),
                ),
              ),
              const SizedBox(width: 8),
              _iconBtn(t, Icons.arrow_upward, i == 0 ? null : () => _move(i, -1)),
              _iconBtn(t, Icons.arrow_downward,
                  i == _sections.length - 1 ? null : () => _move(i, 1)),
              _iconBtn(t, Icons.close,
                  () => setState(() => _sections = [..._sections]..removeAt(i))),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Text('Length', style: ty.footerItem),
              const SizedBox(width: 10),
              DropdownButton<String>(
                value: _lengthOptions.contains(s.length) ? s.length : null,
                hint: Text(s.length, style: ty.footerItem),
                dropdownColor: t.bgCard,
                underline: const SizedBox.shrink(),
                style: ty.evidenceFinding,
                items: [
                  for (final l in _lengthOptions)
                    DropdownMenuItem(value: l, child: Text(l)),
                ],
                onChanged: (v) => replace(s.copyWith(length: v ?? s.length)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text('Draws from', style: ty.footerItem),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final c in _canonicalPrimitives)
                _selectChip(t, ty, c, s.canonicalMap.contains(c), () {
                  final next = List<String>.of(s.canonicalMap);
                  next.contains(c) ? next.remove(c) : next.add(c);
                  replace(s.copyWith(canonicalMap: next));
                }),
            ],
          ),
          if (s.subsections.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text('Sub-sections', style: ty.footerItem),
            const SizedBox(height: 4),
            for (final sub in s.subsections)
              Padding(
                padding: const EdgeInsets.only(left: 4, top: 2),
                child: Text('• ${sub.name}  ·  ${sub.length}',
                    style: ty.compactCites),
              ),
          ],
        ],
      ),
    );
  }

  void _move(int i, int delta) {
    final j = i + delta;
    if (j < 0 || j >= _sections.length) return;
    setState(() {
      final next = [..._sections];
      final tmp = next[i];
      next[i] = next[j];
      next[j] = tmp;
      _sections = [
        for (var k = 0; k < next.length; k++) next[k].copyWith(order: k),
      ];
    });
  }

  Widget _placeholdersCard(CueChartTokens t, CueChartType ty) {
    final ctrl = TextEditingController();
    return CueChartCard(
      head: CueChartCardHead(label: 'Placeholders', count: '· ${_placeholders.length}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Fields that change per child. Cue fills these from the chart.',
              style: ty.sessionHeadline.copyWith(color: t.textTertiary)),
          const SizedBox(height: 12),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final p in _placeholders)
                _removableChip(t, ty, p,
                    () => setState(() => _placeholders = [..._placeholders]..remove(p))),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: ctrl,
                  style: ty.evidenceFinding,
                  decoration: _inputDecoration(t, 'Add a placeholder'),
                  onSubmitted: (v) {
                    final s = v.trim();
                    if (s.isNotEmpty && !_placeholders.contains(s)) {
                      setState(() => _placeholders = [..._placeholders, s]);
                    }
                    ctrl.clear();
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _voiceCard(CueChartTokens t, CueChartType ty) {
    final v = _voice;
    return CueChartCard(
      head: const CueChartCardHead(label: 'Voice register'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Cue will match this voice while honoring language discipline.',
              style: ty.sessionHeadline.copyWith(color: t.textTertiary)),
          const SizedBox(height: 12),
          if (v.commonVerbs.isNotEmpty) ...[
            Text('Common verbs', style: ty.footerItem),
            const SizedBox(height: 6),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final w in v.commonVerbs) _readChip(t, ty, w),
            ]),
            const SizedBox(height: 12),
          ],
          if (v.commonPhrasings.isNotEmpty) ...[
            Text('Common phrasings', style: ty.footerItem),
            const SizedBox(height: 4),
            for (final p in v.commonPhrasings)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text('“$p”', style: ty.evidenceFinding),
              ),
            const SizedBox(height: 12),
          ],
          if (v.sentenceRhythm.isNotEmpty) ...[
            Text('Sentence rhythm', style: ty.footerItem),
            const SizedBox(height: 4),
            Text(v.sentenceRhythm, style: ty.evidenceFinding),
          ],
        ],
      ),
    );
  }

  Widget _forbiddenCard(CueChartTokens t, CueChartType ty) {
    return CueChartCard(
      background: t.accentSoftBg,
      head: const CueChartCardHead(label: 'Vocabulary Cue will replace'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Cue will replace these with neutral language by default. You can '
            'override per-report when drafting.',
            style: ty.sessionHeadline.copyWith(color: t.textBody),
          ),
          const SizedBox(height: 10),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final w in _forbidden)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  border: Border.all(color: t.accent),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(w, style: ty.outcomePill(t.accent)),
              ),
          ]),
        ],
      ),
    );
  }

  Widget _warningsCard(CueChartTokens t, CueChartType ty) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: CueChartCard(
        background: t.bgCardHead,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('A few notes from extraction', style: ty.sessionDay),
            const SizedBox(height: 6),
            for (final w in _warnings)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text('• $w', style: ty.sessionHeadline),
              ),
          ],
        ),
      ),
    );
  }

  Widget _errorCard(CueChartTokens t, CueChartType ty) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: CueChartCard(
        child: Text(_error ?? '', style: ty.sessionHeadline.copyWith(color: t.accent)),
      ),
    );
  }

  // ── Small building blocks ──────────────────────────────────────────────
  Widget _field(CueChartTokens t, CueChartType ty, String label, Widget child) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label.toUpperCase(), style: ty.sparklineLabel),
        const SizedBox(height: 6),
        child,
      ],
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

  Widget _iconBtn(CueChartTokens t, IconData icon, VoidCallback? onTap) {
    return IconButton(
      onPressed: onTap,
      icon: Icon(icon, size: 16),
      color: t.textTertiary,
      visualDensity: VisualDensity.compact,
      splashRadius: 18,
    );
  }

  Widget _selectChip(
      CueChartTokens t, CueChartType ty, String label, bool on, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: on ? t.accentSoftBg : t.bgCard,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: on ? t.accent : t.borderCard),
        ),
        child: Text(label, style: ty.outcomePill(on ? t.accent : t.textTertiary)),
      ),
    );
  }

  Widget _removableChip(
      CueChartTokens t, CueChartType ty, String label, VoidCallback onRemove) {
    return Container(
      padding: const EdgeInsets.fromLTRB(9, 5, 5, 5),
      decoration: BoxDecoration(
        color: t.bgInset,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: t.borderInset),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: ty.outcomePill(t.textBody)),
          const SizedBox(width: 4),
          GestureDetector(
            onTap: onRemove,
            child: Icon(Icons.close, size: 13, color: t.textMuted),
          ),
        ],
      ),
    );
  }

  Widget _readChip(CueChartTokens t, CueChartType ty, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: t.bgInset,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: t.borderInset),
      ),
      child: Text(label, style: ty.outcomePill(t.textBody)),
    );
  }
}
