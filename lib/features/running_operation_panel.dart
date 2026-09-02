/// What the app is doing to the page, docked under the WebView.
///
/// **Why this file exists.** Content-affecting source automation is
/// *user-started, visible, bounded and cancellable* (CLAUDE.md, "Two kinds of
/// network work"). The Browser is the one screen the operation indicator
/// deliberately stays off — it "already shows the save and check panels in
/// full" — so with no panel here a running capture is a Browser moving under a
/// veil with nothing naming it and no way to end it. This is that panel, over
/// the V2 controllers.
///
/// One panel for both operations, where V1 had two. That is not a merge of two
/// designs: V1's save run published a phase, entry counters, an image counter,
/// a scroll position, a log and six controls, and its checker published pages
/// read and entries found — so a shared widget there would have been six
/// controls that did nothing. [QueueRunner] and [CheckController] each publish
/// *is it running* and *stop it*, and nothing else, so the honest panel for
/// both is the same panel with two labels.
///
/// It never claims more than the controllers know: the bar is indeterminate
/// because neither operation knows how much is left, and the stop says "at the
/// next safe point" because stopping is cooperative everywhere.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../library_ui/entry_offline.dart';
import '../library_ui/run_summary.dart';
import '../library_ui/providers.dart';
import '../providers.dart';
import '../save/queue_task.dart';
import '../save/queue_runner.dart';
import '../save/save_state.dart';
import '../ui/palette.dart';
import '../ui/status_style.dart';
import 'operation_indicator.dart' show indicatorTasksProvider;
import 'operation_lane.dart';
import 'operation_progress.dart';
import 'v2_save_flow.dart' show assistHoldProvider;

/// The task the queue runner is working on, and what to call it.
final _activeSaveProvider = FutureProvider.autoDispose
    .family<({SaveTask task, String title})?, String>((ref, taskId) async {
      final services = ref.watch(libraryUiServicesProvider);
      final task = await services.queue.byId(taskId);
      if (task == null) return null;
      final entry = await services.entries.byId(task.entryId);
      return (task: task, title: entry?.title.trim() ?? '');
    });

/// The docked panel. Renders nothing at all when nothing is running.
class RunningOperationPanel extends ConsumerWidget {
  const RunningOperationPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final runner = ref.watch(queueRunnerProvider);
    final check = ref.watch(checkControllerProvider);
    // Null on a surface where nothing can hold a run, which is the honest
    // answer there and the reason this seam is nullable.
    final assist = ref.watch(assistHoldProvider);
    // Merged in so *what is waiting behind this* redraws with everything else:
    // a request that queues while the panel is up changes nothing the runner
    // or the checker publishes.
    final lane = ref.watch(operationLaneProvider);
    return AnimatedBuilder(
      animation: Listenable.merge([runner, check, lane, ?assist]),
      builder: (context, _) {
        // A check and a save can never run together — every Browser-driving
        // operation goes through the one `OperationLane`, and a capture claims
        // the Browser's automation ownership for as long as it drives it — so
        // this is a choice, not a stack. Reading a
        // Source forward is no longer a state of its own: it happens *inside*
        // a download now, between one entry and the next (V2-D56), and the
        // download is what the user started and what they can stop.
        if (check.isRunning) return const _CheckRunning();
        if (!runner.isRunning) return const _WaitingQueue();
        // A run holding for a tap gives its strip up to the sheet doing the
        // asking. The full panel's progress, counters and bar describe motion
        // that has stopped, and the two together took so much of a phone that
        // the WebView the user is being asked to tap had no room left.
        //
        // The stop stays, because it is the only one on this screen and
        // *Cancel run* on the sheet is not one: that ends the **hold**, the
        // capture keeps the failure it already had, and the queue carries on
        // to the next entry.
        if (assist?.pendingSelection != null) {
          return _SaveHolding(taskId: runner.activeTaskId);
        }
        return _SaveRunning(taskId: runner.activeTaskId);
      },
    );
  }
}

/// Work that is queued and has not been started.
///
/// **Why the Browser needs this.** The operation indicator carries the count
/// everywhere else and deliberately stays off this screen, because the panels
/// here say it in full — but they only ever said it about a run *in flight*.
/// So the ordinary end of a save flow, *Queue only*, left the user standing on
/// the Browser with nothing on screen saying they had a queue, and the way to
/// start it three taps away on a screen they had no reason to open.
///
/// A count and a Start, and no more: what each row is, what went wrong with
/// one, and everything that can be done about it is Activity's, which the
/// count opens.
class _WaitingQueue extends ConsumerWidget {
  const _WaitingQueue();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasks = ref.watch(indicatorTasksProvider).value ?? const <SaveTask>[];
    final waiting = tasks.where((t) => t.state == SaveTaskState.queued).length;
    if (waiting == 0) return const SizedBox.shrink();

