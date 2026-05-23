// Phase B — chart action-chip navigation (Prompt 3, Bundle 1, PART B).
//
// One source of truth for navigations triggered from any chart surface. Each
// handler verifies auth first (same pattern as the chart screen's guard) and
// returns a Future the caller can await to refresh chart state on return.
//
// Note: "Review last session" is intentionally NOT here — it's a local scroll
// (ChartSessionHistory.revealSession) that needs the screen's GlobalKey, so it
// lives in the screen. "New STG" routes to the goal-authoring flow (no STG-only
// entry / ltgId param exists on GoalAuthoringScreen).
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../screens/client_sessions_screen.dart';
import '../screens/goal_authoring_screen.dart';
import '../screens/session_planning_screen.dart';

class ChartNavigation {
  const ChartNavigation._();

  /// Returns true when authed; otherwise redirects to login (return → the
  /// chart) and returns false. Callers must short-circuit on false.
  static bool _ensureAuth(BuildContext context, String clientId) {
    if (Supabase.instance.client.auth.currentUser != null) return true;
    final ret = Uri.encodeQueryComponent('/clients/$clientId');
    Navigator.of(context).pushReplacementNamed('/login?return=$ret');
    return false;
  }

  static Future<void> authorLtg(
    BuildContext context, {
    required String clientId,
    required String clientName,
    required int sessionCount,
  }) async {
    if (!_ensureAuth(context, clientId)) return;
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => GoalAuthoringScreen(
        clientId: clientId,
        clientName: clientName,
        sessionCount: sessionCount,
      ),
    ));
  }

  /// No dedicated STG-only flow exists; opens the goal-authoring surface (which
  /// authors LTG + STGs for the client).
  static Future<void> newStg(
    BuildContext context, {
    required String clientId,
    required String clientName,
    required int sessionCount,
  }) =>
      authorLtg(
        context,
        clientId: clientId,
        clientName: clientName,
        sessionCount: sessionCount,
      );

  static Future<void> planSession(
    BuildContext context, {
    required String clientId,
    required String clientName,
    String? seedFocus,
  }) async {
    if (!_ensureAuth(context, clientId)) return;
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => SessionPlanningScreen(
        clientId: clientId,
        clientName: clientName,
        seedFocus: seedFocus,
      ),
    ));
  }

  static Future<void> documentSession(
    BuildContext context, {
    required String clientId,
    required int sessionId,
  }) async {
    if (!_ensureAuth(context, clientId)) return;
    // /sessions/:id/edit → SessionCaptureScreen edit mode (auth-guarded loader).
    await Navigator.of(context).pushNamed('/sessions/$sessionId/edit');
  }

  static Future<void> openSubstrate(
    BuildContext context, {
    required String clientId,
  }) async {
    if (!_ensureAuth(context, clientId)) return;
    await Navigator.of(context).pushNamed('/debug/substrate/$clientId');
  }

  static Future<void> openAllSessions(
    BuildContext context, {
    required String clientId,
    required String clientName,
  }) async {
    if (!_ensureAuth(context, clientId)) return;
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ClientSessionsScreen(
        clientId: clientId,
        clientName: clientName,
      ),
    ));
  }
}
