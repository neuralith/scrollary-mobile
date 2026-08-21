/// The V2 local store. **Schema version 1, created whole** (V2-D26).
///
/// Designed from the domain in docs/V2_ARCHITECTURE.md §6.4 — not from the V1
/// tables, and not migrated from anything. The V1 database
/// (`lib/storage/database.dart`) keeps running beside this one until its
/// cleanup points; the two never share a file.
///
/// Two boundaries this schema is built around:
///
/// * **What syncs carries a nullable `server_id` and cached `revision`.** The
///   local UUID is the permanent primary key; a canonical id sits beside it
///   and is never written over it, because file paths and manifests depend on
///   local ids.
/// * **What is device-owned has neither.** Offline copies, history, page
///   hints, the outbox itself. An offline copy also has no foreign key to its
///   Entry: a remote removal takes library rows and leaves the package on
///   disk (I14), and this row is what lets the cleanup surface say what it is
///   offering to remove.
///
/// `save_queue` and `save_runs` are deliberately absent for now: they are
/// ported from V1 and retargeted to `(entry, location)` by the capture lane
/// (E3), which owns their shape. Adding a guessed shape here would be a
/// second author for the same table.
library;

import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

part 'schema.g.dart';

/// User organisation, a tree. Exactly one system root (I1); deletion reparents
/// and never cascades into content (I5) — the RESTRICT below is the backstop
/// that makes forgetting the reparent an error instead of a data loss.
@DataClassName('FolderRow')
class Folders extends Table {
  TextColumn get id => text()();
  TextColumn get serverId => text().nullable()();
  TextColumn get parentId => text().nullable()();
  TextColumn get kind => text()();
  TextColumn get name => text()();
  IntColumn get sortKey => integer().withDefault(const Constant(0))();
  IntColumn get revision => integer().nullable()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<String> get customConstraints => [
    "CHECK (kind IN ('root','user'))",
    "CHECK ((kind = 'root') = (parent_id IS NULL))",
    'CHECK (parent_id IS NULL OR parent_id <> id)',
    'FOREIGN KEY (parent_id) REFERENCES folders (id) ON DELETE RESTRICT',
  ];
}

/// A logical work. No URL and no host — those belong to its Sources.
@DataClassName('CollectionRow')
class Collections extends Table {
  TextColumn get id => text()();
  TextColumn get serverId => text().nullable()();
  TextColumn get folderId => text()();
  TextColumn get name => text()();
  TextColumn get detectedTitle => text().withDefault(const Constant(''))();
  TextColumn get orderingBasis => text()();
  TextColumn get lifecycle => text().withDefault(const Constant('active'))();
  TextColumn get preferredSourceId => text().nullable()();
  IntColumn get sortKey => integer().withDefault(const Constant(0))();
  IntColumn get revision => integer().nullable()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<String> get customConstraints => [
    "CHECK (ordering_basis IN ('explicitNumericIndex','publicationDate',"
        "'detectedNextLink','discoveryOrder','userDefinedManualOrder'))",
    "CHECK (lifecycle IN ('active','archived'))",
    'FOREIGN KEY (folder_id) REFERENCES folders (id) ON DELETE RESTRICT',
    'FOREIGN KEY (preferred_source_id) REFERENCES sources (id) '
        'ON DELETE SET NULL',
  ];
}

/// One Collection as published on one site. `(host, path_key)` is identity —
/// V1's `collection_key`, one level down.
@DataClassName('SourceRow')
class Sources extends Table {
  TextColumn get id => text()();
  TextColumn get serverId => text().nullable()();
  TextColumn get collectionId => text()();
  TextColumn get host => text()();
  TextColumn get pathKey => text()();
  TextColumn get language => text().withDefault(const Constant(''))();
  TextColumn get lifecycle => text().withDefault(const Constant('active'))();
  TextColumn get resolvedIntoSourceId => text().nullable()();
  DateTimeColumn get firstSeenAt => dateTime()();
  DateTimeColumn get lastSeenAt => dateTime()();
  IntColumn get revision => integer().nullable()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<Set<Column>> get uniqueKeys => [
    {collectionId, host, pathKey},
  ];

  @override
  List<String> get customConstraints => [
    "CHECK (lifecycle IN ('active','dormant','dead','resolvedInto'))",
    'FOREIGN KEY (collection_id) REFERENCES collections (id) '
        'ON DELETE CASCADE',
    'FOREIGN KEY (resolved_into_source_id) REFERENCES sources (id) '
        'ON DELETE SET NULL',
  ];
}

