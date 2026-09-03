import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart';

import '../core/config.dart';
import '../core/device_storage.dart';
import '../data/schema.dart';
import '../save/entry_capture.dart';
import 'capture_journey.dart';
import 'queue_repository.dart';
import 'queue_task.dart';
import 'stop_conditions.dart';

/// How one claimed row is captured.
///
/// The loop owns the row — the claim, the cooperative stop and the terminal
/// verdict — and nothing else. Whether a capture may *ask the user* to point
/// at the reading area is a composition decision, not a queue rule, so it is
/// injected: the app passes the assist-aware capture, and the default is the
/// bare call the queue's own tests drive.
typedef TaskCapture =
    Future<EntryCaptureResult> Function(
      EntryCaptureService capture,
      SaveTask task, {
      bool Function()? shouldContinue,
      bool pageAlreadyLoaded,
    });

/// The default: capture the row exactly as it stands, asking nothing.
Future<EntryCaptureResult> captureTaskDirectly(
  EntryCaptureService capture,
  SaveTask task, {
  bool Function()? shouldContinue,
  bool pageAlreadyLoaded = false,
}) => capture.capture(
  entryId: task.entryId,
  locationId: task.locationId,
  locationUrl: task.locationUrl,
  captureMode: task.captureMode,
  captureModeIsUserSet: task.captureModeIsUserSet,
  shouldContinue: shouldContinue,
  pageAlreadyLoaded: pageAlreadyLoaded,
);

/// What a finished batch came to.
///
/// Kept because a snackbar is not an answer to "did my ten entries download".
/// It lives on the runner rather than in a table: the queue rows are already
/// the durable record of each entry, and this is the one sentence about the
/// batch they belonged to. It survives navigation, and it is replaced by the
/// next run rather than accumulating.
class RunSummary {
  const RunSummary({
    required this.requested,
    required this.downloaded,
    required this.failed,
    required this.cancelled,
    required this.stoppedEarly,
    this.endNote,
  });

  /// What the batch set out to capture.
  final int requested;
  final int downloaded;
  final int failed;
  final int cancelled;

  /// True when the loop ended with work still eligible — the disk gate, or a
  /// stop. "Finished" and "stopped short" are different outcomes.
  final bool stoppedEarly;

  /// Why a sequential capture of a Source ended before its count, in the
  /// user's words ([CaptureJourney.endNote]). Null for an ordinary drain of
  /// the queue, and null for a journey that simply reached the number asked
  /// for: *there were only sixteen* is an answer about the Source, and it is
  /// the one thing the row counts cannot say for themselves.
  final String? endNote;

  int get settled => downloaded + failed + cancelled;

  /// Whether anything about this run needs a person.
  bool get needsAttention => failed > 0 || stoppedEarly;
}

/// Drives the V2 save queue: claims eligible rows one at a time and runs each
/// through [EntryCaptureService].
///
/// The queue rows stay the authority for everything durable — claim, cancel
/// and outcome all live there (`queue_repository.dart` owns the single-winner
/// property). This class is only the worker loop and the app-level signal
/// that a save is running, which the shell reads to keep the Browser painted
/// exactly as it did for V1 runs.
///
/// A run has two halves and they run in that order. First the
/// [CaptureJourney]s this Start authorised — *capture the next twenty from
/// here*, which writes one row, captures it, finds the entry after it and
/// captures that (V2-D56). Then the ordinary drain of whatever else is
/// waiting. Both go through the same claim and the same verdict, because a
/// download that arrived by walking a Source is not a different kind of
/// download.
class QueueRunner extends ChangeNotifier {
  QueueRunner({
    required this.queue,
    required this._captureServiceFor,
    this._cancelPoll = const Duration(milliseconds: 400),
    DeviceStorage? deviceStorage,
    TaskCapture? capture,
    this.config = kDefaultSaveConfig,
  }) : _deviceStorage = deviceStorage ?? DeviceStorage(),
       _capture = capture ?? captureTaskDirectly;

  final SaveQueueRepository queue;
  final EntryCaptureService Function() _captureServiceFor;
  final TaskCapture _capture;
  final Duration _cancelPoll;
  final DeviceStorage _deviceStorage;

