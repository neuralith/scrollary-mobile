/// Consuming Download-to-Mobile intents (roadmap E4, V2-D25, V2_SYNC.md §7).
///
/// A request created somewhere else — the extension, another client — arrives
/// here as an ordinary pulled row. This file is the whole of what a device
/// does with one:
///
/// 1. **Select** the pending requests for Entries this library holds and can
///    reach. A request naming an Entry that is not here, or one with no
///    address on this device, is left alone: claiming is single-winner, and
///    burning the one claim on something this device cannot even attempt
///    would take the request away from a device that could.
/// 2. **Claim** it — the synchronous single-winner transition. Exactly one
///    device wins. A loser marks nothing and skips; the next pull tells it
///    who holds the request now.
/// 3. **Convert** the win into an ordinary local save task, at the requested
///    Location or the Entry's own. Nothing else about the save changes: it is
///    a `queue` row in `queued`, so **it waits for the user's explicit Start**
///    exactly as a save the user asked for on this device would, and the
///    restricted-site policy, the capture bounds and every stopping condition
///    are evaluated here, on the device, unchanged.
/// 4. **Report** the terminal state the local task reached, through the
///    repository's one outbox intent, which the drain routes to `/resolve`.
///
/// Two things this file must never do, and both are invariants rather than
/// preferences:
///
/// * **It never touches library membership.** A refusal, a failure or a
///   cancellation writes a state onto the request and nothing else (I17): the
///   Entry, its Locations, its reading state and its Collection are exactly as
///   they were. Nothing here has a repository that could remove one.
/// * **It never starts a save.** Claiming is a metadata exchange — it fetches
///   no page and drives no browser. The row it creates is waiting work, and
///   the authorisation to run it is the user's, given in the app, never
///   persisted and never implied by a synced intent.
///
/// **Recovery.** The claim is a server transition and the local task is a
/// local row, so a death between them is expected rather than exceptional.
/// Every run begins by reconciling what this device already claimed:
///
/// * a claimed request whose save task is **still live** — nothing to do;
/// * one whose task is **terminal** — resolve it, without re-capturing;
/// * one whose task has **vanished** (never recorded, cleared from Activity,
///   or the app died before it was written) — enqueue again. `enqueue` is
///   idempotent per Entry and the open-task unique index refuses a second live
///   row, so a repeat can never double it;
/// * one whose Entry or address is **gone from this device** — left claimed,
///   because a later pull may bring the address back and a deleted Entry takes
///   its request row with it.
///
/// A request re-offered as `pending` after this device already won it (the
/// claim landed, the local write did not) is recognised by the 409's own
/// `claimed_by_device`: if that is this device, the claim is ours and the
/// conversion proceeds.
///
/// **Composition.** This is a service with one entry point and no scheduler of
/// its own: [DownloadIntentConsumer.consume] is a single opportunity, safe to
/// interrupt and safe to repeat. It belongs after a pull has delivered the
/// requests and before the push drains the outbox, so a resolution reported
/// here leaves on the same opportunity. [createDownloadIntentConsumer] is the
/// shape the provider graph registers.
library;

import 'package:drift/drift.dart';

import '../data/data_ids.dart';
import '../data/download_request_repository.dart';
import '../data/entry_repository.dart';
import '../data/schema.dart';
import '../domain/download_request.dart';
import '../domain/location.dart';
import '../domain/sync_kinds.dart';
import '../save/queue_repository.dart';
import '../save/queue_task.dart';
import '../save/stop_conditions.dart';
import 'device_label.dart';
import 'ids.dart';
import 'transport.dart';

/// What one opportunity did. Counts, not prose: routine success is silent and
/// nothing here is shown to anyone by default.
class DownloadIntentReport {
  const DownloadIntentReport({
    this.claimed = 0,
    this.lost = 0,
    this.skipped = 0,
    this.refused = 0,
    this.resolved = 0,
    this.requeued = 0,
    this.stranded = 0,
    this.errors = const [],
  });

  /// Requests this device won and turned into a waiting save task.
  final int claimed;

  /// Claims another device holds. Nothing was written for these.
  final int lost;

  /// Pending requests for an Entry this library does not hold, or holds with
  /// no address to read it at.
  final int skipped;

  /// Claimed, then withheld by the restricted-site capture policy. Reported as
  /// a terminal failure; no queue row exists.
  final int refused;

  /// Terminal outcomes reported through the outbox.
  final int resolved;

  /// Claims whose save task had vanished and was enqueued again.
  final int requeued;

  /// Claims this device can no longer act on. Left claimed, untouched.
  final int stranded;

  /// Individually failed steps. The opportunity carries on where it can.
  final List<String> errors;
}

