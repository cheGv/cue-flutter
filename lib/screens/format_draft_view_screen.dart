// lib/screens/format_draft_view_screen.dart
//
// Phase C — Cue Mirror Component Two (Format Drafter) + Phase D Component Three
// (full): inline, sentence-level editing.
// Routes:
//   /clients/{clientId}/draft-report/view              (generate mode — args)
//   /clients/{clientId}/draft-report/view/{draftId}    (load an existing draft)
//
// Populated sections render sentence-by-sentence from format_draft_sentences.
// Tapping a sentence edits it in place: autosave (debounce 2s → text_in_progress)
// protects work; Save promotes it to the committed text (status clinician_edited,
// or clinician_authored when the rewrite is substantial), and rebuilds that
// section's draft_sections.content so the Word export reflects what the SLP
// approved. Static-authored sections (Header/History/…) are authored fresh in a
// whole-section editor.
//
// §language-discipline: forbidden words appear ONLY as the clinician's own
// original wording. Every word Cue authors here is neutral.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/format_draft.dart';
import '../models/format_draft_sentence.dart';
import '../repositories/client_chart_state_repository.dart';
import '../repositories/format_draft_sentences_repository.dart';
import '../repositories/format_drafts_repository.dart';
import '../repositories/format_templates_repository.dart';
import '../services/format_drafter_service.dart';
import '../theme/cue_color_scheme.dart';
import '../theme/cue_text_styles.dart';
import '../widgets/app_layout.dart';
import '../widgets/chart/chart_card.dart';

// Superscript glyphs for source markers (¹..⁰).
const _superscripts = ['¹', '²', '³', '⁴', '⁵', '⁶', '⁷', '⁸', '⁹', '¹⁰',
  '¹¹', '¹²', '¹³', '¹⁴', '¹⁵', '¹⁶', '¹⁷', '¹⁸', '¹⁹', '²⁰'];
String _superscript(int oneBased) =>
    oneBased >= 1 && oneBased <= _superscripts.length
        ? _superscripts[oneBased - 1]
        : '($oneBased)';

String _sourceLabel(String sourceType) => switch (sourceType) {
      'session' => 'Session',
      'substrate' => 'Substrate',
      'goal' => 'Goal',
      'citation' => 'Evidence',
      'static_clinician_authored' => 'Authored by you',
      _ => sourceType.isEmpty ? 'Source' : sourceType,
    };

// Hand-rolled Levenshtein distance (two-row). Used to decide whether a saved
// edit is a light correction (clinician_edited, keeps claims) or a substantial
// rewrite (clinician_authored, drops claims).
int _levenshtein(String a, String b) {
  if (a == b) return 0;
  if (a.isEmpty) return b.length;
  if (b.isEmpty) return a.length;
  var prev = List<int>.generate(b.length + 1, (i) => i);
  var curr = List<int>.filled(b.length + 1, 0);
  for (var i = 0; i < a.length; i++) {
    curr[0] = i + 1;
    for (var j = 0; j < b.length; j++) {
      final cost = a.codeUnitAt(i) == b.codeUnitAt(j) ? 0 : 1;
      final del = prev[j + 1] + 1;
      final ins = curr[j] + 1;
      final sub = prev[j] + cost;
      curr[j + 1] = del < ins ? (del < sub ? del : sub) : (ins < sub ? ins : sub);
    }
    final tmp = prev;
    prev = curr;
    curr = tmp;
  }
  return prev[b.length];
}

class FormatDraftViewScreen extends StatefulWidget {
  final String clientId;

  /// Non-null → load this existing draft. Null → generate mode (use [genArgs]).
  final String? draftId;

  /// Generate-mode arguments {templateId, clientId, preset, customStart,
  /// customEnd}. Ignored when [draftId] is set.
  final Map<String, dynamic>? genArgs;

  const FormatDraftViewScreen({
    super.key,
    required this.clientId,
    this.draftId,
    this.genArgs,
  });

  bool get isGenerateMode => draftId == null;