/// One logical unit of reading. An Entry is NOT a URL. There are deliberately
/// no reading, save or download columns here: reading state has its own table
/// and its own clock, and whether this device holds bytes is an OfflineCopy.
@DataClassName('EntryRow')
class Entries extends Table {
  TextColumn get id => text()();
  TextColumn get serverId => text().nullable()();
  TextColumn get collectionId => text().nullable()();
  TextColumn get folderId => text().nullable()();
  RealColumn get ordinal => real().nullable()();
  TextColumn get placement => text()();
  TextColumn get title => text().withDefault(const Constant(''))();
  IntColumn get sortKey => integer().withDefault(const Constant(0))();
  IntColumn get revision => integer().nullable()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<String> get customConstraints => [
    "CHECK (placement IN ('placed','unplaced','userPlaced'))",
    // I3: a Folder iff no Collection. A standalone Entry is first-class.
    'CHECK ((collection_id IS NULL) = (folder_id IS NOT NULL))',
    // A position an unplaced Entry does not have would be a guess.
    "CHECK (placement <> 'unplaced' OR ordinal IS NULL)",
    'FOREIGN KEY (collection_id) REFERENCES collections (id) '
        'ON DELETE CASCADE',
    'FOREIGN KEY (folder_id) REFERENCES folders (id) ON DELETE RESTRICT',
  ];
}

/// This Entry, at one URL, on one Source. `url_key` unique is I6 and the
/// recognition hot path: a known URL resolves in one indexed lookup, offline.
@DataClassName('LocationRow')
class Locations extends Table {
  TextColumn get id => text()();
  TextColumn get serverId => text().nullable()();
  TextColumn get entryId => text()();
  TextColumn get sourceId => text().nullable()();
  TextColumn get url => text()();
  TextColumn get urlKey => text().unique()();
  TextColumn get sourceLabel => text().withDefault(const Constant(''))();
  RealColumn get sourceNumber => real().nullable()();
  DateTimeColumn get discoveredAt => dateTime()();
  TextColumn get discoveryBasis => text().withDefault(const Constant(''))();
  TextColumn get lifecycle => text().withDefault(const Constant('active'))();
  IntColumn get revision => integer().nullable()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<String> get customConstraints => [
    "CHECK (lifecycle IN ('active','retracted'))",
    'FOREIGN KEY (entry_id) REFERENCES entries (id) ON DELETE CASCADE',
    'FOREIGN KEY (source_id) REFERENCES sources (id) ON DELETE CASCADE',
  ];
}

/// The portable fact about an Entry, on its own row and its own clock so the
/// hottest mutation does not bump Entry metadata revisions.
@DataClassName('ReadingStateRow')
class ReadingStates extends Table {
  TextColumn get entryId => text()();
  TextColumn get status => text().withDefault(const Constant('unread'))();
  DateTimeColumn get firstOpenedAt => dateTime().nullable()();
  DateTimeColumn get lastReadAt => dateTime().nullable()();
  DateTimeColumn get completedAt => dateTime().nullable()();
  IntColumn get revision => integer().nullable()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {entryId};

  @override
  List<String> get customConstraints => [
    "CHECK (status IN ('unread','reading','completed'))",
    'FOREIGN KEY (entry_id) REFERENCES entries (id) ON DELETE CASCADE',
  ];
}

/// Progress scoped to the rendering it was measured against (I12): the Source
/// is part of the key, so a reading on one Source can never be silently read
/// as a claim about another.
@DataClassName('MeasurementRow')
class Measurements extends Table {
  TextColumn get entryId => text()();
  TextColumn get sourceId => text()();
  RealColumn get fraction => real()();
  DateTimeColumn get observedAt => dateTime()();
  IntColumn get revision => integer().nullable()();

  @override
  Set<Column> get primaryKey => {entryId, sourceId};

  @override
  List<String> get customConstraints => [
    'CHECK (fraction >= 0 AND fraction <= 1)',
    'FOREIGN KEY (entry_id) REFERENCES entries (id) ON DELETE CASCADE',
    'FOREIGN KEY (source_id) REFERENCES sources (id) ON DELETE CASCADE',
  ];
}