class DownloadIntentConsumer {
  /// The save queue is **the app's own**, taken rather than built: the Start
  /// authorisation lives on the instance, and a consumer holding a second
  /// repository would be reasoning about a queue nobody had started. It is
  /// held privately, so nothing reaches a Start through this object.
  DownloadIntentConsumer(
    this._queue, {
    required LibraryDatabase db,
    DeviceLabelStore? deviceLabel,
    Clock? now,
  }) : _db = db,
       _label = deviceLabel ?? DeviceLabelStore(db),
       _requests = DownloadRequestRepository(db, now: now),
       _entries = EntryRepository(db, now: now),
       _ids = SyncIds(db);

  final LibraryDatabase _db;
  final SaveQueueRepository _queue;
  final DeviceLabelStore _label;
  final DownloadRequestRepository _requests;
  final EntryRepository _entries;
  final SyncIds _ids;

  /// One opportunity: reconcile what is already claimed here, then claim what
  /// is pending and fulfillable.
  ///
  /// Reconciliation runs first so a resolution this device owes leaves before
  /// it asks for more work.
  Future<DownloadIntentReport> consume(SyncTransport transport) async {
    final device = await _label.label();
    final tally = _Tally();
    await _reconcileClaims(device, tally);
    await _claimPending(transport, device, tally);
    return tally.report();
  }

  // ---- claiming ------------------------------------------------------------

  Future<void> _claimPending(
    SyncTransport transport,
    String device,
    _Tally tally,
  ) async {
    for (final row in await _requests.pendingRequests()) {
      final target = await _targetFor(row);
      if (target == null) {
        tally.skipped += 1;
        continue;
      }
      final TransportReply reply;
      try {
        reply = await transport.claimDownloadRequest(
          await _ids.wireIdOf(SyncedEntityKind.downloadRequest, row.id),
          {'device': device},
        );
      } on SyncTransportException catch (e) {
        // The opportunity is over. Nothing was written; the next one resumes.
        tally.errors.add('claim ${row.id}: ${e.message}');
        return;
      }
      if (!reply.ok && !_alreadyOurs(reply, device)) {
        if (reply.status == 409) {
          // Another device owns it, or the request is already terminal.
          // Either way this device marks nothing and converges on the next
          // pull.
          tally.lost += 1;
        } else {
          tally.errors.add(
            'claim ${row.id}: HTTP ${reply.status} ${reply.errorCode ?? ''}',
          );
        }
        continue;
      }
      await _fulfil(row, target, device, tally);
    }
  }

  /// A 409 that names *this* device: the claim was won on an earlier
  /// opportunity whose local write never happened. Proceeding is convergence,
  /// not a second claim.
  bool _alreadyOurs(TransportReply reply, String device) {
    if (reply.status != 409) return false;
    if (reply.errorCode != 'download_request_already_claimed') return false;
    final error = reply.body['error'];
    if (error is! Map) return false;
    final details = error['details'];
    return details is Map && details['claimed_by_device'] == device;
  }

  /// Turn a won claim into a waiting save task, and record both locally.
  Future<void> _fulfil(
    DownloadRequestRow row,
    LocationRow target,
    String device,
    _Tally tally,
  ) async {
    final result = await _queue.enqueue(
      entryId: row.entryId,
      locationId: target.id,
      locationUrl: target.url,
    );
    final task = result.task;
    if (task == null) {
      // Withheld by the restricted-site policy, which is asked for itself at
      // that boundary. The device decided; the decision is reported as a
      // terminal state and no queue row exists to start or retry.
      await _resolve(row, DownloadRequestState.failed, tally, reason: _refused);
      tally.refused += 1;
      return;
    }
    // Conditional on the local row still being `pending`, which it is unless a
    // pull mirrored this device's own claim first. When it did not take, the
    // request is still ours and reconciliation finds the task by its Entry.
    await _requests.recordLocalClaim(
      row.id,
      device: device,
      localSaveTaskId: task.id,
    );
    tally.claimed += 1;
  }

  // ---- reconciling what this device already holds ---------------------------

  Future<void> _reconcileClaims(String device, _Tally tally) async {
    for (final row in await _claimedHere(device)) {
      final task = await _taskFor(row);
      if (task == null) {
        await _requeue(row, tally);
        continue;
      }
      if (task.isLive) continue; // still the queue's business
      final (state, reason) = _outcomeOf(task);
      await _resolve(row, state, tally, reason: reason);
      tally.resolved += 1;
    }
  }

  Future<void> _requeue(DownloadRequestRow row, _Tally tally) async {
    final target = await _targetFor(row);
    if (target == null) {
      // The Entry or its address is not here now. Leave the claim as it is: a
      // later pull may restore the address, and an Entry removed from the
      // library takes its request row with it.
      tally.stranded += 1;
      return;
    }
    final result = await _queue.enqueue(
      entryId: row.entryId,
      locationId: target.id,
      locationUrl: target.url,
    );
    if (result.task == null) {
      await _resolve(row, DownloadRequestState.failed, tally, reason: _refused);
      tally.refused += 1;
      return;
    }
    if (!result.alreadyQueued) tally.requeued += 1;
  }