    final palette = AppPalette.of(context);
    return _PanelFrame(
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                waiting == 1
                    ? '1 download waiting for you to start it.'
                    : '$waiting downloads waiting for you to start them.',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  height: 1.35,
                  color: palette.ink,
                ),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(
              key: const ValueKey('panelStartWaiting'),
              onPressed: () => startQueuedDownloads(context, ref),
              child: const Text('Start'),
            ),
          ],
        ),
      ],
    );
  }
}

/// *A check is waiting for this to finish.* — what the lane holds behind the
/// operation on screen.
///
/// One muted line under the description, and nothing more. The request was
/// already announced when it was made (`queuedBehindSentence`); this is the
/// standing answer to "did that get lost", for a user who has since walked
/// away from the snackbar. It renders nothing when nothing is waiting, so an
/// ordinary single operation looks exactly as it always did.
class _QueuedBehind extends ConsumerWidget {
  const _QueuedBehind();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sentence = waitingBehindSentence(
      ref.watch(operationLaneProvider).waitingLabels,
    );
    if (sentence == null) return const SizedBox.shrink();
    final palette = AppPalette.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Text(
        sentence,
        key: const ValueKey('panelQueuedBehind'),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 11.5, height: 1.35, color: palette.inkMuted),
      ),
    );
  }
}

/// The frame both states share: a surface, a top rule, and room to breathe.
class _PanelFrame extends StatelessWidget {
  const _PanelFrame({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Container(
      key: const ValueKey('runningOperationPanel'),
      decoration: BoxDecoration(
        color: palette.surface,
        border: Border(top: BorderSide(color: palette.divider)),
      ),
      // The bottom inset is the shell tab bar's when there is one — the
      // Scaffold has already taken it out of this MediaQuery — and the
      // device's own when the Browser is hiding its chrome and the bar has
      // gone with it. Carried here rather than around the panel so an idle
      // Browser reserves nothing for a panel that is not there.
      padding: EdgeInsets.fromLTRB(
        16,
        12,
        16,
        14 + MediaQuery.paddingOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }
}

/// Indeterminate, and honestly so: neither operation knows how much is left
/// until it stops, and a bar that claimed a percentage would be inventing one.
class _IndeterminateBar extends StatelessWidget {
  const _IndeterminateBar();

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(3),
      child: LinearProgressIndicator(
        minHeight: 5,
        backgroundColor: palette.border,
        color: palette.primary,
      ),
    );
  }
}

class _StopRow extends StatelessWidget {
  const _StopRow({
    required this.label,
    required this.note,
    required this.buttonKey,
    required this.onStop,
  });

  final String label;
  final String note;
  final Key buttonKey;
  final VoidCallback? onStop;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        OutlinedButton.icon(
          key: buttonKey,
          onPressed: onStop,
          icon: const Icon(Icons.stop, size: 17),
          label: Text(label),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            note,
            style: TextStyle(
              fontSize: 11,
              height: 1.35,
              color: palette.inkMuted,
            ),
          ),
        ),
      ],
    );
  }
}

/// A download that has stopped for a person, folded to the two things still
/// worth a strip of the Browser: what is waiting, and the way to end it.
///
/// The sheet above this one says what it needs and asks for the tap; nothing
/// here repeats it. What cannot move to that sheet is the stop — *Cancel run*
/// there ends the hold, not the download — so it stays, with the same key and
/// the same call the full panel uses.
class _SaveHolding extends ConsumerWidget {
  const _SaveHolding({required this.taskId});

  final String? taskId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final id = taskId;
    final active = id == null ? null : ref.watch(_activeSaveProvider(id)).value;

    return _PanelFrame(
      children: [
        Text(
          'Waiting for you to point at the Entry on this page.',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 12, height: 1.35, color: palette.ink),
        ),
        const SizedBox(height: 10),
        _StopRow(
          label: 'Stop download',
          // Short on purpose. The full panel's paragraph about what survives
          // a stop is worth its room while a run is moving; here every line
          // it wraps to comes off the page the user is being asked to tap,
          // and the dialog the stop opens says all of it anyway.
          note: 'Stops at the next safe point.',
          buttonKey: const ValueKey('panelStopDownload'),
          onStop: active == null
              ? null
              : () => stopRunningDownload(context, ref, active.task),
        ),
      ],
    );
  }
}

class _SaveRunning extends ConsumerWidget {
  const _SaveRunning({required this.taskId});

  final String? taskId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final id = taskId;
    final active = id == null ? null : ref.watch(_activeSaveProvider(id)).value;
    final title = active?.title ?? '';

