import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:web_reader/save/save_run.dart';
import 'package:web_reader/save/save_preflight.dart';
import 'package:web_reader/save/save_state.dart';
import 'package:web_reader/core/config.dart';
import 'package:web_reader/reading/reading_position.dart';
import 'package:web_reader/reading/reading_repository.dart';
import 'package:web_reader/storage/database.dart';
import 'package:web_reader/storage/file_store.dart';
import 'package:web_reader/storage/manifest.dart';

import 'package:drift/native.dart';

import '../tool/fixture/fixture_site.dart';
import 'helpers/fake_browser.dart';

/// Duplicates met DURING a running multi-entry session.
///
/// The whole loop runs for real — preflight, prompt, engine, downloads over a
/// local HTTP server, atomic replacement — only the WebView is faked.
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
    maxEntriesPerRun: 6,
    maxSkippedPerRun: 4,
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
    root = Directory.systemTemp.createTempSync('webread_session');
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

  /// Entry pages 1..[count]; each links rel=next to its successor.
  void servePages(int count) {
    for (var n = 1; n <= count; n++) {
      browser.addPage(
        entryUrl(n),
        entryProbe(
          url: entryUrl(n),
          title: 'Foo Entry $n',
          imageUrls: [for (var i = 1; i <= 3; i++) '$assetBase/img/$n/$i.png'],
          nextHref: n < count ? entryUrl(n + 1) : null,
        ),
      );
    }
  }

  Future<void> seedCollection() => db.upsertCollection(
    Collection(
      contentKind: 'unknownWebContent',
      sequenceKind: 'none',
      orderingBasis: 'discoveryOrder',
      shapeConfidence: 'low',
      lifecycle: 'active',
      id: 'collection-1',
      title: 'Foo',
      sourceUrl: '$host/guide/foo',
      host: 'x.example',
      collectionKey: '/guide/foo',
      createdAt: DateTime(2026, 7, 1),
    ),
  );

  /// A committed, complete (or partial) local entry with real files.
  Future<void> seedSaved(int n, {String status = 'complete'}) async {
    final id = 'c$n';
    final staging = await store.beginEntry(
      collectionId: 'collection-1',
      entryId: id,
    );
    await staging
        .assetFile('001.png')
        .writeAsBytes(panelPng(entry: n, index: 1));
    final relative = await store.commit(
      staging,
      EntryManifest(
        schemaVersion: 1,
        entryId: id,
        collectionId: 'collection-1',
        sourceUrl: entryUrl(n),
        title: 'Foo Entry $n',
        savedAt: DateTime(2026, 7, 10),
        status: status == 'partial' ? SaveStatus.partial : SaveStatus.complete,
        detectedAssetCount: 3,
        storedAssetCount: status == 'partial' ? 1 : 3,
        assets: const [],
      ),
    );
    await db.upsertEntry(
      Entry(
        host: '',
        contentKind: 'unknownWebContent',
        contentKindConfidence: 'low',
        contentKindIsUserSet: false,
        id: id,
        collectionId: 'collection-1',
        title: 'Foo Entry $n',
        sourceUrl: entryUrl(n),
        urlKey: entryUrl(n),
        artifactFormat: 'imageSequence',
        saveStatus: status,
        contentPath: relative,
        savedAt: DateTime(2026, 7, 10),
        detectedAssetCount: 3,
        storedAssetCount: status == 'partial' ? 1 : 3,
        nextSourceUrl: entryUrl(n + 1),
        entryOrder: n,
        byteSize: 128,
        entryNumber: n.toDouble(),
        sourceMarker: 'Entry $n',
        readStatus: 'unread',
        progressFraction: 0,
        progressPageIndex: 0,
        progressOffsetInPage: 0,
      ),
    );
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

  Future<void> awaitRun(
    Future<void> pending, {
    Duration timeout = const Duration(seconds: 60),
  }) => pending.timeout(timeout);

  test('a duplicate met after new saves pauses and asks', () async {
    await seedCollection();
    await seedSaved(2);
    servePages(3);
    browser.setUrl(entryUrl(1));

    var prompts = 0;
    final running = run.start(
      range: SaveScope.fixedCount,
      entryLimit: 2,
      captureModeIsUserSet: false,
      startUrl: entryUrl(1),
      policy: DuplicatePolicy.ask,
    );

    await until(() => run.pendingDuplicate != null);
    prompts++;
    final request = run.pendingDuplicate!;
    expect(request.state, EntryLocalState.complete);
    expect(request.entry!.id, 'c2');
    expect(
      request.availableActions,
      contains(DuplicateChoiceAction.redownload),
    );
    expect(
      request.availableActions,
      isNot(contains(DuplicateChoiceAction.retryMissing)),
      reason: 'a complete entry has no missing files to retry',
    );
    expect(
      run.progress.state,
      SaveState.awaitingSelection,
      reason: 'the run is holding, not downloading',
    );

    // Skip once, without making it a session policy.
    run.resolveDuplicate(const DuplicateChoice(DuplicateChoiceAction.skip));
    await awaitRun(running);

    expect(prompts, 1);
    expect(run.sessionDuplicateDecision, SessionDuplicateDecision.ask);
    final entries = await db.allEntries();
    expect(entries.length, 3, reason: 'ch1 + seeded ch2 + ch3');
    expect(
      entries.where((c) => c.urlKey == entryUrl(2)).single.savedAt,
      DateTime(2026, 7, 10),
      reason: 'the skipped entry was not touched',
    );
    expect(run.progress.storedEntries, 2, reason: 'requested 2 new, got 2');
    expect(run.progress.skippedEntries, 1);
  });

  test('"use this choice" skips every later complete duplicate', () async {
    await seedCollection();
    await seedSaved(2);
    await seedSaved(3);
    servePages(4);
    browser.setUrl(entryUrl(1));

    var prompts = 0;
    DuplicateRequest? lastPrompt;
    run.addListener(() {
      final pending = run.pendingDuplicate;
      if (pending != null && !identical(pending, lastPrompt)) {
        prompts++;
        lastPrompt = pending;
      }
    });

    final running = run.start(
      range: SaveScope.fixedCount,
      entryLimit: 2,
      captureModeIsUserSet: false,
      startUrl: entryUrl(1),
      policy: DuplicatePolicy.ask,
    );

    await until(() => run.pendingDuplicate != null);
    run.resolveDuplicate(
      const DuplicateChoice(DuplicateChoiceAction.skip, applyToSession: true),
    );
    await awaitRun(running);

    expect(prompts, 1, reason: 'entry 3 must not ask again');
    expect(
      run.sessionDuplicateDecision,
      SessionDuplicateDecision.skipCompleteForSession,
    );
    expect(run.progress.storedEntries, 2, reason: 'ch1 and ch4');
    expect(run.progress.skippedEntries, 2);
    expect((await db.allEntries()).length, 4);
  });

  test('re-download once replaces files but keeps reading progress', () async {
    await seedCollection();
    await seedSaved(2);
    servePages(2);
    final reading = ReadingRepository(db);
    await reading.saveProgress(
      'c2',
      const ReadingPosition(fraction: 0.6, anchorIndex: 1, offsetInAnchor: 0.3),
      completed: true,
    );
    final before = (await db.entryById('c2'))!;
    browser.setUrl(entryUrl(2));

    final running = run.start(
      range: SaveScope.fixedCount,
      entryLimit: 1,
      captureModeIsUserSet: false,
      startUrl: entryUrl(2),
      policy: DuplicatePolicy.ask,
    );
    await until(() => run.pendingDuplicate != null);
    run.resolveDuplicate(
      const DuplicateChoice(DuplicateChoiceAction.redownload),
    );
    await awaitRun(running);

    final rows = (await db.allEntries())
        .where((c) => c.urlKey == entryUrl(2))
        .toList();
    expect(rows, hasLength(1), reason: 'no duplicate row');
    final after = rows.single;
    expect(after.id, 'c2');
    expect(after.storedAssetCount, 3, reason: 'files genuinely re-fetched');
    expect(after.readStatus, 'completed');
    expect(after.progressPageIndex, 1);
    expect(after.completedAt, before.completedAt);
    expect(run.sessionDuplicateDecision, SessionDuplicateDecision.ask);
  });

  test('"use this choice" re-downloads every later duplicate', () async {
    await seedCollection();
    await seedSaved(1);
    await seedSaved(2);
    servePages(2);
    browser.setUrl(entryUrl(1));

    var prompts = 0;
    DuplicateRequest? lastPrompt;
    run.addListener(() {
      final pending = run.pendingDuplicate;
      if (pending != null && !identical(pending, lastPrompt)) {
        prompts++;
        lastPrompt = pending;
      }
    });

    final running = run.start(
      range: SaveScope.fixedCount,
      entryLimit: 2,
      captureModeIsUserSet: false,
      startUrl: entryUrl(1),
      policy: DuplicatePolicy.ask,
    );
    await until(() => run.pendingDuplicate != null);
    run.resolveDuplicate(
      const DuplicateChoice(
        DuplicateChoiceAction.redownload,
        applyToSession: true,
      ),
    );
    await awaitRun(running);

    expect(prompts, 1);
    expect(
      run.sessionDuplicateDecision,
      SessionDuplicateDecision.replaceCompleteForSession,
    );
    for (final c in await db.allEntries()) {
      expect(c.storedAssetCount, 3, reason: '${c.title} was re-saved');
    }
    expect((await db.allEntries()).length, 2, reason: 'still two rows');
  });

  test('Stop save ends the run cleanly and is never a policy', () async {
    await seedCollection();
    await seedSaved(1);
    servePages(2);
    browser.setUrl(entryUrl(1));

    final running = run.start(
      range: SaveScope.fixedCount,
      entryLimit: 2,
      captureModeIsUserSet: false,
      startUrl: entryUrl(1),
      policy: DuplicatePolicy.ask,
    );
    await until(() => run.pendingDuplicate != null);
    run.resolveDuplicate(
      const DuplicateChoice(
        DuplicateChoiceAction.stopSave,
        // Even asked-for, stop must not become a session decision.
        applyToSession: true,
      ),
    );
    await awaitRun(running);

    expect(run.progress.state, SaveState.cancelled);
    expect(run.progress.storedEntries, 0);
    expect(run.sessionDuplicateDecision, SessionDuplicateDecision.ask);
    expect(run.sessionPartialDecision, SessionPartialDecision.ask);
  });

  test('a partial entry offers repair choices, not complete ones', () async {
    await seedCollection();
    await seedSaved(2, status: 'partial');
    servePages(2);
    browser.setUrl(entryUrl(1));

    final running = run.start(
      range: SaveScope.fixedCount,
      entryLimit: 2,
      captureModeIsUserSet: false,
      startUrl: entryUrl(1),
      policy: DuplicatePolicy.ask,
    );
    await until(() => run.pendingDuplicate != null);
    final request = run.pendingDuplicate!;
    expect(request.state, EntryLocalState.partial);
    expect(
      request.availableActions,
      containsAll([
        DuplicateChoiceAction.retryMissing,
        DuplicateChoiceAction.restartEntry,
        DuplicateChoiceAction.skip,
        DuplicateChoiceAction.stopSave,
      ]),
    );
    expect(
      request.availableActions,
      isNot(contains(DuplicateChoiceAction.redownload)),
    );

    run.resolveDuplicate(
      const DuplicateChoice(DuplicateChoiceAction.retryMissing),
    );
    await awaitRun(running);

    final fixed = (await db.entryById('c2'))!;
    expect(fixed.saveStatus, 'complete');
    expect(fixed.storedAssetCount, 3);
  });

  test('session decisions survive an interrupted-run resume', () async {
    await seedCollection();
    await seedSaved(1);
    await seedSaved(2);
    servePages(3);
    browser.setUrl(entryUrl(1));

    // What an interrupted run that had answered "skip for session" leaves.
    await db.upsertRun(
      SaveRun(
        visitedCanonicals: '',
        origin: 'queue',
        scope: 'fixedCount',
        id: 'run-interrupted',
        captureModeIsUserSet: false,
        startUrl: entryUrl(1),
        currentUrl: entryUrl(1),
        requestedEntries: 1,
        completedEntries: 0,
        state: 'navigating',
        visitedUrls: '',
        duplicatePolicy: 'ask',
        sessionDuplicateDecision: 'skipCompleteForSession',
        sessionPartialDecision: 'ask',
        createdAt: DateTime(2026, 7, 27),
        updatedAt: DateTime(2026, 7, 27),
      ),
    );

    var prompted = false;
    run.addListener(() {
      if (run.pendingDuplicate != null) prompted = true;
    });

    final resumable = (await db.findResumableRun())!;
    await awaitRun(run.resumeRun(resumable));

    expect(prompted, isFalse, reason: 'the session already answered');
    expect(
      run.sessionDuplicateDecision,
      SessionDuplicateDecision.skipCompleteForSession,
    );
    expect(run.progress.storedEntries, 1, reason: 'ch3 saved');
    expect(run.progress.skippedEntries, 2);
  });

  test('a new run starts back at "ask"', () async {
    await seedCollection();
    servePages(1);
    browser.setUrl(entryUrl(1));

    await awaitRun(
      run.start(
        range: SaveScope.fixedCount,
        entryLimit: 1,
        captureModeIsUserSet: false,
        startUrl: entryUrl(1),
        policy: DuplicatePolicy.ask,
        sessionDuplicate: SessionDuplicateDecision.replaceCompleteForSession,
      ),
    );
    expect(
      run.sessionDuplicateDecision,
      SessionDuplicateDecision.replaceCompleteForSession,
    );

    // The next start resets: a session decision is not a preference.
    browser.setUrl(entryUrl(1));
    final running = run.start(
      range: SaveScope.fixedCount,
      entryLimit: 1,
      captureModeIsUserSet: false,
      startUrl: entryUrl(1),
      policy: DuplicatePolicy.ask,
    );
    await until(() => run.pendingDuplicate != null || !run.isRunning);
    expect(run.sessionDuplicateDecision, SessionDuplicateDecision.ask);
    if (run.pendingDuplicate != null) {
      run.resolveDuplicate(const DuplicateChoice(DuplicateChoiceAction.skip));
    }
    await awaitRun(running);
  });

  test('the requested count means new saves, and the report says so', () async {
    await seedCollection();
    await seedSaved(2);
    await seedSaved(3);
    servePages(4);
    browser.setUrl(entryUrl(1));

    await awaitRun(
      run.start(
        range: SaveScope.fixedCount,
        entryLimit: 2,
        captureModeIsUserSet: false,
        startUrl: entryUrl(1),
        policy: DuplicatePolicy.ask,
        sessionDuplicate: SessionDuplicateDecision.skipCompleteForSession,
      ),
    );

    expect(run.progress.storedEntries, 2, reason: 'ch1 and ch4 are new');
    expect(run.progress.skippedEntries, 2);
    expect(run.progress.requestedEntries, 2);
    expect(
      run.progress.message,
      allOf(
        contains('Requested 2 new'),
        contains('saved 2'),
        contains('skipped 2 existing'),
        contains('traversed 4'),
      ),
    );
  });

  test('skipping cannot become an unbounded crawl', () async {
    await seedCollection();
    for (var n = 1; n <= 6; n++) {
      await seedSaved(n);
    }
    servePages(6);
    browser.setUrl(entryUrl(1));

    await awaitRun(
      run.start(
        range: SaveScope.fixedCount,
        entryLimit: 1,
        captureModeIsUserSet: false,
        startUrl: entryUrl(1),
        policy: DuplicatePolicy.ask,
        sessionDuplicate: SessionDuplicateDecision.skipCompleteForSession,
      ),
    );

    expect(run.progress.storedEntries, 0);
    expect(
      run.progress.skippedEntries,
      config.maxSkippedPerRun,
      reason: 'the skip bound ends the walk',
    );
    expect(
      run.log.join('\n'),
      contains('stopping rather than walking further'),
    );
  });
}