  /// The save task fulfilling [row], by three answers in order: the task it
  /// recorded, the Entry's open task, or the terminal one that ran after the
  /// claim.
  ///
  /// The last two exist because the recorded id can be missing — the app can
  /// die between winning a claim and writing the row. An Entry has at most one
  /// open task by construction, so "the open task for this Entry" is not a
  /// guess.
  Future<SaveTask?> _taskFor(DownloadRequestRow row) async {
    final recorded = row.localSaveTaskId;
    if (recorded != null) {
      final task = await _queue.byId(recorded);
      if (task != null) return task;
    }
    final open = await _queue.openTaskFor(row.entryId);
    if (open != null) return open;
    return _terminalSinceClaim(row);
  }

  Future<SaveTask?> _terminalSinceClaim(DownloadRequestRow row) async {
    final claimedAt = row.claimedAt;
    if (claimedAt == null) return null;
    SaveTask? newest;
    for (final task in await _queue.all()) {
      if (task.entryId != row.entryId || !task.isTerminal) continue;
      final finishedAt = task.finishedAt;
      if (finishedAt == null || finishedAt.isBefore(claimedAt)) continue;
      final held = newest?.finishedAt;
      if (held == null || !finishedAt.isBefore(held)) newest = task;
    }
    return newest;
  }

  Future<List<DownloadRequestRow>> _claimedHere(String device) {
    return (_db.select(_db.downloadRequests)
          ..where(
            (r) =>
                r.state.equals(DownloadRequestState.claimed.name) &
                r.claimedByDevice.equals(device),
          )
          ..orderBy([(r) => OrderingTerm.asc(r.createdAt)]))
        .get();
  }

  // ---- outcomes ------------------------------------------------------------

  /// How a finished save reads as a resolution. `failed` carries the run's own
  /// named stop condition and nothing invented: an unnamed failure reports an
  /// empty reason rather than a guess.
  (DownloadRequestState, String) _outcomeOf(SaveTask task) =>
      switch (task.state) {
        SaveTaskState.completed => (DownloadRequestState.completed, ''),
        SaveTaskState.cancelled => (DownloadRequestState.cancelled, ''),
        _ => (DownloadRequestState.failed, task.stopReason?.name ?? ''),
      };

  Future<void> _resolve(
    DownloadRequestRow row,
    DownloadRequestState state,
    _Tally tally, {
    String reason = '',
  }) async {
    final violation = await _requests.resolveLocally(
      row.id,
      to: state,
      failureReason: reason,
    );
    if (violation != null) {
      tally.errors.add('resolve ${row.id}: $violation');
    }
  }

  static final String _refused = StopReason.captureRestrictedForSite.name;

  // ---- what a request points at --------------------------------------------

  /// The Location this device would read [row] at, or null when it cannot.
  ///
  /// The request's `location_id` is a **preference** (V2_SYNC.md §7): honoured
  /// when it still names an active Location of this Entry, and otherwise
  /// replaced by the Entry's own — a Source that retracted an address has said
  /// it no longer serves it, and an Entry with several Locations is read at
  /// the earliest active one.
  Future<LocationRow?> _targetFor(DownloadRequestRow row) async {
    if (await _entries.byId(row.entryId) == null) return null;
    final preferred = row.locationId;
    if (preferred != null) {
      final location = await _entries.locationById(preferred);
      if (location != null &&
          location.entryId == row.entryId &&
          location.lifecycle == LocationLifecycle.active.name) {
        return location;
      }
    }
    final active =
        await (_db.select(_db.locations)
              ..where(
                (l) =>
                    l.entryId.equals(row.entryId) &
                    l.lifecycle.equals(LocationLifecycle.active.name),
              )
              ..orderBy([(l) => OrderingTerm.asc(l.discoveredAt)])
              ..limit(1))
            .get();
    return active.firstOrNull;
  }
}

/// The composition seam: everything a provider needs to build one.
DownloadIntentConsumer createDownloadIntentConsumer(
  LibraryDatabase db,
  SaveQueueRepository queue,
) => DownloadIntentConsumer(queue, db: db);

class _Tally {
  int claimed = 0;
  int lost = 0;
  int skipped = 0;
  int refused = 0;
  int resolved = 0;
  int requeued = 0;
  int stranded = 0;
  final List<String> errors = [];

  DownloadIntentReport report() => DownloadIntentReport(
    claimed: claimed,
    lost: lost,
    skipped: skipped,
    refused: refused,
    resolved: resolved,
    requeued: requeued,
    stranded: stranded,
    errors: errors,
  );
}
