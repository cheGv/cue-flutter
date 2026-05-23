import 'dart:convert';

import 'package:cue/services/chart_narrator_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

ChartNarratorService _svc(MockClient client,
        {Future<String?> Function()? token}) =>
    ChartNarratorService(
      client: client,
      tokenProvider: token ?? () async => 'test-token',
    );

void main() {
  test('sends context-only payload (no system prompt) and parses narrator',
      () async {
    Map<String, dynamic>? sent;
    final svc = _svc(MockClient((req) async {
      sent = jsonDecode(req.body) as Map<String, dynamic>;
      return http.Response(
        jsonEncode({'narrator': "Dina's long-term goal is still open."}),
        200,
      );
    }));

    final result = await svc.narrate(
      clientId: 'c1',
      clientName: 'Dina',
      clientState: {'ltg_count': 0, 'active_stg_count': 0},
      focusedStg: null,
    );

    expect(result, "Dina's long-term goal is still open.");
    expect(sent!['client_name'], 'Dina');
    expect(sent!.containsKey('client_state'), isTrue);
    // No system prompt leaks client-side (§13).
    expect(sent!.containsKey('system'), isFalse);
    expect(jsonEncode(sent).toLowerCase().contains('you are cue'), isFalse);
  });

  test('caches within TTL — the second call fires no HTTP', () async {
    var calls = 0;
    final svc = _svc(MockClient((req) async {
      calls++;
      return http.Response(jsonEncode({'narrator': 'X.'}), 200);
    }));
    final a = await svc.narrate(
        clientId: 'c1', clientName: 'Dina', clientState: {'ltg_count': 1});
    final b = await svc.narrate(
        clientId: 'c1', clientName: 'Dina', clientState: {'ltg_count': 1});
    expect(a, 'X.');
    expect(b, 'X.');
    expect(calls, 1);
  });

  test('non-200 (e.g. 404 before deploy) returns null', () async {
    final svc = _svc(MockClient((req) async => http.Response('nope', 404)));
    expect(
      await svc.narrate(clientId: 'c1', clientName: 'Dina', clientState: {}),
      isNull,
    );
  });

  test('transport error (same path as timeout) returns null', () async {
    final svc = _svc(MockClient((req) async => throw Exception('down')));
    expect(
      await svc.narrate(clientId: 'c1', clientName: 'Dina', clientState: {}),
      isNull,
    );
  });

  test('null token returns null without calling HTTP', () async {
    var calls = 0;
    final svc = _svc(
      MockClient((req) async {
        calls++;
        return http.Response('{}', 200);
      }),
      token: () async => null,
    );
    expect(
      await svc.narrate(clientId: 'c1', clientName: 'Dina', clientState: {}),
      isNull,
    );
    expect(calls, 0);
  });
}
