/// When sync runs, and what stops it (roadmap G5, G6).
///
/// Metadata sync is the app's one automatic network activity (V2-D20). It is
/// **not** an exception to the rule that content automation is explicit — it
/// is a different rule for a different thing: this file fetches no page,
/// drives no browser and stores no content. Everything it can cause is one
/// call to [SyncEngine.syncOnce].
///
/// What it guarantees:
///
/// - **Never two at once.** A run in flight absorbs every trigger that arrives
///   during it into a single follow-up. Ten reorders during one opportunity
///   produce one more opportunity, not ten.
/// - **Nothing while the app is not in front.** [onAppPaused] cancels every
///   timer and drops the absorbed follow-up. An opportunity already in flight
///   finishes — each of its steps is independently kill-safe, so stopping at
///   the next safe point costs nothing and interrupting mid-step would gain
///   nothing.
/// - **Nothing without a transport.** An unconfigured device records
///   `neverConfigured` and does nothing. That is a state, not an error, and it
///   never reaches a screen outside `Settings → Sync`.
/// - **No thundering start.** Launch, resume, reconnect and the periodic tick
///   are jittered. Only a manual *Sync now* runs immediately.
/// - **A failure waits longer each time.** [RetryPolicy], reset by a success,
///   by a reconnect, or by the user asking.
///
/// What it deliberately does not do: promise background execution. No mobile
/// platform offers it, so the scheduler has no opinion about what happens once
/// the app is gone — [onAppPaused] simply stops, and [onAppResumed] picks up.
///
/// **Connectivity.** There is no connectivity plugin, and none is wanted for
/// this: reacting to a dropped connection is the backoff above, and reacting
/// to a regained one is [onConnectivityRegained], which the composition may
/// call from whatever already knows — a failed page load, a platform callback,
/// a resume. Until something calls it, a reconnect is covered by the periodic
/// tick and the retry. Hooking a real platform signal to it is a composition
/// concern and a later one, if ever.
library;

import 'dart:async';
import 'dart:math' as math;

import '../data/data_ids.dart';
import 'retry.dart';
import 'session.dart';
import 'status.dart';
import 'transport.dart';

/// Where a transport comes from, asked each time rather than held.
///
/// Null means this device has none — development without a service, or a
/// build before sign-in exists. Asked afresh so configuration arriving later
/// needs no restart and no second scheduler.
typedef SyncTransportResolver = SyncTransport? Function();

/// Why an opportunity was asked for. Only the delay in front of it differs.
enum SyncTrigger {
  /// The app started.
  launch,

  /// The app came back to the foreground, subject to
  /// [SyncSchedule.minimumResumeInterval].
  resume,

  /// Something that knows told us the network is back.
  connectivity,

  /// A local mutation was journalled. Debounced, so a burst is one push.
  localMutation,

  /// The foreground tick.
  periodic,

  /// The user pressed *Sync now*. The only trigger with no delay, and the only
  /// one that runs whatever the scheduler thinks about the foreground.
  manual,
}

/// The scheduler's timings, in one object so every number is named, visible
/// and overridable by a test.
class SyncSchedule {
  const SyncSchedule({
    this.startJitter = const Duration(seconds: 3),
    this.foregroundInterval = const Duration(minutes: 15),
    this.minimumResumeInterval = const Duration(minutes: 2),
    this.mutationDebounce = const Duration(seconds: 5),
    this.retry = const RetryPolicy(),
  });

  /// Upper bound on the random delay in front of an automatic start. Small
  /// enough that a launch still feels immediate, large enough that a fleet of
  /// devices woken by the same event does not arrive together.
  final Duration startJitter;

  /// How often an idle foreground app takes an opportunity.
  ///
  /// Conservative on purpose. Sync is metadata — a few rows and a cursor — so
  /// the cost of a tick is small, but the cost of a *habit* is not: a reader
  /// left open for an evening should not be a stream of requests. Fifteen
  /// minutes is far below the point where a second device's changes feel late,
  /// and far above the point where anyone would notice the traffic.
  final Duration foregroundInterval;

