import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:web_reader/save/save_preflight.dart';
import 'package:web_reader/reading/reading_position.dart';
import 'package:web_reader/reading/reading_repository.dart';
import 'package:web_reader/storage/database.dart';
import 'package:web_reader/storage/file_store.dart';
import 'package:web_reader/storage/manifest.dart';

void main() {
  late AppDatabase db;
  late Directory root;
  late FileStore store;
  late SavePreflight preflight;

  const entryUrl = 'https://x.example/guide/foo/883';

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    root = Directory.systemTemp.createTempSync('webread_dup');
    store = FileStore(root);
    Directory(
      p.join(root.path, FileStore.libraryFolderName),
    ).createSync(recursive: true);
    Directory(
      p.join(root.path, FileStore.tmpFolderName),
    ).createSync(recursive: true);
    preflight = SavePreflight(db: db, fileStore: store);
  });

  tearDown(() async {
    await db.close();
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  EntryManifest manifestFor(
    String entryId, {
    SaveStatus status = SaveStatus.complete,
    int assets = 2,
  }) => EntryManifest(
    schemaVersion: 1,
    entryId: entryId,
    collectionId: 'collection-1',
    sourceUrl: entryUrl,
    title: 'Foo 883',
    savedAt: DateTime(2026, 7, 20),
    status: status,
    detectedAssetCount: assets,
    storedAssetCount: assets,
    entryOrder: 1,
    assets: [
      for (var i = 1; i <= assets; i++)
        EntryAsset(
          index: i,
          sourceUrl: 'https://cdn.example/$i.png',
          status: AssetStatus.stored,
          relativePath: 'assets/${i.toString().padLeft(3, '0')}.png',
        ),
    ],
  );

  Future<String> seedSaved({
    String status = 'complete',
    bool withFiles = true,
    String entryId = 'c1',
  }) async {
    await db.upsertCollection(
      Collection(
        contentKind: 'unknownWebContent',
        sequenceKind: 'none',
        orderingBasis: 'discoveryOrder',
        shapeConfidence: 'low',
        lifecycle: 'active',
        id: 'collection-1',
        title: 'Foo',
        sourceUrl: 'https://x.example/guide/foo',
        host: 'x.example',
        collectionKey: '/guide/foo',
        createdAt: DateTime(2026, 7, 1),
      ),
    );

    String? relative;
    if (withFiles) {
      final staging = await store.beginEntry(
        collectionId: 'collection-1',
        entryId: entryId,
      );
      await staging.assetFile('001.png').writeAsBytes([1, 2, 3, 4]);
      await staging.assetFile('002.png').writeAsBytes([5, 6, 7, 8]);
      relative = await store.commit(staging, manifestFor(entryId));
    } else {
      relative = FileStore.entryRelativePath('collection-1', entryId);
    }

    await db.upsertEntry(
      Entry(
        host: '',
        contentKind: 'unknownWebContent',
        contentKindConfidence: 'low',
        contentKindIsUserSet: false,
        id: entryId,
        collectionId: 'collection-1',
        title: 'Foo 883',
        sourceUrl: entryUrl,
        urlKey: entryUrl,
        artifactFormat: 'imageSequence',
        saveStatus: status,
        contentPath: relative,
        savedAt: DateTime(2026, 7, 20),
        detectedAssetCount: 2,
        storedAssetCount: status == 'partial' ? 1 : 2,
        entryOrder: 1,
        byteSize: 8,
        readStatus: 'unread',
        progressFraction: 0,
        progressPageIndex: 0,
        progressOffsetInPage: 0,
      ),
    );
    return relative;
  }

  group('run self-collision', _selfCollisionTests);

  group('preflight classification', () {
    test('an entry never seen is free to save', () async {
      final result = await preflight.inspect(entryUrl);
      expect(result.state, EntryLocalState.none);
      expect(result.needsUserDecision, isFalse);
    });

    test('a complete entry prompts rather than silently skipping', () async {
      await seedSaved();
      final result = await preflight.inspect(entryUrl);

      expect(result.state, EntryLocalState.complete);
      expect(
        result.needsUserDecision,
        isTrue,
        reason: 'the old behaviour logged "already saved" and did nothing',
      );
      expect(result.entry, isNotNull);
    });

    test('a partial entry is distinguished from a complete one', () async {
      await seedSaved(status: 'partial');
      expect(
        (await preflight.inspect(entryUrl)).state,
        EntryLocalState.partial,
      );
    });

    test('a failed entry is not treated as available', () async {
      await seedSaved(status: 'failed', withFiles: false);
      expect((await preflight.inspect(entryUrl)).state, EntryLocalState.failed);
    });

    test(
      'saved in the database but missing on disk is its own state',
      () async {
        await seedSaved(withFiles: false);
        final result = await preflight.inspect(entryUrl);

        expect(result.state, EntryLocalState.filesMissing);
        expect(
          result.existsLocally,
          isFalse,
          reason: 'must never be reported as safely available offline',
        );
      },
    );

    test('an entry owned by an unfinished run blocks a second save', () async {
      await seedSaved();
      await db.upsertRun(
        SaveRun(
          visitedCanonicals: '',
          origin: 'queue',
          scope: 'fixedCount',
          id: 'run-1',
          captureModeIsUserSet: false,
          startUrl: entryUrl,
          currentUrl: entryUrl,
          requestedEntries: 3,
          completedEntries: 1,
          state: 'downloading',
          visitedUrls: entryUrl,
          createdAt: DateTime(2026, 7, 20),
          updatedAt: DateTime(2026, 7, 20),
        ),
      );

      final result = await preflight.inspect(entryUrl);
      expect(result.state, EntryLocalState.inActiveRun);
      expect(result.blockingRun!.id, 'run-1');
      expect(
        result.shouldSaveUnder(DuplicatePolicy.replaceAll),
        isFalse,
        reason: 'two runs on one entry would fight over the same files',
      );
    });
  });

  group('duplicate policy', () {
    EntryPreflight of(EntryLocalState state) =>
        EntryPreflight(state: state, url: entryUrl);

    test('skipComplete leaves saved entries alone but fixes broken ones', () {
      const policy = DuplicatePolicy.skipComplete;
      expect(of(EntryLocalState.complete).shouldSaveUnder(policy), isFalse);
      expect(of(EntryLocalState.partial).shouldSaveUnder(policy), isFalse);
      expect(of(EntryLocalState.failed).shouldSaveUnder(policy), isTrue);
      expect(of(EntryLocalState.filesMissing).shouldSaveUnder(policy), isTrue);
      expect(of(EntryLocalState.none).shouldSaveUnder(policy), isTrue);
    });

    test('retryPartial also re-attempts incomplete entries', () {
      const policy = DuplicatePolicy.retryPartial;
      expect(of(EntryLocalState.partial).shouldSaveUnder(policy), isTrue);
      expect(of(EntryLocalState.complete).shouldSaveUnder(policy), isFalse);
    });

    test('replaceAll re-saves even complete entries', () {
      const policy = DuplicatePolicy.replaceAll;
      expect(of(EntryLocalState.complete).shouldSaveUnder(policy), isTrue);
      expect(of(EntryLocalState.partial).shouldSaveUnder(policy), isTrue);
    });
  });

  group('range preview', () {
    test('summarises what is already saved across a known chain', () async {
      await db.upsertCollection(
        Collection(
          contentKind: 'unknownWebContent',
          sequenceKind: 'none',
          orderingBasis: 'discoveryOrder',
          shapeConfidence: 'low',
          lifecycle: 'active',
          id: 'collection-1',
          title: 'Foo',
          sourceUrl: 'https://x.example/guide/foo',
          host: 'x.example',
          collectionKey: '/guide/foo',
          createdAt: DateTime(2026, 7, 1),
        ),
      );
      for (var n = 1; n <= 2; n++) {
        await db.upsertEntry(
          Entry(
            host: '',
            contentKind: 'unknownWebContent',
            contentKindConfidence: 'low',
            contentKindIsUserSet: false,
            id: 'c$n',
            collectionId: 'collection-1',
            title: 'Foo $n',
            sourceUrl: 'https://x.example/guide/foo/$n',
            urlKey: 'https://x.example/guide/foo/$n',
            artifactFormat: 'imageSequence',
            saveStatus: n == 2 ? 'partial' : 'complete',
            contentPath: 'library/collection-1/entries/c$n',
            savedAt: DateTime(2026, 7, 20),
            detectedAssetCount: 2,
            storedAssetCount: n == 2 ? 1 : 2,
            nextSourceUrl: 'https://x.example/guide/foo/${n + 1}',
            entryOrder: n,
            byteSize: 8,
            readStatus: 'unread',
            progressFraction: 0,
            progressPageIndex: 0,
            progressOffsetInPage: 0,
          ),
        );
        Directory(
          store.resolve('library/collection-1/entries/c$n'),
        ).createSync(recursive: true);
      }

      final range = await preflight.inspectRange(
        'https://x.example/guide/foo/1',
        5,
      );

      expect(range.savedCount, 1);
      expect(range.partialCount, 1);
      expect(range.newCount, 3);
      expect(range.hasExisting, isTrue);
      expect(range.lines.join(' '), contains('already saved'));
      expect(
        range.knownCount,
        lessThan(5),
        reason: 'the rest is only discoverable by visiting each page',
      );
    });

    test('a fresh collection previews as entirely new', () async {
      final range = await preflight.inspectRange(entryUrl, 3);
      expect(range.hasExisting, isFalse);
      expect(range.newCount, 3);
    });
  });

  group('safe replacement', () {
    test('keeps the previous copy until the new one lands', () async {
      final relative = await seedSaved();
      final original = await store
          .assetFile(relative, 'assets/001.png')
          .readAsBytes();

      final staging = await store.beginEntry(
        collectionId: 'collection-1',
        entryId: 'c1',
      );
      await staging.assetFile('001.png').writeAsBytes([9, 9, 9, 9]);
      await staging.assetFile('002.png').writeAsBytes([8, 8, 8, 8]);
      await store.commitReplacing(staging, manifestFor('c1'));

      final replaced = await store
          .assetFile(relative, 'assets/001.png')
          .readAsBytes();
      expect(replaced, isNot(original));
      expect(
        Directory('${store.resolve(relative)}.previous').existsSync(),
        isFalse,
        reason: 'the backup is cleaned up once the replacement succeeds',
      );
    });

    test('a failed replacement leaves the old entry readable', () async {
      final relative = await seedSaved();
      final original = await store
          .assetFile(relative, 'assets/001.png')
          .readAsBytes();

      // Staging that cannot be committed: the directory is gone.
      final staging = await store.beginEntry(
        collectionId: 'collection-1',
        entryId: 'c1',
      );
      staging.dir.deleteSync(recursive: true);

      await expectLater(
        store.commitReplacing(staging, manifestFor('c1')),
        throwsA(anything),
      );

      expect(
        store.entryExists(relative),
        isTrue,
        reason: 'a failed re-download must not cost a readable entry',
      );
      expect(
        await store.assetFile(relative, 'assets/001.png').readAsBytes(),
        original,
      );
      expect(await store.readManifest(relative), isNotNull);
    });

    test('an interrupted replacement is restored at startup', () async {
      final relative = await seedSaved();
      final target = Directory(store.resolve(relative));

      // Exactly what a kill between "step aside" and "move in" leaves.
      target.renameSync('${target.path}.previous');
      expect(store.entryExists(relative), isFalse);

      final restored = await store.restoreInterruptedReplacements();

      expect(restored, 1);
      expect(store.entryExists(relative), isTrue);
      expect(await store.readManifest(relative), isNotNull);
    });

    test('a leftover backup beside a good entry is just cleaned up', () async {
      final relative = await seedSaved();
      Directory(
        '${store.resolve(relative)}.previous',
      ).createSync(recursive: true);

      final restored = await store.restoreInterruptedReplacements();

      expect(restored, 0, reason: 'nothing needed restoring');
      expect(store.entryExists(relative), isTrue);
      expect(
        Directory('${store.resolve(relative)}.previous').existsSync(),
        isFalse,
      );
    });
  });

  group('re-download preserves reading state', () {
    test('progress and completion survive replacing the files', () async {
      await seedSaved();
      final reading = ReadingRepository(db);
      await reading.saveProgress(
        'c1',
        const ReadingPosition(
          fraction: 0.6,
          anchorIndex: 1,
          offsetInAnchor: 0.25,
        ),
        completed: true,
      );

      final before = (await db.entryById('c1'))!;

      // What the engine does on a replace: same row, refreshed save fields,
      // reading fields carried across verbatim.
      await db.upsertEntry(
        before.copyWith(
          savedAt: Value(DateTime(2026, 8, 1)),
          detectedAssetCount: 4,
          storedAssetCount: 4,
          byteSize: 4096,
        ),
      );

      final after = (await db.entryById('c1'))!;
      expect(after.storedAssetCount, 4, reason: 'save metadata refreshed');
      expect(after.readStatus, 'completed');
      expect(after.progressFraction, 1, reason: 'completed reads 100%');
      expect(after.progressPageIndex, 1);
      expect(after.progressOffsetInPage, closeTo(0.25, 0.001));
      expect(after.completedAt, before.completedAt);
    });

    test('replacing does not create a second entry row', () async {
      await seedSaved();
      final staging = await store.beginEntry(
        collectionId: 'collection-1',
        entryId: 'c1',
      );
      await staging.assetFile('001.png').writeAsBytes([9, 9, 9]);
      await store.commitReplacing(staging, manifestFor('c1'));

      final rows = (await db.allEntries())
          .where((c) => c.urlKey == entryUrl)
          .toList();
      expect(rows, hasLength(1));
      expect(rows.single.id, 'c1');
    });
  });
}

/// Regression: a running run must not collide with itself.
void _selfCollisionTests() {
  late AppDatabase db;
  late Directory root;
  late SavePreflight preflight;

  const url = 'https://x.example/guide/foo/1';

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    root = Directory.systemTemp.createTempSync('webread_self');
    preflight = SavePreflight(db: db, fileStore: FileStore(root));
  });
  tearDown(() async {
    await db.close();
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  Future<void> seedRunningRun(String id) => db.upsertRun(
    SaveRun(
      visitedCanonicals: '',
      origin: 'queue',
      scope: 'fixedCount',
      id: id,
      captureModeIsUserSet: false,
      startUrl: url,
      currentUrl: url,
      requestedEntries: 2,
      completedEntries: 0,
      state: 'inspecting',
      visitedUrls: url,
      createdAt: DateTime(2026, 7, 27),
      updatedAt: DateTime(2026, 7, 27),
    ),
  );

  test('a run does not treat its own row as a competing run', () async {
    await seedRunningRun('run-self');

    final result = await preflight.inspect(url, ignoreRunId: 'run-self');

    expect(
      result.state,
      EntryLocalState.none,
      reason:
          'the running run persists its own state before the first '
          'preflight; seeing that as a collision made every save skip '
          'the entry it was asked to save',
    );
    expect(result.shouldSaveUnder(DuplicatePolicy.skipComplete), isTrue);
  });

  test('a genuinely different run still blocks', () async {
    await seedRunningRun('run-other');

    final result = await preflight.inspect(url, ignoreRunId: 'run-mine');

    expect(result.state, EntryLocalState.inActiveRun);
    expect(result.blockingRun!.id, 'run-other');
  });

  test('with no run id supplied, any unfinished run blocks', () async {
    await seedRunningRun('run-other');
    expect((await preflight.inspect(url)).state, EntryLocalState.inActiveRun);
  });
}
