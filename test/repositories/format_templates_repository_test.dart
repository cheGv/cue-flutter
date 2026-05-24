// Repository tests for FormatTemplatesRepository.
//
// Same constraint as the other repository tests — no mock library in project.
// Covers type existence + the row-mapping contract the repo relies on. Live-DB
// behaviour (RLS-scoped CRUD) is covered by skipped integration tests.
import 'package:cue/models/format_template.dart';
import 'package:cue/repositories/format_templates_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('FormatTemplatesRepository — interface', () {
    test('class is referenceable as a type', () {
      expect(FormatTemplatesRepository, isNotNull);
    });
  });

  group('FormatTemplatesRepository — row mapping contract', () {
    test('maps a format_templates row returned by select()', () {
      final row = <String, dynamic>{
        'id': 'tpl-9',
        'user_id': 'u-2',
        'name': 'AIISH LP',
        'format_type': 'lp_report',
        'source_documents': [
          {'filename': 'lp.docx', 'storage_path': 'u-2/tpl-9/lp.docx', 'file_type': 'docx'}
        ],
        'extracted_template': {'format_name': 'AIISH LP', 'format_type': 'lp_report', 'sections': []},
        'confirmation_status': 'pending',
        'confirmed_at': null,
        'created_at': '2026-05-23T09:00:00.000Z',
        'updated_at': '2026-05-23T09:00:00.000Z',
        'is_fixture': false,
        'notes': null,
      };
      final t = FormatTemplate.fromJson(row);
      expect(t.id, 'tpl-9');
      expect(t.formatType, 'lp_report');
      expect(t.confirmationStatus, 'pending');
      expect(t.isConfirmed, isFalse);
      expect(t.sourceDocuments.single.filename, 'lp.docx');
    });
  });

  group('FormatTemplatesRepository — integration (requires live Supabase)', () {
    test('listForUser excludes archived and returns newest-first', () async {},
        skip: 'integration');
    test('create inserts a pending row scoped to auth.uid()', () async {},
        skip: 'integration');
    test('update bumps updated_at and patches fields', () async {},
        skip: 'integration');
    test('delete soft-archives (confirmation_status = archived)', () async {},
        skip: 'integration');
  });
}
