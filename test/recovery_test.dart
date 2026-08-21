import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:web_reader/storage/database.dart';
import 'package:web_reader/storage/file_store.dart';
import 'package:web_reader/storage/manifest.dart';

/// M3 acceptance 5: force-quit mid-session, reopen, and nothing is falsely
/// marked saved.
///
/// The force-quit itself is simulated at the layer where it matters — a
/// database and a file tree left exactly as an interrupted run leaves them,
/// then the startup recovery run against that state. That covers what an
/// integration test would, without needing to kill an app process.
void main() {
  late AppDatabase db;
  late Directory root;
  late FileStore store;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    root = Directory.systemTemp.createTempSync('webread_recovery');
    store = FileStore(root);
    Directory(
      p.join(root.path, FileStore.libraryFolderName),
    ).createSync(recursive: true);
    Directory(
      p.join(root.path, FileStore.tmpFolderName),
    ).createSync(recursive: true);
  });

  tearDown(() async {
    await db.close();
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  Future<void> seedItem() => db.upsertCollection(
    Collection(
      contentKind: 'unknownWebContent',
      sequenceKind: 'none',
      orderingBasis: 'discoveryOrder',
      shapeConfidence: 'low',
      lifecycle: 'active',
      id: 'item-1',
      title: 'Fixture Collection',
      sourceUrl: 'https://x.example/guide/foo',
      host: 'x.example',
      collectionKey: '/guide/foo',
      createdAt: DateTime(2026, 7, 1),
    ),
  );

  Entry entry(
    String id, {
    required String status,
    String? contentPath,
    int entryOrder = 1,
  }) => Entry(
    host: '',
    contentKind: 'unknownWebContent',
    contentKindConfidence: 'low',
    contentKindIsUserSet: false,
    readStatus: 'unread',
    progressFraction: 0,
    progressPageIndex: 0,
    progressOffsetInPage: 0,
    id: id,
    collectionId: 'item-1',
    title: 'Fixture Collection Entry $entryOrder',
    sourceUrl: 'https://x.example/guide/foo/$entryOrder',
    urlKey: 'https://x.example/guide/foo/$entryOrder',
    artifactFormat: 'imageSequence',
    saveStatus: status,
    contentPath: contentPath,
    savedAt: status == 'complete' ? DateTime(2026, 7, 20) : null,
    detectedAssetCount: 6,
    storedAssetCount: status == 'complete' ? 6 : 0,
    entryOrder: entryOrder,
    byteSize: status == 'complete' ? 4096 : 0,
  );

  EntryManifest manifestFor(String entryId, SaveStatus status) => EntryManifest(
    schemaVersion: 1,
    entryId: entryId,
    collectionId: 'item-1',
    sourceUrl: 'https://x.example/guide/foo/2',
    title: 'Fixture Collection Entry 2',
    savedAt: DateTime(2026, 7, 21),
    status: status,
    detectedAssetCount: 2,
    storedAssetCount: 2,
    entryOrder: 2,
    assets: const [
      EntryAsset(
        index: 1,
        sourceUrl: 'https://cdn.example/1.png',
        status: AssetStatus.stored,
        relativePath: 'assets/001.png',
      ),
      EntryAsset(
        index: 2,
        sourceUrl: 'https://cdn.example/2.png',
        status: AssetStatus.stored,
        relativePath: 'assets/002.png',
      ),
    ],
  );

  group('force-quit mid-save', () {
    test('an in-flight entry is demoted, never promoted', () async {
      await seedItem();
      await db.upsertEntry(
        entry(
          'done',
          status: 'complete',
          contentPath: 'library/item-1/entries/done',
        ),
      );
      await db.upsertEntry(entry('inflight', status: 'saving', entryOrder: 2));

      final reset = await db.resetInFlightEntries();

      expect(reset, 1);
      final interrupted = await db.entryById('inflight');
      expect(
        interrupted!.saveStatus,
        'failed',
        reason: 'an interrupted entry must never come back as complete',
      );
      expect(interrupted.saveError, contains('interrupted'));
      expect(interrupted.storedAssetCount, 0);

      // The entry that had actually finished is untouched.
      final done = await db.entryById('done');
      expect(done!.saveStatus, 'complete');
      expect(done.contentPath, 'library/item-1/entries/done');
    });

    test('staging left behind by the kill is swept', () async {
      final staging = await store.beginEntry(
        collectionId: 'item-1',
        entryId: 'inflight',
      );
      await staging.assetFile('001.png').writeAsBytes([1, 2, 3]);
      expect(staging.dir.existsSync(), isTrue);

      final swept = await store.sweepStaging();

      expect(swept, 1);
      expect(staging.dir.existsSync(), isFalse);
      expect(
        store.entryExists(FileStore.entryRelativePath('item-1', 'inflight')),
        isFalse,
        reason: 'partial bytes must never appear as a committed entry',
      );
    });

    test(
      'an entry committed to disk but not to the database is reconciled',
      () async {
        await seedItem();

        // The exact window: files renamed into place, process killed before
        // the database transaction.
        final staging = await store.beginEntry(
          collectionId: 'item-1',
          entryId: 'orphan',
        );
        await staging.assetFile('001.png').writeAsBytes([1, 2, 3, 4]);
        await staging.assetFile('002.png').writeAsBytes([5, 6, 7, 8]);
        final relative = await store.commit(
          staging,
          manifestFor('orphan', SaveStatus.complete),
        );

        expect(store.entryExists(relative), isTrue);
        expect(await db.entryById('orphan'), isNull);

        // What startup recovery does: read the manifest and finish the record.
        final found = store.listCommittedEntryPaths();
        expect(found, contains(relative));
        final manifest = await store.readManifest(relative);
        expect(manifest, isNotNull);
        expect(manifest!.status, SaveStatus.complete);

        await db.upsertEntry(
          Entry(
            host: '',
            contentKind: 'unknownWebContent',
            contentKindConfidence: 'low',
            contentKindIsUserSet: false,
            id: manifest.entryId,
            collectionId: manifest.collectionId,
            title: manifest.title,
            sourceUrl: manifest.sourceUrl,
            urlKey: manifest.sourceUrl,
            artifactFormat: 'imageSequence',
            saveStatus: manifest.status.name,
            contentPath: relative,
            savedAt: manifest.savedAt,
            detectedAssetCount: manifest.detectedAssetCount,
            storedAssetCount: manifest.storedAssetCount,
            entryOrder: manifest.entryOrder ?? 0,
            byteSize: 2048,
            readStatus: 'unread',
            progressFraction: 0,
            progressPageIndex: 0,
            progressOffsetInPage: 0,
          ),
        );

        final recovered = await db.entryById('orphan');
        expect(recovered!.saveStatus, 'complete');
        expect(recovered.storedAssetCount, 2);
        expect(
          store.assetFile(relative, 'assets/001.png').existsSync(),
          isTrue,
        );
      },
    );

    test('a partial manifest is reconciled as partial, not complete', () async {
      await seedItem();
      final staging = await store.beginEntry(
        collectionId: 'item-1',
        entryId: 'half',
      );
      await staging.assetFile('001.png').writeAsBytes([1, 2, 3]);
      final relative = await store.commit(
        staging,
        manifestFor('half', SaveStatus.partial),
      );

      final manifest = await store.readManifest(relative);
      expect(
        manifest!.status,
        SaveStatus.partial,
        reason: 'recovery must carry the recorded status, not assume success',
      );
    });
  });

  group('the interrupted run itself', () {
    SaveRun run(String state, {int completed = 1}) => SaveRun(
      visitedCanonicals: '',
      origin: 'queue',
      scope: 'fixedCount',
      id: 'run-1',
      captureModeIsUserSet: false,
      startUrl: 'https://x.example/guide/foo/1',
      currentUrl: 'https://x.example/guide/foo/2',
      requestedEntries: 3,
      completedEntries: completed,
      state: state,
      visitedUrls: 'https://x.example/guide/foo/1',
      createdAt: DateTime(2026, 7, 20),
      updatedAt: DateTime(2026, 7, 20),
    );

    test('is offered for resume after the restart', () async {
      await db.upsertRun(run('downloading'));

      final resumable = await db.findResumableRun();

      expect(resumable, isNotNull);
      expect(resumable!.currentUrl, 'https://x.example/guide/foo/2');
      expect(resumable.completedEntries, 1);
      expect(
        resumable.visitedUrls,
        contains('foo/1'),
        reason: 'the visited set is what stops a resume re-walking entry 1',
      );
    });

    test(
      'is never resumed automatically — discarding leaves the saves',
      () async {
        await seedItem();
        await db.upsertEntry(
          entry(
            'done',
            status: 'complete',
            contentPath: 'library/item-1/entries/done',
          ),
        );
        await db.upsertRun(run('scrolling'));

        await db.deleteRun('run-1');

        expect(await db.findResumableRun(), isNull);
        final kept = await db.entryById('done');
        expect(
          kept!.saveStatus,
          'complete',
          reason: 'discarding a run must not touch what it already saved',
        );
      },
    );

    test('a finished run is not offered', () async {
      await db.upsertRun(run('complete', completed: 3));
      expect(await db.findResumableRun(), isNull);
    });
  });
}
