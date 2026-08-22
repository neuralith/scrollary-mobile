// The physical-device matrix, run under a watchdog.
//
//   BUILD_ID=$(git rev-parse --short HEAD) \
//   flutter test integration_test/device_matrix_test.dart -d <udid> \
//     --dart-define=BUILD_ID=$BUILD_ID \
//     --dart-define=LIVE_ENTRY_A=<a real entry url> \
//     --dart-define=LIVE_ENTRY_B=<a real entry url on another source> \
//     --dart-define=SOAK_ROUNDS=6
//
// Every wait here is bounded and announces itself, every scenario is capped,
// and a harness stall is reported as a **harness** verdict rather than as
// evidence about the product — see `integration_test/support/device_harness.dart`,
// which is unchanged by the port because what it enforces is about waiting, not
// about V1.
//
// Real pages are supplied at run time and never compiled in. With no
// `LIVE_ENTRY_*` the live scenarios fall back to the in-process fixture and say
// so; nothing skips silently and nothing invents a pass.
//
// ## Ported, retired and changed
//
// * **The check race** now runs a V2 `SourceCheck` rather than V1's
//   `UpdateChecker`, and asserts the same three things: it finishes, it never
//   asks for the Browser back, and it never moves the user off what they are
//   reading. Against the fixture it needs `fixtureObservations` — see that
//   helper for the seam it stands in for.
// * **Cleanup and idle** is unchanged in substance: after every terminal state
//   the covered page must stop animating, nothing may own the Browser, and a
//   lifecycle round trip must stop and resume the surface.
// * **"A second save does not replace a complete Entry" is retired.** It tested
//   V1's `DuplicatePolicy.skipComplete`, which V2 does not have and deliberately
//   did not port: an Entry has one active OfflineCopy (I13), a re-capture
//   commits through `commitReplacing`, and the user asking for a fresh copy gets
//   one. What replaces it below is the property V2 actually holds — a second
//   request while a row is open is the *same* request, and a completed re-capture
//   leaves exactly one active copy and one Entry.
// * **The bounded multi-Entry run** is a queue that drains from one
//   authorisation, which is V2's shape for the same claim.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:web_reader/capability/entitlement.dart';
import 'package:web_reader/core/runtime_diagnostics.dart';
import 'package:web_reader/domain/collection.dart';
import 'package:web_reader/features/reader_screen.dart';
import 'package:web_reader/features/v2_check_flow.dart';
import 'package:web_reader/providers.dart';
import 'package:web_reader/recognition/check.dart';
import 'package:web_reader/save/queue_task.dart';
import 'package:web_reader/save/save_state.dart';

import 'support/device_harness.dart';
import 'support/v2_harness.dart';

const String kBuildId = String.fromEnvironment(
  'BUILD_ID',
  defaultValue: 'unidentified-build',
);
const String kLiveA = String.fromEnvironment('LIVE_ENTRY_A');
const String kLiveB = String.fromEnvironment('LIVE_ENTRY_B');
const int kSoakRounds = int.fromEnvironment('SOAK_ROUNDS', defaultValue: 4);

