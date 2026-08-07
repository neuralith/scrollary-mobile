import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../library/library_check.dart';
import '../capability/foreground_gate.dart';
import '../providers.dart';
import '../storage/database.dart';
import '../ui/palette.dart';
import '../ui/status_style.dart';
import '../ui/theme.dart';
import 'foreground_gate_sheet.dart';
import 'library_check_flow.dart';
import 'library_screen.dart' show LibraryCollection, formatRelative;

/// Library updates: **checking many collections as one visible operation**.
///
/// The distinction this screen furniture exists to make is the one a bare
/// refresh glyph destroys. Pulling a list refreshes what is already on the
/// device; a sync reconciles two copies of the same thing. This does neither:
/// it opens each collection's own source, in the Browser, one at a time, and
/// asks whether anything has been published since. Nothing is downloaded, and
/// nothing about the device changes unless the user then chooses to save.
///
/// So the entry point is a labelled card that says what it will do and to how
/// many collections, and never an icon on its own. The work itself is the
/// existing per-collection check, scheduled by the existing queue — see
/// `library/library_check.dart` for why there is exactly one eligibility rule
/// and exactly one checker.

/// What a Library-wide check would cover, and what it would leave out.
class LibraryCheckPreview {
  const LibraryCheckPreview({required this.eligible, required this.excluded});

  /// Collections a run would visit, in library order.
  final List<LibraryCollection> eligible;

  /// Why each excluded shelf item is out, counted. Ordered by the enum so the
  /// same reasons always read in the same order.
  final Map<CollectionCheckBlock, int> excluded;

  int get eligibleCount => eligible.length;
  int get excludedCount => excluded.values.fold(0, (a, b) => a + b);
  bool get hasAnything => eligible.isNotEmpty;

  /// The most recent time any eligible collection was asked — the honest
  /// answer to "when did I last check?", read from rows that already exist
  /// rather than from a stored library-run timestamp.
  DateTime? get lastCheckedAt {
    DateTime? latest;
    for (final group in eligible) {
      final at = group.collection?.lastCheckAt;
      if (at == null) continue;
      if (latest == null || at.isAfter(latest)) latest = at;
    }
    return latest;
  }

  /// How many eligible collections have ever been checked successfully.
  int get everCheckedCount =>
      eligible.where((g) => g.collection?.lastCheckSuccessAt != null).length;
}

/// Split the shelf through the one eligibility predicate.
LibraryCheckPreview libraryCheckPreview(List<LibraryCollection> shelf) {
  final eligible = <LibraryCollection>[];
  final excluded = <CollectionCheckBlock, int>{};
  for (final group in shelf) {
    final block = collectionCheckBlock(
      collection: group.collection,
      entries: group.entries,
    );
    if (block == null) {
      eligible.add(group);
    } else {
      excluded[block] = (excluded[block] ?? 0) + 1;
    }
  }
  return LibraryCheckPreview(
    eligible: eligible,
    excluded: {
      for (final block in CollectionCheckBlock.values)
        if (excluded[block] != null) block: excluded[block]!,
    },
  );
}

/// The Library-wide report, derived from durable rows every rebuild.
LibraryCheckReport watchLibraryCheckReport(
  WidgetRef ref,
  LibraryCheckPlan? plan, {
  bool browserBusyElsewhere = false,
}) {
  final shelf = ref.watch(allLibraryCollectionsProvider).value ?? const [];
  return computeLibraryCheckReport(
    plan: plan,
    tasks: ref.watch(queueTasksProvider).value ?? const <QueueTask>[],
    collections: [
      for (final group in shelf)
        if (group.collection != null) group.collection!,
    ],
    entries: [for (final group in shelf) ...group.entries],
    staleRemoved: ref.read(updateCheckerProvider).staleRemovedByCollection,
    browserBusyElsewhere: browserBusyElsewhere,
  );
}

// --- starting, stopping, dismissing -----------------------------------------

