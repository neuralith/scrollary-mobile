/// What a Collection and an Entry can be asked to do (roadmap D3).
///
/// Every label here names its **blast radius**, because PRODUCT.md §2.4 is a
/// list of verbs that look alike and are not:
///
/// * *Archive* stops following. It writes one column and removes nothing.
/// * *Remove offline copy* frees bytes **on this device**.
/// * *Remove from library* is your library, everywhere — and it still does not
///   destroy bytes a device is holding (I14).
/// * *Download for offline* is **this device**, and it waits: asking for one
///   writes a queued row and nothing else. The controls that act on that row
///   live in `entry_offline.dart`, which is where the queue's own rules are
///   used.
///
/// The two removals are never offered as substitutes for each other, and no
/// wording in this file may suggest that archiving is a way to delete.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/reading_state.dart';
import '../save/queue_task.dart';
import '../ui/palette.dart';
import '../ui/status_style.dart';
import 'collection_models.dart';
import 'entry_offline.dart';
import 'folder_picker.dart';
import 'library_widgets.dart';
import 'placement_actions.dart';
import 'providers.dart';

// ─── collection ─────────────────────────────────────────────────────────────

enum _CollectionAction { check, archive, follow, move }

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
          // Free, and never gated: what the app will *do* for a user is not
          // smaller without Pro. Absent for an archived collection, because
          // archiving is exactly "stop keeping this current" — offering a
          // check there would contradict the sentence beside it.
          if (!view.archived && ref.read(collectionCheckerProvider) != null)
            ListTile(
              key: const ValueKey('collectionCheck'),
              leading: const Icon(Icons.search),
              title: const Text('Check for new entries'),
              subtitle: const Text(
                'Reads this collection\'s site in the Browser. Nothing is '
                'downloaded.',
              ),
              onTap: () =>
                  Navigator.of(sheetContext).pop(_CollectionAction.check),
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
    case _CollectionAction.check:
      final checker = ref.read(collectionCheckerProvider);
      if (checker != null) await checker(view.collection.id, view.name);
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

enum _EntryAction {
  read,
  markRead,
  markUnread,
  openAtSource,
  place,
  download,
  startDownload,
  removeWaiting,
  stopRunning,
  removeFromActivity,
  removeCopy,
  remove,
}

/// The Entry menu. Which items appear is decided by facts about the Entry —
/// whether it has been read, whether this device holds a copy, whether the
/// queue is already carrying a row for it — and never by what the app would
/// prefer the user to do.
///
/// The queue row is read once, as the sheet opens. Acting on a snapshot is
/// safe here and nowhere near a race: every transition goes through one
/// conditional `UPDATE`, so a row that moved underneath this sheet makes the
/// action lose cleanly and say so.
Future<void> showEntryMenu(
  BuildContext context,
  WidgetRef ref,
  EntryRowView view,
) async {
  final task = ref.read(entrySaveTaskProvider(view.id));
  final action = await showModalBottomSheet<_EntryAction>(
    context: context,
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(20, 14, 20, task == null ? 8 : 2),
            child: Text(
              view.label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: serifStyle(size: 20),
            ),
          ),
          // What the queue is doing about this Entry, in the queue's own
          // recorded outcome where it has one.
          if (task != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
              child: Text(
                saveTaskSentence(task),
                style: TextStyle(
                  fontSize: 12,
                  height: 1.5,
                  color: AppPalette.of(sheetContext).inkMuted,
                ),
              ),
            ),
          if (view.availableOffline)
            ListTile(
              key: const ValueKey('entryRead'),
              leading: const Icon(Icons.menu_book_outlined),
              title: const Text('Read'),
              subtitle: const Text('Opens the copy on this device.'),
              onTap: () => Navigator.of(sheetContext).pop(_EntryAction.read),
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
          // A position the app could not establish is the user's to give, and
          // only theirs (V2-D16).
          if (view.needsPlacement)
            ListTile(
              key: const ValueKey('entryPlace'),
              leading: const Icon(Icons.numbers),
              title: const Text('Set its position'),
              subtitle: const Text(
                'Where this sits in the collection\'s sequence. Nothing is '
                'guessed for you.',
              ),
              onTap: () => Navigator.of(sheetContext).pop(_EntryAction.place),
            ),
          // Downloading is one Entry, onto one device, and it waits. A row
          // already in the queue offers what can be done to *that row*
          // instead — a second request would only ever be a second candidate
          // for one copy (I13).
          if (task == null || task.isTerminal)
            ListTile(
              key: const ValueKey('entryDownload'),
              leading: const Icon(Icons.download_for_offline_outlined),
              title: const Text('Download for offline'),
              subtitle: const Text(
                'Puts a copy on this device. It waits in the queue until you '
                'start it.',
              ),
              onTap: () =>
                  Navigator.of(sheetContext).pop(_EntryAction.download),
            ),
          if (task != null && task.state == SaveTaskState.queued) ...[
            ListTile(
              key: const ValueKey('entryStartDownload'),
              leading: const Icon(Icons.play_arrow),
              title: const Text('Start downloading'),
              subtitle: const Text(
                'Nothing has run on its own. Start it when you are ready.',
              ),
              onTap: () =>
                  Navigator.of(sheetContext).pop(_EntryAction.startDownload),
            ),
            ListTile(
              key: const ValueKey('entryRemoveWaiting'),
              leading: const Icon(Icons.playlist_remove),
              title: const Text('Remove from the download queue'),
              subtitle: const Text(
                'It has not run, so nothing is lost — and you can undo it.',
              ),
              onTap: () =>
                  Navigator.of(sheetContext).pop(_EntryAction.removeWaiting),
            ),
          ],
          if (task != null && task.state == SaveTaskState.running)
            ListTile(
              key: const ValueKey('entryStopDownload'),
              leading: const Icon(Icons.stop_circle_outlined),
              title: const Text('Stop this download'),
              subtitle: const Text('It stops at the next safe point.'),
              onTap: () =>
                  Navigator.of(sheetContext).pop(_EntryAction.stopRunning),
            ),
          if (task != null && task.isTerminal)
            ListTile(
              key: const ValueKey('entryRemoveActivity'),
              leading: const Icon(Icons.delete_outline),
              title: const Text('Remove from activity'),
              subtitle: const Text(
                'Clears this record. Nothing on this device is deleted.',
              ),
              onTap: () => Navigator.of(
                sheetContext,
              ).pop(_EntryAction.removeFromActivity),
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
    case _EntryAction.read:
      final open = ref.read(entryOpenerProvider);
      if (open != null) await open(view.id);
    case _EntryAction.markRead:
      await ref.read(readingRepoProvider).markRead(view.id);
    case _EntryAction.markUnread:
      await ref.read(readingRepoProvider).markUnread(view.id);
    case _EntryAction.openAtSource:
      await _openAtSource(context, ref, view);
    case _EntryAction.place:
      await placeEntryInSequence(context, ref, view);
    case _EntryAction.download:
      await downloadForOffline(context, ref, view);
    case _EntryAction.startDownload:
      await startQueuedDownloads(context, ref, firstTaskId: task?.id);
    case _EntryAction.removeWaiting:
      if (task != null) await removeWaitingDownload(context, ref, task);
    case _EntryAction.stopRunning:
      if (task != null) await stopRunningDownload(context, ref, task);
    case _EntryAction.removeFromActivity:
      if (task != null) await removeDownloadFromActivity(context, ref, task);
    case _EntryAction.removeCopy:
      await removeOfflineCopyOf(context, ref, view);
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
