import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/format_template_lexicon_default.dart';

// Phase C — Cue Mirror, Component Two. Repository for the
// `format_template_lexicon_defaults` table — the SLP's per-template swap/keep
// decision for each forbidden term. RLS scopes every query to the clinician.
class FormatTemplateLexiconDefaultsRepository {
  final SupabaseClient _client;

  FormatTemplateLexiconDefaultsRepository({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  static const _table = 'format_template_lexicon_defaults';

  /// All lexicon decisions the clinician has set for one template.
  Future<List<FormatTemplateLexiconDefault>> listForTemplate(
      String templateId) async {
    final rows = await _client
        .from(_table)
        .select()
        .eq('template_id', templateId)
        .order('forbidden_term', ascending: true);
    return (rows as List)
        .map((r) =>
            FormatTemplateLexiconDefault.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  /// Set (or change) the decision for one term on one template. Upserts on the
  /// (template_id, forbidden_term) unique constraint, so calling twice for the
  /// same term updates in place rather than duplicating.
  Future<FormatTemplateLexiconDefault> upsert({
    required String templateId,
    required String forbiddenTerm,
    required String decision, // 'swap' | 'keep_original'
    String? replacementTerm,
  }) async {
    final uid = _client.auth.currentUser?.id;
    final row = await _client
        .from(_table)
        .upsert(
          {
            'user_id': uid,
            'template_id': templateId,
            'forbidden_term': forbiddenTerm,
            'decision': decision,
            'replacement_term': replacementTerm,
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          },
          onConflict: 'template_id,forbidden_term',
        )
        .select()
        .single();
    return FormatTemplateLexiconDefault.fromJson(row);
  }
}
