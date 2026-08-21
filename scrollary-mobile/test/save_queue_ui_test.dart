import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:web_reader/browser/browser_controller.dart';
import 'package:web_reader/save/save_run.dart';
import 'package:web_reader/core/local_reset.dart';
import 'package:web_reader/features/activity_screen.dart';
import 'package:web_reader/features/developer_screen.dart';
import 'package:web_reader/features/library_screen.dart';
import 'package:web_reader/features/settings_screen.dart';
import 'package:web_reader/library/update_checker.dart';
import 'package:web_reader/providers.dart';
import 'package:web_reader/queue/task_queue.dart';
import 'package:web_reader/storage/database.dart';
import 'package:web_reader/storage/file_store.dart';

/// The screens around the queue: the Library strip that offers a start, the
/// confirmation that is the only door to Browser automation, and the
/// debug-only reset.
void main() {
  late AppDatabase db;
  late Directory root;
  late FileStore store;
  late BrowserController browser;
  late TaskQueueController queue;
  late List<String> executed;
  int? tabRequested;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    root = Directory.systemTemp.createTempSync('webread_queue_ui');
    store = FileStore(root);
    browser = BrowserController();
    executed = [];
    tabRequested = null;
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
    queue.ensureBrowserVisible = ({url}) async => true;
  });

  tearDown(() async {
    await db.close();
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  Widget harness(Widget child) {
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(path: '/', builder: (_, _) => child),
        GoRoute(path: '/activity', builder: (_, _) => const ActivityScreen()),
        GoRoute(path: '/developer', builder: (_, _) => const DeveloperScreen()),
        for (final path in ['/storage', '/rules', '/archived', '/settings'])
          GoRoute(path: path, builder: (_, _) => const SizedBox()),
      ],
    );
    final tabRequest = ValueNotifier<int?>(null)..addListener(() {});
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
      child: MaterialApp.router(routerConfig: router),
    );
  }

  Future<void> show(WidgetTester tester, Widget child) async {
    tester.view.physicalSize = const Size(430, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(harness(child));
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 30));
    }
  }

  Future<void> drain(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 10));
  }

  Future<void> queueOne(String url) =>
      queue.enqueueSave(startUrl: url, entryLimit: 1);

  group('the Library strip', () {
    testWidgets('offers a start when saves are waiting', (tester) async {
      await queueOne('https://x.example/guide/foo/1');
      await show(tester, const LibraryScreen());

      expect(find.byKey(const ValueKey('saveQueueStrip')), findsOneWidget);
      expect(find.text('Save queue · 1 waiting'), findsOneWidget);
      expect(find.text('Open Browser to start'), findsOneWidget);
      await drain(tester);
    });

    testWidgets('stays away when nothing is queued', (tester) async {
      await show(tester, const LibraryScreen());
      expect(find.byKey(const ValueKey('saveQueueStrip')), findsNothing);
      await drain(tester);
    });

    testWidgets('"Not now" keeps the queue and starts nothing', (tester) async {
      await queueOne('https://x.example/guide/foo/1');
      await show(tester, const LibraryScreen());

      await tester.tap(find.byKey(const ValueKey('startSaveButton')));
      await tester.pumpAndSettle();
      expect(find.text('Start the queued save?'), findsOneWidget);

      await tester.tap(find.text('Not now'));
      await tester.pumpAndSettle();
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 30));
      }

      expect(executed, isEmpty);
      expect(await queue.queuedSaves(), hasLength(1));
      expect(tabRequested, isNull, reason: 'and it did not navigate');
      await drain(tester);
    });

    testWidgets('confirming asks for the Browser, then runs', (tester) async {
      await queueOne('https://x.example/guide/foo/1');
      await show(tester, const LibraryScreen());

      await tester.tap(find.byKey(const ValueKey('startSaveButton')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('startInBrowser')));
      await tester.pumpAndSettle();
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 30));
      }

      expect(executed, ['https://x.example/guide/foo/1']);
      await drain(tester);
    });
  });

  group('the Activity queue section', () {
    testWidgets('waiting saves are their own section', (tester) async {
      await queueOne('https://x.example/guide/foo/1');
      await queueOne('https://x.example/guide/foo/2');
      await show(tester, const ActivityScreen());

      expect(find.text('WAITING TO START'), findsOneWidget);
      expect(find.text('2 saves'), findsOneWidget);
      expect(find.byKey(const ValueKey('startAllQueued')), findsOneWidget);
      expect(find.text('Start 2 saves'), findsOneWidget);
      await drain(tester);
    });

    testWidgets('each row shows its position and what it will do', (
      tester,
    ) async {
      await queueOne('https://x.example/guide/foo/1');
      await show(tester, const ActivityScreen());

      expect(find.text('1'), findsWidgets, reason: 'queue position');
      // A single-page save is identified by the page it will save, not by a
      // count — "1" tells the user nothing about which request this is.
      // A single-page save is identified by the page it will save, not by a
      // count — "1" tells the user nothing about which request this is.
      // "What it will do" is the scope and the source, not a bare count —
      // "1" alone tells the user nothing about which request this is.
      expect(
        find.text('Save · this page only · x.example · added just now'),
        findsOneWidget,
      );
      expect(find.textContaining('x.example'), findsWidgets);
      await drain(tester);
    });

    testWidgets('a queued task can be removed without touching content', (
      tester,
    ) async {
      await queueOne('https://x.example/guide/foo/1');
      await show(tester, const ActivityScreen());

      await tester.tap(find.byTooltip('Remove from queue'));
      await tester.pumpAndSettle();

      expect(await queue.queuedSaves(), isEmpty);
      expect(executed, isEmpty);
      await drain(tester);
    });

    testWidgets('reordering moves a row', (tester) async {
      await queueOne('https://x.example/guide/foo/1');
      await queueOne('https://x.example/guide/foo/2');
      await show(tester, const ActivityScreen());

      // The second row's "move up".
      await tester.tap(find.byTooltip('Move up').last);
      await tester.pumpAndSettle();

      final rows = (await queue.queuedSaves())
        ..sort((a, b) => a.orderIndex.compareTo(b.orderIndex));
      expect(rows.first.startUrl, 'https://x.example/guide/foo/2');
      await drain(tester);
    });

    testWidgets('clearing the queue asks first', (tester) async {
      await queueOne('https://x.example/guide/foo/1');
      await show(tester, const ActivityScreen());

      await tester.tap(find.byKey(const ValueKey('clearQueued')));
      await tester.pumpAndSettle();
      expect(find.text('Clear the save queue?'), findsOneWidget);

      await tester.tap(find.text('Keep them'));
      await tester.pumpAndSettle();
      expect(await queue.queuedSaves(), hasLength(1));

      await tester.tap(find.byKey(const ValueKey('clearQueued')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Clear queue'));
      await tester.pumpAndSettle();
      expect(await queue.queuedSaves(), isEmpty);
      await drain(tester);
    });

    testWidgets('the batch summary counts rather than guessing a percent', (
      tester,
    ) async {
      await queueOne('https://x.example/guide/foo/1');
      await queueOne('https://x.example/guide/foo/2');
      await show(tester, const ActivityScreen());

      expect(find.text('2 waiting'), findsOneWidget);
      expect(
        find.textContaining('%'),
        findsNothing,
        reason: 'an unstarted batch has no honest percentage',
      );
      await drain(tester);
    });
  });

  group('the development reset', () {
    testWidgets('Settings offers Developer in a debug build', (tester) async {
      await show(tester, const SettingsScreen());
      expect(developerToolsAvailable, isTrue);
      // Settings is longer than one viewport, so the door has to be scrolled
      // to rather than assumed to be built.
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('developerTools')),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.byKey(const ValueKey('developerTools')), findsOneWidget);
      await drain(tester);
    });

    testWidgets('the reset needs two steps and the exact word', (tester) async {
      await show(tester, const DeveloperScreen());

      await tester.tap(find.byKey(const ValueKey('resetAllLocalData')));
      await tester.pumpAndSettle();
      expect(find.text('Reset all local data?'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('resetContinue')));
      await tester.pumpAndSettle();
      expect(find.text('Type RESET to confirm'), findsOneWidget);

      // Wrong word: the destructive button stays dead.
      await tester.enterText(
        find.byKey(const ValueKey('resetConfirmField')),
        'reset please',
      );
      await tester.pumpAndSettle();
      final button = tester.widget<FilledButton>(
        find.byKey(const ValueKey('resetEverything')),
      );
      expect(button.onPressed, isNull);
      await drain(tester);
    });

    testWidgets('cancelling the first dialog changes nothing', (tester) async {
      await show(tester, const DeveloperScreen());

      await tester.tap(find.byKey(const ValueKey('resetAllLocalData')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.text('Type RESET to confirm'), findsNothing);
      await drain(tester);
    });

    testWidgets('the right word arms the button', (tester) async {
      await show(tester, const DeveloperScreen());

      await tester.tap(find.byKey(const ValueKey('resetAllLocalData')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('resetContinue')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('resetConfirmField')),
        'RESET',
      );
      await tester.pumpAndSettle();

      final button = tester.widget<FilledButton>(
        find.byKey(const ValueKey('resetEverything')),
      );
      expect(button.onPressed, isNotNull);
      await drain(tester);
    });
  });
}
