import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:web_reader/browser/browser_presentation.dart';
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

/// **Finishing** a library-wide check, not performing one.
///
/// The check happens in the Browser because the checker needs a rendered
/// WebView, which means starting one from the Library moves the user. The bug
/// this file exists to prevent is the other half of that move never happening:
/// the last collection finishes, the Browser sits there on somebody's entry
/// list, and the user is left to work out on their own that it is over and to
/// go and find the summary.
///
/// So the properties here are all about *ownership*: what the run took over,
/// that it hands exactly that back, that it does so once, and that a run which
/// never claimed the foreground — the seam a future concurrent mode would use
/// — moves nobody.
void main() {
  late AppDatabase db;
  late Directory root;
  late FakeBrowser browser;
  late List<String> executed;
  late Map<String, Completer<QueueOutcome>> gates;
  late Map<String, QueueOutcome> outcomes;

  const host = 'https://x.example';

  late LibraryCheckFlow flow;
  late BrowserPresentation presentation;
  late ValueNotifier<int?> tabRequest;
  late ValueNotifier<int> tab;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    root = Directory.systemTemp.createTempSync('webread_library_flow');
    browser = FakeBrowser();
    executed = [];
    gates = {};
    outcomes = {};
    // Built here rather than in the harness so a test can arrange the state
    // the run will take over — which Browser surface was showing, which tab
    // the user was on — before anything is pumped.
    flow = LibraryCheckFlow();
    presentation = BrowserPresentation();
    tabRequest = ValueNotifier<int?>(null);
    tab = ValueNotifier<int>(0);
  });

  tearDown(() async {
    flow.dispose();
    presentation.dispose();
    tabRequest.dispose();
    tab.dispose();
    await db.close();
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  Future<void> seed(String id, {String lifecycle = 'active'}) async {
    await db.upsertCollection(
      Collection(
        contentKind: 'unknownWebContent',
        sequenceKind: 'none',
        orderingBasis: 'discoveryOrder',
        shapeConfidence: 'low',
        lifecycle: lifecycle,
        id: id,
        title: 'Collection $id',
        sourceUrl: '$host/guide/$id',
        host: 'x.example',
        collectionKey: '/guide/$id',
        collectionIndexUrl: '$host/guide/$id',
        createdAt: DateTime(2026, 7, 1),
      ),
    );
    await db.upsertEntry(
      Entry(
        host: 'x.example',
        contentKind: 'unknownWebContent',
        contentKindConfidence: 'low',
        contentKindIsUserSet: false,
        id: '$id-c1',
        collectionId: id,
        title: 'Entry 1',
        sourceUrl: '$host/guide/$id/1',
        urlKey: '$host/guide/$id/1',
        artifactFormat: 'imageSequence',
        saveStatus: 'complete',
        contentPath: 'library/$id/entries/$id-c1',
        savedAt: DateTime(2026, 7, 10),
        detectedAssetCount: 1,
        storedAssetCount: 1,
        entryOrder: 1,
        byteSize: 16,
        entryNumber: 1,
        sourceMarker: 'Entry 1',
        readStatus: 'unread',
        progressFraction: 0,
        progressPageIndex: 0,
        progressOffsetInPage: 0,
      ),
    );
  }

  /// Stamp a collection the way a finished check would, so the report reads
  /// the same rows it reads in production.
  Future<void> stampChecked(String id, {String result = 'upToDate'}) =>
      db.writeCollectionCheck(
        id,
        CollectionsCompanion(
          lastCheckAt: Value(DateTime.now()),
          lastCheckSuccessAt: result == 'failed'
              ? const Value.absent()
              : Value(DateTime.now()),
          lastCheckError: result == 'failed'
              ? const Value('source unreachable')
              : const Value(null),
          lastCheckResult: Value(result),
        ),
      );

  late TaskQueueController queue;

  /// Which pages `ensureBrowserVisible` was asked to show. Standing in for
  /// the shell's own hook, which needs a real WebView.
  late List<String?> shown;

  Widget app({bool wireBrowserHook = true}) {
    queue = TaskQueueController(
      db: db,
      browser: browser,
      saveRun: SaveRunController(
        browser: browser,
        db: db,
        fileStore: FileStore(root),
      ),
      checker: UpdateChecker(browser: browser, db: db),
      checkRunner: (task) async {
        executed.add(task.collectionId ?? task.id);
        final gate = gates[task.collectionId];
        if (gate != null) return gate.future;
        return outcomes[task.collectionId] ??
            const QueueOutcome.success('up to date');
      },
    );
    shown = [];
    if (wireBrowserHook) {
      // What the real shell does: bring the Browser forward before the work
      // starts (D47). The tab request is what the fake shell reacts to.
      queue.ensureBrowserVisible = ({url}) async {
        shown.add(url);
        tabRequest.value = 1;
        return true;
      };
    }
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(path: '/', builder: (_, _) => const _FakeShell()),
        GoRoute(
          path: '/reader',
          builder: (context, _) => Scaffold(
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('READER'),
                  TextButton(
                    key: const ValueKey('leaveReader'),
                    onPressed: () => context.pop(),
                    child: const Text('back'),
                  ),
                ],
              ),
            ),
          ),
        ),
        GoRoute(
          path: '/collection/:id',
          builder: (_, state) => Scaffold(
            body: Center(
              child: Text('COLLECTION ${state.pathParameters['id']}'),
            ),
          ),
        ),
        for (final path in ['/storage', '/archived', '/settings', '/activity'])
          GoRoute(path: path, builder: (_, _) => const SizedBox()),
      ],
    );
    addTearDown(router.dispose);

    return ProviderScope(
      overrides: [
        appServicesProvider.overrideWithValue(
          AppServices(
            db: db,
            fileStore: FileStore(root),
            browser: browser,
            saveRun: SaveRunController(
              browser: browser,
              db: db,
              fileStore: FileStore(root),
            ),
            taskQueue: queue,
          ),
        ),
        libraryCheckFlowProvider.overrideWithValue(flow),
        browserPresentationProvider.overrideWithValue(presentation),
        shellTabRequestProvider.overrideWithValue(tabRequest),
        shellTabProvider.overrideWithValue(tab),
      ],
      child: MaterialApp.router(theme: appTheme(), routerConfig: router),
    );
  }

  Future<void> pump(WidgetTester tester, [int frames = 25]) async {
    for (var i = 0; i < frames; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
  }

  Future<void> show(WidgetTester tester, {bool wireBrowserHook = true}) async {
    tester.view.physicalSize = const Size(900, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app(wireBrowserHook: wireBrowserHook));
    await pump(tester);
  }

  Future<void> drain(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 10));
  }

  /// Start a run the way the user does: the card, then the pre-run sheet.
  Future<void> startCheck(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('libraryCheckAllButton')));
    await pump(tester, 12);
    await tester.tap(find.byKey(const ValueKey('confirmLibraryCheck')));
    await pump(tester);
  }

  bool sheetIsUp() => find
      .byKey(const ValueKey('libraryCheckResultSheet'))
      .evaluate()
      .isNotEmpty;

  /// Text inside the completion sheet, told apart from the same words on the
  /// card behind it — both say it, and that is the point.
  Finder inSheet(String text) => find.descendant(
    of: find.byKey(const ValueKey('libraryCheckResultSheet')),
    matching: find.text(text),
  );

  // --- 1. the run takes the Browser, and gives it back ----------------------

  group('the foreground run hands the Browser back', () {
    testWidgets('starting one enters the Browser and records what it took', (
      tester,
    ) async {
      await seed('a');
      await seed('b');
      // The user was on Browser Home before the run; that is what the run
      // covers when it reveals a page to work on.
      presentation.openHome();
      gates['a'] = Completer<QueueOutcome>();

      await show(tester);
      await startCheck(tester);

      expect(tab.value, 1, reason: 'the run is watched in the Browser');
      expect(shown, isNotEmpty, reason: 'the Browser was asked for a page');
      expect(flow.presentation, LibraryCheckPresentation.libraryForeground);
      expect(flow.ownsForeground, isTrue);
      expect(flow.returnTab, 0, reason: 'it started from the Library');
      expect(flow.broughtBrowserForward, isTrue);
      expect(flow.surfaceBefore, BrowserSurface.home);

      gates['a']!.complete(const QueueOutcome.success('up to date'));
      await pump(tester);
      await drain(tester);
    });

    testWidgets('completion returns to the Library and opens the result', (
      tester,
    ) async {
      await seed('a');
      await seed('b');
      await show(tester);
      await startCheck(tester);
      await stampChecked('a');
      await stampChecked('b');
      await pump(tester);

      expect(executed, ['a', 'b'], reason: 'both ran, one at a time');
      expect(tab.value, 0, reason: 'the user is put back where they started');
      expect(sheetIsUp(), isTrue);
      expect(inSheet('Library check complete'), findsOneWidget);
      expect(inSheet('2 collections checked'), findsOneWidget);
      expect(inSheet('Everything is up to date'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('libraryCheckResultSheet')),
          matching: find.textContaining('Nothing was downloaded'),
        ),
        findsOneWidget,
      );
      await drain(tester);
    });

    testWidgets('the local surface the run covered is put back', (
      tester,
    ) async {
      await seed('a');
      presentation.openHome();
      gates['a'] = Completer<QueueOutcome>();

      await show(tester);
      await startCheck(tester);
      // Working on a page reveals the website surface over Home — which is
      // what the Browser does for a check, and what has to be put back.
      presentation.showWebsite();
      gates['a']!.complete(const QueueOutcome.success('up to date'));
      await stampChecked('a');
      await pump(tester);

      expect(
        presentation.surface,
        BrowserSurface.home,
        reason: 'the run revealed the page over Home; it puts Home back',
      );
      await drain(tester);
    });

    testWidgets('a surface the run did not cover is left alone', (
      tester,
    ) async {
      await seed('a');
      // The user was looking at a page before the run, not at Home.
      presentation.showWebsite();

      await show(tester);
      await startCheck(tester);
      await stampChecked('a');
      await pump(tester);

      expect(
        presentation.surface,
        BrowserSurface.website,
        reason: 'nothing was covered, so nothing is restored',
      );
      // And nothing else about the Browser was touched: no page was loaded to
      // undo the run's navigation, and the WebView was not reset.
      expect(browser.navigations, isEmpty);
      await drain(tester);
    });
  });

  // --- 2. once, and only once -----------------------------------------------

  group('the result is presented exactly once', () {
    testWidgets('rebuilds do not open a second sheet', (tester) async {
      await seed('a');
      await show(tester);
      await startCheck(tester);
      await stampChecked('a');
      await pump(tester);
      expect(sheetIsUp(), isTrue);

      // Every rebuild trigger there is: the queue notifies, the streams tick,
      // and the widget tree is pumped for a good while longer.
      await db.upsertCollection((await db.allCollections()).first);
      await pump(tester, 40);

      expect(
        find.byKey(const ValueKey('libraryCheckResultSheet')),
        findsOneWidget,
      );
      expect(flow.completionClaimed, isTrue);
      await drain(tester);
    });

    testWidgets('coming back to the Library does not re-present it', (
      tester,
    ) async {
      await seed('a');
      await show(tester);
      await startCheck(tester);
      await stampChecked('a');
      await pump(tester);

      await tester.tap(find.byKey(const ValueKey('libraryCheckResultDone')));
      await pump(tester);
      expect(sheetIsUp(), isFalse);

      // Leave and come back — the shell keeps the Library alive, so this is
      // the rebuild path a returning user actually takes.
      tabRequest.value = 1;
      await pump(tester);
      tabRequest.value = 0;
      await pump(tester, 40);

      expect(sheetIsUp(), isFalse, reason: 'an answered result is answered');
      await drain(tester);
    });

    testWidgets('dismissing the sheet leaves the report on the card', (
      tester,
    ) async {
      await seed('a');
      await show(tester);
      await startCheck(tester);
      await stampChecked('a');
      await pump(tester);

      await tester.tap(find.byKey(const ValueKey('libraryCheckResultDone')));
      await pump(tester);

      expect(sheetIsUp(), isFalse);
      expect(flow.plan, isNotNull, reason: 'the run is still the card’s');
      expect(
        find.text('Library check complete'),
        findsOneWidget,
        reason: 'dismissing the sheet is not dismissing the result',
      );
      expect(
        find.byKey(const ValueKey('dismissLibraryCheckButton')),
        findsOneWidget,
      );
      await drain(tester);
    });
  });

  // --- 3. every terminal state, and one that is not -------------------------

  group('each ending says what happened', () {
    testWidgets('partial completion returns and reports the failure', (
      tester,
    ) async {
      await seed('a');
      await seed('b');
      outcomes['b'] = const QueueOutcome.failure('source unreachable');

      await show(tester);
      await startCheck(tester);
      await stampChecked('a');
      await pump(tester);

      expect(tab.value, 0);
      expect(inSheet('Library check partly finished'), findsOneWidget);
      expect(
        inSheet('2 collections checked'),
        findsOneWidget,
        reason: 'a collection that failed was still asked',
      );
      expect(inSheet('1 collection needs attention'), findsOneWidget);
      await drain(tester);
    });

    testWidgets('cancelling returns and keeps what was checked', (
      tester,
    ) async {
      await seed('a');
      await seed('b');
      await seed('c');
      gates['a'] = Completer<QueueOutcome>();

      await show(tester);
      await startCheck(tester);
      expect(executed, ['a'], reason: 'one at a time');

      // Stopping is on the card, so the user comes back to the Library for
      // it. (A hidden tab's widgets are built but offstage, and offstage is
      // not tappable — which is also true of the real shell.)
      tabRequest.value = 0;
      await pump(tester);
      await tester.tap(find.byKey(const ValueKey('stopLibraryCheckButton')));
      await pump(tester);
      gates['a']!.complete(const QueueOutcome.success('up to date'));
      await stampChecked('a');
      await pump(tester);

      expect(tab.value, 0);
      expect(inSheet('Library check stopped'), findsOneWidget);
      expect(inSheet('1 collection checked'), findsOneWidget);
      expect(inSheet('2 not checked'), findsOneWidget);
      expect(executed, ['a'], reason: 'the rest were never opened');
      // Cancelling is not deletion, and not a failure label.
      expect(await db.allCollections(), hasLength(3));
      await drain(tester);
    });

    testWidgets('a run that scheduled nothing reports that honestly', (
      tester,
    ) async {
      // Nothing eligible, but the library is not empty — so the card is on
      // screen and the run can be started and immediately have nothing to do.
      await seed('sleeping', lifecycle: 'archived');
      await seed('a');
      // Take the only eligible collection away between the preview and the
      // enqueue: the run is started, and schedules nothing.
      await show(tester);
      await tester.tap(find.byKey(const ValueKey('libraryCheckAllButton')));
      await pump(tester, 12);
      await db.setCollectionLifecycle('a', 'archived');
      await tester.tap(find.byKey(const ValueKey('confirmLibraryCheck')));
      await pump(tester);

      expect(inSheet('No collection was checked'), findsOneWidget);
      expect(sheetIsUp(), isTrue);
      expect(tab.value, 0, reason: 'it never left the Library');
      await drain(tester);
    });

    testWidgets('work still waiting does not end anything', (tester) async {
      await seed('a');
      await seed('b');
      gates['a'] = Completer<QueueOutcome>();

      await show(tester);
      await startCheck(tester);
      await pump(tester, 30);

      expect(sheetIsUp(), isFalse, reason: 'the run has not finished');
      expect(tab.value, 1, reason: 'and the user is still watching it');
      expect(flow.completionClaimed, isFalse);

      gates['a']!.complete(const QueueOutcome.success('up to date'));
      await pump(tester);
      await drain(tester);
    });
  });

  // --- 4. who owns the screen ----------------------------------------------

  group('ownership', () {
    testWidgets('a run the user has left is not yanked back', (tester) async {
      await seed('a');
      gates['a'] = Completer<QueueOutcome>();

      await show(tester);
      await startCheck(tester);
      expect(tab.value, 1);

      // The user goes off to read. That is their surface now, not the run's.
      await tester.tap(find.byKey(const ValueKey('toReader')));
      await pump(tester);
      expect(find.text('READER'), findsOneWidget);

      gates['a']!.complete(const QueueOutcome.success('up to date'));
      await stampChecked('a');
      await pump(tester, 40);

      expect(sheetIsUp(), isFalse, reason: 'nothing interrupts the reader');
      expect(find.text('READER'), findsOneWidget);
      expect(flow.released, isTrue);
      expect(flow.plan, isNotNull, reason: 'the result is not thrown away');
      await drain(tester);
    });

    testWidgets('the report is still waiting on the card afterwards', (
      tester,
    ) async {
      await seed('a');
      gates['a'] = Completer<QueueOutcome>();

      await show(tester);
      await startCheck(tester);
      await tester.tap(find.byKey(const ValueKey('toReader')));
      await pump(tester);
      gates['a']!.complete(const QueueOutcome.success('up to date'));
      await stampChecked('a');
      await pump(tester, 30);

      // Back to the Library of their own accord.
      await tester.tap(find.byKey(const ValueKey('leaveReader')));
      await pump(tester);
      tabRequest.value = 0;
      await pump(tester, 30);
      // Coming back to a screen whose providers were paused while a database
      // write landed trips a debug assertion inside Riverpod's own ticker-mode
      // resume (`_updateTickerMode` → subscription flush → `setState` during
      // build). It predates this flow — a save finishing while the user reads
      // produces the same thing — so it is consumed here rather than allowed
      // to stand in for the behaviour under test.
      tester.takeException();

      expect(find.text('Library check complete'), findsOneWidget);
      expect(sheetIsUp(), isFalse, reason: 'released is released');
      await drain(tester);
    });

    testWidgets('a run that claims nothing on screen moves nobody', (
      tester,
    ) async {
      await seed('a');
      await show(tester, wireBrowserHook: false);

      // The seam a future concurrent mode would use: same checking, same
      // report, no claim on the foreground.
      final startedAt = DateTime.now();
      final scheduled = await queue.enqueueLibraryCheck();
      flow.beginUnattached(
        LibraryCheckPlan(
          startedAt: startedAt,
          collectionIds: [for (final s in scheduled) s.collectionId],
          taskIds: [for (final s in scheduled) s.taskId],
        ),
      );
      await stampChecked('a');
      await pump(tester, 40);

      expect(executed, ['a'], reason: 'the same check ran');
      expect(sheetIsUp(), isFalse, reason: 'no sheet was forced on anyone');
      expect(tab.value, 0, reason: 'and nothing navigated');
      expect(flow.ownsForeground, isFalse);
      // The result is there for whatever wants to present it.
      expect(find.text('Library check complete'), findsOneWidget);
      await drain(tester);
    });
  });

  // --- 5. the engine stays out of the UI ------------------------------------

  test('stopping a library run leaves other queued checks alone', () async {
    await seed('a');
    await seed('b');
    await seed('solo');
    final queue = TaskQueueController(
      db: db,
      browser: browser,
      saveRun: SaveRunController(
        browser: browser,
        db: db,
        fileStore: FileStore(root),
      ),
      checker: UpdateChecker(browser: browser, db: db),
      checkRunner: (task) async => const QueueOutcome.success('up to date'),
    );
    // Nothing drains while the browser is held, so every row stays queued.
    browser.automationOwner = 'hold';
    final soloId = (await queue.enqueueCollectionCheck('solo'))!;
    final scheduled = await queue.enqueueLibraryCheck();
    final runIds = [
      for (final s in scheduled)
        if (s.collectionId != 'solo') s.taskId,
    ];

    final cancelled = await queue.cancelQueuedChecks(onlyTaskIds: runIds);

    expect(cancelled, runIds.length);
    final rows = await db.watchQueueTasks().first;
    expect(
      rows.firstWhere((t) => t.id == soloId).state,
      QueueTaskState.queued.name,
      reason: 'a check queued from a collection screen is not part of the run',
    );
  });

  test('the checker and the report know nothing about navigation', () {
    // The whole point of the split, stated as a file-level fact rather than a
    // convention: if the engine ever imports a route, a tab or a widget, a
    // future non-foreground mode inherits this flow's navigation with it.
    for (final path in const [
      'lib/library/library_check.dart',
      'lib/library/update_checker.dart',
    ]) {
      final source = File(path).readAsStringSync();
      for (final forbidden in const [
        "package:flutter/material.dart",
        "package:go_router",
        'BuildContext',
        'showModalBottomSheet',
        'Navigator',
        'shellTab',
      ]) {
        expect(
          source.contains(forbidden),
          isFalse,
          reason: '$path must not reach $forbidden',
        );
      }
    }
  });
}

