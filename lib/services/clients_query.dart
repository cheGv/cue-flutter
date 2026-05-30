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

class ClientsQuery {
  ClientsQuery({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

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
