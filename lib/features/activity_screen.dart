/// Everything this device is doing on the user's behalf, and what can be done
/// about it — over the V2 save queue.
///
/// **Why a screen and not a row on the shelf.** The queue's state does live on
/// the Entry rows now, and that is the right place for *this Entry's* answer.
/// It is not an answer to "what is my phone doing": a failed row for an Entry
/// three folders down is, in practice, unreachable. The operation indicator
/// names a count and promises a destination for the detail
/// (`operation_indicator.dart`, docs/FOREGROUND_MULTITASKING.md §9), the
/// restricted-site sentence is specified to appear "on a task in Activity that
/// was refused" (STORE_PACKAGE.md §6.5.1), and *Remove from Activity* is named
/// as an invariant (CLAUDE.md, "Structural invariants"). This is that surface.
///
/// It decides nothing. Every verb here is `library_ui/entry_offline.dart`'s,
/// unchanged: cancelling preserves the row, a waiting row goes with an Undo
/// that keeps its place, a running one is asked to stop at its next safe
/// point, and only a terminal row can be removed. Grouped by what the user can
/// do about it, which is the only grouping that earns its heading.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../library_ui/entry_offline.dart';
import '../library_ui/library_widgets.dart';
import '../library_ui/providers.dart';
import '../save/queue_task.dart';
import '../ui/palette.dart';
import '../ui/status_style.dart';

/// Every queue row, newest activity first within each group.
final activityTasksProvider = StreamProvider<List<SaveTask>>(
  (ref) => ref.watch(saveQueueRepoProvider).watch(),
);

/// What to call the Entry a row is for. Falls back to the address rather than
/// to a blank: a row with nothing to name it is still a row the user is owed
/// an account of.
final activityTaskLabelProvider = FutureProvider.autoDispose
    .family<String, String>((ref, entryId) async {
      final entry = await ref.watch(entryRepoProvider).byId(entryId);
      final title = entry?.title.trim() ?? '';
      return title;
    });

class ActivityScreen extends ConsumerWidget {
  const ActivityScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasks = ref.watch(activityTasksProvider);
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: tasks.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => Center(child: Text('$error')),
          data: (rows) => _Activity(rows: rows),
        ),
      ),
    );
  }
}

class _Activity extends ConsumerWidget {
  const _Activity({required this.rows});

  final List<SaveTask> rows;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final running = [
      for (final t in rows)
        if (t.state == SaveTaskState.running) t,
    ];
    final waiting = [
      for (final t in rows)
        if (t.state == SaveTaskState.queued) t,
    ];
    final failed = [
      for (final t in rows)
        if (t.state == SaveTaskState.failed) t,
    ];
    final done = [
      for (final t in rows)
        if (t.state == SaveTaskState.completed ||
            t.state == SaveTaskState.cancelled)
          t,
    ];

    return Column(
      children: [
        LibraryHeader(
          title: 'Activity',
          onBack: Navigator.of(context).canPop()
              ? () => Navigator.of(context).pop()
              : null,
        ),
        Expanded(
          child: rows.isEmpty
              ? const LibraryEmptyState(
                  icon: Icons.done_all,
                  title: 'Nothing is running',
                  body:
                      'Downloads you ask for wait here until you start them. '
                      'Nothing on this device starts on its own.',
                )
              : ListView(
                  padding: const EdgeInsets.only(bottom: 24),
                  children: [
                    if (running.isNotEmpty)
                      ..._section(context, ref, 'RUNNING', running),
                    if (waiting.isNotEmpty) ...[
                      ..._section(context, ref, 'WAITING', waiting),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
                        child: FilledButton(
                          key: const ValueKey('activityStart'),
                          onPressed: () => startQueuedDownloads(context, ref),
                          child: Text(
                            waiting.length == 1
                                ? 'Start 1 download'
                                : 'Start ${waiting.length} downloads',
                          ),
                        ),
                      ),
                    ],
                    if (failed.isNotEmpty)
                      ..._section(context, ref, 'FAILED', failed),
                    if (done.isNotEmpty)
                      ..._section(context, ref, 'FINISHED', done),
                  ],
                ),
        ),
      ],
    );
  }

  List<Widget> _section(
    BuildContext context,
    WidgetRef ref,
    String label,
    List<SaveTask> tasks,
  ) => [
    SectionLabel('$label · ${tasks.length}'),
    const Divider(height: 1),
    for (final task in tasks) ...[
      _TaskRow(task: task),
      const Divider(height: 1),
    ],
  ];
}

class _TaskRow extends ConsumerWidget {
  const _TaskRow({required this.task});

  final SaveTask task;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final label = ref.watch(activityTaskLabelProvider(task.entryId)).value;
    final name = (label == null || label.isEmpty) ? task.locationUrl : label;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  key: ValueKey('activityRow-${task.id}'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 14, color: palette.ink),
                ),
                const SizedBox(height: 3),
                Text(
                  // The row's own verdict, never a sentence written here:
                  // "the site stopped us" and "you stopped it" are different
                  // outcomes and the row is where that difference is kept.
                  saveTaskSentence(task),
                  style: TextStyle(
                    fontSize: 11.5,
                    height: 1.4,
                    color: palette.inkMuted,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          ?_action(context, ref),
        ],
      ),
    );
  }

  /// One verb per row, and it is the one the row's state allows. A live row is
  /// cancelled and never dropped; a terminal one is removed from Activity and
  /// that deletes no Entry, no file and no reading state.
  Widget? _action(BuildContext context, WidgetRef ref) => switch (task.state) {
    SaveTaskState.running => IconButton(
      key: ValueKey('activityStop-${task.id}'),
      tooltip: 'Stop this download',
      icon: const Icon(Icons.stop_circle_outlined),
      onPressed: () => stopRunningDownload(context, ref, task),
    ),
    SaveTaskState.queued => IconButton(
      key: ValueKey('activityRemoveWaiting-${task.id}'),
      tooltip: 'Remove from the download queue',
      icon: const Icon(Icons.close),
      onPressed: () => removeWaitingDownload(context, ref, task),
    ),
    SaveTaskState.completed ||
    SaveTaskState.failed ||
    SaveTaskState.cancelled => IconButton(
      key: ValueKey('activityRemove-${task.id}'),
      tooltip: 'Remove from activity',
      icon: const Icon(Icons.delete_outline),
      onPressed: () => removeDownloadFromActivity(context, ref, task),
    ),
  };
}
