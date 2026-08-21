// M8 acceptance, end to end on the Simulator against the in-process fixture:
// save 1-2, source publishes 3-4, check discovers them WITHOUT downloading,
// save them, count clears, re-check says up to date, state survives a
// restart.
//
//   flutter test integration_test/update_check_test.dart -d <simulator-id>
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:web_reader/app.dart';
import 'package:web_reader/core/config.dart';
import 'package:web_reader/browser/browser_controller.dart';
import 'package:web_reader/save/save_run.dart';
import 'package:web_reader/save/save_preflight.dart';
import 'package:web_reader/library/update_checker.dart';
import 'package:web_reader/providers.dart';
import 'package:web_reader/storage/database.dart';
import 'package:web_reader/storage/file_store.dart';

import '../tool/fixture/fixture_site.dart';

/// Unique per process: a run that is killed mid-way never uninstalls the
/// app, so a fixed name would leak rows into the next invocation.
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
  HttpServer? server;
  late String baseUrl;

  /// The "site" grows mid-test: this is how the source publishes entries.
  var liveEntryCount = 2;

  Future<void> startFixture() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    baseUrl = 'http://127.0.0.1:${server!.port}';
    unawaited(() async {
      try {
        await for (final req in server!) {
          try {
            await handleFixtureRequest(
              req,
              applyDelays: false,
              entryCount: liveEntryCount,
            );
          } catch (_) {}
        }
      } catch (_) {}
    }());
  }

  Future<void> settle(WidgetTester tester, Duration d) async {
    final end = DateTime.now().add(d);
    while (DateTime.now().isBefore(end)) {
      await tester.pump(const Duration(milliseconds: 100));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
  }

  Future<void> boot(WidgetTester tester) async {
    // Own database and storage root: this test must not depend on, or leak
    // into, any other integration test's state.
    db = AppDatabase(name: 'it_update_check_$kRunStamp');
    fileStore = await FileStore.open(
      folderName: 'webread_it_update_check_$kRunStamp',
    );
    browser = BrowserController();
    checker = UpdateChecker(browser: browser, db: db);
    run = SaveRunController(browser: browser, db: db, fileStore: fileStore);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appServicesProvider.overrideWithValue(
            AppServices(
              db: db,
              fileStore: fileStore,
              browser: browser,
              saveRun: run,
              updateChecker: checker,
            ),
          ),
        ],
        child: const WebReaderApp(),
      ),
    );
    await settle(tester, const Duration(seconds: 3));
  }

  Future<void> waitFor(
    WidgetTester tester,
    bool Function() done, {
    Duration timeout = const Duration(minutes: 3),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (!done() && DateTime.now().isBefore(deadline)) {
      await settle(tester, const Duration(milliseconds: 200));
    }
  }

  tearDown(() async {
    run.stop();
    checker.cancel();
    final deadline = DateTime.now().add(const Duration(seconds: 20));
    while (run.isRunning && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    await server?.close(force: true);
    await db.close();
  });

  testWidgets('M8: discover, list, save, clear, up-to-date, persist', (
    tester,
  ) async {
    liveEntryCount = 2;
    await startFixture();
    await boot(tester);

    // --- 1. save entries 1 and 2 --------------------------------------
    await browser.loadAndWait('$baseUrl/entry/1');
    await settle(tester, const Duration(seconds: 1));
    unawaited(run.start(range: SaveScope.fixedCount, entryLimit: 2));
    await waitFor(
      tester,
      () => run.progress.state.isTerminal && !run.isRunning,
    );

    var entries = await db.allEntries();
    expect(entries.length, 2, reason: 'two entries saved');
    final itemId = entries.first.collectionId!;
    debugPrint('[M8] saved ${entries.length} entries');

    // --- 2. the source publishes entries 3 and 4 -------------------------
    liveEntryCount = 4;
    debugPrint('[M8] source now has 4 entries');

    // --- 3-4. check discovers them without downloading --------------------
    final outcome = await checker.check(itemId);
    for (final line in checker.log.reversed) {
      debugPrint('[check] $line');
    }
    expect(outcome.state, UpdateCheckState.updatesAvailable);
    expect(outcome.newEntries, 2);

    entries = await db.allEntries();
    final discovered = entries
        .where((c) => c.saveStatus == 'knownRemote')
        .toList();
    expect(discovered.length, 2, reason: 'entries 3 and 4 discovered');
    for (final c in discovered) {
      expect(c.contentPath, isNull, reason: 'discovered, never downloaded');
      expect(c.storedAssetCount, 0);
      expect(c.discoveredAt, isNotNull);
      expect(c.discoveryBasis, isNotNull);
    }
    debugPrint(
      '[M8] discovered without downloading: '
      '${discovered.map((c) => c.sourceMarker ?? c.title).toList()}',
    );

    // --- 5. the collection row earns its "N new" chip -------------------------
    final item = (await db.collectionById(itemId))!;
    expect(item.lastCheckSuccessAt, isNotNull);
    expect(item.lastCheckResult, 'updatesAvailable');
    debugPrint('[M8] collection row shows "2 new" (2 unsaved known)');

    // --- 6-7. save the discovered entries ------------------------------
    final ordered = [...discovered]
      ..sort((a, b) => (a.entryNumber ?? 0).compareTo(b.entryNumber ?? 0));
    unawaited(
      run.start(
        range: SaveScope.fixedCount,
        entryLimit: ordered.length,
        startUrl: ordered.first.sourceUrl,
        policy: DuplicatePolicy.skipComplete,
      ),
    );
    await waitFor(
      tester,
      () => run.progress.state.isTerminal && !run.isRunning,
    );
    for (final line in run.log.reversed.take(14)) {
      debugPrint('[run] $line');
    }

    entries = await db.allEntries();
    expect(entries.length, 4, reason: 'no duplicate rows created');
    // --- 8. the "N new" count clears ---------------------------------------
    expect(
      entries.where((c) => c.saveStatus == 'knownRemote'),
      isEmpty,
      reason: 'discovered entries became offline entries',
    );
    for (final c in entries) {
      expect(c.contentPath, isNotNull);
      expect(c.saveStatus, anyOf('complete', 'partial'));
    }
    debugPrint('[M8] discovered entries saved; "new" count cleared');

    // --- 9. re-check: up to date -------------------------------------------
    final second = await checker.check(itemId);
    expect(second.state, UpdateCheckState.upToDate);
    expect(second.newEntries, 0);
    debugPrint('[M8] re-check: upToDate');

    // --- 10. check state survives a restart --------------------------------
    await db.close();
    await boot(tester);
    final after = (await db.collectionById(itemId))!;
    expect(after.lastCheckSuccessAt, isNotNull);
    expect(after.lastCheckResult, 'upToDate');
    expect((await db.entriesForCollection(itemId)).length, 4);
    debugPrint(
      '[M8] after restart: lastCheckResult=${after.lastCheckResult} kept',
    );
  });
}
