/// Composition for the V2 library UX (roadmap D1–D6).
///
/// Deliberately **local**. Wiring V2 into the app's routes and its one
/// provider graph is a scheduled task of its own, so nothing here touches
/// `lib/providers.dart`; everything hangs off a single injectable service
/// holder, which is what a widget test overrides.
///
/// The split this file keeps: **reads are drift streams, writes are
/// repositories.** Every rule about the library — reparenting, cycle refusal,
/// archive-writes-lifecycle-only, what a removal takes with it — already lives
/// in `lib/data/`. This layer owns none of it. It queries, groups and hands
/// view models to the widgets.
library;

import 'dart:async';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/collection_repository.dart';
import '../data/entry_repository.dart';
import '../data/folder_repository.dart';
import '../data/offline_copy_repository.dart';
import '../data/reading_state_repository.dart';
import '../data/schema.dart';
import '../domain/reading_state.dart';
import '../save/queue_repository.dart';
import '../save/queue_task.dart';
import '../storage/file_store.dart';
import 'collection_models.dart';
import 'folder_models.dart';
import 'placement_models.dart';
import 'shelf_models.dart';
import 'source_models.dart';

/// The database and the repositories over it, in one object so a test
/// overrides one provider rather than six.
///
/// [fileStore] is required rather than optional. Freeing a downloaded copy is
/// bytes first and rows second, and a services object that could be built
/// without a store would make "the row is gone" available as a way to imply
/// the bytes went with it.
class LibraryUiServices {
  LibraryUiServices(this.db, {required this.fileStore})
    : folders = FolderRepository(db),
      collections = CollectionRepository(db),
      entries = EntryRepository(db),
      reading = ReadingStateRepository(db),
      offline = OfflineCopyRepository(db),
      queue = SaveQueueRepository(db);

  final LibraryDatabase db;
  final FolderRepository folders;
  final CollectionRepository collections;
  final EntryRepository entries;
  final ReadingStateRepository reading;
  final OfflineCopyRepository offline;

  /// The save queue. This layer enqueues, cancels and reads it; it never
  /// claims a row or drives a page.
  final SaveQueueRepository queue;

  /// Where this device's bytes live.
  final FileStore fileStore;
}

final libraryUiServicesProvider = Provider<LibraryUiServices>(
  (ref) => throw UnimplementedError(
    'library_ui composition is not wired yet — override this provider',
  ),
);

final libraryDatabaseProvider = Provider<LibraryDatabase>(
  (ref) => ref.watch(libraryUiServicesProvider).db,
);

final folderRepoProvider = Provider<FolderRepository>(
  (ref) => ref.watch(libraryUiServicesProvider).folders,
);

final collectionRepoProvider = Provider<CollectionRepository>(
  (ref) => ref.watch(libraryUiServicesProvider).collections,
);

final entryRepoProvider = Provider<EntryRepository>(
  (ref) => ref.watch(libraryUiServicesProvider).entries,
);

final readingRepoProvider = Provider<ReadingStateRepository>(
  (ref) => ref.watch(libraryUiServicesProvider).reading,
);

final offlineCopyRepoProvider = Provider<OfflineCopyRepository>(
  (ref) => ref.watch(libraryUiServicesProvider).offline,
);

final saveQueueRepoProvider = Provider<SaveQueueRepository>(
  (ref) => ref.watch(libraryUiServicesProvider).queue,
);

final fileStoreProvider = Provider<FileStore>(
  (ref) => ref.watch(libraryUiServicesProvider).fileStore,
);

/// How this UI hands a Location to whatever will open it.
///
/// Null by default, and that is not a placeholder for missing behaviour: the
/// reading-state write happens either way, because *recording that an Entry
/// was opened at its source* is a library fact and navigating to a page is
/// not. The Browser is attached here when the composition task runs.
typedef SourceOpener = Future<void> Function(String url);

final sourceOpenerProvider = Provider<SourceOpener?>((ref) => null);

/// How this UI hands an authorised queue to whatever will work through it.
///
/// The two halves of a Start are deliberately separate. **Authorising is this
/// lane's** — `SaveQueueRepository.authoriseStart` is the user's explicit
/// permission, held in memory and never persisted — and **running is not**:
/// a save drives the Browser, and nothing in `lib/library_ui/` may. Null means
/// no runner is attached, and the user is told that rather than being handed a
/// Start that authorises work nothing will pick up.
typedef SaveQueueStarter = Future<void> Function();

final saveQueueStarterProvider = Provider<SaveQueueStarter?>((ref) => null);

