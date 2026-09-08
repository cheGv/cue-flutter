// lib/screens/archived_goals_screen.dart
//
// Thread A — Archived goals (minimal: list + restore).
//
// A clinician can archive a goal from the chart, but until now the only way to
// undo was the transient "Undo" snackbar. Once it vanished there was no in-app
// way back. This screen is that durable route: it lists THIS client's archived
// long-term and short-term goals and lets the clinician restore any of them to
// the active chart.
//
// Scope is deliberately minimal — list + restore only. No archive dates,
// reasons, search, filtering, or grouping. Every read/write routes through the
// existing goal repositories; this screen never hand-writes the archive filter:
//   • LtgRepository.listArchivedForClient / restoreCascade  (restoring an LTG
//     also re-activates the child STGs that were archived with it — the
//     repository owns that parent-child cascade)
//   • StgRepository.listArchivedForClient / restore
//
// Reached from client_profile_screen.dart via a quiet "View archived goals"
// link in the chart footer. After each restore it calls [onRestored] so the
// launching chart refreshes. Visual register reuses the chart's card
// primitives (CueChartCard / CueChartButton) — no new design.

import 'package:flutter/material.dart';

import '../models/long_term_goal.dart';
import '../models/short_term_goal.dart';
import '../repositories/ltg_repository.dart';
import '../repositories/stg_repository.dart';
import '../theme/cue_color_scheme.dart';
import '../theme/cue_text_styles.dart';
import '../widgets/app_layout.dart';
import '../widgets/chart/chart_card.dart';

/// Immutable snapshot of a client's archived goals for one load.
class _ArchivedGoals {
  final List<LongTermGoal> ltgs;
  final List<ShortTermGoal> stgs;
  const _ArchivedGoals(this.ltgs, this.stgs);
  bool get isEmpty => ltgs.isEmpty && stgs.isEmpty;
}

class ArchivedGoalsScreen extends StatefulWidget {
  final String clientId;
  final String clientName;

  /// Called after each successful restore so the launching chart can refresh
  /// (the restored goal reappears on the active chart even before the clinician
  /// navigates back).
  final VoidCallback? onRestored;

  const ArchivedGoalsScreen({
    super.key,
    required this.clientId,
    required this.clientName,
    this.onRestored,
  });

  @override
  State<ArchivedGoalsScreen> createState() => _ArchivedGoalsScreenState();
}

class _ArchivedGoalsScreenState extends State<ArchivedGoalsScreen> {
  final _ltgRepo = LtgRepository();
  final _stgRepo = StgRepository();
  late Future<_ArchivedGoals> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_ArchivedGoals> _load() async {
    // Kick off both reads before awaiting so they run concurrently. Both route
    // through the repository's archived-list method (deleted_at IS NOT NULL).
    final ltgsF = _ltgRepo.listArchivedForClient(widget.clientId);
    final stgsF = _stgRepo.listArchivedForClient(widget.clientId);
    return _ArchivedGoals(await ltgsF, await stgsF);
  }

  void _reload() {
    if (!mounted) return;
    // Block body, not an arrow: the arrow's value would be _load()'s Future
    // and setState asserts on a callback that returns one — which made
    // every restore throw right after it succeeded (debug builds).
    setState(() {
      _future = _load();
    });
  }