  @override
  State<FormatDraftViewScreen> createState() => _FormatDraftViewScreenState();
}

class _FormatDraftViewScreenState extends State<FormatDraftViewScreen> {
  final _draftsRepo = FormatDraftsRepository();
  final _templatesRepo = FormatTemplatesRepository();
  final _chartStateRepo = ClientChartStateRepository();
  final _sentencesRepo = FormatDraftSentencesRepository();
  final _drafter = FormatDrafterService();

  FormatDraft? _draft;
  List<FormatDraftSentence> _sentences = [];
  bool _loading = true;
  String? _error;
  bool _markingReviewed = false;
  bool _exporting = false;

  // Resolved display labels for the loading + header lines.
  String _clientName = '';
  String _templateName = 'your';

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      // Resolve display names first (best-effort; never blocks the draft).
      await _resolveLabels();
      final draft = widget.isGenerateMode
          ? await _generate()
          : await _draftsRepo.get(widget.draftId!);
      if (!mounted) return;
      if (draft == null) {
        setState(() {
          _error = 'That draft could not be found.';
          _loading = false;
        });
        return;
      }
      final sentences = await _sentencesRepo.listForDraft(draft.id);
      if (!mounted) return;
      setState(() {
        _draft = draft;
        _sentences = sentences;
        _loading = false;
      });
    } on FormatDrafterException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Something went wrong. $e';
        _loading = false;
      });
    }
  }

  Future<void> _resolveLabels() async {
    try {
      final state = await _chartStateRepo.loadForClient(widget.clientId);
      _clientName = state?.clientName ?? '';
    } catch (_) {/* name is cosmetic */}

    final templateId = widget.isGenerateMode
        ? (widget.genArgs?['templateId'] as String?)
        : null;
    try {
      if (templateId != null) {
        final tpl = await _templatesRepo.get(templateId);
        if (tpl != null && tpl.name.trim().isNotEmpty) _templateName = tpl.name;
      }
    } catch (_) {/* template name is cosmetic */}
  }

  Future<FormatDraft> _generate() async {
    final args = widget.genArgs ?? const {};
    final draft = await _drafter.requestDraft(
      templateId: args['templateId'] as String,
      clientId: args['clientId'] as String? ?? widget.clientId,
      preset: args['preset'] as String? ?? 'all_sessions',
      customStart: args['customStart'] as DateTime?,
      customEnd: args['customEnd'] as DateTime?,
    );
    if (_templateName == 'your') {
      try {
        final tpl = await _templatesRepo.get(draft.templateId);
        if (tpl != null && tpl.name.trim().isNotEmpty) _templateName = tpl.name;
      } catch (_) {/* cosmetic */}
    }
    return draft;
  }

  Future<void> _markReviewed() async {
    final draft = _draft;
    if (draft == null || _markingReviewed) return;
    setState(() => _markingReviewed = true);
    try {
      final updated = await _draftsRepo.update(draft.id, {'status': 'reviewed'});
      if (!mounted) return;
      setState(() {
        _draft = updated;
        _markingReviewed = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Draft marked as reviewed.')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _markingReviewed = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not update the draft. $e')),
      );
    }
  }

  void _saveDraft() {
    // requestDraft already persisted this as status 'draft'; confirm + leave.
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Draft saved.')),
    );
    Navigator.of(context).maybePop();
  }

  bool get _canExport =>
      _draft != null &&
      (_draft!.status == 'draft' || _draft!.status == 'reviewed');

  Future<void> _exportToWord() async {
    final draft = _draft;
    if (draft == null || _exporting) return;
    setState(() => _exporting = true);
    try {
      final result = await _drafter.exportDraft(draftId: draft.id);
      if (!mounted) return;
      setState(() => _exporting = false);
      final opened = await launchUrl(
        Uri.parse(result.signedUrl),
        mode: LaunchMode.externalApplication,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(opened
              ? 'Downloaded ${result.filename}'
              : 'Your document is ready: ${result.filename}'),
        ),
      );
    } on FormatDrafterException catch (e) {
      if (!mounted) return;
      setState(() => _exporting = false);
      _showExportError(e.message);
    } catch (e) {
      if (!mounted) return;
      setState(() => _exporting = false);
      _showExportError('Something went wrong. $e');
    }
  }

  void _showExportError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        action: SnackBarAction(label: 'Retry', onPressed: _exportToWord),
      ),
    );
  }

  // ── Component Three (full) — sentence edit handlers ─────────────────────────

  List<FormatDraftSentence> _sentencesFor(String sectionName) =>
      _sentences.where((s) => s.sectionName == sectionName).toList()
        ..sort((a, b) => a.sentenceOrder.compareTo(b.sentenceOrder));

  Future<void> _reloadSentences() async {
    final draft = _draft;
    if (draft == null) return;
    final r = await _drafter.refresh(draft.id);
    if (!mounted) return;
    setState(() {
      if (r.draft != null) _draft = r.draft;
      _sentences = r.sentences;
    });
  }

  Future<void> _autosaveSentence(FormatDraftSentence s, String text) async {
    try {
      await _drafter.autosaveSentence(s.id, text);
      await _reloadSentences();
    } catch (_) {/* autosave is best-effort; the field still holds the text */}
  }

  Future<void> _commitSentence(FormatDraftSentence s, String newText) async {
    final trimmed = newText.trim();
    if (trimmed.isEmpty) return;
    // >30% of the original length changed → treat as fresh authoring (drop
    // claims); otherwise it stays a clinician_edited sentence that keeps them.
    final dist = _levenshtein(s.textOriginal, trimmed);
    final authored = dist > (s.textOriginal.length * 0.30);
    try {
      await _drafter.commitSentenceEdit(
        draftId: s.draftId,
        sentenceId: s.id,
        sectionName: s.sectionName,
        newText: trimmed,
        status: authored ? 'clinician_authored' : 'clinician_edited',
        sourceClaims:
            authored ? null : s.sourceClaims.map((c) => c.toJson()).toList(),
      );
      await _reloadSentences();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Edit saved')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save the edit. $e')),
      );
    }
  }

  Future<void> _discardSentence(FormatDraftSentence s) async {
    try {
      await _sentencesRepo.update(s.id, {'text_in_progress': null});
      await _reloadSentences();
    } catch (_) {/* best-effort */}
  }

  // Static section: create the authored row, or update an existing one.
  Future<void> _authorStatic(String sectionName, String text) async {
    final draft = _draft;
    if (draft == null) return;
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    final existing =
        _sentencesFor(sectionName).where((s) => s.isClinicianAuthored).toList();
    try {
      if (existing.isNotEmpty) {
        await _drafter.commitSentenceEdit(
          draftId: draft.id,
          sentenceId: existing.first.id,
          sectionName: sectionName,
          newText: trimmed,
          status: 'clinician_authored',
          sourceClaims: null,
        );
      } else {
        await _drafter.authorStaticSection(
          draftId: draft.id,
          sectionName: sectionName,
          templateId: draft.templateId,
          text: trimmed,
        );
      }
      await _reloadSentences();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Section saved')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save the section. $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppLayout(
      title: 'Report draft',
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
                  constraints: const BoxConstraints(maxWidth: 820),
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(hPad, 20, hPad, 96),
                    child: _content(t),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _content(CueChartTokens t) {
    if (_loading) return _loadingView(t);
    if (_error != null) return _errorView(t);
    final draft = _draft;
    if (draft == null) {
      return CueChartCard(
        child: Text('Nothing to show yet.',
            style: CueChartType.of(context).sessionHeadline),
      );
    }
    return _draftView(t, draft);
  }

  Widget _loadingView(CueChartTokens t) {
    final ty = CueChartType.of(context);
    final who = _clientName.trim().isEmpty ? 'this' : "$_clientName's";
    return CueChartCard(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 48),
      child: Column(
        children: [
          const Center(child: CircularProgressIndicator()),
          const SizedBox(height: 18),
          Text(
            widget.isGenerateMode
                ? 'Cue is drafting $who report in your $_templateName format…'
                : 'Loading this draft…',
            style: ty.stgBody,
            textAlign: TextAlign.center,
          ),
          if (widget.isGenerateMode) ...[
            const SizedBox(height: 6),
            Text(
              'Cue is reading the chart, matching your structure and voice, and '
              'tracing every claim back to its source. This takes a moment.',
              style: ty.sessionHeadline.copyWith(color: t.textTertiary),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }

  Widget _errorView(CueChartTokens t) {
    final ty = CueChartType.of(context);
    return CueChartCard(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('This draft did not complete', style: ty.stgBody),
          const SizedBox(height: 8),
          Text(_error ?? '', style: ty.sessionHeadline),
          const SizedBox(height: 18),
          CueChartButton(
            style: CueChartButtonStyle.primary,
            icon: Icons.refresh,
            label: 'Try again',
            onTap: _run,
          ),
        ],
      ),
    );
  }

  Widget _draftView(CueChartTokens t, FormatDraft draft) {
    final ty = CueChartType.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _actionBar(t, ty, draft),
        const SizedBox(height: 16),
        for (var i = 0; i < draft.draftSections.length; i++) ...[
          _buildSectionCard(draft.draftSections[i]),
          if (i < draft.draftSections.length - 1) const SizedBox(height: 16),
        ],
        if (draft.draftSections.isEmpty)
          CueChartCard(
            child: Text(
              'Cue did not produce any sections for this range. Try a wider '
              'date range.',
              style: ty.sessionHeadline,
            ),
          ),
      ],
    );
  }

  Widget _buildSectionCard(DraftSection section) {
    final sentences = _sentencesFor(section.sectionName);
    if (section.isStaticAuthored) {
      final authored =
          sentences.where((s) => s.isClinicianAuthored).toList();
      return StaticSectionCard(
        key: ValueKey('static-${section.sectionName}'),
        section: section,
        authored: authored.isNotEmpty ? authored.first : null,
        onAutosave: _autosaveSentence,
        onSave: (text) => _authorStatic(section.sectionName, text),
      );
    }
    return EditableSectionCard(
      key: ValueKey('editable-${section.sectionName}'),
      section: section,
      sentences: sentences,
      onAutosave: _autosaveSentence,
      onCommit: _commitSentence,
      onDiscard: _discardSentence,
    );
  }

  Widget _actionBar(CueChartTokens t, CueChartType ty, FormatDraft draft) {
    return CueChartCard(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _clientName.trim().isEmpty
                      ? 'Draft in your $_templateName format'
                      : "$_clientName · your $_templateName format",
                  style: ty.metaStrong,
                ),
                const SizedBox(height: 2),
                Text(
                  draft.isReviewed ? 'Reviewed' : 'Draft',
                  style: ty.sessionSub,
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Wrap(
            spacing: 8,
            children: [
              CueChartButton(
                icon: Icons.bookmark_border,
                small: true,
                label: 'Save draft',
                onTap: _saveDraft,
              ),
              CueChartButton(
                style: CueChartButtonStyle.primary,
                small: true,
                icon: draft.isReviewed ? Icons.check : Icons.done_all,
                label: draft.isReviewed
                    ? 'Reviewed'
                    : (_markingReviewed ? 'Saving…' : 'Mark reviewed'),
                enabled: !draft.isReviewed && !_markingReviewed,
                onTap: _markReviewed,
              ),
              CueChartButton(
                style: CueChartButtonStyle.primary,
                small: true,
                icon: Icons.file_download_outlined,
                label: _exporting ? 'Generating…' : 'Export to Word',
                enabled: _canExport && !_exporting,
                onTap: _exportToWord,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Source / lexicon detail sheets (shared) ──────────────────────────────────

void _showSourceSheet(
    BuildContext context, CueChartTokens t, int n, SourceClaim claim) {
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: t.bgCard,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
    ),
    builder: (sheetCtx) {
      final sty = CueChartType.of(sheetCtx);
      return Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('SOURCE ${_superscript(n)}', style: sty.sparklineLabel),
            const SizedBox(height: 8),
            Text(
              '${_sourceLabel(claim.sourceType)}'
              '${claim.sourceId.trim().isEmpty ? '' : ' · ${claim.sourceId}'}',
              style: sty.metaStrong,
            ),
            if (claim.claimText.trim().isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(claim.claimText, style: sty.narratorBody),
            ],
            if (claim.sourceExcerpt.trim().isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: t.bgInset,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: t.borderInset),
                ),
                child: Text('“${claim.sourceExcerpt}”',
                    style: sty.evidenceFinding),
              ),
            ],
          ],
        ),
      );
    },
  );
}

