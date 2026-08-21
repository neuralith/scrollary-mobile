import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_reader/browser/page_data.dart';
import 'package:web_reader/features/library_formats.dart'
    show LibraryCollection;
import 'package:web_reader/library/update_checker.dart';
import 'package:web_reader/storage/database.dart';

import 'helpers/fake_browser.dart';

/// Reconciliation: a check may **withdraw** a discovery it made earlier.
///
/// A `knownRemote` row is a claim about somebody else's site, not something the
/// user has. When a later reading of that site can vouch for the stretch of the
/// collection the row sits in, and the row is not in it, the claim was wrong and
/// the row goes.
///
/// Everything in this file is about the two halves of that sentence being load
/// bearing: *can vouch for* (the observed window) and *not something the user
/// has* (captured, partial, queued, read). A test that only proved rows can be
/// deleted would be testing the easy half.
void main() {
  late AppDatabase db;
  late FakeBrowser browser;
  late UpdateChecker checker;

  const host = 'https://x.example';
  String entryUrl(int n) => '$host/guide/foo/$n';
  const collectionIndexUrl = '$host/guide/foo';

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    browser = FakeBrowser();
    checker = UpdateChecker(
      browser: browser,
      db: db,
      config: const UpdateCheckConfig(cooldownBetweenPages: Duration.zero),
    );
  });

  tearDown(() => db.close());

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

  /// An entry the user holds: files on disk, bytes counted, a save behind it.
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

  /// An entry only ever seen at the source — what reconciliation may retract.
  Future<void> seedDiscovered(int n) => db.upsertEntry(
    Entry(
      host: 'x.example',
      contentKind: 'unknownWebContent',
      contentKindConfidence: 'low',
      contentKindIsUserSet: false,
      id: 'known$n',
      collectionId: 'collection-1',
      title: 'Foo Entry $n',
      sourceUrl: entryUrl(n),
      urlKey: entryUrl(n),
      artifactFormat: 'imageSequence',
      saveStatus: 'knownRemote',
      contentPath: null,
      savedAt: null,
      detectedAssetCount: 0,
      storedAssetCount: 0,
      entryOrder: n,
      byteSize: 0,
      entryNumber: n.toDouble(),
      sourceMarker: 'Entry $n',
      readStatus: 'unread',
      progressFraction: 0,
      progressPageIndex: 0,
      progressOffsetInPage: 0,
      discoveredAt: DateTime(2026, 7, 20),
      discoveryBasis: 'entryList',
      discoveryConfidence: 'high',
    ),
  );

  Future<void> seedQueueTask({
    required String taskType,
    required String state,
    String? startUrl,
    String? collectionId = 'collection-1',
  }) => db.upsertQueueTask(
    QueueTask(
      id: 'task-$taskType-${startUrl ?? collectionId}-$state',
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

  void serveList(List<int> numbers, {String? at}) => browser.addPage(
    at ?? collectionIndexUrl,
    PageProbe(
      url: at ?? collectionIndexUrl,
      title: 'Foo — all entries',
      readyState: 'complete',
      documentHeight: 2000,
      viewportHeight: 800,
      links: [
        for (final n in numbers)
          PageLink(href: '/guide/foo/$n', text: 'Entry $n'),
      ],
    ),
  );

  Future<List<Entry>> rows() => db.entriesForCollection('collection-1');
  Future<List<double?>> numbersWithStatus(String status) async =>
      (await rows())
          .where((e) => e.saveStatus == status)
          .map((e) => e.entryNumber)
          .toList()
        ..sort((a, b) => (a ?? 0).compareTo(b ?? 0));

  group('a discovery the source has withdrawn', () {
    test('is removed, while everything around it is left alone', () async {
      await seedCollection(withCollectionUrl: collectionIndexUrl);
      await seedCaptured(100);
      serveList([103, 102, 101, 100]);

      final first = await checker.check('collection-1');
      expect(first.state, UpdateCheckState.updatesAvailable);
      expect(first.newEntries, 3);
      expect(first.staleRemoved, 0);
      expect(await numbersWithStatus('knownRemote'), [101.0, 102.0, 103.0]);

      // The source withdraws 101 and publishes 104. It still lists 100 — which
      // is what puts 101 inside a stretch this reading can speak for.
      serveList([104, 103, 102, 100]);
      final second = await checker.check('collection-1');

      expect(second.state, UpdateCheckState.updatesAvailable);
      expect(second.staleRemoved, 1);
      expect(second.newEntries, 1, reason: '104, and only 104');
      expect(await numbersWithStatus('knownRemote'), [102.0, 103.0, 104.0]);

      final captured = (await rows()).singleWhere((e) => e.entryNumber == 100);
      expect(captured.saveStatus, 'complete');
      expect(captured.contentPath, 'library/collection-1/entries/ch100');
      expect(captured.byteSize, 128);
      expect(captured.savedAt, isNotNull);
    });

    test('stops being offered as fetchable', () async {
      await seedCollection(withCollectionUrl: collectionIndexUrl);
      await seedCaptured(100);
      serveList([103, 102, 101, 100]);
      await checker.check('collection-1');

      serveList([104, 103, 102, 100]);
      await checker.check('collection-1');

      // The surfaces that offer a save — the "found at the source" count, the
      // remote list and the batch "Save new entries" call — all read this one
      // set, so the row being gone is the whole of the answer.
      final group = LibraryCollection(
        collection: await db.collectionById('collection-1'),
        entries: await rows(),
      );
      expect(group.knownRemoteCount, 3);
      expect(group.knownRemoteEntries.map((e) => e.entryNumber), [
        102.0,
        103.0,
        104.0,
      ]);
      expect(
        group.knownRemoteEntries.map((e) => e.sourceUrl),
        isNot(contains(entryUrl(101))),
      );
      expect(group.entryCount, 1, reason: 'the captured entry, unchanged');
    });
  });

  group('what reconciliation may never touch', () {
    test('a captured entry the source stopped listing stays', () async {
      await seedCollection(withCollectionUrl: collectionIndexUrl);
      await seedCaptured(100);
      serveList([103, 102, 101, 100]);
      await checker.check('collection-1');

      // The user saves 101. A save fills in the row the discovery created — it
      // never makes a second one — so this is that row, promoted.
      final discovered = (await rows()).singleWhere(
        (e) => e.entryNumber == 101,
      );
      await db.upsertEntry(
        discovered.copyWith(
          saveStatus: 'complete',
          contentPath: const Value('library/collection-1/entries/known101'),
          savedAt: Value(DateTime(2026, 7, 25)),
          captureMode: const Value('imageSequence'),
          storedAssetCount: 3,
          detectedAssetCount: 3,
          byteSize: 128,
        ),
      );
      serveList([104, 103, 102, 100]);
      final outcome = await checker.check('collection-1');

      final kept = (await rows()).singleWhere((e) => e.entryNumber == 101);
      expect(kept.saveStatus, 'complete');
      expect(kept.contentPath, isNotNull);
      expect(kept.byteSize, 128);
      expect(kept.storedAssetCount, 3);
      expect(outcome.staleRemoved, 0);
    });

    test('a partial entry stays', () async {
      await seedCollection(withCollectionUrl: collectionIndexUrl);
      await seedCaptured(100);
      await seedCaptured(101, status: 'partial');
      await seedDiscovered(102);
      serveList([104, 103, 102, 100]);

      final outcome = await checker.check('collection-1');

      final kept = (await rows()).singleWhere((e) => e.entryNumber == 101);
      expect(kept.saveStatus, 'partial');
      expect(kept.contentPath, isNotNull);
      expect(outcome.staleRemoved, 0);
    });

    test('a discovery with reading state on it stays', () async {
      // Defence in depth. Nothing today can open a `knownRemote` row, so a row
      // carrying both is already contradictory — and a contradictory row is
      // exactly the one not to delete on the strength of its status column.
      await seedCollection(withCollectionUrl: collectionIndexUrl);
      await seedCaptured(100);
      await seedDiscovered(101);
      await db.writeEntryReading(
        'known101',
        EntriesCompanion(
          readStatus: const Value('reading'),
          progressFraction: const Value(0.4),
          lastReadAt: Value(DateTime(2026, 7, 22)),
        ),
      );
      serveList([104, 103, 102, 100]);

      final outcome = await checker.check('collection-1');

      expect((await rows()).any((e) => e.entryNumber == 101), isTrue);
      expect(outcome.staleRemoved, 0);
    });

    test('an entry with a queued save stays until that save is over', () async {
      await seedCollection(withCollectionUrl: collectionIndexUrl);
      await seedCaptured(100);
      await seedDiscovered(101);
      await seedDiscovered(102);
      await seedQueueTask(
        taskType: 'entrySave',
        state: 'queued',
        startUrl: entryUrl(101),
      );
      // The source lists neither 101 nor 102.
      serveList([105, 104, 103, 100]);

      final first = await checker.check('collection-1');
      expect(
        first.staleRemoved,
        1,
        reason: '102 goes; 101 is work the user asked for',
      );
      expect((await rows()).any((e) => e.entryNumber == 101), isTrue);

      // The save finished (or failed) and the row is history. Nothing is
      // waiting on 101 any more, so the next check may retract it.
      await db.updateQueueTaskIfState(
        id: 'task-entrySave-${entryUrl(101)}-queued',
        expected: const ['queued'],
        values: const QueueTasksCompanion(state: Value('completed')),
      );
      final second = await checker.check('collection-1');

      expect(second.staleRemoved, 1);
      expect((await rows()).any((e) => e.entryNumber == 101), isFalse);
    });

    test('a running save protects its entry too', () async {
      await seedCollection(withCollectionUrl: collectionIndexUrl);
      await seedCaptured(100);
      await seedDiscovered(101);
      await seedQueueTask(
        taskType: 'entrySave',
        state: 'running',
        startUrl: entryUrl(101),
      );
      serveList([105, 104, 103, 100]);

      final outcome = await checker.check('collection-1');

      expect(outcome.staleRemoved, 0);
      expect((await rows()).any((e) => e.entryNumber == 101), isTrue);
    });

    test('a pending multi-entry save stops reconciliation for the whole '
        'collection', () async {
      // Where a sequence save will *reach* is not knowable from its row, so
      // nothing in the collection is retracted while one is outstanding.
      await seedCollection(withCollectionUrl: collectionIndexUrl);
      await seedCaptured(100);
      await seedDiscovered(101);
      await seedDiscovered(102);
      await seedQueueTask(
        taskType: 'sequenceSave',
        state: 'queued',
        startUrl: entryUrl(100),
      );
      serveList([105, 104, 103, 100]);

      final outcome = await checker.check('collection-1');

      expect(outcome.staleRemoved, 0);
      expect(await numbersWithStatus('knownRemote'), [
        101.0,
        102.0,
        103.0,
        104.0,
        105.0,
      ]);
    });
  });

  group('the observed window', () {
    test('an entry below what the page covered is kept', () async {
      await seedCollection(withCollectionUrl: collectionIndexUrl);
      await seedCaptured(200);
      await seedDiscovered(150); // from an older, deeper reading
      await seedDiscovered(205);
      await seedDiscovered(207);
      // One page of a paginated list: it reaches back to 200 and no further.
      serveList([220, 215, 210, 205, 200]);

      final outcome = await checker.check('collection-1');

      expect(
        (await rows()).any((e) => e.entryNumber == 150),
        isTrue,
        reason: 'a page that never covered 150 says nothing about it',
      );
      expect(
        (await rows()).any((e) => e.entryNumber == 207),
        isFalse,
        reason: '207 sits inside the covered stretch and was not on it',
      );
      expect(outcome.staleRemoved, 1);
      expect(outcome.newEntries, 3, reason: '210, 215, 220');
    });

    test(
      'an oldest-first list cannot rule out anything above its top',
      () async {
        await seedCollection(withCollectionUrl: collectionIndexUrl);
        await seedCaptured(100);
        await seedDiscovered(102);
        await seedDiscovered(400);
        serveList([100, 101, 103]); // ascending: page 1 of an oldest-first list

        final outcome = await checker.check('collection-1');

        expect(
          (await rows()).any((e) => e.entryNumber == 102),
          isFalse,
          reason: 'inside [100, 103] and absent from a complete reading of it',
        );
        expect(
          (await rows()).any((e) => e.entryNumber == 400),
          isTrue,
          reason: 'later pages of an oldest-first list are where 400 would be',
        );
        expect(outcome.staleRemoved, 1);
      },
    );

    test('a captured entry above the list withdraws the open ceiling', () async {
      // A newest-first list may normally be trusted to have the newest entry at
      // its top. An entry whose bytes are on this device, above that top, is
      // the library saying otherwise — so the ceiling closes.
      await seedCollection(withCollectionUrl: collectionIndexUrl);
      await seedCaptured(100);
      await seedCaptured(500);
      await seedDiscovered(400);
      serveList([104, 103, 102, 101, 100]);

      final outcome = await checker.check('collection-1');

      expect((await rows()).any((e) => e.entryNumber == 400), isTrue);
      expect(outcome.staleRemoved, 0);
    });

    test('an unnumbered discovery is never retracted', () async {
      await seedCollection(withCollectionUrl: collectionIndexUrl);
      await seedCaptured(100);
      await db.upsertEntry(
        Entry(
          host: 'x.example',
          contentKind: 'unknownWebContent',
          contentKindConfidence: 'low',
          contentKindIsUserSet: false,
          id: 'known-extra',
          collectionId: 'collection-1',
          title: 'Side Story',
          sourceUrl: '$host/guide/foo/side-story',
          urlKey: '$host/guide/foo/side-story',
          artifactFormat: 'imageSequence',
          saveStatus: 'knownRemote',
          detectedAssetCount: 0,
          storedAssetCount: 0,
          entryOrder: 101,
          byteSize: 0,
          entryNumber: null,
          readStatus: 'unread',
          progressFraction: 0,
          progressPageIndex: 0,
          progressOffsetInPage: 0,
          discoveredAt: DateTime(2026, 7, 20),
          discoveryBasis: 'entryList',
          discoveryConfidence: 'high',
        ),
      );
      serveList([104, 103, 102, 101, 100]);

      final outcome = await checker.check('collection-1');

      expect(
        (await rows()).any((e) => e.id == 'known-extra'),
        isTrue,
        reason: 'no number, no position, nothing to prove absence against',
      );
      expect(outcome.staleRemoved, 0);
    });
  });

  group('checks that may not conclude anything about absence', () {
    test('a list too short to order retracts nothing', () async {
      await seedCollection(withCollectionUrl: collectionIndexUrl);
      await seedCaptured(100);
      await seedDiscovered(101);
      // Recognisable — it shows an entry we hold — but two numbered links are a
      // coincidence, not an ordering.
      serveList([102, 100]);

      final outcome = await checker.check('collection-1');

      expect((await rows()).any((e) => e.entryNumber == 101), isTrue);
      expect(outcome.staleRemoved, 0);
    });

    test(
      'a reading truncated by the new-entry bound retracts nothing',
      () async {
        final bounded = UpdateChecker(
          browser: browser,
          db: db,
          config: const UpdateCheckConfig(
            maxNewEntries: 2,
            cooldownBetweenPages: Duration.zero,
          ),
        );
        await seedCollection(withCollectionUrl: collectionIndexUrl);
        await seedCaptured(100);
        await seedDiscovered(101);
        serveList([106, 105, 104, 103, 102, 100]);

        final outcome = await bounded.check('collection-1');

        expect(
          (await rows()).any((e) => e.entryNumber == 101),
          isTrue,
          reason: 'the reading stopped short of what the page held',
        );
        expect(outcome.staleRemoved, 0);
        expect(outcome.newEntries, 2);
      },
    );

    test('an unrecognised page retracts nothing', () async {
      await seedCollection(withCollectionUrl: collectionIndexUrl);
      await seedCaptured(100);
      await seedDiscovered(101);
      browser.addPage(
        collectionIndexUrl,
        const PageProbe(
          url: collectionIndexUrl,
          title: 'Something else entirely',
          readyState: 'complete',
          documentHeight: 2000,
          viewportHeight: 800,
          links: [PageLink(href: '/about', text: 'About')],
        ),
      );
      // The chain walk gets its turn and finds nothing either.
      browser.addPage(
        entryUrl(101),
        const PageProbe(
          url: '$host/guide/foo/101',
          title: 'Foo Entry 101',
          readyState: 'complete',
          documentHeight: 2000,
          viewportHeight: 800,
          links: [PageLink(href: '/guide/foo', text: 'Index')],
        ),
      );

      final outcome = await checker.check('collection-1');

      expect((await rows()).any((e) => e.entryNumber == 101), isTrue);
      expect(outcome.staleRemoved, 0);
    });

    test('a failed check retracts nothing', () async {
      await seedCollection(withCollectionUrl: collectionIndexUrl);
      await seedCaptured(100);
      await seedDiscovered(101);
      // No fixture for any page: nothing can be read at all.

      final outcome = await checker.check('collection-1');

      expect(outcome.state, UpdateCheckState.failed);
      expect(outcome.staleRemoved, 0);
      expect(await numbersWithStatus('knownRemote'), [101.0]);
    });

    test('a cancelled check retracts nothing', () async {
      await seedCollection(withCollectionUrl: collectionIndexUrl);
      await seedCaptured(100);
      await seedDiscovered(101);
      serveList([104, 103, 102, 100]);
      // Stop the check the moment the list has been read — after the reading
      // exists, before anything is written or retracted.
      checker.addListener(() {
        if (checker.log.any((l) => l.contains('entry list:'))) checker.cancel();
      });

      final outcome = await checker.check('collection-1');

      expect(outcome.state, UpdateCheckState.cancelled);
      expect(outcome.staleRemoved, 0);
      expect((await rows()).any((e) => e.entryNumber == 101), isTrue);
    });

    test('a check stopped on entry identity retracts nothing', () async {
      await seedCollection(withCollectionUrl: collectionIndexUrl);
      await seedCaptured(100);
      await seedDiscovered(101);
      // The label/metadata weld: labels read 1046, 1022 … while the addresses
      // read 104, 102. 103's label happens to stay clean, which is what proves
      // this source numbers both the same way.
      browser.addPage(
        collectionIndexUrl,
        const PageProbe(
          url: collectionIndexUrl,
          title: 'Foo — all entries',
          readyState: 'complete',
          documentHeight: 2000,
          viewportHeight: 800,
          links: [
            PageLink(href: '/guide/foo/104', text: 'Entry 1046 days ago'),
            PageLink(href: '/guide/foo/103', text: 'Entry 103last week'),
            PageLink(href: '/guide/foo/102', text: 'Entry 1022 weeks ago'),
            PageLink(href: '/guide/foo/100', text: 'Entry 1003 weeks ago'),
          ],
        ),
      );

      final outcome = await checker.check('collection-1');

      expect(outcome.state, UpdateCheckState.failed);
      expect(outcome.stoppedOnEntryIdentity, isTrue);
      expect(outcome.staleRemoved, 0);
      expect(
        (await rows()).any((e) => e.entryNumber == 101),
        isTrue,
        reason: 'a source we are reading wrongly proves no absence',
      );
    });

    test('next-chain discovery never retracts anything', () async {
      // No collection page at all, so the walk is the only strategy — and two
      // hops ahead of the newest entry says nothing about the collection's
      // membership.
      await seedCollection();
      await seedCaptured(100);
      await seedDiscovered(101);
      for (final n in [101, 102, 103]) {
        browser.addPage(
          entryUrl(n),
          PageProbe(
            url: entryUrl(n),
            title: 'Foo Entry $n',
            readyState: 'complete',
            documentHeight: 2000,
            viewportHeight: 800,
            links: [
              if (n < 103) PageLink(href: '/guide/foo/${n + 1}', text: 'Next'),
            ],
          ),
        );
      }

      final outcome = await checker.check('collection-1');

      expect(outcome.staleRemoved, 0);
      expect(
        (await rows()).any((e) => e.entryNumber == 101),
        isTrue,
        reason: 'the chain walk has no window to judge absence against',
      );
    });
  });

  group('the checkpoint a stale discovery had frozen', () {
    test('is corrected inside the same check', () async {
      // The failure this feature exists for: one wrong high number, and every
      // real entry compares as older than what we already "have" — the
      // collection reports up to date forever.
      await seedCollection(withCollectionUrl: collectionIndexUrl);
      await seedCaptured(100);
      await seedDiscovered(400);

      serveList([104, 103, 102, 101, 100]);
      final outcome = await checker.check('collection-1');

      expect(outcome.staleRemoved, 1);
      expect((await rows()).any((e) => e.entryNumber == 400), isFalse);
      expect(
        outcome.newEntries,
        4,
        reason: 'the same page, re-read against a checkpoint that is now true',
      );
      expect(await numbersWithStatus('knownRemote'), [
        101.0,
        102.0,
        103.0,
        104.0,
      ]);
    });

    test('does not come back on the next check', () async {
      await seedCollection(withCollectionUrl: collectionIndexUrl);
      await seedCaptured(100);
      await seedDiscovered(400);
      serveList([104, 103, 102, 101, 100]);
      await checker.check('collection-1');

      final second = await checker.check('collection-1');

      expect(second.state, UpdateCheckState.upToDate);
      expect(second.staleRemoved, 0);
      expect(second.newEntries, 0);
      expect(await numbersWithStatus('knownRemote'), [
        101.0,
        102.0,
        103.0,
        104.0,
      ]);

      // And the source can still move forward from there.
      serveList([105, 104, 103, 102, 101, 100]);
      final third = await checker.check('collection-1');
      expect(third.newEntries, 1);
      expect(third.staleRemoved, 0);
    });
  });

  group('the observed window, as a reading', () {
    PageProbe listProbe(List<PageLink> links) => PageProbe(
      url: collectionIndexUrl,
      title: 'Foo — all entries',
      readyState: 'complete',
      links: links,
    );

    EntryListDiscovery discover(
      List<int> numbers, {
      double? latestKnown,
      Set<String> known = const {},
      int maxNew = 20,
    }) => discoverFromEntryList(
      listProbe([
        for (final n in numbers)
          PageLink(href: '/guide/foo/$n', text: 'Entry $n'),
      ]),
      collectionKey: '/guide/foo',
      latestKnownNumber: latestKnown,
      knownUrlKeys: known,
      maxNew: maxNew,
    );

    test('describes every entry the page showed, not only the new ones', () {
      final result = discover(
        [104, 103, 102, 101, 100],
        latestKnown: 102,
        known: {entryUrl(100), entryUrl(101), entryUrl(102)},
      );

      final window = result.observedWindow!;
      expect(window.from, 100);
      expect(window.to, 104);
      expect(window.urlKeys, {for (var n = 100; n <= 104; n++) entryUrl(n)});
      expect(result.newEntries.map((c) => c.number), [103.0, 104.0]);
    });

    test('a newest-first list rules out everything above its top', () {
      final window = discover([104, 103, 102, 101, 100]).observedWindow!;

      expect(window.openAbove, isTrue);
      expect(window.covers(400), isTrue);
      expect(window.covers(99), isFalse);
    });

    test('an oldest-first list does not', () {
      final window = discover([100, 101, 102, 103, 104]).observedWindow!;

      expect(window.openAbove, isFalse);
      expect(window.covers(105), isFalse);
      expect(window.covers(102), isTrue);
    });

    test('an unorderable list describes no window at all', () {
      expect(discover([102, 100]).observedWindow, isNull);
    });

    test('a truncated reading describes no window at all', () {
      final result = discover([106, 105, 104, 103, 102, 101], maxNew: 2);

      expect(result.dropped, greaterThan(0));
      expect(result.observedWindow, isNull);
    });

    test('a page that is not this collection describes no window', () {
      final result = discoverFromEntryList(
        listProbe(const [PageLink(href: '/about', text: 'About')]),
        collectionKey: '/guide/foo',
        latestKnownNumber: 100,
        knownUrlKeys: const {},
      );

      expect(result.listRecognised, isFalse);
      expect(result.observedWindow, isNull);
    });

    test('a doubted list describes no window', () {
      final result = discoverFromEntryList(
        listProbe(const [
          PageLink(href: '/guide/foo/104', text: 'Entry 1046 days ago'),
          PageLink(href: '/guide/foo/103', text: 'Entry 103last week'),
          PageLink(href: '/guide/foo/102', text: 'Entry 1022 weeks ago'),
          PageLink(href: '/guide/foo/100', text: 'Entry 1003 weeks ago'),
        ]),
        collectionKey: '/guide/foo',
        latestKnownNumber: 100,
        knownUrlKeys: {entryUrl(100)},
      );

      expect(result.concerns, isNotEmpty);
      expect(result.observedWindow, isNull);
    });

    test('an entry that cannot be placed on the number line kills it', () {
      // "Side Story" sits between two numbered entries, so it is admitted as an
      // entry — but a list whose own numbers cannot place every member is one
      // the interval does not faithfully describe.
      final result = discoverFromEntryList(
        listProbe(const [
          PageLink(href: '/guide/foo/104', text: 'Entry 104'),
          PageLink(href: '/guide/foo/103', text: 'Entry 103'),
          PageLink(href: '/guide/foo/102', text: 'Entry 102'),
        ]),
        collectionKey: '/guide/foo',
        latestKnownNumber: 100,
        knownUrlKeys: {'$host/guide/foo/side-story'},
      );
      expect(result.observedWindow, isNotNull);

      final withUnplaceable = discoverFromEntryList(
        listProbe(const [
          PageLink(href: '/guide/foo/side-story', text: 'Side Story'),
          PageLink(href: '/guide/foo/104', text: 'Entry 104'),
          PageLink(href: '/guide/foo/103', text: 'Entry 103'),
          PageLink(href: '/guide/foo/102', text: 'Entry 102'),
        ]),
        collectionKey: '/guide/foo',
        latestKnownNumber: 100,
        // Known, so it is kept as an entry rather than filtered out — and it
        // leads the list, so it has no numbered neighbour above it to borrow
        // from.
        knownUrlKeys: {'$host/guide/foo/side-story'},
      );
      expect(withUnplaceable.observedWindow?.from, 102);
    });
  });

  group('the deletion rule itself', () {
    test('cannot be pointed at a row that is not a bare discovery', () async {
      // The rule lives at the database, not at the caller: the caller says what
      // it saw, never which rows to delete. Handed an observation that covers
      // everything, only the bare discovery goes.
      await seedCollection(withCollectionUrl: collectionIndexUrl);
      await seedCaptured(100);
      await seedCaptured(101, status: 'partial');
      await seedDiscovered(102);

      final removed = await db.reconcileDiscoveredEntries(
        collectionId: 'collection-1',
        observedUrlKeys: const {},
        windowFrom: 0,
        windowTo: 1000,
        windowOpenAbove: true,
      );

      expect(removed.map((e) => e.entryNumber), [102.0]);
      expect((await rows()).map((e) => e.entryNumber), [100.0, 101.0]);
    });

    test('leaves the collection whole when nothing qualifies', () async {
      await seedCollection(withCollectionUrl: collectionIndexUrl);
      await seedCaptured(100);

      final removed = await db.reconcileDiscoveredEntries(
        collectionId: 'collection-1',
        observedUrlKeys: const {},
        windowFrom: 0,
        windowTo: 1000,
        windowOpenAbove: true,
      );

      expect(removed, isEmpty);
      expect(await rows(), hasLength(1));
    });
  });
}
