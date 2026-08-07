/// The local library. **Schema version 1, created whole.**
///
/// There is no migration system in this file and deliberately no room for one to
/// grow back by accident: [AppDatabase.schemaVersion] is 1, the strategy has an
/// `onCreate` and no `onUpgrade`, and `database_test.dart` asserts both — plus
/// that no table or column from any earlier model exists.
///
/// The product model is four concepts and the physical schema uses them
/// directly:
///
/// * **Library** — every row in [Collections] plus every standalone [Entries]
///   row. Not a table; a view over the two.
/// * **Collection** — a related group of entries: a sequential publication, a
///   dated feed, a multi-page document, or a group the user made by hand.
/// * **Entry** — one independently readable saved unit. **`collection_id` is
///   nullable**: a standalone entry is a first-class library citizen and is
///   never wrapped in a collection of one to make the schema tidy.
/// * **Page / Section** — structural parts *inside* an entry. They live in the
///   entry's `manifest.json`, next to the bytes they describe, not in a table:
///   the manifest is what makes an entry directory self-describing, and a second
///   copy in SQLite would be a cache that can disagree with the files.
library;

import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import '../core/url_utils.dart' show normalizeUrl;

part 'database.g.dart';

/// A related group of entries.
@DataClassName('Collection')
class Collections extends Table {
  TextColumn get id => text()();

  /// Detected title, as the source wrote it.
  TextColumn get title => text()();

  /// What the user renamed it to. Presentation only — never part of matching,
  /// never part of a storage path.
  TextColumn get userTitle => text().nullable()();

  TextColumn get sourceUrl => text()();
  TextColumn get host => text()();

  /// Identity within a host. What a later save matches against, so a rename can
  /// never split a collection or create a second one.
  TextColumn get collectionKey => text().nullable()();

  /// A stable URL for the collection's index page, when the source offered one.
  TextColumn get collectionIndexUrl => text().nullable()();

  /// Which signal produced the key, and how much it can be trusted. Kept so a
  /// wrong grouping is explainable rather than mysterious.
  TextColumn get identityBasis => text().nullable()();
  TextColumn get identityConfidence => text().nullable()();

  // --- content shape (three independent dimensions; see content_shape.dart) --

  /// `ContentKind.name`. What the entries in this collection are.
  TextColumn get contentKind =>
      text().withDefault(const Constant('unknownWebContent'))();

  /// `SequenceKind.name`. How the entries continue into one another — including
  /// `none`, which is a real answer.
  TextColumn get sequenceKind => text().withDefault(const Constant('none'))();

  /// `OrderingBasis.name`. What decides the reading order.
  TextColumn get orderingBasis =>
      text().withDefault(const Constant('discoveryOrder'))();

  /// `ShapeConfidence.name` for the two above. Low means the UI says
  /// "saved items" instead of naming a structure the source never declared.
  TextColumn get shapeConfidence => text().withDefault(const Constant('low'))();

  /// How many entries the source says exist, when it said so at all.
  ///
  /// **Nullable, and usually null.** An open-ended sequence has no total, and a
  /// number here that was never published is a lie the whole UI then repeats.
  IntColumn get knownEntryTotal => integer().nullable()();

  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get lastOpenedAt => dateTime().nullable()();
  DateTimeColumn get lastSavedAt => dateTime().nullable()();

  /// Denormalised reading pointers. Derivable, but every library query orders on
  /// them, and recomputing a per-collection aggregate for each row on every
  /// stream emission is the difference between a snappy list and a stuttery one.
  /// Written in the same call as the entry change that causes them.
  TextColumn get lastOpenedEntryId => text().nullable()();
  TextColumn get lastCompletedEntryId => text().nullable()();
  DateTimeColumn get lastReadAt => dateTime().nullable()();

  // --- update checking ------------------------------------------------------
  // Outcome of the last "check for new entries". Latest-known and unsaved counts
  // are deliberately NOT denormalised — they derive from the entries table,
  // where a stale copy would be a lie the UI repeats.

  DateTimeColumn get lastCheckAt => dateTime().nullable()();
  DateTimeColumn get lastCheckSuccessAt => dateTime().nullable()();
  TextColumn get lastCheckError => text().nullable()();

  /// upToDate / updatesAvailable / failed / cancelled / needsUserInput.
  TextColumn get lastCheckResult => text().nullable()();

  // --- lifecycle ------------------------------------------------------------

  /// `active` | `archived`. Archiving hides a collection and excludes it from
  /// checks; it never touches entries or files.
  TextColumn get lifecycle => text().withDefault(const Constant('active'))();

  DateTimeColumn get archivedAt => dateTime().nullable()();

  /// What to do with a finished entry's offline files when the reader moves
  /// forward inside this collection: `remove` · `keep`, or **null** while this
  /// collection has never been asked.
  ///
  /// The only source of truth. There is no app-wide default and no per-entry
  /// copy: null means "ask on the next eligible transition", and an unrecognised
  /// value reads as null, which asks rather than guessing at removal.
  TextColumn get cleanupPreference => text().nullable()();

  /// `CaptureMode.name` the user asked to reuse for this collection, or null
  /// while they never said.
  ///
  /// **A proposal, never an instruction.** Every save re-measures the page and
  /// runs this through `CaptureCapabilities.resolve`, so a remembered "text
  /// and images" cannot force a document out of a page that has no text — it
  /// falls back and the run says why. An unrecognised value reads as null,
  /// which means "detect", not "guess".
  TextColumn get preferredCaptureMode => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<Set<Column>> get uniqueKeys => [
    {host, collectionKey},
  ];
}

/// One independently readable saved unit.
@DataClassName('Entry')
class Entries extends Table {
  TextColumn get id => text()();

