import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_reader/storage/database.dart';

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() => db.close());

  Collection item(String id) => Collection(
    contentKind: 'unknownWebContent',
    sequenceKind: 'none',
    orderingBasis: 'discoveryOrder',
    shapeConfidence: 'low',
    lifecycle: 'active',
    id: id,
    title: 'Fixture image sequence',
    sourceUrl: 'http://localhost:8099/entry',
    host: 'localhost',
    createdAt: DateTime(2026, 7, 25),
  );

  Entry entry(
    String id,
    String itemId, {
    int entryOrder = 1,
    String status = 'complete',
    String? urlKey,
  }) => Entry(
    host: 'localhost',
    contentKind: 'unknownWebContent',
    contentKindConfidence: 'low',
    contentKindIsUserSet: false,
    readStatus: 'unread',
    progressFraction: 0,
    progressPageIndex: 0,
    progressOffsetInPage: 0,
    id: id,
    collectionId: itemId,
    title: 'Entry $entryOrder',
    sourceUrl: 'http://localhost:8099/entry/$entryOrder',
    urlKey: urlKey ?? 'http://localhost:8099/entry/$entryOrder',
    artifactFormat: 'imageSequence',
    saveStatus: status,
    contentPath: 'library/$itemId/entries/$id',
    savedAt: DateTime(2026, 7, 25, 12, entryOrder),
    detectedAssetCount: 6,
    storedAssetCount: 6,
    entryOrder: entryOrder,
    byteSize: 1024,
  );

  test('insert and read back a library item', () async {
    await db.upsertCollection(item('item-1'));

    final found = await db.findCollectionBySourceUrl(
      'http://localhost:8099/entry',
    );
    expect(found, isNotNull);
    expect(found!.title, 'Fixture image sequence');
    expect(found.host, 'localhost');
  });

  test('entries are returned in save-chain order', () async {
    await db.upsertCollection(item('item-1'));
    // Insert out of order on purpose.
    await db.upsertEntry(entry('c3', 'item-1', entryOrder: 3));
    await db.upsertEntry(entry('c1', 'item-1', entryOrder: 1));
    await db.upsertEntry(entry('c2', 'item-1', entryOrder: 2));

    final entries = await db.entriesForCollection('item-1');
    expect(entries.map((c) => c.entryOrder), [1, 2, 3]);
    expect(entries.map((c) => c.id), ['c1', 'c2', 'c3']);
  });

  test('the same urlKey cannot be saved twice for one item', () async {
    await db.upsertCollection(item('item-1'));
    await db.upsertEntry(entry('c1', 'item-1', entryOrder: 1));

    final duplicate = entry(
      'c-other',
      'item-1',
      entryOrder: 9,
    ).copyWith(urlKey: 'http://localhost:8099/entry/1');

    await expectLater(db.upsertEntry(duplicate), throwsA(isA<Exception>()));
  });

  test('findEntryByUrlKey locates an existing save', () async {
    await db.upsertCollection(item('item-1'));
    await db.upsertEntry(entry('c1', 'item-1', entryOrder: 1));

    final found = await db.findEntryByUrlKey(
      'item-1',
      'http://localhost:8099/entry/1',
    );
    expect(found?.id, 'c1');

    final missing = await db.findEntryByUrlKey(
      'item-1',
      'http://localhost:8099/nope',
    );
    expect(missing, isNull);
  });

  test(
    'resetInFlightEntries demotes interrupted saves, never promotes',
    () async {
      await db.upsertCollection(item('item-1'));
      await db.upsertEntry(entry('c1', 'item-1', entryOrder: 1));
      await db.upsertEntry(
        entry('c2', 'item-1', entryOrder: 2, status: 'saving'),
      );

      final reset = await db.resetInFlightEntries();
      expect(reset, 1);

      final interrupted = await db.entryById('c2');
      expect(interrupted!.saveStatus, 'failed');
      expect(interrupted.saveError, contains('interrupted'));

      // The already-complete entry is untouched.
      final done = await db.entryById('c1');
      expect(done!.saveStatus, 'complete');
    },
  );

  test('markEntryContentMissing keeps the row but drops the path', () async {
    await db.upsertCollection(item('item-1'));
    await db.upsertEntry(entry('c1', 'item-1', entryOrder: 1));

    await db.markEntryContentMissing('c1');

    final row = await db.entryById('c1');
    expect(row, isNotNull, reason: 'history must survive missing files');
    expect(row!.contentPath, isNull);
    expect(row.saveStatus, 'failed');
  });

  test('watchAllEntries emits when an entry commits', () async {
    await db.upsertCollection(item('item-1'));

    final emissions = <int>[];
    final sub = db.watchAllEntries().listen((rows) {
      emissions.add(rows.length);
    });

    await db.upsertEntry(entry('c1', 'item-1', entryOrder: 1));
    await pumpEventQueue();
    await db.upsertEntry(entry('c2', 'item-1', entryOrder: 2));
    await pumpEventQueue();
    await sub.cancel();

    expect(emissions.last, 2);
  });

  group('save runs', () {
    SaveRun run(String id, String state, {int completed = 0}) => SaveRun(
      visitedCanonicals: '',
      origin: 'queue',
      scope: 'fixedCount',
      id: id,
      captureModeIsUserSet: false,
      startUrl: 'http://localhost:8099/entry/1',
      currentUrl: 'http://localhost:8099/entry/2',
      requestedEntries: 3,
      completedEntries: completed,
      state: state,
      visitedUrls: 'http://localhost:8099/entry/1',
      createdAt: DateTime(2026, 7, 25),
      updatedAt: DateTime(2026, 7, 25),
    );

    test('an interrupted run is resumable, a finished one is not', () async {
      await db.upsertRun(run('j1', 'complete', completed: 3));
      expect(await db.findResumableRun(), isNull);

      await db.upsertRun(run('j2', 'downloading', completed: 1));
      final resumable = await db.findResumableRun();
      expect(resumable?.id, 'j2');
      expect(resumable?.completedEntries, 1);
      expect(resumable?.visitedUrls, contains('entry/1'));
    });

    test('cancelled and failed runs are not offered for resume', () async {
      await db.upsertRun(run('j-cancelled', 'cancelled'));
      await db.upsertRun(run('j-failed', 'failed'));
      expect(await db.findResumableRun(), isNull);
    });

    test('deleting a run removes it from the resume list', () async {
      await db.upsertRun(run('j1', 'scrolling'));
      expect(await db.findResumableRun(), isNotNull);
      await db.deleteRun('j1');
      expect(await db.findResumableRun(), isNull);
    });
  });
}
