/// Collection and Source repository (roadmap C4).
///
/// Follow semantics per V2-D13: a Collection in the library IS followed
/// (`lifecycle = active`); archiving is how following stops and writes
/// `lifecycle` and nothing else. Sources carry their whole life in one row
/// (V2-D14): a site returning is a state change, not a row moved between
/// tables.
library;

import 'package:drift/drift.dart';

import '../domain/collection.dart';
import '../domain/invariants.dart';
import '../domain/source.dart' as domain;
import '../domain/sync_kinds.dart';
import 'data_ids.dart';
import 'data_violations.dart';
import 'outbox_writer.dart';
import 'schema.dart';

class CollectionRepository {
  CollectionRepository(this._db, {Clock? now, IdGenerator? newId})
    : _now = now ?? utcNow,
      _newId = newId ?? newLocalId,
      _outbox = OutboxWriter(_db, newId: newId);

  final LibraryDatabase _db;
  final Clock _now;
  final IdGenerator _newId;
  final OutboxWriter _outbox;

  // ---- Collection ----------------------------------------------------------

  Future<(CollectionRow?, InvariantViolation?)> create({
    required String name,
    required String folderId,
    required OrderingBasis orderingBasis,
    String detectedTitle = '',
    int sortKey = 0,
  }) async {
    return _db.transaction(() async {
      final id = _newId();
      final collection = Collection(
        id: id,
        folderId: folderId,
        name: name,
        orderingBasis: orderingBasis,
      );
      final violation = collection.validate();
      if (violation != null) return (null, violation);
      final at = _now();
      await _db
          .into(_db.collections)
          .insert(
            CollectionsCompanion.insert(
              id: id,
              folderId: folderId,
              name: name,
              detectedTitle: Value(detectedTitle),
              orderingBasis: orderingBasis.name,
              sortKey: Value(sortKey),
              updatedAt: at,
            ),
          );
      await _outbox.record(
        kind: SyncedEntityKind.collection,
        entityId: id,
        op: OutboxOp.upsert,
        at: at,
        fields: {
          'folder_id': folderId,
          'name': name,
          'detected_title': detectedTitle,
          'ordering_basis': orderingBasis.name,
          'lifecycle': CollectionLifecycle.active.name,
          'preferred_source_id': null,
          'sort_key': sortKey,
        },
      );
      return (await byId(id), null);
    });
  }

  /// Archive writes `lifecycle` and nothing else. It is never deletion.
  Future<InvariantViolation?> archive(String id) =>
      _setLifecycle(id, CollectionLifecycle.archived);

  /// Following again is the same single-column write back to `active`.
  Future<InvariantViolation?> follow(String id) =>
      _setLifecycle(id, CollectionLifecycle.active);

  Future<InvariantViolation?> _setLifecycle(
    String id,
    CollectionLifecycle lifecycle,
  ) async {
    return _db.transaction(() async {
      if (await byId(id) == null) return unknownRow;
      final at = _now();
      await (_db.update(_db.collections)..where((c) => c.id.equals(id))).write(
        CollectionsCompanion(
          lifecycle: Value(lifecycle.name),
          updatedAt: Value(at),
        ),
      );
      await _outbox.record(
        kind: SyncedEntityKind.collection,
        entityId: id,
        op: OutboxOp.upsert,
        at: at,
        fields: {'lifecycle': lifecycle.name},
      );
      return null;
    });
  }

  Future<InvariantViolation?> rename(String id, String name) async {
    return _db.transaction(() async {
      if (await byId(id) == null) return unknownRow;
      final at = _now();
      await (_db.update(_db.collections)..where((c) => c.id.equals(id))).write(
        CollectionsCompanion(name: Value(name), updatedAt: Value(at)),
      );
      await _outbox.record(
        kind: SyncedEntityKind.collection,
        entityId: id,
        op: OutboxOp.upsert,
        at: at,
        fields: {'name': name},
      );
      return null;
    });
  }