void _showSwapSheet(BuildContext context, CueChartTokens t, LexiconSwap s) {
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: t.bgCard,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
    ),
    builder: (sheetCtx) {
      final sty = CueChartType.of(sheetCtx);
      return Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('LANGUAGE ADJUSTED', style: sty.sparklineLabel),
            const SizedBox(height: 12),
            Text('Original: “${s.original}”.', style: sty.narratorBody),
            const SizedBox(height: 6),
            Text('Replaced by your lexicon default → “${s.replacement}”.',
                style: sty.narratorBody),
            const SizedBox(height: 10),
            Text('Edit the sentence to author it in your own words.',
                style: sty.footerItem),
          ],
        ),
      );
    },
  );
}

Widget _sourceRow(BuildContext context, CueChartTokens t, CueChartType ty,
    int n, SourceClaim claim) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: () => _showSourceSheet(context, t, n, claim),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 24,
              child: Text(_superscript(n),
                  style: ty.evidenceFinding.copyWith(color: t.accent)),
            ),
            Expanded(
              child: Text(
                claim.claimText.trim().isEmpty
                    ? '${_sourceLabel(claim.sourceType)} source'
                    : claim.claimText,
                style: ty.evidenceCite,
              ),
            ),
            const SizedBox(width: 8),
            Icon(Icons.north_east, size: 13, color: t.textMuted),
          ],
        ),
      ),
    ),
  );
}

