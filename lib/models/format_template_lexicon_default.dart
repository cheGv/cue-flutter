// lib/models/format_template_lexicon_default.dart
//
// Phase C — Cue Mirror, Component Two (Format Drafter).
// Mirrors public.format_template_lexicon_defaults: the SLP's once-per-template
// decision for each forbidden term observed in her format — swap it for Cue's
// neutral replacement, or keep her original wording.

import 'package:flutter/foundation.dart';

@immutable
class FormatTemplateLexiconDefault {
  final String id;
  final String userId;
  final String templateId;
  final String forbiddenTerm;
  final String? replacementTerm; // null when decision == 'keep_original'
  final String decision; // swap | keep_original
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const FormatTemplateLexiconDefault({
    required this.id,
    required this.userId,
    required this.templateId,
    required this.forbiddenTerm,
    required this.decision,
    this.replacementTerm,
    this.createdAt,
    this.updatedAt,
  });

  bool get isSwap => decision == 'swap';

  factory FormatTemplateLexiconDefault.fromJson(Map<String, dynamic> json) =>
      FormatTemplateLexiconDefault(
        id: (json['id'] ?? '').toString(),
        userId: (json['user_id'] ?? '').toString(),
        templateId: (json['template_id'] ?? '').toString(),
        forbiddenTerm: (json['forbidden_term'] as String?) ?? '',
        replacementTerm: json['replacement_term'] as String?,
        decision: (json['decision'] as String?) ?? 'swap',
        createdAt: _date(json['created_at']),
        updatedAt: _date(json['updated_at']),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'user_id': userId,
        'template_id': templateId,
        'forbidden_term': forbiddenTerm,
        if (replacementTerm != null) 'replacement_term': replacementTerm,
        'decision': decision,
        if (createdAt != null) 'created_at': createdAt!.toIso8601String(),
        if (updatedAt != null) 'updated_at': updatedAt!.toIso8601String(),
      };

  static DateTime? _date(dynamic v) =>
      v is String && v.isNotEmpty ? DateTime.tryParse(v) : null;
}
