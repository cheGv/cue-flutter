// lib/services/day_state_service.dart
//
// Phase 4.0.7.5 — SLP-controlled Today day state.
//
// Three render states on Today: open (default), closed (SLP tapped Good
// night Cue), reopened (open after a previous close on the same date).
// Persistence: public.slp_day_states keyed by (slp_id, date). No row
// for a given date == open. Reopening flips state back to 'open' and
// stamps last_reopened_at; the original last_closed_at is preserved
// for audit so the "reopened" subtitle can render the close time.

import 'package:supabase_flutter/supabase_flutter.dart';

enum CueDayState { open, closed, reopened }

class DayStateRecord {
  final CueDayState state;
  final DateTime?   lastClosedAt;
  final DateTime?   lastReopenedAt;

  const DayStateRecord({
    required this.state,
    this.lastClosedAt,
    this.lastReopenedAt,
  });

  static const open = DayStateRecord(state: CueDayState.open);
}

class DayStateService {
  DayStateService._();
  static final instance = DayStateService._();

  SupabaseClient get _sb => Supabase.instance.client;

  String _todayDate() => DateTime.now().toIso8601String().split('T').first;

  /// Returns the day state for the current SLP on today's local date.
  /// Missing row → open. Row with state='open' AND last_closed_at present
  /// → reopened. Row with state='closed' → closed.
  Future<DayStateRecord> loadToday() async {
    final uid = _sb.auth.currentUser?.id;
    if (uid == null) return DayStateRecord.open;
    try {
      final row = await _sb
          .from('slp_day_states')
          .select('state, last_closed_at, last_reopened_at')
          .eq('slp_id', uid)
          .eq('date', _todayDate())
          .maybeSingle();
      if (row == null) return DayStateRecord.open;
      final stateStr = (row['state'] as String?) ?? 'open';
      final closedAt = _parseTs(row['last_closed_at']);
      final reopenedAt = _parseTs(row['last_reopened_at']);
      if (stateStr == 'closed') {
        return DayStateRecord(
          state:          CueDayState.closed,
          lastClosedAt:   closedAt,
          lastReopenedAt: reopenedAt,
        );
      }
      // state == 'open' but with a prior close means reopened.
      final isReopened = closedAt != null || reopenedAt != null;
      return DayStateRecord(
        state:          isReopened ? CueDayState.reopened : CueDayState.open,
        lastClosedAt:   closedAt,
        lastReopenedAt: reopenedAt,
      );
    } catch (_) {
      return DayStateRecord.open;
    }
  }

  /// Mark the current day as closed for this SLP.
  Future<DayStateRecord> closeToday() async {
    final uid = _sb.auth.currentUser?.id;
    if (uid == null) return DayStateRecord.open;
    final now = DateTime.now().toUtc().toIso8601String();
    final today = _todayDate();
    try {
      await _sb.from('slp_day_states').upsert({
        'slp_id':         uid,
        'date':           today,
        'state':          'closed',
        'last_closed_at': now,
        'updated_at':     now,
      }, onConflict: 'slp_id,date');
    } catch (_) {/* swallow — UI will reload state on next fetch */}
    return loadToday();
  }

  /// Reopen today: flip state back to open, stamp last_reopened_at.
  /// Preserves last_closed_at on the existing row for audit.
  Future<DayStateRecord> reopenToday() async {
    final uid = _sb.auth.currentUser?.id;
    if (uid == null) return DayStateRecord.open;
    final now = DateTime.now().toUtc().toIso8601String();
    final today = _todayDate();
    try {
      await _sb.from('slp_day_states').update({
        'state':            'open',
        'last_reopened_at': now,
        'updated_at':       now,
      }).eq('slp_id', uid).eq('date', today);
    } catch (_) {}
    return loadToday();
  }

  DateTime? _parseTs(dynamic v) {
    if (v is String && v.isNotEmpty) {
      try { return DateTime.parse(v).toLocal(); } catch (_) {}
    }
    return null;
  }
}
