import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart';

import '../core/config.dart';
import '../core/device_storage.dart';
import '../data/schema.dart';
import '../save/entry_capture.dart';
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
    });

/// The default: capture the row exactly as it stands, asking nothing.
Future<EntryCaptureResult> captureTaskDirectly(
  EntryCaptureService capture,
  SaveTask task, {
  bool Function()? shouldContinue,
}) => capture.capture(
  entryId: task.entryId,
  locationId: task.locationId,
  locationUrl: task.locationUrl,
  captureMode: task.captureMode,
  captureModeIsUserSet: task.captureModeIsUserSet,
  shouldContinue: shouldContinue,
);

/// Drives the V2 save queue: claims eligible rows one at a time and runs each
/// through [EntryCaptureService].
///
/// The queue rows stay the authority for everything durable — claim, cancel
/// and outcome all live there (`queue_repository.dart` owns the single-winner
/// property). This class is only the worker loop and the app-level signal
/// that a save is running, which the shell reads to keep the Browser painted
/// exactly as it did for V1 runs.
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
  String? _activeTaskId;
  int _batchTotal = 0;
  int _batchDone = 0;

  /// True while the loop is claiming or capturing.
  bool get isRunning => _running;

  /// How many rows this batch set out to capture.
  ///
  /// Taken when the loop starts and raised if more work appears while it runs,
  /// because a batch is what the queue holds rather than a number promised in
  /// advance. Zero when nothing is running.
  int get batchTotal => _batchTotal;

  /// How many of them have reached a terminal state, however they got there.
  int get batchDone => _batchDone;

  /// The 1-based position of the row being captured — the *3* in "entry 3 of
  /// 10". Zero when nothing is running.
  int get batchPosition => _running ? _batchDone + 1 : 0;

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
    _batchTotal = 0;
    _batchDone = 0;
    notifyListeners();
    queue.authoriseStart();
    try {
      while (!_disposed) {
        final eligible = await queue.eligible();
        if (eligible.isEmpty) break;
        // What is left, plus what has already been settled, is what this batch
        // is trying to do. Recomputed each pass so a row enqueued mid-batch is
        // counted rather than making the total a promise that goes stale.
        final total = _batchDone + eligible.length;
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
        _batchDone++;
        if (!_disposed) notifyListeners();
      }
    } finally {
      queue.revokeStart();
      _activeTaskId = null;
      _running = false;
      if (!_disposed) notifyListeners();
    }
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

  Future<void> _run(SaveTask task) async {
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
