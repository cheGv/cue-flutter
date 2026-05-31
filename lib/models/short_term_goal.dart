import 'package:flutter/foundation.dart';

// ---------------------------------------------------------------------------
// §6.3 — Cue hierarchy (least → most support)
//
// Open vocabulary — older rows, free-text imports, and cross-framework dialects
// (e.g. PROMPT levels, ABA prompt hierarchies) all land here. The parser MUST
// degrade to `unknown` rather than throw; the raw value is preserved on the
// owning model field (ShortTermGoal.currentCueLevelRaw / initialCueLevelRaw,
// StgEvidence.cueLevelUsed) so the UI can still surface it.
// ---------------------------------------------------------------------------
enum CueLevel {
  independent,
  minimal,
  moderate,
  maximal,
  handOverHand,
  unknown;

  String toJson() => switch (this) {
        CueLevel.handOverHand => 'hand_over_hand',
        CueLevel.unknown => 'unknown',
        _ => name,
      };

  /// Display label — `unknown` falls back to em-dash; pair with the raw value
  /// at the call site (`raw ?? cueLevel.displayLabel()`) when you have it.
  String displayLabel() => switch (this) {
        CueLevel.independent => 'Independent',
        CueLevel.minimal => 'Minimal',
        CueLevel.moderate => 'Moderate',
        CueLevel.maximal => 'Maximal',
        CueLevel.handOverHand => 'Hand-over-hand',
        CueLevel.unknown => '—',
      };

  /// Tolerant parse — null input returns null, unrecognized input returns
  /// [CueLevel.unknown]. Never throws. Callers that need the original string
  /// should capture it alongside (see model `*Raw` fields).
  static CueLevel? fromString(String? s) {
    if (s == null) return null;
    return switch (s) {
      'hand_over_hand' => CueLevel.handOverHand,
      'independent' => CueLevel.independent,
      'minimal' => CueLevel.minimal,
      'moderate' => CueLevel.moderate,
      'maximal' => CueLevel.maximal,
      _ => CueLevel.unknown,
    };
  }
}

