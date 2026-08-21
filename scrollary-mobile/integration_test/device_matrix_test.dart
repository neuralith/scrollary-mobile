// The physical-device matrix, run under a watchdog.
//
//   BUILD_ID=$(git rev-parse --short HEAD)+$(…tree hash…) \
//   flutter test integration_test/device_matrix_test.dart -d <udid> \
//     --dart-define=BUILD_ID=$BUILD_ID \
//     --dart-define=LIVE_ENTRY_A=<a real entry url> \
//     --dart-define=LIVE_ENTRY_B=<a real entry url on another source> \
//     --dart-define=SOAK_ROUNDS=6
//
// Replaces `device_validation_test.dart`, which was correct about *what* to
// measure and wrong about *how to wait*: three device runs were lost to it
// sitting inside a generous timeout after a scenario had already failed,
// producing nothing for a quarter of an hour. Every wait here is bounded and
// announces itself, every scenario is capped, and a harness stall is reported
// as a harness verdict rather than as evidence about the product — see
// `integration_test/support/device_harness.dart`.
//
// Real pages are supplied at run time and never compiled in. With no
// `LIVE_ENTRY_*` the live scenarios skip themselves and say so.
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';
import 'package:web_reader/app.dart';
import 'package:web_reader/browser/browser_controller.dart';
import 'package:web_reader/capability/foreground_multitasking.dart';
import 'package:web_reader/core/config.dart';
import 'package:web_reader/core/runtime_diagnostics.dart';
import 'package:web_reader/features/reader_screen.dart';
import 'package:web_reader/library/update_checker.dart';
import 'package:web_reader/providers.dart';
import 'package:web_reader/save/save_run.dart';
import 'package:web_reader/save/save_state.dart';
import 'package:web_reader/storage/database.dart';
import 'package:web_reader/storage/file_store.dart';
import 'package:web_reader/storage/manifest.dart';

import '../tool/fixture/fixture_site.dart';
import 'support/device_harness.dart';

const String kBuildId = String.fromEnvironment(
  'BUILD_ID',
  defaultValue: 'unidentified-build',
);
const String kLiveA = String.fromEnvironment('LIVE_ENTRY_A');
const String kLiveB = String.fromEnvironment('LIVE_ENTRY_B');
const int kSoakRounds = int.fromEnvironment('SOAK_ROUNDS', defaultValue: 4);

/// Per-phase ceilings. Deliberately tight: a real save of a real page on this
/// hardware takes 30–60 s, so 100 s means "something is wrong", not "be
/// patient". Being wrong about that costs one scenario, not a whole run.
const kLoad = Duration(seconds: 30);
const kOperation = Duration(seconds: 100);
const kSettle = Duration(seconds: 20);

