/// What a Collection and an Entry can be asked to do (roadmap D3).
///
/// Every label here names its **blast radius**, because PRODUCT.md §2.4 is a
/// list of verbs that look alike and are not:
///
/// * *Archive* stops following. It writes one column and removes nothing.
/// * *Remove offline copy* frees bytes **on this device**.
/// * *Remove from library* is your library, everywhere — and it still does not
///   destroy bytes a device is holding (I14).
///
/// The two removals are never offered as substitutes for each other, and no
/// wording in this file may suggest that archiving is a way to delete.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/reading_state.dart';
import '../ui/status_style.dart';
import 'collection_models.dart';
import 'folder_picker.dart';
import 'library_widgets.dart';
import 'providers.dart';

// ─── collection ─────────────────────────────────────────────────────────────

enum _CollectionAction { archive, follow, move }

Future<void> showCollectionMenu(
  BuildContext context,
  WidgetRef ref,
  CollectionView view,
) async {
  final action = await showModalBottomSheet<_CollectionAction>(
    context: context,
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
            child: Text(
              view.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: serifStyle(size: 20),
            ),
          ),
          if (view.archived)
            ListTile(
              key: const ValueKey('collectionFollow'),
              leading: const Icon(Icons.bookmark_added_outlined),
              title: const Text('Follow again'),
              subtitle: const Text(
                'Scrollary keeps this collection current as you read.',
              ),
              onTap: () =>
                  Navigator.of(sheetContext).pop(_CollectionAction.follow),
            )
          else
            ListTile(
              key: const ValueKey('collectionArchive'),
              leading: const Icon(Icons.inventory_2_outlined),
              title: const Text('Archive'),
              subtitle: const Text(
                'Stops following it. Entries, reading state and anything on '
                'this device stay exactly as they are.',
              ),
              onTap: () =>
                  Navigator.of(sheetContext).pop(_CollectionAction.archive),
            ),
          ListTile(
            key: const ValueKey('collectionMove'),
            leading: const Icon(Icons.drive_file_move_outline),
            title: const Text('Move to folder'),
            subtitle: const Text('How you organise your library.'),
            onTap: () => Navigator.of(sheetContext).pop(_CollectionAction.move),
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
  if (action == null || !context.mounted) return;

  final repository = ref.read(collectionRepoProvider);
  switch (action) {
    case _CollectionAction.archive:
      final violation = await repository.archive(view.collection.id);
      if (!context.mounted) return;
      showLibraryMessage(
        context,
        violation != null
            ? violation.message
            : 'Archived. Nothing was removed.',
      );
    case _CollectionAction.follow:
      final violation = await repository.follow(view.collection.id);
      if (!context.mounted) return;
      showLibraryMessage(
        context,
        violation != null ? violation.message : 'Following again.',
      );
    case _CollectionAction.move:
      final target = await pickFolder(
        context,
        title: 'Move “${view.name}” to',
        currentId: view.collection.folderId,
      );
      if (target == null || !context.mounted) return;
      final violation = await repository.moveToFolder(
        view.collection.id,
        target,
      );
      if (!context.mounted || violation == null) return;
      showLibraryMessage(context, violation.message);
  }
}

// ─── entry ──────────────────────────────────────────────────────────────────

enum _EntryAction { markRead, markUnread, openAtSource, removeCopy, remove }

/// The Entry menu. Which items appear is decided by facts about the Entry —
/// whether it has been read, whether this device holds a copy — and never by
/// what the app would prefer the user to do.
Future<void> showEntryMenu(
  BuildContext context,
  WidgetRef ref,
  EntryRowView view,
) async {
  final action = await showModalBottomSheet<_EntryAction>(
    context: context,
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
            child: Text(
              view.label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: serifStyle(size: 20),
            ),
          ),
          if (view.status == ReadStatus.completed)
            ListTile(
              key: const ValueKey('entryMarkUnread'),
              leading: const Icon(Icons.remove_done),
              title: const Text('Mark unread'),
              subtitle: const Text('Reading state follows the entry itself.'),
              onTap: () =>
                  Navigator.of(sheetContext).pop(_EntryAction.markUnread),
            )
          else
            ListTile(
              key: const ValueKey('entryMarkRead'),
              leading: const Icon(Icons.done_all),
              title: const Text('Mark read'),
              subtitle: const Text('Reading state follows the entry itself.'),
              onTap: () =>
                  Navigator.of(sheetContext).pop(_EntryAction.markRead),
            ),
          ListTile(
            key: const ValueKey('entryOpenAtSource'),
            leading: const Icon(Icons.open_in_new),
            title: const Text('Open at source'),
            subtitle: const Text(
              'Records that you opened it. Position is not measured on a '
              'website, so nothing is guessed about how far you got.',
            ),
            onTap: () =>
                Navigator.of(sheetContext).pop(_EntryAction.openAtSource),
          ),
          // Not wired, and therefore not offered as though it were: the
          // capture lane owns downloading, and a control that appears to start
          // one would be a button that lies.
          const ListTile(
            key: ValueKey('entryDownload'),
            enabled: false,
            leading: Icon(Icons.download_for_offline_outlined),
            title: Text('Download for offline'),
            subtitle: Text('Not available yet.'),
          ),
          if (view.availableOffline)
            ListTile(
              key: const ValueKey('entryRemoveCopy'),
              leading: const Icon(Icons.cloud_off),
              title: const Text('Remove offline copy'),
              subtitle: const Text(
                'Frees the bytes on this device. The entry stays in your '
                'library.',
              ),
              onTap: () =>
                  Navigator.of(sheetContext).pop(_EntryAction.removeCopy),
            ),
          ListTile(
            key: const ValueKey('entryRemove'),
            leading: const Icon(Icons.playlist_remove),
            title: const Text('Remove from library'),
            subtitle: const Text('Your library, on every device you use.'),
            onTap: () => Navigator.of(sheetContext).pop(_EntryAction.remove),
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
  if (action == null || !context.mounted) return;

  switch (action) {
    case _EntryAction.markRead:
      await ref.read(readingRepoProvider).markRead(view.id);
    case _EntryAction.markUnread:
      await ref.read(readingRepoProvider).markUnread(view.id);
    case _EntryAction.openAtSource:
      await _openAtSource(context, ref, view);
    case _EntryAction.removeCopy:
      await _removeOfflineCopy(context, ref, view);
    case _EntryAction.remove:
      await _removeFromLibrary(context, ref, view);
  }
}

/// Opening at the source is two facts, in this order: the page opens, and the
/// library records that it was opened (I16 — never that it was finished).
Future<void> _openAtSource(
  BuildContext context,
  WidgetRef ref,
  EntryRowView view,
) async {
  final opener = ref.read(sourceOpenerProvider);
  final url = await primaryLocationUrl(
    ref.read(libraryDatabaseProvider),
    view.id,
  );
  if (!context.mounted) return;
  if (url == null) {
    showLibraryMessage(context, 'No address is recorded for this entry.');
    return;
  }
  if (opener == null) {
    // Honest rather than silent: nothing opened, so nothing is recorded as
    // having been opened.
    showLibraryMessage(context, 'Opening a source is not available yet.');
    return;
  }
  await opener(url);
  await ref.read(readingRepoProvider).recordSourceAccess(view.id);
}

/// Device-local, and said so. This removes **this device's record** of the
/// bytes; the package itself is deleted through the FileStore, whose V2 call
/// site belongs to the capture lane.
Future<void> _removeOfflineCopy(
  BuildContext context,
  WidgetRef ref,
  EntryRowView view,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Remove the offline copy?'),
      content: Text(
        'Frees the bytes this device is holding for “${view.label}”. It stays '
        'in your library, your reading state is untouched, and no other '
        'device is affected.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('Remove copy'),
        ),
      ],
    ),
  );
  if (confirmed != true) return;
  await ref.read(offlineCopyRepoProvider).removeCopies(view.id);
}

Future<void> _removeFromLibrary(
  BuildContext context,
  WidgetRef ref,
  EntryRowView view,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text('Remove “${view.label}” from your library?'),
      content: const Text(
        'It leaves your library on every device you use. Anything this device '
        'has already downloaded is kept until you remove that separately.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('Remove'),
        ),
      ],
    ),
  );
  if (confirmed != true) return;
  final violation = await ref.read(entryRepoProvider).removeEntry(view.id);
  if (!context.mounted || violation == null) return;
  showLibraryMessage(context, violation.message);
}
