/// A library file in the shape a build before schema version 2 left on disk.
///
/// The only place the missing-column failure can be observed: every suite that
/// builds its database fresh gets the declared schema and can never see it.
/// Written through today's schema and then cut back, rather than restating the
/// whole of version 1, so the fixture describes exactly one thing — the delta
/// [LibraryDatabase]'s `onUpgrade` closes.
library;

import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:web_reader/data/schema.dart';

/// When everything in the fixture happened.
final versionOneLibraryAt = DateTime.utc(2026, 8, 1, 12);

/// Writes one Collection with one Entry, Source, Location, reading state and
/// offline copy into [file], then strips the file back to version 1.
Future<void> writeVersionOneLibrary(
  File file, {
  String collectionName = 'A work',
  String entryTitle = 'Entry 12',
}) async {
  final at = versionOneLibraryAt;
  final db = LibraryDatabase.forTesting(NativeDatabase(file));

  await db
      .into(db.folders)
      .insert(
        FoldersCompanion.insert(
          id: 'root',
          kind: 'root',
          name: 'Library',
          updatedAt: at,
        ),
      );
  await db
      .into(db.collections)
      .insert(
        CollectionsCompanion.insert(
          id: 'coll',
          folderId: 'root',
          name: collectionName,
          orderingBasis: 'discoveryOrder',
          updatedAt: at,
        ),
      );
  await db
      .into(db.entries)
      .insert(
        EntriesCompanion.insert(
          id: 'entry',
          collectionId: const Value('coll'),
          ordinal: const Value(12),
          placement: 'placed',
          title: Value(entryTitle),
          updatedAt: at,
        ),
      );
  await db
      .into(db.readingStates)
      .insert(
        ReadingStatesCompanion.insert(
          entryId: 'entry',
          status: const Value('reading'),
          lastReadAt: Value(at),
          updatedAt: at,
        ),
      );
  await db
      .into(db.offlineCopies)
      .insert(
        OfflineCopiesCompanion.insert(
          id: 'copy',
          entryId: 'entry',
          locationUrl: 'https://x.example/work/12',
          capturedAt: at,
          artifactFormat: 'structuredDocument',
          contentPath: '/packages/entry/document.json',
          createdAt: at,
        ),
      );

  await db
      .into(db.sources)
      .insert(
        SourcesCompanion.insert(
          id: 'source',
          collectionId: 'coll',
          host: 'x.example',
          pathKey: '/work',
          firstSeenAt: at,
          lastSeenAt: at,
          updatedAt: at,
        ),
      );
  await db
      .into(db.locations)
      .insert(
        LocationsCompanion.insert(
          id: 'loc',
          entryId: 'entry',
          sourceId: const Value('source'),
          url: 'https://x.example/work/12',
          urlKey: 'x.example/work/12',
          discoveredAt: at,
          updatedAt: at,
        ),
      );

  // What version 2 added, taken back off.
  await db.customStatement('ALTER TABLE collections DROP COLUMN capture_mode');
  await db.customStatement('ALTER TABLE collections DROP COLUMN entry_sort');
  await db.customStatement('ALTER TABLE locations DROP COLUMN published_at');
  await db.customStatement('DROP TABLE collection_check_states');
  await db.customStatement('DROP TABLE asset_origins');
  await db.customStatement('PRAGMA user_version = 1');
  await db.close();
}
