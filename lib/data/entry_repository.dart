/// Entry and Location repository (roadmap C5).
///
/// An Entry is not a URL. Standalone Entries are first-class (folder XOR
/// collection, I3); an unplaced Entry is a real, visible state that the user
/// resolves, never a guess (V2-D16). Retraction is source-scoped evidence
/// (I15) and deliberately DOES NOT sync — each device reconciles its own
/// reading (V2_SYNC.md §5) — while removing a Location by hand is a user
/// removal and does.
library;

import 'package:drift/drift.dart';

import '../domain/entry.dart';
import '../domain/invariants.dart';
import '../domain/location.dart' as domain;
import '../domain/sync_kinds.dart';
import 'data_ids.dart';
import 'data_violations.dart';
import 'outbox_writer.dart';
import 'schema.dart';

class EntryRepository {
  EntryRepository(this._db, {Clock? now, IdGenerator? newId})
    : _now = now ?? utcNow,
      _newId = newId ?? newLocalId,
      _outbox = OutboxWriter(_db, newId: newId);

  final LibraryDatabase _db;
  final Clock _now;
  final IdGenerator _newId;
  final OutboxWriter _outbox;

  // ---- Entry ---------------------------------------------------------------

  /// Creates an Entry inside a Collection. Pass an [ordinal] with
  /// [Placement.placed] (or [Placement.userPlaced]); pass neither for an
  /// honest unplaced Entry.
  Future<(EntryRow?, InvariantViolation?)> createInCollection({
    required String collectionId,
    double? ordinal,
    Placement placement = Placement.placed,
    String title = '',
    int sortKey = 0,
  }) {
    return _create(
      collectionId: collectionId,
      folderId: null,
      ordinal: ordinal,
      placement: placement,
      title: title,
      sortKey: sortKey,
    );
  }

  /// Creates a standalone Entry living directly in a Folder — never wrapped
  /// in a Collection of one.
  Future<(EntryRow?, InvariantViolation?)> createStandalone({
    required String folderId,
    String title = '',
    int sortKey = 0,
  }) {
    return _create(
      collectionId: null,
      folderId: folderId,
      ordinal: null,
      placement: Placement.placed,
      title: title,
      sortKey: sortKey,
    );
  }

  Future<(EntryRow?, InvariantViolation?)> _create({
    required String? collectionId,
    required String? folderId,
    required double? ordinal,
    required Placement placement,
    required String title,
    required int sortKey,
  }) async {
    return _db.transaction(() async {
      final id = _newId();
      final entry = Entry(
        id: id,
        collectionId: collectionId,
        folderId: folderId,
        ordinal: ordinal,
        placement: placement,
        title: title,
        sortKey: sortKey,
      );
      final violation = entry.validate();
      if (violation != null) return (null, violation);
      final at = _now();
      try {
        await _db
            .into(_db.entries)
            .insert(
              EntriesCompanion.insert(
                id: id,
                collectionId: Value(collectionId),
                folderId: Value(folderId),
                ordinal: Value(ordinal),
                placement: placement.name,
                title: Value(title),
                sortKey: Value(sortKey),
                updatedAt: at,
              ),
            );
      } on Exception catch (e) {
        if (_mentions(e, 'entries.collection_id, entries.ordinal')) {
          return (null, duplicateOrdinal);
        }
        rethrow;
      }
      await _outbox.record(
        kind: SyncedEntityKind.entry,
        entityId: id,
        op: OutboxOp.upsert,
        at: at,
        fields: {
          'collection_id': collectionId,
          'folder_id': folderId,
          'ordinal': ordinal,
          'placement': placement.name,
          'title': title,
          'sort_key': sortKey,
        },
      );
      return (await byId(id), null);
    });
  }

  /// The unplaced → userPlaced transition: the user chose a position.
  Future<(EntryRow?, InvariantViolation?)> placeEntry(
    String id,
    double ordinal,
  ) => _placeAt(id, ordinal, Placement.userPlaced);

