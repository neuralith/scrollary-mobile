/// What this device is holding, and what it can honestly free.
///
/// **Removing a copy is never deleting an Entry.** The Entry, its Locations,
/// its reading state and every other device are untouched: an Entry is in the
/// library because somebody wants to read it, not because bytes were
/// downloaded (PRODUCT.md §2.4). Nothing here may be offered as a way to
/// remove anything from the library.
///
/// ### Two sources, and where they disagree
///
/// The rows say which packages this device holds; the disk says which packages
/// are actually there. V1's storage screen only ever asked the rows, because
/// the rows *were* the library. V2's `offline_copies` is device state beside a
/// library that syncs, so the two can genuinely diverge — a package survives a
/// database that was reset, and a row survives files a restore did not carry —
/// and a cleanup surface that only reads one of them either hides bytes it
/// could free or offers bytes that are not there.
///
/// So [survey] reads both and reports the disagreement as itself:
///
///  * **held** — an active copy whose package is on disk. The ordinary case,
///    and the only one whose bytes are counted as *this app's usage*.
///  * **orphans** — a committed package with no active copy row. Real bytes,
///    freeable, and nothing in the library refers to them. This is the half
///    of the retired startup recovery that still has a job: V1 rebuilt an
///    Entry row from a package like this, and V2 must not — an Entry is a
///    synced library fact and a package on one device is not evidence for one
///    (V2-D22, I14). What was a silent rebuild is now an offer to free.
///  * **missing** — an active copy row whose package is gone. Not an error and
///    not a demotion: the Entry stays listed with its reading history, and the
///    stale row is dropped so the figure stops counting bytes that do not
///    exist.
///
/// Byte lifecycles themselves — the atomic commit, the `.previous` restore,
/// the staging sweep — belong to the ported [FileStore] and are untouched.
/// This file only decides *who asks*.
library;

import 'package:flutter/foundation.dart';

import '../data/collection_repository.dart';
import '../data/entry_repository.dart';
import '../data/offline_copy_repository.dart';
import '../data/reading_state_repository.dart';
import '../domain/offline_copy.dart';
import '../domain/reading_state.dart';
import '../save/entry_capture.dart' show removeOfflineCopies;
import 'file_store.dart';

/// One copy this device's rows claim, with what the library knows about it.
class HeldCopy {
  const HeldCopy({
    required this.copy,
    required this.title,
    required this.collectionId,
    required this.collectionName,
    required this.finished,
    required this.bytes,
  });

  final OfflineCopy copy;

  /// The Entry's own title. Never derived from the package: the manifest
  /// records what a save saw, and the Entry records what the library calls it.
  final String title;

  /// Null for a standalone Entry, which is a first-class library item and not
  /// a collection of one.
  final String? collectionId;
  final String collectionName;

  /// Read to the end. The only set the bulk offer targets.
  final bool finished;

  /// Bytes on disk, measured rather than taken from the row: the row records
  /// what a capture wrote, and this is what is there now.
  final int bytes;

  String get entryId => copy.entryId;
}

/// A committed package with no active copy row behind it.
class OrphanPackage {
  const OrphanPackage({required this.relativePath, required this.bytes});

  final String relativePath;
  final int bytes;
}

/// Storage this device holds, grouped the way the screen shows it.
class CollectionStorage {
  const CollectionStorage({
    required this.id,
    required this.name,
    required this.copies,
  });

  /// Null for the standalone group.
  final String? id;
  final String name;
  final List<HeldCopy> copies;

  int get bytes => copies.fold(0, (sum, c) => sum + c.bytes);
  int get entryCount => copies.length;
}

/// Everything the storage surface needs, read once.
class StorageSurvey {
  const StorageSurvey({
    required this.held,
    required this.missing,
    required this.orphans,
  });

  static const empty = StorageSurvey(held: [], missing: [], orphans: []);

  final List<HeldCopy> held;
  final List<HeldCopy> missing;
  final List<OrphanPackage> orphans;

  int get heldBytes => held.fold(0, (sum, c) => sum + c.bytes);
  int get orphanBytes => orphans.fold(0, (sum, o) => sum + o.bytes);

  List<HeldCopy> get finished => [
    for (final copy in held)
      if (copy.finished) copy,
  ];

  int get finishedBytes => finished.fold(0, (sum, c) => sum + c.bytes);

