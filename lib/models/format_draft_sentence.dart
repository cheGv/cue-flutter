// lib/models/format_draft_sentence.dart
//
// Phase D — Cue Mirror Component Three (full). Mirrors public.format_draft_sentences:
// one row per sentence of a draft section. Defensive fromJson (Phase C pattern —
// `as String? ?? ''`, guarded int/date) so a thin or partially-edited row never
// crashes the editor. Reuses SourceClaim / LexiconSwap from format_draft.dart.

import 'package:flutter/foundation.dart';

import 'format_draft.dart' show SourceClaim, LexiconSwap;

@immutable
class FormatDraftSentence {
  final String id;
  final String draftId;
  final String sectionName;
  final int sentenceOrder;
  final String text; // current committed text
  final String? textInProgress; // autosaved, uncommitted edit
  final String textOriginal; // immutable Cue-generated version
  final String status; // cue_drafted | clinician_edited | clinician_authored
  final List<SourceClaim> sourceClaims;
  final List<LexiconSwap> lexiconSwaps;
  final String clinicianId;
  final String templateId;
  final Map<String, dynamic>? substrateSnapshot;
  final DateTime? editedAt;
  final DateTime? savedAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  const FormatDraftSentence({
    required this.id,
    required this.draftId,
    required this.sectionName,
    required this.sentenceOrder,
    required this.text,
    required this.textOriginal,
    required this.status,
    required this.clinicianId,
    required this.templateId,
    required this.createdAt,
    required this.updatedAt,
    this.textInProgress,
    this.sourceClaims = const [],
    this.lexiconSwaps = const [],
    this.substrateSnapshot,
    this.editedAt,
    this.savedAt,
  });

  bool get isCueDrafted => status == 'cue_drafted';
  bool get isClinicianAuthored => status == 'clinician_authored';
  bool get isEdited => status != 'cue_drafted';

  /// An autosaved edit exists that hasn't been committed via Save.
  bool get hasUnsavedEdit =>
      textInProgress != null &&
      textInProgress!.trim().isNotEmpty &&
      textInProgress != text;

  /// What the editor shows: the in-progress edit if present, else committed text.
  String get displayText =>
      (textInProgress != null && textInProgress!.isNotEmpty)
          ? textInProgress!
          : text;

  factory FormatDraftSentence.fromJson(Map<String, dynamic> json) =>
      FormatDraftSentence(
        id: (json['id'] as String?) ?? '',
        draftId: (json['draft_id'] as String?) ?? '',
        sectionName: (json['section_name'] as String?) ?? '',
        sentenceOrder: _int(json['sentence_order']),
        text: (json['text'] as String?) ?? '',
        textInProgress: json['text_in_progress'] as String?,
        textOriginal: (json['text_original'] as String?) ?? '',
        status: (json['status'] as String?) ?? 'cue_drafted',
        sourceClaims: _asList(json['source_claims'])
            .map((e) =>
                SourceClaim.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
        lexiconSwaps: _asList(json['lexicon_swaps'])
            .map((e) =>
                LexiconSwap.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
        clinicianId: (json['clinician_id'] as String?) ?? '',
        templateId: (json['template_id'] as String?) ?? '',
        substrateSnapshot: json['substrate_snapshot'] is Map
            ? Map<String, dynamic>.from(json['substrate_snapshot'] as Map)
            : null,
        editedAt: _date(json['edited_at']),
        savedAt: _date(json['saved_at']),
        createdAt: _date(json['created_at']) ?? DateTime.now(),
        updatedAt: _date(json['updated_at']) ?? DateTime.now(),
      );
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