/// Ask first, then start. The sheet is where the scope of the operation is
/// stated: how many collections, which are left out, and that it is a
/// foreground operation that downloads nothing.
///
/// Starting from here is what makes the run a **foreground** one: the queue
/// will bring the Browser forward to work in, so this records what it is
/// about to take over — which tab the user was on and what the Browser's own
/// surface was showing — and [LibraryCheckCompletionWatcher] hands both back
/// when the run reaches a terminal state. None of that reaches the checker,
/// which still knows nothing about tabs or screens.
Future<void> startLibraryCheck(BuildContext context, WidgetRef ref) async {
  final flow = ref.read(libraryCheckFlowProvider);
  final queue = ref.read(taskQueueProvider);
  final presentation = ref.read(browserPresentationProvider);
  final tab = ref.read(shellTabProvider).value;
  final shelf = ref.read(allLibraryCollectionsProvider).value ?? const [];
  final preview = libraryCheckPreview(shelf);

  // Everything the run needs is read before the sheet opens. Nothing after it
  // touches the widget's context or `ref`: the card that offered the check is
  // replaced by the card that reports it, and a run must not be lost because
  // the element that started it went away.
  final choice = await showLibraryCheckSheet(context, ref, preview);
  // Dismissed, or *Not now*: nothing is scheduled and nothing moves.
  if (choice == null) return;
  if (choice == StartChoice.enableAndKeepUsingApp) {
    await setKeepWorkingPreference(ref, true);
  }
  // The one difference the capability makes here. A visible-Browser run owns
  // the foreground: it takes the user to the Browser and owes them the way
  // back, which is what `beginForeground` records. A multitasking run claims
  // nothing about what the user is looking at — it checks, reports and
  // navigates nobody — which is the `unattached` presentation this flow was
  // built with from the start. Same queue, same checker, same report.
  final keepUsingApp = choice != StartChoice.inBrowser;

  // Stamped before the first row exists: everything discovered or checked at
  // or after this instant belongs to this run.
  final startedAt = DateTime.now();
  if (keepUsingApp) {
    flow.beginUnattached(LibraryCheckPlan.preparing(startedAt));
  } else {
    flow.beginForeground(
      plan: LibraryCheckPlan.preparing(startedAt),
      returnTab: tab,
      surfaceBefore: presentation.surface,
      // Only Browser-dependent work moves the user. A run that schedules
      // nothing never leaves the Library, so it has nothing to hand back.
      willUseBrowser: preview.hasAnything,
    );
  }
  final scheduled = await queue.enqueueLibraryCheck();
  flow.attachPlan(
    LibraryCheckPlan(
      startedAt: startedAt,
      collectionIds: [for (final s in scheduled) s.collectionId],
      taskIds: [for (final s in scheduled) s.taskId],
    ),
  );
}

/// Stop the run. The queue's own semantic, unchanged: waiting collections are
/// dropped, the one in flight finishes. Everything already checked is kept —
/// the results are rows, and stopping writes nothing over them.
///
/// Scoped to **this run's rows**: a single-collection check the user queued
/// from a collection screen is not part of what they asked to stop here.
Future<void> stopLibraryCheck(WidgetRef ref) async {
  final flow = ref.read(libraryCheckFlowProvider);
  final plan = flow.plan;
  if (plan == null) return;
  flow.requestStop();
  await ref
      .read(taskQueueProvider)
      .cancelQueuedChecks(onlyTaskIds: plan.taskIds);
}

/// Clear the finished run from the screen. Results stay on the collections
/// themselves; this only puts the card back to its resting state.
void dismissLibraryCheck(WidgetRef ref) =>
    ref.read(libraryCheckFlowProvider).clear();

// --- the pre-run sheet ------------------------------------------------------

