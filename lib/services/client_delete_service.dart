// lib/services/client_delete_service.dart
//
// Delete affordances, Step 3 — the RECOVERABLE delete for a client or an
// assessment case (both are `clients` rows). Sibling of
// session_archive_service.dart and the same write shape: deleted_at +
// deleted_by + delete_reason, after the archive_dialog. The label is
// DELETE, not Archive — "archive" already means goals in this codebase and
// clients carry a separate discharge axis that is deliberately not built.
//
// This is the reversible one, so it DOES get an Undo snackbar — the
// opposite of the trial-run hard delete (trial_run_delete_service.dart),
// which is permanent and offers none. A trial run is refused here at two
// layers (the in-memory flag, and `is_trial_case = false` on the UPDATE)
// so no single button ever behaves the same for both.
//
// Deleted means deleted, not hidden from lists: ClientsQuery already gates
// every list read, and ClientsQuery.requireLiveClient (added in this step)
// makes every capture loader refuse a soft-deleted client by id.

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../widgets/archive_dialog.dart';
import 'trial_run_delete_service.dart' show isTrialRun;

enum ClientSoftDeleteOutcomeKind { refusedTrial, cancelled, deleted, failed }

class ClientSoftDeleteOutcome {
  final ClientSoftDeleteOutcomeKind kind;

  /// Clinician-readable. Null for cancelled and deleted.
  final String? message;

  /// The reason the clinician picked, on [ClientSoftDeleteOutcomeKind.deleted].
  final String? reason;

  const ClientSoftDeleteOutcome._(this.kind, {this.message, this.reason});

  static const cancelled =
      ClientSoftDeleteOutcome._(ClientSoftDeleteOutcomeKind.cancelled);
  static const refusedTrial = ClientSoftDeleteOutcome._(
    ClientSoftDeleteOutcomeKind.refusedTrial,
    message: 'Trial runs are deleted permanently from the Trial runs list, '
        'not this way.',
  );
  factory ClientSoftDeleteOutcome.deleted({String? reason}) =>
      ClientSoftDeleteOutcome._(ClientSoftDeleteOutcomeKind.deleted,
          reason: reason);
  factory ClientSoftDeleteOutcome.failed(String message) =>
      ClientSoftDeleteOutcome._(ClientSoftDeleteOutcomeKind.failed,
          message: message);
}

/// Thrown by [ClientDeleteService.softDelete] when the UPDATE touched no
/// row: the row is a trial run, is already deleted, or is not the
/// clinician's.
class ClientSoftDeleteRefused implements Exception {
  final String message;
  const ClientSoftDeleteRefused(this.message);
  @override
  String toString() => message;
}

/// True for an assessment-only engagement (an "assessment case" in the UI).
bool isAssessmentCase(Map<String, dynamic> client) =>
    client['engagement_type'] == 'assessment_only';

/// The dialog's words. Pure, so the copy is testable: says DELETE, says
/// recoverable, never says archive.
({String title, String body}) clientSoftDeleteCopy(Map<String, dynamic> client) {
  final name = (client['name'] as String?)?.trim();
  final noun = isAssessmentCase(client) ? 'assessment case' : 'client';
  final who = (name == null || name.isEmpty) ? 'This $noun' : '"$name"';
  return (
    title: 'Delete this $noun?',
    body: '$who disappears from your lists — Today, Clients, Assessing and '
        'Ask Cue — and its records cannot be opened until it is restored. '
        'Nothing is erased: this is recoverable, and you can undo it right '
        'away.',
  );
}

const clientSoftDeleteReasons = <String>[
  'Duplicate record',
  'Wrong client',
  'Test entry',
  'Other',
];

