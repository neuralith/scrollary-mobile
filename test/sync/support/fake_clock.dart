/// A [SyncClock] the test drives by hand (roadmap G5/G6).
///
/// Every rule in `lib/sync/scheduler.dart` is about *when*, so a test that
/// cannot move time can only assert that the code compiles. This clock fires
/// alarms in order, lets each one's asynchronous work finish before the next,
/// and — the part that matters most — can be asked what is still armed, so a
/// timer the scheduler forgot to cancel is a failing assertion rather than a
/// battery complaint six months later.
library;

import 'package:web_reader/sync/scheduler.dart';

class FakeSyncClock implements SyncClock {
  FakeSyncClock([DateTime? start])
    : _now = start ?? DateTime.utc(2026, 8, 21, 10);

  DateTime _now;
  final List<_FakeAlarm> _alarms = <_FakeAlarm>[];

  /// When the most recent alarm fired. The moment a scheduler arms its next
  /// wake-up is the moment one fired, so this is what a delay is measured
  /// against — `nextDelay` alone would be short by however far the test
  /// advanced past the firing.
  DateTime? lastFiredAt;

  @override
  DateTime now() => _now;

  @override
  SyncAlarm after(Duration delay, void Function() action) {
    final alarm = _FakeAlarm(
      _now.add(delay.isNegative ? Duration.zero : delay),
      action,
      _alarms,
    );
    _alarms.add(alarm);
    return alarm;
  }

  /// How many wake-ups are armed. Zero after a clean dispose.
  int get pendingAlarms => _alarms.length;

  /// How far away each armed wake-up is, for asserting jitter and debounce
  /// bounds without depending on which alarm is which.
  List<Duration> get pendingDelays => [
    for (final alarm in _alarms) alarm.at.difference(_now),
  ];

  /// The nearest armed wake-up, or null.
  Duration? get nextDelay {
    final delays = pendingDelays..sort();
    return delays.isEmpty ? null : delays.first;
  }

  /// Moves time forward to `now + by`, firing every alarm it passes in order.
  ///
  /// [settle] runs after each firing and once at the end. Pass the scheduler's
  /// `whenIdle`: an alarm starts an opportunity, and the alarm the opportunity
  /// arms afterwards must exist before the loop looks for the next one.
  Future<void> advance(Duration by, {Future<void> Function()? settle}) async {
    final target = _now.add(by);
    while (true) {
      final due = [
        for (final alarm in _alarms)
          if (!alarm.at.isAfter(target)) alarm,
      ]..sort((a, b) => a.at.compareTo(b.at));
      if (due.isEmpty) break;
      final next = due.first;
      _alarms.remove(next);
      _now = next.at;
      lastFiredAt = next.at;
      next.action();
      if (settle != null) await settle();
    }
    _now = target;
    if (settle != null) await settle();
  }
}

class _FakeAlarm implements SyncAlarm {
  _FakeAlarm(this.at, this.action, this._owner);

  final DateTime at;
  final void Function() action;
  final List<_FakeAlarm> _owner;

  @override
  void cancel() => _owner.remove(this);
}
