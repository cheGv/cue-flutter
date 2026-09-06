// lib/services/trial_run_delete_service.dart
//
// Delete affordances, Step 2 — the ONE genuinely irreversible action in the
// app: a trial run is deleted for good. Real cases and clients are never
// hard-deleted (they get the recoverable path in Step 3); this file refuses
// them at every layer it can reach.
//
// Three layers, each independently sufficient for the refusal:
//   1. runTrialRunDelete gates on the in-memory row's is_trial_case — the
//      same gate _convertToTherapy uses — before anything is shown or sent.
//   2. TrialRunDeleteService.delete re-reads the row and refuses unless the
//      server says it is a trial run, BEFORE touching storage.
//   3. The DELETE itself carries `is_trial_case = true`, so a non-trial row
//      cannot be removed by this path even if both gates above were bypassed.
//
// Ordering: format_draft_exports storage objects go first, the row second.
// SQL cascade never touches the bucket, and the format_drafts rows that hold
// the object paths die with the client row — deleting the row first would
// orphan the files forever. The inverse failure (objects gone, then the row
// blocked by 23503) is benign: an export is regenerable from its draft row,
// which survives.
//
// 23503 is the known, real-data-untested failure mode: a trial run can in
// principle accrue sessions / goals / reasoning threads (their client FK is
// NO ACTION). The audit found zero, so that branch is exercised only by the
// unit test against the exact Postgres wording captured live on sandbox.
//
// No Supabase seam is added to the Assessing screen. The orchestrator takes
// plain closures so its branches are testable; the service takes the
// optional SupabaseClient every repository in lib/repositories already takes.

import 'package:supabase_flutter/supabase_flutter.dart';

/// The single predicate the gate, the card and the handler all share.
bool isTrialRun(Map<String, dynamic> client) => client['is_trial_case'] == true;

enum TrialRunDeleteOutcomeKind { refusedNotTrial, cancelled, deleted, failed }

class TrialRunDeleteOutcome {
  final TrialRunDeleteOutcomeKind kind;

  /// Clinician-readable. Null for [TrialRunDeleteOutcomeKind.cancelled] and
  /// [TrialRunDeleteOutcomeKind.deleted].
  final String? message;

  const TrialRunDeleteOutcome._(this.kind, [this.message]);

  static const cancelled =
      TrialRunDeleteOutcome._(TrialRunDeleteOutcomeKind.cancelled);
  static const deleted =
      TrialRunDeleteOutcome._(TrialRunDeleteOutcomeKind.deleted);
  static const refusedNotTrial = TrialRunDeleteOutcome._(
    TrialRunDeleteOutcomeKind.refusedNotTrial,
    'Only a trial run can be deleted permanently. '
    'Real cases are not deleted this way.',
  );
  factory TrialRunDeleteOutcome.failed(String message) =>
      TrialRunDeleteOutcome._(TrialRunDeleteOutcomeKind.failed, message);
}

/// Thrown by [TrialRunDeleteService.delete] when the server-side gate
/// refuses. Carries a clinician-readable message.
class TrialRunDeleteRefused implements Exception {
  final String message;
  const TrialRunDeleteRefused(this.message);
  @override
  String toString() => message;
}

/// Turns a Postgres foreign-key block (SQLSTATE 23503) into plain words, or
/// returns null when [error] is anything else.
///
/// Built on the exact wording captured live on sandbox 2026-09-06:
///   message: update or delete on table "clients" violates foreign key
///            constraint "sessions_client_id_fkey" on table "sessions"
///   details: Key (id)=(…) is still referenced from table "sessions".
/// `details` is read first (`from table "x"`); the message fallback takes the
/// LAST `on table "x"` because the first names the parent, "clients".
String? describeTrialRunDeleteBlock(Object error) {
  if (error is! PostgrestException || error.code != '23503') return null;
  final details = '${error.details ?? ''}';
  final table = RegExp(r'from table "([^"]+)"').firstMatch(details)?.group(1) ??
      RegExp(r'from table "([^"]+)"').firstMatch(error.message)?.group(1) ??
      _lastOnTable(error.message);
  final what = switch (table) {
    'sessions' => 'session notes',
    'goals' || 'long_term_goals' || 'short_term_goals' || 'goal_plans' =>
      'goals',
    'reasoning_threads' => 'reasoning threads',
    null => 'other records',
    _ => table.replaceAll('_', ' '),
  };
  return "This trial run still has $what linked to it, so it couldn't be "
      'deleted. It is still in your trial runs.';
}