  /// Held copies by Collection, largest first.
  List<CollectionStorage> get byCollection {
    final groups = <String, List<HeldCopy>>{};
    final names = <String, String>{};
    for (final copy in held) {
      final key = copy.collectionId ?? '';
      groups.putIfAbsent(key, () => []).add(copy);
      names[key] = copy.collectionName;
    }
    final rows = [
      for (final entry in groups.entries)
        CollectionStorage(
          id: entry.key.isEmpty ? null : entry.key,
          name: names[entry.key] ?? '',
          copies: entry.value,
        ),
    ]..sort((a, b) => b.bytes.compareTo(a.bytes));
    return rows;
  }
}

/// Freeing what this device is holding.
class CleanupService {
  CleanupService({
    required this.offlineCopies,
    required this.entries,
    required this.collections,
    required this.reading,
    required this.fileStore,
  });

  final OfflineCopyRepository offlineCopies;
  final EntryRepository entries;
  final CollectionRepository collections;
  final ReadingStateRepository reading;
  final FileStore fileStore;

  /// Bumped once per batch that actually freed something.
  ///
  /// Removal happens from more than one place, and anything showing a storage
  /// figure listens here rather than every call site remembering to refresh
  /// it.
  final ValueNotifier<int> removals = ValueNotifier(0);

  /// Read the rows and the disk, and report where they disagree.
  Future<StorageSurvey> survey() async {
    final copies = await offlineCopies.allCopies();
    final onDisk = fileStore.listCommittedEntryPaths().toSet();
    final claimed = <String>{};

    final held = <HeldCopy>[];
    final missing = <HeldCopy>[];
    final collectionNames = <String, String>{};

    for (final copy in copies) {
      if (!copy.active) continue;
      claimed.add(copy.contentPath);
      final entry = await entries.byId(copy.entryId);
      final collectionId = entry?.collectionId;
      if (collectionId != null && !collectionNames.containsKey(collectionId)) {
        collectionNames[collectionId] =
            (await collections.byId(collectionId))?.name ?? '';
      }
      final present = fileStore.entryExists(copy.contentPath);
      final row = HeldCopy(
        copy: copy,
        title: entry?.title ?? '',
        collectionId: collectionId,
        collectionName: collectionId == null
            ? 'Standalone'
            : collectionNames[collectionId] ?? '',
        finished:
            (await reading.stateOf(copy.entryId)).status ==
            ReadStatus.completed,
        bytes: present ? await fileStore.entryByteSize(copy.contentPath) : 0,
      );
      (present ? held : missing).add(row);
    }

    final orphans = <OrphanPackage>[];
    for (final relative in onDisk) {
      if (claimed.contains(relative)) continue;
      orphans.add(
        OrphanPackage(
          relativePath: relative,
          bytes: await fileStore.entryByteSize(relative),
        ),
      );
    }

    return StorageSurvey(held: held, missing: missing, orphans: orphans);
  }

  /// Free the bytes for [entryIds]: the packages, then the rows.
  ///
  /// The order is the capture lane's and is not this surface's to change —
  /// rows first would leave a package under `library/` that the next survey
  /// would report as an orphan. Returns how many entries were freed.
  Future<int> removeCopiesOf(List<String> entryIds) async {
    var freed = 0;
    for (final id in entryIds) {
      final removed = await removeOfflineCopies(
        entryId: id,
        offlineCopies: offlineCopies,
        fileStore: fileStore,
      );
      if (removed > 0) freed++;
    }
    if (freed > 0) removals.value++;
    return freed;
  }

  /// Discard packages nothing refers to. Files only — there are no rows.
  Future<int> discardOrphans(List<OrphanPackage> orphans) async {
    var removed = 0;
    for (final orphan in orphans) {
      try {
        await fileStore.deleteEntryContent(orphan.relativePath);
        removed++;
      } catch (e) {
        debugPrint('[cleanup] orphan ${orphan.relativePath}: $e');
      }
    }
    if (removed > 0) removals.value++;
    return removed;
  }

  /// Drop copy rows whose package is gone.
  ///
  /// Rows only, and nothing else: the Entry stays in the library with its
  /// reading state, exactly as it does when a copy is removed on purpose.
  Future<int> forgetMissing(List<HeldCopy> rows) async {
    var removed = 0;
    for (final row in rows) {
      removed += await offlineCopies.removeCopies(row.entryId);
    }
    return removed;
  }
}
