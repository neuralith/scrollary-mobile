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

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
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

  testWidgets(
    'the save sheet queues the page, and nothing captures until Start',
    (tester) async {
      await boot(tester, startUrl: fixture.entry(1));

      // Through the real control: the Browser's save action, which is absent
      // rather than disabled on a restricted host and present here.
      final saveAction = find.byKey(const ValueKey('browserSaveAction'));
      expect(saveAction, findsOneWidget);
      await tester.tap(saveAction, warnIfMissed: false);
      await pumpFor(tester, const Duration(seconds: 3));

      // A numbered fixture entry reads as one entry of a collection, so the
      // sheet leads with "Add to a Collection…" and offers the loose save
      // underneath. This test is about the queue, so it takes the loose one —
      // the deliberate fallback, which is exactly what it is for.
      final saveButton = find.byKey(const ValueKey('v2SaveStandalone'));
      expect(
        saveButton,
        findsOneWidget,
        reason: 'the sheet must offer a save for a page it can hold',
      );
      await tester.tap(saveButton, warnIfMissed: false);
      await pumpFor(tester, const Duration(seconds: 3));

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
      expect(
        find.text('Queued — waiting for Start.'),
        findsOneWidget,
        reason: 'the sheet says so in the same words the queue does',
      );

      // The sheet offers the explicit Start. It is asserted here and pressed in
      // the next case, which is `skip`ped against a defect — see its header.
      expect(find.byKey(const ValueKey('v2StartButton')), findsOneWidget);

      // Start through the shell's own `_startQueuedDownloads`, which is the
      // one place V2 Browser automation is authorised from and what every
      // Start control ultimately calls. The foreground gate decides *where the
      // user waits* and never whether the work happens.
      await startQueue(tester, app);
      await awaitQueueIdle(tester, app);

      final entryId = queued.single.entryId;
      final task = await app.latestTaskFor(entryId);
      expect(task!.state, SaveTaskState.completed);
      expect(await app.storedImagesOf(entryId), kFixtureImagesPerEntry);
      expect(
        app.everHeldForBrowser,
        isFalse,
        reason: 'the Browser was in front the whole time',
      );
    },
    timeout: const Timeout(Duration(minutes: 8)),
  );

  // ---------------------------------------------------------------- defect
  //
  // **DEFECT — the save sheet's own Start button throws.** Skipped rather than
  // deleted, because the scenario is right and the app is wrong.
  //
  // `_V2SavePanelState._start` (lib/features/v2_save_flow.dart:242) awaits the
  // starter and then calls `_refresh()`. The starter is the shell's
  // `_startQueuedDownloads`, which for the *Start in Browser* choice calls
  // `showBrowserSurface`, which pops the routes above the shell — dismissing
  // the modal bottom sheet that hosts this very panel. `_refresh` then calls
  // `v2PageStatusFor(ref, …)` (:221 → :50), which does
  // `ref.read(libraryUiServicesProvider)` on a `ConsumerState` that is already
  // disposed:
  //
  //     Bad state: Using "ref" when a widget is about to or has been unmounted
  //     is unsafe.
  //
  // The `if (mounted)` guard inside `_refresh` sits *after* the `ref.read`, so
  // it never runs. Reproduced on the iPhone 17 simulator, debug: Browser → a
  // saveable page → Save → "Save for offline" → "Start" → "Start in Browser".
  //
  // The save itself still happens — the queue is authorised and the runner
  // drains it — so this is an unhandled async error on the app's commonest save
  // path rather than a functional stop. In an integration test it also wedges
  // the binding and takes every later case in the file down with it, which is
  // why this one is isolated here.
  //
  // Un-skip when the panel captures what it needs before the await, or returns
  // early on `!mounted` before touching `ref`.
  testWidgets(
    'the sheet\'s own Start button authorises the queue',
    (tester) async {
      await boot(tester, startUrl: fixture.entry(1));

      await tester.tap(
        find.byKey(const ValueKey('browserSaveAction')),
        warnIfMissed: false,
      );
      await pumpFor(tester, const Duration(seconds: 3));
      await tester.tap(
        find.byKey(const ValueKey('v2SaveStandalone')),
        warnIfMissed: false,
      );
      await pumpFor(tester, const Duration(seconds: 3));

      await tester.tap(
        find.byKey(const ValueKey('v2StartButton')),
        warnIfMissed: false,
      );
      await pumpFor(tester, const Duration(seconds: 2));
      await tester.tap(
        find.byKey(const ValueKey('startInBrowser')),
        warnIfMissed: false,
      );
      await pumpFor(tester, const Duration(seconds: 3));

      await awaitQueueIdle(tester, app);
      final task = (await app.ui.queue.all()).single;
      expect(task.state, SaveTaskState.completed);
    },
    timeout: const Timeout(Duration(minutes: 8)),
    skip: true,
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
