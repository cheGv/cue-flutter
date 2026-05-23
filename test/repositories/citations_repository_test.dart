// Repository tests for CitationsRepository.
//
// No mock library in project. Covers: type existence and the row-mapping
// contract — in particular that Citation.fromJson tolerates the embedded
// `short_term_goals` object that loadCitationsForClient's
// `select('*, short_term_goals!inner(client_id)')` adds to each row.
import 'package:flutter_test/flutter_test.dart';
import 'package:cue/models/citation.dart';
import 'package:cue/repositories/citations_repository.dart';

void main() {
  group('CitationsRepository — interface', () {
    test('class is referenceable as a type', () {
      expect(CitationsRepository, isNotNull);
    });
  });

  group('CitationsRepository — row mapping contract', () {
    test('maps a plain citations row', () {
      final row = <String, dynamic>{
        'id': 'c-1',
        'stg_id': 's-1',
        'tier': 'level_2',
        'finding': 'Co-regulation routines extend therapeutic gains.',
        'author_year': 'Garcia · 2023',
        'source_url': null,
        'display_order': 2,
      };
      final c = Citation.fromJson(row);
      expect(c.stgId, 's-1');
      expect(c.tier, EvidenceTier.level2);
      expect(c.displayOrder, 2);
    });

    test('fromJson ignores the embedded short_term_goals join object', () {
      // Shape returned by loadCitationsForClient's embedded select.
      final joinedRow = <String, dynamic>{
        'id': 'c-2',
        'stg_id': 's-1',
        'tier': 'practice',
        'finding': 'Caregiver coaching efficacy in Indian household contexts.',
        'author_year': 'Patel · 2024',
        'display_order': 3,
        'short_term_goals': {'client_id': 'client-1'},
      };
      final c = Citation.fromJson(joinedRow);
      expect(c.id, 'c-2');
      expect(c.stgId, 's-1');
      expect(c.tier, EvidenceTier.practice);
      expect(c.displayOrder, 3);
    });
  });

  group('CitationsRepository — integration (requires live Supabase)', () {
    test('loadCitationsForStg returns rows in display order', () async {},
        skip: 'integration');
    test('loadCitationsForClient joins through short_term_goals', () async {},
        skip: 'integration');
  });
}
