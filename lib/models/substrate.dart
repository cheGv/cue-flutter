// lib/models/substrate.dart
//
// Phase A — Substrate models. Mirror the four tables created in
// supabase/migrations/20260521120000_phase_a_substrate_tables.sql:
//   • substrate_cells       — one row per (client, layer, sub_category)
//   • substrate_sources      — source attribution per cell
//   • substrate_tags         — patient-specific clinical-concept tags
//   • substrate_relations    — GLOBAL hand-authored threading graph
//
// Controlled vocabulary lives in docs/substrate-taxonomy.md (v0.1, locked
// for Phase A). CUE PRODUCT LAW: these carry evidence + attribution + a tag
// relation graph. Nothing here ranks, scores, concludes, or recommends.
//
// Parsing convention matches the rest of lib/models: plain immutable
// classes, defensive fromJson factories, snake_case-aware enums with
// toJson()/fromString(). client_id (not patient_id) per the migration's
// §7 schema-reconciliation note — there is no `patients` table.

import 'package:flutter/foundation.dart';

// ── Layer — six-domain clinical-evidence taxonomy ────────────────────────────
//
// Declaration order IS the fixed UI render order. Regulation is always
// first: the polyvagal-informed paradigm gates everything above it. The
// order is paradigm, not preference — never sort layers any other way.
// (DB text sort would put 'safety_regulation' LAST alphabetically, which
// is why grouping/ordering is the view's job via these enum values, not
// an ORDER BY layer.)
enum SubstrateLayer {
  safetyRegulation,
  cognitiveLinguistic,
  communicationPragmatic,
  motorSpeech,
  familyEnvironment,
  developmentalTrajectory;

  String toJson() => switch (this) {
        SubstrateLayer.safetyRegulation => 'safety_regulation',
        SubstrateLayer.cognitiveLinguistic => 'cognitive_linguistic',
        SubstrateLayer.communicationPragmatic => 'communication_pragmatic',
        SubstrateLayer.motorSpeech => 'motor_speech',
        SubstrateLayer.familyEnvironment => 'family_environment',
        SubstrateLayer.developmentalTrajectory => 'developmental_trajectory',
      };

  static SubstrateLayer? fromString(String? s) => switch (s) {
        'safety_regulation' => SubstrateLayer.safetyRegulation,
        'cognitive_linguistic' => SubstrateLayer.cognitiveLinguistic,
        'communication_pragmatic' => SubstrateLayer.communicationPragmatic,
        'motor_speech' => SubstrateLayer.motorSpeech,
        'family_environment' => SubstrateLayer.familyEnvironment,
        'developmental_trajectory' => SubstrateLayer.developmentalTrajectory,
        _ => null,
      };

  /// Section heading exactly as authored in the taxonomy doc.
  String get title => switch (this) {
        SubstrateLayer.safetyRegulation => 'Safety and regulation',
        SubstrateLayer.cognitiveLinguistic => 'Cognitive-linguistic substrate',
        SubstrateLayer.communicationPragmatic =>
          'Communication-pragmatic substrate',
        SubstrateLayer.motorSpeech => 'Motor-speech substrate',
        SubstrateLayer.familyEnvironment => 'Family system and environment',
        SubstrateLayer.developmentalTrajectory => 'Developmental trajectory',
      };
}

// ── Cell attribute — cross-cutting flags (jsonb array on the cell) ───────────
enum SubstrateAttribute {
  safetyFlag,
  prognostic,
  ageConditional,
  assessmentFit;

  String toJson() => switch (this) {
        SubstrateAttribute.safetyFlag => 'safety_flag',
        SubstrateAttribute.prognostic => 'prognostic',
        SubstrateAttribute.ageConditional => 'age_conditional',
        SubstrateAttribute.assessmentFit => 'assessment_fit',
      };

  static SubstrateAttribute? fromString(String? s) => switch (s) {
        'safety_flag' => SubstrateAttribute.safetyFlag,
        'prognostic' => SubstrateAttribute.prognostic,
        'age_conditional' => SubstrateAttribute.ageConditional,
        'assessment_fit' => SubstrateAttribute.assessmentFit,
        _ => null,
      };

