import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:web_reader/browser/page_data.dart';
import 'package:web_reader/features/library_check_flow.dart';
import 'package:web_reader/features/library_screen.dart';
import 'package:web_reader/library/library_check.dart';
import 'package:web_reader/library/update_checker.dart';
import 'package:web_reader/providers.dart';
import 'package:web_reader/queue/task_queue.dart';
import 'package:web_reader/save/save_run.dart';
import 'package:web_reader/storage/database.dart';
import 'package:web_reader/storage/file_store.dart';
import 'package:web_reader/ui/theme.dart';

import 'helpers/fake_browser.dart';

/// Checking **many collections as one operation**, and saying so.
///
/// The properties this file exists to hold, in the order they matter:
///
/// 1. one eligibility rule, asked by the queue and by the screen, so the count
///    the user is shown is the count that runs;
/// 2. one checker — a library-wide run *is* the per-collection check, repeated;
/// 3. a report that stays true when a collection finds nothing, finds
///    something, cannot be checked, or is never reached;
/// 4. discovery is never a download.
void main() {
  late AppDatabase db;
  late Directory root;
  late FakeBrowser browser;

  const host = 'https://x.example';

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    root = Directory.systemTemp.createTempSync('webread_library_check');
    browser = FakeBrowser();
  });

  tearDown(() async {
    await db.close();
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  Collection collectionRow(
    String id, {
    String lifecycle = 'active',
    String? collectionHost,
    String? sourceUrl,
    String? indexUrl,
    String? key,
  }) => Collection(
    contentKind: 'unknownWebContent',
    sequenceKind: 'none',
    orderingBasis: 'discoveryOrder',
    shapeConfidence: 'low',
    lifecycle: lifecycle,
    id: id,
    title: 'Collection $id',
    sourceUrl: sourceUrl ?? '$host/guide/$id',
    host: collectionHost ?? 'x.example',
    collectionKey: key ?? '/guide/$id',
    collectionIndexUrl: indexUrl,
    createdAt: DateTime(2026, 7, 1),
  );

  Entry entryRow(
    String collectionId,
    int n, {
    String? url,
    String saveStatus = 'complete',
  }) => Entry(
    host: 'x.example',
    contentKind: 'unknownWebContent',
    contentKindConfidence: 'low',
    contentKindIsUserSet: false,
    id: '$collectionId-c$n',
    collectionId: collectionId,
    title: 'Entry $n',
    sourceUrl: url ?? '$host/guide/$collectionId/$n',
    urlKey: url ?? '$host/guide/$collectionId/$n',
    artifactFormat: 'imageSequence',
    saveStatus: saveStatus,
    contentPath: 'library/$collectionId/entries/$collectionId-c$n',
    savedAt: DateTime(2026, 7, 10),
    detectedAssetCount: 1,
    storedAssetCount: 1,
    entryOrder: n,
    byteSize: 16,
    entryNumber: n.toDouble(),
    sourceMarker: 'Entry $n',
    readStatus: 'unread',
    progressFraction: 0,
    progressPageIndex: 0,
    progressOffsetInPage: 0,
  );

  Future<void> seed(
    String id, {
    String lifecycle = 'active',
    String? collectionHost,
    String? sourceUrl,
    String? indexUrl,
    int entries = 1,
  }) async {
    await db.upsertCollection(
      collectionRow(
        id,
        lifecycle: lifecycle,
        collectionHost: collectionHost,
        sourceUrl: sourceUrl,
        indexUrl: indexUrl,
      ),
    );
    for (var n = 1; n <= entries; n++) {
      await db.upsertEntry(entryRow(id, n));
    }
  }

  TaskQueueController makeQueue({
    UpdateChecker? checker,
    List<String>? executed,
    Map<String, QueueOutcome>? outcomes,
    Map<String, Completer<QueueOutcome>>? gates,
  }) {
    final queue = TaskQueueController(
      db: db,
      browser: browser,
      saveRun: SaveRunController(
        browser: browser,
        db: db,
        fileStore: FileStore(root),
      ),
      checker: checker ?? UpdateChecker(browser: browser, db: db),
      checkRunner: checker != null
          ? null
          : (task) async {
              executed?.add(task.collectionId ?? task.id);
              final gate = gates?[task.collectionId];
              if (gate != null) return gate.future;
              return outcomes?[task.collectionId] ??
                  const QueueOutcome.success('up to date');
            },
    );
    queue.ensureBrowserVisible = ({url}) async => true;
    return queue;
  }

  /// Let the pump and whatever it started make progress. Real milliseconds
  /// rather than microtask turns: the checker and the scheduler both await
  /// timers, so counting turns is not a way of waiting for them.
  Future<void> settle([int ms = 120]) =>
      Future<void>.delayed(Duration(milliseconds: ms));

  /// Wait until the queue has nothing left to run.
  Future<void> settleQueue(TaskQueueController queue) async {
    for (var i = 0; i < 200; i++) {
      await settle(15);
      if (!queue.isRunning && (await db.pendingQueueTasks()).isEmpty) return;
    }
    fail('the queue never drained');
  }

  Future<LibraryCheckReport> reportFor(
    LibraryCheckPlan plan, {
    bool browserBusyElsewhere = false,
  }) async => computeLibraryCheckReport(
    plan: plan,
    tasks: await db.watchQueueTasks().first,
    collections: await db.allCollections(),
    entries: await db.allEntries(),
    browserBusyElsewhere: browserBusyElsewhere,
  );

  /// What the screen does: enqueue, and remember which rows are this run's.
  Future<LibraryCheckPlan> startRun(TaskQueueController queue) async {
    final startedAt = DateTime.now();
    final scheduled = await queue.enqueueLibraryCheck();
    return LibraryCheckPlan(
      startedAt: startedAt,
      collectionIds: [for (final s in scheduled) s.collectionId],
      taskIds: [for (final s in scheduled) s.taskId],
    );
  }

  // --- 1. one eligibility rule ----------------------------------------------

  group('which collections a library check covers', () {
    test('an ordinary collection with a saved entry is eligible', () {
      expect(
        collectionCheckBlock(
          collection: collectionRow('s1'),
          entries: [entryRow('s1', 1)],
        ),
        isNull,
      );
    });

    test('archived is asleep', () {
      expect(
        collectionCheckBlock(
          collection: collectionRow('s1', lifecycle: 'archived'),
          entries: [entryRow('s1', 1)],
        ),
        CollectionCheckBlock.archived,
      );
    });

    test('a restricted source is refused, by host or by either URL', () {
      expect(
        collectionCheckBlock(
          collection: collectionRow('s1', collectionHost: 'www.netflix.com'),
          entries: [entryRow('s1', 1)],
        ),
        CollectionCheckBlock.restrictedSource,
      );
      expect(
        collectionCheckBlock(
          collection: collectionRow(
            's2',
            sourceUrl: 'https://tv.apple.com/show/example',
          ),
          entries: [entryRow('s2', 1)],
        ),
        CollectionCheckBlock.restrictedSource,
      );
    });

    test('a collection with nothing to start from is left out', () {
      // No saved entry at all: the checker itself refuses this, so scheduling
      // it would only produce a row that fails.
      expect(
        collectionCheckBlock(
          collection: collectionRow('s1'),
          entries: const [],
        ),
        CollectionCheckBlock.nothingToCheckYet,
      );
      // Entries, but none with a page address and no collection page either.
      expect(
        collectionCheckBlock(
          collection: collectionRow('s1'),
          entries: [entryRow('s1', 1, url: '')],
        ),
        CollectionCheckBlock.nothingToCheckYet,
      );
      // The same collection *with* an index page is checkable again.
      expect(
        collectionCheckBlock(
          collection: collectionRow('s1', indexUrl: '$host/guide/s1'),
          entries: [entryRow('s1', 1, url: '')],
        ),
        isNull,
      );
    });

    test('a standalone entry is not a collection to check', () {
      expect(
        collectionCheckBlock(collection: null, entries: [entryRow('none', 1)]),
        CollectionCheckBlock.standalone,
      );
    });

    test('the queue schedules exactly the eligible collections', () async {
      await seed('ok-1');
      await seed('ok-2');
      await seed('sleeping', lifecycle: 'archived');
      await seed('blocked', collectionHost: 'www.netflix.com');
      await db.upsertCollection(collectionRow('empty')); // no entries
      browser.automationOwner = 'hold'; // nothing runs during the assertion
      final queue = makeQueue();

      final scheduled = await queue.enqueueLibraryCheck();

      expect(
        scheduled.map((s) => s.collectionId).toSet(),
        {'ok-1', 'ok-2'},
        reason: 'archived, restricted and unstartable collections are not work',
      );
      final rows = await db.watchQueueTasks().first;
      expect(rows, hasLength(2));
      expect(rows.map((t) => t.taskType).toSet(), {
        QueueTaskType.collectionCheck.name,
      });
    });

    test('the preview count is the count that runs', () async {
      await seed('ok-1');
      await seed('sleeping', lifecycle: 'archived');
      browser.automationOwner = 'hold';
      final queue = makeQueue();

      final checkable = await queue.checkableCollections();
      final scheduled = await queue.enqueueLibraryCheck();

      expect(checkable.map((c) => c.id), scheduled.map((s) => s.collectionId));
    });
  });

  // --- 2. one checker -------------------------------------------------------

  group('a library run is the per-collection check, repeated', () {
    /// A collection page listing entries 1..n, newest first.
    PageProbe listPage(String id, int upTo) => PageProbe(
      url: '$host/guide/$id',
      title: 'Collection $id',
      readyState: 'complete',
      documentHeight: 2000,
      viewportHeight: 800,
      links: [
        for (var n = upTo; n >= 1; n--)
          PageLink(href: '/guide/$id/$n', text: 'Entry $n'),
      ],
    );

    test('every eligible collection goes through UpdateChecker', () async {
      await seed('quiet', indexUrl: '$host/guide/quiet', entries: 3);
      await seed('busy', indexUrl: '$host/guide/busy', entries: 3);
      // "quiet" lists exactly what is already held; "busy" lists two more.
      browser.addPage('$host/guide/quiet', listPage('quiet', 3));
      browser.addPage('$host/guide/busy', listPage('busy', 5));
      final checker = UpdateChecker(
        browser: browser,
        db: db,
        config: const UpdateCheckConfig(cooldownBetweenPages: Duration.zero),
      );
      final queue = makeQueue(checker: checker);

      final plan = await startRun(queue);
      await settleQueue(queue);
      final report = await reportFor(plan);

      expect(report.total, 2);
      expect(report.checkedCount, 2, reason: 'both collections were asked');
      expect(report.phase, LibraryCheckPhase.completed);
      expect(report.newEntryCount, 2);
      expect(report.withNewEntriesCount, 1);
      expect(report.upToDateCount, 1);
      expect(report.needsAttentionCount, 0);
      // The authoritative per-collection state was written by the checker, not
      // by the library run.
      for (final item in await db.allCollections()) {
        expect(item.lastCheckSuccessAt, isNotNull);
        expect(item.lastCheckResult, isNotNull);
      }
    });

    test('discovery is never a download', () async {
      await seed('busy', indexUrl: '$host/guide/busy', entries: 3);
      browser.addPage('$host/guide/busy', listPage('busy', 5));
      final checker = UpdateChecker(
        browser: browser,
        db: db,
        config: const UpdateCheckConfig(cooldownBetweenPages: Duration.zero),
      );
      final queue = makeQueue(checker: checker);

      final plan = await startRun(queue);
      await settleQueue(queue);

      final report = await reportFor(plan);
      expect(report.newEntryCount, 2);
      final discovered = (await db.allEntries())
          .where((c) => c.saveStatus == 'knownRemote')
          .toList();
      expect(discovered, hasLength(2));
      for (final entry in discovered) {
        expect(entry.contentPath, isNull, reason: 'nothing was written');
        expect(entry.savedAt, isNull);
        expect(entry.byteSize, 0);
      }
      // And nothing queued itself to fetch them: saving stays an explicit act.
      final rows = await db.watchQueueTasks().first;
      expect(
        rows.where(
          (t) => taskWaitsForExplicitStart(queueTaskTypeFromName(t.taskType)),
        ),
        isEmpty,
      );
    });

    test('a run finding nothing still reports the work it did', () async {
      await seed('quiet-1', indexUrl: '$host/guide/quiet-1', entries: 3);
      await seed('quiet-2', indexUrl: '$host/guide/quiet-2', entries: 3);
      browser.addPage('$host/guide/quiet-1', listPage('quiet-1', 3));
      browser.addPage('$host/guide/quiet-2', listPage('quiet-2', 3));
      final queue = makeQueue(
        checker: UpdateChecker(
          browser: browser,
          db: db,
          config: const UpdateCheckConfig(cooldownBetweenPages: Duration.zero),
        ),
      );

      final plan = await startRun(queue);
      await settleQueue(queue);
      final report = await reportFor(plan);

      expect(report.phase, LibraryCheckPhase.completed);
      expect(report.checkedCount, 2, reason: '"nothing new" is still work');
      expect(report.upToDateCount, 2);
      expect(report.newEntryCount, 0);
    });
  });

  // --- 3. an honest report --------------------------------------------------

  group('the report stays true', () {
    test('one failing collection keeps the others’ results', () async {
      await seed('a');
      await seed('b');
      await seed('c');
      final queue = makeQueue(
        outcomes: {'b': const QueueOutcome.failure('source unreachable')},
      );

      final plan = await startRun(queue);
      await settleQueue(queue);
      // The checker writes the per-collection result; the stubbed runner does
      // not, so the two that succeeded are stamped the way a real check would.
      for (final id in ['a', 'c']) {
        await db.writeCollectionCheck(
          id,
          CollectionsCompanion(
            lastCheckAt: Value(DateTime.now()),
            lastCheckSuccessAt: Value(DateTime.now()),
            lastCheckResult: const Value('upToDate'),
          ),
        );
      }
      final report = await reportFor(plan);

      expect(report.phase, LibraryCheckPhase.partiallyCompleted);
      expect(report.checkedCount, 3);
      expect(report.upToDateCount, 2, reason: 'a failure erases no result');
      expect(report.needsAttentionCount, 1);
      expect(report.needingAttention.single.collectionId, 'b');
      expect(
        report.needingAttention.single.detail,
        contains('source unreachable'),
      );
    });

    test('stopping keeps what was checked and leaves the rest alone', () async {
      await seed('a');
      await seed('b');
      await seed('c');
      final gate = Completer<QueueOutcome>();
      final executed = <String>[];
      final queue = makeQueue(executed: executed, gates: {'a': gate});

      final plan = await startRun(queue);
      await settle();
      expect(executed, ['a'], reason: 'one at a time');

      // The card's Stop: waiting collections are dropped, the one in flight
      // finishes — the queue's own semantic, unchanged.
      await queue.cancelQueuedChecks();
      gate.complete(const QueueOutcome.success('up to date'));
      await settle();
      await db.writeCollectionCheck(
        'a',
        CollectionsCompanion(
          lastCheckAt: Value(DateTime.now()),
          lastCheckSuccessAt: Value(DateTime.now()),
          lastCheckResult: const Value('upToDate'),
        ),
      );

      final report = await reportFor(plan.asStopping());
      expect(report.phase, LibraryCheckPhase.cancelled);
      expect(report.checkedCount, 1, reason: 'the finished one is kept');
      expect(report.upToDateCount, 1);
      expect(report.notCheckedCount, 2);
      expect(executed, ['a'], reason: 'the rest were never opened');
      // Cancelling is not deletion: every collection and entry is still here.
      expect(await db.allCollections(), hasLength(3));
      expect(await db.allEntries(), hasLength(3));
    });

    test('a run cancelled before anything ran is not a success', () async {
      await seed('a');
      await seed('b');
      browser.automationOwner = 'hold';
      final queue = makeQueue();

      final plan = await startRun(queue);
      await queue.cancelQueuedChecks();
      final report = await reportFor(plan.asStopping());

      expect(report.phase, LibraryCheckPhase.cancelled);
      expect(report.checkedCount, 0);
      expect(report.notCheckedCount, 2);
    });

    test('work still waiting for the Browser reads as blocked', () async {
      await seed('a');
      await seed('b');
      // A direct save owns the shared WebView: the checks are queued, not
      // failed, and the card says so rather than reporting progress.
      browser.automationOwner = 'a save';
      final queue = makeQueue();

      final plan = await startRun(queue);
      await settle();

      final blocked = await reportFor(plan, browserBusyElsewhere: true);
      expect(blocked.phase, LibraryCheckPhase.blocked);
      expect(blocked.remainingCount, 2);
      expect(blocked.checkedCount, 0);
      final rows = await db.watchQueueTasks().first;
      expect(rows.map((t) => t.state).toSet(), {QueueTaskState.queued.name});
    });

    test('mid-run reads as checking, with the collection named', () async {
      await seed('a');
      await seed('b');
      final gate = Completer<QueueOutcome>();
      final queue = makeQueue(gates: {'a': gate});

      final plan = await startRun(queue);
      await settle();
      final report = await reportFor(plan);

      expect(report.phase, LibraryCheckPhase.checking);
      expect(report.currentTitle, 'Collection a');
      expect(report.remainingCount, 2);
      expect(report.checkedCount, 0);
      gate.complete(const QueueOutcome.success('up to date'));
      await settle();
    });

    test('a plan that scheduled nothing is not a completed run', () async {
      final report = await reportFor(
        LibraryCheckPlan(
          startedAt: DateTime.now(),
          collectionIds: const [],
          taskIds: const [],
        ),
      );
      expect(report.phase, LibraryCheckPhase.failedBeforeAnyCheck);
    });
  });

  // --- 4. the screen --------------------------------------------------------

  group('the library screen states the operation', () {
    Widget harness({LibraryCheckPlan? plan}) {
      final services = AppServices(
        db: db,
        fileStore: FileStore(root),
        browser: browser,
        saveRun: SaveRunController(
          browser: browser,
          db: db,
          fileStore: FileStore(root),
        ),
      );
      final flow = LibraryCheckFlow();
      addTearDown(flow.dispose);
      // Seeded as a run that owns nothing on screen: this group is about what
      // the card says, not about the foreground flow's navigation, which
      // `library_check_flow_test.dart` covers.
      if (plan != null) flow.beginUnattached(plan);
      return ProviderScope(
        overrides: [
          appServicesProvider.overrideWithValue(services),
          libraryCheckFlowProvider.overrideWithValue(flow),
        ],
        child: MaterialApp.router(
          theme: appTheme(),
          routerConfig: GoRouter(
            routes: [
              GoRoute(path: '/', builder: (_, _) => const LibraryScreen()),
              GoRoute(
                path: '/collection/:id',
                builder: (_, _) => const SizedBox(),
              ),
              GoRoute(path: '/storage', builder: (_, _) => const SizedBox()),
              GoRoute(path: '/archived', builder: (_, _) => const SizedBox()),
              GoRoute(path: '/settings', builder: (_, _) => const SizedBox()),
              GoRoute(path: '/activity', builder: (_, _) => const SizedBox()),
            ],
          ),
        ),
      );
    }

    /// A tall surface. The pre-run sheet states the whole scope of the
    /// operation, which does not fit in the 600pt default — and a tap that
    /// lands past the bottom edge hits the barrier and reads as "not now".
    void useTallScreen(WidgetTester tester) {
      tester.view.physicalSize = const Size(900, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
    }

    Future<void> pumpUntil(WidgetTester tester, Finder finder) async {
      for (var i = 0; i < 60; i++) {
        await tester.pump(const Duration(milliseconds: 20));
        if (finder.evaluate().isNotEmpty) return;
      }
      expect(finder, findsWidgets);
    }

    /// Bounded pumping. `pumpAndSettle` cannot be used on this screen: the
    /// library streams keep scheduling frames, so "settled" never arrives.
    Future<void> pumpFrames(WidgetTester tester, [int frames = 12]) async {
      for (var i = 0; i < frames; i++) {
        await tester.pump(const Duration(milliseconds: 30));
      }
    }

    Future<void> drain(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 10));
    }

    testWidgets('the entry point is a label, not a glyph', (tester) async {
      await seed('a');
      await seed('b');

      await tester.pumpWidget(harness());
      await pumpUntil(tester, find.text('Check all collections'));

      // The scope is on screen before anything is tapped, in words.
      expect(find.text('LIBRARY UPDATES'), findsOneWidget);
      expect(
        find.text('Check your collections for new entries'),
        findsOneWidget,
      );
      expect(
        find.textContaining('2 collections can be checked'),
        findsOneWidget,
      );
      expect(find.textContaining('nothing is downloaded'), findsOneWidget);
      // And it is not a bare toolbar icon any more.
      expect(find.byIcon(Icons.sync), findsNothing);
      await drain(tester);
    });

    testWidgets('excluded collections are counted, not hidden', (tester) async {
      await seed('a');
      await seed('sleeping', lifecycle: 'archived');

      await tester.pumpWidget(harness());
      await pumpUntil(tester, find.text('Check all collections'));

      expect(
        find.textContaining('1 collection can be checked'),
        findsOneWidget,
      );
      expect(find.textContaining('1 left out'), findsOneWidget);
      await drain(tester);
    });

    testWidgets('nothing eligible gets an explanation, not a no-op run', (
      tester,
    ) async {
      useTallScreen(tester);
      // On the shelf, but not checkable: its source is a service this app
      // does not save from. (An archived-only library shows no card at all —
      // the library's own empty state already says what to do.)
      await seed('blocked', collectionHost: 'www.netflix.com');

      await tester.pumpWidget(harness());
      await pumpUntil(
        tester,
        find.textContaining('No collection can be checked'),
      );

      await tester.tap(find.byKey(const ValueKey('libraryCheckAllButton')));
      await pumpFrames(tester);

      expect(find.text('Nothing to check yet'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('confirmLibraryCheck')),
        findsNothing,
        reason: 'there is nothing to start',
      );
      expect(await db.pendingQueueTasks(), isEmpty);
      await tester.tap(find.text('Close'));
      await pumpFrames(tester);
      await drain(tester);
    });

    testWidgets('the sheet states the scope before the run starts', (
      tester,
    ) async {
      useTallScreen(tester);
      await seed('a');
      await seed('b');
      await seed('sleeping', lifecycle: 'archived');
      browser.automationOwner = 'hold';

      await tester.pumpWidget(harness());
      await pumpUntil(tester, find.text('Check all collections'));
      await tester.tap(find.byKey(const ValueKey('libraryCheckAllButton')));
      await pumpFrames(tester);

      expect(find.text('Library updates'), findsOneWidget);
      expect(
        find.textContaining('2 collections will be checked'),
        findsOneWidget,
      );
      expect(find.textContaining('Archived — 1'), findsOneWidget);
      expect(find.textContaining('no background'), findsOneWidget);
      expect(find.textContaining('Metadata only'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('confirmLibraryCheck')));
      await pumpFrames(tester);

      final rows = await db.pendingQueueTasks();
      expect(rows, hasLength(2), reason: 'exactly the eligible collections');
      await drain(tester);
    });

    testWidgets('a finished run reports the work, not just the finds', (
      tester,
    ) async {
      await seed('a');
      await seed('b');
      final now = DateTime.now();
      final plan = LibraryCheckPlan(
        startedAt: now.subtract(const Duration(minutes: 1)),
        collectionIds: const ['a', 'b'],
        taskIds: const ['t-a', 't-b'],
      );
      for (final (id, task) in [('a', 't-a'), ('b', 't-b')]) {
        await db.upsertQueueTask(
          QueueTask(
            id: task,
            taskType: QueueTaskType.collectionCheck.name,
            captureModeIsUserSet: false,
            collectionId: id,
            origin: kQueueOriginQueue,
            state: QueueTaskState.completed.name,
            orderIndex: 0,
            queuedAt: now,
            finishedAt: now,
          ),
        );
        await db.writeCollectionCheck(
          id,
          CollectionsCompanion(
            lastCheckAt: Value(now),
            lastCheckSuccessAt: Value(now),
            lastCheckResult: const Value('upToDate'),
          ),
        );
      }

      await tester.pumpWidget(harness(plan: plan));
      await pumpUntil(tester, find.text('Library check complete'));

      // The work is on screen even though nothing was found.
      expect(find.text('2 collections checked'), findsOneWidget);
      expect(find.text('Everything is up to date'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('dismissLibraryCheckButton')),
        findsOneWidget,
      );
      await drain(tester);
    });
  });

  // --- 5. nothing was smuggled in -------------------------------------------

  test('no entitlement, usage-counter or purchase state exists in lib/', () {
    // Note: `paywall` is deliberately absent. In this app it names a *site's*
    // paywall — a stopping condition — which is the opposite of a paywall the
    // app puts in front of its own features.
    //
    // **`lib/capability/` is exempt, and only it.** This guard was written when
    // nothing in the product was paid, and its real subject is stated in its
    // own failure message: *checking is unrestricted*. That is still true —
    // Library checks, saves, recovery, retry and every byte already on disk are
    // ungated and cannot be gated, because the capability seam reaches exactly
    // one behaviour: whether an operation may continue while another screen is
    // in front. What the guard forbids everywhere else is unchanged, so a
    // counter, a purchase record or a second gate cannot appear in a screen, an
    // engine or a repository. See docs/FOREGROUND_MULTITASKING.md §10.
    // Keyed by path, each with the reason it is not gating state.
    const exempt = <String, String>{
      // The seam itself: three pure functions and one value object.
      'lib/capability/': 'the capability seam — no counter, no purchase record',
      // These two only *name* it: an import and a type. Neither decides
      // anything; both defer to the seam above.
      'lib/features/settings_screen.dart': 'imports the developer control',
      'lib/main.dart': 'reads the persisted override at startup',
      'lib/features/developer_screen.dart':
          'hosts the internal-build-only control; compiled out of release',
    };
    const forbidden = <String>[
      'library_check_runs_used',
      'complimentary_checks_remaining',
      'is_pro',
      'ispro',
      'pro_required',
      'prorequired',
      'trial_expired',
      'trialexpired',
      'purchase_required',
      'entitlement',
      'upgrade_to_pro',
      'upgradetopro',
      'in_app_purchase',
      'storekit',
      'billingclient',
    ];
    final offenders = <String>[];
    for (final file in Directory('lib').listSync(recursive: true)) {
      if (file is! File || !file.path.endsWith('.dart')) continue;
      if (exempt.keys.any(file.path.contains)) continue;
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final lower = lines[i].toLowerCase();
        for (final word in forbidden) {
          if (lower.contains(word)) {
            offenders.add('${file.path}:${i + 1} $word');
          }
        }
      }
    }
    expect(
      offenders,
      isEmpty,
      reason:
          'checking is unrestricted; no gating, counter or purchase state may '
          'sit dormant in the app waiting to be switched on',
    );
  });
}
