/// Permanent deletion of one collection.
///
/// **This is not archiving and not removing offline files.** Archiving flips
/// `collections.lifecycle` and touches nothing else; removing offline files
/// deletes bytes and deliberately keeps every row, so the entry stays in the
/// library with its reading history. This deletes the collection outright: the
/// row, its entries, their files, the reading progress on them, the
/// preferences stored on the collection, and the activity rows that named it.
/// Afterwards the library is in the state it was in before the collection was
/// ever saved, and saving the same source again makes a new one.
///
/// ### Why the files move before the rows go
///
/// Startup recovery rebuilds a missing entry row from the `manifest.json`
/// beside its bytes — that is what makes an entry package self-describing. So
/// deleting rows first and bytes second has a failure mode that is worse than
/// losing the delete: a kill in between leaves committed packages under
/// `library/` with no rows, and the next launch reconciles them back into a
/// collection the user deleted.
///
/// Every directory the collection owns is therefore **renamed** into
/// `tmp/deleting-<id>` first, in one step per directory:
///
///  * a rename is atomic and cannot half-move a tree;
///  * `tmp/` is swept at startup, so a crash after the move loses nothing and
///    leaks nothing;
///  * a failure before the rows are touched restores what was moved and
///    reports a refusal — nothing is deleted and the collection still works;
///  * a crash between the move and the transaction leaves rows whose files are
///    gone, which the library already renders honestly ("not available
///    offline") and which a second delete finishes off. It cannot resurrect.
///
/// The one thing this cannot be is a single transaction across SQLite and the
/// filesystem. Given that, the ordering above is chosen so the reachable
/// intermediate state is the visible, recoverable one.
library;

import 'dart:io';

import 'package:path/path.dart' as p;

import '../core/url_utils.dart';
import '../queue/task_queue.dart';
import '../save/page_hint.dart' show collectionFingerprint;
import '../storage/cleanup.dart';
import '../storage/database.dart';
import '../storage/file_store.dart';
import 'collection_repository.dart' show displayNameFor;

/// Why a permanent delete did not happen. Each one is a different sentence to
/// the user, which is the whole reason this is not a bool.
enum DeleteRefusal {
  /// The collection is no longer in the library — something else removed it.
  gone,

  /// An entry is open in the reader, or a save is still finishing for this
  /// collection. Deleting under either would pull data out from under work
  /// that is still writing.
  inUse,

  /// The saved files could not be moved out of the library. **Nothing was
  /// deleted** — the collection is exactly as it was.
  filesKept,
}

/// What the confirmation dialog quotes, measured before anything is touched.
class CollectionDeletionPlan {
  const CollectionDeletionPlan({
    required this.collectionId,
    required this.displayName,
    required this.entryCount,
    required this.offlineCount,
    required this.bytes,
    required this.pendingTasks,
    required this.hasReadingProgress,
  });

  final String collectionId;
  final String displayName;

  /// Entries a save has at least been attempted for.
  final int entryCount;

  /// Entries whose files are on this device right now.
  final int offlineCount;
  final int bytes;

  /// Waiting or running activity rows that name this collection.
  final int pendingTasks;

  /// Whether anything here has been opened or finished, so the dialog only
  /// promises to delete reading progress when there is some.
  final bool hasReadingProgress;
}

/// What a delete did, or why it did not run.
class CollectionDeletionResult {
  const CollectionDeletionResult.deleted({
    required this.deletedEntries,
    required this.freedBytes,
    required this.cancelledTasks,
    this.detail = '',
  }) : refusal = null;

  const CollectionDeletionResult.refused(this.refusal, this.detail)
    : deletedEntries = 0,
      freedBytes = 0,
      cancelledTasks = 0;

  /// Null when the collection is gone.
  final DeleteRefusal? refusal;

  /// One line the UI can show verbatim.
  final String detail;
  final int deletedEntries;
  final int freedBytes;
  final int cancelledTasks;

  bool get ok => refusal == null;
}

