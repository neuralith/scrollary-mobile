/// ReadingState repository (roadmap C6).
///
/// All writes are read-modify-write and go through one serialising queue —
/// the rule V1 learned expensively (`V2_ARCHITECTURE.md` §6.2): a stale
/// in-flight write must never clobber a newer one, and a sync path that
/// bypasses the queue reintroduces that race. The pull path below therefore
/// runs through the same queue.
///
/// Completion is a value, not a floor (V2-D6): `markUnread` exists to lower
/// progress. Opening at a source records access and never completion (I16).
///
/// Outbox payloads carry the full state field set every time: reading state
/// merges as one scalar row under last-write-wins, and a whole-row value makes
/// the merge deterministic.
library;

import 'package:drift/drift.dart';

import '../domain/invariants.dart';
import '../domain/reading_state.dart';
import '../domain/sync_kinds.dart';
import 'data_ids.dart';
import 'data_violations.dart';
import 'outbox_writer.dart';
import 'schema.dart';

class ReadingStateRepository {
  ReadingStateRepository(this._db, {Clock? now, IdGenerator? newId})
    : _now = now ?? utcNow,
      _outbox = OutboxWriter(_db, newId: newId);

  final LibraryDatabase _db;
  final Clock _now;
  final OutboxWriter _outbox;

  Future<void> _tail = Future.value();

  /// Serialises every mutation. The returned future completes with the
  /// operation; failures do not break the chain.
  Future<T> _serialised<T>(Future<T> Function() action) {
    final run = _tail.then((_) => action());
    _tail = run.then((_) {}, onError: (_) {});
    return run;
  }

  /// I16 / V2-D9: opening an Entry at its source. Sets first-opened once,
  /// last-read always, unread → reading, and never touches completion.
  Future<(ReadingState?, InvariantViolation?)> recordSourceAccess(
    String entryId, {
    DateTime? at,
  }) {
    return _serialised(() async {
      return _db.transaction(() async {
        if (!await _entryExists(entryId)) return (null, unknownRow);
        final when = (at ?? _now()).toUtc();
        final current = await _domainState(entryId);
        final next = current.recordSourceAccess(when);
        await _write(next, when);
        return (next, null);
      });
    });
  }

  /// Explicit completion. Available for any Entry, downloaded or not.
  Future<(ReadingState?, InvariantViolation?)> markRead(
    String entryId, {
    DateTime? at,
  }) {
    return _serialised(() async {
      return _db.transaction(() async {
        if (!await _entryExists(entryId)) return (null, unknownRow);
        final when = (at ?? _now()).toUtc();
        final current = await _domainState(entryId);
        final next = ReadingState(
          entryId: entryId,
          status: ReadStatus.completed,
          firstOpenedAt: current.firstOpenedAt ?? when,
          lastReadAt: when,
          completedAt: when,
          updatedAt: when,
        );
        await _write(next, when);
        return (next, null);
      });
    });
  }

  /// Lowers progress deliberately: back to unread, completion cleared. The
  /// open/read history stays — it happened.
  Future<(ReadingState?, InvariantViolation?)> markUnread(
    String entryId, {
    DateTime? at,
  }) {
    return _serialised(() async {
      return _db.transaction(() async {
        if (!await _entryExists(entryId)) return (null, unknownRow);
        final when = (at ?? _now()).toUtc();
        final current = await _domainState(entryId);
        final next = ReadingState(
          entryId: entryId,
          status: ReadStatus.unread,
          firstOpenedAt: current.firstOpenedAt,
          lastReadAt: current.lastReadAt,
          completedAt: null,
          updatedAt: when,
        );
        await _write(next, when);
        return (next, null);
      });
    });
  }

  /// The state of an Entry. Absent rows read as unread (I10): reading state
  /// exists for every Entry, stored or not.
  Future<ReadingState> stateOf(String entryId) => _domainState(entryId);

  // ---- Pull path (sync lane): same queue, no outbox. -----------------------

