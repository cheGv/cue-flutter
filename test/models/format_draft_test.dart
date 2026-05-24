// Phase C — Cue Mirror, Component Two. Model round-trip tests for the draft
// schema (FormatDraft + DraftSection + SourceClaim + LexiconSwap +
// GenerationMetadata) and the lexicon-default model.
import 'package:cue/models/format_draft.dart';
import 'package:cue/models/format_template_lexicon_default.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('FormatDraft.fromJson', () {
    final row = {
      'id': 'd1',
      'user_id': 'u1',
      'client_id': 'c1',
      'template_id': 't1',
      'date_range_start': '2026-04-01T00:00:00.000Z',
      'date_range_end': '2026-05-01T00:00:00.000Z',
      'date_range_preset': 'monthly',
      'draft_sections': [
        {
          'section_name': 'Assessment Information',
          'content': 'The child demonstrates emerging skills¹.',
          'source_claims': [
            {
              'claim_text': 'demonstrates emerging skills',
              'source_type': 'session',
              'source_id': '42',
              'source_excerpt': 'observed sorting by colour',
            }
          ],
          'lexicon_swaps': [
            {
              'original': 'delay',
              'replacement': 'emerging speech and language profile',
              'position_in_content': 12,
            }
          ],
        }
      ],
      'generation_metadata': {
        'model': 'claude-opus-4-5',
        'tokens': {'input_tokens': 1200, 'output_tokens': 800},
        'latency_ms': 4200,
        'template_version_snapshot': {'format_name': 'AIISH PT', 'section_count': 9},
      },
      'status': 'draft',
      'created_at': '2026-05-25T10:00:00.000Z',
      'updated_at': '2026-05-25T10:00:00.000Z',
      'generated_at': '2026-05-25T10:00:00.000Z',
      'is_fixture': false,
    };

    test('maps a full row including nested sections, claims and swaps', () {
      final d = FormatDraft.fromJson(row);
      expect(d.id, 'd1');
      expect(d.clientId, 'c1');
      expect(d.templateId, 't1');
      expect(d.dateRangePreset, 'monthly');
      expect(d.status, 'draft');
      expect(d.draftSections, hasLength(1));

      final s = d.draftSections.first;
      expect(s.sectionName, 'Assessment Information');
      expect(s.sourceClaims.single.sourceType, 'session');
      expect(s.sourceClaims.single.sourceId, '42');
      expect(s.lexiconSwaps.single.original, 'delay');
      expect(s.lexiconSwaps.single.positionInContent, 12);

      expect(d.generationMetadata.model, 'claude-opus-4-5');
      expect(d.generationMetadata.inputTokens, 1200);
      expect(d.generationMetadata.outputTokens, 800);
      expect(d.generationMetadata.latencyMs, 4200);
      expect(d.generationMetadata.templateVersionSnapshot['section_count'], 9);
    });

    test('round-trips through toJson without losing nested structure', () {
      final once = FormatDraft.fromJson(row);
      final twice = FormatDraft.fromJson(once.toJson());
      expect(twice.draftSections.single.sectionName, 'Assessment Information');
      expect(twice.draftSections.single.sourceClaims.single.claimText,
          'demonstrates emerging skills');
      expect(twice.draftSections.single.lexiconSwaps.single.replacement,
          'emerging speech and language profile');
      expect(twice.generationMetadata.inputTokens, 1200);
    });

    test('defensive: missing draft_sections yields an empty section list', () {
      final d = FormatDraft.fromJson({
        'id': 'd2',
        'user_id': 'u1',
        'client_id': 'c1',
        'template_id': 't1',
      });
      expect(d.draftSections, isEmpty);
      expect(d.generationMetadata.model, '');
      expect(d.status, 'draft');
    });

    test('DraftSection.isStaticAuthored detects clinician-authored placeholders',
        () {
      const s = DraftSection(
        sectionName: 'History',
        content: 'To be authored by clinician.',
        sourceClaims: [
          SourceClaim(
              claimText: 'placeholder', sourceType: 'static_clinician_authored'),
        ],
      );
      expect(s.isStaticAuthored, isTrue);
    });
  });

  group('FormatTemplateLexiconDefault', () {
    test('maps a swap decision with a replacement term', () {
      final d = FormatTemplateLexiconDefault.fromJson({
        'id': 'lx1',
        'user_id': 'u1',
        'template_id': 't1',
        'forbidden_term': 'delay',
        'replacement_term': 'emerging speech and language profile',
        'decision': 'swap',
      });
      expect(d.isSwap, isTrue);
      expect(d.replacementTerm, 'emerging speech and language profile');
      // round-trip
      final again = FormatTemplateLexiconDefault.fromJson(d.toJson());
      expect(again.forbiddenTerm, 'delay');
      expect(again.decision, 'swap');
    });

    test('keep_original decision carries no replacement', () {
      final d = FormatTemplateLexiconDefault.fromJson({
        'id': 'lx2',
        'user_id': 'u1',
        'template_id': 't1',
        'forbidden_term': 'delay',
        'decision': 'keep_original',
      });
      expect(d.isSwap, isFalse);
      expect(d.replacementTerm, isNull);
    });
  });
}
