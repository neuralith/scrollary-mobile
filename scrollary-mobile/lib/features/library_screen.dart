import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../save/capture_policy.dart';
import '../save/save_state.dart';
import '../library/library_sort.dart';
import '../library/content_shape.dart';
import '../library/entry_labels.dart';
import '../library/collection_repository.dart';
import '../app.dart';
import '../providers.dart';
import '../queue/task_queue.dart';
import '../reading/reading_position.dart';
import '../ui/palette.dart';
import '../ui/status_style.dart';
import '../ui/theme.dart';
import 'library_check_ui.dart';
import 'open_in_browser.dart';
import 'save_queue_ui.dart';
import 'resume_point.dart';
import 'collection_detail_screen.dart' show sortEntriesForReading;
import 'storage_screen.dart' show StoragePill;
import '../storage/database.dart';

/// The library, grouped by collection.
///
/// One row per collection, not one row per entry: entries of the same collection
/// belong together, and two collection on the same host stay apart.
class LibraryScreen extends ConsumerWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groups = ref.watch(libraryCollectionsProvider);
    final resumable = ref.watch(resumableRunProvider);

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            const _LibraryHeader(),
            // Zero-sized, and deliberately NOT inside the list below: a
            // `ListView`'s children are built lazily, so a watcher scrolled
            // out of view is a watcher that is not watching. A library-wide
            // check that ends while the user is in the Browser has to be
            // noticed wherever the Library happens to be scrolled to.
            const LibraryCheckCompletionWatcher(),
            Expanded(
              child: groups.when(
                loading: () => const _LibrarySkeleton(),
                error: (e, _) => _LibraryError(error: '$e'),
                data: (list) {
                  final continueEntries =
                      ref.watch(continueReadingProvider).value ?? const [];
                  final resumeRun = resumable.value;

                  return ListView(
                    padding: const EdgeInsets.only(bottom: 24),
                    children: [
                      const _ActivityStrip(),
                      if (resumeRun != null) _ResumeCard(run: resumeRun),
                      const SectionLabel(
                        'CONTINUE READING',
                        padding: EdgeInsets.fromLTRB(20, 14, 20, 8),
                      ),
                      _ContinueRow(
                        entries: continueEntries,
                        allCollection: list,
                      ),
                      // Library maintenance, stated rather than implied by a
                      // glyph: what a check covers, what it found, and that it
                      // downloads nothing (see library_check_ui.dart). Absent
                      // on an empty library — there is nothing to check yet,
                      // and the empty state below already says what to do.
                      if (list.isNotEmpty) ...[
                        const SectionLabel(
                          'LIBRARY UPDATES',
                          padding: EdgeInsets.fromLTRB(20, 20, 20, 4),
                        ),
                        const LibraryUpdatesCard(),
                      ],
                      SectionLabel(
                        'YOUR LIBRARY · ${list.length}',
                        trailing: const _SortControl(),
                      ),
                      if (list.isEmpty)
                        const _EmptyLibrary()
                      else ...[
                        const Divider(),
                        for (final group in list) ...[
                          _CollectionRow(group: group),
                          const Divider(),
                        ],
                      ],
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The header carries navigation only.
///
/// Checking every collection used to live here as a bare sync glyph with a
/// tooltip — which is indistinguishable from "refresh this screen" and from
/// "sync my devices", and is unreachable to anyone who does not hover. It is
/// now a labelled card in the list ([LibraryUpdatesCard]) that states its scope
/// before it starts.
class _LibraryHeader extends ConsumerWidget {
  const _LibraryHeader();

  @override
  Widget build(BuildContext context, WidgetRef ref) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 10, 12, 6),
    child: Row(
      // The title inherits body ink from the theme rather than naming a
      // colour: `serifStyle()` with no colour is the whole point (D62).
      // Centred, not bottom-aligned: the actions are all one height now, and
      // a serif title's box is taller than its glyphs, so aligning bottoms
      // pushed the word visibly below the row it belongs to.
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Text(
            'Library',
            style: serifStyle(),
            // At 320pt this word wrapped to three lines and dragged the whole
            // header down with it.
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const StoragePill(),
        HeaderIconButton(
          icon: Icons.inventory_2,
          tooltip: 'Archived',
          onPressed: () => LeaveBrowserGuard.push(context, '/archived'),
        ),
        HeaderIconButton(
          icon: Icons.settings,
          tooltip: 'Settings',
          onPressed: () => LeaveBrowserGuard.push(context, '/settings'),
        ),
      ],
    ),
  );
}

/// A live band above the library when the queue has anything to say. It is a
/// summary, not a control surface — the controls live on the activity screen.
/// "Save queue · 6 waiting" — quiet, and honest that nothing is running.
///
/// Deliberately not the busy blue of an active run: this is a plan, not
/// progress, and dressing it up as progress is how a user ends up believing
/// downloads are happening when they are not.
class _SaveQueueStrip extends ConsumerWidget {
  const _SaveQueueStrip({required this.count});

  final int count;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Material(
        color: palette.surfaceHigh,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: const ValueKey('saveQueueStrip'),
          onTap: () => LeaveBrowserGuard.push(context, '/activity'),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: palette.border),
            ),
            padding: const EdgeInsets.fromLTRB(13, 10, 10, 10),
            child: Row(
              children: [
                Icon(
                  Icons.playlist_add_check,
                  size: 20,
                  color: palette.inkMuted,
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Save queue · $count waiting',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          fontVariations: wght(500),
                          fontWeight: FontWeight.w500,
                          color: palette.inkStrong,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Open Browser to start',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: palette.inkFaint,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  key: const ValueKey('startSaveButton'),
                  onPressed: () => confirmAndStartSaves(context, ref),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    visualDensity: VisualDensity.compact,
                  ),
                  child: const Text('Start'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ActivityStrip extends ConsumerWidget {
  const _ActivityStrip();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasks = ref.watch(queueTasksProvider).value ?? const <QueueTask>[];
    final running = tasks
        .where((t) => t.state == QueueTaskState.running.name)
        .toList();
    final queued = tasks
        .where((t) => t.state == QueueTaskState.queued.name)
        .length;
    final failed = tasks
        .where((t) => t.state == QueueTaskState.failed.name)
        .length;
    final controller = ref.watch(saveRunProvider);
    final active = running.firstOrNull;

    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        // Visible when the queue has anything to say — or when a save
        // (queued or direct) is holding for the Browser: that banner must
        // reach the user wherever they are.
        final waiting =
            controller.progress.state == SaveState.waitingForBrowser;
        if (running.isEmpty && queued == 0 && failed == 0 && !waiting) {
          return const SizedBox.shrink();
        }
        // Queued saves that have not been started are their own state:
        // nothing is happening, and the only thing that matters is the
        // button that would make it happen (D46).
        final summary = QueueSummary.of(tasks);
        if (running.isEmpty && !waiting && summary.hasQueuedSaves) {
          return _SaveQueueStrip(count: summary.queuedSaves);
        }
        return _stripBody(context, controller.progress, active, queued, failed);
      },
    );
  }

  Widget _stripBody(
    BuildContext context,
    SaveProgress run,
    QueueTask? active,
    int queued,
    int failed,
  ) {
    final phase = active == null ? 'QUEUED' : run.state.name.toUpperCase();
    final pct = run.detectedImages > 0
        ? (run.storedImages / run.detectedImages).clamp(0.0, 1.0)
        : 0.0;

    // A save holding on a hidden WebView needs the user, not a percent:
    // the strip becomes the banner, and its action opens the Browser.
    final palette = AppPalette.of(context);

    if (run.state == SaveState.waitingForBrowser) {
      return Consumer(
        builder: (context, ref, _) => Container(
          margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          padding: const EdgeInsets.fromLTRB(13, 12, 10, 12),
          decoration: BoxDecoration(
            color: palette.warnContainer,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: palette.warnBorder),
          ),
          child: Row(
            children: [
              Icon(Icons.pause_circle, size: 22, color: palette.warn),
              const SizedBox(width: 11),
              Expanded(
                child: Text(
                  'Save is waiting — open the Browser to continue.',
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.4,
                    color: palette.onWarnContainer,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: () => showBrowserSurface(context, ref),
                child: const Text('Open Browser'),
              ),
            ],
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Material(
        color: palette.primaryContainer,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => LeaveBrowserGuard.push(context, '/activity'),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(13, 13, 10, 12),
                child: Row(
                  children: [
                    Icon(
                      Icons.downloading,
                      size: 22,
                      color: palette.onPrimaryContainer,
                    ),
                    const SizedBox(width: 11),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            phase,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: monoStyle(color: palette.onPrimaryContainer),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            active == null
                                ? '$queued waiting'
                                : (run.entryTitle.isEmpty
                                      ? 'Working'
                                      : run.entryTitle),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13,
                              fontVariations: wght(500),
                              fontWeight: FontWeight.w500,
                              color: palette.onPrimaryContainer,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          '${(pct * 100).round()}%',
                          style: monoStyle(
                            size: 12,
                            color: palette.onPrimaryContainer,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '$queued queued · $failed failed',
                          style: TextStyle(
                            fontSize: 11,
                            color: palette.onPrimaryContainer,
                          ),
                        ),
                      ],
                    ),
                    Icon(
                      Icons.chevron_right,
                      size: 20,
                      color: palette.onPrimaryContainer,
                    ),
                  ],
                ),
              ),
              LinearProgressIndicator(
                value: pct,
                minHeight: 3,
                backgroundColor: palette.primaryBorder,
                color: palette.primary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SortControl extends ConsumerWidget {
  const _SortControl();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final sort = ref.watch(librarySortProvider).value ?? LibrarySort.lastRead;
    final label = sort == LibrarySort.name ? 'Name' : 'Last read';

    return Material(
      color: palette.surfaceHigh,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(999),
        side: BorderSide(color: palette.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => setLibrarySort(
          ref,
          sort == LibrarySort.name ? LibrarySort.lastRead : LibrarySort.name,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.swap_vert, size: 16, color: palette.inkStrong),
              const SizedBox(width: 5),
              Text(
                label,
                style: TextStyle(fontSize: 12, color: palette.inkStrong),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Horizontally scrolling continue cards. Empty states say *why* they are
/// empty — "nothing saved", "nothing opened yet" and "you finished
/// everything" are three different situations and only one is a problem.
class _ContinueRow extends StatelessWidget {
  const _ContinueRow({required this.entries, required this.allCollection});

  final List<ResumePoint> entries;
  final List<LibraryCollection> allCollection;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    if (entries.isEmpty) {
      final anyReadable = allCollection.any((g) => g.offlineCount > 0);
      final anyOpened = allCollection.any((g) => g.lastReadAt != null);
      final (title, body) = !anyReadable
          ? (
              'Nothing readable yet',
              'Saves that failed or lost their files cannot be read. '
                  'Save an entry to start.',
            )
          : anyOpened
          ? (
              "You're up to date",
              'You have finished every entry you have saved. Save more '
                  'to keep going.',
            )
          : (
              'Nothing opened yet',
              'Entries you start show up here with your exact position.',
            );

      return Container(
        margin: const EdgeInsets.fromLTRB(20, 4, 20, 0),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: palette.surfaceMuted,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: palette.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(
                fontSize: 14,
                fontVariations: wght(600),
                fontWeight: FontWeight.w600,
                color: palette.ink,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              body,
              style: TextStyle(
                fontSize: 13,
                height: 1.5,
                color: palette.inkMuted,
              ),
            ),
          ],
        ),
      );
    }

    return SizedBox(
      // Two blocks tall — identity row, then the progress line — with the
      // same slack over the content the taller card had, so a scaled-up
      // text size still fits.
      height: 111,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 6),
        itemCount: entries.length,
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemBuilder: (context, i) => _ContinueCard(entry: entries[i]),
      ),
    );
  }
}

/// One Continue card: which entry, how far in, and how that reads as panels.
class _ContinueCard extends StatelessWidget {
  const _ContinueCard({required this.entry});

  final ResumePoint entry;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final pct = (entry.progress * 100).clamp(0, 100).round();

    return SizedBox(
      key: ValueKey('continueCard-${entry.entry.id}'),
      // Wide enough that the progress line ("68% • 12 entries remaining")
      // renders at full size; the FittedBox below covers what is left.
      width: 240,
      child: Material(
        color: palette.surfaceMuted,
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => context.push('/reader/${entry.entry.id}'),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: palette.border),
            ),
            padding: const EdgeInsets.fromLTRB(14, 13, 14, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    MonogramTile(
                      id: entry.group.id,
                      title: entry.displayName,
                      size: 34,
                      radius: 10,
                      fontSize: 15,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            entry.displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13,
                              height: 1.25,
                              fontVariations: wght(600),
                              fontWeight: FontWeight.w600,
                              color: palette.ink,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            entry.sourceMarker,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: monoStyle(color: palette.inkMuted),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    // The same component the entry list uses, so a card and
                    // a row cannot draw the same fraction two ways.
                    EntryProgressRing(
                      key: ValueKey('continueRing-${entry.entry.id}'),
                      fraction: entry.progress,
                      completed: entry.isCompleted,
                    ),
                    const SizedBox(width: 8),
                    // One line, and it stays one line: an ellipsised
                    // "12 entries remain…" is worse than a line a few
                    // percent smaller, so it scales down instead of
                    // truncating when the text is long or scaled up.
                    Expanded(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(
                                text: '$pct%',
                                style: monoStyle(color: palette.primary),
                              ),
                              TextSpan(
                                text: ' • ${entry.laterEntriesLabel}',
                                style: monoStyle(color: palette.inkMuted),
                              ),
                            ],
                          ),
                          maxLines: 1,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One collection row: monogram, name, update-check chip, host, counts, and — only
/// when there is one — a warning line.
class _CollectionRow extends ConsumerWidget {
  const _CollectionRow({required this.group});

  final LibraryCollection group;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final checker = ref.watch(updateCheckerProvider);
    return ListenableBuilder(
      listenable: checker,
      builder: (context, _) => _row(
        context,
        ref,
        checking: checker.isRunning && checker.activeItemId == group.id,
      ),
    );
  }

  Widget _row(BuildContext context, WidgetRef ref, {required bool checking}) {
    final palette = AppPalette.of(context);
    final chip = checkLook(
      palette: palette,
      checking: checking,
      failed: group.lastCheckFailed,
      checkedAt: group.lastCheckedAt,
      newCount: group.knownRemoteCount,
      checkedLabel: formatRelative(group.lastCheckedAt),
    );
    final warning = group.warningLine(palette);

    return Stack(
      key: ValueKey('collectionRow-${group.id}'),
      children: [
        InkWell(
          onTap: () => context.push('/collection/${group.id}'),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 13, 48, 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                MonogramTile(id: group.id, title: group.displayName),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              group.displayName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 15,
                                height: 1.3,
                                fontVariations: wght(600),
                                fontWeight: FontWeight.w600,
                                color: palette.ink,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          StatusChip(
                            icon: chip.icon,
                            label: chip.label,
                            bg: chip.bg,
                            fg: chip.fg,
                            border: chip.border,
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        group.host,
                        style: monoStyle(color: palette.inkFaint),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Icon(
                            Icons.download_for_offline,
                            size: 15,
                            color: palette.primary,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '${group.offlineCount}',
                            style: TextStyle(
                              fontSize: 12,
                              color: palette.primary,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Icon(Icons.circle, size: 9, color: palette.primary),
                          const SizedBox(width: 4),
                          Text(
                            '${group.unreadOfflineCount} unread',
                            style: TextStyle(
                              fontSize: 12,
                              color: palette.inkMuted,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Flexible(
                            child: Text(
                              group.lastReadAt == null
                                  ? 'never opened'
                                  : formatRelative(group.lastReadAt),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                color: palette.inkFaint,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (warning != null) ...[
                        const SizedBox(height: 7),
                        Row(
                          children: [
                            Icon(warning.icon, size: 15, color: warning.color),
                            const SizedBox(width: 5),
                            Expanded(
                              child: Text(
                                warning.label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: warning.color,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        Positioned(
          top: 0,
          bottom: 0,
          right: 4,
          child: Center(
            child: IconButton(
              tooltip: 'Collection actions',
              icon: const Icon(Icons.more_vert, size: 20),
              color: palette.inkFaint,
              onPressed: () => showCollectionMenu(context, ref, group),
            ),
          ),
        ),
      ],
    );
  }
}

/// The per-collection overflow sheet. Check and rules are wired; rename lives on
/// the collection detail screen, and archive arrives with the lifecycle column.
Future<void> showCollectionMenu(
  BuildContext context,
  WidgetRef ref,
  LibraryCollection group,
) {
  // Read once, before the sheet: the sheet outlives this build's `ref`.
  final queue = ref.read(taskQueueProvider);

  return showModalBottomSheet<void>(
    context: context,
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 10),
            child: Text(
              group.displayName,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: serifStyle(size: 20),
            ),
          ),
          ListTile(
            // Not a sync glyph, and not "check for updates" — both read as
            // "update the app" or "reconcile my devices". The label names the
            // scope (this one collection) and the subtitle names the limit.
            leading: const Icon(Icons.manage_search),
            title: const Text('Check this collection'),
            subtitle: const Text('Look for new entries · nothing downloaded'),
            onTap: () async {
              Navigator.of(sheetContext).pop();
              // The M8 per-collection check, on the queue (M14): runs now if the
              // browser is free, waits its turn otherwise. State lands on the
              // row chip either way. Null means the restricted-site capture
              // policy refused it — a check is discovery for capture.
              final id = await queue.enqueueCollectionCheck(group.id);
              if (id != null || !context.mounted) return;
              ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                const SnackBar(content: Text(kCaptureRestrictedMessage)),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.inventory_2),
            title: const Text('Archive'),
            subtitle: const Text('Hidden from library · reversible'),
            onTap: () {
              Navigator.of(sheetContext).pop();
              confirmArchiveCollection(context, ref, group);
            },
          ),
          ListTile(
            leading: const Icon(Icons.ads_click),
            title: const Text('Element rules'),
            subtitle: Text(group.host),
            onTap: () {
              Navigator.of(sheetContext).pop();
              context.push('/rules');
            },
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}

/// The archive confirm dialog (M16, Q25). States exactly what happens: the
/// collection leaves the library and stops being checked; pending queue tasks are
/// cancelled and the dialog says how many; nothing on disk is touched.
Future<bool> confirmArchiveCollection(
  BuildContext context,
  WidgetRef ref,
  LibraryCollection group,
) async {
  final queue = ref.read(taskQueueProvider);
  final repo = ref.read(collectionRepositoryProvider);
  final pendingCount = (await queue.pendingTasksForCollection(group.id)).length;
  if (!context.mounted) return false;

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) {
      final palette = AppPalette.of(context);
      return AlertDialog(
        icon: Icon(Icons.inventory_2, size: 26, color: palette.primary),
        title: const Text('Archive this collection?'),
        content: Text.rich(
          TextSpan(
            style: TextStyle(
              fontSize: 13,
              height: 1.55,
              color: palette.inkMuted,
            ),
            children: [
              const TextSpan(
                text:
                    'It leaves the library and stops being checked for '
                    'updates. ',
              ),
              if (pendingCount > 0)
                TextSpan(
                  text:
                      'This cancels $pendingCount pending '
                      'task${pendingCount == 1 ? '' : 's'}. ',
                  style: TextStyle(
                    color: palette.onWarnContainer,
                    backgroundColor: palette.warnContainer,
                  ),
                ),
              const TextSpan(
                text:
                    'Downloads stay on the device and you can restore it any '
                    'time.',
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Archive'),
          ),
        ],
      );
    },
  );
  if (confirmed != true) return false;

  await queue.cancelTasksForCollection(group.id);
  await repo.archive(group.id);
  if (context.mounted) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Archived "${group.displayName}".')));
  }
  return true;
}

class _EmptyLibrary extends StatelessWidget {
  const _EmptyLibrary();

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 10, 20, 10),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 26),
      decoration: BoxDecoration(
        color: palette.surfaceMuted,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: palette.border),
      ),
      child: Column(
        children: [
          Icon(Icons.travel_explore, size: 30, color: palette.inkFaint),
          const SizedBox(height: 10),
          Text(
            'Nothing saved yet',
            style: TextStyle(
              fontSize: 16,
              fontVariations: wght(600),
              fontWeight: FontWeight.w600,
              color: palette.ink,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Open an entry in the browser and tap Save. The app scrolls '
            'the page, saves what it finds, and the entry shows up here — '
            'readable offline.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              height: 1.55,
              color: palette.inkMuted,
            ),
          ),
        ],
      ),
    );
  }
}

class _LibrarySkeleton extends StatelessWidget {
  const _LibrarySkeleton();

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      children: [
        for (final w in const [0.62, 0.78, 0.54, 0.70, 0.58, 0.74])
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: palette.surfaceInset,
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      FractionallySizedBox(
                        widthFactor: w,
                        child: Container(
                          height: 12,
                          color: palette.surfaceInset,
                        ),
                      ),
                      const SizedBox(height: 7),
                      FractionallySizedBox(
                        widthFactor: w * 0.6,
                        child: Container(
                          height: 10,
                          color: palette.surfaceMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _LibraryError extends StatelessWidget {
  const _LibraryError({required this.error});

  final String error;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: palette.dangerContainer,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: palette.dangerBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.sd_card_alert, size: 26, color: palette.danger),
              const SizedBox(height: 8),
              Text(
                "Can't read the local library",
                style: TextStyle(
                  fontSize: 17,
                  fontVariations: wght(600),
                  fontWeight: FontWeight.w600,
                  color: palette.onDangerContainer,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'The library database did not open. Your downloaded entries '
                'are still on the device — nothing was deleted.',
                style: TextStyle(
                  fontSize: 13,
                  height: 1.5,
                  color: palette.onDangerContainer,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                error,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: monoStyle(color: palette.danger),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ResumeCard extends ConsumerWidget {
  const _ResumeCard({required this.run});
  final SaveRun run;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final controller = ref.read(saveRunProvider);
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: palette.warnContainer,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: palette.warnBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Unfinished save',
            style: TextStyle(
              fontSize: 13,
              fontVariations: wght(600),
              fontWeight: FontWeight.w600,
              color: palette.onWarnContainer,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '${run.completedEntries} of ${run.requestedEntries} entries '
            'saved before the app closed.',
            style: TextStyle(
              fontSize: 12,
              height: 1.5,
              color: palette.onWarnContainer,
            ),
          ),
          Text(
            run.currentUrl ?? run.startUrl,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: monoStyle(color: palette.warn),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              FilledButton(
                // Through the queue, which brings the Browser forward first
                // (D47) and records the outcome — but as a *direct* run: a
                // resumed save never becomes a pending queue task (D58).
                onPressed: () =>
                    ref.read(taskQueueProvider).resumeInterruptedSave(run),
                child: const Text('Resume'),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: () => controller.discardRun(run),
                child: const Text('Discard'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The one warning a collection row is allowed to show, most serious first.
class CollectionWarning {
  const CollectionWarning(this.icon, this.label, this.color);
  final IconData icon;
  final String label;
  final Color color;
}

/// A collection plus the numbers its library row shows.
/// One row on the library shelf: a [Collection] with its entries, **or** a
/// standalone entry that belongs to no collection.
///
/// A union rather than "wrap the standalone entry in a collection of one". The
/// database has no such row and must not gain one: a phantom group in the
/// library is something the user never made, cannot meaningfully open, and would
/// make "3 collections" mean "3 unrelated articles". [collection] is null for a
/// standalone entry, and [isStandalone] is what screens branch on.
///
/// Known limitation: archiving is a collection-level state, so a standalone
/// entry always reads as `active`. Removing its offline files and re-saving it
/// work exactly as they do for an entry inside a collection.
class LibraryCollection {
  const LibraryCollection({this.collection, required this.entries});

  /// Null when this shelf item *is* a single entry.
  final Collection? collection;
  final List<Entry> entries;

  bool get isStandalone => collection == null;

  /// The one entry, for a standalone shelf item.
  Entry? get standaloneEntry => isStandalone ? entries.firstOrNull : null;

  /// Stable identity for list keys and routes.
  String get id => collection?.id ?? (entries.firstOrNull?.id ?? '');

  String get host => collection?.host ?? (entries.firstOrNull?.host ?? '');

  /// Standalone entries have no archive state of their own.
  String get lifecycle => collection?.lifecycle ?? 'active';

  /// The detected title, and the user's override. Both null for a standalone
  /// entry, whose name is the entry's own title — see [displayName].
  String? get title => collection?.title;
  String? get userTitle => collection?.userTitle;

  /// The finished-entry cleanup decision. Always null for a standalone entry:
  /// the preference is per collection, and there is no forward transition to
  /// apply it to.
  String? get cleanupPreference => collection?.cleanupPreference;
  DateTime? get archivedAt => collection?.archivedAt;
  DateTime? get createdAt =>
      collection?.createdAt ?? entries.firstOrNull?.savedAt;
  DateTime? get lastReadAt =>
      collection?.lastReadAt ?? entries.firstOrNull?.lastReadAt;

  /// The vocabulary this shelf item uses for its entries, from the stored
  /// shape — never a noun typed into a screen.
  EntryLabels get labels => collection == null
      ? labelsFor(
          kind: ContentKind.fromName(entries.firstOrNull?.contentKind),
          confidence: ShapeConfidence.fromName(
            entries.firstOrNull?.contentKindConfidence,
          ),
        )
      : labelsFor(
          kind: ContentKind.fromName(collection!.contentKind),
          sequence: SequenceKind.fromName(collection!.sequenceKind),
          confidence: ShapeConfidence.fromName(collection!.shapeConfidence),
        );

  /// Total the source published, when it published one. Null is the normal
  /// answer and must never be rendered as a number.
  int? get knownEntryTotal => collection?.knownEntryTotal;

  bool get isOpenEnded =>
      SequenceKind.fromName(collection?.sequenceKind).isOpenEnded;

  String get displayName {
    final c = collection;
    if (c != null) return displayNameFor(c);
    final entry = entries.firstOrNull;
    final title = entry?.title.trim() ?? '';
    if (title.isNotEmpty) return title;
    return entry?.host.isNotEmpty == true ? entry!.host : 'Saved page';
  }

  /// Entries a save has at least been attempted for. Discovered-but-not-
  /// saved entries are counted separately — "12 entries" must not
  /// quietly include ones the device does not hold.
  List<Entry> get savedEntries =>
      entries.where((c) => c.saveStatus != 'knownRemote').toList();

  /// Known to exist on the source, not yet saved (from an update check).
  List<Entry> get knownRemoteEntries =>
      entries.where((c) => c.saveStatus == 'knownRemote').toList();

  int get entryCount => savedEntries.length;
  int get knownRemoteCount => knownRemoteEntries.length;

  /// The newest entry the source is known to have, saved or not.
  String? get latestKnownLabel {
    final all = sortEntriesForReading(entries);
    if (all.isEmpty) return null;
    final last = all.last;
    final label = last.sourceMarker;
    return (label != null && label.isNotEmpty) ? label : last.title;
  }

  int get offlineCount => entries
      .where((c) => c.contentPath != null && c.saveStatus != 'failed')
      .length;

  /// Locally readable entries the user has not finished. This is the number
  /// a reader actually wants on the shelf: "how much is waiting for me here".
  int get unreadOfflineCount => entries
      .where(
        (c) =>
            c.contentPath != null &&
            (c.saveStatus == 'complete' || c.saveStatus == 'partial') &&
            c.readStatus != ReadStatus.completed.name,
      )
      .length;

  int get partialEntries =>
      entries.where((c) => c.saveStatus == 'partial').length;
  int get failedEntries =>
      entries.where((c) => c.saveStatus == 'failed').length;
  int get problemEntries => partialEntries + failedEntries;

  /// One line, worst first. Nothing wrong means no line at all — a row without
  /// a warning is the normal case and must not carry an empty slot.
  ///
  /// Takes the palette rather than baking a colour in: this is view data, and
  /// a model that names `0xFF8E3B31` decides what the dark theme looks like
  /// from inside a getter nobody thinks of as presentation.
  CollectionWarning? warningLine(AppPalette palette) {
    if (failedEntries > 0) {
      return CollectionWarning(
        Icons.error,
        '$failedEntries save${failedEntries == 1 ? '' : 's'} failed',
        palette.danger,
      );
    }
    if (partialEntries > 0) {
      return CollectionWarning(
        Icons.arrow_circle_down,
        '${labels.count(partialEntries)} partial',
        palette.warn,
      );
    }
    return null;
  }

  /// Update-check state for the row. `null` means **never checked** — which
  /// the UI must render as "not checked yet", never as zero new entries.
  DateTime? get lastCheckedAt => collection?.lastCheckSuccessAt;
  bool get lastCheckFailed => collection?.lastCheckError != null;

  DateTime? get lastSavedAt {
    DateTime? latest = collection?.lastSavedAt;
    for (final c in entries) {
      final at = c.savedAt;
      if (at == null) continue;
      if (latest == null || at.isAfter(latest)) latest = at;
    }
    return latest;
  }

  /// The most recently saved entry, which is what a reader coming back is
  /// most likely looking for.
  String? get latestEntryLabel {
    Entry? newest;
    for (final c in entries) {
      if (c.savedAt == null) continue;
      if (newest?.savedAt == null || c.savedAt!.isAfter(newest!.savedAt!)) {
        newest = c;
      }
    }
    newest ??= entries.isEmpty ? null : entries.last;
    if (newest == null) return null;
    final label = newest.sourceMarker;
    return (label != null && label.isNotEmpty) ? label : newest.title;
  }
}

String formatRelative(DateTime? t) {
  if (t == null) return 'not saved';
  final diff = DateTime.now().difference(t);
  if (diff.inMinutes < 1) return 'just now';
  if (diff.inHours < 1) return '${diff.inMinutes}m ago';
  if (diff.inDays < 1) return '${diff.inHours}h ago';
  return '${diff.inDays}d ago';
}

String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}
