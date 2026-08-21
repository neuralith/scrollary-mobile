import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

/// How a scenario ended.
enum ScenarioOutcome {
  /// Everything the scenario asserted held.
  passed,

  /// The scenario ran to the end but something it checked was not true.
  failed,

  /// The scenario stopped making progress and the watchdog ended it. This is
  /// **the harness's own verdict**, not the app's, and is reported separately
  /// from `failed` because the two mean completely different things: `failed`
  /// is evidence about the product, `stalled` is evidence about the test.
  stalled,

  /// Preconditions were not met — no live URL, no Entry to read. Not a defect.
  skipped,

  /// An earlier scenario made this one's result meaningless.
  abandoned,
}

/// One scenario's structured result. One of these per scenario, always — a
/// matrix that reports nothing for a scenario that crashed is a matrix that
/// quietly shrinks.
class ScenarioResult {
  ScenarioResult(this.name);

  final String name;
  ScenarioOutcome outcome = ScenarioOutcome.skipped;
  Duration elapsed = Duration.zero;
  String detail = '';

  /// The phase the scenario was in when it ended. The single most useful thing
  /// to know about a stall.
  String lastPhase = '-';

  /// The operation's own last known state, so a harness stall can be told from
  /// an application hold.
  String lastOperationState = '-';
  final List<String> notes = [];

  @override
  String toString() =>
      '[SCN] ${outcome.name.toUpperCase().padRight(9)} '
      '${elapsed.inSeconds.toString().padLeft(4)}s  ${name.padRight(46)} '
      'phase=${lastPhase.padRight(24)} op=$lastOperationState'
      '${detail.isEmpty ? '' : '  :: $detail'}';
}

/// Raised when a bounded wait stops making progress. Carries the phase so the
/// report can say *where*, not just *that*.
class HarnessStall implements Exception {
  HarnessStall(this.phase, this.waited);

  final String phase;
  final Duration waited;

  @override
  String toString() =>
      'stalled in "$phase" after ${waited.inSeconds}s with no progress';
}

/// Runs a matrix of scenarios so that one bad scenario cannot take the run
/// down with it.
///
/// The rule this class exists to enforce: **never wait silently**. Three device
/// runs were lost to a harness sitting inside a generous timeout after a test
/// had already failed, producing nothing for a quarter of an hour. Every wait
/// here is bounded, announces itself, and reports where it was when it gave up.
class DeviceHarness {
  DeviceHarness({required this.fingerprint});

  /// Identifies the source the installed build came from, so a result can
  /// never be attributed to code it did not run.
  final String fingerprint;

  final List<ScenarioResult> results = [];
  ScenarioResult? _current;

  /// Set when a scenario fails in a way that makes later ones meaningless.
  String? _fatal;

  /// The phase currently running, for the heartbeat and for stall reports.
  String phase = '-';

  /// Supplies the operation's own state, so the report can distinguish an
  /// application hold from a harness deadlock.
  String Function()? operationState;

  DateTime _lastHeartbeat = DateTime.now();

  /// Mark the scenario as not-run because a precondition was not met.
  ///
  /// **A scenario that returns early must never report `passed`.** It did not
  /// assert anything, so calling it a pass manufactures evidence — which is the
  /// exact failure this class exists to prevent, and which it committed itself
  /// on its first real run: a six-round soak bailed out on a missing Entry and
  /// was recorded as PASSED.
  void skip(String why) {
    _skipped = why;
    note('skipped — $why');
  }

  String? _skipped;

  void note(String message) {
    _current?.notes.add(message);
    debugPrint('[dev] $message');
  }

  /// Announce where we are. Called from inside every wait, so a long-running
  /// phase is visible as it happens rather than only in hindsight.
  void _heartbeat(String waiting, Duration waited) {
    final now = DateTime.now();
    if (now.difference(_lastHeartbeat) < const Duration(seconds: 5)) return;
    _lastHeartbeat = now;
    debugPrint(
      '[dev] .. ${waited.inSeconds}s in "$waiting" '
      '(op=${operationState?.call() ?? '-'})',
    );
  }

