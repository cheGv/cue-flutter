// lib/constants/app_routes.dart
//
// Centralized route paths. Use these constants instead of hardcoding
// path strings at call sites so a destination can be repointed in one
// place.

class AppRoutes {
  AppRoutes._();

  static const String today = '/today';
  static const String clients = '/clients';

  // Phase 4.1.7 — Inbox screen shipped. The Clients action-line banner
  // ("N sessions waiting to be documented") routes here via
  // Navigator.pushNamed(context, AppRoutes.inbox); both the banner and
  // the Inbox screen read from the same draft-session query in
  // ClientsRosterService.listDraftSessions().
  static const String inbox = '/inbox';
}