  /// Where the free-space floor comes from. The same [SaveConfig] the engine
  /// is built with, so the two cannot drift apart.
  final SaveConfig config;

  bool _running = false;
  bool _disposed = false;

  /// True from the moment a stop is honoured until the run ends.
  ///
  /// A user's Stop is about the **operation**, not about the row that happened
  /// to be running when they pressed it. That distinction did not exist while
  /// a run was only ever a list of rows; a sequential capture is one bounded
  /// thing the user asked for, so stopping it stops the traversal, the rows
  /// after it and the rest of the drain (V2-D56).
  bool _stopped = false;
  String? _activeTaskId;

  /// The journeys waiting for a Start, in the order they were asked for.
  final List<CaptureJourney> _journeys = [];

  /// What the journeys of this run promised between them, which is the number
  /// the user typed rather than the length of a queue that only ever holds the
  /// step being taken.
  int _bound = 0;
  String? _endNote;
  int _batchTotal = 0;
  int _batchDone = 0;
  int _batchDownloaded = 0;
  int _batchFailed = 0;
  int _batchCancelled = 0;
  RunSummary? _lastRun;

  /// True while the loop is claiming or capturing.
  bool get isRunning => _running;

  /// How many entries this batch set out to capture.
  ///
  /// A journey's own count when there is one — the number the user typed,
  /// known from the first entry rather than derived from a queue that holds
  /// one step at a time. Otherwise what the queue holds, raised if more work
  /// appears while the loop runs. Zero when nothing is running.
  int get batchTotal => _batchTotal;

  /// How many of them have reached a terminal state, however they got there.
  int get batchDone => _batchDone;

  /// The 1-based position of the row being captured — the *3* in "entry 3 of
  /// 10". Zero when nothing is running.
  int get batchPosition => _running ? _batchDone + 1 : 0;

  /// The last finished batch, or null before the first one. Cleared by the
  /// next [start].
  RunSummary? get lastRun => _lastRun;

  /// Forget the last run's summary — the user has read it.
  void clearLastRun() {
    if (_lastRun == null) return;
    _lastRun = null;
    notifyListeners();
  }

  /// Take this journey on the next [start].
  ///
  /// The flow that asked for *capture the next N* hands the journey over here
  /// and the user's Start runs it — so *Queue only* is a complete answer that
  /// starts nothing, and *Start now* is one authorisation that runs the whole
  /// operation. Nothing about holding a journey authorises anything: like the
  /// queue's own Start it is in memory only, and a relaunch has none.
  void follow(CaptureJourney journey) {
    if (_disposed) return;
    _journeys.add(journey);
    notifyListeners();
  }

  /// How many Entries the journeys waiting for a Start have between them.
  int get pendingJourneyEntries =>
      _journeys.fold(0, (n, journey) => n + journey.requested);

  /// One more journey's worth of entries this run has taken on. The batch is
  /// never smaller than what the journeys promised, whichever pass they were
  /// taken on.
  void _raiseBound(int by) {
    _bound += by;
    if (_bound <= _batchTotal) return;
    _batchTotal = _bound;
    if (!_disposed) notifyListeners();
  }

  /// Test hook, mirroring the V1 controller's: the shell's surface and leave
  /// gates are exercised without driving a real capture.
  @visibleForTesting
  void debugSetRunning(bool value) {
    _running = value;
    notifyListeners();
  }

  /// The row being worked on, for surfaces that want to name it.
  String? get activeTaskId => _activeTaskId;

  /// Capture drives the Browser for its whole read phase; the shell keeps the
  /// surface painted for as long as the loop runs.
  bool get needsRenderedBrowser => _running;

