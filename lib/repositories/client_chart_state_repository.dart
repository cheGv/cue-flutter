import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/client_chart_state.dart';

// Reads the `client_chart_state` SQL view (one row per non-deleted client).
//
// Named ClientChartStateRepository (not ChartContextRepository) to avoid
// collision with lib/utils/chart_context.dart, which is an unrelated
// AI-prompt context builder.
class ClientChartStateRepository {
  final SupabaseClient _client;

  ClientChartStateRepository({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  static const _view = 'client_chart_state';

  /// Derived chart state for a single client, or null if the client does not
  /// exist (or is soft-deleted — the view filters those out).
  Future<ClientChartState?> loadForClient(String clientId) async {
    final row = await _client
        .from(_view)
        .select()
        .eq('client_id', clientId)
        .maybeSingle();
    return row == null ? null : ClientChartState.fromJson(row);
  }
}
