// Phase B — session headline service (Prompt 3, Bundle 2b, PART B2/B5).
//
// Cache-first: returns sessions.ai_headline immediately when present (no call).
// Otherwise sends CONTEXT ONLY to the proxy's /session-headline endpoint
// (prompt is server-side, §13), writes the result back to ai_headline, and
// returns it. Returns null on any error — the display layer falls back to
// soap/notes → "Session on {date}".
//
// Lazy queue: calls are serialized with 200ms spacing (max 1 in-flight), so
// rendering N rows fires N sequential calls, not N parallel ones.
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart' hide Session;

import '../models/session.dart';
import '../repositories/sessions_repository.dart';

class SessionHeadlineService {
  SessionHeadlineService({
    http.Client? client,
    Future<String?> Function()? tokenProvider,
    Future<void> Function(int sessionId, String headline)? onGenerated,
    String baseUrl = _defaultBase,
  })  : _client = client ?? http.Client(),
        _tokenProvider = tokenProvider ?? _defaultToken,
        _onGenerated = onGenerated ?? _defaultWriteBack,
        _base = baseUrl;

  static const _defaultBase = 'https://cue-ai-proxy.onrender.com';
  static const _timeout = Duration(seconds: 5);
  static const _spacing = Duration(milliseconds: 200);

  final http.Client _client;
  final Future<String?> Function() _tokenProvider;
  final Future<void> Function(int sessionId, String headline) _onGenerated;
  final String _base;

  // Serial queue tail — each request chains off the previous.
  Future<void> _chain = Future<void>.value();

  static Future<String?> _defaultToken() async =>
      Supabase.instance.client.auth.currentSession?.accessToken;

  static Future<void> _defaultWriteBack(int id, String headline) =>
      SessionsRepository().updateAiHeadline(id, headline);

  /// The cached headline immediately if present; otherwise a lazily-queued
  /// proxy generation (written back on success). Null on any error.
  Future<String?> headlineFor(Session session) {
    final cached = session.aiHeadline?.trim();
    if (cached != null && cached.isNotEmpty) return Future.value(cached);
    return _enqueue(() => _generate(session));
  }

  Future<T> _enqueue<T>(Future<T> Function() task) {
    final next = _chain.then((_) => task());
    // Keep the chain alive even if a task throws.
    _chain = next.then((_) {}, onError: (_) {});
    return next;
  }

  Future<String?> _generate(Session s) async {
    await Future<void>.delayed(_spacing);
    final token = await _tokenProvider();
    if (token == null) return null;

    final payload = <String, dynamic>{
      'session_id': s.id,
      'client_name': s.clientName,
      'session_date':
          (s.date ?? s.createdAt).toIso8601String().split('T').first,
      'soap_note': s.soapNote,
      'notes': s.notes,
      'outcome': s.outcome?.toDbValue(),
      'next_session_focus': s.nextSessionFocus,
    };

    try {
      final resp = await _client
          .post(
            Uri.parse('$_base/session-headline'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
            body: jsonEncode(payload),
          )
          .timeout(_timeout);
      if (resp.statusCode != 200) return null;
      final body = jsonDecode(resp.body) as Map<String, dynamic>;
      final text = (body['headline'] as String?)?.trim();
      if (text == null || text.isEmpty) return null;
      try {
        await _onGenerated(s.id, text);
      } catch (_) {
        // Write-back is best-effort; still surface the generated headline.
      }
      return text;
    } catch (_) {
      return null;
    }
  }
}