  /// Pump until [done], or give up. Returns whether [done] came true.
  ///
  /// Distinct from `expect`-ing: a scenario decides for itself what a false
  /// return means, which is what lets the matrix continue.
  Future<bool> waitFor(
    WidgetTester tester,
    String what,
    bool Function() done, {
    required Duration limit,
  }) async {
    phase = what;
    final started = DateTime.now();
    while (!done()) {
      final waited = DateTime.now().difference(started);
      if (waited >= limit) {
        debugPrint(
          '[dev] !! gave up waiting for "$what" after ${limit.inSeconds}s',
        );
        return false;
      }
      _heartbeat(what, waited);
      await tester.pump(const Duration(milliseconds: 200));
      await Future<void>.delayed(const Duration(milliseconds: 80));
    }
    return true;
  }

  /// Pump for a fixed span, still announcing itself.
  Future<void> pumpFor(
    WidgetTester tester,
    Duration span, [
    String? what,
  ]) async {
    if (what != null) phase = what;
    final started = DateTime.now();
    while (DateTime.now().difference(started) < span) {
      _heartbeat(what ?? phase, DateTime.now().difference(started));
      await tester.pump(const Duration(milliseconds: 50));
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
  }

  /// Run one scenario under a hard ceiling, recording exactly one result.
  ///
  /// [teardown] always runs, so the next scenario starts from a known device
  /// state — no owner, no wakelock, no live operation.
  Future<ScenarioResult> scenario(
    String name, {
    required Duration limit,
    required Future<void> Function() body,
    Future<void> Function()? teardown,
    bool fatalOnFailure = false,
  }) async {
    final result = ScenarioResult(name);
    results.add(result);
    _current = result;
    phase = 'starting';

    if (_fatal != null) {
      result.outcome = ScenarioOutcome.abandoned;
      result.detail = 'after: $_fatal';
      debugPrint(result.toString());
      return result;
    }

    debugPrint('[dev] ==== $name ====');
    _skipped = null;
    final started = DateTime.now();
    try {
      await body().timeout(limit);
      result.outcome = _skipped == null
          ? ScenarioOutcome.passed
          : ScenarioOutcome.skipped;
      if (_skipped != null) result.detail = _skipped!;
    } on TimeoutException {
      result.outcome = ScenarioOutcome.stalled;
      result.detail = 'scenario ceiling of ${limit.inSeconds}s reached';
    } on HarnessStall catch (e) {
      result.outcome = ScenarioOutcome.stalled;
      result.detail = e.toString();
    } on TestFailure catch (e) {
      result.outcome = ScenarioOutcome.failed;
      result.detail = e.message?.split('\n').first ?? 'assertion failed';
    } catch (e) {
      result.outcome = ScenarioOutcome.failed;
      result.detail = '$e'.split('\n').first;
    } finally {
      result.elapsed = DateTime.now().difference(started);
      result.lastPhase = phase;
      result.lastOperationState = operationState?.call() ?? '-';
      try {
        await teardown?.call();
      } catch (e) {
        result.notes.add('teardown problem: $e');
      }
      if (fatalOnFailure && result.outcome != ScenarioOutcome.passed) {
        _fatal = '$name ${result.outcome.name}';
      }
      debugPrint(result.toString());
      _current = null;
      phase = 'idle';
    }
    return result;
  }

  /// The whole matrix, as a table plus a one-line verdict.
  void report() {
    debugPrint('[dev] ================ MATRIX ($fingerprint) ================');
    for (final r in results) {
      debugPrint(r.toString());
      for (final n in r.notes) {
        debugPrint('[dev]        · $n');
      }
    }
    final counts = <ScenarioOutcome, int>{};
    for (final r in results) {
      counts[r.outcome] = (counts[r.outcome] ?? 0) + 1;
    }
    debugPrint(
      '[dev] VERDICT ${counts.entries.map((e) => '${e.value} ${e.key.name}').join(' · ')}',
    );
  }
}