/// A mirrored intent, never content, plus this device's own claim state.
@DataClassName('DownloadRequestRow')
class DownloadRequests extends Table {
  TextColumn get id => text()();
  TextColumn get serverId => text().nullable()();
  TextColumn get entryId => text()();
  TextColumn get locationId => text().nullable()();
  TextColumn get state => text()();
  TextColumn get idempotencyKey => text().withDefault(const Constant(''))();
  TextColumn get createdBy => text().withDefault(const Constant(''))();
  DateTimeColumn get createdAt => dateTime()();
  TextColumn get claimedByDevice => text().withDefault(const Constant(''))();
  DateTimeColumn get claimedAt => dateTime().nullable()();
  DateTimeColumn get resolvedAt => dateTime().nullable()();
  TextColumn get failureReason => text().withDefault(const Constant(''))();
  IntColumn get revision => integer().nullable()();

  /// The local save task this device created when it claimed the request.
  /// Device state, never synced.
  TextColumn get localSaveTaskId => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<String> get customConstraints => [
    "CHECK (state IN ('pending','claimed','completed','failed','cancelled'))",
    'FOREIGN KEY (entry_id) REFERENCES entries (id) ON DELETE CASCADE',
    'FOREIGN KEY (location_id) REFERENCES locations (id) ON DELETE SET NULL',
  ];
}

/// Device-local bytes with provenance as values (V2-D22). No foreign key to
/// entries — deliberately. A remote removal takes library rows and leaves the
/// package on disk (I14); this row survives to name what cleanup would remove.
@DataClassName('OfflineCopyRow')
class OfflineCopies extends Table {
  TextColumn get id => text()();
  TextColumn get entryId => text()();

  // Provenance, copied at capture. Values, never references.
  TextColumn get locationUrl => text()();
  TextColumn get sourceName => text().withDefault(const Constant(''))();
  TextColumn get sourceHost => text().withDefault(const Constant(''))();
  TextColumn get sourceLanguage => text().withDefault(const Constant(''))();
  DateTimeColumn get capturedAt => dateTime()();

  TextColumn get artifactFormat => text()();
  TextColumn get contentPath => text()();
  IntColumn get byteSize => integer().withDefault(const Constant(0))();

  /// The reading anchor: position inside this artifact, meaningless without
  /// the bytes it indexes. Never leaves the device.
  IntColumn get anchorIndex => integer().nullable()();
  RealColumn get anchorOffset => real().nullable()();

  BoolColumn get active => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

/// One row per manual page visit. Unchanged in spirit from V1's
/// `browsing_history`: only navigation the user performed themselves is
/// written here, and it never synchronises — cloud sync is not cloud browsing
/// history.
@DataClassName('HistoryRow')
class History extends Table {
  TextColumn get id => text()();
  TextColumn get url => text()();
  TextColumn get urlKey => text()();
  TextColumn get host => text()();
  TextColumn get title => text()();
  TextColumn get source => text().withDefault(const Constant('manual'))();
  TextColumn get finalUrl => text().nullable()();
  BoolColumn get completed => boolean().withDefault(const Constant(true))();
  DateTimeColumn get visitedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Append-only, ordered intents awaiting the drain. The rowid is the order.
/// Entity kinds here are the synced kinds ONLY — an intent about an offline
/// copy or history cannot be expressed (I11).
@DataClassName('OutboxRow')
class Outbox extends Table {
  IntColumn get opId => integer().autoIncrement()();
  TextColumn get mutationId => text().unique()();
  TextColumn get entityKind => text()();
  TextColumn get entityId => text()();
  TextColumn get op => text()();
  TextColumn get payload => text()();
  DateTimeColumn get createdAt => dateTime()();
  IntColumn get attempts => integer().withDefault(const Constant(0))();
  TextColumn get lastError => text().nullable()();

