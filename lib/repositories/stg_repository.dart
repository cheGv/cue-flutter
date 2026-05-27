import 'package:flutter/foundation.dart';
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

  /// The STG to show "in focus": the one with the most recent
  /// session_goal_data activity for this client, falling back to the
  /// most-recently-created active STG. Returns null when there are no STGs.
  Future<ShortTermGoal?> loadFocusedStgForClient(String clientId) async {
    try {
      final rows = await _client
          .from('session_goal_data')
          .select('short_term_goal_id, created_at, short_term_goals!inner(client_id)')
          .eq('short_term_goals.client_id', clientId)
          .not('short_term_goal_id', 'is', null)
          .order('created_at', ascending: false)
          .limit(1);
      final list = List<Map<String, dynamic>>.from(rows);
      if (list.isNotEmpty) {
        final stgId = list.first['short_term_goal_id']?.toString();
        if (stgId != null) {
          final row =
              await _client.from(_table).select().eq('id', stgId).maybeSingle();
          if (row != null) return ShortTermGoal.fromJson(row);
        }
      }
    } on PostgrestException catch (e) {
      // Focused-STG lookup is optional; on a DB/relationship error fall through
      // to the fallback below — but LOG it so the failure is never silent.
      debugPrint('[StgRepository.loadFocusedStgForClient] session_goal_data '
          'lookup failed (PostgREST ${e.code}): ${e.message} — falling back '
          'to most-recently-created active STG.');
    } catch (e, st) {
      debugPrint('[StgRepository.loadFocusedStgForClient] unexpected error: '
          '$e\n$st — falling back to most-recently-created active STG.');
    }
    final fallback = await _client
        .from(_table)
        .select()
        .eq('client_id', clientId)
        .eq('status', 'active')
        .order('created_at', ascending: false)
        .limit(1);
    final list = List<Map<String, dynamic>>.from(fallback);
    return list.isEmpty ? null : ShortTermGoal.fromJson(list.first);
  }

  List<ShortTermGoal> _mapRows(List<dynamic> rows) =>
      rows.map((r) => ShortTermGoal.fromJson(r as Map<String, dynamic>)).toList();
}
