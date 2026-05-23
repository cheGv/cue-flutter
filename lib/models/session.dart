import 'package:flutter/foundation.dart';

import 'session_outcome.dart';

// Session — immutable model for the `sessions` table.
//
// Created fresh in Phase B. Before this, session rows were read inline via raw
// `.from('sessions')` calls (~15 call sites) with ad-hoc Map access and no
// model. Those sites are intentionally NOT refactored here — see the Phase B
// report's "session call-site cleanup" note.
//
// Column names match the actual Supabase schema. Notable points:
//   id                 bigint   -> int (identity, NOT a uuid)
//   client_id          uuid     -> String
//   date               date     -> the session date (NOT `session_date`)
//   next_session_focus text     -> reused as the plan-forward seed; there is no
//                                  separate `next_session_intent` column
//   outcome            session_outcome (added in Phase B; nullable)
@immutable
class Session {
  // Identity / ownership
  final int id;
  final String clientId;
  final String clientName;
  final String? userId;
  final String status;

  // Scheduling
  final DateTime? date;
  final int? durationMinutes;

  // Phase B additions
  final SessionOutcome? outcome;
  final String? nextSessionFocus;

  // Barriers (NOT NULL booleans in schema)
  final bool barrierMotor;
  final bool barrierLinguistic;
  final bool barrierCognitive;
  final bool barrierSensory;
  final bool barrierEnvironmental;
  final bool barrierMotivational;
  final bool barrierDeviceAccess;

  // Structured clinical content
  final String? targetBehaviour; // British spelling matches the column
  final String? condition;
  final String? criterion;
  final String? activityName;
  final String? activityRationale;
  final String? promptApproach;
  final int? promptLevelUsed;
  final int? attempts;
  final int? independentResponses;
  final int? promptedResponses;
  final String? clientAffect;
  final String? goalMet;
  final String? homeProgramme;
  final String? soapNote;
  final String? parentSummary;
  final String? transcript;
  final String? notes;

  // Goal links
  final String? goalId;
  final String? shortTermGoalId;

  // AI / attestation
  final bool? aiGenerated;
  final bool? clinicianAttested;
  final DateTime? attestedAt;
  final String? attestedBy;
  final String? parentUpdate;
  final DateTime? parentUpdateGeneratedAt;
  final String? aiHeadline; // AI one-line session summary (Phase B, cached)

  // Population payload (jsonb)
  final Map<String, dynamic>? populationPayload;

  // Soft delete
  final DateTime? deletedAt;
  final String? deletedBy;
  final String? deleteReason;

  // Timestamps
  final DateTime createdAt;
  final DateTime? updatedAt;

  const Session({
    required this.id,
    required this.clientId,
    this.clientName = '',
    this.userId,
    this.status = '',
    this.date,
    this.durationMinutes,
    this.outcome,
    this.nextSessionFocus,
    this.barrierMotor = false,
    this.barrierLinguistic = false,
    this.barrierCognitive = false,
    this.barrierSensory = false,
    this.barrierEnvironmental = false,
    this.barrierMotivational = false,
    this.barrierDeviceAccess = false,
    this.targetBehaviour,
    this.condition,
    this.criterion,
    this.activityName,
    this.activityRationale,
    this.promptApproach,
    this.promptLevelUsed,
    this.attempts,
    this.independentResponses,
    this.promptedResponses,
    this.clientAffect,
    this.goalMet,
    this.homeProgramme,
    this.soapNote,
    this.parentSummary,
    this.transcript,
    this.notes,
    this.goalId,
    this.shortTermGoalId,
    this.aiGenerated,
    this.clinicianAttested,
    this.attestedAt,
    this.attestedBy,
    this.parentUpdate,
    this.parentUpdateGeneratedAt,
    this.aiHeadline,
    this.populationPayload,
    this.deletedAt,
    this.deletedBy,
    this.deleteReason,
    required this.createdAt,
    this.updatedAt,
  });

