import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_reader/features/storage_screen.dart';
import 'package:web_reader/providers.dart';
import 'package:web_reader/storage/cleanup.dart';
import 'package:web_reader/storage/database.dart';
import 'package:web_reader/storage/file_store.dart';

/// The Storage screen's numbers: derived from real stored data, reactive to
/// removals, and never counting things that are not on the device.
void main() {
  late AppDatabase db;
  late Directory root;
  late ProviderContainer container;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    root = Directory.systemTemp.createTempSync('webread_storage');
    container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
        fileStoreProvider.overrideWithValue(FileStore(root)),
      ],
    );
  });
  tearDown(() async {
    container.dispose();
    await db.close();
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  Future<void> seedCollection(String id, String title) => db.upsertCollection(
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

  Future<void> seedEntry(
    String collection,
    int n, {
    required int bytes,
    String readStatus = 'unread',
    bool offline = true,
    String saveStatus = 'complete',
  }) => db.upsertEntry(
    Entry(
      host: '',
      contentKind: 'unknownWebContent',
      contentKindConfidence: 'low',
      contentKindIsUserSet: false,
      id: '$collection-c$n',
      collectionId: collection,
      title: 'Entry $n',
      sourceUrl: 'https://x.example/guide/$collection/$n',
      urlKey: 'https://x.example/guide/$collection/$n',
      artifactFormat: 'imageSequence',
      saveStatus: saveStatus,
      contentPath: offline
          ? 'library/$collection/entries/$collection-c$n'
          : null,
      savedAt: DateTime(2026, 7, 20),
      detectedAssetCount: 3,
      storedAssetCount: 3,
      entryOrder: n,
      byteSize: offline ? bytes : 0,
      entryNumber: n.toDouble(),
      sourceMarker: 'Entry $n',
      readStatus: readStatus,
      progressFraction: readStatus == 'completed' ? 1 : 0,
      progressPageIndex: 0,
      progressOffsetInPage: 0,
    ),
  );

  /// Read the summary once it has data.
  Future<StorageSummary> summary() async {
    for (var i = 0; i < 60; i++) {
      final value = container.read(storageSummaryProvider);
      if (value.hasValue) return value.value!;
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    fail('storage summary never resolved');
  }

  test(
    'totals come from real stored sizes, largest collection first',
    () async {
      container.listen(storageSummaryProvider, (_, _) {});
      await seedCollection('s1', 'Small');
      await seedCollection('s2', 'Big');
      await seedEntry('s1', 1, bytes: 1000);
      await seedEntry('s2', 1, bytes: 5000);
      await seedEntry('s2', 2, bytes: 4000);

      final s = await summary();
      expect(s.totalBytes, 10000);
      expect(s.offlineEntries, 3);
      expect(s.offlineCollection, 2);
      expect(
        s.collection.map((r) => r.group.displayName),
        ['Big', 'Small'],
        reason: 'largest first by default',
      );
      expect(s.collection.first.bytes, 9000);
      expect(s.collection.first.offlineEntries, 2);
    },
  );

  test('entries with no local files are not counted', () async {
    container.listen(storageSummaryProvider, (_, _) {});
    await seedCollection('s1', 'Foo');
    await seedEntry('s1', 1, bytes: 1000);
    await seedEntry('s1', 2, bytes: 0, offline: false);
    await seedEntry(
      's1',
      3,
      bytes: 0,
      offline: false,
      saveStatus: 'knownRemote',
    );

    final s = await summary();
    expect(s.offlineEntries, 1);
    expect(s.totalBytes, 1000);
  });

  test(
    'the finished-entry estimate counts only completed offline ones',
    () async {
      container.listen(storageSummaryProvider, (_, _) {});
      await seedCollection('s1', 'Foo');
      await seedEntry('s1', 1, bytes: 1000, readStatus: 'completed');
      await seedEntry('s1', 2, bytes: 2000, readStatus: 'completed');
      await seedEntry('s1', 3, bytes: 4000, readStatus: 'inProgress');
      await seedEntry('s1', 4, bytes: 8000);

      final s = await summary();
      expect(s.finishedOfflineEntries, 2);
      expect(s.finishedOfflineBytes, 3000);
      expect(s.totalBytes, 15000, reason: 'unaffected by read state');
    },
  );

  test(
    'totals fall when files are removed, without losing the entries',
    () async {
      container.listen(storageSummaryProvider, (_, _) {});
      await seedCollection('s1', 'Foo');
      await seedEntry('s1', 1, bytes: 1000, readStatus: 'completed');
      await seedEntry('s1', 2, bytes: 2000);
      expect((await summary()).totalBytes, 3000);

      final cleanup = CleanupService(db: db, fileStore: FileStore(root));
      await cleanup.removeOffline(['s1-c1']);

      // Reactive: the same stream the library uses drives this.
      for (var i = 0; i < 60; i++) {
        final s = container.read(storageSummaryProvider).value;
        if (s != null && s.totalBytes == 2000) break;
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      final after = await summary();
      expect(after.totalBytes, 2000);
      expect(after.offlineEntries, 1);
      expect(
        (await db.entriesForCollection('s1')),
        hasLength(2),
        reason: 'metadata is never deleted by a cleanup',
      );
      expect((await db.entryById('s1-c1'))!.readStatus, 'completed');
    },
  );

  test('a collection with nothing offline drops out of the list', () async {
    container.listen(storageSummaryProvider, (_, _) {});
    await seedCollection('s1', 'Foo');
    await seedEntry('s1', 1, bytes: 1000);
    expect((await summary()).offlineCollection, 1);

    await CleanupService(
      db: db,
      fileStore: FileStore(root),
    ).removeOffline(['s1-c1']);
    for (var i = 0; i < 60; i++) {
      final s = container.read(storageSummaryProvider).value;
      if (s != null && s.offlineCollection == 0) break;
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }

    final after = await summary();
    expect(after.offlineCollection, 0);
    expect(after.totalBytes, 0);
    expect(
      await db.collectionById('s1'),
      isNotNull,
      reason: 'the collection itself is untouched',
    );
  });

  test('archived collection still count towards storage', () async {
    // They hold real bytes on the device; hiding them from the shelf does
    // not hide them from the disk.
    container.listen(storageSummaryProvider, (_, _) {});
    await seedCollection('s1', 'Foo');
    await seedEntry('s1', 1, bytes: 1000);
    await db.setCollectionLifecycle('s1', 'archived');

    for (var i = 0; i < 60; i++) {
      final s = container.read(storageSummaryProvider).value;
      if (s != null && s.offlineCollection == 1) break;
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    expect((await summary()).totalBytes, 1000);
  });
}
