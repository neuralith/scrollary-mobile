import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:web_reader/browser/browser_controller.dart';
import 'package:web_reader/capability/foreground_multitasking.dart';
import 'package:web_reader/features/activity_screen.dart';
import 'package:web_reader/features/operation_indicator.dart';
import 'package:web_reader/library/update_checker.dart';
import 'package:web_reader/providers.dart';
import 'package:web_reader/queue/task_queue.dart';
import 'package:web_reader/save/save_run.dart';
import 'package:web_reader/save/save_state.dart';
import 'package:web_reader/storage/database.dart';
import 'package:web_reader/storage/file_store.dart';
import 'package:web_reader/ui/status_style.dart';

/// The compact background-activity indicator.
///
/// One sentence under test: **it says that work is outstanding and how much,
/// and nothing else.** Everything in words — progress, logs, failures, stop,
/// retry, the way back to the Browser — is one tap away on Activity, which is
/// the surface that already owns those controls. A panel that follows the user
/// onto the page they are reading is a panel they learn to ignore, so this one
/// is a pill and it leaves with the Reader's bars.
void main() {
  late AppDatabase db;
  late Directory root;
  late FileStore store;
  late BrowserController browser;
  late SaveRunController run;
  late UpdateChecker checker;
  late TaskQueueController queue;
  late ValueNotifier<bool> browserOnScreen;
  late ReaderChromeVisibility readerChrome;
  late ForegroundMultitasking capability;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    root = Directory.systemTemp.createTempSync('webread_activity_pill');
    store = FileStore(root);
    browser = BrowserController();
    run = SaveRunController(browser: browser, db: db, fileStore: store);
    checker = UpdateChecker(browser: browser, db: db);
    browserOnScreen = ValueNotifier<bool>(false);
    readerChrome = ReaderChromeVisibility();
    capability = ForegroundMultitasking();
    queue = TaskQueueController(
      db: db,
      browser: browser,
      saveRun: run,
      checker: checker,
      saveRunner: (task) async => const QueueOutcome.success('saved'),
    );
    queue.ensureBrowserVisible = ({url}) async => true;
  });

  tearDown(() async {
    browserOnScreen.dispose();
    readerChrome.dispose();
    capability.dispose();
    await db.close();
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  // --- the widget ----------------------------------------------------------

  var opened = 0;
  var browserOpened = 0;
  double textScale = 1.0;

  Widget harness() {
    opened = 0;
    browserOpened = 0;
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) =>
              const Scaffold(body: Center(child: Text('some screen'))),
        ),
        GoRoute(path: '/activity', builder: (_, _) => const ActivityScreen()),
      ],
    );
    return ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        fileStoreProvider.overrideWithValue(store),
        browserProvider.overrideWithValue(browser),
        saveRunProvider.overrideWithValue(run),
        updateCheckerProvider.overrideWithValue(checker),
        taskQueueProvider.overrideWithValue(queue),
        browserOnScreenProvider.overrideWithValue(browserOnScreen),
        readerChromeVisibleProvider.overrideWithValue(readerChrome),
        foregroundMultitaskingProvider.overrideWithValue(capability),
      ],
      // The same placement the app uses: above the router, so the pill is
      // reachable from every screen the router pushes over the shell.
      child: MaterialApp.router(
        routerConfig: router,
        builder: (context, child) => MediaQuery(
          // Wrapped rather than set on the view, so a test can ask for a
          // reader's text size without the pill's own geometry being the only
          // thing that changes.
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: Stack(
            fit: StackFit.expand,
            children: [
              ?child,
              OperationIndicator(
                onOpenDetails: () {
                  opened++;
                  router.push('/activity');
                },
                onOpenBrowser: () => browserOpened++,
              ),
            ],
          ),
        ),
      ),
    );
  }

  final pill = find.byKey(const ValueKey('operationIndicator'));

  Future<void> show(
    WidgetTester tester, {
    Size size = const Size(430, 900),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(harness());
    await settle(tester);
  }

  /// Unmount inside the body, then let drift's stream teardown timers run —
  /// the fake clock only turns while the test body is still going.
  void indicatorTest(String name, Future<void> Function(WidgetTester) body) {
    testWidgets(name, (tester) async {
      await body(tester);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 10));
    });
  }

  Future<void> queueSave(String url) =>
      queue.enqueueSave(startUrl: url, entryLimit: 1);

  /// A queue row with its timestamps stated, which `enqueueSave` cannot give
  /// — it stamps `DateTime.now()`, and what the failure marker weighs is when
  /// one thing finished against when another was asked for.
  Future<void> putTask({
    required String id,
    required QueueTaskState state,
    required DateTime queuedAt,
    DateTime? finishedAt,
    int orderIndex = 0,
  }) => db.upsertQueueTask(
    QueueTask(
      id: id,
      taskType: QueueTaskType.entrySave.name,
      startUrl: 'https://x.example/guide/foo/$id',
      captureModeIsUserSet: false,
      state: state.name,
      origin: kQueueOriginQueue,
      orderIndex: orderIndex,
      queuedAt: queuedAt,
      finishedAt: finishedAt,
    ),
  );

  /// Read the count the pill is showing.
  String countOn(WidgetTester tester) => tester
      .widgetList<Text>(find.descendant(of: pill, matching: find.byType(Text)))
      .first
      .data!;

  bool spinning(WidgetTester tester) => find
      .descendant(of: pill, matching: find.byType(CircularProgressIndicator))
      .evaluate()
      .isNotEmpty;

  bool hasIcon(WidgetTester tester, IconData icon) =>
      find
          .descendant(of: pill, matching: find.byIcon(icon))
          .evaluate()
          .length ==
      1;

  group('when it is there at all', () {
    indicatorTest('nothing outstanding shows nothing', (tester) async {
      await show(tester);
      expect(pill, findsNothing);
    });

    indicatorTest('queued work brings it up with its count', (tester) async {
      await queueSave('https://x.example/guide/foo/1');
      await queueSave('https://x.example/guide/foo/2');
      await show(tester);

      expect(pill, findsOneWidget);
      expect(countOn(tester), '2');
    });

    indicatorTest('waiting work never claims to be moving', (tester) async {
      await queueSave('https://x.example/guide/foo/1');
      await show(tester);

      expect(
        spinning(tester),
        isFalse,
        reason: 'a save waiting for an explicit Start is not running',
      );
      expect(hasIcon(tester, Icons.schedule), isTrue);
    });

    indicatorTest('a running save spins and counts itself', (tester) async {
      run.debugSetRunning(true);
      run.debugSetProgress(const SaveProgress(state: SaveState.scrolling));
      await show(tester);

      expect(pill, findsOneWidget);
      expect(countOn(tester), '1');
      expect(spinning(tester), isTrue);
    });

    indicatorTest('a direct run and its queue row are one job, not two', (
      tester,
    ) async {
      await db.upsertQueueTask(
        QueueTask(
          id: 'running-1',
          taskType: QueueTaskType.entrySave.name,
          captureModeIsUserSet: false,
          state: QueueTaskState.running.name,
          origin: kQueueOriginQueue,
          orderIndex: 0,
          queuedAt: DateTime(2026, 8, 1),
        ),
      );
      run.debugSetRunning(true);
      run.debugSetProgress(const SaveProgress(state: SaveState.scrolling));
      await show(tester);

      expect(countOn(tester), '1');
    });

    indicatorTest('it stays out of the Browser, which says it all already', (
      tester,
    ) async {
      await queueSave('https://x.example/guide/foo/1');
      await show(tester);
      expect(pill, findsOneWidget);

      browserOnScreen.value = true;
      await settle(tester);
      expect(pill, findsNothing);
    });
  });

  group('as work moves', () {
    indicatorTest('the count falls as rows leave the queue', (tester) async {
      await queueSave('https://x.example/guide/foo/1');
      await queueSave('https://x.example/guide/foo/2');
      await queueSave('https://x.example/guide/foo/3');
      await show(tester);
      expect(countOn(tester), '3');

      final first = (await queue.queuedSaves()).first;
      await queue.cancelTask(first.id);
      await settle(tester);

      expect(countOn(tester), '2');
    });

    indicatorTest('it goes when the last of the work is cancelled', (
      tester,
    ) async {
      await queueSave('https://x.example/guide/foo/1');
      await show(tester);
      expect(pill, findsOneWidget);

      for (final task in await queue.queuedSaves()) {
        await queue.cancelTask(task.id);
      }
      await settle(tester);

      expect(
        pill,
        findsNothing,
        reason: 'a cancelled row is history, and history is not activity',
      );
    });

    indicatorTest('a finished run leaves nothing floating', (tester) async {
      run.debugSetRunning(true);
      run.debugSetProgress(const SaveProgress(state: SaveState.scrolling));
      await show(tester);
      expect(pill, findsOneWidget);

      run.debugSetRunning(false);
      run.debugSetProgress(const SaveProgress());
      await settle(tester);

      expect(pill, findsNothing);
    });
  });

  group('states that are not progress', () {
    indicatorTest('a paused run says paused rather than spinning', (
      tester,
    ) async {
      run.debugSetRunning(true);
      run.debugSetProgress(const SaveProgress(state: SaveState.paused));
      await show(tester);

      expect(pill, findsOneWidget);
      expect(spinning(tester), isFalse);
      expect(hasIcon(tester, Icons.pause_circle_outline), isTrue);
    });

    indicatorTest('a run holding for the user is marked, not spun', (
      tester,
    ) async {
      run.debugSetRunning(true);
      run.debugSetProgress(
        const SaveProgress(state: SaveState.waitingForBrowser),
      );
      await show(tester);

      expect(spinning(tester), isFalse);
      expect(hasIcon(tester, Icons.error_outline), isTrue);
    });

    indicatorTest('failed history on its own is not an activity indicator', (
      tester,
    ) async {
      await putTask(
        id: 'failed-1',
        state: QueueTaskState.failed,
        queuedAt: DateTime(2026, 8, 1),
        finishedAt: DateTime(2026, 8, 1, 0, 5),
      );
      await show(tester);

      expect(
        pill,
        findsNothing,
        reason: 'an indicator that never leaves is one nobody reads',
      );
    });
  });

  // --- which failures are this run's ---------------------------------------
  //
  // A `failed` row is terminal history and it is kept, for up to the whole
  // history limit. The question the marker has to answer is not "has anything
  // ever failed" — something always has — but "did the work I am watching lose
  // one".

  group('the failure marker', () {
    final wave = DateTime(2026, 8, 5, 12);

    indicatorTest('marks a casualty of the batch still running', (
      tester,
    ) async {
      // Three queued together; the second died thirty seconds in.
      await putTask(
        id: 'q-1',
        state: QueueTaskState.queued,
        queuedAt: wave,
        orderIndex: 1,
      );
      await putTask(
        id: 'q-2',
        state: QueueTaskState.queued,
        queuedAt: wave,
        orderIndex: 2,
      );
      await putTask(
        id: 'f-1',
        state: QueueTaskState.failed,
        queuedAt: wave,
        finishedAt: wave.add(const Duration(seconds: 30)),
        orderIndex: 3,
      );
      await show(tester);

      expect(countOn(tester), '2', reason: 'a failed row is not outstanding');
      expect(
        hasIcon(tester, Icons.error_outline),
        isTrue,
        reason: 'the batch being watched lost one, and that is worth saying',
      );
    });

    indicatorTest('leaves an unrelated older failure out of it', (
      tester,
    ) async {
      // Failed days ago and never cleared; Activity still lists it.
      await putTask(
        id: 'f-old',
        state: QueueTaskState.failed,
        queuedAt: wave.subtract(const Duration(days: 3)),
        finishedAt: wave.subtract(const Duration(days: 3, minutes: -2)),
        orderIndex: 1,
      );
      // …and a perfectly healthy save queued today.
      await putTask(
        id: 'q-new',
        state: QueueTaskState.queued,
        queuedAt: wave,
        orderIndex: 2,
      );
      await show(tester);

      expect(pill, findsOneWidget);
      expect(countOn(tester), '1');
      expect(
        hasIcon(tester, Icons.error_outline),
        isFalse,
        reason: 'last week is not this run, and a badge always lit is ignored',
      );
    });

    indicatorTest('a failure it cannot place in time is not claimed', (
      tester,
    ) async {
      await putTask(
        id: 'f-undated',
        state: QueueTaskState.failed,
        queuedAt: wave,
        orderIndex: 1,
      );
      await putTask(
        id: 'q-1',
        state: QueueTaskState.queued,
        queuedAt: wave,
        orderIndex: 2,
      );
      await show(tester);

      expect(pill, findsOneWidget);
      expect(
        hasIcon(tester, Icons.error_outline),
        isFalse,
        reason: 'silence is the safe answer for a marker meant to be believed',
      );
    });

    indicatorTest('every failure stays reachable on Activity regardless', (
      tester,
    ) async {
      await putTask(
        id: 'f-old',
        state: QueueTaskState.failed,
        queuedAt: wave.subtract(const Duration(days: 3)),
        finishedAt: wave.subtract(const Duration(days: 3)),
        orderIndex: 1,
      );
      await putTask(
        id: 'q-new',
        state: QueueTaskState.queued,
        queuedAt: wave,
        orderIndex: 2,
      );
      await show(tester);

      await tester.tap(pill);
      await settle(tester);

      expect(find.text('FAILED'), findsOneWidget);
      expect(
        find.text('1 needs you'),
        findsOneWidget,
        reason: 'scoping the marker must not hide the row it stopped marking',
      );
    });
  });

  group('the way to the detail', () {
    indicatorTest('tapping it opens Activity, with its controls intact', (
      tester,
    ) async {
      await queueSave('https://x.example/guide/foo/1');
      await show(tester);

      await tester.tap(pill);
      await settle(tester);

      expect(opened, 1);
      expect(find.byType(ActivityScreen), findsOneWidget);
      expect(find.text('WAITING TO START'), findsOneWidget);
      expect(find.byKey(const ValueKey('startAllQueued')), findsOneWidget);
      expect(find.byTooltip('Remove from queue'), findsOneWidget);
    });

    indicatorTest('a direct run is stoppable from where the pill sends you', (
      tester,
    ) async {
      run.debugSetRunning(true);
      run.debugSetProgress(const SaveProgress(state: SaveState.scrolling));
      await show(tester);

      await tester.tap(pill);
      await settle(tester);

      // The run holds no queue row while it runs (D58) — Activity presents it
      // from the controller, and the stop is still one tap from the pill.
      expect(find.byKey(const ValueKey('directSaveRow')), findsOneWidget);
      expect(find.byKey(const ValueKey('directSaveStop')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('directSaveOpenBrowser')),
        findsOneWidget,
      );
    });
  });

  // --- where a "Needs you" goes --------------------------------------------
  //
  // "Needs you" is one action, and it is the same one every time: the sign-in,
  // the CAPTCHA, the consent dialog and the ambiguous next-Entry control are
  // all answered on the Browser, because the selection overlay is drawn on
  // that screen and nowhere else (docs/FOREGROUND_MULTITASKING.md §9).

  group('a held operation', () {
    indicatorTest('sends the user to the Browser, not to a list', (
      tester,
    ) async {
      run.debugSetRunning(true);
      run.debugSetProgress(
        const SaveProgress(state: SaveState.waitingForBrowser),
      );
      await show(tester);

      await tester.tap(pill);
      await settle(tester);

      expect(browserOpened, 1);
      expect(
        opened,
        0,
        reason:
            'a list whose only live control opens the Browser is a '
            'tap spent on nothing',
      );
      expect(find.byType(ActivityScreen), findsNothing);
    });

    indicatorTest('a run holding on a hidden Browser goes there too', (
      tester,
    ) async {
      run.debugSetRunning(true);
      run.debugSetProgress(const SaveProgress(state: SaveState.scrolling));
      run.pauseForBrowserHidden();
      await show(tester);

      expect(hasIcon(tester, Icons.error_outline), isTrue);
      await tester.tap(pill);
      await settle(tester);

      expect(browserOpened, 1);
      expect(opened, 0);
    });

    indicatorTest('a page selection is answered where it is drawn', (
      tester,
    ) async {
      run.debugSetRunning(true);
      run.debugSetProgress(
        const SaveProgress(state: SaveState.awaitingSelection),
      );
      await show(tester);

      await tester.tap(pill);
      await settle(tester);
      expect(browserOpened, 1);
    });

    indicatorTest('everything else still goes to Activity', (tester) async {
      await queueSave('https://x.example/guide/foo/1');
      await show(tester);

      await tester.tap(pill);
      await settle(tester);

      expect(opened, 1);
      expect(browserOpened, 0);
    });

    indicatorTest('and the button says which, out loud', (tester) async {
      final semantics = tester.ensureSemantics();
      run.debugSetRunning(true);
      run.debugSetProgress(
        const SaveProgress(state: SaveState.waitingForBrowser),
      );
      await show(tester);

      expect(
        find.bySemanticsLabel(RegExp('Opens the Browser')),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel(RegExp('needs you')), findsOneWidget);
      semantics.dispose();
    });
  });

  group('reader chrome', () {
    indicatorTest('hiding the reader bars hides it too', (tester) async {
      await queueSave('https://x.example/guide/foo/1');
      await show(tester);
      expect(pill, findsOneWidget);

      readerChrome.publish(false);
      await settle(tester);
      expect(pill, findsNothing);
    });

    indicatorTest('bringing the bars back brings it back', (tester) async {
      await queueSave('https://x.example/guide/foo/1');
      await show(tester);
      readerChrome.publish(false);
      await settle(tester);

      readerChrome.publish(true);
      await settle(tester);
      expect(pill, findsOneWidget);
    });

    indicatorTest('and it does not come back if the work finished meanwhile', (
      tester,
    ) async {
      await queueSave('https://x.example/guide/foo/1');
      await show(tester);
      readerChrome.publish(false);
      await settle(tester);

      for (final task in await queue.queuedSaves()) {
        await queue.cancelTask(task.id);
      }
      readerChrome.publish(true);
      await settle(tester);

      expect(pill, findsNothing);
    });
  });

  group('accessibility and entitlement', () {
    indicatorTest('it is one button, described in words', (tester) async {
      final semantics = tester.ensureSemantics();
      await queueSave('https://x.example/guide/foo/1');
      await queueSave('https://x.example/guide/foo/2');
      await show(tester);

      expect(
        find.bySemanticsLabel(RegExp('2 waiting')),
        findsOneWidget,
        reason: 'a bare "2" tells a screen reader nothing',
      );
      expect(find.bySemanticsLabel(RegExp('Opens Activity')), findsOneWidget);
      semantics.dispose();
    });

    indicatorTest('a large count cannot overflow the pill', (tester) async {
      for (var i = 0; i < 120; i++) {
        await db.upsertQueueTask(
          QueueTask(
            id: 'q$i',
            taskType: QueueTaskType.entrySave.name,
            captureModeIsUserSet: false,
            state: QueueTaskState.queued.name,
            origin: kQueueOriginQueue,
            orderIndex: i,
            queuedAt: DateTime(2026, 8, 1),
          ),
        );
      }
      await show(tester);

      expect(countOn(tester), '99+');
      expect(tester.takeException(), isNull);
    });

    indicatorTest('the touch target holds at the app-wide size', (
      tester,
    ) async {
      await queueSave('https://x.example/guide/foo/1');
      await show(tester);

      final box = tester.getRect(pill);
      expect(box.height, greaterThanOrEqualTo(kHeaderActionSize));
      expect(box.width, greaterThanOrEqualTo(kHeaderActionSize));
    });

    indicatorTest('it grows for a reader at 200%, rather than overflowing', (
      tester,
    ) async {
      textScale = 2.0;
      addTearDown(() => textScale = 1.0);
      await queueSave('https://x.example/guide/foo/1');
      await queueSave('https://x.example/guide/foo/2');
      await show(tester, size: const Size(320, 640));

      expect(tester.takeException(), isNull, reason: 'nothing overflowed');
      final box = tester.getRect(pill);
      expect(box.height, greaterThanOrEqualTo(kHeaderActionSize));
      expect(
        box.left,
        greaterThan(0),
        reason: 'it still fits across the narrowest screen the app supports',
      );
    });

    indicatorTest('it clears the status bar and anything in the bar below it', (
      tester,
    ) async {
      // A notch-sized inset, the case the constant exists for.
      tester.view.padding = const FakeViewPadding(top: 59 * 3);
      addTearDown(tester.view.reset);
      await queueSave('https://x.example/guide/foo/1');
      await show(tester);

      final box = tester.getRect(pill);
      expect(
        box.top,
        greaterThanOrEqualTo(59 + kToolbarHeight),
        reason: 'below the safe area AND below where app-bar actions sit',
      );
      expect(box.right, lessThanOrEqualTo(430));
    });

    indicatorTest('knowing what the device is doing is never gated', (
      tester,
    ) async {
      expect(
        capability.enabled,
        isFalse,
        reason: 'setup: the paid capability is off',
      );
      await queueSave('https://x.example/guide/foo/1');
      await show(tester);

      expect(
        pill,
        findsOneWidget,
        reason:
            'status and cancellation are free (FOREGROUND_MULTITASKING '
            'docs, §10.1)',
      );
    });

    indicatorTest('a Free user watching a held save still sees it', (
      tester,
    ) async {
      // The state a Free user genuinely reaches: a Browser-dependent phase was
      // running, they chose to leave, the run held. Nothing about the pill is
      // entitlement-aware — it reports the state the leave gate produced.
      expect(capability.proAvailable, isFalse, reason: 'setup: no Pro');
      run.debugSetRunning(true);
      run.debugSetProgress(const SaveProgress(state: SaveState.scrolling));
      run.pauseForBrowserHidden();
      await show(tester);

      expect(pill, findsOneWidget);
      expect(hasIcon(tester, Icons.error_outline), isTrue);
      await tester.tap(pill);
      await settle(tester);
      expect(
        browserOpened,
        1,
        reason: 'and the way back to the Browser is free, as it always was',
      );
    });
  });

  // --- the counting itself -------------------------------------------------

  group('BackgroundActivity', () {
    QueueTask row(
      QueueTaskState state, {
      QueueTaskType? type,
      DateTime? queuedAt,
      DateTime? finishedAt,
      String? id,
    }) => QueueTask(
      id: id ?? '${state.name}-${type?.name}',
      taskType: (type ?? QueueTaskType.entrySave).name,
      captureModeIsUserSet: false,
      state: state.name,
      origin: kQueueOriginQueue,
      orderIndex: 0,
      queuedAt: queuedAt ?? DateTime(2026, 8, 1),
      finishedAt: finishedAt,
    );

    BackgroundActivity resolve(
      List<QueueTask> tasks, {
      bool runningWithoutTask = false,
      bool needsUser = false,
      bool paused = false,
    }) => BackgroundActivity.resolve(
      tasks: tasks,
      runningWithoutTask: runningWithoutTask,
      needsUser: needsUser,
      paused: paused,
    );

    test('an empty queue is nothing to report', () {
      final activity = resolve(const []);
      expect(activity.remaining, 0);
      expect(activity.isPresent, isFalse);
    });

    group('scoping failures to the wave', () {
      final wave = DateTime(2026, 8, 5, 12);

      test('a failure that happened alongside the outstanding work counts', () {
        expect(
          resolve([
            row(QueueTaskState.queued, queuedAt: wave, id: 'a'),
            row(
              QueueTaskState.failed,
              queuedAt: wave,
              finishedAt: wave.add(const Duration(seconds: 30)),
              id: 'b',
            ),
          ]).failed,
          1,
        );
      });

      test('one from before the outstanding work was asked for does not', () {
        expect(
          resolve([
            row(QueueTaskState.queued, queuedAt: wave, id: 'a'),
            row(
              QueueTaskState.failed,
              queuedAt: wave.subtract(const Duration(days: 3)),
              finishedAt: wave.subtract(const Duration(days: 3)),
              id: 'b',
            ),
          ]).failed,
          0,
        );
      });

      test('the oldest outstanding row is what the wave is measured from', () {
        // Queued at 12:00, another at 12:10, a failure at 12:05: still this
        // wave, because the wave began with the first of them.
        expect(
          resolve([
            row(QueueTaskState.queued, queuedAt: wave, id: 'a'),
            row(
              QueueTaskState.running,
              queuedAt: wave.add(const Duration(minutes: 10)),
              id: 'b',
            ),
            row(
              QueueTaskState.failed,
              queuedAt: wave,
              finishedAt: wave.add(const Duration(minutes: 5)),
              id: 'c',
            ),
          ]).failed,
          1,
        );
      });

      test('a failure with no finish time is never claimed', () {
        expect(
          resolve([
            row(QueueTaskState.queued, queuedAt: wave, id: 'a'),
            row(QueueTaskState.failed, queuedAt: wave, id: 'b'),
          ]).failed,
          0,
        );
      });

      test('with nothing outstanding there is no wave to belong to', () {
        expect(
          resolve([
            row(
              QueueTaskState.failed,
              queuedAt: wave,
              finishedAt: wave.add(const Duration(minutes: 1)),
              id: 'b',
            ),
          ]).failed,
          0,
        );
      });

      test('completed and cancelled rows are not failures', () {
        expect(
          resolve([
            row(QueueTaskState.queued, queuedAt: wave, id: 'a'),
            row(
              QueueTaskState.completed,
              queuedAt: wave,
              finishedAt: wave.add(const Duration(minutes: 1)),
              id: 'b',
            ),
            row(
              QueueTaskState.cancelled,
              queuedAt: wave,
              finishedAt: wave.add(const Duration(minutes: 2)),
              id: 'c',
            ),
          ]).failed,
          0,
        );
      });
    });

    test('queued and running are both outstanding', () {
      final activity = resolve([
        row(QueueTaskState.queued),
        row(QueueTaskState.queued, type: QueueTaskType.collectionCheck),
        row(QueueTaskState.running),
      ]);
      expect(activity.active, 1);
      expect(activity.waiting, 2);
      expect(activity.remaining, 3);
      expect(activity.inMotion, isTrue);
    });

    test('a run without a row still counts as one job', () {
      final activity = resolve(const [], runningWithoutTask: true);
      expect(activity.active, 1);
      expect(activity.isPresent, isTrue);
    });

    test('a run WITH a row is not counted twice', () {
      final activity = resolve([
        row(QueueTaskState.running),
      ], runningWithoutTask: true);
      expect(activity.active, 1);
    });

    test('finished work is history, not activity', () {
      final activity = resolve([
        row(QueueTaskState.completed),
        row(QueueTaskState.cancelled, type: QueueTaskType.collectionCheck),
        row(QueueTaskState.failed, type: QueueTaskType.checkAllCollections),
      ]);
      expect(activity.remaining, 0);
      expect(
        activity.failed,
        0,
        reason: 'with nothing in flight there is no run for it to be about',
      );
      expect(
        activity.isPresent,
        isFalse,
        reason: 'a failed row belongs to Activity, not to a permanent badge',
      );
    });

    test('nothing that is holding is allowed to look like motion', () {
      expect(
        resolve(const [], runningWithoutTask: true, needsUser: true).inMotion,
        isFalse,
      );
      expect(
        resolve(const [], runningWithoutTask: true, paused: true).inMotion,
        isFalse,
      );
    });

    test('a hold is worth showing even with an empty queue', () {
      expect(resolve(const [], paused: true).isPresent, isTrue);
      expect(resolve(const [], needsUser: true).isPresent, isTrue);
    });

    test('the description says what the counts are', () {
      final activity = resolve([
        row(QueueTaskState.queued),
        row(QueueTaskState.running),
        row(
          QueueTaskState.failed,
          type: QueueTaskType.collectionCheck,
          finishedAt: DateTime(2026, 8, 1, 0, 1),
        ),
      ]);
      expect(activity.description, contains('1 running'));
      expect(activity.description, contains('1 waiting'));
      expect(activity.description, contains('1 failed'));
      expect(activity.description, contains('Opens Activity'));
    });

    test('a held operation says where it will take you instead', () {
      expect(
        resolve(
          const [],
          runningWithoutTask: true,
          needsUser: true,
        ).description,
        contains('Opens the Browser'),
      );
    });
  });
}

/// Let the drift stream deliver and the widgets rebuild, on the fake clock.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}