  /// Human-facing pill label.
  String get label => switch (this) {
        SubstrateAttribute.safetyFlag => 'Safety',
        SubstrateAttribute.prognostic => 'Prognostic',
        SubstrateAttribute.ageConditional => 'Age-conditional',
        SubstrateAttribute.assessmentFit => 'Assessment fit',
      };
}

// ── Source type — substrate_sources.source_type ──────────────────────────────
enum SubstrateSourceType {
  sessionNote,
  intake,
  externalReport,
  assessment;

  String toJson() => switch (this) {
        SubstrateSourceType.sessionNote => 'session_note',
        SubstrateSourceType.intake => 'intake',
        SubstrateSourceType.externalReport => 'external_report',
        SubstrateSourceType.assessment => 'assessment',
      };

  static SubstrateSourceType? fromString(String? s) => switch (s) {
        'session_note' => SubstrateSourceType.sessionNote,
        'intake' => SubstrateSourceType.intake,
        'external_report' => SubstrateSourceType.externalReport,
        'assessment' => SubstrateSourceType.assessment,
        _ => null,
      };

  String get label => switch (this) {
        SubstrateSourceType.sessionNote => 'Session note',
        SubstrateSourceType.intake => 'Intake',
        SubstrateSourceType.externalReport => 'External report',
        SubstrateSourceType.assessment => 'Assessment',
      };
}

// ── Relation strength / direction — substrate_relations edges ────────────────
enum SubstrateRelationStrength {
  strong,
  moderate,
  weak;

  String toJson() => name;

  // DB CHECK guarantees one of three; default to moderate defensively.
  static SubstrateRelationStrength fromString(String? s) => switch (s) {
        'strong' => SubstrateRelationStrength.strong,
        'weak' => SubstrateRelationStrength.weak,
        _ => SubstrateRelationStrength.moderate,
      };
}

enum SubstrateRelationDirection {
  mutual,
  sourceToTarget;

  String toJson() => switch (this) {
        SubstrateRelationDirection.sourceToTarget => 'source_to_target',
        SubstrateRelationDirection.mutual => 'mutual',
      };

  static SubstrateRelationDirection fromString(String? s) => switch (s) {
        'source_to_target' => SubstrateRelationDirection.sourceToTarget,
        _ => SubstrateRelationDirection.mutual,
      };
}

// ── substrate_sources ────────────────────────────────────────────────────────
@immutable
class SubstrateSource {
  final String id;
  final String cellId;
  final SubstrateSourceType? sourceType;

  /// Narrator session id (sessions.id is bigint, stored as text), intake
  /// form id, external report ref, assessment entry — origin pointer.
  final String? sourceRef;

  /// Verbatim quoted material that grounds the cell.
  final String? excerpt;
  final DateTime? date;

  const SubstrateSource({
    required this.id,
    required this.cellId,
    this.sourceType,
    this.sourceRef,
    this.excerpt,
    this.date,
  });

  factory SubstrateSource.fromJson(Map<String, dynamic> json) =>
      SubstrateSource(
        id: (json['id'] ?? '').toString(),
        cellId: (json['cell_id'] ?? '').toString(),
        sourceType:
            SubstrateSourceType.fromString(json['source_type'] as String?),
        sourceRef: json['source_ref'] as String?,
        excerpt: json['excerpt'] as String?,
        date: _parseDate(json['date']),
      );
}

// ── substrate_tags ───────────────────────────────────────────────────────────
@immutable
class SubstrateTag {
  final String id;
  final String cellId;
  final String tag;

  const SubstrateTag({
    required this.id,
    required this.cellId,
    required this.tag,
  });

  factory SubstrateTag.fromJson(Map<String, dynamic> json) => SubstrateTag(
        id: (json['id'] ?? '').toString(),
        cellId: (json['cell_id'] ?? '').toString(),
        tag: (json['tag'] ?? '').toString(),
      );
}

// ── substrate_cells ──────────────────────────────────────────────────────────
@immutable
class SubstrateCell {
  final String id;
  final String clientId;

