// Phase C — Cue Mirror, Component Two. Service tests for FormatDrafterService:
//  • requestDraft posts {template_id, client_id, date_range, locked_template,
//    lexicon_defaults, canonical_data} and leaks NO prompt client-side (§13).
//  • the proxy response is parsed and persisted via FormatDraftsRepository.
//  • assembleCanonicalContext pulls from every canonical repository.
//  • a non-200 surfaces the server error as FormatDrafterException.
//
// Repositories are injected as implements-based fakes (no Supabase.instance is
// touched at construction). The proxy is a MockClient — no live network.
import 'dart:convert';

import 'package:cue/models/citation.dart';
import 'package:cue/models/client_chart_state.dart';
import 'package:cue/models/format_draft.dart';
import 'package:cue/models/format_template.dart';
import 'package:cue/models/format_template_lexicon_default.dart';
import 'package:cue/models/session.dart';
import 'package:cue/models/short_term_goal.dart';
import 'package:cue/models/stg_session_metric.dart';
import 'package:cue/models/substrate.dart';
import 'package:cue/repositories/citations_repository.dart';
import 'package:cue/repositories/client_chart_state_repository.dart';
import 'package:cue/repositories/format_drafts_repository.dart';
import 'package:cue/repositories/format_template_lexicon_defaults_repository.dart';
import 'package:cue/repositories/format_templates_repository.dart';
import 'package:cue/repositories/ltg_repository.dart';
import 'package:cue/repositories/sessions_repository.dart';
import 'package:cue/repositories/stg_metrics_repository.dart';
import 'package:cue/repositories/stg_repository.dart';
import 'package:cue/repositories/substrate_repository.dart';
import 'package:cue/services/format_drafter_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

