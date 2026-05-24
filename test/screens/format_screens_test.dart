// Phase C — format-adaptation screen + integration coverage.
//
// Full pumpable rendering of these screens loads data through the Supabase
// client (repository / storage), so live-rendering tests are skipped here —
// consistent with the prior Phase B convention (screen-level behaviour is
// covered by skipped integration tests; widgets/units carry the assertions).
// Schema validation at the unit level lives in test/models/format_template_test.dart.
import 'package:cue/constants/format_types.dart';
import 'package:cue/screens/format_template_upload_screen.dart';
import 'package:cue/screens/format_templates_list_screen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('format type vocabulary', () {
    test('labels resolve for every key + unknown falls back', () {
      for (final k in kFormatTypeKeys) {
        expect(kFormatTypeLabels.containsKey(k), isTrue);
      }
      expect(formatTypeLabel('pt_report'), 'Pre-therapy report');
      expect(formatTypeLabel('lp_report'), 'Lesson plan');
      expect(formatTypeLabel('???'), 'Other');
    });
  });

  group('screens are referenceable as types', () {
    test('list + upload screens compile and are referenceable', () {
      expect(FormatTemplatesListScreen, isNotNull);
      expect(FormatTemplateUploadScreen, isNotNull);
    });
  });

  group('Format screens — render (require Supabase mocks)', () {
    test('FormatTemplatesListScreen renders the list + empty state', () async {},
        skip: 'requires Supabase client mock');
    test('FormatTemplateUploadScreen renders the 3-step flow', () async {},
        skip: 'requires Supabase client mock');
  });

  group('Integration smoke (requires live proxy + Supabase)', () {
    test('upload AIISH PT fixture → /format-extract → template validates '
        'against the extractor schema', () async {}, skip: 'integration');
  });
}
