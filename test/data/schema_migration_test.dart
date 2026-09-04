/// Opening a library that already exists.
///
/// The schema was declared "created whole, version 1, no `onUpgrade`" while no
/// database outside a development machine existed. Columns and tables were
/// then added to it — `collections.capture_mode`, `collections.entry_sort`,
/// `locations.published_at`, `collection_check_states`, `asset_origins` — with
/// the version left at 1, so a library somebody was already using opened
/// missing all of them and drift's generated mapper threw *Null check operator
/// used on a null value* on the first read of `collections`. The Library drew
/// nothing (V2-D75).
///
/// The library-flow twin is `test/library_ui/legacy_library_open_test.dart`.
library;

import 'dart:io';

import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_reader/data/collection_repository.dart';
import 'package:web_reader/data/schema.dart';

import '../helpers/version_one_library.dart';

void main() {
  late Directory dir;
  late File file;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('scrollary_schema_migration');
    file = File('${dir.path}/library.sqlite');
  });

  tearDown(() async {
    await dir.delete(recursive: true);
  });

  LibraryDatabase open() => LibraryDatabase.forTesting(NativeDatabase(file));

  final at = versionOneLibraryAt;

  test('a version-1 library still lists its Collections', () async {
    await writeVersionOneLibrary(file);
    final db = open();
    addTearDown(db.close);

    final collections = await db.select(db.collections).get();
    expect(collections, hasLength(1));
    expect(collections.single.name, 'A work');
    // Unset, which is a question nobody has answered — not a default anybody
    // chose. Both readers resolve an empty string to null.
    expect(collections.single.captureMode, '');
    expect(collections.single.entrySort, '');
  });

  test('nothing the user owned is lost by the upgrade', () async {
    await writeVersionOneLibrary(file);
    final db = open();
    addTearDown(db.close);

    final entry = await db.select(db.entries).getSingle();
    expect(entry.title, 'Entry 12');
    expect(entry.ordinal, 12);
    expect(entry.collectionId, 'coll');

    final source = await db.select(db.sources).getSingle();
    expect(source.collectionId, 'coll');
    expect(source.pathKey, '/work');

    final location = await db.select(db.locations).getSingle();
    expect(location.sourceId, 'source');
    expect(location.url, 'https://x.example/work/12');
    expect(location.publishedAt, isNull);

    final reading = await db.select(db.readingStates).getSingle();
    expect(reading.status, 'reading');
    expect(reading.lastReadAt?.toUtc(), at);

    final copy = await db.select(db.offlineCopies).getSingle();
    expect(copy.contentPath, '/packages/entry/document.json');
    expect(copy.active, isTrue);
  });

  test('the tables the upgrade adds are usable, not merely present', () async {
    await writeVersionOneLibrary(file);
    final db = open();
    addTearDown(db.close);

    await db
        .into(db.collectionCheckStates)
        .insert(
          CollectionCheckStatesCompanion.insert(
            collectionId: 'coll',
            checkedAt: Value(at),
          ),
        );
    expect(
      (await db.select(db.collectionCheckStates).getSingle()).failed,
      isFalse,
    );

    await db
        .into(db.assetOrigins)
        .insert(
          AssetOriginsCompanion.insert(
            origin: 'https://cdn.example',
            updatedAt: at,
          ),
        );
    expect((await db.select(db.assetOrigins).getSingle()).verdict, 'unknown');

    await CollectionRepository(db).setEntrySort('coll', 'numberDesc');
    expect(
      (await db.select(db.collections).getSingle()).entrySort,
      'numberDesc',
    );
  });

  test(
    'a database already carrying the new shape upgrades untouched',
    () async {
      // What a device that installed the build which declared the columns but
      // had not yet bumped the version has on disk: version 2's shape, stamped
      // 1. The step must add nothing and lose nothing.
      final seed = open();
      await seed
          .into(seed.folders)
          .insert(
            FoldersCompanion.insert(
              id: 'root',
              kind: 'root',
              name: 'Library',
              updatedAt: at,
            ),
          );
      await seed
          .into(seed.collections)
          .insert(
            CollectionsCompanion.insert(
              id: 'coll',
              folderId: 'root',
              name: 'A work',
              orderingBasis: 'discoveryOrder',
              captureMode: const Value('textAndImages'),
              entrySort: const Value('numberAsc'),
              updatedAt: at,
            ),
          );
      await seed.customStatement('PRAGMA user_version = 1');
      await seed.close();

      final db = open();
      addTearDown(db.close);
      final row = await db.select(db.collections).getSingle();
      expect(row.captureMode, 'textAndImages');
      expect(row.entrySort, 'numberAsc');
    },
  );

  test('opening an upgraded library again is a no-op', () async {
    await writeVersionOneLibrary(file);
    final first = open();
    await first.select(first.collections).get();
    await first.close();

    final second = open();
    addTearDown(second.close);
    expect(await second.select(second.collections).get(), hasLength(1));
    final version = await second
        .customSelect('PRAGMA user_version')
        .getSingle();
    expect(version.read<int>('user_version'), 2);
  });
}