Future<StartChoice?> showLibraryCheckSheet(
  BuildContext context,
  WidgetRef ref,
  LibraryCheckPreview preview,
) async {
  final gate = ref.read(foregroundMultitaskingProvider).startGate;
  return showModalBottomSheet<StartChoice>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) {
      final palette = AppPalette.of(sheetContext);
      return SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 6, 20, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Library updates', style: serifStyle(size: 22)),
                const SizedBox(height: 6),
                Text(
                  preview.hasAnything
                      ? 'Scrollary opens each collection’s own source and asks '
                            'whether anything new has been published. You do '
                            'not have to open them one by one.'
                      : 'This is how you check every collection at once, '
                            'without opening them one by one.',
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.5,
                    color: palette.inkMuted,
                  ),
                ),
                const SizedBox(height: 16),
                if (preview.hasAnything)
                  _SheetFact(
                    icon: Icons.manage_search,
                    accent: true,
                    title:
                        '${preview.eligibleCount} '
                        '${preview.eligibleCount == 1 ? 'collection' : 'collections'} '
                        'will be checked',
                    body: preview.lastCheckedAt == null
                        ? 'None of them has been checked before.'
                        : 'Last check ${formatRelative(preview.lastCheckedAt)} · '
                              '${preview.everCheckedCount} of '
                              '${preview.eligibleCount} checked at least once.',
                  )
                else
                  _SheetFact(
                    icon: Icons.travel_explore,
                    title: 'Nothing to check yet',
                    body:
                        'A collection can be checked once it has a saved entry '
                        'and is not archived. Save something first, then come '
                        'back here.',
                  ),
                if (preview.excludedCount > 0) ...[
                  const SizedBox(height: 10),
                  _SheetFact(
                    icon: Icons.remove_circle_outline,
                    title: '${preview.excludedCount} left out',
                    body: [
                      for (final entry in preview.excluded.entries)
                        '${collectionCheckBlockLabel(entry.key)} — '
                            '${entry.value}',
                    ].join('\n'),
                  ),
                ],
                if (preview.hasAnything) ...[
                  const SizedBox(height: 16),
                  const SectionLabel(
                    'WHAT HAPPENS',
                    padding: EdgeInsets.only(bottom: 8),
                  ),
                  _SheetPoint(
                    icon: Icons.visibility,
                    text: gate == StartGate.multitaskingReady
                        ? 'One collection at a time, in the Browser. It runs '
                              'only while the app is open — there is no '
                              'background or scheduled checking.'
                        : 'One collection at a time, in the Browser, while you '
                              'watch. It runs only while the app is open — '
                              'there is no background or scheduled checking.',
                  ),
                  const _SheetPoint(
                    icon: Icons.cloud,
                    text:
                        'Metadata only. Nothing is downloaded: anything new is '
                        'listed for you, and saving it stays a separate step '
                        'you choose.',
                  ),
                  const _SheetPoint(
                    icon: Icons.stop_circle,
                    text:
                        'You can stop at any point. Collections already checked '
                        'keep their results; the rest are simply not checked '
                        'yet.',
                  ),
                ],
                const SizedBox(height: 18),
                if (preview.hasAnything) ...[
                  ForegroundStartActions(
                    key: const ValueKey('confirmLibraryCheck'),
                    gate: gate,
                    action: ForegroundGateAction.startCollectionCheck,
                    inBrowserLabel: 'Check in Browser',
                    keepUsingAppLabel: 'Check and keep using Scrollary',
                    onChoice: (choice) =>
                        Navigator.of(sheetContext).pop(choice),
                  ),
                  const SizedBox(height: 8),
                ],
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(sheetContext).pop(),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: Text(preview.hasAnything ? 'Not now' : 'Close'),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

class _SheetFact extends StatelessWidget {
  const _SheetFact({
    required this.icon,
    required this.title,
    required this.body,
    this.accent = false,
  });