// ---------------------------------------------------------------------------
// §6.4 — Clinical domain
//
// Open vocabulary — the DB has accumulated multiple dialects of the same idea
// (e.g. "VOI" vs "voice" for the voice domain). The parser accepts known
// aliases and degrades to `unknown` for anything else; the raw string is
// preserved on [ShortTermGoal.domainRaw] for display.
//
// NOTE: this layer is parser-tolerant only. Normalizing the actual stored
// values across the DB is a separate data-hygiene task.
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
  cognitiveCommunication,
  unknown;

  String toJson() => switch (this) {
        StgDomain.expressiveLanguage => 'expressive_language',
        StgDomain.receptiveLanguage => 'receptive_language',
        StgDomain.motorSpeech => 'motor_speech',
        StgDomain.feedingSwallowing => 'feeding_swallowing',
        StgDomain.aacOperational => 'AAC_operational',
        StgDomain.aacLinguistic => 'AAC_linguistic',
        StgDomain.aacSocial => 'AAC_social',
        StgDomain.cognitiveCommunication => 'cognitive_communication',
        StgDomain.unknown => 'unknown',
        _ => name,
      };

  /// Display label — `unknown` falls back to em-dash; pair with the raw value
  /// at the call site when you have it.
  String displayLabel() => switch (this) {
        StgDomain.articulation => 'Articulation',
        StgDomain.phonology => 'Phonology',
        StgDomain.expressiveLanguage => 'Expressive language',
        StgDomain.receptiveLanguage => 'Receptive language',
        StgDomain.pragmatics => 'Pragmatics',
        StgDomain.fluency => 'Fluency',
        StgDomain.voice => 'Voice',
        StgDomain.motorSpeech => 'Motor speech',
        StgDomain.feedingSwallowing => 'Feeding & swallowing',
        StgDomain.aacOperational => 'AAC — operational',
        StgDomain.aacLinguistic => 'AAC — linguistic',
        StgDomain.aacSocial => 'AAC — social',
        StgDomain.literacy => 'Literacy',
        StgDomain.cognitiveCommunication => 'Cognitive communication',
        StgDomain.unknown => '—',
      };

  /// Tolerant parse — null input returns null, unrecognized input returns
  /// [StgDomain.unknown]. Never throws. Known dialect aliases (e.g. "VOI" for
  /// voice, "MS" for motor_speech) are folded into their canonical case here.
  static StgDomain? fromString(String? s) {
    if (s == null) return null;
    return switch (s) {
      // Canonical DB strings
      'expressive_language' => StgDomain.expressiveLanguage,
      'receptive_language' => StgDomain.receptiveLanguage,
      'motor_speech' => StgDomain.motorSpeech,
      'feeding_swallowing' => StgDomain.feedingSwallowing,
      'AAC_operational' => StgDomain.aacOperational,
      'AAC_linguistic' => StgDomain.aacLinguistic,
      'AAC_social' => StgDomain.aacSocial,
      'cognitive_communication' => StgDomain.cognitiveCommunication,
      'articulation' => StgDomain.articulation,
      'phonology' => StgDomain.phonology,
      'pragmatics' => StgDomain.pragmatics,
      'fluency' => StgDomain.fluency,
      'voice' => StgDomain.voice,
      'literacy' => StgDomain.literacy,
      // Common dialect aliases observed in live data — fold to canonical.
      'VOI' || 'voi' || 'Voice' => StgDomain.voice,
      'ART' || 'art' => StgDomain.articulation,
      'PHO' || 'pho' => StgDomain.phonology,
      'FLU' || 'flu' || 'Fluency' => StgDomain.fluency,
      'LAN' || 'lan' || 'language' => StgDomain.expressiveLanguage,
      _ => StgDomain.unknown,
    };
  }
}

// ---------------------------------------------------------------------------
// §6.5 — Clinical framework
//
// Open vocabulary. SLPs draw from a long tail of named frameworks/techniques
// (voice-domain examples: RVT, VFE, LSVT-LOUD, SOVT). The parser MUST tolerate
// any string — known frameworks land on their case, anything else returns
// `unknown` and the raw value is preserved on [ShortTermGoal.frameworkRaw].
//
// `other` is the explicit "Other" choice in authoring UI; `unknown` is the
// parser fallback for unrecognized inputs. Keep them distinct.
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
  // Voice-domain technique frameworks.
  rvt,
  vfe,
  lsvtLoud,
  sovt,
  other,
  unknown;

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
        StgFramework.rvt => 'RVT',
        StgFramework.vfe => 'VFE',
        StgFramework.lsvtLoud => 'LSVT-LOUD',
        StgFramework.sovt => 'SOVT',
        StgFramework.other => 'Other',
        StgFramework.unknown => 'unknown',
      };

  /// Display label — `unknown` falls back to em-dash; pair with the raw value
  /// at the call site when you have it.
  String displayLabel() => switch (this) {
        StgFramework.prompt => 'PROMPT',
        StgFramework.opt => 'OPT',
        StgFramework.aac => 'AAC',
        StgFramework.nla => 'Natural Language Acquisition',
        StgFramework.dir => 'DIR / Floortime',
        StgFramework.hanen => 'Hanen',
        StgFramework.pecs => 'PECS',
        StgFramework.coreWord => 'Core Word',
        StgFramework.motorSpeech => 'Motor Speech',
        StgFramework.phonologicalProcess => 'Phonological Process',
        StgFramework.interoceptionInformed => 'Interoception-informed',
        StgFramework.polyvagalInformed => 'Polyvagal-informed',
        StgFramework.rvt => 'Resonant Voice Therapy',
        StgFramework.vfe => 'Vocal Function Exercises',
        StgFramework.lsvtLoud => 'LSVT LOUD',
        StgFramework.sovt => 'SOVT',
        StgFramework.other => 'Other',
        StgFramework.unknown => '—',
      };

  /// Tolerant parse — null input returns null, unrecognized input returns
  /// [StgFramework.unknown]. Never throws.
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
      'RVT' => StgFramework.rvt,
      'VFE' => StgFramework.vfe,
      'LSVT-LOUD' || 'LSVT_LOUD' || 'LSVT LOUD' => StgFramework.lsvtLoud,
      'SOVT' => StgFramework.sovt,
      'Other' => StgFramework.other,
      _ => StgFramework.unknown,
    };
  }
}

