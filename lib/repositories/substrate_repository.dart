import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/substrate.dart';

// Reads the Phase A substrate tables (migration
// 20260521120000_phase_a_substrate_tables.sql).
//
// substrate_cells.client_id references clients(id); substrate_relations is a
// GLOBAL graph (not per-client). RLS is deferred (§11) so in the sandbox
// these reads run unscoped — every clinician sees every row. Per-clinician
// isolation lands before external onboarding (policy template in the
// migration footer).
class SubstrateRepository {
  final SupabaseClient _client;

  SubstrateRepository({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  static const _cells = 'substrate_cells';
  static const _relations = 'substrate_relations';

  /// Every cell for a client, each with its embedded sources and tags
  /// (PostgREST FK embedding — one round trip).
  ///
  /// Ordered by created_at so the within-layer order is stable (seed
  /// insertion order). Layer grouping/ordering is the view's job via
  /// SubstrateLayer's fixed declaration order: ordering by the `layer`
  /// text column would sort 'safety_regulation' LAST alphabetically and
  /// break the "regulation always first" paradigm.
  Future<List<SubstrateCell>> loadCellsForClient(String clientId) async {
    final rows = await _client
        .from(_cells)
        .select('*, substrate_sources(*), substrate_tags(*)')
        .eq('client_id', clientId)
        .order('created_at', ascending: true);
    return rows.map(SubstrateCell.fromJson).toList();
  }

  /// The entire global threading graph. Independent of any client; consumed
  /// by tag-overlap traversal when threading interaction lands.
  Future<List<SubstrateRelation>> loadAllRelations() async {
    final rows = await _client.from(_relations).select();
    return rows.map(SubstrateRelation.fromJson).toList();
  }
}
