// lib/models/reasoning_thread.dart
//
// Phase 4.0.7.20d — a Cue Reasoning thread is keyed to (clinician_id,
// client_id, ltg_id?, stg_id?) and holds the full message list.
// Domains_active filters which EBP frameworks the edge function may
// cite when assembling its system prompt.

class ReasoningThread {
  final String id;
  final String clientId;
  final String? ltgId;
  final String? stgId;
  final List<String> domainsActive;
  final String? title;
  final DateTime createdAt;
  final DateTime updatedAt;

  const ReasoningThread({
    required this.id,
    required this.clientId,
    this.ltgId,
    this.stgId,
    required this.domainsActive,
    this.title,
    required this.createdAt,
    required this.updatedAt,
  });

  factory ReasoningThread.fromJson(Map<String, dynamic> json) {
    return ReasoningThread(
      id:        (json['id']         ?? '').toString(),
      clientId:  (json['client_id']  ?? '').toString(),
      ltgId:     (json['ltg_id'] as String?),
      stgId:     (json['stg_id'] as String?),
      domainsActive: (json['domains_active'] is List)
          ? List<String>.from(
              (json['domains_active'] as List).map((e) => e.toString()))
          : const [],
      title:     (json['title'] as String?),
      createdAt: _parseTs(json['created_at']) ?? DateTime.now(),
      updatedAt: _parseTs(json['updated_at']) ?? DateTime.now(),
    );
  }

  static DateTime? _parseTs(dynamic v) {
    if (v is String && v.isNotEmpty) {
      try { return DateTime.parse(v).toLocal(); } catch (_) {}
    }
    return null;
  }
}

class FrameworkCitation {
  final String shortCode;
  final String name;
  final String? description;
  final List<String> keyAuthors;
  final String? evidenceLevel;
  final String? whenToUse;

  const FrameworkCitation({
    required this.shortCode,
    required this.name,
    this.description,
    required this.keyAuthors,
    this.evidenceLevel,
    this.whenToUse,
  });

  factory FrameworkCitation.fromJson(Map<String, dynamic> json) {
    return FrameworkCitation(
      shortCode:    (json['short_code']    ?? '').toString(),
      name:         (json['name']          ?? '').toString(),
      description:  (json['description']   as String?),
      keyAuthors: (json['key_authors'] is List)
          ? List<String>.from(
              (json['key_authors'] as List).map((e) => e.toString()))
          : const [],
      evidenceLevel: (json['evidence_level'] as String?),
      whenToUse:     (json['when_to_use']    as String?),
    );
  }
}
