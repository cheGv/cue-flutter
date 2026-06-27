import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/cas_session_progress.dart';

// Matches the `cas_session_progress` table.
//   session_id is bigint (int) — sessions.id is a bigint identity column.
//   client_id  is uuid (String) — references clients.id (CAS-family naming).
//
// Reads/writes rows and calls the assembler RPC. NO business logic, NO trend
// assembly in Dart — the verbatim trend lives in the SQL function
// assemble_cas_progress (single source of truth), exactly as the recall card's
// assembly lives in assemble_recall_card.
class CasSessionProgressRepository {
  final SupabaseClient _client;

  CasSessionProgressRepository({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  static const _table = 'cas_session_progress';

  /// Upsert N level rows for one (session, stg, client) — one row per
  /// complexity level. The conflict target is the UNIQUE
  /// (session_id, stg_id, level_order), so re-capturing the same session's
  /// levels overwrites in place instead of inserting duplicates. Returns the
  /// stored rows (with server-assigned id + created_at).
  ///
  /// Callers build the list with [CasSessionProgress.draft] (which applies the
  /// CueLevel tolerance); every row in one call should share the same
  /// session_id / stg_id / client_id.
  Future<List<CasSessionProgress>> upsertLevels(
    List<CasSessionProgress> levels,
  ) async {
    if (levels.isEmpty) return const [];
    final payload = levels.map((l) => l.toInsertJson()).toList();
    final rows = await _client
        .from(_table)
        .upsert(payload, onConflict: 'session_id,stg_id,level_order')
        .select();
    return _mapRows(rows);
  }

  /// All progress rows for an STG — newest session first, then by level_order
  /// (matches the sibling repos' newest-first ordering). This is the raw-row
  /// read; for the assembled, session-grouped trend use [callBrief].
  Future<List<CasSessionProgress>> readForStg(String stgId) async {
    final rows = await _client
        .from(_table)
        .select()
        .eq('stg_id', stgId)
        .order('session_id', ascending: false)
        .order('level_order', ascending: true);
    return _mapRows(rows);
  }

  /// Thin RPC passthrough to the SQL assembler. Returns the verbatim assembled
  /// brief jsonb — shape: { stg_id, assembled_at, sessions: [ { session_id,
  /// session_date, levels: [...] } ] }, with sessions = [] (never null) when
  /// there is no history. No assembly happens here; the SQL function is the
  /// single source of truth.
  Future<Map<String, dynamic>> callBrief(String stgId) async {
    final result = await _client.rpc(
      'assemble_cas_progress',
      params: {'p_stg_id': stgId},
    );
    return Map<String, dynamic>.from(result as Map);
  }

  List<CasSessionProgress> _mapRows(List<dynamic> rows) => rows
      .map((r) => CasSessionProgress.fromJson(r as Map<String, dynamic>))
      .toList();
}
