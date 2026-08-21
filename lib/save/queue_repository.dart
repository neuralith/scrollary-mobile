/// Persistence and state transitions for the V2 save queue (roadmap E3).
///
/// **The one property this file exists to hold: every claim and every cancel
/// is one conditional `UPDATE`, so exactly one of a racing pair wins and the
/// loser is told.** V1 learned that the hard way — a pump reads the pending
/// rows, awaits the Browser coming forward, then claims one, and a cancel
/// landing inside that await was silently overwritten by a blind write. Both
/// sides go through [SaveQueueRepository.updateIfState] and nothing else may
/// write a state.
///
/// What this class is not: a scheduler. It owns ordering, persistence and
/// history; the work itself belongs to whatever drives the Browser. Splitting
/// them is what makes the whole state machine host-testable — there is no
/// WebView anywhere in this file.
///
/// Three rules carried from V1 that are easy to lose in a port:
///
/// * **Nothing starts without an explicit Start**, and that authorisation is
///   never persisted ([saveStartAuthorised]). Queued rows survive a restart;
///   permission to drive the Browser does not.
/// * **A cancel writes the row now**, not when the worker notices, because
///   [demoteInterruptedRuns] promotes a killed `running` row back to `queued`
///   and an in-memory-only request would hand the user their cancelled work
///   back on relaunch.
/// * **A restricted target becomes a terminal `failed` row**, never a silent
///   deletion. The user queued something and is owed a record of what became
///   of it.
library;

import 'package:drift/drift.dart';

import '../data/data_ids.dart';
import '../data/schema.dart';
import 'capture_mode.dart';
import 'capture_policy.dart';
import 'queue_task.dart';
import 'stop_conditions.dart';

/// What [SaveQueueRepository.enqueue] did.
///
/// `alreadyQueued` is not a failure: the Entry is in the queue, which is what
/// the user asked for. It exists so a caller can say "already in the queue"
/// instead of a second "added".
class SaveEnqueueResult {
  const SaveEnqueueResult._({
    this.task,
    this.alreadyQueued = false,
    this.refusedReason,
  });

  const SaveEnqueueResult.added(SaveTask task) : this._(task: task);
  const SaveEnqueueResult.alreadyQueued(SaveTask task)
    : this._(task: task, alreadyQueued: true);

  /// Refused by the restricted-site capture policy. **No row is written**, so
  /// there is nothing to start, retry or clean up later.
  const SaveEnqueueResult.restricted()
    : this._(refusedReason: kCaptureRestrictedMessage);

  final SaveTask? task;
  final bool alreadyQueued;
  final String? refusedReason;

  bool get restricted => refusedReason != null;
}

class SaveQueueRepository {
  SaveQueueRepository(this._db, {Clock? now, IdGenerator? newId})
    : _now = now ?? utcNow,
      _newId = newId ?? newLocalId;

  final LibraryDatabase _db;
  final Clock _now;
  final IdGenerator _newId;

  /// How many terminal rows are kept. History is bounded; queue rows are never
  /// the content, so pruning them deletes no Entry, no file and no reading
  /// state.
  static const int historyLimit = 50;

  // --- authorisation: in memory, never on disk ------------------------------

  bool _saveStartAuthorised = false;

  /// True between "the user pressed Start" and the queue running dry.
  ///
  /// **Deliberately not persisted.** A relaunch that resumed saving because a
  /// row existed yesterday is exactly what the product forbids, and this field
  /// is the whole of the difference. Nothing writes it to the database, and a
  /// second repository over the same file starts unauthorised.
  bool get saveStartAuthorised => _saveStartAuthorised;

  /// The user pressed Start. Authorises the queued saves to be claimed.
  void authoriseStart() => _saveStartAuthorised = true;

  /// The batch is over — by a stop, by the queue draining, or by the app
  /// closing. Adding more work later is a new decision and gets a new Start.
  void revokeStart() => _saveStartAuthorised = false;

  // --- cooperative stopping -------------------------------------------------

  final Set<String> _stopRequested = <String>{};

  /// Asked by a worker between safe boundaries: *may I carry on?*
  ///
  /// The durable half of a cancellation is the `cancelled` row, written
  /// immediately. This is the half that reaches a run already in flight, and
  /// it is why the wording everywhere is "at the next safe point" — nothing
  /// here kills anything mid-write.
  bool shouldContinue(String taskId) => !_stopRequested.contains(taskId);