Widget _swapRow(
    BuildContext context, CueChartTokens t, CueChartType ty, LexiconSwap s) {
  return Padding(
    padding: const EdgeInsets.only(top: 6),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: t.accentSoftBg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: t.accent.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(Icons.published_with_changes, size: 14, color: t.accent),
          const SizedBox(width: 6),
          Expanded(
            child: Text('Language adjusted', style: ty.outcomePill(t.accent)),
          ),
          GestureDetector(
            onTap: () => _showSwapSheet(context, t, s),
            child: Icon(Icons.info_outline, size: 14, color: t.accent),
          ),
        ],
      ),
    ),
  );
}

String _markerRun(int count) {
  final b = StringBuffer();
  for (var i = 1; i <= count; i++) {
    if (i > 1) b.write(' ');
    b.write(_superscript(i));
  }
  return b.toString();
}

// ── Editable (sentence-level) section ────────────────────────────────────────

class EditableSectionCard extends StatefulWidget {
  final DraftSection section;
  final List<FormatDraftSentence> sentences;
  final Future<void> Function(FormatDraftSentence, String) onAutosave;
  final Future<void> Function(FormatDraftSentence, String) onCommit;
  final Future<void> Function(FormatDraftSentence) onDiscard;

  const EditableSectionCard({
    super.key,
    required this.section,
    required this.sentences,
    required this.onAutosave,
    required this.onCommit,
    required this.onDiscard,
  });

