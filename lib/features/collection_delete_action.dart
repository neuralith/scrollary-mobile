import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../library/collection_deletion.dart';
import '../library/entry_labels.dart';
import '../providers.dart';
import '../ui/palette.dart';
import '../ui/status_style.dart';
import '../ui/theme.dart';
import 'cleanup_dialogs.dart';
import 'library_screen.dart' show LibraryCollection, formatBytes;

/// The permanent-delete flow: measure, confirm, delete, report.
///
/// Kept apart from the collection screen because it is the one action there
/// that cannot be undone, and the copy that says so is the feature. Everything
/// else in that menu is reversible — rename, archive, and removing offline
/// files all leave the collection in the library.
///
/// [onConfirmed] fires once the user has said yes and **before** the delete
/// runs. It is where the caller leaves the collection screen, and the order is
/// deliberate: the rows vanishing is what takes this collection out of the
/// library stream, so a screen still standing on it would rebuild into its
/// "no longer listed" state and then be popped out from under the rebuild —
/// a teardown racing a data change, for no gain. Leaving first makes the
/// sequence one-way: the confirmation is the decision, and the outcome is
/// reported to the library the user is already back on. A refusal is still
/// reported in full, and nothing has been deleted when one happens.
///
/// Returns true only when the collection is actually gone.
Future<bool> confirmDeleteCollection(
  BuildContext context,
  WidgetRef ref,
  LibraryCollection group, {
  VoidCallback? onConfirmed,
}) async {
  final service = ref.read(collectionDeletionProvider);
  final plan = await service.plan(group.id);
  if (!context.mounted) return false;
  if (plan == null) {
    showCleanupToast(
      context,
      text: 'This collection is no longer in your library.',
      icon: Icons.info_outline,
    );
    return false;
  }

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (_) => _DeleteCollectionDialog(plan: plan, labels: group.labels),
  );
  if (confirmed != true || !context.mounted) return false;

  // Read both while the asking screen is still alive: it is about to be left,
  // and the confirmation has to outlive it.
  final messenger = ScaffoldMessenger.of(context);
  final palette = AppPalette.of(context);
  onConfirmed?.call();

  final result = await service.delete(group.id);
  if (!result.ok) {
    // Refusals are never silent. Nothing was deleted, and the line says which
    // of the three reasons it was.
    showCleanupToastOn(
      messenger,
      palette,
      text: result.detail,
      icon: Icons.error_outline,
    );
    return false;
  }

  showCleanupToastOn(
    messenger,
    palette,
    // The count the dialog showed, not the raw number of rows: a discovered
    // entry that was never saved is a row too, and quoting a bigger number
    // than the one the user just approved reads like something extra went.
    text: [
      'Deleted “${plan.displayName}”',
      group.labels.count(plan.entryCount),
      if (result.freedBytes > 0) '${formatBytes(result.freedBytes)} freed',
    ].join(' · '),
    icon: Icons.delete_forever,
  );
  return true;
}

/// The destructive confirmation.
///
/// It names every kind of thing that goes, in the collection's own vocabulary,
/// and quotes the numbers measured before anything was touched. There is
/// deliberately no typing step: nothing else in this app asks a user to spell
/// a name back, and inventing the pattern here would be friction the product
/// does not otherwise use. What it does instead is separate the action from
/// the reversible ones, colour it as destructive, and state plainly that it
/// cannot be undone.
class _DeleteCollectionDialog extends StatelessWidget {
  const _DeleteCollectionDialog({required this.plan, required this.labels});

  final CollectionDeletionPlan plan;
  final EntryLabels labels;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final losses = <String>[
      'Its ${labels.many} and every file downloaded for them',
      if (plan.hasReadingProgress)
        'Your reading progress, and where you were up to',
      "This collection's own settings",
      if (plan.pendingTasks > 0)
        'Anything waiting for it in Activity '
            '(${plan.pendingTasks} task${plan.pendingTasks == 1 ? '' : 's'})',
    ];

    return AlertDialog(
      // The list plus the facts box is taller than a short phone in
      // landscape, and the action row is what would be pushed off.
      scrollable: true,
      icon: Icon(Icons.delete_forever, size: 26, color: palette.danger),
      title: const Text('Delete this collection?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            plan.displayName,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              fontVariations: wght(600),
              fontWeight: FontWeight.w600,
              color: palette.inkStrong,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'This removes it from your library completely, along with '
            'everything that exists only for it:',
            style: TextStyle(
              fontSize: 13,
              height: 1.55,
              color: palette.inkMuted,
            ),
          ),
          const SizedBox(height: 9),
          for (final line in losses)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 5),
                    child: Icon(Icons.circle, size: 5, color: palette.inkFaint),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      line,
                      style: TextStyle(
                        fontSize: 12.5,
                        height: 1.5,
                        color: palette.inkMuted,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            decoration: BoxDecoration(
              color: palette.surfaceMuted,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: palette.border),
            ),
            child: Column(
              children: [
                for (final (k, v) in <(String, String)>[
                  (labels.Many, '${plan.entryCount}'),
                  ('Downloaded', '${plan.offlineCount}'),
                  ('Space freed', '~${formatBytes(plan.bytes)}'),
                ])
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          k,
                          style: monoStyle(size: 11.5, color: palette.inkMuted),
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
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: palette.dangerContainer,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: palette.dangerBorder),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.warning_amber, size: 16, color: palette.danger),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'This cannot be undone. To have it back you would have to '
                    'save it from the source again.',
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.5,
                      color: palette.onDangerContainer,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const ValueKey('confirmDeleteCollection'),
          onPressed: () => Navigator.pop(context, true),
          style: FilledButton.styleFrom(
            backgroundColor: palette.danger,
            foregroundColor: palette.onDanger,
          ),
          child: const Text('Delete permanently'),
        ),
      ],
    );
  }
}
