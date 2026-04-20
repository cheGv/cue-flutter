import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/short_term_goal.dart';

// Matches the `short_term_goals` table. Uses actual column names — see §7 drift
// note in CLAUDE.md: long_term_goal_id / client_id / user_id (not ltg_id etc.).
class StgRepository {
  final SupabaseClient _client;

  StgRepository({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  static const _table = 'short_term_goals';

  Future<List<ShortTermGoal>> listForClient(String clientId) async {
    final rows = await _client
        .from(_table)
        .select()
        .eq('client_id', clientId)
        .order('created_at', ascending: false);
    return _mapRows(rows);
  }

  Future<List<ShortTermGoal>> listForLtg(String longTermGoalId) async {
    final rows = await _client
        .from(_table)
        .select()
        .eq('long_term_goal_id', longTermGoalId)
        .order('sequence_num', ascending: true);
    return _mapRows(rows);
  }

  Future<ShortTermGoal> create(Map<String, dynamic> insertData) async {
    final row = await _client
        .from(_table)
        .insert(insertData)
        .select()
        .single();
    return ShortTermGoal.fromJson(row);
  }

  Future<ShortTermGoal> update(
      String id, Map<String, dynamic> updateData) async {
    final row = await _client
        .from(_table)
        .update(updateData)
        .eq('id', id)
        .select()
        .single();
    return ShortTermGoal.fromJson(row);
  }

  // Convenience wrapper — never auto-advances to 'mastered' (§10 invariant).
  Future<ShortTermGoal> updateStatus(String id, StgStatus status) =>
      update(id, {'status': status.toJson()});

  List<ShortTermGoal> _mapRows(List<dynamic> rows) =>
      rows.map((r) => ShortTermGoal.fromJson(r as Map<String, dynamic>)).toList();
}
