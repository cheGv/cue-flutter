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

  group('storage upload (requires live Supabase)', () {
    test('uploadSourceDocument writes to {uid}/{templateId}/{filename}',
        () async {}, skip: 'integration');
  });
}
