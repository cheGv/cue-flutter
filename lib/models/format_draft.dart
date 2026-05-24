// lib/models/format_draft.dart
//
// Phase C — Cue Mirror, Component Two (Format Drafter).
// Mirrors the public.format_drafts table + the structured draft schema produced
// server-side by POST /format-draft. Defensive fromJson — draft_sections arrive
// from an LLM and may have missing/extra fields. Every clinical claim carries
// its source (SourceClaim); every neutral-language substitution is recorded
// (LexiconSwap) so the Cue draft view can show §language-discipline visibility.

import 'package:flutter/foundation.dart';

@immutable
class FormatDraft {
  final String id;
  final String userId;
  final String clientId;
  final String templateId;
  final DateTime? dateRangeStart;
  final DateTime? dateRangeEnd;
  final String? dateRangePreset; // weekly | monthly | quarterly | all_sessions | custom
  final List<DraftSection> draftSections;
  final GenerationMetadata generationMetadata;
  final String status; // draft | reviewed | signed | archived
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime generatedAt;
  final bool isFixture;
  final String? notes;

  const FormatDraft({
    required this.id,
    required this.userId,
    required this.clientId,
    required this.templateId,
    required this.draftSections,
    required this.generationMetadata,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    required this.generatedAt,
    this.dateRangeStart,
    this.dateRangeEnd,
    this.dateRangePreset,
    this.isFixture = false,
    this.notes,
  });

  bool get isReviewed => status == 'reviewed';

  factory FormatDraft.fromJson(Map<String, dynamic> json) => FormatDraft(
        id: json['id'] as String,
        userId: json['user_id'] as String,
        clientId: json['client_id'] as String,
        templateId: json['template_id'] as String,
        dateRangeStart: _date(json['date_range_start']),
        dateRangeEnd: _date(json['date_range_end']),
        dateRangePreset: json['date_range_preset'] as String?,
        draftSections: _asList(json['draft_sections'])
            .map((e) => DraftSection.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
        generationMetadata: GenerationMetadata.fromJson(
          json['generation_metadata'] is Map
              ? Map<String, dynamic>.from(json['generation_metadata'] as Map)
              : const {},
        ),
        status: (json['status'] as String?) ?? 'draft',
        createdAt: _date(json['created_at']) ?? DateTime.now(),
        updatedAt: _date(json['updated_at']) ?? DateTime.now(),
        generatedAt: _date(json['generated_at']) ?? DateTime.now(),
        isFixture: (json['is_fixture'] as bool?) ?? false,
        notes: json['notes'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'user_id': userId,
        'client_id': clientId,
        'template_id': templateId,
        if (dateRangeStart != null)
          'date_range_start': dateRangeStart!.toIso8601String(),
        if (dateRangeEnd != null)
          'date_range_end': dateRangeEnd!.toIso8601String(),
        if (dateRangePreset != null) 'date_range_preset': dateRangePreset,
        'draft_sections': draftSections.map((s) => s.toJson()).toList(),
        'generation_metadata': generationMetadata.toJson(),
        'status': status,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
        'generated_at': generatedAt.toIso8601String(),
        'is_fixture': isFixture,
        if (notes != null) 'notes': notes,
      };
}

@immutable
class DraftSection {
  final String sectionName;
  final String content;
  final List<SourceClaim> sourceClaims;
  final List<LexiconSwap> lexiconSwaps;

  const DraftSection({
    required this.sectionName,
    this.content = '',
    this.sourceClaims = const [],
    this.lexiconSwaps = const [],
  });

  /// A clinician-authored placeholder section (no canonical session data).
  bool get isStaticAuthored =>
      sourceClaims.length == 1 &&
      sourceClaims.first.sourceType == 'static_clinician_authored';

  factory DraftSection.fromJson(Map<String, dynamic> json) => DraftSection(
        sectionName: (json['section_name'] as String?) ?? '',
        content: (json['content'] as String?) ?? '',
        sourceClaims: _asList(json['source_claims'])
            .map((e) => SourceClaim.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
        lexiconSwaps: _asList(json['lexicon_swaps'])
            .map((e) => LexiconSwap.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
      );

  Map<String, dynamic> toJson() => {
        'section_name': sectionName,
        'content': content,
        'source_claims': sourceClaims.map((c) => c.toJson()).toList(),
        'lexicon_swaps': lexiconSwaps.map((s) => s.toJson()).toList(),
      };
}

@immutable
class SourceClaim {
  final String claimText;
  final String sourceType; // session | substrate | goal | citation | static_clinician_authored
  final String sourceId;
  final String sourceExcerpt;

  const SourceClaim({
    required this.claimText,
    required this.sourceType,
    this.sourceId = '',
    this.sourceExcerpt = '',
  });

  factory SourceClaim.fromJson(Map<String, dynamic> json) => SourceClaim(
        claimText: (json['claim_text'] as String?) ?? '',
        sourceType: (json['source_type'] as String?) ?? '',
        sourceId: (json['source_id'] ?? '').toString(),
        sourceExcerpt: (json['source_excerpt'] as String?) ?? '',
      );

  Map<String, dynamic> toJson() => {
        'claim_text': claimText,
        'source_type': sourceType,
        'source_id': sourceId,
        'source_excerpt': sourceExcerpt,
      };
}

@immutable
class LexiconSwap {
  final String original;
  final String replacement;
  final int positionInContent;

  const LexiconSwap({
    required this.original,
    required this.replacement,
    this.positionInContent = 0,
  });

  factory LexiconSwap.fromJson(Map<String, dynamic> json) => LexiconSwap(
        original: (json['original'] as String?) ?? '',
        replacement: (json['replacement'] as String?) ?? '',
        positionInContent: _int(json['position_in_content']),
      );

  Map<String, dynamic> toJson() => {
        'original': original,
        'replacement': replacement,
        'position_in_content': positionInContent,
      };
}

@immutable
class GenerationMetadata {
  final String model;
  final int inputTokens;
  final int outputTokens;
  final int latencyMs;
  final Map<String, dynamic> templateVersionSnapshot;

  const GenerationMetadata({
    this.model = '',
    this.inputTokens = 0,
    this.outputTokens = 0,
    this.latencyMs = 0,
    this.templateVersionSnapshot = const {},
  });

  factory GenerationMetadata.fromJson(Map<String, dynamic> json) {
    final tokens = json['tokens'] is Map
        ? Map<String, dynamic>.from(json['tokens'] as Map)
        : const <String, dynamic>{};
    return GenerationMetadata(
      model: (json['model'] as String?) ?? '',
      inputTokens: _int(tokens['input_tokens']),
      outputTokens: _int(tokens['output_tokens']),
      latencyMs: _int(json['latency_ms']),
      templateVersionSnapshot: json['template_version_snapshot'] is Map
          ? Map<String, dynamic>.from(json['template_version_snapshot'] as Map)
          : const {},
    );
  }

  Map<String, dynamic> toJson() => {
        'model': model,
        'tokens': {'input_tokens': inputTokens, 'output_tokens': outputTokens},
        'latency_ms': latencyMs,
        'template_version_snapshot': templateVersionSnapshot,
      };
}

// ── Defensive coercion helpers ───────────────────────────────────────────────
List<dynamic> _asList(dynamic v) => v is List ? v : const [];

int _int(dynamic v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v) ?? 0;
  return 0;
}

DateTime? _date(dynamic v) {
  if (v is String && v.isNotEmpty) return DateTime.tryParse(v);
  return null;
}
