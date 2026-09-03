// The V2 save flow, end to end against the in-process fixture on a real
// WebView.
//
//   flutter test integration_test/save_flow_test.dart -d <device-id>
//
// Nothing is mocked. A live WebView loads the fixture, the ported engine
// scrolls it, the IntersectionObserver panels arrive, bytes are downloaded into
// the app container, a manifest is written, the package is committed and an
// OfflineCopy is recorded.
//
// ## What this suite proves that V1's did not
//
// **The explicit Start is the whole shape of V2's save.** V1 had one call —
// `SaveRunController.start(range:, entryLimit:)` — that queued nothing and
// began driving the Browser immediately. V2 splits it: the Browser's save sheet
// writes a `save_queue` row and stops, and *nothing* touches a page until the
// user presses Start, an authorisation held in memory and never persisted. The
// first two cases here are that split, and it is the reason a save cannot
// resume itself on relaunch.
//
// ## Retired with V1, and deliberately not reinvented
//
// * **The multi-Entry traversal run** (`SaveScope.fixedCount`, "save 3 entries
//   and follow the chain", "loop and end-of-chain are handled"). V2 has no
//   traversal save: the queue's unit of work is **one Entry at one Location**
//   (V2-D15), and walking a source's `rel=next` to decide what to capture is
//   `recognition/check.dart`'s job now, where it discovers rows and downloads
//   nothing. There is no V2 surface that takes an entry count and drives the
//   Browser forward through it, so a scenario for one would be testing code
//   that does not exist. What is kept here is the property that mattered —
//   several Entries settled correctly from one authorisation — expressed the
//   way V2 expresses it, as a queue that drains.
// * **The duplicate-decision panel** (`DuplicatePolicy.replaceAll` /
//   `skipComplete`). V2 has no policy parameter and no prompt: an Entry has one
//   active OfflineCopy (I13), `enqueue` is idempotent while a row is open, and
//   a re-capture of an Entry that already has bytes commits through
//   `commitReplacing`, which keeps the old package readable until the new one
//   is in place. The last case here asserts that outcome directly.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:web_reader/capability/entitlement.dart';
import 'package:web_reader/features/v2_save_flow.dart';
import 'package:web_reader/save/queue_task.dart';
import 'package:web_reader/save/save_state.dart';
import 'package:web_reader/storage/manifest.dart';

