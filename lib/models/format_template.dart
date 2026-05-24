// lib/models/format_template.dart
//
// Phase C — Cue Format Adaptation, Component One (Format Extractor).
// Mirrors the public.format_templates table + the structured extraction schema
// produced server-side by POST /format-extract. Defensive fromJson — the
// extracted_template arrives from an LLM and may have missing/extra fields.

import 'package:flutter/foundation.dart';

@immutable
class FormatTemplate {
  final String id;
  final String userId;
  final String name;
  final String formatType; // pt_report | lp_report | progress_report | session_note | discharge_summary | other
  final List<SourceDocument> sourceDocuments;
  final ExtractedTemplate extractedTemplate;
  final String confirmationStatus; // pending | confirmed | archived
  final DateTime? confirmedAt;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool isFixture;
  final String? notes;

  const FormatTemplate({
    required this.id,
    required this.userId,
    required this.name,
    required this.formatType,
    required this.sourceDocuments,
    required this.extractedTemplate,
    required this.confirmationStatus,
    required this.createdAt,
    required this.updatedAt,
    this.confirmedAt,
    this.isFixture = false,
    this.notes,
  });

  bool get isConfirmed => confirmationStatus == 'confirmed';

  factory FormatTemplate.fromJson(Map<String, dynamic> json) {
    return FormatTemplate(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      name: (json['name'] as String?) ?? '',
      formatType: (json['format_type'] as String?) ?? 'other',
      sourceDocuments: _asList(json['source_documents'])
          .map((e) => SourceDocument.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(),
      extractedTemplate: ExtractedTemplate.fromJson(
        json['extracted_template'] is Map
            ? Map<String, dynamic>.from(json['extracted_template'] as Map)
            : const {},
      ),
      confirmationStatus: (json['confirmation_status'] as String?) ?? 'pending',
      confirmedAt: _date(json['confirmed_at']),
      createdAt: _date(json['created_at']) ?? DateTime.now(),
      updatedAt: _date(json['updated_at']) ?? DateTime.now(),
      isFixture: (json['is_fixture'] as bool?) ?? false,
      notes: json['notes'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'user_id': userId,
        'name': name,
        'format_type': formatType,
        'source_documents': sourceDocuments.map((d) => d.toJson()).toList(),
        'extracted_template': extractedTemplate.toJson(),
        'confirmation_status': confirmationStatus,
        if (confirmedAt != null) 'confirmed_at': confirmedAt!.toIso8601String(),
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
        'is_fixture': isFixture,
        if (notes != null) 'notes': notes,
      };
}

@immutable
class SourceDocument {
  final String filename;
  final String storagePath;
  final DateTime? uploadedAt;
  final String fileType; // 'pdf' | 'docx'

  const SourceDocument({
    required this.filename,
    required this.storagePath,
    required this.fileType,
    this.uploadedAt,
  });

  factory SourceDocument.fromJson(Map<String, dynamic> json) => SourceDocument(
        filename: (json['filename'] as String?) ?? '',
        storagePath: (json['storage_path'] as String?) ?? '',
        fileType: (json['file_type'] as String?) ?? 'docx',
        uploadedAt: _date(json['uploaded_at']),
      );

  Map<String, dynamic> toJson() => {
        'filename': filename,
        'storage_path': storagePath,
        'file_type': fileType,
        'uploaded_at': (uploadedAt ?? DateTime.now()).toIso8601String(),
      };
}

/// The structural skeleton returned by /format-extract. Field names mirror the
/// server-side schema exactly so the (edited) template round-trips back to
/// /format-confirm unchanged.
@immutable
class ExtractedTemplate {
  final String formatName;
  final String formatType;
  final List<FormatSection> sections;
  final List<String> placeholders;
  final VoiceRegister voiceRegister;
  final List<String> forbiddenVocabularyObserved;
  final List<String> extractionWarnings;

  const ExtractedTemplate({
    this.formatName = '',
    this.formatType = 'other',
    this.sections = const [],
    this.placeholders = const [],
    this.voiceRegister = const VoiceRegister(),
    this.forbiddenVocabularyObserved = const [],
    this.extractionWarnings = const [],
  });

  bool get isEmpty => sections.isEmpty && placeholders.isEmpty && formatName.isEmpty;

  factory ExtractedTemplate.fromJson(Map<String, dynamic> json) {
    return ExtractedTemplate(
      formatName: (json['format_name'] as String?) ?? '',
      formatType: (json['format_type'] as String?) ?? 'other',
      sections: _asList(json['sections'])
          .map((e) => FormatSection.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(),
      placeholders: _asStringList(json['placeholders']),
      voiceRegister: json['voice_register'] is Map
          ? VoiceRegister.fromJson(
              Map<String, dynamic>.from(json['voice_register'] as Map))
          : const VoiceRegister(),
      forbiddenVocabularyObserved:
          _asStringList(json['forbidden_vocabulary_observed']),
      extractionWarnings: _asStringList(json['extraction_warnings']),
    );
  }

  Map<String, dynamic> toJson() => {
        'format_name': formatName,
        'format_type': formatType,
        'sections': sections.map((s) => s.toJson()).toList(),
        'placeholders': placeholders,
        'voice_register': voiceRegister.toJson(),
        'forbidden_vocabulary_observed': forbiddenVocabularyObserved,
        'extraction_warnings': extractionWarnings,
      };

  ExtractedTemplate copyWith({
    String? formatName,
    String? formatType,
    List<FormatSection>? sections,
    List<String>? placeholders,
    VoiceRegister? voiceRegister,
  }) =>
      ExtractedTemplate(
        formatName: formatName ?? this.formatName,
        formatType: formatType ?? this.formatType,
        sections: sections ?? this.sections,
        placeholders: placeholders ?? this.placeholders,
        voiceRegister: voiceRegister ?? this.voiceRegister,
        forbiddenVocabularyObserved: forbiddenVocabularyObserved,
        extractionWarnings: extractionWarnings,
      );
}

@immutable
class FormatSection {
  final String name;
  final int order;
  final String length; // 'short prose' | 'bulleted list' | 'table' | 'paragraph'
  final String? numbering;
  final List<FormatSection> subsections;
  final List<String> canonicalMap;

  const FormatSection({
    required this.name,
    this.order = 0,
    this.length = 'paragraph',
    this.numbering,
    this.subsections = const [],
    this.canonicalMap = const [],
  });

  factory FormatSection.fromJson(Map<String, dynamic> json) => FormatSection(
        name: (json['name'] as String?) ?? '',
        order: (json['order'] as num?)?.toInt() ?? 0,
        length: (json['length'] as String?) ?? 'paragraph',
        numbering: json['numbering'] as String?,
        subsections: _asList(json['subsections'])
            .map((e) => FormatSection.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
        canonicalMap: _asStringList(json['canonical_map']),
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'order': order,
        'length': length,
        'numbering': numbering,
        'subsections': subsections.isEmpty
            ? null
            : subsections.map((s) => s.toJson()).toList(),
        'canonical_map': canonicalMap,
      };

  FormatSection copyWith({
    String? name,
    int? order,
    String? length,
    String? numbering,
    List<FormatSection>? subsections,
    List<String>? canonicalMap,
  }) =>
      FormatSection(
        name: name ?? this.name,
        order: order ?? this.order,
        length: length ?? this.length,
        numbering: numbering ?? this.numbering,
        subsections: subsections ?? this.subsections,
        canonicalMap: canonicalMap ?? this.canonicalMap,
      );
}

@immutable
class VoiceRegister {
  final List<String> commonVerbs;
  final List<String> commonPhrasings;
  final String sentenceRhythm;
  final Map<String, dynamic> terminologyPreferences;

  const VoiceRegister({
    this.commonVerbs = const [],
    this.commonPhrasings = const [],
    this.sentenceRhythm = '',
    this.terminologyPreferences = const {},
  });

  factory VoiceRegister.fromJson(Map<String, dynamic> json) => VoiceRegister(
        commonVerbs: _asStringList(json['common_verbs']),
        commonPhrasings: _asStringList(json['common_phrasings']),
        sentenceRhythm: (json['sentence_rhythm'] as String?) ?? '',
        terminologyPreferences: json['terminology_preferences'] is Map
            ? Map<String, dynamic>.from(json['terminology_preferences'] as Map)
            : const {},
      );

  Map<String, dynamic> toJson() => {
        'common_verbs': commonVerbs,
        'common_phrasings': commonPhrasings,
        'sentence_rhythm': sentenceRhythm,
        'terminology_preferences': terminologyPreferences,
      };
}

// ── Defensive coercion helpers ───────────────────────────────────────────────
List<dynamic> _asList(dynamic v) => v is List ? v : const [];

List<String> _asStringList(dynamic v) =>
    v is List ? v.map((e) => e.toString()).toList() : const [];

DateTime? _date(dynamic v) {
  if (v is String && v.isNotEmpty) {
    return DateTime.tryParse(v);
  }
  return null;
}
