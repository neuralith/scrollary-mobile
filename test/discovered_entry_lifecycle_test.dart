import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_reader/browser/page_data.dart';
import 'package:web_reader/features/library_check_ui.dart'
    show libraryCheckResultLines;
import 'package:web_reader/library/library_check.dart';
import 'package:web_reader/library/update_checker.dart';
import 'package:web_reader/queue/task_queue.dart';
import 'package:web_reader/save/save_run.dart';
import 'package:web_reader/core/config.dart' show SaveScope;
import 'package:web_reader/storage/database.dart';
import 'package:web_reader/storage/file_store.dart';

import 'helpers/fake_browser.dart';

/// The rest of a discovered entry's life: seen again, given up on, saved and
/// failed, or forgotten on purpose.
///
/// A `knownRemote` row is the one thing in this library the app made up rather
/// than the user asking for it, and these are the four things that can happen
/// to it short of being saved. Each has the same shape: the app may change what
/// it *said about the source*, and may never change what the user has.
void main() {
  late AppDatabase db;
  late FakeBrowser browser;
  late UpdateChecker checker;
  late Directory root;

  const host = 'https://x.example';
  String entryUrl(int n) => '$host/guide/foo/$n';
  const collectionIndexUrl = '$host/guide/foo';

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    browser = FakeBrowser();
    root = Directory.systemTemp.createTempSync('webread_lifecycle');
    checker = UpdateChecker(
      browser: browser,
      db: db,
      config: const UpdateCheckConfig(cooldownBetweenPages: Duration.zero),
    );
  });

  tearDown(() async {
    await db.close();
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  Future<void> seedCollection({String? withCollectionUrl}) =>
      db.upsertCollection(
        Collection(
          contentKind: 'unknownWebContent',
          sequenceKind: 'none',
          orderingBasis: 'discoveryOrder',
          shapeConfidence: 'low',
          lifecycle: 'active',
          id: 'collection-1',
          title: 'Foo',
          sourceUrl: collectionIndexUrl,
          host: 'x.example',
          collectionKey: '/guide/foo',
          collectionIndexUrl: withCollectionUrl,
          createdAt: DateTime(2026, 7, 1),
        ),
      );

  Future<void> seedCaptured(int n, {String status = 'complete'}) =>
      db.upsertEntry(
        Entry(
          host: 'x.example',
          contentKind: 'unknownWebContent',
          contentKindConfidence: 'low',
          contentKindIsUserSet: false,
          id: 'ch$n',
          collectionId: 'collection-1',
          title: 'Foo Entry $n',
          sourceUrl: entryUrl(n),
          urlKey: entryUrl(n),
          artifactFormat: 'imageSequence',
          captureMode: 'imageSequence',
          saveStatus: status,
          contentPath: 'library/collection-1/entries/ch$n',
          savedAt: DateTime(2026, 7, 10),
          detectedAssetCount: 3,
          storedAssetCount: status == 'partial' ? 1 : 3,
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

  Future<void> seedDiscovered(
    int n, {
    String? title,
    double? number,
    String basis = 'entryList',
    String confidence = 'high',
    String? nextSourceUrl,
    String? saveError,
  }) => db.upsertEntry(
    Entry(
      host: 'x.example',
      contentKind: 'unknownWebContent',
      contentKindConfidence: 'low',
      contentKindIsUserSet: false,
      id: 'known$n',
      collectionId: 'collection-1',
      title: title ?? 'Foo Entry $n',
      sourceUrl: entryUrl(n),
      urlKey: entryUrl(n),
      artifactFormat: 'imageSequence',
      saveStatus: 'knownRemote',
      detectedAssetCount: 0,
      storedAssetCount: 0,
      nextSourceUrl: nextSourceUrl,
      entryOrder: n,
      byteSize: 0,
      entryNumber: number ?? n.toDouble(),
      sourceMarker: 'Entry $n',
      saveError: saveError,
      readStatus: 'unread',
      progressFraction: 0,
      progressPageIndex: 0,
      progressOffsetInPage: 0,
      discoveredAt: DateTime(2026, 7, 20),
      discoveryBasis: basis,
      discoveryConfidence: confidence,
    ),
  );

  Future<void> seedQueueTask({
    required String taskType,
    required String state,
    String? startUrl,
    String? collectionId = 'collection-1',
  }) => db.upsertQueueTask(
    QueueTask(
      id: 'task-$taskType-${startUrl ?? collectionId}',
      taskType: taskType,
      collectionId: collectionId,
      startUrl: startUrl,
      entryLimit: taskType == 'sequenceSave' ? 10 : 1,
      captureModeIsUserSet: false,
      state: state,
      origin: 'queue',
      orderIndex: 1,
      queuedAt: DateTime(2026, 7, 21),
    ),
  );

  void serveList(List<PageLink> links) => browser.addPage(
    collectionIndexUrl,
    PageProbe(
      url: collectionIndexUrl,
      title: 'Foo — all entries',
      readyState: 'complete',
      documentHeight: 2000,
      viewportHeight: 800,
      links: links,
    ),
  );

  void serveNumbered(List<int> numbers, {String Function(int)? label}) =>
      serveList([
        for (final n in numbers)
          PageLink(
            href: '/guide/foo/$n',
            text: label == null ? 'Entry $n' : label(n),
          ),
      ]);

  Future<Entry?> row(String id) => db.entryById(id);

  // --- 1. seen again --------------------------------------------------------

  group('a discovered entry seen again', () {
    test('takes the source\'s corrected label', () async {
      await seedCollection(withCollectionUrl: collectionIndexUrl);
      await seedCaptured(100);
      await seedDiscovered(101, title: 'Entry 101 (draft)');
      serveNumbered([103, 102, 101, 100]);

      await checker.check('collection-1');

      final refreshed = (await row('known101'))!;
      expect(refreshed.title, 'Entry 101');
      expect(
        refreshed.sourceMarker,
        'Entry 101',
        reason: 'the marker is derived from the label it was read with',
      );
    });

    test('is not counted as a discovery', () async {
      await seedCollection(withCollectionUrl: collectionIndexUrl);
      await seedCaptured(100);
      await seedDiscovered(101, title: 'Entry 101 (draft)');
      serveNumbered([102, 101, 100]);

      final outcome = await checker.check('collection-1');

      expect(
        outcome.newEntries,
        1,
        reason: '102 is new; 101 was refreshed, which is not a finding',
      );
    });

    test('fills in a number it did not have, and keeps one it did', () async {
      await seedCollection(withCollectionUrl: collectionIndexUrl);
      await seedCaptured(100);
      // 101 was found by a chain walk that read no number off its page; 102
      // carries a number this app has already ordered the collection by.
      await seedDiscovered(101);
      await db.upsertEntry(
        (await row('known101'))!.copyWith(entryNumber: const Value(null)),
      );
      await seedDiscovered(102, number: 999);
      serveNumbered([102, 101, 100]);

      await checker.check('collection-1');

      expect(
        (await row('known101'))!.entryNumber,
        101,
        reason: 'a null number is a gap the source can fill',
      );
      expect(
        (await row('known102'))!.entryNumber,
        999,
        reason: 'a stored number orders the collection — never overwritten',
      );
    });

    test('upgrades weak provenance, never downgrades strong', () async {
      await seedCollection(withCollectionUrl: collectionIndexUrl);
      await seedCaptured(100);
      await seedDiscovered(101, basis: 'nextChain', confidence: 'low');
      await seedDiscovered(102, basis: 'entryList', confidence: 'high');
      serveNumbered([102, 101, 100]);

      await checker.check('collection-1');

      final upgraded = (await row('known101'))!;
      expect(upgraded.discoveryBasis, 'entryList');
      expect(upgraded.discoveryConfidence, 'high');
      final unchanged = (await row('known102'))!;
      expect(unchanged.discoveryBasis, 'entryList');
      expect(unchanged.discoveryConfidence, 'high');
    });

    test('leaves the discovery time alone', () async {
      // What a run's report counts to answer "what did this check find". Move
      // it on a re-sighting and every entry the source still lists reads as
      // newly discovered.
      await seedCollection(withCollectionUrl: collectionIndexUrl);
      await seedCaptured(100);
      await seedDiscovered(101, title: 'Entry 101 (draft)');
      serveNumbered([102, 101, 100]);

      await checker.check('collection-1');

      expect((await row('known101'))!.discoveredAt, DateTime(2026, 7, 20));
    });

    test('cannot touch an entry that has since been saved', () async {
      await seedCollection(withCollectionUrl: collectionIndexUrl);
      await seedCaptured(100);
      await seedCaptured(101);
      serveNumbered([102, 101, 100], label: (n) => 'Entry $n — REPRINT');

      await checker.check('collection-1');

      final captured = (await row('ch101'))!;
      expect(captured.title, 'Foo Entry 101');
      expect(captured.sourceMarker, 'Entry 101');
      expect(captured.contentPath, isNotNull);
      expect(captured.byteSize, 128);
      expect(captured.saveStatus, 'complete');
    });

    test('cannot touch reading state, or a row that carries any', () async {
      await seedCollection(withCollectionUrl: collectionIndexUrl);
      await seedCaptured(100);
      await seedDiscovered(101, title: 'Entry 101 (draft)');
      await db.writeEntryReading(
        'known101',
        EntriesCompanion(
          readStatus: const Value('reading'),
          progressFraction: const Value(0.5),
          lastReadAt: Value(DateTime(2026, 7, 22)),
        ),
      );
      serveNumbered([102, 101, 100]);

      await checker.check('collection-1');

      final untouched = (await row('known101'))!;
      expect(untouched.title, 'Entry 101 (draft)');
      expect(untouched.readStatus, 'reading');
      expect(untouched.progressFraction, 0.5);
    });

    test('a contradicted reading refreshes nothing at all', () async {
      // The label/metadata weld: the checker refuses the whole page rather
      // than writing — and a refusal must not leak through the refresh path
      // either.
      await seedCollection(withCollectionUrl: collectionIndexUrl);
      await seedCaptured(100);
      await seedDiscovered(102);
      serveList(const [
        PageLink(href: '/guide/foo/104', text: 'Entry 1046 days ago'),
        PageLink(href: '/guide/foo/103', text: 'Entry 103last week'),
        PageLink(href: '/guide/foo/102', text: 'Entry 1022 weeks ago'),
        PageLink(href: '/guide/foo/100', text: 'Entry 1003 weeks ago'),
      ]);

      final outcome = await checker.check('collection-1');

      expect(outcome.stoppedOnEntryIdentity, isTrue);
      final kept = (await row('known102'))!;
      expect(kept.title, 'Foo Entry 102');
      expect(kept.entryNumber, 102);
    });

    test(
      'fills a missing next address without replacing a known one',
      () async {
        await seedCollection(withCollectionUrl: collectionIndexUrl);
        await seedCaptured(100);
        await seedDiscovered(101, nextSourceUrl: entryUrl(102));

        final wrote = await db.refreshDiscoveredEntry(
          id: 'known101',
          title: 'Foo Entry 101',
          number: 101,
          sourceMarker: 'Entry 101',
          basis: 'entryList',
          confidence: 'high',
          nextSourceUrl: '$host/guide/foo/999',
        );

        expect(wrote, isEmpty);
        expect((await row('known101'))!.nextSourceUrl, entryUrl(102));
      },
    );
  });

  // --- 2. forgotten on purpose ---------------------------------------------

  group('forgetting an entry', () {
    test('removes a discovered row that nothing is waiting on', () async {
      await seedCollection();
      await seedCaptured(100);
      await seedDiscovered(101);

      expect(
        await db.forgetDiscoveredEntry('known101'),
        ForgetDiscoveryResult.forgotten,
      );
      expect(await row('known101'), isNull);
      expect((await row('ch100'))!.contentPath, isNotNull);
    });

    test('takes it out of what the source is said to have', () async {
      await seedCollection();
      await seedCaptured(100);
      await seedDiscovered(101);
      await seedDiscovered(102);

      await db.forgetDiscoveredEntry('known101');

      final remaining = (await db.entriesForCollection(
        'collection-1',
      )).where((e) => e.saveStatus == 'knownRemote').toList();
      expect(remaining.map((e) => e.entryNumber), [102.0]);
    });

    test('refuses a captured entry', () async {
      await seedCollection();
      await seedCaptured(100);

      expect(
        await db.forgetDiscoveredEntry('ch100'),
        ForgetDiscoveryResult.notADiscovery,
      );
      expect(await row('ch100'), isNotNull);
    });

    test('refuses a partial entry', () async {
      await seedCollection();
      await seedCaptured(100, status: 'partial');

      expect(
        await db.forgetDiscoveredEntry('ch100'),
        ForgetDiscoveryResult.notADiscovery,
      );
      expect((await row('ch100'))!.contentPath, isNotNull);
    });

    test('refuses one carrying reading state', () async {
      await seedCollection();
      await seedDiscovered(101);
      await db.writeEntryReading(
        'known101',
        EntriesCompanion(
          readStatus: const Value('reading'),
          progressFraction: const Value(0.3),
        ),
      );

      expect(
        await db.forgetDiscoveredEntry('known101'),
        ForgetDiscoveryResult.notADiscovery,
      );
      expect(await row('known101'), isNotNull);
    });

    test('refuses one with a queued save, and says so', () async {
      await seedCollection();
      await seedDiscovered(101);
      await seedQueueTask(
        taskType: 'entrySave',
        state: 'queued',
        startUrl: entryUrl(101),
      );

      final result = await db.forgetDiscoveredEntry('known101');

      expect(result, ForgetDiscoveryResult.claimedByQueue);
      expect(result.refusal, contains('waiting to be saved'));
      expect(await row('known101'), isNotNull);
    });

    test('refuses one with a running save', () async {
      await seedCollection();
      await seedDiscovered(101);
      await seedQueueTask(
        taskType: 'entrySave',
        state: 'running',
        startUrl: entryUrl(101),
      );

      expect(
        await db.forgetDiscoveredEntry('known101'),
        ForgetDiscoveryResult.claimedByQueue,
      );
      expect(await row('known101'), isNotNull);
    });

    test(
      'refuses while a multi-entry save is loose in the collection',
      () async {
        await seedCollection();
        await seedDiscovered(101);
        await seedQueueTask(
          taskType: 'sequenceSave',
          state: 'queued',
          startUrl: entryUrl(90),
        );

        expect(
          await db.forgetDiscoveredEntry('known101'),
          ForgetDiscoveryResult.claimedByQueue,
        );
      },
    );

    test('allows it again once that save is over', () async {
      await seedCollection();
      await seedDiscovered(101);
      await seedQueueTask(
        taskType: 'entrySave',
        state: 'queued',
        startUrl: entryUrl(101),
      );
      await db.updateQueueTaskIfState(
        id: 'task-entrySave-${entryUrl(101)}',
        expected: const ['queued'],
        values: const QueueTasksCompanion(state: Value('failed')),
      );

      expect(
        await db.forgetDiscoveredEntry('known101'),
        ForgetDiscoveryResult.forgotten,
      );
    });

    test('says nothing about a row that is already gone', () async {
      expect(
        await db.forgetDiscoveredEntry('no-such-entry'),
        ForgetDiscoveryResult.missing,
      );
      expect(ForgetDiscoveryResult.missing.refusal, isNull);
      expect(ForgetDiscoveryResult.forgotten.refusal, isNull);
    });
  });

  // --- 3. reporting ---------------------------------------------------------

  group('what a run reports', () {
    LibraryCheckReport report({
      required int found,
      required Map<String, int> removed,
      String result = 'updatesAvailable',
    }) {
      final startedAt = DateTime(2026, 8, 1, 12);
      return computeLibraryCheckReport(
        plan: LibraryCheckPlan(
          startedAt: startedAt,
          collectionIds: const ['collection-1'],
          taskIds: const ['task-1'],
        ),
        tasks: [
          QueueTask(
            id: 'task-1',
            taskType: 'collectionCheck',
            collectionId: 'collection-1',
            captureModeIsUserSet: false,
            state: 'completed',
            origin: 'queue',
            orderIndex: 0,
            queuedAt: startedAt,
          ),
        ],
        collections: [
          Collection(
            contentKind: 'unknownWebContent',
            sequenceKind: 'none',
            orderingBasis: 'discoveryOrder',
            shapeConfidence: 'low',
            lifecycle: 'active',
            id: 'collection-1',
            title: 'Foo',
            sourceUrl: collectionIndexUrl,
            host: 'x.example',
            createdAt: DateTime(2026, 7, 1),
            lastCheckAt: startedAt.add(const Duration(seconds: 5)),
            lastCheckResult: result,
          ),
        ],
        entries: [
          for (var i = 0; i < found; i++)
            Entry(
              host: 'x.example',
              contentKind: 'unknownWebContent',
              contentKindConfidence: 'low',
              contentKindIsUserSet: false,
              id: 'new$i',
              collectionId: 'collection-1',
              title: 'Foo Entry $i',
              sourceUrl: entryUrl(i),
              urlKey: entryUrl(i),
              artifactFormat: 'imageSequence',
              saveStatus: 'knownRemote',
              detectedAssetCount: 0,
              storedAssetCount: 0,
              entryOrder: i,
              byteSize: 0,
              readStatus: 'unread',
              progressFraction: 0,
              progressPageIndex: 0,
              progressOffsetInPage: 0,
              discoveredAt: startedAt.add(const Duration(seconds: 5)),
            ),
        ],
        staleRemoved: removed,
      );
    }

    test('nothing removed says nothing about removals', () {
      final r = report(found: 2, removed: const {});

      expect(r.staleRemovedCount, 0);
      expect(r.lines.single.staleRemoved, 0);
      expect(
        libraryCheckResultLines(r).where((l) => l.contains('no longer')),
        isEmpty,
      );
    });

    test('one removal reads as one', () {
      final r = report(
        found: 0,
        removed: const {'collection-1': 1},
        result: 'upToDate',
      );

      expect(r.staleRemovedCount, 1);
      final lines = libraryCheckResultLines(r);
      expect(
        lines.singleWhere((l) => l.contains('no longer at the source')),
        '1 entry is no longer at the source and was taken off the list — '
        'none had been downloaded',
      );
    });

    test('several removals read as several', () {
      final r = report(
        found: 0,
        removed: const {'collection-1': 3},
        result: 'upToDate',
      );

      expect(
        libraryCheckResultLines(
          r,
        ).singleWhere((l) => l.contains('no longer at the source')),
        '3 entries are no longer at the source and were taken off the list — '
        'none had been downloaded',
      );
    });

    test('found and removed are never the same number', () {
      final r = report(found: 2, removed: const {'collection-1': 3});

      expect(r.newEntryCount, 2);
      expect(r.staleRemovedCount, 3);
      final lines = libraryCheckResultLines(r);
      expect(lines.any((l) => l.contains('2 new entries')), isTrue);
      expect(lines.any((l) => l.contains('3 entries are no longer')), isTrue);
      expect(
        lines.any((l) => l.contains('5')),
        isFalse,
        reason: 'the two are never added together',
      );
    });

    test('a collection this run never reached reports no removals', () {
      final r = computeLibraryCheckReport(
        plan: LibraryCheckPlan(
          startedAt: DateTime(2026, 8, 1, 12),
          collectionIds: const ['collection-1'],
          taskIds: const ['task-1'],
        ),
        tasks: const [],
        collections: const [],
        entries: const [],
        staleRemoved: const {'collection-1': 4},
      );

      expect(r.staleRemovedCount, 0);
    });

    test(
      'the checker records removals per collection for the session',
      () async {
        await seedCollection(withCollectionUrl: collectionIndexUrl);
        await seedCaptured(100);
        await seedDiscovered(101);
        serveNumbered([104, 103, 102, 100]);

        final outcome = await checker.check('collection-1');

        expect(outcome.staleRemoved, 1);
        expect(checker.staleRemovedFor('collection-1'), 1);
        expect(checker.staleRemovedByCollection, {'collection-1': 1});
        expect(checker.staleRemovedFor('collection-2'), 0);
      },
    );

    test('a later clean check for the same collection replaces it', () async {
      await seedCollection(withCollectionUrl: collectionIndexUrl);
      await seedCaptured(100);
      await seedDiscovered(101);
      serveNumbered([104, 103, 102, 100]);
      await checker.check('collection-1');
      expect(checker.staleRemovedFor('collection-1'), 1);

      await checker.check('collection-1');

      expect(checker.staleRemovedFor('collection-1'), 0);
    });
  });

  // --- 4. a save that failed ------------------------------------------------

  group('a discovered entry whose save failed', () {
    TaskQueueController queueWith(QueueOutcome Function(QueueTask) run) =>
        TaskQueueController(
          db: db,
          browser: browser,
          saveRun: SaveRunController(
            browser: browser,
            db: db,
            fileStore: FileStore(root),
          ),
          checker: checker,
          saveRunner: (task) async => run(task),
          checkRunner: (task) async => const QueueOutcome.success('done'),
        );

    Future<void> settle() =>
        Future<void>.delayed(const Duration(milliseconds: 150));

    test('is noted on the row, and not deleted', () async {
      await seedCollection();
      await seedDiscovered(101);
      final queue = queueWith(
        (_) => const QueueOutcome.failure('the page could not be opened'),
      );

      await queue.enqueueSave(startUrl: entryUrl(101), entryLimit: 1);
      await queue.startQueuedSaves();
      await settle();

      final kept = (await row('known101'))!;
      expect(kept.saveError, 'the page could not be opened');
      expect(
        kept.saveStatus,
        'knownRemote',
        reason: 'a failed attempt says nothing about what the source has',
      );
      expect(kept.contentPath, isNull);
    });

    test('is still a discovery, so it can still be forgotten', () async {
      await seedCollection();
      await seedDiscovered(101, saveError: 'timed out');

      expect(isDiscoveredOnlyEntry((await row('known101'))!), isTrue);
      expect(
        await db.forgetDiscoveredEntry('known101'),
        ForgetDiscoveryResult.forgotten,
      );
    });

    test('is left out of the next "save the new entries"', () async {
      // The action queues what the section offers, and the section offers what
      // has not already been tried — otherwise the same failing address is
      // re-queued on every press.
      await seedCollection();
      await seedDiscovered(101, saveError: 'the page could not be opened');
      await seedDiscovered(102);
      final queue = queueWith((_) => const QueueOutcome.success('1 saved'));

      final entries = (await db.entriesForCollection(
        'collection-1',
      )).where((e) => e.saveError == null).toList();
      final result = await queue.enqueueEntries(entries);

      expect(result.queuedIds, hasLength(1));
      final queued = await db.pendingQueueTasks();
      expect(queued.map((t) => t.startUrl), [entryUrl(102)]);
    });

    test('rejoins it when the user asks for that entry again', () async {
      await seedCollection();
      await seedDiscovered(101, saveError: 'timed out');

      await db.clearDiscoveryCaptureFailure('known101');

      expect((await row('known101'))!.saveError, isNull);
    });

    test('a successful save is never given a failure note', () async {
      await seedCollection();
      await seedDiscovered(101);
      final queue = queueWith((_) => const QueueOutcome.success('1 saved'));

      await queue.enqueueSave(startUrl: entryUrl(101), entryLimit: 1);
      await queue.startQueuedSaves();
      await settle();

      expect((await row('known101'))!.saveError, isNull);
    });

    test('a captured entry is never given one either', () async {
      await seedCollection();
      await seedCaptured(101);
      final queue = queueWith((_) => const QueueOutcome.failure('boom'));

      await queue.enqueueSave(startUrl: entryUrl(101), entryLimit: 1);
      await queue.startQueuedSaves();
      await settle();

      final captured = (await row('ch101'))!;
      expect(captured.saveError, isNull);
      expect(captured.saveStatus, 'complete');
      expect(captured.contentPath, isNotNull);
    });

    test('a multi-entry save that fails blames no single entry', () async {
      // A sequence save stops for reasons that belong to the run, not to the
      // entry it happened to start on.
      await seedCollection();
      await seedDiscovered(101);
      final queue = queueWith((_) => const QueueOutcome.failure('stopped'));

      await queue.enqueueSave(
        startUrl: entryUrl(101),
        entryLimit: 5,
        range: SaveScope.fixedCount,
      );
      await queue.startQueuedSaves();
      await settle();

      expect((await row('known101'))!.saveError, isNull);
    });
  });
}
