import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_reader/save/capture_mode.dart';
import 'package:web_reader/save/save_run.dart';
import 'package:web_reader/save/save_preflight.dart';
import 'package:web_reader/save/save_state.dart';
import 'package:web_reader/core/config.dart';
import 'package:web_reader/features/save_preflight_sheet.dart';
import 'package:web_reader/features/save_scope_sheet.dart';
import 'package:web_reader/library/update_checker.dart';
import 'package:web_reader/queue/task_queue.dart';
import 'package:web_reader/storage/database.dart';
import 'package:web_reader/storage/file_store.dart';

import 'helpers/fake_browser.dart';

/// Start Save runs *this* request, now, and leaves the queue alone (D58).
///
/// The rule under test in one sentence: a direct save creates no pending
/// queue task, releases none, reorders none, and finishing it authorises
/// nothing — the pending batch is still waiting for its own Start.
void main() {
  late AppDatabase db;
  late Directory root;
  late FakeBrowser browser;
  late _ScriptedRun run;
  late _FakeChecker checker;
  late List<String> executed;
  late List<String> browserAsks;
  late bool browserAvailable;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    root = Directory.systemTemp.createTempSync('webread_direct_save');
    browser = FakeBrowser();
    run = _ScriptedRun(browser: browser, db: db, fileStore: FileStore(root));
    checker = _FakeChecker(browser: browser, db: db);
    executed = [];
    browserAsks = [];
    browserAvailable = true;
  });

  tearDown(() async {
    await db.close();
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  TaskQueueController makeQueue() {
    final queue = TaskQueueController(
      db: db,
      browser: browser,
      saveRun: run,
      checker: checker,
      saveRunner: (task) async {
        executed.add(task.startUrl ?? task.id);
        return const QueueOutcome.success('saved');
      },
      checkRunner: (task) async {
        executed.add('check:${task.collectionId}');
        return const QueueOutcome.success('checked');
      },
    );
    queue.ensureBrowserVisible = ({url}) async {
      browserAsks.add('asked');
      return browserAvailable;
    };
    return queue;
  }

  Future<void> settle() =>
      Future<void>.delayed(const Duration(milliseconds: 120));

  String url(int n) => 'https://x.example/guide/foo/$n';

  Future<void> queueThree(TaskQueueController queue) async {
    for (final n in [200, 201, 202]) {
      await queue.enqueueSave(startUrl: url(n), entryLimit: 1);
    }
  }

  group('starting directly', () {
    test('runs the request and creates no pending queue task', () async {
      final queue = makeQueue();

      final result = await queue.startDirectSave(
        captureModeIsUserSet: false,
        startUrl: url(350),
        entryLimit: 1,
        range: SaveScope.currentPageOnly,
      );
      expect(result, DirectStartResult.started);
      expect(browserAsks, ['asked'], reason: 'rendered-Browser check first');
      await settle();

      expect(run.started, [url(350)]);
      expect(run.origin, SaveOrigin.direct);
      expect(
        await queue.queuedSaves(),
        isEmpty,
        reason: 'a direct save is not a queue entry',
      );
    });

    test('the run only begins after the Browser is confirmed', () async {
      browserAvailable = false;
      final queue = makeQueue();

      final result = await queue.startDirectSave(
        captureModeIsUserSet: false,
        startUrl: url(350),
        entryLimit: 1,
      );
      await settle();

      expect(result, DirectStartResult.browserUnavailable);
      expect(run.started, isEmpty, reason: 'nothing scrolled');
      expect(await db.pendingQueueTasks(), isEmpty, reason: 'and nothing sat');
    });

    test('an empty page is refused before anything is created', () async {
      final queue = makeQueue();
      expect(
        await queue.startDirectSave(startUrl: '   ', entryLimit: 1),
        DirectStartResult.noPage,
      );
      expect(browserAsks, isEmpty);
      expect(await db.pendingQueueTasks(), isEmpty);
    });

    test('the outcome lands in Activity history as a direct run', () async {
      final queue = makeQueue();
      await queue.startDirectSave(startUrl: url(350), entryLimit: 1);
      await run.finish(stored: 1);
      await settle();

      final rows = await db.watchQueueTasks().first;
      expect(rows, hasLength(1));
      final row = rows.single;
      expect(row.origin, kQueueOriginDirect);
      expect(isDirectOriginTask(row), isTrue);
      expect(row.state, QueueTaskState.completed.name);
      expect(row.outcome, contains('1 saved'));
      expect(
        row.startedAt,
        isNotNull,
        reason: 'it ran; it never merely waited',
      );
      // History, never a plan: nothing here can be released by the pump.
      expect(await queue.queuedSaves(), isEmpty);
    });

    test('a failed direct run is reported as failed, with its error', () async {
      final queue = makeQueue();
      await queue.startDirectSave(startUrl: url(350), entryLimit: 1);
      await run.finish(
        stored: 0,
        state: SaveState.failed,
        error: 'insufficientStorage',
      );
      await settle();

      final row = (await db.watchQueueTasks().first).single;
      expect(row.state, QueueTaskState.failed.name);
      expect(row.lastError, 'insufficientStorage');
    });
  });

  group('the pending queue is left alone', () {
    test('queued entries stay queued, in order, while one runs now', () async {
      final queue = makeQueue();
      await queueThree(queue);
      await settle();
      expect(executed, isEmpty, reason: 'queued work waits for Start (D46)');

      await queue.startDirectSave(startUrl: url(350), entryLimit: 1);
      await settle();

      final waiting = await queue.queuedSaves()
        ..sort((a, b) => a.orderIndex.compareTo(b.orderIndex));
      expect(waiting.map((t) => t.startUrl), [url(200), url(201), url(202)]);
      expect(run.started, [url(350)]);
      expect(executed, isEmpty);
    });

    test('finishing a direct save does not release the queue', () async {
      final queue = makeQueue();
      await queueThree(queue);
      await queue.startDirectSave(startUrl: url(350), entryLimit: 1);
      await run.finish(stored: 1);
      await settle();
      await settle();

      expect(
        executed,
        isEmpty,
        reason: 'the batch still waits for its own Start',
      );
      expect(queue.saveStartAuthorised, isFalse);
      expect(await queue.queuedSaves(), hasLength(3));
    });

    test('an explicitly started batch survives a direct save', () async {
      final queue = makeQueue();
      await queueThree(queue);
      await queue.startQueuedSaves();
      await settle();

      // The batch ran because the user started it — that is the one thing a
      // direct save must not undo.
      expect(executed, [url(200), url(201), url(202)]);

      await queue.startDirectSave(startUrl: url(350), entryLimit: 1);
      await run.finish(stored: 1);
      await settle();
      expect(run.started, [url(350)]);
    });

    test(
      'the queue pump cannot slip in while a direct start is claimed',
      () async {
        final queue = makeQueue();
        // A check drains on its own (D46) — but not into a Browser that a
        // direct save has already claimed.
        await db.upsertCollection(
          Collection(
            contentKind: 'unknownWebContent',
            sequenceKind: 'none',
            orderingBasis: 'discoveryOrder',
            shapeConfidence: 'low',
            lifecycle: 'active',
            id: 'collection-1',
            title: 'Foo',
            sourceUrl: 'https://x.example/guide/foo',
            host: 'x.example',
            collectionKey: '/guide/foo',
            createdAt: DateTime(2026, 7, 1),
          ),
        );
        await queue.startDirectSave(startUrl: url(350), entryLimit: 1);
        await queue.enqueueCollectionCheck('collection-1');
        await settle();

        expect(executed, isEmpty, reason: 'the check waits its turn');
        expect(queue.directSaveRunning, isTrue);

        await run.finish(stored: 1);
        await settle();
        expect(executed, ['check:collection-1'], reason: 'and then it runs');
      },
    );
  });

  group('Browser ownership', () {
    test('a second direct start is refused while one is running', () async {
      final queue = makeQueue();
      await queue.startDirectSave(startUrl: url(350), entryLimit: 1);
      await settle();

      final second = await queue.startDirectSave(
        captureModeIsUserSet: false,
        startUrl: url(351),
        entryLimit: 1,
      );
      expect(second, DirectStartResult.browserBusy);
      expect(run.started, [url(350)], reason: 'the first one is untouched');
      expect(await db.pendingQueueTasks(), isEmpty, reason: 'and none queued');
    });

    test('an update check blocks a direct start and is named', () async {
      final queue = makeQueue();
      browser.automationOwner = 'an update check';
      checker.running = true;

      expect(queue.browserOwner?.label, contains('update check'));
      expect(
        await queue.startDirectSave(startUrl: url(350), entryLimit: 1),
        DirectStartResult.browserBusy,
      );

      checker.running = false;
      browser.automationOwner = null;
      expect(queue.browserOwner, isNull);
    });

    test(
      'a download-only phase is named as such, not as "using the Browser"',
      () async {
        final queue = makeQueue();
        run.debugSetRunning(true);
        run.debugSetProgress(
          const SaveProgress(
            state: SaveState.fetchingAssets,
            currentUrl: 'https://x.example/guide/foo/350',
          ),
        );

        final owner = queue.browserOwner!;
        expect(
          owner.needsBrowser,
          isFalse,
          reason: 'downloads need no surface',
        );
        expect(owner.label, contains('downloads'));
        // Queueing is unaffected: it starts nothing, so it cannot conflict.
        final queued = await queue.enqueueSave(
          captureModeIsUserSet: false,
          startUrl: url(400),
          entryLimit: 1,
        );
        expect(queued.alreadyQueued, isFalse);
        expect(await queue.queuedSaves(), hasLength(1));
        run.debugSetRunning(false);
      },
    );
  });

  group('the launch survives the duplicate preflight', () {
    SaveLaunchPlan? plan(
      SaveSheetAction action,
      PreflightChoice choice, {
      DuplicatePolicy? policy,
      int limit = 5,
      SaveScope range = SaveScope.fixedCount,
    }) => planAfterPreflight(
      action: action,
      choice: choice,
      requestedLimit: limit,
      requestedRange: range,
      policy: policy,
    );

    test('a direct re-download stays direct, and is one entry', () {
      final result = plan(
        SaveSheetAction.startNow,
        PreflightChoice.redownload,
        policy: DuplicatePolicy.replaceAll,
      );
      expect(result!.action, SaveSheetAction.startNow);
      expect(result.entryLimit, 1);
      expect(result.range, SaveScope.currentPageOnly);
      expect(result.policy, DuplicatePolicy.replaceAll);
    });

    test('a queued re-download stays queued', () {
      final result = plan(
        SaveSheetAction.addToQueue,
        PreflightChoice.redownload,
        policy: DuplicatePolicy.replaceAll,
      );
      expect(result!.action, SaveSheetAction.addToQueue);
      expect(result.entryLimit, 1);
    });

    test('every repair-shaped answer is a single entry', () {
      for (final choice in const [
        PreflightChoice.redownload,
        PreflightChoice.retryMissing,
        PreflightChoice.restartSave,
        PreflightChoice.repair,
      ]) {
        final result = plan(SaveSheetAction.startNow, choice)!;
        expect(result.entryLimit, 1, reason: choice.name);
        expect(result.range, SaveScope.currentPageOnly);
        expect(result.action, SaveSheetAction.startNow);
      }
    });

    test('saving what follows keeps the requested range and launch', () {
      for (final action in SaveSheetAction.values) {
        final result = plan(
          action,
          PreflightChoice.saveFollowing,
          limit: 7,
          range: SaveScope.fixedCount,
        )!;
        expect(result.action, action);
        expect(result.entryLimit, 7);
        expect(result.range, SaveScope.fixedCount);
      }
    });

    test('a restart after discarding keeps the launch too', () {
      final result = plan(
        SaveSheetAction.startNow,
        PreflightChoice.discardRunAndRestart,
        limit: 3,
      );
      expect(result!.action, SaveSheetAction.startNow);
      expect(result.entryLimit, 3);
    });

    test('answers that are not saves launch nothing', () {
      for (final choice in const [
        PreflightChoice.openExisting,
        PreflightChoice.removeRecord,
        PreflightChoice.resumeRun,
        PreflightChoice.cancel,
      ]) {
        expect(
          plan(SaveSheetAction.startNow, choice),
          isNull,
          reason: choice.name,
        );
      }
    });
  });

  group('recovery', () {
    test('an interrupted direct save is recorded as direct', () async {
      final queue = makeQueue();
      await queue.startDirectSave(
        captureModeIsUserSet: false,
        startUrl: url(350),
        entryLimit: 3,
        range: SaveScope.fixedCount,
      );
      await settle();
      await run.persistInterrupted(url(351));

      final row = await db.findResumableRun();
      expect(row, isNotNull);
      expect(row!.origin, SaveOrigin.direct.name);
      expect(saveOriginFromName(row.origin), SaveOrigin.direct);
    });

    test('resuming stays direct and never enters the pending queue', () async {
      final queue = makeQueue();
      await queueThree(queue);
      await db.upsertRun(
        SaveRun(
          visitedCanonicals: '',
          id: 'run-1',
          captureModeIsUserSet: false,
          startUrl: url(350),
          currentUrl: url(351),
          requestedEntries: 3,
          completedEntries: 1,
          state: SaveState.scrolling.name,
          visitedUrls: url(350),
          scope: SaveScope.fixedCount.name,
          origin: SaveOrigin.direct.name,
          createdAt: DateTime(2026, 7, 28),
          updatedAt: DateTime(2026, 7, 28),
        ),
      );
      final resumable = (await db.findResumableRun())!;

      final result = await queue.resumeInterruptedSave(resumable);
      await settle();

      expect(result, DirectStartResult.started);
      expect(run.resumed, ['run-1']);
      expect(run.origin, SaveOrigin.direct);
      expect(
        (await queue.queuedSaves()).map((t) => t.startUrl),
        [url(200), url(201), url(202)],
        reason: 'the pending queue is untouched by a recovery',
      );
      expect(executed, isEmpty);
    });

    test('a legacy run with no origin reads as queue work', () {
      expect(saveOriginFromName(null), SaveOrigin.queue);
    });
  });

  group('preflight sees an active direct run', () {
    test('a running direct save owns its entry', () async {
      final queue = makeQueue();
      await queue.startDirectSave(startUrl: url(350), entryLimit: 1);
      await settle();
      await run.persistInterrupted(url(350));

      final preflight = SavePreflight(db: db, fileStore: FileStore(root));
      final result = await preflight.inspect(url(350));
      expect(result.state, EntryLocalState.inActiveRun);
      expect(result.blockingRun?.origin, SaveOrigin.direct.name);
    });
  });
}

/// An update checker whose "is it running" answer the test owns.
class _FakeChecker extends UpdateChecker {
  _FakeChecker({required super.browser, required super.db});

  bool running = false;

  @override
  bool get isRunning => running;
}

/// A save run that can be started and finished on command.
///
/// The real loop needs fixture pages and a WebView; what these tests are about
/// is the *launch*: who started it, what it did to the queue, and what it left
/// behind. Everything below the launch is exercised by the save suites.
class _ScriptedRun extends SaveRunController {
  _ScriptedRun({
    required super.browser,
    required super.db,
    required super.fileStore,
  }) : super(config: const SaveConfig());

  final List<String> started = [];
  final List<String> resumed = [];
  Completer<void>? _gate;
  String? _runRowId;

  @override
  @override
  Future<void> start({
    required int entryLimit,
    int? maxBytes,
    CaptureMode? captureMode,
    bool captureModeIsUserSet = false,
    bool rememberForCollection = false,
    String? startUrl,
    DuplicatePolicy policy = DuplicatePolicy.skipComplete,
    SessionDuplicateDecision sessionDuplicate = SessionDuplicateDecision.ask,
    SessionPartialDecision sessionPartial = SessionPartialDecision.ask,
    SaveScope range = SaveScope.fixedCount,
    SaveOrigin origin = SaveOrigin.direct,
  }) async {
    started.add(startUrl ?? browser.currentUrl);
    this.origin = origin;
    scope = range;
    duplicatePolicy = policy;
    debugSetRunning(true);
    debugSetProgress(
      SaveProgress(
        state: SaveState.inspecting,
        currentUrl: startUrl ?? '',
        requestedEntries: entryLimit,
        entryIndex: 1,
      ),
    );
    browser.automationOwner = 'a save run';
    _gate = Completer<void>();
    await _gate!.future;
    browser.automationOwner = null;
    debugSetRunning(false);
    notifyListeners();
  }

  @override
  Future<void> resumeRun(SaveRun run) async {
    resumed.add(run.id);
    await start(
      entryLimit: run.requestedEntries - run.completedEntries,
      startUrl: run.currentUrl ?? run.startUrl,
      range: saveScopeFromName(run.scope),
      origin: saveOriginFromName(run.origin),
    );
  }

  /// Persist the row an interrupted run would leave behind.
  Future<void> persistInterrupted(String currentUrl) async {
    debugSetProgress(
      progress.copyWith(state: SaveState.scrolling, currentUrl: currentUrl),
    );
    await debugPersist();
    _runRowId = runId;
  }

  Future<void> finish({
    required int stored,
    SaveState state = SaveState.complete,
    String? error,
  }) async {
    debugSetProgress(
      progress.copyWith(
        state: state,
        storedEntries: stored,
        lastError: error,
        message: '$stored saved',
      ),
    );
    if (_runRowId != null) await db.deleteRun(_runRowId!);
    _gate?.complete();
    _gate = null;
    await Future<void>.delayed(Duration.zero);
  }
}