// ---------------------------------------------------------------------------
// §6.6 — STG lifecycle status
//
// Clinical lifecycle, ORTHOGONAL to archival (deleted_at). 'active',
// 'achieved', and 'discontinued' are the three first-class states the
// lifecycle UI sets; 'mastered' is the legacy synonym for achieved (kept so
// pre-existing rows keep their meaning and surface in the Completed section),
// and 'on_hold' / 'modified' are legacy states that remain in the active list.
//
// An achieved/discontinued goal STAYS visible on the chart (in the Completed /
// Closed section); only archival (deleted_at) hides it.
// ---------------------------------------------------------------------------
enum StgStatus {
  active,
  achieved,
  mastered,
  onHold,
  discontinued,
  modified;

  String toJson() => switch (this) {
        StgStatus.onHold => 'on_hold',
        _ => name, // 'active' | 'achieved' | 'mastered' | 'discontinued' | 'modified'
      };

  /// Tolerant parse — recognised values map to their case; anything else
  /// degrades to [StgStatus.active] (never throws). 'achieved' and
  /// 'discontinued' are first-class (not swallowed into active).
  static StgStatus fromString(String s) => switch (s) {
        'active' => StgStatus.active,
        'achieved' => StgStatus.achieved,
        'mastered' => StgStatus.mastered,
        'on_hold' => StgStatus.onHold,
        'discontinued' => StgStatus.discontinued,
        'modified' => StgStatus.modified,
        _ => StgStatus.active,
      };

  /// Goal reached its target — surfaces in the chart's "Completed" section.
  /// Treats the legacy 'mastered' as equivalent to 'achieved'.
  bool get isCompleted =>
      this == StgStatus.achieved || this == StgStatus.mastered;

  /// Goal closed without being met — surfaces in the chart's "Closed" section.
  bool get isClosed => this == StgStatus.discontinued;

  /// In the active working set (eligible to be "in focus"). On-hold/modified
  /// are legacy non-closed states and remain active-eligible.
  bool get isActiveLifecycle => !isCompleted && !isClosed;

  String displayLabel() => switch (this) {
        StgStatus.active => 'Active',
        StgStatus.achieved => 'Achieved',
        StgStatus.mastered => 'Achieved',
        StgStatus.onHold => 'On hold',
        StgStatus.discontinued => 'Discontinued',
        StgStatus.modified => 'Modified',
      };
}

// ---------------------------------------------------------------------------
// Mastery criterion — JSONB blob attached to an STG.
//
// Two shapes, both legitimate clinical data:
//
//   (a) Quantified — trial-based domains (articulation, phonology, etc.):
//       { "accuracy_pct": 80, "consecutive_sessions": 3,
//         "trials_per_session": 10 }
//
//   (b) Qualitative hint — non-trial domains (voice, fluency, motor speech)
//       where mastery is described in prose:
//       { "hint": "80% phonation continuity across 3 consecutive sessions" }
//
// All sub-fields are nullable; a blob may carry quantified-only, hint-only, or
// (rare) both. The display layer should call [displayLine] which resolves the
// right thing to render — never compose a partial quantified string by hand.
// ---------------------------------------------------------------------------
@immutable
class MasteryCriterion {
  final int? accuracyPct;
  final int? consecutiveSessions;
  final int? trialsPerSession;

