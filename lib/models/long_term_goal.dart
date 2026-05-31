import 'package:flutter/foundation.dart';

// ---------------------------------------------------------------------------
// §6.6 (LTG) — Long-term goal lifecycle status.
//
// Clinical lifecycle, ORTHOGONAL to archival (deleted_at). The three states
// the lifecycle UI sets are first-class (not swallowed into active):
//   active        — being worked
//   achieved      — target met (stays visible, in the chart's Completed section)
//   discontinued  — closed without being met (Closed section)
// An unrecognised value degrades to [active] (tolerant — never throws), matching
// the StgStatus parsing posture.
// ---------------------------------------------------------------------------
enum LtgStatus {
  active,
  achieved,
  discontinued;

  String toJson() => name; // 'active' | 'achieved' | 'discontinued'

  static LtgStatus fromString(String? s) => switch (s) {
        'active' => LtgStatus.active,
        'achieved' => LtgStatus.achieved,
        'discontinued' => LtgStatus.discontinued,
        _ => LtgStatus.active,
      };

  bool get isCompleted => this == LtgStatus.achieved;
  bool get isClosed => this == LtgStatus.discontinued;
  bool get isActiveLifecycle => this == LtgStatus.active;

  String displayLabel() => switch (this) {
        LtgStatus.active => 'Active',
        LtgStatus.achieved => 'Achieved',
        LtgStatus.discontinued => 'Discontinued',
      };
}

// ---------------------------------------------------------------------------
// LongTermGoal — immutable model for the `long_term_goals` table.
//
// Column names match the live Supabase schema (verified sandbox
// uuqhusmgoiaxdvtgbmwh, 2026-05-29): id, client_id, user_id, domain, goal_text,
// original_text, status, sequence_num, time_frame_weeks, target_date, category,
// framework, notes, achieved_at, created_at, updated_at, deleted_at.
//
// This models the clinically- and UI-relevant subset (the chart's LTG anchor +
// the lifecycle controls). The lifecycle repository writes TARGETED column maps
// (only the columns a given action changes) — it never round-trips a full
// `toJson()` back as an upsert — so the unmodeled columns (plan_id,
// evidence_rationale, rationale, is_ai_generated, priority_chips_json) are never
// at risk of being clobbered. `toJson` is for serialization/caching/tests.
// ---------------------------------------------------------------------------
@immutable
class LongTermGoal {
  final String id;
  final String clientId;
  final String userId;
  final String domain;
  final String goalText;
  final String? originalText;
  final LtgStatus status;
  final int? sequenceNum;
  final int? timeFrameWeeks;
  final DateTime? targetDate;
  final String? category;
  final String? framework;
  final String? notes;
  final DateTime? achievedAt;
  final DateTime createdAt;
  final DateTime? updatedAt;

  // Soft-archive timestamp (migration 20260529120000). Non-null ⇒ archived
  // (hidden from the chart, reversibly). ORTHOGONAL to [status].
  final DateTime? deletedAt;

  const LongTermGoal({
    required this.id,
    required this.clientId,
    required this.userId,
    this.domain = '',
    this.goalText = '',
    this.originalText,
    this.status = LtgStatus.active,
    this.sequenceNum,
    this.timeFrameWeeks,
    this.targetDate,
    this.category,
    this.framework,
    this.notes,
    this.achievedAt,
    required this.createdAt,
    this.updatedAt,
    this.deletedAt,
  });

  /// Archived (soft-deleted) — hidden from the chart, restorable.
  bool get isArchived => deletedAt != null;

  /// Active working set: clinically active AND not archived. Single definition
  /// the chart's active-filter uses for LTGs.
  bool get isActive => status == LtgStatus.active && deletedAt == null;

  /// Display text for the goal body — prefers the canonical `goal_text`, falls
  /// back to the raw `original_text` if goal_text is somehow blank.
  String get displayText {
    final g = goalText.trim();
    if (g.isNotEmpty) return g;
    return originalText?.trim() ?? '';
  }

  factory LongTermGoal.fromJson(Map<String, dynamic> json) => LongTermGoal(
        id: json['id'] as String,
        clientId: json['client_id'] as String,
        userId: json['user_id'] as String,
        domain: json['domain'] as String? ?? '',
        goalText: json['goal_text'] as String? ?? '',
        originalText: json['original_text'] as String?,
        status: LtgStatus.fromString(json['status'] as String?),
        sequenceNum: (json['sequence_num'] as num?)?.toInt(),
        timeFrameWeeks: (json['time_frame_weeks'] as num?)?.toInt(),
        targetDate: _parseDate(json['target_date']),
        category: json['category'] as String?,
        framework: json['framework'] as String?,
        notes: json['notes'] as String?,
        achievedAt: _parseDate(json['achieved_at']),
        createdAt: _parseDate(json['created_at']) ??
            DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
        updatedAt: _parseDate(json['updated_at']),
        deletedAt: _parseDate(json['deleted_at']),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'client_id': clientId,
        'user_id': userId,
        'domain': domain,
        'goal_text': goalText,
        if (originalText != null) 'original_text': originalText,
        'status': status.toJson(),
        if (sequenceNum != null) 'sequence_num': sequenceNum,
        if (timeFrameWeeks != null) 'time_frame_weeks': timeFrameWeeks,
        if (targetDate != null)
          'target_date': targetDate!.toIso8601String(),
        if (category != null) 'category': category,
        if (framework != null) 'framework': framework,
        if (notes != null) 'notes': notes,
        if (achievedAt != null) 'achieved_at': achievedAt!.toIso8601String(),
        'created_at': createdAt.toIso8601String(),
        if (updatedAt != null) 'updated_at': updatedAt!.toIso8601String(),
        if (deletedAt != null) 'deleted_at': deletedAt!.toIso8601String(),
      };

  static DateTime? _parseDate(dynamic v) =>
      v is String ? DateTime.tryParse(v) : null;
}