late String kFixtureBase;
final String kStamp = DateTime.now().millisecondsSinceEpoch.toRadixString(36);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late FileStore fileStore;
  late BrowserController browser;
  late SaveRunController run;
  late UpdateChecker checker;
  late HttpServer server;
  final diagnostics = RuntimeDiagnostics();
  final harness = DeviceHarness(fingerprint: kBuildId);
  var boots = 0;

  setUpAll(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    kFixtureBase = 'http://127.0.0.1:${server.port}';
    unawaited(() async {
      try {
        await for (final req in server) {
          try {
            await handleFixtureRequest(req);
          } catch (_) {
            /* client went away */
          }
        }
      } catch (_) {
        /* server closed */
      }
    }());
    debugPrint('[dev] build under test: $kBuildId');
    debugPrint('[dev] live A supplied: ${kLiveA.isNotEmpty}');
    debugPrint('[dev] live B supplied: ${kLiveB.isNotEmpty}');
  });

  tearDownAll(() {
    server.close(force: true);
    harness.report();
  });

  String liveOr(int n) => kLiveA.isNotEmpty ? kLiveA : '$kFixtureBase/entry/$n';

  Future<void> boot(WidgetTester tester, {required bool enabled}) async {
    final tag = 'it_mx_${boots++}_$kStamp';
    db = AppDatabase(name: tag);
    fileStore = await FileStore.open(folderName: 'webread_$tag');
    browser = BrowserController();
    run = SaveRunController(browser: browser, db: db, fileStore: fileStore);
    final services = AppServices(
      db: db,
      fileStore: fileStore,
      browser: browser,
      saveRun: run,
      foregroundMultitasking: ForegroundMultitasking(enabled),
    );
    checker = services.updateChecker;
    harness.operationState = () =>
        '${run.isRunning ? run.progress.state.name : (checker.isRunning ? 'checking' : 'idle')}'
        '/owner=${browser.automationOwner ?? '-'}'
        '/painted=${browser.surfaceIsPainted}';
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appServicesProvider.overrideWithValue(services)],
        child: const WebReaderApp(),
      ),
    );
    await tester.pumpAndSettle(const Duration(seconds: 2));
  }

  /// Return the device to a known state: nothing running, nothing owned.
  Future<void> quiesce(WidgetTester tester) async {
    run.stop();
    checker.cancel();
    await harness.waitFor(
      tester,
      'releasing the WebView',
      () =>
          !run.isRunning &&
          !checker.isRunning &&
          browser.automationOwner == null,
      limit: kSettle,
    );
    await harness.pumpFor(tester, const Duration(seconds: 1), 'settling');
    try {
      await db.close();
    } catch (_) {
      /* already closed */
    }
  }

  Future<void> showBrowser(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('navTab-Browser')));
    await harness.pumpFor(
      tester,
      const Duration(milliseconds: 700),
      'to Browser',
    );
  }

  Future<void> showLibrary(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('navTab-Library')));
    await harness.pumpFor(
      tester,
      const Duration(milliseconds: 700),
      'to Library',
    );
    // The leave sheet, whatever shape it takes for this build's entitlement:
    // *Pause and leave* is the one answer that is always offered, to everyone.
    final leave = find.byKey(const ValueKey('leavePauseAndLeave'));
    if (leave.evaluate().isNotEmpty) {
      harness.note('leave-Browser sheet shown — held the task and left');
      await tester.tap(leave);
      await harness.pumpFor(
        tester,
        const Duration(milliseconds: 700),
        'confirming',
      );
    }
  }

  Future<bool> openReader(WidgetTester tester, String entryId) async {
    final ctx = tester.element(find.byKey(const ValueKey('navTab-Library')));
    GoRouter.of(ctx).push('/reader/$entryId');
    await harness.pumpFor(tester, const Duration(seconds: 2), 'opening Reader');
    return find.byType(ReaderScreen).evaluate().isNotEmpty;
  }

  Future<void> closeReader(WidgetTester tester) async {
    if (find.byType(ReaderScreen).evaluate().isEmpty) return;
    GoRouter.of(tester.element(find.byType(ReaderScreen))).pop();
    await harness.pumpFor(tester, const Duration(seconds: 2), 'closing Reader');
  }

  /// Load [url] and start a one-page save. Returns whether it reached a
  /// terminal state inside the ceiling.
  Future<bool> saveOne(WidgetTester tester, String url) async {
    await browser.loadAndWait(url, timeout: kLoad);
    await harness.pumpFor(tester, const Duration(seconds: 3), 'page settling');
    unawaited(
      run.start(range: SaveScope.currentPageOnly, entryLimit: 1, startUrl: url),
    );
    return harness.waitFor(
      tester,
      'save to finish',
      () => run.progress.state.isTerminal && !run.isRunning,
      limit: kOperation,
    );
  }

  Future<int> reportMemory() async {
    final snap = await diagnostics.snapshot();
    return snap.memoryFootprintBytes == null
        ? -1
        : (snap.memoryFootprintBytes! / 1048576).round();
  }

  Future<String> quiescenceOf(WidgetTester tester, String label) async {
    var raf = -1;
    try {
      await browser.debugEvaluate('''
        window.__q = 0;
        const s = () => { window.__q++; requestAnimationFrame(s); };
        requestAnimationFrame(s); return 1;
      ''');
      await harness.pumpFor(
        tester,
        const Duration(seconds: 1),
        'sampling $label',
      );
      final v = await browser.debugEvaluate('return window.__q;');
      raf = v is num ? v.round() : -1;
    } catch (_) {
      /* no page */
    }
    final snap = await diagnostics.snapshot();
    final line =
        '$label raf/s=$raf painted=${browser.surfaceIsPainted} '
        'owner=${browser.automationOwner ?? '-'} '
        'live=${run.isRunning || checker.isRunning} '
        'mem=${snap.memoryFootprintBytes == null ? '?' : (snap.memoryFootprintBytes! / 1048576).round()}MB '
        'thermal=${snap.thermalState} '
        'battery=${snap.batteryLevel == null ? '?' : (snap.batteryLevel! * 100).round()}%/${snap.batteryState}';
    harness.note(line);
    return line;
  }

  // ------------------------------------------------------------------ matrix

  testWidgets('device matrix', (tester) async {
    // --- 1. the Collection-check race, repeated -----------------------------
    await harness.scenario(
      'check race x3 · Reader on top · real site',
      limit: const Duration(minutes: 9),
      body: () async {
        if (kLiveA.isEmpty) {
          harness.skip('skipped — no LIVE_ENTRY_A');
          return;
        }
        await boot(tester, enabled: true);
        await showBrowser(tester);
        final saved = await saveOne(tester, kLiveA);
        harness.note(
          'seed save terminal=$saved state=${run.progress.state.name}',
        );
        final readable = (await db.allEntries())
            .where((e) => e.contentPath != null)
            .toList();
        final collectionId = (await db.allEntries())
            .map((e) => e.collectionId)
            .whereType<String>()
            .firstOrNull;
        if (readable.isEmpty || collectionId == null) {
          harness.skip('no Collection to check — precondition unmet');
          return;
        }
        expect(await openReader(tester, readable.first.id), isTrue);

        for (var i = 1; i <= 3; i++) {
          final started = DateTime.now();
          final outcome = checker.check(collectionId);
          final done = await harness.waitFor(
            tester,
            'check $i',
            () => !checker.isRunning,
            limit: kOperation,
          );
          final result = await outcome;
          final took = DateTime.now().difference(started);
          final log = checker.log.join('\n');
          harness.note(
            'check $i: done=$done state=${result.state.name} '
            'new=${result.newEntries} pages=${result.pagesInspected} '
            'took=${took.inSeconds}s '
            'askedForBrowser=${log.contains('open the Browser')} '
            'settled=${log.contains('settling')}',
          );
          expect(done, isTrue, reason: 'check $i did not finish');
          expect(
            log.contains('open the Browser'),
            isFalse,
            reason:
                'check $i asked for the Browser back — the race is not fixed',
          );
          expect(
            result.state,
            isNot(UpdateCheckState.failed),
            reason: 'check $i failed: ${result.error}',
          );
          expect(
            find.byType(ReaderScreen),
            findsOneWidget,
            reason: 'check $i moved the user',
          );
          expect(
            browser.automationOwner,
            isNull,
            reason: 'check $i leaked the owner',
          );
          await harness.pumpFor(
            tester,
            const Duration(seconds: 2),
            'between checks',
          );
        }
        await closeReader(tester);
      },
      teardown: () => quiesce(tester),
    );

    // --- 2. cleanup and idle -------------------------------------------------
    await harness.scenario(
      'cleanup · terminal and idle states',
      limit: const Duration(minutes: 8),
      body: () async {
        await boot(tester, enabled: true);
        final url = liveOr(1);
        await quiescenceOf(tester, '1 fresh');
        await showBrowser(tester);
        await browser.loadAndWait(url, timeout: kLoad);
        await harness.pumpFor(
          tester,
          const Duration(seconds: 3),
          'page settling',
        );
        await quiescenceOf(tester, '2 Browser open');
        await showLibrary(tester);
        await quiescenceOf(tester, '3 left Browser');

        await showBrowser(tester);
        final ok = await saveOne(tester, url);
        harness.note('save terminal=$ok state=${run.progress.state.name}');
        await quiescenceOf(tester, '4 after save');
        expect(browser.automationOwner, isNull);

        final readable = (await db.allEntries())
            .where((e) => e.contentPath != null)
            .toList();
        if (readable.isNotEmpty) {
          expect(await openReader(tester, readable.first.id), isTrue);
          final r = await quiescenceOf(tester, '5 Reader idle');
          expect(
            r,
            contains('raf/s=0'),
            reason: 'a covered idle page must not animate',
          );
          await harness.pumpFor(tester, const Duration(seconds: 45), 'idling');
          final later = await quiescenceOf(tester, '6 +45s');
          expect(later, contains('raf/s=0'));
          expect(later, contains('owner=-'));
          await closeReader(tester);
        }

        // Cancellation.
        await showBrowser(tester);
        await browser.loadAndWait(url, timeout: kLoad);
        await harness.pumpFor(
          tester,
          const Duration(seconds: 3),
          'page settling',
        );
        unawaited(
          run.start(
            range: SaveScope.currentPageOnly,
            entryLimit: 1,
            startUrl: url,
          ),
        );
        await harness.waitFor(
          tester,
          'save to reach a Browser phase',
          () => run.progress.state == SaveState.scrolling || !run.isRunning,
          limit: kOperation,
        );
        run.stop();
        await harness.waitFor(
          tester,
          'cancel to settle',
          () => !run.isRunning,
          limit: kSettle,
        );
        await showLibrary(tester);
        final cancelled = await quiescenceOf(tester, '7 after cancellation');
        expect(cancelled, contains('raf/s=0'));
        expect(cancelled, contains('owner=-'));

        // Lifecycle round trip.
        await showBrowser(tester);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        await harness.pumpFor(tester, const Duration(seconds: 2), 'inactive');
        expect(
          browser.surfaceIsPainted,
          isFalse,
          reason: 'not in front means drawing nothing',
        );
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await harness.pumpFor(tester, const Duration(seconds: 3), 'resumed');
        expect(browser.surfaceIsPainted, isTrue);
        expect(browser.automationOwner, isNull);
      },
      teardown: () => quiesce(tester),
    );

    // --- 3. overwrite protection --------------------------------------------
    await harness.scenario(
      'a second save does not replace a complete Entry',
      limit: const Duration(minutes: 7),
      body: () async {
        await boot(tester, enabled: true);
        final url = liveOr(1);
        await showBrowser(tester);
        if (!await saveOne(tester, url)) {
          harness.skip('first save did not finish — precondition unmet');
          return;
        }
        final target = (await db.allEntries())
            .where((e) => e.contentPath != null)
            .firstOrNull;
        if (target == null) {
          harness.skip('no offline Entry — precondition unmet');
          return;
        }
        final before = await fileStore.readManifest(target.contentPath!);
        harness.note(
          'before: status=${before?.status.name} '
          'stored=${before?.storedAssetCount} savedAt=${before?.savedAt}',
        );
        if (before?.status != SaveStatus.complete) {
          harness.skip('first save was not complete — nothing to protect');
          return;
        }
        final countBefore = (await db.allEntries())
            .where((e) => e.contentPath != null)
            .length;

        await showBrowser(tester);
        await saveOne(tester, url);
        final after = await fileStore.readManifest(target.contentPath!);
        harness.note(
          'after: status=${after?.status.name} '
          'stored=${after?.storedAssetCount} savedAt=${after?.savedAt}',
        );
        expect(after, isNotNull, reason: 'the Entry must still be there');
        expect(
          after!.savedAt,
          before!.savedAt,
          reason: 'a complete Entry must not be rewritten',
        );
        expect(after.storedAssetCount, before.storedAssetCount);
        expect(
          (await db.allEntries()).where((e) => e.contentPath != null).length,
          countBefore,
          reason: 'no duplicate Entry beside it',
        );
      },
      teardown: () => quiesce(tester),
    );

    // --- 4. save while reading, both sources --------------------------------
    for (final (name, url) in [('A', kLiveA), ('B', kLiveB)]) {
      await harness.scenario(
        'source $name · save while the Reader is open',
        limit: const Duration(minutes: 8),
        body: () async {
          if (url.isEmpty) {
            harness.skip('skipped — no LIVE_ENTRY_$name');
            return;
          }
          await boot(tester, enabled: true);
          await showBrowser(tester);
          if (!await saveOne(tester, url)) {
            harness.skip('seed save did not finish');
            return;
          }
          final seed = (await db.allEntries())
              .where((e) => e.contentPath != null)
              .firstOrNull;
          final m = seed == null
              ? null
              : await fileStore.readManifest(seed.contentPath!);
          harness.note(
            'watched: ${m?.storedAssetCount}/${m?.detectedAssetCount} '
            'status=${m?.status.name}',
          );
          if (seed == null) return;

          final states = <SaveState>{};
          void collect() => states.add(run.progress.state);
          run.addListener(collect);

          await showBrowser(tester);
          await browser.loadAndWait(url, timeout: kLoad);
          await harness.pumpFor(
            tester,
            const Duration(seconds: 3),
            'page settling',
          );
          unawaited(
            run.start(
              range: SaveScope.currentPageOnly,
              entryLimit: 1,
              startUrl: url,
            ),
          );
          await harness.waitFor(
            tester,
            'save to reach a Browser phase',
            () => run.progress.state == SaveState.scrolling || !run.isRunning,
            limit: kOperation,
          );
          expect(await openReader(tester, seed.id), isTrue);
          for (var i = 0; i < 8 && run.isRunning; i++) {
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
            'covered save to finish',
            () => run.progress.state.isTerminal && !run.isRunning,
            limit: kOperation,
          );
          run.removeListener(collect);
          harness.note(
            'covered: done=$done state=${run.progress.state.name} '
            'held=${states.contains(SaveState.waitingForBrowser)} '
            'mem=${await reportMemory()}MB',
          );
          expect(done, isTrue, reason: 'the covered save did not finish');
          expect(
            states,
            isNot(contains(SaveState.waitingForBrowser)),
            reason: 'it had to ask for the Browser back',
          );
          expect(
            find.byType(ReaderScreen),
            findsOneWidget,
            reason: 'the user was pulled off what they were reading',
          );
          await closeReader(tester);
        },
        teardown: () => quiesce(tester),
      );
    }

    // --- 5. multi-Entry from the Library tab --------------------------------
    await harness.scenario(
      'bounded multi-Entry run · Library on top',
      limit: const Duration(minutes: 9),
      body: () async {
        await boot(tester, enabled: true);
        final states = <SaveState>{};
        void collect() => states.add(run.progress.state);
        run.addListener(collect);
        await showBrowser(tester);
        final url = liveOr(1);
        await browser.loadAndWait(url, timeout: kLoad);
        await harness.pumpFor(
          tester,
          const Duration(seconds: 3),
          'page settling',
        );
        unawaited(
          run.start(range: SaveScope.fixedCount, entryLimit: 2, startUrl: url),
        );
        await harness.waitFor(
          tester,
          'run to reach a Browser phase',
          () => run.progress.state == SaveState.scrolling || !run.isRunning,
          limit: kOperation,
        );
        await showLibrary(tester);
        final done = await harness.waitFor(
          tester,
          'multi-Entry run to finish',
          () => run.progress.state.isTerminal && !run.isRunning,
          limit: const Duration(minutes: 4),
        );
        run.removeListener(collect);
        harness.note(
          'multi: done=$done stored=${run.progress.storedEntries} '
          'held=${states.contains(SaveState.waitingForBrowser)} '
          'walked=${states.contains(SaveState.navigating)} '
          'mem=${await reportMemory()}MB',
        );
        expect(done, isTrue);
        expect(states, isNot(contains(SaveState.waitingForBrowser)));
        expect(browser.automationOwner, isNull);
      },
      teardown: () => quiesce(tester),
    );

    // --- 6. soak -------------------------------------------------------------
    await harness.scenario(
      'soak · $kSoakRounds rounds',
      limit: Duration(minutes: 6 + kSoakRounds * 3),
      body: () async {
        await boot(tester, enabled: true);
        final url = liveOr(1);
        await showBrowser(tester);
        if (!await saveOne(tester, url)) {
          harness.skip('soak seed did not finish');
          return;
        }
        final seed = (await db.allEntries())
            .where((e) => e.contentPath != null)
            .firstOrNull;
        if (seed == null) return;

        final memory = <int>[];
        var completions = 0;
        var holds = 0;
        final started = DateTime.now();
        for (var round = 1; round <= kSoakRounds; round++) {
          harness.note('soak round $round starting');
          final states = <SaveState>{};
          void collect() => states.add(run.progress.state);
          run.addListener(collect);
          await showBrowser(tester);
          await browser.loadAndWait(url, timeout: kLoad);
          await harness.pumpFor(
            tester,
            const Duration(seconds: 2),
            'page settling',
          );
          unawaited(
            run.start(
              range: SaveScope.currentPageOnly,
              entryLimit: 1,
              startUrl: url,
            ),
          );
          await harness.waitFor(
            tester,
            'round $round to reach a Browser phase',
            () => run.progress.state == SaveState.scrolling || !run.isRunning,
            limit: kOperation,
          );
          await openReader(tester, seed.id);
          final done = await harness.waitFor(
            tester,
            'round $round to finish',
            () => run.progress.state.isTerminal && !run.isRunning,
            limit: kOperation,
          );
          run.removeListener(collect);
          if (done) completions++;
          if (states.contains(SaveState.waitingForBrowser)) holds++;
          final mem = await reportMemory();
          memory.add(mem);
          harness.note(
            'soak round $round: done=$done state=${run.progress.state.name} '
            'owner=${browser.automationOwner ?? '-'} mem=${mem}MB',
          );
          expect(
            browser.automationOwner,
            isNull,
            reason: 'round $round leaked the owner',
          );
          await closeReader(tester);
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
