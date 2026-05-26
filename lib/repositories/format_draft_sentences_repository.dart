import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/format_draft_sentence.dart';

// Phase D — Cue Mirror Component Three. Repository for format_draft_sentences.
// RLS scopes every query to the authenticated clinician (clinician_id =
// auth.uid()). The proxy is the authoritative WRITER at draft generation; this
// repo handles reads + clinician edits (autosave / save / static authoring).
class FormatDraftSentencesRepository {
  final SupabaseClient _client;

  FormatDraftSentencesRepository({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  static const _table = 'format_draft_sentences';

  /// All sentences for a draft, ordered by section then position.
  Future<List<FormatDraftSentence>> listForDraft(String draftId) async {
    final rows = await _client
        .from(_table)
        .select()
        .eq('draft_id', draftId)
        .order('section_name')
        .order('sentence_order', ascending: true);
    return (rows as List)
        .map((r) => FormatDraftSentence.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  /// Sentences for one section, in order.
  Future<List<FormatDraftSentence>> listForSection(
      String draftId, String sectionName) async {
    final rows = await _client
        .from(_table)
        .select()
        .eq('draft_id', draftId)
        .eq('section_name', sectionName)
        .order('sentence_order', ascending: true);
    return (rows as List)
        .map((r) => FormatDraftSentence.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  /// Generic patch — autosave (text_in_progress) and save (text/status/...).
  /// Always bumps updated_at.
  Future<FormatDraftSentence> update(
      String id, Map<String, dynamic> fields) async {
    final patch = <String, dynamic>{
      ...fields,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };
    final row =
        await _client.from(_table).update(patch).eq('id', id).select().single();
    return FormatDraftSentence.fromJson(row);
  }

  /// Insert a clinician-authored sentence (static-section authoring, Part F).
  Future<FormatDraftSentence> create({
    required String draftId,
    required String sectionName,
    required int sentenceOrder,
    required String text,
    required String templateId,
    String status = 'clinician_authored',
  }) async {
    final now = DateTime.now().toUtc().toIso8601String();
    final row = await _client.from(_table).insert({
      'draft_id': draftId,
      'section_name': sectionName,
      'sentence_order': sentenceOrder,
      'text': text,
      'text_original': text,
      'status': status,
      'source_claims': null,
      'lexicon_swaps': null,
      'clinician_id': _client.auth.currentUser?.id,
      'template_id': templateId,
      'saved_at': now,
      'edited_at': now,
    }).select().single();
    return FormatDraftSentence.fromJson(row);
  }

  /// Edited/authored sentences for a clinician — the future fine-tuning corpus
  /// query (optionally narrowed to one template). Excludes cue_drafted rows.
  Future<List<FormatDraftSentence>> listEditedForClinician(
    String clinicianId, {
    String? templateId,
  }) async {
    var filter = _client
        .from(_table)
        .select()
        .eq('clinician_id', clinicianId)
        .neq('status', 'cue_drafted');
    if (templateId != null) filter = filter.eq('template_id', templateId);
    final rows = await filter.order('updated_at', ascending: false);
    return (rows as List)
        .map((r) => FormatDraftSentence.fromJson(r as Map<String, dynamic>))
        .toList();
  }
}
