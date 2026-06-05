// lib/services/hold_service.dart
//
// The Hold's working-memory brain (Phase 4.1.x). A DERIVED VIEW over
// existing repositories — it stores NOTHING. There is no hold_items table
// and no Hold-owned migration. Each item is present only while its source
// object is unfinished; it leaves on its own when the clinician resolves
// the underlying work. There is no "mark as read".
//
// Pattern mirrors today_widgets_service.dart / clients_roster_service.dart:
//   • currentUser guard → empty list when signed out
//   • parallel reads (Future.wait), each defensive (try/catch → empty)
//   • soft-delete + trial-case filtering inherited from the sources
//   • returns plain view-models, never throws into the UI
//
// V1 surfaces TWO data-ready sources only (draft session notes + notes
// awaiting attestation). The third approved source — in-flight goal-plan
// drafts — is DEFERRED: no screen today reopens a draft goal_plans row for
// a general client, so a tap would force a restart and break the Hold's one
// promise (tap → finish that work). The enum value below is kept so the
// re-entry seam is obvious; see loadHeldItems for exactly where it slots in.

import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'clients_roster_service.dart';
import 'name_formatter.dart';

/// What kind of unfinished work an item represents. All V1 kinds belong to
/// the single "work-in-flight" visual class.
enum HeldKind {
  /// A session note saved as a draft (sessions.status == 'draft').
  draftNote,

  /// DEFERRED — in-flight goal-plan draft (goal_plans.status == 'draft').
  /// Not produced in V1: no screen REOPENS a draft plan for a general
  /// client, so resuming would restart it. When a "reopen draft" door
  /// exists, restore source #2 in ~10 lines:
  ///   1. add a `_goalPlanDrafts()` helper (goal_plans where user_id=uid AND
  ///      status='draft' AND updated_at >= now()-14d, joined to clients for
  ///      name + trial filter), mapping to HeldItem whose resume opens that
  ///      new reopen-draft screen;
  ///   2. add `_goalPlanDrafts()` as a third future in loadHeldItems below.
  goalPlanDraft,

  /// A finalized note awaiting the clinician's review + attestation
  /// (sessions.status == 'complete', SOAP present, clinician_attested != true).
  pendingAiReview,
}

/// How tapping a held item routes the clinician back to the work. Carries
/// only data — the Navigator call lives in the strip widget (which has a
/// BuildContext). Both V1 sources use named routes.
@immutable
class HeldResume {
  final HeldKind kind;
  final String? namedRoute; // e.g. '/sessions/12/edit' or '/sessions/12'
  final String clientId;
  final String clientName;
  const HeldResume({
    required this.kind,
    required this.clientId,
    required this.clientName,
    this.namedRoute,
  });
}

/// One piece of unfinished work surfaced on The Hold. NEVER persisted.
@immutable
class HeldItem {
  final HeldKind kind;
  final String clientId;
  final String clientName;
  final String title; // one quiet line, e.g. "Draft note · Aarav"
  final DateTime recencyTs; // drives "most recent wins"
  final bool consequence; // the one verified urgency signal (in-assessment)
  final HeldResume resume;
  const HeldItem({
    required this.kind,
    required this.clientId,
    required this.clientName,
    required this.title,
    required this.recencyTs,
    required this.consequence,
    required this.resume,
  });
}

class HoldService {
  HoldService._();

  static final SupabaseClient _sb = Supabase.instance.client;

  /// All of the clinician's unfinished work, unscoped. The caller applies
  /// scope + salience via [scopeAndRank] (kept here so the rule lives in one
  /// place and the widget stays render-only).
  static Future<List<HeldItem>> loadHeldItems() async {
    final uid = _sb.auth.currentUser?.id;
    if (uid == null) return const [];

    final results = await Future.wait<List<HeldItem>>([
      _draftNotes(),
      _pendingAiReview(),
      // SEAM (deferred source #2): add `_goalPlanDrafts()` here once a
      // "reopen draft plan" screen exists. See HeldKind.goalPlanDraft.
    ]);

    return <HeldItem>[for (final r in results) ...r];
  }

  /// Apply salience for a given surface.
  ///   [clientId] given → that client's items only, most-recent first.
  ///   [clientId] null  → all clients, in-assessment first, then recency.
  /// We do NOT invent urgency beyond the verified in-assessment signal.
  static List<HeldItem> scopeAndRank(List<HeldItem> items, String? clientId) {
    final scoped = clientId == null
        ? <HeldItem>[...items]
        : items.where((i) => i.clientId == clientId).toList();

    if (clientId != null) {
      scoped.sort((a, b) => b.recencyTs.compareTo(a.recencyTs));
    } else {
      scoped.sort((a, b) {
        if (a.consequence != b.consequence) return a.consequence ? -1 : 1;
        return b.recencyTs.compareTo(a.recencyTs);
      });
    }
    return scoped;
  }

