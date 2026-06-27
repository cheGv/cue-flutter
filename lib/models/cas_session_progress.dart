import 'package:flutter/foundation.dart';

import 'short_term_goal.dart' show CueLevel;

// ---------------------------------------------------------------------------
// CasSessionProgress — immutable model for the `cas_session_progress` table.
//
// One row per (session x complexity level): the spine complexity (level) x
// accuracy x cue, captured per session and repeated over time. Stands beside
// cas_assessments (the one-time snapshot) as stg_evidence stands beside a goal.
//
// Column names match the actual Supabase schema:
//   session_id          bigint  (sessions.id is bigint identity, not uuid)
//   client_id           uuid    (references clients.id — CAS-family naming,
//                                NOT stg_evidence's outlier `patient_id`)
//   accuracy            text    (tolerant String; the DB CHECK enforces the
//                                three values 'accurate'|'partial'|'inaccurate'
//                                — mirrors stg_evidence keeping cue_level_used a
//                                plain String rather than a model-side enum)
//   cue_level_used      text    (CueLevel wire string)
//   cue_level_used_raw  text    (verbatim passthrough; populated only when the
//                                cue value did not parse to a canonical
//                                CueLevel — the *Raw-on-fallback convention from
//                                ShortTermGoal.currentCueLevelRaw)
// ---------------------------------------------------------------------------
@immutable
class CasSessionProgress {
  final String id;
  final String stgId;
  final int sessionId; // bigint — sessions.id
  final String clientId; // uuid — clients.id

  final String levelLabel;
  final int levelOrder;

  // Tolerant String — the DB CHECK is the enforcer (accurate|partial|inaccurate).
  final String? accuracy;

  // Normalized CueLevel wire string (independent|minimal|moderate|maximal|
  // hand_over_hand|unknown). Read [cueLevel] for the typed view.
  final String? cueLevelUsed;
  // Verbatim original — set only when [cueLevelUsed] is 'unknown' (parser
  // fallback), so an unexpected cue value survives the round-trip.
  final String? cueLevelUsedRaw;

  final DateTime createdAt;

  const CasSessionProgress({
    required this.id,
    required this.stgId,
    required this.sessionId,
    required this.clientId,
    required this.levelLabel,
    required this.levelOrder,
    this.accuracy,
    this.cueLevelUsed,
    this.cueLevelUsedRaw,
    required this.createdAt,
  });

  /// Typed view of the stored cue. Tolerant: a null/unrecognized stored value
  /// resolves to [CueLevel.unknown]; the verbatim original remains in
  /// [cueLevelUsedRaw]. Never throws.
  CueLevel get cueLevel => CueLevel.fromString(cueLevelUsed) ?? CueLevel.unknown;

  /// Display value for the cue — the raw token when the enum fell back to
  /// `unknown` (so a non-canonical value still shows), else the enum label.
  /// Mirrors ShortTermGoal.currentCueLevelDisplay.
  String? get cueLevelDisplay {
    final c = cueLevel;
    if (c == CueLevel.unknown) return cueLevelUsedRaw;
    return c.displayLabel();
  }

  factory CasSessionProgress.fromJson(Map<String, dynamic> json) =>
      CasSessionProgress(
        id: json['id'] as String,
        stgId: json['stg_id'] as String,
        sessionId: (json['session_id'] as num).toInt(),
        clientId: json['client_id'] as String,
        levelLabel: json['level_label'] as String,
        levelOrder: (json['level_order'] as num).toInt(),
        accuracy: json['accuracy'] as String?,
        cueLevelUsed: json['cue_level_used'] as String?,
        cueLevelUsedRaw: json['cue_level_used_raw'] as String?,
        createdAt: DateTime.parse(json['created_at'] as String),
      );

  /// Build an insert-ready level row from a RAW cue value, applying CueLevel
  /// tolerance: [cueLevelUsed] becomes the normalized wire string, and the
  /// original [cueRaw] is preserved in [cueLevelUsedRaw] only when it failed to
  /// parse to a canonical CueLevel (i.e. normalized to 'unknown'). Never throws
  /// on an unexpected cue. id + created_at are server-assigned; the placeholders
  /// here are dropped by [toInsertJson].
  factory CasSessionProgress.draft({
    required String stgId,
    required int sessionId,
    required String clientId,
    required String levelLabel,
    required int levelOrder,
    String? accuracy,
    String? cueRaw,
  }) {
    final parsed = CueLevel.fromString(cueRaw); // null | CueLevel (tolerant)
    final wire = parsed?.toJson();
    final keptRaw =
        parsed == CueLevel.unknown ? cueRaw : null; // raw only on fallback
    return CasSessionProgress(
      id: '',
      stgId: stgId,
      sessionId: sessionId,
      clientId: clientId,
      levelLabel: levelLabel,
      levelOrder: levelOrder,
      accuracy: accuracy,
      cueLevelUsed: wire,
      cueLevelUsedRaw: keptRaw,
      createdAt: DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  // Full round-trip JSON (includes id + created_at).
  Map<String, dynamic> toJson() => {
        'id': id,
        'stg_id': stgId,
        'session_id': sessionId,
        'client_id': clientId,
        'level_label': levelLabel,
        'level_order': levelOrder,
        if (accuracy != null) 'accuracy': accuracy,
        if (cueLevelUsed != null) 'cue_level_used': cueLevelUsed,
        if (cueLevelUsedRaw != null) 'cue_level_used_raw': cueLevelUsedRaw,
        'created_at': createdAt.toIso8601String(),
      };

  // Insert/upsert payload — omits id + created_at (both server-defaulted).
  Map<String, dynamic> toInsertJson() => {
        'stg_id': stgId,
        'session_id': sessionId,
        'client_id': clientId,
        'level_label': levelLabel,
        'level_order': levelOrder,
        if (accuracy != null) 'accuracy': accuracy,
        if (cueLevelUsed != null) 'cue_level_used': cueLevelUsed,
        if (cueLevelUsedRaw != null) 'cue_level_used_raw': cueLevelUsedRaw,
      };

  CasSessionProgress copyWith({
    String? id,
    String? stgId,
    int? sessionId,
    String? clientId,
    String? levelLabel,
    int? levelOrder,
    String? accuracy,
    String? cueLevelUsed,
    String? cueLevelUsedRaw,
    DateTime? createdAt,
  }) =>
      CasSessionProgress(
        id: id ?? this.id,
        stgId: stgId ?? this.stgId,
        sessionId: sessionId ?? this.sessionId,
        clientId: clientId ?? this.clientId,
        levelLabel: levelLabel ?? this.levelLabel,
        levelOrder: levelOrder ?? this.levelOrder,
        accuracy: accuracy ?? this.accuracy,
        cueLevelUsed: cueLevelUsed ?? this.cueLevelUsed,
        cueLevelUsedRaw: cueLevelUsedRaw ?? this.cueLevelUsedRaw,
        createdAt: createdAt ?? this.createdAt,
      );
}