/// Deletes a collection and everything that exists only because of it.
///
/// What it deliberately leaves alone is as much of the contract as what it
/// removes: standalone entries, other collections, saved sites, browsing
/// history, favicons, settings, and the navigation hints the user taught by
/// tapping — those are keyed to a *page shape on a host*, are shared with
/// every other collection there, and are exactly what makes saving the same
/// source again work as well as it did the first time.
class CollectionDeletionService {
  CollectionDeletionService({
    required this.db,
    required this.fileStore,
    required this.cleanup,
    this.queue,
  });

  final AppDatabase db;
  final FileStore fileStore;

  /// Consulted for its locks — an entry open in the reader or mid-save is the
  /// same "in use" here as it is for removing files.
  final CleanupService cleanup;

  /// Optional: without it there is no pending work to cancel. Null only in
  /// tests and headless contexts that never built a queue.
  final TaskQueueController? queue;

  /// The numbers the confirmation shows. Null when there is no such
  /// collection.
  Future<CollectionDeletionPlan?> plan(String collectionId) async {
    final collection = await db.collectionById(collectionId);
    if (collection == null) return null;
    final entries = await db.entriesForCollection(collectionId);
    final pending =
        await queue?.pendingTasksForCollection(collectionId) ??
        const <QueueTask>[];

    return CollectionDeletionPlan(
      collectionId: collectionId,
      displayName: displayNameFor(collection),
      entryCount: entries.where((e) => e.saveStatus != 'knownRemote').length,
      offlineCount: entries.where(_isOffline).length,
      bytes: entries.fold<int>(0, (sum, e) => sum + e.byteSize),
      pendingTasks: pending.length,
      hasReadingProgress: entries.any(
        (e) => e.lastReadAt != null || e.readStatus != 'unread',
      ),
    );
  }

  /// Delete [collectionId] permanently.
  ///
  /// Stops first, then moves the bytes, then removes the rows. Every early
  /// return leaves the collection usable.
  Future<CollectionDeletionResult> delete(String collectionId) async {
    final collection = await db.collectionById(collectionId);
    if (collection == null) {
      return const CollectionDeletionResult.refused(
        DeleteRefusal.gone,
        'This collection is no longer in your library.',
      );
    }
    final entries = await db.entriesForCollection(collectionId);
    final addresses = _Addresses.of(collection, entries);

    // 1. Take the collection's work off the queue. Queued rows are cancelled
    //    outright; a running one is asked to stop at its next safe point.
    final cancelled = await _cancelWorkFor(collection, addresses);

    // 2. Refuse while anything is still holding the collection. A cooperative
    //    stop lands between entries, not instantly, and deleting the row an
    //    in-flight save is about to write to would either resurrect the
    //    collection or fail the save with a constraint error. "Try again in a
    //    moment" is the honest answer, and it is a moment.
    final busy = await _busyReason(collectionId, entries, addresses);
    if (busy != null) {
      return CollectionDeletionResult.refused(DeleteRefusal.inUse, busy);
    }

    // 3. The bytes leave the library before any row does.
    final staging = Directory(
      p.join(
        fileStore.rootDir.path,
        FileStore.tmpFolderName,
        'deleting-$collectionId',
      ),
    );
    try {
      _takeFilesAside(collection: collection, entries: entries, stage: staging);
    } catch (e) {
      return CollectionDeletionResult.refused(
        DeleteRefusal.filesKept,
        'The saved files could not be removed, so nothing was deleted ($e).',
      );
    }

    // 4. Rows. One transaction, dependents first — `PRAGMA foreign_keys` is
    //    on, so the collection row cannot go while an entry still points at
    //    it.
    final freed = entries.fold<int>(0, (sum, e) => sum + e.byteSize);
    await db.transaction(() async {
      await db.deleteQueueTasksForCollection(collectionId);
      for (final run in await db.allRuns()) {
        if (_runTargets(run, collectionId, addresses)) {
          await db.deleteRun(run.id);
        }
      }
      await db.deleteEntriesForCollection(collectionId);
      await db.deleteCollection(collectionId);
    });

    // 5. Only now are the bytes expendable. A failure here leaks into `tmp/`,
    //    which the startup sweep owns — it is not a failed delete.
    try {
      if (staging.existsSync()) staging.deleteSync(recursive: true);
    } catch (_) {}

    // Storage figures are watching this, not the five call sites that free
    // space.
    if (freed > 0) cleanup.removals.value++;

    return CollectionDeletionResult.deleted(
      deletedEntries: entries.length,
      freedBytes: freed,
      cancelledTasks: cancelled,
    );
  }

