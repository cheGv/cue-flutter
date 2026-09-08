// lib/services/clients_query.dart
//
// Phase 4.0.7.29 Stage 2A — THE single read gate for the `clients` table.
//
// Every DIRECT read of `clients` in a real workflow must route through
// [ClientsQuery.read]. It bakes in the two safety predicates that were
// previously scattered per-query (or missing entirely):
//   • deleted_at IS NULL    — soft-delete (was duplicated across 7+ call sites)
//   • is_trial_case = false — Trial Run wall: a trial case (a clients row with
//                             is_trial_case = true) must NEVER surface in a real
//                             workflow.
//
// Seeing trial cases requires an EXPLICIT opt-in: read(..., includeTrial: true).
// The ONLY caller permitted to opt in is Stage 2B's "Trial runs" section.
// Nothing in a real workflow may pass includeTrial: true.
//
// NOTE (Stage 2A.3): join/aggregate surfaces that reach `clients` indirectly
// via sessions / short_term_goals / daily_roster cannot use this gate (their
// driving table is not `clients`). Those apply an explicit
// `.eq('clients.is_trial_case', false)` embedded filter at their own call
// sites. This gate covers DIRECT `clients` reads only.
//
// KNOWN DEPENDENCY: the cas_* child tables have RLS DISABLED in sandbox, so for
// the Pediatric CAS domain this app-layer gate (plus the enumerated join
// filters) is the ONLY trial wall until the 4.0.7.30 RLS pass.

import 'package:supabase_flutter/supabase_flutter.dart';

/// Whether a client may be opened. Only [live] lets a loader proceed.
enum ClientLiveness { live, deleted, missing }

/// The client exists but was soft-deleted (clients.deleted_at set).
/// Deleted means deleted, not hidden from lists: every capture loader
/// refuses with this, even when the caller holds the client's id.
class ClientDeletedException implements Exception {
  final String clientId;
  const ClientDeletedException(this.clientId);
  @override
  String toString() =>
      'This client was deleted. Restore it to open its records.';
}

/// No such client for this clinician (never existed, or not hers — RLS
/// makes those indistinguishable, deliberately).
class ClientNotFoundException implements Exception {
  final String clientId;
  const ClientNotFoundException(this.clientId);
  @override
  String toString() => 'This client could not be found.';
}

class ClientsQuery {
  ClientsQuery({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  /// Delete affordances Step 4 — the ONE read that wants soft-deleted rows:
  /// the restore list. Newest deletion first. Trial runs are excluded even
  /// here (they are hard-deleted, never soft; a stray flag must not offer a
  /// "restore" that would re-admit one to the real lists).
  PostgrestTransformBuilder<List<Map<String, dynamic>>> readDeleted(
      String columns) {
    return _client
        .from('clients')
        .select(columns)
        .not('deleted_at', 'is', null)
        .eq('is_trial_case', false)
        .order('deleted_at', ascending: false);
  }

  /// Pure: the decision [requireLiveClient] makes on the row it read.
  static ClientLiveness livenessOf(Map<String, dynamic>? row) {
    if (row == null) return ClientLiveness.missing;
    return row['deleted_at'] == null
        ? ClientLiveness.live
        : ClientLiveness.deleted;
  }

  /// Delete affordances Step 3 — the by-id gate that closes the hole the
  /// audit found: [read] filters LISTS, but the capture loaders key on
  /// client_id and never consulted deleted_at, so a soft-deleted client's
  /// assessments stayed reachable by id or deep link. Every capture parent
  /// loader (loadOrCreate / resolveParent) and the draft assembler call
  /// this FIRST and let it throw.
  ///
  /// Trial runs pass (the trial surface uses the same loaders); a row of
  /// another clinician reads as missing under RLS.
  Future<void> requireLiveClient(String clientId) async {
    final row = await _client
        .from('clients')
        .select('id, deleted_at')
        .eq('id', clientId)
        .maybeSingle();
    switch (livenessOf(row)) {
      case ClientLiveness.live:
        return;
      case ClientLiveness.deleted:
        throw ClientDeletedException(clientId);
      case ClientLiveness.missing:
        throw ClientNotFoundException(clientId);
    }
  }

  /// Base read of `clients`, scoped to NON-deleted, NON-trial rows by default.
  ///
  /// Returns a [PostgrestFilterBuilder] so callers chain their own
  /// `.eq(...)` / `.not(...)` / `.order(...)` / `.maybeSingle()` exactly as
  /// before — the two safety predicates are already applied at the root.
  ///
  /// [columns] is the PostgREST select list (use `'*'` for all columns).
  /// Pass [includeTrial] = true ONLY from the Trial-runs surface (Stage 2B).
  PostgrestFilterBuilder<List<Map<String, dynamic>>> read(
    String columns, {
    bool includeTrial = false,
  }) {
    final base =
        _client.from('clients').select(columns).isFilter('deleted_at', null);
    return includeTrial ? base : base.eq('is_trial_case', false);
  }
}