/// Gate → confirm → execute, as one sequence with one outcome. Closures,
/// so every branch is testable without a Supabase seam: a trial run never
/// reaches [confirm], a cancel never reaches [execute], and the reason the
/// clinician picked travels with the outcome.
Future<ClientSoftDeleteOutcome> runClientSoftDelete({
  required Map<String, dynamic> client,
  required Future<ArchiveDialogResult> Function() confirm,
  required Future<void> Function(String clientId, String? reason) execute,
}) async {
  if (isTrialRun(client)) return ClientSoftDeleteOutcome.refusedTrial;
  final id = client['id']?.toString() ?? '';
  if (id.isEmpty) {
    return ClientSoftDeleteOutcome.failed(
        'This record has no id — nothing to delete.');
  }
  final result = await confirm();
  if (!result.confirmed) return ClientSoftDeleteOutcome.cancelled;
  try {
    await execute(id, result.reason);
    return ClientSoftDeleteOutcome.deleted(reason: result.reason);
  } on ClientSoftDeleteRefused catch (e) {
    return ClientSoftDeleteOutcome.failed(e.message);
  } catch (e) {
    return ClientSoftDeleteOutcome.failed('Could not delete: $e');
  }
}

/// The confirmation, in the archive_dialog shape with the DELETE label.
Future<ArchiveDialogResult> showClientSoftDeleteDialog({
  required BuildContext context,
  required Map<String, dynamic> client,
}) {
  final copy = clientSoftDeleteCopy(client);
  return showArchiveDialog(
    context: context,
    title: copy.title,
    body: copy.body,
    reasons: clientSoftDeleteReasons,
    confirmLabel: 'Delete',
  );
}

/// The composition both lists use: dialog + service, one outcome.
Future<ClientSoftDeleteOutcome> deleteClientWithDialog({
  required BuildContext context,
  required Map<String, dynamic> client,
}) {
  return runClientSoftDelete(
    client: client,
    confirm: () => showClientSoftDeleteDialog(context: context, client: client),
    execute: (id, reason) => ClientDeleteService().softDelete(id, reason: reason),
  );
}

/// The Undo snackbar — this delete is reversible, so it says so and offers
/// the way back. Mirrors client_profile_screen's _snackUndo (6 s, clears
/// any earlier bar). [onUndo] restores; [onSettled] runs afterwards either
/// way so the caller can reload.
void showClientDeletedUndo(
  BuildContext context, {
  required String message,
  required Future<void> Function() onUndo,
  required VoidCallback onSettled,
}) {
  ScaffoldMessenger.of(context)
    ..clearSnackBars()
    ..showSnackBar(SnackBar(
      content: Text(message),
      duration: const Duration(seconds: 6),
      action: SnackBarAction(
        label: 'Undo',
        onPressed: () async {
          try {
            await onUndo();
          } finally {
            onSettled();
          }
        },
      ),
    ));
}

class ClientDeleteService {
  ClientDeleteService({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  /// Soft-deletes [clientId]: deleted_at (UTC now), deleted_by (the
  /// signed-in clinician), delete_reason — the session-archive shape.
  /// `is_trial_case = false` on the UPDATE means a trial run cannot be
  /// soft-deleted by this path even if the in-memory gate were bypassed.
  Future<void> softDelete(String clientId, {String? reason}) async {
    final rows = await _client
        .from('clients')
        .update({
          'deleted_at': DateTime.now().toUtc().toIso8601String(),
          'deleted_by': _client.auth.currentUser?.id,
          'delete_reason': reason,
        })
        .eq('id', clientId)
        .eq('is_trial_case', false)
        .isFilter('deleted_at', null)
        .select('id');
    if (rows.isEmpty) {
      throw const ClientSoftDeleteRefused(
          'Nothing was deleted — the record is a trial run, is already '
          'deleted, or is not yours.');
    }
  }

  /// Clears the trio. The row is untouched otherwise, so everything it
  /// owned is exactly as it was.
  Future<void> restore(String clientId) async {
    await _client.from('clients').update({
      'deleted_at': null,
      'deleted_by': null,
      'delete_reason': null,
    }).eq('id', clientId);
  }
}
