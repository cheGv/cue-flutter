import 'package:flutter/foundation.dart';

// ---------------------------------------------------------------------------
// §6.3 — Cue hierarchy (least → most support)
// ---------------------------------------------------------------------------
enum CueLevel {
  independent,
  minimal,
  moderate,
  maximal,
  handOverHand;

  String toJson() => switch (this) {
        CueLevel.handOverHand => 'hand_over_hand',
        _ => name,
      };

  static CueLevel? fromString(String? s) {
    if (s == null) return null;
    return switch (s) {
      'hand_over_hand' => CueLevel.handOverHand,
      _ => CueLevel.values.firstWhere(
            (e) => e.name == s,
            orElse: () => throw ArgumentError('Unknown CueLevel: $s'),
          ),
    };
  }
}

// ---------------------------------------------------------------------------
// §6.4 — Clinical domain
// ---------------------------------------------------------------------------
enum StgDomain {
  articulation,
  phonology,
  expressiveLanguage,
  receptiveLanguage,
  pragmatics,
  fluency,
  voice,
  motorSpeech,
  feedingSwallowing,
  aacOperational,
  aacLinguistic,
  aacSocial,
  literacy,
  cognitiveCommunication;

  String toJson() => switch (this) {
        StgDomain.expressiveLanguage => 'expressive_language',
        StgDomain.receptiveLanguage => 'receptive_language',
        StgDomain.motorSpeech => 'motor_speech',
        StgDomain.feedingSwallowing => 'feeding_swallowing',
        StgDomain.aacOperational => 'AAC_operational',
        StgDomain.aacLinguistic => 'AAC_linguistic',
        StgDomain.aacSocial => 'AAC_social',
        StgDomain.cognitiveCommunication => 'cognitive_communication',
        _ => name,
      };

  static StgDomain? fromString(String? s) {
    if (s == null) return null;
    return switch (s) {
      'expressive_language' => StgDomain.expressiveLanguage,
      'receptive_language' => StgDomain.receptiveLanguage,
      'motor_speech' => StgDomain.motorSpeech,
      'feeding_swallowing' => StgDomain.feedingSwallowing,
      'AAC_operational' => StgDomain.aacOperational,
      'AAC_linguistic' => StgDomain.aacLinguistic,
      'AAC_social' => StgDomain.aacSocial,
      'cognitive_communication' => StgDomain.cognitiveCommunication,
      _ => StgDomain.values.firstWhere(
            (e) => e.name == s,
            orElse: () => throw ArgumentError('Unknown StgDomain: $s'),
          ),
    };
  }
}

// ---------------------------------------------------------------------------
// §6.5 — Clinical framework
// ---------------------------------------------------------------------------
enum StgFramework {
  prompt,
  opt,
  aac,
  nla,
  dir,
  hanen,
  pecs,
  coreWord,
  motorSpeech,
  phonologicalProcess,
  interoceptionInformed,
  polyvagalInformed,
  other;

  String toJson() => switch (this) {
        StgFramework.prompt => 'PROMPT',
        StgFramework.opt => 'OPT',
        StgFramework.aac => 'AAC',
        StgFramework.nla => 'NLA',
        StgFramework.dir => 'DIR',
        StgFramework.hanen => 'Hanen',
        StgFramework.pecs => 'PECS',
        StgFramework.coreWord => 'Core_Word',
        StgFramework.motorSpeech => 'Motor_Speech',
        StgFramework.phonologicalProcess => 'Phonological_Process',
        StgFramework.interoceptionInformed => 'Interoception_Informed',
        StgFramework.polyvagalInformed => 'Polyvagal_Informed',
        StgFramework.other => 'Other',
      };

  static StgFramework? fromString(String? s) {
    if (s == null) return null;
    return switch (s) {
      'PROMPT' => StgFramework.prompt,
      'OPT' => StgFramework.opt,
      'AAC' => StgFramework.aac,
      'NLA' => StgFramework.nla,
      'DIR' => StgFramework.dir,
      'Hanen' => StgFramework.hanen,
      'PECS' => StgFramework.pecs,
      'Core_Word' => StgFramework.coreWord,
      'Motor_Speech' => StgFramework.motorSpeech,
      'Phonological_Process' => StgFramework.phonologicalProcess,
      'Interoception_Informed' => StgFramework.interoceptionInformed,
      'Polyvagal_Informed' => StgFramework.polyvagalInformed,
      'Other' => StgFramework.other,
      _ => throw ArgumentError('Unknown StgFramework: $s'),
    };
  }
}

// ---------------------------------------------------------------------------
// §6.6 — STG lifecycle status
// ---------------------------------------------------------------------------
enum StgStatus {
  active,
  mastered,
  onHold,
  discontinued,
  modified;

  String toJson() => switch (this) {
        StgStatus.onHold => 'on_hold',
        _ => name,
      };

  static StgStatus fromString(String s) => switch (s) {
        'on_hold' => StgStatus.onHold,
        'mastered' => StgStatus.mastered,
        'discontinued' => StgStatus.discontinued,
        'modified' => StgStatus.modified,
        _ => StgStatus.active,
      };
}

