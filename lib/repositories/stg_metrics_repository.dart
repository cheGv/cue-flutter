import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/stg_session_metric.dart';

// Matches the `stg_session_metrics` table — per-STG per-session sparkline data.
class StgMetricsRepository {
  final SupabaseClient _client;

  StgMetricsRepository({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  static const _table = 'stg_session_metrics';

  /// Metrics for an STG ordered oldest-first — sparkline left-to-right order.
  Future<List<StgSessionMetric>> loadMetricsForStg(String stgId) async {
    final rows = await _client
        .from(_table)
        .select()
        .eq('stg_id', stgId)
        .order('recorded_at', ascending: true);
    return _mapRows(rows);
  }

  List<StgSessionMetric> _mapRows(List<dynamic> rows) => rows
      .map((r) => StgSessionMetric.fromJson(r as Map<String, dynamic>))
      .toList();
}
