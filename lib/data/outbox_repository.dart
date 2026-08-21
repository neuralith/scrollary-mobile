/// Outbox storage and sync bookkeeping (roadmap C10).
///
/// The outbox is append-only and ordered; rowid is the order. Writing happens
/// only through [OutboxWriter] inside repository transactions — this class is
/// the drain's side: read in order, record attempts, acknowledge.
///
/// `sync_state` is one row: the cursor (highest server revision seen), last
/// success, last attempt, last error. The pending count is derived from the
/// outbox by COUNT(*) — a stored copy would be a cache that can lie.
library;

import 'package:drift/drift.dart';

import 'schema.dart';

class OutboxRepository {
  OutboxRepository(this._db);

  final LibraryDatabase _db;

  /// Pending intents, oldest first — the order they must reach the server in.
  Future<List<OutboxRow>> pending({int limit = 100}) {
    return (_db.select(_db.outbox)
          ..orderBy([(o) => OrderingTerm.asc(o.opId)])
          ..limit(limit))
        .get();
  }

  /// Records one delivery attempt, with the failure if there was one.
  Future<void> markAttempt(int opId, {String? error}) async {
    final row = await (_db.select(
      _db.outbox,
    )..where((o) => o.opId.equals(opId))).getSingleOrNull();
    if (row == null) return;
    await (_db.update(_db.outbox)..where((o) => o.opId.equals(opId))).write(
      OutboxCompanion(
        attempts: Value(row.attempts + 1),
        lastError: Value(error),
      ),
    );
  }

  /// Removes acknowledged intents. Only an `applied` / `duplicate` /
  /// terminally-`rejected` server outcome acknowledges; an ambiguous failure
  /// never does — the mutation id makes the retry safe.
  Future<void> ack(Iterable<int> opIds) async {
    await (_db.delete(_db.outbox)..where((o) => o.opId.isIn(opIds))).go();
  }

  /// Derived, never cached.
  Future<int> pendingCount() async {
    final count = _db.outbox.opId.count();
    final query = _db.selectOnly(_db.outbox)..addColumns([count]);
    final row = await query.getSingle();
    return row.read(count) ?? 0;
  }

  // ---- Drain surface (additive, roadmap G1). -------------------------------

  /// The marker a terminally-rejected intent carries in `last_error`. A parked
  /// row stays visible (the user can see what failed and why) but never
  /// re-enters a drain — resending it would be rejected identically forever.
  static const rejectedPrefix = 'rejected:';

  /// Drainable intents after [afterOpId], oldest first, excluding parked
  /// rejections. Keyset pagination so a wall of parked rows cannot stall the
  /// drain.
  Future<List<OutboxRow>> pendingAfter(int afterOpId, {int limit = 50}) {
    return (_db.select(_db.outbox)
          ..where(
            (o) =>
                o.opId.isBiggerThanValue(afterOpId) &
                (o.lastError.isNull() |
                    o.lastError.like('$rejectedPrefix%').not()),
          )
          ..orderBy([(o) => OrderingTerm.asc(o.opId)])
          ..limit(limit))
        .get();
  }

  /// Parks a row the server rejected with a named reason. Not an ack: the row
  /// stays for the problems surface, marked so drains skip it.
  Future<void> markRejected(int opId, String reason) async {
    await (_db.update(_db.outbox)..where((o) => o.opId.equals(opId))).write(
      OutboxCompanion(lastError: Value('$rejectedPrefix$reason')),
    );
  }

  /// Parked rejections, for the sync-status surface.
  Future<List<OutboxRow>> rejected() {
    return (_db.select(_db.outbox)
          ..where((o) => o.lastError.like('$rejectedPrefix%'))
          ..orderBy([(o) => OrderingTerm.asc(o.opId)]))
        .get();
  }
}

/// The singleton sync-state row (`CHECK (id = 1)`).
class SyncStateStore {
  SyncStateStore(this._db);

  final LibraryDatabase _db;

  static const _id = 1;

  Future<SyncStateRow> _ensure() async {
    final existing = await (_db.select(
      _db.syncState,
    )..where((s) => s.id.equals(_id))).getSingleOrNull();
    if (existing != null) return existing;
    await _db
        .into(_db.syncState)
        .insert(
          const SyncStateCompanion(id: Value(_id)),
          mode: InsertMode.insertOrIgnore,
        );
    return (_db.select(
      _db.syncState,
    )..where((s) => s.id.equals(_id))).getSingle();
  }

  /// The highest server revision this device has seen; 0 means bootstrap.
  Future<int> cursor() async => (await _ensure()).cursor;

  Future<void> setCursor(int value) async {
    await _ensure();
    await (_db.update(_db.syncState)..where((s) => s.id.equals(_id))).write(
      SyncStateCompanion(cursor: Value(value)),
    );
  }

  Future<void> recordAttempt(DateTime at) async {
    await _ensure();
    await (_db.update(_db.syncState)..where((s) => s.id.equals(_id))).write(
      SyncStateCompanion(lastAttemptAt: Value(at)),
    );
  }

  Future<void> recordSuccess(DateTime at) async {
    await _ensure();
    await (_db.update(_db.syncState)..where((s) => s.id.equals(_id))).write(
      SyncStateCompanion(
        lastSuccessAt: Value(at),
        lastAttemptAt: Value(at),
        lastError: const Value(null),
      ),
    );
  }

  Future<void> recordError(String message, DateTime at) async {
    await _ensure();
    await (_db.update(_db.syncState)..where((s) => s.id.equals(_id))).write(
      SyncStateCompanion(lastAttemptAt: Value(at), lastError: Value(message)),
    );
  }

  Future<SyncStateRow> current() => _ensure();
}
