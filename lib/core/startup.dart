/// The work between launching the app and having a library to show, expressed
/// as named steps so the splash can report what is actually happening.
///
/// The steps themselves are the ones `main()` has always run — recovery,
/// backfills, repairs, history pruning, queue restore. What is new is that they
/// are *named and observable*: a boot that takes two seconds because a thousand
/// entries are being reconciled now says so, instead of showing a blank window.
///
/// Only the first step is [StartupStep.critical]: without a database and a file
/// store there is no app. Everything after it is maintenance — it logs, records
/// a warning and lets the app start, exactly as the old `try`/`catch` blocks did.
library;

import 'package:flutter/foundation.dart';

/// One reported unit of startup work.
@immutable
class StartupStep {
  const StartupStep({
    required this.label,
    required this.run,
    this.critical = false,
  });

  /// What the splash says while this step runs. User-facing, present tense.
  final String label;

  final Future<void> Function() run;

  /// A failure here stops the boot and shows the failure screen. A failure in
  /// any other step is recorded and skipped.
  final bool critical;
}

/// A snapshot of the sequence, as the splash draws it.
@immutable
class StartupRun {
  const StartupRun({
    required this.labels,
    required this.completed,
    required this.finished,
    this.error,
    this.warnings = const [],
  });

  StartupRun.initial(List<StartupStep> steps)
    : labels = [for (final s in steps) s.label],
      completed = 0,
      finished = false,
      error = null,
      warnings = const [];

  final List<String> labels;

  /// Steps that have been attempted — the one at this index is running.
  final int completed;

  /// Every step has been attempted, or a critical one failed.
  final bool finished;

  /// Set when a critical step threw. The app cannot continue.
  final Object? error;

  /// Non-critical failures, in order. Reported to the log, and kept so a
  /// failure screen or a future diagnostics view does not have to re-derive it.
  final List<String> warnings;

  bool get hasFailed => error != null;

  double get fraction =>
      labels.isEmpty ? 1 : (completed / labels.length).clamp(0, 1).toDouble();

  /// The step being worked on, or null once the sequence has ended.
  String? get currentLabel =>
      finished || completed >= labels.length ? null : labels[completed];

  StartupRun _copyWith({
    int? completed,
    bool? finished,
    Object? error,
    List<String>? warnings,
  }) => StartupRun(
    labels: labels,
    completed: completed ?? this.completed,
    finished: finished ?? this.finished,
    error: error ?? this.error,
    warnings: warnings ?? this.warnings,
  );
}

/// Runs [steps] in order and publishes progress.
class StartupController extends ValueNotifier<StartupRun> {
  StartupController(this.steps, {this.minStepDuration = Duration.zero})
    : super(StartupRun.initial(steps));

  final List<StartupStep> steps;

  /// Floor on how long a step is *reported* for.
  ///
  /// Startup work is usually milliseconds, and a progress line that flickers
  /// through five labels in one frame reads as a glitch rather than as
  /// progress. This paces the report; it never delays the work itself, which
  /// has already run when the wait happens. Zero in tests.
  final Duration minStepDuration;

  bool _started = false;

  Future<void> run() async {
    if (_started) return;
    _started = true;
    final warnings = <String>[];

    for (var i = 0; i < steps.length; i++) {
      final step = steps[i];
      final startedAt = DateTime.now();
      try {
        await step.run();
      } catch (e, stack) {
        debugPrint('[startup] ${step.label} failed: $e\n$stack');
        if (step.critical) {
          value = value._copyWith(finished: true, error: e, warnings: warnings);
          return;
        }
        warnings.add('${step.label}: $e');
      }
      await _pace(startedAt);
      value = value._copyWith(
        completed: i + 1,
        finished: i == steps.length - 1,
        warnings: List.unmodifiable(warnings),
      );
    }

    // An empty sequence still has to end.
    if (steps.isEmpty) value = value._copyWith(finished: true);
  }

  Future<void> _pace(DateTime startedAt) async {
    if (minStepDuration == Duration.zero) return;
    final elapsed = DateTime.now().difference(startedAt);
    if (elapsed < minStepDuration) {
      await Future<void>.delayed(minStepDuration - elapsed);
    }
  }
}
