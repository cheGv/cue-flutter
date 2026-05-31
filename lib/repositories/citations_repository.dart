import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/citation.dart';

// Matches the `citations` table — academic / clinical evidence per STG.
class CitationsRepository {
  final SupabaseClient _client;

  CitationsRepository({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  static const _table = 'citations';

  /// Citations for a single STG, in display order (the evidence-ladder order).
  Future<List<Citation>> loadCitationsForStg(String stgId) async {
    final rows = await _client
        .from(_table)
        .select()
        .eq('stg_id', stgId)
        .order('display_order', ascending: true);
    return _mapRows(rows);
  }

  /// All citations for a client, joined through their STGs (citations.stg_id ->
  /// short_term_goals.id -> short_term_goals.client_id). Ordered by STG, then
  /// display order. The embedded short_term_goals object is ignored by
  /// Citation.fromJson.
  Future<List<Citation>> loadCitationsForClient(String clientId) async {
    final rows = await _client
        .from(_table)
        .select('*, short_term_goals!inner(client_id, deleted_at)')
        .eq('short_term_goals.client_id', clientId)
        // Don't surface citations whose parent STG is soft-archived.
        .filter('short_term_goals.deleted_at', 'is', null)
        .order('stg_id', ascending: true)
        .order('display_order', ascending: true);
    return _mapRows(rows);
  }

  List<Citation> _mapRows(List<dynamic> rows) =>
      rows.map((r) => Citation.fromJson(r as Map<String, dynamic>)).toList();
}
