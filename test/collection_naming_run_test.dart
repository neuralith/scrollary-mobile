import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:web_reader/core/config.dart';
import 'package:web_reader/library/collection_repository.dart';
import 'package:web_reader/save/save_run.dart';
import 'package:web_reader/save/save_state.dart';
import 'package:web_reader/storage/database.dart';
import 'package:web_reader/storage/file_store.dart';

import 'helpers/fake_browser.dart';
import '../tool/fixture/fixture_site.dart';

/// The naming prompt through the real run loop.
///
/// The point of these tests, over the repository-level ones in
/// `collection_naming_test.dart`, is *when* the prompt arrives and what a
/// cancel actually costs: the run holds on page 1 before anything is written,
/// and declining ends it with the library exactly as it was.
void main() {
  late AppDatabase db;
  late Directory root;
  late FileStore store;
  late FakeBrowser browser;
  late HttpServer server;
  late String assetBase;

  const host = 'https://x.example';
  String entryUrl(int n) => '$host/guide/the-long-guide/$n';

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

  setUpAll(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    assetBase = 'http://127.0.0.1:${server.port}';
    server.listen((req) async {
      final match = RegExp(r'^/img/(\d+)/(\d+)\.png$').firstMatch(req.uri.path);
      if (match == null) {
        req.response.statusCode = 404;
        await req.response.close();
        return;
      }
      req.response.headers.contentType = ContentType('image', 'png');
      req.response.add(
        panelPng(
          entry: int.parse(match.group(1)!),
          index: int.parse(match.group(2)!),
        ),
      );
      await req.response.close();
    });
  });
  tearDownAll(() => server.close(force: true));

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    root = Directory.systemTemp.createTempSync('webread_naming');
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

  SaveRunController controller({required bool asks}) => SaveRunController(
    browser: browser,
    db: db,
    fileStore: store,
    config: config,
    asksForCollectionName: asks,
  );

  /// Entry pages 1..[count], each linking rel=next to its successor. The page
  /// titles carry a marker, which is what the identity layer strips down to
  /// the suggestion.
  void servePages(int count) {
    for (var n = 1; n <= count; n++) {
      browser.addPage(
        entryUrl(n),
        entryProbe(
          url: entryUrl(n),
          title: 'The Long Guide Part $n',
          imageUrls: [for (var i = 1; i <= 3; i++) '$assetBase/img/$n/$i.png'],
          nextHref: n < count ? entryUrl(n + 1) : null,
        ),
      );
    }
  }

  Future<void> until(
    bool Function() done, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (!done()) {
      if (DateTime.now().isAfter(deadline)) fail('timed out');
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  }

  test(
    'a run creating a collection holds before anything is written',
    () async {
      servePages(3);
      browser.setUrl(entryUrl(1));
      final run = controller(asks: true);

      final running = run.start(
        range: SaveScope.fixedCount,
        entryLimit: 2,
        captureModeIsUserSet: false,
        startUrl: entryUrl(1),
      );

      await until(() => run.pendingCollectionName != null);

      // The hold is real: nothing exists yet in either table.
      expect(await db.allCollections(), isEmpty);
      expect(await db.allEntries(), isEmpty);
      expect(run.pendingCollectionName!.suggestedName, 'The Long Guide');
      expect(run.pendingCollectionName!.host, 'x.example');
      expect(run.progress.state, SaveState.awaitingSelection);

      run.resolveCollectionName('My Reading Shelf');
      await running.timeout(const Duration(seconds: 60));

      final collections = await db.allCollections();
      expect(collections, hasLength(1));
      expect(displayNameFor(collections.single), 'My Reading Shelf');
      expect(collections.single.title, 'The Long Guide');
      expect((await db.allEntries()).length, 2);
    },
  );

  test('cancelling the prompt saves nothing and ends the run', () async {
    servePages(3);
    browser.setUrl(entryUrl(1));
    final run = controller(asks: true);

    final running = run.start(
      range: SaveScope.fixedCount,
      entryLimit: 2,
      captureModeIsUserSet: false,
      startUrl: entryUrl(1),
    );

    await until(() => run.pendingCollectionName != null);
    run.resolveCollectionName(null);
    await running.timeout(const Duration(seconds: 60));

    expect(await db.allCollections(), isEmpty);
    expect(await db.allEntries(), isEmpty);
    expect(run.progress.state, SaveState.cancelled);
    expect(browser.automationOwner, isNull, reason: 'gave the browser back');
  });

  test('stopping the task from elsewhere releases the hold', () async {
    // Activity's cancel calls `stop()` directly. A run parked on the naming
    // completer is not inside the engine and not at the loop head, so without
    // stop() releasing it the run would hold the Browser and the wakelock for
    // good and the row would read "stopping" forever.
    servePages(3);
    browser.setUrl(entryUrl(1));
    final run = controller(asks: true);

    final running = run.start(
      range: SaveScope.fixedCount,
      entryLimit: 2,
      captureModeIsUserSet: false,
      startUrl: entryUrl(1),
    );

    await until(() => run.pendingCollectionName != null);
    run.stop();
    await running.timeout(const Duration(seconds: 60));

    expect(run.pendingCollectionName, isNull);
    expect(run.isRunning, isFalse);
    expect(await db.allCollections(), isEmpty);
    expect(await db.allEntries(), isEmpty);
    expect(browser.automationOwner, isNull);
  });

  test('a second save into that collection is not asked again', () async {
    servePages(4);
    browser.setUrl(entryUrl(1));
    final run = controller(asks: true);

    final first = run.start(
      range: SaveScope.fixedCount,
      entryLimit: 1,
      captureModeIsUserSet: false,
      startUrl: entryUrl(1),
    );
    await until(() => run.pendingCollectionName != null);
    run.resolveCollectionName('My Reading Shelf');
    await first.timeout(const Duration(seconds: 60));

    // A different page of the same collection: it joins what already exists.
    browser.setUrl(entryUrl(3));
    var asked = false;
    run.addListener(() {
      if (run.pendingCollectionName != null) asked = true;
    });
    await run
        .start(
          range: SaveScope.fixedCount,
          entryLimit: 1,
          captureModeIsUserSet: false,
          startUrl: entryUrl(3),
        )
        .timeout(const Duration(seconds: 60));

    expect(asked, isFalse);
    final collections = await db.allCollections();
    expect(collections, hasLength(1));
    expect(displayNameFor(collections.single), 'My Reading Shelf');
    expect((await db.allEntries()).length, 2);
  });

  test('a run that cannot ask names the collection as it always did', () async {
    servePages(3);
    browser.setUrl(entryUrl(1));
    final run = controller(asks: false);

    await run
        .start(
          range: SaveScope.fixedCount,
          entryLimit: 2,
          captureModeIsUserSet: false,
          startUrl: entryUrl(1),
        )
        .timeout(const Duration(seconds: 60));

    expect(run.pendingCollectionName, isNull);
    final collections = await db.allCollections();
    expect(collections, hasLength(1));
    expect(collections.single.userTitle, isNull);
    expect(displayNameFor(collections.single), 'The Long Guide');
    expect((await db.allEntries()).length, 2);
  });
}
