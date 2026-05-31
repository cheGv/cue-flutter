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

  /// Non-archived STGs for a client (any clinical status), newest first. The
  /// chart splits these into active / completed / closed by [ShortTermGoal]
  /// status; archived goals (deleted_at set) are excluded here and only
  /// surface via [listArchivedForClient].
  Future<List<ShortTermGoal>> listForClient(String clientId) async {
    final rows = await _client
        .from(_table)
        .select()
        .eq('client_id', clientId)
        .isFilter('deleted_at', null)
        .order('created_at', ascending: false);
    return _mapRows(rows);
  }

  /// Archived STGs for a client (deleted_at set), most-recently-archived first.
  /// Backs the Undo / "Archived goals" restore path.
  Future<List<ShortTermGoal>> listArchivedForClient(String clientId) async {
    final rows = await _client
        .from(_table)
        .select()
        .eq('client_id', clientId)
        .not('deleted_at', 'is', null)
        .order('deleted_at', ascending: false);
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

  // ── Lifecycle: clinician-initiated status changes ─────────────────────────
  //
  // Status is ORTHOGONAL to archival. A status change keeps the goal visible
  // on the chart (in the Completed / Closed section); it never touches
  // deleted_at, and it never touches linked sessions/evidence.

  /// Set the clinical status. Stamps `mastered_at` when moving to achieved and
  /// clears it on reactivation, so the completion timestamp tracks the state.
  Future<ShortTermGoal> setStatus(String id, StgStatus status) {
    final nowIso = DateTime.now().toUtc().toIso8601String();
    final data = <String, dynamic>{
      'status': status.toJson(),
      'updated_at': nowIso,
    };
    if (status == StgStatus.achieved || status == StgStatus.mastered) {
      data['mastered_at'] = nowIso;
    } else if (status == StgStatus.active) {
      data['mastered_at'] = null; // reactivating clears the completion stamp
    }
    return update(id, data);
  }

  // ── Lifecycle: soft archive (NEVER hard-delete) ───────────────────────────

  /// Archive a single STG (created-by-mistake path). Sets deleted_at; the goal
  /// vanishes from the chart but all linked sessions/evidence are untouched.
  /// Returns the ISO timestamp written (handy for an Undo that targets it).
  Future<String> archive(String id) async {
    final ts = DateTime.now().toUtc().toIso8601String();
    await _client
        .from(_table)
        .update({'deleted_at': ts, 'updated_at': ts}).eq('id', id);
    return ts;
  }

  /// Restore a single archived STG (Undo) — nulls deleted_at.
  Future<void> restore(String id) async {
    await _client.from(_table).update({
      'deleted_at': null,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', id);
  }

  // ── Lifecycle: LTG-cascade helpers (reversible) ───────────────────────────
  //
  // When an LTG is archived, its CURRENTLY-LIVE children are stamped with the
  // SAME timestamp as the LTG. Restoring the LTG re-activates exactly those
  // children (matched on that shared timestamp), leaving any STG that was
  // archived independently — at a different time — still archived.

  /// Archive every currently-live child STG of [ltgId], stamping the shared
  /// [isoTimestamp]. STGs already archived (different timestamp) are left as-is.
  Future<void> archiveForLtg(String ltgId, String isoTimestamp) async {
    await _client
        .from(_table)
        .update({'deleted_at': isoTimestamp, 'updated_at': isoTimestamp})
        .eq('long_term_goal_id', ltgId)
        .isFilter('deleted_at', null);
  }

  /// Restore only the children archived AS PART OF this LTG archive — those
  /// whose deleted_at equals the LTG's [isoTimestamp].
  Future<void> restoreForLtg(String ltgId, String isoTimestamp) async {
    await _client
        .from(_table)
        .update({
          'deleted_at': null,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('long_term_goal_id', ltgId)
        .eq('deleted_at', isoTimestamp);
  }

  /// Count of currently-live child STGs under [ltgId] — drives the
  /// "its N short-term goals go with it" archive confirmation.
  Future<int> activeChildCount(String ltgId) async {
    final rows = await _client
        .from(_table)
        .select('id')
        .eq('long_term_goal_id', ltgId)
        .isFilter('deleted_at', null);
    return (rows as List).length;
  }

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
          final row = await _client
              .from(_table)
              .select()
              .eq('id', stgId)
              .isFilter('deleted_at', null) // never focus an archived STG
              .maybeSingle();
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
        .isFilter('deleted_at', null) // never focus an archived STG
        .order('created_at', ascending: false)
        .limit(1);
    final list = List<Map<String, dynamic>>.from(fallback);
    return list.isEmpty ? null : ShortTermGoal.fromJson(list.first);
  }

  List<ShortTermGoal> _mapRows(List<dynamic> rows) =>
      rows.map((r) => ShortTermGoal.fromJson(r as Map<String, dynamic>)).toList();
}