  /// Start draining. The explicit user Start this represents is what
  /// authorises queued work — authorisation is never persisted.
  Future<void> start() async {
    if (_running || _disposed) return;
    _running = true;
    _stopped = false;
    _batchDone = 0;
    _batchDownloaded = 0;
    _batchFailed = 0;
    _batchCancelled = 0;
    _lastRun = null;
    _endNote = null;
    _bound = 0;
    _batchTotal = 0;
    notifyListeners();
    queue.authoriseStart();
    try {
      while (!_disposed && !_stopped) {
        // A sequential capture first, and re-asked every pass: one started
        // while this run is going belongs to this run, exactly as a row
        // enqueued mid-batch does.
        if (_journeys.isNotEmpty) {
          final journey = _journeys.removeAt(0);
          _raiseBound(journey.requested);
          await journey.run(
            capture: _captureRow,
            shouldContinue: () => !_disposed && !_stopped,
          );
          _endNote ??= journey.endNote;
          continue;
        }
        final eligible = await queue.eligible();
        if (eligible.isEmpty) break;
        // What is left, plus what has already been settled, is what this batch
        // is trying to do — never less than what the journeys promised.
        // Recomputed each pass so a row enqueued mid-batch is counted rather
        // than making the total a promise that goes stale.
        final drained = _batchDone + eligible.length;
        final total = drained > _bound ? drained : _bound;
        if (total != _batchTotal) {
          _batchTotal = total;
          if (!_disposed) notifyListeners();
        }
        // The disk gate, asked once per row rather than once per batch: free
        // space is a moving figure, and a batch that checked only at the start
        // would fill the device on its fourth entry. Carried over from V1's
        // run, which is the only place it lived.
        //
        // Asked **before** the claim, and settled the way a restricted row is
        // settled — `queued` straight to `failed`. Claiming first would stamp
        // `startedAt` on a capture that never started, and a row that says it
        // began is a row a reader has to be told to distrust.
        if (await _settleIfOutOfSpace(eligible.first)) break;

        final claimed = await queue.claim(eligible.first.id);
        // Lost to a cancel that got there first: skip and carry on — the
        // loser is told, and the row keeps its own verdict.
        if (claimed == null) continue;
        await _run(claimed);
        await _settleVerdict(claimed.id);
      }
    } finally {
      queue.revokeStart();
      _activeTaskId = null;
      _running = false;
      _bound = 0;
      if (_batchTotal > 0) {
        _lastRun = RunSummary(
          requested: _batchTotal,
          downloaded: _batchDownloaded,
          failed: _batchFailed,
          cancelled: _batchCancelled,
          stoppedEarly: _batchDone < _batchTotal,
          endNote: _endNote,
        );
      }
      if (!_disposed) notifyListeners();
    }
  }

  /// Capture one row a journey has just written, in the loop that owns the
  /// queue. [CaptureJourney] decides *which* Entry; everything about running
  /// it — the disk gate, the claim, the cooperative stop and the terminal
  /// verdict — stays here, so a journeyed download and a drained one are the
  /// same download.
  ///
  /// False means the journey goes no further: the run is over, the device is
  /// out of room, or the user stopped this row — which stops the operation it
  /// belonged to rather than only the page it was on.
  Future<bool> _captureRow(
    String taskId, {
    required bool pageAlreadyLoaded,
  }) async {
    if (_disposed || _stopped) return false;
    final row = await queue.byId(taskId);
    if (row == null || row.isTerminal) return false;
    if (await _settleIfOutOfSpace(row)) {
      _stopped = true;
      return false;
    }
    final claimed = await queue.claim(taskId);
    // Lost to a cancel that got there first: the row keeps its own verdict,
    // and the journey it belonged to is over.
    if (claimed == null) return false;
    await _run(claimed, pageAlreadyLoaded: pageAlreadyLoaded);
    final verdict = await _settleVerdict(claimed.id);
    if (verdict == SaveTaskState.cancelled) _stopped = true;
    return !_disposed && !_stopped;
  }

  /// The row's own verdict, read back rather than inferred: a cancel that
  /// landed mid-capture is the row's answer, not the loop's.
  Future<SaveTaskState?> _settleVerdict(String taskId) async {
    _batchDone++;
    final state = (await queue.byId(taskId))?.state;
    switch (state) {
      case SaveTaskState.completed:
        _batchDownloaded++;
      case SaveTaskState.cancelled:
        _batchCancelled++;
      case SaveTaskState.failed:
        _batchFailed++;
      case _:
        break;
    }
    if (!_disposed) notifyListeners();
    return state;
  }