  /// Free-text criterion used by qualitative/voice goals when the SLP didn't
  /// (or couldn't) reduce the rule to a trial-based number. Preserved
  /// verbatim through round-trip so the prose isn't lost.
  final String? hint;

  const MasteryCriterion({
    this.accuracyPct,
    this.consecutiveSessions,
    this.trialsPerSession,
    this.hint,
  });

  factory MasteryCriterion.fromJson(Map<String, dynamic> json) =>
      MasteryCriterion(
        accuracyPct: (json['accuracy_pct'] as num?)?.toInt(),
        consecutiveSessions: (json['consecutive_sessions'] as num?)?.toInt(),
        trialsPerSession: (json['trials_per_session'] as num?)?.toInt(),
        hint: (json['hint'] as String?)?.trim().isEmpty == true
            ? null
            : json['hint'] as String?,
      );

  Map<String, dynamic> toJson() => {
        if (accuracyPct != null) 'accuracy_pct': accuracyPct,
        if (consecutiveSessions != null)
          'consecutive_sessions': consecutiveSessions,
        if (trialsPerSession != null) 'trials_per_session': trialsPerSession,
        if (hint != null) 'hint': hint,
      };

  /// True when both `accuracy_pct` and `consecutive_sessions` are present —
  /// enough to compose a coherent quantified line. A blob with only one of
  /// the two is treated as "no quantified rule" so we don't render
  /// "null% for 3 sessions" or "80% for null sessions".
  bool get hasQuantifiedRule =>
      accuracyPct != null && consecutiveSessions != null;

  /// Canonical one-line text for display on the STG card. Resolves in order:
  ///   1) Quantified shape → "80% across 3 consecutive sessions" (+ trial
  ///      detail when `trialsPerSession` is also present).
  ///   2) Hint-only shape → the hint string verbatim.
  ///   3) Neither populated → null (caller should render nothing).
  ///
  /// Hint is intentionally NOT appended when quantified is also present:
  /// the quantified line IS the rule, and tacking on prose would muddle the
  /// register. If a blob carries both, the hint is preserved on round-trip
  /// but not surfaced through this getter.
  String? get displayLine {
    if (hasQuantifiedRule) {
      final base =
          '$accuracyPct% across $consecutiveSessions consecutive sessions';
      if (trialsPerSession != null) {
        return '$base of $trialsPerSession trials each';
      }
      return base;
    }
    final h = hint?.trim();
    if (h != null && h.isNotEmpty) return h;
    return null;
  }
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
  // Raw-string preservation for parser fallbacks. When the enum lands on
  // `.unknown` (open-vocabulary value the parser doesn't recognize), the
  // original DB string is held here so the UI can still surface it. When the
  // enum is a known case (or null), these stay null. The convenience getters
  // [frameworkDisplay] / [domainDisplay] / [currentCueLevelDisplay] /
  // [initialCueLevelDisplay] resolve the right thing to show.
  final String? frameworkRaw;
  final String? domainRaw;
  final String? currentCueLevelRaw;
  final String? initialCueLevelRaw;
  final bool parentVisible;
  final String? parentFriendlyLabel;
  final String? parentRoutineAnchor;
  final String? notes;

  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? masteredAt;