  /// The collection this entry belongs to, or **null for a standalone entry**.
  ///
  /// Nullable is the whole point: a single saved article is a library item in
  /// its own right. Wrapping it in a one-entry collection would put a group in
  /// the library that the user never made and cannot meaningfully open.
  TextColumn get collectionId =>
      text().nullable().references(Collections, #id)();

  TextColumn get title => text()();

  /// The address this entry was saved from. Durable metadata: it survives
  /// removal of the offline files, archiving, restoring, re-saving and every
  /// reading-state write, because every writer names its columns. It is what
  /// "Open original page" stands on.
  TextColumn get sourceUrl => text()();

  /// Normalised [sourceUrl] — identity.
  TextColumn get urlKey => text()();

  /// `<link rel=canonical>` when the page declared one. A second identity
  /// signal, and the one that catches a navigation loop that changes the address
  /// while serving the same document.
  TextColumn get canonicalUrl => text().nullable()();

  /// Registrable host of [sourceUrl], lowercased. Denormalised onto the entry
  /// because a standalone entry has no collection to read it from, and because
  /// source attribution shows the domain on every screen.
  TextColumn get host => text().withDefault(const Constant(''))();

  /// The page's own `<title>`, kept verbatim. [title] may be cleaned up for
  /// display; this is what the source actually called it.
  TextColumn get sourceTitle => text().nullable()();

  /// Publication date, only when it was parsed from the page with confidence.
  /// Null means "not published, as far as we can honestly tell".
  DateTimeColumn get publishedAt => dateTime().nullable()();

  /// `ContentKind.name` for this entry, and how much that is trusted.
  TextColumn get contentKind =>
      text().withDefault(const Constant('unknownWebContent'))();
  TextColumn get contentKindConfidence =>
      text().withDefault(const Constant('low'))();

  /// True once the user corrected the detected kind. Detection must never
  /// overwrite a human answer on a later re-save.
  BoolColumn get contentKindIsUserSet =>
      boolean().withDefault(const Constant(false))();

  // --- stored artifact ------------------------------------------------------
  // What this entry's package actually HOLDS, as opposed to what the page was
  // (`content_kind`) or what the save was asked for (`capture_mode`). Kept
  // apart on purpose: correcting a label to "article" must never make an image
  // package get parsed as a document, and only this column decides that.

  /// `ArtifactFormat.name`. Mirrors the entry's `manifest.json`, which stays
  /// the authority — this copy exists so the library can describe an entry
  /// without opening a file per row.
  TextColumn get artifactFormat =>
      text().withDefault(const Constant('imageSequence'))();

  /// `CaptureMode.name` actually used, or null for an entry that was only ever
  /// discovered. What was *used*, never what was requested: a run that fell
  /// back records the fallback.
  ///
  /// There is deliberately no `capture_mode_is_user_set` beside it. Whether a
  /// person picked the mode is a fact about the *save*, and it is recorded on
  /// the run, the queue row and the entry's manifest. A fourth copy on the row
  /// would be one more place for the same fact to drift out of agreement,
  /// and nothing reads it that the manifest cannot answer.
  TextColumn get captureMode => text().nullable()();

  // --- save state -----------------------------------------------------------
  // knownRemote | saving | complete | partial | failed
  //
  // Queueing is deliberately absent: a queued save is a row in [QueueTasks],
  // not a state of the entry, and nothing here changes until the engine
  // commits. Anything asking "is this entry spoken for?" must ask the queue —
  // see [AppDatabase.reconcileDiscoveredEntries], which does.

  TextColumn get saveStatus => text()();

  /// Relative to the FileStore root. Never absolute.
  TextColumn get contentPath => text().nullable()();
  DateTimeColumn get savedAt => dateTime().nullable()();
  IntColumn get detectedAssetCount =>
      integer().withDefault(const Constant(0))();
  IntColumn get storedAssetCount => integer().withDefault(const Constant(0))();
  TextColumn get nextSourceUrl => text().nullable()();

  /// Authoritative position within the collection. Its *meaning* is given by the
  /// collection's `orderingBasis`, which is why the basis is stored rather than
  /// assumed.
  IntColumn get entryOrder => integer().withDefault(const Constant(0))();
  TextColumn get saveError => text().nullable()();
  IntColumn get byteSize => integer().withDefault(const Constant(0))();

  /// The number the *source* printed for this entry, when it printed one. `REAL`
  /// so `12.5` works. Null for anything not numeric — and null is never filled
  /// in by guessing.
  RealColumn get entryNumber => real().nullable()();

  /// The marker as the source wrote it: `Part 3`, `Prologue`, `Page 12 of 40`.
  /// Kept verbatim; the display label is derived in `entry_labels.dart`.
  TextColumn get sourceMarker => text().nullable()();

  // --- reading state --------------------------------------------------------
  // Deliberately separate from save state: an entry can be re-saved and stay
  // completed, and a save must never reset where the user was.

  TextColumn get readStatus => text().withDefault(const Constant('unread'))();

  /// 0..1 through the entry. The durable half of the position — content
  /// independent, so it still means something after a re-save.
  RealColumn get progressFraction => real().withDefault(const Constant(0))();

  /// Anchor: page index within the entry plus how far down it. Precise, but goes
  /// stale if the page count changes — which is what the fraction covers.
  IntColumn get progressPageIndex => integer().withDefault(const Constant(0))();
  RealColumn get progressOffsetInPage =>
      real().withDefault(const Constant(0))();

  DateTimeColumn get firstOpenedAt => dateTime().nullable()();
  DateTimeColumn get lastReadAt => dateTime().nullable()();
  DateTimeColumn get completedAt => dateTime().nullable()();
  DateTimeColumn get progressUpdatedAt => dateTime().nullable()();

  // --- discovery ------------------------------------------------------------
  // An entry found by an update check is a real row with
  // `saveStatus = 'knownRemote'` and no `contentPath` — known to exist at the
  // source, holding nothing locally. Discovered, saved and read are three
  // independent facts about one entry.
  //
  // This is the one state the app may retract on its own: a row that is still
  // *only* a discovery describes the source, so a later reliable reading of
  // the source can show it is no longer true. The moment anything of the
  // user's is attached to it — bytes, a queued save, a reading position — it
  // stops being retractable. `reconcileDiscoveredEntries` is that rule.

  DateTimeColumn get discoveredAt => dateTime().nullable()();

  /// entryList / nextChain / userPageHint / manual.
  TextColumn get discoveryBasis => text().nullable()();
  TextColumn get discoveryConfidence => text().nullable()();

  /// When the USER removed this entry's offline files. Distinct from files the
  /// system lost: a removed entry reads as "not available offline — save again",
  /// never as an error. Cleared explicitly on re-save.
  DateTimeColumn get offlineRemovedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};

  /// Identity within a collection. Standalone entries (`collection_id IS NULL`)
  /// are covered by a partial unique index created in `onCreate` — SQLite treats
  /// NULLs as distinct in a composite UNIQUE, so this constraint alone would let
  /// the same standalone page be saved twice.
  @override
  List<Set<Column>> get uniqueKeys => [
    {collectionId, urlKey},
  ];
}

/// Just enough to recognise and resume an interrupted multi-entry save run.
@DataClassName('SaveRun')
class SaveRuns extends Table {
  TextColumn get id => text()();
  TextColumn get collectionId => text().nullable()();
  TextColumn get startUrl => text()();
  TextColumn get currentUrl => text().nullable()();

  /// How many *new* entries this run was authorised to save. Always a real
  /// number, including for open-ended sequences — there is no "unlimited".
  IntColumn get requestedEntries => integer()();
  IntColumn get completedEntries => integer().withDefault(const Constant(0))();
  TextColumn get state => text()();
  TextColumn get lastError => text().nullable()();

  /// Which stopping condition ended the run (`StopReason.name`), or null while
  /// it is still going. Named rather than inferred, so "stopped because the site
  /// asked for a login" can never be reported as "finished".
  TextColumn get stopReason => text().nullable()();

  /// Newline-separated normalised URLs already walked in this run.
  TextColumn get visitedUrls => text().withDefault(const Constant(''))();

  /// Newline-separated canonical URLs already seen. Kept separately from
  /// [visitedUrls] because the loop that matters most is the one where the
  /// address changes and the document does not.
  TextColumn get visitedCanonicals => text().withDefault(const Constant(''))();

  /// The duplicate policy the run started with, so a resume applies the same one
  /// instead of silently reverting to the default.
  TextColumn get duplicatePolicy => text().nullable()();

  /// Session-scoped answers to "this entry is already saved". Persisted on the
  /// run — they survive an interrupted-session resume — and die with it. Never a
  /// global preference.
  TextColumn get sessionDuplicateDecision => text().nullable()();
  TextColumn get sessionPartialDecision => text().nullable()();

  /// `SaveScope.name` — currentPageOnly | selectedEntries | fixedCount.
  /// A resume continues in the same mode, and an unrecognised value (a row
  /// written before the open-ended scope was removed) reads as the safest
  /// one rather than saving more than was asked for.
  TextColumn get scope =>
      text().withDefault(const Constant('currentPageOnly'))();

  /// The user's explicit storage ceiling in bytes, when they set one. Required
  /// alongside a count for open-ended sequences.
  IntColumn get maxBytes => integer().nullable()();

  /// `CaptureMode.name` the run was started with — image sequence, text only,
  /// or text and images.
  ///
  /// Replaced the old `include_images` boolean, which could not express the
  /// difference between "an ordered sequence of full-size images" and "an
  /// article with pictures in it" and which nothing ever read. Nullable
  /// because a resume of a run started before the mode was chosen re-detects
  /// rather than assuming one.
  TextColumn get captureMode => text().nullable()();

  /// Whether the user picked the mode themselves, so a resume does not quietly
  /// re-detect over a deliberate choice.
  BoolColumn get captureModeIsUserSet =>
      boolean().withDefault(const Constant(false))();

  /// Why a running save is paused (`browserHidden` today; null otherwise).
  TextColumn get pauseReason => text().nullable()();

  /// `direct` | `queue` — how this run was launched. Persisted so an interrupted
  /// direct save resumes as a direct save rather than being quietly turned into
  /// pending queue work.
  TextColumn get origin => text().withDefault(const Constant('queue'))();

  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

/// One row per user preference, and the store for local acknowledgements.
///
/// A tiny key-value table rather than columns: preferences arrive one at a time
/// and none of them deserves a schema change each.
class Settings extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};
}

