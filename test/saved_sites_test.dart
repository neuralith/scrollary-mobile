import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_reader/browser/saved_sites_repository.dart';
import 'package:web_reader/storage/database.dart';

/// Saved sites are the user's own list (§4, D54): seeded once, editable in
/// every direction, never silently duplicated, and never recreated behind
/// their back.
void main() {
  late AppDatabase db;
  late SavedSitesRepository repo;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = SavedSitesRepository(db);
  });

  tearDown(() => db.close());

  group('nothing is seeded', () {
    test('a clean install has an empty saved-sites list', () async {
      // The app ships no starting point. A pre-seeded site is a recommendation
      // it is not entitled to make, and a "supported starting point" is how a
      // neutral reading tool acquires a provider catalogue by accident.
      expect(await repo.all(), isEmpty);
    });

    test('the list only ever holds what the user put in it', () async {
      await repo.save(url: 'https://example.test/', title: 'Example');
      final sites = await repo.all();
      expect(sites, hasLength(1));
      expect(sites.single.title, 'Example');
    });

    test('a removed site stays removed', () async {
      final saved = await repo.save(
        url: 'https://example.test/',
        title: 'Example',
      );
      await repo.remove(saved.site.id);
      expect(await repo.all(), isEmpty);
    });
  });

  group('duplicates', () {
    test(
      'an already-saved URL reports the existing row, not a second',
      () async {
        await repo.save(url: 'https://a.example/page', title: 'A');
        final again = await repo.save(
          url: 'https://a.example/page',
          title: 'B',
        );
        expect(again.outcome, SaveSiteOutcome.duplicate);
        expect(
          again.site.title,
          'A',
          reason: 'untouched until the user says so',
        );
        expect(await repo.all(), hasLength(1));
      },
    );

    test('updateExisting edits the existing tile instead of adding', () async {
      await repo.save(url: 'https://a.example/page', title: 'A');
      final updated = await repo.save(
        url: 'https://a.example/page',
        title: 'Renamed',
        updateExisting: true,
      );
      expect(updated.outcome, SaveSiteOutcome.updated);
      final sites = await repo.all();
      expect(sites, hasLength(1));
      expect(savedSiteDisplayTitle(sites.single), 'Renamed');
    });

    test('URLs that only differ by tracking noise are the same site', () async {
      await repo.save(url: 'https://a.example/page', title: 'A');
      final again = await repo.save(
        url: 'https://a.example/page?utm_source=x',
        title: 'A',
      );
      expect(again.outcome, SaveSiteOutcome.duplicate);
    });

    test('two pages on one host are two saved sites', () async {
      await repo.save(url: 'https://a.example/one', title: 'One');
      final second = await repo.save(
        url: 'https://a.example/two',
        title: 'Two',
      );
      expect(second.outcome, SaveSiteOutcome.created);
      expect(await repo.all(), hasLength(2));
    });

    test(
      'editing a row into its own URL is not a duplicate of itself',
      () async {
        final created = await repo.save(url: 'https://a.example/x', title: 'A');
        final edited = await repo.save(
          url: 'https://a.example/x',
          title: 'A renamed',
          editingId: created.site.id,
        );
        expect(edited.outcome, SaveSiteOutcome.updated);
        expect(await repo.all(), hasLength(1));
      },
    );
  });

  group('ordering', () {
    setUp(() async {
      for (final name in ['A', 'B', 'C']) {
        await repo.save(url: 'https://$name.example/', title: name);
      }
    });

    test('new sites go to the back', () async {
      expect((await repo.all()).map((s) => s.title), ['A', 'B', 'C']);
    });

    test('moving up and down persists', () async {
      final sites = await repo.all();
      await repo.move(sites[2].id, up: true);
      expect((await repo.all()).map((s) => s.title), ['A', 'C', 'B']);

      await repo.move(sites[2].id, up: false);
      expect((await repo.all()).map((s) => s.title), ['A', 'B', 'C']);
    });

    test('moving past either end does nothing', () async {
      final sites = await repo.all();
      await repo.move(sites.first.id, up: true);
      await repo.move(sites.last.id, up: false);
      expect((await repo.all()).map((s) => s.title), ['A', 'B', 'C']);
    });

    test('rows that were never reordered still have a stable order', () async {
      // Equal indices are what a seeded/imported set looks like; the fallback
      // is creation time, so the list never shuffles between reads.
      for (final site in await repo.all()) {
        await db.writeSavedSite(
          site.id,
          const SavedSitesCompanion(orderIndex: Value(0)),
        );
      }
      final first = (await repo.all()).map((s) => s.title).toList();
      final second = (await repo.all()).map((s) => s.title).toList();
      expect(first, second);
      expect(first, ['A', 'B', 'C']);
    });
  });

  group('naming', () {
    test(
      'a rename shows, and clearing it falls back to the page title',
      () async {
        final created = await repo.save(
          url: 'https://a.example/',
          title: 'Page title',
        );
        await repo.rename(created.site.id, 'My name');
        expect(savedSiteDisplayTitle((await repo.all()).single), 'My name');

        await repo.rename(created.site.id, '');
        expect(savedSiteDisplayTitle((await repo.all()).single), 'Page title');
      },
    );

    test(
      'an empty title falls back to the host rather than saving blank',
      () async {
        final created = await repo.save(
          url: 'https://a.example/x',
          title: '  ',
        );
        expect(savedSiteDisplayTitle(created.site), 'a.example');
      },
    );
  });

  group('persistence', () {
    test('saved sites and their order survive a repository rebuild', () async {
      await repo.save(url: 'https://a.example/', title: 'A');
      await repo.save(url: 'https://b.example/', title: 'B');
      // Hand order is the point of this list, so the reordering has to survive
      // too — not just the rows.
      await repo.move((await repo.all()).last.id, up: true);
      expect((await repo.all()).map((s) => s.title), ['B', 'A']);

      // Same database, new repository — what a restart looks like to this
      // layer.
      final reborn = SavedSitesRepository(db);
      expect((await reborn.all()).map((s) => s.title), ['B', 'A']);
      expect(await reborn.isSaved('https://a.example/'), isTrue);
      expect(await reborn.isSaved('https://b.example/'), isTrue);
    });

    test('lookup is by normalised URL, not raw text', () async {
      await repo.save(url: 'https://a.example/page/', title: 'A');
      expect(await repo.isSaved('https://a.example/page'), isTrue);
      expect(await repo.isSaved('https://a.example/other'), isFalse);
    });
  });

  test('hundreds of saved sites stay manageable', () async {
    for (var i = 0; i < 300; i++) {
      await repo.save(url: 'https://site$i.example/', title: 'Site $i');
    }
    final watch = Stopwatch()..start();
    final sites = await repo.all();
    watch.stop();
    expect(sites, hasLength(300));
    expect(sites.first.title, 'Site 0');
    expect(sites.last.title, 'Site 299');
    expect(watch.elapsedMilliseconds, lessThan(1000));
  });
}
