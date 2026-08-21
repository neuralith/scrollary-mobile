import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_reader/browser/page_data.dart';
import 'package:web_reader/save/save_preflight.dart';
import 'package:web_reader/library/update_checker.dart';
import 'package:web_reader/storage/database.dart';
import 'package:web_reader/storage/file_store.dart';

import 'helpers/fake_browser.dart';

/// The M8 update check: bounded, metadata-only discovery over the same
/// navigation trust chain saves use.
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

  Future<void> seedSaved(int n, {String? nextUrl}) => db.upsertEntry(
    Entry(
      host: '',
      contentKind: 'unknownWebContent',
      contentKindConfidence: 'low',
      contentKindIsUserSet: false,
      id: 'ch$n',
      collectionId: 'collection-1',
      title: 'Foo Entry $n',
      sourceUrl: entryUrl(n),
      urlKey: entryUrl(n),
      artifactFormat: 'imageSequence',
      saveStatus: 'complete',
      contentPath: 'library/collection-1/entries/ch$n',
      savedAt: DateTime(2026, 7, 10),
      detectedAssetCount: 3,
      storedAssetCount: 3,
      nextSourceUrl: nextUrl,
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

  /// Entry pages [from]..[to], each linking rel=next to its successor.
  void serveChain(int from, int to) {
    for (var n = from; n <= to; n++) {
      browser.addPage(
        entryUrl(n),
        entryProbe(
          url: entryUrl(n),
          title: 'Foo Entry $n',
          imageUrls: const [],
          nextHref: n < to ? entryUrl(n + 1) : null,
        ),
      );
    }
  }

  group('next-chain discovery', () {
    test('finds new entries without downloading anything', () async {
      await seedCollection();
      await seedSaved(1, nextUrl: entryUrl(2));
      await seedSaved(2); // saved while it was the newest — no next
      serveChain(2, 4);

      final outcome = await checker.check('collection-1');

      expect(outcome.state, UpdateCheckState.updatesAvailable);
      expect(outcome.newEntries, 2);

      final discovered = (await db.allEntries())
          .where((c) => c.saveStatus == 'knownRemote')
          .toList();
      expect(discovered, hasLength(2));
      for (final c in discovered) {
        expect(c.contentPath, isNull, reason: 'metadata only, no bytes');
        expect(c.storedAssetCount, 0);
        expect(c.discoveredAt, isNotNull);
        expect(c.discoveryBasis, 'nextChain');
      }
      expect(discovered.map((c) => c.entryNumber), containsAll([3.0, 4.0]));
    });

    test('a second check discovers nothing new and reports upToDate', () async {
      await seedCollection();
      await seedSaved(1, nextUrl: entryUrl(2));
      await seedSaved(2);
      serveChain(2, 4);

      await checker.check('collection-1');
      final second = await checker.check('collection-1');

      expect(second.state, UpdateCheckState.upToDate);
      expect(second.newEntries, 0);
      expect(
        (await db.allEntries())
            .where((c) => c.saveStatus == 'knownRemote')
            .length,
        2,
        reason: 'no duplicate discovery rows',
      );
    });

    test(
      'check state is persisted on the collection, including failures',
      () async {
        await seedCollection();
        await seedSaved(1, nextUrl: entryUrl(2));
        await seedSaved(2);
        serveChain(2, 3);

        await checker.check('collection-1');
        var item = (await db.collectionById('collection-1'))!;
        expect(item.lastCheckAt, isNotNull);
        expect(item.lastCheckSuccessAt, isNotNull);
        expect(item.lastCheckResult, 'updatesAvailable');
        expect(item.lastCheckError, isNull);

        // Now a failing check: the latest entry's page does not exist.
        await db.upsertEntry(
          (await db.entryById('ch2'))!.copyWith(sourceUrl: '$host/gone'),
        );
        browser.pages.clear();
        final failing = await checker.check('collection-1');
        expect(failing.state, UpdateCheckState.failed);

        item = (await db.collectionById('collection-1'))!;
        expect(item.lastCheckResult, 'failed');
        expect(item.lastCheckError, isNotNull);
      },
    );

    test('bounded: stops at maxNewEntries and maxPagesInspected', () async {
      final bounded = UpdateChecker(
        browser: browser,
        db: db,
        config: const UpdateCheckConfig(
          maxNewEntries: 3,
          maxPagesInspected: 5,
          // Lifted so this test still measures the two bounds it is named
          // after. With the shipped depth of 2 the walk stops before either
          // of them is reached — which is the point of the depth group below.
          maxForwardDepth: 10,
          cooldownBetweenPages: Duration.zero,
        ),
      );
      await seedCollection();
      await seedSaved(1, nextUrl: entryUrl(2));
      await seedSaved(2);
      serveChain(2, 40); // a "site" with vastly more than the bound

      final outcome = await bounded.check('collection-1');

      expect(outcome.state, UpdateCheckState.updatesAvailable);
      expect(outcome.newEntries, 3);
      expect(
        outcome.pagesInspected,
        lessThanOrEqualTo(5),
        reason: 'never an unbounded crawl',
      );
    });

    test('cancel stops the walk and keeps what was found', () async {
      await seedCollection();
      await seedSaved(1, nextUrl: entryUrl(2));
      await seedSaved(2);
      serveChain(2, 10);

      // Cancel as soon as the first discovery lands.
      checker.addListener(() {
        if (checker.log.any((l) => l.contains('found:'))) checker.cancel();
      });

      final outcome = await checker.check('collection-1');
      expect(outcome.state, UpdateCheckState.cancelled);
      expect(
        (await db.allEntries())
            .where((c) => c.saveStatus == 'knownRemote')
            .length,
        greaterThanOrEqualTo(1),
        reason: 'discovered metadata is kept, not rolled back',
      );

      final item = (await db.collectionById('collection-1'))!;
      expect(item.lastCheckResult, 'cancelled');
    });

    test('a next link that leaves the collection ends the check', () async {
      await seedCollection();
      await seedSaved(1, nextUrl: entryUrl(2));
      await seedSaved(2);
      browser.addPage(
        entryUrl(2),
        entryProbe(
          url: entryUrl(2),
          title: 'Foo Entry 2',
          imageUrls: const [],
          nextHref: '$host/guide/OTHER-SERIES/1',
        ),
      );

      final outcome = await checker.check('collection-1');
      expect(outcome.state, UpdateCheckState.upToDate);
      expect(outcome.newEntries, 0);
      expect(
        (await db.entriesForCollection('collection-1')).length,
        2,
        reason: 'nothing from another collection was recorded',
      );
    });

    test('refuses to run while something else drives the browser', () async {
      await seedCollection();
      await seedSaved(1);
      browser.automationOwner = 'a save run';

      final outcome = await checker.check('collection-1');
      expect(outcome.state, UpdateCheckState.failed);
      expect(outcome.error, contains('save run'));

      browser.automationOwner = null;
    });

    test('a discovered entry is free to save, not a failed one', () async {
      await seedCollection();
      await seedSaved(1, nextUrl: entryUrl(2));
      await seedSaved(2);
      serveChain(2, 3);
      await checker.check('collection-1');

      final discovered = (await db.allEntries())
          .where((c) => c.saveStatus == 'knownRemote')
          .single;
      expect(discovered.entryNumber, 3.0);

      final root = Directory.systemTemp.createTempSync('webread_uc');
      addTearDown(() => root.deleteSync(recursive: true));
      final preflight = await SavePreflight(
        db: db,
        fileStore: FileStore(root),
      ).inspect(discovered.sourceUrl, collectionId: 'collection-1');

      expect(
        preflight.state,
        EntryLocalState.none,
        reason: 'saving it must neither prompt nor look like a retry',
      );
    });
  });

  group('forward depth', () {
    /// The product rule: **the page a check starts on is depth 0**, and the
    /// check may follow at most [kUpdateCheckForwardDepth] "next entry" links
    /// from there. Everything in this group exists to pin that sentence down,
    /// because "two entries" and "two hops" are not the same number and the
    /// difference is one extra request to someone else's site.
    test('the shipped bound is two forward transitions', () {
      expect(kUpdateCheckForwardDepth, 2);
      expect(kDefaultUpdateCheckConfig.maxForwardDepth, 2);
    });

    test('follows no more than two entry transitions', () async {
      await seedCollection();
      await seedSaved(1, nextUrl: entryUrl(2));
      await seedSaved(2);
      serveChain(2, 40); // far more available than the bound allows

      final outcome = await checker.check('collection-1');

      expect(outcome.state, UpdateCheckState.updatesAvailable);
      expect(outcome.newEntries, 2);
      final discovered = (await db.allEntries())
          .where((c) => c.saveStatus == 'knownRemote')
          .toList();
      expect(
        discovered.map((c) => c.entryNumber).toSet(),
        {3.0, 4.0},
        reason: 'entry 5 is one hop too far and is left for the next check',
      );
      expect(checker.forwardDepth, 2);
    });

    test(
      'the starting page is depth 0 — reading it is not a transition',
      () async {
        // No stored next link, so the check must open the latest known entry's
        // own page to find one. That page is where the check *starts*: three
        // pages are read, and only two of them were reached by following a
        // next link.
        await seedCollection();
        await seedSaved(1, nextUrl: entryUrl(2));
        await seedSaved(2);
        serveChain(2, 40);

        final outcome = await checker.check('collection-1');

        expect(outcome.pagesInspected, 3, reason: 'entry 2, then 3, then 4');
        expect(
          checker.forwardDepth,
          2,
          reason: 'the entry-2 page was the origin, not a hop',
        );
        expect(outcome.newEntries, 2);
      },
    );

    test(
      'depth counts hops, not pages, when the next link is stored',
      () async {
        // Same collection, but the latest known entry already carries its next
        // link, so the check never opens it. Two pages are read instead of
        // three — and the same two entries are found, because the bound is on
        // transitions either way.
        await seedCollection();
        await seedSaved(1, nextUrl: entryUrl(2));
        await seedSaved(2, nextUrl: entryUrl(3));
        serveChain(2, 40);

        final outcome = await checker.check('collection-1');

        expect(outcome.pagesInspected, 2, reason: 'entry 3, then entry 4');
        expect(checker.forwardDepth, 2);
        expect(
          (await db.allEntries())
              .where((c) => c.saveStatus == 'knownRemote')
              .map((c) => c.entryNumber)
              .toSet(),
          {3.0, 4.0},
        );
      },
    );

    test('the walk stops on the bound and says so, without failing', () async {
      await seedCollection();
      await seedSaved(1, nextUrl: entryUrl(2));
      await seedSaved(2);
      serveChain(2, 40);

      final outcome = await checker.check('collection-1');

      expect(
        outcome.state,
        UpdateCheckState.updatesAvailable,
        reason: 'a bound reached is not an error and not "up to date"',
      );
      expect(
        checker.log.any((l) => l.contains('forward depth bound reached')),
        isTrue,
      );
      // The last discovered row carries its own next link, so the next check
      // resumes from here rather than walking this stretch again.
      final last = (await db.allEntries()).firstWhere(
        (c) => c.entryNumber == 4.0,
      );
      expect(last.nextSourceUrl, entryUrl(5));
    });

    test('a second check continues from where the first stopped', () async {
      await seedCollection();
      await seedSaved(1, nextUrl: entryUrl(2));
      await seedSaved(2);
      serveChain(2, 40);

      await checker.check('collection-1');
      await checker.check('collection-1');

      expect(
        (await db.allEntries())
            .where((c) => c.saveStatus == 'knownRemote')
            .map((c) => c.entryNumber)
            .toSet(),
        {3.0, 4.0, 5.0, 6.0},
        reason: 'shallow per run, not a ceiling on what can ever be found',
      );
    });

    test('the bound is configuration, not a magic number', () async {
      final shallow = UpdateChecker(
        browser: browser,
        db: db,
        config: const UpdateCheckConfig(
          maxForwardDepth: 1,
          cooldownBetweenPages: Duration.zero,
        ),
      );
      await seedCollection();
      await seedSaved(1, nextUrl: entryUrl(2));
      await seedSaved(2);
      serveChain(2, 40);

      final outcome = await shallow.check('collection-1');

      expect(outcome.newEntries, 1);
      expect(shallow.forwardDepth, 1);
    });

    test('reading one entry list is not a traversal', () async {
      // The depth bound is about *following links between entries*. A
      // collection page is a single page read, so it may still report every
      // new entry it lists — that is what keeps a check useful on sites that
      // have an index.
      await seedCollection(withCollectionUrl: collectionIndexUrl);
      await seedSaved(1);
      await seedSaved(2);
      browser.addPage(
        collectionIndexUrl,
        PageProbe(
          url: collectionIndexUrl,
          title: 'Foo — all entries',
          readyState: 'complete',
          documentHeight: 2000,
          viewportHeight: 800,
          links: [
            for (var n = 9; n >= 1; n--)
              PageLink(href: '/guide/foo/$n', text: 'Entry $n'),
          ],
        ),
      );

      final outcome = await checker.check('collection-1');

      expect(outcome.newEntries, 7, reason: 'entries 3 through 9');
      expect(
        checker.forwardDepth,
        0,
        reason: 'nothing was followed — one page was read',
      );
      expect(outcome.pagesInspected, 1);
    });
  });

  group('stopping a check', () {
    test('a cancel stops entry-list discovery where it stands', () async {
      await seedCollection(withCollectionUrl: collectionIndexUrl);
      await seedSaved(1);
      await seedSaved(2);
      browser.addPage(
        collectionIndexUrl,
        PageProbe(
          url: collectionIndexUrl,
          title: 'Foo — all entries',
          readyState: 'complete',
          documentHeight: 2000,
          viewportHeight: 800,
          links: [
            for (var n = 6; n >= 1; n--)
              PageLink(href: '/guide/foo/$n', text: 'Entry $n'),
          ],
        ),
      );
      // Stop the moment the first discovery lands — the panel's Stop button,
      // pressed while the list is being written.
      checker.addListener(() {
        if (checker.log.any((l) => l.contains('found:'))) checker.cancel();
      });

      final outcome = await checker.check('collection-1');

      expect(outcome.state, UpdateCheckState.cancelled);
      expect(
        (await db.allEntries())
            .where((c) => c.saveStatus == 'knownRemote')
            .length,
        1,
        reason: 'the remaining three were never written',
      );
    });

    test('a cancelled check opens no further pages', () async {
      await seedCollection();
      await seedSaved(1, nextUrl: entryUrl(2));
      await seedSaved(2);
      serveChain(2, 40);
      checker.addListener(() {
        if (checker.log.any((l) => l.contains('found:'))) checker.cancel();
      });

      await checker.check('collection-1');

      expect(
        browser.navigations,
        isNot(contains(entryUrl(4))),
        reason: 'navigation stops with the check, not after it',
      );
    });

    test('cancelling keeps every saved entry and its files', () async {
      await seedCollection();
      await seedSaved(1, nextUrl: entryUrl(2));
      await seedSaved(2);
      serveChain(2, 40);
      checker.addListener(() {
        if (checker.log.any((l) => l.contains('found:'))) checker.cancel();
      });

      await checker.check('collection-1');

      final saved = (await db.allEntries())
          .where((c) => c.saveStatus == 'complete')
          .toList();
      expect(saved, hasLength(2));
      for (final entry in saved) {
        expect(entry.contentPath, isNotNull);
        expect(entry.byteSize, 128);
        expect(entry.storedAssetCount, 3);
      }
      expect(await db.collectionById('collection-1'), isNotNull);
    });
  });

  group('the page a check starts on', () {
    test('is the collection page when there is one', () async {
      await seedCollection(withCollectionUrl: collectionIndexUrl);
      await seedSaved(1);

      expect(
        await checker.firstPageToInspect('collection-1'),
        collectionIndexUrl,
      );
    });

    test('is the stored next link when there is no collection page', () async {
      await seedCollection();
      await seedSaved(1, nextUrl: entryUrl(2));
      await seedSaved(2, nextUrl: entryUrl(3));

      expect(await checker.firstPageToInspect('collection-1'), entryUrl(3));
    });

    test('is the latest known entry when there is no stored link', () async {
      await seedCollection();
      await seedSaved(1, nextUrl: entryUrl(2));
      await seedSaved(2);

      expect(await checker.firstPageToInspect('collection-1'), entryUrl(2));
    });

    test('is nothing when there is nothing to start from', () async {
      await seedCollection();

      expect(await checker.firstPageToInspect('collection-1'), isNull);
      expect(await checker.firstPageToInspect('no-such-collection'), isNull);
    });

    test('opens no page and writes nothing', () async {
      await seedCollection(withCollectionUrl: collectionIndexUrl);
      await seedSaved(1);

      await checker.firstPageToInspect('collection-1');

      expect(browser.navigations, isEmpty);
      expect(checker.isRunning, isFalse);
      expect(browser.automationOwner, isNull);
    });
  });

  group('collection-page checkpoint', () {
    PageProbe collectionListPage(List<int> entriesNewestFirst) => PageProbe(
      url: collectionIndexUrl,
      title: 'Foo — all entries',
      readyState: 'complete',
      documentHeight: 2000,
      viewportHeight: 800,
      links: [
        for (final n in entriesNewestFirst)
          PageLink(href: '/guide/foo/$n', text: 'Entry $n'),
      ],
    );

    test('a newest-first list is recorded oldest first', () async {
      await seedCollection(withCollectionUrl: collectionIndexUrl);
      await seedSaved(1);
      await seedSaved(2);
      browser.addPage(
        collectionIndexUrl,
        collectionListPage([6, 5, 4, 3, 2, 1]),
      );

      final outcome = await checker.check('collection-1');

      expect(outcome.state, UpdateCheckState.updatesAvailable);
      expect(outcome.newEntries, 4);

      final discovered =
          (await db.allEntries())
              .where((c) => c.saveStatus == 'knownRemote')
              .toList()
            ..sort((a, b) => a.entryOrder.compareTo(b.entryOrder));
      expect(
        discovered.map((c) => c.entryNumber),
        [3.0, 4.0, 5.0, 6.0],
        reason: 'sequence runs forward even though the page runs backward',
      );
      expect(discovered.every((c) => c.discoveryBasis == 'entryList'), isTrue);
    });

    test('an unorderable list does not stop the check early', () async {
      await seedCollection(withCollectionUrl: collectionIndexUrl);
      await seedSaved(1, nextUrl: entryUrl(2));
      await seedSaved(2);
      // Recognisable (it shows entries we hold) but too short to establish an
      // ordering — so "nothing new here" is not evidence of being up to date.
      browser.addPage(collectionIndexUrl, collectionListPage([2, 1]));
      serveChain(2, 3);

      final outcome = await checker.check('collection-1');

      expect(
        outcome.state,
        UpdateCheckState.updatesAvailable,
        reason: 'the chain walk got its turn instead of an early up-to-date',
      );
      final discovered = (await db.allEntries())
          .where((c) => c.saveStatus == 'knownRemote')
          .toList();
      expect(discovered.single.entryNumber, 3.0);
      expect(discovered.single.discoveryBasis, 'nextChain');
    });
  });

  group('entry-list discovery (pure)', () {
    PageProbe listProbe(List<PageLink> links) => PageProbe(
      url: collectionIndexUrl,
      title: 'Foo — all entries',
      readyState: 'complete',
      links: links,
    );

    test('new numbered entries above the latest known are found', () {
      final probe = listProbe([
        const PageLink(href: '/guide/foo/1', text: 'Entry 1'),
        const PageLink(href: '/guide/foo/2', text: 'Entry 2'),
        const PageLink(href: '/guide/foo/3', text: 'Entry 3'),
        const PageLink(href: '/guide/foo/4', text: 'Entry 4'),
        // Same host, different collection: must not leak in.
        const PageLink(href: '/guide/bar/9', text: 'Entry 9'),
        // Unnumbered: cannot be established as new from a list alone.
        const PageLink(href: '/guide/foo/extra', text: 'Extra'),
      ]);

      final result = discoverFromEntryList(
        probe,
        collectionKey: '/guide/foo',
        latestKnownNumber: 2,
        knownUrlKeys: {entryUrl(1), entryUrl(2)},
      );

      expect(result.listRecognised, isTrue);
      expect(result.newEntries.map((c) => c.number), [3.0, 4.0]);
      expect(result.knownSeen, 2);
    });

    test('an unrelated page is not "up to date", it is unrecognised', () {
      final probe = listProbe([
        const PageLink(href: '/about', text: 'About us'),
        const PageLink(href: '/login', text: 'Login'),
      ]);

      final result = discoverFromEntryList(
        probe,
        collectionKey: '/guide/foo',
        latestKnownNumber: 2,
        knownUrlKeys: {entryUrl(1), entryUrl(2)},
      );

      expect(
        result.listRecognised,
        isFalse,
        reason: 'a 404 or an error page must fall back to the chain walk',
      );
      expect(result.newEntries, isEmpty);
    });

    test('a newest-first list is read in its own order', () {
      // What most sites actually serve: entry 6 at the top, 1 at the bottom.
      final probe = listProbe([
        for (var n = 6; n >= 1; n--)
          PageLink(href: '/guide/foo/$n', text: 'Entry $n'),
      ]);

      final result = discoverFromEntryList(
        probe,
        collectionKey: '/guide/foo',
        latestKnownNumber: 3,
        knownUrlKeys: {entryUrl(1), entryUrl(2), entryUrl(3)},
      );

      expect(result.direction, EntryListDirection.newestFirst);
      expect(result.orderingConfident, isTrue);
      expect(
        result.newEntries.map((c) => c.number),
        [4.0, 5.0, 6.0],
        reason: 'emitted oldest first so save runs forward',
      );
    });

    test('decimal entries sort between their neighbours', () {
      final probe = listProbe([
        const PageLink(href: '/guide/foo/386', text: 'Entry 386'),
        const PageLink(href: '/guide/foo/385-5', text: 'Entry 385.5'),
        const PageLink(href: '/guide/foo/385', text: 'Entry 385'),
        const PageLink(href: '/guide/foo/384', text: 'Entry 384'),
      ]);

      final result = discoverFromEntryList(
        probe,
        collectionKey: '/guide/foo',
        latestKnownNumber: 385,
        knownUrlKeys: {'$host/guide/foo/385', '$host/guide/foo/384'},
      );

      expect(
        result.newEntries.map((c) => c.number),
        [385.5, 386.0],
        reason: '385 < 385.5 < 386 — never a string comparison',
      );
    });

    test('an unnumbered entry above the known block is not discarded', () {
      final probe = listProbe([
        const PageLink(href: '/guide/foo/5', text: 'Entry 5'),
        const PageLink(href: '/guide/foo/extra', text: 'Side Story'),
        const PageLink(href: '/guide/foo/4', text: 'Entry 4'),
        const PageLink(href: '/guide/foo/3', text: 'Entry 3'),
        const PageLink(href: '/guide/foo/2', text: 'Entry 2'),
        // Page furniture at a different depth: still excluded.
        const PageLink(href: '/guide/foo', text: 'All entries'),
      ]);

      final result = discoverFromEntryList(
        probe,
        collectionKey: '/guide/foo',
        latestKnownNumber: 3,
        knownUrlKeys: {entryUrl(2), entryUrl(3)},
      );

      expect(
        result.newEntries.map((c) => c.title),
        ['Entry 4', 'Side Story', 'Entry 5'],
        reason: 'placed by list position, since it has no number to compare',
      );
    });

    test('the same entry linked twice is recorded once', () {
      final probe = listProbe([
        const PageLink(href: '/guide/foo/4', text: 'Entry 4'),
        const PageLink(href: '/guide/foo/4', text: 'Entry 4 (new!)'),
        const PageLink(href: '/guide/foo/3', text: 'Entry 3'),
        const PageLink(href: '/guide/foo/2', text: 'Entry 2'),
      ]);

      final result = discoverFromEntryList(
        probe,
        collectionKey: '/guide/foo',
        latestKnownNumber: 3,
        knownUrlKeys: {entryUrl(2), entryUrl(3)},
      );

      expect(result.newEntries, hasLength(1));
      expect(result.newEntries.single.number, 4.0);
    });

    test('a library that starts in the middle continues from there', () {
      // 400 entries listed newest first; the user holds 100–105.
      final probe = listProbe([
        for (var n = 400; n >= 1; n--)
          PageLink(href: '/guide/foo/$n', text: 'Entry $n'),
      ]);

      final result = discoverFromEntryList(
        probe,
        collectionKey: '/guide/foo',
        latestKnownNumber: 105,
        knownUrlKeys: {for (var n = 100; n <= 105; n++) entryUrl(n)},
        maxNew: 5,
      );

      expect(
        result.newEntries.map((c) => c.number),
        [106.0, 107.0, 108.0, 109.0, 110.0],
        reason: 'upward from the checkpoint, not from entry 1',
      );
      expect(
        result.dropped,
        greaterThan(0),
        reason: 'the rest are reported, not silently forgotten',
      );
    });

    test('shortcut links above the list do not defeat the ordering', () {
      // What both live sites actually serve: "First Entry" and "Latest
      // Entry" jump links sit above a newest-first list. They break strict
      // monotonicity, and an earlier version of this went `unknown` on every
      // real page because of them.
      final probe = listProbe([
        const PageLink(href: '/guide/foo/1', text: 'İlk part'),
        const PageLink(href: '/guide/foo/8', text: 'En Son part'),
        for (var n = 8; n >= 1; n--)
          PageLink(href: '/guide/foo/$n', text: 'Entry $n'),
      ]);

      final result = discoverFromEntryList(
        probe,
        collectionKey: '/guide/foo',
        latestKnownNumber: 6,
        knownUrlKeys: {for (var n = 1; n <= 6; n++) entryUrl(n)},
      );

      expect(result.direction, EntryListDirection.newestFirst);
      expect(
        result.orderingConfident,
        isTrue,
        reason: 'a couple of jump links is not an unorderable list',
      );
      expect(result.newEntries.map((c) => c.number), [7.0, 8.0]);
    });

    test('an unnumbered entry is placed between its neighbours', () {
      // Ordering by interpolated position, not by list index — so a shortcut
      // link at the top cannot displace it either.
      final probe = listProbe([
        const PageLink(href: '/guide/foo/1', text: 'First Entry'),
        const PageLink(href: '/guide/foo/386', text: 'Entry 386'),
        const PageLink(href: '/guide/foo/extra', text: 'Side Story'),
        const PageLink(href: '/guide/foo/385', text: 'Entry 385'),
        const PageLink(href: '/guide/foo/384', text: 'Entry 384'),
      ]);

      final result = discoverFromEntryList(
        probe,
        collectionKey: '/guide/foo',
        latestKnownNumber: 385,
        knownUrlKeys: {
          '$host/guide/foo/1',
          '$host/guide/foo/384',
          '$host/guide/foo/385',
        },
      );

      expect(
        result.newEntries.map((c) => c.title),
        ['Side Story', 'Entry 386'],
        reason: 'interpolated to 385.5 — after 385, before 386',
      );
    });

    test('an unorderable list is not confident, even when it is a list', () {
      final probe = listProbe([
        const PageLink(href: '/guide/foo/2', text: 'Entry 2'),
        const PageLink(href: '/guide/foo/5', text: 'Entry 5'),
        const PageLink(href: '/guide/foo/3', text: 'Entry 3'),
      ]);

      final result = discoverFromEntryList(
        probe,
        collectionKey: '/guide/foo',
        latestKnownNumber: 5,
        knownUrlKeys: {entryUrl(2), entryUrl(3), entryUrl(5)},
      );

      expect(result.listRecognised, isTrue);
      expect(result.newEntries, isEmpty);
      expect(
        result.orderingConfident,
        isFalse,
        reason: 'nothing new here is a guess, so the caller keeps looking',
      );
    });

    test('respects the maxNew bound', () {
      final probe = listProbe([
        for (var n = 1; n <= 30; n++)
          PageLink(href: '/guide/foo/$n', text: 'Entry $n'),
      ]);

      final result = discoverFromEntryList(
        probe,
        collectionKey: '/guide/foo',
        latestKnownNumber: 2,
        knownUrlKeys: {entryUrl(1), entryUrl(2)},
        maxNew: 5,
      );

      expect(result.newEntries, hasLength(5));
      expect(
        result.newEntries.first.number,
        3.0,
        reason: 'oldest new first, so save continues in reading order',
      );
    });

    /// A list row's label used to be `a.textContent`, which concatenates the
    /// row's elements with no separator: `<span>Entry 101</span><span>2 weeks
    /// ago</span>` reached the probe as `"Entry 1012 weeks ago"`. The bridge no
    /// longer produces that reading — see `elementText` — so the `separated`
    /// fixture below is what a real page now yields, and it is the case that
    /// has to keep working.
    ///
    /// The `glued` fixture is kept as the **second** line: a producer fault
    /// that gets past the bridge again, whether from a future change here or
    /// from a page where the browser could give no rendered text at all. What
    /// is asserted about it is not that the numbers come out right — nothing
    /// downstream can know that 1012 was meant to be 101 — but that the
    /// contradiction is noticed and nothing is written on it.
    ///
    /// The wrong number was never the whole damage. Ordering, the list's
    /// measured direction and the checkpoint the next check starts from were
    /// all derived from it, so each is checked separately.
    group('a label welded to its metadata', () {
      // The same five rows twice: newest first, one already held, differing
      // only in whether the markup separated the two elements.
      const glued = [
        PageLink(href: '/guide/foo/104', text: 'Entry 1046 days ago'),
        PageLink(href: '/guide/foo/103', text: 'Entry 103last week'),
        PageLink(href: '/guide/foo/102', text: 'Entry 1022 weeks ago'),
        PageLink(href: '/guide/foo/101', text: 'Entry 1012 weeks ago'),
        PageLink(href: '/guide/foo/100', text: 'Entry 1003 weeks ago'),
      ];
      const separated = [
        PageLink(href: '/guide/foo/104', text: 'Entry 104 6 days ago'),
        PageLink(href: '/guide/foo/103', text: 'Entry 103 last week'),
        PageLink(href: '/guide/foo/102', text: 'Entry 102 2 weeks ago'),
        PageLink(href: '/guide/foo/101', text: 'Entry 101 2 weeks ago'),
        PageLink(href: '/guide/foo/100', text: 'Entry 100 3 weeks ago'),
      ];

      EntryListDiscovery discover(List<PageLink> links) =>
          discoverFromEntryList(
            listProbe(links),
            collectionKey: '/guide/foo',
            latestKnownNumber: 100,
            knownUrlKeys: {entryUrl(100)},
          );

      test('the separated list is read correctly, and doubts nothing', () {
        final result = discover(separated);

        expect(result.direction, EntryListDirection.newestFirst);
        expect(result.orderingConfident, isTrue);
        expect(result.knownSeen, 1);
        expect(result.newEntries.map((c) => c.number), [
          101.0,
          102.0,
          103.0,
          104.0,
        ]);
        expect(
          result.concerns,
          isEmpty,
          reason: 'an ordinary list must never trip the safety net',
        );
      });

      test('a glued label is doubted, with both readings kept', () {
        final result = discover(glued);

        // Entry 103's metadata began with a letter, so its two readings still
        // agree — which is what proves this source numbers its addresses the
        // way it numbers its labels, and therefore what makes the other four
        // disagreements mean something.
        expect(result.concerns.map((c) => c.url), [
          entryUrl(101),
          entryUrl(102),
          entryUrl(104),
        ]);
        final first = result.concerns.first;
        expect(first.labelNumber, 1012.0);
        expect(first.urlNumber, 101.0);
        expect(first.nearbyNumbers, [100.0, 101.0, 102.0, 103.0, 104.0]);
        expect(first.doubt, EntryIdentityDoubt.labelFarFromAddressRun);
      });

      test('a doubted entry is not offered for persistence', () {
        // Removed here as well as reported: the caller stops on `concerns`,
        // but this function is public and pure, and a caller that read only
        // `newEntries` must still be unable to write one.
        final result = discover(glued);

        expect(result.newEntries.map((c) => c.url), [entryUrl(103)]);
        expect(result.newEntries.map((c) => c.number), [103.0]);
      });

      test('no doubted number can reach the checkpoint', () {
        // The durable half of the original bug: `latestKnownNumber` is the
        // highest number held, so a corrupted 1046 written once would make
        // every later check ask for entries above 1046 and find none — the
        // collection reporting up to date forever.
        final highest = discover(glued).newEntries
            .map((c) => c.number ?? 0)
            .fold<double>(100, (a, b) => a > b ? a : b);

        expect(
          highest,
          lessThanOrEqualTo(104.0),
          reason: 'a checkpoint above the real list silently ends discovery',
        );
      });

      test('an unnumbered entry beside a doubted one is still unaffected', () {
        // The safety net judges numbers, and only against addresses. A row
        // with no number of its own is not evidence and is not a suspect.
        final result = discover([
          ...glued,
          const PageLink(href: '/guide/foo/side-story', text: 'Side Story'),
        ]);

        expect(
          result.concerns.map((c) => c.url),
          isNot(contains('$host/guide/foo/side-story')),
        );
      });
    });
  });

  /// What the check *does* when it cannot justify an entry's number.
  ///
  /// The pure tests above prove the reading is doubted. These prove the doubt
  /// is load-bearing: nothing is written, the checkpoint the next check starts
  /// from is untouched, and the run ends where the doubt was found rather than
  /// carrying on into the chain walk and asking a second question of a source
  /// we have just shown we are reading wrongly.
  group('a check that cannot identify an entry', () {
    PageProbe listPage(List<PageLink> links) => PageProbe(
      url: collectionIndexUrl,
      title: 'Foo — all entries',
      readyState: 'complete',
      documentHeight: 2000,
      viewportHeight: 800,
      links: links,
    );

    // As a lost element boundary renders it: every address clean, the labels
    // carrying the first digit of the timestamp beside them. Entry 103's
    // metadata began with a letter, so its readings still agree.
    PageProbe gluedPage() => listPage(const [
      PageLink(href: '/guide/foo/104', text: 'Entry 1046 days ago'),
      PageLink(href: '/guide/foo/103', text: 'Entry 103last week'),
      PageLink(href: '/guide/foo/102', text: 'Entry 1022 weeks ago'),
      PageLink(href: '/guide/foo/101', text: 'Entry 1012 weeks ago'),
      PageLink(href: '/guide/foo/100', text: 'Entry 100 3 weeks ago'),
    ]);

    Future<void> seedHolding100() async {
      await seedCollection(withCollectionUrl: collectionIndexUrl);
      await seedSaved(100);
    }

    test('stops, and says so without naming its internals', () async {
      await seedHolding100();
      browser.addPage(collectionIndexUrl, gluedPage());

      final outcome = await checker.check('collection-1');

      expect(outcome.state, UpdateCheckState.failed);
      expect(outcome.stoppedOnEntryIdentity, isTrue);
      expect(outcome.error, kEntryIdentityUnreliableMessage);
      expect(outcome.newEntries, 0);
    });

    test('writes no entry at all, not even the rows it could read', () async {
      // Entry 103 read cleanly and would have been a correct row. It is still
      // not written: the page it came from is being read incorrectly, and
      // taking the parts that happen to look right is how a half-corrupt
      // reading becomes permanent.
      await seedHolding100();
      browser.addPage(collectionIndexUrl, gluedPage());

      await checker.check('collection-1');

      final discovered = (await db.allEntries())
          .where((c) => c.saveStatus == 'knownRemote')
          .toList();
      expect(discovered, isEmpty);
    });

    test('leaves the checkpoint exactly where it was', () async {
      // The failure this exists to prevent: one 1046 written once makes every
      // later check ask for entries above 1046 and find none, so the
      // collection reports up to date for good.
      await seedHolding100();
      browser.addPage(collectionIndexUrl, gluedPage());

      await checker.check('collection-1');

      final numbers = (await db.allEntries()).map((c) => c.entryNumber);
      expect(numbers, [100.0]);
    });

    test('does not fall through to the chain walk', () async {
      await seedHolding100();
      browser.addPage(collectionIndexUrl, gluedPage());
      // Reachable, and full of entries — none of which may be walked, because
      // the doubt was about how this source is being read, not about this page.
      serveChain(100, 110);

      final outcome = await checker.check('collection-1');

      expect(outcome.state, UpdateCheckState.failed);
      expect(
        outcome.pagesInspected,
        1,
        reason: 'the collection page, and nothing after it',
      );
    });

    test('records the failure on the collection like any other', () async {
      await seedHolding100();
      browser.addPage(collectionIndexUrl, gluedPage());

      await checker.check('collection-1');

      final item = (await db.collectionById('collection-1'))!;
      expect(item.lastCheckResult, 'failed');
      expect(item.lastCheckError, kEntryIdentityUnreliableMessage);
      expect(
        item.lastCheckSuccessAt,
        isNull,
        reason: 'a refusal is not a successful check',
      );
    });

    test('keeps the evidence for a report that does not exist yet', () async {
      await seedHolding100();
      browser.addPage(collectionIndexUrl, gluedPage());

      final outcome = await checker.check('collection-1');

      final first = outcome.concerns.first;
      expect(outcome.concerns.map((c) => c.url), [
        entryUrl(101),
        entryUrl(102),
        entryUrl(104),
      ]);
      expect(first.labelNumber, 1012.0);
      expect(first.urlNumber, 101.0);
      expect(first.label, 'Entry 1012 weeks ago');
      expect(first.nearbyNumbers, contains(103.0));
    });

    test('a collection numbered its own way still checks normally', () async {
      // Gaps, a decimal, and a step that is not one — none of which is this
      // check's business. The whole point of the net is that it does not have
      // an opinion about numbering.
      await seedHolding100();
      browser.addPage(
        collectionIndexUrl,
        listPage(const [
          PageLink(href: '/guide/foo/130', text: 'Entry 130 2 days ago'),
          PageLink(href: '/guide/foo/120-5', text: 'Entry 120.5 a week ago'),
          PageLink(href: '/guide/foo/120', text: 'Entry 120 3 weeks ago'),
          PageLink(href: '/guide/foo/110', text: 'Entry 110 2 months ago'),
          PageLink(href: '/guide/foo/100', text: 'Entry 100 4 months ago'),
        ]),
      );

      final outcome = await checker.check('collection-1');

      expect(outcome.state, UpdateCheckState.updatesAvailable);
      expect(outcome.concerns, isEmpty);
      final discovered =
          (await db.allEntries())
              .where((c) => c.saveStatus == 'knownRemote')
              .toList()
            ..sort((a, b) => a.entryOrder.compareTo(b.entryOrder));
      expect(discovered.map((c) => c.entryNumber), [
        110.0,
        120.0,
        120.5,
        130.0,
      ]);
    });
  });
}
