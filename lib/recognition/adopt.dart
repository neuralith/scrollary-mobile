/// Establishing Collection context for a page the library does not hold yet.
///
/// **Why this file exists.** Recognition answers *what do we already know
/// about this address* and stops there, correctly: a new host can never be
/// matched to an existing Collection by title, and V2 refuses to guess
/// (V2-D16, PRODUCT.md §5.3). But between "we could not tell" and "save it as
/// a loose Entry in the root Folder" there is a person who knows the answer.
/// This file is the operation they drive: *this page belongs to that
/// Collection*, or *this page starts a new one*.
///
/// Three rules it carries:
///
/// * **The user decides identity; the app never infers it.** A detected title
///   pre-fills a field and filters a list. It never selects, and similarity is
///   never a match (V2-D44).
/// * **Nothing transitional is written.** A Collection, its Source, the Entry
///   and the Location are one transaction. There is no standalone Entry
///   created first and repaired afterwards — that is the state this file
///   exists to prevent.
/// * **A Source belongs to the Collection it was created under.** If the same
///   `(host, path_key)` already sits under another Collection, the answer is a
///   refusal the user can read, never a silent move (V2-D14: a site that moves
///   is a lifecycle change, not a reparenting).
library;

import 'package:drift/drift.dart';

import '../data/collection_repository.dart';
import '../data/data_ids.dart';
import '../data/data_violations.dart';
import '../data/download_request_repository.dart';
import '../data/entry_repository.dart';
import '../data/folder_repository.dart';
import '../data/measurement_repository.dart';
import '../data/outbox_writer.dart';
import '../data/reading_state_repository.dart';
import '../data/recognition_index.dart';
import '../data/schema.dart';
import '../domain/collection.dart';
import '../domain/invariants.dart';
import '../domain/location.dart' show LocationLifecycle;
import '../domain/sync_kinds.dart';
import '../library/collection_identity.dart' show parseEntryNumber;
import 'reconcile.dart';
import 'recognise.dart';

/// How a Location that arrived because a person saved the page they were on
/// says it was found — the counterpart of `kSourceListingBasis`, and one
/// spelling in one place for the same reason.
const String kUserSaveBasis = 'userSave';

/// What an adoption did.
class AdoptionOutcome {
  const AdoptionOutcome({
    this.collectionId,
    this.sourceId,
    this.entryId,
    this.locationId,
    this.violation,
    this.mergedIntoExistingEntry = false,
    this.sourceReused = false,
  });

  /// A refusal, carrying the sentence the user is shown.
  const AdoptionOutcome.refused(InvariantViolation this.violation)
    : collectionId = null,
      sourceId = null,
      entryId = null,
      locationId = null,
      mergedIntoExistingEntry = false,
      sourceReused = false;

  final String? collectionId;
  final String? sourceId;
  final String? entryId;
  final String? locationId;
  final InvariantViolation? violation;

  /// True when the address joined an Entry the Collection already held, rather
  /// than creating one — cross-source equivalence, decided by
  /// `EntryReconciler` and nowhere else.
  final bool mergedIntoExistingEntry;

  /// True when the Source already existed under this Collection and was used
  /// as it stands. Adding the same site twice is not an error.
  final bool sourceReused;

  bool get succeeded => violation == null && entryId != null;
}

/// What establishing Collection context for a **listing** did.
///
/// Its own type rather than an [AdoptionOutcome] with a null `entryId`,
/// because §3's rule is that the index page is never an Entry: an outcome
/// whose `succeeded` asked for one would make the honest answer here look
/// like a failure.
class SourceAdoption {
  const SourceAdoption({
    this.collectionId,
    this.sourceId,
    this.violation,
    this.sourceReused = false,
    this.createdCollection = false,
  });

  const SourceAdoption.refused(InvariantViolation this.violation)
    : collectionId = null,
      sourceId = null,
      sourceReused = false,
      createdCollection = false;

  final String? collectionId;
  final String? sourceId;
  final InvariantViolation? violation;
  final bool sourceReused;

  /// True when this call brought the Collection into existence.
  final bool createdCollection;