  /// First name only, with any trailing "(age)" parenthetical stripped —
  /// mirrors client_profile_screen's _firstName so the copy reads the same.
  String get _firstName {
    final cleaned = widget.clientName.replaceAll(RegExp(r'\(.*\)'), '').trim();
    final first = cleaned.split(RegExp(r'\s+')).first;
    return first.isEmpty ? widget.clientName : first;
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _restoreLtg(LongTermGoal ltg) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      // restoreCascade re-activates exactly the child STGs archived with this
      // LTG (matched on the shared timestamp). Existing repository logic — not
      // reimplemented here.
      await _ltgRepo.restoreCascade(ltg.id);
    } catch (e) {
      messenger
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text("Couldn't restore goal: $e")));
      return;
    }
    widget.onRestored?.call();
    _reload();
    _snack('Long-term goal restored to the chart.');
  }

  Future<void> _restoreStg(ShortTermGoal stg) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await _stgRepo.restore(stg.id);
    } catch (e) {
      messenger
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text("Couldn't restore goal: $e")));
      return;
    }
    widget.onRestored?.call();
    _reload();
    _snack('Short-term goal restored to the chart.');
  }

  String _stgText(ShortTermGoal s) {
    final sp = s.specific.trim();
    if (sp.isNotEmpty) return sp;
    final tb = s.targetBehavior?.trim();
    if (tb != null && tb.isNotEmpty) return tb;
    final m = s.measurable.trim();
    return m.isNotEmpty ? m : 'Untitled goal';
  }

  String _ltgText(LongTermGoal g) {
    final t = g.displayText.trim();
    return t.isEmpty ? 'Untitled goal' : t;
  }

  @override
  Widget build(BuildContext context) {
    return AppLayout(
      title: 'Archived goals',
      activeRoute: 'roster',
      body: LayoutBuilder(
        builder: (context, constraints) {
          final tokens = CueChartTokens.of(context);
          final isCompact = constraints.maxWidth < 768;
          return ColoredBox(
            color: tokens.bgCanvas,
            child: FutureBuilder<_ArchivedGoals>(
              future: _future,
              builder: (context, snap) {
                if (snap.hasError) {
                  return _ErrorBox(message: '${snap.error}', onRetry: _reload);
                }
                if (!snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                return _body(snap.data!, isCompact, tokens);
              },
            ),
          );
        },
      ),
    );
  }

  Widget _body(_ArchivedGoals data, bool isCompact, CueChartTokens t) {
    final ty = CueChartType.of(context);
    final hPad = isCompact ? 16.0 : 24.0;
    return SingleChildScrollView(
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1080),
          child: Padding(
            padding: EdgeInsets.fromLTRB(hPad, 12, hPad, 96),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _breadcrumb(t, ty),
                const SizedBox(height: 16),
                if (data.isEmpty)
                  _emptyState(ty)
                else ...[
                  if (data.ltgs.isNotEmpty) ...[
                    _goalCard(
                      'Long-term goals',
                      data.ltgs.length,
                      [
                        for (var i = 0; i < data.ltgs.length; i++)
                          _GoalRow(
                            text: _ltgText(data.ltgs[i]),
                            showTopBorder: i > 0,
                            onRestore: () => _restoreLtg(data.ltgs[i]),
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),
                  ],
                  if (data.stgs.isNotEmpty)
                    _goalCard(
                      'Short-term goals',
                      data.stgs.length,
                      [
                        for (var i = 0; i < data.stgs.length; i++)
                          _GoalRow(
                            text: _stgText(data.stgs[i]),
                            showTopBorder: i > 0,
                            onRestore: () => _restoreStg(data.stgs[i]),
                          ),
                      ],
                    ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _breadcrumb(CueChartTokens t, CueChartType ty) {
    return Align(
      alignment: Alignment.centerLeft,
      child: InkWell(
        onTap: () => Navigator.maybePop(context),
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.arrow_back_rounded, size: 16, color: t.textTertiary),
              const SizedBox(width: 6),
              Text("Back to $_firstName's chart", style: ty.footerItem),
            ],
          ),
        ),
      ),
    );
  }

  Widget _goalCard(String title, int count, List<Widget> rows) {
    return CueChartCard(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
      head: CueChartCardHead(label: title, count: '· $count'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: rows,
      ),
    );
  }

  Widget _emptyState(CueChartType ty) {
    return CueChartCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Nothing archived', style: ty.narratorStrong),
          const SizedBox(height: 8),
          Text(
            "Goals you archive from $_firstName's chart appear here, ready to "
            "bring back. Nothing is ever deleted.",
            style: ty.narratorBody,
          ),
        ],
      ),
    );
  }
}

/// One archived-goal row: the goal text + a Restore action. Mirrors the
/// lifecycle-goals row register (number-less, since the section header already
/// names the kind), with the lifecycle menu replaced by a single Restore btn.
class _GoalRow extends StatelessWidget {
  final String text;
  final bool showTopBorder;
  final VoidCallback onRestore;

  const _GoalRow({
    required this.text,
    required this.showTopBorder,
    required this.onRestore,
  });

  @override
  Widget build(BuildContext context) {
    final t = CueChartTokens.of(context);
    final ty = CueChartType.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: showTopBorder
          ? BoxDecoration(
              border: Border(top: BorderSide(color: t.borderDivider)),
            )
          : null,
      child: Row(
        children: [
          Expanded(
            child: Text(
              text,
              style: ty.compactBody.copyWith(color: t.textSecondary),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 12),
          CueChartButton(
            label: 'Restore',
            icon: Icons.restore_rounded,
            small: true,
            onTap: onRestore,
          ),
        ],
      ),
    );
  }
}

class _ErrorBox extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorBox({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final t = CueChartTokens.of(context);
    final ty = CueChartType.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              "Couldn't load archived goals.",
              style: ty.narratorStrong,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              message,
              style: ty.narratorBody.copyWith(color: t.textTertiary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            CueChartButton(
              label: 'Try again',
              icon: Icons.refresh_rounded,
              onTap: onRetry,
            ),
          ],
        ),
      ),
    );
  }
}