// ── Fakes ─────────────────────────────────────────────────────────────────
class _FakeTemplatesRepo implements FormatTemplatesRepository {
  @override
  Future<FormatTemplate?> get(String id) async => FormatTemplate(
        id: id,
        userId: 'u1',
        name: 'AIISH',
        formatType: 'pt_report',
        sourceDocuments: const [],
        extractedTemplate: const ExtractedTemplate(
          formatName: 'AIISH PT',
          formatType: 'pt_report',
          sections: [
            FormatSection(name: 'Summary', canonicalMap: ['observation']),
          ],
          forbiddenVocabularyObserved: ['delay'],
        ),
        confirmationStatus: 'confirmed',
        createdAt: DateTime(2026, 5, 25),
        updatedAt: DateTime(2026, 5, 25),
      );
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _FakeDraftsRepo implements FormatDraftsRepository {
  List<dynamic>? capturedSections;
  Map<String, dynamic>? capturedMeta;
  String? capturedClientId;
  String? capturedPreset;

  @override
  Future<FormatDraft> create({
    required String clientId,
    required String templateId,
    required List<dynamic> draftSections,
    required Map<String, dynamic> generationMetadata,
    String? dateRangePreset,
    DateTime? dateRangeStart,
    DateTime? dateRangeEnd,
    String status = 'draft',
  }) async {
    capturedSections = draftSections;
    capturedMeta = generationMetadata;
    capturedClientId = clientId;
    capturedPreset = dateRangePreset;
    return FormatDraft.fromJson({
      'id': 'persisted-1',
      'user_id': 'u1',
      'client_id': clientId,
      'template_id': templateId,
      'draft_sections': draftSections,
      'generation_metadata': generationMetadata,
      'status': status,
    });
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _FakeLexiconRepo implements FormatTemplateLexiconDefaultsRepository {
  @override
  Future<List<FormatTemplateLexiconDefault>> listForTemplate(
          String templateId) async =>
      [
        FormatTemplateLexiconDefault(
          id: 'lx1',
          userId: 'u1',
          templateId: templateId,
          forbiddenTerm: 'delay',
          decision: 'swap',
          replacementTerm: 'emerging speech and language profile',
        ),
      ];
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _FakeSessionsRepo implements SessionsRepository {
  bool called = false;
  @override
  Future<List<Session>> loadForClientFiltered(String clientId,
      {DateTime? after,
      DateTime? before,
      String? searchQuery,
      bool includePlanned = false}) async {
    called = true;
    return <Session>[];
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _FakeSubstrateRepo implements SubstrateRepository {
  bool called = false;
  @override
  Future<List<SubstrateCell>> loadCellsForClient(String clientId) async {
    called = true;
    return <SubstrateCell>[];
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _FakeLtgRepo implements LtgRepository {
  bool called = false;
  @override
  Future<List<Map<String, dynamic>>> listForClient(String clientId) async {
    called = true;
    return <Map<String, dynamic>>[];
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _FakeStgRepo implements StgRepository {
  bool called = false;
  @override
  Future<List<ShortTermGoal>> listForClient(String clientId) async {
    called = true;
    return <ShortTermGoal>[];
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _FakeCitationsRepo implements CitationsRepository {
  bool called = false;
  @override
  Future<List<Citation>> loadCitationsForClient(String clientId) async {
    called = true;
    return <Citation>[];
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _FakeMetricsRepo implements StgMetricsRepository {
  @override
  Future<List<StgSessionMetric>> loadMetricsForStg(String stgId) async =>
      <StgSessionMetric>[];
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _FakeChartStateRepo implements ClientChartStateRepository {
  bool called = false;
  @override
  Future<ClientChartState?> loadForClient(String clientId) async {
    called = true;
    return null;
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

// Build a service whose only live edge is the injected MockClient.
FormatDrafterService _svc(
  http.Client client, {
  _FakeDraftsRepo? drafts,
  _FakeSessionsRepo? sessions,
  _FakeSubstrateRepo? substrate,
  _FakeLtgRepo? ltg,
  _FakeStgRepo? stg,
  _FakeCitationsRepo? citations,
  _FakeChartStateRepo? chartState,
}) =>
    FormatDrafterService(
      client: client,
      tokenProvider: () async => 'test-jwt',
      baseUrl: 'https://proxy.test',
      templatesRepository: _FakeTemplatesRepo(),
      draftsRepository: drafts ?? _FakeDraftsRepo(),
      lexiconRepository: _FakeLexiconRepo(),
      sessionsRepository: sessions ?? _FakeSessionsRepo(),
      substrateRepository: substrate ?? _FakeSubstrateRepo(),
      ltgRepository: ltg ?? _FakeLtgRepo(),
      stgRepository: stg ?? _FakeStgRepo(),
      citationsRepository: citations ?? _FakeCitationsRepo(),
      metricsRepository: _FakeMetricsRepo(),
      chartStateRepository: chartState ?? _FakeChartStateRepo(),
    );

void main() {
  test(
      'requestDraft posts the locked template + canonical data with NO prompt (§13), parses + persists',
      () async {
    late Map<String, dynamic> sentBody;
    late String sentPath;
    final mock = MockClient((req) async {
      sentPath = req.url.path;
      sentBody = jsonDecode(req.body) as Map<String, dynamic>;
      return http.Response(
        jsonEncode({
          'draft_sections': [
            {
              'section_name': 'Summary',
              'content': 'The child demonstrates emerging skills.',
              'source_claims': [
                {'claim_text': 'demonstrates emerging skills', 'source_type': 'session', 'source_id': '1', 'source_excerpt': 'x'}
              ],
              'lexicon_swaps': [],
            }
          ],
          'generation_metadata': {
            'model': 'claude-opus-4-5',
            'tokens': {'input_tokens': 100, 'output_tokens': 50},
            'latency_ms': 1234,
          },
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });

    final drafts = _FakeDraftsRepo();
    final draft = await _svc(mock, drafts: drafts).requestDraft(
      templateId: 't1',
      clientId: 'c1',
      preset: 'all_sessions',
    );

    // Right endpoint.
    expect(sentPath, '/format-draft');
    // §13: the client sends references + data, never a prompt.
    expect(sentBody.containsKey('prompt'), isFalse);
    expect(sentBody.containsKey('system'), isFalse);
    expect(sentBody.containsKey('system_prompt'), isFalse);
    // Required payload shape.
    expect(sentBody['template_id'], 't1');
    expect(sentBody['client_id'], 'c1');
    expect(sentBody['locked_template'], isA<Map>());
    expect(sentBody['lexicon_defaults'], isA<List>());
    expect((sentBody['lexicon_defaults'] as List).first['forbidden_term'], 'delay');
    expect(sentBody['canonical_data'], isA<Map>());
    // locked_template carries the extractor schema's keys.
    expect((sentBody['locked_template'] as Map)['format_name'], 'AIISH PT');

    // Response parsed into the persisted draft.
    expect(draft.id, 'persisted-1');
    expect(draft.draftSections.single.sectionName, 'Summary');
    expect(draft.generationMetadata.model, 'claude-opus-4-5');
    // Persisted with the proxy's sections + metadata + preset.
    expect(drafts.capturedClientId, 'c1');
    expect(drafts.capturedPreset, 'all_sessions');
    expect(drafts.capturedSections, isNotNull);
    expect(drafts.capturedMeta?['model'], 'claude-opus-4-5');
  });

  test('assembleCanonicalContext pulls from every canonical repository', () async {
    final mock = MockClient((req) async => http.Response('{}', 200));
    final sessions = _FakeSessionsRepo();
    final substrate = _FakeSubstrateRepo();
    final ltg = _FakeLtgRepo();
    final stg = _FakeStgRepo();
    final citations = _FakeCitationsRepo();
    final chartState = _FakeChartStateRepo();

    final ctx = await _svc(
      mock,
      sessions: sessions,
      substrate: substrate,
      ltg: ltg,
      stg: stg,
      citations: citations,
      chartState: chartState,
    ).assembleCanonicalContext('c1');

    // Every canonical key present.
    for (final k in [
      'client_meta',
      'substrate_cells',
      'long_term_goals',
      'short_term_goals',
      'sessions',
      'citations',
      'metrics',
    ]) {
      expect(ctx.containsKey(k), isTrue, reason: 'missing $k');
    }
    // Each unconditional repository was queried.
    expect(sessions.called, isTrue);
    expect(substrate.called, isTrue);
    expect(ltg.called, isTrue);
    expect(stg.called, isTrue);
    expect(citations.called, isTrue);
    expect(chartState.called, isTrue);
  });

  test('non-200 surfaces the server error as FormatDrafterException', () async {
    final mock = MockClient((req) async => http.Response(
        jsonEncode({'error': 'Anthropic upstream failure'}), 502));
    expect(
      () => _svc(mock).requestDraft(
          templateId: 't1', clientId: 'c1', preset: 'monthly'),
      throwsA(isA<FormatDrafterException>()),
    );
  });

  test(
      'exportDraft posts {draft_id, format} with NO prompt (§13) and parses signed_url + filename',
      () async {
    late String sentPath;
    String? sentAuth;
    late Map<String, dynamic> sentBody;
    final mock = MockClient((req) async {
      sentPath = req.url.path;
      sentAuth = req.headers['Authorization'];
      sentBody = jsonDecode(req.body) as Map<String, dynamic>;
      return http.Response(
        jsonEncode({
          'signed_url': 'https://signed.example/report.docx?token=abc',
          'filename': 'Asha_AIISH PT_2026-05-24.docx',
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });

    final result = await _svc(mock).exportDraft(draftId: 'd1');

    expect(sentPath, '/format-draft-export');
    expect(sentAuth, 'Bearer test-jwt');
    expect(sentBody, {'draft_id': 'd1', 'format': 'docx'});
    // §13: the client sends only references, never a prompt.
    expect(sentBody.containsKey('prompt'), isFalse);
    expect(sentBody.containsKey('system'), isFalse);
    expect(sentBody.containsKey('system_prompt'), isFalse);
    // Response parsed into (signedUrl, filename).
    expect(result.signedUrl, 'https://signed.example/report.docx?token=abc');
    expect(result.filename, 'Asha_AIISH PT_2026-05-24.docx');
  });

  test('exportDraft surfaces a non-200 as FormatDrafterException', () async {
    final mock = MockClient((req) async => http.Response(
        jsonEncode({'error': 'Draft not found or access denied'}), 404));
    expect(
      () => _svc(mock).exportDraft(draftId: 'missing'),
      throwsA(isA<FormatDrafterException>()),
    );
  });

  test('exportDraft throws when the response carries no download link',
      () async {
    final mock = MockClient(
        (req) async => http.Response(jsonEncode({'filename': 'x.docx'}), 200));
    expect(
      () => _svc(mock).exportDraft(draftId: 'd1'),
      throwsA(isA<FormatDrafterException>()),
    );
  });
}
