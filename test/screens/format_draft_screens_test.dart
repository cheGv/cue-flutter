// Phase C — Cue Mirror, Component Two (Format Drafter) screen coverage.
//
// Full pumpable rendering of these screens loads data through the Supabase
// client (repositories / drafter service), so live-rendering tests are skipped
// here — consistent with the Phase B / Component One convention in
// test/screens/format_screens_test.dart (screen-level behaviour is covered by
// skipped integration tests; widgets/units carry the assertions). Schema-level
// validation lives in test/models/format_draft_test.dart.

import 'package:cue/constants/cue_lexicon.dart';
import 'package:cue/screens/format_draft_initiate_screen.dart';
import 'package:cue/screens/format_draft_view_screen.dart';
import 'package:cue/screens/format_lexicon_defaults_screen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Cue neutral-replacement lexicon', () {
    test('every curated forbidden term maps to a neutral replacement', () {
      for (final entry in kCueNeutralReplacements.entries) {
        expect(entry.value.trim(), isNotEmpty);
        // §language-discipline — the neutral replacement itself must not reuse
        // the deficit-style term it replaces.
        expect(entry.value.toLowerCase().contains(entry.key.toLowerCase()),
            isFalse,
            reason: 'replacement for "${entry.key}" must be neutral');
      }
    });

    test('cueNeutralReplacement is case-insensitive and falls back', () {
      expect(cueNeutralReplacement('delay'),
          kCueNeutralReplacements['delay']);
      expect(cueNeutralReplacement('DELAY'),
          kCueNeutralReplacements['delay']);
      expect(cueNeutralReplacement('Not Achieved'),
          kCueNeutralReplacements['not achieved']);
      expect(cueNeutralReplacement('a-word-cue-never-curated'),
          'a neutral description');
    });
  });

  group('Format-drafter screens are referenceable as types', () {
    test('initiate + lexicon + view screens compile and are referenceable', () {
      expect(FormatDraftInitiateScreen, isNotNull);
      expect(FormatLexiconDefaultsScreen, isNotNull);
      expect(FormatDraftViewScreen, isNotNull);
    });

    test('view screen mode flag derives from draftId', () {
      const generate = FormatDraftViewScreen(clientId: 'c1');
      const stored = FormatDraftViewScreen(clientId: 'c1', draftId: 'd1');
      expect(generate.isGenerateMode, isTrue);
      expect(stored.isGenerateMode, isFalse);
    });
  });

  group('Format-drafter screens — render (require Supabase mocks)', () {
    test('FormatDraftInitiateScreen renders template + date-range selectors',
        () async {},
        skip: 'requires Supabase client mock');
    test('FormatLexiconDefaultsScreen renders one swap/keep choice per term',
        () async {},
        skip: 'requires Supabase client mock');
    test('FormatDraftViewScreen renders sections, source footnotes, and '
        'language-adjusted rows', () async {},
        skip: 'requires Supabase client mock');
    test(
        'FormatDraftViewScreen action bar shows an "Export to Word" primary '
        'button, enabled for draft|reviewed, that calls exportDraft on tap',
        () async {},
        skip: 'requires Supabase client mock (full-screen pump); the export '
            'call path is covered in '
            'test/services/format_drafter_service_test.dart');
  });

  group('Integration smoke (requires live proxy + Supabase)', () {
    // Generate a draft for Aarav with the confirmed AIISH template and expect
    // draft_sections to validate against the FormatDraft schema.
    test(
        'generate draft for Aarav (25f4d2e8-e0e5-4a5c-981b-132d40db77ca) '
        'with the confirmed AIISH template → draft_sections validate',
        () async {},
        skip: 'integration');
    test(
        'export a reviewed draft → .docx lands in format_draft_exports and a '
        'signed URL downloads it',
        () async {},
        skip: 'integration');
  });
}