  final IconData icon;
  final String title;
  final String body;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
      decoration: BoxDecoration(
        color: accent ? palette.primaryContainer : palette.surfaceMuted,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: accent ? palette.primaryBorder : palette.border,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            icon,
            size: 20,
            color: accent ? palette.onPrimaryContainer : palette.inkMuted,
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontVariations: wght(600),
                    fontWeight: FontWeight.w600,
                    color: accent ? palette.onPrimaryContainer : palette.ink,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  body,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.45,
                    color: accent
                        ? palette.onPrimaryContainer
                        : palette.inkMuted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SheetPoint extends StatelessWidget {
  const _SheetPoint({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 17, color: palette.inkFaint),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 12.5,
                height: 1.45,
                color: palette.inkMuted,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// --- finishing the foreground run -------------------------------------------

/// Ends the *presentation* of a foreground library-wide run.
///
/// The run itself ends in the queue, which knows nothing about screens. What
/// is left over is what starting it from the Library did to the user: it put
/// them in the Browser to watch. This watches for the run reaching a terminal
/// state and, if the flow still owns that presentation, hands it back — the
/// Browser's own local surface first, then the tab, then the result.
///
/// It is a widget rather than a listener on the flow because presenting needs
/// a `BuildContext`, and it lives in the Library tab because the Library tab
/// is always built inside the shell's `IndexedStack` — so it is watching even
/// while the user is looking at the Browser. Nothing here reaches the checker;
/// a run that does not own the foreground ([LibraryCheckPresentation.unattached])
/// passes through it untouched.
class LibraryCheckCompletionWatcher extends ConsumerStatefulWidget {
  const LibraryCheckCompletionWatcher({super.key});

  @override
  ConsumerState<LibraryCheckCompletionWatcher> createState() =>
      _LibraryCheckCompletionWatcherState();
}

class _LibraryCheckCompletionWatcherState
    extends ConsumerState<LibraryCheckCompletionWatcher> {
  late final LibraryCheckFlow _flow;

  @override
  void initState() {
    super.initState();
    _flow = ref.read(libraryCheckFlowProvider)..addListener(_evaluate);
    // Subscriptions rather than `ref.watch`, deliberately. A run can end while
    // the user is reading — a route pushed *above* the shell — and a widget
    // under a covered route is not rebuilt merely because a stream ticked. The
    // end of a run has to be noticed then too, if only to decide that this
    // flow no longer owns the screen and should keep quiet about it.
    ref.listenManual(queueTasksProvider, (_, _) => _evaluate());
    ref.listenManual(allLibraryCollectionsProvider, (_, _) => _evaluate());
  }

  @override
  void dispose() {
    _flow.removeListener(_evaluate);
    super.dispose();
  }

  /// Has this run ended? Called from listeners, never from `build`.
  void _evaluate() {
    if (!mounted) return;
    if (_flow.plan == null || _flow.completionClaimed) return;
    if (!_report().isTerminal) return;
    // Off the notification, so the sheet is never opened from inside whatever
    // write just landed.
    Future.microtask(_finish);
  }

  List<LibraryCollection> get _shelf =>
      ref.read(allLibraryCollectionsProvider).value ?? const [];

  LibraryCheckReport _report() => computeLibraryCheckReport(
    plan: _flow.plan,
    tasks: ref.read(queueTasksProvider).value ?? const <QueueTask>[],
    collections: [
      for (final group in _shelf)
        if (group.collection != null) group.collection!,
    ],
    entries: [for (final group in _shelf) ...group.entries],
    staleRemoved: ref.read(updateCheckerProvider).staleRemovedByCollection,
  );

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();

  Future<void> _finish() async {
    if (!mounted) return;
    final flow = _flow;
    // Once, for this run, whatever else happened in the meantime.
    if (!flow.claimCompletion()) return;
    // Read again rather than trusting the value that tripped the listener:
    // between the two, the row that ended the run may have been joined by the
    // entries it discovered.
    final report = _report();

    // Does this run still own what the user is looking at? The shell route
    // being the current one is the whole test: the run took the user to a tab
    // *inside* the shell, so being anywhere in it — Library or Browser — means
    // the presentation is still the run's. A pushed route (the reader,
    // Settings, Activity, a collection) is the user having replaced it with
    // something of their own, and that is not something to interrupt for a
    // result the Library card is already holding.
    final isCurrentRoute = ModalRoute.of(context)?.isCurrent ?? true;
    if (!flow.ownsForeground || !isCurrentRoute) {
      flow.releaseForeground();
      return;
    }

    // 1. Give the Browser back what the run covered. Nothing is closed,
    //    cleared or reloaded — see LibraryCheckFlow.restoreBrowserSurface.
    flow.restoreBrowserSurface(ref.read(browserPresentationProvider));
    // 2. Put the user back where they started the run.
    ref.read(shellTabRequestProvider).value = flow.returnTab;
    if (!mounted) return;
    // 3. Show what happened, over the surface they started from. The sheet is
    //    a route, so it does not depend on the tab switch having painted.
    await showLibraryCheckResultSheet(context, report);
  }
}

/// The finished run, presented where it was started.
///
/// Reads the same [LibraryCheckReport] the card reads and says the same words
/// ([libraryCheckResultHead], [libraryCheckResultLines]) — there is one
/// aggregation and one vocabulary, and this is a second view of them, not a
/// second version.
Future<void> showLibraryCheckResultSheet(
  BuildContext context,
  LibraryCheckReport report,
) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  builder: (sheetContext) {
    final palette = AppPalette.of(sheetContext);
    final head = libraryCheckResultHead(report, palette);
    final lines = libraryCheckResultLines(report);
    final followUps = libraryCheckFollowUps(report);

    return SafeArea(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 6, 20, 16),
          child: Column(
            key: const ValueKey('libraryCheckResultSheet'),
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(head.icon, size: 24, color: head.color),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Text(head.title, style: serifStyle(size: 21)),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Semantics(
                label: '${head.title}. ${lines.join('. ')}',
                excludeSemantics: true,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final line in lines)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(
                          line,
                          style: TextStyle(
                            fontSize: 14,
                            height: 1.45,
                            color: palette.ink,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              if (report.phase != LibraryCheckPhase.failedBeforeAnyCheck) ...[
                const SizedBox(height: 8),
                Text(
                  // The sentence that keeps discovery and download apart. It
                  // is here even when nothing was found, because what the user
                  // is being told is what the app did *not* do.
                  'Nothing was downloaded. Saving anything new is a separate '
                  'step you choose.',
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.45,
                    color: palette.inkMuted,
                  ),
                ),
              ],
              if (followUps.isNotEmpty) ...[
                const SizedBox(height: 12),
                const SectionLabel(
                  'WORTH OPENING',
                  padding: EdgeInsets.only(bottom: 4),
                ),
                for (final line in followUps.take(6))
                  _ResultRow(
                    key: ValueKey(
                      'libraryCheckSheetResult-${line.collectionId}',
                    ),
                    line: line,
                    // The sheet is a route above the shell; opening a
                    // collection from it must not leave it hanging over the
                    // screen the user asked for.
                    onOpened: () => Navigator.of(sheetContext).pop(),
                  ),
                if (followUps.length > 6)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      '+${followUps.length - 6} more in your library',
                      style: TextStyle(fontSize: 12, color: palette.inkFaint),
                    ),
                  ),
              ],
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  key: const ValueKey('libraryCheckResultDone'),
                  onPressed: () => Navigator.of(sheetContext).pop(),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: const Text('Done'),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                // Dismissing the sheet is not dismissing the result: the card
                // on the Library keeps it until the user clears it.
                'This stays on the Library until you dismiss it there.',
                style: TextStyle(fontSize: 11.5, color: palette.inkFaint),
              ),
            ],
          ),
        ),
      ),
    );
  },
);