  @override
  List<String> get customConstraints => [
    "CHECK (entity_kind IN ('folder','collection','source','entry',"
        "'location','readingState','measurement','downloadRequest'))",
    "CHECK (op IN ('upsert','delete'))",
  ];
}

/// One row of sync bookkeeping: the cursor is the highest server revision this
/// device has seen. Pending work is counted from the outbox, never cached.
@DataClassName('SyncStateRow')
class SyncState extends Table {
  IntColumn get id => integer()();
  IntColumn get cursor => integer().withDefault(const Constant(0))();
  DateTimeColumn get lastSuccessAt => dateTime().nullable()();
  DateTimeColumn get lastAttemptAt => dateTime().nullable()();
  TextColumn get lastError => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<String> get customConstraints => ['CHECK (id = 1)'];
}

/// What a person taught by tapping an element. Empty on a clean install;
/// nothing seeds it. Carried over from V1 unchanged.
@DataClassName('PageHintRow')
class PageHints extends Table {
  TextColumn get id => text()();
  TextColumn get host => text()();
  TextColumn get hintPath => text().nullable()();
  TextColumn get scope => text()();
  TextColumn get kind => text()();
  TextColumn get locatorJson => text()();
  TextColumn get exampleSourceUrl => text().nullable()();
  TextColumn get exampleTargetUrl => text().nullable()();
  BoolColumn get sameHostOnly => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get lastUsedAt => dateTime().nullable()();
  IntColumn get successCount => integer().withDefault(const Constant(0))();
  IntColumn get failureCount => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {id};
}

/// The user's own hand-ordered list of sites. Never seeded, never written by
/// automation. Carried over from V1 unchanged.
@DataClassName('SavedSiteRow')
class SavedSites extends Table {
  TextColumn get id => text()();
  TextColumn get url => text()();
  TextColumn get urlKey => text()();
  TextColumn get host => text()();
  TextColumn get title => text()();
  TextColumn get userTitle => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get lastOpenedAt => dateTime().nullable()();
  IntColumn get orderIndex => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {id};
}

/// Per-host icon cache; a null-bytes row is a negative entry. Carried over
/// from V1 unchanged.
@DataClassName('FaviconRow')
class Favicons extends Table {
  TextColumn get host => text()();
  BlobColumn get bytes => blob().nullable()();
  TextColumn get sourceUrl => text().nullable()();
  DateTimeColumn get fetchedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {host};
}

/// Small key-value settings, as in V1.
@DataClassName('SettingRow')
class LocalSettings extends Table {
  @override
  String get tableName => 'settings';

  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};
}

@DriftDatabase(
  tables: [
    Folders,
    Collections,
    Sources,
    Entries,
    Locations,
    ReadingStates,
    Measurements,
    DownloadRequests,
    OfflineCopies,
    History,
    Outbox,
    SyncState,
    PageHints,
    SavedSites,
    Favicons,
    LocalSettings,
  ],
)
class LibraryDatabase extends _$LibraryDatabase {
  /// [name] exists for tests; the app always uses the default. A different
  /// file from V1's `webread`, because the two schemas coexist until the V1
  /// cleanup points and must never share a database.
  LibraryDatabase({String name = 'scrollary_library'})
    : super(driftDatabase(name: name));
  LibraryDatabase.forTesting(super.executor);

  /// **One.** Created whole; no `onUpgrade`, no schema history (V2-D26).
  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();

      const indexes = [
        // I1: at most one root folder in this library.
        'CREATE UNIQUE INDEX IF NOT EXISTS idx_folders_one_root '
            "ON folders(kind) WHERE kind = 'root'",
        // I8: an ordinal is unique within its collection. Partial, because a
        // composite UNIQUE treats NULLs as distinct and standalone entries
        // have neither collection nor ordinal.
        'CREATE UNIQUE INDEX IF NOT EXISTS idx_entries_ordinal '
            'ON entries(collection_id, ordinal) '
            'WHERE collection_id IS NOT NULL AND ordinal IS NOT NULL',
        // Recognition index: (host, path_key) resolves a Source in one lookup.
        'CREATE UNIQUE INDEX IF NOT EXISTS idx_sources_identity '
            'ON sources(host, path_key)',
        // I13: at most one active offline copy per entry on this device.
        'CREATE UNIQUE INDEX IF NOT EXISTS idx_offline_copies_active '
            'ON offline_copies(entry_id) WHERE active = 1',
        // Idempotency by construction, mirroring the server: at most one open
        // request per entry.
        'CREATE UNIQUE INDEX IF NOT EXISTS idx_download_requests_open '
            'ON download_requests(entry_id) '
            "WHERE state IN ('pending','claimed')",
        // Read paths.
        'CREATE INDEX IF NOT EXISTS idx_locations_entry '
            'ON locations(entry_id)',
        'CREATE INDEX IF NOT EXISTS idx_locations_source '
            'ON locations(source_id)',
        'CREATE INDEX IF NOT EXISTS idx_entries_folder '
            'ON entries(folder_id) WHERE folder_id IS NOT NULL',
        'CREATE INDEX IF NOT EXISTS idx_collections_folder '
            'ON collections(folder_id, sort_key)',
        'CREATE INDEX IF NOT EXISTS idx_history_visited '
            'ON history(visited_at DESC)',
        'CREATE UNIQUE INDEX IF NOT EXISTS idx_saved_sites_url '
            'ON saved_sites(url_key)',
      ];
      for (final statement in indexes) {
        await customStatement(statement);
      }
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );
}