// ---------------------------------------------------------------------------
// Mastery criterion — canonical JSONB shape from §6.2
// ---------------------------------------------------------------------------
@immutable
class MasteryCriterion {
  final int accuracyPct;
  final int consecutiveSessions;
  final int trialsPerSession;

  const MasteryCriterion({
    required this.accuracyPct,
    required this.consecutiveSessions,
    required this.trialsPerSession,
  });

  factory MasteryCriterion.fromJson(Map<String, dynamic> json) =>
      MasteryCriterion(
        accuracyPct: (json['accuracy_pct'] as num).toInt(),
        consecutiveSessions: (json['consecutive_sessions'] as num).toInt(),
        trialsPerSession: (json['trials_per_session'] as num).toInt(),
      );

  Map<String, dynamic> toJson() => {
        'accuracy_pct': accuracyPct,
        'consecutive_sessions': consecutiveSessions,
        'trials_per_session': trialsPerSession,
      };
}

// ---------------------------------------------------------------------------
// ShortTermGoal — immutable model for the `short_term_goals` table.
// Column names match actual Supabase schema (see §7 drift note in CLAUDE.md).
//   long_term_goal_id  (not ltg_id)
//   client_id          (not patient_id)
//   user_id            (not created_by)
// ---------------------------------------------------------------------------
@immutable
class ShortTermGoal {
  final String id;
  final String longTermGoalId; // long_term_goal_id
  final String clientId;       // client_id
  final String userId;         // user_id

  // Pre-existing columns
  final String specific;
  final String measurable;
  final int? targetAccuracy;
  final int? timeBoundSessions;
  final int sessionsAttempted;
  final int? sequenceNum;
  final bool isAiGenerated;
  final String? originalText;

  // STG memory-layer columns added in migration 20260419_add_stg_memory_layer
  final String? targetBehavior;
  final String? context;
  final MasteryCriterion? masteryCriterion;
  final CueLevel? currentCueLevel;
  final CueLevel? initialCueLevel;
  final String? cueFadePlan;
  final StgStatus status;
  final double? currentAccuracy;
  final int sessionsAtCriterion;
  final int totalSessionsWorked;
  final StgFramework? framework;
  final StgDomain? domain;
  final bool parentVisible;
  final String? parentFriendlyLabel;
  final String? parentRoutineAnchor;
  final String? notes;

  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? masteredAt;

  const ShortTermGoal({
    required this.id,
    required this.longTermGoalId,
    required this.clientId,
    required this.userId,
    this.specific = '',
    this.measurable = '',
    this.targetAccuracy,
    this.timeBoundSessions,
    this.sessionsAttempted = 0,
    this.sequenceNum,
    this.isAiGenerated = false,
    this.originalText,
    this.targetBehavior,
    this.context,
    this.masteryCriterion,
    this.currentCueLevel,
    this.initialCueLevel,
    this.cueFadePlan,
    this.status = StgStatus.active,
    this.currentAccuracy,
    this.sessionsAtCriterion = 0,
    this.totalSessionsWorked = 0,
    this.framework,
    this.domain,
    this.parentVisible = false,
    this.parentFriendlyLabel,
    this.parentRoutineAnchor,
    this.notes,
    required this.createdAt,
    required this.updatedAt,
    this.masteredAt,
  });

