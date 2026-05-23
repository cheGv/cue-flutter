// lib/screens/client_sessions_screen.dart
//
// Phase B — full session timeline (Prompt 3, Bundle 2b, PART C). The chart's
// "open all sessions →" link lands here: the complete session history with a
// date-range filter + debounced search. Reuses ChartSessionHistory for the
// expandable rows; headlines come from the same SessionHeadlineService.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide Session;

import '../models/session.dart';
import '../repositories/sessions_repository.dart';
import '../services/session_headline_service.dart';
import '../theme/cue_color_scheme.dart';
import '../theme/cue_text_styles.dart';
import '../widgets/app_layout.dart';
import '../widgets/chart/chart_session_history.dart';

enum _Range { last30, last90, all }

class ClientSessionsScreen extends StatefulWidget {
  final String clientId;
  final String? clientName;

  const ClientSessionsScreen({
    super.key,
    required this.clientId,
    this.clientName,
  });

  @override
  State<ClientSessionsScreen> createState() => _ClientSessionsScreenState();
}

class _ClientSessionsScreenState extends State<ClientSessionsScreen> {
  final _searchController = TextEditingController();
  final Map<int, String> _headlineOverrides = {};
  Timer? _debounce;

  _Range _range = _Range.all;
  String _searchQuery = '';
  late String _clientName = widget.clientName ?? '';
  late Future<List<Session>> _future;

  @override
  void initState() {
    super.initState();
    if (Supabase.instance.client.auth.currentUser == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final ret = Uri.encodeQueryComponent('/clients/${widget.clientId}');
        Navigator.pushReplacementNamed(context, '/login?return=$ret');
      });
    } else if (_clientName.isEmpty) {
      _fetchClientName();
    }
    _reload();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _fetchClientName() async {
    try {
      final row = await Supabase.instance.client
          .from('clients')
          .select('name')
          .eq('id', widget.clientId)
          .maybeSingle();
      if (!mounted || row == null) return;
      setState(() => _clientName = (row['name'] as String?)?.trim() ?? '');
    } catch (_) {/* name stays empty; header tolerates it */}
  }

  DateTime? get _after => switch (_range) {
        _Range.last30 => DateTime.now().subtract(const Duration(days: 30)),
        _Range.last90 => DateTime.now().subtract(const Duration(days: 90)),
        _Range.all => null,
      };

  void _reload() {
    _future = SessionsRepository().loadForClientFiltered(
      widget.clientId,
      after: _after,
      searchQuery: _searchQuery.isEmpty ? null : _searchQuery,
    );
    _future.then((sessions) {
      if (mounted) _kickHeadlines(sessions);
    }).catchError((Object _) {});
  }

  void _kickHeadlines(List<Session> sessions) {
    final svc = SessionHeadlineService();
    for (final s in sessions.take(8)) {
      if (s.aiHeadline?.trim().isNotEmpty ?? false) continue;
      svc.headlineFor(s).then((text) {
        if (!mounted || text == null) return;
        setState(() => _headlineOverrides[s.id] = text);
      });
    }
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 200), () {
      if (!mounted) return;
      setState(() {
        _searchQuery = value.trim();
        _reload();
      });
    });
  }

  void _setRange(_Range r) {
    if (_range == r) return;
    setState(() {
      _range = r;
      _reload();
    });
  }

  @override
  Widget build(BuildContext context) {
    final cue = CueColorsResolved.of(context);
    return AppLayout(
      title: _clientName.isEmpty ? 'Sessions' : _clientName,
      activeRoute: 'roster',
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isCompact = constraints.maxWidth < 768;
          final rr = CueReadingRoom.of(context, isCompact: isCompact);
          final hPad = isCompact ? 16.0 : 24.0;
          return ColoredBox(
            color: cue.chartPaper,
            child: SingleChildScrollView(
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 760),
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(hPad, 12, hPad, 64),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _BackToChart(clientId: widget.clientId),
                        const SizedBox(height: 8),
                        Text(
                          _clientName.isEmpty ? '—' : _clientName,
                          style: rr.name.copyWith(fontSize: 24, color: cue.sienna),
                        ),
                        const SizedBox(height: 6),
                        Text('SESSION HISTORY', style: rr.sectionLabel),
                        const SizedBox(height: 16),
                        _filterRow(cue, rr),
                        const SizedBox(height: 18),
                        FutureBuilder<List<Session>>(
                          future: _future,
                          builder: (context, snap) {
                            if (snap.connectionState ==
                                    ConnectionState.waiting &&
                                !snap.hasData) {
                              return Text('—', style: rr.emptyItalic);
                            }
                            final sessions = snap.data ?? const <Session>[];
                            if (sessions.isEmpty) {
                              return Text(
                                'No sessions match this filter.',
                                style: rr.emptyItalic,
                              );
                            }
                            return ChartSessionHistory(
                              sessions: sessions,
                              clientName: _clientName,
                              headlineOverrides: _headlineOverrides,
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

  Widget _filterRow(CueColorsResolved cue, CueReadingRoom rr) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          children: [
            _rangeChip('30 days', _Range.last30, cue, rr),
            _rangeChip('90 days', _Range.last90, cue, rr),
            _rangeChip('All time', _Range.all, cue, rr),
          ],
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _searchController,
          onChanged: _onSearchChanged,
          style: rr.compactText,
          decoration: InputDecoration(
            isDense: true,
            hintText: 'Search sessions…',
            hintStyle: rr.historyMeta,
            prefixIcon: Icon(Icons.search, size: 18, color: cue.textSecondary),
            border: OutlineInputBorder(
              borderSide: BorderSide(color: cue.border, width: 0.5),
            ),
            enabledBorder: OutlineInputBorder(
              borderSide: BorderSide(color: cue.border, width: 0.5),
            ),
            focusedBorder: OutlineInputBorder(
              borderSide: BorderSide(color: cue.sienna, width: 1),
            ),
          ),
        ),
      ],
    );
  }

  Widget _rangeChip(
    String label,
    _Range r,
    CueColorsResolved cue,
    CueReadingRoom rr,
  ) {
    final selected = _range == r;
    return InkWell(
      onTap: () => _setRange(r),
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? cue.sienna.withValues(alpha: 0.10) : null,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected
                ? cue.sienna.withValues(alpha: 0.30)
                : cue.border,
            width: 0.5,
          ),
        ),
        child: Text(
          label,
          style: rr.chip(selected ? cue.sienna : cue.textSecondary),
        ),
      ),
    );
  }
}

class _BackToChart extends StatelessWidget {
  final String clientId;
  const _BackToChart({required this.clientId});

  @override
  Widget build(BuildContext context) {
    final cue = CueColorsResolved.of(context);
    final rr = CueReadingRoom.of(context, isCompact: false);
    return Align(
      alignment: Alignment.centerLeft,
      child: InkWell(
        onTap: () {
          if (Navigator.canPop(context)) {
            Navigator.pop(context);
          } else {
            Navigator.pushReplacementNamed(context, '/clients/$clientId');
          }
        },
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.arrow_back_rounded, size: 15, color: cue.sienna),
              const SizedBox(width: 6),
              Text('Back to chart', style: rr.historyLink),
            ],
          ),
        ),
      ),
    );
  }
}
