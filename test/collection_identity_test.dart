import 'package:flutter_test/flutter_test.dart';
import 'package:web_reader/library/collection_identity.dart';
import 'package:web_reader/library/entry_labels.dart';

void main() {
  group('collection title from an entry page title', () {
    test('strips a Turkish entry marker and the site tagline', () {
      expect(
        collectionTitleFromPageTitle(
          'The Long Guide 883. part - Türkçe guide Oku |',
        ),
        'The Long Guide',
      );
    });

    test('strips an English entry marker and the site name', () {
      expect(
        collectionTitleFromPageTitle(
          "Setup Notes Part 101 - Read Online | Example Docs",
        ),
        'Setup Notes',
      );
    });

    test('strips a German entry marker', () {
      expect(
        collectionTitleFromPageTitle('Der Held Kapitel 42 | LesenOnline'),
        'Der Held',
      );
    });

    test('leaves a title with no entry marker alone', () {
      expect(
        collectionTitleFromPageTitle('Some Collection'),
        'Some Collection',
      );
    });

    test('handles empty and null input', () {
      expect(collectionTitleFromPageTitle(null), isNull);
      expect(collectionTitleFromPageTitle('   '), isNull);
    });
  });

  group('entry numbers', () {
    test('reads a number next to an entry word, in any of the languages', () {
      expect(parseEntryNumber(title: 'Foo Entry 101'), 101);
      expect(parseEntryNumber(title: 'Foo 883. part'), 883);
      expect(parseEntryNumber(title: 'Der Held Kapitel 42'), 42);
    });

    test('supports decimal entries', () {
      expect(parseEntryNumber(title: 'Foo Entry 12.5'), 12.5);
    });

    test('falls back to the URL when the title has no number', () {
      expect(
        parseEntryNumber(
          title: 'Some Collection',
          url: 'https://x.example/guide/foo/884-part-oku',
        ),
        884,
      );
    });

    test('returns null for a non-numeric identifier', () {
      // "Extra" and "Prologue" are real entry names; they must not be
      // coerced to 0, which would drag them to the front of the list.
      expect(
        parseEntryNumber(
          title: 'Foo — Extra',
          url: 'https://x.example/foo/extra',
        ),
        isNull,
      );
    });
  });

  group('entry labels', () {
    test('keeps the marker the site used', () {
      expect(
        sourceMarkerFrom(title: 'The Long Guide 883. part - Oku'),
        '883. part',
      );
      expect(
        sourceMarkerFrom(title: 'Setup Notes Part 101 - Read'),
        'Part 101',
      );
    });

    test('falls back to the number, then to the URL segment', () {
      // The marker holds what the *source* wrote. With only a parsed number to
      // go on that is the number itself — naming it "Entry 7" would put the
      // app's own vocabulary into the field that exists to hold the source's,
      // and the display label is where the app's word belongs.
      expect(sourceMarkerFrom(title: 'Untitled', number: 7), '7');
      expect(
        sourceMarkerFrom(title: '', url: 'https://x.example/foo/prologue'),
        'prologue',
      );
    });
  });

  group('collection identity', () {
    test('three entries of one collection resolve to one key', () {
      final ids = [
        'https://a.example/guide/the-long-guide/883-part-oku',
        'https://a.example/guide/the-long-guide/884-part-oku',
        'https://a.example/guide/the-long-guide/885-part-oku',
      ].map((u) => resolveCollectionIdentity(entryUrl: u)).toList();

      expect(ids.map((i) => i.collectionKey).toSet(), hasLength(1));
      expect(ids.first.collectionKey, '/guide/the-long-guide');
      expect(ids.first.confidence, IdentityConfidence.high);
    });

    test('two collection on the same host stay apart', () {
      final a = resolveCollectionIdentity(
        entryUrl: 'https://a.example/guide/collection-a/1-part-oku',
      );
      final b = resolveCollectionIdentity(
        entryUrl: 'https://a.example/guide/collection-b/1-part-oku',
      );

      expect(a.host, b.host);
      expect(
        a.collectionKey,
        isNot(b.collectionKey),
        reason: 'same host must not mean same collection',
      );
    });

    test('the two real layouts each get their own key', () {
      final first = resolveCollectionIdentity(
        entryUrl: 'https://example.com/guide/the-long-guide/883-part-oku',
      );
      final second = resolveCollectionIdentity(
        entryUrl: 'https://example.com/comics/setup-notes-f886a8af/entry/101',
      );

      expect(first.collectionKey, '/guide/the-long-guide');
      expect(second.collectionKey, '/comics/setup-notes-f886a8af');
    });

    test(
      'a link back to the collection index wins, and names the collection',
      () {
        final identity = resolveCollectionIdentity(
          entryUrl: 'https://x.example/guide/slug-abc/883-part-oku',
          pageTitle: 'Slug ABC 883. part - Oku',
          hints: const PageHints(
            prefixLinks: [
              PageRef(
                href: 'https://x.example/guide/slug-abc',
                path: '/guide/slug-abc',
                text: 'The Long Guide',
              ),
              PageRef(
                href: 'https://x.example/guide',
                path: '/guide',
                text: 'All guide',
              ),
            ],
          ),
        );

        expect(identity.basis, 'collection link');
        expect(identity.collectionKey, '/guide/slug-abc');
        expect(identity.detectedTitle, 'The Long Guide');
        expect(identity.collectionIndexUrl, 'https://x.example/guide/slug-abc');
      },
    );

    test('og:title is preferred over the page title for the name', () {
      final identity = resolveCollectionIdentity(
        entryUrl: 'https://x.example/guide/foo/12',
        pageTitle: 'Foo Entry 12 - Read free | SiteName',
        hints: const PageHints(ogTitle: 'Foo: The Real Title Entry 12'),
      );
      expect(identity.detectedTitle, 'Foo: The Real Title');
    });

    test('a flat URL falls back to the title, keyed per collection', () {
      final a = resolveCollectionIdentity(
        entryUrl: 'https://x.example/',
        pageTitle: 'Collection One Entry 3',
      );
      final b = resolveCollectionIdentity(
        entryUrl: 'https://x.example/',
        pageTitle: 'Collection Two Entry 3',
      );

      expect(a.confidence, IdentityConfidence.medium);
      expect(a.collectionKey, isNot(b.collectionKey));
      expect(a.canMerge, isTrue);
    });

    // A site given over entirely to one work publishes its entries with
    // nothing above them but the domain, so the fingerprint strips the only
    // segment there is. That leaves `/`, which is a real collection path —
    // and, being a prefix of every address on the host, one that has to be
    // claimed narrowly. `addressKeysRoot` is where the narrowness lives
    // (V2-D72); these pin its two halves at the identity level, and
    // `test/recognition/root_source_test.dart` proves what it means for
    // membership.
    test('an entry published straight off the domain keys the root', () {
      final identity = resolveCollectionIdentity(
        entryUrl: 'https://x.example/quiet-harbour-chapter-561/',
        pageTitle: 'Quiet Harbour Chapter 561 - Quiet Harbour',
      );

      expect(identity.collectionKey, '/');
      expect(identity.confidence, IdentityConfidence.high);
      expect(identity.basis, 'root fingerprint');
      expect(
        identity.collectionIndexUrl,
        'https://x.example/',
        reason: 'the listing of a work published at the root is the root',
      );
    });

    test('consecutive entries of it resolve to the one key', () {
      final keys = [561, 562, 563]
          .map(
            (n) => resolveCollectionIdentity(
              entryUrl: 'https://x.example/quiet-harbour-chapter-$n/',
            ).collectionKey,
          )
          .toSet();

      expect(keys, {'/'});
    });

    // **Identity and membership are two questions.** They were one predicate
    // (V2-D72), which is right for the key and wrong for the list: a root
    // Source whose Entries live below a segment matched none of its own
    // links. These pin the split — the key stays strict, the list is read by
    // the entry reading.
    test('an address below a segment keys no root but can be one of its '
        'Entries', () {
      const entry = 'https://x.example/entry/1';
      expect(
        addressKeysRoot(entry),
        isFalse,
        reason: 'two segments never key the root — the key rule is unchanged',
      );
      expect(
        addressIsRootMember(url: entry, label: 'Entry 1'),
        isTrue,
        reason: 'but a listing that says so is what makes it a member',
      );
    });

    test('membership still keeps the rest of the site out', () {
      for (final url in [
        'https://x.example/about-us/',
        'https://x.example/contact/',
        'https://x.example/tag/action/',
        'https://x.example/parts/',
        // **A number is not an entry number.** The address reading's last
        // resort takes any bare number in the final segment, and a real
        // listing links to plenty: pagination, year archives, a numbered tag.
        // Membership asks for an entry word as well.
        'https://x.example/page/2',
        'https://x.example/archive/2024',
        'https://x.example/tag/90s',
      ]) {
        expect(
          addressIsRootMember(url: url),
          isFalse,
          reason: '$url names no entry, so it joins no work',
        );
      }
    });

    test('every address that keys the root is one of its Entries', () {
      // Membership is a **widening** of the key, never a narrowing: V2-D72's
      // own shape publishes at `/12`, which carries no entry word for the
      // address half to find, and a site that works today must go on working.
      for (final url in [
        'https://x.example/12',
        'https://x.example/quiet-harbour-chapter-561/',
        'https://x.example/bolum-88',
      ]) {
        expect(addressKeysRoot(url), isTrue, reason: 'precondition for $url');
        expect(
          addressIsRootMember(url: url),
          isTrue,
          reason: '$url keys the root, so it is on it',
        );
      }
    });

    test('a label the listing printed answers where the address does not', () {
      // Sites that address entries by slug still print a number beside them.
      expect(
        addressIsRootMember(
          url: 'https://x.example/read/the-quiet-morning',
          label: 'Chapter 12',
        ),
        isTrue,
      );
      expect(
        addressIsRootMember(url: 'https://x.example/read/the-quiet-morning'),
        isFalse,
        reason: 'and with nothing printed, the address answers alone',
      );
    });

    test('the root is claimed only where the address numbers an entry', () {
      // `/chapters/` strips exactly as an entry segment does, so the
      // fingerprint alone would call it the root. It is an index, and the
      // absence of a number is what refuses it.
      final index = resolveCollectionIdentity(
        entryUrl: 'https://x.example/chapters/',
        pageTitle: 'Chapters',
      );

      expect(index.collectionKey, isNot('/'));
      expect(index.confidence, isNot(IdentityConfidence.high));
    });

    // The residual, kept visible on purpose: whether a root-level entry keys
    // the root depends on the fingerprint recognising its slug as an entry
    // segment. A slug that carries its number but no entry word does not
    // strip, so the entry's own address becomes the key and each entry keys a
    // Source of its own. Unchanged by V2-D72, and not something the root rule
    // can reach without loosening the fingerprint for every site.
    test('a root-level entry whose slug carries no entry word still keys '
        'itself', () {
      final first = resolveCollectionIdentity(
        entryUrl: 'https://x.example/quiet-harbour-561/',
      );
      final second = resolveCollectionIdentity(
        entryUrl: 'https://x.example/quiet-harbour-562/',
      );

      expect(first.collectionKey, '/quiet-harbour-561');
      expect(second.collectionKey, isNot(first.collectionKey));
    });

    test('nothing to go on is low confidence and must not merge', () {
      final identity = resolveCollectionIdentity(
        entryUrl: 'https://x.example/',
      );
      expect(identity.confidence, IdentityConfidence.low);
      expect(
        identity.canMerge,
        isFalse,
        reason: 'an extra group is recoverable; a wrong merge is not',
      );
    });
  });

  group('entry ordering', () {
    ({double? number, int entryOrder, DateTime? savedAt}) ch(
      double? number,
      int entryOrder, [
      DateTime? at,
    ]) => (number: number, entryOrder: entryOrder, savedAt: at);

    test('parsed number wins over save entryOrder', () {
      final list = [ch(885, 1), ch(883, 2), ch(884, 3)]
        ..sort(compareEntriesForReading);
      expect(list.map((c) => c.number), [883, 884, 885]);
    });

    test('decimal entries slot between integers', () {
      final list = [ch(13, 1), ch(12.5, 2), ch(12, 3)]
        ..sort(compareEntriesForReading);
      expect(list.map((c) => c.number), [12, 12.5, 13]);
    });

    test('unnumbered entries sort after numbered ones, by entryOrder', () {
      final list = [ch(null, 2), ch(5, 9), ch(null, 1)]
        ..sort(compareEntriesForReading);
      expect(list.first.number, 5);
      expect(list[1].entryOrder, 1);
      expect(list[2].entryOrder, 2);
    });

    test('save time breaks a full tie', () {
      final early = DateTime(2026, 1, 1);
      final late = DateTime(2026, 6, 1);
      final list = [ch(null, 0, late), ch(null, 0, early)]
        ..sort(compareEntriesForReading);
      expect(list.first.savedAt, early);
    });
  });

  group('entry numbers from real-world shapes', () {
    test('localized wrappers, both word orders', () {
      expect(parseEntryNumber(title: 'Entry 487'), 487);
      expect(parseEntryNumber(title: '487. part'), 487);
      expect(parseEntryNumber(title: 'part 487'), 487);
      expect(parseEntryNumber(title: 'Kapitel 12'), 12);
      expect(parseEntryNumber(title: 'Capítulo 33'), 33);
      expect(parseEntryNumber(title: 'Entry 9'), 9);
    });

    test('decimals, with either separator', () {
      expect(parseEntryNumber(title: 'Entry 487.5'), 487.5);
      expect(parseEntryNumber(title: '487,5. part'), 487.5);
      expect(parseEntryNumber(title: 'part 385,5'), 385.5);
    });

    test('URLs: word-then-number, number-then-word, and path separators', () {
      expect(
        parseEntryNumber(url: 'https://x.example/comics/slug/entry/137'),
        137,
      );
      expect(
        parseEntryNumber(url: 'https://x.example/guide/foo/883-part-oku'),
        883,
      );
      expect(parseEntryNumber(url: 'https://x.example/s/entry-101'), 101);
    });

    test('a URL decimal is only read next to an entry word', () {
      expect(
        parseEntryNumber(url: 'https://x.example/s/entry-385-5'),
        385.5,
        reason: 'the site spells 385.5 this way',
      );
      expect(
        parseEntryNumber(url: 'https://x.example/s/12-3'),
        12,
        reason: 'no entry word: 12-3 is as likely a date as a decimal',
      );
    });

    test('headings and breadcrumbs are read when the title is unhelpful', () {
      expect(
        parseEntryNumber(
          title: 'Read Online | Example Docs',
          extra: const ['Entry 512', null],
        ),
        512,
      );
      expect(
        parseEntryNumber(
          title: 'guide Oku',
          url: 'https://x.example/s/xyz',
          extra: const [null, null, '77. part'],
        ),
        77,
      );
    });

    test('the title wins over a weaker source', () {
      expect(
        parseEntryNumber(
          title: 'Entry 500',
          url: 'https://x.example/s/entry-499',
          extra: const ['Entry 498'],
        ),
        500,
      );
    });

    test('non-numeric entries stay non-numeric', () {
      expect(parseEntryNumber(title: 'Prologue'), isNull);
      expect(parseEntryNumber(title: 'Extra'), isNull);
      expect(
        parseEntryNumber(title: 'Side Story', url: 'https://x.example/s/side'),
        isNull,
        reason: 'inventing a number here would reorder the whole collection',
      );
    });

    test('the source marker is kept, separately from the display label', () {
      const title = 'The Long Guide 883. part - Read Online';
      final number = parseEntryNumber(title: title);
      expect(number, 883);
      expect(sourceMarkerFrom(title: title, number: number), '883. part');
      // The marker records what the source wrote; the display label is the
      // product's own word, produced from the detected shape. Two facts, two
      // fields — the marker is never overwritten by the label.
      const chapters = EntryLabels(EntryLabelStyle.chapter);
      expect(
        entryDisplayLabel(
          labels: chapters,
          number: number,
          sourceMarker: sourceMarkerFrom(title: title, number: number),
        ),
        chapters.numbered(883),
        reason: 'one product label, no redundant source strings',
      );
    });
  });
}
