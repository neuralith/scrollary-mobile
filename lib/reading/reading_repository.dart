import 'package:drift/drift.dart' show Value;

import '../features/collection_detail_screen.dart' show sortEntriesForReading;
import '../storage/database.dart';
import 'reading_position.dart';

/// Reads and writes reading state, and keeps the collection pointers honest.
///
/// The invariant everything else leans on: **save never touches reading
/// state, and reading never touches save state.** An entry can be
/// re-downloaded and stay exactly where the user was.
class ReadingRepository {
  ReadingRepository(this.db);

  final AppDatabase db;

  /// All writes go through one queue.
  ///
  /// Every write here is read-modify-write, and the reader flushes from four
  /// places (debounce, dwell completion, lifecycle change, dispose) without
  /// awaiting each other. Unserialized, a stale in-flight save could read
  /// "not completed", lose the race, and write over a completion that had
  /// already landed. The queue makes the outcome the call order, always —
  /// which is also what guarantees a pending write cannot clobber a newer one.
  ///
  /// Null when idle, and an idle write starts *synchronously* in the caller's
  /// zone. Not an optimisation: an unconditional `.then` hop deadlocks under
  /// a widget test's fake-async zone when awaited before the first pump.
  Future<void>? _writeQueue;

  Future<T> _serialized<T>(Future<T> Function() action) {
    final previous = _writeQueue;
    final result = previous == null ? action() : previous.then((_) => action());
    Future<void>? entry;
    // Keep the chain alive even when a write fails, and let it drain so the
    // next uncontended write starts synchronously again.
    entry = result.then<void>((_) {}, onError: (_) {})
      ..whenComplete(() {
        if (identical(_writeQueue, entry)) _writeQueue = null;
      });
    _writeQueue = entry;
    return result;
  }

  // --- reading an entry ---------------------------------------------------

  /// Opening an entry records that it was opened. It does **not** mark it
  /// read — that would make "I glanced at it" indistinguishable from "I
  /// finished it".
  Future<void> markOpened(String entryId) => _serialized(() async {
    final entry = await db.entryById(entryId);
    if (entry == null) return;
    final now = DateTime.now();

    await db.writeEntryReading(
      entryId,
      EntriesCompanion(
        firstOpenedAt: Value(entry.firstOpenedAt ?? now),
        lastReadAt: Value(now),
        // A completed entry that is reopened stays completed until the user
        // says otherwise.
        readStatus: Value(
          entry.readStatus == ReadStatus.completed.name
              ? entry.readStatus
              : ReadStatus.inProgress.name,
        ),
      ),
    );
    await _refreshCollectionPointers(
      entry.collectionId,
      openedEntryId: entryId,
    );
  });

  Future<void> saveProgress(
    String entryId,
    ReadingPosition position, {
    bool completed = false,
  }) => _serialized(() async {
    final entry = await db.entryById(entryId);
    if (entry == null) return;
    final now = DateTime.now();

    final alreadyCompleted = entry.readStatus == ReadStatus.completed.name;
    final becomesCompleted = completed || alreadyCompleted;

    await db.writeEntryReading(
      entryId,
      EntriesCompanion(
        // The anchor keeps following the scroll — resuming a finished entry
        // still lands where the reader actually is — but the *fraction* obeys
        // the completed-is-100% rule.
        progressFraction: Value(
          becomesCompleted ? 1.0 : position.fraction.clamp(0.0, 1.0),
        ),
        progressPageIndex: Value(position.anchorIndex),
        progressOffsetInPage: Value(position.offsetInAnchor.clamp(0.0, 1.0)),
        lastReadAt: Value(now),
        progressUpdatedAt: Value(now),
        readStatus: Value(
          becomesCompleted
              ? ReadStatus.completed.name
              : ReadStatus.inProgress.name,
        ),
        completedAt: Value(
          becomesCompleted ? (entry.completedAt ?? now) : null,
        ),
      ),
    );
    await _refreshCollectionPointers(
      entry.collectionId,
      openedEntryId: entryId,
    );
  });