  bool get succeeded => violation == null && sourceId != null;
}

/// The user-assisted half of recognition.
class LibraryAdoption {
  /// [db] is the one addition to the collaborators this class was declared
  /// with, and it is unavoidable: [adoptStandalone] moves rows no repository
  /// exposes a writer for — an Entry's own Collection membership, a
  /// standalone Location's Source, the device's queue rows and the offline
  /// copies whose bytes must survive the move. It also makes the four writes
  /// of [createCollection] one transaction. Without it those two operations
  /// have no database to work against and say so rather than half-writing.
  LibraryAdoption({
    required this.folders,
    required this.collections,
    required this.entries,
    required this.index,
    this._db,
    Clock? now,
  }) : _now = now ?? utcNow;

  final FolderRepository folders;
  final CollectionRepository collections;
  final EntryRepository entries;
  final RecognitionIndex index;

  final LibraryDatabase? _db;
  final Clock _now;

  late final EntryReconciler _reconciler = EntryReconciler(
    entries: entries,
    index: index,
  );

  /// *This page is another Source of [collectionId].*
  ///
  /// Ensures the Source, then puts the address through the same reconciliation
  /// discovery uses: an equal ordinal under a numeric basis joins the Entry
  /// that already holds it; anything else is a new Entry, placed only when the
  /// evidence places it.
  ///
  /// Refuses with [sourceIdentityTaken] when this `(host, path_key)` already
  /// belongs to a different Collection, and with [sourceKeyUnavailable] when
  /// the address yields no stable Source key at all.
  Future<AdoptionOutcome> addToExistingCollection({
    required String collectionId,
    required RecognitionKeys keys,
    required String pageTitle,
    double? printedNumber,
    String language = '',
  }) async {
    final pathKey = keys.pathKey;
    if (pathKey == null) {
      return const AdoptionOutcome.refused(sourceKeyUnavailable);
    }
    final collection = await collections.byId(collectionId);
    if (collection == null) return const AdoptionOutcome.refused(unknownRow);

    // One URL is one place (I6). An address the library already holds is not
    // a second Location and not an error either: the rows it already has are
    // the answer, and nothing is written.
    final held = await index.lookupUrl(keys.urlKey);
    if (held != null) {
      return AdoptionOutcome(
        collectionId: held.entry.collectionId,
        sourceId: held.location.sourceId,
        entryId: held.entry.id,
        locationId: held.location.id,
        sourceReused: true,
      );
    }

    final ensured = await _ensureSource(
      collectionId: collectionId,
      host: keys.host,
      pathKey: pathKey,
      language: language,
    );
    final source = ensured.source;
    if (source == null) {
      return AdoptionOutcome.refused(ensured.violation ?? unknownRow);
    }

    final reconciled = await _reconciler.entryFor(
      collectionId: collectionId,
      basis: OrderingBasis.values.byName(collection.orderingBasis),
      printedNumber: printedNumber,
      title: pageTitle,
    );
    final entryId = reconciled.entryId;
    if (entryId == null) {
      return AdoptionOutcome.refused(reconciled.violation ?? unknownRow);
    }

    final (location, locationViolation) = await entries.addLocation(
      entryId: entryId,
      url: keys.url,
      urlKey: keys.urlKey,
      sourceId: source.id,
      sourceNumber: printedNumber,
      discoveryBasis: kUserSaveBasis,
    );
    if (location == null) {
      return AdoptionOutcome.refused(locationViolation ?? unknownRow);
    }

    return AdoptionOutcome(
      collectionId: collectionId,
      sourceId: source.id,
      entryId: entryId,
      locationId: location.id,
      mergedIntoExistingEntry: reconciled.mergedIntoExistingEntry,
      sourceReused: ensured.reused,
    );
  }

