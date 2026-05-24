import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/format_template.dart';

// Phase C — repository for the `format_templates` table. RLS scopes every
// query to the authenticated clinician; methods never cross clinicians.
class FormatTemplatesRepository {
  final SupabaseClient _client;

  FormatTemplatesRepository({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  static const _table = 'format_templates';

  /// Active (non-archived) templates for the current clinician, newest first.
  Future<List<FormatTemplate>> listForUser() async {
    final rows = await _client
        .from(_table)
        .select()
        .neq('confirmation_status', 'archived')
        .order('created_at', ascending: false);
    return (rows as List)
        .map((r) => FormatTemplate.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  Future<FormatTemplate?> get(String id) async {
    final row = await _client.from(_table).select().eq('id', id).maybeSingle();
    return row == null ? null : FormatTemplate.fromJson(row);
  }

  /// Insert a new pending template. Source documents may be empty here and
  /// filled by [update] after upload (the storage path needs the new id).
  Future<FormatTemplate> create({
    required String name,
    required String formatType,
    List<SourceDocument> sourceDocuments = const [],
  }) async {
    final uid = _client.auth.currentUser?.id;
    final row = await _client
        .from(_table)
        .insert({
          'user_id': uid,
          'name': name,
          'format_type': formatType,
          'source_documents': sourceDocuments.map((d) => d.toJson()).toList(),
          'confirmation_status': 'pending',
        })
        .select()
        .single();
    return FormatTemplate.fromJson(row);
  }

  /// Generic field patch; always bumps updated_at.
  Future<FormatTemplate> update(String id, Map<String, dynamic> fields) async {
    final patch = <String, dynamic>{
      ...fields,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };
    final row =
        await _client.from(_table).update(patch).eq('id', id).select().single();
    return FormatTemplate.fromJson(row);
  }

  /// Soft delete — archive rather than hard-delete (preserves source docs for
  /// audit; hidden from [listForUser]).
  Future<void> delete(String id) async {
    await _client.from(_table).update({
      'confirmation_status': 'archived',
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', id);
  }
}