/// The persistent activity queue.
///
/// Deliberately a **separate table** from [SaveRuns]: that table is the save
/// loop's own resume record with its own lifecycle. Queue entries outlive their
/// run — they *are* the history — so overloading one table would force every
/// existing query to re-learn which rows are which. The queue schedules; the
/// controllers still do the work.
class QueueTasks extends Table {
  TextColumn get id => text()();

  /// entrySave | sequenceSave | collectionCheck | checkAllCollections |
  /// offlineCleanup
  TextColumn get taskType => text()();
  TextColumn get collectionId => text().nullable()();
  TextColumn get startUrl => text().nullable()();

  /// The explicit ceiling on new entries. Never null for a multi-entry task.
  IntColumn get entryLimit => integer().nullable()();
  IntColumn get maxBytes => integer().nullable()();

  /// `CaptureMode.name` for a save task, or null for a task that stores
  /// nothing (a check, a cleanup) and for one queued before a mode was chosen.
  TextColumn get captureMode => text().nullable()();

  /// Whether that mode was the user's explicit choice.
  BoolColumn get captureModeIsUserSet =>
      boolean().withDefault(const Constant(false))();

  TextColumn get duplicatePolicy => text().nullable()();

  /// `SaveScope.name`.
  TextColumn get scope => text().nullable()();

  /// queued | running | completed | failed | cancelled
  TextColumn get state => text().withDefault(const Constant('queued'))();

  /// `queue` | `direct` — whether this row is queued work or the record of a
  /// save the user started straight from the Browser.
  ///
  /// A `direct` row is **only ever terminal**: a direct save creates no pending
  /// entry, so nothing here can be released by the queue pump. It exists for
  /// Activity history and error reporting.
  TextColumn get origin => text().withDefault(const Constant('queue'))();

  /// Short human summary of how it ended.
  TextColumn get outcome => text().nullable()();
  TextColumn get lastError => text().nullable()();

  /// Which stopping condition ended it (`StopReason.name`), when one did.
  TextColumn get stopReason => text().nullable()();

  /// FIFO order within the queue.
  IntColumn get orderIndex => integer().withDefault(const Constant(0))();
  DateTimeColumn get queuedAt => dateTime()();
  DateTimeColumn get startedAt => dateTime().nullable()();
  DateTimeColumn get finishedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// A navigation hint the **user** created by pointing at a control, when
/// automatic detection was not confident.
///
/// Three properties make this a local user preference rather than a site
/// catalogue, and all three are asserted in tests:
///
/// 1. **The app ships none.** This table is empty on a clean install and nothing
///    seeds it. There is no bundled selector, host list or provider catalogue
///    anywhere in the binary.
/// 2. **Only the user writes it.** A row exists because a person tapped an
///    element on a page they had already opened themselves.
/// 3. **It is local.** No account, no sync, no upload, no sharing.
///
/// `host` and `hintPath` are stored because that is *where the user made the
/// hint* — a hint taught on one collection must never be applied to an unrelated
/// one. They are scoping for a local preference, not behaviour keyed to a
/// website the developer chose to support.
@DataClassName('UserPageHintRow')
class UserPageHints extends Table {
  TextColumn get id => text()();
  TextColumn get host => text()();

  /// Collection fingerprint, or a path shape for `pathShape` scope. Null only
  /// for site-wide hints, which the user has to opt into explicitly.
  TextColumn get hintPath => text().nullable()();
  TextColumn get scope => text()();
  TextColumn get kind => text()();

  /// Serialised `DomLocator` — a bag of independent signals, not one selector.
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

/// One row per *manual* page visit in the Browser.
///
/// Deliberately a separate table from [SavedSites]: history is a log the user
/// clears by time range, saved sites are a curated list they order by hand.
/// Storing one as a flavour of the other would make "clear the last hour" able
/// to delete a bookmark.
///
/// Only navigation the user performed themselves is written here. Save
/// automation and update checks move the same WebView and must never appear.
class BrowsingHistory extends Table {
  TextColumn get id => text()();
  TextColumn get url => text()();

  /// Normalised [url]. Grouping, dedup-within-a-window and "remove every visit
  /// to this page" all key off this, never the raw text.
  TextColumn get urlKey => text()();
  TextColumn get host => text()();
  TextColumn get title => text()();

  /// Where the visit came from. Persisted even though the UI only ever shows
  /// `manual`: a row that says how it got here is debuggable, and a filter is
  /// cheaper to widen than a lost column is to reconstruct.
  TextColumn get source => text().withDefault(const Constant('manual'))();

  /// The address the load actually settled on, when a redirect moved it.
  TextColumn get finalUrl => text().nullable()();

  /// Only completed, user-visible destinations are recorded, so this is true for
  /// every row written today. Kept because "the load finished" is the property
  /// the recording rule turns on, and an explicit column is what makes that rule
  /// inspectable rather than implied by absence.
  BoolColumn get completed => boolean().withDefault(const Constant(true))();

  DateTimeColumn get visitedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

/// The user's own list of sites. User-controlled, hand-ordered, never written by
/// automation, and never seeded with a site the developer chose.
class SavedSites extends Table {
  TextColumn get id => text()();
  TextColumn get url => text()();

  /// Identity for duplicate detection. Two saved sites may share a host; they
  /// may not share a normalised URL.
  TextColumn get urlKey => text()();
  TextColumn get host => text()();
  TextColumn get title => text()();

  /// What the user typed instead. Presentation only — [title] is kept so
  /// clearing a rename falls back to something real.
  TextColumn get userTitle => text().nullable()();

  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get lastOpenedAt => dateTime().nullable()();

  /// Hand-ordered position. Ties fall back to [createdAt], so a row that was
  /// never reordered still has a stable place.
  IntColumn get orderIndex => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {id};
}

/// A tiny per-host icon cache. Optional by construction: a miss renders the
/// hostname-initial fallback and nothing upstream waits on it.
class FaviconCache extends Table {
  TextColumn get host => text()();

  /// The icon bytes, or null when the last attempt failed. A null row is a
  /// *negative* cache entry — it stops every list rebuild from re-requesting an
  /// icon the site does not have.
  BlobColumn get bytes => blob().nullable()();
  TextColumn get sourceUrl => text().nullable()();
  DateTimeColumn get fetchedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {host};
}

@DriftDatabase(
  tables: [
    Collections,
    Entries,
    SaveRuns,
    UserPageHints,
    Settings,
    QueueTasks,
    BrowsingHistory,
    SavedSites,
    FaviconCache,
  ],
)
class AppDatabase extends _$AppDatabase {
  /// [name] exists for integration tests, which give every test file its own
  /// database so no state leaks between them. The app always uses the default.
  AppDatabase({String name = 'webread'}) : super(driftDatabase(name: name));
  AppDatabase.forTesting(super.executor);

  /// **One.** This schema is created whole and has no history.
  ///
  /// There is no `onUpgrade` branch, no schema dump, no step verifier and no
  /// data-copying routine anywhere in the project. If the schema needs to change
  /// after release, that will be a migration written then — not a chain of
  /// branches kept alive now for a shape no installed copy has ever had.
  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();

      // Standalone-entry identity. A composite UNIQUE cannot do this job:
      // SQLite treats NULLs as distinct, so `UNIQUE(collection_id, url_key)`
      // happily accepts the same standalone page twice.
      await customStatement(
        'CREATE UNIQUE INDEX IF NOT EXISTS idx_entries_standalone_url '
        'ON entries(url_key) WHERE collection_id IS NULL',
      );

