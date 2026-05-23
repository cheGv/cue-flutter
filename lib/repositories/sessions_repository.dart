// supabase_flutter re-exports gotrue's `Session` (an auth session). Hide it so
// `Session` here unambiguously means our sessions-table model.
import 'package:supabase_flutter/supabase_flutter.dart' hide Session;
import '../models/session.dart';

// Matches the `sessions` table.
//
// Read-only for now. Session writes (create / update / attest / soft-delete)
// currently live inline across ~15 `.from('sessions')` call sites in screens
// and services. Those are intentionally NOT consolidated in Phase B (this is a
// data-layer-only prompt); they are flagged for a later cleanup pass. The
// "Write methods (deferred)" marker below is where they will land.
class SessionsRepository {
  final SupabaseClient _client;

  SessionsRepository({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  static const _table = 'sessions';

  /// Active (non-deleted) sessions for a client, newest first. By default
  /// excludes pre-session intents (status 'planned'/'draft') so chart counts +
  /// history reflect only sessions on record; pass includePlanned: true to
  /// include them (e.g. to look up a Plan-today draft for upsert).
  Future<List<Session>> loadForClient(
    String clientId, {
    bool includePlanned = false,
  }) async {
    final rows = await _client
        .from(_table)
        .select()
        .eq('client_id', clientId)
        .isFilter('deleted_at', null)
        .order('created_at', ascending: false);
    final list = _mapRows(rows);
    if (includePlanned) return list;
    return list
        .where((s) => s.status != 'planned' && s.status != 'draft')
        .toList();
  }

  /// Full-timeline load: date range applied server-side; optional case-
  /// insensitive text search applied client-side over soap_note / notes /
  /// next_session_focus / ai_headline. Excludes planned/draft by default.
  Future<List<Session>> loadForClientFiltered(
    String clientId, {
    DateTime? after,
    DateTime? before,
    String? searchQuery,
    bool includePlanned = false,
  }) async {
    var query = _client
        .from(_table)
        .select()
        .eq('client_id', clientId)
        .isFilter('deleted_at', null);
    if (after != null) query = query.gte('date', _isoDate(after));
    if (before != null) query = query.lte('date', _isoDate(before));
    final rows = await query.order('created_at', ascending: false);

    var list = _mapRows(rows);
    if (!includePlanned) {
      list = list
          .where((s) => s.status != 'planned' && s.status != 'draft')
          .toList();
    }
    final q = searchQuery?.trim().toLowerCase();
    if (q != null && q.isNotEmpty) {
      list = list.where((s) {
        final hay = [s.soapNote, s.notes, s.nextSessionFocus, s.aiHeadline]
            .whereType<String>()
            .join(' ')
            .toLowerCase();
        return hay.contains(q);
      }).toList();
    }
    return list;
  }

  /// A single session by its bigint id, or null if not found / soft-deleted.
  Future<Session?> loadById(int id) async {
    final row = await _client
        .from(_table)
        .select()
        .eq('id', id)
        .isFilter('deleted_at', null)
        .maybeSingle();
    return row == null ? null : Session.fromJson(row);
  }

  // ── Writes ───────────────────────────────────────────────────────────────
  // Broader session writes (attest / softDelete / full create) remain inline in
  // screens for now; consolidating them is a separate cleanup pass.

  /// Save a "Plan today's session" draft. If a planned session already exists
  /// for this client today, update its planned_focus in place; otherwise insert
  /// a new draft (status = 'planned'). Returns the planned session's id.
  Future<int> savePlannedSession({
    required String clientId,
    required String clientName,
    required String plannedFocus,
  }) async {
    final today = _todayIso();
    final existing = await _client
        .from(_table)
        .select('id')
        .eq('client_id', clientId)
        .eq('status', 'planned')
        .eq('date', today)
        .isFilter('deleted_at', null)
        .maybeSingle();
    if (existing != null) {
      final id = (existing['id'] as num).toInt();
      await _client
          .from(_table)
          .update({'planned_focus': plannedFocus}).eq('id', id);
      return id;
    }
    final uid = _client.auth.currentUser?.id;
    final inserted = await _client.from(_table).insert({
      'client_id': clientId,
      'client_name': clientName,
      'status': 'planned',
      'date': today,
      'planned_focus': plannedFocus,
      'user_id': ?uid,
    }).select('id').single();
    return (inserted['id'] as num).toInt();
  }

  /// Persist an AI-generated headline onto a session (cache write).
  Future<void> updateAiHeadline(int sessionId, String headline) async {
    await _client
        .from(_table)
        .update({'ai_headline': headline}).eq('id', sessionId);
  }

  static String _todayIso() => _isoDate(DateTime.now());

  static String _isoDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  List<Session> _mapRows(List<dynamic> rows) =>
      rows.map((r) => Session.fromJson(r as Map<String, dynamic>)).toList();
}
