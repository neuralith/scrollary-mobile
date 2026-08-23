/// What the last batch came to, and the detail behind it.
///
/// **Why this file exists.** A ten-entry download used to end in silence: the
/// operation indicator simply disappeared when the count reached zero, and the
/// only sentence anyone ever saw about the batch was a snackbar describing the
/// *queueing*, held in a bottom sheet's state and destroyed with the sheet.
/// "Did my ten entries download" had no answer anywhere.
///
/// Two rules it carries:
///
/// * **Compact by default, detailed on request.** The card is four numbers and
///   at most two actions. The log — hundreds of lines from one scrolled page —
///   is behind *Details*, because a routine save should never make anyone read
///   an engine trace.
/// * **"Finished" and "stopped short" are different outcomes** and are never
///   folded into one. A run the disk gate ended, or the user stopped, says so.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/operation_progress.dart';
import '../providers.dart';
import '../save/queue_runner.dart';
import '../save/queue_task.dart';
import '../ui/palette.dart';
import '../ui/status_style.dart';
import 'library_widgets.dart';
import 'providers.dart';

/// The headline, in the user's words.
///
/// Pure, so what a person reads at the end of a run is one testable function
/// rather than a widget tree.
String runSummaryHeadline(RunSummary run) {
  if (run.downloaded == 0) {
    if (run.cancelled > 0 && run.failed == 0) return 'Download stopped';
    return 'Nothing was downloaded';
  }
  if (run.downloaded == run.requested) {
    return run.downloaded == 1
        ? '1 entry downloaded'
        : '${run.downloaded} entries downloaded';
  }
  return '${run.downloaded} of ${run.requested} entries downloaded';
}

/// The second line: what happened to the rest. Empty when nothing did.
String runSummaryDetail(RunSummary run) {
  final parts = <String>[];
  if (run.failed > 0) {
    parts.add(
      run.failed == 1
          ? '1 could not be completed'
          : '${run.failed} could not be completed',
    );
  }
  if (run.cancelled > 0) {
    parts.add(run.cancelled == 1 ? '1 stopped' : '${run.cancelled} stopped');
  }
  // A sequential capture that ran out of source says *why* it is short, which
  // is an answer about the site rather than about the run — so it replaces
  // the generic sentence instead of standing beside it.
  final note = run.endNote;
  if (note != null) {
    parts.add(note);
  } else if (run.stoppedEarly) {
    parts.add('the run ended before the rest were reached');
  }
  return parts.join(' · ');
}

/// Where the summary comes from.
///
/// A nullable seam rather than [queueRunnerProvider] itself: Activity is
/// mounted on surfaces that have no runner — and "no runner" is honestly "no
/// run has happened", which is exactly what the card should draw. Composition
/// overrides it with the one runner the app drains through.
final runSummarySourceProvider = Provider<QueueRunner?>((ref) => null);

/// The card Activity shows above the list once a batch is over.
class RunSummaryCard extends ConsumerWidget {
  const RunSummaryCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final runner = ref.watch(runSummarySourceProvider);
    if (runner == null) return const SizedBox.shrink();
    return AnimatedBuilder(
      animation: runner,
      builder: (context, _) {
        final run = runner.lastRun;
        if (run == null || runner.isRunning) return const SizedBox.shrink();
        return _Card(run: run, runner: runner);
      },
    );
  }
}

class _Card extends ConsumerWidget {
  const _Card({required this.run, required this.runner});

  final RunSummary run;
  final QueueRunner runner;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final detail = runSummaryDetail(run);

    return Container(
      key: const ValueKey('runSummaryCard'),
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
      decoration: BoxDecoration(
        color: palette.surface,
        border: Border.all(
          color: run.needsAttention ? palette.warnBorder : palette.divider,
        ),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  runSummaryHeadline(run),
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              IconButton(
                key: const ValueKey('runSummaryDismiss'),
                tooltip: 'Dismiss this summary',
                iconSize: 18,
                icon: const Icon(Icons.close),
                onPressed: runner.clearLastRun,
              ),
            ],
          ),
          if (detail.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2, right: 6),
              child: Text(
                detail,
                style: TextStyle(
                  fontSize: 12,
                  height: 1.35,
                  color: palette.inkMuted,
                ),
              ),
            ),
          const SizedBox(height: 6),
          Row(
            children: [
              if (run.failed > 0)
                TextButton(
                  key: const ValueKey('runSummaryRetryFailed'),
                  onPressed: () => _retryFailed(context, ref),
                  child: const Text('Retry failed'),
                ),
              TextButton(
                key: const ValueKey('runSummaryDetails'),
                onPressed: () => showOperationDetails(context, ref),
                child: const Text('Details'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Put every failed row of this batch back in the queue. Still waits for
  /// Start, like every other enqueue.
  Future<void> _retryFailed(BuildContext context, WidgetRef ref) async {
    final queue = ref.read(saveQueueRepoProvider);
    final tasks = await queue.all();
    var again = 0;
    for (final task in tasks.where((t) => t.state == SaveTaskState.failed)) {
      if (await queue.retry(task.id) != null) again++;
    }
    if (!context.mounted) return;
    ref.read(runSummarySourceProvider)?.clearLastRun();
    showLibraryMessage(
      context,
      again == 0
          ? 'None of those can be retried.'
          : '$again back in the queue. Nothing starts until you start it.',
    );
  }
}

/// The detail, on request: what the engine said, newest last.
///
/// Deliberately plain. It exists for the moment something went wrong and
/// someone needs to see why — not as a surface anyone is expected to read.
Future<void> showOperationDetails(BuildContext context, WidgetRef ref) {
  final log = ref.read(operationProgressProvider).log;
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) {
      final palette = AppPalette.of(sheetContext);
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'What happened',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              Text(
                log.isEmpty
                    ? 'Nothing was recorded for the last download.'
                    : 'The last download, as the app read the page.',
                style: TextStyle(fontSize: 12, color: palette.inkMuted),
              ),
              const SizedBox(height: 12),
              Flexible(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 360),
                  child: SingleChildScrollView(
                    key: const ValueKey('operationDetailsLog'),
                    child: SelectableText(
                      log.isEmpty ? '—' : log.join('\n'),
                      style: monoStyle(size: 11.5, color: palette.ink),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}
