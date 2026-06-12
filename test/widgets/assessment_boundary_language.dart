// test/widgets/assessment_boundary_language.dart
//
// THE BOUNDARY test suite (intern-scaffold spec §5) — shared helper, not a
// test file. The RED column of the boundary pairs as literal assertions:
// the intern computes what inputs deterministically dictate and never infers
// what inputs merely suggest. Import this from any assessment-surface test
// and run [expectNoInferentialLanguage] over every rendered state — it makes
// inferential output unrepresentable in a passing build.
//
// First consumers: loud_result_test.dart (the component's own chrome),
// wab_k_aq_widget_test.dart (every state of the AQ proving widget).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Word-bounded, case-insensitive. A formula has one answer; an inference is
/// a choice, and choices are the clinician's.
final List<RegExp> kForbiddenInference = [
  RegExp(r'\bindicat(es|ed|ing|ion|ive)\b', caseSensitive: false),
  RegExp(r'\bsuggest(s|ed|ing|ion|ive)?\b', caseSensitive: false),
  RegExp(r'\bconsider\b', caseSensitive: false),
  RegExp(r'\blean(s|ing)?\s+toward', caseSensitive: false),
  RegExp(r'\bthis child has\b', caseSensitive: false),
  RegExp(r'\byou should\b', caseSensitive: false),
  RegExp(r'\brecommend', caseSensitive: false),
  RegExp(r'\btypically\b', caseSensitive: false),
  RegExp(r'\bcatch up\b', caseSensitive: false),
  RegExp(r'\bprognosis\b', caseSensitive: false),
  RegExp(r'\blikel(y|ihood)\b', caseSensitive: false),
  RegExp(r'requiring intervention', caseSensitive: false),
  RegExp(r'\bdiagnos(is|es|ed|tic)\b', caseSensitive: false),
];

/// Every string currently rendered by a [Text] widget in the tree.
Iterable<String> allRenderedText(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .map((t) => t.data ?? t.textSpan?.toPlainText() ?? '');

/// Sweep the whole rendered tree against [kForbiddenInference].
void expectNoInferentialLanguage(WidgetTester tester) {
  for (final text in allRenderedText(tester)) {
    for (final pattern in kForbiddenInference) {
      expect(pattern.hasMatch(text), isFalse,
          reason: 'forbidden inferential language "$pattern" in: "$text"');
    }
  }
}
