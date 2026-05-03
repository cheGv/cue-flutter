// lib/services/session_archive_service.dart
//
// Phase 4.0.7.10b — single source of truth for archiving (soft-deleting)
// a session. Surfaced from:
//   - report_screen.dart's app-bar kebab (existing in f2ceb76, now thin-
//     wraps this service)
//   - client_profile_screen.dart's timeline session-card kebab (added in
//     4.0.7.10b)
//
// Soft-delete only. Sessions are never hard-deleted — clinical-legal
// record retention. The PATCH writes deleted_at + deleted_by +
// delete_reason; queries elsewhere already filter `deleted_at IS NULL`.
//
// The service shows the confirmation dialog and runs the PATCH. It does
// NOT navigate (pop) or refresh — those are caller decisions because
// each surface has its own context and reload semantics. Returns true
// when the row was archived, false when the user cancelled or an error
// surfaced.

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../widgets/archive_dialog.dart';

Future<bool> archiveSession({
  required BuildContext context,
  required Map<String, dynamic> session,
}) async {
  final id = session['id'];
  if (id == null) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Session has no id — nothing to archive.'),
        ),
      );
    }
    return false;
  }

  final attested = session['clinician_attested'] == true;
  final attestedAt =
      (session['attested_at'] as String?)?.split('T').first;

  final body = attested
      ? 'This session was attested${attestedAt != null ? ' on $attestedAt' : ''}. '
        'Archiving keeps the record but hides it from your active sessions list. '
        'Required for clinical-legal audit trail.'
      : "Archived sessions are hidden from the client's history. "
        'The data stays in your account.';

  final result = await showArchiveDialog(
    context: context,
    title: 'Archive this session?',
    body: body,
    reasons: const [
      'Duplicate generation',
      'Wrong client',
      'Test session',
      'Session did not occur',
      'Other',
    ],
    reasonRequired: attested,
  );
  if (!result.confirmed) return false;

  final supabase = Supabase.instance.client;
  try {
    await supabase.from('sessions').update({
      'deleted_at':    DateTime.now().toUtc().toIso8601String(),
      'deleted_by':    supabase.auth.currentUser?.id,
      'delete_reason': result.reason,
    }).eq('id', id);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Session archived.')),
      );
    }
    return true;
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Archive failed: $e')),
      );
    }
    return false;
  }
}
