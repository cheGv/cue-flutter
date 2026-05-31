// lib/services/goals_query.dart
//
// THE single read gate for the goal tables (short_term_goals / long_term_goals).
//
// Mirrors the ClientsQuery pattern: every DIRECT read of a goal table in a
// screen or service routes through here, so the soft-archive filter
// (deleted_at IS NULL) lives in ONE place instead of being hand-written at each
// call site. A goal with deleted_at set is ARCHIVED (hidden, reversibly) and
// must never surface in a normal goal read.
//
// Returns a PostgrestFilterBuilder so callers chain their own
// `.eq(...)` / `.order(...)` / `.limit()` / `.maybeSingle()` exactly as before —
// the archive filter is already applied at the root.
//
// NOTE: the typed goal repositories (stg_repository / ltg_repository) apply the
// same filter inside their own methods; this gate covers the direct,
// differently-shaped queries (clinician-scoped counts, joined trial filters,
// AI-context all-status reads) that don't fit a typed repository method.

import 'package:supabase_flutter/supabase_flutter.dart';

class GoalsQuery {
  GoalsQuery({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  /// Read `short_term_goals`, excluding soft-archived rows (deleted_at IS NULL).
  /// [columns] is the PostgREST select list (default `'*'`).
  PostgrestFilterBuilder<List<Map<String, dynamic>>> stgReads([
    String columns = '*',
  ]) =>
      _client
          .from('short_term_goals')
          .select(columns)
          .isFilter('deleted_at', null);

  /// Read `long_term_goals`, excluding soft-archived rows (deleted_at IS NULL).
  /// [columns] is the PostgREST select list (default `'*'`).
  PostgrestFilterBuilder<List<Map<String, dynamic>>> ltgReads([
    String columns = '*',
  ]) =>
      _client
          .from('long_term_goals')
          .select(columns)
          .isFilter('deleted_at', null);
}
