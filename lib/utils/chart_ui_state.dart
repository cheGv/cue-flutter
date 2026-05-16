// lib/utils/chart_ui_state.dart
//
// Phase 4.1.0 — per-client persistence for chart-screen UI state:
//   • Expanded/collapsed LTG and STG ladder rows.
//   • Expanded/collapsed session-history rows.
//
// Backed by SharedPreferences. Keyed by client_id + a short scope. The
// keys are intentionally namespaced so the Phase 1.5 migration to a
// Supabase `goal_ui_state` (or session_ui_state) table can read the
// localStorage values once and then evict them.
//
// Storage shape (one key per row):
//   chart_ui_state:<scope>:<client_id>:<row_id> = "open" | "shut"
//
// Defaults follow the prompt:
//   • LTG ladder rows: collapsed by default.
//   • STG ladder rows: expanded by default.
//   • Session-history rows: the most-recent row expanded, older
//     rows collapsed — caller passes the default explicitly via
//     [defaultExpanded] since "most recent" is positional.
//
// Reads are async-safe — the public API returns `Future<bool>` for
// queries and `Future<void>` for writes. Widgets should pre-load the
// state in initState() into a local map and mutate it optimistically;
// see ChartGoalLadder for the canonical wiring pattern.

import 'package:shared_preferences/shared_preferences.dart';

enum ChartUiScope { ltg, stg, session }

/// Phase 4.1.2 — single-focus STG state. The chart screen shows at most one
/// STG expanded at any time; the rest render as compact rows. The currently
/// focused STG id persists per-client-per-SLP under
/// `chart_ui_state:focused_stg:<client_id>`. Default when no value exists:
/// caller's choice (typically the most-recently-updated active STG).

class ChartUiState {
  ChartUiState._();

  static const String _prefix = 'chart_ui_state';

  static String _scopeKey(ChartUiScope s) {
    switch (s) {
      case ChartUiScope.ltg:     return 'ltg';
      case ChartUiScope.stg:     return 'stg';
      case ChartUiScope.session: return 'sess';
    }
  }

  static String _key(ChartUiScope s, String clientId, String rowId) =>
      '$_prefix:${_scopeKey(s)}:$clientId:$rowId';

  /// Returns true if the given row is expanded. If no value is stored,
  /// returns [defaultExpanded].
  static Future<bool> isExpanded({
    required ChartUiScope scope,
    required String clientId,
    required String rowId,
    required bool defaultExpanded,
  }) async {
    if (clientId.isEmpty || rowId.isEmpty) return defaultExpanded;
    try {
      final prefs = await SharedPreferences.getInstance();
      final v = prefs.getString(_key(scope, clientId, rowId));
      if (v == 'open') return true;
      if (v == 'shut') return false;
      return defaultExpanded;
    } catch (_) {
      return defaultExpanded;
    }
  }

  /// Persists the expanded state for the given row.
  static Future<void> setExpanded({
    required ChartUiScope scope,
    required String clientId,
    required String rowId,
    required bool expanded,
  }) async {
    if (clientId.isEmpty || rowId.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _key(scope, clientId, rowId),
        expanded ? 'open' : 'shut',
      );
    } catch (_) {/* best-effort */}
  }

  // ── Focused-STG state (Phase 4.1.2) ────────────────────────────────────

  static String _focusedStgKey(String clientId) =>
      '$_prefix:focused_stg:$clientId';

  /// Returns the persisted focused STG id for [clientId], or null if none
  /// has been set yet (caller picks a default — typically the most
  /// recently updated active STG).
  static Future<String?> getFocusedStgId(String clientId) async {
    if (clientId.isEmpty) return null;
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_focusedStgKey(clientId));
    } catch (_) {
      return null;
    }
  }

  static Future<void> setFocusedStgId(String clientId, String stgId) async {
    if (clientId.isEmpty || stgId.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_focusedStgKey(clientId), stgId);
    } catch (_) {/* best-effort */}
  }
}
