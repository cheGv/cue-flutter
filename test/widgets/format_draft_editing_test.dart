// Phase D — Cue Mirror Component Three. Widget tests for the public, callback-
// driven EditableSectionCard. No Supabase needed: the card renders sentences
// and reports edits through callbacks, so it pumps in isolation.
//
// Sentences render as Text.rich, so text finders use findRichText: true.
import 'package:cue/models/format_draft.dart';
import 'package:cue/models/format_draft_sentence.dart';
import 'package:cue/screens/format_draft_view_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

FormatDraftSentence _sentence({
  String text = 'The child demonstrates emerging skills.',
  String status = 'cue_drafted',
  String? inProgress,
}) =>
    FormatDraftSentence.fromJson({
      'id': 's1',
      'draft_id': 'd1',
      'section_name': 'Summary',
      'sentence_order': 0,
      'text': text,
      'text_original': text,
      'status': status,
      'text_in_progress': inProgress,
      'clinician_id': 'u1',
      'template_id': 't1',
    });

Future<void> _pump(WidgetTester t, Widget child) async {
  await t.pumpWidget(MaterialApp(
    theme: ThemeData(brightness: Brightness.light),
    home: Scaffold(body: SingleChildScrollView(child: child)),
  ));
  await t.pump(const Duration(milliseconds: 50));
}

EditableSectionCard _card({
  required List<FormatDraftSentence> sentences,
  Future<void> Function(FormatDraftSentence, String)? onAutosave,
  Future<void> Function(FormatDraftSentence, String)? onCommit,
  Future<void> Function(FormatDraftSentence)? onDiscard,
}) =>
    EditableSectionCard(
      section: const DraftSection(sectionName: 'Summary'),
      sentences: sentences,
      onAutosave: onAutosave ?? (_, _) async {},
      onCommit: onCommit ?? (_, _) async {},
      onDiscard: onDiscard ?? (_) async {},
    );

void main() {
  testWidgets('renders the sentence as text, not a field, until tapped',
      (t) async {
    await _pump(t, _card(sentences: [_sentence()]));
    expect(
        find.textContaining('The child demonstrates emerging skills',
            findRichText: true),
        findsOneWidget);
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('tapping a sentence opens an inline editor', (t) async {
    await _pump(t, _card(sentences: [_sentence()]));
    await t.tap(find.textContaining('The child demonstrates emerging skills',
        findRichText: true));
    await t.pump();
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('Save'), findsOneWidget);
    expect(find.text('Discard'), findsOneWidget);
  });

  testWidgets('autosave fires ~2s after a change (debounced)', (t) async {
    String? autosaved;
    await _pump(t,
        _card(sentences: [_sentence()], onAutosave: (_, x) async => autosaved = x));
    await t.tap(find.textContaining('The child demonstrates emerging skills',
        findRichText: true));
    await t.pump();
    await t.enterText(find.byType(TextField), 'Edited sentence.');
    await t.pump();
    expect(autosaved, isNull); // debounced — not yet
    await t.pump(const Duration(seconds: 2));
    await t.pump();
    expect(autosaved, 'Edited sentence.');
  });

  testWidgets('Save commits the edited text via onCommit', (t) async {
    String? committed;
    await _pump(t,
        _card(sentences: [_sentence()], onCommit: (_, x) async => committed = x));
    await t.tap(find.textContaining('The child demonstrates emerging skills',
        findRichText: true));
    await t.pump();
    await t.enterText(find.byType(TextField), 'Final text.');
    await t.pump();
    await t.tap(find.text('Save'));
    await t.pump();
    expect(committed, 'Final text.');
  });

  testWidgets('Discard reverts via onDiscard and leaves edit mode', (t) async {
    var discarded = false;
    await _pump(
      t,
      _card(
        sentences: [_sentence(inProgress: 'half-typed edit')],
        onDiscard: (_) async => discarded = true,
      ),
    );
    await t.tap(find.textContaining('half-typed edit', findRichText: true));
    await t.pump();
    await t.tap(find.text('Discard'));
    await t.pump();
    expect(discarded, isTrue);
    expect(find.byType(TextField), findsNothing);
  });
}
