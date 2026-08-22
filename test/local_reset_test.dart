import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:web_reader/browser/saved_sites_repository.dart';
import 'package:web_reader/capability/foreground_multitasking.dart';
import 'package:web_reader/core/local_reset.dart';
import 'package:web_reader/data/local_settings.dart';
import 'package:web_reader/data/schema.dart';
import 'package:web_reader/features/v2_composition.dart'
    show BrowsingHistoryStore;
import 'package:web_reader/save/queue_repository.dart';
import 'package:web_reader/storage/file_store.dart';

import 'data/support/repo_harness.dart';
import 'helpers/fake_browser.dart';

/// The development reset: everything goes, in a controlled order, and a
/// partial failure says so rather than claiming success.
void main() {
  late RepoHarness repos;
  late LibraryDatabase db;
  late SaveQueueRepository queue;
  late SavedSitesRepository saved;
  late BrowsingHistoryStore history;
  late LocalSettingsStore settings;
  late FakeBrowser browser;
  late Directory root;
  late FileStore store;
  var cookiesCleared = 0;

  setUp(() {
    repos = RepoHarness();
    db = repos.db;
    queue = SaveQueueRepository(db);
    saved = SavedSitesRepository(db);
    history = BrowsingHistoryStore(db);
    settings = LocalSettingsStore(db);
    browser = FakeBrowser();
    root = Directory.systemTemp.createTempSync('webread_reset');
    store = FileStore(root);
    cookiesCleared = 0;
  });

  tearDown(() async {
    await repos.close();
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  LocalResetService makeService({Future<void> Function()? cookies}) =>
      LocalResetService(
        db: db,
        fileStore: store,
        browser: browser,
        clearCookies:
            cookies ??
            () async {
              cookiesCleared++;
            },
      );

  Future<List<EntryRow>> entryRows() => db.select(db.entries).get();
  Future<List<CollectionRow>> collectionRows() =>
      db.select(db.collections).get();

  /// A device that has been used: a collection, an entry with files on disk,
  /// reading progress, a queued task, a saved rule and a setting.
  Future<void> seedUsedApp() async {
    final seeded = await repos.seedLibrary();
    await repos.reading.markRead(seeded.entry.id);
    await repos.offline.recordCopy(
      entryId: seeded.entry.id,
      locationUrl: seeded.location.url,
      artifactFormat: 'imageSequence',
      contentPath: 'library/collection-1/entries/c1',
      byteSize: 64,
    );
    await settings.set(ForegroundMultitasking.settingKey, 'true');
    await queue.enqueue(
      entryId: seeded.entry.id,
      locationUrl: 'https://x.example/guide/foo/2',
    );
    await saved.save(url: 'https://x.example/guide/foo', title: 'Foo');
    await history.recordVisit(
      landedUrl: 'https://x.example/guide/foo/1',
      title: 'Entry 1',
      userInitiated: true,
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
    expect(await entryRows(), isNotEmpty);

    final report = await makeService().resetEverything();

    expect(report.ok, isTrue, reason: report.toString());
    expect(await entryRows(), isEmpty);
    expect(await collectionRows(), isEmpty);
    expect(await queue.watch().first, isEmpty);
    expect(await settings.get(ForegroundMultitasking.settingKey), isNull);
  });

  test('every table is emptied, discovered from the schema', () async {
    await seedUsedApp();
    await makeService().resetEverything();

    // Every table, with nothing exempted: V2 seeds nothing on create, so a
    // reset device holds no row it did not put there itself.
    for (final table in db.allTables) {
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
      await saved.all(),
      isEmpty,
      reason: 'a reset must not put a developer-chosen site back',
    );
    // Nothing the user set survives either.
    expect(await settings.get(ForegroundMultitasking.settingKey), isNull);
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
    expect(await entryRows(), isEmpty);
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
    expect(await entryRows(), isEmpty);
  });
}
