import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:web_reader/save/save_run.dart';
import 'package:web_reader/core/config.dart';
import 'package:web_reader/core/device_storage.dart';
import 'package:web_reader/storage/database.dart';
import 'package:web_reader/storage/file_store.dart';

import 'helpers/fake_browser.dart';
import '../tool/fixture/fixture_site.dart';
import 'package:web_reader/save/stop_conditions.dart';

/// The three save ranges through the real run loop: current entry,
/// fixed count, and until-end with its loop protection and safety limit.
void main() {
  late AppDatabase db;
  late Directory root;
  late FileStore store;
  late FakeBrowser browser;
  late SaveRunController run;
  late HttpServer server;
  late String assetBase;

  const host = 'https://x.example';
  String entryUrl(int n) => '$host/guide/foo/$n';

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
    root = Directory.systemTemp.createTempSync('webread_range');
    store = FileStore(root);
    Directory(
      p.join(root.path, FileStore.libraryFolderName),
    ).createSync(recursive: true);
    Directory(
      p.join(root.path, FileStore.tmpFolderName),
    ).createSync(recursive: true);
    browser = FakeBrowser();
    run = SaveRunController(
      browser: browser,
      db: db,
      fileStore: store,
      config: config,
    );
  });
  tearDown(() async {
    await db.close();
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  /// Entry pages 1..[count]; each links rel=next to its successor. With
  /// [loopBackFrom], that entry's next points back at entry 1.
  void servePages(int count, {int? loopBackFrom}) {
    for (var n = 1; n <= count; n++) {
      final next = n == loopBackFrom
          ? entryUrl(1)
          : (n < count ? entryUrl(n + 1) : null);
      browser.addPage(
        entryUrl(n),
        entryProbe(
          url: entryUrl(n),
          title: 'Foo Entry $n',
          imageUrls: [for (var i = 1; i <= 3; i++) '$assetBase/img/$n/$i.png'],
          nextHref: next,
        ),
      );
    }
  }

  test('current entry saves exactly one and stops', () async {
    servePages(4);
    browser.setUrl(entryUrl(1));
    await run.start(
      entryLimit: 99, // ignored: the mode wins
      captureModeIsUserSet: false,
      startUrl: entryUrl(1),
      range: SaveScope.currentPageOnly,
    );

    expect((await db.allEntries()).length, 1);
    expect(run.progress.message, contains('Saved 1 item'));
  });

  test('fixed count saves exactly N new entries', () async {
    servePages(5);
    browser.setUrl(entryUrl(1));
    await run.start(
      entryLimit: 2,
      captureModeIsUserSet: false,
      startUrl: entryUrl(1),
      range: SaveScope.fixedCount,
    );

    expect((await db.allEntries()).length, 2);
  });

  test('a collection that ends early stops there, not at the number', () async {
    servePages(2);
    browser.setUrl(entryUrl(1));
    await run.start(
      // Room for more than the collection holds.
      entryLimit: 5,
      captureModeIsUserSet: false,
      startUrl: entryUrl(1),
      range: SaveScope.fixedCount,
    );

    expect((await db.allEntries()).length, 2);
    expect(run.stopReason, StopReason.noNextPage);
  });

  test('the typed number is the ceiling, and it is the user\'s', () async {
    servePages(6);
    browser.setUrl(entryUrl(1));
    await run.start(
      entryLimit: 3,
      captureModeIsUserSet: false,
      startUrl: entryUrl(1),
      range: SaveScope.fixedCount,
    );

    expect((await db.allEntries()).length, 3, reason: 'bounded');
    // Every ceiling is now one the user typed, so nothing may blame an
    // internal "safety limit" the user never saw.
    expect(run.stopReason, StopReason.userLimitReached);
    expect(run.progress.message, isNot(contains('safety limit')));
  });

  test(
    'a navigation loop stops the run before the number is reached',
    () async {
      servePages(2, loopBackFrom: 2); // 1 -> 2 -> 1
      browser.setUrl(entryUrl(1));
      await run.start(
        // A ceiling above the loop, so it is the loop that ends the run.
        entryLimit: 5,
        captureModeIsUserSet: false,
        startUrl: entryUrl(1),
        range: SaveScope.fixedCount,
      );

      expect(
        (await db.allEntries()).length,
        2,
        reason: 'each entry once; the loop edge is rejected as visited',
      );
    },
  );

  test('the range mode is persisted on the run row', () async {
    // No page for the URL: the run records itself, then fails to inspect —
    // the persisted row is what matters here.
    browser.setUrl(entryUrl(9));
    await run.start(
      entryLimit: 1,
      captureModeIsUserSet: false,
      startUrl: entryUrl(9),
      range: SaveScope.fixedCount,
    );
    expect(run.scope, SaveScope.fixedCount);
  });

  test('resume continues in the persisted mode', () async {
    servePages(2);
    browser.setUrl(entryUrl(1));
    // A killed run left this row behind.
    await db.upsertRun(
      SaveRun(
        visitedCanonicals: '',
        origin: 'queue',
        scope: SaveScope.fixedCount.name,
        id: 'run-1-aaaaaaaa',
        collectionId: null,
        captureModeIsUserSet: false,
        startUrl: entryUrl(1),
        currentUrl: entryUrl(1),
        requestedEntries: 3,
        completedEntries: 0,
        state: 'navigating',
        visitedUrls: '',
        createdAt: DateTime(2026, 7, 27),
        updatedAt: DateTime(2026, 7, 27),
      ),
    );

    final row = (await db.findResumableRun())!;
    await run.resumeRun(row);

    expect(run.scope, SaveScope.fixedCount);
    expect((await db.allEntries()).length, 2, reason: 'ran to the end');
  });

  test('an unrecognised persisted scope reads as the safest one', () {
    // Rows written before the open-ended scope was removed must not resolve
    // to something that saves more than the user asked for.
    expect(saveScopeFromName('untilNoNextPage'), SaveScope.currentPageOnly);
    expect(saveScopeFromName(null), SaveScope.currentPageOnly);
  });

  test('disk refusal blocks the start with a distinct error', () async {
    servePages(1);
    browser.setUrl(entryUrl(1));
    final blocked = SaveRunController(
      browser: browser,
      db: db,
      fileStore: store,
      config: config,
      deviceStorage: _FixedStorage(free: 100 * 1024 * 1024), // < 500 MB floor
    );

    await blocked.start(
      range: SaveScope.fixedCount,
      entryLimit: 1,
      captureModeIsUserSet: false,
      startUrl: entryUrl(1),
    );

    expect(blocked.progress.lastError, 'insufficientStorage');
    expect(await db.allEntries(), isEmpty);
    expect(browser.automationOwner, isNull, reason: 'never took the browser');
  });
}

class _FixedStorage extends DeviceStorage {
  _FixedStorage({required this.free});
  final int free;

  @override
  Future<int?> freeBytes() async => free;

  @override
  Future<bool> excludeFromBackup(String absolutePath) async => true;
}
