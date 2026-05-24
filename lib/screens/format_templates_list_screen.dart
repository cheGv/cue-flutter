// lib/screens/format_templates_list_screen.dart
//
// Phase C — Report formats list. Route: /settings/formats.
// Lists the clinician's confirmed + pending format templates. "+ Add format"
// opens the upload flow; each row's Edit re-opens that template. Reuses the
// Phase B chart visual primitives (CueChartTokens/Type/Card/Button).

import 'package:flutter/material.dart';

import '../constants/format_types.dart';
import '../models/format_template.dart';
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

class FormatTemplatesListScreen extends StatefulWidget {
  const FormatTemplatesListScreen({super.key});

  @override
  State<FormatTemplatesListScreen> createState() =>
      _FormatTemplatesListScreenState();
}

class _FormatTemplatesListScreenState extends State<FormatTemplatesListScreen> {
  final _repo = FormatTemplatesRepository();
  late Future<List<FormatTemplate>> _future;

  @override
  void initState() {
    super.initState();
    _future = _repo.listForUser();
  }

  void _reload() => setState(() => _future = _repo.listForUser());

  Future<void> _openNew() async {
    await Navigator.of(context).pushNamed('/settings/formats/new');
    if (mounted) _reload();
  }

  Future<void> _openEdit(String id) async {
    await Navigator.of(context).pushNamed('/settings/formats/new?id=$id');
    if (mounted) _reload();
  }

  @override
  Widget build(BuildContext context) {
    return AppLayout(
      title: 'Report formats',
      activeRoute: 'settings',
      body: LayoutBuilder(
        builder: (context, constraints) {
          final t = CueChartTokens.of(context);
          final ty = CueChartType.of(context);
          final hPad = constraints.maxWidth < 768 ? 16.0 : 24.0;
          return ColoredBox(
            color: t.bgCanvas,
            child: SingleChildScrollView(
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 840),
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(hPad, 20, hPad, 96),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _intro(t, ty),
                        const SizedBox(height: 16),
                        FutureBuilder<List<FormatTemplate>>(
                          future: _future,
                          builder: (context, snap) {
                            if (snap.hasError) {
                              return CueChartCard(
                                child: Text(
                                  'This list could not load. ${snap.error}',
                                  style: ty.sessionHeadline,
                                ),
                              );
                            }
                            if (!snap.hasData) {
                              return const Padding(
                                padding: EdgeInsets.only(top: 48),
                                child: Center(child: CircularProgressIndicator()),
                              );
                            }
                            final items = snap.data!;
                            if (items.isEmpty) return _emptyState(t, ty);
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                for (final tpl in items) ...[
                                  _templateCard(t, ty, tpl),
                                  const SizedBox(height: 12),
                                ],
                              ],
                            );
                          },
                        ),
                      ],
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

  Widget _intro(CueChartTokens t, CueChartType ty) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(
            'Cue learns the structure of your reports from a few samples, then '
            'drafts in your format. Upload 3–5 of one report type to begin.',
            style: ty.narratorBody,
          ),
        ),
        const SizedBox(width: 16),
        CueChartButton(
          style: CueChartButtonStyle.primary,
          icon: Icons.add,
          label: 'Add format',
          onTap: _openNew,
        ),
      ],
    );
  }

  Widget _emptyState(CueChartTokens t, CueChartType ty) {
    return CueChartCard(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('No formats yet', style: ty.stgBody),
          const SizedBox(height: 8),
          Text(
            'Upload three to five of your own reports — a pre-therapy report, a '
            'lesson plan, whatever you write — and Cue will read the structure '
            'you follow and adapt to it.',
            style: ty.sessionHeadline,
          ),
          const SizedBox(height: 18),
          Align(
            alignment: Alignment.centerLeft,
            child: CueChartButton(
              style: CueChartButtonStyle.primary,
              icon: Icons.add,
              label: 'Add your first format',
              onTap: _openNew,
            ),
          ),
        ],
      ),
    );
  }

  Widget _templateCard(CueChartTokens t, CueChartType ty, FormatTemplate tpl) {
    return CueChartCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tpl.name.trim().isEmpty ? 'Untitled format' : tpl.name,
                  style: ty.sessionDay,
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 10,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(formatTypeLabel(tpl.formatType), style: ty.footerItem),
                    _statusPill(t, ty, tpl.confirmationStatus),
                    Text('· Created ${_fmtDate(tpl.createdAt)}',
                        style: ty.footerItem),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          CueChartButton(
            style: CueChartButtonStyle.ghost,
            small: true,
            icon: Icons.edit_outlined,
            label: 'Edit',
            onTap: () => _openEdit(tpl.id),
          ),
        ],
      ),
    );
  }

  Widget _statusPill(CueChartTokens t, CueChartType ty, String status) {
    final bool confirmed = status == 'confirmed';
    final bg = confirmed ? t.outcomeProgressBg : t.accentSoftBg;
    final fg = confirmed ? t.outcomeProgressText : t.accent;
    final label = confirmed ? 'CONFIRMED' : 'PENDING';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(4)),
      child: Text(label, style: ty.outcomeTag(fg)),
    );
  }
}
