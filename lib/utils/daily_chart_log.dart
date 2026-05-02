// lib/utils/daily_chart_log.dart
//
// Tracks which client charts the SLP has opened today, for Monday-first
// noticed-moment detection. Backed by SharedPreferences.
//
// Storage shape:
//   key   = "clients_opened_today_<YYYY-MM-DD>"
//   value = comma-separated list of client UUIDs in open order
//
// Stale keys (anything that doesn't match today's date) are pruned on app
// start by [pruneStaleEntries].

import 'package:shared_preferences/shared_preferences.dart';

class DailyChartLog {
  DailyChartLog._();

  static const String _prefix = 'clients_opened_today_';

  static String _today() {
    final n = DateTime.now();
    return '${n.year.toString().padLeft(4, "0")}-'
           '${n.month.toString().padLeft(2, "0")}-'
           '${n.day.toString().padLeft(2, "0")}';
  }

  /// Reads today's open log. First entry was the first chart opened today.
  static Future<List<String>> readToday() async {
    final prefs = await SharedPreferences.getInstance();
    final raw   = prefs.getString('$_prefix${_today()}');
    if (raw == null || raw.isEmpty) return const [];
    return raw.split(',').where((s) => s.trim().isNotEmpty).toList();
  }

  /// Returns true if [clientId] is the first chart opened today (or if no
  /// chart has been opened yet today). The check is read-only.
  static Future<bool> isFirstClientToday(String clientId) async {
    final list = await readToday();
    if (list.isEmpty) return true;
    return list.first == clientId;
  }

  /// Appends [clientId] to today's log if not already present. Idempotent.
  static Future<void> markOpened(String clientId) async {
    if (clientId.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final key   = '$_prefix${_today()}';
    final raw   = prefs.getString(key) ?? '';
    final list  = raw.isEmpty
        ? <String>[]
        : raw.split(',').where((s) => s.trim().isNotEmpty).toList();
    if (list.contains(clientId)) return;
    list.add(clientId);
    await prefs.setString(key, list.join(','));
  }

  /// Removes any 'clients_opened_today_*' keys that don't belong to today.
  /// Call once on app launch.
  static Future<void> pruneStaleEntries() async {
    final prefs   = await SharedPreferences.getInstance();
    final today   = _today();
    final todayKey = '$_prefix$today';
    for (final k in prefs.getKeys().toList()) {
      if (k.startsWith(_prefix) && k != todayKey) {
        await prefs.remove(k);
      }
    }
  }
}