  factory Session.fromJson(Map<String, dynamic> json) => Session(
        id: (json['id'] as num).toInt(),
        clientId: json['client_id'] as String,
        clientName: json['client_name'] as String? ?? '',
        userId: json['user_id'] as String?,
        status: json['status'] as String? ?? '',
        date: _parseDateTime(json['date']),
        durationMinutes: (json['duration_minutes'] as num?)?.toInt(),
        outcome: SessionOutcome.fromString(json['outcome'] as String?),
        nextSessionFocus: json['next_session_focus'] as String?,
        barrierMotor: json['barrier_motor'] as bool? ?? false,
        barrierLinguistic: json['barrier_linguistic'] as bool? ?? false,
        barrierCognitive: json['barrier_cognitive'] as bool? ?? false,
        barrierSensory: json['barrier_sensory'] as bool? ?? false,
        barrierEnvironmental: json['barrier_environmental'] as bool? ?? false,
        barrierMotivational: json['barrier_motivational'] as bool? ?? false,
        barrierDeviceAccess: json['barrier_device_access'] as bool? ?? false,
        targetBehaviour: json['target_behaviour'] as String?,
        condition: json['condition'] as String?,
        criterion: json['criterion'] as String?,
        activityName: json['activity_name'] as String?,
        activityRationale: json['activity_rationale'] as String?,
        promptApproach: json['prompt_approach'] as String?,
        promptLevelUsed: (json['prompt_level_used'] as num?)?.toInt(),
        attempts: (json['attempts'] as num?)?.toInt(),
        independentResponses: (json['independent_responses'] as num?)?.toInt(),
        promptedResponses: (json['prompted_responses'] as num?)?.toInt(),
        clientAffect: json['client_affect'] as String?,
        goalMet: json['goal_met'] as String?,
        homeProgramme: json['home_programme'] as String?,
        soapNote: json['soap_note'] as String?,
        parentSummary: json['parent_summary'] as String?,
        transcript: json['transcript'] as String?,
        notes: json['notes'] as String?,
        goalId: json['goal_id'] as String?,
        shortTermGoalId: json['short_term_goal_id'] as String?,
        aiGenerated: json['ai_generated'] as bool?,
        clinicianAttested: json['clinician_attested'] as bool?,
        attestedAt: _parseDateTime(json['attested_at']),
        attestedBy: json['attested_by'] as String?,
        parentUpdate: json['parent_update'] as String?,
        parentUpdateGeneratedAt:
            _parseDateTime(json['parent_update_generated_at']),
        aiHeadline: json['ai_headline'] as String?,
        populationPayload: json['population_payload'] is Map
            ? Map<String, dynamic>.from(json['population_payload'] as Map)
            : null,
        deletedAt: _parseDateTime(json['deleted_at']),
        deletedBy: json['deleted_by'] as String?,
        deleteReason: json['delete_reason'] as String?,
        createdAt: _parseDateTime(json['created_at']) ??
            DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
        updatedAt: _parseDateTime(json['updated_at']),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'client_id': clientId,
        'client_name': clientName,
        if (userId != null) 'user_id': userId,
        'status': status,
        if (date != null) 'date': _formatDate(date!),
        if (durationMinutes != null) 'duration_minutes': durationMinutes,
        if (outcome != null) 'outcome': outcome!.toDbValue(),
        if (nextSessionFocus != null) 'next_session_focus': nextSessionFocus,
        'barrier_motor': barrierMotor,
        'barrier_linguistic': barrierLinguistic,
        'barrier_cognitive': barrierCognitive,
        'barrier_sensory': barrierSensory,
        'barrier_environmental': barrierEnvironmental,
        'barrier_motivational': barrierMotivational,
        'barrier_device_access': barrierDeviceAccess,
        if (targetBehaviour != null) 'target_behaviour': targetBehaviour,
        if (condition != null) 'condition': condition,
        if (criterion != null) 'criterion': criterion,
        if (activityName != null) 'activity_name': activityName,
        if (activityRationale != null) 'activity_rationale': activityRationale,
        if (promptApproach != null) 'prompt_approach': promptApproach,
        if (promptLevelUsed != null) 'prompt_level_used': promptLevelUsed,
        if (attempts != null) 'attempts': attempts,
        if (independentResponses != null)
          'independent_responses': independentResponses,
        if (promptedResponses != null) 'prompted_responses': promptedResponses,
        if (clientAffect != null) 'client_affect': clientAffect,
        if (goalMet != null) 'goal_met': goalMet,
        if (homeProgramme != null) 'home_programme': homeProgramme,
        if (soapNote != null) 'soap_note': soapNote,
        if (parentSummary != null) 'parent_summary': parentSummary,
        if (transcript != null) 'transcript': transcript,
        if (notes != null) 'notes': notes,
        if (goalId != null) 'goal_id': goalId,
        if (shortTermGoalId != null) 'short_term_goal_id': shortTermGoalId,
        if (aiGenerated != null) 'ai_generated': aiGenerated,
        if (clinicianAttested != null) 'clinician_attested': clinicianAttested,
        if (attestedAt != null) 'attested_at': attestedAt!.toIso8601String(),
        if (attestedBy != null) 'attested_by': attestedBy,
        if (parentUpdate != null) 'parent_update': parentUpdate,
        if (parentUpdateGeneratedAt != null)
          'parent_update_generated_at':
              parentUpdateGeneratedAt!.toIso8601String(),
        if (aiHeadline != null) 'ai_headline': aiHeadline,
        if (populationPayload != null) 'population_payload': populationPayload,
        if (deletedAt != null) 'deleted_at': deletedAt!.toIso8601String(),
        if (deletedBy != null) 'deleted_by': deletedBy,
        if (deleteReason != null) 'delete_reason': deleteReason,
        'created_at': createdAt.toIso8601String(),
        if (updatedAt != null) 'updated_at': updatedAt!.toIso8601String(),
      };

  static DateTime? _parseDateTime(dynamic v) =>
      v is String ? DateTime.tryParse(v) : null;

  static String _formatDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}
