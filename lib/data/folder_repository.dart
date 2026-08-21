/// Folder repository (roadmap C3): the tree, and the only code that changes it.
///
/// Deletion reparents children to the deleted Folder's parent and never
/// cascades into content (I5) — the schema's RESTRICT foreign keys are the
/// backstop, this repository is the behaviour. The delete syncs as ONE intent
/// (the folder's `delete`): the server performs the same reparent on its side,
/// and the reparented children flow back as ordinary changes, so children are
/// not individually pushed.
///
/// The root is created locally without an outbox intent: every library gets a
/// root, so the server mints its own canonically and the sync lane maps the
/// local root onto it at first contact. Pushing a locally minted root would
/// collide with the server's one-root-per-library index.
library;

import 'package:drift/drift.dart';

import '../domain/folder.dart';
import '../domain/invariants.dart';
import '../domain/sync_kinds.dart';
import 'data_ids.dart';
import 'data_violations.dart';
import 'outbox_writer.dart';
import 'schema.dart';

/// What a delete-with-reparent moved, so the caller can say it out loud.
class ReparentCounts {
  const ReparentCounts({
    required this.folders,
    required this.collections,
    required this.entries,
  });

  final int folders;
  final int collections;
  final int entries;

  int get total => folders + collections + entries;
}

class FolderRepository {
  FolderRepository(this._db, {Clock? now, IdGenerator? newId})
    : _now = now ?? utcNow,
      _newId = newId ?? newLocalId,
      _outbox = OutboxWriter(_db, newId: newId);

  final LibraryDatabase _db;
  final Clock _now;
  final IdGenerator _newId;
  final OutboxWriter _outbox;

  /// Returns the root Folder, creating it on first use. No outbox intent —
  /// see the library comment.
  Future<FolderRow> ensureRoot() async {
    return _db.transaction(() async {
      final existing = await (_db.select(
        _db.folders,
      )..where((f) => f.kind.equals(FolderKind.root.name))).getSingleOrNull();
      if (existing != null) return existing;
      final at = _now();
      final row = FoldersCompanion.insert(
        id: _newId(),
        kind: FolderKind.root.name,
        name: 'Library',
        updatedAt: at,
      );
      await _db.into(_db.folders).insert(row);
      return (_db.select(
        _db.folders,
      )..where((f) => f.kind.equals(FolderKind.root.name))).getSingle();
    });
  }

  /// Creates a user Folder. [parentId] defaults to the root.
  Future<(FolderRow?, InvariantViolation?)> create(
    String name, {
    String? parentId,
    int sortKey = 0,
  }) async {
    return _db.transaction(() async {
      final parent = parentId ?? (await ensureRoot()).id;
      if (await _byId(parent) == null) return (null, unknownParentFolder);
      final id = _newId();
      final folder = Folder(
        id: id,
        kind: FolderKind.user,
        name: name,
        parentId: parent,
        sortKey: sortKey,
      );
      final violation = folder.validate();
      if (violation != null) return (null, violation);
      final at = _now();
      await _db
          .into(_db.folders)
          .insert(
            FoldersCompanion.insert(
              id: id,
              parentId: Value(parent),
              kind: FolderKind.user.name,
              name: name,
              sortKey: Value(sortKey),
              updatedAt: at,
            ),
          );
      await _outbox.record(
        kind: SyncedEntityKind.folder,
        entityId: id,
        op: OutboxOp.upsert,
        at: at,
        fields: {
          'parent_id': parent,
          'kind': FolderKind.user.name,
          'name': name,
          'sort_key': sortKey,
        },
      );
      return (await _byId(id), null);
    });
  }

  Future<(FolderRow?, InvariantViolation?)> rename(
    String id,
    String name,
  ) async {
    return _db.transaction(() async {
      final row = await _byId(id);
      if (row == null) return (null, unknownRow);
      if (row.kind == FolderKind.root.name) return (null, rootFolderImmutable);
      final at = _now();
      await (_db.update(_db.folders)..where((f) => f.id.equals(id))).write(
        FoldersCompanion(name: Value(name), updatedAt: Value(at)),
      );
      await _outbox.record(
        kind: SyncedEntityKind.folder,
        entityId: id,
        op: OutboxOp.upsert,
        at: at,
        fields: {'name': name},
      );
      return (await _byId(id), null);
    });
  }

