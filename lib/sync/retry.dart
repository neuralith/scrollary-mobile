/// Backoff for a failed sync opportunity (roadmap G6).
///
/// Pure arithmetic, deliberately: the scheduler owns *when* to be woken, this
/// file owns *how long to wait*, and a policy with no clock and no timer can
/// be asserted exactly.
///
/// A failure here is never the user's problem to solve — a flat aeroplane, a
/// captive-portal Wi-Fi, a service restart. So the shape is the ordinary one:
/// **exponential, capped, jittered**, reset by a success or by a manual *Sync
/// now*. Nothing about it retries harder than the last attempt; the cap is
/// what stops a week offline from becoming a week of doubling.
///
/// The jitter is subtractive (a delay is never *longer* than its nominal step)
/// so the progression's ceiling is the cap and nothing else. It exists so that
/// many devices knocked offline by the same event do not come back in step.
library;

import 'dart:math' as math;

class RetryPolicy {
  const RetryPolicy({
    this.initialDelay = const Duration(seconds: 30),
    this.maxDelay = const Duration(minutes: 30),
    this.multiplier = 2.0,
    this.jitterFraction = 0.2,
  }) : assert(multiplier >= 1, 'a retry never comes back sooner than the last'),
       assert(jitterFraction >= 0 && jitterFraction < 1);

  /// The wait after the first failure. Long enough that a transient blip is
  /// over, short enough that a user who fixes their connection is not left
  /// staring at a stale library.
  final Duration initialDelay;

  /// The ceiling. Past it the app is simply offline, and asking more often
  /// than this buys nothing — a resume, a reconnect or a *Sync now* all cut
  /// straight through the wait.
  final Duration maxDelay;

  final double multiplier;

  /// How much of a step may be shaved off, as a fraction. A delay always lands
  /// in `(nominal * (1 - jitterFraction), nominal]`.
  final double jitterFraction;

  /// Guards `pow` against a device that has been failing for a very long time.
  /// At the default multiplier the cap is reached by the seventh failure, so
  /// this bound is never the thing that decides a delay.
  static const int _maxExponent = 16;

  /// The nominal step for [consecutiveFailures], before jitter.
  Duration nominalDelay(int consecutiveFailures) {
    assert(consecutiveFailures >= 1, 'there is no delay before a failure');
    final exponent = math.min(consecutiveFailures - 1, _maxExponent);
    final milliseconds = math.min(
      initialDelay.inMilliseconds * math.pow(multiplier, exponent).toDouble(),
      maxDelay.inMilliseconds.toDouble(),
    );
    return Duration(milliseconds: milliseconds.round());
  }

  /// The delay to wait after [consecutiveFailures] failures in a row.
  ///
  /// [roll] is a uniform sample in `[0, 1)` — passed in rather than drawn here
  /// so the caller owns the source of randomness and a test owns the value.
  Duration delayAfter(int consecutiveFailures, double roll) {
    assert(roll >= 0 && roll < 1, 'roll is a uniform sample in [0, 1)');
    final nominal = nominalDelay(consecutiveFailures).inMilliseconds;
    return Duration(
      milliseconds: (nominal * (1 - jitterFraction * roll)).round(),
    );
  }
}