  Future<InvariantViolation?> moveToFolder(String id, String folderId) async {
    return _db.transaction(() async {
      if (await byId(id) == null) return unknownRow;
      final folder = await (_db.select(
        _db.folders,
      )..where((f) => f.id.equals(folderId))).getSingleOrNull();
      if (folder == null) return unknownParentFolder;
      final at = _now();
      await (_db.update(_db.collections)..where((c) => c.id.equals(id))).write(
        CollectionsCompanion(folderId: Value(folderId), updatedAt: Value(at)),
      );
      await _outbox.record(
        kind: SyncedEntityKind.collection,
        entityId: id,
        op: OutboxOp.upsert,
        at: at,
        fields: {'folder_id': folderId},
      );
      return null;
    });
  }

  /// Sets or clears the preferred Source, validating I9 through the domain.
  Future<InvariantViolation?> setPreferredSource(
    String collectionId,
    String? sourceId,
  ) async {
    return _db.transaction(() async {
      final row = await byId(collectionId);
      if (row == null) return unknownRow;
      final collection = Collection(
        id: row.id,
        folderId: row.folderId,
        name: row.name,
        orderingBasis: OrderingBasis.values.byName(row.orderingBasis),
        preferredSourceId: sourceId,
      );
      domain.Source? preferred;
      if (sourceId != null) {
        final sourceRow = await _sourceById(sourceId);
        preferred = sourceRow == null ? null : _toDomain(sourceRow);
      }
      final violation = collection.validatePreferredSource(preferred);
      if (violation != null) return violation;
      final at = _now();
      await (_db.update(
        _db.collections,
      )..where((c) => c.id.equals(collectionId))).write(
        CollectionsCompanion(
          preferredSourceId: Value(sourceId),
          updatedAt: Value(at),
        ),
      );
      await _outbox.record(
        kind: SyncedEntityKind.collection,
        entityId: collectionId,
        op: OutboxOp.upsert,
        at: at,
        fields: {'preferred_source_id': sourceId},
      );
      return null;
    });
  }

  /// A deliberate user removal (V2_SYNC.md §5): tombstones on the server, and
  /// locally takes the Collection's rows with it through the schema's
  /// cascades. Offline copies have no foreign key and survive (I14).
  Future<InvariantViolation?> removeCollection(String id) async {
    return _db.transaction(() async {
      if (await byId(id) == null) return unknownRow;
      final at = _now();
      await (_db.delete(_db.collections)..where((c) => c.id.equals(id))).go();
      await _outbox.record(
        kind: SyncedEntityKind.collection,
        entityId: id,
        op: OutboxOp.delete,
        at: at,
      );
      return null;
    });
  }

  Future<CollectionRow?> byId(String id) => (_db.select(
    _db.collections,
  )..where((c) => c.id.equals(id))).getSingleOrNull();

  Future<List<CollectionRow>> inFolder(String folderId) {
    return (_db.select(_db.collections)
          ..where((c) => c.folderId.equals(folderId))
          ..orderBy([
            (c) => OrderingTerm.asc(c.sortKey),
            (c) => OrderingTerm.asc(c.name),
          ]))
        .get();
  }

  // ---- Source --------------------------------------------------------------

  Future<(SourceRow?, InvariantViolation?)> addSource({
    required String collectionId,
    required String host,
    required String pathKey,
    String language = '',
    DateTime? firstSeenAt,
  }) async {
    return _db.transaction(() async {
      if (await byId(collectionId) == null) return (null, unknownRow);
      final id = _newId();
      final at = _now();
      final seen = firstSeenAt ?? at;
      try {
        await _db
            .into(_db.sources)
            .insert(
              SourcesCompanion.insert(
                id: id,
                collectionId: collectionId,
                host: host,
                pathKey: pathKey,
                language: Value(language),
                firstSeenAt: seen,
                lastSeenAt: seen,
                updatedAt: at,
              ),
            );
      } on Exception catch (e) {
        if (_isUniqueViolation(e)) return (null, sourceIdentityTaken);
        rethrow;
      }
      await _outbox.record(
        kind: SyncedEntityKind.source,
        entityId: id,
        op: OutboxOp.upsert,
        at: at,
        fields: {
          'collection_id': collectionId,
          'host': host,
          'path_key': pathKey,
          'language': language,
          'lifecycle': domain.SourceLifecycle.active.name,
          'resolved_into_source_id': null,
          'first_seen_at': wireTime(seen),
          'last_seen_at': wireTime(seen),
        },
      );
      return (await _sourceById(id), null);
    });
  }

