import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/stg_evidence.dart';

// Matches the `stg_evidence` table.
// session_id is bigint (int) — sessions.id is a bigint identity column.
// patient_id is uuid (String) — references clients.id.
class StgEvidenceRepository {
  final SupabaseClient _client;

  StgEvidenceRepository({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  static const _table = 'stg_evidence';

  Future<List<StgEvidence>> listForStg(String stgId) async {
    final rows = await _client
        .from(_table)
        .select()
        .eq('stg_id', stgId)
        .order('created_at', ascending: false);
    return _mapRows(rows);
  }

  Future<List<StgEvidence>> listForSession(int sessionId) async {
    final rows = await _client
        .from(_table)
        .select()
        .eq('session_id', sessionId)
        .order('created_at', ascending: false);
    return _mapRows(rows);
  }

  Future<StgEvidence> create(StgEvidence evidence) async {
    final row = await _client
        .from(_table)
        .insert(evidence.toInsertJson())
        .select()
        .single();
    return StgEvidence.fromJson(row);
  }

  Future<StgEvidence> markVerified(String id) async {
    final row = await _client
        .from(_table)
        .update({'clinician_verified': true})
        .eq('id', id)
        .select()
        .single();
    return StgEvidence.fromJson(row);
  }

  List<StgEvidence> _mapRows(List<dynamic> rows) =>
      rows.map((r) => StgEvidence.fromJson(r as Map<String, dynamic>)).toList();
}