  /// Source #1 — draft session notes. Reuses listDraftSessions() verbatim:
  /// the documented single-source-of-truth (status='draft', soft-delete +
  /// trial filtered, client name joined, carries the in-assessment signal).
  static Future<List<HeldItem>> _draftNotes() async {
    try {
      final drafts = await ClientsRosterService().listDraftSessions();
      return [
        for (final d in drafts)
          HeldItem(
            kind: HeldKind.draftNote,
            clientId: d.clientId,
            clientName: d.clientName,
            title: 'Draft note · ${_firstName(d.clientName)}',
            recencyTs: d.sessionDate ?? d.updatedAt,
            consequence: d.consequenceSignal == ConsequenceSignal.inAssessment,
            resume: HeldResume(
              kind: HeldKind.draftNote,
              clientId: d.clientId,
              clientName: d.clientName,
              namedRoute: '/sessions/${d.id}/edit',
            ),
          ),
      ];
    } catch (_) {
      return const [];
    }
  }

  /// Source #3 — finalized notes awaiting attestation. Scoped to
  /// status='complete' ON PURPOSE: this is the load-bearing dedup that keeps
  /// a still-draft+unattested session from showing twice (it stays a draft
  /// note under source #1). Do NOT widen this to "not attested" regardless
  /// of status.
  static Future<List<HeldItem>> _pendingAiReview() async {
    final uid = _sb.auth.currentUser?.id;
    if (uid == null) return const [];
    try {
      final rows = await _sb
          .from('sessions')
          .select('id, client_id, date, updated_at, soap_note, '
              'clinician_attested, clients!inner(name, is_trial_case)')
          .eq('user_id', uid)
          .eq('status', 'complete')
          .isFilter('deleted_at', null)
          .eq('clients.is_trial_case', false)
          .order('updated_at', ascending: false);

      final out = <HeldItem>[];
      for (final raw in rows as List) {
        final r = Map<String, dynamic>.from(raw as Map);
        final soap = (r['soap_note'] as String?)?.trim();
        if (soap == null || soap.isEmpty) continue; // SOAP must be present
        if (r['clinician_attested'] == true) continue; // not yet attested

        final client = r['clients'] as Map?;
        final name =
            NameFormatter.displayName((client?['name'] as String?) ?? '');
        final id = (r['id'] as num).toInt();
        final cid = (r['client_id'] ?? '').toString();

        out.add(HeldItem(
          kind: HeldKind.pendingAiReview,
          clientId: cid,
          clientName: name,
          title: 'Ready to sign · ${_firstName(name)}',
          recencyTs: _parseTs(r['updated_at']) ??
              _parseTs(r['date']) ??
              DateTime.fromMillisecondsSinceEpoch(0),
          consequence: false, // no verified consequence signal for this source
          resume: HeldResume(
            kind: HeldKind.pendingAiReview,
            clientId: cid,
            clientName: name,
            namedRoute: '/sessions/$id',
          ),
        ));
      }
      return out;
    } catch (_) {
      return const [];
    }
  }

  static String _firstName(String fullName) {
    final t = fullName.trim();
    if (t.isEmpty) return 'this child';
    return t.split(RegExp(r'\s+')).first;
  }

  static DateTime? _parseTs(dynamic v) =>
      v is String && v.isNotEmpty ? DateTime.tryParse(v) : null;
}

/// Global ChangeNotifier singleton — mirrors cueHoldController / themeNotifier
/// / sidebarNotifier. Holds the current derived list (never source-of-truth
/// data). A monotonic token prevents an older in-flight load from clobbering
/// a newer one.
class HoldItemsController extends ChangeNotifier {
  List<HeldItem> _items = const [];
  bool _loading = false;
  int _token = 0;

  List<HeldItem> get items => _items;
  bool get loading => _loading;

  Future<void> refresh() async {
    final myToken = ++_token;
    _loading = true;
    notifyListeners();
    try {
      final next = await HoldService.loadHeldItems();
      if (myToken != _token) return; // superseded by a newer refresh
      _items = next;
      _loading = false;
      notifyListeners();
    } catch (_) {
      if (myToken != _token) return;
      _loading = false; // keep prior items; never throw into the UI
      notifyListeners();
    }
  }
}

final HoldItemsController holdItemsController = HoldItemsController();

/// App-wide route observer so the held-work strip can re-derive whenever the
/// clinician returns to the strip's screen (didPopNext). Registered in
/// main.dart's MaterialApp.navigatorObservers; the strip subscribes to it as
/// RouteAware. Typed to PageRoute so it fires for full-page routes only (not
/// dialogs / popups).
final RouteObserver<PageRoute<dynamic>> holdRouteObserver =
    RouteObserver<PageRoute<dynamic>>();
