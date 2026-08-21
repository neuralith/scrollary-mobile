import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:web_reader/storage/cleanup.dart';
import 'package:web_reader/storage/database.dart';
import 'package:web_reader/storage/file_store.dart';
import 'package:web_reader/storage/manifest.dart';

/// Offline-file removal: the files go, everything that makes the entry a
/// entry stays. This is the contract the whole cleanup feature rests on.
void main() {
  late AppDatabase db;
  late Directory root;
  late FileStore store;
  late CleanupService cleanup;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    root = Directory.systemTemp.createTempSync('webread_cleanup');
    store = FileStore(root);
    Directory(
      p.join(root.path, FileStore.libraryFolderName),
    ).createSync(recursive: true);
    Directory(
      p.join(root.path, FileStore.tmpFolderName),
    ).createSync(recursive: true);
    cleanup = CleanupService(
      db: db,
      fileStore: store,
      undoWindow: const Duration(milliseconds: 200),
    );
  });
  tearDown(() async {
    await db.close();
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  Future<void> seedCollection() => db.upsertCollection(
    Collection(
      contentKind: 'unknownWebContent',
      sequenceKind: 'none',
      orderingBasis: 'discoveryOrder',
      shapeConfidence: 'low',
      lifecycle: 'active',
      id: 's1',
      title: 'Foo',
      sourceUrl: 'https://x.example/guide/foo',
      host: 'x.example',
      collectionKey: '/guide/foo',
      createdAt: DateTime(2026, 7, 1),
    ),
  );

  /// A committed entry with real files, fully read by default.
  Future<Entry> seedEntry(
    int n, {
    String readStatus = 'completed',
    String saveStatus = 'complete',
  }) async {
    final id = 'c$n';
    final staging = await store.beginEntry(collectionId: 's1', entryId: id);
    for (var i = 1; i <= 3; i++) {
      await staging.assetFile('00$i.png').writeAsBytes(List.filled(500, 7));
    }
    final relative = await store.commit(
      staging,
      EntryManifest(
        schemaVersion: EntryManifest.currentSchemaVersion,
        entryId: id,
        collectionId: 's1',
        sourceUrl: 'https://x.example/guide/foo/$n',
        title: 'Foo Entry $n',
        savedAt: DateTime(2026, 7, 20),
        status: SaveStatus.complete,
        detectedAssetCount: 3,
        storedAssetCount: 3,
        assets: const [],
      ),
    );
    final entry = Entry(
      host: '',
      contentKind: 'unknownWebContent',
      contentKindConfidence: 'low',
      contentKindIsUserSet: false,
      id: id,
      collectionId: 's1',
      title: 'Foo Entry $n',
      sourceUrl: 'https://x.example/guide/foo/$n',
      urlKey: 'https://x.example/guide/foo/$n',
      artifactFormat: 'imageSequence',
      saveStatus: saveStatus,
      contentPath: relative,
      savedAt: DateTime(2026, 7, 20),
      detectedAssetCount: 3,
      storedAssetCount: 3,
      entryOrder: n,
      byteSize: 1500,
      entryNumber: n.toDouble(),
      sourceMarker: 'Entry $n',
      readStatus: readStatus,
      progressFraction: readStatus == 'completed' ? 1 : 0.42,
      progressPageIndex: 2,
      progressOffsetInPage: 0.25,
      firstOpenedAt: DateTime(2026, 7, 21),
      lastReadAt: DateTime(2026, 7, 22),
      completedAt: readStatus == 'completed' ? DateTime(2026, 7, 22) : null,
      discoveredAt: DateTime(2026, 7, 19),
      discoveryBasis: 'entryList',
      discoveryConfidence: 'high',
    );
    await db.upsertEntry(entry);
    return entry;
  }

  test('files go; every piece of metadata stays', () async {
    await seedCollection();
    final before = await seedEntry(1);
    final dir = Directory(store.resolve(before.contentPath!));
    expect(dir.existsSync(), isTrue);

    final result = await cleanup.removeOffline([before.id]);
    expect(result.removed, 1);
    expect(result.freedBytes, 1500);

    final after = (await db.entryById('c1'))!;
    expect(after.contentPath, isNull, reason: 'no longer offline');
    expect(after.byteSize, 0);
    expect(after.offlineRemovedAt, isNotNull, reason: 'user removal recorded');

    // Everything that must survive.
    expect(after.collectionId, before.collectionId);
    expect(after.sourceUrl, before.sourceUrl);
    expect(after.urlKey, before.urlKey);
    expect(after.entryOrder, before.entryOrder);
    expect(after.entryNumber, before.entryNumber);
    expect(after.sourceMarker, before.sourceMarker);
    expect(after.readStatus, 'completed');
    expect(after.progressFraction, before.progressFraction);
    expect(after.progressPageIndex, before.progressPageIndex);
    expect(after.completedAt, before.completedAt);
    expect(after.lastReadAt, before.lastReadAt);
    expect(after.firstOpenedAt, before.firstOpenedAt);
    expect(after.discoveredAt, before.discoveredAt);
    expect(after.discoveryBasis, before.discoveryBasis);
    // The collection itself is untouched.
    expect(await db.collectionById('s1'), isNotNull);
  });

  test('the entry can be saved again afterwards', () async {
    await seedCollection();
    final entry = await seedEntry(1);
    await cleanup.removeOffline([entry.id]);
    expect((await db.entryById('c1'))!.contentPath, isNull);

    // A re-save writes the row and explicitly clears the removed marker
    // (drift's upsert treats a null field as "leave it alone", so the engine
    // clears it deliberately — see AppDatabase.clearOfflineRemovedMark).
    await db.upsertEntry(
      entry.copyWith(contentPath: Value(entry.contentPath), byteSize: 1500),
    );
    await db.clearOfflineRemovedMark(entry.id);
    final resaved = (await db.entryById('c1'))!;
    expect(resaved.contentPath, isNotNull);
    expect(resaved.offlineRemovedAt, isNull);
    expect(resaved.readStatus, 'completed', reason: 'history survived');
  });

  test('undo restores both the files and the row', () async {
    await seedCollection();
    final entry = await seedEntry(1);
    final dir = Directory(store.resolve(entry.contentPath!));

    final result = await cleanup.removeOffline([entry.id]);
    expect(dir.existsSync(), isFalse, reason: 'moved aside');
    expect(result.canUndo, isTrue);

    await result.undo.undo();
    expect(dir.existsSync(), isTrue, reason: 'files are back');
    final after = (await db.entryById('c1'))!;
    expect(after.contentPath, entry.contentPath);
    expect(after.byteSize, 1500);
    expect(after.offlineRemovedAt, isNull);
  });

  test('after the undo window the files are really gone', () async {
    await seedCollection();
    final entry = await seedEntry(1);
    final dir = Directory(store.resolve(entry.contentPath!));

    final result = await cleanup.removeOffline([entry.id]);
    await Future<void>.delayed(const Duration(milliseconds: 400));

    expect(result.canUndo, isFalse);
    expect(dir.existsSync(), isFalse);
    final undoDir = Directory(
      p.join(root.path, FileStore.tmpFolderName, 'undo-c1'),
    );
    expect(undoDir.existsSync(), isFalse, reason: 'staging cleaned');
  });

  test('an entry open in the reader cannot be removed', () async {
    await seedCollection();
    final entry = await seedEntry(1);
    cleanup.openReaderEntryId.value = entry.id;

    expect(await cleanup.lockReasonFor(entry), 'open in the reader');
    final result = await cleanup.removeOffline([entry.id]);

    expect(result.removed, 0);
    expect(result.keptLocked, hasLength(1));
    expect(result.keptLocked.single, contains('open in the reader'));
    expect((await db.entryById('c1'))!.contentPath, isNotNull);
    expect(Directory(store.resolve(entry.contentPath!)).existsSync(), isTrue);
  });

  test('an entry being saved cannot be removed', () async {
    await seedCollection();
    final entry = await seedEntry(1, saveStatus: 'saving');
    expect(await cleanup.lockReasonFor(entry), 'being saved');
    final result = await cleanup.removeOffline([entry.id]);
    expect(result.removed, 0, reason: 'not even eligible');
  });

  test('bulk removal reports progress and skips locked entries', () async {
    await seedCollection();
    for (var n = 1; n <= 5; n++) {
      await seedEntry(n);
    }
    cleanup.openReaderEntryId.value = 'c3';

    final progress = <(int, int)>[];
    final result = await cleanup.removeOfflineNow([
      'c1',
      'c2',
      'c3',
      'c4',
      'c5',
    ], onProgress: (processed, freed) => progress.add((processed, freed)));

    expect(result.removed, 4, reason: 'c3 was open');
    expect(result.freedBytes, 4 * 1500);
    expect(result.keptLocked, hasLength(1));
    expect(progress, isNotEmpty, reason: 'observable while it runs');
    expect((await db.entryById('c3'))!.contentPath, isNotNull);
    for (final id in ['c1', 'c2', 'c4', 'c5']) {
      expect((await db.entryById(id))!.contentPath, isNull);
      expect((await db.entryById(id))!.readStatus, 'completed');
    }
  });

  test('a bulk removal stops between entries when asked (D64)', () async {
    await seedCollection();
    for (var n = 1; n <= 5; n++) {
      await seedEntry(n);
    }

    // Stop after the second entry — the boundary the queue's Cancel uses.
    var processedSoFar = 0;
    final result = await cleanup.removeOfflineNow(
      ['c1', 'c2', 'c3', 'c4', 'c5'],
      onProgress: (processed, _) => processedSoFar = processed,
      shouldContinue: () => processedSoFar < 2,
    );

    expect(result.removed, 2);
    expect(result.stoppedEarly, isTrue, reason: 'and it says so');
    for (final id in ['c1', 'c2']) {
      expect((await db.entryById(id))!.contentPath, isNull);
    }
    for (final id in ['c3', 'c4', 'c5']) {
      final entry = (await db.entryById(id))!;
      expect(
        entry.contentPath,
        isNotNull,
        reason: 'never reached — the files are still there',
      );
      expect(Directory(store.resolve(entry.contentPath!)).existsSync(), isTrue);
      expect(entry.offlineRemovedAt, isNull, reason: 'and nothing was marked');
    }
  });

  test('a removal that is never asked to stop runs to the end', () async {
    await seedCollection();
    for (var n = 1; n <= 3; n++) {
      await seedEntry(n);
    }
    final result = await cleanup.removeOfflineNow([
      'c1',
      'c2',
      'c3',
    ], shouldContinue: () => true);
    expect(result.removed, 3);
    expect(result.stoppedEarly, isFalse);
  });

  test(
    'removing an entry whose files already vanished still records it',
    () async {
      await seedCollection();
      final entry = await seedEntry(1);
      Directory(store.resolve(entry.contentPath!)).deleteSync(recursive: true);

      final result = await cleanup.removeOffline([entry.id]);
      expect(result.removed, 1);
      expect((await db.entryById('c1'))!.offlineRemovedAt, isNotNull);
    },
  );

  group('the per-collection cleanup preference', () {
    Future<CollectionCleanupPreference?> prefOf(String id) async =>
        collectionCleanupFromName(
          (await db.collectionById(id))!.cleanupPreference,
        );

    Future<void> seedSecondCollection() => db.upsertCollection(
      Collection(
        contentKind: 'unknownWebContent',
        sequenceKind: 'none',
        orderingBasis: 'discoveryOrder',
        shapeConfidence: 'low',
        lifecycle: 'active',
        id: 's2',
        title: 'Bar',
        sourceUrl: 'https://x.example/guide/bar',
        host: 'x.example',
        collectionKey: '/guide/bar',
        createdAt: DateTime(2026, 7, 2),
      ),
    );

    test('a new collection has no decision', () async {
      await seedCollection();
      expect(await prefOf('s1'), isNull);
    });

    test('stores, reads back, and resets to undecided', () async {
      await seedCollection();
      await db.setCollectionCleanupPreference(
        's1',
        CollectionCleanupPreference.remove.name,
      );
      expect(await prefOf('s1'), CollectionCleanupPreference.remove);

      await db.setCollectionCleanupPreference(
        's1',
        CollectionCleanupPreference.keep.name,
      );
      expect(await prefOf('s1'), CollectionCleanupPreference.keep);

      // "Ask again next time" — a null that must actually reach the column.
      await db.setCollectionCleanupPreference('s1', null);
      expect(await prefOf('s1'), isNull);
    });

    test('each collection carries its own, and resets independently', () async {
      await seedCollection();
      await seedSecondCollection();

      await db.setCollectionCleanupPreference(
        's1',
        CollectionCleanupPreference.remove.name,
      );
      await db.setCollectionCleanupPreference(
        's2',
        CollectionCleanupPreference.keep.name,
      );
      expect(await prefOf('s1'), CollectionCleanupPreference.remove);
      expect(await prefOf('s2'), CollectionCleanupPreference.keep);

      await db.setCollectionCleanupPreference('s1', null);
      expect(await prefOf('s1'), isNull);
      expect(
        await prefOf('s2'),
        CollectionCleanupPreference.keep,
        reason: 'resetting one collection says nothing about another',
      );
    });

    test('an unknown or empty stored value reads as undecided', () async {
      await seedCollection();
      for (final stored in ['nonsense', '', 'ask', 'REMOVE']) {
        await db.setCollectionCleanupPreference('s1', stored);
        expect(
          await prefOf('s1'),
          isNull,
          reason: '"$stored" is not a decision; ask rather than guess',
        );
      }
    });

    test(
      'the obsolete global key is not a decision for any collection',
      () async {
        await seedCollection();
        await seedSecondCollection();
        for (final stale in ['remove', 'keep', 'ask', 'nonsense']) {
          await db.setSetting('storage.afterFinished', stale);
          expect(await prefOf('s1'), isNull);
          expect(await prefOf('s2'), isNull);
        }
      },
    );

    test('changing it never touches already-stored entries', () async {
      await seedCollection();
      final entry = await seedEntry(1);
      await db.setCollectionCleanupPreference(
        's1',
        CollectionCleanupPreference.remove.name,
      );
      // The decision is a rule for future transitions, not a command.
      expect((await db.entryById(entry.id))!.contentPath, isNotNull);
      expect(Directory(store.resolve(entry.contentPath!)).existsSync(), isTrue);
    });
  });

  group('across a restart', () {
    test('each collection keeps its own decision, on disk', () async {
      final file = File(p.join(root.path, 'restart.sqlite'));
      var reopened = AppDatabase.forTesting(NativeDatabase(file));
      for (final (id, title) in [('s1', 'Foo'), ('s2', 'Bar')]) {
        await reopened.upsertCollection(
          Collection(
            contentKind: 'unknownWebContent',
            sequenceKind: 'none',
            orderingBasis: 'discoveryOrder',
            shapeConfidence: 'low',
            lifecycle: 'active',
            id: id,
            title: title,
            sourceUrl: 'https://x.example/guide/$id',
            host: 'x.example',
            collectionKey: '/guide/$id',
            createdAt: DateTime(2026, 7, 1),
          ),
        );
      }
      await reopened.setCollectionCleanupPreference(
        's1',
        CollectionCleanupPreference.remove.name,
      );
      await reopened.setCollectionCleanupPreference(
        's2',
        CollectionCleanupPreference.keep.name,
      );
      await reopened.close();

      // A second process opening the same file — the restart case.
      reopened = AppDatabase.forTesting(NativeDatabase(file));
      expect(
        (await reopened.collectionById('s1'))!.cleanupPreference,
        CollectionCleanupPreference.remove.name,
      );
      expect(
        (await reopened.collectionById('s2'))!.cleanupPreference,
        CollectionCleanupPreference.keep.name,
      );

      await reopened.setCollectionCleanupPreference('s2', null);
      await reopened.close();

      reopened = AppDatabase.forTesting(NativeDatabase(file));
      expect(
        (await reopened.collectionById('s2'))!.cleanupPreference,
        isNull,
        reason: 'a reset survives too — it is a stored null, not a gap',
      );
      await reopened.close();
    });
  });
}
