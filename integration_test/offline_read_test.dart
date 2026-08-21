// M2: save online, then read with the source gone — in one run.
//
//   flutter test integration_test/offline_read_test.dart -d <simulator-id>
//
// The fixture is served *in-process on the simulator*, so the test can shut it
// down mid-run. That is what makes "offline" provable rather than asserted:
// after `server.close(force: true)` the source genuinely does not exist, and
// every panel the reader shows must have come off disk.
//
// (`flutter test integration_test/...` uninstalls the app afterwards, wiping
// the container — which is why the save and the offline read must happen in
// the same run rather than as two separate invocations.)
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
import 'package:web_reader/storage/database.dart';
import 'package:web_reader/storage/file_store.dart';
import 'package:web_reader/storage/manifest.dart';

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
  HttpServer? server;
  late String baseUrl;

  Future<void> startFixture() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    baseUrl = 'http://127.0.0.1:${server!.port}';
    unawaited(() async {
      try {
        await for (final req in server!) {
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
    debugPrint('[fixture] serving on $baseUrl');
  }

  Future<void> stopFixture() async {
    await server?.close(force: true);
    server = null;
    debugPrint('[fixture] STOPPED — the source no longer exists');
  }

  Future<bool> sourceReachable() async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 2);
    try {
      final req = await client.getUrl(Uri.parse('$baseUrl/entry/1'));
      final res = await req.close();
      await res.drain<void>();
      return true;
    } catch (_) {
      return false;
    } finally {
      client.close(force: true);
    }
  }

  Future<void> pumpFor(WidgetTester tester, Duration duration) async {
    final end = DateTime.now().add(duration);
    while (DateTime.now().isBefore(end)) {
      await tester.pump(const Duration(milliseconds: 100));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
  }

  Future<void> bootApp(WidgetTester tester) async {
    db = AppDatabase(name: 'it_offline_read_$kRunStamp');
    fileStore = await FileStore.open(
      folderName: 'webread_it_offline_read_$kRunStamp',
    );
    browser = BrowserController();
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
    // Not pumpAndSettle: the browser tab hosts a live WebView that never
    // settles, so pump on a clock instead.
    await pumpFor(tester, const Duration(seconds: 3));
  }

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
    expect(done(), isTrue, reason: 'timed out waiting for the condition');
  }

  /// A collection row in the All Collection list, regardless of what Continue cards
  /// sit above it. Identified by key rather than widget type — the redesigned
  /// row is a Stack, not a ListTile.
  Finder collectionCard() => find.byWidgetPredicate(
    (w) =>
        w.key is ValueKey<String> &&
        (w.key! as ValueKey<String>).value.startsWith('collectionRow-'),
  );

  /// A saved-entry row on the collection detail screen.
  Finder entryRow() => find.byWidgetPredicate(
    (w) =>
        w.key is ValueKey<String> &&
        (w.key! as ValueKey<String>).value.startsWith('entryRow-'),
  );

  /// Switch to the Library tab. "Library" is both the tab label and the
  /// screen title, so the tab carries its own key.
  Future<void> openLibraryTab(WidgetTester tester) => tester.tap(
    find.byKey(const ValueKey('navTab-Library')),
    warnIfMissed: false,
  );

  tearDown(() async {
    await stopFixture();
    await db.close();
  });

  testWidgets('M2: save online, kill the source, read entirely from disk', (
    tester,
  ) async {
    // --- 1. save, with the source up -------------------------------
    await startFixture();
    expect(await sourceReachable(), isTrue, reason: 'fixture should be up');

    await bootApp(tester);
    await browser.loadAndWait('$baseUrl/entry/1');
    await pumpFor(tester, const Duration(seconds: 1));

    unawaited(run.start(range: SaveScope.fixedCount, entryLimit: 3));
    await pumpUntil(
      tester,
      () => run.progress.state.isTerminal && !run.isRunning,
    );
    for (final line in run.log.reversed) {
      debugPrint('[run] $line');
    }

    final entries = await db.watchAllEntries().first;
    expect(entries.length, 3);

    // --- 2. confirm the files are really there -------------------------
    var panelsOnDisk = 0;
    for (final entry in entries) {
      final relative = entry.contentPath!;
      expect(
        relative,
        isNot(startsWith('/')),
        reason: 'paths must be relative to the app container',
      );
      final manifest = await fileStore.readManifest(relative);
      expect(manifest, isNotNull);
      for (final asset in manifest!.storedAssets) {
        final file = fileStore.assetFile(relative, asset.relativePath!);
        expect(file.existsSync(), isTrue);
        final bytes = await file.readAsBytes();
        expect(bytes.sublist(0, 4), [
          0x89,
          0x50,
          0x4e,
          0x47,
        ], reason: 'real PNG bytes, not a placeholder');
        panelsOnDisk++;
      }
      debugPrint(
        '[M2] ${entry.title}: '
        '${manifest.storedAssets.length} panels · ${manifest.status.name}',
      );
    }
    expect(panelsOnDisk, 17, reason: '6 + 5 (one 503) + 6');

    // --- 3. destroy the source ------------------------------------------
    await stopFixture();
    expect(
      await sourceReachable(),
      isFalse,
      reason: 'the source must be genuinely gone for this to prove anything',
    );

    // --- 4. restart the app against the same container ------------------
    await db.close();
    await bootApp(tester);

    final afterRestart = await db.watchAllEntries().first;
    expect(afterRestart.length, 3, reason: 'library survived the restart');

    // --- 5. read it, through the real UI --------------------------------
    await openLibraryTab(tester);
    await pumpFor(tester, const Duration(seconds: 2));

    await pumpUntil(
      tester,
      () => collectionCard().evaluate().isNotEmpty,
      timeout: const Duration(seconds: 20),
    );

    // Since M4 the library is grouped: collection card → collection detail →
    // entry tile → reader.
    await tester.ensureVisible(collectionCard().first);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(collectionCard().first, warnIfMissed: false);
    await pumpUntil(
      tester,
      () => find.textContaining('images').evaluate().isNotEmpty,
      timeout: const Duration(seconds: 20),
    );
    await tester.ensureVisible(entryRow().first);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(entryRow().first, warnIfMissed: false);
    await pumpFor(tester, const Duration(seconds: 3));

    final images = tester.widgetList<Image>(find.byType(Image)).toList();
    expect(images, isNotEmpty, reason: 'the reader rendered panels');
    for (final image in images) {
      // `cacheWidth` wraps the provider in a ResizeImage; unwrapping it also
      // confirms the decode-width limit is actually applied, which is what
      // keeps a 60-panel entry from becoming hundreds of MB of bitmaps.
      final provider = image.image;
      expect(provider, isA<ResizeImage>());
      final resize = provider as ResizeImage;
      expect(resize.width, isNotNull, reason: 'decode width must be bounded');
      expect(
        resize.imageProvider,
        isA<FileImage>().having(
          (f) => f.file.existsSync(),
          'file exists',
          isTrue,
        ),
        reason:
            'every panel must come from a local file — the reader must '
            'never fall back to a remote URL',
      );
    }
    expect(find.textContaining('no longer'), findsNothing);

    debugPrint(
      '[M2] reader rendered ${images.length} local panels with the '
      'source server destroyed',
    );
  });

  testWidgets('M2: a partial entry warns instead of pretending to be whole', (
    tester,
  ) async {
    await startFixture();
    await bootApp(tester);
    await browser.loadAndWait('$baseUrl/entry/$kBrokenEntry');
    await pumpFor(tester, const Duration(seconds: 1));

    unawaited(run.start(range: SaveScope.fixedCount, entryLimit: 1));
    await pumpUntil(
      tester,
      () => run.progress.state.isTerminal && !run.isRunning,
    );

    final entries = await db.watchAllEntries().first;
    final partial = entries.where((c) => c.saveStatus == 'partial');
    expect(
      partial,
      isNotEmpty,
      reason: 'the 503 panel must produce a partial, never a false complete',
    );

    final entry = partial.first;
    expect(entry.storedAssetCount, lessThan(entry.detectedAssetCount));

    final manifest = await fileStore.readManifest(entry.contentPath!);
    expect(manifest!.status, SaveStatus.partial);
    expect(manifest.statusReason, contains('assetsFailed'));

    final failed = manifest.assets
        .where((a) => a.status == AssetStatus.failed)
        .toList();
    expect(failed, isNotEmpty);
    expect(failed.first.error, isNotNull);
    expect(
      failed.first.relativePath,
      isNull,
      reason: 'a failed asset must not claim a local file',
    );

    await stopFixture();

    // The reader shows the warning, offline. Grouped library since M4:
    // collection card → collection detail → entry tile → reader. Waits are on
    // conditions, not clocks — stream providers emit when they emit.
    await openLibraryTab(tester);
    await pumpUntil(
      tester,
      () => collectionCard().evaluate().isNotEmpty,
      timeout: const Duration(seconds: 20),
    );
    // Earlier tests fill the sections above All Collection, so the collection card
    // can sit below the fold — bring it into view, then open THE partial
    // entry by its own label rather than whatever tile happens to be first.
    await tester.ensureVisible(collectionCard().first);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(collectionCard().first, warnIfMissed: false);
    final partialLabel = entry.sourceMarker ?? entry.title;
    await pumpUntil(
      tester,
      () => find
          .descendant(of: entryRow(), matching: find.text(partialLabel))
          .evaluate()
          .isNotEmpty,
      timeout: const Duration(seconds: 20),
    );
    final partialTile = find.ancestor(
      of: find.text(partialLabel),
      matching: entryRow(),
    );
    await tester.ensureVisible(partialTile.first);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(partialTile.first, warnIfMissed: false);
    await pumpFor(tester, const Duration(seconds: 3));

    expect(find.textContaining('Partial save'), findsOneWidget);

    debugPrint(
      '[M2] partial entry "${entry.title}": '
      '${entry.storedAssetCount}/${entry.detectedAssetCount} panels, '
      'reason=${manifest.statusReason}, warning shown offline',
    );
  });

  testWidgets('M2: deleted local files degrade gracefully, keeping history', (
    tester,
  ) async {
    await startFixture();
    await bootApp(tester);
    await browser.loadAndWait('$baseUrl/entry/1');
    await pumpFor(tester, const Duration(seconds: 1));

    // replaceAll: earlier tests in this run saved this entry on a
    // fixture at a dead port; a skip would chase that stale chain. This test
    // needs a fresh save whose files it can then destroy.
    unawaited(
      run.start(
        range: SaveScope.fixedCount,
        entryLimit: 1,
        policy: DuplicatePolicy.replaceAll,
      ),
    );
    await pumpUntil(
      tester,
      () => run.progress.state.isTerminal && !run.isRunning,
    );

    final entry = (await db.watchAllEntries().first).first;
    final relative = entry.contentPath!;

    // Simulate the OS or the user reclaiming the space behind our back.
    await stopFixture();
    Directory(fileStore.resolve(relative)).deleteSync(recursive: true);

    await openLibraryTab(tester);
    await pumpUntil(
      tester,
      () => collectionCard().evaluate().isNotEmpty,
      timeout: const Duration(seconds: 20),
    );
    await tester.ensureVisible(collectionCard().first);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(collectionCard().first, warnIfMissed: false);

    // Open the gutted entry itself: the database has not yet noticed the
    // files are gone, so the reader is what discovers it — and must degrade
    // to an explicit message rather than crash.
    // By key, not by label or position: the entry list is number-first and
    // newest-first now, so neither the visible text nor the row's index is a
    // stable way to find one particular entry.
    final goneTile = find.byKey(ValueKey('entryRow-${entry.id}'));
    await pumpUntil(
      tester,
      () => goneTile.evaluate().isNotEmpty,
      timeout: const Duration(seconds: 20),
    );
    await tester.ensureVisible(goneTile);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(goneTile, warnIfMissed: false);
    await pumpFor(tester, const Duration(seconds: 3));

    // No crash, an explicit message, and the row survives.
    expect(find.text('The files for this entry are gone'), findsOneWidget);

    final stillListed = await db.entryById(entry.id);
    expect(
      stillListed,
      isNotNull,
      reason: 'deleting files must never delete reading history',
    );
    expect(stillListed!.title, entry.title);

    debugPrint('[M2] "${entry.title}" lost its files, kept its row');
  });
}