String? _lastOnTable(String message) {
  final all = RegExp(r'on table "([^"]+)"').allMatches(message).toList();
  return all.isEmpty ? null : all.last.group(1);
}

/// Gate → confirm → execute, as one sequence with one outcome.
///
/// [confirm] is the dialog; [execute] is the deletion. Both are closures so
/// every branch below is testable without a Supabase seam anywhere: a
/// non-trial row never reaches [confirm], a cancel never reaches [execute],
/// and a 23503 from [execute] comes back as words, never as an exception.
Future<TrialRunDeleteOutcome> runTrialRunDelete({
  required Map<String, dynamic> client,
  required Future<bool> Function() confirm,
  required Future<void> Function(String clientId) execute,
}) async {
  if (!isTrialRun(client)) return TrialRunDeleteOutcome.refusedNotTrial;
  final id = client['id']?.toString() ?? '';
  if (id.isEmpty) {
    return TrialRunDeleteOutcome.failed(
        'This trial run has no id — nothing to delete.');
  }
  if (!await confirm()) return TrialRunDeleteOutcome.cancelled;
  try {
    await execute(id);
    return TrialRunDeleteOutcome.deleted;
  } on TrialRunDeleteRefused catch (e) {
    return TrialRunDeleteOutcome.failed(e.message);
  } catch (e) {
    return TrialRunDeleteOutcome.failed(describeTrialRunDeleteBlock(e) ??
        'Could not delete this trial run: $e');
  }
}

class TrialRunDeleteService {
  TrialRunDeleteService({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  static const _bucket = 'format_draft_exports';

  /// Permanently deletes the trial run [clientId]: its export files in the
  /// bucket, then the clients row (the FK cascade takes the capture families,
  /// format_drafts and format_draft_sentences with it).
  ///
  /// Throws [TrialRunDeleteRefused] when the row is not a trial run or is
  /// already gone; lets a [PostgrestException] (23503 included) propagate so
  /// the caller can render it.
  Future<void> delete(String clientId) async {
    // Layer 2 — the server's word, before any object is touched.
    final row = await _client
        .from('clients')
        .select('id, is_trial_case')
        .eq('id', clientId)
        .maybeSingle();
    if (row == null) {
      throw const TrialRunDeleteRefused(
          'This trial run is already gone. Refresh the list.');
    }
    if (row['is_trial_case'] != true) {
      throw const TrialRunDeleteRefused(
          'Only a trial run can be deleted permanently. '
          'Real cases are not deleted this way.');
    }

    // Export files first. Two sources of truth, unioned: the recorded
    // export_path, and a listing of the <uid>/<draft_id>/ prefix the proxy
    // writes under (covers an upload whose path write never landed).
    // Archived drafts are included — their files are just as orphanable.
    final uid = _client.auth.currentUser?.id;
    final drafts = await _client
        .from('format_drafts')
        .select('id, export_path')
        .eq('client_id', clientId);
    final paths = <String>{};
    for (final d in drafts) {
      final recorded = d['export_path'];
      if (recorded is String && recorded.isNotEmpty) paths.add(recorded);
      if (uid == null) continue;
      final prefix = '$uid/${d['id']}';
      final files = await _client.storage.from(_bucket).list(path: prefix);
      for (final f in files) {
        if (f.id == null) continue; // folder placeholder, not an object
        paths.add('$prefix/${f.name}');
      }
    }
    if (paths.isNotEmpty) {
      await _client.storage.from(_bucket).remove(paths.toList());
    }

    // Layer 3 — the predicate makes a non-trial delete impossible here.
    final deleted = await _client
        .from('clients')
        .delete()
        .eq('id', clientId)
        .eq('is_trial_case', true)
        .select('id');
    if (deleted.isEmpty) {
      throw const TrialRunDeleteRefused(
          'Nothing was deleted — the row is not a trial run, or it was '
          'already removed.');
    }
  }
}
