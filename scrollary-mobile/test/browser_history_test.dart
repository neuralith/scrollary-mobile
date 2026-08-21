import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_reader/browser/history_repository.dart';
import 'package:web_reader/browser/saved_sites_repository.dart';
import 'package:web_reader/storage/database.dart';

/// The recording rule (§7, D53), the clear ranges (§10) and the aggregation
/// (§9). This is the file that guards "save automation never pollutes
/// browsing history".
void main() {
  late AppDatabase db;
  late HistoryRepository history;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    history = HistoryRepository(db);
  });

  tearDown(() => db.close());

  Future<BrowsingHistoryData?> visit(
    String url, {
    String title = 'A page',
    NavigationSource source = NavigationSource.manual,
    bool completed = true,
    DateTime? at,
  }) => history.recordVisit(
    url: url,
    title: title,
    source: source,
    completed: completed,
    now: at,
  );

  group('what gets recorded', () {
    test('a completed manual visit is recorded', () async {
      final row = await visit('https://example.com/guide/x/1', title: 'Ch 1');
      expect(row, isNotNull);
      expect(row!.host, 'example.com');
      expect(row.title, 'Ch 1');
      expect(row.source, 'manual');
      expect(await db.visits(), hasLength(1));
    });

    test('every automation source is excluded', () async {
      for (final source in NavigationSource.values) {
        if (source == NavigationSource.manual) continue;
        expect(
          await visit('https://example.com/guide/x/2', source: source),
          isNull,
          reason: source.name,
        );
      }
      expect(await db.visits(), isEmpty);
    });

    test('a save walking the entry chain leaves no history', () async {
      // What the save run does: many pages, one after another.
      for (var i = 1; i <= 12; i++) {
        await visit(
          'https://example.com/guide/x/$i',
          source: NavigationSource.saveAutomation,
        );
      }
      expect(await db.visits(), isEmpty);
    });

    test(
      'an update check reading a collection index leaves no history',
      () async {
        await visit(
          'https://example.com/guide/x',
          source: NavigationSource.updateCheck,
        );
        expect(await db.visits(), isEmpty);
      },
    );

    test('a load that never completed is not a destination', () async {
      expect(
        await visit('https://example.com/guide/x/1', completed: false),
        isNull,
      );
    });

    test('non-page URLs are excluded', () async {
      for (final url in [
        'about:blank',
        '',
        '   ',
        'reader://open?entry=1',
        'data:text/html,hello',
        'file:///tmp/x.html',
      ]) {
        expect(await visit(url), isNull, reason: url);
      }
      expect(await db.visits(), isEmpty);
    });

    test('a page with no title reads as its host, not as blank', () async {
      final row = await visit('https://example.com/guide/x/1', title: '  ');
      expect(row!.title, 'example.com');
    });
  });

  group('repeated visits', () {
    test('a reload inside the window refreshes one row', () async {
      final start = DateTime(2026, 7, 28, 12);
      final first = await visit('https://a.example/x', at: start);
      final second = await visit(
        'https://a.example/x',
        at: start.add(const Duration(minutes: 5)),
      );
      expect(second!.id, first!.id, reason: 'same row, not a second');
      final rows = await db.visits();
      expect(rows, hasLength(1));
      expect(rows.single.visitedAt, start.add(const Duration(minutes: 5)));
    });

    test('a visit outside the window is its own row', () async {
      final start = DateTime(2026, 7, 28, 12);
      await visit('https://a.example/x', at: start);
      await visit(
        'https://a.example/x',
        at: start.add(kVisitCollapseWindow + const Duration(minutes: 1)),
      );
      expect(await db.visits(), hasLength(2));
    });

    test('different pages on one host are different rows', () async {
      await visit('https://a.example/x');
      await visit('https://a.example/y');
      expect(await db.visits(), hasLength(2));
    });
  });

  group('clear ranges', () {
    late DateTime now;

    setUp(() async {
      now = DateTime(2026, 7, 28, 15);
      await visit(
        'https://a.example/1',
        at: now.subtract(const Duration(minutes: 20)),
      );
      await visit(
        'https://a.example/2',
        at: now.subtract(const Duration(hours: 5)),
      );
      await visit(
        'https://b.example/3',
        at: now.subtract(const Duration(days: 3)),
      );
      await visit(
        'https://c.example/4',
        at: now.subtract(const Duration(days: 30)),
      );
    });

    test('counts are read before anything is deleted', () async {
      expect(await history.countIn(HistoryClearRange.lastHour, now: now), 1);
      expect(await history.countIn(HistoryClearRange.today, now: now), 2);
      expect(
        await history.countIn(HistoryClearRange.lastSevenDays, now: now),
        3,
      );
      expect(await history.countIn(HistoryClearRange.allTime, now: now), 4);
    });

    test('last hour removes only the last hour', () async {
      expect(await history.clear(HistoryClearRange.lastHour, now: now), 1);
      expect(await db.visits(), hasLength(3));
    });

    test('today is the calendar day, not the last 24 hours', () async {
      expect(await history.clear(HistoryClearRange.today, now: now), 2);
      expect(await db.visits(), hasLength(2));
    });

    test('last 7 days', () async {
      expect(await history.clear(HistoryClearRange.lastSevenDays, now: now), 3);
      expect(await db.visits(), hasLength(1));
    });

    test('all time empties it', () async {
      expect(await history.clear(HistoryClearRange.allTime, now: now), 4);
      expect(await db.visits(), isEmpty);
    });

    test('clearing history keeps saved sites, library and settings', () async {
      final saved = SavedSitesRepository(db);
      // Two rows the *user* saved. There is no seeded row to make up the count,
      // and the point of the test is that clearing history reaches none of them.
      await saved.save(url: 'https://a.example/', title: 'A');
      await saved.save(url: 'https://b.example/', title: 'B');
      await db.setSetting('collection.entrySort', 'newestFirst');
      await db.upsertCollection(
        Collection(
          contentKind: 'unknownWebContent',
          sequenceKind: 'none',
          orderingBasis: 'discoveryOrder',
          shapeConfidence: 'low',
          id: 'item-1',
          title: 'Collection',
          sourceUrl: 'https://a.example/collection',
          host: 'a.example',
          createdAt: now,
          lifecycle: 'active',
        ),
      );

      await history.clear(HistoryClearRange.allTime, now: now);

      expect(
        (await db.allSavedSites()).map((s) => s.title),
        ['A', 'B'],
        reason: 'clearing history must not reach the saved-sites list',
      );
      expect(await db.setting('collection.entrySort'), 'newestFirst');
      expect(await db.allCollections(), hasLength(1));
    });
  });

  group('removal by row and by site', () {
    test('one visit can be removed', () async {
      final row = await visit('https://a.example/1');
      await visit('https://a.example/2');
      expect(await history.removeVisit(row!.id), 1);
      expect(await db.visits(), hasLength(1));
    });

    test('every visit to a site can be removed', () async {
      await visit('https://a.example/1');
      await visit('https://a.example/2');
      await visit('https://b.example/3');
      expect(await history.removeHost('a.example'), 2);
      final rows = await db.visits();
      expect(rows, hasLength(1));
      expect(rows.single.host, 'b.example');
    });
  });

  group('grouping', () {
    test('by day, in display order, with empty groups dropped', () async {
      final now = DateTime(2026, 7, 28, 15);
      await visit(
        'https://a.example/1',
        at: now.subtract(const Duration(hours: 2)),
      );
      await visit(
        'https://a.example/2',
        at: now.subtract(const Duration(days: 1)),
      );
      await visit(
        'https://a.example/3',
        at: now.subtract(const Duration(days: 9)),
      );

      final groups = groupVisitsByDay(await db.visits(), now: now);
      expect(groups.map((g) => g.$1), [
        HistoryDayGroup.today,
        HistoryDayGroup.yesterday,
        HistoryDayGroup.earlier,
      ]);
      expect(groups.every((g) => g.$2.isNotEmpty), isTrue);
    });

    test('by host, with counts and the latest page', () async {
      final now = DateTime(2026, 7, 28, 15);
      await visit(
        'https://a.example/old',
        at: now.subtract(const Duration(days: 2)),
      );
      await visit(
        'https://a.example/new',
        title: 'Newest',
        at: now.subtract(const Duration(minutes: 5)),
      );
      await visit(
        'https://b.example/1',
        at: now.subtract(const Duration(days: 1)),
      );

      final hosts = HistoryRepository.groupByHost(await db.visits());
      expect(hosts.first.host, 'a.example', reason: 'most recently active');
      expect(hosts.first.visitCount, 2);
      expect(hosts.first.latestUrl, 'https://a.example/new');
      expect(hosts.first.latestTitle, 'Newest');
      expect(hosts.first.siteRoot, 'https://a.example/');
    });
  });

  group('search', () {
    // Two visits on **different hosts**. Search covers three columns, so the
    // fixture has to be able to tell them apart — one host matching both rows
    // cannot show that a host query is a host query.
    setUp(() async {
      await visit(
        'https://a.example/guide/long-guide/885',
        title: 'The Long Guide',
      );
      await visit('https://b.example/notes/field/137', title: 'Field Notes');
    });

    test('matches title, URL and host', () async {
      expect(await history.search('long guide'), hasLength(1), reason: 'title');
      expect(await history.search('notes/field'), hasLength(1), reason: 'url');
      expect(await history.search('b.example'), hasLength(1), reason: 'host');
      expect(
        await history.search('example'),
        hasLength(2),
        reason: 'a query both hosts share matches both',
      );
    });

    test('is case-insensitive', () async {
      expect(await history.search('FIELD NOTES'), hasLength(1));
      expect(await history.search('field notes'), hasLength(1));
    });

    test('an empty query returns everything', () async {
      expect(await history.search('   '), hasLength(2));
    });
  });

  group('retention', () {
    test('drops rows older than the age bound', () async {
      final now = DateTime(2026, 7, 28);
      await visit(
        'https://a.example/old',
        at: now.subtract(const Duration(days: 200)),
      );
      await visit(
        'https://a.example/new',
        at: now.subtract(const Duration(days: 2)),
      );

      expect(await history.prune(now: now), 1);
      final rows = await db.visits();
      expect(rows, hasLength(1));
      expect(rows.single.url, 'https://a.example/new');
    });

    test('recent history is never silently removed', () async {
      final now = DateTime(2026, 7, 28);
      for (var i = 0; i < 30; i++) {
        await visit(
          'https://a.example/$i',
          at: now.subtract(Duration(days: i)),
        );
      }
      expect(await history.prune(now: now), 0);
      expect(await db.visits(), hasLength(30));
    });
  });

  group('performance', () {
    test('10,000 seeded visits stay searchable', () async {
      final now = DateTime(2026, 7, 28);
      await db.batch((batch) {
        batch.insertAll(db.browsingHistory, [
          for (var i = 0; i < 10000; i++)
            BrowsingHistoryData(
              id: 'v$i',
              url: 'https://site${i % 40}.example/page/$i',
              urlKey: 'https://site${i % 40}.example/page/$i',
              host: 'site${i % 40}.example',
              title: i == 7777 ? 'The needle' : 'Page $i',
              source: 'manual',
              completed: true,
              visitedAt: now.subtract(Duration(minutes: i)),
            ),
        ]);
      });

      final watch = Stopwatch()..start();
      final hits = await history.search('The needle');
      watch.stop();
      expect(hits, hasLength(1));
      expect(
        watch.elapsedMilliseconds,
        lessThan(2000),
        reason: 'search over 10k rows must stay interactive',
      );
    });

    test('the recent query is bounded, not the whole table', () async {
      final now = DateTime(2026, 7, 28);
      await db.batch((batch) {
        batch.insertAll(db.browsingHistory, [
          for (var i = 0; i < 900; i++)
            BrowsingHistoryData(
              id: 'v$i',
              url: 'https://a.example/$i',
              urlKey: 'https://a.example/$i',
              host: 'a.example',
              title: 'Page $i',
              source: 'manual',
              completed: true,
              visitedAt: now.subtract(Duration(minutes: i)),
            ),
        ]);
      });

      expect(await db.visits(limit: 200), hasLength(200));
      // Newest first, so a bounded read is the *useful* 200.
      expect((await db.visits(limit: 5)).first.url, 'https://a.example/0');
    });
  });
}
