import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../library/update_checker.dart';
import '../providers.dart';
import '../queue/task_queue.dart';
import '../save/save_run.dart';
import '../save/save_state.dart';
import '../storage/database.dart';
import '../ui/palette.dart';
import '../ui/status_style.dart';

/// How far below the safe area the indicator floats.
///
/// One number for every screen, because every screen puts something at the top
/// right: an `AppBar`'s actions sit inside [kToolbarHeight], and the Reader's
/// own bar is a [kHeaderActionSize] control row plus 14pt of padding — two
/// short of the same figure. Derived from the framework's constant rather than
/// written out, so a toolbar that ever changes height takes this with it;
/// clearing it is what keeps the pill off a control the user was reaching for.
const double kOperationIndicatorTopInset = kToolbarHeight + 8;

/// How much work is outstanding, from the state that already owns the answer.
///
/// No counter of its own: the queue's rows are the record of queued, running,
/// failed and finished work, and the two controllers are the record of the one
/// operation that can run without a row — a direct save and an update check are
/// started from the Browser and hold no queue row until they end (D58). This
/// only reads them, so nothing here can drift from what Activity shows.
@immutable
class BackgroundActivity {
  const BackgroundActivity({
    required this.active,
    required this.waiting,
    required this.failed,
    required this.needsUser,
    required this.paused,
  });

  factory BackgroundActivity.resolve({
    required List<QueueTask> tasks,
    required bool runningWithoutTask,
    required bool needsUser,
    required bool paused,
  }) {
    final summary = QueueSummary.of(tasks);
    final live = runningWithoutTask ? 1 : 0;
    return BackgroundActivity(
      // One task runs at a time — the shared WebView makes it structural — so
      // these are the same job counted two ways whenever both are set. The
      // larger of the two is the honest count, never their sum.
      active: summary.running > live ? summary.running : live,
      waiting: summary.queued,
      failed: failuresAlongsideOutstanding(tasks),
      needsUser: needsUser,
      paused: paused,
    );
  }

  /// Failures that belong to the work still in flight.
  ///
  /// **Not `QueueSummary.failed`, deliberately.** A `failed` row is terminal
  /// history and it is *kept* — Activity lists it under "needs you" and it can
  /// be retried there for as long as the history holds it, which is up to
  /// `TaskQueueController.historyLimit` rows. Counting all of them beside a
  /// live count means one save that failed last week marks every run made
  /// afterwards, and a badge that is always lit is one nobody reads. The
  /// failure is not new information; the run it is being shown next to is.
  ///
  /// The scoping rule introduces nothing. A failure counts while the work it
  /// happened *alongside* is still going: it finished after the oldest thing
  /// still queued or running was asked for. That is the batch case people
  /// actually care about — five saves started together and the third died —
  /// and it excludes the unrelated wave by construction rather than by a
  /// window anyone has to tune. Both columns are already written on every row
  /// and already read by the Activity screen.
  ///
  /// A failed row with no `finishedAt` cannot be placed in time, so it does not
  /// count: silence is the safe answer for a marker whose whole job is to be
  /// believed.
  static int failuresAlongsideOutstanding(List<QueueTask> tasks) {
    DateTime? oldestOutstanding;
    for (final task in tasks) {
      switch (queueTaskStateFromName(task.state)) {
        case QueueTaskState.queued || QueueTaskState.running:
          if (oldestOutstanding == null ||
              task.queuedAt.isBefore(oldestOutstanding)) {
            oldestOutstanding = task.queuedAt;
          }
        case _:
          continue;
      }
    }
    // Nothing outstanding: there is no wave for a failure to belong to. The
    // pill is either absent or reporting a hold, which speaks for itself.
    if (oldestOutstanding == null) return 0;

    var failures = 0;
    for (final task in tasks) {
      if (queueTaskStateFromName(task.state) != QueueTaskState.failed) continue;
      final finished = task.finishedAt;
      if (finished == null) continue;
      if (finished.isAfter(oldestOutstanding)) failures++;
    }
    return failures;
  }

