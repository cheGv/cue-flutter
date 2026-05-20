// lib/services/recall_card_source.dart
//
// Cue Recall Assistant — card-source seam.
//
// The resolver depends ONLY on the `RecallCardSource` interface. A future
// local-store implementation (B in the design conversation) is added by
// providing another implementation of this interface and changing one
// binding; the resolver code is untouched. This seam is the entire reason
// the resolver is structured this way — see the design conversation
// "load-bearing seam" callout (2026-05-19).
//
// V1 ships ONE implementation, [DirectTableCardSource], which reads
// recall_cards directly via the Supabase client. RLS scopes the read to
// the calling clinician (user_id = auth.uid()) — no manual user_id
// filter, mirroring how every other direct-table read in the app behaves
// (e.g. ClientProfileScreen._fetchSessions at client_profile_screen.dart:
// 200-208).
//
// Measured fact (2026-05-19, sandbox): direct table read warm ~0.5 s.
// Hot-path budget is met without invoking the recall-card edge function.

import 'package:supabase_flutter/supabase_flutter.dart';

// ─────────────────────────────────────────────────────────────────
// Data model — mirrors the jsonb produced by
// public.assemble_recall_card(uuid). The field set is the contract
// between Postgres and Flutter; if the SQL assembler changes, this
// model is the one place Dart needs to update.
// ─────────────────────────────────────────────────────────────────

class RecallCard {
  final String clientId;
  final DateTime? assembledAt;
  final RecallLastSession? lastSession;
  final List<Map<String, dynamic>> activeStgs;
  final List<Map<String, dynamic>> activeLtgs;

  /// Raw jsonb payload. Kept for forward-compatibility: new fields land
  /// in `raw` automatically and can be promoted to typed getters later
  /// without breaking existing callers.
  final Map<String, dynamic> raw;

  const RecallCard({
    required this.clientId,
    required this.assembledAt,
    required this.lastSession,
    required this.activeStgs,
    required this.activeLtgs,
    required this.raw,
  });

  factory RecallCard.fromJson(Map<String, dynamic> json) {
    final lsRaw = json['last_session'];
    final lastSession = lsRaw is Map<String, dynamic>
        ? RecallLastSession.fromJson(lsRaw)
        : null;

    final stgs = (json['active_stgs'] as List?)
            ?.whereType<Map>()
            .map((m) => Map<String, dynamic>.from(m))
            .toList() ??
        const <Map<String, dynamic>>[];
    final ltgs = (json['active_ltgs'] as List?)
            ?.whereType<Map>()
            .map((m) => Map<String, dynamic>.from(m))
            .toList() ??
        const <Map<String, dynamic>>[];

    DateTime? parsedAssembledAt;
    final assembledRaw = json['assembled_at'];
    if (assembledRaw is String) {
      parsedAssembledAt = DateTime.tryParse(assembledRaw);
    }

    return RecallCard(
      clientId: (json['client_id'] ?? '').toString(),
      assembledAt: parsedAssembledAt,
      lastSession: lastSession,
      activeStgs: stgs,
      activeLtgs: ltgs,
      raw: json,
    );
  }
}

class RecallLastSession {
  final int? id;
  final String? date;
  final int? attempts;
  final int? independentResponses;
  final int? promptedResponses;
  final String? parentUpdate;
  final String? homeProgramme;
  final String? soapNote;
  final String? notes;
  final String? targetBehaviour;
  final String? activityName;
  final String? nextSessionFocus;
  final String? clientAffect;
  final bool? goalMet;

  /// Raw last_session map. Same forward-compat rationale as RecallCard.raw.
  final Map<String, dynamic> raw;

  const RecallLastSession({
    required this.id,
    required this.date,
    required this.attempts,
    required this.independentResponses,
    required this.promptedResponses,
    required this.parentUpdate,
    required this.homeProgramme,
    required this.soapNote,
    required this.notes,
    required this.targetBehaviour,
    required this.activityName,
    required this.nextSessionFocus,
    required this.clientAffect,
    required this.goalMet,
    required this.raw,
  });

  factory RecallLastSession.fromJson(Map<String, dynamic> json) {
    int? toInt(dynamic v) {
      if (v == null) return null;
      if (v is int) return v;
      if (v is num) return v.toInt();
      if (v is String) return int.tryParse(v);
      return null;
    }

    String? toStr(dynamic v) {
      if (v == null) return null;
      final s = v.toString().trim();
      return s.isEmpty ? null : s;
    }

    bool? toBool(dynamic v) {
      if (v == null) return null;
      if (v is bool) return v;
      if (v is String) {
        if (v.toLowerCase() == 'true') return true;
        if (v.toLowerCase() == 'false') return false;
      }
      return null;
    }

    return RecallLastSession(
      id: toInt(json['id']),
      date: toStr(json['date']),
      attempts: toInt(json['attempts']),
      independentResponses: toInt(json['independent_responses']),
      promptedResponses: toInt(json['prompted_responses']),
      parentUpdate: toStr(json['parent_update']),
      homeProgramme: toStr(json['home_programme']),
      soapNote: toStr(json['soap_note']),
      notes: toStr(json['notes']),
      targetBehaviour: toStr(json['target_behaviour']),
      activityName: toStr(json['activity_name']),
      nextSessionFocus: toStr(json['next_session_focus']),
      clientAffect: toStr(json['client_affect']),
      goalMet: toBool(json['goal_met']),
      raw: json,
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// The seam — abstract interface the resolver depends on.
// ─────────────────────────────────────────────────────────────────

abstract class RecallCardSource {
  /// Returns the card for [clientId], or null if no card exists / the
  /// row's card payload is null (e.g. dirty-but-never-assembled).
  /// Implementations MUST NOT throw on common failure paths
  /// (network blip, row absent); they return null and let the resolver
  /// route the question to the slow path.
  Future<RecallCard?> getCard(String clientId);
}

// ─────────────────────────────────────────────────────────────────
// V1 implementation — direct read on public.recall_cards.
// ─────────────────────────────────────────────────────────────────

class DirectTableCardSource implements RecallCardSource {
  final SupabaseClient _client;

  /// Constructor mirrors ClientsRosterService / StgRepository: optional
  /// supabase client param defaulting to the app's singleton. Test sites
  /// pass an explicit client; production call sites use the default.
  DirectTableCardSource({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  @override
  Future<RecallCard?> getCard(String clientId) async {
    try {
      final row = await _client
          .from('recall_cards')
          .select('card')
          .eq('client_id', clientId)
          .maybeSingle();

      if (row == null) return null;
      final cardRaw = row['card'];
      if (cardRaw is! Map) return null;
      final cardJson = Map<String, dynamic>.from(cardRaw);
      if (cardJson.isEmpty) return null;
      return RecallCard.fromJson(cardJson);
    } catch (_) {
      // Network / RLS / row-absent — all treated the same: the resolver
      // gets null and routes to the slow path. Errors here MUST NOT
      // propagate; the recall UX is "answer or fall through," never
      // "explode."
      return null;
    }
  }
}