  /// *Start a new Collection for this page.*
  ///
  /// Collection, Source, Entry and Location in one transaction. [name] is the
  /// user's, never the detected title silently. The ordering basis is
  /// `explicitNumericIndex` only when this page actually printed a number —
  /// claiming a numeric basis for a work that numbers nothing would license
  /// cross-source merging the evidence does not support (V2-D16).
  Future<AdoptionOutcome> createCollection({
    required String name,
    required RecognitionKeys keys,
    required String pageTitle,
    double? printedNumber,
    String? folderId,
    String language = '',
  }) async {
    final pathKey = keys.pathKey;
    if (pathKey == null) {
      return const AdoptionOutcome.refused(sourceKeyUnavailable);
    }
    // A site already published under a Collection never moves to another one
    // (V2-D14). Asked before anything is created, so the refusal costs no row.
    if (await index.lookupSource(keys.host, pathKey) != null) {
      return const AdoptionOutcome.refused(sourceIdentityTaken);
    }
    final folder = folderId ?? (await folders.ensureRoot()).id;

    try {
      return await _atomically(() async {
        final (collection, collectionViolation) = await collections.create(
          name: name,
          folderId: folder,
          orderingBasis: _basisFor(printedNumber),
          detectedTitle: keys.detectedCollectionTitle ?? '',
        );
        if (collection == null) throw _Abort(collectionViolation ?? unknownRow);

        final (source, sourceViolation) = await collections.addSource(
          collectionId: collection.id,
          host: keys.host,
          pathKey: pathKey,
          language: language,
        );
        if (source == null) throw _Abort(sourceViolation ?? unknownRow);

        final reconciled = await _reconciler.entryFor(
          collectionId: collection.id,
          basis: _basisFor(printedNumber),
          printedNumber: printedNumber,
          title: pageTitle,
        );
        final entryId = reconciled.entryId;
        if (entryId == null) throw _Abort(reconciled.violation ?? unknownRow);

        final (location, locationViolation) = await entries.addLocation(
          entryId: entryId,
          url: keys.url,
          urlKey: keys.urlKey,
          sourceId: source.id,
          sourceNumber: printedNumber,
          discoveryBasis: kUserSaveBasis,
        );
        if (location == null) throw _Abort(locationViolation ?? unknownRow);

        return AdoptionOutcome(
          collectionId: collection.id,
          sourceId: source.id,
          entryId: entryId,
          locationId: location.id,
          mergedIntoExistingEntry: reconciled.mergedIntoExistingEntry,
        );
      });
    } on _Abort catch (abort) {
      return AdoptionOutcome.refused(abort.violation);
    }
  }

  /// *This listing is where a Source lives.*
  ///
  /// The index page's half of the matrix (§3): Collection context and the
  /// Source under it, and **no Entry**. A listing is not a unit of reading, so
  /// no `Entry 0` is invented for it — what it lists is found by a check,
  /// which is a separate, visible act.
  ///
  /// Exactly one of [collectionId] and [newCollectionName] names where the
  /// Source goes.
  Future<SourceAdoption> addListingSource({
    String? collectionId,
    String? newCollectionName,
    required RecognitionKeys keys,
    String? folderId,
    String language = '',
  }) async {
    final pathKey = keys.pathKey;
    if (pathKey == null) {
      return const SourceAdoption.refused(sourceKeyUnavailable);
    }
    if ((collectionId == null) == (newCollectionName == null)) {
      return const SourceAdoption.refused(adoptionTargetAmbiguous);
    }

    if (collectionId != null) {
      if (await collections.byId(collectionId) == null) {
        return const SourceAdoption.refused(unknownRow);
      }
      final ensured = await _ensureSource(
        collectionId: collectionId,
        host: keys.host,
        pathKey: pathKey,
        language: language,
      );
      if (ensured.source == null) {
        return SourceAdoption.refused(ensured.violation ?? unknownRow);
      }
      return SourceAdoption(
        collectionId: collectionId,
        sourceId: ensured.source!.id,
        sourceReused: ensured.reused,
      );
    }

    if (await index.lookupSource(keys.host, pathKey) != null) {
      return const SourceAdoption.refused(sourceIdentityTaken);
    }
    final folder = folderId ?? (await folders.ensureRoot()).id;
    try {
      return await _atomically(() async {
        final (collection, collectionViolation) = await collections.create(
          name: newCollectionName!,
          folderId: folder,
          // A listing printed no number of its own, and inventing a numeric
          // basis from a page that numbers nothing would license merging the
          // evidence does not support (V2-D16). What the list holds is the
          // check's answer, not this call's.
          orderingBasis: _basisFor(null),
          detectedTitle: keys.detectedCollectionTitle ?? '',
        );
        if (collection == null) throw _Abort(collectionViolation ?? unknownRow);
        final (source, sourceViolation) = await collections.addSource(
          collectionId: collection.id,
          host: keys.host,
          pathKey: pathKey,
          language: language,
        );
        if (source == null) throw _Abort(sourceViolation ?? unknownRow);
        return SourceAdoption(
          collectionId: collection.id,
          sourceId: source.id,
          createdCollection: true,
        );
      });
    } on _Abort catch (abort) {
      return SourceAdoption.refused(abort.violation);
    }
  }