  /// Consume the stop request for [taskId], reporting whether one was made.
  /// Called once as a run unwinds, so a flag can never outlive its task.
  bool takeStopRequest(String taskId) => _stopRequested.remove(taskId);

  // --- the single writer ----------------------------------------------------

  /// Write [values] onto a row **only while it is still in one of [expected]**,
  /// and say whether that happened.
  ///
  /// A companion rather than a data class on purpose: drift's
  /// `insertOnConflictUpdate` reads a null field as *absent*, so it cannot
  /// clear `started_at`.
  Future<bool> updateIfState({
    required String id,
    required List<SaveTaskState> expected,
    required SaveQueueCompanion values,
  }) async {
    final names = [for (final s in expected) s.name];
    final changed = await (_db.update(
      _db.saveQueue,
    )..where((t) => t.id.equals(id) & t.state.isIn(names))).write(values);
    return changed > 0;
  }

  // --- enqueueing -----------------------------------------------------------

  /// Add a save request. It **waits**: nothing navigates, nothing scrolls, no
  /// WebView is touched until the user starts the queue.
  ///
  /// The restricted-site policy is asked here, for itself. A refusal writes no
  /// row at all — there is nothing to start, so there is nothing to record.
  ///
  /// Idempotent per Entry: a second request while one is still waiting or
  /// running returns the existing row rather than stacking a duplicate behind
  /// it. An Entry has one active OfflineCopy (I13), so two open tasks for it
  /// could only ever be two candidates for one copy.
  Future<SaveEnqueueResult> enqueue({
    required String entryId,
    required String locationUrl,
    String? locationId,
    CaptureMode? captureMode,
    bool captureModeIsUserSet = false,
  }) async {
    if (isCaptureRestricted(locationUrl)) {
      return const SaveEnqueueResult.restricted();
    }
    final open = await openTaskFor(entryId);
    if (open != null) return SaveEnqueueResult.alreadyQueued(open);

    final at = _now();
    final id = _newId();
    await _db
        .into(_db.saveQueue)
        .insert(
          SaveQueueCompanion.insert(
            id: id,
            entryId: entryId,
            locationId: Value(locationId),
            locationUrl: locationUrl,
            captureMode: Value(captureMode?.name),
            captureModeIsUserSet: Value(captureModeIsUserSet),
            state: Value(SaveTaskState.queued.name),
            origin: Value(SaveTaskOrigin.queue.name),
            orderIndex: Value(await nextOrderIndex()),
            queuedAt: at,
          ),
        );
    return SaveEnqueueResult.added((await byId(id))!);
  }

  /// Record a save the user started straight from the Browser: **history, not
  /// a plan**. Written terminal, so no pump can ever release it.
  Future<SaveTask> recordDirectOutcome({
    required String entryId,
    required String locationUrl,
    required SaveTaskState state,
    String? locationId,
    CaptureMode? captureMode,
    String? outcome,
    String? lastError,
    StopReason? stopReason,
  }) async {
    assert(state.isTerminal, 'a direct row is only ever terminal');
    final at = _now();
    final id = _newId();
    await _db
        .into(_db.saveQueue)
        .insert(
          SaveQueueCompanion.insert(
            id: id,
            entryId: entryId,
            locationId: Value(locationId),
            locationUrl: locationUrl,
            captureMode: Value(captureMode?.name),
            state: Value(state.name),
            origin: Value(SaveTaskOrigin.direct.name),
            outcome: Value(outcome),
            lastError: Value(lastError),
            stopReason: Value(stopReason?.name),
            orderIndex: Value(await nextOrderIndex()),
            queuedAt: at,
            startedAt: Value(at),
            finishedAt: Value(at),
          ),
        );
    await pruneHistory();
    return (await byId(id))!;
  }

  // --- claiming and finishing -----------------------------------------------

  /// The rows a pump may consider right now, in queue order.
  ///
  /// Empty until the user has pressed Start: save is the one kind of work that
  /// waits for an explicit authorisation, and it is not persisted.
  Future<List<SaveTask>> eligible() async {
    if (!_saveStartAuthorised) return const [];
    return _tasksWhere([SaveTaskState.queued]);
  }