  @override
  State<EditableSectionCard> createState() => EditableSectionCardState();
}

class EditableSectionCardState extends State<EditableSectionCard> {
  String? _editingId;
  final _controller = TextEditingController();
  Timer? _debounce;
  String _autosaveLabel = '';

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _startEdit(FormatDraftSentence s) {
    setState(() {
      _editingId = s.id;
      _controller.text = s.displayText;
      _autosaveLabel = '';
    });
  }

  void _stopEdit() {
    _debounce?.cancel();
    if (!mounted) return;
    setState(() {
      _editingId = null;
      _autosaveLabel = '';
    });
  }

  void _onChanged(FormatDraftSentence s, String text) {
    setState(() => _autosaveLabel = 'Saving…');
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 2), () async {
      await widget.onAutosave(s, text);
      if (!mounted) return;
      setState(() => _autosaveLabel = 'Autosaved');
    });
  }

  Future<void> _save(FormatDraftSentence s) async {
    _debounce?.cancel();
    await widget.onCommit(s, _controller.text);
    _stopEdit();
  }

  Future<void> _discard(FormatDraftSentence s) async {
    _debounce?.cancel();
    await widget.onDiscard(s);
    _stopEdit();
  }

  @override
  Widget build(BuildContext context) {
    final t = CueChartTokens.of(context);
    final ty = CueChartType.of(context);
    final s = widget.section;
    final sentences = widget.sentences;

    return CueChartCard(
      head: CueChartCardHead(
        label: s.sectionName.trim().isEmpty ? 'Section' : s.sectionName,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (sentences.isEmpty)
            Text('No content drafted for this section.',
                style: ty.sessionHeadline.copyWith(color: t.textTertiary))
          else
            for (var i = 0; i < sentences.length; i++)
              _sentenceBlock(t, ty, sentences[i],
                  isLast: i == sentences.length - 1),
        ],
      ),
    );
  }

  Widget _sentenceBlock(CueChartTokens t, CueChartType ty,
      FormatDraftSentence s, {required bool isLast}) {
    final editing = _editingId == s.id;
    final someoneEditing = _editingId != null;

    if (editing) {
      return Container(
        margin: EdgeInsets.only(bottom: isLast ? 0 : 12),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: t.bgInset,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: t.accent, width: 1.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _controller,
              autofocus: true,
              maxLines: null,
              style: ty.narratorBody,
              cursorColor: t.accent,
              decoration: const InputDecoration(
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
              onChanged: (text) => _onChanged(s, text),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                if (_autosaveLabel.isNotEmpty)
                  Text(_autosaveLabel,
                      style: ty.footerItem.copyWith(color: t.textMuted)),
                const Spacer(),
                CueChartButton(
                  small: true,
                  icon: Icons.close,
                  label: 'Discard',
                  onTap: () => _discard(s),
                ),
                const SizedBox(width: 8),
                CueChartButton(
                  style: CueChartButtonStyle.primary,
                  small: true,
                  icon: Icons.check,
                  label: 'Save',
                  onTap: () => _save(s),
                ),
              ],
            ),
          ],
        ),
      );
    }

    final showSources = s.isCueDrafted && s.sourceClaims.isNotEmpty;
    final showSwaps = s.isCueDrafted && s.lexiconSwaps.isNotEmpty;
    return Opacity(
      opacity: someoneEditing ? 0.45 : 1.0,
      child: Padding(
        padding: EdgeInsets.only(bottom: isLast ? 0 : 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
              borderRadius: BorderRadius.circular(6),
              onTap: someoneEditing ? null : () => _startEdit(s),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 2),
                child: Text.rich(TextSpan(children: [
                  TextSpan(text: s.displayText, style: ty.narratorBody),
                  if (showSources)
                    TextSpan(
                      text: ' ${_markerRun(s.sourceClaims.length)}',
                      style: ty.narratorBody.copyWith(color: t.accent),
                    ),
                  if (s.hasUnsavedEdit)
                    TextSpan(
                      text: '  • unsaved',
                      style: ty.footerItem.copyWith(color: t.accent),
                    )
                  else if (s.isEdited)
                    TextSpan(
                      text: '  • edited',
                      style: ty.footerItem.copyWith(color: t.textMuted),
                    ),
                ])),
              ),
            ),
            if (showSources) ...[
              const SizedBox(height: 6),
              for (var i = 0; i < s.sourceClaims.length; i++)
                _sourceRow(context, t, ty, i + 1, s.sourceClaims[i]),
            ],
            if (showSwaps)
              for (final sw in s.lexiconSwaps) _swapRow(context, t, ty, sw),
          ],
        ),
      ),
    );
  }
}