  /// The unplaced → placed transition the *app* may make: a Source printed an
  /// explicit number for an Entry that had none (V2-D16).
  ///
  /// Deliberately not [Placement.userPlaced]. That spelling is the user's own
  /// answer, and a position derived from what a site printed is not it — the
  /// two stay distinguishable so a later reading, or the user, can tell which
  /// of them put the Entry where it is. Everything else is [placeEntry]'s: the
  /// same I8 refusal when the position is taken, and the same single intent.
  ///
  /// Whether a reading *may* place an Entry is `recognition/check.dart`'s
  /// judgement, not this writer's: this one writes what it is handed.
  Future<(EntryRow?, InvariantViolation?)> placeFromSource(
    String id,
    double ordinal,
  ) => _placeAt(id, ordinal, Placement.placed);

  Future<(EntryRow?, InvariantViolation?)> _placeAt(
    String id,
    double ordinal,
    Placement placement,
  ) async {
    return _db.transaction(() async {
      final row = await byId(id);
      if (row == null) return (null, unknownRow);
      final at = _now();
      try {
        await (_db.update(_db.entries)..where((e) => e.id.equals(id))).write(
          EntriesCompanion(
            ordinal: Value(ordinal),
            placement: Value(placement.name),
            updatedAt: Value(at),
          ),
        );
      } on Exception catch (e) {
        if (_mentions(e, 'entries.collection_id, entries.ordinal')) {
          return (null, duplicateOrdinal);
        }
        rethrow;
      }
      await _outbox.record(
        kind: SyncedEntityKind.entry,
        entityId: id,
        op: OutboxOp.upsert,
        at: at,
        fields: {'ordinal': ordinal, 'placement': placement.name},
      );
      return (await byId(id), null);
    });
  }

  /// A deliberate user removal (V2_SYNC.md §5). Library rows cascade; the
  /// OfflineCopy row has no foreign key and survives, which is I14 locally.
  Future<InvariantViolation?> removeEntry(String id) async {
    return _db.transaction(() async {
      if (await byId(id) == null) return unknownRow;
      final at = _now();
      await (_db.delete(_db.entries)..where((e) => e.id.equals(id))).go();
      await _outbox.record(
        kind: SyncedEntityKind.entry,
        entityId: id,
        op: OutboxOp.delete,
        at: at,
      );
      return null;
    });
  }

  Future<EntryRow?> byId(String id) => (_db.select(
    _db.entries,
  )..where((e) => e.id.equals(id))).getSingleOrNull();

  Future<List<EntryRow>> entriesOf(String collectionId) {
    return (_db.select(_db.entries)
          ..where((e) => e.collectionId.equals(collectionId))
          ..orderBy([
            (e) => OrderingTerm.asc(e.ordinal),
            (e) => OrderingTerm.asc(e.sortKey),
          ]))
        .get();
  }

  Future<List<EntryRow>> unplacedOf(String collectionId) {
    return (_db.select(_db.entries)..where(
          (e) =>
              e.collectionId.equals(collectionId) &
              e.placement.equals(Placement.unplaced.name),
        ))
        .get();
  }

  // ---- Location ------------------------------------------------------------

