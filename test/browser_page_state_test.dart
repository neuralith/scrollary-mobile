import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_reader/browser/browser_controller.dart';
import 'package:web_reader/core/config.dart';
import 'package:web_reader/browser/history_repository.dart'
    show NavigationSource;
import 'package:web_reader/save/save_run.dart';
import 'package:web_reader/save/save_preflight.dart';
import 'package:web_reader/save/save_state.dart';
import 'package:web_reader/core/url_utils.dart';
import 'package:web_reader/features/browser_save_state.dart';
import 'package:web_reader/core/device_storage.dart';
import 'package:web_reader/queue/task_queue.dart';
import 'package:web_reader/storage/database.dart';
import 'package:web_reader/storage/file_store.dart';

import 'helpers/fake_browser.dart';

/// The Browser's save state is **page** state (D59).
///
/// The bug this file exists to prevent: a save completes, and the Browser
/// goes on showing "complete" on every page the user opens afterwards, with
/// Save looking blocked. The fix is not to hide the widget — it is that the
/// state is derived from the page on screen and the work that genuinely
/// matches it.
void main() {
  const pageA = 'https://x.example/guide/foo/350';
  const pageB = 'https://x.example/guide/foo/351';
  final keyA = pageIdentityKey(pageA);
  final keyB = pageIdentityKey(pageB);

  SaveRunRecord finished({
    required int session,
    String url = pageA,
    SaveState state = SaveState.complete,
    SaveOrigin origin = SaveOrigin.direct,
  }) => SaveRunRecord(
    runId: 'run-1',
    origin: origin,
    state: state,
    urlKey: pageIdentityKey(url),
    pageSession: session,
    storedEntries: 1,
    skippedEntries: 0,
    message: 'Saved 1 entry(s)',
  );

  BrowserSaveState resolve({
    String pageKey = '',
    int pageSession = 2,
    bool hasActiveRun = false,
    String activePageKey = '',
    SaveState activeState = SaveState.idle,
    bool needsRenderedBrowser = false,
    bool awaitingUser = false,
    bool pausedForBrowser = false,
    bool checkerRunning = false,
    bool pageEnteredManually = true,
    SaveRunRecord? lastRun,
    EntryLocalState? pageEntryState,
    bool pageIsQueued = false,
    bool captureRestricted = false,
  }) => resolveBrowserSaveState(
    pageKey: pageKey,
    pageSession: pageSession,
    hasActiveRun: hasActiveRun,
    activePageKey: activePageKey,
    activeState: activeState,
    needsRenderedBrowser: needsRenderedBrowser,
    awaitingUser: awaitingUser,
    pausedForBrowser: pausedForBrowser,
    checkerRunning: checkerRunning,
    pageEnteredManually: pageEnteredManually,
    lastRun: lastRun,
    pageEntryState: pageEntryState,
    pageIsQueued: pageIsQueued,
    captureRestricted: captureRestricted,
  );

  group('page session identity', () {
    test('a main-frame page change starts a new session', () {
      final browser = BrowserController();
      addTearDown(browser.dispose);

      browser.onLoadStart(pageA);
      final first = browser.pageSession;
      expect(first, greaterThan(0));
      expect(browser.pageSessionKey, keyA);

      browser.onLoadStart(pageB);
      expect(browser.pageSession, first + 1);
      expect(browser.pageSessionKey, keyB);
    });

    test('a hash jump is the same page, not a new one', () async {
      final browser = BrowserController();
      addTearDown(browser.dispose);

      browser.onLoadStart(pageA);
      final session = browser.pageSession;
      browser.onUrlChanged('$pageA#comments');
      await browser.onLoadStop('$pageA#comments');
      expect(browser.pageSession, session);
    });

    test('the same page reloading is the same page', () async {
      final browser = BrowserController();
      addTearDown(browser.dispose);

      browser.onLoadStart(pageA);
      final session = browser.pageSession;
      // Load start, progress, stop — one page, several callbacks.
      await browser.onLoadStop(pageA);
      browser.onUrlChanged(pageA);
      browser.onLoadStart(pageA);
      expect(browser.pageSession, session);
    });

    test('a redirect resolves into one page, not two states', () async {
      final browser = BrowserController();
      addTearDown(browser.dispose);

      browser.onLoadStart(pageA);
      // The server sends us elsewhere; the landing page is what is on screen.
      await browser.onLoadStop(pageB);
      expect(browser.pageSessionKey, keyB);
      expect(browser.currentUrl, pageB);
    });

    test('about:blank and app schemes start no session at all', () {
      final browser = BrowserController();
      addTearDown(browser.dispose);

      browser.onLoadStart('about:blank');
      expect(browser.pageSession, 0);
      expect(browser.pageSessionKey, isEmpty);
      browser.onLoadStart('mailto:someone@example.com');
      expect(browser.pageSession, 0);
    });

    test('automation moving the page is not the user browsing', () {
      final browser = BrowserController();
      addTearDown(browser.dispose);

      browser.onLoadStart(pageA);
      expect(browser.pageSessionIsManual, isTrue);

      browser.automationOwner = 'a save run';
      browser.navigationSource = NavigationSource.saveAutomation;
      browser.onLoadStart(pageB);
      expect(browser.pageSessionSource, NavigationSource.saveAutomation);
      expect(browser.pageSessionIsManual, isFalse);
    });
  });

  group('a finished run belongs to the page it finished on', () {
    for (final state in const [
      SaveState.complete,
      SaveState.failed,
      SaveState.cancelled,
      SaveState.partial,
    ]) {
      test('${state.name} clears when the Browser moves to another page', () {
        final run = finished(session: 2, state: state);

        // Still on the page it happened on: the result is shown.
        final onPage = resolve(pageKey: keyA, pageSession: 2, lastRun: run);
        expect(onPage.result, isNotNull);

        // The user navigates: a new session, and the result goes with the
        // page it belonged to.
        final next = resolve(pageKey: keyB, pageSession: 3, lastRun: run);
        expect(next.result, isNull);
        expect(next.status, BrowserSaveStatus.save);
        expect(next.label, 'Save');
        expect(
          next.canStartDirect,
          isTrue,
          reason: 'a historical run never disables Save',
        );
        expect(next.canQueue, isTrue);
        expect(next.showsRunPanel, isFalse);
      });
    }

    test('the same URL in a later session is still a new page', () {
      // Re-visiting the page a save finished on is a fresh visit; the old
      // result does not come back with it.
      final run = finished(session: 2);
      final again = resolve(pageKey: keyA, pageSession: 7, lastRun: run);
      expect(again.result, isNull);
      expect(again.status, BrowserSaveStatus.save);
    });

    test('a completed run elsewhere never shows on this page', () {
      final run = finished(session: 2, url: pageA);
      final elsewhere = resolve(pageKey: keyB, pageSession: 2, lastRun: run);
      expect(elsewhere.result, isNull);
    });
  });

  group('active work', () {
    test('the run on this page is what this page shows', () {
      final ui = resolve(
        pageKey: keyA,
        hasActiveRun: true,
        activePageKey: keyA,
        activeState: SaveState.scrolling,
        needsRenderedBrowser: true,
      );
      expect(ui.status, BrowserSaveStatus.saving);
      expect(ui.showsRunPanel, isTrue);
      expect(ui.opensSaveSheet, isFalse);
    });

    test('automation navigating on does not end the run it belongs to', () {
      // The engine hopped to the next entry: new page session, new page key,
      // and the run simply moved with it.
      final ui = resolve(
        pageKey: keyB,
        pageSession: 3,
        hasActiveRun: true,
        activePageKey: keyB,
        activeState: SaveState.extracting,
        needsRenderedBrowser: true,
        pageEnteredManually: false,
      );
      expect(ui.status, BrowserSaveStatus.saving);
      expect(ui.showsRunPanel, isTrue);
    });

    test('mid-hop, the run is still the run', () {
      // While navigating, the run's page is the *target* and the Browser is
      // still showing the page it is leaving. They are supposed to disagree,
      // and the panel must not blink out of existence for it.
      final ui = resolve(
        pageKey: keyA,
        hasActiveRun: true,
        activePageKey: keyB,
        activeState: SaveState.navigating,
        needsRenderedBrowser: true,
      );
      expect(ui.status, BrowserSaveStatus.saving);
      expect(ui.showsRunPanel, isTrue);
    });

    test('a page automation put here belongs to the run that put it there', () {
      final ui = resolve(
        pageKey: keyB,
        hasActiveRun: true,
        activePageKey: '',
        activeState: SaveState.inspecting,
        needsRenderedBrowser: true,
        pageEnteredManually: false,
      );
      expect(ui.status, BrowserSaveStatus.saving);
    });

    test('a run working elsewhere is not this page state', () {
      final ui = resolve(
        pageKey: keyB,
        hasActiveRun: true,
        activePageKey: keyA,
        activeState: SaveState.fetchingAssets,
      );
      expect(ui.status, BrowserSaveStatus.busyElsewhere);
      expect(ui.showsRunPanel, isFalse);
      expect(ui.canQueue, isTrue, reason: 'queueing starts nothing');
      expect(ui.canStartDirect, isFalse);
      expect(ui.busyLabel, isNotNull);
    });

    test('a download-only phase on this page says so', () {
      final ui = resolve(
        pageKey: keyA,
        hasActiveRun: true,
        activePageKey: keyA,
        activeState: SaveState.fetchingAssets,
      );
      expect(ui.status, BrowserSaveStatus.downloading);
    });

    test('holding for the Browser is its own state', () {
      final ui = resolve(
        pageKey: keyA,
        hasActiveRun: true,
        activePageKey: keyA,
        activeState: SaveState.scrolling,
        pausedForBrowser: true,
      );
      expect(ui.status, BrowserSaveStatus.waitingForBrowser);
    });

    test('a question to the user outranks the phase', () {
      final ui = resolve(
        pageKey: keyA,
        hasActiveRun: true,
        activePageKey: keyA,
        activeState: SaveState.awaitingSelection,
        awaitingUser: true,
      );
      expect(ui.status, BrowserSaveStatus.needsInput);
    });

    test('an update check blocks the direct start, not the queue', () {
      final ui = resolve(pageKey: keyA, checkerRunning: true);
      expect(ui.status, BrowserSaveStatus.busyElsewhere);
      expect(ui.canQueue, isTrue);
      expect(ui.canStartDirect, isFalse);
    });
  });

  group('what this page already has', () {
    test('a saved page offers to save again, never refuses', () {
      final ui = resolve(
        pageKey: keyA,
        pageEntryState: EntryLocalState.complete,
      );
      expect(ui.status, BrowserSaveStatus.availableOffline);
      expect(ui.canStartDirect, isTrue);
      expect(ui.canQueue, isTrue);
      expect(ui.detail, 'Already available offline');
    });

    test('a queued page shows queued, and only its own page does', () {
      final ui = resolve(pageKey: keyA, pageIsQueued: true);
      expect(ui.status, BrowserSaveStatus.queued);
      expect(ui.opensSaveSheet, isFalse);

      final other = resolve(pageKey: keyB, pageIsQueued: false);
      expect(other.status, BrowserSaveStatus.save);
    });

    test('with no page loaded there is nothing to start', () {
      final ui = resolve(pageKey: '');
      expect(ui.canStartDirect, isFalse);
      expect(ui.canQueue, isFalse);
      expect(ui.result, isNull);
    });
  });

  group('the controller publishes a page-scoped record', () {
    late AppDatabase db;
    late Directory root;
    late FakeBrowser browser;
    late SaveRunController run;

    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      root = Directory.systemTemp.createTempSync('webread_run_record');
      browser = FakeBrowser();
      run = SaveRunController(
        browser: browser,
        db: db,
        fileStore: FileStore(root),
        deviceStorage: _NoSpace(),
      );
    });

    tearDown(() async {
      await db.close();
      if (root.existsSync()) root.deleteSync(recursive: true);
    });

    test('a run that refuses to start still reports its result', () async {
      browser.debugEnterPage(pageA);
      final session = browser.pageSession;

      await run.start(
        range: SaveScope.fixedCount,
        entryLimit: 1,
        startUrl: pageA,
      );

      final record = run.lastRun;
      expect(record, isNotNull);
      expect(record!.state, SaveState.failed);
      expect(record.error, 'insufficientStorage');
      expect(record.urlKey, keyA);
      expect(record.pageSession, session);
      expect(run.hasActiveRun, isFalse, reason: 'a result is not a run');

      // On its own page it is shown…
      expect(
        resolve(
          pageKey: keyA,
          pageSession: session,
          lastRun: run.lastRun,
        ).result,
        isNotNull,
      );
      // …and the moment the Browser is somewhere else, it is not.
      browser.debugEnterPage(pageB);
      expect(
        resolve(
          pageKey: browser.pageSessionKey,
          pageSession: browser.pageSession,
          lastRun: run.lastRun,
        ).result,
        isNull,
      );
    });

    test('starting again drops the previous result', () async {
      browser.debugEnterPage(pageA);
      await run.start(
        range: SaveScope.fixedCount,
        entryLimit: 1,
        startUrl: pageA,
      );
      expect(run.lastRun, isNotNull);

      await run.start(
        range: SaveScope.fixedCount,
        entryLimit: 1,
        startUrl: pageB,
      );
      expect(run.lastRun!.urlKey, keyB, reason: 'this run, not the last one');
    });

    test('dismissing a result clears it for good', () async {
      browser.debugEnterPage(pageA);
      await run.start(
        range: SaveScope.fixedCount,
        entryLimit: 1,
        startUrl: pageA,
      );
      run.clearLastRun();
      expect(run.lastRun, isNull);
    });

    test('a direct run is recorded as direct', () async {
      await run.start(
        range: SaveScope.fixedCount,
        entryLimit: 1,
        startUrl: pageA,
        origin: SaveOrigin.direct,
      );
      expect(run.lastRun!.origin, SaveOrigin.direct);
    });
  });

  group('matching a queued task to a page', () {
    QueueTask task(
      String url, {
      String state = 'queued',
      String type = 'entrySave',
    }) => QueueTask(
      origin: 'queue',
      id: url,
      captureModeIsUserSet: false,
      taskType: type,
      startUrl: url,
      state: state,
      orderIndex: 1,
      queuedAt: DateTime(2026, 7, 28),
    );

    test('a waiting task for this page matches, fragments and all', () {
      expect(pageHasQueuedSave([task(pageA)], keyA), isTrue);
      expect(pageHasQueuedSave([task('$pageA#top')], keyA), isTrue);
      expect(pageHasQueuedSave([task(pageB)], keyA), isFalse);
    });

    test('running and finished rows are not "queued"', () {
      expect(pageHasQueuedSave([task(pageA, state: 'running')], keyA), isFalse);
      expect(
        pageHasQueuedSave([task(pageA, state: 'completed')], keyA),
        isFalse,
        reason: 'history must not make a page look queued',
      );
    });

    test('a queued check is not a queued save', () {
      expect(
        pageHasQueuedSave([task(pageA, type: 'collectionCheck')], keyA),
        isFalse,
      );
    });

    test('an empty page matches nothing', () {
      expect(pageHasQueuedSave([task(pageA)], ''), isFalse);
    });
  });
}

/// A device with nothing left, so a run refuses at the door — the cheapest
/// real run there is, and one with a result worth reporting.
class _NoSpace extends DeviceStorage {
  @override
  Future<int?> freeBytes() async => 1024;
}