  /// *This loose Entry belongs in that Collection after all.*
  ///
  /// Derives Source identity from the Entry's own address. When the Collection
  /// already holds an equivalent Entry, the two become one: the Location moves
  /// across, reading state merges by the rules already in `sync/identity.dart`
  /// (never discarding the more-progressed side), measurements and queue rows
  /// follow, and an existing OfflineCopy keeps its bytes and its provenance —
  /// domain reorganisation never destroys device-local content.
  Future<AdoptionOutcome> adoptStandalone({
    required String entryId,
    required String collectionId,
  }) async {
    final db = _requireDatabase('adoptStandalone');

    final entry = await entries.byId(entryId);
    if (entry == null) return const AdoptionOutcome.refused(unknownRow);
    if (entry.collectionId != null) {
      return const AdoptionOutcome.refused(entryNotStandalone);
    }
    final collection = await collections.byId(collectionId);
    if (collection == null) return const AdoptionOutcome.refused(unknownRow);

    final locations = await entries.locationsOf(entryId);
    // Earliest active first — the address this Entry is read at. A retracted
    // one is still an address, and is used only when there is nothing else.
    final primary =
        locations
            .where((l) => l.lifecycle == LocationLifecycle.active.name)
            .firstOrNull ??
        locations.firstOrNull;
    if (primary == null) {
      return const AdoptionOutcome.refused(sourceKeyUnavailable);
    }
    final keys = RecognitionKeys.of(primary.url);
    final pathKey = keys.pathKey;
    if (pathKey == null) {
      return const AdoptionOutcome.refused(sourceKeyUnavailable);
    }

    final ensured = await _ensureSource(
      collectionId: collectionId,
      host: keys.host,
      pathKey: pathKey,
      language: '',
    );
    final source = ensured.source;
    if (source == null) {
      return AdoptionOutcome.refused(ensured.violation ?? unknownRow);
    }

    // The Entry's own reading of itself: its title first, its address second,
    // which is exactly what `parseEntryNumber` already orders.
    final printed = parseEntryNumber(title: entry.title, url: primary.url);
    final plan = await _reconciler.planFor(
      collectionId: collectionId,
      basis: OrderingBasis.values.byName(collection.orderingBasis),
      printedNumber: printed,
    );

    final target = plan.existing;
    try {
      if (target != null) {
        return await _atomically(
          () => _mergeInto(
            db: db,
            entry: entry,
            target: target,
            source: source,
            locations: locations,
            collectionId: collectionId,
            sourceReused: ensured.reused,
          ),
        );
      }
      return await _atomically(
        () => _moveIn(
          db: db,
          entry: entry,
          plan: plan,
          source: source,
          locations: locations,
          collectionId: collectionId,
          sourceReused: ensured.reused,
        ),
      );
    } on _Abort catch (abort) {
      return AdoptionOutcome.refused(abort.violation);
    }
  }

  // ---- the two halves of an adoption -------------------------------------