  /// Explicit "I have read this", regardless of where the scroll is.
  Future<void> markRead(String entryId) => _serialized(() async {
    final entry = await db.entryById(entryId);
    if (entry == null) return;
    final now = DateTime.now();
    await db.writeEntryReading(
      entryId,
      EntriesCompanion(
        readStatus: Value(ReadStatus.completed.name),
        completedAt: Value(entry.completedAt ?? now),
        lastReadAt: Value(now),
        // Jump the bar to the end so a manually-read entry does not still
        // look half finished.
        progressFraction: const Value(1),
      ),
    );
    await _refreshCollectionPointers(
      entry.collectionId,
      openedEntryId: entryId,
    );
  });

  /// Explicit "I have not read this".
  ///
  /// Keeps the *anchor*: the user is saying it is unfinished, not that they
  /// were never there, so resuming still lands where they got to. The
  /// fraction, though, is dropped back to zero when the entry was
  /// completed — completion had forced it to 100% (see [readProgressFor]), so
  /// leaving it there would show a full bar on an entry marked unread.
  Future<void> markUnread(String entryId) => _serialized(() async {
    final entry = await db.entryById(entryId);
    if (entry == null) return;
    final wasCompleted = entry.readStatus == ReadStatus.completed.name;
    await db.writeEntryReading(
      entryId,
      EntriesCompanion(
        readStatus: const Value('unread'),
        completedAt: const Value(null),
        progressFraction: wasCompleted ? const Value(0) : const Value.absent(),
        // Stamped so a progress write that was already in flight when the
        // user tapped is recognisable as the older one.
        progressUpdatedAt: Value(DateTime.now()),
      ),
    );
    await _refreshCollectionPointers(entry.collectionId);
  });

  ReadingPosition positionOf(Entry entry) => ReadingPosition(
    fraction: entry.progressFraction,
    anchorIndex: entry.progressPageIndex,
    offsetInAnchor: entry.progressOffsetInPage,
  );

  // --- collection pointers -----------------------------------------------------

  /// Recompute a collection's denormalised reading pointers from its entries.
  ///
  /// Cheap (one collection's rows) and always correct, so it runs after every
  /// change rather than being incrementally patched — incremental pointer maths
  /// is exactly the sort of thing that drifts out of sync. A null
  /// [collectionId] is an ordinary case, not an error: standalone entries have
  /// no pointers to refresh.
  Future<void> _refreshCollectionPointers(
    String? collectionId, {
    String? openedEntryId,
  }) async {
    // A standalone entry has no collection to point at. Its own reading columns
    // are the whole record, and they were just written by the caller.
    if (collectionId == null) return;
    final entries = await db.entriesForCollection(collectionId);
    if (entries.isEmpty) return;

    DateTime? lastRead;
    Entry? lastCompleted;
    for (final c in entries) {
      final at = c.lastReadAt;
      if (at != null && (lastRead == null || at.isAfter(lastRead))) {
        lastRead = at;
      }
      if (c.readStatus == ReadStatus.completed.name) {
        final completedAt = c.completedAt;
        if (lastCompleted == null ||
            (completedAt != null &&
                (lastCompleted.completedAt == null ||
                    completedAt.isAfter(lastCompleted.completedAt!)))) {
          lastCompleted = c;
        }
      }
    }

    // The most recently opened entry, unless this call names one.
    String? lastOpened = openedEntryId;
    if (lastOpened == null) {
      DateTime? newest;
      for (final c in entries) {
        final at = c.lastReadAt;
        if (at == null) continue;
        // `!isBefore` rather than `isAfter`: two writes can land in the same
        // millisecond, and on a tie the later entry in reading order is the
        // one the reader is actually on.
        if (newest == null || !at.isBefore(newest)) {
          newest = at;
          lastOpened = c.id;
        }
      }
    }

    await db.writeCollectionReading(
      collectionId,
      CollectionsCompanion(
        lastOpenedEntryId: Value(lastOpened),
        lastCompletedEntryId: Value(lastCompleted?.id),
        lastReadAt: Value(lastRead),
      ),
    );
  }

