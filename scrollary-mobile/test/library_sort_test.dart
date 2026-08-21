import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:web_reader/features/library_screen.dart';
import 'package:web_reader/library/library_sort.dart';
import 'package:web_reader/providers.dart';
import 'package:web_reader/storage/database.dart';

/// M13 backend: the persisted sort, the pure ordering, and the narrow
/// per-collection stream that keeps one entry's change from rippling through
/// every collection.
void main() {
  Collection item(String id, String title, {DateTime? lastReadAt}) =>
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
        lastReadAt: lastReadAt,
      );

  Entry entry(String id, String itemId) => Entry(
    host: '',
    contentKind: 'unknownWebContent',
    contentKindConfidence: 'low',
    contentKindIsUserSet: false,
    id: id,
    collectionId: itemId,
    title: 'ch',
    sourceUrl: 'https://x.example/guide/$itemId/$id',
    urlKey: 'https://x.example/guide/$itemId/$id',
    artifactFormat: 'imageSequence',
    saveStatus: 'complete',
    contentPath: 'library/$itemId/entries/$id',
    detectedAssetCount: 1,
    storedAssetCount: 1,
    entryOrder: 1,
    byteSize: 1,
    readStatus: 'unread',
    progressFraction: 0,
    progressPageIndex: 0,
    progressOffsetInPage: 0,
  );

  LibraryCollection collectionOf(Collection i) =>
      LibraryCollection(collection: i, entries: [entry('c-${i.id}', i.id)]);

  group('sortLibraryCollections (pure)', () {
    test('lastRead: recently read first, never-read after, ties by name', () {
      final groups = [
        collectionOf(item('b', 'Beta')), // never read
        collectionOf(item('a', 'Alpha', lastReadAt: DateTime(2026, 7, 20))),
        collectionOf(item('z', 'Zeta', lastReadAt: DateTime(2026, 7, 26))),
        collectionOf(item('c', 'Aardvark')), // never read
      ];

      final sorted = sortLibraryCollections(groups, LibrarySort.lastRead);

      expect(sorted.map((g) => g.collection!.id).toList(), [
        'z', // most recently read
        'a',
        'c', // never read, then alphabetical
        'b',
      ]);
    });

    test('name: case-insensitive natural order', () {
      final groups = [
        collectionOf(item('1', 'zeta')),
        collectionOf(item('2', 'Alpha')),
        collectionOf(item('3', 'entry 10 collection')),
        collectionOf(item('4', 'entry 2 collection')),
      ];

      final sorted = sortLibraryCollections(groups, LibrarySort.name);

      expect(sorted.map((g) => g.collection!.title).toList(), [
        'Alpha',
        'entry 2 collection',
        'entry 10 collection',
        'zeta',
      ]);
    });

    test('unknown stored value falls back to the default sort', () {
      expect(librarySortFromName('nonsense'), LibrarySort.lastRead);
      expect(librarySortFromName(null), LibrarySort.lastRead);
      expect(librarySortFromName('name'), LibrarySort.name);
    });
  });

  group('settings persistence', () {
    test('the sort survives closing and reopening the database', () async {
      final dir = Directory.systemTemp.createTempSync('webread_settings');
      addTearDown(() => dir.deleteSync(recursive: true));
      final file = File(p.join(dir.path, 'settings_test.sqlite'));

      var db = AppDatabase.forTesting(NativeDatabase(file));
      expect(await db.setting(kLibrarySortSettingKey), isNull);
      await db.setSetting(kLibrarySortSettingKey, LibrarySort.name.name);
      await db.close();

      // "Restart": a brand-new handle over the same file.
      db = AppDatabase.forTesting(NativeDatabase(file));
      addTearDown(db.close);
      expect(
        librarySortFromName(await db.setting(kLibrarySortSettingKey)),
        LibrarySort.name,
      );
    });

    test('watchSetting emits the change', () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);

      final emissions = <String?>[];
      final sub = db.watchSetting(kLibrarySortSettingKey).listen(emissions.add);
      addTearDown(sub.cancel);

      await Future<void>.delayed(const Duration(milliseconds: 50));
      await db.setSetting(kLibrarySortSettingKey, 'name');
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(emissions, [null, 'name']);
    });
  });

  group('per-collection stream narrowing', () {
    test(
      "a progress write for collection A does not re-emit collection B's entries",
      () async {
        final db = AppDatabase.forTesting(NativeDatabase.memory());
        addTearDown(db.close);
        await db.upsertCollection(item('a', 'Alpha'));
        await db.upsertCollection(item('b', 'Beta'));
        await db.upsertEntry(entry('ca', 'a'));
        await db.upsertEntry(entry('cb', 'b'));

        final container = ProviderContainer(
          overrides: [databaseProvider.overrideWithValue(db)],
        );
        addTearDown(container.dispose);

        var aEmissions = 0;
        var bEmissions = 0;
        container.listen(collectionEntriesProvider('a'), (_, next) {
          if (next.hasValue) aEmissions++;
        }, fireImmediately: true);
        container.listen(collectionEntriesProvider('b'), (_, next) {
          if (next.hasValue) bEmissions++;
        }, fireImmediately: true);

        // Let both streams deliver their first value.
        await Future<void>.delayed(const Duration(milliseconds: 100));
        final aBefore = aEmissions, bBefore = bEmissions;
        expect(aBefore, greaterThan(0));
        expect(bBefore, greaterThan(0));

        // A reading-progress write to collection A's entry. Drift invalidates
        // per table, so B's underlying stream fires too — the distinct()
        // must swallow it.
        await db.writeEntryReading(
          'ca',
          EntriesCompanion(
            progressFraction: const Value(0.5),
            progressUpdatedAt: Value(DateTime(2026, 7, 27)),
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 150));

        expect(
          aEmissions,
          greaterThan(aBefore),
          reason: "collection A's own data changed — it must emit",
        );
        expect(
          bEmissions,
          bBefore,
          reason:
              "collection B's data is unchanged — the distinct stream must not "
              'emit, so per-collection widgets do not rebuild',
        );
      },
    );
  });
}
