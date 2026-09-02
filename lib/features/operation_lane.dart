/// The one lane everything that drives the Browser runs in.
///
/// **Why this file exists.** There is exactly one WebView, and two operations
/// navigating it at once corrupt both. `BrowserController.automationOwner`
/// says who holds it, and the Collection check refuses to start while
/// somebody else does — but a *refusal* throws away a request the user made
/// for a perfectly reasonable reason, and each start surface only ever knew
/// about its own kind of work. A download run and a check could therefore be
/// started against the same WebView from two different screens, and a second
/// download start reported "Starting 3 downloads" over a run that was already
/// going.
///
/// So the rule is not *refuse the second*, it is **queue the second, and say
/// so**. This class is the whole of that: one active operation, a FIFO of the
/// requests waiting behind it, and a callback that fires the moment a request
/// has to wait so the surface can tell the user in their own words.
///
/// Four things it deliberately is not:
///
/// * **Not an authorisation.** Like the queue's own Start it lives in memory
///   and a relaunch has none. Submitting work here does not make it allowed;
///   the sheet that asked already did that.
/// * **Not a scheduler.** Nothing is retried, delayed or run on its behalf. A
///   submitted request runs exactly once, when its turn comes.
/// * **Not the durable queue.** Downloads are rows in `save_queue` and stay
///   the authority for what is waiting; the lane only decides *when the
///   worker runs*.
/// * **Not a second stop.** Stopping an operation is the operation's own —
///   the lane simply moves on to whatever is next.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A request waiting for the lane.
class _Waiting {
  _Waiting(this.key, this.label) : gate = Completer<void>();

  final String key;
  final String label;
  final Completer<void> gate;
}

/// One operation at a time, in the order they were asked for.
class OperationLane extends ChangeNotifier {
  String? _activeKey;
  String? _activeLabel;
  final List<_Waiting> _waiting = [];

  /// True while something holds the lane.
  bool get isBusy => _activeKey != null;

  /// What holds it, as a noun phrase a sentence can be built from — `a
  /// download`, `a check`. Null when the lane is free.
  String? get activeLabel => _activeLabel;

  /// How many requests are waiting their turn.
  int get waiting => _waiting.length;

  /// What is waiting, in the order it will run, as the same noun phrases
  /// [activeLabel] uses. So a panel can say *a check is waiting for this to
  /// finish* rather than only counting.
  List<String> get waitingLabels => [
    for (final request in _waiting) request.label,
  ];

  /// Whether [key] is the operation running now, or one already waiting.
  ///
  /// The one thing a caller has to ask *before* submitting: a second tap on
  /// the same control is a duplicate, not a second request, and stacking it
  /// would run the same operation twice.
  bool holds(String key) =>
      _activeKey == key || _waiting.any((request) => request.key == key);

  /// Run [body] in the lane.
  ///
  /// Runs straight away when the lane is free. Otherwise the request joins the
  /// back of the queue and [whenQueued] is called with what is running now, so
  /// the surface can say *that is already going, this is queued* before it
  /// returns to the user. The future completes with [body]'s value once the
  /// turn comes and the work is done.
  ///
  /// [key] identifies the *kind* of work, so [holds] can recognise a
  /// duplicate. [label] is how this work is named in somebody else's sentence.
  Future<T> submit<T>({
    required String key,
    required String label,
    required Future<T> Function() body,
    void Function(String activeLabel)? whenQueued,
  }) async {
    if (_activeKey == null) {
      _activeKey = key;
      _activeLabel = label;
      notifyListeners();
    } else {
      final request = _Waiting(key, label);
      _waiting.add(request);
      whenQueued?.call(_activeLabel!);
      notifyListeners();
      // The gate is completed by [_release] *after* it has made this request
      // the active one, so there is no frame in which the lane looks free.
      await request.gate.future;
    }
    try {
      return await body();
    } finally {
      _release();
    }
  }

  /// Hand the lane to whatever is next, or leave it free.
  void _release() {
    if (_waiting.isEmpty) {
      _activeKey = null;
      _activeLabel = null;
      notifyListeners();
      return;
    }
    final next = _waiting.removeAt(0);
    _activeKey = next.key;
    _activeLabel = next.label;
    notifyListeners();
    next.gate.complete();
  }
}

/// How a queued request is announced, in one sentence.
///
/// Built here rather than typed at each call site so every surface says the
/// same two things in the same order: what is already running, and that this
/// request was kept.
String queuedBehindSentence({
  required String active,
  required String request,
}) =>
    '${active[0].toUpperCase()}${active.substring(1)} is already running — '
    '$request has been added to the queue and starts when it finishes.';

/// What is waiting behind the operation on screen, in one line — or null when
/// nothing is.
///
/// Said from the point of view of the thing running: the panel already names
/// *that*, so this only has to answer "and then what". One waiting request is
/// named; several are counted, because a strip across the bottom of a phone is
/// not a list.
String? waitingBehindSentence(List<String> waiting) => switch (waiting.length) {
  0 => null,
  1 =>
    '${waiting.single[0].toUpperCase()}${waiting.single.substring(1)} is '
        'waiting for this to finish.',
  final n => '$n more requests are waiting for this to finish.',
};

/// What the lane calls a download run.
const String kDownloadWorkLabel = 'a download';

/// What the lane calls a check, of one Collection or of all of them.
const String kCheckWorkLabel = 'a check';

/// The lane key every download run shares. There is one download pipeline —
/// the `save_queue` rows and the worker that drains them — so a second
/// request is never a second run.
const String kDownloadWorkKey = 'downloads';

/// The lane key of the library-wide check.
const String kLibraryCheckWorkKey = 'check:library';

/// The lane key of a check of one Collection.
String collectionCheckWorkKey(String collectionId) => 'check:$collectionId';

/// The lane, shared by everything that drives the Browser.
final operationLaneProvider = Provider<OperationLane>((ref) {
  final lane = OperationLane();
  ref.onDispose(lane.dispose);
  return lane;
});
