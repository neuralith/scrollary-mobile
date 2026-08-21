import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:web_reader/browser/browser_controller.dart';
import 'package:web_reader/features/activity_screen.dart';
import 'package:web_reader/features/library_screen.dart';
import 'package:web_reader/features/save_queue_ui.dart';
import 'package:web_reader/library/update_checker.dart';
import 'package:web_reader/providers.dart';
import 'package:web_reader/queue/task_queue.dart';
import 'package:web_reader/save/save_run.dart';
import 'package:web_reader/storage/database.dart';
import 'package:web_reader/storage/file_store.dart';
import 'package:web_reader/ui/theme.dart';

/// Starting the queue must put the user in front of the Browser.
///
/// The bug this file exists to prevent: the Browser is a *tab inside the
/// shell route*, and every start action only asked for the tab. Started from
/// Activity — a route pushed above the shell, and where the Start button
/// actually lives — the index moved underneath a screen the user was still
/// looking at, so the queue drove a Browser nobody could see. Nothing about
/// the app supports background saving, so a start that does not show the
/// Browser is a start that lies.
void main() {
  late AppDatabase db;
  late Directory root;
  late FileStore store;
  late BrowserController browser;
  late TaskQueueController queue;
  late ValueNotifier<int?> tabRequest;

  /// The start URLs the scheduler actually ran, in order.
  late List<String> executed;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    root = Directory.systemTemp.createTempSync('webread_queue_start_nav');
    store = FileStore(root);
    browser = BrowserController();
    executed = [];
    tabRequest = ValueNotifier<int?>(null);
    queue = TaskQueueController(
      db: db,
      browser: browser,
      saveRun: SaveRunController(browser: browser, db: db, fileStore: store),
      checker: UpdateChecker(browser: browser, db: db),
      saveRunner: (task) async {
        executed.add(task.startUrl ?? task.id);
        return const QueueOutcome.success('saved');
      },
    );
    // The shell's own hook is exercised by the integration suites, which have
    // a real WebView to attach. Here it stands in as "the Browser is ready",
    // so what is under test is the navigation the start action itself does.
    queue.ensureBrowserVisible = ({url}) async => true;
  });

  tearDown(() async {
    tabRequest.dispose();
    await db.close();
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  /// The shell, reduced to the one thing that matters here: the Browser is a
  /// tab it owns, not a route, so anything pushed on top hides it.
  Widget app() {
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(path: '/', builder: (_, _) => const _FakeShell()),
        GoRoute(path: '/activity', builder: (_, _) => const ActivityScreen()),
        // Stands in for Collection Detail: a route pushed above the shell,
        // with a start action of its own.
        GoRoute(
          path: '/collection',
          builder: (context, state) => Scaffold(
            appBar: AppBar(title: const Text('COLLECTION DETAIL')),
            body: Column(
              children: [
                TextButton(
                  onPressed: () => context.push('/activity'),
                  child: const Text('to activity'),
                ),
                Consumer(
                  builder: (context, ref, _) => TextButton(
                    key: const ValueKey('startFromCollection'),
                    onPressed: () => confirmAndStartSaves(context, ref),
                    child: const Text('start from here'),
                  ),
                ),
              ],
            ),
          ),
        ),
        for (final path in ['/storage', '/rules', '/archived', '/settings'])
          GoRoute(path: path, builder: (_, _) => const SizedBox()),
      ],
    );
    addTearDown(router.dispose);

    return ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        fileStoreProvider.overrideWithValue(store),
        browserProvider.overrideWithValue(browser),
        taskQueueProvider.overrideWithValue(queue),
        saveRunProvider.overrideWithValue(
          SaveRunController(browser: browser, db: db, fileStore: store),
        ),
        updateCheckerProvider.overrideWithValue(
          UpdateChecker(browser: browser, db: db),
        ),
        shellTabRequestProvider.overrideWithValue(tabRequest),
      ],
      child: MaterialApp.router(theme: appTheme(), routerConfig: router),
    );
  }

  /// The queue runs off the widget tree, so pumping frames is not enough on
  /// its own — the microtasks have to be given room too.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
  }

  Future<void> show(WidgetTester tester) async {
    tester.view.physicalSize = const Size(430, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app());
    await settle(tester);
  }

  Future<void> drain(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 10));
  }

  Future<void> queueOne(String url) =>
      queue.enqueueSave(startUrl: url, entryLimit: 1);

  Future<void> openActivity(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('toActivity')));
    await tester.pumpAndSettle();
    expect(find.text('Activity'), findsOneWidget);
  }

  Future<void> confirmStart(WidgetTester tester) async {
    await tester.pumpAndSettle();
    expect(find.textContaining('queued save'), findsWidgets);
    await tester.tap(find.byKey(const ValueKey('startInBrowser')));
    await tester.pumpAndSettle();
    await settle(tester);
  }

  /// What the user can see: the Browser, or something covering it.
  void expectsShowingBrowser(WidgetTester tester) {
    expect(find.text('BROWSER'), findsOneWidget);
    expect(find.text('Activity'), findsNothing);
    expect(find.text('COLLECTION DETAIL'), findsNothing);
  }

  group('starting the queue from Activity', () {
    testWidgets('leaves the queue screen and shows the Browser', (
      tester,
    ) async {
      await queueOne('https://x.example/guide/foo/1');
      await show(tester);
      await openActivity(tester);

      await tester.tap(find.byKey(const ValueKey('startAllQueued')));
      await confirmStart(tester);

      // The regression, stated directly: the user must not still be looking
      // at the queue while the save drives the Browser behind it.
      expectsShowingBrowser(tester);
      expect(tabRequest.value, isNull, reason: 'the shell consumed it');
      expect(executed, ['https://x.example/guide/foo/1']);
      await drain(tester);
    });

    testWidgets('opens the Browser for the entry at the front of the queue', (
      tester,
    ) async {
      await queueOne('https://x.example/guide/foo/1');
      await queueOne('https://x.example/guide/foo/2');
      await show(tester);
      await openActivity(tester);

      await tester.tap(find.byKey(const ValueKey('startAllQueued')));
      await confirmStart(tester);

      expectsShowingBrowser(tester);
      // Order is the queue's, unchanged by the navigation: the entry the
      // Browser is shown for is the one the queue actually claimed first.
      expect(executed, [
        'https://x.example/guide/foo/1',
        'https://x.example/guide/foo/2',
      ]);
      await drain(tester);
    });

    testWidgets('"Start this one" starts that row, and still navigates', (
      tester,
    ) async {
      await queueOne('https://x.example/guide/foo/1');
      await queueOne('https://x.example/guide/foo/2');
      await show(tester);
      await openActivity(tester);

      // The second row's play button — a queue-start path of its own.
      await tester.tap(find.byTooltip('Start this one').last);
      await confirmStart(tester);

      expectsShowingBrowser(tester);
      expect(
        executed.first,
        'https://x.example/guide/foo/2',
        reason: 'the row that was started ran first',
      );
      await drain(tester);
    });

    testWidgets('two routes deep still lands on the Browser', (tester) async {
      await queueOne('https://x.example/guide/foo/1');
      await show(tester);
      // Library → Collection Detail → Activity: one pop would not be enough.
      await tester.tap(find.byKey(const ValueKey('toCollection')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('to activity'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('startAllQueued')));
      await confirmStart(tester);

      expectsShowingBrowser(tester);
      expect(executed, ['https://x.example/guide/foo/1']);
      await drain(tester);
    });

    testWidgets('nothing is pushed — no duplicate Browser or shell', (
      tester,
    ) async {
      await queueOne('https://x.example/guide/foo/1');
      await show(tester);
      await openActivity(tester);
      final router = GoRouter.of(tester.element(find.text('Activity')));

      await tester.tap(find.byKey(const ValueKey('startAllQueued')));
      await confirmStart(tester);

      // Popped back to the shell that was always there, not forward onto a
      // second copy of it.
      expect(router.canPop(), isFalse);
      expect(find.byType(_FakeShell), findsOneWidget);
      expect(find.text('BROWSER'), findsOneWidget);
      await drain(tester);
    });
  });

  group('starting the queue from the Library', () {
    testWidgets('shows the Browser without pushing a route', (tester) async {
      await queueOne('https://x.example/guide/foo/1');
      await show(tester);
      expect(find.byKey(const ValueKey('saveQueueStrip')), findsOneWidget);
      final router = GoRouter.of(tester.element(find.byType(_FakeShell)));

      await tester.tap(find.byKey(const ValueKey('startSaveButton')));
      await confirmStart(tester);

      expectsShowingBrowser(tester);
      expect(router.canPop(), isFalse, reason: 'still the one shell route');
      expect(find.byType(_FakeShell), findsOneWidget);
      expect(executed, ['https://x.example/guide/foo/1']);
      await drain(tester);
    });
  });

  group('starting the queue from a collection route', () {
    testWidgets('leaves the collection and shows the Browser', (tester) async {
      await queueOne('https://x.example/guide/foo/1');
      await show(tester);
      await tester.tap(find.byKey(const ValueKey('toCollection')));
      await tester.pumpAndSettle();
      expect(find.text('COLLECTION DETAIL'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('startFromCollection')));
      await confirmStart(tester);

      expectsShowingBrowser(tester);
      expect(executed, ['https://x.example/guide/foo/1']);
      await drain(tester);
    });
  });

  group('the Browser is already in front', () {
    testWidgets('starting adds no second Browser and pops nothing extra', (
      tester,
    ) async {
      await queueOne('https://x.example/guide/foo/1');
      await show(tester);
      // Already on the Browser tab, then off to the queue screen and back
      // via Start — the path most likely to duplicate something.
      await tester.tap(find.byKey(const ValueKey('showBrowser')));
      await tester.pumpAndSettle();
      expect(find.text('BROWSER'), findsOneWidget);
      await openActivity(tester);

      await tester.tap(find.byKey(const ValueKey('startAllQueued')));
      await confirmStart(tester);

      final router = GoRouter.of(tester.element(find.byType(_FakeShell)));
      expect(find.text('BROWSER'), findsOneWidget);
      expect(find.byType(_FakeShell), findsOneWidget);
      expect(router.canPop(), isFalse);
      expect(executed, ['https://x.example/guide/foo/1']);
      await drain(tester);
    });
  });

  group('an empty queue', () {
    testWidgets('says so and goes nowhere', (tester) async {
      await show(tester);
      await tester.tap(find.byKey(const ValueKey('toCollection')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('startFromCollection')));
      await tester.pumpAndSettle();

      expect(
        find.text('Nothing is waiting in the save queue.'),
        findsOneWidget,
      );
      expect(find.text('Start queued saves?'), findsNothing);
      // Still exactly where they were: nothing started, so nothing opened.
      expect(find.text('COLLECTION DETAIL'), findsOneWidget);
      expect(find.text('BROWSER'), findsNothing);
      expect(tabRequest.value, isNull);
      expect(executed, isEmpty);
      await drain(tester);
    });

    testWidgets('declining the confirmation navigates nowhere', (tester) async {
      await queueOne('https://x.example/guide/foo/1');
      await show(tester);
      await openActivity(tester);

      await tester.tap(find.byKey(const ValueKey('startAllQueued')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Not now'));
      await settle(tester);

      expect(find.text('Activity'), findsOneWidget);
      expect(find.text('BROWSER'), findsNothing);
      expect(executed, isEmpty);
      expect(await queue.queuedSaves(), hasLength(1));
      await drain(tester);
    });
  });
}

/// The shell, as far as this file is concerned: a Library tab, a Browser tab,
/// and an index it owns. `IndexedStack` is deliberately not used — the point
/// of every assertion here is what the user can *see*.
class _FakeShell extends ConsumerStatefulWidget {
  const _FakeShell();

  @override
  ConsumerState<_FakeShell> createState() => _FakeShellState();
}

class _FakeShellState extends ConsumerState<_FakeShell> {
  int _index = 0;
  late final ValueNotifier<int?> _tabRequest;

  @override
  void initState() {
    super.initState();
    _tabRequest = ref.read(shellTabRequestProvider)..addListener(_onRequested);
  }

  @override
  void dispose() {
    _tabRequest.removeListener(_onRequested);
    super.dispose();
  }

  void _onRequested() {
    final requested = _tabRequest.value;
    if (requested == null) return;
    _tabRequest.value = null;
    if (requested != _index) setState(() => _index = requested);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: _index == 1
        ? const Center(child: Text('BROWSER'))
        : const LibraryScreen(),
    bottomNavigationBar: Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        TextButton(
          key: const ValueKey('toCollection'),
          onPressed: () => context.push('/collection'),
          child: const Text('collection'),
        ),
        TextButton(
          key: const ValueKey('toActivity'),
          onPressed: () => context.push('/activity'),
          child: const Text('activity'),
        ),
        TextButton(
          key: const ValueKey('showBrowser'),
          onPressed: () => setState(() => _index = 1),
          child: const Text('browser'),
        ),
      ],
    ),
  );
}
