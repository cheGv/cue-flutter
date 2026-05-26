// Phase D — Cue Mirror Component Three. Contract tests for the sentence repo:
// type reference + the row-mapping contract (the shape select() returns parses
// correctly, defensively). Query integration is gated behind a live Supabase
// (skipped here — exercised manually end-to-end against sandbox), matching the
// Component Two repository-test convention.
import 'package:cue/models/format_draft_sentence.dart';
import 'package:cue/repositories/format_draft_sentences_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('FormatDraftSentencesRepository — contract', () {
    test('is referenceable as a type', () {
      expect(FormatDraftSentencesRepository, isNotNull);
    });

    test('maps a format_draft_sentences row returned by select()', () {
      final s = FormatDraftSentence.fromJson(<String, dynamic>{
        'id': 's1',
        'draft_id': 'd1',
        'section_name': 'History',
        'sentence_order': 2,
        'text': 'The child was brought to the clinic.',
        'text_original': 'The child was brought to the clinic.',
        'status': 'cue_drafted',
        'source_claims': [
          {
            'claim_text': 'brought to the clinic',
            'source_type': 'session',
            'source_id': '1',
            'source_excerpt': 'x'
          }
        ],
        'lexicon_swaps': [],
        'clinician_id': 'u1',
        'template_id': 't1',
        'created_at': '2026-05-27T10:00:00.000Z',
        'updated_at': '2026-05-27T10:00:00.000Z',
      });
      expect(s.id, 's1');
      expect(s.sectionName, 'History');
      expect(s.sentenceOrder, 2);
      expect(s.status, 'cue_drafted');
      expect(s.isCueDrafted, isTrue);
      expect(s.sourceClaims.single.sourceType, 'session');
    });

    test('defensive fromJson tolerates a thin / null-bearing row', () {
      final s = FormatDraftSentence.fromJson(<String, dynamic>{
        'id': 's2',
        'draft_id': 'd1',
        'section_name': 'Summary',
        'sentence_order': 0,
        'text': 'Authored by the clinician.',
        'text_original': 'Authored by the clinician.',
        'status': 'clinician_authored',
        'source_claims': null,
        'lexicon_swaps': null,
        'clinician_id': 'u1',
        'template_id': 't1',
      });
      expect(s.sourceClaims, isEmpty);
      expect(s.lexiconSwaps, isEmpty);
      expect(s.isClinicianAuthored, isTrue);
      expect(s.isEdited, isTrue);
    });

    test('hasUnsavedEdit + displayText reflect an autosaved, uncommitted edit',
        () {
      final s = FormatDraftSentence.fromJson(<String, dynamic>{
        'id': 's3',
        'draft_id': 'd1',
        'section_name': 'Summary',
        'sentence_order': 0,
        'text': 'committed',
        'text_in_progress': 'in progress',
        'text_original': 'committed',
        'status': 'cue_drafted',
        'clinician_id': 'u1',
        'template_id': 't1',
      });
      expect(s.hasUnsavedEdit, isTrue);
      expect(s.displayText, 'in progress');
    });

    test(
        'listForDraft / listForSection / update / create / listEditedForClinician (live)',
        () async {},
        skip: 'integration');
  });
}
