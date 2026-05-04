// lib/models/reasoning_message.dart
//
// Phase 4.0.7.20d — one turn of a Cue Reasoning conversation. Mirrors
// the public.reasoning_messages row shape returned by the
// reasoning-respond edge function.

class ReasoningMessage {
  final String id;
  final String threadId;
  final String role; // 'user' | 'assistant' | 'system'
  final String content;
  final List<Map<String, dynamic>> citations;
  final List<String> frameworkIds;
  final bool appliedToGoal;
  final DateTime createdAt;

  const ReasoningMessage({
    required this.id,
    required this.threadId,
    required this.role,
    required this.content,
    required this.citations,
    required this.frameworkIds,
    required this.appliedToGoal,
    required this.createdAt,
  });

  factory ReasoningMessage.fromJson(Map<String, dynamic> json) {
    return ReasoningMessage(
      id:        (json['id']         ?? '').toString(),
      threadId:  (json['thread_id']  ?? '').toString(),
      role:      (json['role']       ?? 'assistant').toString(),
      content:   (json['content']    ?? '').toString(),
      citations: (json['citations'] is List)
          ? List<Map<String, dynamic>>.from(
              (json['citations'] as List).whereType<Map>().map(
                  (m) => Map<String, dynamic>.from(m)))
          : const [],
      frameworkIds: (json['framework_ids'] is List)
          ? List<String>.from(
              (json['framework_ids'] as List).map((e) => e.toString()))
          : const [],
      appliedToGoal: json['applied_to_goal'] == true,
      createdAt: _parseTs(json['created_at']) ?? DateTime.now(),
    );
  }

  static DateTime? _parseTs(dynamic v) {
    if (v is String && v.isNotEmpty) {
      try { return DateTime.parse(v).toLocal(); } catch (_) {}
    }
    return null;
  }
}
