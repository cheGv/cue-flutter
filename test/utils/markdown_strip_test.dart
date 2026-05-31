import 'package:cue/utils/markdown_strip.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('stripInlineMarkdown', () {
    test('strips single-asterisk italics', () {
      expect(stripInlineMarkdown('*italic*'), 'italic');
    });

    test('strips double-asterisk bold', () {
      expect(stripInlineMarkdown('**bold**'), 'bold');
    });

    test('strips underscore italics and double-underscore bold', () {
      expect(stripInlineMarkdown('_under_'), 'under');
      expect(stripInlineMarkdown('__strong__'), 'strong');
    });

    test('strips inline code and strikethrough', () {
      expect(stripInlineMarkdown('`code`'), 'code');
      expect(stripInlineMarkdown('~~gone~~'), 'gone');
    });

    test('unwraps links and images to their text', () {
      expect(stripInlineMarkdown('[Cue](https://cue.app)'), 'Cue');
      expect(stripInlineMarkdown('![alt text](https://img.png)'), 'alt text');
    });

    test('strips leading ATX headings without reflowing', () {
      expect(stripInlineMarkdown('## Title'), 'Title');
      expect(stripInlineMarkdown('# A\n### B'), 'A\nB');
    });

    test('does NOT corrupt snake_case identifiers', () {
      expect(stripInlineMarkdown('target_behavior'), 'target_behavior');
      expect(stripInlineMarkdown('feeding_swallowing_skill'),
          'feeding_swallowing_skill');
      // emphasis next to a snake_case word: strip the emphasis, keep the word
      expect(stripInlineMarkdown('_focus_ on target_behavior'),
          'focus on target_behavior');
    });

    test('passes plain text through unchanged', () {
      const plain = "Asha's last session — week 1 of 4.";
      expect(stripInlineMarkdown(plain), plain);
      expect(stripInlineMarkdown(''), '');
    });

    test('handles mixed inline markup in one line', () {
      expect(
        stripInlineMarkdown("*Asha's session* — **STG 1.A** in `focus`"),
        "Asha's session — STG 1.A in focus",
      );
    });

    // The exact reported case (client feeb0c03 / Asha).
    test('the Asha status line loses its asterisks', () {
      const raw =
          "*Asha's last session remains undocumented — STG 1.A in focus, "
          "fluency domain, week 1 of 4.*";
      final out = stripInlineMarkdown(raw);
      expect(out.contains('*'), isFalse);
      expect(
        out,
        "Asha's last session remains undocumented — STG 1.A in focus, "
        "fluency domain, week 1 of 4.",
      );
    });

    test('no emphasis markers survive for a marker-heavy string', () {
      final out = stripInlineMarkdown(
          '**a** *b* _c_ __d__ ~~e~~ `f` [g](http://h)');
      for (final marker in ['*', '_', '~', '`']) {
        expect(out.contains(marker), isFalse,
            reason: 'marker "$marker" should be gone: "$out"');
      }
    });
  });
}
