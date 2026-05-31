import 'package:supabase_flutter/supabase_flutter.dart';

// Client briefing — Layer 1: per-SLP "last viewed" anchor (client_view_log).
//
// Records when the current clinician last opened a client's chart, so the
// briefing can compute "since your last visit". Per-SLP per-client (PK is
// user_id + client_id), RLS-scoped to auth.uid().
//
// CRITICAL ordering — read-then-write: [readPriorThenRecord] fetches the value
// as it was BEFORE this open (what the brief consumes), THEN upserts now().
// Updating first would make "since last visit" always read "just now".
class ClientViewLogRepository {
  final SupabaseClient _client;

  ClientViewLogRepository({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  static const _table = 'client_view_log';

  String? get _uid => _client.auth.currentUser?.id;

  /// The PRIOR last_viewed_at for (current user, [clientId]) — i.e. the value
  /// from the previous open. Returns null when this clinician has never opened
  /// this client before (first visit). Read-only; does NOT write.
  Future<DateTime?> fetchPriorViewedAt(String clientId) async {
    final uid = _uid;
    if (uid == null) return null;
    final row = await _client
        .from(_table)
        .select('last_viewed_at')
        .eq('user_id', uid)
        .eq('client_id', clientId)
        .maybeSingle();
    final raw = row?['last_viewed_at'] as String?;
    return raw == null ? null : DateTime.tryParse(raw);
  }

  /// Upsert (current user, [clientId]) → last_viewed_at = [at] (default now()).
  Future<void> recordView(String clientId, {DateTime? at}) async {
    final uid = _uid;
    if (uid == null) return;
    final ts = (at ?? DateTime.now().toUtc()).toIso8601String();
    await _client.from(_table).upsert(
      {
        'user_id': uid,
        'client_id': clientId,
        'last_viewed_at': ts,
      },
      onConflict: 'user_id,client_id',
    );
  }

  /// The read-then-write the chart runs on open: fetch the PRIOR timestamp
  /// (what the brief consumes this session), THEN stamp now(). Returns the
  /// prior value (null on first-ever visit). The write is best-effort — a
  /// write failure still returns the prior value already read.
  Future<DateTime?> readPriorThenRecord(String clientId, {DateTime? now}) async {
    final prior = await fetchPriorViewedAt(clientId);
    try {
      await recordView(clientId, at: now);
    } catch (_) {
      // Non-fatal: the prior value (already read) is what the brief needs;
      // a failed stamp just means next open sees the same prior.
    }
    return prior;
  }
}
