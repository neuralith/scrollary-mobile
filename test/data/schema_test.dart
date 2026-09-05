/// SQL-layer tests for the fresh V2 local schema (roadmap C2).
///
/// The domain twins live in test/domain/. Here the same invariants are proven
/// at the database boundary: a CHECK, a partial unique index or a foreign key
/// refuses the row even if every Dart guard is bypassed.
library;

import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_reader/data/schema.dart';

void main() {
  late LibraryDatabase db;

  setUp(() {
    db = LibraryDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  Future<List<String>> tableNames() async {
    final rows = await db
        .customSelect(
          "SELECT name FROM sqlite_master WHERE type = 'table' "
          "AND name NOT LIKE 'sqlite_%'",
        )
        .get();
    return rows.map((r) => r.read<String>('name')).toList();
  }

  Future<void> insertRoot({String id = 'root'}) => db
      .into(db.folders)
      .insert(
        FoldersCompanion.insert(
          id: id,
          kind: 'root',
          name: 'Library',
          updatedAt: DateTime.utc(2026),
        ),
      );

  Future<void> insertUserFolder(String id, String parentId) => db
      .into(db.folders)
      .insert(
        FoldersCompanion.insert(
          id: id,
          kind: 'user',
          name: id,
          parentId: Value(parentId),
          updatedAt: DateTime.utc(2026),
        ),
      );

  Future<void> insertCollection(String id, String folderId) => db
      .into(db.collections)
      .insert(
        CollectionsCompanion.insert(
          id: id,
          folderId: folderId,
          name: id,
          orderingBasis: 'explicitNumericIndex',
          updatedAt: DateTime.utc(2026),
        ),
      );

  Future<void> insertEntry(
    String id, {
    String? collectionId,
    String? folderId,
    double? ordinal,
    String placement = 'placed',
  }) => db
      .into(db.entries)
      .insert(
        EntriesCompanion.insert(
          id: id,
          collectionId: Value(collectionId),
          folderId: Value(folderId),
          ordinal: Value(ordinal),
          placement: placement,
          updatedAt: DateTime.utc(2026),
        ),
      );

  group('clean creation', () {
    test('schema version is 3 and creates whole', () async {
      expect(db.schemaVersion, 3);
      final names = await tableNames();
      expect(
        names,
        containsAll(<String>[
          'folders',
          'collections',
          'sources',
          'entries',
          'locations',
          'reading_states',
          'measurements',
          'download_requests',
          'offline_copies',
          'save_queue',
          'history',
          'outbox',
          'sync_state',
          'collection_check_states',
          'page_hints',
          'saved_sites',
          'favicons',
          'asset_origins',
          'settings',
        ]),
      );
    });

    test('entries carry no download or reading columns (§5.2)', () async {
      final rows = await db.customSelect('PRAGMA table_info(entries)').get();
      final columns = rows.map((r) => r.read<String>('name')).toSet();
      for (final v1Column in [
        'save_status',
        'content_path',
        'byte_size',
        'artifact_format',
        'offline_removed_at',
        'read_status',
        'progress',
        'url_key',
      ]) {
        expect(columns.contains(v1Column), isFalse, reason: v1Column);
      }
    });

    test('the recognition indexes exist', () async {
      final rows = await db
          .customSelect("SELECT name FROM sqlite_master WHERE type = 'index'")
          .get();
      final names = rows.map((r) => r.read<String>('name')).toSet();
      expect(names, contains('idx_sources_identity'));
      expect(names, contains('idx_entries_ordinal'));
      expect(names, contains('idx_folders_one_root'));
      expect(names, contains('idx_offline_copies_active'));
      expect(names, contains('idx_download_requests_open'));
      expect(names, contains('idx_save_queue_open'));
      expect(names, contains('idx_save_queue_pending'));
    });
  });

  group('I1 at the SQL layer', () {
    test('a second root is refused by the partial unique index', () async {
      await insertRoot();
      expect(() => insertRoot(id: 'root2'), throwsA(anything));
    });

    test('a root with a parent is refused by the CHECK', () async {
      await insertRoot();
      expect(
        () => db
            .into(db.folders)
            .insert(
              FoldersCompanion.insert(
                id: 'bad',
                kind: 'root',
                name: 'bad',
                parentId: const Value('root'),
                updatedAt: DateTime.utc(2026),
              ),
            ),
        throwsA(anything),
      );
    });

    test('a user folder without a parent is refused by the CHECK', () async {
      expect(
        () => db
            .into(db.folders)
            .insert(
              FoldersCompanion.insert(
                id: 'orphan',
                kind: 'user',
                name: 'orphan',
                updatedAt: DateTime.utc(2026),
              ),
            ),
        throwsA(anything),
      );
    });
  });

  group('I3 at the SQL layer', () {
    setUp(() async {
      await insertRoot();
      await insertCollection('c1', 'root');
    });

    test('an Entry with both a Collection and a Folder is refused', () {
      expect(
        () => insertEntry('e1', collectionId: 'c1', folderId: 'root'),
        throwsA(anything),
      );
    });

    test('an Entry with neither is refused', () {
      expect(() => insertEntry('e1'), throwsA(anything));
    });

    test('a standalone Entry in a Folder is accepted', () async {
      await insertEntry('e1', folderId: 'root');
    });

    test('an unplaced Entry with an ordinal is refused', () {
      expect(
        () => insertEntry(
          'e1',
          collectionId: 'c1',
          ordinal: 5,
          placement: 'unplaced',
        ),
        throwsA(anything),
      );
    });
  });

  group('I6 at the SQL layer', () {
    test('two Locations with one url_key are refused', () async {
      await insertRoot();
      await insertCollection('c1', 'root');
      await insertEntry('e1', collectionId: 'c1', ordinal: 1);
      await insertEntry('e2', collectionId: 'c1', ordinal: 2);

      Future<void> insertLocation(String id, String entryId) => db
          .into(db.locations)
          .insert(
            LocationsCompanion.insert(
              id: id,
              entryId: entryId,
              url: 'https://example.com/a',
              urlKey: 'example.com/a',
              discoveredAt: DateTime.utc(2026),
              updatedAt: DateTime.utc(2026),
            ),
          );

      await insertLocation('l1', 'e1');
      expect(() => insertLocation('l2', 'e2'), throwsA(anything));
    });
  });

  group('I8 at the SQL layer', () {
    setUp(() async {
      await insertRoot();
      await insertCollection('c1', 'root');
      await insertCollection('c2', 'root');
    });

    test(
      'two Entries with one ordinal in one Collection are refused',
      () async {
        await insertEntry('e1', collectionId: 'c1', ordinal: 100);
        expect(
          () => insertEntry('e2', collectionId: 'c1', ordinal: 100),
          throwsA(anything),
        );
      },
    );

    test('the same ordinal in another Collection is fine', () async {
      await insertEntry('e1', collectionId: 'c1', ordinal: 100);
      await insertEntry('e2', collectionId: 'c2', ordinal: 100);
    });

    test('several unplaced Entries may coexist without ordinals', () async {
      await insertEntry('e1', collectionId: 'c1', placement: 'unplaced');
      await insertEntry('e2', collectionId: 'c1', placement: 'unplaced');
    });
  });

  group('I13 at the SQL layer', () {
    test('a second active copy for one Entry is refused', () async {
      Future<void> insertCopy(String id, {bool active = true}) => db
          .into(db.offlineCopies)
          .insert(
            OfflineCopiesCompanion.insert(
              id: id,
              entryId: 'e1',
              locationUrl: 'https://example.com/a',
              capturedAt: DateTime.utc(2026),
              artifactFormat: 'imageSequence',
              contentPath: 'library/e1',
              active: Value(active),
              createdAt: DateTime.utc(2026),
            ),
          );

      await insertCopy('o1');
      expect(() => insertCopy('o2'), throwsA(anything));
      // A replaced, inactive copy is allowed to coexist.
      await insertCopy('o3', active: false);
    });
  });

  group('I14 groundwork — offline copies survive entry deletion', () {
    test('deleting an Entry cascades library rows, not the copy row', () async {
      await insertRoot();
      await insertCollection('c1', 'root');
      await insertEntry('e1', collectionId: 'c1', ordinal: 1);
      await db
          .into(db.readingStates)
          .insert(
            ReadingStatesCompanion.insert(
              entryId: 'e1',
              updatedAt: DateTime.utc(2026),
            ),
          );
      await db
          .into(db.offlineCopies)
          .insert(
            OfflineCopiesCompanion.insert(
              id: 'o1',
              entryId: 'e1',
              locationUrl: 'https://example.com/a',
              capturedAt: DateTime.utc(2026),
              artifactFormat: 'imageSequence',
              contentPath: 'library/e1',
              createdAt: DateTime.utc(2026),
            ),
          );

      await (db.delete(db.entries)..where((t) => t.id.equals('e1'))).go();

      final readingRows = await db.select(db.readingStates).get();
      expect(readingRows, isEmpty);
      final copies = await db.select(db.offlineCopies).get();
      expect(copies, hasLength(1));
    });
  });

  group('foreign keys are on', () {
    test('an Entry pointing at a missing Collection is refused', () {
      expect(
        () => insertEntry('e1', collectionId: 'ghost', ordinal: 1),
        throwsA(anything),
      );
    });

    test(
      'deleting a Folder with children is refused at the SQL layer',
      () async {
        await insertRoot();
        await insertUserFolder('f1', 'root');
        await insertCollection('c1', 'f1');
        expect(
          () => (db.delete(db.folders)..where((t) => t.id.equals('f1'))).go(),
          throwsA(anything),
        );
      },
    );
  });

  group('device-local bookkeeping', () {
    test('sync_state accepts only its single row', () async {
      await db
          .into(db.syncState)
          .insert(SyncStateCompanion.insert(id: const Value(1)));
      expect(
        () => db
            .into(db.syncState)
            .insert(SyncStateCompanion.insert(id: const Value(2))),
        throwsA(anything),
      );
    });

    test('the outbox refuses device-owned kinds and unknown ops', () async {
      Future<void> insertOp(String kind, String op) => db
          .into(db.outbox)
          .insert(
            OutboxCompanion.insert(
              mutationId: '$kind-$op',
              entityKind: kind,
              entityId: 'x',
              op: op,
              payload: '{}',
              createdAt: DateTime.utc(2026),
            ),
          );

      await insertOp('readingState', 'upsert');
      expect(() => insertOp('offlineCopy', 'upsert'), throwsA(anything));
      expect(() => insertOp('entry', 'annex'), throwsA(anything));
    });

    test('a measurement fraction above one is refused', () async {
      await insertRoot();
      await insertCollection('c1', 'root');
      await db
          .into(db.sources)
          .insert(
            SourcesCompanion.insert(
              id: 's1',
              collectionId: 'c1',
              host: 'example.com',
              pathKey: 'work',
              firstSeenAt: DateTime.utc(2026),
              lastSeenAt: DateTime.utc(2026),
              updatedAt: DateTime.utc(2026),
            ),
          );
      await insertEntry('e1', collectionId: 'c1', ordinal: 1);
      expect(
        () => db
            .into(db.measurements)
            .insert(
              MeasurementsCompanion.insert(
                entryId: 'e1',
                sourceId: 's1',
                fraction: 1.5,
                observedAt: DateTime.utc(2026),
              ),
            ),
        throwsA(anything),
      );
    });
  });

  group('the save queue at the SQL layer (E3)', () {
    Future<void> seed() async {
      await insertRoot();
      await insertCollection('c1', 'root');
      await insertEntry('e1', collectionId: 'c1', ordinal: 1);
      await insertEntry('e2', collectionId: 'c1', ordinal: 2);
      await db
          .into(db.sources)
          .insert(
            SourcesCompanion.insert(
              id: 's1',
              collectionId: 'c1',
              host: 'reading.example.com',
              pathKey: 'serial-alpha',
              firstSeenAt: DateTime.utc(2026),
              lastSeenAt: DateTime.utc(2026),
              updatedAt: DateTime.utc(2026),
            ),
          );
      await db
          .into(db.locations)
          .insert(
            LocationsCompanion.insert(
              id: 'l1',
              entryId: 'e1',
              sourceId: const Value('s1'),
              url: 'https://reading.example.com/a',
              urlKey: 'https://reading.example.com/a',
              discoveredAt: DateTime.utc(2026),
              updatedAt: DateTime.utc(2026),
            ),
          );
    }

    Future<void> insertTask(
      String id, {
      String entryId = 'e1',
      String? locationId = 'l1',
      String state = 'queued',
      String origin = 'queue',
    }) => db
        .into(db.saveQueue)
        .insert(
          SaveQueueCompanion.insert(
            id: id,
            entryId: entryId,
            locationId: Value(locationId),
            locationUrl: 'https://reading.example.com/a',
            state: Value(state),
            origin: Value(origin),
            queuedAt: DateTime.utc(2026),
          ),
        );

    test('the queue is device state: no server id, no revision', () async {
      final rows = await db.customSelect('PRAGMA table_info(save_queue)').get();
      final columns = rows.map((r) => r.read<String>('name')).toSet();
      expect(columns.contains('server_id'), isFalse);
      expect(columns.contains('revision'), isFalse);
      expect(columns, containsAll(['entry_id', 'location_id', 'order_index']));
    });

    test('the five states are the only ones a row may hold', () async {
      await seed();
      for (final state in [
        'queued',
        'running',
        'completed',
        'failed',
        'cancelled',
      ]) {
        await (db.delete(db.saveQueue)).go();
        await insertTask('t-$state', state: state);
      }
      await (db.delete(db.saveQueue)).go();
      expect(() => insertTask('t6', state: 'dismissed'), throwsA(anything));
    });

    test('a direct row can never be waiting or running', () async {
      await seed();
      await insertTask('t1', state: 'completed', origin: 'direct');
      expect(
        () => insertTask('t2', state: 'queued', origin: 'direct'),
        throwsA(anything),
      );
      expect(() => insertTask('t3', origin: 'sideways'), throwsA(anything));
    });

    test('a second open task for one Entry is refused', () async {
      await seed();
      await insertTask('t1');
      expect(() => insertTask('t2'), throwsA(anything));
      // A terminal row for the same Entry is history and may coexist.
      await insertTask('t3', state: 'failed');
      // Another Entry queues freely.
      await insertTask('t4', entryId: 'e2', locationId: null);
    });

    test('deleting an Entry takes its queue rows; a Location only clears the '
        'pointer', () async {
      await seed();
      await insertTask('t1');
      await (db.delete(db.locations)..where((l) => l.id.equals('l1'))).go();
      final afterLocation = await db.select(db.saveQueue).getSingle();
      expect(afterLocation.locationId, isNull);
      expect(afterLocation.locationUrl, 'https://reading.example.com/a');

      await (db.delete(db.entries)..where((t) => t.id.equals('e1'))).go();
      expect(await db.select(db.saveQueue).get(), isEmpty);
    });
  });
}
