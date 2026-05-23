// lib/screens/substrate_route.dart
//
// Host for SubstrateView. Self-loads (unlike TimelineRoute, which receives
// data via Navigator args) because no upstream surface owns substrate data
// yet — this is the verification harness for the Phase A read path. Mirrors
// the deep-link-loader pattern in main.dart.
//
// Reachability: registered ONLY behind kDebugMode in main.dart as
// /debug/substrate/:clientId (alongside the recall-test harness). It is
// tree-shaken from release builds and not wired into production navigation.
// The permanent mount point (a Profile tab, a chart surface, etc.) is a
// later decision.

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/substrate.dart';
import '../repositories/substrate_repository.dart';
import '../theme/cue_color_scheme.dart';
import '../theme/cue_type_v3.dart';
import '../widgets/substrate/substrate_view.dart';

class SubstrateRoute extends StatefulWidget {
  final String clientId;

  /// Optional — skips the clients name lookup when the caller already knows it.
  final String? clientName;

  const SubstrateRoute({
    super.key,
    required this.clientId,
    this.clientName,
  });

  @override
  State<SubstrateRoute> createState() => _SubstrateRouteState();
}

class _SubstrateRouteState extends State<SubstrateRoute> {
  late Future<_SubstrateData> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_SubstrateData> _load() async {
    final repo = SubstrateRepository();

    // Exercise the full Phase A read path in one shot (step 4): both cell and
    // relation queries, plus a lightweight name lookup for page identity.
    // Awaited sequentially so a failure in one can't leave the other as a
    // dangling future logging stray errors during verification.
    final cells = await repo.loadCellsForClient(widget.clientId);
    final relations = await repo.loadAllRelations();

    var name = widget.clientName;
    if (name == null || name.trim().isEmpty) {
      try {
        final row = await Supabase.instance.client
            .from('clients')
            .select('name')
            .eq('id', widget.clientId)
            .maybeSingle();
        name = row?['name'] as String?;
      } catch (_) {
        // Name is cosmetic for the harness; fall through to "Substrate".
      }
    }

    return _SubstrateData(cells: cells, relations: relations, clientName: name);
  }

  @override
  Widget build(BuildContext context) {
    final cue = CueColorsResolved.of(context);

    return Scaffold(
      backgroundColor: cue.bgCanvas,
      appBar: AppBar(title: const Text('Substrate')),
      body: FutureBuilder<_SubstrateData>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  'Could not load the substrate.\n${snapshot.error}',
                  textAlign: TextAlign.center,
                  style: CueTypeV3.body(color: cue.textBody),
                ),
              ),
            );
          }

          final data = snapshot.data!;
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 820),
              child: SingleChildScrollView(
                child: SubstrateView(
                  cells: data.cells,
                  relations: data.relations,
                  clientName: data.clientName,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _SubstrateData {
  final List<SubstrateCell> cells;
  final List<SubstrateRelation> relations;
  final String? clientName;

  const _SubstrateData({
    required this.cells,
    required this.relations,
    required this.clientName,
  });
}
