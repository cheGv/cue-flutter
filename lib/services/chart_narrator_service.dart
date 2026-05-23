// Phase B — chart narrator service (Prompt 3, Bundle 2b, PART B1/B4).
//
// Sends CONTEXT ONLY to the proxy's /chart-narrator endpoint — the system
// prompt lives server-side (CLAUDE.md §13). Returns the AI sentence, or null on
// any error (timeout, 404 before deploy, parse error); the narrator widget's
// computed template handles null.
//
// http.Client + tokenProvider are injectable so the service is unit-testable
// without a live Supabase / network.
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

class ChartNarratorService {
  ChartNarratorService({
    http.Client? client,
    Future<String?> Function()? tokenProvider,
    String baseUrl = _defaultBase,
  })  : _client = client ?? http.Client(),
        _tokenProvider = tokenProvider ?? _defaultToken,
        _base = baseUrl;

  static const _defaultBase = 'https://cue-ai-proxy.onrender.com';
  static const _ttl = Duration(minutes: 10);
  static const _timeout = Duration(seconds: 5);

  final http.Client _client;
  final Future<String?> Function() _tokenProvider;
  final String _base;
  final Map<String, _Entry> _cache = {};

  static Future<String?> _defaultToken() async =>
      Supabase.instance.client.auth.currentSession?.accessToken;

  Future<String?> narrate({
    required String clientId,
    required String clientName,
    required Map<String, dynamic> clientState,
    Map<String, dynamic>? focusedStg,
  }) async {
    final payload = <String, dynamic>{
      'client_id': clientId,
      'client_name': clientName,
      'client_state': clientState,
      'focused_stg': focusedStg,
    };

    final key = '$clientId:${jsonEncode(payload).hashCode}';
    final hit = _cache[key];
    if (hit != null && DateTime.now().difference(hit.at) < _ttl) {
      return hit.value;
    }

    final token = await _tokenProvider();
    if (token == null) return null;

    try {
      final resp = await _client
          .post(
            Uri.parse('$_base/chart-narrator'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
            body: jsonEncode(payload),
          )
          .timeout(_timeout);
      if (resp.statusCode != 200) return null;
      final body = jsonDecode(resp.body) as Map<String, dynamic>;
      final text = (body['narrator'] as String?)?.trim();
      if (text == null || text.isEmpty) return null;
      _cache[key] = _Entry(text, DateTime.now());
      return text;
    } catch (_) {
      return null;
    }
  }
}

class _Entry {
  final String value;
  final DateTime at;
  const _Entry(this.value, this.at);
}
