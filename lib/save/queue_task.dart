/// The V2 save queue's unit of work: **one Entry, at one Location** (V2-D15).
///
/// V1's queue scheduled addresses, because in V1 an Entry *was* a URL. Here
/// the two are separate: the task names the Entry it will produce an
/// OfflineCopy for, and the Location that says where to read it from. The
/// address is carried alongside, because a Location a Source retracts must not
/// leave a queued task with nothing to open.
///
/// Everything else about this file is V1's `lib/queue/task_queue.dart`,
/// unchanged in substance:
///
/// * **Five states, and `cancelled` is one of them.** Cancelling preserves the
///   row; only [SaveTaskState.isTerminal] rows can be deleted, and deleting
///   one is *Remove from Activity*, not a sixth state.
/// * **A task never starts itself.** Save is the one kind of work that waits
///   for an explicit Start, and that authorisation is in-memory only — see
///   `queue_repository.dart`.
/// * **Stopping is cooperative.** A cancel writes the row immediately and asks
///   the worker to stop; the worker stops at its next safe boundary.
library;

import 'capture_mode.dart';
import 'stop_conditions.dart';

/// The five states, and nothing else. There is deliberately no `dismissed`:
/// a terminal row is history, history is already bounded and already
/// wholesale-deletable, and a sixth state would only be a history row every
/// reader has to learn to hide.
enum SaveTaskState {
  queued,
  running,
  completed,
  failed,
  cancelled;

  static SaveTaskState fromName(String? name) => SaveTaskState.values
      .firstWhere((s) => s.name == name, orElse: () => SaveTaskState.failed);

  /// Finished, one way or another. The only rows that may be deleted.
  bool get isTerminal =>
      this == SaveTaskState.completed ||
      this == SaveTaskState.failed ||
      this == SaveTaskState.cancelled;

  /// Still the queue's business: waiting or moving.
  bool get isLive => !isTerminal;
}

/// Where the row came from. A `direct` row records a save the user started
/// straight from the Browser and is **only ever terminal**: it created no
/// pending work, so nothing can release it later.
enum SaveTaskOrigin {
  queue,
  direct;

  static SaveTaskOrigin fromName(String? name) => SaveTaskOrigin.values
      .firstWhere((o) => o.name == name, orElse: () => SaveTaskOrigin.queue);
}

/// What a cancel actually did.
///
/// Four outcomes rather than void, ported verbatim from V1: "it had already
/// started" and "it never started" are different things to tell the user, and
/// a tap that lost the race with a claim must not be reported as a clean
/// removal.
enum SaveCancelOutcome {
  /// It was still waiting; it is now a cancelled row and will not run.
  cancelledBeforeStart,

  /// It was already running. The worker has been asked to stop at its next
  /// safe boundary; the row is cancelled from this moment on.
  stoppingRunning,

  /// Already terminal — there was nothing left to cancel.
  alreadyFinished,

  /// No such row: pruned, cleared, or cancelled by something else first.
  gone,
}

/// The outcome text a cancelled-while-waiting row carries.
const kSaveTaskCancelledBeforeStart = 'cancelled before it started';

/// The outcome text a cancelled-while-running row carries. Written the moment
/// the cancel is asked for, not when the worker notices — that is what makes a
/// cancellation survive a kill, because a row left `running` is demoted back
/// to `queued` on the next start.
const kSaveTaskStopping = 'stopping — cancelled by you';

/// One queued (or historical) save.
///
/// A read-only projection of a `save_queue` row. Every transition goes through
/// `SaveQueueRepository`, which is the only thing that may write one.
class SaveTask {
  const SaveTask({
    required this.id,
    required this.entryId,
    required this.locationUrl,
    required this.state,
    required this.origin,
    required this.orderIndex,
    required this.queuedAt,
    this.locationId,
    this.captureMode,
    this.captureModeIsUserSet = false,
    this.outcome,
    this.lastError,
    this.stopReason,
    this.startedAt,
    this.finishedAt,
  });

  final String id;

  /// The Entry this save is for. What an OfflineCopy will be recorded against.
  final String entryId;

  /// The Location it reads from, when the library still lists one.
  final String? locationId;

  /// The address, carried as a value. A retracted Location must not strand a
  /// task that already knows where it was going.
  final String locationUrl;

  /// `CaptureMode`, or **null meaning "decide from the settled page"** — which
  /// is a decision, not the absence of one.
  final CaptureMode? captureMode;
  final bool captureModeIsUserSet;

  final SaveTaskState state;
  final SaveTaskOrigin origin;
  final String? outcome;
  final String? lastError;

  /// Which named condition ended it. "Finished" and "the site stopped us" are
  /// different outcomes and live in different values.
  final StopReason? stopReason;

  final int orderIndex;
  final DateTime queuedAt;
  final DateTime? startedAt;
  final DateTime? finishedAt;

  bool get isTerminal => state.isTerminal;
  bool get isLive => state.isLive;
}
