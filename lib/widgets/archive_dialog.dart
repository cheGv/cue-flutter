// lib/widgets/archive_dialog.dart
//
// Phase 4.0.7.10 — shared archive confirmation dialog. Used by:
//   - client list (kebab on row → archive client)
//   - session list / report screen (kebab → archive session)
//
// Soft-delete only — clinical-legal record retention. The caller writes
// to public.{clients|sessions}.deleted_at after the user confirms.
//
// Reason picker is OPTIONAL by default (covers the client-archive case
// and the unattested-session case). Caller passes `reasonRequired: true`
// for attested sessions where the audit trail demands a reason.
//
// Returns: ArchiveDialogResult with .confirmed (bool) and .reason (String?
// — the picker selection, possibly with free-text appended for "Other").

import 'package:flutter/material.dart';

class ArchiveDialogResult {
  final bool confirmed;
  final String? reason;
  const ArchiveDialogResult._(this.confirmed, this.reason);
  static const cancelled = ArchiveDialogResult._(false, null);
}

Future<ArchiveDialogResult> showArchiveDialog({
  required BuildContext context,
  required String title,
  required String body,
  required List<String> reasons,
  bool reasonRequired = false,
}) async {
  String? selectedReason;
  final freeTextCtrl = TextEditingController();

  final result = await showDialog<ArchiveDialogResult>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) {
      return StatefulBuilder(
        builder: (ctx, setLocal) {
          final canConfirm = !reasonRequired ||
              (selectedReason != null &&
                  (selectedReason != 'Other' ||
                      freeTextCtrl.text.trim().isNotEmpty));

          return AlertDialog(
            title: Text(title),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(body, style: const TextStyle(height: 1.5)),
                  if (reasons.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Text(
                      reasonRequired ? 'Reason (required)' : 'Reason (optional)',
                      style: const TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 6),
                    for (final r in reasons)
                      RadioListTile<String>(
                        title: Text(r,
                            style: const TextStyle(fontSize: 13)),
                        value: r,
                        groupValue: selectedReason,
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        onChanged: (v) =>
                            setLocal(() => selectedReason = v),
                      ),
                    if (selectedReason == 'Other') ...[
                      const SizedBox(height: 4),
                      TextField(
                        controller: freeTextCtrl,
                        decoration: const InputDecoration(
                          hintText: 'Briefly describe',
                          isDense: true,
                          border: OutlineInputBorder(),
                        ),
                        maxLines: 2,
                        onChanged: (_) => setLocal(() {}),
                      ),
                    ],
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () =>
                    Navigator.pop(ctx, ArchiveDialogResult.cancelled),
                child: const Text('Cancel'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFC25450),
                  foregroundColor: Colors.white,
                ),
                onPressed: canConfirm
                    ? () {
                        String? reason = selectedReason;
                        if (reason == 'Other' &&
                            freeTextCtrl.text.trim().isNotEmpty) {
                          reason = 'Other: ${freeTextCtrl.text.trim()}';
                        }
                        Navigator.pop(
                            ctx, ArchiveDialogResult._(true, reason));
                      }
                    : null,
                child: const Text('Archive'),
              ),
            ],
          );
        },
      );
    },
  );

  return result ?? ArchiveDialogResult.cancelled;
}