  /// The Entry stays and joins the Collection: membership, position, and its
  /// Locations' Source.
  Future<AdoptionOutcome> _moveIn({
    required LibraryDatabase db,
    required EntryRow entry,
    required ReconcilePlan plan,
    required SourceRow source,
    required List<LocationRow> locations,
    required String collectionId,
    required bool sourceReused,
  }) async {
    final at = _now();
    final outbox = OutboxWriter(db);
    try {
      await (db.update(db.entries)..where((e) => e.id.equals(entry.id))).write(
        EntriesCompanion(
          collectionId: Value(collectionId),
          folderId: const Value(null),
          ordinal: Value(plan.ordinal),
          placement: Value(plan.placement.name),
          updatedAt: Value(at),
        ),
      );
    } on Exception catch (e) {
      if (e.toString().contains('entries.collection_id, entries.ordinal')) {
        throw const _Abort(duplicateOrdinal);
      }
      rethrow;
    }
    await outbox.record(
      kind: SyncedEntityKind.entry,
      entityId: entry.id,
      op: OutboxOp.upsert,
      at: at,
      fields: {
        'collection_id': collectionId,
        'folder_id': null,
        'ordinal': plan.ordinal,
        'placement': plan.placement.name,
      },
    );

    for (final location in locations) {
      await _repointLocation(
        db: db,
        outbox: outbox,
        at: at,
        location: location,
        entryId: entry.id,
        sourceId: source.id,
      );
    }

    return AdoptionOutcome(
      collectionId: collectionId,
      sourceId: source.id,
      entryId: entry.id,
      locationId: locations.firstOrNull?.id,
      sourceReused: sourceReused,
    );
  }

  /// The Collection already holds this Entry: everything the loose one carried
  /// moves onto the one that stays, and only then does its row go.
  ///
  /// Order matters twice. The Locations move **before** the Entry is removed,
  /// because removal cascades to them; and the bytes are never touched at all
  /// — an OfflineCopy row is re-pointed, never deleted (I14).
  Future<AdoptionOutcome> _mergeInto({
    required LibraryDatabase db,
    required EntryRow entry,
    required EntryRow target,
    required SourceRow source,
    required List<LocationRow> locations,
    required String collectionId,
    required bool sourceReused,
  }) async {
    final at = _now();
    final outbox = OutboxWriter(db);

    for (final location in locations) {
      await _repointLocation(
        db: db,
        outbox: outbox,
        at: at,
        location: location,
        entryId: target.id,
        sourceId: source.id,
      );
    }

    await _mergeReadingState(db, outbox, at, entry.id, target.id);
    await _mergeMeasurements(db, outbox, at, entry.id, target.id);
    await _mergeDownloadRequests(db, entry.id, target.id);
    await _mergeSaveQueue(db, at, entry.id, target.id);
    await _mergeOfflineCopies(db, entry.id, target.id);

    final violation = await entries.removeEntry(entry.id);
    if (violation != null) throw _Abort(violation);

    return AdoptionOutcome(
      collectionId: collectionId,
      sourceId: source.id,
      entryId: target.id,
      locationId: locations.firstOrNull?.id,
      mergedIntoExistingEntry: true,
      sourceReused: sourceReused,
    );
  }

  Future<void> _repointLocation({
    required LibraryDatabase db,
    required OutboxWriter outbox,
    required DateTime at,
    required LocationRow location,
    required String entryId,
    required String sourceId,
  }) async {
    await (db.update(
      db.locations,
    )..where((l) => l.id.equals(location.id))).write(
      LocationsCompanion(
        entryId: Value(entryId),
        sourceId: Value(sourceId),
        updatedAt: Value(at),
      ),
    );
    await outbox.record(
      kind: SyncedEntityKind.location,
      entityId: location.id,
      op: OutboxOp.upsert,
      at: at,
      fields: {'entry_id': entryId, 'source_id': sourceId},
    );
  }