// --- the card on the Library screen -----------------------------------------

/// The Library-wide entry point, and the same card is the run's progress and
/// its result. One place on the screen for one operation, so a user who starts
/// a check does not have to go looking for where it went.
class LibraryUpdatesCard extends ConsumerWidget {
  const LibraryUpdatesCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final flow = ref.watch(libraryCheckFlowProvider);
    // Watched in this element's own build — not inside the builders below —
    // because that is what registers the dependency. A card whose report came
    // from a `ref.watch` buried in a nested builder only updated when
    // something else happened to notify, which is not the same thing as being
    // up to date.
    final shelf = ref.watch(allLibraryCollectionsProvider).value ?? const [];
    final tasks = ref.watch(queueTasksProvider).value ?? const <QueueTask>[];

    return ListenableBuilder(
      listenable: flow,
      builder: (context, _) {
        final plan = flow.plan;
        // The scheduler is consulted only once a run exists. A card that is
        // merely *offering* a check has no reason to depend on it, and reading
        // it at rest made the whole Library screen unbuildable wherever the
        // service graph is not wired up.
        if (plan == null) {
          return _frame(
            context,
            _IdleBody(preview: libraryCheckPreview(shelf)),
          );
        }
        final queue = ref.read(taskQueueProvider);
        return ListenableBuilder(
          listenable: queue,
          builder: (context, _) {
            final report = computeLibraryCheckReport(
              plan: plan,
              tasks: tasks,
              collections: [
                for (final group in shelf)
                  if (group.collection != null) group.collection!,
              ],
              entries: [for (final group in shelf) ...group.entries],
              staleRemoved: ref
                  .read(updateCheckerProvider)
                  .staleRemovedByCollection,
              browserBusyElsewhere: queue.browserOwner != null,
            );
            return _frame(context, switch (report.phase) {
              LibraryCheckPhase.idle => _IdleBody(
                preview: libraryCheckPreview(shelf),
              ),
              LibraryCheckPhase.preparing ||
              LibraryCheckPhase.checking ||
              LibraryCheckPhase.blocked => _RunningBody(report: report),
              _ => _ResultBody(report: report),
            });
          },
        );
      },
    );
  }

  Widget _frame(BuildContext context, Widget child) {
    final palette = AppPalette.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Container(
        decoration: BoxDecoration(
          color: palette.surfaceMuted,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: palette.border),
        ),
        padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
        child: child,
      ),
    );
  }
}

