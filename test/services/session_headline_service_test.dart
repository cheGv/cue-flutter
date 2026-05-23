import 'dart:convert';

import 'package:cue/models/session.dart';
import 'package:cue/models/session_outcome.dart';
import 'package:cue/services/session_headline_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Session _sess({int id = 1, String? aiHeadline}) => Session(
      id: id,
      clientId: 'c1',
      clientName: 'Dina',
      createdAt: DateTime(2026, 5, 21),
      date: DateTime(2026, 5, 21),
      outcome: SessionOutcome.progress,
      soapNote: 'Worked on /s/ blends with caregiver scaffolding.',
      aiHeadline: aiHeadline,
    );

void main() {
  test('cache hit (ai_headline present) returns immediately, no HTTP',
      () async {
    var calls = 0;
    final svc = SessionHeadlineService(
      client: MockClient((req) async {
        calls++;
        return http.Response('{}', 200);
      }),
      tokenProvider: () async => 't',
      onGenerated: (_, _) async {},
    );
    final r = await svc.headlineFor(_sess(aiHeadline: 'Cached headline held.'));
    expect(r, 'Cached headline held.');
    expect(calls, 0);
  });

  test('cache miss calls proxy (context-only), parses, writes back', () async {
    Map<String, dynamic>? body;
    int? wroteId;
    String? wroteText;
    final svc = SessionHeadlineService(
      client: MockClient((req) async {
        body = jsonDecode(req.body) as Map<String, dynamic>;
        return http.Response(
          jsonEncode({'headline': 'Co-regulation strategy introduced.'}),
          200,
        );
      }),
      tokenProvider: () async => 't',
      onGenerated: (id, h) async {
        wroteId = id;
        wroteText = h;
      },
    );

    final r = await svc.headlineFor(_sess(id: 7));
    expect(r, 'Co-regulation strategy introduced.');
    expect(wroteId, 7);
    expect(wroteText, 'Co-regulation strategy introduced.');
    expect(body!['session_id'], 7);
    expect(body!.containsKey('soap_note'), isTrue);
    // No system prompt client-side (§13).
    expect(jsonEncode(body).toLowerCase().contains('you are cue'), isFalse);
  });

  test('error returns null and does NOT write back', () async {
    var wrote = false;
    final svc = SessionHeadlineService(
      client: MockClient((req) async => http.Response('err', 500)),
      tokenProvider: () async => 't',
      onGenerated: (_, _) async => wrote = true,
    );
    final r = await svc.headlineFor(_sess(id: 9));
    expect(r, isNull);
    expect(wrote, isFalse);
  });
}
