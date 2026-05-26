import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/format_draft.dart';

// Phase C — Cue Mirror, Component Two. Repository for the `format_drafts`
// table. RLS scopes every query to the authenticated clinician. Delete is a
// soft-archive (status = 'archived') to preserve the draft trail; listForClient
// hides archived rows.
class FormatDraftsRepository {
  final SupabaseClient _client;

  FormatDraftsRepository({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  static const _table = 'format_drafts';

  /// Active (non-archived) drafts for a client, newest generated first.
  Future<List<FormatDraft>> listForClient(String clientId) async {
    final rows = await _client
        .from(_table)
        .select()
        .eq('client_id', clientId)
        .neq('status', 'archived')
        .order('generated_at', ascending: false);
    return (rows as List)
        .map((r) => FormatDraft.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  Future<FormatDraft?> get(String id) async {
    final row = await _client.from(_table).select().eq('id', id).maybeSingle();
    return row == null ? null : FormatDraft.fromJson(row);
  }

  /// DEPRECATED (Phase D): the proxy's `POST /format-draft` is now the
  /// authoritative writer — it INSERTs format_drafts + format_draft_sentences
  /// atomically and returns `draft_id`. `FormatDrafterService.requestDraft`
  /// reads the draft back via [get] instead of calling this. Retained for
  /// tests/fixtures and back-compat; do NOT use for live draft generation.
  ///
  /// Persist a freshly generated draft. draftSections + generationMetadata are
  /// the raw JSON returned by /format-draft (stored verbatim as jsonb).
  Future<FormatDraft> create({
    required String clientId,
    required String templateId,
    required List<dynamic> draftSections,
    required Map<String, dynamic> generationMetadata,
    String? dateRangePreset,
    DateTime? dateRangeStart,
    DateTime? dateRangeEnd,
    String status = 'draft',
  }) async {
    final uid = _client.auth.currentUser?.id;
    final row = await _client
        .from(_table)
        .insert({
          'user_id': uid,
          'client_id': clientId,
          'template_id': templateId,
          'date_range_preset': dateRangePreset,
          'date_range_start': dateRangeStart?.toIso8601String(),
          'date_range_end': dateRangeEnd?.toIso8601String(),
          'draft_sections': draftSections,
          'generation_metadata': generationMetadata,
          'status': status,
        })
        .select()
        .single();
    return FormatDraft.fromJson(row);
  }

  /// Generic field patch; always bumps updated_at.
  Future<FormatDraft> update(String id, Map<String, dynamic> fields) async {
    final patch = <String, dynamic>{
      ...fields,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };
    final row =
        await _client.from(_table).update(patch).eq('id', id).select().single();
    return FormatDraft.fromJson(row);
  }

  /// Soft delete — archive rather than hard-delete (hidden from listForClient).
  Future<void> delete(String id) async {
    await _client.from(_table).update({
      'status': 'archived',
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', id);
  }
}