  /// Jobs moving right now, including a save or check that never took a row.
  final int active;

  /// Rows waiting their turn — queued checks and cleanups, which drain on
  /// their own, and saves, which wait for an explicit Start.
  final int waiting;

  /// Rows that ended badly and are still in Activity.
  final int failed;

  /// The operation will not move again until a person does something.
  final bool needsUser;

  /// Held where it is, by the user or by a hidden Browser.
  final bool paused;

  int get remaining => active + waiting;

  /// Is there anything to say at all? Failed rows deliberately do **not**
  /// count: they are history until something is running beside them, and an
  /// indicator that never goes away is one nobody reads.
  bool get isPresent => remaining > 0 || needsUser || paused;

  /// True only while something is genuinely moving — what a spinner is allowed
  /// to claim. Waiting saves do not move on their own, and neither does a run
  /// that is holding for the user.
  bool get inMotion => active > 0 && !needsUser && !paused;

  /// What a screen reader is told. The counts in words, because "3" alone
  /// says nothing about what three is, and the destination named, because a
  /// button that does not say where it goes is one nobody presses twice.
  String get description {
    final parts = <String>[
      if (active > 0) '$active running',
      if (waiting > 0) '$waiting waiting',
      if (failed > 0) '$failed failed',
    ];
    final body = parts.isEmpty ? 'nothing outstanding' : parts.join(', ');
    final lead = needsUser
        ? 'Background work needs you'
        : (paused ? 'Background work paused' : 'Background work');
    final destination = needsUser ? 'Opens the Browser.' : 'Opens Activity.';
    return '$lead — $body. $destination';
  }
}

/// What a running operation looks like from anywhere that is not the Browser.
///
/// Hosted above the router, so it is reachable from the Reader, the Library,
/// Settings and every screen that is pushed over them. It is **free and never
/// gated**: knowing what your device is doing, and being able to stop it, is
/// not a feature to sell (docs/FOREGROUND_MULTITASKING.md §10.1).
///
/// Deliberately a **count, not an account**. It says that work is outstanding
/// and how much; every word of detail, and every control — stop, retry,
/// reorder, "Open Browser" for a run that needs one — lives on the Activity
/// screen, which this opens. A status panel that follows the user onto the
/// page they are reading is a panel they learn to ignore.
///
/// Absent on the Browser itself, which already shows the save and check panels
/// in full — two accounts of the same run, one over the other, is how a user
/// stops believing either. Absent, too, while the Reader has hidden its
/// chrome: the bars and this go together, so nothing is left floating over a
/// page someone is reading.
class OperationIndicator extends ConsumerStatefulWidget {
  const OperationIndicator({
    required this.onOpenDetails,
    required this.onOpenBrowser,
    super.key,
  });

  /// Opens the detailed surface — Activity. Passed in rather than looked up:
  /// this widget is built above the router, where the router's own inherited
  /// widget is not in scope.
  final VoidCallback onOpenDetails;

  /// Brings the Browser forward, on the page the held operation is already on.
  ///
  /// The destination for a "Needs you", and the reason this is a second
  /// callback rather than a branch inside the first: **"Needs you" is one
  /// action** (docs/FOREGROUND_MULTITASKING.md §9). Every state that produces
  /// one — a sign-in, a CAPTCHA, a consent dialog, an ambiguous next-Entry
  /// control, a run holding on a hidden WebView — is answered in the Browser
  /// and nowhere else: the selection overlay is drawn on that screen alone.
  /// Landing the user on a list, from which the only live control is a button
  /// that opens the Browser, is a tap spent on nothing.
  final VoidCallback onOpenBrowser;

  @override
  ConsumerState<OperationIndicator> createState() => _OperationIndicatorState();
}

class _OperationIndicatorState extends ConsumerState<OperationIndicator> {
  late final SaveRunController _run;
  late final UpdateChecker _checker;
  late final ValueNotifier<bool> _browserOnScreen;
  late final ReaderChromeVisibility _readerChromeVisible;