/// Icon, title, supporting lines — the shape every state of the card uses, so
/// starting a check does not make the card jump about.
class _CardHead extends StatelessWidget {
  const _CardHead({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.lines,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 22, color: iconColor),
        const SizedBox(width: 11),
        Expanded(
          child: Semantics(
            // One sentence for a screen reader instead of five fragments read
            // as five separate labels.
            label: '$title. ${lines.join('. ')}',
            excludeSemantics: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.3,
                    fontVariations: wght(600),
                    fontWeight: FontWeight.w600,
                    color: palette.ink,
                  ),
                ),
                for (final line in lines) ...[
                  const SizedBox(height: 3),
                  Text(
                    line,
                    style: TextStyle(
                      fontSize: 12.5,
                      height: 1.4,
                      color: palette.inkMuted,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _IdleBody extends ConsumerWidget {
  const _IdleBody({required this.preview});

  final LibraryCheckPreview preview;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final n = preview.eligibleCount;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _CardHead(
          icon: Icons.manage_search,
          iconColor: palette.inkMuted,
          title: 'Check your collections for new entries',
          lines: [
            n == 0
                ? 'No collection can be checked yet.'
                : '$n ${n == 1 ? 'collection' : 'collections'} can be checked'
                      '${preview.excludedCount > 0 ? ' · ${preview.excludedCount} left out' : ''}',
            if (n > 0)
              preview.lastCheckedAt == null
                  ? 'Never checked · nothing is downloaded'
                  : 'Last check ${formatRelative(preview.lastCheckedAt)} · '
                        'nothing is downloaded',
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            key: const ValueKey('libraryCheckAllButton'),
            onPressed: () => startLibraryCheck(context, ref),
            icon: const Icon(Icons.manage_search, size: 19),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 13),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            label: const FittedBox(
              fit: BoxFit.scaleDown,
              child: Text('Check all collections'),
            ),
          ),
        ),
      ],
    );
  }
}

class _RunningBody extends ConsumerWidget {
  const _RunningBody({required this.report});

