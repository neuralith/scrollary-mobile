/// What the entry being captured right now is doing, and the log behind it.
///
/// **Why this file exists.** `SaveEngine` has always published its progress —
/// images detected, images stored, failures, retries, the scroll position, a
/// running log — through two nullable callbacks. The V2 composition built the
/// engine without either, so those lines were not merely unrendered: they were
/// never produced. A ten-entry download showed one indeterminate bar and an
/// entry title, and the counters the engine computed went nowhere.
///
/// This is the other end of those callbacks. It holds the newest reading and a
/// bounded slice of the log, and it is the only thing between the engine and
/// the panel.
///
/// Three rules it carries:
///
/// * **Seeing what the device is doing is never gated.** Nothing here asks
///   what a user has, and nothing above it may
///   (docs/V2_CAPABILITY_PARITY.md).
/// * **The log is not the interface.** It is kept for the moment something
///   goes wrong and someone needs the detail; the routine surface shows counts.
/// * **Bounded, like everything else.** The log keeps its last
///   [kOperationLogLimit] lines. A save that scrolls a long page produces
///   hundreds, and an unbounded buffer on a device is a leak with a nice name.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../save/save_state.dart';

/// How many log lines are kept. Enough to explain one entry's capture.
const int kOperationLogLimit = 300;

/// The live reading, for whoever is drawing it.
class OperationProgress extends ChangeNotifier {
  SaveProgress _progress = const SaveProgress();
  final List<String> _log = <String>[];

  /// The newest reading from the capture engine. Idle between entries.
  SaveProgress get progress => _progress;

  /// The log, oldest first. Never shown by default.
  List<String> get log => List.unmodifiable(_log);

  /// True when there is something worth putting on screen — the engine has
  /// said anything at all about the entry it is on.
  bool get hasReading =>
      _progress.state != SaveState.idle ||
      _progress.detectedImages > 0 ||
      _progress.storedImages > 0;

  /// The engine's own update shape: it hands us a function from the last
  /// reading to the next one, so a phase that only knows about images does not
  /// have to restate the entry it belongs to.
  void apply(SaveProgress Function(SaveProgress) update) {
    _progress = update(_progress);
    notifyListeners();
  }

  void record(String line) {
    _log.add(line);
    if (_log.length > kOperationLogLimit) {
      _log.removeRange(0, _log.length - kOperationLogLimit);
    }
    notifyListeners();
  }

  /// A new entry is starting: the counters belong to it, not to the one
  /// before. The log is kept — it is the thread through the whole batch, and
  /// it is what makes "the third one failed" explainable.
  void beginEntry() {
    _progress = const SaveProgress();
    notifyListeners();
  }

  /// The batch is over. Counters go quiet; the log survives so a completed run
  /// can still be explained.
  void finish() {
    _progress = const SaveProgress();
    notifyListeners();
  }

  /// Forget everything, including the log.
  void clear() {
    _progress = const SaveProgress();
    _log.clear();
    notifyListeners();
  }
}

/// The one store, for the app and for whatever is drawing it.
final operationProgressProvider = Provider<OperationProgress>((ref) {
  final progress = OperationProgress();
  ref.onDispose(progress.dispose);
  return progress;
});