  Future<(LocationRow?, InvariantViolation?)> addLocation({
    required String entryId,
    required String url,
    required String urlKey,
    String? sourceId,
    String sourceLabel = '',
    double? sourceNumber,
    String discoveryBasis = '',
  }) async {
    return _db.transaction(() async {
      final entryRow = await byId(entryId);
      if (entryRow == null) return (null, unknownRow);
      final id = _newId();
      final at = _now();
      final location = domain.Location(
        id: id,
        entryId: entryId,
        sourceId: sourceId,
        url: url,
        urlKey: urlKey,
        sourceLabel: sourceLabel,
        sourceNumber: sourceNumber,
        discoveryBasis: discoveryBasis,
        discoveredAt: at,
      );
      final entry = Entry(
        id: entryRow.id,
        collectionId: entryRow.collectionId,
        folderId: entryRow.folderId,
        ordinal: entryRow.ordinal,
        placement: Placement.values.byName(entryRow.placement),
        title: entryRow.title,
        sortKey: entryRow.sortKey,
      );
      final violation = location.validateAgainstEntry(entry);
      if (violation != null) return (null, violation);
      try {
        await _db
            .into(_db.locations)
            .insert(
              LocationsCompanion.insert(
                id: id,
                entryId: entryId,
                sourceId: Value(sourceId),
                url: url,
                urlKey: urlKey,
                sourceLabel: Value(sourceLabel),
                sourceNumber: Value(sourceNumber),
                discoveredAt: at,
                discoveryBasis: Value(discoveryBasis),
                updatedAt: at,
              ),
            );
      } on Exception catch (e) {
        if (_mentions(e, 'url_key')) return (null, duplicateUrlKey);
        rethrow;
      }
      await _outbox.record(
        kind: SyncedEntityKind.location,
        entityId: id,
        op: OutboxOp.upsert,
        at: at,
        fields: {
          'entry_id': entryId,
          'source_id': sourceId,
          'url': url,
          'url_key': urlKey,
          'source_label': sourceLabel,
          'source_number': sourceNumber,
          'discovered_at': wireTime(at),
          'discovery_basis': discoveryBasis,
          'lifecycle': domain.LocationLifecycle.active.name,
        },
      );
      return (await locationById(id), null);
    });
  }

  /// The fill-in writer: the fields a second reading of an address has
  /// established that the stored Location did not carry.
  ///
  /// Narrow on purpose. **Only the arguments named are written** — a null
  /// argument is *absent*, never a clearing null — because deciding which
  /// blanks a re-listing may fill is `recognition/check.dart`'s judgement and
  /// nothing else may reach these columns. There is deliberately no way to
  /// write `url`, `url_key`, `discovered_at` or `lifecycle` here: identity is
  /// not evidence, when an address was first seen is not a re-sighting, and
  /// the lifecycle has its own scoped writer above.
  ///
  /// The row's clock moves, and the one intent carries exactly the fields the
  /// row did — the contract's `fields` object is sparse, so an omitted key is
  /// "unchanged" on the server too. A call that names nothing writes nothing,
  /// outbox included: a mutation that changes no field is not one.
  Future<(LocationRow?, InvariantViolation?)> updateLocationEvidence(
    String locationId, {
    String? sourceLabel,
    double? sourceNumber,
    String? discoveryBasis,
  }) async {
    return _db.transaction(() async {
      final row = await locationById(locationId);
      if (row == null) return (null, unknownRow);
      // An omitted key is "unchanged"; a null value would be "cleared", and a
      // fill-in never clears anything. The null-aware `?` leaves the key out.
      final fields = <String, Object?>{
        'source_label': ?sourceLabel,
        'source_number': ?sourceNumber,
        'discovery_basis': ?discoveryBasis,
      };
      if (fields.isEmpty) return (row, null);
      final at = _now();
      await (_db.update(
        _db.locations,
      )..where((l) => l.id.equals(locationId))).write(
        LocationsCompanion(
          sourceLabel: Value.absentIfNull(sourceLabel),
          sourceNumber: Value.absentIfNull(sourceNumber),
          discoveryBasis: Value.absentIfNull(discoveryBasis),
          updatedAt: Value(at),
        ),
      );
      await _outbox.record(
        kind: SyncedEntityKind.location,
        entityId: locationId,
        op: OutboxOp.upsert,
        at: at,
        fields: fields,
      );
      return (await locationById(locationId), null);
    });
  }

