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
  ) async {
    return _db.transaction(() async {
      final row = await byId(id);
      if (row == null) return (null, unknownRow);
      final at = _now();
      try {
        await (_db.update(_db.entries)..where((e) => e.id.equals(id))).write(
          EntriesCompanion(
            ordinal: Value(ordinal),
            placement: Value(Placement.userPlaced.name),
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
        fields: {'ordinal': ordinal, 'placement': Placement.userPlaced.name},
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
        .insert(
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
          mode: InsertMode.insertOrReplace,
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
        .insert(
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
          mode: InsertMode.insertOrReplace,
        );
  }

  Future<void> applyRemoteLocationDelete(String id) async {
    await (_db.delete(_db.locations)..where((l) => l.id.equals(id))).go();
  }

  bool _mentions(Exception e, String needle) => e.toString().contains(needle);
}
