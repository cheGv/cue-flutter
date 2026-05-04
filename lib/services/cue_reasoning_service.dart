// lib/services/cue_reasoning_service.dart
//
// Phase 4.0.7.20d — Cue Reasoning V1 client. Wraps the Supabase
// edge function `reasoning-respond` (verify_jwt = true) and the
// reasoning_threads / reasoning_messages tables.
//
// The edge function does:
//   - Auth check (RLS-enforced clinician_id ownership of thread).
//   - Goal-context fetch + EBP framework filter by domains_active.
//   - Anthropic Sonnet 4.6 call with clinical-reasoning system prompt.
//   - Persist user + assistant turns to reasoning_messages.
//   - Return:
//       { thread_id, message, cited_frameworks, suggested_revision,
//         token_usage }
//
// This service does NOT do its own prompt engineering or framework
// fetching — that's all server-side. It owns:
//   - Marshalling the call.
//   - Parsing the response into typed models.
//   - Loading prior thread history (direct table read, RLS-protected).
//   - Recording when a message has been applied to a goal.

import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/reasoning_message.dart';
import '../models/reasoning_thread.dart';

/// Result of a single sendMessage call. `messages` contains both the
/// user turn the caller submitted and the assistant turn that came
/// back, so the panel can append the pair atomically and stay in sync
/// with the server.
class CueReasoningResult {
  final String threadId;
  final List<ReasoningMessage> messages;
  final List<FrameworkCitation> citedFrameworks;
  final String? suggestedRevision;
  final Map<String, dynamic>? tokenUsage;

  const CueReasoningResult({
    required this.threadId,
    required this.messages,
    required this.citedFrameworks,
    this.suggestedRevision,
    this.tokenUsage,
  });
}

class CueReasoningException implements Exception {
  final String message;
  final String? detail;
  CueReasoningException(this.message, {this.detail});
  @override
  String toString() =>
      detail == null ? message : '$message ($detail)';
}

class CueReasoningService {
  CueReasoningService._();
  static final instance = CueReasoningService._();

  SupabaseClient get _sb => Supabase.instance.client;

  /// Send a user message into a reasoning thread. Pass `threadId` to
  /// continue an existing thread, or omit to let the edge function
  /// create one keyed to (clinician_id, client_id, ltg_id, stg_id).
  Future<CueReasoningResult> sendMessage({
    String? threadId,
    String? clientId,
    String? ltgId,
    String? stgId,
    required String userMessage,
    List<String>? domainsActive,
  }) async {
    final body = <String, dynamic>{
      'thread_id':      ?threadId,
      'client_id':      ?clientId,
      'ltg_id':         ?ltgId,
      'stg_id':         ?stgId,
      'domains_active': ?domainsActive,
      'user_message':   userMessage,
    };

    final FunctionResponse response;
    try {
      response = await _sb.functions.invoke(
        'reasoning-respond',
        body: body,
      );
    } catch (e) {
      throw CueReasoningException(
          'Could not reach Cue Reasoning.', detail: '$e');
    }

    final status = response.status;
    final raw = response.data;
    if (status >= 400 || raw == null) {
      String msg = 'Cue Reasoning failed (HTTP $status).';
      String? detail;
      if (raw is Map) {
        final m = Map<String, dynamic>.from(raw);
        if (m['error']  is String) msg    = m['error']  as String;
        if (m['detail'] is String) detail = m['detail'] as String;
      }
      throw CueReasoningException(msg, detail: detail);
    }

    final Map<String, dynamic> data = (raw is Map<String, dynamic>)
        ? raw
        : Map<String, dynamic>.from(raw as Map);

    final returnedThreadId = (data['thread_id'] ?? '').toString();
    if (returnedThreadId.isEmpty) {
      throw CueReasoningException(
          'Cue Reasoning returned no thread id.', detail: '$data');
    }

    final assistantRaw = data['message'];
    final List<ReasoningMessage> messages = [];
    if (assistantRaw is Map) {
      messages.add(
          ReasoningMessage.fromJson(Map<String, dynamic>.from(assistantRaw)));
    }

    final citedRaw = data['cited_frameworks'];
    final List<FrameworkCitation> cited = (citedRaw is List)
        ? citedRaw
            .whereType<Map>()
            .map((m) => FrameworkCitation.fromJson(
                Map<String, dynamic>.from(m)))
            .toList()
        : <FrameworkCitation>[];

    return CueReasoningResult(
      threadId:          returnedThreadId,
      messages:          messages,
      citedFrameworks:   cited,
      suggestedRevision: data['suggested_revision'] as String?,
      tokenUsage: (data['token_usage'] is Map)
          ? Map<String, dynamic>.from(data['token_usage'] as Map)
          : null,
    );
  }

  /// Loads existing message history for a thread, in chronological
  /// order. RLS scopes this to threads the current clinician owns.
  Future<List<ReasoningMessage>> loadThreadHistory(String threadId) async {
    try {
      final rows = await _sb
          .from('reasoning_messages')
          .select()
          .eq('thread_id', threadId)
          .order('created_at', ascending: true);
      return (rows as List)
          .whereType<Map>()
          .map((m) => ReasoningMessage.fromJson(
              Map<String, dynamic>.from(m)))
          .toList();
    } catch (e) {
      throw CueReasoningException(
          'Could not load reasoning history.', detail: '$e');
    }
  }

  /// Find any existing thread for a (client, ltg|stg) pair so the SLP
  /// can resume reasoning a week later. Returns null when no thread
  /// exists yet — the caller should leave thread_id null on the first
  /// sendMessage call so the edge function creates one.
  Future<ReasoningThread?> findThread({
    required String clientId,
    String? ltgId,
    String? stgId,
  }) async {
    try {
      var query = _sb
          .from('reasoning_threads')
          .select()
          .eq('client_id', clientId);
      if (ltgId != null) query = query.eq('ltg_id', ltgId);
      if (stgId != null) query = query.eq('stg_id', stgId);
      final rows = await query
          .order('updated_at', ascending: false)
          .limit(1);
      if ((rows as List).isEmpty) return null;
      return ReasoningThread.fromJson(
          Map<String, dynamic>.from(rows.first as Map));
    } catch (_) {
      return null;
    }
  }

  /// Mark a message as having been applied to a downstream goal field
  /// (rationale, framework, etc). Used by Cite-this-in-rationale and
  /// Apply-suggested-revision flows. Best-effort — failure does not
  /// block the caller-side write.
  Future<bool> applyMessageToGoal({
    required String messageId,
    required String goalId,
    required String fieldName,
    required String contentToInject,
  }) async {
    try {
      await _sb.from('reasoning_messages').update({
        'applied_to_goal':       true,
        'applied_to_goal_id':    goalId,
        'applied_to_field_name': fieldName,
        'applied_at':            DateTime.now().toUtc().toIso8601String(),
      }).eq('id', messageId);
      return true;
    } catch (_) {
      return false;
    }
  }
}
