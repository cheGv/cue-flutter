// lib/widgets/trial_run_delete_dialog.dart
//
// Delete affordances, Step 2 — confirmation for the ONE irreversible action
// in the app. Same shape as archive_dialog.dart (AlertDialog, barrier not
// dismissible, Cancel TextButton + coral FilledButton) but deliberately NOT
// showArchiveDialog: that dialog's confirm label is "Archive" and its
// vocabulary belongs to the recoverable actions. This one says permanent,
// offers no reason picker (nothing is retained to attach a reason to), and
// its caller must not follow it with an Undo — undo implies recoverable.

import 'package:flutter/material.dart';

/// Returns true only when the clinician tapped "Delete permanently".
Future<bool> showTrialRunDeleteDialog({
  required BuildContext context,
  required String name,
}) async {
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      title: const Text('Delete this trial run?'),
      content: Text(
        '"$name" will be deleted permanently, along with everything captured '
        'in it — assessment entries and any drafts. There is no way to get '
        'it back.',
        style: const TextStyle(height: 1.5),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFFC25450),
            foregroundColor: Colors.white,
          ),
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Delete permanently'),
        ),
      ],
    ),
  );
  return result ?? false;
}