/// Per-phase ceilings. Deliberately tight: a real capture of a real page on
/// this hardware takes 30–60 s, so 100 s means "something is wrong", not "be
/// patient". Being wrong about that costs one scenario, not a whole run.
const kOperation = Duration(seconds: 100);
const kSettle = Duration(seconds: 20);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final fixture = FixtureSite();
  final diagnostics = RuntimeDiagnostics();
  final harness = DeviceHarness(fingerprint: kBuildId);
  late V2App app;
  var boots = 0;

  setUpAll(() async {
    await fixture.start();
    debugPrint('[dev] build under test: $kBuildId');
    debugPrint('[dev] live A supplied: ${kLiveA.isNotEmpty}');
    debugPrint('[dev] live B supplied: ${kLiveB.isNotEmpty}');
  });

  tearDownAll(() async {
    await fixture.stop();
    harness.report();
  });

  String liveOr(int n) => kLiveA.isNotEmpty ? kLiveA : fixture.entry(n);

  Future<void> boot(WidgetTester tester, {required bool multitasking}) async {
    app = V2App(
      tag: 'mx_${boots++}_$kRunStamp',
      multitaskingPreference: multitasking,
      entitlement: multitasking
          ? EntitlementOverride.forcePro
          : EntitlementOverride.forceFree,
      observationsOver: fixtureObservations(fixture),
    );
    harness.operationState = () =>
        '${app.runner.isRunning ? 'saving' : (app.check.isRunning ? 'checking' : 'idle')}'
        '/owner=${app.browser.automationOwner ?? '-'}'
        '/painted=${app.browser.surfaceIsPainted}';
    await app.boot(tester);
    await showBrowser(tester);
  }

  /// Return the device to a known state: nothing running, nothing owned.
  Future<void> quiesce(WidgetTester tester) async {
    app.check.cancel();
    for (final task in await app.ui.queue.pending()) {
      await app.ui.queue.cancel(task.id);
    }
    await harness.waitFor(
      tester,
      'releasing the WebView',
      () =>
          !app.runner.isRunning &&
          !app.check.isRunning &&
          app.browser.automationOwner == null,
      limit: kSettle,
    );
    await harness.pumpFor(tester, const Duration(seconds: 1), 'settling');
    await app.shutdown(dumpLog: false);
  }

  bool surfacePainted(WidgetTester tester) => ProviderScope.containerOf(
    tester.element(libraryTab),
  ).read(browserSurfacePaintedProvider).value;

  /// Queue [url] and drain it. Returns whether the queue fell idle inside the
  /// ceiling.
  Future<({bool done, String entryId})> captureOne(
    WidgetTester tester,
    String url, {
    String? collectionId,
  }) async {
    await openPage(tester, app, url);
    await harness.pumpFor(tester, const Duration(seconds: 2), 'page settling');
    final entryId = await app.queueSaveOf(url, collectionId: collectionId);
    await startQueue(tester, app);
    final done = await harness.waitFor(
      tester,
      'capture to finish',
      () => !app.runner.isRunning,
      limit: kOperation,
    );
    return (done: done, entryId: entryId);
  }

  Future<int> reportMemory() async {
    final snapshot = await diagnostics.snapshot();
    return snapshot.memoryFootprintBytes == null
        ? -1
        : (snapshot.memoryFootprintBytes! / 1048576).round();
  }

  /// The last rAF sample [quiescenceOf] took, in ticks per second.
  var lastRaf = -1;

  /// An idle page must not be being driven.
  ///
  /// **The rAF floor is platform-specific, and that is a measurement rather
  /// than a concession.** §3.1 measured an unpainted surface at 0 ticks/s on
  /// iOS and about 13 on Android, where the platform throttles rather than
  /// stops. So the ceiling here is well under a display rate — anything at or
  /// near 60 means the page is still being composited and driven — while the
  /// two assertions that are absolute on both platforms are that nothing owns
  /// the Browser and nothing is live.
  void expectQuiet(String line, String label) {
    expect(
      lastRaf,
      lessThan(20),
      reason: '$label: a covered idle page must not animate (raf/s=$lastRaf)',
    );
    expect(line, contains('owner=-'), reason: '$label: the owner leaked');
    expect(line, contains('live=false'), reason: '$label: work is still going');
  }

  /// Sample what the device is doing right now, and say it in one line.
  Future<String> quiescenceOf(WidgetTester tester, String label) async {
    var raf = -1;
    try {
      await app.browser.debugEvaluate('''
        window.__q = 0;
        const s = () => { window.__q++; requestAnimationFrame(s); };
        requestAnimationFrame(s); return 1;
      ''');
      await harness.pumpFor(
        tester,
        const Duration(seconds: 1),
        'sampling $label',
      );
      final value = await app.browser.debugEvaluate('return window.__q;');
      raf = value is num ? value.round() : -1;
      lastRaf = raf;
    } catch (_) {
      /* no page */
    }
    final snapshot = await diagnostics.snapshot();
    final line =
        '$label raf/s=$raf painted=${app.browser.surfaceIsPainted} '
        'owner=${app.browser.automationOwner ?? '-'} '
        'live=${app.runner.isRunning || app.check.isRunning} '
        'mem=${snapshot.memoryFootprintBytes == null ? '?' : (snapshot.memoryFootprintBytes! / 1048576).round()}MB '
        'thermal=${snapshot.thermalState} '
        'battery=${snapshot.batteryLevel == null ? '?' : (snapshot.batteryLevel! * 100).round()}%/${snapshot.batteryState}';
    harness.note(line);
    return line;
  }

  /// A Collection on the fixture's index page with one preferred Source.
  Future<String> seedCollection() async {
    final root = await app.ui.folders.ensureRoot();
    final (collection, _) = await app.ui.collections.create(
      name: 'Fixture image sequence',
      folderId: root.id,
      orderingBasis: OrderingBasis.explicitNumericIndex,
    );
    final (source, _) = await app.ui.collections.addSource(
      collectionId: collection!.id,
      host: '127.0.0.1',
      pathKey: '/',
    );
    await app.ui.collections.setPreferredSource(collection.id, source!.id);
    return collection.id;
  }

  // ------------------------------------------------------------------ matrix

  testWidgets('device matrix', (tester) async {
    // --- 1. the Collection-check race, repeated -----------------------------
    await harness.scenario(
      'check race x3 · Reader on top',
      limit: const Duration(minutes: 9),
      body: () async {
        await boot(tester, multitasking: true);
        final collectionId = await seedCollection();
        final seed = await captureOne(
          tester,
          fixture.entry(1),
          collectionId: collectionId,
        );
        harness.note('seed capture done=${seed.done}');
        if (!seed.done) {
          harness.skip('the seed capture did not finish');
          return;
        }
        expect(await openedReader(tester, seed.entryId), isTrue);

        for (var i = 1; i <= 3; i++) {
          final started = DateTime.now();
          final outcome = app.check.run(
            collectionId,
            limits: kCollectionCheckLimits,
          );
          final done = await harness.waitFor(
            tester,
            'check $i',
            () => !app.check.isRunning,
            limit: kOperation,
          );
          final result = await outcome;
          final took = DateTime.now().difference(started);
          harness.note(
            'check $i: done=$done state=${result?.state.name} '
            'new=${result?.newEntryIds.length} pages=${result?.pagesRead} '
            'stop=${result?.stopReason?.name} took=${took.inSeconds}s',
          );
          expect(done, isTrue, reason: 'check $i did not finish');
          expect(result, isNotNull, reason: 'check $i never ran');
          expect(
            result!.state,
            isNot(SourceCheckState.stopped),
            reason: 'check $i stopped short: ${result.stopReason?.name}',
          );
          expect(
            find.byType(ReaderScreen),
            findsOneWidget,
            reason: 'check $i moved the user',
          );
          expect(
            surfacePainted(tester),
            isTrue,
            reason: 'check $i read a page the app was not drawing',
          );
          expect(
            app.browser.automationOwner,
            isNull,
            reason: 'check $i leaked the owner',
          );
          await harness.pumpFor(
            tester,
            const Duration(seconds: 2),
            'between checks',
          );
        }
        await popRoute(tester);
      },
      teardown: () => quiesce(tester),
    );

    // --- 2. cleanup and idle ------------------------------------------------
    await harness.scenario(
      'cleanup · terminal and idle states',
      limit: const Duration(minutes: 8),
      body: () async {
        await boot(tester, multitasking: true);
        final url = liveOr(1);
        await quiescenceOf(tester, '1 fresh');
        await openPage(tester, app, url);
        await quiescenceOf(tester, '2 Browser open');
        await showLibrary(tester);
        await quiescenceOf(tester, '3 left Browser');

        await showBrowser(tester);
        final captured = await captureOne(tester, url);
        harness.note('capture done=${captured.done}');
        await quiescenceOf(tester, '4 after capture');
        expect(app.browser.automationOwner, isNull);

        if (captured.done &&
            await app.ui.offline.activeCopyOf(captured.entryId) != null) {
          expect(await openedReader(tester, captured.entryId), isTrue);
          expectQuiet(
            await quiescenceOf(tester, '5 Reader idle'),
            'Reader idle',
          );
          await harness.pumpFor(tester, const Duration(seconds: 45), 'idling');
          expectQuiet(await quiescenceOf(tester, '6 +45s'), 'Reader +45s');
          await popRoute(tester);
        }

        // Cancellation.
        await showBrowser(tester);
        await openPage(tester, app, url);
        final entryId = await app.queueSaveOf(url);
        await startQueue(tester, app);
        await harness.waitFor(
          tester,
          'capture to reach a Browser phase',
          () =>
              app.engineStates.contains(SaveState.scrolling) ||
              !app.runner.isRunning,
          limit: kOperation,
        );
        final open = await app.taskFor(entryId);
        if (open != null) await app.ui.queue.cancel(open.id);
        await harness.waitFor(
          tester,
          'cancel to settle',
          () => !app.runner.isRunning,
          limit: kSettle,
        );
        await showLibrary(tester);
        expectQuiet(
          await quiescenceOf(tester, '7 after cancellation'),
          'after cancellation',
        );

        // Lifecycle round trip. Not in front means drawing nothing.
        await showBrowser(tester);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        await harness.pumpFor(tester, const Duration(seconds: 2), 'inactive');
        expect(
          app.browser.surfaceIsPainted,
          isFalse,
          reason: 'not in front means drawing nothing',
        );
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await harness.pumpFor(tester, const Duration(seconds: 3), 'resumed');
        expect(app.browser.surfaceIsPainted, isTrue);
        expect(app.browser.automationOwner, isNull);
      },
      teardown: () => quiesce(tester),
    );

    // --- 3. one Entry, one copy ---------------------------------------------
    await harness.scenario(
      'a re-capture leaves one Entry and one active copy',
      limit: const Duration(minutes: 8),
      body: () async {
        await boot(tester, multitasking: true);
        final url = liveOr(1);
        final first = await captureOne(tester, url);
        if (!first.done) {
          harness.skip('the first capture did not finish');
          return;
        }
        final before = await app.ui.offline.activeCopyOf(first.entryId);
        if (before == null) {
          harness.skip('no offline copy — precondition unmet');
          return;
        }
        harness.note(
          'before: path=${before.contentPath} bytes=${before.byteSize}',
        );

        // A second request while nothing is open is a new row; a second request
        // while one is open is the same row.
        final again = await app.ui.queue.enqueue(
          entryId: first.entryId,
          locationUrl: url,
        );
        expect(again.refusedReason, isNull);
        final duplicate = await app.ui.queue.enqueue(
          entryId: first.entryId,
          locationUrl: url,
        );
        expect(
          duplicate.alreadyQueued,
          isTrue,
          reason: 'one open task per Entry — an Entry has one active copy',
        );

        await startQueue(tester, app);
        final done = await harness.waitFor(
          tester,
          're-capture to finish',
          () => !app.runner.isRunning,
          limit: kOperation,
        );
        harness.note('re-capture done=$done');

        final copies = await app.ui.offline.allCopies();
        expect(
          copies.where((c) => c.entryId == first.entryId && c.active),
          hasLength(1),
          reason: 'I13: one active OfflineCopy per Entry per device',
        );
        final after = await app.ui.offline.activeCopyOf(first.entryId);
        expect(
          after!.contentPath,
          before.contentPath,
          reason: 'replaced in place, never stacked beside itself',
        );
      },
      teardown: () => quiesce(tester),
    );

    // --- 4. capture while reading, both sources ------------------------------
    for (final (name, url) in [('A', kLiveA), ('B', kLiveB)]) {
      await harness.scenario(
        'source $name · capture while the Reader is open',
        limit: const Duration(minutes: 8),
        body: () async {
          if (url.isEmpty) {
            harness.skip('no LIVE_ENTRY_$name');
            return;
          }
          await boot(tester, multitasking: true);
          final seed = await captureOne(tester, url);
          if (!seed.done ||
              await app.ui.offline.activeCopyOf(seed.entryId) == null) {
            harness.skip('the seed capture did not finish');
            return;
          }
          final manifest = await app.manifestOf(seed.entryId);
          harness.note(
            'watched: ${manifest?.storedAssetCount}/'
            '${manifest?.detectedAssetCount} status=${manifest?.status.name}',
          );

          app.resetObservations();
          await openPage(tester, app, url);
          final second = await app.queueSaveOf(url);
          await startQueue(tester, app);
          await harness.waitFor(
            tester,
            'capture to reach a Browser phase',
            () =>
                app.engineStates.contains(SaveState.scrolling) ||
                !app.runner.isRunning,
            limit: kOperation,
          );
          expect(await openedReader(tester, seed.entryId), isTrue);
          for (var i = 0; i < 8 && app.runner.isRunning; i++) {
            await tester.drag(
              find.byType(ReaderScreen),
              const Offset(0, -280),
              warnIfMissed: false,
            );
            await harness.pumpFor(
              tester,
              const Duration(milliseconds: 500),
              'reading',
            );
          }
          final done = await harness.waitFor(
            tester,
            'covered capture to finish',
            () => !app.runner.isRunning,
            limit: kOperation,
          );
          harness.note(
            'covered: done=$done held=${app.everHeldForBrowser} '
            'mem=${await reportMemory()}MB',
          );
          expect(done, isTrue, reason: 'the covered capture did not finish');
          expect(
            app.everHeldForBrowser,
            isFalse,
            reason: 'it had to ask for the Browser back',
          );
          expect(
            find.byType(ReaderScreen),
            findsOneWidget,
            reason: 'the user was pulled off what they were reading',
          );
          expect(
            (await app.latestTaskFor(second))!.state,
            SaveTaskState.completed,
          );
          await popRoute(tester);
        },
        teardown: () => quiesce(tester),
      );
    }

    // --- 5. a queue that drains from the Library tab -------------------------
    await harness.scenario(
      'bounded queue · Library on top',
      limit: const Duration(minutes: 9),
      body: () async {
        await boot(tester, multitasking: true);
        await openPage(tester, app, fixture.entry(1));
        final ids = <String>[
          for (final n in [1, 2, 3])
            await app.queueSaveOf(fixture.entry(n), title: 'Entry $n'),
        ];
        await startQueue(tester, app);
        await harness.waitFor(
          tester,
          'queue to reach a Browser phase',
          () =>
              app.engineStates.contains(SaveState.scrolling) ||
              !app.runner.isRunning,
          limit: kOperation,
        );
        expect(
          await showLibrary(tester),
          isFalse,
          reason: 'a multitasking task is not stranded by a tab switch',
        );
        final done = await harness.waitFor(
          tester,
          'queue to drain',
          () => !app.runner.isRunning,
          limit: const Duration(minutes: 5),
        );
        harness.note(
          'queue: done=$done held=${app.everHeldForBrowser} '
          'mem=${await reportMemory()}MB',
        );
        expect(done, isTrue);
        expect(app.everHeldForBrowser, isFalse);
        expect(app.browser.automationOwner, isNull);
        for (final id in ids) {
          expect((await app.latestTaskFor(id))!.state, SaveTaskState.completed);
        }
      },
      teardown: () => quiesce(tester),
    );

    // --- 6. soak -------------------------------------------------------------
    await harness.scenario(
      'soak · $kSoakRounds rounds',
      limit: Duration(minutes: 6 + kSoakRounds * 3),
      body: () async {
        await boot(tester, multitasking: true);
        final url = liveOr(1);
        final seed = await captureOne(tester, url);
        if (!seed.done ||
            await app.ui.offline.activeCopyOf(seed.entryId) == null) {
          harness.skip('the soak seed did not finish');
          return;
        }

        final memory = <int>[];
        var completions = 0;
        var holds = 0;
        final started = DateTime.now();
        for (var round = 1; round <= kSoakRounds; round++) {
          harness.note('soak round $round starting');
          app.resetObservations();
          await showBrowser(tester);
          await openPage(tester, app, url);
          final entryId = await app.queueSaveOf(url, title: 'round $round');
          await startQueue(tester, app);
          await harness.waitFor(
            tester,
            'round $round to reach a Browser phase',
            () =>
                app.engineStates.contains(SaveState.scrolling) ||
                !app.runner.isRunning,
            limit: kOperation,
          );
          await openedReader(tester, seed.entryId);
          final done = await harness.waitFor(
            tester,
            'round $round to finish',
            () => !app.runner.isRunning,
            limit: kOperation,
          );
          if (done) completions++;
          if (app.everHeldForBrowser) holds++;
          final mem = await reportMemory();
          memory.add(mem);
          final task = await app.latestTaskFor(entryId);
          harness.note(
            'soak round $round: done=$done state=${task?.state.name} '
            'owner=${app.browser.automationOwner ?? '-'} mem=${mem}MB',
          );
          expect(
            app.browser.automationOwner,
            isNull,
            reason: 'round $round leaked the owner',
          );
          await popRoute(tester);
        }
        final elapsed = DateTime.now().difference(started);
        harness.note(
          'SOAK: $completions/$kSoakRounds completed, $holds holds, '
          '${elapsed.inMinutes}m${elapsed.inSeconds % 60}s, '
          'memory ${memory.join('→')}MB',
        );
        expect(completions, kSoakRounds, reason: 'not every round completed');
        expect(holds, 0, reason: 'a round had to ask for the Browser');
        if (memory.length >= 2 && memory.first > 0) {
          final growth = (memory.last - memory.first) / memory.first;
          harness.note(
            'soak memory growth ${(growth * 100).toStringAsFixed(1)}%',
          );
          expect(growth, lessThan(0.25), reason: 'memory trended up');
        }
      },
      teardown: () => quiesce(tester),
    );
  }, timeout: const Timeout(Duration(minutes: 75)));
}

/// Push the reader and report whether it is what ended up on top.
Future<bool> openedReader(WidgetTester tester, String entryId) async {
  await openReader(tester, entryId);
  return find.byType(ReaderScreen).evaluate().isNotEmpty;
}
