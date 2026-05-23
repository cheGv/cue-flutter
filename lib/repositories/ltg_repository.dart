import 'package:supabase_flutter/supabase_flutter.dart';

// Minimal read repository for `long_term_goals`. There is no LTG Dart model
// yet, so this returns raw rows; the chart's LTG anchor extracts the primary
// goal's display fields. Added in Phase B so the chart avoids inline `.from()`
// queries (the per-prompt-1 discipline). A typed model can replace this later.
class LtgRepository {
  final SupabaseClient _client;

  LtgRepository({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  static const _table = 'long_term_goals';

  Future<List<Map<String, dynamic>>> listForClient(String clientId) async {
    final rows = await _client
        .from(_table)
        .select()
        .eq('client_id', clientId)
        .order('sequence_num', ascending: true);
    return List<Map<String, dynamic>>.from(rows);
  }
}