  /// Too little room to take another entry? Then say so on the row that would
  /// have run, and stop.
  ///
  /// **A platform that will not answer is not a refusal.** `freeBytes` returns
  /// null when it cannot say, and treating that as zero would stop every save
  /// on a device whose channel is missing — so unknown means carry on, exactly
  /// as V1 had it. The engine's own guards still apply below this.
  ///
  /// The rows behind this one stay **queued**, not failed: nothing about them
  /// is wrong, and freeing space is all it takes to start them again.
  Future<bool> _settleIfOutOfSpace(SaveTask next) async {
    final free = await _deviceStorage.freeBytes();
    if (free == null || free >= config.minFreeSpaceToStart) return false;
    await queue.updateIfState(
      id: next.id,
      expected: [SaveTaskState.queued],
      values: SaveQueueCompanion(
        state: Value(SaveTaskState.failed.name),
        // The sentence comes from the reason, never from here: one stop, one
        // wording, wherever it is read.
        outcome: Value(StopReason.insufficientStorage.message),
        lastError: Value(StopReason.insufficientStorage.message),
        stopReason: Value(StopReason.insufficientStorage.name),
        finishedAt: Value(DateTime.now().toUtc()),
      ),
    );
    return true;
  }

  Future<void> _run(SaveTask task, {bool pageAlreadyLoaded = false}) async {
    _activeTaskId = task.id;
    notifyListeners();

    // The cooperative stop: a cancellation is written to the row the moment
    // it is asked for, so the row's state is the one honest answer. Polled on
    // a timer because the capture asks synchronously.
    var cancelled = false;
    final poll = Timer.periodic(_cancelPoll, (_) async {
      final row = await queue.byId(task.id);
      if (row == null || row.state != SaveTaskState.running) cancelled = true;
    });

    try {
      final result = await _capture(
        _captureServiceFor(),
        task,
        shouldContinue: () => !cancelled && !_disposed,
        pageAlreadyLoaded: pageAlreadyLoaded,
      );
      switch (result.status) {
        case EntryCaptureStatus.captured:
          await queue.finish(
            task.id,
            state: SaveTaskState.completed,
            outcome: _capturedSentence(result),
          );
        case EntryCaptureStatus.refused:
          await queue.finish(
            task.id,
            state: SaveTaskState.failed,
            stopReason: StopReason.captureRestrictedForSite,
          );
        case EntryCaptureStatus.failed:
          // A cancel that landed first keeps its own verdict: finish() is
          // conditional on the row still being `running`.
          await queue.finish(
            task.id,
            state: SaveTaskState.failed,
            lastError: result.error,
            stopReason: result.stopReason,
          );
      }
    } catch (e) {
      await queue.finish(task.id, state: SaveTaskState.failed, lastError: '$e');
    } finally {
      poll.cancel();
      // This row is no longer being captured, and the next one is not being
      // captured yet. Held open, the field went on naming the row that had
      // just finished — which for a sequential capture of a Source is the
      // whole page load the walk makes to find the next Entry (V2-D56), so
      // the panel said the app was downloading the previous Entry while the
      // Browser was visibly on its way to another one.
      _activeTaskId = null;
      if (!_disposed) notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

/// What a finished download says for itself in Activity.
///
/// `outcome` is a **sentence column** — every other writer puts words in it —
/// and this one used to put `contentPath` there, so a finished row showed the
/// user a relative store path. The counts come from the manifest the capture
/// just wrote, which is where "saved with gaps" is decided.
String _capturedSentence(EntryCaptureResult result) {
  final manifest = result.manifest;
  if (manifest == null) return 'Downloaded to this device.';
  final detected = manifest.detectedAssetCount;
  final stored = manifest.storedAssetCount;
  if (detected <= 0) return 'Downloaded to this device.';
  // "Finished" and "finished with gaps" are different outcomes and are never
  // folded into one (CLAUDE.md, "The app stops; it never works around").
  return stored >= detected
      ? 'Downloaded to this device · $stored ${_images(stored)}.'
      : 'Downloaded with gaps · $stored of $detected images.';
}

String _images(int n) => n == 1 ? 'image' : 'images';
