import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/long_term_goal.dart';
import 'stg_repository.dart';

// Repository for `long_term_goals`.
//
// [listForClient] still returns RAW rows because the chart's LTG anchor +
// stg_numbering consume maps directly; adding the typed [LongTermGoal] model
// (lib/models/long_term_goal.dart) did not require churning those call sites.
// The lifecycle methods below own the soft-archive + status semantics; the
// archived list returns typed models.
class LtgRepository {
  final SupabaseClient _client;
  final StgRepository _stgRepo;

  LtgRepository({SupabaseClient? client, StgRepository? stgRepository})
      : _client = client ?? Supabase.instance.client,
        _stgRepo = stgRepository ??
            StgRepository(client: client ?? Supabase.instance.client);

  static const _table = 'long_term_goals';

  /// Non-archived LTGs for a client (any clinical status), by sequence. The
  /// chart shows these and styles by status; archived LTGs (deleted_at set) are
  /// excluded and only surface via [listArchivedForClient].
  Future<List<Map<String, dynamic>>> listForClient(String clientId) async {
    final rows = await _client
        .from(_table)
        .select()
        .eq('client_id', clientId)
        .isFilter('deleted_at', null)
        .order('sequence_num', ascending: true);
    return List<Map<String, dynamic>>.from(rows);
  }

  /// Archived LTGs for a client (deleted_at set), most-recently-archived first.
  /// Typed — backs the Undo / "Archived goals" restore path.
  Future<List<LongTermGoal>> listArchivedForClient(String clientId) async {
    final rows = await _client
        .from(_table)
        .select()
        .eq('client_id', clientId)
        .not('deleted_at', 'is', null)
        .order('deleted_at', ascending: false);
    return (rows as List)
        .map((r) => LongTermGoal.fromJson(Map<String, dynamic>.from(r as Map)))
        .toList();
  }

  // ── Lifecycle: clinician-initiated status changes ─────────────────────────
  //
  // Orthogonal to archival. Keeps the LTG visible (Completed / Closed section);
  // never touches deleted_at or any child STG / session / evidence.

  /// Set the LTG's clinical status. Stamps `achieved_at` on achieved and clears
  /// it on reactivation.
  Future<void> setStatus(String id, LtgStatus status) async {
    final nowIso = DateTime.now().toUtc().toIso8601String();
    final data = <String, dynamic>{
      'status': status.toJson(),
      'updated_at': nowIso,
    };
    if (status == LtgStatus.achieved) {
      data['achieved_at'] = nowIso;
    } else if (status == LtgStatus.active) {
      data['achieved_at'] = null;
    }
    await _client.from(_table).update(data).eq('id', id);
  }

  // ── Lifecycle: soft archive with reversible STG cascade ───────────────────
  //
  // NEVER hard-delete. Archiving an LTG stamps deleted_at on the LTG AND on its
  // currently-live child STGs with the SAME timestamp, so a restore re-activates
  // exactly those children (StgRepository matches on the shared timestamp).
  // Sessions/evidence are never touched.

  /// Archive [ltgId] and cascade to its currently-live child STGs. Returns the
  /// shared ISO timestamp written (the Undo handle).
  Future<String> archiveCascade(String ltgId) async {
    final ts = DateTime.now().toUtc().toIso8601String();
    // Children first, so a mid-failure leaves the LTG live (visible) rather
    // than orphaning archived children under a live LTG.
    await _stgRepo.archiveForLtg(ltgId, ts);
    await _client
        .from(_table)
        .update({'deleted_at': ts, 'updated_at': ts}).eq('id', ltgId);
    return ts;
  }

  /// Restore [ltgId] and re-activate exactly the children archived with it.
  /// Reads the LTG's own deleted_at and matches children against that value, so
  /// any STG archived independently (different timestamp) stays archived.
  Future<void> restoreCascade(String ltgId) async {
    final row = await _client
        .from(_table)
        .select('deleted_at')
        .eq('id', ltgId)
        .maybeSingle();
    final ts = row?['deleted_at'] as String?;
    if (ts == null) return; // already live — nothing to restore
    await _stgRepo.restoreForLtg(ltgId, ts);
    await _client.from(_table).update({
      'deleted_at': null,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', ltgId);
  }
}
