import 'dart:async';

import 'package:flutter/foundation.dart';

import '../save/entry_capture.dart';
import 'queue_repository.dart';
import 'queue_task.dart';
import 'stop_conditions.dart';

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
  });

  final SaveQueueRepository queue;
  final EntryCaptureService Function() _captureServiceFor;
  final Duration _cancelPoll;

  bool _running = false;
  bool _disposed = false;
  String? _activeTaskId;

  /// True while the loop is claiming or capturing.
  bool get isRunning => _running;

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
    notifyListeners();
    queue.authoriseStart();
    try {
      while (!_disposed) {
        final eligible = await queue.eligible();
        if (eligible.isEmpty) break;
        final claimed = await queue.claim(eligible.first.id);
        // Lost to a cancel that got there first: skip and carry on — the
        // loser is told, and the row keeps its own verdict.
        if (claimed == null) continue;
        await _run(claimed);
      }
    } finally {
      queue.revokeStart();
      _activeTaskId = null;
      _running = false;
      if (!_disposed) notifyListeners();
    }
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
      final result = await _captureServiceFor().capture(
        entryId: task.entryId,
        locationId: task.locationId,
        locationUrl: task.locationUrl,
        captureMode: task.captureMode,
        captureModeIsUserSet: task.captureModeIsUserSet,
        shouldContinue: () => !cancelled && !_disposed,
      );
      switch (result.status) {
        case EntryCaptureStatus.captured:
          await queue.finish(
            task.id,
            state: SaveTaskState.completed,
            outcome: result.contentPath,
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
