// M5 + M6 acceptance, end to end on the Simulator against the in-process
// fixture: save, read, leave, restart, complete, continue, mark unread.
//
//   flutter test integration_test/reading_flow_test.dart -d <simulator-id>
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
import 'package:web_reader/providers.dart';
import 'package:web_reader/reading/reading_position.dart';
import 'package:web_reader/reading/reading_repository.dart';
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
  late ReadingRepository reading;
  HttpServer? server;
  late String baseUrl;

  Future<void> startFixture() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    baseUrl = 'http://127.0.0.1:${server!.port}';
    unawaited(() async {
      try {
        await for (final req in server!) {
          try {
            await handleFixtureRequest(req, applyDelays: false);
          } catch (_) {}
        }
      } catch (_) {}
    }());
  }

  /// Pump repeatedly rather than once: the WebView is a platform view, and a
  /// single pump is not always enough for it to be created and attached before
  /// the test drives it.
  Future<void> settle(WidgetTester tester, Duration d) async {
    final end = DateTime.now().add(d);
    while (DateTime.now().isBefore(end)) {
      await tester.pump(const Duration(milliseconds: 100));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
  }

  Future<void> boot(WidgetTester tester) async {
    db = AppDatabase(name: 'it_reading_flow_$kRunStamp');
    fileStore = await FileStore.open(
      folderName: 'webread_it_reading_flow_$kRunStamp',
    );
    browser = BrowserController();
    reading = ReadingRepository(db);
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
    final deadline = DateTime.now().add(const Duration(seconds: 20));
    while (run.isRunning && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    await server?.close(force: true);
    await db.close();
  });

  testWidgets('M5+M6: save, read, restart, complete, continue', (tester) async {
    await startFixture();
    await boot(tester);

    // --- save two entries -------------------------------------------
    await browser.loadAndWait('$baseUrl/entry/1');
    await settle(tester, const Duration(seconds: 1));
    unawaited(run.start(range: SaveScope.fixedCount, entryLimit: 2));
    await waitFor(
      tester,
      () => run.progress.state.isTerminal && !run.isRunning,
    );

    for (final line in run.log.reversed) {
      debugPrint('[run] $line');
    }
    var entries = await db.allEntries();
    expect(entries.length, 2, reason: 'two entries saved');
    final sorted = [...entries]
      ..sort((a, b) => a.entryOrder.compareTo(b.entryOrder));
    final first = sorted.first;
    final second = sorted.last;
    debugPrint(
      '[M5] saved ${entries.length}: '
      '${sorted.map((c) => c.sourceMarker).toList()}',
    );

    // --- 1-3. read partway, then leave -----------------------------------
    await reading.markOpened(first.id);
    await reading.saveProgress(
      first.id,
      const ReadingPosition(fraction: 0.5, anchorIndex: 2, offsetInAnchor: 0.4),
    );

    var reloaded = (await db.entryById(first.id))!;
    expect(reloaded.progressFraction, closeTo(0.5, 0.01));
    expect(reloaded.readStatus, 'inProgress');
    debugPrint('[M5] saved position: ${reading.positionOf(reloaded)}');

    // --- 4-6. "restart the app": new db handle over the same container ----
    await db.close();
    await boot(tester);

    reloaded = (await db.entryById(first.id))!;
    final restored = reading.positionOf(reloaded);
    expect(
      restored.anchorIndex,
      2,
      reason: 'the anchor survived a full restart',
    );
    expect(restored.offsetInAnchor, closeTo(0.4, 0.01));
    expect(restored.fraction, closeTo(0.5, 0.01));
    debugPrint('[M5] restored after restart: $restored');

    // --- M6. the collection is in Continue, on entry 1 ----------------------
    var state = computeCollectionReadingState(
      await db.entriesForCollection(first.collectionId!),
    );
    expect(state.continueEntry!.id, first.id);
    debugPrint('[M6] continue -> ${state.continueEntry!.sourceMarker}');

    // --- 7. finish it ----------------------------------------------------
    await reading.markRead(first.id);
    reloaded = (await db.entryById(first.id))!;
    expect(reloaded.readStatus, 'completed');
    expect(reloaded.completedAt, isNotNull);

    // --- M6. Continue advances to entry 2 ------------------------------
    state = computeCollectionReadingState(
      await db.entriesForCollection(first.collectionId!),
    );
    expect(state.continueEntry!.id, second.id);
    debugPrint(
      '[M6] after completing 1, continue -> '
      '${state.continueEntry!.sourceMarker}',
    );

    // --- everything read: leaves Continue, keeps its last-read time ------
    await reading.markRead(second.id);
    state = computeCollectionReadingState(
      await db.entriesForCollection(first.collectionId!),
    );
    expect(state.allCompleted, isTrue);
    expect(state.continueEntry, isNull);
    expect(state.lastReadAt, isNotNull, reason: 'last-read time kept');
    debugPrint('[M6] all read: continue=null, lastReadAt kept');

    // --- 8-9. mark unread restores eligibility ---------------------------
    await reading.markUnread(first.id);
    state = computeCollectionReadingState(
      await db.entriesForCollection(first.collectionId!),
    );
    expect(state.continueEntry!.id, first.id);
    expect(
      (await db.entryById(first.id))!.progressPageIndex,
      2,
      reason: 'marking unread keeps the position so it can be resumed',
    );
    debugPrint(
      '[M6] after mark-unread, continue -> '
      '${state.continueEntry!.sourceMarker}',
    );

    // --- 10. re-download preserves reading progress ----------------------
    await reading.markRead(first.id);
    final beforeRedownload = (await db.entryById(first.id))!;

    await browser.loadAndWait(first.sourceUrl);
    await settle(tester, const Duration(seconds: 1));
    unawaited(
      run.start(
        range: SaveScope.fixedCount,
        entryLimit: 1,
        policy: DuplicatePolicy.replaceAll,
      ),
    );
    await waitFor(
      tester,
      () => run.progress.state.isTerminal && !run.isRunning,
    );

    final afterRedownload = (await db.entryById(first.id))!;
    expect(
      (await db.allEntries()).where((c) => c.urlKey == first.urlKey).length,
      1,
      reason: 're-download must not create a duplicate row',
    );
    expect(afterRedownload.readStatus, 'completed');
    expect(
      afterRedownload.progressPageIndex,
      beforeRedownload.progressPageIndex,
    );
    expect(afterRedownload.completedAt, beforeRedownload.completedAt);
    expect(afterRedownload.storedAssetCount, greaterThan(0));
    debugPrint(
      '[M5] after re-download: status=${afterRedownload.readStatus} '
      'anchor=${afterRedownload.progressPageIndex} '
      'images=${afterRedownload.storedAssetCount}',
    );

    for (final line in run.log.reversed.take(12)) {
      debugPrint('[run] $line');
    }
  });
}