/// How a placement leaves this device (roadmap D6).
///
/// Unimplemented by default, in the same spirit as [libraryUiServicesProvider]:
/// the transport is a lane of its own, and this one consumes the interface.
final placementSubmitProvider = Provider<PlacementSubmit>(
  (ref) => throw UnimplementedError(
    'placement submission is not wired yet — override this provider',
  ),
);

/// The root Folder, created on first use. "At the library root" means "in the
/// root Folder" (V2-D21), so the shelf always has a folder to stand on.
final rootFolderProvider = FutureProvider<FolderRow>(
  (ref) => ref.watch(folderRepoProvider).ensureRoot(),
);

/// One Folder's contents: its subfolders, its Collections and the standalone
/// Entries that live in it directly.
///
/// Null means the Folder is gone — deleted from another surface while this
/// one was open.
final shelfProvider = StreamProvider.family<ShelfView?, String>((
  ref,
  folderId,
) {
  final db = ref.watch(libraryDatabaseProvider);
  return _libraryTicks(db).asyncMap((_) => _loadShelf(db, folderId));
});

/// One Collection and its **one** Entry list. Null means the Collection is
/// gone.
final collectionViewProvider = StreamProvider.family<CollectionView?, String>((
  ref,
  collectionId,
) {
  final db = ref.watch(libraryDatabaseProvider);
  return _libraryTicks(db).asyncMap((_) => _loadCollection(db, collectionId));
});

/// One Collection's Sources, in the order they were first seen.
///
/// Its own stream rather than a field on [collectionViewProvider]: the Sources
/// section redraws when a site's lifecycle changes or the preference pointer
/// moves, and neither of those touches an Entry. Every lifecycle is carried —
/// a dead Source is a row this query returns like any other (V2-D14).
final collectionSourcesProvider =
    StreamProvider.family<List<SourceView>, String>((ref, collectionId) {
      final db = ref.watch(libraryDatabaseProvider);
      return _mergeTicks([
        db.select(db.sources).watch(),
        db.select(db.collections).watch(),
      ]).asyncMap((_) => _loadSources(db, collectionId));
    });

/// This device's save queue, keyed by Entry.
///
/// One open row per Entry at most, because [SaveQueueRepository.enqueue] is
/// idempotent per Entry; where an Entry has only history, the newest terminal
/// row stands, so "it failed" survives on the row that failed rather than
/// vanishing the moment the run ended.
final saveTasksByEntryProvider = StreamProvider<Map<String, SaveTask>>((ref) {
  return ref.watch(saveQueueRepoProvider).watch().map(_latestTaskByEntry);
});

/// The one save-queue row that speaks for [entryId] right now, or null.
final entrySaveTaskProvider = Provider.family<SaveTask?, String>(
  (ref, entryId) => ref.watch(saveTasksByEntryProvider).value?[entryId],
);

/// The whole Folder tree, flattened with a depth for indentation — what the
/// move picker offers. The schema is hierarchical from day one; the shelf
/// itself stays flat and navigates (V2-D21, O-A).
final folderTreeProvider = StreamProvider<List<FolderNode>>((ref) {
  final db = ref.watch(libraryDatabaseProvider);
  return db.select(db.folders).watch().map(flattenFolderTree);
});

/// What deleting [folderId] would move, counted the same way the repository
/// counts what it moved — so the confirmation and the outcome cannot disagree
/// about the number.
///
/// A plain function rather than a provider: it is read once, at the moment the
/// confirmation opens, and a cached answer is exactly the wrong thing here.
Future<ReparentCounts> countFolderChildren(
  LibraryDatabase db,
  String folderId,
) async {
  final folders = await (db.select(
    db.folders,
  )..where((f) => f.parentId.equals(folderId))).get();
  final collections = await (db.select(
    db.collections,
  )..where((c) => c.folderId.equals(folderId))).get();
  final entries = await (db.select(
    db.entries,
  )..where((e) => e.folderId.equals(folderId))).get();
  return ReparentCounts(
    folders: folders.length,
    collections: collections.length,
    entries: entries.length,
  );
}

// ─── queries ────────────────────────────────────────────────────────────────

/// A tick whenever anything the library UX draws changes.
///
/// Every table, genuinely: drift invalidates per table, so watching
/// `collections` alone misses a reading-state write, and watching `entries`
/// alone misses an offline copy being freed. V1 learned this as a shelf that
/// showed stale numbers until something happened to touch a collection row.
Stream<void> _libraryTicks(LibraryDatabase db) => _mergeTicks([
  db.select(db.folders).watch(),
  db.select(db.collections).watch(),
  db.select(db.entries).watch(),
  db.select(db.locations).watch(),
  db.select(db.readingStates).watch(),
  db.select(db.offlineCopies).watch(),
]);

