import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:web_reader/features/browser_save_state.dart';
import 'package:web_reader/library/update_checker.dart';
import 'package:web_reader/queue/task_queue.dart';
import 'package:web_reader/save/capture_policy.dart';
import 'package:web_reader/save/save_preflight.dart';
import 'package:web_reader/save/save_run.dart';
import 'package:web_reader/save/save_state.dart';
import 'package:web_reader/save/stop_conditions.dart';
import 'package:web_reader/core/config.dart';
import 'package:web_reader/storage/database.dart';
import 'package:web_reader/storage/file_store.dart';

import 'helpers/fake_browser.dart';
import '../tool/fixture/fixture_site.dart';

/// The restricted-site capture policy at every boundary that can begin or
/// continue a capture.
///
/// The rule under test, in one sentence: **a hidden button is not
/// enforcement.** Each boundary here is exercised directly, with the UI out of
/// the picture, because each of them is reachable without the UI — by a stale
/// queue row, a resume, a retry, a redirect, or an update check.
///
/// This file names commercial content services in order to prove they are
/// refused. Nothing here contacts one: every restricted address is a literal
/// string that no code path is allowed to reach the network with, and the one
/// end-to-end run serves its images from a local socket.
void main() {
  late AppDatabase db;
  late Directory root;
  late FileStore store;
  late FakeBrowser browser;

  // Two restricted addresses of the two different rule kinds, plus a permitted
  // one, used throughout.
  const restrictedDomainUrl = 'https://www.netflix.com/title/80100172';
  const restrictedHostUrl = 'https://tv.apple.com/show/example';
  const allowedUrl = 'https://x.example/guide/foo/1';

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    root = Directory.systemTemp.createTempSync('webread_restriction');
    store = FileStore(root);
    Directory(
      p.join(root.path, FileStore.libraryFolderName),
    ).createSync(recursive: true);
    Directory(
      p.join(root.path, FileStore.tmpFolderName),
    ).createSync(recursive: true);
    browser = FakeBrowser();
  });

  tearDown(() async {
    await db.close();
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  SaveRunController makeRun({SaveConfig config = const SaveConfig()}) =>
      SaveRunController(
        browser: browser,
        db: db,
        fileStore: store,
        config: config,
      );

  /// A queue whose real work is replaced by a recorder, so "did anything start"
  /// is answerable without standing up a WebView.
  ({TaskQueueController queue, List<String> executed}) makeQueue({
    SaveRunController? run,
    UpdateChecker? checker,
  }) {
    final executed = <String>[];
    final queue = TaskQueueController(
      db: db,
      browser: browser,
      saveRun: run ?? makeRun(),
      checker: checker ?? UpdateChecker(browser: browser, db: db),
      saveRunner: (task) async {
        executed.add(task.startUrl ?? task.id);
        return const QueueOutcome.success('saved');
      },
      checkRunner: (task) async {
        executed.add(task.collectionId ?? task.id);
        return const QueueOutcome.success('checked');
      },
    );
    return (queue: queue, executed: executed);
  }

  Future<void> settle() =>
      Future<void>.delayed(const Duration(milliseconds: 120));

  Future<void> seedCollection(String id, String host, String sourceUrl) =>
      db.upsertCollection(
        Collection(
          contentKind: 'unknownWebContent',
          sequenceKind: 'none',
          orderingBasis: 'discoveryOrder',
          shapeConfidence: 'low',
          lifecycle: 'active',
          id: id,
          title: 'Collection $id',
          sourceUrl: sourceUrl,
          host: host,
          collectionKey: '/title',
          collectionIndexUrl: sourceUrl,
          createdAt: DateTime(2026, 7, 1),
        ),
      );

  /// An entry that is already saved, already read halfway, and has real bytes
  /// on disk. Nothing this policy does may touch any of that.
  Future<Entry> seedSavedEntry({
    required String id,
    required String url,
    String? collectionId,
  }) async {
    final dir = Directory(p.join(root.path, 'library', 'seeded', id))
      ..createSync(recursive: true);
    File(p.join(dir.path, 'manifest.json')).writeAsStringSync('{}');
    final entry = Entry(
      id: id,
      collectionId: collectionId,
      title: 'Already saved',
      sourceUrl: url,
      urlKey: url,
      host: Uri.parse(url).host,
      contentKind: 'unknownWebContent',
      contentKindConfidence: 'low',
      contentKindIsUserSet: false,
      artifactFormat: 'imageSequence',
      saveStatus: 'complete',
      contentPath: 'library/seeded/$id',
      savedAt: DateTime(2026, 7, 2),
      detectedAssetCount: 3,
      storedAssetCount: 3,
      entryOrder: 1,
      byteSize: 4242,
      readStatus: 'reading',
      progressFraction: 0.5,
      progressPageIndex: 2,
      progressOffsetInPage: 0.25,
    );
    await db.upsertEntry(entry);
    return entry;
  }

  /// Nothing was staged, and nothing was left behind.
  void expectNoStagingLeft() {
    final tmp = Directory(p.join(root.path, FileStore.tmpFolderName));
    final leftovers = tmp.existsSync()
        ? tmp.listSync().map((e) => p.basename(e.path)).toList()
        : <String>[];
    expect(
      leftovers,
      isEmpty,
      reason: 'a refusal must leave no temporary staging behind',
    );
  }

  // --- 1. the Browser action ------------------------------------------------

  group('the Browser save action', () {
    BrowserSaveState resolve({
      required String url,
      bool hasActiveRun = false,
      String activePageKey = '',
      SaveRunRecord? lastRun,
      EntryLocalState? pageEntryState,
      bool pageIsQueued = false,
      bool checkerRunning = false,
    }) => resolveBrowserSaveState(
      pageKey: url,
      pageSession: 7,
      hasActiveRun: hasActiveRun,
      activePageKey: activePageKey,
      activeState: SaveState.idle,
      needsRenderedBrowser: false,
      awaitingUser: false,
      pausedForBrowser: false,
      checkerRunning: checkerRunning,
      lastRun: lastRun,
      pageEntryState: pageEntryState,
      pageIsQueued: pageIsQueued,
      // Exactly what the Browser computes from the address on screen.
      captureRestricted: isCaptureRestricted(url),
    );

    test('no capture action on a restricted domain', () {
      final ui = resolve(url: restrictedDomainUrl);
      expect(ui.status, BrowserSaveStatus.restricted);
      expect(ui.offersCapture, isFalse, reason: 'nothing is rendered at all');
      expect(ui.canStartDirect, isFalse);
      expect(ui.canQueue, isFalse);
      expect(ui.opensSaveSheet, isFalse);
      expect(ui.showsRunPanel, isFalse);
      expect(
        ui.detail,
        isNull,
        reason: 'browsing a restricted site earns no warning',
      );
      expect(ui.busyLabel, isNull);
    });

    test('no capture action on a restricted exact host', () {
      expect(resolve(url: restrictedHostUrl).offersCapture, isFalse);
    });

    test('the parent of a restricted exact host keeps its capture action', () {
      final ui = resolve(url: 'https://developer.apple.com/documentation');
      expect(ui.status, BrowserSaveStatus.save);
      expect(ui.offersCapture, isTrue);
      expect(ui.canStartDirect, isTrue);
    });

    test('capture comes back on a permitted page', () {
      final ui = resolve(url: allowedUrl);
      expect(ui.status, BrowserSaveStatus.save);
      expect(ui.offersCapture, isTrue);
      expect(ui.canQueue, isTrue);
    });

    test('a stale successful result cannot bring the action back', () {
      final ui = resolve(
        url: restrictedDomainUrl,
        lastRun: SaveRunRecord(
          runId: 'r1',
          origin: SaveOrigin.direct,
          state: SaveState.complete,
          urlKey: restrictedDomainUrl,
          pageSession: 7,
          storedEntries: 3,
          skippedEntries: 0,
          message: 'Saved 3 items',
        ),
      );
      expect(ui.status, BrowserSaveStatus.restricted);
      expect(ui.offersCapture, isFalse);
      expect(ui.result, isNull);
    });

    test('a stale failed result cannot bring the action back', () {
      final ui = resolve(
        url: restrictedDomainUrl,
        lastRun: SaveRunRecord(
          runId: 'r1',
          origin: SaveOrigin.queue,
          state: SaveState.failed,
          urlKey: restrictedDomainUrl,
          pageSession: 7,
          storedEntries: 0,
          skippedEntries: 0,
          message: 'failed',
          error: 'boom',
        ),
      );
      expect(ui.offersCapture, isFalse);
    });

    test('an already-saved page on a restricted site offers no re-save', () {
      final ui = resolve(
        url: restrictedDomainUrl,
        pageEntryState: EntryLocalState.complete,
      );
      expect(ui.status, BrowserSaveStatus.restricted);
      expect(ui.offersCapture, isFalse);
    });

    test('a queued row from before the policy offers no start', () {
      final ui = resolve(url: restrictedDomainUrl, pageIsQueued: true);
      expect(ui.status, BrowserSaveStatus.restricted);
      expect(ui.canStartDirect, isFalse);
    });

    test('a run working elsewhere does not restore the action', () {
      final ui = resolve(
        url: restrictedDomainUrl,
        hasActiveRun: true,
        activePageKey: allowedUrl,
      );
      expect(ui.status, BrowserSaveStatus.restricted);
      expect(ui.canQueue, isFalse);
    });
  });

  // --- 2. direct start ------------------------------------------------------

  group('a direct capture start', () {
    test('is refused, with nothing queued and nothing run', () async {
      final (:queue, :executed) = makeQueue();
      final result = await queue.startDirectSave(
        startUrl: restrictedDomainUrl,
        entryLimit: 1,
      );
      await settle();

      expect(result, DirectStartResult.restrictedSite);
      expect(queue.directSaveRunning, isFalse);
      expect(executed, isEmpty);
      expect(await db.pendingQueueTasks(), isEmpty);
      expect(await db.allEntries(), isEmpty);
      expect(browser.navigations, isEmpty);
      expectNoStagingLeft();
    });

    test('is refused for a restricted exact host too', () async {
      final (:queue, executed: _) = makeQueue();
      expect(
        await queue.startDirectSave(startUrl: restrictedHostUrl, entryLimit: 1),
        DirectStartResult.restrictedSite,
      );
    });

    test('a permitted address still starts', () async {
      // The negative control: the refusal above is the policy, not a queue
      // that has stopped starting anything. The run has no fixture page to
      // save and gives up quickly, which is not what this case is about — only
      // that it was allowed to begin.
      final run = makeRun(
        config: const SaveConfig(
          domReadyTimeout: Duration(milliseconds: 50),
          maxSaveDuration: Duration(milliseconds: 200),
        ),
      );
      final (:queue, executed: _) = makeQueue(run: run);
      expect(
        await queue.startDirectSave(startUrl: allowedUrl, entryLimit: 1),
        DirectStartResult.started,
      );
      // Let it unwind before the fixture database is torn down.
      while (queue.directSaveRunning) {
        await settle();
      }
    });
  });

  // --- 3. the run controller itself ----------------------------------------

  group('the save run', () {
    test(
      'refuses to start, writing no run row and taking no Browser',
      () async {
        final run = makeRun();
        await run.start(
          entryLimit: 3,
          startUrl: restrictedDomainUrl,
          range: SaveScope.fixedCount,
        );

        expect(run.progress.state, SaveState.failed);
        expect(run.stopReason, StopReason.captureRestrictedForSite);
        expect(run.progress.message, kCaptureRestrictedMessage);
        expect(run.isRunning, isFalse);
        expect(
          browser.automationOwner,
          isNull,
          reason: 'a refused run never claims the shared WebView',
        );
        expect(browser.navigationLocked, isFalse);
        expect(browser.navigations, isEmpty);
        expect(await db.allRuns(), isEmpty);
        expect(await db.allEntries(), isEmpty);
        expectNoStagingLeft();
      },
    );

    test('reports the refusal as this page\'s result', () async {
      final run = makeRun();
      await run.start(
        entryLimit: 1,
        startUrl: restrictedHostUrl,
        range: SaveScope.currentPageOnly,
      );
      expect(run.lastRun, isNotNull);
      expect(run.lastRun!.state, SaveState.failed);
      expect(run.lastRun!.storedEntries, 0);
    });
  });

  // --- 4. enqueueing --------------------------------------------------------

  group('adding to the queue', () {
    test('writes no row for a restricted address', () async {
      final (:queue, executed: _) = makeQueue();
      final result = await queue.enqueueSave(
        startUrl: restrictedDomainUrl,
        entryLimit: 1,
      );

      expect(result.restricted, isTrue);
      expect(result.id, isEmpty);
      expect(result.alreadyQueued, isFalse);
      expect(
        await db.pendingQueueTasks(),
        isEmpty,
        reason: 'a permanently-failing row is not a useful record',
      );
    });

    test('a batch queues the permitted entries and names the rest', () async {
      final ok = await seedSavedEntry(id: 'e-ok', url: allowedUrl);
      final blocked = await seedSavedEntry(
        id: 'e-blocked',
        url: restrictedDomainUrl,
      );
      final (:queue, executed: _) = makeQueue();

      final result = await queue.enqueueEntries([ok, blocked]);

      expect(result.queued, 1);
      expect(result.restricted.map((e) => e.id), ['e-blocked']);
      final pending = await db.pendingQueueTasks();
      expect(pending.map((t) => t.startUrl), [allowedUrl]);

      // The refused entry is untouched: still saved, still where it was.
      final after = await db.entryById('e-blocked');
      expect(after!.contentPath, blocked.contentPath);
      expect(after.saveStatus, 'complete');
      expect(after.progressFraction, 0.5);
    });
  });

  // --- 5. stale queued rows -------------------------------------------------

  group('a queued row whose site is now restricted', () {
    Future<QueueTask> insertStaleSave(String url) async {
      final task = QueueTask(
        id: 'stale-1',
        taskType: QueueTaskType.entrySave.name,
        startUrl: url,
        entryLimit: 1,
        captureModeIsUserSet: false,
        scope: SaveScope.currentPageOnly.name,
        origin: kQueueOriginQueue,
        state: QueueTaskState.queued.name,
        orderIndex: 1,
        queuedAt: DateTime(2026, 7, 1),
      );
      await db.upsertQueueTask(task);
      return task;
    }

    test('is settled by the pump instead of running', () async {
      await insertStaleSave(restrictedDomainUrl);
      final (:queue, :executed) = makeQueue();

      await queue.startQueuedSaves();
      await settle();

      final row = await db.queueTaskById('stale-1');
      expect(row, isNotNull, reason: 'the record is kept, never deleted');
      expect(row!.state, QueueTaskState.failed.name);
      expect(row.lastError, kCaptureRestrictedMessage);
      expect(row.stopReason, StopReason.captureRestrictedForSite.name);
      expect(executed, isEmpty, reason: 'no work was performed');
      expect(await db.allEntries(), isEmpty);
      expectNoStagingLeft();
    });

    test('does not block permitted work behind it', () async {
      await insertStaleSave(restrictedDomainUrl);
      final (:queue, :executed) = makeQueue();
      await queue.enqueueSave(startUrl: allowedUrl, entryLimit: 1);

      await queue.startQueuedSaves();
      await settle();

      expect(executed, [allowedUrl]);
    });

    test('cannot be pushed to the front and started', () async {
      await insertStaleSave(restrictedHostUrl);
      final (:queue, :executed) = makeQueue();

      expect(await queue.startQueuedTask('stale-1'), isFalse);
      await settle();

      expect(executed, isEmpty);
      expect((await db.queueTaskById('stale-1'))!.state, 'failed');
    });

    test('cannot be retried back into the queue', () async {
      await insertStaleSave(restrictedDomainUrl);
      final (:queue, executed: _) = makeQueue();
      // Settle it first, so this is a retry of a terminal row.
      await queue.startQueuedSaves();
      await settle();

      expect(await queue.retryTask('stale-1'), isNull);
      final pending = await db.pendingQueueTasks();
      expect(
        pending.where((t) => t.state == 'queued'),
        isEmpty,
        reason: 'a history row must not become a plan that runs',
      );
    });

    test('a retry of a permitted row still works', () async {
      final (:queue, executed: _) = makeQueue();
      await queue.enqueueSave(startUrl: allowedUrl, entryLimit: 1);
      final queued = (await queue.queuedSaves()).single;
      await queue.cancelTask(queued.id);

      expect(await queue.retryTask(queued.id), isNotNull);
    });
  });

  // --- 6. resume ------------------------------------------------------------

  group('resuming an interrupted run', () {
    SaveRun interrupted({required String startUrl, String? currentUrl}) =>
        SaveRun(
          id: 'run-00000001',
          startUrl: startUrl,
          currentUrl: currentUrl,
          requestedEntries: 5,
          completedEntries: 2,
          state: SaveState.paused.name,
          visitedUrls: '',
          visitedCanonicals: '',
          scope: SaveScope.fixedCount.name,
          captureModeIsUserSet: false,
          origin: SaveOrigin.direct.name,
          createdAt: DateTime(2026, 7, 1),
          updatedAt: DateTime(2026, 7, 1),
        );

    test('is refused when it would continue into a restricted site', () async {
      final (:queue, :executed) = makeQueue();
      final result = await queue.resumeInterruptedSave(
        interrupted(startUrl: allowedUrl, currentUrl: restrictedDomainUrl),
      );

      expect(result, DirectStartResult.restrictedSite);
      expect(executed, isEmpty);
      expect(browser.navigations, isEmpty);
    });

    test('is refused when the run began on a restricted site', () async {
      final (:queue, executed: _) = makeQueue();
      expect(
        await queue.resumeInterruptedSave(
          interrupted(startUrl: restrictedHostUrl),
        ),
        DirectStartResult.restrictedSite,
      );
    });

    test('the controller refuses the same resume directly', () async {
      final run = makeRun();
      await db.upsertRun(interrupted(startUrl: restrictedDomainUrl));
      await run.resumeRun(interrupted(startUrl: restrictedDomainUrl));

      expect(run.stopReason, StopReason.captureRestrictedForSite);
      expect(run.progress.state, SaveState.failed);
      expect(browser.navigations, isEmpty);
      expect(await db.allEntries(), isEmpty);
    });
  });

  // --- 7. update checking ---------------------------------------------------

  group('collection update checking', () {
    test('generates no queue work for a restricted collection', () async {
      await seedCollection('c-blocked', 'www.netflix.com', restrictedDomainUrl);
      final (:queue, :executed) = makeQueue();

      expect(await queue.enqueueCollectionCheck('c-blocked'), isNull);
      await settle();

      expect(await db.pendingQueueTasks(), isEmpty);
      expect(executed, isEmpty);
    });

    test('"check everything" skips it and checks the rest', () async {
      await seedCollection('c-blocked', 'www.netflix.com', restrictedDomainUrl);
      await seedCollection('c-ok', 'x.example', allowedUrl);
      // Both collections hold a saved entry, so the only thing separating them
      // is the policy — not eligibility.
      await seedSavedEntry(
        id: 'e-blocked',
        url: restrictedDomainUrl,
        collectionId: 'c-blocked',
      );
      await seedSavedEntry(id: 'e-ok', url: allowedUrl, collectionId: 'c-ok');
      final (:queue, :executed) = makeQueue();

      final ids = await queue.enqueueCheckAll();
      await settle();

      expect(ids, hasLength(1), reason: 'one row, for the permitted one');
      expect(executed, [
        'c-ok',
      ], reason: 'the restricted collection produced no work of any kind');
    });

    test('the checker refuses and navigates nowhere', () async {
      await seedCollection('c-blocked', 'tv.apple.com', restrictedHostUrl);
      await seedSavedEntry(
        id: 'e1',
        url: restrictedHostUrl,
        collectionId: 'c-blocked',
      );
      final checker = UpdateChecker(browser: browser, db: db);

      final outcome = await checker.check('c-blocked');

      expect(outcome.state, UpdateCheckState.failed);
      expect(outcome.error, kCaptureRestrictedMessage);
      expect(outcome.newEntries, 0);
      expect(browser.navigations, isEmpty);
      expect(browser.automationOwner, isNull);
      // No discovered rows were invented, and the held entry is untouched.
      expect((await db.entriesForCollection('c-blocked')).single.id, 'e1');
    });
  });

  // --- 8. a redirect mid-run ------------------------------------------------

  group('a redirect into a restricted site', () {
    late HttpServer server;
    late String assetBase;

    const config = SaveConfig(
      scrollDelay: Duration.zero,
      quietPeriod: Duration.zero,
      requiredStableChecks: 1,
      maxScrollIterations: 2,
      maxScrollPasses: 1,
      domReadyTimeout: Duration(seconds: 2),
      maxAssetWait: Duration(seconds: 2),
      downloadRetries: 0,
      cooldownBetweenEntries: Duration.zero,
      maxEntriesPerRun: 10,
    );

    setUp(() async {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      assetBase = 'http://127.0.0.1:${server.port}';
      server.listen((req) async {
        final m = RegExp(r'^/img/(\d+)/(\d+)\.png$').firstMatch(req.uri.path);
        if (m == null) {
          req.response.statusCode = 404;
          await req.response.close();
          return;
        }
        req.response.headers.contentType = ContentType('image', 'png');
        req.response.add(
          panelPng(
            entry: int.parse(m.group(1)!),
            index: int.parse(m.group(2)!),
          ),
        );
        await req.response.close();
      });
    });
    tearDown(() => server.close(force: true));

    test('stops the run before probing, downloading or committing', () async {
      const one = 'https://x.example/guide/foo/1';
      const two = 'https://x.example/guide/foo/2';

      browser.addPage(
        one,
        entryProbe(
          url: one,
          title: 'Foo Entry 1',
          imageUrls: [for (var i = 1; i <= 3; i++) '$assetBase/img/1/$i.png'],
          nextHref: two,
        ),
      );
      // Entry 2 redirects into a restricted service. Deliberately no fixture
      // page is registered for the destination: if anything probed it, the
      // fake browser would have to answer, and it cannot.
      browser.redirects[two] = restrictedDomainUrl;
      browser.setUrl(one);

      final run = makeRun(config: config);
      await run.start(
        entryLimit: 4,
        startUrl: one,
        range: SaveScope.fixedCount,
      );

      expect(run.stopReason, StopReason.captureRestrictedForSite);

      // Entry 1 committed and survived; entry 2 produced nothing at all.
      final entries = await db.allEntries();
      expect(entries, hasLength(1));
      expect(entries.single.sourceUrl, one);
      expect(entries.single.saveStatus, 'complete');
      expect(entries.single.contentPath, isNotNull);

      // Nothing partial, nothing staged, and no library folder for a second
      // entry.
      expectNoStagingLeft();
      expect(
        await db.findEntryByUrlKeyAnywhere(restrictedDomainUrl),
        isNull,
        reason: 'no entry, not even a failed one, for the restricted address',
      );
    });
  });

  // --- 9. nothing already held is disturbed --------------------------------

  group('existing user data', () {
    test('survives every refusal untouched', () async {
      await seedCollection('c1', 'www.netflix.com', restrictedDomainUrl);
      final before = await seedSavedEntry(
        id: 'held',
        url: restrictedDomainUrl,
        collectionId: 'c1',
      );
      final bytes = Directory(p.join(root.path, 'library', 'seeded', 'held'));

      final (:queue, executed: _) = makeQueue();
      await queue.startDirectSave(startUrl: restrictedDomainUrl, entryLimit: 1);
      await queue.enqueueSave(startUrl: restrictedDomainUrl, entryLimit: 1);
      await queue.enqueueCollectionCheck('c1');
      await queue.enqueueEntries([before]);
      await makeRun().start(
        entryLimit: 1,
        startUrl: restrictedDomainUrl,
        range: SaveScope.currentPageOnly,
      );
      await settle();

      final after = await db.entryById('held');
      expect(after, isNotNull);
      expect(after!.contentPath, before.contentPath);
      expect(after.saveStatus, 'complete');
      expect(after.byteSize, 4242);
      expect(after.readStatus, 'reading');
      expect(after.progressFraction, 0.5);
      expect(after.progressPageIndex, 2);
      expect(after.progressOffsetInPage, 0.25);
      expect(after.sourceUrl, restrictedDomainUrl);
      expect(await db.collectionById('c1'), isNotNull);
      expect(
        bytes.existsSync(),
        isTrue,
        reason: 'the policy prevents new capture; it never deletes',
      );
    });
  });
}