  /// Records the publish date a reading of this address established.
  ///
  /// Its own writer rather than another parameter on [updateLocationEvidence],
  /// because that method's contract is that **everything it names goes to the
  /// outbox** — the `fields` map and the columns are built from the same
  /// arguments so the two cannot drift apart. `published_at` is not in
  /// `contracts/evidence.yaml`, so it cannot go there, and adding a silent
  /// exception inside that method is how the guarantee would quietly stop
  /// being true.
  ///
  /// Local-only, and the precedent is [retractLocation] directly below: a
  /// Location write that stays on this device. Two consequences worth stating:
  ///
  /// * **`updated_at` is not touched.** It is the row's last-writer-wins clock
  ///   (V2-D6), and moving it for a field that never syncs would let this
  ///   device's row beat a legitimate remote update and discard it.
  /// * **It never clears.** [publishedAt] is non-null by signature, so a site
  ///   that stops printing a date leaves the one already read standing.
  ///
  /// The last reading wins where a site corrects itself. Writes nothing when
  /// the stored date already names the same instant, so a re-capture of an
  /// unchanged page is not a database write. Compared with
  /// [DateTime.isAtSameMomentAs] rather than `==`, because drift stores a
  /// `DateTime` as a unix timestamp and hands it back in local time: the row's
  /// value is never `identical` to the UTC one a page was parsed into, and
  /// `==` would rewrite the same date on every capture.
  Future<InvariantViolation?> recordLocationPublishedAt(
    String locationId,
    DateTime publishedAt,
  ) async {
    return _db.transaction(() async {
      final row = await locationById(locationId);
      if (row == null) return unknownRow;
      if (row.publishedAt?.isAtSameMomentAs(publishedAt) ?? false) {
        return null;
      }
      await (_db.update(_db.locations)..where((l) => l.id.equals(locationId)))
          .write(LocationsCompanion(publishedAt: Value(publishedAt)));
      return null;
    });
  }

  /// Source-scoped retraction (I15). Evidence, not a user removal: it writes
  /// the lifecycle locally and DOES NOT sync — no outbox row, no tombstone
  /// (V2_SYNC.md §5). [readingSourceId] names the Source whose own reading
  /// justifies the retraction; any other Source's Location is refused.
  Future<InvariantViolation?> retractLocation(
    String locationId, {
    required String readingSourceId,
  }) async {
    return _db.transaction(() async {
      final row = await locationById(locationId);
      if (row == null) return unknownRow;
      final location = domain.Location(
        id: row.id,
        entryId: row.entryId,
        sourceId: row.sourceId,
        url: row.url,
        urlKey: row.urlKey,
      );
      if (!domain.mayRetractLocation(
        readingSourceId: readingSourceId,
        location: location,
      )) {
        return retractionOutOfScope;
      }
      await (_db.update(
        _db.locations,
      )..where((l) => l.id.equals(locationId))).write(
        LocationsCompanion(
          lifecycle: Value(domain.LocationLifecycle.retracted.name),
          updatedAt: Value(_now()),
        ),
      );
      return null;
    });
  }

  /// A user removing an address by hand IS a removal and syncs (V2_SYNC.md
  /// §5). Copies keep their provenance snapshot.
  Future<InvariantViolation?> removeLocationByHand(String locationId) async {
    return _db.transaction(() async {
      if (await locationById(locationId) == null) return unknownRow;
      final at = _now();
      await (_db.delete(
        _db.locations,
      )..where((l) => l.id.equals(locationId))).go();
      await _outbox.record(
        kind: SyncedEntityKind.location,
        entityId: locationId,
        op: OutboxOp.delete,
        at: at,
      );
      return null;
    });
  }

  Future<LocationRow?> locationById(String id) => (_db.select(
    _db.locations,
  )..where((l) => l.id.equals(id))).getSingleOrNull();

  Future<List<LocationRow>> locationsOf(String entryId) {
    return (_db.select(_db.locations)
          ..where((l) => l.entryId.equals(entryId))
          ..orderBy([(l) => OrderingTerm.asc(l.discoveredAt)]))
        .get();
  }

  /// Every Location one Source has shown, in the order they were discovered —
  /// **one** read on `idx_locations_source`.
  ///
  /// What a source-scoped reading needs is a Source's own Locations, and
  /// asking for them by Entry meant a walk of the Collection's Entries with a
  /// query per Entry. This is that answer asked for directly. Retracted rows
  /// are included: whether a lifecycle disqualifies a row is the caller's
  /// judgement (a checkpoint excludes them; a reconciliation must see them).
  Future<List<LocationRow>> locationsOfSource(String sourceId) {
    return (_db.select(_db.locations)
          ..where((l) => l.sourceId.equals(sourceId))
          ..orderBy([(l) => OrderingTerm.asc(l.discoveredAt)]))
        .get();
  }