import 'support/v2_harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final fixture = FixtureSite();
  late V2App app;
  var caseIndex = 0;

  setUpAll(fixture.start);
  tearDownAll(fixture.stop);

  Future<void> boot(WidgetTester tester, {String? startUrl}) async {
    app = V2App(tag: 'save_${caseIndex++}_$kRunStamp');
    await app.boot(tester);
    // The shell boots on the Library tab, and a WKWebView that has never been
    // painted reports zero layout metrics — which collapses any measurement the
    // save then depends on. `openPage` also dismisses Browser Home, so the
    // page the save controls describe is the page on screen.
    await showBrowser(tester);
    if (startUrl != null) await openPage(tester, app, startUrl);
  }

  tearDown(() => app.shutdown());

  testWidgets(
    'the bridge can inspect a live DOM',
    (tester) async {
      await boot(tester, startUrl: fixture.entry(1));

      final probe = await app.browser.probe(withLinks: true);

      expect(probe.title, contains('Entry 1'));
      expect(probe.url, contains('/entry/1'));
      expect(probe.documentHeight, greaterThan(0));
      expect(probe.viewportHeight, greaterThan(0));
      expect(probe.readyState, anyOf('interactive', 'complete'));
      expect(probe.images.length, greaterThan(5));
      expect(probe.links, isNotEmpty);
      expect(probe.links.any((l) => l.rel.contains('next')), isTrue);

      debugPrint(
        '[save] title="${probe.title}" images=${probe.images.length} '
        'height=${probe.documentHeight} links=${probe.links.length}',
      );
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );

  // ------------------------------------------------ the sheet, as it is now
  //
  // These three cases were written against a sheet that offered a **loose
  // save** — `v2SaveStandalone`, a button beside "Add to a Collection…" that
  // wrote an Entry belonging to nothing. V2-D69 retired it: a page the library
  // does not hold yet is asked *one* question, which Collection this is, and
  // the capture options belong to the sheet that answer hands back. There is
  // no fallback to take any more, so the old route into the queue does not
  // exist and these cases were asserting a control the product removed.
  //
  // What they are about has not changed, and is re-expressed here over the
  // flow that shipped:
  //
  //   * queueing writes a row and starts nothing (the V1/V2 split);
  //   * a launch closes the sheet and the surface underneath performs the
  //     Start (V2-D67);
  //   * the launch is **one** decision with three values, and nothing asks
  //     again after it (V2-D52, V2-D62).
  //
  // **Why `/text/N` and not `/entry/N`.** Every answer the picker can give
  // writes a Source, and a Source is `(host, path_key)`. `/entry/1`'s
  // fingerprint strips the number and then `entry` as an entry word, leaving
  // `/`, and `addressKeysRoot` refuses it because the path is two segments —
  // so the sheet honestly offers nothing to save there. `/text` survives as a
  // key. The image-sequence bytes are proved by the two cases below, which
  // write their rows through the repositories.

  /// One entry of the fixture's prose collection — the shape a Source can be
  /// made from.
  String textEntry(int n) => '${fixture.base}/text/$n';

  Finder key(String value) => find.byKey(ValueKey(value));

  /// Browser → Save → *Add to a Collection…* → *New collection* → this entry.
  ///
  /// Ends with the save sheet open on its launches: the range answered, the
  /// name in the field, and nothing written yet.
  Future<void> answerTheCollectionQuestion(
    WidgetTester tester, {
    int? fromHere,
  }) async {
    expect(
      key('browserSaveAction'),
      findsOneWidget,
      reason: 'the save control is present on a page that is not restricted',
    );
    await tester.tap(key('browserSaveAction'), warnIfMissed: false);
    await pumpFor(tester, const Duration(seconds: 3));

    expect(
      key('v2SaveStandalone'),
      findsNothing,
      reason: 'there is no loose save to fall back to any more (V2-D69)',
    );
    expect(
      key('v2AddToCollection'),
      findsOneWidget,
      reason: 'which Collection this is, is the whole question',
    );
    await tester.tap(key('v2AddToCollection'), warnIfMissed: false);
    await pumpFor(tester, const Duration(seconds: 2));

    await tester.tap(key('collectionPickerNew'), warnIfMissed: false);
    await pumpFor(tester, const Duration(seconds: 2));

    // The picker's answer turns this same sheet into the one that saves: the
    // name, the range and the launches, with no screen in between (V2-D57).
    expect(key('collectionNameField'), findsOneWidget);
    if (fromHere == null) {
      await tester.tap(key('saveScopeThisEntry'), warnIfMissed: false);
      await pumpFor(tester, const Duration(seconds: 1));
      return;
    }
    // *The next N from here*: one sequential journey along this Source
    // (V2-D56), which is also what gives a run long enough to be watched.
    await tester.tap(key('saveScopeFromHere'), warnIfMissed: false);
    await pumpFor(tester, const Duration(seconds: 1));
    // The field does not autofocus — choosing a range is not asking for a
    // keyboard over the launches — so this is the tap that raises it.
    await tester.tap(key('saveCountField'), warnIfMissed: false);
    await pumpFor(tester, const Duration(seconds: 1));
    await tester.enterText(key('saveCountField'), '$fromHere');
    await pumpFor(tester, const Duration(seconds: 1));
    // OK, exactly as an iOS user has to: the number pad has no return key,
    // and the bar it sits on is taking the room the launches need until it
    // goes.
    await tester.tap(key('saveCountOk'), warnIfMissed: false);
    await pumpFor(tester, const Duration(seconds: 1));
  }

  /// Press one of the sheet's own controls, scrolling to it first — the sheet
  /// asks three questions above them, so on a phone they start below the fold.
  Future<void> press(WidgetTester tester, String optionKey) async {
    await tester.ensureVisible(key(optionKey));
    await pumpFor(tester, const Duration(milliseconds: 500));
    await tester.tap(key(optionKey), warnIfMissed: false);
    await pumpFor(tester, const Duration(seconds: 3));
  }

  testWidgets(
    'the sheet queues the page, and nothing captures until Start',
    (tester) async {
      await boot(tester, startUrl: textEntry(1));
      await answerTheCollectionQuestion(tester);

      // *Queue only* — the answer that is complete and starts nothing.
      await press(tester, 'saveScopeAddToQueue');

      // One row, waiting. This is the half of the flow V1 did not have.
      final queued = await app.ui.queue.all();
      expect(queued, hasLength(1));
      expect(queued.single.state, SaveTaskState.queued);
      expect(
        app.runner.isRunning,
        isFalse,
        reason: 'a queued save must not begin on its own',
      );
      expect(
        await app.ui.offline.allCopies(),
        isEmpty,
        reason: 'and it must not have written any bytes',
      );
      // The library half happened, and only the library half.
      final root = await app.ui.folders.ensureRoot();
      expect(
        await app.ui.collections.inFolder(root.id),
        hasLength(1),
        reason: 'the picker\'s answer created exactly one Collection',
      );
      expect(
        find.text('Queued — waiting for Start.'),
        findsOneWidget,
        reason: 'the sheet says so in the same words the queue does',
      );
      expect(
        key('v2StartButton'),
        findsOneWidget,
        reason: 'and offers the explicit Start for the row it just wrote',
      );

      // Start through the shell's own `_startQueuedDownloads`, which is the
      // one place V2 Browser automation is authorised from. The foreground
      // gate decides *where the user waits* and never whether the work
      // happens — and it is asked here because *Queue only* answered nothing
      // about a launch.
      await startQueue(tester, app);
      await awaitQueueIdle(tester, app);

      final entryId = queued.single.entryId;
      final task = await app.latestTaskFor(entryId);
      expect(task!.state, SaveTaskState.completed);
      expect(
        await app.ui.offline.activeCopyOf(entryId),
        isNotNull,
        reason: 'the row the sheet wrote became bytes on this device',
      );
      expect(
        app.everHeldForBrowser,
        isFalse,
        reason: 'the Browser was in front the whole time',
      );
    },
    timeout: const Timeout(Duration(minutes: 8)),
  );

  // ------------------------------------------------- the sheet's own launches
  //
  // V2-D67: **a launch closes the save sheet, and the surface underneath
  // performs the Start.** The sheet is a modal route over the Browser and
  // `QueueRunner.start` does not return until the batch is done, so a sheet
  // that awaited the starter itself sat over the page it had just sent the app
  // to read.
  //
  // Both cases below press the launch **on the sheet**, which is where it
  // lives now (V2-D62). That is also the assertion that matters most about it:
  // the launch is one decision with three values, so answering it here must
  // not produce a second question afterwards (V2-D52).
  testWidgets(
    'a start on the sheet closes it and runs, without asking twice',
    (tester) async {
      await boot(tester, startUrl: textEntry(1));
      await answerTheCollectionQuestion(tester);

      await press(tester, 'startInBrowser');

      expect(
        find.byType(V2SavePanel),
        findsNothing,
        reason: 'the sheet closes on the way to the Start it asked for',
      );
      expect(
        key('startInBrowser'),
        findsNothing,
        reason:
            'the launch was answered on the sheet, so nothing asks a second '
            'time where the user would like to wait (V2-D52)',
      );

      await awaitQueueIdle(tester, app);
      final task = (await app.ui.queue.all()).single;
      expect(task.state, SaveTaskState.completed);
      expect(await app.ui.offline.activeCopyOf(task.entryId), isNotNull);
    },
    timeout: const Timeout(Duration(minutes: 8)),
  );

  // The defect this case exists for: *Start and keep using* took the branch
  // that claims the Browser surface **without popping anything**, so the save
  // sheet stayed on screen over the page for the whole run — the one launch
  // whose entire promise is that the user carries straight on. It runs on the
  // Pro arm because that is the only arm the row is offered on.
  testWidgets(
    'a keep-using-the-app start closes the sheet and leaves the Browser '
    'usable while the work runs',
    (tester) async {
      app = V2App(
        tag: 'save_${caseIndex++}_$kRunStamp',
        multitaskingPreference: true,
        entitlement: EntitlementOverride.forcePro,
      );
      await app.boot(tester);
      await showBrowser(tester);
      await openPage(tester, app, textEntry(1));

      await answerTheCollectionQuestion(tester, fromHere: 3);
      expect(
        key('startKeepUsingApp'),
        findsOneWidget,
        reason: 'the Pro arm is the one this row is offered on',
      );
      await press(tester, 'startKeepUsingApp');

      // The whole of the bug, asserted: nothing of the save UI is left, no
      // modal barrier stands between the user and the page, and the work is
      // visible and stoppable from the Browser they are still on.
      //
      // Not `browserSaveAction`: **while a run runs that control is not drawn
      // at all** (`BrowserSaveActions`, and the tooltip's own comment says
      // so), so asserting it hit-testable asserted the absence of the run.
      // What a user has instead is the docked panel, which is the surface this
      // launch promises to leave them with.
      expect(find.byType(V2SavePanel), findsNothing);
      expect(
        find.byType(ModalBarrier).hitTestable(),
        findsNothing,
        reason: 'nothing modal is left between the user and the page',
      );
      await pumpUntil(
        tester,
        () => key('panelStopDownload').hitTestable().evaluate().isNotEmpty,
        timeout: const Duration(seconds: 60),
        reason:
            'the run is on screen under the page, and the user can end it '
            'without leaving where they are',
      );

      await awaitQueueIdle(tester, app);
      final copies = (await app.ui.offline.allCopies())
          .where((c) => c.active)
          .toList();
      expect(
        copies,
        hasLength(3),
        reason:
            'the journey the sheet authorised ran to its count with the '
            'sheet gone',
      );
      for (final task in await app.ui.queue.all()) {
        expect(task.state, SaveTaskState.completed);
      }
    },
    timeout: const Timeout(Duration(minutes: 8)),
  );

  testWidgets(
    'one Start drains every queued Entry',
    (tester) async {
      await boot(tester, startUrl: fixture.entry(1));

      final ids = <int, String>{};
      for (final n in [1, 2, 3]) {
        ids[n] = await app.queueSaveOf(fixture.entry(n), title: 'Entry $n');
      }
      expect(await app.ui.queue.pending(), hasLength(3));

      await startQueue(tester, app);
      await awaitQueueIdle(tester, app);

      for (final n in [1, 2, 3]) {
        final task = await app.latestTaskFor(ids[n]!);
        expect(
          task!.state,
          SaveTaskState.completed,
          reason:
              'entry $n ended ${task.state.name}: '
              '${task.lastError ?? task.outcome}',
        );
      }
      expect(
        await app.ui.queue.pending(),
        isEmpty,
        reason: 'one authorisation drained the whole queue',
      );
      expect(
        app.ui.queue.saveStartAuthorised,
        isFalse,
        reason: 'and the authorisation was revoked when it ran dry',
      );

      // Entry 2's fifth panel is a 503, deliberately and on every run.
      final second = await app.manifestOf(ids[2]!);
      expect(
        second!.status,
        SaveStatus.partial,
        reason: 'the 503 panel must produce a partial, never a false complete',
      );
      expect(second.storedAssetCount, kFixtureImagesPerEntry - 1);
      final failed = second.assets.where((a) => a.status == AssetStatus.failed);
      expect(failed, hasLength(1));
      expect(failed.first.error, isNotNull);
      expect(
        failed.first.relativePath,
        isNull,
        reason: 'a failed asset must not claim a local file',
      );

      for (final n in [1, 3]) {
        final manifest = await app.manifestOf(ids[n]!);
        expect(manifest!.status, SaveStatus.complete);
        expect(manifest.storedAssetCount, kFixtureImagesPerEntry);
        expect(manifest.detectedAssetCount, kFixtureImagesPerEntry);
      }
    },
    timeout: const Timeout(Duration(minutes: 12)),
  );

  testWidgets(
    'stored assets are real bytes, in reading order',
    (tester) async {
      await boot(tester, startUrl: fixture.entry(1));

      final entryId = await app.queueSaveOf(fixture.entry(1));
      await startQueue(tester, app);
      await awaitQueueIdle(tester, app);

      final copy = await app.ui.offline.activeCopyOf(entryId);
      expect(copy, isNotNull, reason: 'the capture recorded no copy');
      final relative = copy!.contentPath;
      expect(
        relative,
        isNot(startsWith('/')),
        reason:
            'stored paths are relative to the app container — the iOS path '
            'carries a UUID that changes between installs',
      );
      expect(Directory(app.fileStore.resolve(relative)).existsSync(), isTrue);

      final manifest = (await app.fileStore.readManifest(relative))!;
      expect(manifest.storedAssets.map((a) => a.relativePath), [
        'assets/001.png',
        'assets/002.png',
        'assets/003.png',
        'assets/004.png',
        'assets/005.png',
        'assets/006.png',
      ]);

      var totalBytes = 0;
      for (final asset in manifest.storedAssets) {
        final file = app.fileStore.assetFile(relative, asset.relativePath!);
        expect(file.existsSync(), isTrue, reason: asset.relativePath);
        final bytes = await file.readAsBytes();
        expect(bytes.length, greaterThan(1000));
        expect(
          bytes.sublist(0, 4),
          [0x89, 0x50, 0x4e, 0x47],
          reason: 'real PNG bytes, not a placeholder or an HTML error page',
        );
        totalBytes += bytes.length;
      }
      expect(copy.byteSize, greaterThan(0));
      debugPrint(
        '[save] ${manifest.storedAssetCount} images, $totalBytes bytes',
      );
    },
    timeout: const Timeout(Duration(minutes: 8)),
  );

  testWidgets(
    'capturing an Entry again replaces its copy without duplicating it',
    (tester) async {
      await boot(tester, startUrl: fixture.entry(1));

      final entryId = await app.queueSaveOf(fixture.entry(1));
      await startQueue(tester, app);
      await awaitQueueIdle(tester, app);

      final before = await app.ui.offline.activeCopyOf(entryId);
      expect(before, isNotNull);
      final beforeManifest = (await app.manifestOf(entryId))!;
      expect(beforeManifest.status, SaveStatus.complete);

      // A second request for the same Entry. The queue is idempotent while a
      // row is open, so this is a genuinely new row over a terminal one.
      final again = await app.ui.queue.enqueue(
        entryId: entryId,
        locationUrl: fixture.entry(1),
      );
      expect(again.alreadyQueued, isFalse);
      expect(again.refusedReason, isNull);

      await startQueue(tester, app);
      await awaitQueueIdle(tester, app);

      final copies = await app.ui.offline.allCopies();
      expect(
        copies.where((c) => c.entryId == entryId && c.active),
        hasLength(1),
        reason: 'an Entry has one active OfflineCopy on a device (I13)',
      );
      final after = await app.ui.offline.activeCopyOf(entryId);
      expect(
        after!.contentPath,
        before!.contentPath,
        reason: 'the package is replaced in place, not stacked beside itself',
      );
      final afterManifest = (await app.manifestOf(entryId))!;
      expect(afterManifest.status, SaveStatus.complete);
      expect(afterManifest.storedAssetCount, beforeManifest.storedAssetCount);
      expect(
        Directory(app.fileStore.resolve(after.contentPath)).existsSync(),
        isTrue,
        reason: 'and the replacement left a readable package behind it',
      );
    },
    timeout: const Timeout(Duration(minutes: 12)),
  );

  testWidgets(
    'cancelling a running download stops it without a false success',
    (tester) async {
      await boot(tester, startUrl: fixture.entry(1));

      final entryId = await app.queueSaveOf(fixture.entry(1));
      await startQueue(tester, app);

      // Let it get properly into a Browser phase — a cancel before the capture
      // has started proves nothing about stopping one that has.
      await pumpUntil(
        tester,
        () => app.runner.activeTaskId != null && app.runner.isRunning,
        timeout: const Duration(seconds: 60),
        reason: 'the queue never claimed the row',
      );
      final taskId = app.runner.activeTaskId!;
      await pumpUntil(
        tester,
        () => app.engineStates.contains(SaveState.scrolling),
        timeout: const Duration(seconds: 90),
        reason: 'the capture never reached a Browser phase',
      );

      // The user's cancel, through the queue — one conditional UPDATE, so exactly
      // one of a racing pair wins.
      final outcome = await app.ui.queue.cancel(taskId);
      expect(outcome, SaveCancelOutcome.stoppingRunning);

      await awaitQueueIdle(tester, app, timeout: const Duration(minutes: 2));

      final row = await app.ui.queue.byId(taskId);
      expect(
        row!.state,
        SaveTaskState.cancelled,
        reason:
            'cancelling preserves the row in the cancelled state — there is no '
            'sixth state, and a cancel is never a deletion',
      );
      expect(row.outcome, kSaveTaskStopping);
      expect(
        await app.ui.offline.activeCopyOf(entryId),
        isNull,
        reason: 'a cancelled capture commits nothing',
      );
    },
    timeout: const Timeout(Duration(minutes: 8)),
  );
}
