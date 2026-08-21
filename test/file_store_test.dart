import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:web_reader/storage/file_store.dart';
import 'package:web_reader/storage/manifest.dart';

void main() {
  late Directory root;
  late FileStore store;

  setUp(() {
    root = Directory.systemTemp.createTempSync('webread_test');
    store = FileStore(root);
    Directory(
      p.join(root.path, FileStore.libraryFolderName),
    ).createSync(recursive: true);
    Directory(
      p.join(root.path, FileStore.tmpFolderName),
    ).createSync(recursive: true);
  });

  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  EntryManifest manifest(
    String entryId,
    String itemId, {
    SaveStatus status = SaveStatus.complete,
    List<EntryAsset> assets = const [],
  }) => EntryManifest(
    schemaVersion: 1,
    entryId: entryId,
    collectionId: itemId,
    sourceUrl: 'http://localhost:8099/entry/1',
    title: 'Entry 1',
    savedAt: DateTime(2026, 7, 25),
    status: status,
    detectedAssetCount: assets.length,
    storedAssetCount: assets.where((a) => a.isStored).length,
    assets: assets,
  );

  group('relative paths', () {
    test('entryRelativePath is relative and predictable', () {
      final rel = FileStore.entryRelativePath('item-1', 'chap-1');
      expect(rel, 'library/item-1/entries/chap-1');
      expect(rel, isNot(startsWith('/')));
    });

    test(
      'resolve joins against the runtime root, not a stored absolute path',
      () {
        final rel = FileStore.entryRelativePath('item-1', 'chap-1');
        expect(store.resolve(rel), p.join(root.path, rel));

        // The same relative path resolves correctly under a *different* root,
        // which is the whole point: the iOS container path moves between installs.
        final moved = FileStore(Directory('/somewhere/else'));
        expect(moved.resolve(rel), '/somewhere/else/$rel');
      },
    );

    test('asset paths in a staging handle are relative to the entry dir', () {
      expect(StagingHandle.assetRelativePath('001.png'), 'assets/001.png');
    });
  });

  group('staging and atomic commit', () {
    test('nothing exists at the final path until commit', () async {
      final handle = await store.beginEntry(
        collectionId: 'item-1',
        entryId: 'c1',
      );
      await handle.assetFile('001.png').writeAsBytes([1, 2, 3]);

      final rel = FileStore.entryRelativePath('item-1', 'c1');
      expect(
        store.entryExists(rel),
        isFalse,
        reason: 'staging must not be visible as a committed entry',
      );

      await store.commit(handle, manifest('c1', 'item-1'));
      expect(store.entryExists(rel), isTrue);
    });

    test('commit writes a readable manifest and moves the assets', () async {
      final handle = await store.beginEntry(
        collectionId: 'item-1',
        entryId: 'c1',
      );
      await handle.assetFile('001.png').writeAsBytes([1, 2, 3, 4]);

      final rel = await store.commit(
        handle,
        manifest(
          'c1',
          'item-1',
          assets: const [
            EntryAsset(
              index: 1,
              sourceUrl: 'http://localhost:8099/img/1/1.png',
              status: AssetStatus.stored,
              relativePath: 'assets/001.png',
            ),
          ],
        ),
      );

      final restored = await store.readManifest(rel);
      expect(restored, isNotNull);
      expect(restored!.entryId, 'c1');
      expect(store.assetFile(rel, 'assets/001.png').existsSync(), isTrue);
      expect(
        handle.dir.existsSync(),
        isFalse,
        reason: 'staging is consumed by the move',
      );
    });

    test('discard leaves no trace', () async {
      final handle = await store.beginEntry(
        collectionId: 'item-1',
        entryId: 'c1',
      );
      await handle.assetFile('001.png').writeAsBytes([1]);
      await store.discard(handle);

      expect(handle.dir.existsSync(), isFalse);
      expect(
        store.entryExists(FileStore.entryRelativePath('item-1', 'c1')),
        isFalse,
      );
    });

    test('sweepStaging removes orphans left by a crash', () async {
      await store.beginEntry(collectionId: 'item-1', entryId: 'c1');
      await store.beginEntry(collectionId: 'item-1', entryId: 'c2');

      expect(await store.sweepStaging(), 2);
      expect(await store.sweepStaging(), 0);
    });
  });

  group('reconciliation and deletion', () {
    test('listCommittedEntryPaths finds committed entries only', () async {
      final h1 = await store.beginEntry(collectionId: 'item-1', entryId: 'c1');
      await store.commit(h1, manifest('c1', 'item-1'));
      // A staging dir that never committed must not be listed.
      await store.beginEntry(collectionId: 'item-1', entryId: 'c2');

      final paths = store.listCommittedEntryPaths();
      expect(paths, ['library/item-1/entries/c1']);
    });

    test(
      'deleteEntryContent removes files but not the parent structure',
      () async {
        final handle = await store.beginEntry(
          collectionId: 'item-1',
          entryId: 'c1',
        );
        await handle.assetFile('001.png').writeAsBytes([1, 2, 3]);
        final rel = await store.commit(handle, manifest('c1', 'item-1'));

        expect(store.entryExists(rel), isTrue);
        await store.deleteEntryContent(rel);
        expect(store.entryExists(rel), isFalse);
      },
    );

    test('entryByteSize totals the stored bytes', () async {
      final handle = await store.beginEntry(
        collectionId: 'item-1',
        entryId: 'c1',
      );
      await handle.assetFile('001.png').writeAsBytes(List.filled(100, 0));
      await handle.assetFile('002.png').writeAsBytes(List.filled(250, 0));
      final rel = await store.commit(handle, manifest('c1', 'item-1'));

      // Assets plus the manifest itself.
      expect(await store.entryByteSize(rel), greaterThan(350));
    });

    test(
      'readManifest returns null for a directory with no manifest',
      () async {
        Directory(
          store.resolve('library/item-x/entries/ghost'),
        ).createSync(recursive: true);
        expect(
          await store.readManifest('library/item-x/entries/ghost'),
          isNull,
        );
      },
    );
  });
}
