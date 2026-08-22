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
import '../library_ui/providers.dart';
import '../providers.dart';
import '../save/queue_task.dart';
import '../ui/palette.dart';
import '../ui/status_style.dart';

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
    return AnimatedBuilder(
      animation: Listenable.merge([runner, check]),
      builder: (context, _) {
        // A check and a save can never run together — the Browser's automation
        // ownership is single — so this is a choice, not a stack.
        if (check.isRunning) return const _CheckRunning();
        if (!runner.isRunning) return const SizedBox.shrink();
        return _SaveRunning(taskId: runner.activeTaskId);
      },
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
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
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
        const SizedBox(height: 10),
        const _IndeterminateBar(),
        const SizedBox(height: 12),
        _StopRow(
          label: 'Stop download',
          note:
              'Stops at the next safe point. Nothing already on this device is '
              'removed, and the entry stays in your library.',
          buttonKey: const ValueKey('panelStopDownload'),
          onStop: active == null
              ? null
              : () => stopRunningDownload(context, ref, active.task),
        ),
      ],
    );
  }
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
