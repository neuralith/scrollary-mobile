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
// The adoption half of the save flow lives with the flow it belongs to. This
// is the one call into it from the library: *this loose Entry belongs in that
// Collection after all*.
// STUB IMPORT — switch to '../features/v2_add_flow.dart' at merge.
import '../features/v2_add_flow.dart';
import '../providers.dart' show capturePreferenceProvider;
import '../save/capture_mode.dart';
import 'entry_details.dart';
import '../save/queue_task.dart';
import '../ui/palette.dart';
import '../ui/status_style.dart';
import 'collection_models.dart';
import 'collection_picker.dart';
import 'entry_offline.dart';
import 'folder_picker.dart';
import 'library_widgets.dart';
import 'placement_actions.dart';
import 'providers.dart';

// ─── collection ─────────────────────────────────────────────────────────────

enum _CollectionAction { check, captureMode, archive, follow, move, remove }

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
          // What this collection is normally saved as, changeable after the
          // fact. The save sheet is where it is *set*; this is where someone
          // who changed their mind goes, without having to find a page of it
          // and open the save sheet to get at the question.
          ListTile(
            key: const ValueKey('collectionCaptureMode'),
            leading: const Icon(Icons.tune),
            title: const Text('What to save'),
            subtitle: const Text(
              'Used for entries of this collection, where the page can be '
              'saved that way.',
            ),
            onTap: () =>
                Navigator.of(sheetContext).pop(_CollectionAction.captureMode),
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
          // Last, and never worded as a tidier archive: the two removals in
          // this app are different sizes and the labels have to say so.
          ListTile(
            key: const ValueKey('collectionRemove'),
            leading: const Icon(Icons.playlist_remove),
            title: const Text('Remove from library'),
            subtitle: const Text('Your library, on every device you use.'),
            onTap: () =>
                Navigator.of(sheetContext).pop(_CollectionAction.remove),
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
    case _CollectionAction.captureMode:
      await showCaptureModePreference(context, ref, view);
    case _CollectionAction.archive:
      final violation = await repository.archive(view.collection.id);
      if (violation != null) {
        if (!context.mounted) return;
        showLibraryMessage(context, violation.message);
        return;
      }
      // Archiving is "stop keeping this current", so downloads that have not
      // started yet are work nobody is waiting for any more. A run already in
      // flight is left to finish — stopping is cooperative everywhere in this
      // app, and killing a task mid-write is not something archiving asked
      // for.
      final stopped = await cancelWaitingDownloadsOf(ref, view.collection.id);
      if (!context.mounted) return;
      showLibraryMessage(
        context,
        stopped == 0
            ? 'Archived. Nothing was removed.'
            : 'Archived. Nothing was removed, and '
                  '${stopped == 1 ? '1 waiting download was' : '$stopped waiting downloads were'} '
                  'cancelled.',
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
    case _CollectionAction.remove:
      await _removeCollectionFromLibrary(context, ref, view);
  }
}

/// Cancel the Collection's **waiting** save tasks, and say how many there
/// were.
///
/// Queued only. A running task is asked to stop nowhere here: archiving is not
/// a stop, and the one thing this app never does is offer a stop that does not
/// stop — so a row already claimed by the queue keeps its own outcome.
Future<int> cancelWaitingDownloadsOf(WidgetRef ref, String collectionId) async {
  final entries = await ref.read(entryRepoProvider).entriesOf(collectionId);
  if (entries.isEmpty) return 0;
  final ids = {for (final entry in entries) entry.id};
  final queue = ref.read(saveQueueRepoProvider);
  var stopped = 0;
  for (final task in await queue.pending()) {
    if (task.state != SaveTaskState.queued) continue;
    if (!ids.contains(task.entryId)) continue;
    // One conditional UPDATE, so a row the pump claimed in the same instant
    // loses cleanly here rather than being reported as cancelled.
    final outcome = await queue.cancel(task.id);
    if (outcome == SaveCancelOutcome.cancelledBeforeStart) stopped += 1;
  }
  return stopped;
}

/// *Remove from library* for a whole Collection.
///
/// The blast radius, stated: the Collection, its Entries and the addresses
/// they were read at leave the library **on every device**. Bytes already on
/// this device are not touched — an OfflineCopy has no foreign key and
/// survives the cascade (I14), which is exactly why the confirmation says so
/// rather than leaving the user to find out.
Future<void> _removeCollectionFromLibrary(
  BuildContext context,
  WidgetRef ref,
  CollectionView view,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text('Remove “${view.name}” from your library?'),
      content: const Text(
        'Its entries, and the addresses they were read at, leave your library '
        'on every device you use. Anything this device has already downloaded '
        'stays until you remove it here.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Cancel'),
        ),
        TextButton(
          key: const ValueKey('confirmCollectionRemove'),
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('Remove'),
        ),
      ],
    ),
  );
  if (confirmed != true) return;
  // Waiting work first: a task whose Entry is about to go would be cascaded
  // away as a row rather than cancelled as a decision.
  await cancelWaitingDownloadsOf(ref, view.collection.id);
  final violation = await ref
      .read(collectionRepoProvider)
      .removeCollection(view.collection.id);
  if (!context.mounted) return;
  showLibraryMessage(
    context,
    violation != null
        ? violation.message
        : 'Removed from your library. Downloads on this device were kept.',
  );
}