  /// Rebuild every collection's pointers from its entries.
  ///
  /// Not a migration: the pointers are a denormalised cache of the entry rows,
  /// and this is the routine that makes the cache reconstructible after a bulk
  /// operation (a batch cleanup, a re-grouping) touched many rows at once.
  Future<void> rebuildCollectionPointers() async {
    for (final collection in await db.allCollections()) {
      await _refreshCollectionPointers(collection.id);
    }
  }
}

/// What the library needs to know about one collection's reading state.
///
/// Derived rather than stored, apart from the ordering pointers: counts drift
/// the moment an edge case is missed, and at these row counts deriving is free.
class CollectionReadingState {
  const CollectionReadingState({
    required this.entries,
    this.currentEntry,
    this.nextUnread,
    this.lastCompleted,
    this.lastReadAt,
  });

  /// Entries that are actually readable offline, in reading order.
  final List<Entry> entries;

  /// The unfinished entry to resume, if any.
  final Entry? currentEntry;

  /// The next readable entry the user has not finished.
  final Entry? nextUnread;
  final Entry? lastCompleted;
  final DateTime? lastReadAt;

  /// What "Continue Reading" should open: the unfinished entry, else the
  /// next unread one.
  Entry? get continueEntry => currentEntry ?? nextUnread;

  bool get hasSomethingToRead => continueEntry != null;
  bool get everOpened => lastReadAt != null;

  int get unreadCount =>
      entries.where((c) => c.readStatus != ReadStatus.completed.name).length;

  bool get allCompleted => entries.isNotEmpty && unreadCount == 0;

  double get currentProgress {
    final c = currentEntry;
    return c == null
        ? 0
        : readProgressFor(readStatus: c.readStatus, stored: c.progressFraction);
  }
}

/// Work out a collection's reading state from its entries.
///
/// Only locally readable entries count. An entry known to exist on the
/// source but not stored cannot be continued into, so offering it would send
/// the reader somewhere it cannot go.
CollectionReadingState computeCollectionReadingState(List<Entry> allEntries) {
  final readable = sortEntriesForReading(
    allEntries
        .where(
          (c) =>
              c.contentPath != null &&
              (c.saveStatus == 'complete' || c.saveStatus == 'partial'),
        )
        .toList(),
  );

  if (readable.isEmpty) return const CollectionReadingState(entries: []);

  DateTime? lastReadAt;
  Entry? lastCompleted;
  for (final c in readable) {
    final at = c.lastReadAt;
    if (at != null && (lastReadAt == null || at.isAfter(lastReadAt))) {
      lastReadAt = at;
    }
    if (c.readStatus == ReadStatus.completed.name) lastCompleted = c;
  }

  // An unfinished entry the user actually started. Most recently read wins,
  // so jumping back to an earlier entry resumes there.
  Entry? current;
  DateTime? currentRead;
  for (final c in readable) {
    if (c.readStatus != ReadStatus.inProgress.name) continue;
    final at = c.lastReadAt;
    if (current == null ||
        (at != null && (currentRead == null || at.isAfter(currentRead)))) {
      current = c;
      currentRead = at;
    }
  }

  // Otherwise the earliest entry not yet finished — which after completing
  // entry 1 is entry 2.
  Entry? nextUnread;
  for (final c in readable) {
    if (c.readStatus == ReadStatus.completed.name) continue;
    if (identical(c, current)) continue;
    nextUnread = c;
    break;
  }

  return CollectionReadingState(
    entries: readable,
    currentEntry: current,
    nextUnread: nextUnread,
    lastCompleted: lastCompleted,
    lastReadAt: lastReadAt,
  );
}
