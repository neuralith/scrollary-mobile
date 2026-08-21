import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:web_reader/save/save_run.dart';
import 'package:web_reader/core/local_reset.dart';
import 'package:web_reader/library/update_checker.dart';
import 'package:web_reader/queue/task_queue.dart';
import 'package:web_reader/storage/database.dart';
import 'package:web_reader/storage/file_store.dart';

import 'helpers/fake_browser.dart';
import 'package:web_reader/features/collection_detail_screen.dart'
    show kEntrySortKey;

/// The development reset: everything goes, in a controlled order, and a
/// partial failure says so rather than claiming success.
void main() {
  late AppDatabase db;
  late FakeBrowser browser;
  late Directory root;
  late FileStore store;
  late TaskQueueController queue;
  late SaveRunController run;
  var cookiesCleared = 0;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    browser = FakeBrowser();
    root = Directory.systemTemp.createTempSync('webread_reset');
    store = FileStore(root);
    cookiesCleared = 0;
    run = SaveRunController(browser: browser, db: db, fileStore: store);
    queue = TaskQueueController(
      db: db,
      browser: browser,
      saveRun: run,
      checker: UpdateChecker(browser: browser, db: db),
      saveRunner: (_) async => const QueueOutcome.success('x'),
      checkRunner: (_) async => const QueueOutcome.success('x'),
    );
  });

  tearDown(() async {
    await db.close();
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  LocalResetService makeService({Future<void> Function()? cookies}) =>
      LocalResetService(
        db: db,
        fileStore: store,
        browser: browser,
        saveRun: run,
        checker: UpdateChecker(browser: browser, db: db),
        taskQueue: queue,
        clearCookies:
            cookies ??
            () async {
              cookiesCleared++;
            },
      );

  /// A device that has been used: a collection, an entry with files on disk,
  /// reading progress, a queued task, a saved rule and a setting.
  Future<void> seedUsedApp() async {
    await db.upsertCollection(
      Collection(
        contentKind: 'unknownWebContent',
        sequenceKind: 'none',
        orderingBasis: 'discoveryOrder',
        shapeConfidence: 'low',
        lifecycle: 'active',
        id: 'collection-1',
        title: 'Foo',
        sourceUrl: 'https://x.example/guide/foo',
        host: 'x.example',
        collectionKey: '/guide/foo',
        createdAt: DateTime(2026, 7, 1),
      ),
    );
    await db.upsertEntry(
      Entry(
        host: '',
        contentKind: 'unknownWebContent',
        contentKindConfidence: 'low',
        contentKindIsUserSet: false,
        id: 'c1',
        collectionId: 'collection-1',
        title: 'Entry 1',
        sourceUrl: 'https://x.example/guide/foo/1',
        urlKey: 'https://x.example/guide/foo/1',
        artifactFormat: 'imageSequence',
        saveStatus: 'complete',
        contentPath: 'library/collection-1/entries/c1',
        savedAt: DateTime(2026, 7, 20),
        detectedAssetCount: 1,
        storedAssetCount: 1,
        entryOrder: 1,
        byteSize: 64,
        entryNumber: 1,
        sourceMarker: 'Entry 1',
        readStatus: 'completed',
        progressFraction: 1,
        progressPageIndex: 0,
        progressOffsetInPage: 0,
      ),
    );
    await db.setSetting('collection.entrySort', 'oldestFirst');
    await queue.enqueueSave(
      startUrl: 'https://x.example/guide/foo/2',
      entryLimit: 1,
    );

    final dir = Directory(p.join(root.path, 'library', 'collection-1'))
      ..createSync(recursive: true);
    File(p.join(dir.path, 'panel.png')).writeAsBytesSync([1, 2, 3]);
    Directory(
      p.join(root.path, 'tmp', 'staging-1'),
    ).createSync(recursive: true);
    Directory(
      p.join(root.path, 'library', 'collection-1.previous'),
    ).createSync(recursive: true);
  }

  test('the developer tools are debug-only', () {
    // The test binary is a debug build, so the gate is open here — the value
    // being kDebugMode is what guarantees it is shut in release.
    expect(developerToolsAvailable, kDebugMode);
    expect(kReleaseMode, isFalse, reason: 'sanity: tests run in debug');
  });

  test('a used app comes back empty', () async {
    await seedUsedApp();
    expect(await db.allEntries(), isNotEmpty);

    final report = await makeService().resetEverything();

    expect(report.ok, isTrue, reason: report.toString());
    expect(await db.allEntries(), isEmpty);
    expect(await db.allCollections(), isEmpty);
    expect(await db.watchQueueTasks().first, isEmpty);
    expect(await db.setting(kEntrySortKey), isNull);
  });

  test('a collection cleanup decision does not survive a reset', () async {
    await seedUsedApp();
    final collection = (await db.allCollections()).first;
    await db.setCollectionCleanupPreference(collection.id, 'remove');
    expect(
      (await db.collectionById(collection.id))!.cleanupPreference,
      'remove',
    );

    await makeService().resetEverything();

    // The decision lives on the collection row, so it goes with it: a reset
    // app asks the question again, exactly as a clean install does. There is no
    // separate setting for it to hide in.
    expect(await db.collectionById(collection.id), isNull);
    expect(await db.allCollections(), isEmpty);
  });

  test('every table is emptied, discovered from the schema', () async {
    await seedUsedApp();
    await makeService().resetEverything();

    // The wipe empties everything; the two rows that exist afterwards are the
    // clean-install seed put back on purpose (D54) — the default saved site
    // and the flag that stops it being seeded twice.
    const reseeded = {'saved_sites', 'settings'};

    for (final table in db.allTables) {
      if (reseeded.contains(table.actualTableName)) continue;
      final rows = await db
          .customSelect('SELECT COUNT(*) AS n FROM ${table.actualTableName}')
          .getSingle();
      expect(
        rows.read<int>('n'),
        0,
        reason: '${table.actualTableName} still has rows',
      );
    }

    // A reset makes the app a clean install again — and a clean install has an
    // empty saved-sites list. Nothing is seeded back, because nothing is seeded
    // in the first place: a site the developer chose would be a recommendation
    // the app is not entitled to make.
    expect(
      await db.allSavedSites(),
      isEmpty,
      reason: 'a reset must not put a developer-chosen site back',
    );
    // Nothing the user set survives either, including the sort preference.
    expect(await db.setting(kEntrySortKey), isNull);
  });

  test('saved files, staging and replacement backups all go', () async {
    await seedUsedApp();
    expect(
      Directory(p.join(root.path, 'library', 'collection-1')).existsSync(),
      isTrue,
    );

    await makeService().resetEverything();

    expect(
      Directory(p.join(root.path, 'library', 'collection-1')).existsSync(),
      isFalse,
    );
    expect(
      Directory(p.join(root.path, 'tmp', 'staging-1')).existsSync(),
      isFalse,
    );
    expect(
      Directory(
        p.join(root.path, 'library', 'collection-1.previous'),
      ).existsSync(),
      isFalse,
    );
    // The empty skeleton is put back, so the next save is a normal one.
    expect(Directory(p.join(root.path, 'library')).existsSync(), isTrue);
    expect(Directory(p.join(root.path, 'tmp')).existsSync(), isTrue);
  });

  test('cookies are cleared', () async {
    await seedUsedApp();
    await makeService().resetEverything();
    expect(cookiesCleared, 1);
  });

  test('a build with no cookie store reports skipped, not cleared', () async {
    final service = LocalResetService(
      db: db,
      fileStore: store,
      browser: browser,
      saveRun: run,
      checker: UpdateChecker(browser: browser, db: db),
      taskQueue: queue,
    );
    final report = await service.resetEverything();
    expect(report.ok, isTrue);
    expect(
      report.steps.firstWhere((s) => s.area == 'browser session').detail,
      contains('skipped'),
    );
  });

  test('active work is stopped before anything is deleted', () async {
    await seedUsedApp();
    browser.automationOwner = 'save';

    await makeService().resetEverything();

    expect(browser.automationOwner, isNull);
    expect(await queue.queuedSaves(), isEmpty);
    expect(queue.saveStartAuthorised, isFalse);
  });

  test('the report names every area', () async {
    await seedUsedApp();
    final report = await makeService().resetEverything();
    // Four areas, not five: the "browser defaults" step existed only to reseed
    // a saved site, and there is no longer a default to restore.
    expect(report.steps.map((s) => s.area), [
      'active work',
      'database rows',
      'saved files',
      'browser session',
    ]);
    expect(report.summary, contains('Reset complete'));
  });

  test('a failing area is reported, and does not claim success', () async {
    await seedUsedApp();
    final service = makeService(
      cookies: () async => throw StateError('cookie store unavailable'),
    );

    final report = await service.resetEverything();

    expect(report.ok, isFalse);
    expect(report.summary, contains('INCOMPLETE'));
    expect(report.failures.single.area, 'browser session');
    // The areas that DID work still worked — a partial failure leaves the
    // app recoverable, not half-wiped and lying about it.
    expect(await db.allEntries(), isEmpty);
    expect(
      Directory(p.join(root.path, 'library', 'collection-1')).existsSync(),
      isFalse,
    );
  });

  test('resetting twice is harmless', () async {
    await seedUsedApp();
    await makeService().resetEverything();
    final second = await makeService().resetEverything();
    expect(second.ok, isTrue);
    expect(await db.allEntries(), isEmpty);
  });
}