  /// Take a queued row for this worker. **Null means it was lost** — a cancel
  /// or another claim got there first — and the caller must skip the row and
  /// carry on rather than reviving it into `running`.
  Future<SaveTask?> claim(String id) async {
    final won = await updateIfState(
      id: id,
      expected: [SaveTaskState.queued],
      values: SaveQueueCompanion(
        state: Value(SaveTaskState.running.name),
        startedAt: Value(_now()),
      ),
    );
    if (!won) {
      // A row nobody is running cannot have a live stop request against it.
      _stopRequested.remove(id);
      return null;
    }
    return byId(id);
  }

  /// Write how a run ended. Conditional on the row still being `running`, so a
  /// cancellation that landed first keeps its own verdict — "the site stopped
  /// us" and "you stopped it" are different outcomes and must not overwrite
  /// each other.
  Future<bool> finish(
    String id, {
    required SaveTaskState state,
    String? outcome,
    String? lastError,
    StopReason? stopReason,
  }) async {
    assert(state.isTerminal, 'a run ends in a terminal state');
    return updateIfState(
      id: id,
      expected: [SaveTaskState.running],
      values: SaveQueueCompanion(
        state: Value(state.name),
        outcome: Value(outcome),
        lastError: Value(lastError),
        stopReason: Value(stopReason?.name),
        finishedAt: Value(_now()),
      ),
    );
  }

  // --- cancelling -----------------------------------------------------------

  /// Cancel a waiting row outright, or ask the running one to stop.
  ///
  /// Reads the row, acts on what it finds, and — when a queued row turns out
  /// to have been claimed in the same instant — reads it again rather than
  /// reporting a cancellation that did not happen.
  Future<SaveCancelOutcome> cancel(String id) async {
    final task = await byId(id);
    if (task == null) return SaveCancelOutcome.gone;

    if (task.state == SaveTaskState.queued) {
      final won = await updateIfState(
        id: id,
        expected: [SaveTaskState.queued],
        values: SaveQueueCompanion(
          state: Value(SaveTaskState.cancelled.name),
          outcome: const Value(kSaveTaskCancelledBeforeStart),
          lastError: const Value(null),
          stopReason: Value(StopReason.cancelledByUser.name),
          finishedAt: Value(_now()),
        ),
      );
      if (won) {
        await pruneHistory();
        return SaveCancelOutcome.cancelledBeforeStart;
      }
      // Lost the race with a claim. Fall through and read the row again.
      final now = await byId(id);
      if (now == null || now.state != SaveTaskState.running) {
        return SaveCancelOutcome.gone;
      }
      return _stopRunning(id);
    }

    if (task.state == SaveTaskState.running) return _stopRunning(id);
    return SaveCancelOutcome.alreadyFinished;
  }

  /// Move a running row to `cancelled` **now** and raise the cooperative flag.
  ///
  /// Conditional for the same reason a claim is: the run may have ended
  /// between reading the row and writing to it, and stamping `cancelled` over
  /// a finished run would misreport work that actually completed.
  Future<SaveCancelOutcome> _stopRunning(String id) async {
    final marked = await updateIfState(
      id: id,
      expected: [SaveTaskState.running],
      values: SaveQueueCompanion(
        state: Value(SaveTaskState.cancelled.name),
        outcome: const Value(kSaveTaskStopping),
        lastError: const Value(null),
        stopReason: Value(StopReason.cancelledByUser.name),
        finishedAt: Value(_now()),
      ),
    );
    if (!marked) return SaveCancelOutcome.alreadyFinished;
    // Only now: a flag raised for a task that had already finished would never
    // be cleared.
    _stopRequested.add(id);
    return SaveCancelOutcome.stoppingRunning;
  }