  /// Moves [id] under [newParentId], refusing the root, an unknown target and
  /// any move that would make the folder contain itself (I2).
  Future<InvariantViolation?> move(String id, String newParentId) async {
    return _db.transaction(() async {
      final row = await _byId(id);
      if (row == null) return unknownRow;
      if (row.kind == FolderKind.root.name) return rootFolderImmutable;
      if (await _byId(newParentId) == null) return unknownParentFolder;
      final all = await _db.select(_db.folders).get();
      final parentOf = {for (final f in all) f.id: f.parentId};
      if (wouldCreateFolderCycle(
        parentOf: parentOf,
        folderId: id,
        newParentId: newParentId,
      )) {
        return folderCycle;
      }
      final at = _now();
      await (_db.update(_db.folders)..where((f) => f.id.equals(id))).write(
        FoldersCompanion(parentId: Value(newParentId), updatedAt: Value(at)),
      );
      await _outbox.record(
        kind: SyncedEntityKind.folder,
        entityId: id,
        op: OutboxOp.upsert,
        at: at,
        fields: {'parent_id': newParentId},
      );
      return null;
    });
  }

  /// Deletes [id], reparenting its child folders, collections and standalone
  /// entries to its parent (I5). One outbox intent: the folder's delete.
  Future<(ReparentCounts?, InvariantViolation?)> deleteWithReparent(
    String id,
  ) async {
    return _db.transaction(() async {
      final row = await _byId(id);
      if (row == null) return (null, unknownRow);
      if (row.kind == FolderKind.root.name) return (null, rootFolderImmutable);
      final target = row.parentId!;
      final at = _now();
      final folders =
          await (_db.update(
            _db.folders,
          )..where((f) => f.parentId.equals(id))).write(
            FoldersCompanion(parentId: Value(target), updatedAt: Value(at)),
          );
      final collections =
          await (_db.update(
            _db.collections,
          )..where((c) => c.folderId.equals(id))).write(
            CollectionsCompanion(folderId: Value(target), updatedAt: Value(at)),
          );
      final entries =
          await (_db.update(
            _db.entries,
          )..where((e) => e.folderId.equals(id))).write(
            EntriesCompanion(folderId: Value(target), updatedAt: Value(at)),
          );
      await (_db.delete(_db.folders)..where((f) => f.id.equals(id))).go();
      await _outbox.record(
        kind: SyncedEntityKind.folder,
        entityId: id,
        op: OutboxOp.delete,
        at: at,
      );
      return (
        ReparentCounts(
          folders: folders,
          collections: collections,
          entries: entries,
        ),
        null,
      );
    });
  }

  Future<FolderRow?> byId(String id) => _byId(id);

  /// Children of [parentId], in the user's order.
  Future<List<FolderRow>> childrenOf(String parentId) {
    return (_db.select(_db.folders)
          ..where((f) => f.parentId.equals(parentId))
          ..orderBy([
            (f) => OrderingTerm.asc(f.sortKey),
            (f) => OrderingTerm.asc(f.name),
          ]))
        .get();
  }

  // ---- Pull path (sync lane): no outbox, ever. -----------------------------

  /// Applies a server-side Folder row. Every column written explicitly, so a
  /// null really clears (the drift absent-vs-null trap).
  Future<void> applyRemote({
    required String id,
    required String? serverId,
    required String? parentId,
    required String kind,
    required String name,
    required int sortKey,
    required int revision,
    required DateTime updatedAt,
  }) async {
    await _db
        .into(_db.folders)
        .insert(
          FoldersCompanion(
            id: Value(id),
            serverId: Value(serverId),
            parentId: Value(parentId),
            kind: Value(kind),
            name: Value(name),
            sortKey: Value(sortKey),
            revision: Value(revision),
            updatedAt: Value(updatedAt),
          ),
          mode: InsertMode.insertOrReplace,
        );
  }

  /// Applies a server-side tombstone. The server reparents before it deletes,
  /// and revisions deliver the reparented children first, so a remaining
  /// child here means an inconsistent batch — the RESTRICT foreign key
  /// refuses it rather than losing content.
  Future<void> applyRemoteDelete(String id) async {
    await (_db.delete(_db.folders)..where((f) => f.id.equals(id))).go();
  }

  Future<FolderRow?> _byId(String id) => (_db.select(
    _db.folders,
  )..where((f) => f.id.equals(id))).getSingleOrNull();
}
