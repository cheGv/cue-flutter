import 'package:flutter/foundation.dart';

// ---------------------------------------------------------------------------
// Evidence source — controlled vocabulary (§6.7)
// ---------------------------------------------------------------------------
enum EvidenceSource {
  manualEntry,
  aiExtractedNarrator,
  aiExtractedNote;

  String toJson() => switch (this) {
        EvidenceSource.manualEntry => 'manual_entry',
        EvidenceSource.aiExtractedNarrator => 'ai_extracted_narrator',
        EvidenceSource.aiExtractedNote => 'ai_extracted_note',
      };

  static EvidenceSource fromString(String s) => switch (s) {
        'manual_entry' => EvidenceSource.manualEntry,
        'ai_extracted_narrator' => EvidenceSource.aiExtractedNarrator,
        'ai_extracted_note' => EvidenceSource.aiExtractedNote,
        _ => EvidenceSource.manualEntry,
      };
}

// ---------------------------------------------------------------------------
// StgEvidence — immutable model for the `stg_evidence` table.
// Column names match actual Supabase schema:
//   session_id  bigint  (sessions.id is bigint identity, not uuid)
//   patient_id  uuid    (references clients.id — "patients" = clients)
// ---------------------------------------------------------------------------
@immutable
class StgEvidence {
  final String id;
  final String stgId;
  final int sessionId;    // bigint — sessions.id
  final String patientId; // uuid  — clients.id

  final int? trialsAttempted;
  final int? trialsCorrect;
  // accuracy_pct is a generated stored column; present on reads, omit on writes
  final double? accuracyPct;

  final String? cueLevelUsed;        // free text — see §6.3 for valid values
  final String? contextThisSession;
  final String? clinicianObservation;
  final String? recommendation;

  final EvidenceSource source;
  final double? aiConfidence; // 0–1; required when source is ai_extracted_*
  final bool clinicianVerified;

  final DateTime createdAt;

  const StgEvidence({
    required this.id,
    required this.stgId,
    required this.sessionId,
    required this.patientId,
    this.trialsAttempted,
    this.trialsCorrect,
    this.accuracyPct,
    this.cueLevelUsed,
    this.contextThisSession,
    this.clinicianObservation,
    this.recommendation,
    required this.source,
    this.aiConfidence,
    this.clinicianVerified = false,
    required this.createdAt,
  });

  factory StgEvidence.fromJson(Map<String, dynamic> json) => StgEvidence(
        id: json['id'] as String,
        stgId: json['stg_id'] as String,
        sessionId: (json['session_id'] as num).toInt(),
        patientId: json['patient_id'] as String,
        trialsAttempted: json['trials_attempted'] as int?,
        trialsCorrect: json['trials_correct'] as int?,
        accuracyPct: (json['accuracy_pct'] as num?)?.toDouble(),
        cueLevelUsed: json['cue_level_used'] as String?,
        contextThisSession: json['context_this_session'] as String?,
        clinicianObservation: json['clinician_observation'] as String?,
        recommendation: json['recommendation'] as String?,
        source: EvidenceSource.fromString(json['source'] as String),
        aiConfidence: (json['ai_confidence'] as num?)?.toDouble(),
        clinicianVerified: json['clinician_verified'] as bool? ?? false,
        createdAt: DateTime.parse(json['created_at'] as String),
      );

  // Full round-trip JSON (includes accuracy_pct for display/caching)
  Map<String, dynamic> toJson() => {
        'id': id,
        'stg_id': stgId,
        'session_id': sessionId,
        'patient_id': patientId,
        if (trialsAttempted != null) 'trials_attempted': trialsAttempted,
        if (trialsCorrect != null) 'trials_correct': trialsCorrect,
        if (accuracyPct != null) 'accuracy_pct': accuracyPct,
        if (cueLevelUsed != null) 'cue_level_used': cueLevelUsed,
        if (contextThisSession != null)
          'context_this_session': contextThisSession,
        if (clinicianObservation != null)
          'clinician_observation': clinicianObservation,
        if (recommendation != null) 'recommendation': recommendation,
        'source': source.toJson(),
        if (aiConfidence != null) 'ai_confidence': aiConfidence,
        'clinician_verified': clinicianVerified,
        'created_at': createdAt.toIso8601String(),
      };

  // Insert payload — omits id, accuracy_pct (generated), created_at (defaulted)
  Map<String, dynamic> toInsertJson() => {
        'stg_id': stgId,
        'session_id': sessionId,
        'patient_id': patientId,
        if (trialsAttempted != null) 'trials_attempted': trialsAttempted,
        if (trialsCorrect != null) 'trials_correct': trialsCorrect,
        if (cueLevelUsed != null) 'cue_level_used': cueLevelUsed,
        if (contextThisSession != null)
          'context_this_session': contextThisSession,
        if (clinicianObservation != null)
          'clinician_observation': clinicianObservation,
        if (recommendation != null) 'recommendation': recommendation,
        'source': source.toJson(),
        if (aiConfidence != null) 'ai_confidence': aiConfidence,
        'clinician_verified': clinicianVerified,
      };

  StgEvidence copyWith({
    String? id,
    String? stgId,
    int? sessionId,
    String? patientId,
    int? trialsAttempted,
    int? trialsCorrect,
    double? accuracyPct,
    String? cueLevelUsed,
    String? contextThisSession,
    String? clinicianObservation,
    String? recommendation,
    EvidenceSource? source,
    double? aiConfidence,
    bool? clinicianVerified,
    DateTime? createdAt,
  }) =>
      StgEvidence(
        id: id ?? this.id,
        stgId: stgId ?? this.stgId,
        sessionId: sessionId ?? this.sessionId,
        patientId: patientId ?? this.patientId,
        trialsAttempted: trialsAttempted ?? this.trialsAttempted,
        trialsCorrect: trialsCorrect ?? this.trialsCorrect,
        accuracyPct: accuracyPct ?? this.accuracyPct,
        cueLevelUsed: cueLevelUsed ?? this.cueLevelUsed,
        contextThisSession: contextThisSession ?? this.contextThisSession,
        clinicianObservation:
            clinicianObservation ?? this.clinicianObservation,
        recommendation: recommendation ?? this.recommendation,
        source: source ?? this.source,
        aiConfidence: aiConfidence ?? this.aiConfidence,
        clinicianVerified: clinicianVerified ?? this.clinicianVerified,
        createdAt: createdAt ?? this.createdAt,
      );
}