  // Soft-archive timestamp (migration 20260529120000). Non-null ⇒ archived
  // (hidden from the chart, reversibly). ORTHOGONAL to [status]: an
  // achieved/discontinued goal is still visible; only deletedAt hides it.
  final DateTime? deletedAt;

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
    this.frameworkRaw,
    this.domainRaw,
    this.currentCueLevelRaw,
    this.initialCueLevelRaw,
    this.parentVisible = false,
    this.parentFriendlyLabel,
    this.parentRoutineAnchor,
    this.notes,
    required this.createdAt,
    required this.updatedAt,
    this.masteredAt,
    this.deletedAt,
  });

  /// Archived (soft-deleted) — hidden from the chart, restorable.
  bool get isArchived => deletedAt != null;

  /// The active working set: clinically active AND not archived. This is the
  /// single definition the chart's active-list filter uses.
  bool get isActive => status == StgStatus.active && deletedAt == null;

  /// What to render for the framework on a chip or label. Resolves in order:
  /// (1) raw string when the enum is `.unknown` (so "RVT" still appears even if
  /// it's not a first-class case), (2) the enum's display label for known
  /// cases, (3) null when the field is unset.
  String? get frameworkDisplay {
    final f = framework;
    if (f == null) return null;
    if (f == StgFramework.unknown) return frameworkRaw;
    return f.displayLabel();
  }

  /// Same resolution rule for domain. Used by chart_stg_compact +
  /// chart_trajectory_strip so a "VOI" (canonicalised to voice) shows as
  /// "Voice", and an unrecognised value still surfaces its raw token.
  String? get domainDisplay {
    final d = domain;
    if (d == null) return null;
    if (d == StgDomain.unknown) return domainRaw;
    // Keep the DB-style identifier here (e.g. 'voice', 'motor_speech') because
    // the chart pill currently uppercases the toJson() form. Switch to
    // displayLabel() when the pill rendering is restyled.
    return d.toJson();
  }

  String? get currentCueLevelDisplay {
    final c = currentCueLevel;
    if (c == null) return null;
    if (c == CueLevel.unknown) return currentCueLevelRaw;
    return c.displayLabel();
  }

  String? get initialCueLevelDisplay {
    final c = initialCueLevel;
    if (c == null) return null;
    if (c == CueLevel.unknown) return initialCueLevelRaw;
    return c.displayLabel();
  }

  factory ShortTermGoal.fromJson(Map<String, dynamic> json) {
    // Parse open-vocabulary enums tolerantly and capture the raw string
    // whenever the parser falls back to `.unknown`. The parallel *Raw fields
    // are how the UI surfaces values the enum doesn't recognise (e.g. RVT,
    // VFE, LSVT-LOUD before they were added — or any future framework).
    final frameworkRawIn = json['framework'] as String?;
    final framework = StgFramework.fromString(frameworkRawIn);
    final domainRawIn = json['domain'] as String?;
    final domain = StgDomain.fromString(domainRawIn);
    final currentCueRawIn = json['current_cue_level'] as String?;
    final currentCueLevel = CueLevel.fromString(currentCueRawIn);
    final initialCueRawIn = json['initial_cue_level'] as String?;
    final initialCueLevel = CueLevel.fromString(initialCueRawIn);

    return ShortTermGoal(
      id: json['id'] as String,
      longTermGoalId: json['long_term_goal_id'] as String,
      clientId: json['client_id'] as String,
      userId: json['user_id'] as String,
      specific: json['specific'] as String? ?? '',
      measurable: json['measurable'] as String? ?? '',
      targetAccuracy: (json['target_accuracy'] as num?)?.toInt(),
      timeBoundSessions: (json['time_bound_sessions'] as num?)?.toInt(),
      sessionsAttempted: (json['sessions_attempted'] as num?)?.toInt() ?? 0,
      sequenceNum: (json['sequence_num'] as num?)?.toInt(),
      isAiGenerated: json['is_ai_generated'] as bool? ?? false,
      originalText: json['original_text'] as String?,
      targetBehavior: json['target_behavior'] as String?,
      context: json['context'] as String?,
      masteryCriterion: json['mastery_criterion'] != null
          ? MasteryCriterion.fromJson(
              Map<String, dynamic>.from(json['mastery_criterion'] as Map))
          : null,
      currentCueLevel: currentCueLevel,
      currentCueLevelRaw:
          currentCueLevel == CueLevel.unknown ? currentCueRawIn : null,
      initialCueLevel: initialCueLevel,
      initialCueLevelRaw:
          initialCueLevel == CueLevel.unknown ? initialCueRawIn : null,
      cueFadePlan: json['cue_fade_plan'] as String?,
      status: StgStatus.fromString(json['status'] as String? ?? 'active'),
      currentAccuracy: (json['current_accuracy'] as num?)?.toDouble(),
      sessionsAtCriterion:
          (json['sessions_at_criterion'] as num?)?.toInt() ?? 0,
      totalSessionsWorked:
          (json['total_sessions_worked'] as num?)?.toInt() ?? 0,
      framework: framework,
      frameworkRaw:
          framework == StgFramework.unknown ? frameworkRawIn : null,
      domain: domain,
      domainRaw: domain == StgDomain.unknown ? domainRawIn : null,
      parentVisible: json['parent_visible'] as bool? ?? false,
      parentFriendlyLabel: json['parent_friendly_label'] as String?,
      parentRoutineAnchor: json['parent_routine_anchor'] as String?,
      notes: json['notes'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
      masteredAt: json['mastered_at'] != null
          ? DateTime.parse(json['mastered_at'] as String)
          : null,
      deletedAt: json['deleted_at'] != null
          ? DateTime.parse(json['deleted_at'] as String)
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
          'current_cue_level': currentCueLevel == CueLevel.unknown
              ? (currentCueLevelRaw ?? currentCueLevel!.toJson())
              : currentCueLevel!.toJson(),
        if (initialCueLevel != null)
          'initial_cue_level': initialCueLevel == CueLevel.unknown
              ? (initialCueLevelRaw ?? initialCueLevel!.toJson())
              : initialCueLevel!.toJson(),
        if (cueFadePlan != null) 'cue_fade_plan': cueFadePlan,
        'status': status.toJson(),
        if (currentAccuracy != null) 'current_accuracy': currentAccuracy,
        'sessions_at_criterion': sessionsAtCriterion,
        'total_sessions_worked': totalSessionsWorked,
        // Round-trip the raw string when the enum landed on `.unknown` so we
        // don't clobber an unrecognised but valid clinical value on writeback.
        if (framework != null)
          'framework': framework == StgFramework.unknown
              ? (frameworkRaw ?? framework!.toJson())
              : framework!.toJson(),
        if (domain != null)
          'domain': domain == StgDomain.unknown
              ? (domainRaw ?? domain!.toJson())
              : domain!.toJson(),
        'parent_visible': parentVisible,
        if (parentFriendlyLabel != null)
          'parent_friendly_label': parentFriendlyLabel,
        if (parentRoutineAnchor != null)
          'parent_routine_anchor': parentRoutineAnchor,
        if (notes != null) 'notes': notes,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
        if (masteredAt != null) 'mastered_at': masteredAt!.toIso8601String(),
        if (deletedAt != null) 'deleted_at': deletedAt!.toIso8601String(),
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
    String? frameworkRaw,
    String? domainRaw,
    String? currentCueLevelRaw,
    String? initialCueLevelRaw,
    bool? parentVisible,
    String? parentFriendlyLabel,
    String? parentRoutineAnchor,
    String? notes,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? masteredAt,
    DateTime? deletedAt,
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
        frameworkRaw: frameworkRaw ?? this.frameworkRaw,
        domainRaw: domainRaw ?? this.domainRaw,
        currentCueLevelRaw: currentCueLevelRaw ?? this.currentCueLevelRaw,
        initialCueLevelRaw: initialCueLevelRaw ?? this.initialCueLevelRaw,
        parentVisible: parentVisible ?? this.parentVisible,
        parentFriendlyLabel: parentFriendlyLabel ?? this.parentFriendlyLabel,
        parentRoutineAnchor: parentRoutineAnchor ?? this.parentRoutineAnchor,
        notes: notes ?? this.notes,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        masteredAt: masteredAt ?? this.masteredAt,
        deletedAt: deletedAt ?? this.deletedAt,
      );
}