  /// Null only if the DB ever returned an unknown layer value (the CHECK
  /// constraint prevents this); such a cell groups into no layer section.
  final SubstrateLayer? layer;
  final String subCategory;

  /// Null / blank = "not yet on file" — an open clinical question, still
  /// rendered. Never treat an empty cell as missing data.
  final String? content;
  final List<SubstrateAttribute> attributes;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? createdBy;

  /// Embedded via PostgREST FK selection (substrate_sources(*)).
  final List<SubstrateSource> sources;

  /// Embedded via PostgREST FK selection (substrate_tags(*)).
  final List<SubstrateTag> tags;

  const SubstrateCell({
    required this.id,
    required this.clientId,
    required this.layer,
    required this.subCategory,
    this.content,
    this.attributes = const [],
    required this.createdAt,
    required this.updatedAt,
    this.createdBy,
    this.sources = const [],
    this.tags = const [],
  });

  /// An open clinical question — content not yet on file.
  bool get isEmpty => content == null || content!.trim().isEmpty;

  bool get hasSafetyFlag => attributes.contains(SubstrateAttribute.safetyFlag);
  bool get isPrognostic => attributes.contains(SubstrateAttribute.prognostic);

  factory SubstrateCell.fromJson(Map<String, dynamic> json) => SubstrateCell(
        id: (json['id'] ?? '').toString(),
        clientId: (json['client_id'] ?? '').toString(),
        layer: SubstrateLayer.fromString(json['layer'] as String?),
        subCategory: (json['sub_category'] ?? '').toString(),
        content: json['content'] as String?,
        attributes: _parseAttributes(json['attributes']),
        createdAt: _parseTs(json['created_at']) ?? DateTime.now(),
        updatedAt: _parseTs(json['updated_at']) ?? DateTime.now(),
        createdBy: json['created_by'] as String?,
        sources: _parseChildren(json['substrate_sources'], SubstrateSource.fromJson),
        tags: _parseChildren(json['substrate_tags'], SubstrateTag.fromJson),
      );
}

// ── substrate_relations — GLOBAL clinical-knowledge graph ────────────────────
@immutable
class SubstrateRelation {
  final String id;
  final String sourceTag;
  final String targetTag;
  final SubstrateRelationStrength strength;
  final SubstrateRelationDirection direction;

  /// One-line clinical rationale — authored, never generated.
  final String? reasoning;

  const SubstrateRelation({
    required this.id,
    required this.sourceTag,
    required this.targetTag,
    required this.strength,
    required this.direction,
    this.reasoning,
  });

  factory SubstrateRelation.fromJson(Map<String, dynamic> json) =>
      SubstrateRelation(
        id: (json['id'] ?? '').toString(),
        sourceTag: (json['source_tag'] ?? '').toString(),
        targetTag: (json['target_tag'] ?? '').toString(),
        strength:
            SubstrateRelationStrength.fromString(json['strength'] as String?),
        direction: SubstrateRelationDirection.fromString(
            json['direction'] as String?),
        reasoning: json['reasoning'] as String?,
      );
}

// ── Parsing helpers ──────────────────────────────────────────────────────────

DateTime? _parseTs(dynamic v) {
  if (v is String && v.isNotEmpty) {
    try {
      return DateTime.parse(v).toLocal();
    } catch (_) {}
  }
  return null;
}

DateTime? _parseDate(dynamic v) {
  if (v is String && v.isNotEmpty) {
    try {
      return DateTime.parse(v); // date-only; no timezone shift wanted
    } catch (_) {}
  }
  return null;
}

List<SubstrateAttribute> _parseAttributes(dynamic v) {
  if (v is List) {
    return v
        .map((e) => SubstrateAttribute.fromString(e?.toString()))
        .whereType<SubstrateAttribute>()
        .toList();
  }
  return const [];
}

List<T> _parseChildren<T>(
    dynamic v, T Function(Map<String, dynamic>) fromJson) {
  if (v is List) {
    return v
        .whereType<Map>()
        .map((m) => fromJson(Map<String, dynamic>.from(m)))
        .toList();
  }
  return <T>[];
}