  // ---- Pull path (sync lane): no outbox, ever. -----------------------------

  Future<void> applyRemoteEntry({
    required String id,
    required String? serverId,
    required String? collectionId,
    required String? folderId,
    required double? ordinal,
    required String placement,
    required String title,
    required int sortKey,
    required int revision,
    required DateTime updatedAt,
  }) async {
    await _db
        .into(_db.entries)
        .insertOnConflictUpdate(
          EntriesCompanion(
            id: Value(id),
            serverId: Value(serverId),
            collectionId: Value(collectionId),
            folderId: Value(folderId),
            ordinal: Value(ordinal),
            placement: Value(placement),
            title: Value(title),
            sortKey: Value(sortKey),
            revision: Value(revision),
            updatedAt: Value(updatedAt),
          ),
        );
  }

  Future<void> applyRemoteEntryDelete(String id) async {
    await (_db.delete(_db.entries)..where((e) => e.id.equals(id))).go();
  }

  Future<void> applyRemoteLocation({
    required String id,
    required String? serverId,
    required String entryId,
    required String? sourceId,
    required String url,
    required String urlKey,
    required String sourceLabel,
    required double? sourceNumber,
    required DateTime discoveredAt,
    required String discoveryBasis,
    required String lifecycle,
    required int revision,
    required DateTime updatedAt,
  }) async {
    await _db
        .into(_db.locations)
        .insertOnConflictUpdate(
          LocationsCompanion(
            id: Value(id),
            serverId: Value(serverId),
            entryId: Value(entryId),
            sourceId: Value(sourceId),
            url: Value(url),
            urlKey: Value(urlKey),
            sourceLabel: Value(sourceLabel),
            sourceNumber: Value(sourceNumber),
            discoveredAt: Value(discoveredAt),
            discoveryBasis: Value(discoveryBasis),
            lifecycle: Value(lifecycle),
            revision: Value(revision),
            updatedAt: Value(updatedAt),
          ),
        );
  }

  Future<void> applyRemoteLocationDelete(String id) async {
    await (_db.delete(_db.locations)..where((l) => l.id.equals(id))).go();
  }

  // ---- Sync-lane surface (additive, roadmap G3): no outbox, no clock. ------

  Future<void> applyEntryServerId(String id, String serverId) async {
    await (_db.update(_db.entries)..where((e) => e.id.equals(id))).write(
      EntriesCompanion(serverId: Value(serverId)),
    );
  }

  Future<void> applyLocationServerId(String id, String serverId) async {
    await (_db.update(_db.locations)..where((l) => l.id.equals(id))).write(
      LocationsCompanion(serverId: Value(serverId)),
    );
  }

  /// The Location holding this natural identity, if any — the collision probe
  /// for merge-before-insert (`url_key` is unique locally, I6).
  Future<LocationRow?> locationByUrlKey(String urlKey) => (_db.select(
    _db.locations,
  )..where((l) => l.urlKey.equals(urlKey))).getSingleOrNull();

  Future<void> rewriteEntryFolderRefs(String from, String to) async {
    await (_db.update(_db.entries)..where((e) => e.folderId.equals(from)))
        .write(EntriesCompanion(folderId: Value(to)));
  }

  Future<void> rewriteEntryCollectionRefs(String from, String to) async {
    await (_db.update(_db.entries)..where((e) => e.collectionId.equals(from)))
        .write(EntriesCompanion(collectionId: Value(to)));
  }

  Future<void> rewriteLocationEntryRefs(String from, String to) async {
    await (_db.update(_db.locations)..where((l) => l.entryId.equals(from)))
        .write(LocationsCompanion(entryId: Value(to)));
  }

  Future<void> rewriteLocationSourceRefs(String from, String to) async {
    await (_db.update(_db.locations)..where((l) => l.sourceId.equals(from)))
        .write(LocationsCompanion(sourceId: Value(to)));
  }

  bool _mentions(Exception e, String needle) => e.toString().contains(needle);
}