  // --- stopping -------------------------------------------------------------

  /// Cancel everything queued or running for this collection.
  ///
  /// Two passes, because a save task carries a collection id only when the
  /// caller knew one. A save started from the Browser is attributed by its
  /// address instead, and a queued row aimed at a page of this collection
  /// would otherwise run after the delete and rebuild it.
  Future<int> _cancelWorkFor(
    Collection collection,
    _Addresses addresses,
  ) async {
    final controller = queue;
    if (controller == null) return 0;

    var cancelled = await controller.cancelTasksForCollection(collection.id);
    for (final task in await db.pendingQueueTasks()) {
      if (task.collectionId == collection.id) continue; // pass one had it
      final url = task.startUrl;
      if (url == null || !addresses.belongs(url)) continue;
      final result = await controller.cancelTask(task.id);
      if (result == CancelResult.cancelledBeforeStart ||
          result == CancelResult.stoppingRunning) {
        cancelled++;
      }
    }
    return cancelled;
  }

  /// Why the collection cannot be deleted right now, or null when it can.
  Future<String?> _busyReason(
    String collectionId,
    List<Entry> entries,
    _Addresses addresses,
  ) async {
    for (final entry in entries) {
      final lock = await cleanup.lockReasonFor(entry);
      if (lock != null) {
        return 'An entry of this collection is $lock. Close it and try '
            'again.';
      }
    }

    // A save the user started straight from the Browser has no queue row to
    // read, so ask the run itself where it is.
    final run = cleanup.saveRun;
    if (run != null &&
        run.hasActiveRun &&
        addresses.belongs(run.progress.currentUrl)) {
      return 'A save is still working on this collection. It has been asked '
          'to stop — try again in a moment.';
    }

    final stillPending = (await db.pendingQueueTasks()).where(
      (t) => t.collectionId == collectionId,
    );
    if (stillPending.isNotEmpty) {
      return 'A task for this collection is still finishing. Try again in a '
          'moment.';
    }
    return null;
  }

  // --- files ----------------------------------------------------------------

  /// Move every directory this collection owns into [stage].
  ///
  /// Throws when a move fails, having first put back the ones that succeeded,
  /// so the caller can refuse with the collection intact.
  void _takeFilesAside({
    required Collection collection,
    required List<Entry> entries,
    required Directory stage,
  }) {
    if (stage.existsSync()) stage.deleteSync(recursive: true);
    stage.createSync(recursive: true);

    final moved = <(Directory from, Directory to)>[];
    var n = 0;
    try {
      for (final dir in _ownedDirectories(collection, entries)) {
        if (!dir.existsSync()) continue;
        final target = Directory(p.join(stage.path, '${n++}'));
        dir.renameSync(target.path);
        moved.add((dir, target));
      }
    } catch (_) {
      for (final (from, to) in moved.reversed) {
        try {
          if (!from.existsSync() && to.existsSync()) {
            from.parent.createSync(recursive: true);
            to.renameSync(from.path);
          }
        } catch (_) {
          // Nothing left to try. The rethrow below is what stops the rows
          // from being deleted, which is what matters.
        }
      }
      rethrow;
    }
  }