  /// A resume inside this window of the last opportunity does not take
  /// another. Switching to another app to copy a link and switching back is
  /// not new information.
  final Duration minimumResumeInterval;

  /// How long a journalled mutation waits for its neighbours.
  ///
  /// A *maximum* wait, not a sliding one: the first mutation of a burst fixes
  /// the moment, and later ones join it rather than pushing it out. Renaming
  /// three folders in a row is one push; it can never become a push that keeps
  /// being deferred.
  final Duration mutationDebounce;

  final RetryPolicy retry;
}

/// A pending wake-up.
abstract class SyncAlarm {
  void cancel();
}

/// How the scheduler measures time and arranges to be woken.
///
/// A seam rather than bare [Timer] and [DateTime.now]: every rule in this file
/// is about *when*, and a test that cannot move time can only assert that the
/// code compiles.
abstract class SyncClock {
  DateTime now();

  SyncAlarm after(Duration delay, void Function() action);
}

/// The real one.
class SystemSyncClock implements SyncClock {
  const SystemSyncClock();

  @override
  DateTime now() => utcNow();

  @override
  SyncAlarm after(Duration delay, void Function() action) =>
      _TimerAlarm(Timer(delay, action));
}

class _TimerAlarm implements SyncAlarm {
  _TimerAlarm(this._timer);

  final Timer _timer;

  @override
  void cancel() => _timer.cancel();
}

/// Decides when [SyncEngine.syncOnce] runs, and publishes what Settings shows.
///
/// The composition owns the lifecycle calls. Nothing in this class reaches for
/// a platform signal on its own, and nothing about it is a screen.
class SyncScheduler implements SyncStatusSource {
  /// Named `engine:`, `transport:`, `schedule:`, `clock:` and `random:` at the
  /// call site — the fields stay private because nothing outside this class
  /// may reach the engine directly and bypass the single-flight rule.
  SyncScheduler({
    required this._engine,
    required this._transport,
    this._schedule = const SyncSchedule(),
    this._clock = const SystemSyncClock(),
    math.Random? random,
  }) : _random = random ?? math.Random() {
    _status = SyncStatusView.initial(configured: _transport() != null);
  }

  final SyncEngine _engine;
  final SyncTransportResolver _transport;
  final SyncSchedule _schedule;
  final SyncClock _clock;
  final math.Random _random;

  final StreamController<SyncStatusView> _statuses =
      StreamController<SyncStatusView>.broadcast();

  late SyncStatusView _status;
  SyncStatus? _snapshot;

  bool _disposed = false;

  /// Whether an opportunity is inside [SyncEngine.syncOnce] right now. Drives
  /// the `syncing` phase and nothing else.
  bool _running = false;

  /// Whether the app is in front. False until the composition says otherwise:
  /// a scheduler that assumed it was would run before anything told it to.
  bool _foreground = false;

  /// The opportunity in flight, including its bookkeeping tail.
  Future<void>? _active;

  /// One absorbed follow-up. A boolean, not a queue — the whole point is that
  /// a hundred triggers during a run are still one more run.
  bool _pending = false;

  int _failures = 0;
  DateTime? _nextRetryAt;
  DateTime? _lastOpportunityAt;

  DateTime? _wakeAt;
  SyncAlarm? _wakeAlarm;
  SyncAlarm? _tickAlarm;

  /// Callers of [syncNow] waiting for an opportunity that has not started yet.
  final List<Completer<void>> _waiting = <Completer<void>>[];

  // ─── what Settings reads ──────────────────────────────────────────────────

  @override
  SyncStatusView get status => _status;

  @override
  Stream<SyncStatusView> get statusChanges => _statuses.stream;

  @override
  Future<void> refreshStatus() async {
    final snapshot = await _engine.status();
    if (_disposed) return;
    _snapshot = snapshot;
    _publish();
  }

  // ─── the hooks the composition calls ──────────────────────────────────────

  /// The app started and is in front.
  void onAppLaunch() {
    if (_disposed) return;
    _foreground = true;
    _startTicking();
    _request(SyncTrigger.launch);
    unawaited(refreshStatus());
  }