  factory ShortTermGoal.fromJson(Map<String, dynamic> json) {
    return ShortTermGoal(
      id: json['id'] as String,
      longTermGoalId: json['long_term_goal_id'] as String,
      clientId: json['client_id'] as String,
      userId: json['user_id'] as String,
      specific: json['specific'] as String? ?? '',
      measurable: json['measurable'] as String? ?? '',
      targetAccuracy: json['target_accuracy'] as int?,
      timeBoundSessions: json['time_bound_sessions'] as int?,
      sessionsAttempted: json['sessions_attempted'] as int? ?? 0,
      sequenceNum: json['sequence_num'] as int?,
      isAiGenerated: json['is_ai_generated'] as bool? ?? false,
      originalText: json['original_text'] as String?,
      targetBehavior: json['target_behavior'] as String?,
      context: json['context'] as String?,
      masteryCriterion: json['mastery_criterion'] != null
          ? MasteryCriterion.fromJson(
              Map<String, dynamic>.from(json['mastery_criterion'] as Map))
          : null,
      currentCueLevel:
          CueLevel.fromString(json['current_cue_level'] as String?),
      initialCueLevel:
          CueLevel.fromString(json['initial_cue_level'] as String?),
      cueFadePlan: json['cue_fade_plan'] as String?,
      status: StgStatus.fromString(json['status'] as String? ?? 'active'),
      currentAccuracy: (json['current_accuracy'] as num?)?.toDouble(),
      sessionsAtCriterion: json['sessions_at_criterion'] as int? ?? 0,
      totalSessionsWorked: json['total_sessions_worked'] as int? ?? 0,
      framework: StgFramework.fromString(json['framework'] as String?),
      domain: StgDomain.fromString(json['domain'] as String?),
      parentVisible: json['parent_visible'] as bool? ?? false,
      parentFriendlyLabel: json['parent_friendly_label'] as String?,
      parentRoutineAnchor: json['parent_routine_anchor'] as String?,
      notes: json['notes'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
      masteredAt: json['mastered_at'] != null
          ? DateTime.parse(json['mastered_at'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'long_term_goal_id': longTermGoalId,
        'client_id': clientId,
        'user_id': userId,
        'specific': specific,
        'measurable': measurable,
        if (targetAccuracy != null) 'target_accuracy': targetAccuracy,
        if (timeBoundSessions != null) 'time_bound_sessions': timeBoundSessions,
        'sessions_attempted': sessionsAttempted,
        if (sequenceNum != null) 'sequence_num': sequenceNum,
        'is_ai_generated': isAiGenerated,
        if (originalText != null) 'original_text': originalText,
        if (targetBehavior != null) 'target_behavior': targetBehavior,
        if (context != null) 'context': context,
        if (masteryCriterion != null)
          'mastery_criterion': masteryCriterion!.toJson(),
        if (currentCueLevel != null)
          'current_cue_level': currentCueLevel!.toJson(),
        if (initialCueLevel != null)
          'initial_cue_level': initialCueLevel!.toJson(),
        if (cueFadePlan != null) 'cue_fade_plan': cueFadePlan,
        'status': status.toJson(),
        if (currentAccuracy != null) 'current_accuracy': currentAccuracy,
        'sessions_at_criterion': sessionsAtCriterion,
        'total_sessions_worked': totalSessionsWorked,
        if (framework != null) 'framework': framework!.toJson(),
        if (domain != null) 'domain': domain!.toJson(),
        'parent_visible': parentVisible,
        if (parentFriendlyLabel != null)
          'parent_friendly_label': parentFriendlyLabel,
        if (parentRoutineAnchor != null)
          'parent_routine_anchor': parentRoutineAnchor,
        if (notes != null) 'notes': notes,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
        if (masteredAt != null) 'mastered_at': masteredAt!.toIso8601String(),
      };

  ShortTermGoal copyWith({
    String? id,
    String? longTermGoalId,
    String? clientId,
    String? userId,
    String? specific,
    String? measurable,
    int? targetAccuracy,
    int? timeBoundSessions,
    int? sessionsAttempted,
    int? sequenceNum,
    bool? isAiGenerated,
    String? originalText,
    String? targetBehavior,
    String? context,
    MasteryCriterion? masteryCriterion,
    CueLevel? currentCueLevel,
    CueLevel? initialCueLevel,
    String? cueFadePlan,
    StgStatus? status,
    double? currentAccuracy,
    int? sessionsAtCriterion,
    int? totalSessionsWorked,
    StgFramework? framework,
    StgDomain? domain,
    bool? parentVisible,
    String? parentFriendlyLabel,
    String? parentRoutineAnchor,
    String? notes,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? masteredAt,
  }) =>
      ShortTermGoal(
        id: id ?? this.id,
        longTermGoalId: longTermGoalId ?? this.longTermGoalId,
        clientId: clientId ?? this.clientId,
        userId: userId ?? this.userId,
        specific: specific ?? this.specific,
        measurable: measurable ?? this.measurable,
        targetAccuracy: targetAccuracy ?? this.targetAccuracy,
        timeBoundSessions: timeBoundSessions ?? this.timeBoundSessions,
        sessionsAttempted: sessionsAttempted ?? this.sessionsAttempted,
        sequenceNum: sequenceNum ?? this.sequenceNum,
        isAiGenerated: isAiGenerated ?? this.isAiGenerated,
        originalText: originalText ?? this.originalText,
        targetBehavior: targetBehavior ?? this.targetBehavior,
        context: context ?? this.context,
        masteryCriterion: masteryCriterion ?? this.masteryCriterion,
        currentCueLevel: currentCueLevel ?? this.currentCueLevel,
        initialCueLevel: initialCueLevel ?? this.initialCueLevel,
        cueFadePlan: cueFadePlan ?? this.cueFadePlan,
        status: status ?? this.status,
        currentAccuracy: currentAccuracy ?? this.currentAccuracy,
        sessionsAtCriterion: sessionsAtCriterion ?? this.sessionsAtCriterion,
        totalSessionsWorked: totalSessionsWorked ?? this.totalSessionsWorked,
        framework: framework ?? this.framework,
        domain: domain ?? this.domain,
        parentVisible: parentVisible ?? this.parentVisible,
        parentFriendlyLabel: parentFriendlyLabel ?? this.parentFriendlyLabel,
        parentRoutineAnchor: parentRoutineAnchor ?? this.parentRoutineAnchor,
        notes: notes ?? this.notes,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        masteredAt: masteredAt ?? this.masteredAt,
      );
}
