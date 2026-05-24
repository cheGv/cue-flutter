import 'package:cue/models/format_template.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('FormatTemplate.fromJson', () {
    test('maps a full row including nested extracted_template', () {
      final row = <String, dynamic>{
        'id': 'tpl-1',
        'user_id': 'u-1',
        'name': 'AIISH PT',
        'format_type': 'pt_report',
        'source_documents': [
          {
            'filename': 'a.docx',
            'storage_path': 'u-1/tpl-1/a.docx',
            'file_type': 'docx',
            'uploaded_at': '2026-05-23T09:00:00.000Z',
          }
        ],
        'extracted_template': {
          'format_name': 'AIISH PT',
          'format_type': 'pt_report',
          'sections': [
            {
              'name': 'Assessment information',
              'order': 3,
              'length': 'paragraph',
              'numbering': 'Roman',
              'subsections': [
                {
                  'name': 'Linguistic skills',
                  'order': 4,
                  'length': 'table',
                  'numbering': null,
                  'subsections': null,
                  'canonical_map': ['observation', 'metrics'],
                }
              ],
              'canonical_map': ['observation'],
            }
          ],
          'placeholders': ['Client name', 'Age'],
          'voice_register': {
            'common_verbs': ['exhibits', 'demonstrates'],
            'common_phrasings': ['At present, the child...'],
            'sentence_rhythm': 'flowing paragraphs',
            'terminology_preferences': {'clinician': 'clinician'},
          },
          'forbidden_vocabulary_observed': [],
          'extraction_warnings': ['Section names varied across documents'],
        },
        'confirmation_status': 'confirmed',
        'confirmed_at': '2026-05-23T10:00:00.000Z',
        'created_at': '2026-05-23T09:00:00.000Z',
        'updated_at': '2026-05-23T10:00:00.000Z',
        'is_fixture': false,
        'notes': null,
      };

      final t = FormatTemplate.fromJson(row);
      expect(t.id, 'tpl-1');
      expect(t.userId, 'u-1');
      expect(t.formatType, 'pt_report');
      expect(t.isConfirmed, isTrue);
      expect(t.confirmedAt, isNotNull);
      expect(t.sourceDocuments, hasLength(1));
      expect(t.sourceDocuments.first.fileType, 'docx');
      expect(t.sourceDocuments.first.storagePath, 'u-1/tpl-1/a.docx');
      expect(t.extractedTemplate.sections, hasLength(1));
      expect(t.extractedTemplate.sections.first.subsections, hasLength(1));
      expect(t.extractedTemplate.sections.first.subsections.first.name,
          'Linguistic skills');
      expect(t.extractedTemplate.sections.first.subsections.first.canonicalMap,
          containsAll(['observation', 'metrics']));
      expect(t.extractedTemplate.voiceRegister.commonVerbs, contains('exhibits'));
      expect(t.extractedTemplate.extractionWarnings, isNotEmpty);
    });

    test('defensive: empty extracted_template yields an empty template', () {
      final t = FormatTemplate.fromJson({
        'id': 'x',
        'user_id': 'u',
        'name': 'n',
        'format_type': 'other',
        'source_documents': [],
        'extracted_template': {},
        'confirmation_status': 'pending',
        'created_at': '2026-05-23T09:00:00.000Z',
        'updated_at': '2026-05-23T09:00:00.000Z',
      });
      expect(t.extractedTemplate.isEmpty, isTrue);
      expect(t.isConfirmed, isFalse);
      expect(t.sourceDocuments, isEmpty);
    });
  });

  group('ExtractedTemplate schema round-trip', () {
    test('parses the extractor schema and re-emits the same top-level keys', () {
      const schemaKeys = {
        'format_name',
        'format_type',
        'sections',
        'placeholders',
        'voice_register',
        'forbidden_vocabulary_observed',
        'extraction_warnings',
      };
      final et = ExtractedTemplate.fromJson({
        'format_name': 'AIISH PT',
        'format_type': 'pt_report',
        'sections': [
          {
            'name': 'Goals',
            'order': 7,
            'length': 'bulleted list',
            'numbering': 'Roman',
            'subsections': [
              {'name': 'Short-term goals', 'order': 1, 'length': 'bulleted list', 'canonical_map': ['goals']}
            ],
            'canonical_map': ['goals'],
          }
        ],
        'placeholders': ['Client name'],
        'voice_register': {
          'common_verbs': ['demonstrates'],
          'common_phrasings': ['The client demonstrates...'],
          'sentence_rhythm': 'short clinical bullets',
          'terminology_preferences': {'AAC device': 'communication aid'},
        },
        'forbidden_vocabulary_observed': ['poor'],
        'extraction_warnings': [],
      });

      expect(et.sections.first.subsections, hasLength(1));
      expect(et.forbiddenVocabularyObserved, contains('poor'));
      expect(et.voiceRegister.terminologyPreferences['AAC device'],
          'communication aid');

      final back = et.toJson();
      expect(back.keys.toSet(), equals(schemaKeys));
      // recursive subsection survives the round-trip
      final sec = (back['sections'] as List).first as Map<String, dynamic>;
      expect(sec['subsections'], isNotNull);
      expect((sec['subsections'] as List).first['name'], 'Short-term goals');
    });

    test('FormatSection.toJson nulls subsections when empty', () {
      const s = FormatSection(name: 'Summary', order: 4, length: 'paragraph');
      expect(s.toJson()['subsections'], isNull);
    });
  });
}