/// The shell, reduced to what this flow depends on: two tabs in an
/// `IndexedStack` — so the Library keeps living while the Browser is on screen,
/// which is what lets a run that ends over there be noticed at all — plus the
/// request/report pair of notifiers the real shell owns.
class _FakeShell extends ConsumerStatefulWidget {
  const _FakeShell();

  @override
  ConsumerState<_FakeShell> createState() => _FakeShellState();
}

class _FakeShellState extends ConsumerState<_FakeShell> {
  int _index = 0;
  late final ValueNotifier<int?> _request;
  late final ValueNotifier<int> _tab;

  @override
  void initState() {
    super.initState();
    _request = ref.read(shellTabRequestProvider)..addListener(_onRequested);
    _tab = ref.read(shellTabProvider);
    _tab.value = _index;
  }

  @override
  void dispose() {
    _request.removeListener(_onRequested);
    super.dispose();
  }

  void _onRequested() {
    final requested = _request.value;
    if (requested == null) return;
    _request.value = null;
    if (requested == _index) return;
    setState(() => _index = requested);
    _tab.value = _index;
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: IndexedStack(
      index: _index,
      children: const [
        LibraryScreen(),
        Center(child: Text('BROWSER')),
      ],
    ),
    // The one thing the real shell also offers from either tab: a way onto a
    // route pushed *above* it, which is what "the user took the screen for
    // something else" means here.
    bottomNavigationBar: TextButton(
      key: const ValueKey('toReader'),
      onPressed: () => context.push('/reader'),
      child: const Text('read something'),
    ),
  );
}
