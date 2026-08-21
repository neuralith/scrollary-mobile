import 'dart:io';

import 'package:drift/drift.dart' show Migrator;

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_reader/storage/database.dart';

/// The schema is version 1 and has no history.
///
/// These assertions are the ones that would catch a migration system growing
/// back, a legacy table surviving a rename, or the standalone-entry constraint
/// being dropped as "redundant".
void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<List<String>> tableNames() async {
    final rows = await db
        .customSelect(
          "SELECT name FROM sqlite_master WHERE type = 'table' "
          "AND name NOT LIKE 'sqlite_%'",
        )
        .get();
    return rows.map((r) => r.read<String>('name')).toList()..sort();
  }

  Future<List<String>> columnNames(String table) async {
    final rows = await db.customSelect('PRAGMA table_info($table)').get();
    return rows.map((r) => r.read<String>('name')).toList()..sort();
  }

  group('version', () {
    test('the schema version is 1', () {
      expect(db.schemaVersion, 1);
    });

    test('a fresh database reports user_version 1', () async {
      final row = await db.customSelect('PRAGMA user_version').getSingle();
      expect(row.read<int>('user_version'), 1);
    });

    test('there is no upgrade path, in the strategy or in the source', () async {
      expect(db.migration.onCreate, isNotNull);

      // drift always fills in an `onUpgrade`; the one we get is *its* default,
      // which throws. That is the assertion: no upgrade path was written, so
      // any attempt to use one fails loudly instead of half-migrating.
      await expectLater(
        db.migration.onUpgrade(Migrator(db), 0, 1),
        throwsA(anything),
        reason: 'the strategy must supply no upgrade path of its own',
      );

      // Belt and braces: no migration machinery anywhere in the file. Matched
      // as code rather than as prose — the doc comment above the strategy says
      // the words "onUpgrade" and "migration" precisely to explain their
      // absence, and a check that could not tell those apart would be a check
      // nobody could satisfy.
      final source = File('lib/storage/database.dart').readAsStringSync();
      for (final banned in [
        'onUpgrade:',
        'm.addColumn',
        'm.alterTable',
        'if (from <',
        'schemaVersion => 2',
        'VerifySelf',
        'schema_versions',
        'stepByStep',
      ]) {
        expect(
          source.contains(banned),
          isFalse,
          reason: 'database.dart mentions "$banned"',
        );
      }
    });

    test('no schema dump or step-verifier directory exists', () {
      for (final path in [
        'drift_schemas',
        'test/drift/schemas',
        'test/generated/schema.dart',
        'test/generated_migrations',
      ]) {
        expect(
          FileSystemEntity.typeSync(path),
          FileSystemEntityType.notFound,
          reason: '$path is migration infrastructure',
        );
      }
    });
  });

  group('tables', () {
    test('exactly the nine tables of the version-1 model exist', () async {
      expect(await tableNames(), [
        'browsing_history',
        'collections',
        'entries',
        'favicon_cache',
        'queue_tasks',
        'save_runs',
        'saved_sites',
        'settings',
        'user_page_hints',
      ]);
    });

    test('no table from the previous model exists', () async {
      final names = await tableNames();
      for (final legacy in [
        'library_items',
        'chapters',
        'capture_jobs',
        'site_rule_rows',
        'capture_session',
        'capture_session_visit',
        'capture_event',
        'site_recipe',
        'source',
      ]) {
        expect(names, isNot(contains(legacy)));
      }
    });
  });

  group('columns', () {
    test('entries carries the neutral column names', () async {
      final columns = await columnNames('entries');
      expect(
        columns,
        containsAll([
          'collection_id',
          'save_status',
          'saved_at',
          'save_error',
          'entry_order',
          'entry_number',
          'source_marker',
          'content_kind',
          'content_kind_confidence',
          'content_kind_is_user_set',
          'canonical_url',
          'host',
          'published_at',
          'progress_page_index',
          'progress_offset_in_page',
        ]),
      );
    });

    test('no column from the previous model exists anywhere', () async {
      const legacy = [
        'library_item_id',
        'chapter_id',
        'chapter_number',
        'chapter_label',
        'chapter_order',
        'capture_status',
        'captured_at',
        'capture_error',
        'sequence',
        'progress_image_index',
        'progress_offset_in_image',
        'detected_image_count',
        'stored_image_count',
        'series_key',
        'series_url',
        'series_path',
        'finished_cleanup',
        'range_mode',
        'chapter_limit',
        'is_default',
        'last_opened_chapter_id',
        'last_completed_chapter_id',
      ];
      for (final table in await tableNames()) {
        final columns = await columnNames(table);
        for (final name in legacy) {
          expect(
            columns,
            isNot(contains(name)),
            reason: '$table still has $name',
          );
        }
      }
    });

    test('collections carries the three shape dimensions', () async {
      expect(
        await columnNames('collections'),
        containsAll([
          'collection_key',
          'collection_index_url',
          'content_kind',
          'sequence_kind',
          'ordering_basis',
          'shape_confidence',
          'known_entry_total',
          'cleanup_preference',
          'last_opened_entry_id',
          'last_completed_entry_id',
        ]),
      );
    });

    test('save_runs records its bounds, mode and why it stopped', () async {
      expect(
        await columnNames('save_runs'),
        containsAll([
          'scope',
          'max_bytes',
          // What to produce, not a boolean about images: the old
          // `include_images` could not express the difference between an
          // ordered image sequence and an article with pictures in it.
          'capture_mode',
          'capture_mode_is_user_set',
          'stop_reason',
          'visited_canonicals',
          'origin',
        ]),
      );
      expect(await columnNames('save_runs'), isNot(contains('include_images')));
    });

    test(
      'entries record the stored artifact separately from the label',
      () async {
        final columns = await columnNames('entries');
        expect(
          columns,
          containsAll([
            // What the package HOLDS...
            'artifact_format',
            'capture_mode',
            // ...kept apart from what the page WAS.
            'content_kind',
            'content_kind_confidence',
            'content_kind_is_user_set',
          ]),
        );
      },
    );

    test('collections can remember a capture mode', () async {
      expect(
        await columnNames('collections'),
        contains('preferred_capture_mode'),
      );
    });

    test('queue tasks carry the capture mode', () async {
      expect(
        await columnNames('queue_tasks'),
        containsAll(['capture_mode', 'capture_mode_is_user_set']),
      );
      expect(
        await columnNames('queue_tasks'),
        isNot(contains('include_images')),
      );
    });
  });

  group('constraints', () {
    test('an entry may have no collection', () async {
      final columns = await db.customSelect('PRAGMA table_info(entries)').get();
      final collectionId = columns.firstWhere(
        (r) => r.read<String>('name') == 'collection_id',
      );
      expect(
        collectionId.read<int>('notnull'),
        0,
        reason: 'a standalone entry is a first-class library item',
      );
    });

    test('the standalone-entry unique index exists', () async {
      final rows = await db
          .customSelect(
            "SELECT name, sql FROM sqlite_master WHERE type = 'index' "
            "AND name = 'idx_entries_standalone_url'",
          )
          .get();
      expect(rows, hasLength(1));
      expect(
        rows.single.read<String>('sql'),
        contains('collection_id IS NULL'),
        reason:
            'a composite UNIQUE cannot enforce this — SQLite treats NULLs as '
            'distinct',
      );
    });

    test('foreign keys are on, and entries reference collections', () async {
      final pragma = await db.customSelect('PRAGMA foreign_keys').getSingle();
      expect(pragma.read<int>('foreign_keys'), 1);

      final keys = await db
          .customSelect('PRAGMA foreign_key_list(entries)')
          .get();
      expect(keys, hasLength(1));
      expect(keys.single.read<String>('table'), 'collections');
    });

    test('the read-path indexes are created with the schema', () async {
      final rows = await db
          .customSelect(
            "SELECT name FROM sqlite_master WHERE type = 'index' "
            "AND name LIKE 'idx_%'",
          )
          .get();
      final names = rows.map((r) => r.read<String>('name')).toSet();
      expect(
        names,
        containsAll([
          'idx_entries_standalone_url',
          'idx_entries_collection_order',
          'idx_entries_collection_save',
          'idx_entries_collection_read',
          'idx_entries_url_key',
          'idx_entries_canonical',
          'idx_entries_last_read',
          'idx_collections_lifecycle_read',
          'idx_collections_created',
          'idx_queue_state_order',
          'idx_history_source_visited',
          'idx_saved_sites_url',
        ]),
      );
    });
  });

  group('a clean install ships nothing', () {
    test('no page hints', () async {
      expect(await db.countPageHints(), 0);
    });

    test('no saved sites', () async {
      expect(await db.allSavedSites(), isEmpty);
    });

    test('no collections and no entries', () async {
      expect(await db.allCollections(), isEmpty);
      expect(await db.allEntries(), isEmpty);
    });

    test('no settings — not even a seed marker', () async {
      final rows = await db.select(db.settings).get();
      expect(rows, isEmpty);
    });
  });
}