  @override
  void initState() {
    super.initState();
    _run = ref.read(saveRunProvider);
    _checker = ref.read(updateCheckerProvider);
    _browserOnScreen = ref.read(browserOnScreenProvider);
    _readerChromeVisible = ref.read(readerChromeVisibleProvider);
    for (final source in [
      _run,
      _checker,
      _browserOnScreen,
      _readerChromeVisible,
    ]) {
      source.addListener(_onChanged);
    }
  }

  @override
  void dispose() {
    for (final source in [
      _run,
      _checker,
      _browserOnScreen,
      _readerChromeVisible,
    ]) {
      source.removeListener(_onChanged);
    }
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  /// True when the operation will not move again until a person does
  /// something. Distinct from merely waiting, which resolves itself.
  bool get _needsUser {
    if (_checker.pendingSelection != null) return true;
    if (!_run.hasActiveRun) return false;
    // Held because the Browser was left while the run needed it: the way out
    // is the user opening it again, which is exactly what Activity offers.
    if (_run.pauseReason == kPauseBrowserHidden) return true;
    return switch (_run.progress.state) {
      SaveState.awaitingSelection || SaveState.waitingForBrowser => true,
      _ => false,
    };
  }

  @override
  Widget build(BuildContext context) {
    final tasks = ref.watch(queueTasksProvider).value ?? const <QueueTask>[];
    final activity = BackgroundActivity.resolve(
      tasks: tasks,
      runningWithoutTask: _run.hasActiveRun || _checker.isRunning,
      needsUser: _needsUser,
      paused: _run.isPaused,
    );

    if (!activity.isPresent ||
        _browserOnScreen.value ||
        !_readerChromeVisible.value) {
      return const SizedBox.shrink();
    }

    final palette = AppPalette.of(context);
    final count = activity.remaining > 99 ? '99+' : '${activity.remaining}';
    // A held operation is answered in the Browser and nowhere else; everything
    // else is answered on Activity.
    final onTap = activity.needsUser
        ? widget.onOpenBrowser
        : widget.onOpenDetails;

    return Positioned(
      top: MediaQuery.paddingOf(context).top + kOperationIndicatorTopInset,
      right: 12,
      child: Semantics(
        container: true,
        button: true,
        // Announced when it starts needing a person, and at no other time: a
        // live region on a count that ticks would talk over the whole app.
        liveRegion: activity.needsUser,
        label: activity.description,
        onTap: onTap,
        child: ExcludeSemantics(
          child: Material(
            color: palette.surface,
            elevation: 3,
            borderRadius: BorderRadius.circular(999),
            child: InkWell(
              key: const ValueKey('operationIndicator'),
              onTap: onTap,
              borderRadius: BorderRadius.circular(999),
              child: Container(
                // The header action size as a *floor*, not a fixed height: the
                // touch target is never smaller than the one the rest of the
                // app uses, and a reader at 200% text size grows the pill
                // rather than overflowing it.
                constraints: const BoxConstraints(
                  minWidth: kHeaderActionSize,
                  minHeight: kHeaderActionSize,
                ),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: palette.divider),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: _glyph(activity, palette),
                    ),
                    const SizedBox(width: 7),
                    Text(
                      count,
                      style: monoStyle(size: 12.5, color: palette.ink),
                    ),
                    if (activity.failed > 0) ...[
                      const SizedBox(width: 6),
                      Icon(
                        Icons.error_outline,
                        size: 14,
                        color: palette.danger,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// One glyph, and it never claims more than is true: a spinner only while
  /// something is actually moving.
  Widget _glyph(BackgroundActivity activity, AppPalette palette) {
    if (activity.needsUser) {
      return Icon(Icons.error_outline, size: 16, color: palette.warn);
    }
    if (activity.paused) {
      return Icon(
        Icons.pause_circle_outline,
        size: 16,
        color: palette.inkMuted,
      );
    }
    if (activity.inMotion) {
      return CircularProgressIndicator(strokeWidth: 2, color: palette.primary);
    }
    return Icon(Icons.schedule, size: 16, color: palette.inkMuted);
  }
}