  /// The app came back to the foreground.
  void onAppResumed() {
    if (_disposed) return;
    _foreground = true;
    _startTicking();
    final last = _lastOpportunityAt;
    if (last != null &&
        _clock.now().difference(last) < _schedule.minimumResumeInterval) {
      // Too soon to be worth anything. The tick still covers this session.
      return;
    }
    _request(SyncTrigger.resume);
  }

  /// The app left the foreground. Nothing new starts until it comes back.
  void onAppPaused() {
    if (_disposed) return;
    _foreground = false;
    _pending = false;
    _cancelWake();
    _tickAlarm?.cancel();
    _tickAlarm = null;
  }

  /// Something that knows says the network is back.
  void onConnectivityRegained() {
    if (_disposed) return;
    _request(SyncTrigger.connectivity);
  }

  /// One local mutation was journalled. Safe to call on every outbox append —
  /// it is a boolean and a timer, never a query.
  void onLocalMutation() {
    if (_disposed) return;
    _request(SyncTrigger.localMutation);
  }

  /// The user pressed *Sync now*.
  ///
  /// Completes when the opportunity this call asked for has finished — never
  /// when a run that was already going finishes, so the button's disabled
  /// state matches the work the user asked for.
  @override
  Future<void> syncNow() {
    if (_disposed) return Future<void>.value();
    final waiter = Completer<void>();
    _waiting.add(waiter);
    _request(SyncTrigger.manual);
    return waiter.future;
  }

  /// Completes when nothing is in flight. For tests and for an orderly
  /// shutdown; the app itself never waits for sync.
  Future<void> whenIdle() async {
    while (_active != null) {
      await _active;
    }
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _cancelWake();
    _tickAlarm?.cancel();
    _tickAlarm = null;
    _pending = false;
    for (final waiter in _claimWaiting()) {
      if (!waiter.isCompleted) waiter.complete();
    }
    unawaited(_statuses.close());
  }

  // ─── scheduling ───────────────────────────────────────────────────────────

  void _request(SyncTrigger trigger) {
    // Manual is the one trigger that does not ask whether the app is in front:
    // it exists because a person pressed a button, which is the strongest
    // evidence of a foreground there is.
    if (trigger != SyncTrigger.manual && !_foreground) return;

    // Asking on purpose, or learning the network is back, clears the wait. A
    // backoff exists to stop the app hammering a service that is not there,
    // never to make a user wait for something they asked for.
    if (trigger == SyncTrigger.manual || trigger == SyncTrigger.connectivity) {
      _failures = 0;
      _nextRetryAt = null;
      _publish();
    }

    if (_active != null) {
      _pending = true;
      return;
    }
    _wakeNoLaterThan(_clock.now().add(_delayFor(trigger)));
  }

  Duration _delayFor(SyncTrigger trigger) => switch (trigger) {
    SyncTrigger.manual => Duration.zero,
    SyncTrigger.localMutation => _schedule.mutationDebounce,
    SyncTrigger.launch ||
    SyncTrigger.resume ||
    SyncTrigger.connectivity ||
    SyncTrigger.periodic => _jitter(),
  };

  Duration _jitter() => Duration(
    microseconds: _random.nextInt(
      math.max(1, _schedule.startJitter.inMicroseconds),
    ),
  );

  /// Arms the single wake-up, never later than [at] and never before a
  /// backoff the scheduler is still serving.
  ///
  /// One alarm for every reason to wake, so a debounce and a retry cannot
  /// fight over a field. The retry time is a floor rather than a candidate:
  /// otherwise a local mutation would walk straight through the backoff and
  /// hammer a service that has just failed.
  void _wakeNoLaterThan(DateTime at) {
    if (_disposed) return;
    final floor = _nextRetryAt;
    final target = floor != null && at.isBefore(floor) ? floor : at;
    final held = _wakeAt;
    if (held != null && !held.isAfter(target)) return;
    _wakeAlarm?.cancel();
    _wakeAt = target;
    final delay = target.difference(_clock.now());
    _wakeAlarm = _clock.after(
      delay.isNegative ? Duration.zero : delay,
      _onWake,
    );
  }