  /// Put a cancelled row back where it was — the Undo behind "removed from the
  /// queue".
  ///
  /// **In place, keeping its `order_index`**: a retry would clone it to the
  /// back of the queue, which is a different thing to offer for an accidental
  /// tap. Only a `cancelled` row qualifies, so an undo racing a history clear
  /// does nothing rather than resurrecting work twice.
  Future<bool> restoreQueued(String id) async {
    final restored = await updateIfState(
      id: id,
      expected: [SaveTaskState.cancelled],
      values: SaveQueueCompanion(
        state: Value(SaveTaskState.queued.name),
        outcome: const Value(null),
        lastError: const Value(null),
        stopReason: const Value(null),
        startedAt: const Value(null),
        finishedAt: const Value(null),
      ),
    );
    if (restored) _stopRequested.remove(id);
    return restored;
  }

  /// Drop one **terminal** row — *Remove from Activity*.
  ///
  /// A waiting or running row is unreachable from here by construction:
  /// dropping a live row would orphan work that is still moving, and those go
  /// through [cancel]. Queue rows are never the content, so this deletes no
  /// Entry, no file and no reading state.
  Future<bool> removeTerminal(String id) async {
    final terminal = [
      for (final s in SaveTaskState.values)
        if (s.isTerminal) s.name,
    ];
    final deleted = await (_db.delete(
      _db.saveQueue,
    )..where((t) => t.id.equals(id) & t.state.isIn(terminal))).go();
    return deleted > 0;
  }

  // --- the restricted-site policy, at this boundary -------------------------

  /// Turn a queued row whose target is restricted into a terminal failure, in
  /// place. True when the row was restricted, whether or not this call is what
  /// settled it.
  ///
  /// Asked by the pump before it claims anything, which is where a **stale**
  /// task is stopped: a row queued when its host was permitted, or one that
  /// survived a restart, arrives here like any other. Deliberately a `failed`
  /// row rather than a deletion, carrying the policy's own named reason, and
  /// nothing re-runs it on its own.
  Future<bool> settleIfRestricted(SaveTask task) async {
    if (!isCaptureRestricted(task.locationUrl)) return false;
    final settled = await updateIfState(
      id: task.id,
      // Queued only, exactly as V1: a row already claimed belongs to its
      // runner, which asks the policy for itself before it probes.
      expected: [SaveTaskState.queued],
      values: SaveQueueCompanion(
        state: Value(SaveTaskState.failed.name),
        outcome: const Value(kCaptureRestrictedMessage),
        lastError: const Value(kCaptureRestrictedMessage),
        stopReason: Value(StopReason.captureRestrictedForSite.name),
        finishedAt: Value(_now()),
      ),
    );
    if (settled) await pruneHistory();
    return true;
  }

  /// Re-enqueue a terminal task as a fresh row at the back of the queue.
  ///
  /// Null when the retry is refused — including by the restricted-site policy,
  /// which is what stops a history row on a restricted service being turned
  /// back into work that runs.
  Future<SaveTask?> retry(String id) async {
    final task = await byId(id);
    if (task == null || !task.isTerminal) return null;
    final result = await enqueue(
      entryId: task.entryId,
      locationUrl: task.locationUrl,
      locationId: task.locationId,
      captureMode: task.captureMode,
      captureModeIsUserSet: task.captureModeIsUserSet,
    );
    return result.task;
  }

  // --- startup --------------------------------------------------------------

  /// Call once at startup. A row left `running` by a kill never ran to
  /// completion and must not pretend it did, so it is demoted to `queued` —
  /// which is also why a cancellation is written the moment it is asked for.
  /// Returns how many rows were demoted.
  Future<int> demoteInterruptedRuns() async {
    return (_db.update(
      _db.saveQueue,
    )..where((t) => t.state.equals(SaveTaskState.running.name))).write(
      SaveQueueCompanion(
        state: Value(SaveTaskState.queued.name),
        startedAt: const Value(null),
      ),
    );
  }

  // --- reordering -----------------------------------------------------------

  Future<int> nextOrderIndex() async {
    final row = await (_db.selectOnly(
      _db.saveQueue,
    )..addColumns([_db.saveQueue.orderIndex.max()])).getSingle();
    return (row.read(_db.saveQueue.orderIndex.max()) ?? 0) + 1;
  }

  /// Move a queued task to the front. Renumbered from a base above every
  /// existing row, so a reorder can never collide with a running task's index
  /// or with history.
  Future<void> moveToFront(String id) async {
    final queued = await _tasksWhere([SaveTaskState.queued]);
    if (!queued.any((t) => t.id == id)) return;
    await _writeOrder([
      ...queued.where((t) => t.id == id),
      ...queued.where((t) => t.id != id),
    ]);
  }

