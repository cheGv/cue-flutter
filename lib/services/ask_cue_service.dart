// lib/services/ask_cue_service.dart
//
// Phase 5.1+5.2 — Ask Cue service. Unified chat surface replacing
// Cue Study (retired) + the prior Reasoning panel data layer.
//
// Stream<String> API throughout per founder decision Q1 (Option 2):
// the spec requires a streaming UX, but the underlying Render proxy +
// Supabase edge function are both batch (single JSON response) today.
// Until SSE lands (Phase 5.3, alongside voice input), the Stream emits
// the full assistant text in one chunk after the network call returns.
// Callers wire to the Stream now so the future SSE swap is internal.
//
// Scope:
//   • Client-scoped threads: ltg_id IS NULL AND stg_id IS NULL.
//     No goal anchor. The migrated 15 Cue Study threads land here.
//   • Goal-scoped threads:   ltg_id or stg_id non-null. Existing
//     Reasoning behavior (citations, frameworks_active filter)
//     applies. The reasoning-respond edge function handles both;
//     the check constraint that previously forced a goal anchor
//     was dropped in the Phase 5.0 DB migration.
//
// This service does NOT do prompt engineering or framework fetching —
// that's all server-side (reasoning-respond edge function). It owns
// thread CRUD, message marshalling, and the stream wrapper.

import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/reasoning_message.dart';
import '../models/reasoning_thread.dart';

/// Result of a streamed sendMessage call. The stream emits the
/// assistant text incrementally (one chunk in v1; multiple chunks
/// once SSE lands). When the stream closes, [completion] resolves
/// with the persisted message + framework citations.
class AskCueStreamResult {
  final Stream<String> textStream;
  final Future<AskCueCompletion> completion;
  const AskCueStreamResult({
    required this.textStream,
    required this.completion,
  });
}

class AskCueCompletion {
  final String threadId;
  final ReasoningMessage assistantMessage;
  final List<FrameworkCitation> citedFrameworks;
  final String? suggestedRevision;
  const AskCueCompletion({
    required this.threadId,
    required this.assistantMessage,
    required this.citedFrameworks,
    this.suggestedRevision,
  });
}

class AskCueException implements Exception {
  final String message;
  final String? detail;
  AskCueException(this.message, {this.detail});
  @override
  String toString() => detail == null ? message : '$message ($detail)';
}

class AskCueService {
  AskCueService._();
  static final instance = AskCueService._();

  SupabaseClient get _sb => Supabase.instance.client;

  /// List threads for a client, newest-first. Both client-scoped
  /// (ltg_id IS NULL AND stg_id IS NULL) and goal-scoped threads
  /// are returned; the caller decides how to render the scope dot.
  Future<List<ReasoningThread>> listThreads({
    required String clientId,
  }) async {
    try {
      final rows = await _sb
          .from('reasoning_threads')
          .select()
          .eq('client_id', clientId)
          .order('updated_at', ascending: false);
      return (rows as List)
          .whereType<Map>()
          .map((m) => ReasoningThread.fromJson(
              Map<String, dynamic>.from(m)))
          .toList();
    } catch (e) {
      throw AskCueException('Could not load Ask Cue threads.',
          detail: '$e');
    }
  }

  /// Find a specific scope's thread (legacy helper — same as
  /// CueReasoningService.findThread). Returns null if no thread
  /// exists yet.
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
      // Client-scoped: explicitly filter goal anchors null so we
      // don't pick up a stale goal-scoped thread.
      if (ltgId == null && stgId == null) {
        query = query.isFilter('ltg_id', null).isFilter('stg_id', null);
      }
      final rows =
          await query.order('updated_at', ascending: false).limit(1);
      if ((rows as List).isEmpty) return null;
      return ReasoningThread.fromJson(
          Map<String, dynamic>.from(rows.first as Map));
    } catch (_) {
      return null;
    }
  }

  /// Load message history for a thread, chronological. RLS scopes
  /// to the current clinician's threads.
  Future<List<ReasoningMessage>> loadHistory(String threadId) async {
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
      throw AskCueException('Could not load thread history.',
          detail: '$e');
    }
  }

  /// Send a user message and stream the assistant response.
  ///
  /// Pass [threadId] to continue an existing thread, or omit for
  /// the edge function to create one keyed to (clinician_id,
  /// client_id, ltg_id, stg_id). For client-scoped threads pass
  /// neither ltgId nor stgId — the post-Phase 5.0 schema allows
  /// both null.
  AskCueStreamResult sendMessage({
    String? threadId,
    required String clientId,
    String? ltgId,
    String? stgId,
    required String userMessage,
    List<String>? domainsActive,
  }) {
    final controller = StreamController<String>();
    final completion = Completer<AskCueCompletion>();

    Future<void>(() async {
      try {
        final body = <String, dynamic>{
          'thread_id':      ?threadId,
          'client_id':      clientId,
          'ltg_id':         ?ltgId,
          'stg_id':         ?stgId,
          'domains_active': ?domainsActive,
          'user_message':   userMessage,
        };

        final response = await _sb.functions.invoke(
          'reasoning-respond',
          body: body,
        );
        final raw = response.data;
        if (response.status >= 400 || raw == null) {
          throw AskCueException(
              'Cue couldn\'t respond (HTTP ${response.status}).');
        }

        final data = (raw is Map<String, dynamic>)
            ? raw
            : Map<String, dynamic>.from(raw as Map);
        final returnedThreadId = (data['thread_id'] ?? '').toString();
        if (returnedThreadId.isEmpty) {
          throw AskCueException('Cue returned no thread id.');
        }

        final assistantRaw = data['message'];
        if (assistantRaw is! Map) {
          throw AskCueException('Cue returned no message body.');
        }
        final assistant = ReasoningMessage.fromJson(
            Map<String, dynamic>.from(assistantRaw));

        // Single-chunk emit per Phase 5.1+5.2 streaming-deferred
        // decision. Real SSE lands in Phase 5.3.
        controller.add(assistant.content);
        await controller.close();

        final citedRaw = data['cited_frameworks'];
        final cited = (citedRaw is List)
            ? citedRaw
                .whereType<Map>()
                .map((m) => FrameworkCitation.fromJson(
                    Map<String, dynamic>.from(m)))
                .toList()
            : <FrameworkCitation>[];

        completion.complete(AskCueCompletion(
          threadId:         returnedThreadId,
          assistantMessage: assistant,
          citedFrameworks:  cited,
          suggestedRevision: data['suggested_revision'] as String?,
        ));
      } catch (e, st) {
        if (!controller.isClosed) {
          controller.addError(e, st);
          await controller.close();
        }
        if (!completion.isCompleted) completion.completeError(e, st);
      }
    });

    return AskCueStreamResult(
      textStream: controller.stream,
      completion: completion.future,
    );
  }
}
