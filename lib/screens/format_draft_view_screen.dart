// lib/screens/format_draft_view_screen.dart
//
// Phase C — Cue Mirror, Component Two (Format Drafter).
// Routes:
//   /clients/{clientId}/draft-report/view              (generate mode — args)
//   /clients/{clientId}/draft-report/view/{draftId}    (load an existing draft)
//
// Generate mode receives {templateId, clientId, preset, customStart, customEnd}
// via RouteSettings.arguments, shows a calm loading state while
// FormatDrafterService().requestDraft(...) runs (the service persists the draft
// on success), then renders the returned FormatDraft. draftId mode loads the
// stored draft and renders it.
//
// Rendering: one CueChartCard per DraftSection, in order. Every clinical claim
// is source-traceable — each section's content is followed by a numbered
// footnote list (¹ ² ³ …) of its source_claims, each tappable for the source
// detail. Neutral-language substitutions are shown as quiet "Language adjusted"
// rows with a per-instance, report-only toggle back to the SLP's original
// wording (local UI state only — never persisted, never changes the template
// default). Static-authored sections show their placeholder + a quiet note that
// they are authored in Component Three.
//
// NOTE: the ¹ ² ³ source markers and the "Language adjusted" affordances are
// Cue-draft-only review aids. They will NOT appear in Component Four's PDF
// export — that surface renders the clinician-facing report without Cue's
// internal traceability scaffolding.
//
// §language-discipline: forbidden words appear ONLY as the clinician's own
// original wording (LexiconSwap.original) shown for her review. Every word Cue
// authors in this screen is neutral.

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/format_draft.dart';
import '../repositories/client_chart_state_repository.dart';
import '../repositories/format_drafts_repository.dart';
import '../repositories/format_templates_repository.dart';
import '../services/format_drafter_service.dart';
import '../theme/cue_color_scheme.dart';
import '../theme/cue_text_styles.dart';
import '../widgets/app_layout.dart';
import '../widgets/chart/chart_card.dart';

// Superscript glyphs for the source markers (¹..⁰), reused for the footnote
// list. Index 0 → '¹'.
const _superscripts = ['¹', '²', '³', '⁴', '⁵', '⁶', '⁷', '⁸', '⁹', '¹⁰',
  '¹¹', '¹²', '¹³', '¹⁴', '¹⁵', '¹⁶', '¹⁷', '¹⁸', '¹⁹', '²⁰'];