  final LibraryCheckReport report;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final total = report.total;
    final done = report.checkedCount;
    final blocked = report.phase == LibraryCheckPhase.blocked;
    final preparing = report.phase == LibraryCheckPhase.preparing;

    final counts = [
      '$done checked',
      if (report.newEntryCount > 0)
        '${report.newEntryCount} new '
            '${report.newEntryCount == 1 ? 'entry' : 'entries'} found',
      if (report.needsAttentionCount > 0)
        '${report.needsAttentionCount} '
            '${report.needsAttentionCount == 1 ? 'needs' : 'need'} attention',
      '${report.remainingCount} remaining',
    ].join(' · ');

    final where = preparing
        ? 'Preparing the list of collections…'
        : blocked
        ? 'Waiting for the Browser — something else is using it. This starts '
              'as soon as it is free.'
        : report.currentTitle != null
        ? 'Now checking “${report.currentTitle}”'
        : 'Waiting for the next collection.';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _CardHead(
          icon: Icons.manage_search,
          iconColor: palette.primary,
          title: preparing
              ? 'Starting a library check'
              : 'Checking $total ${total == 1 ? 'collection' : 'collections'}',
          lines: [if (!preparing) counts, where],
        ),
        const SizedBox(height: 12),
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(
            // A determinate bar is honest here in a way it is not inside one
            // collection's check: the number of collections is known before
            // the first page opens.
            value: total == 0 ? null : done / total,
            minHeight: 5,
            backgroundColor: palette.border,
            color: palette.primary,
            semanticsLabel: 'Collections checked',
            // A percentage, because this is a progress bar's *value*: a
            // sentence here is rejected outright by the semantics layer. The
            // counts are read out by the card's own label above.
            semanticsValue: total == 0
                ? null
                : '${(done / total * 100).round()}%',
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                key: const ValueKey('stopLibraryCheckButton'),
                onPressed: preparing ? null : () => stopLibraryCheck(ref),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                child: const FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text('Stop after this collection'),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// How a finished run is named, in one place.
///
/// The card and the completion sheet are two views of the same terminal
/// report, so they say the same words: a second wording is how "9 up to date"
/// on one surface becomes "everything is fine" on the other.
({IconData icon, Color color, String title}) libraryCheckResultHead(
  LibraryCheckReport report,
  AppPalette palette,
) => switch (report.phase) {
  LibraryCheckPhase.failedBeforeAnyCheck => (
    icon: Icons.error_outline,
    color: palette.warn,
    title: 'No collection was checked',
  ),
  LibraryCheckPhase.cancelled => (
    icon: Icons.stop_circle,
    color: palette.inkMuted,
    title: 'Library check stopped',
  ),
  LibraryCheckPhase.partiallyCompleted => (
    icon: Icons.error_outline,
    color: palette.warn,
    title: 'Library check partly finished',
  ),
  _ when report.newEntryCount > 0 => (
    icon: Icons.cloud,
    color: palette.primary,
    title: 'Library check complete',
  ),
  _ => (
    icon: Icons.update,
    color: palette.inkMuted,
    title: 'Library check complete',
  ),
};

/// What a finished run actually did, line by line.
///
/// The work is stated even when there is nothing new: a run that found nothing
/// still asked every source, and hiding that makes the feature look like it
/// did nothing.
List<String> libraryCheckResultLines(LibraryCheckReport report) {
  final newEntries = report.newEntryCount;
  final withNew = report.withNewEntriesCount;
  if (report.phase == LibraryCheckPhase.failedBeforeAnyCheck) {
    return const [
      'Nothing was scheduled, so no source was opened and nothing changed.',
    ];
  }
  return [
    '${report.checkedCount} '
        '${report.checkedCount == 1 ? 'collection' : 'collections'} checked',
    if (newEntries > 0)
      '$newEntries new ${newEntries == 1 ? 'entry' : 'entries'} in $withNew '
          '${withNew == 1 ? 'collection' : 'collections'} — not downloaded'
    else if (report.upToDateCount > 0)
      'Everything is up to date',
    // Its own line, and never added to the count above: an entry that appeared
    // and an entry that went away are opposite results, and only one of them
    // is something to go and save. Nothing here was ever downloaded, so the
    // sentence says so rather than reading as a deletion.
    if (report.staleRemovedCount > 0)
      '${report.staleRemovedCount} '
          '${report.staleRemovedCount == 1 ? 'entry is' : 'entries are'} no '
          'longer at the source and '
          '${report.staleRemovedCount == 1 ? 'was' : 'were'} taken off the '
          'list — none had been downloaded',
    if (report.needsAttentionCount > 0)
      '${report.needsAttentionCount} '
          '${report.needsAttentionCount == 1 ? 'collection needs' : 'collections need'} '
          'attention',
    if (report.notCheckedCount > 0) '${report.notCheckedCount} not checked',
  ];
}

/// The collections worth opening after a run: something new, or something
/// wrong. Never more than the card or sheet can show without becoming a list.
List<CollectionCheckLine> libraryCheckFollowUps(LibraryCheckReport report) => [
  ...report.withNewEntries,
  ...report.needingAttention,
];

class _ResultBody extends ConsumerWidget {
  const _ResultBody({required this.report});

  final LibraryCheckReport report;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final head = libraryCheckResultHead(report, palette);
    final (icon, iconColor, title) = (head.icon, head.color, head.title);
    final lines = libraryCheckResultLines(report);
    final followUps = libraryCheckFollowUps(report);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _CardHead(icon: icon, iconColor: iconColor, title: title, lines: lines),
        if (followUps.isNotEmpty) ...[
          const SizedBox(height: 11),
          for (final line in followUps.take(6))
            _ResultRow(
              key: ValueKey('libraryCheckResult-${line.collectionId}'),
              line: line,
            ),
          if (followUps.length > 6)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                '+${followUps.length - 6} more in your library',
                style: TextStyle(fontSize: 12, color: palette.inkFaint),
              ),
            ),
        ],
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                key: const ValueKey('dismissLibraryCheckButton'),
                onPressed: () => dismissLibraryCheck(ref),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                child: const Text('Dismiss'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton(
                key: const ValueKey('libraryCheckAgainButton'),
                // Not "dismiss, then start": clearing the plan first would
                // rebuild this card away and take the context the sheet needs
                // with it. Confirming replaces the finished run on its own.
                onPressed: () => startLibraryCheck(context, ref),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                child: const FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text('Check again'),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// One collection worth opening after a run: it has something new, or it could
/// not be checked. Tapping opens the collection — the run never opens anything
/// on its own.
class _ResultRow extends StatelessWidget {
  const _ResultRow({super.key, required this.line, this.onOpened});

  final CollectionCheckLine line;

  /// Run just before the collection opens. The sheet uses it to close itself
  /// so the user does not arrive behind it.
  final VoidCallback? onOpened;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final isNew = line.outcome == CollectionCheckOutcome.newEntries;
    final retracted = line.staleRemoved > 0
        ? ' · ${line.staleRemoved} no longer at the source'
        : '';
    final detail = isNew
        ? '${line.newEntries} new '
              '${line.newEntries == 1 ? 'entry' : 'entries'} · not downloaded'
              '$retracted'
        : (line.detail ?? 'Could not be checked');

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          onOpened?.call();
          context.push('/collection/${line.collectionId}');
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          child: Row(
            children: [
              Icon(
                isNew ? Icons.cloud : Icons.error_outline,
                size: 18,
                color: isNew ? palette.primary : palette.warn,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      line.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontVariations: wght(500),
                        fontWeight: FontWeight.w500,
                        color: palette.ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      detail,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11.5, color: palette.inkMuted),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, size: 18, color: palette.inkFaint),
            ],
          ),
        ),
      ),
    );
  }
}