      // Read paths that exist on every library screen. Cheap at our row counts,
      // and created with the schema rather than bolted on later.
      const indexes = [
        'CREATE INDEX IF NOT EXISTS idx_entries_collection_order '
            'ON entries(collection_id, entry_order)',
        'CREATE INDEX IF NOT EXISTS idx_entries_collection_save '
            'ON entries(collection_id, save_status)',
        'CREATE INDEX IF NOT EXISTS idx_entries_collection_read '
            'ON entries(collection_id, read_status)',
        'CREATE INDEX IF NOT EXISTS idx_entries_url_key ON entries(url_key)',
        'CREATE INDEX IF NOT EXISTS idx_entries_canonical '
            'ON entries(canonical_url)',
        'CREATE INDEX IF NOT EXISTS idx_entries_last_read '
            'ON entries(last_read_at DESC)',
        'CREATE INDEX IF NOT EXISTS idx_collections_lifecycle_read '
            'ON collections(lifecycle, last_read_at DESC)',
        'CREATE INDEX IF NOT EXISTS idx_collections_created '
            'ON collections(created_at DESC)',
        'CREATE INDEX IF NOT EXISTS idx_queue_state_order '
            'ON queue_tasks(state, order_index)',
        'CREATE INDEX IF NOT EXISTS idx_history_source_visited '
            'ON browsing_history(source, visited_at DESC)',
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

  // --- user page hints ------------------------------------------------------

  Future<List<UserPageHintRow>> hintsForHost(String host) =>
      (select(userPageHints)..where((t) => t.host.equals(host))).get();

  Stream<List<UserPageHintRow>> watchAllHints() => (select(
    userPageHints,
  )..orderBy([(t) => OrderingTerm.desc(t.createdAt)])).watch();

  /// How many hints exist. Used by the "the app ships no site rules" test, which
  /// asserts a freshly created database has zero.
  Future<int> countPageHints() async {
    final count = userPageHints.id.count();
    final row = await (selectOnly(
      userPageHints,
    )..addColumns([count])).getSingle();
    return row.read(count) ?? 0;
  }

  Future<void> upsertHint(UserPageHintRow hint) =>
      into(userPageHints).insertOnConflictUpdate(hint);

  Future<void> deleteHint(String id) =>
      (delete(userPageHints)..where((t) => t.id.equals(id))).go();

  Future<int> clearPageHints() => delete(userPageHints).go();

  Future<void> recordHintUse(String id, {required bool success}) async {
    final row = await (select(
      userPageHints,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    if (row == null) return;
    await (update(userPageHints)..where((t) => t.id.equals(id))).write(
      UserPageHintsCompanion(
        lastUsedAt: Value(success ? DateTime.now() : row.lastUsedAt),
        successCount: Value(success ? row.successCount + 1 : row.successCount),
        failureCount: Value(success ? row.failureCount : row.failureCount + 1),
      ),
    );
  }

  // --- collections ----------------------------------------------------------

  Future<Collection?> findCollectionBySourceUrl(String sourceUrl) => (select(
    collections,
  )..where((t) => t.sourceUrl.equals(sourceUrl))).getSingleOrNull();

  Future<void> upsertCollection(Collection collection) =>
      into(collections).insertOnConflictUpdate(collection);

  /// The collection a future save should join: matched on identity, never on
  /// display name.
  Future<Collection?> findCollectionByKey(String host, String collectionKey) =>
      (select(collections)..where(
            (t) => t.host.equals(host) & t.collectionKey.equals(collectionKey),
          ))
          .getSingleOrNull();

  Future<Collection?> collectionById(String id) =>
      (select(collections)..where((t) => t.id.equals(id))).getSingleOrNull();

  Future<void> renameCollection(String id, String? userTitle) =>
      (update(collections)..where((t) => t.id.equals(id))).write(
        CollectionsCompanion(
          userTitle: Value(
            userTitle == null || userTitle.trim().isEmpty
                ? null
                : userTitle.trim(),
          ),
        ),
      );

  Future<void> markCollectionSaved(String id, DateTime at) =>
      (update(collections)..where((t) => t.id.equals(id))).write(
        CollectionsCompanion(lastSavedAt: Value(at)),
      );

  /// Record the detected shape of a collection. Narrow writer: shape is a claim
  /// about structure, so it must only ever be set deliberately.
  Future<void> writeCollectionShape(String id, CollectionsCompanion values) =>
      (update(collections)..where((t) => t.id.equals(id))).write(values);

  /// Delete one collection's row.
  ///
  /// Its entries must be gone first: `PRAGMA foreign_keys` is on, so this
  /// fails rather than orphaning them. Only permanent deletion reaches here —
  /// archiving writes [setCollectionLifecycle] and removing offline files
  /// writes no collection column at all.
  Future<int> deleteCollection(String id) =>
      (delete(collections)..where((t) => t.id.equals(id))).go();

  /// Delete every entry of one collection, reading state included.
  ///
  /// The counterpart of [deleteCollection] and never used on its own: an
  /// entry-shaped hole under a collection that still exists would be a
  /// collection that has lost its contents without saying so.
  Future<int> deleteEntriesForCollection(String collectionId) =>
      (delete(entries)..where((t) => t.collectionId.equals(collectionId))).go();

  /// Remove collections nothing points at. Only ever empty ones — a collection
  /// with entries is never deleted here.
  Future<int> deleteEmptyCollections() async {
    final used =
        await (selectOnly(entries, distinct: true)
              ..addColumns([entries.collectionId])
              ..where(entries.collectionId.isNotNull()))
            .map((r) => r.read(entries.collectionId)!)
            .get();
    return (delete(collections)..where((t) => t.id.isNotIn(used))).go();
  }

  Future<List<Entry>> allEntries() => select(entries).get();

  /// Standalone entries — the library's other first-class citizen.
  Future<List<Entry>> standaloneEntries() =>
      (select(entries)..where((t) => t.collectionId.isNull())).get();

  Future<void> reassignEntry(String entryId, String? collectionId) =>
      (update(entries)..where((t) => t.id.equals(entryId))).write(
        EntriesCompanion(collectionId: Value(collectionId)),
      );

  /// Ordering fields, each independently settable.
  ///
  /// Companion-valued rather than plain nullables so that "leave it alone" and
  /// "set it to null" are different requests. A plain `double? number` cannot
  /// express the difference, and the version that could not would silently wipe
  /// a parsed number every time a caller only wanted to move a row.
  Future<void> setEntryOrdering(
    String entryId, {
    Value<double?> number = const Value.absent(),
    Value<String?> marker = const Value.absent(),
    Value<int> order = const Value.absent(),
  }) => (update(entries)..where((t) => t.id.equals(entryId))).write(
    EntriesCompanion(
      entryNumber: number,
      sourceMarker: marker,
      entryOrder: order,
    ),
  );

  /// The user corrected this entry's content kind. Sets the user-set flag in the
  /// same write, so a later re-save cannot silently overwrite the answer.
  ///
  /// **Semantic only.** It deliberately cannot reach `artifact_format`:
  /// relabelling an entry as an article must never make the reader try to
  /// parse an image package as a document. What a thing *is called* and what
  /// its bytes *are* are different facts, and only a save can change the
  /// second one.
  Future<void> setEntryContentKind(String entryId, String kind) =>
      (update(entries)..where((t) => t.id.equals(entryId))).write(
        EntriesCompanion(
          contentKind: Value(kind),
          contentKindConfidence: const Value('high'),
          contentKindIsUserSet: const Value(true),
        ),
      );

  // --- reading state --------------------------------------------------------

  /// Reading-only write. Deliberately narrow: save code has no DAO method that
  /// can reach these columns, so a save cannot reset progress.
  Future<void> writeEntryReading(String id, EntriesCompanion values) =>
      (update(entries)..where((t) => t.id.equals(id))).write(values);

  /// Narrow writer for the entry's source address. Separate from every other
  /// update so that "where did this come from" can only ever be changed
  /// deliberately.
  Future<void> writeEntrySource(String id, String sourceUrl) =>
      (update(entries)..where((t) => t.id.equals(id))).write(
        EntriesCompanion(sourceUrl: Value(sourceUrl)),
      );

  Future<void> writeCollectionReading(String id, CollectionsCompanion values) =>
      (update(collections)..where((t) => t.id.equals(id))).write(values);

  /// Update-check outcome for a collection. Narrow like [writeEntryReading]:
  /// nothing else can reach the check columns by accident.
  Future<void> writeCollectionCheck(String id, CollectionsCompanion values) =>
      (update(collections)..where((t) => t.id.equals(id))).write(values);

  Stream<List<Entry>> watchEntriesForCollection(String collectionId) =>
      (select(entries)
            ..where((t) => t.collectionId.equals(collectionId))
            ..orderBy([(t) => OrderingTerm.asc(t.entryOrder)]))
          .watch();

  /// One-shot read. Boot routines and tests use this rather than taking the
  /// first emission of a stream: under a widget test's fake clock a stream's
  /// first event never arrives until frames are pumped, so awaiting one
  /// deadlocks.
  Future<List<Collection>> allCollections() => select(collections).get();

  Stream<List<Collection>> watchCollections() => (select(
    collections,
  )..orderBy([(t) => OrderingTerm.desc(t.createdAt)])).watch();

  Future<void> touchCollection(String id) =>
      (update(collections)..where((t) => t.id.equals(id))).write(
        CollectionsCompanion(lastOpenedAt: Value(DateTime.now())),
      );

  /// The collection's finished-entry cleanup decision: `remove` · `keep`, or
  /// null to go back to asking on the next eligible transition.
  ///
  /// Narrow, and scoped to one id: a decision taken while reading one collection
  /// can never land on another. It writes a rule for future transitions only —
  /// no file is touched here.
  Future<void> setCollectionCleanupPreference(String id, String? pref) =>
      (update(collections)..where((t) => t.id.equals(id))).write(
        CollectionsCompanion(cleanupPreference: Value(pref)),
      );

  /// Remember (or forget) the capture mode to propose for this collection.
  ///
  /// Narrow and scoped to one id, like the cleanup preference. Null clears it,
  /// which is why this cannot go through `upsertCollection` — that would read
  /// the null as "leave it alone" and make "stop remembering" a no-op.
  Future<void> setCollectionPreferredCaptureMode(String id, String? mode) =>
      (update(collections)..where((t) => t.id.equals(id))).write(
        CollectionsCompanion(preferredCaptureMode: Value(mode)),
      );

  /// Flip a collection between `active` and `archived`. Rows only — never
  /// entries, never files.
  Future<void> setCollectionLifecycle(String id, String lifecycle) =>
      (update(collections)..where((t) => t.id.equals(id))).write(
        CollectionsCompanion(
          lifecycle: Value(lifecycle),
          archivedAt: Value(lifecycle == 'archived' ? DateTime.now() : null),
        ),
      );

  // --- entries --------------------------------------------------------------

  /// Look up an entry by URL alone, across every collection and the standalone
  /// entries.
  ///
  /// The preflight runs before the collection is resolved, so it cannot scope
  /// the lookup — and an entry that exists elsewhere is still an existing entry
  /// as far as the user is concerned.
  Future<Entry?> findEntryByUrlKeyAnywhere(String urlKey) =>
      (select(entries)
            ..where((t) => t.urlKey.equals(urlKey))
            ..limit(1))
          .getSingleOrNull();

  /// Look up an entry by the canonical URL the page declared. The other half of
  /// loop detection: same document, different address.
  Future<Entry?> findEntryByCanonicalUrl(String canonicalUrl) =>
      (select(entries)
            ..where((t) => t.canonicalUrl.equals(canonicalUrl))
            ..limit(1))
          .getSingleOrNull();

  Future<Entry?> findEntryByUrlKey(String? collectionId, String urlKey) =>
      (select(entries)..where(
            (t) =>
                (collectionId == null
                    ? t.collectionId.isNull()
                    : t.collectionId.equals(collectionId)) &
                t.urlKey.equals(urlKey),
          ))
          .getSingleOrNull();

  /// Upsert an entry row.
  ///
  /// Note the drift semantic this rests on: `insertOnConflictUpdate` treats a
  /// null field on the data class as *absent*, so nullable columns keep their
  /// previous value. Anything that must be actively cleared needs its own narrow
  /// writer — see [clearOfflineRemovedMark].
  Future<void> upsertEntry(Entry entry) =>
      into(entries).insertOnConflictUpdate(entry);

  /// A save just put files back: the entry is no longer "removed by the user".
  /// Without this the marker would outlive the removal and a later system-side
  /// file loss would be reported as a deliberate removal.
  Future<void> clearOfflineRemovedMark(String id) =>
      (update(entries)..where((t) => t.id.equals(id))).write(
        const EntriesCompanion(offlineRemovedAt: Value(null)),
      );

  Future<List<Entry>> entriesForCollection(String collectionId) =>
      (select(entries)
            ..where((t) => t.collectionId.equals(collectionId))
            ..orderBy([(t) => OrderingTerm.asc(t.entryOrder)]))
          .get();

  Stream<List<Entry>> watchAllEntries() =>
      (select(entries)..orderBy([
            (t) => OrderingTerm.asc(t.collectionId),
            (t) => OrderingTerm.asc(t.entryOrder),
          ]))
          .watch();

  Future<Entry?> entryById(String id) =>
      (select(entries)..where((t) => t.id.equals(id))).getSingleOrNull();

  Future<void> markEntryContentMissing(String id) =>
      (update(entries)..where((t) => t.id.equals(id))).write(
        const EntriesCompanion(
          contentPath: Value(null),
          saveStatus: Value('failed'),
          saveError: Value('local files missing'),
        ),
      );

  Future<void> deleteEntry(String id) =>
      (delete(entries)..where((t) => t.id.equals(id))).go();

  /// Drop the discovered-only entries of one collection that the source's own
  /// entry list no longer carries.
  ///
  /// **The eligibility rule lives here, and only here.** The caller passes what
  /// it *observed* — the complete set of entry addresses one page showed and
  /// the numeric interval that page can vouch for — and never a list of rows to
  /// delete. It is therefore not possible for a caller, present or future, to
  /// name an entry into deletion: every row this touches has to satisfy the
  /// predicate below on its own, read inside the transaction that removes it.
  ///
  /// A row goes only when all of this holds:
  ///
  /// 1. It is a discovery and nothing more — [isDiscoveredOnlyEntry], which
  ///    reads every column that could carry something of the user's, not just
  ///    `save_status`.
  /// 2. It carries a number, so it can be placed against the observed
  ///    interval. An unnumbered discovery is never reconciled: there is no
  ///    position from which to say the page should have shown it.
  /// 3. That number falls inside the interval the page covered.
  /// 4. Its address was absent from the page's *complete* link set.
  /// 5. No queued or running save names it, and none is loose in this
  ///    collection.
  ///
  /// Returns the rows removed, for the log. Empty is the ordinary answer.
  Future<List<Entry>> reconcileDiscoveredEntries({
    required String collectionId,
    required Set<String> observedUrlKeys,
    required double windowFrom,
    required double windowTo,
    required bool windowOpenAbove,
  }) => transaction(() async {
    final rows = await entriesForCollection(collectionId);
    if (rows.isEmpty) return const <Entry>[];

    final claims = await _pendingSaveClaims();
    // A multi-entry save walks forward from its start address, so which entries
    // it will reach is not knowable from the row. While one is outstanding for
    // this collection, nothing here is reconciled at all.
    if (claims.collectionIds.contains(collectionId)) return const <Entry>[];

    // --- the ceiling ---------------------------------------------------------
    // An open ceiling says "the source has nothing newer than the top of this
    // list". The library can contradict that directly: an entry whose bytes are
    // on this device came from a page of this collection that sits above the
    // list we just read, which means the list was not the front of it. Fall
    // back to the closed interval rather than trusting the reading.
    var openAbove = windowOpenAbove;
    if (openAbove) {
      for (final row in rows) {
        final number = row.entryNumber;
        if (row.contentPath != null && number != null && number > windowTo) {
          openAbove = false;
          break;
        }
      }
    }

    final removed = <Entry>[];
    for (final row in rows) {
      if (!isDiscoveredOnlyEntry(row)) continue;
      final number = row.entryNumber;
      if (number == null) continue;
      if (number < windowFrom) continue;
      if (!openAbove && number > windowTo) continue;
      if (observedUrlKeys.contains(row.urlKey)) continue;
      if (claims.urlKeys.contains(row.urlKey)) continue;
      removed.add(row);
    }
    if (removed.isEmpty) return const <Entry>[];

    await (delete(
      entries,
    )..where((t) => t.id.isIn([for (final row in removed) row.id]))).go();
    return removed;
  });

  /// Forget one discovered entry, because the user asked.
  ///
  /// The manual half of [reconcileDiscoveredEntries] and the same rule: the
  /// only difference is where the evidence comes from. A check proves the
  /// source no longer lists the entry; here the person looking at it says so.
  /// Neither can reach a row that is anything more than a discovery, and
  /// neither cancels work — an entry a save is waiting on is refused, in
  /// words, rather than quietly taken out from under it.
  ///
  /// Deletes app-made metadata only: no file is touched, because a row this
  /// accepts has none.
  Future<ForgetDiscoveryResult> forgetDiscoveredEntry(String id) =>
      transaction(() async {
        final row = await entryById(id);
        if (row == null) return ForgetDiscoveryResult.missing;
        if (!isDiscoveredOnlyEntry(row)) {
          return ForgetDiscoveryResult.notADiscovery;
        }
        final claims = await _pendingSaveClaims();
        final collectionId = row.collectionId;
        if (claims.urlKeys.contains(row.urlKey) ||
            (collectionId != null &&
                claims.collectionIds.contains(collectionId))) {
          return ForgetDiscoveryResult.claimedByQueue;
        }
        await (delete(entries)..where((t) => t.id.equals(id))).go();
        return ForgetDiscoveryResult.forgotten;
      });

  /// Refresh the source-side metadata of a row that is **still only a
  /// discovery**, when a later check sees the same entry again.
  ///
  /// Field rules live here rather than at the caller, so a second caller
  /// cannot arrive with a looser idea of what "refresh" means. Each is a
  /// strict improvement or nothing:
  ///
  /// * **title** — replaced when the source now prints a different non-empty
  ///   one. A discovered row's title is the source's own label and nothing
  ///   else; there is no user-set entry title in this schema to protect.
  /// * **number** — only ever *filled in*. A stored number orders the
  ///   collection and is the checkpoint later checks measure against, so
  ///   overwriting one on the strength of a second reading trades a known
  ///   value for a guess. A disagreement is reported and kept, not resolved.
  /// * **marker** — recomputed by the caller, applied only when the title or
  ///   number it was derived from actually changed.
  /// * **basis / confidence** — only upgraded, never downgraded: an entry
  ///   first seen two hops down a chain and later found on the collection's
  ///   own list is better attested than it was.
  /// * **next address** — only filled in, so a chain that is already known is
  ///   never replaced by a second opinion.
  ///
  /// `discovered_at` is deliberately **not** touched. It is what a run's report
  /// counts to answer "what did this check find", and refreshing it on a
  /// re-sighting would make every entry the source still lists look newly
  /// discovered. Recording a separate last-seen time would need a column this
  /// schema does not have.
  ///
  /// Returns the names of the fields actually written — empty when nothing
  /// changed, and empty when the row is no longer a bare discovery.
  Future<Set<String>> refreshDiscoveredEntry({
    required String id,
    required String title,
    required double? number,
    required String? sourceMarker,
    required String basis,
    required String confidence,
    String? nextSourceUrl,
  }) => transaction(() async {
    final row = await entryById(id);
    if (row == null || !isDiscoveredOnlyEntry(row)) return const <String>{};

    final written = <String>{};
    final trimmedTitle = title.trim();
    final titleChanged = trimmedTitle.isNotEmpty && trimmedTitle != row.title;
    final numberFilled = row.entryNumber == null && number != null;
    final upgradeProvenance =
        confidence == 'high' && row.discoveryConfidence != 'high';
    final fillNext =
        row.nextSourceUrl == null &&
        nextSourceUrl != null &&
        nextSourceUrl.trim().isNotEmpty;

    if (titleChanged) written.add('title');
    if (numberFilled) written.add('number');
    if (upgradeProvenance) written.add('provenance');
    if (fillNext) written.add('nextAddress');
    if (written.isEmpty) return const <String>{};

    await (update(entries)..where((t) => t.id.equals(id))).write(
      EntriesCompanion(
        title: titleChanged ? Value(trimmedTitle) : const Value.absent(),
        entryNumber: numberFilled ? Value(number) : const Value.absent(),
        sourceMarker: (titleChanged || numberFilled) && sourceMarker != null
            ? Value(sourceMarker)
            : const Value.absent(),
        discoveryBasis: upgradeProvenance ? Value(basis) : const Value.absent(),
        discoveryConfidence: upgradeProvenance
            ? Value(confidence)
            : const Value.absent(),
        nextSourceUrl: fillNext ? Value(nextSourceUrl) : const Value.absent(),
      ),
    );
    return written;
  });

  /// Note that a capture of a discovered entry was attempted and failed.
  ///
  /// **Not a conclusion about the source.** A save fails for a dead address, a
  /// dropped connection, a sign-in wall and a bug in this app alike, and this
  /// column does not claim to tell them apart — it records that the attempt
  /// happened, which is what stops "save the new entries" queueing the same
  /// failing address every time the button is pressed. The entry stays
  /// discovered, stays listed, stays individually retryable and stays subject
  /// to the ordinary reconciliation rule.
  ///
  /// Writes one column, and only onto a row that is still a bare discovery: a
  /// save that got far enough to commit has already written the row properly,
  /// and must not have a failure note pasted over it.
  Future<bool> recordDiscoveryCaptureFailure({
    required String urlKey,
    required String error,
    String? collectionId,
  }) => transaction(() async {
    final row = collectionId == null
        ? await findEntryByUrlKeyAnywhere(urlKey)
        : await findEntryByUrlKey(collectionId, urlKey);
    if (row == null || !isDiscoveredOnlyEntry(row)) return false;
    await (update(entries)..where((t) => t.id.equals(row.id))).write(
      EntriesCompanion(saveError: Value(error.trim().isEmpty ? null : error)),
    );
    return true;
  });

  /// Clear the failure note, so the entry rejoins "save the new entries".
  ///
  /// The user asking for this one entry again *is* the retry: a failure that
  /// was a dropped connection should not exile an entry from the batch
  /// forever, and the person who taps it is better placed to know that than
  /// any rule this app could write.
  Future<void> clearDiscoveryCaptureFailure(String id) =>
      (update(entries)..where((t) => t.id.equals(id))).write(
        const EntriesCompanion(saveError: Value(null)),
      );

  /// Addresses and collections a **waiting or running save** is aimed at.
  ///
  /// The one place "the user has already asked for this" is answered, so
  /// reconciliation and manual forgetting cannot drift apart. Queue state is
  /// not entry state — nothing on the entry row says a save is coming — so it
  /// has to be read from the queue, and it is read inside the same transaction
  /// as the deletion it guards.
  Future<({Set<String> urlKeys, Set<String> collectionIds})>
  _pendingSaveClaims() async {
    final urlKeys = <String>{};
    final collectionIds = <String>{};
    for (final task in await pendingQueueTasks()) {
      if (task.taskType != 'entrySave' && task.taskType != 'sequenceSave') {
        continue;
      }
      // A multi-entry save's reach is not knowable from its row: it walks
      // forward from its start address for as far as it was allowed.
      final collectionId = task.collectionId;
      if (task.taskType == 'sequenceSave' && collectionId != null) {
        collectionIds.add(collectionId);
      }
      final url = task.startUrl;
      if (url != null && url.trim().isNotEmpty) urlKeys.add(normalizeUrl(url));
    }
    return (urlKeys: urlKeys, collectionIds: collectionIds);
  }

  /// Startup recovery: an entry left mid-flight is reset, never promoted.
  Future<int> resetInFlightEntries() =>
      (update(entries)..where((t) => t.saveStatus.equals('saving'))).write(
        const EntriesCompanion(
          saveStatus: Value('failed'),
          saveError: Value('interrupted by app restart'),
        ),
      );

  // --- save runs ------------------------------------------------------------

  /// Clear a run's pause reason. Needed for the same reason as
  /// [clearOfflineRemovedMark]: `upsertRun` leaves nullable columns alone when
  /// the data class carries null, so a resumed run would keep looking
  /// "paused — Browser required" forever.
  Future<void> clearRunPauseReason(String id) =>
      (update(saveRuns)..where((t) => t.id.equals(id))).write(
        const SaveRunsCompanion(pauseReason: Value(null)),
      );

  Future<void> upsertRun(SaveRun run) =>
      into(saveRuns).insertOnConflictUpdate(run);

  Future<SaveRun?> findResumableRun() =>
      (select(saveRuns)
            ..where((t) => t.state.isNotIn(['complete', 'cancelled', 'failed']))
            ..orderBy([(t) => OrderingTerm.desc(t.updatedAt)])
            ..limit(1))
          .getSingleOrNull();

  Stream<SaveRun?> watchResumableRun() =>
      (select(saveRuns)
            ..where((t) => t.state.isNotIn(['complete', 'cancelled', 'failed']))
            ..orderBy([(t) => OrderingTerm.desc(t.updatedAt)])
            ..limit(1))
          .watchSingleOrNull();

  Future<void> deleteRun(String id) =>
      (delete(saveRuns)..where((t) => t.id.equals(id))).go();

  /// Every run row, resumable or not. Read by permanent collection deletion,
  /// which has to recognise an interrupted run that was walking the collection
  /// being deleted — the resume offer is otherwise delayed work that rebuilds
  /// it.
  Future<List<SaveRun>> allRuns() => select(saveRuns).get();

  // --- settings -------------------------------------------------------------

  Future<void> setSetting(String key, String value) =>
      into(settings).insertOnConflictUpdate(Setting(key: key, value: value));

  /// One-shot read. Boot paths and tests want the value now, not the first
  /// emission of a stream.
  Future<String?> setting(String key) async => (await (select(
    settings,
  )..where((t) => t.key.equals(key))).getSingleOrNull())?.value;

  Stream<String?> watchSetting(String key) =>
      (select(settings)..where((t) => t.key.equals(key)))
          .watchSingleOrNull()
          .map((row) => row?.value);

  Future<int> deleteSetting(String key) =>
      (delete(settings)..where((t) => t.key.equals(key))).go();

  // --- activity queue -------------------------------------------------------

  Future<void> upsertQueueTask(QueueTask task) =>
      into(queueTasks).insertOnConflictUpdate(task);

  Future<QueueTask?> queueTaskById(String id) =>
      (select(queueTasks)..where((t) => t.id.equals(id))).getSingleOrNull();

  /// Write [values] onto a queue row **only while it is still in one of
  /// [expected]**, and say whether that happened.
  ///
  /// The queue's two state transitions race each other: the pump reads the
  /// pending rows, awaits `ensureBrowserVisible`, then claims one — and a
  /// cancellation landing inside that await would be silently overwritten by a
  /// blind `upsertQueueTask`. Making claim and cancel both conditional means
  /// exactly one of them wins, in SQLite, and the loser is told.
  ///
  /// A companion rather than a data class on purpose: `insertOnConflictUpdate`
  /// reads a null field as *absent*, so it cannot clear `startedAt`.
  Future<bool> updateQueueTaskIfState({
    required String id,
    required List<String> expected,
    required QueueTasksCompanion values,
  }) async {
    final changed = await (update(
      queueTasks,
    )..where((t) => t.id.equals(id) & t.state.isIn(expected))).write(values);
    return changed > 0;
  }

  /// Delete one **terminal** queue row. Queued and running rows are unreachable
  /// from here by construction: dropping a live row would orphan work that is
  /// still moving.
  Future<bool> deleteTerminalQueueTask(String id) async {
    final deleted =
        await (delete(queueTasks)..where(
              (t) =>
                  t.id.equals(id) &
                  t.state.isIn(['completed', 'failed', 'cancelled']),
            ))
            .go();
    return deleted > 0;
  }

  /// Drop every activity row that names one collection, in any state.
  ///
  /// Reachable only from permanent collection deletion, and unlike
  /// [deleteTerminalQueueTask] it does not spare live rows — the caller has
  /// already cancelled them, and a row still naming a collection that no
  /// longer exists is either work aimed at nothing or history about nothing.
  Future<int> deleteQueueTasksForCollection(String collectionId) => (delete(
    queueTasks,
  )..where((t) => t.collectionId.equals(collectionId))).go();

  Future<List<QueueTask>> pendingQueueTasks() =>
      (select(queueTasks)
            ..where((t) => t.state.isIn(['queued', 'running']))
            ..orderBy([(t) => OrderingTerm.asc(t.orderIndex)]))
          .get();

  Stream<List<QueueTask>> watchQueueTasks() => (select(
    queueTasks,
  )..orderBy([(t) => OrderingTerm.asc(t.orderIndex)])).watch();

  Future<int> nextQueueOrderIndex() async {
    final max = await (selectOnly(
      queueTasks,
    )..addColumns([queueTasks.orderIndex.max()])).getSingle();
    return (max.read(queueTasks.orderIndex.max()) ?? 0) + 1;
  }

  /// Keep only the newest [keep] terminal entries. History is bounded; the queue
  /// rows are never the content — deleting them deletes nothing else.
  Future<int> pruneQueueHistory({int keep = 50}) async {
    final terminal =
        await (select(queueTasks)
              ..where((t) => t.state.isIn(['completed', 'failed', 'cancelled']))
              ..orderBy([(t) => OrderingTerm.desc(t.finishedAt)]))
            .get();
    if (terminal.length <= keep) return 0;
    final doomed = terminal.skip(keep).map((t) => t.id).toList();
    return (delete(queueTasks)..where((t) => t.id.isIn(doomed))).go();
  }

  /// Clear terminal history only — queued/running rows and, above all, saved
  /// content are untouched.
  Future<int> clearQueueHistory() => (delete(
    queueTasks,
  )..where((t) => t.state.isIn(['completed', 'failed', 'cancelled']))).go();

  // --- browsing history -----------------------------------------------------
  //
  // Every read here filters on `source` explicitly rather than relying on the
  // writer to have kept automation out. Two independent guards, because a save
  // run flooding the user's history is the failure mode that matters.

  Future<void> insertVisit(BrowsingHistoryData visit) =>
      into(browsingHistory).insertOnConflictUpdate(visit);

  /// The most recent visit to [urlKey], if it happened within [window].
  ///
  /// Repeated visits are stored as individual rows — that is what keeps "clear
  /// the last hour" honest — but reloading the same page four times in a minute
  /// is one visit as far as the user is concerned, so a recent row is refreshed
  /// in place instead of stacking.
  Future<BrowsingHistoryData?> recentVisitTo(
    String urlKey, {
    required String source,
    required Duration window,
    DateTime? now,
  }) {
    final since = (now ?? DateTime.now()).subtract(window);
    return (select(browsingHistory)
          ..where(
            (t) =>
                t.urlKey.equals(urlKey) &
                t.source.equals(source) &
                t.visitedAt.isBiggerThanValue(since),
          )
          ..orderBy([(t) => OrderingTerm.desc(t.visitedAt)])
          ..limit(1))
        .getSingleOrNull();
  }

  /// Newest-first manual visits, bounded. Browser Home's "recently visited"
  /// strip and the History screen both come through here, so neither can
  /// accidentally read the whole table.
  Stream<List<BrowsingHistoryData>> watchVisits({
    String source = 'manual',
    int limit = 200,
  }) =>
      (select(browsingHistory)
            ..where((t) => t.source.equals(source))
            ..orderBy([(t) => OrderingTerm.desc(t.visitedAt)])
            ..limit(limit))
          .watch();

  Future<List<BrowsingHistoryData>> visits({
    String source = 'manual',
    int limit = 200,
  }) =>
      (select(browsingHistory)
            ..where((t) => t.source.equals(source))
            ..orderBy([(t) => OrderingTerm.desc(t.visitedAt)])
            ..limit(limit))
          .get();

  /// Case-insensitive match on title, URL or host. `LIKE` is ASCII-case-
  /// insensitive in SQLite, so both sides are lowered explicitly — non-ASCII
  /// titles are the normal case here, not the exception.
  Future<List<BrowsingHistoryData>> searchVisits(
    String query, {
    String source = 'manual',
    int limit = 200,
  }) {
    final needle = '%${query.trim().toLowerCase()}%';
    return (select(browsingHistory)
          ..where(
            (t) =>
                t.source.equals(source) &
                (t.title.lower().like(needle) |
                    t.url.lower().like(needle) |
                    t.host.lower().like(needle)),
          )
          ..orderBy([(t) => OrderingTerm.desc(t.visitedAt)])
          ..limit(limit))
        .get();
  }

  /// How many manual visits fall in `[since, now]`. Drives the counts the
  /// clear-history sheet shows *before* anything is deleted.
  Future<int> countVisitsSince(
    DateTime? since, {
    String source = 'manual',
  }) async {
    final count = browsingHistory.id.count();
    final query = selectOnly(browsingHistory)..addColumns([count]);
    query.where(
      since == null
          ? browsingHistory.source.equals(source)
          : browsingHistory.source.equals(source) &
                browsingHistory.visitedAt.isBiggerOrEqualValue(since),
    );
    final row = await query.getSingle();
    return row.read(count) ?? 0;
  }

  Future<int> deleteVisit(String id) =>
      (delete(browsingHistory)..where((t) => t.id.equals(id))).go();

  Future<int> deleteVisitsForHost(String host, {String source = 'manual'}) =>
      (delete(
        browsingHistory,
      )..where((t) => t.host.equals(host) & t.source.equals(source))).go();

  /// Clear a time range. `since == null` means all time. Scoped to [source] so
  /// clearing the user's browsing never touches an automation audit row.
  Future<int> deleteVisitsSince(DateTime? since, {String source = 'manual'}) =>
      (delete(browsingHistory)..where(
            (t) => since == null
                ? t.source.equals(source)
                : t.source.equals(source) &
                      t.visitedAt.isBiggerOrEqualValue(since),
          ))
          .go();

  /// Retention: drop anything older than [before], then anything beyond [keep]
  /// rows. Both bounds, because either alone leaves a way to grow without limit
  /// (a quiet year, or a very busy afternoon).
  Future<int> pruneHistory({
    required DateTime before,
    required int keep,
    String source = 'manual',
  }) async {
    var removed =
        await (delete(browsingHistory)..where(
              (t) =>
                  t.source.equals(source) &
                  t.visitedAt.isSmallerThanValue(before),
            ))
            .go();
    final surviving =
        await (select(browsingHistory)
              ..where((t) => t.source.equals(source))
              ..orderBy([(t) => OrderingTerm.desc(t.visitedAt)]))
            .get();
    if (surviving.length > keep) {
      final doomed = surviving.skip(keep).map((v) => v.id).toList();
      removed += await (delete(
        browsingHistory,
      )..where((t) => t.id.isIn(doomed))).go();
    }
    return removed;
  }

  // --- saved sites ----------------------------------------------------------

  Stream<List<SavedSite>> watchSavedSites() =>
      (select(savedSites)..orderBy([
            (t) => OrderingTerm.asc(t.orderIndex),
            (t) => OrderingTerm.asc(t.createdAt),
          ]))
          .watch();

  Future<List<SavedSite>> allSavedSites() =>
      (select(savedSites)..orderBy([
            (t) => OrderingTerm.asc(t.orderIndex),
            (t) => OrderingTerm.asc(t.createdAt),
          ]))
          .get();

  Future<SavedSite?> savedSiteByUrlKey(String urlKey) => (select(
    savedSites,
  )..where((t) => t.urlKey.equals(urlKey))).getSingleOrNull();

  Future<SavedSite?> savedSiteById(String id) =>
      (select(savedSites)..where((t) => t.id.equals(id))).getSingleOrNull();

  Future<void> upsertSavedSite(SavedSite site) =>
      into(savedSites).insertOnConflictUpdate(site);

  /// Narrow writer for the fields the rename/edit sheet owns.
  ///
  /// Needed for the same reason as [clearOfflineRemovedMark]: an upsert would
  /// read a null `userTitle` as "leave it alone", so clearing a rename would
  /// silently do nothing.
  Future<void> writeSavedSite(String id, SavedSitesCompanion values) =>
      (update(savedSites)..where((t) => t.id.equals(id))).write(values);

  Future<int> deleteSavedSite(String id) =>
      (delete(savedSites)..where((t) => t.id.equals(id))).go();

  Future<int> nextSavedSiteOrderIndex() async {
    final max = await (selectOnly(
      savedSites,
    )..addColumns([savedSites.orderIndex.max()])).getSingle();
    return (max.read(savedSites.orderIndex.max()) ?? 0) + 1;
  }

  // --- favicons -------------------------------------------------------------

  Future<FaviconCacheData?> favicon(String host) => (select(
    faviconCache,
  )..where((t) => t.host.equals(host))).getSingleOrNull();

  Future<List<FaviconCacheData>> allFavicons() => select(faviconCache).get();

  Future<void> putFavicon(FaviconCacheData icon) =>
      into(faviconCache).insertOnConflictUpdate(icon);

  Future<int> clearFavicons() => delete(faviconCache).go();
}

/// How [AppDatabase.forgetDiscoveredEntry] ended.
///
/// Named outcomes rather than a bool, because two of the three refusals have
/// to be said out loud: "this is no longer only a discovery" and "a save you
/// asked for is waiting on it" are different facts, and an action that just
/// did nothing would leave the user tapping it again.
enum ForgetDiscoveryResult {
  forgotten,

  /// The row carries content, reading state or a correction of the user's. Not
  /// app-made metadata any more, so not this action's business.
  notADiscovery,

  /// A queued or running save names it. Refused rather than cancelling work
  /// nobody asked to cancel.
  claimedByQueue,

  /// Already gone.
  missing;

  /// One sentence for the user, or null when there is nothing to say.
  String? get refusal => switch (this) {
    ForgetDiscoveryResult.forgotten || ForgetDiscoveryResult.missing => null,
    ForgetDiscoveryResult.notADiscovery =>
      'This entry has been saved, so it is kept. Remove its offline files '
          'instead if you need the space.',
    ForgetDiscoveryResult.claimedByQueue =>
      'This entry is waiting to be saved. Remove it from Activity first.',
  };
}

/// Is this row **only** a record of what an update check saw at the source?
///
/// The question the app's automatic and manual removals of discovered entries
/// both rest on, so it is asked of every column that could hold something the
/// user would lose, rather than of `save_status` alone. A status can be written
/// by one code path while a second one has already attached bytes or a reading
/// position to the same row, and this predicate is what makes that ordering
/// irrelevant.
///
/// Public so the screens that *offer* those removals ask this rather than
/// re-deriving it from `save_status`. It answers only the row half of the
/// question — whether a save is waiting on the entry is the queue's to answer,
/// and [AppDatabase.forgetDiscoveredEntry] asks both.
///
/// Deliberately conservative in both directions: a row that fails any clause
/// is kept, including one whose columns disagree with each other. Repairing a
/// contradictory row is not this function's business, and treating an
/// unexpected combination as "safe to delete" is exactly the mistake worth
/// designing against.
bool isDiscoveredOnlyEntry(Entry entry) =>
    entry.saveStatus == 'knownRemote' &&
    entry.discoveredAt != null &&
    // Nothing stored, and nothing that says something ever was.
    entry.contentPath == null &&
    entry.savedAt == null &&
    entry.byteSize == 0 &&
    entry.storedAssetCount == 0 &&
    entry.captureMode == null &&
    // Not files the user removed on purpose — that row is a save they still
    // own the history of.
    entry.offlineRemovedAt == null &&
    // No reading state. A discovery cannot be opened, so any of this means the
    // row is not what it claims to be.
    entry.readStatus == 'unread' &&
    entry.progressFraction == 0 &&
    entry.progressPageIndex == 0 &&
    entry.progressOffsetInPage == 0 &&
    entry.firstOpenedAt == null &&
    entry.lastReadAt == null &&
    entry.completedAt == null &&
    entry.progressUpdatedAt == null &&
    // Not a correction the user made to what this is.
    !entry.contentKindIsUserSet;
// `save_error` is deliberately absent. A failed capture attempt is a note
// about one attempt, not something the user owns and not evidence about the
// source — a row carrying one is still exactly as removable as it was.