  void _cancelWake() {
    _wakeAlarm?.cancel();
    _wakeAlarm = null;
    _wakeAt = null;
  }

  void _onWake() {
    _wakeAlarm = null;
    _wakeAt = null;
    if (_disposed) return;
    _begin();
  }

  void _startTicking() {
    _tickAlarm?.cancel();
    _tickAlarm = _clock.after(_schedule.foregroundInterval, _onTick);
  }

  void _onTick() {
    _tickAlarm = null;
    if (_disposed || !_foreground) return;
    // Re-arm first: an opportunity that fails must not take the tick with it.
    _startTicking();
    _request(SyncTrigger.periodic);
  }

  void _begin() {
    if (_disposed || _active != null) return;
    // Manual callers are already waiting; nothing else needs a foreground
    // check here, because _request refused every non-manual trigger without
    // one and onAppPaused cancelled the alarm that would have got us here.
    _active = _pump()
      ..whenComplete(() {
        _active = null;
      });
  }

  /// One opportunity, then at most one absorbed follow-up.
  ///
  /// The bound is deliberate. Without it a steady trickle of local mutations
  /// during long runs could keep the loop turning indefinitely; with it, work
  /// that arrives after the follow-up goes back through the ordinary wake
  /// path, where the debounce and the backoff apply.
  Future<void> _pump() async {
    var followUps = 0;
    while (true) {
      await _opportunity();
      if (_disposed || !_pending) return;
      _pending = false;
      if (!_foreground) return;
      followUps += 1;
      final floor = _nextRetryAt;
      if (followUps > 1 || (floor != null && _clock.now().isBefore(floor))) {
        // Back through the ordinary wake path, which is the only place a
        // delay is applied: the debounce here, and the backoff floor inside
        // _wakeNoLaterThan. Waking at *now* would be the loop again, wearing
        // a timer.
        _wakeNoLaterThan(_clock.now().add(_schedule.mutationDebounce));
        return;
      }
    }
  }

  Future<void> _opportunity() async {
    // Claimed before anything is awaited: a *Sync now* pressed during this
    // opportunity belongs to the next one, not this one.
    final waiting = _claimWaiting();
    try {
      final transport = _transport();
      if (transport == null) {
        // Nothing to reach. Recorded as a state, never surfaced as an error,
        // and never retried — there is nothing to retry against.
        _publish();
        return;
      }
      _lastOpportunityAt = _clock.now();
      _running = true;
      _publish();

      SyncOutcome? outcome;
      try {
        outcome = await _engine.syncOnce(transport);
      } on Object {
        // syncOnce turns a transport failure into an outcome. Anything that
        // still escapes is a defect, and a defect must not take the scheduler
        // down with it — it counts as a failed opportunity like any other.
        outcome = null;
      }
      if (_disposed) return;

      if (outcome != null && outcome.succeeded) {
        _failures = 0;
        _nextRetryAt = null;
      } else {
        _failures += 1;
        _nextRetryAt = _clock.now().add(
          _schedule.retry.delayAfter(_failures, _random.nextDouble()),
        );
        if (_foreground) _wakeNoLaterThan(_nextRetryAt!);
      }
      _running = false;
      // One read of the snapshot per opportunity, at its end: the pending and
      // rejected counts are the engine's to state, and this is the moment both
      // have just changed.
      await refreshStatus();
    } finally {
      _running = false;
      _publish();
      for (final waiter in waiting) {
        if (!waiter.isCompleted) waiter.complete();
      }
    }
  }

  List<Completer<void>> _claimWaiting() {
    final claimed = List<Completer<void>>.of(_waiting);
    _waiting.clear();
    return claimed;
  }

  void _publish() {
    if (_disposed) return;
    final view = deriveSyncStatus(
      snapshot: _snapshot,
      configured: _transport() != null,
      running: _running,
      nextRetryAt: _nextRetryAt,
    );
    if (view == _status) return;
    _status = view;
    if (!_statuses.isClosed) _statuses.add(view);
  }
}