// ── Static (whole-section) authoring ─────────────────────────────────────────

class StaticSectionCard extends StatefulWidget {
  final DraftSection section;
  final FormatDraftSentence? authored;
  final Future<void> Function(FormatDraftSentence, String) onAutosave;
  final Future<void> Function(String) onSave;

  const StaticSectionCard({
    super.key,
    required this.section,
    required this.authored,
    required this.onAutosave,
    required this.onSave,
  });

  @override
  State<StaticSectionCard> createState() => StaticSectionCardState();
}

class StaticSectionCardState extends State<StaticSectionCard> {
  bool _editing = false;
  final _controller = TextEditingController();
  Timer? _debounce;
  String _autosaveLabel = '';

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _startEdit() {
    setState(() {
      _editing = true;
      _controller.text = widget.authored?.displayText ?? '';
      _autosaveLabel = '';
    });
  }

  void _onChanged(String text) {
    final authored = widget.authored;
    if (authored == null) return; // no row yet — autosave begins after first Save
    setState(() => _autosaveLabel = 'Saving…');
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 2), () async {
      await widget.onAutosave(authored, text);
      if (!mounted) return;
      setState(() => _autosaveLabel = 'Autosaved');
    });
  }

  Future<void> _save() async {
    _debounce?.cancel();
    await widget.onSave(_controller.text);
    if (!mounted) return;
    setState(() {
      _editing = false;
      _autosaveLabel = '';
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = CueChartTokens.of(context);
    final ty = CueChartType.of(context);
    final s = widget.section;
    final authored = widget.authored;

    return CueChartCard(
      head: CueChartCardHead(
        label: s.sectionName.trim().isEmpty ? 'Section' : s.sectionName,
      ),
      child: _editing
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: t.bgInset,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: t.accent, width: 1.5),
                  ),
                  child: TextField(
                    controller: _controller,
                    autofocus: true,
                    maxLines: null,
                    minLines: 3,
                    style: ty.narratorBody,
                    cursorColor: t.accent,
                    decoration: InputDecoration(
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                      hintText: 'Author this section in your own words…',
                      hintStyle:
                          ty.narratorBody.copyWith(color: t.textTertiary),
                    ),
                    onChanged: _onChanged,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    if (_autosaveLabel.isNotEmpty)
                      Text(_autosaveLabel,
                          style: ty.footerItem.copyWith(color: t.textMuted)),
                    const Spacer(),
                    CueChartButton(
                      small: true,
                      icon: Icons.close,
                      label: 'Cancel',
                      onTap: () => setState(() => _editing = false),
                    ),
                    const SizedBox(width: 8),
                    CueChartButton(
                      style: CueChartButtonStyle.primary,
                      small: true,
                      icon: Icons.check,
                      label: 'Save',
                      onTap: _save,
                    ),
                  ],
                ),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  authored != null && authored.text.trim().isNotEmpty
                      ? authored.text
                      : 'This section is authored by you.',
                  style: authored != null && authored.text.trim().isNotEmpty
                      ? ty.narratorBody
                      : ty.sessionHeadline.copyWith(
                          color: t.textTertiary,
                          fontStyle: FontStyle.italic,
                        ),
                ),
                const SizedBox(height: 10),
                CueChartButton(
                  style: authored == null
                      ? CueChartButtonStyle.primary
                      : CueChartButtonStyle.normal,
                  small: true,
                  icon: Icons.edit_note_outlined,
                  label: authored == null ? 'Author this section' : 'Edit',
                  onTap: _startEdit,
                ),
              ],
            ),
    );
  }
}
