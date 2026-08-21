// The product claim, end to end: a save and a check the user started keep
// running while the user reads an Entry they already have.
//
//   flutter test integration_test/foreground_multitasking_test.dart -d <device>
//
// Nothing is mocked. A real WebView loads the in-process fixture, the real
// engine scrolls it, the fixture's IntersectionObserver-driven panels load,
// bytes are downloaded and a manifest is written — all while the Reader route
// is on screen above the shell.
//
// The control arm matters as much as the claim: with the capability off, the
// same run must *hold* rather than read a page the app is no longer drawing.
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
import 'package:web_reader/features/reader_screen.dart';
import 'package:web_reader/library/update_checker.dart';
import 'package:web_reader/providers.dart';
import 'package:web_reader/save/save_run.dart';
import 'package:web_reader/save/save_state.dart';
import 'package:web_reader/storage/database.dart';
import 'package:web_reader/storage/file_store.dart';

import '../tool/fixture/fixture_site.dart';

late String kFixtureBase;
const int kFixtureImagesPerEntry = 6;

final String kRunStamp = DateTime.now().millisecondsSinceEpoch.toRadixString(
  36,
);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late FileStore fileStore;
  late BrowserController browser;
  late SaveRunController run;
  late UpdateChecker checker;
  late ForegroundMultitasking capability;
  late HttpServer server;
  var caseIndex = 0;

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
  });

  tearDownAll(() => server.close(force: true));

  Future<void> bootApp(WidgetTester tester, {required bool enabled}) async {
    final tag = 'it_fg_${caseIndex++}_$kRunStamp';
    db = AppDatabase(name: tag);
    fileStore = await FileStore.open(folderName: 'webread_$tag');
    browser = BrowserController();
    run = SaveRunController(browser: browser, db: db, fileStore: fileStore);
    capability = ForegroundMultitasking(enabled);
    final services = AppServices(
      db: db,
      fileStore: fileStore,
      browser: browser,
      saveRun: run,
      foregroundMultitasking: capability,
    );
    checker = services.updateChecker;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appServicesProvider.overrideWithValue(services)],
        child: const WebReaderApp(),
      ),
    );
    await tester.pumpAndSettle(const Duration(seconds: 2));
  }

  /// Pump on a clock: `pumpAndSettle` would hang on the WebView's continuous
  /// animation.
  Future<void> pumpUntil(
    WidgetTester tester,
    bool Function() done, {
    Duration timeout = const Duration(minutes: 4),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (!done() && DateTime.now().isBefore(deadline)) {
      await tester.pump(const Duration(milliseconds: 200));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  }

  Future<void> pumpFor(WidgetTester tester, Duration duration) async {
    final deadline = DateTime.now().add(duration);
    while (DateTime.now().isBefore(deadline)) {
      await tester.pump(const Duration(milliseconds: 50));
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
  }

  /// Show the Browser, load [url], and save exactly that page.
  Future<void> saveOnePage(WidgetTester tester, String url) async {
    await tester.tap(find.byKey(const ValueKey('navTab-Browser')));
    await pumpFor(tester, const Duration(milliseconds: 600));
    await browser.loadAndWait(url);
    await pumpFor(tester, const Duration(seconds: 2));
    unawaited(
      run.start(range: SaveScope.currentPageOnly, entryLimit: 1, startUrl: url),
    );
  }

  /// Open the Reader on an Entry that is already downloaded — the screen the
  /// whole feature exists for.
  Future<void> openReader(WidgetTester tester, String entryId) async {
    // The bottom bar, because it is the one thing that is never offstage —
    // the shell's tabs are, by design, and a finder skips those.
    final context = tester.element(
      find.byKey(const ValueKey('navTab-Library')),
    );
    GoRouter.of(context).push('/reader/$entryId');
    await pumpFor(tester, const Duration(seconds: 2));
    expect(
      find.byType(ReaderScreen),
      findsOneWidget,
      reason: 'the Reader must be the screen on top',
    );
  }

  Future<int> storedImagesFor(String url) async {
    for (final entry in await db.allEntries()) {
      if (entry.sourceUrl != url) continue;
      final path = entry.contentPath;
      if (path == null) return 0;
      final manifest = await fileStore.readManifest(path);
      return manifest?.storedAssetCount ?? 0;
    }
    return -1;
  }

  tearDown(() async {
    // Stop anything still driving the WebView before the database goes, or
    // the pump writes into a closed connection and the noise buries the
    // assertion that actually failed.
    run.stop();
    checker.cancel();
    await Future<void>.delayed(const Duration(seconds: 1));
    for (final line in run.log.reversed) {
      debugPrint('[fg:save] $line');
    }
    for (final line in checker.log.reversed) {
      debugPrint('[fg:check] $line');
    }
    await db.close();
  });

  testWidgets(
    'a save runs to completion while the Reader is open',
    (tester) async {
      await bootApp(tester, enabled: true);

      // One Entry saved the ordinary way, so there is something to read.
      await saveOnePage(tester, '$kFixtureBase/entry/1');
      await pumpUntil(
        tester,
        () => run.progress.state.isTerminal && !run.isRunning,
      );
      expect(run.progress.state, SaveState.complete);
      final first = (await db.allEntries()).firstWhere(
        (e) => e.sourceUrl == '$kFixtureBase/entry/1',
      );

      // Now start a second save and leave for the Reader immediately.
      final states = <SaveState>{};
      void collect() => states.add(run.progress.state);
      run.addListener(collect);
      addTearDown(() => run.removeListener(collect));

      await saveOnePage(tester, '$kFixtureBase/entry/3');
      await pumpUntil(
        tester,
        () => run.progress.state == SaveState.scrolling || !run.isRunning,
        timeout: const Duration(seconds: 40),
      );
      await openReader(tester, first.id);

      await pumpUntil(
        tester,
        () => run.progress.state.isTerminal && !run.isRunning,
      );

      expect(
        find.byType(ReaderScreen),
        findsOneWidget,
        reason: 'the user was never pulled off the Entry they were reading',
      );
      expect(
        states,
        isNot(contains(SaveState.waitingForBrowser)),
        reason: 'the run never had to ask for the Browser back',
      );
      expect(run.progress.state, SaveState.complete);
      expect(
        await storedImagesFor('$kFixtureBase/entry/3'),
        kFixtureImagesPerEntry,
        reason: 'the same bytes a watched run would have stored',
      );
    },
    timeout: const Timeout(Duration(minutes: 8)),
  );

  testWidgets(
    'with the capability off, the same save holds instead',
    (tester) async {
      await bootApp(tester, enabled: false);

      await saveOnePage(tester, '$kFixtureBase/entry/1');
      await pumpUntil(
        tester,
        () => run.progress.state.isTerminal && !run.isRunning,
      );
      final first = (await db.allEntries()).firstWhere(
        (e) => e.sourceUrl == '$kFixtureBase/entry/1',
      );

      final states = <SaveState>{};
      void collect() => states.add(run.progress.state);
      run.addListener(collect);
      addTearDown(() => run.removeListener(collect));

      await saveOnePage(tester, '$kFixtureBase/entry/3');
      await pumpUntil(
        tester,
        () => run.progress.state == SaveState.scrolling || !run.isRunning,
        timeout: const Duration(seconds: 40),
      );
      await openReader(tester, first.id);

      // It must hold, not push on. Give it long enough that a run which was
      // going to carry on would have finished.
      await pumpFor(tester, const Duration(seconds: 25));

      expect(
        states,
        contains(SaveState.waitingForBrowser),
        reason: 'a run must not read a page the app has stopped drawing',
      );
      expect(run.progress.state.isTerminal, isFalse);

      // And coming back releases it, with nothing lost.
      final context = tester.element(find.byType(ReaderScreen));
      GoRouter.of(context).pop();
      await pumpFor(tester, const Duration(seconds: 2));
      await pumpUntil(
        tester,
        () => run.progress.state.isTerminal && !run.isRunning,
      );
      expect(run.progress.state, SaveState.complete);
      expect(
        await storedImagesFor('$kFixtureBase/entry/3'),
        kFixtureImagesPerEntry,
      );
    },
    timeout: const Timeout(Duration(minutes: 8)),
  );

  testWidgets(
    'a bounded multi-Entry run continues from the Library tab',
    (tester) async {
      await bootApp(tester, enabled: true);

      final states = <SaveState>{};
      void collect() => states.add(run.progress.state);
      run.addListener(collect);
      addTearDown(() => run.removeListener(collect));

      await tester.tap(find.byKey(const ValueKey('navTab-Browser')));
      await pumpFor(tester, const Duration(milliseconds: 600));
      await browser.loadAndWait('$kFixtureBase/entry/1');
      await pumpFor(tester, const Duration(seconds: 2));
      unawaited(
        run.start(
          range: SaveScope.fixedCount,
          entryLimit: 3,
          startUrl: '$kFixtureBase/entry/1',
        ),
      );
      await pumpUntil(
        tester,
        () => run.progress.state == SaveState.scrolling || !run.isRunning,
        timeout: const Duration(seconds: 40),
      );

      // The other half of the mechanism: not a pushed route, but the shell's
      // own tab. The Browser child has to stay drawn underneath the Library.
      await tester.tap(find.byKey(const ValueKey('navTab-Library')));
      await pumpFor(tester, const Duration(seconds: 1));

      await pumpUntil(
        tester,
        () => run.progress.state.isTerminal && !run.isRunning,
      );

      expect(
        states,
        isNot(contains(SaveState.waitingForBrowser)),
        reason: 'the Library tab must not strand the run',
      );
      expect(
        states,
        containsAll(<SaveState>[SaveState.detectingNext, SaveState.navigating]),
        reason: 'it really walked forward, it did not just finish one page',
      );
      expect(run.progress.storedEntries, 3);
      expect(
        await storedImagesFor('$kFixtureBase/entry/3'),
        kFixtureImagesPerEntry,
      );
    },
    timeout: const Timeout(Duration(minutes: 10)),
  );

  testWidgets(
    'a Collection check runs while the Reader is open',
    (tester) async {
      await bootApp(tester, enabled: true);

      // Two Entries, so the collection has a chain to walk from.
      for (final n in [1, 2]) {
        await saveOnePage(tester, '$kFixtureBase/entry/$n');
        await pumpUntil(
          tester,
          () => run.progress.state.isTerminal && !run.isRunning,
        );
      }
      final entries = await db.allEntries();
      final collectionId = entries
          .map((e) => e.collectionId)
          .whereType<String>()
          .first;
      final first = entries.firstWhere(
        (e) => e.sourceUrl == '$kFixtureBase/entry/1',
      );

      await openReader(tester, first.id);

      final outcome = checker.check(collectionId);
      await pumpFor(tester, const Duration(seconds: 3));
      debugPrint(
        '[fg] check started: painted=${browser.surfaceIsPainted} '
        'running=${checker.isRunning} capability=${capability.enabled}',
      );
      await pumpUntil(tester, () => !checker.isRunning, timeout: kCheckTimeout);
      final result = await outcome;

      expect(
        find.byType(ReaderScreen),
        findsOneWidget,
        reason: 'the check never moved the user',
      );
      expect(
        checker.log.join('\n'),
        isNot(contains('open the Browser')),
        reason: 'it never had to ask for the Browser back',
      );
      expect(result.state, UpdateCheckState.updatesAvailable);
      expect(result.newEntries, greaterThan(0));
      expect(
        result.pagesInspected,
        greaterThan(0),
        reason: 'it really navigated and read pages, with the Reader on screen',
      );
    },
    timeout: const Timeout(Duration(minutes: 8)),
  );
}

const kCheckTimeout = Duration(minutes: 3);
