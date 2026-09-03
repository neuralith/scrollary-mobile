/// The V2 local store. **Schema version 1, created whole** (V2-D26).
///
/// Designed from the domain in docs/V2_ARCHITECTURE.md §6.4 — not from the V1
/// tables, and not migrated from anything. The V1 database it replaced ran
/// beside it until the retirement cutover and never shared a file with it; a
/// device that ran an older build still has that file, and nothing here opens
/// it.
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
/// `save_queue` is the capture lane's own table (E3): V1's `queue_tasks`,
/// ported and retargeted to `(entry, location)`. `save_runs` is still absent,
/// and now for a different reason than when this was written: V2 *does* have a
/// Browser-driven traversal (`lib/recognition/walk.dart`), but it is a
/// **discovery** act that writes Entries and Locations and then ends. What it
/// resolves is durable the moment it is resolved, so there is no half-finished
/// run to resume — the queue rows it produced are the resume record.
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

  /// What this Collection is normally saved as (V2-D53), and what order its
  /// Entries are drawn in — two answers the user gave about the work, and two
  /// answers that follow them to their other devices.
  ///
  /// Columns rather than `settings` rows: both are per-Collection state, and
  /// a key-value row keyed by a local id could neither sync nor survive the
  /// Collection being merged into another. Empty string is **unset** — a
  /// question nobody has answered, which is not the same as an answer that
  /// happens to be the default; `captureModeFromName` and `parseEntrySort`
  /// both resolve an unreadable value to null for that reason.
  ///
  /// Opaque on the wire: the server stores and echoes both and interprets
  /// neither (contracts/openapi.yaml `Collection`), so a new sort field is a
  /// client release and not a backend one.
  TextColumn get captureMode => text().withDefault(const Constant(''))();
  TextColumn get entrySort => text().withDefault(const Constant(''))();
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
///
/// **That identity is unique library-wide, not per Collection** (I18): a site
/// publishes one work, and which work is the user's answer (V2-D45). The
/// unique index `idx_sources_identity` in [LibraryDatabase]'s `onCreate` is
/// where it is enforced, and the service enforces the same rule with the same
/// scope, so neither side can hold a Source state the other cannot. A
/// Collection-scoped constraint would be implied by it and is deliberately
/// absent: two spellings of one rule is how they come apart.
///
/// [host] is stored folded to lower case (DNS is case-insensitive); [pathKey]
/// is stored exactly as read, because RFC 3986 paths are case-sensitive.
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
  List<String> get customConstraints => [
    "CHECK (lifecycle IN ('active','dormant','dead','resolvedInto'))",
    'CHECK (host = lower(host))',
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

  /// The date the source said this page was published, when it said one.
  ///
  /// Evidence about a page, exactly like [sourceLabel] and [sourceNumber]
  /// beside it, so it lives on the Location rather than the Entry: two Sources
  /// of one Collection can publish the same Entry on different days, and the
  /// Entry has no one answer.
  ///
  /// **It synchronises**, through `contracts/openapi.yaml`'s `Location`. It
  /// has to: `ordering_basis: publicationDate` is library state that already
  /// crossed, so a Collection could be ordered by publication date on one
  /// device and by nothing at all on another, which is the same list in two
  /// orders. Writing it therefore moves the row's `updated_at` like any other
  /// synced field — it is the last-writer-wins clock, and this device does
  /// hold newer information about the row.
  ///
  /// Null is ordinary and permanent for a page nobody has opened, and for
  /// every page whose site prints no date.
  DateTimeColumn get publishedAt => dateTime().nullable()();
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

/// The device's save queue — V1's `queue_tasks`, retargeted to
/// `(entry, location)` (V2-D15). Device state, never synced (V2_SYNC.md §4.8).
///
/// The five states and their rules are ported verbatim from V1 and carried in
/// `lib/save/queue_task.dart`. Three of them are load-bearing here:
///
/// * `cancelled` is a **state, not a deletion** — a cancel preserves the row,
///   and only `lib/save/queue_repository.dart` deletes one, and only while it
///   is already terminal.
/// * `order_index` survives a cancellation, which is what lets the Undo behind
///   "removed from the queue" put a waiting row back exactly where it was
///   rather than at the end.
/// * every claim and every cancel is one conditional `UPDATE` against these
///   columns, so exactly one of a racing pair wins and the loser is told.
///
/// [locationUrl] is denormalised on purpose. `location_id` is a pointer into
/// library rows a Source may retract or a sync may remove; the address the
/// user asked to save is what the task is *about*, and a task that forgot it
/// could neither run, report nor be retried.
@DataClassName('SaveTaskRow')
class SaveQueue extends Table {
  TextColumn get id => text()();
  TextColumn get entryId => text()();
  TextColumn get locationId => text().nullable()();
  TextColumn get locationUrl => text()();

  /// `CaptureMode.name`, or null for a task queued before a mode was chosen —
  /// which means "decide from the settled page", not "assume one".
  TextColumn get captureMode => text().nullable()();
  BoolColumn get captureModeIsUserSet =>
      boolean().withDefault(const Constant(false))();

  /// queued | running | completed | failed | cancelled
  TextColumn get state => text().withDefault(const Constant('queued'))();

  /// `queue` | `direct` — queued work, or the record of a save started
  /// straight from the Browser. A `direct` row is only ever terminal.
  TextColumn get origin => text().withDefault(const Constant('queue'))();

  TextColumn get outcome => text().nullable()();
  TextColumn get lastError => text().nullable()();

  /// `StopReason.name`, when a named condition ended it.
  TextColumn get stopReason => text().nullable()();

  IntColumn get orderIndex => integer().withDefault(const Constant(0))();
  DateTimeColumn get queuedAt => dateTime()();
  DateTimeColumn get startedAt => dateTime().nullable()();
  DateTimeColumn get finishedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<String> get customConstraints => [
    "CHECK (state IN ('queued','running','completed','failed','cancelled'))",
    "CHECK (origin IN ('queue','direct'))",
    // A direct save creates no pending work: there is nothing for a pump to
    // release, so such a row exists only as history.
    "CHECK (origin <> 'direct' OR state NOT IN ('queued','running'))",
    'FOREIGN KEY (entry_id) REFERENCES entries (id) ON DELETE CASCADE',
    'FOREIGN KEY (location_id) REFERENCES locations (id) ON DELETE SET NULL',
  ];
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

/// What this device's last update check of a Collection came to.
///
/// **Device state, and never synced.** Per-Source check timestamps are on
/// V2_SYNC.md §4.8's list of what does not cross, and the reason holds: a
/// phone that checked an hour ago has said nothing about what a tablet has
/// done. The kind is deliberately absent from [SyncedEntityKind], so an
/// intent about one of these rows cannot be expressed.
///
/// It is a table rather than session memory because *Not checked yet* on
/// every launch is not what a device that checked five minutes ago should
/// say. What is **not** stored is the run in progress: [checking] has no
/// column, because a check that was interrupted by a kill is not still
/// running and a restart must not claim it is.
///
/// The set of Entries a check found is likewise session-only. It answers
/// "what arrived while you were looking", and after a restart those Entries
/// are simply Entries in the library.
@DataClassName('CollectionCheckRow')
class CollectionCheckStates extends Table {
  TextColumn get collectionId => text()();
  DateTimeColumn get checkedAt => dateTime().nullable()();
  BoolColumn get failed => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {collectionId};

  @override
  List<String> get customConstraints => [
    'FOREIGN KEY (collection_id) REFERENCES collections (id) '
        'ON DELETE CASCADE',
  ];
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

/// What this device has learned about whether an origin will hand over the
/// files it serves.
///
/// **Keyed by origin, and deliberately not by Source or Collection.** The fact
/// is about the machine that answers for the bytes: one reading site served
/// its own promotional images perfectly while every panel of the reading came
/// from a separate host that refused all of them. A Source is
/// `(host, path_key)`, so scoping it there would re-learn the same refusal
/// once per work on the same site — dozens of doomed requests each time — and
/// a Collection can span several Sources on different hosts. An origin also
/// survives a site reorganising its paths, and keeps a second CDN on the same
/// site judged on its own evidence.
///
/// **Learned, never seeded, and never synced.** Empty on a clean install, like
/// `page_hints` and `saved_sites`. It is an observation this device made about
/// how a host answered *this device*, which is not a fact about the library
/// and has no business travelling to another device that may sit behind a
/// different network.
///
/// Nothing here is a "supported sites" list in either direction: an entry only
/// ever says how a host answered, and the only thing it changes is how many
/// times the app asks again before believing it.
@DataClassName('AssetOriginRow')
class AssetOrigins extends Table {
  /// `scheme://host[:port]`, lowercased. The unit the answer belongs to.
  TextColumn get origin => text()();

  /// `unknown` · `suspected` · `refusing`. See `AssetOriginVerdict`.
  TextColumn get verdict => text().withDefault(const Constant('unknown'))();

  /// Captures — not assets — that this origin refused, counted once per
  /// Location so re-saving the same page cannot promote a verdict on its own.
  IntColumn get refusedCaptures => integer().withDefault(const Constant(0))();

  /// The last Location that was refused, so the count above stays honest.
  TextColumn get lastRefusedLocationKey => text().nullable()();

  /// When this origin last handed over a file. Any success at all clears a
  /// verdict: the host changed its mind, or it never meant it.
  DateTimeColumn get lastServedAt => dateTime().nullable()();
  DateTimeColumn get firstRefusedAt => dateTime().nullable()();

  /// When the verdict reached `refusing`. What staleness is measured from.
  DateTimeColumn get establishedAt => dateTime().nullable()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {origin};

  @override
  List<String> get customConstraints => [
    "CHECK (verdict IN ('unknown','suspected','refusing'))",
  ];
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
    SaveQueue,
    History,
    Outbox,
    SyncState,
    CollectionCheckStates,
    PageHints,
    SavedSites,
    Favicons,
    AssetOrigins,
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
        // Idempotent by construction, exactly as the request index above:
        // an Entry has one active copy (I13), so a second tap while a save
        // for it is still waiting or running is the same request, not a
        // second one. Keyed on the Entry rather than on `(entry, location)`
        // because saving one Entry from two Sources at once could only
        // produce two candidates for one active copy.
        'CREATE UNIQUE INDEX IF NOT EXISTS idx_save_queue_open '
            'ON save_queue(entry_id) '
            "WHERE state IN ('queued','running')",
        // The pump's own read: pending work in the order it was queued.
        'CREATE INDEX IF NOT EXISTS idx_save_queue_pending '
            'ON save_queue(state, order_index)',
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
