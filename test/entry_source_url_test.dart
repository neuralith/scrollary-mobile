import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_reader/features/entry_actions.dart';
import 'package:web_reader/reading/reading_position.dart';
import 'package:web_reader/reading/reading_repository.dart';
import 'package:web_reader/storage/cleanup.dart';
import 'package:web_reader/storage/database.dart';
import 'package:web_reader/storage/file_store.dart';

/// An entry's source URL is durable metadata: it is what "Open on website"
/// and "Save again" both stand on, and it must outlive the files.
void main() {
  late AppDatabase db;
  late Directory root;
  late FileStore store;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    root = Directory.systemTemp.createTempSync('webread_srcurl');
    store = FileStore(root);
  });
  tearDown(() async {
    await db.close();
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  const url = 'https://x.example/guide/foo/12';

  Future<void> seedCollection() => db.upsertCollection(
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

  /// An entry as save leaves it: files on disk, source URL recorded.
  Future<void> seedSaved({String sourceUrl = url}) async {
    final dir = Directory('${root.path}/library/collection-1/entries/c1')
      ..createSync(recursive: true);
    File('${dir.path}/001.png').writeAsBytesSync(List.filled(64, 7));
    await db.upsertEntry(
      Entry(
        host: '',
        contentKind: 'unknownWebContent',
        contentKindConfidence: 'low',
        contentKindIsUserSet: false,
        id: 'c1',
        collectionId: 'collection-1',
        title: 'Foo Entry 12',
        sourceUrl: sourceUrl,
        urlKey: sourceUrl,
        artifactFormat: 'imageSequence',
        saveStatus: 'complete',
        contentPath: 'library/collection-1/entries/c1',
        savedAt: DateTime(2026, 7, 20),
        detectedAssetCount: 1,
        storedAssetCount: 1,
        entryOrder: 12,
        byteSize: 64,
        entryNumber: 12,
        sourceMarker: 'Entry 12',
        readStatus: 'unread',
        progressFraction: 0,
        progressPageIndex: 0,
        progressOffsetInPage: 0,
      ),
    );
  }

  test('a saved entry stores the page it came from', () async {
    await seedCollection();
    await seedSaved();

    final entry = (await db.entryById('c1'))!;
    expect(entry.sourceUrl, url);
    expect(hasUsableSourceUrl(entry), isTrue);
  });

  test('a discovered remote entry stores its URL too', () async {
    await seedCollection();
    // What the update checker writes: metadata only, no files, but the
    // address is the whole point of the row.
    await db.upsertEntry(
      Entry(
        host: '',
        contentKind: 'unknownWebContent',
        contentKindConfidence: 'low',
        contentKindIsUserSet: false,
        id: 'c2',
        collectionId: 'collection-1',
        title: 'Foo Entry 13',
        sourceUrl: 'https://x.example/guide/foo/13',
        urlKey: 'https://x.example/guide/foo/13',
        artifactFormat: 'imageSequence',
        saveStatus: 'knownRemote',
        detectedAssetCount: 0,
        storedAssetCount: 0,
        entryOrder: 13,
        byteSize: 0,
        entryNumber: 13,
        sourceMarker: 'Entry 13',
        readStatus: 'unread',
        progressFraction: 0,
        progressPageIndex: 0,
        progressOffsetInPage: 0,
        discoveredAt: DateTime(2026, 7, 26),
        discoveryBasis: 'entryList',
      ),
    );

    final entry = (await db.entryById('c2'))!;
    expect(entry.contentPath, isNull, reason: 'metadata only');
    expect(entry.sourceUrl, 'https://x.example/guide/foo/13');
    expect(hasUsableSourceUrl(entry), isTrue);
    expect(isReadableOffline(entry), isFalse);
  });

  test('removing offline files keeps every piece of metadata', () async {
    await seedCollection();
    await seedSaved();
    // Give it a reading history and a discovery trail worth losing.
    final reading = ReadingRepository(db);
    await reading.saveProgress(
      'c1',
      const ReadingPosition(fraction: 0.6, anchorIndex: 1, offsetInAnchor: 0.2),
      completed: true,
    );
    await db.writeEntryReading(
      'c1',
      const EntriesCompanion(
        discoveryBasis: Value('entryList'),
        discoveryConfidence: Value('high'),
      ),
    );

    final before = (await db.entryById('c1'))!;
    await CleanupService(db: db, fileStore: store).removeOfflineNow(['c1']);
    final after = (await db.entryById('c1'))!;

    expect(after.contentPath, isNull, reason: 'the files are the only loss');
    expect(after.offlineRemovedAt, isNotNull);

    expect(after.sourceUrl, url);
    expect(after.urlKey, before.urlKey);
    expect(after.sourceMarker, 'Entry 12');
    expect(after.entryNumber, 12);
    expect(after.collectionId, 'collection-1');
    expect(after.readStatus, 'completed');
    expect(after.progressFraction, 1);
    expect(after.progressPageIndex, 1);
    expect(after.completedAt, before.completedAt);
    expect(after.discoveryBasis, before.discoveryBasis);
    expect(after.discoveryConfidence, before.discoveryConfidence);
  });

  test('a removed entry stays listed, as a known entry', () async {
    await seedCollection();
    await seedSaved();
    await CleanupService(db: db, fileStore: store).removeOfflineNow(['c1']);

    final entries = await db.entriesForCollection('collection-1');
    expect(entries, hasLength(1), reason: 'still in the collection list');
    expect(isReadableOffline(entries.single), isFalse);
    expect(hasUsableSourceUrl(entries.single), isTrue);
  });

  test('re-downloading keeps the same source identity', () async {
    await seedCollection();
    await seedSaved();
    await CleanupService(db: db, fileStore: store).removeOfflineNow(['c1']);

    // The engine re-commits the same row, refreshing save fields only.
    final removed = (await db.entryById('c1'))!;
    await db.upsertEntry(
      removed.copyWith(
        artifactFormat: 'imageSequence',
        saveStatus: 'complete',
        contentPath: const Value('library/collection-1/entries/c1'),
        byteSize: 128,
        storedAssetCount: 1,
        savedAt: Value(DateTime(2026, 8, 1)),
      ),
    );
    await db.clearOfflineRemovedMark('c1');

    final after = (await db.entryById('c1'))!;
    expect(after.sourceUrl, url, reason: 'same entry, same address');
    expect(after.urlKey, removed.urlKey);
    expect(after.offlineRemovedAt, isNull);
    expect(after.readStatus, 'unread');
  });

  group('missing source URLs', () {
    test('a blank URL is not usable, and is never navigated to', () async {
      await seedCollection();
      await seedSaved(sourceUrl: '');
      expect(hasUsableSourceUrl((await db.entryById('c1'))!), isFalse);
    });
  });
}