  /// The merge policy is `ReadingStateRepository.rewriteEntryRef`'s and is not
  /// re-decided here: the newer clock wins, so the more-progressed side is
  /// never discarded. What is added is the intent — an adoption is the user's
  /// act, so the survivor's state has to reach their other devices, where the
  /// sync lane's own merge has nothing to tell them.
  Future<void> _mergeReadingState(
    LibraryDatabase db,
    OutboxWriter outbox,
    DateTime at,
    String from,
    String to,
  ) async {
    final before = await _readingRow(db, to);
    await ReadingStateRepository(db).rewriteEntryRef(from, to);
    final after = await _readingRow(db, to);
    if (after == null) return;
    if (before != null && before.updatedAt == after.updatedAt) return;
    await outbox.record(
      kind: SyncedEntityKind.readingState,
      entityId: to,
      op: OutboxOp.upsert,
      at: at,
      fields: {
        'status': after.status,
        'first_opened_at': wireTime(after.firstOpenedAt),
        'last_read_at': wireTime(after.lastReadAt),
        'completed_at': wireTime(after.completedAt),
      },
    );
  }

  /// `MeasurementRepository.rewriteEntryRef`'s policy, unchanged: per
  /// `(entry, source)` cell the newer observation stands, so a cell the target
  /// already holds keeps its own reading unless the moving one is later. A
  /// measurement is scoped to the rendering it was taken against (I12), so
  /// nothing is ever re-scoped here.
  Future<void> _mergeMeasurements(
    LibraryDatabase db,
    OutboxWriter outbox,
    DateTime at,
    String from,
    String to,
  ) async {
    final moving = await (db.select(
      db.measurements,
    )..where((m) => m.entryId.equals(from))).get();
    if (moving.isEmpty) return;
    await MeasurementRepository(db).rewriteEntryRef(from, to);
    for (final row in moving) {
      final landed =
          await (db.select(db.measurements)..where(
                (m) => m.entryId.equals(to) & m.sourceId.equals(row.sourceId),
              ))
              .getSingleOrNull();
      if (landed == null || landed.observedAt != row.observedAt) continue;
      await outbox.record(
        kind: SyncedEntityKind.measurement,
        entityId: to,
        op: OutboxOp.upsert,
        at: at,
        fields: {
          'source_id': row.sourceId,
          'fraction': row.fraction,
          'observed_at': wireTime(row.observedAt),
        },
      );
    }
  }

  /// A request is an intent the server owns (I17). Re-pointed, except where
  /// the survivor already has an open one — two open requests for one Entry
  /// is exactly what the schema's index forbids, and the duplicate goes the
  /// way `sync/identity.dart` sends a duplicate: locally, with no tombstone,
  /// because the server never asked for this and never hears of it.
  Future<void> _mergeDownloadRequests(
    LibraryDatabase db,
    String from,
    String to,
  ) async {
    const open = ['pending', 'claimed'];
    final survivorHasOpen =
        await (db.select(db.downloadRequests)
              ..where((r) => r.entryId.equals(to) & r.state.isIn(open)))
            .getSingleOrNull() !=
        null;
    if (survivorHasOpen) {
      final requests = DownloadRequestRepository(db);
      final duplicates = await (db.select(
        db.downloadRequests,
      )..where((r) => r.entryId.equals(from) & r.state.isIn(open))).get();
      for (final row in duplicates) {
        await requests.applyRemoteDelete(row.id);
      }
    }
    await DownloadRequestRepository(db).rewriteEntryRefs(from, to);
  }

  /// Device state, never synced. A waiting row for an Entry the survivor is
  /// already waiting on is the same request — enqueueing is idempotent per
  /// Entry — so it is **cancelled**, which preserves the row, rather than
  /// deleted.
  Future<void> _mergeSaveQueue(
    LibraryDatabase db,
    DateTime at,
    String from,
    String to,
  ) async {
    const open = ['queued', 'running'];
    final survivorHasOpen =
        await (db.select(db.saveQueue)
              ..where((t) => t.entryId.equals(to) & t.state.isIn(open)))
            .getSingleOrNull() !=
        null;
    if (survivorHasOpen) {
      await (db.update(
        db.saveQueue,
      )..where((t) => t.entryId.equals(from) & t.state.isIn(open))).write(
        SaveQueueCompanion(
          state: const Value('cancelled'),
          finishedAt: Value(at),
        ),
      );
    }
    await (db.update(db.saveQueue)..where((t) => t.entryId.equals(from))).write(
      SaveQueueCompanion(entryId: Value(to)),
    );
  }