  /// Everything on disk that exists only because of this collection.
  ///
  /// The collection directory covers the ordinary case and takes the
  /// `.previous` backups of an interrupted replacement with it. The two extra
  /// sources are real and neither is inside it:
  ///
  ///  * an entry that was saved standalone and later moved into this
  ///    collection keeps its `standalone/<id>` path — only the row moved;
  ///  * `tmp/undo-<id>` is a removal waiting out its undo window, and
  ///    restoring one after the delete would put a package back under
  ///    `library/` for startup recovery to find.
  Iterable<Directory> _ownedDirectories(
    Collection collection,
    List<Entry> entries,
  ) sync* {
    yield Directory(
      fileStore.resolve(FileStore.collectionRelativePath(collection.id)),
    );
    for (final entry in entries) {
      final path = entry.contentPath;
      if (path != null) yield Directory(fileStore.resolve(path));
      yield Directory(
        p.join(
          fileStore.rootDir.path,
          FileStore.tmpFolderName,
          'undo-${entry.id}',
        ),
      );
      yield Directory(
        p.join(fileStore.rootDir.path, FileStore.tmpFolderName, entry.id),
      );
    }
  }

  /// Whether an interrupted save run was walking this collection. Such a run
  /// is offered as "resume" on the library screen, and resuming one into a
  /// deleted collection is the delayed work that rebuilds it.
  bool _runTargets(SaveRun run, String collectionId, _Addresses addresses) {
    if (run.collectionId == collectionId) return true;
    if (addresses.belongs(run.startUrl)) return true;
    final current = run.currentUrl;
    return current != null && addresses.belongs(current);
  }

  static bool _isOffline(Entry entry) =>
      entry.contentPath != null &&
      (entry.saveStatus == 'complete' || entry.saveStatus == 'partial');
}

/// "Is this address a page of the collection being deleted?"
///
/// Two answers, because the work that has to be stopped is not only work
/// aimed at pages already saved. A queued save started from the Browser
/// carries no collection id, and its target is usually the *next* page —
/// one this device has never held and has no row for.
///
///  * a saved page: the address matches an entry, the collection's source, or
///    its index;
///  * an unsaved page of the same collection: same host, and the same
///    collection path — [collectionFingerprint] against the stored
///    `collectionKey`, which is the app's own definition of "same collection"
///    and the one that grouped these entries in the first place.
///
/// The second test is skipped for a key that is not a path. A hand-made group
/// (`manual:…`), a low-confidence one (`…#…`), a title-keyed one and a
/// host-keyed one all carry keys deliberately built so nothing can match them,
/// and honouring that here is what stops a delete from cancelling an unrelated
/// collection's work on a busy host.
class _Addresses {
  const _Addresses._(this._keys, this._host, this._path);

  factory _Addresses.of(Collection collection, List<Entry> entries) {
    final keys = <String>{
      for (final entry in entries) ...[
        normalizeUrl(entry.urlKey),
        normalizeUrl(entry.sourceUrl),
      ],
      normalizeUrl(collection.sourceUrl),
      if (collection.collectionIndexUrl != null)
        normalizeUrl(collection.collectionIndexUrl!),
    }..removeWhere((key) => key.isEmpty);

    final key = collection.collectionKey;
    final isPath = key != null && key.startsWith('/') && !key.contains('#');
    return _Addresses._(
      keys,
      collection.host.toLowerCase(),
      isPath ? _tidyPath(key) : null,
    );
  }

  final Set<String> _keys;
  final String _host;

  /// The collection path, or null when this collection's key is not one.
  final String? _path;

  bool belongs(String url) {
    final normalized = normalizeUrl(url);
    if (normalized.isEmpty) return false;
    if (_keys.contains(normalized)) return true;

    final path = _path;
    if (path == null || _host.isEmpty) return false;
    final uri = Uri.tryParse(url);
    if (uri == null || uri.host.toLowerCase() != _host) return false;
    return _tidyPath(collectionFingerprint(url)) == path;
  }

  /// Lowercased, no trailing slash — the same shape the identity resolver
  /// stores a collection key in.
  static String _tidyPath(String path) {
    var out = path.trim().toLowerCase();
    while (out.length > 1 && out.endsWith('/')) {
      out = out.substring(0, out.length - 1);
    }
    return out;
  }
}
