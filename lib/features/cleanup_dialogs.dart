/// Confirming a removal, and saying what happened.
///
/// Two things, and one rule between them: **the caller computes the facts.**
/// This file never guesses at a size, a count or what will be kept — a dialog
/// that estimated its own numbers would be a second, differently-derived
/// answer to a question the storage survey has already answered.
///
/// The D37 collection-cleanup question and the finished-entry dialog that
/// asked it lived here too. Both went with the reader's V1 route: they were
/// asked on a forward move to the *next entry in a collection*, and a reader
/// opened over an OfflineCopy has no neighbour list to move through.
library;

import 'package:flutter/material.dart';

import '../ui/palette.dart';
import '../ui/status_style.dart';

/// One removal confirmation for every scope: a single entry, a selection,
/// a whole collection, or every finished entry. Facts are computed by the
/// caller so this widget never guesses at sizes.
class RemovalSummary {
  const RemovalSummary({
    required this.title,
    required this.body,
    required this.facts,
    this.lockNote,
    this.cta = 'Remove files',
  });

  final String title;
  final String body;

  /// key → value rows ("Entries" → "412", "Space freed" → "~3.4 GB").
  final List<(String, String)> facts;

  /// Entries that will be kept because something is using them.
  final String? lockNote;
  final String cta;
}

Future<bool> showRemovalConfirm({
  required BuildContext context,
  required RemovalSummary summary,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) {
      final palette = AppPalette.of(context);
      return AlertDialog(
        icon: Icon(Icons.delete_sweep, size: 26, color: palette.inkMuted),
        title: Text(summary.title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              summary.body,
              style: TextStyle(
                fontSize: 13,
                height: 1.55,
                color: palette.inkMuted,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
              decoration: BoxDecoration(
                color: palette.surfaceMuted,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: palette.border),
              ),
              child: Column(
                children: [
                  for (final (k, v) in summary.facts)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            k,
                            style: monoStyle(
                              size: 11.5,
                              color: palette.inkMuted,
                            ),
                          ),
                          Text(
                            v,
                            style: monoStyle(size: 11.5, color: palette.ink),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            if (summary.lockNote != null) ...[
              const SizedBox(height: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.lock, size: 15, color: palette.warn),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      summary.lockNote!,
                      style: TextStyle(
                        fontSize: 11.5,
                        height: 1.45,
                        color: palette.warn,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(summary.cta),
          ),
        ],
      );
    },
  );
  return confirmed ?? false;
}

Row _toastRow(AppPalette palette, IconData icon, String text) => Row(
  children: [
    Icon(icon, size: 19, color: palette.toastAccent),
    const SizedBox(width: 10),
    Expanded(
      child: Text(
        text,
        style: TextStyle(fontSize: 12.5, height: 1.4, color: palette.toastInk),
      ),
    ),
  ],
);

/// The design's dark toast, with an optional Undo.
/// Say what a cleanup did.
///
/// **There is no Undo here, and there deliberately is not one.** Cleanup
/// deletes packages from disk outright — `FileStore.deleteEntryContent` is a
/// recursive delete, not a move to staging — so an Undo action would be a
/// button that cannot do what it says. The honest version of reversibility is
/// the confirmation before it: it names the entries and the space, and it is
/// the same reasoning V2-D33 records for Folder deletion.
void showCleanupToast(
  BuildContext context, {
  required String text,
  IconData icon = Icons.delete_sweep,
}) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  final palette = AppPalette.of(context);
  messenger.clearSnackBars();
  messenger.showSnackBar(
    SnackBar(
      duration: const Duration(milliseconds: 4200),
      backgroundColor: palette.toastSurface,
      content: _toastRow(palette, icon, text),
    ),
  );
}