/// Emit a tick whenever any of [sources] emits.
///
/// `sync: true` matters. Drift delivers each query stream's first value in a
/// microtask; forwarding it through an async controller adds another
/// event-loop hop, which a widget test's fake clock never turns — the screen
/// simply never leaves its loading state.
Stream<void> _mergeTicks(List<Stream<Object?>> sources) {
  final subscriptions = <StreamSubscription<Object?>>[];
  late final StreamController<void> controller;
  controller = StreamController<void>.broadcast(
    sync: true,
    onListen: () {
      for (final source in sources) {
        subscriptions.add(
          source.listen(
            (_) => controller.add(null),
            onError: controller.addError,
          ),
        );
      }
    },
    onCancel: () {
      for (final s in subscriptions) {
        unawaited(s.cancel());
      }
      subscriptions.clear();
    },
  );
  return controller.stream;
}

Future<ShelfView?> _loadShelf(LibraryDatabase db, String folderId) async {
  final folder = await (db.select(
    db.folders,
  )..where((f) => f.id.equals(folderId))).getSingleOrNull();
  if (folder == null) return null;

  final subfolders =
      await (db.select(db.folders)
            ..where((f) => f.parentId.equals(folderId))
            ..orderBy([
              (f) => OrderingTerm.asc(f.sortKey),
              (f) => OrderingTerm.asc(f.name),
            ]))
          .get();

  final collections =
      await (db.select(db.collections)
            ..where((c) => c.folderId.equals(folderId))
            ..orderBy([
              (c) => OrderingTerm.asc(c.sortKey),
              (c) => OrderingTerm.asc(c.name),
            ]))
          .get();

  // Standalone Entries are shelf items in their own right, beside the
  // Collections rather than hidden inside one (I3).
  final standalone =
      await (db.select(db.entries)
            ..where((e) => e.folderId.equals(folderId))
            ..orderBy([
              (e) => OrderingTerm.asc(e.sortKey),
              (e) => OrderingTerm.asc(e.title),
            ]))
          .get();

  final collectionIds = [for (final c in collections) c.id];
  final memberEntries = collectionIds.isEmpty
      ? const <EntryRow>[]
      : await (db.select(
          db.entries,
        )..where((e) => e.collectionId.isIn(collectionIds))).get();

  final status = await _statusByEntry(db);
  final offline = await _entriesWithAnActiveCopy(db);
  final labels = await _sourceLabels(db, [for (final e in standalone) e.id]);

  final total = <String, int>{};
  final unread = <String, int>{};
  for (final entry in memberEntries) {
    final id = entry.collectionId!;
    total[id] = (total[id] ?? 0) + 1;
    if ((status[entry.id] ?? ReadStatus.unread) != ReadStatus.completed) {
      unread[id] = (unread[id] ?? 0) + 1;
    }
  }

  return ShelfView(
    folder: folder,
    folders: subfolders,
    collections: [
      for (final c in collections)
        ShelfCollectionView(
          row: c,
          entryCount: total[c.id] ?? 0,
          unreadCount: unread[c.id] ?? 0,
        ),
    ],
    entries: [
      for (final e in standalone)
        EntryRowView.from(
          row: e,
          status: status[e.id] ?? ReadStatus.unread,
          availableOffline: offline.contains(e.id),
          sourceLabel: labels[e.id],
        ),
    ],
  );
}

Future<CollectionView?> _loadCollection(
  LibraryDatabase db,
  String collectionId,
) async {
  final collection = await (db.select(
    db.collections,
  )..where((c) => c.id.equals(collectionId))).getSingleOrNull();
  if (collection == null) return null;

  final rows = await (db.select(
    db.entries,
  )..where((e) => e.collectionId.equals(collectionId))).get();
  final status = await _statusByEntry(db);
  final offline = await _entriesWithAnActiveCopy(db);
  final labels = await _sourceLabels(db, [for (final e in rows) e.id]);

  return CollectionView.from(
    collection: collection,
    entries: [
      for (final row in rows)
        EntryRowView.from(
          row: row,
          status: status[row.id] ?? ReadStatus.unread,
          availableOffline: offline.contains(row.id),
          sourceLabel: labels[row.id],
        ),
    ],
  );
}

