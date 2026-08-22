import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_reader/browser/browsing_history.dart';
import 'package:web_reader/browser/saved_sites_repository.dart';
import 'package:web_reader/data/collection_repository.dart';
import 'package:web_reader/data/folder_repository.dart';
import 'package:web_reader/data/local_settings.dart';
import 'package:web_reader/data/schema.dart';
import 'package:web_reader/domain/collection.dart';
import 'package:web_reader/features/v2_composition.dart';
import 'package:web_reader/recognition/history.dart';

/// The recording rule (§7, D53), the clear ranges (§10) and the aggregation
/// (§9). This is the file that guards "save automation never pollutes
/// browsing history".
///
/// V1's `HistoryRepository` owned all three at once. They are three owners
/// now, over the one V2 `history` table: [HistoryStore] refuses everything
/// that is not a completed, user-performed load of a web page,
/// [BrowsingHistoryStore] is the browser surface in front of it (the collapse
/// window, the clear ranges, the retention sweep), and the grouping is pure
/// functions in `browsing_history.dart`. Each test below is aimed at whichever
/// of the three owns the rule it was written for.
void main() {
  late LibraryDatabase db;

  /// The gate: what is written at all, and the violation named when it is not.
  late HistoryStore store;

  /// The browser surface over it: what the Browser's navigation callback,
  /// the History screen and the clear sheet all talk to.
  late BrowsingHistoryStore history;

  setUp(() {
    db = LibraryDatabase.forTesting(NativeDatabase.memory());
    store = HistoryStore(db);
    history = BrowsingHistoryStore(db);
  });

  tearDown(() => db.close());

  /// One completed navigation, as the Browser reports it.
  Future<void> visit(
    String url, {
    String title = 'A page',
    NavigationSource source = NavigationSource.manual,
    bool completed = true,
    DateTime? at,
  }) => history.recordVisit(
    landedUrl: url,
    title: title,
    // The mapping the composition applies to every load: only [manual] is
    // the user, and every other source is a machine moving the same browser.
    userInitiated: source == NavigationSource.manual,
    completed: completed,
    at: at,
  );

  /// Newest first and bounded — what every screen reads.
  Future<List<HistoryRow>> visits({int limit = 200}) =>
      history.recent(limit: limit);

  group('what gets recorded', () {
    test('a completed manual visit is recorded', () async {
      await visit('https://example.com/guide/x/1', title: 'Ch 1');
      final rows = await visits();
      expect(rows, hasLength(1));
      final row = rows.single;
      expect(row.host, 'example.com');
      expect(row.title, 'Ch 1');
      expect(row.source, 'manual');
    });

    test('a page with no title reads as its host, not as blank', () async {
      // The fallback belongs to the browser surface, not to the store: a
      // title is a fact about the page, and *what to show when there is not
      // one* is a fact about the list it appears in.
      await visit('https://example.com/guide/x/1', title: '');

      expect((await visits()).single.title, 'example.com');
    });

    test('every automation source is excluded', () async {
      for (final source in NavigationSource.values) {
        if (source == NavigationSource.manual) continue;
        // Stated at the gate itself, so the refusal is a named invariant and
        // not merely an empty table.
        final (row, violation) = await store.recordVisit(
          url: 'https://example.com/guide/x/2',
          userInitiated: source == NavigationSource.manual,
        );
        expect(row, isNull, reason: source.name);
        expect(violation, historyNotUserInitiated, reason: source.name);

        await visit('https://example.com/guide/x/2', source: source);
      }
      expect(await visits(), isEmpty);
    });

    test('a save walking the entry chain leaves no history', () async {
      // What the save run does: many pages, one after another.
      for (var i = 1; i <= 12; i++) {
        await visit(
          'https://example.com/guide/x/$i',
          source: NavigationSource.saveAutomation,
        );
      }
      expect(await visits(), isEmpty);
    });

    test(
      'an update check reading a collection index leaves no history',
      () async {
        await visit(
          'https://example.com/guide/x',
          source: NavigationSource.updateCheck,
        );
        expect(await visits(), isEmpty);
      },
    );

    test('a load that never completed is not a destination', () async {
      final (row, violation) = await store.recordVisit(
        url: 'https://example.com/guide/x/1',
        userInitiated: true,
        completed: false,
      );
      expect(row, isNull);
      expect(violation, historyVisitIncomplete);

      await visit('https://example.com/guide/x/1', completed: false);
      expect(await visits(), isEmpty);
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
        final (row, violation) = await store.recordVisit(
          url: url,
          userInitiated: true,
        );
        expect(row, isNull, reason: url);
        expect(violation, historyNotAWebPage, reason: url);

        await visit(url);
      }
      expect(await visits(), isEmpty);
    });
  });

  group('repeated visits', () {
    test('a reload inside the window refreshes one row', () async {
      final start = DateTime(2026, 7, 28, 12);
      await visit('https://a.example/x', at: start);
      final first = (await visits()).single;

      final again = start.add(const Duration(minutes: 5));
      await visit('https://a.example/x', at: again);

      final rows = await visits();
      expect(rows, hasLength(1));
      expect(rows.single.id, first.id, reason: 'same row, not a second');
      expect(rows.single.visitedAt.isAtSameMomentAs(again), isTrue);
    });

    test('a visit outside the window is its own row', () async {
      final start = DateTime(2026, 7, 28, 12);
      await visit('https://a.example/x', at: start);
      await visit(
        'https://a.example/x',
        at: start.add(kVisitCollapseWindow + const Duration(minutes: 1)),
      );
      expect(await visits(), hasLength(2));
    });

    test('different pages on one host are different rows', () async {
      await visit('https://a.example/x');
      await visit('https://a.example/y');
      expect(await visits(), hasLength(2));
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
      expect(await visits(), hasLength(3));
    });

    test('today is the calendar day, not the last 24 hours', () async {
      expect(await history.clear(HistoryClearRange.today, now: now), 2);
      expect(await visits(), hasLength(2));
    });

    test('last 7 days', () async {
      expect(await history.clear(HistoryClearRange.lastSevenDays, now: now), 3);
      expect(await visits(), hasLength(1));
    });

    test('all time empties it', () async {
      expect(await history.clear(HistoryClearRange.allTime, now: now), 4);
      expect(await visits(), isEmpty);
    });

    test('clearing history keeps saved sites, library and settings', () async {
      final saved = SavedSitesRepository(db);
      // Two rows the *user* saved. There is no seeded row to make up the count,
      // and the point of the test is that clearing history reaches none of them.
      await saved.save(url: 'https://a.example/', title: 'A');
      await saved.save(url: 'https://b.example/', title: 'B');
      final settings = LocalSettingsStore(db);
      await settings.set('collection.entrySort', 'newestFirst');
      final root = await FolderRepository(db).ensureRoot();
      final (collection, violation) = await CollectionRepository(db).create(
        name: 'Collection',
        folderId: root.id,
        orderingBasis: OrderingBasis.discoveryOrder,
      );
      expect(violation, isNull);
      expect(collection, isNotNull);

      await history.clear(HistoryClearRange.allTime, now: now);

      expect(
        (await saved.all()).map((s) => s.title),
        ['A', 'B'],
        reason: 'clearing history must not reach the saved-sites list',
      );
      expect(await settings.get('collection.entrySort'), 'newestFirst');
      expect(await db.select(db.collections).get(), hasLength(1));
    });
  });

  group('removal by row and by site', () {
    test('one visit can be removed', () async {
      await visit('https://a.example/1');
      final row = (await visits()).single;
      await visit('https://a.example/2');
      expect(await history.removeVisit(row.id), 1);
      expect(await visits(), hasLength(1));
    });

    test('every visit to a site can be removed', () async {
      await visit('https://a.example/1');
      await visit('https://a.example/2');
      await visit('https://b.example/3');
      expect(await history.removeHost('a.example'), 2);
      final rows = await visits();
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

      final groups = groupVisitsByDay(await visits(), now: now);
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

      final hosts = groupVisitsByHost(await visits());
      expect(hosts.first.host, 'a.example', reason: 'most recently active');
      expect(hosts.first.visitCount, 2);
      expect(hosts.first.latestUrl, 'https://a.example/new');
      expect(hosts.first.latestTitle, 'Newest');
      expect(hosts.first.siteRoot, 'https://a.example/');
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
      final rows = await visits();
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
      expect(await visits(), hasLength(30));
    });
  });

  group('performance', () {
    test('the recent query is bounded, not the whole table', () async {
      final now = DateTime(2026, 7, 28);
      await db.batch((batch) {
        batch.insertAll(db.history, [
          for (var i = 0; i < 900; i++)
            HistoryRow(
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

      expect(await visits(limit: 200), hasLength(200));
      // Newest first, so a bounded read is the *useful* 200.
      expect((await visits(limit: 5)).first.url, 'https://a.example/0');
    });
  });
}
