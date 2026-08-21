import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_reader/reading/reading_position.dart';
import 'package:web_reader/reading/reading_repository.dart';
import 'package:web_reader/storage/database.dart';

void main() {
  late AppDatabase db;
  late ReadingRepository reading;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    reading = ReadingRepository(db);
  });
  tearDown(() => db.close());

  Future<void> seed({int entries = 3, String status = 'complete'}) async {
    await db.upsertCollection(
      Collection(
        contentKind: 'unknownWebContent',
        sequenceKind: 'none',
        orderingBasis: 'discoveryOrder',
        shapeConfidence: 'low',
        lifecycle: 'active',
        id: 'collection-1',
        title: 'Fixture Collection',
        sourceUrl: 'https://x.example/guide/foo',
        host: 'x.example',
        collectionKey: '/guide/foo',
        createdAt: DateTime(2026, 7, 1),
      ),
    );
    for (var n = 1; n <= entries; n++) {
      await db.upsertEntry(
        Entry(
          host: '',
          contentKind: 'unknownWebContent',
          contentKindConfidence: 'low',
          contentKindIsUserSet: false,
          id: 'c$n',
          collectionId: 'collection-1',
          title: 'Fixture Collection Entry $n',
          sourceUrl: 'https://x.example/guide/foo/$n',
          urlKey: 'https://x.example/guide/foo/$n',
          artifactFormat: 'imageSequence',
          saveStatus: status,
          contentPath: 'library/collection-1/entries/c$n',
          savedAt: DateTime(2026, 7, 20),
          detectedAssetCount: 6,
          storedAssetCount: 6,
          entryOrder: n,
          byteSize: 1024,
          entryNumber: n.toDouble(),
          sourceMarker: 'Entry $n',
          readStatus: 'unread',
          progressFraction: 0,
          progressPageIndex: 0,
          progressOffsetInPage: 0,
        ),
      );
    }
  }

  group('opening an entry', () {
    test('records that it was opened but does not mark it read', () async {
      await seed();
      await reading.markOpened('c1');

      final entry = await db.entryById('c1');
      expect(entry!.readStatus, ReadStatus.inProgress.name);
      expect(entry.firstOpenedAt, isNotNull);
      expect(entry.lastReadAt, isNotNull);
      expect(
        entry.completedAt,
        isNull,
        reason: 'glancing at an entry is not finishing it',
      );
    });

    test('reopening a completed entry leaves it completed', () async {
      await seed();
      await reading.markRead('c1');
      await reading.markOpened('c1');

      final entry = await db.entryById('c1');
      expect(entry!.readStatus, ReadStatus.completed.name);
    });

    test('updates the collection pointers', () async {
      await seed();
      await reading.markOpened('c2');

      final collection = (await db.collectionById('collection-1'))!;
      expect(collection.lastOpenedEntryId, 'c2');
      expect(collection.lastReadAt, isNotNull);
    });
  });

  group('saving progress', () {
    test('stores the anchor and the fraction together', () async {
      await seed();
      await reading.saveProgress(
        'c1',
        const ReadingPosition(
          fraction: 0.42,
          anchorIndex: 3,
          offsetInAnchor: 0.25,
        ),
      );

      final entry = await db.entryById('c1');
      expect(entry!.progressFraction, closeTo(0.42, 0.001));
      expect(entry.progressPageIndex, 3);
      expect(entry.progressOffsetInPage, closeTo(0.25, 0.001));
      expect(entry.readStatus, ReadStatus.inProgress.name);
      expect(entry.progressUpdatedAt, isNotNull);
    });

    test('completes when told to, and records when', () async {
      await seed();
      await reading.saveProgress(
        'c1',
        const ReadingPosition(fraction: 0.98, anchorIndex: 5),
        completed: true,
      );

      final entry = await db.entryById('c1');
      expect(entry!.readStatus, ReadStatus.completed.name);
      expect(entry.completedAt, isNotNull);
    });

    test(
      'a completed entry keeps its completion when scrolled again',
      () async {
        await seed();
        await reading.markRead('c1');
        final firstCompletion = (await db.entryById('c1'))!.completedAt;

        await reading.saveProgress(
          'c1',
          const ReadingPosition(fraction: 0.2, anchorIndex: 1),
        );

        final entry = await db.entryById('c1');
        expect(entry!.readStatus, ReadStatus.completed.name);
        expect(entry.completedAt, firstCompletion);
        expect(
          entry.progressPageIndex,
          1,
          reason: 'the anchor still tracks where they actually are',
        );
        expect(
          entry.progressFraction,
          1,
          reason: 'a finished entry reads 100%, wherever the scroll is',
        );
      },
    );

    test('progress survives being read back after a reopen', () async {
      await seed();
      await reading.saveProgress(
        'c1',
        const ReadingPosition(
          fraction: 0.5,
          anchorIndex: 2,
          offsetInAnchor: 0.5,
        ),
      );

      // What a restart looks like: a fresh repository over the same rows.
      final reloaded = ReadingRepository(db);
      final position = reloaded.positionOf((await db.entryById('c1'))!);

      expect(position.fraction, closeTo(0.5, 0.001));
      expect(position.anchorIndex, 2);
      expect(position.offsetInAnchor, closeTo(0.5, 0.001));
    });
  });

  group('mark read and unread', () {
    test('mark read completes it and fills the bar', () async {
      await seed();
      await reading.markRead('c1');

      final entry = await db.entryById('c1');
      expect(entry!.readStatus, ReadStatus.completed.name);
      expect(entry.progressFraction, 1.0);
      expect(entry.completedAt, isNotNull);
    });

    test('mark unread keeps the position so it can be resumed', () async {
      await seed();
      await reading.saveProgress(
        'c1',
        const ReadingPosition(
          fraction: 0.6,
          anchorIndex: 3,
          offsetInAnchor: 0.4,
        ),
        completed: true,
      );
      await reading.markUnread('c1');

      final entry = await db.entryById('c1');
      expect(entry!.readStatus, ReadStatus.unread.name);
      expect(entry.completedAt, isNull);
      expect(
        entry.progressPageIndex,
        3,
        reason: 'unread means unfinished, not never-visited',
      );
      expect(entry.progressOffsetInPage, closeTo(0.4, 0.001));
      expect(
        entry.progressFraction,
        0,
        reason:
            'completion had forced the bar to 100%; unread empties it '
            'again rather than leaving a full bar on an unread entry',
      );
    });

    test('marking unread moves the collection pointer back', () async {
      await seed();
      await reading.markRead('c1');
      expect(
        (await db.collectionById('collection-1'))!.lastCompletedEntryId,
        'c1',
      );

      await reading.markUnread('c1');
      expect(
        (await db.collectionById('collection-1'))!.lastCompletedEntryId,
        isNull,
      );
    });
  });

  group('collection reading state', () {
    test(
      'an untouched collection has a next entry but nothing in progress',
      () async {
        await seed();
        final state = computeCollectionReadingState(
          await db.entriesForCollection('collection-1'),
        );

        expect(state.currentEntry, isNull);
        expect(state.nextUnread!.id, 'c1');
        expect(state.continueEntry!.id, 'c1');
        expect(state.everOpened, isFalse);
      },
    );

    test('a partly read entry is the one to continue', () async {
      await seed();
      await reading.saveProgress('c1', const ReadingPosition(fraction: 0.5));

      final state = computeCollectionReadingState(
        await db.entriesForCollection('collection-1'),
      );
      expect(state.currentEntry!.id, 'c1');
      expect(state.continueEntry!.id, 'c1');
    });

    test('completing one advances to the next unread', () async {
      await seed();
      await reading.markRead('c1');

      final state = computeCollectionReadingState(
        await db.entriesForCollection('collection-1'),
      );
      expect(state.currentEntry, isNull);
      expect(state.continueEntry!.id, 'c2');
      expect(state.lastCompleted!.id, 'c1');
    });

    test('completing everything leaves nothing to continue', () async {
      await seed();
      for (final id in ['c1', 'c2', 'c3']) {
        await reading.markRead(id);
      }

      final state = computeCollectionReadingState(
        await db.entriesForCollection('collection-1'),
      );
      expect(state.allCompleted, isTrue);
      expect(state.continueEntry, isNull);
      expect(state.unreadCount, 0);
      expect(
        state.lastReadAt,
        isNotNull,
        reason: 'it still belongs in Recently Read',
      );
    });

    test(
      'marking an earlier entry unread makes it continuable again',
      () async {
        await seed();
        for (final id in ['c1', 'c2', 'c3']) {
          await reading.markRead(id);
        }
        await reading.markUnread('c2');

        final state = computeCollectionReadingState(
          await db.entriesForCollection('collection-1'),
        );
        expect(state.allCompleted, isFalse);
        expect(state.continueEntry!.id, 'c2');
      },
    );

    test('an entry that is not stored locally is never offered', () async {
      await seed(entries: 2, status: 'failed');
      final state = computeCollectionReadingState(
        await db.entriesForCollection('collection-1'),
      );
      expect(
        state.continueEntry,
        isNull,
        reason: 'the reader cannot open something that was never saved',
      );
      expect(state.entries, isEmpty);
    });

    test('a partial save is still readable and still counts', () async {
      await seed(entries: 1, status: 'partial');
      final state = computeCollectionReadingState(
        await db.entriesForCollection('collection-1'),
      );
      expect(state.continueEntry!.id, 'c1');
    });
  });

  group('save must not disturb reading', () {
    test(
      'rebuildCollectionPointers rebuilds pointers from the entries',
      () async {
        await seed();
        await reading.markRead('c1');
        await reading.saveProgress('c2', const ReadingPosition(fraction: 0.3));

        // Corrupt the denormalised pointers, as a bad migration might.
        await db.writeCollectionReading(
          'collection-1',
          const CollectionsCompanion(
            lastOpenedEntryId: Value('nonsense'),
            lastCompletedEntryId: Value('nonsense'),
          ),
        );

        await reading.rebuildCollectionPointers();

        final collection = (await db.collectionById('collection-1'))!;
        expect(collection.lastCompletedEntryId, 'c1');
        expect(collection.lastOpenedEntryId, 'c2');
      },
    );
  });

  group('write serialization (lifecycle safety)', () {
    // The reader flushes from four places — debounce, dwell completion,
    // lifecycle change, dispose — without awaiting each other. Every write
    // here is read-modify-write, so ordering is the whole game: a stale
    // in-flight save landing late must not overwrite a newer state.

    test('a stale unawaited save cannot undo a completion', () async {
      await seed();

      // Fired together, no awaits in between: the completion write and a
      // plain progress write that (unserialized) could read "not completed"
      // before the first write lands and then clobber it.
      final f1 = reading.saveProgress(
        'c1',
        const ReadingPosition(fraction: 0.99, anchorIndex: 5),
        completed: true,
      );
      final f2 = reading.saveProgress(
        'c1',
        const ReadingPosition(fraction: 0.98, anchorIndex: 5),
      );
      await Future.wait([f1, f2]);

      final entry = (await db.entryById('c1'))!;
      expect(entry.readStatus, 'completed');
      expect(entry.completedAt, isNotNull);
      expect(
        entry.progressPageIndex,
        5,
        reason: 'the later position still wins',
      );
      expect(
        entry.progressFraction,
        1,
        reason: 'the completion sticks, and completed means 100%',
      );
    });

    test('interleaved writes resolve in call order', () async {
      await seed();

      // markRead then markUnread then a progress save, all in flight at once.
      // Call order is the user's intent; the final state must reflect it.
      final futures = [
        reading.markRead('c1'),
        reading.markUnread('c1'),
        reading.saveProgress(
          'c1',
          const ReadingPosition(fraction: 0.4, anchorIndex: 2),
        ),
      ];
      await Future.wait(futures);

      final entry = (await db.entryById('c1'))!;
      expect(entry.readStatus, 'inProgress');
      expect(entry.completedAt, isNull, reason: 'markUnread cleared it');
      expect(entry.progressFraction, closeTo(0.4, 0.001));
      expect(entry.progressPageIndex, 2);
    });

    test(
      'a delayed progress write cannot un-finish a completed entry',
      () async {
        await seed();
        // The reader's own sequence when someone answers "mark complete and
        // continue": the entry is marked, and a progress write that was already
        // in flight for it lands afterwards carrying `completed: false`.
        await reading.markRead('c1');
        await reading.saveProgress(
          'c1',
          const ReadingPosition(fraction: 0.42, anchorIndex: 1),
        );

        final entry = (await db.entryById('c1'))!;
        expect(entry.readStatus, 'completed');
        expect(entry.completedAt, isNotNull);
        expect(
          entry.progressFraction,
          1,
          reason: 'a completed entry is 100% read, on every write',
        );
        expect(
          entry.progressPageIndex,
          1,
          reason:
              'the anchor still follows the scroll — only the status is fixed',
        );
      },
    );

    test('a failed write does not wedge the queue', () async {
      await seed();
      // A write against a nonexistent entry resolves harmlessly…
      await reading.saveProgress('ghost', const ReadingPosition(fraction: 1));
      // …and the queue still processes what follows.
      await reading.markRead('c1');
      expect((await db.entryById('c1'))!.readStatus, 'completed');
    });
  });
}