/// Reading state for every Entry that has a row. An absent row reads as
/// unread — reading state exists for every Entry, stored or not (I10).
Future<Map<String, ReadStatus>> _statusByEntry(LibraryDatabase db) async {
  final rows = await db.select(db.readingStates).get();
  return {
    for (final row in rows) row.entryId: ReadStatus.values.byName(row.status),
  };
}

/// Entries this device holds bytes for. Availability is a row state; it never
/// decides whether an Entry is listed.
Future<Set<String>> _entriesWithAnActiveCopy(LibraryDatabase db) async {
  final rows = await (db.select(
    db.offlineCopies,
  )..where((c) => c.active.equals(true))).get();
  return {for (final row in rows) row.entryId};
}

/// The earliest active Location's own label per Entry — evidence of what one
/// site printed, used only when the Entry has no title of its own.
Future<Map<String, String>> _sourceLabels(
  LibraryDatabase db,
  List<String> entryIds,
) async {
  if (entryIds.isEmpty) return const {};
  final rows =
      await (db.select(db.locations)
            ..where(
              (l) => l.entryId.isIn(entryIds) & l.lifecycle.equals('active'),
            )
            ..orderBy([(l) => OrderingTerm.asc(l.discoveredAt)]))
          .get();
  final labels = <String, String>{};
  for (final row in rows) {
    if (row.sourceLabel.trim().isEmpty) continue;
    labels.putIfAbsent(row.entryId, () => row.sourceLabel.trim());
  }
  return labels;
}

/// Every Source of one Collection, with the Collection's preference resolved
/// against it and a `resolvedInto` pointer followed one step.
///
/// One step, not the whole chain: the row says where *this* site went, and a
/// section that silently reported the end of a chain would hide a move the
/// user can see in the list beside it.
Future<List<SourceView>> _loadSources(
  LibraryDatabase db,
  String collectionId,
) async {
  final collection = await (db.select(
    db.collections,
  )..where((c) => c.id.equals(collectionId))).getSingleOrNull();
  if (collection == null) return const [];

  final rows =
      await (db.select(db.sources)
            ..where((s) => s.collectionId.equals(collectionId))
            ..orderBy([
              (s) => OrderingTerm.asc(s.firstSeenAt),
              (s) => OrderingTerm.asc(s.host),
            ]))
          .get();
  final byId = {for (final row in rows) row.id: row};
  return [
    for (final row in rows)
      SourceView(
        row: row,
        preferred: collection.preferredSourceId == row.id,
        resolvedInto: byId[row.resolvedIntoSourceId],
      ),
  ];
}

/// The open task for an Entry, or its newest terminal row when it has none.
Map<String, SaveTask> _latestTaskByEntry(List<SaveTask> tasks) {
  final byEntry = <String, SaveTask>{};
  for (final task in tasks) {
    final held = byEntry[task.entryId];
    if (held == null || (!task.isTerminal && held.isTerminal)) {
      byEntry[task.entryId] = task;
      continue;
    }
    if (held.isTerminal && task.isTerminal) {
      final a = held.finishedAt ?? held.queuedAt;
      final b = task.finishedAt ?? task.queuedAt;
      if (!b.isBefore(a)) byEntry[task.entryId] = task;
    }
  }
  return byEntry;
}

/// The Entry already holding [ordinal] in [collectionId], if there is one.
///
/// Read at the moment a position is typed and again is never assumed: this is
/// what the user is shown *before* they commit, and I8 is enforced by the
/// schema regardless of what this returns.
Future<EntryRow?> entryAtOrdinal(
  LibraryDatabase db,
  String collectionId,
  double ordinal,
) {
  return (db.select(db.entries)
        ..where(
          (e) =>
              e.collectionId.equals(collectionId) & e.ordinal.equals(ordinal),
        )
        ..limit(1))
      .getSingleOrNull();
}

/// The Location this Entry is read at: its earliest active one.
///
/// An Entry is not a URL — it may have several Locations, or none at all, and
/// "none" is a real answer rather than an error.
Future<LocationRow?> primaryLocation(LibraryDatabase db, String entryId) async {
  final rows =
      await (db.select(db.locations)
            ..where(
              (l) => l.entryId.equals(entryId) & l.lifecycle.equals('active'),
            )
            ..orderBy([(l) => OrderingTerm.asc(l.discoveredAt)])
            ..limit(1))
          .get();
  return rows.firstOrNull;
}

/// The address of [primaryLocation].
Future<String?> primaryLocationUrl(LibraryDatabase db, String entryId) async =>
    (await primaryLocation(db, entryId))?.url;
