import 'dart:convert';

import 'package:cue/models/format_template.dart';
import 'package:cue/services/format_extractor_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

FormatExtractorService _svc(MockClient client) => FormatExtractorService(
      client: client,
      tokenProvider: () async => 'test-token',
      // Inject the signer so requestExtraction needs no live Supabase storage.
      signedUrlProvider: (path) async => 'https://signed.example/$path',
    );

const _doc = SourceDocument(
  filename: 'a.docx',
  storagePath: 'u-1/tpl-1/a.docx',
  fileType: 'docx',
);

void main() {
  group('requestExtraction', () {
    test('posts {template_id, files[...]} with signed urls; parses template + '
        'warnings; no prompt leaks client-side (§13)', () async {
      Map<String, dynamic>? sent;
      String? url;
      final svc = _svc(MockClient((req) async {
        url = req.url.toString();
        sent = jsonDecode(req.body) as Map<String, dynamic>;
        return http.Response(
          jsonEncode({
            'extracted_template': {
              'format_name': 'AIISH PT',
              'format_type': 'pt_report',
              'sections': [
                {
                  'name': 'Background information',
                  'order': 1,
                  'length': 'table',
                  'numbering': 'Roman',
                  'subsections': null,
                  'canonical_map': ['static_clinician_authored'],
                }
              ],
              'placeholders': ['Client name', 'Registration number'],
              'voice_register': {
                'common_verbs': ['exhibits'],
                'common_phrasings': ['At present, the child...'],
                'sentence_rhythm': 'flowing paragraphs',
                'terminology_preferences': {},
              },
              'forbidden_vocabulary_observed': [],
              'extraction_warnings': [],
            },
            'extraction_warnings': ['Section names varied'],
            'raw_text_per_document': ['<h1>I. Background</h1>'],
          }),
          200,
        );
      }));

      final res = await svc.requestExtraction(
        templateId: 'tpl-1',
        sourceDocuments: const [_doc],
      );

      expect(url, endsWith('/format-extract'));
      expect(sent!['template_id'], 'tpl-1');
      final files = sent!['files'] as List;
      expect(files, hasLength(1));
      final f = files.first as Map<String, dynamic>;
      expect(f['filename'], 'a.docx');
      expect(f['file_type'], 'docx');
      expect(f['storage_path'], 'u-1/tpl-1/a.docx');
      expect(f['signed_url'], 'https://signed.example/u-1/tpl-1/a.docx');

      expect(res.template.formatName, 'AIISH PT');
      expect(res.template.formatType, 'pt_report');
      expect(res.template.sections.single.canonicalMap,
          contains('static_clinician_authored'));
      expect(res.template.placeholders, contains('Registration number'));
      expect(res.warnings, contains('Section names varied'));

      // §13 — the client never sends a system prompt.
      expect(sent!.containsKey('system'), isFalse);
      expect(jsonEncode(sent).toLowerCase().contains('you are cue'), isFalse);
    });

    test('non-200 surfaces the server error message as an exception', () async {
      final svc = _svc(MockClient((req) async =>
          http.Response(jsonEncode({'error': 'No readable documents'}), 422)));
      expect(
        () => svc.requestExtraction(templateId: 'tpl-1', sourceDocuments: const [_doc]),
        throwsA(isA<FormatExtractorException>()
            .having((e) => e.message, 'message', contains('No readable documents'))),
      );
    });
  });

  group('confirmTemplate', () {
    test('posts {template_id, confirmed_template} and parses confirmed_at',
        () async {
      Map<String, dynamic>? sent;
      String? url;
      final svc = _svc(MockClient((req) async {
        url = req.url.toString();
        sent = jsonDecode(req.body) as Map<String, dynamic>;
        return http.Response(
          jsonEncode({'template_id': 'tpl-1', 'confirmed_at': '2026-05-23T10:00:00Z'}),
          200,
        );
      }));

      final at = await svc.confirmTemplate(
        templateId: 'tpl-1',
        confirmedTemplate: const ExtractedTemplate(
          formatName: 'AIISH PT',
          formatType: 'pt_report',
          sections: [FormatSection(name: 'Background information', order: 1, length: 'table')],
          placeholders: ['Client name'],
        ),
      );

      expect(url, endsWith('/format-confirm'));
      expect(sent!['template_id'], 'tpl-1');
      final ct = sent!['confirmed_template'] as Map<String, dynamic>;
      expect(ct['format_name'], 'AIISH PT');
      expect(ct.containsKey('sections'), isTrue);
      expect(ct.containsKey('voice_register'), isTrue);
      expect(at, isNotNull);
      expect(jsonEncode(sent).toLowerCase().contains('you are cue'), isFalse);
    });

    test('non-200 throws FormatExtractorException', () async {
      final svc = _svc(MockClient((req) async =>
          http.Response(jsonEncode({'error': 'Template not found'}), 404)));
      expect(
        () => svc.confirmTemplate(
          templateId: 'tpl-x',
          confirmedTemplate: const ExtractedTemplate(formatName: 'x', formatType: 'other'),
        ),
        throwsA(isA<FormatExtractorException>()),
      );
    });
  });

  group('requestGeometryExtraction', () {
    test('posts docx files to /format-extract-v2; parses geometry summary; '
        'no prompt leaks (§13)', () async {
      Map<String, dynamic>? sent;
      String? url;
      final svc = _svc(MockClient((req) async {
        url = req.url.toString();
        sent = jsonDecode(req.body) as Map<String, dynamic>;
        return http.Response(
          jsonEncode({
            'template_id': 'tpl-1',
            'geometry': {
              'page_setup': {'width': 16839, 'height': 11907, 'orientation': 'landscape'},
              'default_font': {'family': 'Cambria', 'size': 24},
              'counts': {'tables': 2, 'images': 0, 'main_table_columns': 9},
              'media': [],
            },
          }),
          200,
        );
      }));

      final res = await svc.requestGeometryExtraction(
        templateId: 'tpl-1',
        sourceDocuments: const [_doc],
      );

      expect(url, endsWith('/format-extract-v2'));
      expect(sent!['template_id'], 'tpl-1');
      expect(sent!['files'] as List, hasLength(1));
      expect(res.orientation, 'landscape');
      expect(res.tables, 2);
      expect(res.images, 0);
      expect(res.mainTableColumns, 9);
      expect(res.defaultFont['family'], 'Cambria');
      expect(sent!.containsKey('system'), isFalse);
    });

    test('skips non-docx sources; throws when no .docx is present', () async {
      final svc = _svc(MockClient((req) async => http.Response('{}', 200)));
      const pdf =
          SourceDocument(filename: 'a.pdf', storagePath: 'u/t/a.pdf', fileType: 'pdf');
      expect(
        () => svc.requestGeometryExtraction(
            templateId: 'tpl-1', sourceDocuments: const [pdf]),
        throwsA(isA<FormatExtractorException>()
            .having((e) => e.message, 'message', contains('.docx'))),
      );
    });

    test('non-200 surfaces the server error', () async {
      final svc = _svc(MockClient((req) async => http.Response(
          jsonEncode({'error': 'Could not parse document geometry'}), 422)));
      expect(
        () => svc.requestGeometryExtraction(
            templateId: 'tpl-1', sourceDocuments: const [_doc]),
        throwsA(isA<FormatExtractorException>().having(
            (e) => e.message, 'message', contains('parse document geometry'))),
      );
    });
  });

  group('renderMirrorTest', () {
    test('posts {template_id} to /format-mirror-render; parses signed url + summary',
        () async {
      Map<String, dynamic>? sent;
      String? url;
      final svc = _svc(MockClient((req) async {
        url = req.url.toString();
        sent = jsonDecode(req.body) as Map<String, dynamic>;
        return http.Response(
          jsonEncode({
            'signed_url': 'https://signed.example/mirror.docx',
            'filename': 'Vrishin LP_mirror_2026-05-27.docx',
            'geometry_summary': {
              'page_setup': {'orientation': 'landscape'},
              'counts': {'tables': 2, 'images': 0},
            },
          }),
          200,
        );
      }));

      final res = await svc.renderMirrorTest(templateId: 'tpl-1');
      expect(url, endsWith('/format-mirror-render'));
      expect(sent!['template_id'], 'tpl-1');
      expect(sent!.containsKey('client_name_swap'), isFalse);
      expect(res.signedUrl, 'https://signed.example/mirror.docx');
      expect(res.filename, contains('mirror'));
      expect((res.summary['counts'] as Map)['tables'], 2);
    });

    test('includes client_name_swap when both from + to are provided', () async {
      Map<String, dynamic>? sent;
      final svc = _svc(MockClient((req) async {
        sent = jsonDecode(req.body) as Map<String, dynamic>;
        return http.Response(
            jsonEncode({'signed_url': 'x', 'filename': 'f.docx'}), 200);
      }));
      await svc.renderMirrorTest(templateId: 'tpl-1', swapFrom: 'Vrishin', swapTo: 'Asha');
      final swap = sent!['client_name_swap'] as Map<String, dynamic>;
      expect(swap['from'], 'Vrishin');
      expect(swap['to'], 'Asha');
    });

    test('non-200 throws FormatExtractorException', () async {
      final svc = _svc(MockClient((req) async => http.Response(
          jsonEncode({'error': 'This template has no geometry yet'}), 422)));
      expect(
        () => svc.renderMirrorTest(templateId: 'tpl-1'),
        throwsA(isA<FormatExtractorException>()),
      );
    });
  });

  group('requestSlotIdentification', () {
    test('posts {template_id} to /format-identify-slots; resolves on 200', () async {
      Map<String, dynamic>? sent;
      String? url;
      final svc = _svc(MockClient((req) async {
        url = req.url.toString();
        sent = jsonDecode(req.body) as Map<String, dynamic>;
        return http.Response(
          jsonEncode({'template_id': 'tpl-1', 'slot_map': {'slot_count': 5, 'slots': []}}),
          200,
        );
      }));
      await svc.requestSlotIdentification(templateId: 'tpl-1');
      expect(url, endsWith('/format-identify-slots'));
      expect(sent!['template_id'], 'tpl-1');
    });

    test('non-200 surfaces the server error (not swallowed)', () async {
      final svc = _svc(MockClient((req) async => http.Response(
          jsonEncode({'error': 'Slot identification failed: model overloaded'}), 502)));
      expect(
        () => svc.requestSlotIdentification(templateId: 'tpl-1'),
        throwsA(isA<FormatExtractorException>().having(
            (e) => e.message, 'message', contains('Slot identification failed'))),
      );
    });
  });

  group('storage upload (requires live Supabase)', () {
    test('uploadSourceDocument writes to {uid}/{templateId}/{filename}',
        () async {}, skip: 'integration');
  });
}
