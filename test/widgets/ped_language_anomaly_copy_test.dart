// test/widgets/ped_language_anomaly_copy_test.dart
//
// The capture-entry statement's WORDS. Pure and top-level so the copy is
// pinned without mounting the surface (which would need a Supabase seam
// it does not have — see the commit note).
//
// Design law: state the fact, name the repair. No apology, and no
// narrating the tool's own carefulness.

import 'package:flutter_test/flutter_test.dart';

import 'package:cue/widgets/assessment/ped_language_capture_surface.dart';

void main() {
  group('anomaly line', () {
    test('names the section, the count, and the repair', () {
      final line = pedLanguageAnomalyLine('Speech', 2);
      expect(line, contains('Speech'));
      expect(line, contains('2 milestones'));
      expect(line, contains('Re-run Done'));
    });

    test('singular reads correctly', () {
      final line = pedLanguageAnomalyLine('Literacy', 1);
      expect(line, contains('1 milestone in it'));
      expect(line, isNot(contains('milestones')));
    });

    test('uses the surface\'s own vocabulary — "milestone", not the shared '
        'gate\'s neutral "item"', () {
      expect(pedLanguageAnomalyLine('Speech', 3), contains('milestone'));
      expect(pedLanguageAnomalyLine('Speech', 3), isNot(contains('item')));
    });

    test('no apology, no restraint-narration, no hedging', () {
      final line = pedLanguageAnomalyLine('Language', 4).toLowerCase();
      for (final banned in [
        'sorry',
        'unfortunately',
        'apolog',
        'we never',
        'cue does not',
        'to be safe',
        'out of caution',
      ]) {
        expect(line, isNot(contains(banned)), reason: banned);
      }
    });

    test('states it as fact — the section IS marked done and the rows did '
        'NOT save', () {
      final line = pedLanguageAnomalyLine('Speech', 2);
      expect(line, contains('marked done'));
      expect(line, contains('never saved'));
    });
  });

  group('section labels are one source', () {
    test('the surface exports its labels so a refusal elsewhere can name '
        'the section instead of printing an internal key', () {
      expect(kPedLanguageSectionLabels['speech'], 'Speech');
      expect(kPedLanguageSectionLabels['language'], 'Language');
      expect(kPedLanguageSectionLabels['literacy'], 'Literacy');
      expect(kPedLanguageSectionLabels.length, 3);
    });
  });
}