String _superscript(int oneBased) =>
    oneBased >= 1 && oneBased <= _superscripts.length
        ? _superscripts[oneBased - 1]
        : '($oneBased)';

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
  final _drafter = FormatDrafterService();

  FormatDraft? _draft;
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
      setState(() {
        _draft = draft;
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
    // After a generate, resolve the template name from the persisted draft if we
    // could not earlier (cosmetic).
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

  // The draft is persisted at generation and the per-instance lexicon toggles
  // are ephemeral (never persisted, never alter the export), so there is no
  // "unsaved" state — export is available whenever the draft is open for work.
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
          _SectionCard(section: draft.draftSections[i]),
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

// ── One draft section ────────────────────────────────────────────────────────

class _SectionCard extends StatefulWidget {
  final DraftSection section;
  const _SectionCard({required this.section});

  @override
  State<_SectionCard> createState() => _SectionCardState();
}

class _SectionCardState extends State<_SectionCard> {
  // Per-swap, report-only override: when true, show the SLP's ORIGINAL wording
  // for this instance instead of Cue's neutral replacement. Keyed by the swap's
  // position in this section's lexiconSwaps list. LOCAL ONLY — never persisted,
  // never alters the template default.
  final Set<int> _useOriginal = {};

  @override
  Widget build(BuildContext context) {
    final t = CueChartTokens.of(context);
    final ty = CueChartType.of(context);
    final s = widget.section;

    if (s.isStaticAuthored) return _staticCard(t, ty, s);

    return CueChartCard(
      head: CueChartCardHead(
        label: s.sectionName.trim().isEmpty ? 'Section' : s.sectionName,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Body content with the source markers appended (¹..ⁿ map to the
          // numbered footnote list below). Cue-draft-only — see file header.
          Text.rich(
            TextSpan(children: [
              TextSpan(text: s.content, style: ty.narratorBody),
              if (s.sourceClaims.isNotEmpty)
                TextSpan(
                  text: ' ${_markerRun(s.sourceClaims.length)}',
                  style: ty.narratorBody.copyWith(color: t.accent),
                ),
            ]),
          ),
          if (s.sourceClaims.isNotEmpty) ...[
            const SizedBox(height: 16),
            Container(height: 1, color: t.borderDivider),
            const SizedBox(height: 12),
            Text('SOURCES', style: ty.sparklineLabel),
            const SizedBox(height: 8),
            for (var i = 0; i < s.sourceClaims.length; i++)
              _sourceRow(t, ty, i + 1, s.sourceClaims[i]),
          ],
          if (s.lexiconSwaps.isNotEmpty) ...[
            const SizedBox(height: 16),
            Container(height: 1, color: t.borderDivider),
            const SizedBox(height: 12),
            for (var i = 0; i < s.lexiconSwaps.length; i++)
              _swapRow(t, ty, i, s.lexiconSwaps[i]),
          ],
        ],
      ),
    );
  }

  // "¹ ² ³" run appended to the body so the SLP sees claims are sourced.
  String _markerRun(int count) {
    final b = StringBuffer();
    for (var i = 1; i <= count; i++) {
      if (i > 1) b.write(' ');
      b.write(_superscript(i));
    }
    return b.toString();
  }

  Widget _staticCard(CueChartTokens t, CueChartType ty, DraftSection s) {
    return CueChartCard(
      head: CueChartCardHead(
        label: s.sectionName.trim().isEmpty ? 'Section' : s.sectionName,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            s.content.trim().isEmpty
                ? 'This section is authored by you.'
                : s.content,
            style: ty.sessionHeadline.copyWith(
              color: t.textTertiary,
              fontStyle: FontStyle.italic,
            ),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: t.bgInset,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: t.borderInset),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.edit_note_outlined, size: 15, color: t.textMuted),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    'Author this section in Component Three (coming soon)',
                    style: ty.footerItem,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sourceRow(
      CueChartTokens t, CueChartType ty, int n, SourceClaim claim) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: () => _showSource(t, ty, n, claim),
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

  void _showSource(
      CueChartTokens t, CueChartType ty, int n, SourceClaim claim) {
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

  Widget _swapRow(CueChartTokens t, CueChartType ty, int index, LexiconSwap s) {
    final showingOriginal = _useOriginal.contains(index);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: t.accentSoftBg,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: t.accent.withValues(alpha: 0.4)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.published_with_changes,
                    size: 14, color: t.accent),
                const SizedBox(width: 6),
                Expanded(
                  child: Text('Language adjusted',
                      style: ty.outcomePill(t.accent)),
                ),
                GestureDetector(
                  onTap: () => _showSwapDetail(t, s),
                  child: Icon(Icons.info_outline, size: 14, color: t.accent),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              showingOriginal
                  // Showing the SLP's own original wording (her data) for this
                  // report only.
                  ? 'Using your wording “${s.original}” for this report.'
                  : 'Cue used “${s.replacement}” in place of your original '
                      'wording.',
              style: ty.sessionHeadline.copyWith(color: t.textBody),
            ),
            const SizedBox(height: 6),
            GestureDetector(
              onTap: () => setState(() {
                if (showingOriginal) {
                  _useOriginal.remove(index);
                } else {
                  _useOriginal.add(index);
                }
              }),
              child: Text(
                showingOriginal
                    ? 'Use Cue’s neutral wording instead'
                    : 'Use original “${s.original}” for this report only',
                style: ty.footerItem.copyWith(
                  color: t.accent,
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showSwapDetail(CueChartTokens t, LexiconSwap s) {
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
              Text(
                'Replaced by your lexicon default → “${s.replacement}”.',
                style: sty.narratorBody,
              ),
            ],
          ),
        );
      },
    );
  }

  String _sourceLabel(String sourceType) => switch (sourceType) {
        'session' => 'Session',
        'substrate' => 'Substrate',
        'goal' => 'Goal',
        'citation' => 'Evidence',
        'static_clinician_authored' => 'Authored by you',
        _ => sourceType.isEmpty ? 'Source' : sourceType,
      };
}