  /// Lifecycle transition. `resolvedInto` requires a target Source of the
  /// same Collection; any other transition clears the pointer.
  Future<InvariantViolation?> setSourceLifecycle(
    String sourceId,
    domain.SourceLifecycle lifecycle, {
    String? resolvedIntoSourceId,
  }) async {
    return _db.transaction(() async {
      final row = await _sourceById(sourceId);
      if (row == null) return unknownRow;
      String? pointer;
      if (lifecycle == domain.SourceLifecycle.resolvedInto) {
        if (resolvedIntoSourceId == null) return resolvedIntoForeign;
        final target = await _sourceById(resolvedIntoSourceId);
        if (target == null ||
            target.collectionId != row.collectionId ||
            target.id == sourceId) {
          return resolvedIntoForeign;
        }
        pointer = resolvedIntoSourceId;
      }
      final at = _now();
      await (_db.update(
        _db.sources,
      )..where((s) => s.id.equals(sourceId))).write(
        SourcesCompanion(
          lifecycle: Value(lifecycle.name),
          resolvedIntoSourceId: Value(pointer),
          updatedAt: Value(at),
        ),
      );
      await _outbox.record(
        kind: SyncedEntityKind.source,
        entityId: sourceId,
        op: OutboxOp.upsert,
        at: at,
        fields: {
          'lifecycle': lifecycle.name,
          'resolved_into_source_id': pointer,
        },
      );
      return null;
    });
  }

  /// A deliberate user removal of a Source. Its Locations cascade; Entries
  /// stay (V2_SYNC.md §5).
  Future<InvariantViolation?> removeSource(String sourceId) async {
    return _db.transaction(() async {
      if (await _sourceById(sourceId) == null) return unknownRow;
      final at = _now();
      await (_db.delete(_db.sources)..where((s) => s.id.equals(sourceId))).go();
      await _outbox.record(
        kind: SyncedEntityKind.source,
        entityId: sourceId,
        op: OutboxOp.delete,
        at: at,
      );
      return null;
    });
  }

  /// Follows a `resolvedInto` chain to its terminal Source, refusing to loop.
  Future<SourceRow?> terminalSourceOf(String sourceId) async {
    final seen = <String>{};
    var cursor = await _sourceById(sourceId);
    while (cursor != null &&
        cursor.lifecycle == domain.SourceLifecycle.resolvedInto.name &&
        cursor.resolvedIntoSourceId != null) {
      if (!seen.add(cursor.id)) return null;
      cursor = await _sourceById(cursor.resolvedIntoSourceId!);
    }
    return cursor;
  }

  Future<List<SourceRow>> sourcesOf(String collectionId) {
    return (_db.select(_db.sources)
          ..where((s) => s.collectionId.equals(collectionId))
          ..orderBy([(s) => OrderingTerm.asc(s.firstSeenAt)]))
        .get();
  }

  Future<SourceRow?> sourceById(String id) => _sourceById(id);

  // ---- Pull path (sync lane): no outbox, ever. -----------------------------

  Future<void> applyRemoteCollection({
    required String id,
    required String? serverId,
    required String folderId,
    required String name,
    required String detectedTitle,
    required String orderingBasis,
    required String lifecycle,
    required String? preferredSourceId,
    required int sortKey,
    required int revision,
    required DateTime updatedAt,
  }) async {
    await _db
        .into(_db.collections)
        .insertOnConflictUpdate(
          CollectionsCompanion(
            id: Value(id),
            serverId: Value(serverId),
            folderId: Value(folderId),
            name: Value(name),
            detectedTitle: Value(detectedTitle),
            orderingBasis: Value(orderingBasis),
            lifecycle: Value(lifecycle),
            preferredSourceId: Value(preferredSourceId),
            sortKey: Value(sortKey),
            revision: Value(revision),
            updatedAt: Value(updatedAt),
          ),
        );
  }

