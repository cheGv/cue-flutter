// lib/screens/format_lexicon_defaults_screen.dart
//
// Phase C — Cue Mirror, Component Two (Format Drafter).
// Route: /clients/{clientId}/draft-report/lexicon. Shown ONCE per template —
// the first time the clinician drafts in a format whose own report vocabulary
// includes deficit-style terms. For each such term she decides: let Cue replace
// it with neutral language (default), or keep her original wording. Her choice
// is saved as a per-template default (format_template_lexicon_defaults) and
// then the draft proceeds (E4, generate mode).
//
// §language-discipline: the ONLY place a forbidden word appears in this screen
// is as the clinician's own original term, shown as data for her decision.
// Every word Cue itself authors here is neutral.

import 'package:flutter/material.dart';

import '../constants/cue_lexicon.dart';
import '../models/format_template.dart';
import '../repositories/format_template_lexicon_defaults_repository.dart';
import '../repositories/format_templates_repository.dart';
import '../theme/cue_color_scheme.dart';
import '../theme/cue_text_styles.dart';
import '../widgets/app_layout.dart';
import '../widgets/chart/chart_card.dart';

class FormatLexiconDefaultsScreen extends StatefulWidget {
  final String clientId;
  final String templateId;
  final String preset;
  final DateTime? customStart;
  final DateTime? customEnd;

  const FormatLexiconDefaultsScreen({
    super.key,
    required this.clientId,
    required this.templateId,
    required this.preset,
    this.customStart,
    this.customEnd,
  });

  @override
  State<FormatLexiconDefaultsScreen> createState() =>
      _FormatLexiconDefaultsScreenState();
}

class _FormatLexiconDefaultsScreenState
    extends State<FormatLexiconDefaultsScreen> {
  final _templatesRepo = FormatTemplatesRepository();
  final _lexiconRepo = FormatTemplateLexiconDefaultsRepository();

  late Future<FormatTemplate?> _future;

  // term → true when the SLP wants Cue to swap it (default), false to keep hers.
  final Map<String, bool> _swap = {};
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<FormatTemplate?> _load() async {
    final tpl = await _templatesRepo.get(widget.templateId);
    if (tpl != null) {
      for (final term in tpl.extractedTemplate.forbiddenVocabularyObserved) {
        _swap.putIfAbsent(term, () => true); // default: replace
      }
    }
    return tpl;
  }

  Future<void> _save(FormatTemplate template) async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final terms = template.extractedTemplate.forbiddenVocabularyObserved;
      for (final term in terms) {
        final swap = _swap[term] ?? true;
        await _lexiconRepo.upsert(
          templateId: widget.templateId,
          forbiddenTerm: term,
          decision: swap ? 'swap' : 'keep_original',
          replacementTerm: swap ? cueNeutralReplacement(term) : null,
        );
      }
      if (!mounted) return;
      // Defaults set — proceed into the draft (generate mode).
      Navigator.of(context).pushReplacementNamed(
        '/clients/${widget.clientId}/draft-report/view',
        arguments: {
          'templateId': widget.templateId,
          'clientId': widget.clientId,
          'preset': widget.preset,
          'customStart': widget.customStart,
          'customEnd': widget.customEnd,
        },
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not save your choices. $e';
        _saving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppLayout(
      title: 'Your language preferences',
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
                    child: FutureBuilder<FormatTemplate?>(
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
                        final tpl = snap.data;
                        if (tpl == null) {
                          return CueChartCard(
                            child: Text('That format could not be found.',
                                style: CueChartType.of(context).sessionHeadline),
                          );
                        }
                        return _body(t, tpl);
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

  Widget _body(CueChartTokens t, FormatTemplate template) {
    final ty = CueChartType.of(context);
    final terms = template.extractedTemplate.forbiddenVocabularyObserved;
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
        CueChartCard(
          head: const CueChartCardHead(label: 'A one-time choice for this format'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Cue noticed a few words in your sample reports that it can '
                'soften to more neutral, strengths-based language. For each one, '
                'tell Cue what you prefer. You only set this once per format — '
                'you can still override any single report later.',
                style: ty.narratorBody,
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        for (final term in terms) ...[
          _termCard(t, ty, term),
          const SizedBox(height: 12),
        ],
        const SizedBox(height: 4),
        Align(
          alignment: Alignment.centerRight,
          child: CueChartButton(
            style: CueChartButtonStyle.primary,
            icon: Icons.check,
            label: _saving ? 'Saving…' : 'Save and draft',
            enabled: !_saving,
            onTap: () => _save(template),
          ),
        ),
      ],
    );
  }

  Widget _termCard(CueChartTokens t, CueChartType ty, String term) {
    final neutral = cueNeutralReplacement(term);
    final swap = _swap[term] ?? true;
    return CueChartCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // The clinician's own term — shown as data, in a quiet quoted register.
          Text('Your wording', style: ty.sparklineLabel.copyWith()),
          const SizedBox(height: 4),
          Text('“$term”', style: ty.stgBody),
          const SizedBox(height: 14),
          _choice(
            t,
            ty,
            selected: swap,
            title: 'Replace with “$neutral”',
            subtitle: 'Cue uses neutral, strengths-based language by default.',
            onTap: () => setState(() => _swap[term] = true),
          ),
          const SizedBox(height: 8),
          _choice(
            t,
            ty,
            selected: !swap,
            title: 'Keep “$term” in my reports',
            subtitle: 'Cue leaves your original wording exactly as written.',
            onTap: () => setState(() => _swap[term] = false),
          ),
        ],
      ),
    );
  }

  Widget _choice(
    CueChartTokens t,
    CueChartType ty, {
    required bool selected,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: selected ? t.accentSoftBg : t.bgInset,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: selected ? t.accent : t.borderInset),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              selected ? Icons.radio_button_checked : Icons.radio_button_off,
              size: 18,
              color: selected ? t.accent : t.textMuted,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: selected ? ty.metaStrong : ty.sessionHeadline),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: ty.sessionHeadline.copyWith(color: t.textTertiary)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
