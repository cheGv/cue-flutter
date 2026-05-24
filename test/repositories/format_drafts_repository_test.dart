// Phase C — Cue Mirror, Component Two. Contract tests for the draft + lexicon
// repositories: type references, the row-mapping contract (the shape select()
// returns parses correctly), and integration tests gated behind a live
// Supabase (skipped here — exercised manually end-to-end against sandbox).
import 'package:cue/models/format_draft.dart';
import 'package:cue/models/format_template_lexicon_default.dart';
import 'package:cue/repositories/format_drafts_repository.dart';
import 'package:cue/repositories/format_template_lexicon_defaults_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('FormatDraftsRepository — contract', () {
    test('is referenceable as a type', () {
      expect(FormatDraftsRepository, isNotNull);
    });

    test('maps a format_drafts row returned by select()', () {
      final row = <String, dynamic>{
        'id': 'd1',
        'user_id': 'u1',
        'client_id': 'c1',
        'template_id': 't1',
        'date_range_preset': 'all_sessions',
        'draft_sections': [
          {'section_name': 'Summary', 'content': 'x', 'source_claims': [], 'lexicon_swaps': []}
        ],
        'generation_metadata': {'model': 'claude-opus-4-5'},
        'status': 'draft',
        'created_at': '2026-05-25T10:00:00.000Z',
        'updated_at': '2026-05-25T10:00:00.000Z',
        'generated_at': '2026-05-25T10:00:00.000Z',
      };
      final d = FormatDraft.fromJson(row);
      expect(d.id, 'd1');
      expect(d.draftSections.single.sectionName, 'Summary');
      expect(d.status, 'draft');
    });

    test('listForClient excludes archived and returns newest-first',
        () async {}, skip: 'integration');
    test('create persists a draft scoped to auth.uid()', () async {},
        skip: 'integration');
    test('update bumps updated_at and patches fields', () async {},
        skip: 'integration');
    test('delete soft-archives (status = archived)', () async {},
        skip: 'integration');
  });

  group('FormatTemplateLexiconDefaultsRepository — contract', () {
    test('is referenceable as a type', () {
      expect(FormatTemplateLexiconDefaultsRepository, isNotNull);
    });

    test('maps a lexicon-defaults row returned by select()', () {
      final d = FormatTemplateLexiconDefault.fromJson(<String, dynamic>{
        'id': 'lx1',
        'user_id': 'u1',
        'template_id': 't1',
        'forbidden_term': 'poor',
        'replacement_term': 'emerging',
        'decision': 'swap',
      });
      expect(d.forbiddenTerm, 'poor');
      expect(d.isSwap, isTrue);
    });

    test('listForTemplate returns the clinician\'s decisions', () async {},
        skip: 'integration');
    test('upsert writes once per (template_id, forbidden_term)', () async {},
        skip: 'integration');
  });
}