  Future<void> applyRemoteCollectionDelete(String id) async {
    await (_db.delete(_db.collections)..where((c) => c.id.equals(id))).go();
  }

  Future<void> applyRemoteSource({
    required String id,
    required String? serverId,
    required String collectionId,
    required String host,
    required String pathKey,
    required String language,
    required String lifecycle,
    required String? resolvedIntoSourceId,
    required DateTime firstSeenAt,
    required DateTime lastSeenAt,
    required int revision,
    required DateTime updatedAt,
  }) async {
    await _db
        .into(_db.sources)
        .insertOnConflictUpdate(
          SourcesCompanion(
            id: Value(id),
            serverId: Value(serverId),
            collectionId: Value(collectionId),
            host: Value(host),
            pathKey: Value(pathKey),
            language: Value(language),
            lifecycle: Value(lifecycle),
            resolvedIntoSourceId: Value(resolvedIntoSourceId),
            firstSeenAt: Value(firstSeenAt),
            lastSeenAt: Value(lastSeenAt),
            revision: Value(revision),
            updatedAt: Value(updatedAt),
          ),
        );
  }

  Future<void> applyRemoteSourceDelete(String id) async {
    await (_db.delete(_db.sources)..where((s) => s.id.equals(id))).go();
  }

  // ---- Sync-lane surface (additive, roadmap G3): no outbox, no clock. ------

  Future<void> applyCollectionServerId(String id, String serverId) async {
    await (_db.update(_db.collections)..where((c) => c.id.equals(id))).write(
      CollectionsCompanion(serverId: Value(serverId)),
    );
  }

  Future<void> applySourceServerId(String id, String serverId) async {
    await (_db.update(_db.sources)..where((s) => s.id.equals(id))).write(
      SourcesCompanion(serverId: Value(serverId)),
    );
  }

  /// The Source holding this natural identity, if any — the collision probe
  /// for merge-before-insert (the local `(host, path_key)` index is unique).
  Future<SourceRow?> sourceByIdentity(String host, String pathKey) =>
      (_db.select(_db.sources)
            ..where((s) => s.host.equals(host) & s.pathKey.equals(pathKey)))
          .getSingleOrNull();

  /// Repoints collection rows living in folder [from] at [to].
  Future<void> rewriteCollectionFolderRefs(String from, String to) async {
    await (_db.update(_db.collections)..where((c) => c.folderId.equals(from)))
        .write(CollectionsCompanion(folderId: Value(to)));
  }

  /// Repoints sources of collection [from] at [to].
  Future<void> rewriteSourceCollectionRefs(String from, String to) async {
    await (_db.update(_db.sources)..where((s) => s.collectionId.equals(from)))
        .write(SourcesCompanion(collectionId: Value(to)));
  }

  /// Repoints source-valued references ([from] → [to]) held by this
  /// repository's tables: preferred pointers and `resolvedInto` targets.
  Future<void> rewriteSourceRefs(String from, String to) async {
    await (_db.update(_db.collections)
          ..where((c) => c.preferredSourceId.equals(from)))
        .write(CollectionsCompanion(preferredSourceId: Value(to)));
    await (_db.update(_db.sources)
          ..where((s) => s.resolvedIntoSourceId.equals(from)))
        .write(SourcesCompanion(resolvedIntoSourceId: Value(to)));
  }

  // ---- helpers -------------------------------------------------------------

  Future<SourceRow?> _sourceById(String id) => (_db.select(
    _db.sources,
  )..where((s) => s.id.equals(id))).getSingleOrNull();

  domain.Source _toDomain(SourceRow row) => domain.Source(
    id: row.id,
    collectionId: row.collectionId,
    host: row.host,
    pathKey: row.pathKey,
    language: row.language,
    lifecycle: domain.SourceLifecycle.values.byName(row.lifecycle),
    resolvedIntoSourceId: row.resolvedIntoSourceId,
    firstSeenAt: row.firstSeenAt,
    lastSeenAt: row.lastSeenAt,
  );

  bool _isUniqueViolation(Exception e) =>
      e.toString().contains('UNIQUE constraint failed');
}
