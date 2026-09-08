// lib/screens/deleted_clients_screen.dart
//
// Delete affordances, Step 4 — the durable way back for a soft-deleted
// client or assessment case. Mirrors archived_goals_screen.dart (list +
// restore, chart-card primitives, no new design) and closes the TODO that
// sat in settings_screen.dart since soft delete shipped.
//
// The Undo snackbar after a delete is transient; once it vanishes this is
// the only route back. Every row shows what was deleted, when, and the
// reason if one was given. Restore is ClientDeleteService.restore — the
// SAME call the Undo path makes (clears deleted_at + deleted_by +
// delete_reason). There is deliberately no second restore anywhere.
//
// Reads route through ClientsQuery.readDeleted, the one read in the app
// that wants soft-deleted rows; this screen never hand-writes that filter.
//
// Reached from Settings → "Deleted clients" (/settings/deleted).
//
// Loader and restorer are injectable at construction — this is a new
// screen, so the seam is its design, not a retrofit. Production defaults
// are the real query and the real service.

import 'package:flutter/material.dart';

import '../services/client_delete_service.dart';
import '../services/clients_query.dart';
import '../services/clients_roster_service.dart' show cueRelativeDayLabel;
import '../theme/cue_color_scheme.dart';
import '../theme/cue_text_styles.dart';
import '../widgets/app_layout.dart';
import '../widgets/chart/chart_card.dart';

/// One soft-deleted client, as the restore list shows it.
class DeletedClientRow {
  final String id;
  final String name;
  final bool isAssessmentCase;
  final DateTime? deletedAt;
  final String? reason;

  const DeletedClientRow({
    required this.id,
    required this.name,
    required this.isAssessmentCase,
    required this.deletedAt,
    required this.reason,
  });

  static DeletedClientRow fromRow(Map<String, dynamic> r) {
    final name = (r['name'] as String?)?.trim();
    final raw = r['deleted_at'];
    final reason = (r['delete_reason'] as String?)?.trim();
    return DeletedClientRow(
      id: r['id'].toString(),
      name: (name == null || name.isEmpty) ? 'Unnamed' : name,
      isAssessmentCase: r['engagement_type'] == 'assessment_only',
      deletedAt: raw is String ? DateTime.tryParse(raw)?.toLocal() : null,
      reason: (reason == null || reason.isEmpty) ? null : reason,
    );
  }

  String get kindLabel => isAssessmentCase ? 'Assessment case' : 'Client';

  /// "Deleted 2 days ago · Wrong client" — when, then the reason if any.
  /// Pure, so the copy is testable; [now] is injectable for that.
  String detailLine({DateTime? now}) {
    final when = deletedAt == null
        ? 'Deleted'
        : 'Deleted ${_relative(deletedAt!, now ?? DateTime.now())}';
    return reason == null ? when : '$when · $reason';
  }

  static String _relative(DateTime ref, DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    final refDay = DateTime(ref.year, ref.month, ref.day);
    if (today.difference(refDay).inDays <= 0) return 'today';
    return cueRelativeDayLabel(ref);
  }
}

/// The columns the list needs — exactly what [DeletedClientRow.fromRow]
/// reads.
const deletedClientsColumns =
    'id, name, engagement_type, deleted_at, delete_reason';

typedef DeletedClientsLoader = Future<List<DeletedClientRow>> Function();
typedef ClientRestorer = Future<void> Function(String clientId);

Future<List<DeletedClientRow>> _defaultLoader() async {
  final rows = await ClientsQuery().readDeleted(deletedClientsColumns);
  return [for (final r in rows) DeletedClientRow.fromRow(r)];
}

Future<void> _defaultRestorer(String clientId) =>
    ClientDeleteService().restore(clientId);

class DeletedClientsScreen extends StatefulWidget {
  final DeletedClientsLoader loader;
  final ClientRestorer restorer;

  /// Called after each successful restore so a launching list can refresh.
  final VoidCallback? onRestored;

  const DeletedClientsScreen({
    super.key,
    this.loader = _defaultLoader,
    this.restorer = _defaultRestorer,
    this.onRestored,
  });

  @override
  State<DeletedClientsScreen> createState() => _DeletedClientsScreenState();
}

class _DeletedClientsScreenState extends State<DeletedClientsScreen> {
  late Future<List<DeletedClientRow>> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.loader();
  }

  void _reload() {
    if (!mounted) return;
    // Block body, not an arrow: the arrow's value would be the loader's
    // Future and setState asserts on a callback that returns one.
    setState(() {
      _future = widget.loader();
    });
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _restore(DeletedClientRow row) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await widget.restorer(row.id);
    } catch (e) {
      messenger
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text("Couldn't restore: $e")));
      return;
    }
    widget.onRestored?.call();
    _reload();
    _snack('${row.name} is back in your lists.');
  }

  @override
  Widget build(BuildContext context) {
    return AppLayout(
      title: 'Deleted clients',
      activeRoute: 'settings',
      body: LayoutBuilder(
        builder: (context, constraints) {
          final tokens = CueChartTokens.of(context);
          final isCompact = constraints.maxWidth < 768;
          return ColoredBox(
            color: tokens.bgCanvas,
            child: FutureBuilder<List<DeletedClientRow>>(
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

  Widget _body(List<DeletedClientRow> rows, bool isCompact, CueChartTokens t) {
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
                if (rows.isEmpty)
                  _emptyState(ty)
                else
                  CueChartCard(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                    head: CueChartCardHead(
                        label: 'Deleted', count: '· ${rows.length}'),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (var i = 0; i < rows.length; i++)
                          _DeletedRow(
                            row: rows[i],
                            showTopBorder: i > 0,
                            onRestore: () => _restore(rows[i]),
                          ),
                      ],
                    ),
                  ),
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
              Text('Back to Settings', style: ty.footerItem),
            ],
          ),
        ),
      ),
    );
  }

  Widget _emptyState(CueChartType ty) {
    return CueChartCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Nothing deleted', style: ty.narratorStrong),
          const SizedBox(height: 8),
          Text(
            'Clients and assessment cases you delete appear here, ready to '
            'bring back. Nothing is erased.',
            style: ty.narratorBody,
          ),
        ],
      ),
    );
  }
}

/// One deleted row: name + kind on the first line, when + reason on the
/// second, and a single Restore action. Same register as the archived
/// goal row.
class _DeletedRow extends StatelessWidget {
  final DeletedClientRow row;
  final bool showTopBorder;
  final VoidCallback onRestore;

  const _DeletedRow({
    required this.row,
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        row.name,
                        style: ty.narratorStrong,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(row.kindLabel,
                        style: ty.ltgMeta.copyWith(color: t.textTertiary)),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  row.detailLine(),
                  style: ty.compactBody.copyWith(color: t.textSecondary),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
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
              "Couldn't load deleted clients.",
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