  /// **No file is touched and no row is deleted.** The copy moves onto the
  /// survivor with its provenance intact; if the survivor already holds an
  /// active copy, that one stays active and the arriving one is marked
  /// inactive — one active copy per Entry per device (I13), and the bytes of
  /// both remain exactly where they are.
  Future<void> _mergeOfflineCopies(
    LibraryDatabase db,
    String from,
    String to,
  ) async {
    final moving = await (db.select(
      db.offlineCopies,
    )..where((c) => c.entryId.equals(from))).get();
    if (moving.isEmpty) return;
    final survivorHasActive =
        await (db.select(db.offlineCopies)
              ..where((c) => c.entryId.equals(to) & c.active.equals(true)))
            .getSingleOrNull() !=
        null;
    for (final row in moving) {
      await (db.update(
        db.offlineCopies,
      )..where((c) => c.id.equals(row.id))).write(
        OfflineCopiesCompanion(
          entryId: Value(to),
          active: Value(row.active && !survivorHasActive),
        ),
      );
    }
  }

  // ---- shared ------------------------------------------------------------

  /// The Source of [collectionId] for this identity, made if it is new.
  ///
  /// A `(host, path_key)` already published under another Collection is a
  /// refusal and never a move (V2-D14).
  Future<_EnsuredSource> _ensureSource({
    required String collectionId,
    required String host,
    required String pathKey,
    required String language,
  }) async {
    final existing = await index.lookupSource(host, pathKey);
    if (existing != null) {
      if (existing.collectionId != collectionId) {
        return const _EnsuredSource(violation: sourceIdentityTaken);
      }
      return _EnsuredSource(source: existing, reused: true);
    }
    final (row, violation) = await collections.addSource(
      collectionId: collectionId,
      host: host,
      pathKey: pathKey,
      language: language,
    );
    return _EnsuredSource(source: row, violation: violation);
  }

  /// V2_ARCHITECTURE §4.3: only an explicit numeric index gives equivalence
  /// something to key on. A page that printed no number tells us the order it
  /// was discovered in and nothing more, so that is what the Collection says
  /// it is ordered by — a basis under which nothing merges automatically,
  /// which is the honest state for a structure the app has not seen yet.
  OrderingBasis _basisFor(double? printedNumber) => printedNumber != null
      ? OrderingBasis.explicitNumericIndex
      : OrderingBasis.discoveryOrder;

  /// One transaction where there is a database to open one on. Drift nests
  /// through savepoints, so the repositories' own `transaction` calls inside
  /// this one join it rather than committing early.
  Future<T> _atomically<T>(Future<T> Function() action) {
    final db = _db;
    return db == null ? action() : db.transaction(action);
  }

  LibraryDatabase _requireDatabase(String operation) {
    final db = _db;
    if (db == null) {
      throw StateError(
        '$operation moves rows no repository exposes a writer for; construct '
        'LibraryAdoption with its database',
      );
    }
    return db;
  }

  Future<ReadingStateRow?> _readingRow(LibraryDatabase db, String entryId) =>
      (db.select(
        db.readingStates,
      )..where((r) => r.entryId.equals(entryId))).getSingleOrNull();
}

class _EnsuredSource {
  const _EnsuredSource({this.source, this.reused = false, this.violation});

  final SourceRow? source;
  final bool reused;
  final InvariantViolation? violation;
}

/// Rolls back the transaction an adoption is written in, carrying the refusal
/// out with it. Never escapes this file.
class _Abort implements Exception {
  const _Abort(this.violation);

  final InvariantViolation violation;
}

/// No stable Source key could be derived from this address, so no Source can
/// be made from it — a real answer, and the reason the user is told.
const sourceKeyUnavailable = InvariantViolation(
  'I5',
  'this address does not identify a site section this app can follow',
);

/// The Entry is already in a Collection, so there is nothing to adopt.
const entryNotStandalone = InvariantViolation(
  'I3',
  'this entry already belongs to a collection',
);

/// A Collection to join and a Collection to create are two different answers,
/// and an adoption is given exactly one of them.
const adoptionTargetAmbiguous = InvariantViolation(
  'I4',
  'name one collection to join, or one to create',
);