    return _PanelFrame(
      children: [
        Row(
          children: [
            StatusChip(
              icon: Icons.downloading,
              label: 'Downloading',
              bg: palette.primaryContainer,
              fg: palette.onPrimaryContainer,
              border: palette.primaryBorder,
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                title.isEmpty ? 'One item' : title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: monoStyle(size: 11.5, color: palette.inkMuted),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          // What the operation *is*, said whatever the progress happens to be:
          // it is the sentence that stops a moving Browser reading as something
          // the site is doing.
          'Reading this page to make an offline copy. The Browser has to stay '
          'in front while the page is read.',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 12, height: 1.35, color: palette.ink),
        ),
        const _QueuedBehind(),
        const SizedBox(height: 10),
        const OperationProgressLine(),
        const SizedBox(height: 10),
        const _IndeterminateBar(),
        const SizedBox(height: 12),
        // Progressive disclosure: the routine surface is the counts above.
        // What the engine actually said is one tap away, for the moment a
        // save goes wrong and someone has to explain why.
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            key: const ValueKey('panelOperationDetails'),
            onPressed: () => showOperationDetails(context, ref),
            child: const Text('Details'),
          ),
        ),
        _StopRow(
          label: 'Stop download',
          note:
              'Stops at the next safe point, and nothing after it is opened. '
              'Nothing already on this device is removed, and the entry stays '
              'in your library.',
          buttonKey: const ValueKey('panelStopDownload'),
          onStop: active == null
              ? null
              : () => stopRunningDownload(context, ref, active.task),
        ),
      ],
    );
  }
}

/// *Entry 3 of 10 · 12 of 18 images* — the counts, and nothing else.
///
/// Two sources, because they answer two different questions and neither can
/// answer the other's. The batch position is the queue runner's: V2 captures
/// one row at a time, so "which entry" is a fact about the loop. The image
/// counts are the engine's, published through [OperationProgress] — the
/// callbacks the composition used not to pass.
///
/// Absent rather than zeroed when there is nothing to say: a line reading
/// "0 of 0 images" is worse than no line. Never gated
/// (docs/V2_CAPABILITY_PARITY.md).
class OperationProgressLine extends ConsumerStatefulWidget {
  const OperationProgressLine({super.key, this.compact = false});

  /// One line instead of two, for the Browser's own strip.
  final bool compact;

  @override
  ConsumerState<OperationProgressLine> createState() =>
      _OperationProgressLineState();
}

class _OperationProgressLineState extends ConsumerState<OperationProgressLine> {
  late final OperationProgress _progress;
  late final QueueRunner _runner;

  @override
  void initState() {
    super.initState();
    _progress = ref.read(operationProgressProvider);
    _runner = ref.read(queueRunnerProvider);
    _progress.addListener(_onChanged);
    _runner.addListener(_onChanged);
  }

  @override
  void dispose() {
    _progress.removeListener(_onChanged);
    _runner.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final parts = operationProgressParts(
      position: _runner.batchPosition,
      total: _runner.batchTotal,
      progress: _progress.progress,
    );
    if (parts.isEmpty) return const SizedBox.shrink();

    return Text(
      parts.join(' · '),
      key: const ValueKey('operationProgressLine'),
      maxLines: widget.compact ? 1 : 2,
      overflow: TextOverflow.ellipsis,
      style: monoStyle(size: 12, color: palette.ink),
    );
  }
}

/// The pieces of the progress line, in order, leaving out what is not known.
///
/// Pure so the wording is testable without a widget tree, and so "what does a
/// user see at this moment" is one function rather than a render.
List<String> operationProgressParts({
  required int position,
  required int total,
  required SaveProgress progress,
}) {
  final parts = <String>[];
  // A batch of one needs no position: "entry 1 of 1" is noise.
  if (position > 0 && total > 1) parts.add('Entry $position of $total');
  final detected = progress.detectedImages;
  final stored = progress.storedImages;
  if (detected > 0) {
    parts.add('$stored of $detected images');
  } else if (stored > 0) {
    parts.add('$stored ${stored == 1 ? 'image' : 'images'}');
  }
  if (progress.failedImages > 0) {
    parts.add('${progress.failedImages} could not be fetched');
  }
  return parts;
}

class _CheckRunning extends ConsumerWidget {
  const _CheckRunning();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    return _PanelFrame(
      children: [
        Row(
          children: [
            StatusChip(
              icon: Icons.sync,
              // Never "Downloading": the whole point of this panel is that the
              // two operations can be told apart at a glance. Nothing is being
              // downloaded while this is on screen.
              label: 'Checking',
              bg: palette.primaryContainer,
              fg: palette.onPrimaryContainer,
              border: palette.primaryBorder,
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          'Checking this collection for new entries — metadata only, nothing '
          'is downloaded.',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 12, height: 1.35, color: palette.ink),
        ),
        const _QueuedBehind(),
        const SizedBox(height: 10),
        const _IndeterminateBar(),
        const SizedBox(height: 12),
        _StopRow(
          label: 'Stop check',
          note:
              'Stops at the next safe point. Entries already found are kept, '
              'and nothing on this device is affected.',
          buttonKey: const ValueKey('panelStopCheck'),
          onStop: ref.read(checkControllerProvider).cancel,
        ),
      ],
    );
  }
}