  Future<void> applyRemote({
    required String entryId,
    required String status,
    required DateTime? firstOpenedAt,
    required DateTime? lastReadAt,
    required DateTime? completedAt,
    required int revision,
    required DateTime updatedAt,
  }) {
    return _serialised(() async {
      await _db
          .into(_db.readingStates)
          .insertOnConflictUpdate(
            ReadingStatesCompanion(
              entryId: Value(entryId),
              status: Value(status),
              firstOpenedAt: Value(firstOpenedAt),
              lastReadAt: Value(lastReadAt),
              completedAt: Value(completedAt),
              revision: Value(revision),
              updatedAt: Value(updatedAt),
            ),
          );
    });
  }

  Future<void> applyRemoteDelete(String entryId) {
    return _serialised(() async {
      await (_db.delete(
        _db.readingStates,
      )..where((r) => r.entryId.equals(entryId))).go();
    });
  }

  /// Moves the state row of a merged-away duplicate Entry onto its survivor
  /// (roadmap G3). If the survivor already has a row, the newer clock wins.
  Future<void> rewriteEntryRef(String from, String to) {
    return _serialised(() async {
      final moving = await (_db.select(
        _db.readingStates,
      )..where((r) => r.entryId.equals(from))).getSingleOrNull();
      if (moving == null) return;
      final existing = await (_db.select(
        _db.readingStates,
      )..where((r) => r.entryId.equals(to))).getSingleOrNull();
      await (_db.delete(
        _db.readingStates,
      )..where((r) => r.entryId.equals(from))).go();
      if (existing == null || existing.updatedAt.isBefore(moving.updatedAt)) {
        await _db
            .into(_db.readingStates)
            .insertOnConflictUpdate(
              ReadingStatesCompanion(
                entryId: Value(to),
                status: Value(moving.status),
                firstOpenedAt: Value(moving.firstOpenedAt),
                lastReadAt: Value(moving.lastReadAt),
                completedAt: Value(moving.completedAt),
                revision: Value(moving.revision),
                updatedAt: Value(moving.updatedAt),
              ),
            );
      }
    });
  }

  // ---- helpers -------------------------------------------------------------

  Future<bool> _entryExists(String entryId) async {
    final row = await (_db.select(
      _db.entries,
    )..where((e) => e.id.equals(entryId))).getSingleOrNull();
    return row != null;
  }

  Future<ReadingState> _domainState(String entryId) async {
    final row = await (_db.select(
      _db.readingStates,
    )..where((r) => r.entryId.equals(entryId))).getSingleOrNull();
    if (row == null) return ReadingState(entryId: entryId);
    // Drift reads stored timestamps back in local time; the domain speaks UTC.
    return ReadingState(
      entryId: row.entryId,
      status: ReadStatus.values.byName(row.status),
      firstOpenedAt: row.firstOpenedAt?.toUtc(),
      lastReadAt: row.lastReadAt?.toUtc(),
      completedAt: row.completedAt?.toUtc(),
      updatedAt: row.updatedAt.toUtc(),
    );
  }

  Future<void> _write(ReadingState state, DateTime at) async {
    await _db
        .into(_db.readingStates)
        .insertOnConflictUpdate(
          ReadingStatesCompanion(
            entryId: Value(state.entryId),
            status: Value(state.status.name),
            firstOpenedAt: Value(state.firstOpenedAt),
            lastReadAt: Value(state.lastReadAt),
            completedAt: Value(state.completedAt),
            updatedAt: Value(at),
          ),
        );
    await _outbox.record(
      kind: SyncedEntityKind.readingState,
      entityId: state.entryId,
      op: OutboxOp.upsert,
      at: at,
      fields: {
        'status': state.status.name,
        'first_opened_at': wireTime(state.firstOpenedAt),
        'last_read_at': wireTime(state.lastReadAt),
        'completed_at': wireTime(state.completedAt),
      },
    );
  }
}