  Future<void> _writeOrder(List<SaveTask> ordered) async {
    final base = await nextOrderIndex();
    await _db.transaction(() async {
      for (var i = 0; i < ordered.length; i++) {
        await (_db.update(_db.saveQueue)
              ..where((t) => t.id.equals(ordered[i].id)))
            .write(SaveQueueCompanion(orderIndex: Value(base + i)));
      }
    });
  }

  // --- history --------------------------------------------------------------

  /// Keep only the newest [keep] terminal rows.
  Future<int> pruneHistory({int keep = historyLimit}) async {
    final terminal = await _tasksWhere([
      SaveTaskState.completed,
      SaveTaskState.failed,
      SaveTaskState.cancelled,
    ], newestFirst: true);
    if (terminal.length <= keep) return 0;
    final doomed = [for (final t in terminal.skip(keep)) t.id];
    return (_db.delete(_db.saveQueue)..where((t) => t.id.isIn(doomed))).go();
  }

  /// Clear terminal history only. Waiting and running rows are untouched, and
  /// so, above all, is every saved package.
  Future<int> clearHistory() {
    final terminal = [
      for (final s in SaveTaskState.values)
        if (s.isTerminal) s.name,
    ];
    return (_db.delete(
      _db.saveQueue,
    )..where((t) => t.state.isIn(terminal))).go();
  }

  // --- reads ----------------------------------------------------------------

  Future<SaveTask?> byId(String id) async {
    final row = await (_db.select(
      _db.saveQueue,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    return row == null ? null : _toDomain(row);
  }

  /// The waiting or running task for an Entry, if there is one. History is
  /// deliberately excluded: an Entry saved last week must not block an
  /// intentional re-save today.
  Future<SaveTask?> openTaskFor(String entryId) async {
    final rows =
        await (_db.select(_db.saveQueue)
              ..where(
                (t) =>
                    t.entryId.equals(entryId) &
                    t.state.isIn([
                      SaveTaskState.queued.name,
                      SaveTaskState.running.name,
                    ]),
              )
              ..limit(1))
            .get();
    return rows.isEmpty ? null : _toDomain(rows.first);
  }

  /// Queued and running rows, in queue order.
  Future<List<SaveTask>> pending() =>
      _tasksWhere([SaveTaskState.queued, SaveTaskState.running]);

  Future<List<SaveTask>> all() async {
    final rows = await (_db.select(
      _db.saveQueue,
    )..orderBy([(t) => OrderingTerm.asc(t.orderIndex)])).get();
    return [for (final row in rows) _toDomain(row)];
  }

  Stream<List<SaveTask>> watch() =>
      (_db.select(_db.saveQueue)
            ..orderBy([(t) => OrderingTerm.asc(t.orderIndex)]))
          .watch()
          .map((rows) => [for (final row in rows) _toDomain(row)]);

  Future<List<SaveTask>> _tasksWhere(
    List<SaveTaskState> states, {
    bool newestFirst = false,
  }) async {
    final names = [for (final s in states) s.name];
    final rows =
        await (_db.select(_db.saveQueue)
              ..where((t) => t.state.isIn(names))
              ..orderBy([
                if (newestFirst)
                  (t) => OrderingTerm.desc(t.finishedAt)
                else
                  (t) => OrderingTerm.asc(t.orderIndex),
              ]))
            .get();
    return [for (final row in rows) _toDomain(row)];
  }

  SaveTask _toDomain(SaveTaskRow row) => SaveTask(
    id: row.id,
    entryId: row.entryId,
    locationId: row.locationId,
    locationUrl: row.locationUrl,
    captureMode: captureModeFromName(row.captureMode),
    captureModeIsUserSet: row.captureModeIsUserSet,
    state: SaveTaskState.fromName(row.state),
    origin: SaveTaskOrigin.fromName(row.origin),
    outcome: row.outcome,
    lastError: row.lastError,
    stopReason: StopReason.fromName(row.stopReason),
    orderIndex: row.orderIndex,
    queuedAt: row.queuedAt,
    startedAt: row.startedAt,
    finishedAt: row.finishedAt,
  );
}