// ─── entry ──────────────────────────────────────────────────────────────────

enum _EntryAction {
  read,
  details,
  markRead,
  markUnread,
  openAtSource,
  place,
  addToCollection,
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
          // What the library actually holds, verbatim. The list rows lead
          // with an Entry's position and drop the part of a page title that
          // only repeats it and the work's name — a *presentation* rule, so
          // the evidence behind it has to be one tap away or the rule is a
          // deletion pretending to be tidiness.
          ListTile(
            key: const ValueKey('entryDetails'),
            leading: const Icon(Icons.info_outline),
            title: const Text('Details'),
            subtitle: const Text(
              'What the source called it, where it is read from, and what '
              'this device holds.',
            ),
            onTap: () => Navigator.of(sheetContext).pop(_EntryAction.details),
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
          // A standalone Entry is a first-class library item, not a mistake
          // to be corrected — so this is offered, never urged, and only where
          // it means anything: an Entry that is already in a Collection has
          // nothing to adopt it (I3).
          if (view.row.collectionId == null)
            ListTile(
              key: const ValueKey('entryAddToCollection'),
              leading: const Icon(Icons.library_add_outlined),
              title: const Text('Add to a collection…'),
              subtitle: const Text(
                'Moves this entry into a collection you already have. '
                'Nothing on this device is removed.',
              ),
              onTap: () =>
                  Navigator.of(sheetContext).pop(_EntryAction.addToCollection),
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
    case _EntryAction.details:
      await showEntryDetails(context, ref, view);
    case _EntryAction.openAtSource:
      await _openAtSource(context, ref, view);
    case _EntryAction.place:
      await placeEntryInSequence(context, ref, view);
    case _EntryAction.addToCollection:
      await _addEntryToCollection(context, ref, view);
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

/// *Add to a collection…* for a standalone Entry.
///
/// The picker cannot create one here, deliberately: this operation moves an
/// Entry into a Collection that already exists, and a Collection of one Entry
/// is the shape I3 exists to forbid. Where the Collection already holds an
/// equivalent Entry the two become one — the domain decides that, by the same
/// reconciliation every save path uses, and says so in its own sentence.
Future<void> _addEntryToCollection(
  BuildContext context,
  WidgetRef ref,
  EntryRowView view,
) async {
  // No suggested filter: an Entry's own title is not a Collection name, and
  // pre-filling one here would hide the very list the user came to read.
  final choice = await showCollectionPicker(context, ref, allowCreate: false);
  if (choice is! ExistingCollectionChoice || !context.mounted) return;
  final report = await v2AdoptStandalone(
    ref,
    entryId: view.id,
    collectionId: choice.id,
  );
  if (!context.mounted) return;
  showLibraryMessage(context, report.sentence ?? 'Added to “${choice.name}”.');
}

/// Choose what entries of this Collection are normally saved as.
///
/// Four answers, and the fourth is a real one: **Ask each time** clears the
/// preference and goes back to letting the page propose. There is no "safest"
/// capture mode — each produces a different artifact — so *no answer* has to
/// stay expressible.
///
/// What is chosen here proposes; the page still disposes. A collection kept as
/// images asks again on an entry that has none, and this preference is
/// untouched by that: it was an answer about the work.
Future<void> showCaptureModePreference(
  BuildContext context,
  WidgetRef ref,
  CollectionView view,
) async {
  final preferences = ref.read(capturePreferenceProvider);
  final current = await preferences.of(view.collection.id);
  if (!context.mounted) return;

  final chosen = await showModalBottomSheet<_ModeChoice>(
    context: context,
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
            child: Text('What to save', style: serifStyle(size: 20)),
          ),
          for (final mode in CaptureMode.values)
            ListTile(
              key: ValueKey('collectionCaptureMode_${mode.name}'),
              leading: Icon(
                current == mode
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
              ),
              title: Text(mode.label),
              subtitle: Text(mode.description),
              onTap: () =>
                  Navigator.of(sheetContext).pop(_ModeChoice.remember(mode)),
            ),
          ListTile(
            key: const ValueKey('collectionCaptureModeAsk'),
            leading: Icon(
              current == null
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
            ),
            title: const Text('Ask each time'),
            subtitle: const Text(
              'Scrollary proposes what the page itself can offer.',
            ),
            onTap: () =>
                Navigator.of(sheetContext).pop(const _ModeChoice.ask()),
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
  if (chosen == null || !context.mounted) return;

  final mode = chosen.mode;
  if (mode == null) {
    await preferences.forget(view.collection.id);
    if (!context.mounted) return;
    showLibraryMessage(context, 'Scrollary will ask each time.');
    return;
  }
  await preferences.remember(view.collection.id, mode);
  if (!context.mounted) return;
  showLibraryMessage(context, 'Entries of ${view.name} save as ${mode.label}.');
}

/// A mode, or the deliberate absence of one.
class _ModeChoice {
  const _ModeChoice.remember(CaptureMode this.mode);
  const _ModeChoice.ask() : mode = null;

  final CaptureMode? mode;
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
