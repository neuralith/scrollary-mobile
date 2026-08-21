/// DownloadRequest repository: the device's view of a synced intent.
///
/// The single-winner claim itself is a SYNCHRONOUS server transition
/// (contracts/openapi.yaml `/download-requests/{id}/claim`) — a queued claim
/// is meaningless, because exactly one device may win. So:
///
/// * [applyRemote] mirrors server rows from the pull feed (no outbox);
/// * [recordLocalClaim] records a claim this device already WON on the server,
///   plus the local save task it created (device column, no outbox);
/// * [resolveLocally] records the terminal outcome durably and queues ONE
///   outbox intent — the drain routes `downloadRequest` intents to the
///   `/resolve` endpoint, never to `/mutations`, which excludes the kind.
///
/// A failure never changes library membership (I17): nothing here touches an
/// Entry.
library;

import 'package:drift/drift.dart';

import '../domain/download_request.dart';
import '../domain/invariants.dart';
import '../domain/sync_kinds.dart';
import 'data_ids.dart';
import 'data_violations.dart';
import 'outbox_writer.dart';
import 'schema.dart';

class DownloadRequestRepository {
  DownloadRequestRepository(this._db, {Clock? now, IdGenerator? newId})
    : _now = now ?? utcNow,
      _outbox = OutboxWriter(_db, newId: newId);

  final LibraryDatabase _db;
  final Clock _now;
  final OutboxWriter _outbox;

  /// Requests this device could act on: pending mirrors of the intent.
  Future<List<DownloadRequestRow>> pendingRequests() {
    return (_db.select(_db.downloadRequests)
          ..where((r) => r.state.equals(DownloadRequestState.pending.name))
          ..orderBy([(r) => OrderingTerm.asc(r.createdAt)]))
        .get();
  }

  Future<DownloadRequestRow?> byId(String id) => (_db.select(
    _db.downloadRequests,
  )..where((r) => r.id.equals(id))).getSingleOrNull();

  /// Records a claim this device already won on the server, and the local
  /// save task the claim became. Conditional on `pending`, mirroring the
  /// server's own transition; no outbox — the server state already changed.
  Future<InvariantViolation?> recordLocalClaim(
    String id, {
    required String device,
    required String localSaveTaskId,
    DateTime? at,
  }) async {
    return _db.transaction(() async {
      final when = (at ?? _now()).toUtc();
      final updated =
          await (_db.update(_db.downloadRequests)..where(
                (r) =>
                    r.id.equals(id) &
                    r.state.equals(DownloadRequestState.pending.name),
              ))
              .write(
                DownloadRequestsCompanion(
                  state: Value(DownloadRequestState.claimed.name),
                  claimedByDevice: Value(device),
                  claimedAt: Value(when),
                  localSaveTaskId: Value(localSaveTaskId),
                ),
              );
      if (updated == 0) {
        final row = await byId(id);
        return row == null ? unknownRow : requestAlreadyClaimed;
      }
      return null;
    });
  }

  /// Records the terminal outcome of this device's save durably, and queues
  /// the report to the server as the one outbox intent this table produces.
  Future<InvariantViolation?> resolveLocally(
    String id, {
    required DownloadRequestState to,
    String failureReason = '',
    DateTime? at,
  }) async {
    return _db.transaction(() async {
      final row = await byId(id);
      if (row == null) return unknownRow;
      final when = (at ?? _now()).toUtc();
      final current = DownloadRequest(
        id: row.id,
        entryId: row.entryId,
        locationId: row.locationId,
        state: DownloadRequestState.values.byName(row.state),
        claimedByDevice: row.claimedByDevice,
      );
      final (resolved, violation) = current.resolve(
        to: to,
        at: when,
        reason: failureReason,
      );
      if (violation != null || resolved == null) return violation;
      await (_db.update(
        _db.downloadRequests,
      )..where((r) => r.id.equals(id))).write(
        DownloadRequestsCompanion(
          state: Value(resolved.state.name),
          resolvedAt: Value(when),
          failureReason: Value(resolved.failureReason),
        ),
      );
      await _outbox.record(
        kind: SyncedEntityKind.downloadRequest,
        entityId: id,
        op: OutboxOp.upsert,
        at: when,
        fields: {
          'state': resolved.state.name,
          'failure_reason': resolved.failureReason,
        },
      );
      return null;
    });
  }

  // ---- Pull path (sync lane): no outbox, ever. -----------------------------

  Future<void> applyRemote({
    required String id,
    required String? serverId,
    required String entryId,
    required String? locationId,
    required String state,
    required String idempotencyKey,
    required String createdBy,
    required DateTime createdAt,
    required String claimedByDevice,
    required DateTime? claimedAt,
    required DateTime? resolvedAt,
    required String failureReason,
    required int revision,
  }) async {
    // Preserve the device-only column across the replace.
    final existing = await byId(id);
    await _db
        .into(_db.downloadRequests)
        .insertOnConflictUpdate(
          DownloadRequestsCompanion(
            id: Value(id),
            serverId: Value(serverId),
            entryId: Value(entryId),
            locationId: Value(locationId),
            state: Value(state),
            idempotencyKey: Value(idempotencyKey),
            createdBy: Value(createdBy),
            createdAt: Value(createdAt),
            claimedByDevice: Value(claimedByDevice),
            claimedAt: Value(claimedAt),
            resolvedAt: Value(resolvedAt),
            failureReason: Value(failureReason),
            revision: Value(revision),
            localSaveTaskId: Value(existing?.localSaveTaskId),
          ),
        );
  }

  Future<void> applyRemoteDelete(String id) async {
    await (_db.delete(
      _db.downloadRequests,
    )..where((r) => r.id.equals(id))).go();
  }

  // ---- Sync-lane surface (additive, roadmap G3). ---------------------------

  Future<void> applyServerId(String id, String serverId) async {
    await (_db.update(_db.downloadRequests)..where((r) => r.id.equals(id)))
        .write(DownloadRequestsCompanion(serverId: Value(serverId)));
  }

  Future<void> rewriteEntryRefs(String from, String to) async {
    await (_db.update(_db.downloadRequests)
          ..where((r) => r.entryId.equals(from)))
        .write(DownloadRequestsCompanion(entryId: Value(to)));
  }

  Future<void> rewriteLocationRefs(String from, String to) async {
    await (_db.update(_db.downloadRequests)
          ..where((r) => r.locationId.equals(from)))
        .write(DownloadRequestsCompanion(locationId: Value(to)));
  }
}
