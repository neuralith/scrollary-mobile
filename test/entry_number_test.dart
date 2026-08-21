import 'package:flutter_test/flutter_test.dart';
import 'package:web_reader/library/collection_identity.dart';

/// Reading an entry's own number out of what a site wrote.
///
/// Every case here is a shape the parser got wrong. The two defects behind
/// them were:
///
/// 1. The word list held `chap|ch` but not `chapter`, so the commonest entry
///    title in English matched only a prefix and then demanded a digit where
///    `"ter 12"` stood — `"Chapter 12"` parsed as *no number*. The same gap
///    made `/chapter-1234` unreadable, and the unfenced `ch` matched inside
///    `Watch`.
/// 2. The URL matcher took the **first** word-and-number in the whole path.
///    A path carries the collection then the entry, and the collection's slug
///    is identical for every entry in it — so `/the-guide-vol-1/chapter-88`
///    read `vol-1` and numbered every chapter in the collection "1".
void main() {
  group('numbers in a title', () {
    test('the plain English forms', () {
      expect(parseEntryNumber(title: 'Chapter 12'), 12);
      expect(parseEntryNumber(title: 'Chapter 12 - The Long Guide'), 12);
      expect(parseEntryNumber(title: 'The Long Guide Chapter 137'), 137);
      expect(parseEntryNumber(title: 'Chapter 5: A Title'), 5);
      expect(parseEntryNumber(title: 'Chapters 40'), 40);
      expect(parseEntryNumber(title: 'Chap. 8'), 8);
      expect(parseEntryNumber(title: 'Ch.9'), 9);
      expect(parseEntryNumber(title: 'Episode 22'), 22);
      expect(parseEntryNumber(title: 'Ep. 3'), 3);
      expect(parseEntryNumber(title: 'Part 3'), 3);
      expect(parseEntryNumber(title: 'Entry 487'), 487);
    });

    test('decimals, in both notations', () {
      expect(parseEntryNumber(title: 'Chapter 12.5'), 12.5);
      expect(parseEntryNumber(title: 'Bölüm 487,5'), 487.5);
    });

    test('the number may lead', () {
      expect(parseEntryNumber(title: '487. Bölüm'), 487);
      expect(parseEntryNumber(title: '12 Kapitel'), 12);
    });

    test('a more specific word wins', () {
      // The volume is not the entry, and reading it as one puts every chapter
      // of volume 2 at position 2.
      expect(parseEntryNumber(title: 'Vol. 2 Chapter 9'), 9);
      expect(parseEntryNumber(title: 'Volume 3, Part 7'), 7);
    });

    test('an entry word inside another word is not an entry word', () {
      expect(parseEntryNumber(title: 'Watch 1080p Guide'), isNull);
      expect(parseEntryNumber(title: 'Search 5 results'), isNull);
      expect(parseEntryNumber(title: 'Chile 7'), isNull);
      expect(parseEntryNumber(title: 'Deep 4'), isNull);
    });

    test('no number is a real answer', () {
      expect(parseEntryNumber(title: 'Prologue'), isNull);
      expect(parseEntryNumber(title: 'Extras'), isNull);
      expect(parseEntryNumber(title: 'Something Untitled'), isNull);
    });
  });

  group('numbers in a URL', () {
    test('the entry segment wins over the collection slug', () {
      // The regression that numbered every chapter "1".
      expect(
        parseEntryNumber(
          url: 'https://a.example/manga/the-guide-1/chapter-1234',
        ),
        1234,
      );
      expect(
        parseEntryNumber(url: 'https://a.example/read/guide-vol-1/chapter-88'),
        88,
      );
      expect(
        parseEntryNumber(url: 'https://a.example/guide-part-1/entry/77'),
        77,
      );
      expect(
        parseEntryNumber(url: 'https://a.example/the-guide-1/chapter/1234'),
        1234,
      );
    });

    test('a collection slug alone does not become the entry number', () {
      // Nothing in the last segment says "1", so 1 must not be invented from
      // the slug that every sibling shares.
      expect(parseEntryNumber(url: 'https://a.example/the-guide-1/1234'), 1234);
    });

    test('the usual shapes', () {
      expect(parseEntryNumber(url: 'https://a.example/foo/chapter-12'), 12);
      expect(parseEntryNumber(url: 'https://a.example/foo/chapter/12'), 12);
      expect(parseEntryNumber(url: 'https://a.example/foo/ch-5'), 5);
      expect(parseEntryNumber(url: 'https://a.example/foo/bolum_12'), 12);
      expect(parseEntryNumber(url: 'https://a.example/foo/883-part'), 883);
      expect(parseEntryNumber(url: 'https://a.example/foo/entry-385-5'), 385.5);
      expect(
        parseEntryNumber(url: 'https://a.example/guide/chapter-1234/'),
        1234,
      );
    });

    test('a bare number in the last segment is the last resort', () {
      expect(parseEntryNumber(url: 'https://a.example/g/1/12'), 12);
      expect(parseEntryNumber(url: 'https://a.example/v1/c1234'), 1234);
      expect(parseEntryNumber(url: 'https://a.example/foo'), isNull);
    });
  });

  group('title beats URL', () {
    test('a numbered title is preferred over the path', () {
      expect(
        parseEntryNumber(
          title: 'Chapter 88',
          url: 'https://a.example/the-guide-1/chapter-88',
        ),
        88,
      );
    });

    test('an unnumbered title falls through to the path', () {
      expect(
        parseEntryNumber(
          title: 'Prologue',
          url: 'https://a.example/the-guide-1/chapter-1234',
        ),
        1234,
      );
    });
  });

  group('the marker the source printed', () {
    test('is kept verbatim', () {
      expect(
        sourceMarkerFrom(
          title: 'Chapter 12 - The Long Guide',
          url: 'https://a.example/foo/chapter-12',
          number: 12,
        ),
        'Chapter 12',
      );
    });
  });

  /// A list row is not one string on the page — it is several elements, and
  /// `Node.textContent` concatenates them with **no separator**. A row built as
  ///
  ///     <a href="/chapter/101"><span>Chapter 101</span><span>2 weeks ago</span></a>
  ///
  /// used to reach Dart as `"Chapter 1012 weeks ago"` whenever the markup
  /// carried no whitespace between the two elements. Entry 101 became entry
  /// 1012, and the digit it gained was the age of the page, so it moved.
  ///
  /// **The fix is upstream of this file**, in the bridge's `elementText`, which
  /// reads what the element says rather than what characters it contains. These
  /// tests exist to hold that line from below, and they are the reason the
  /// parser was left alone:
  ///
  /// * the reading the bridge now produces parses correctly;
  /// * the reading it used to produce is **irrecoverable**, so no rule added
  ///   here could have fixed it — `"Chapter 1012 weeks ago"` does not contain
  ///   the information that the entry is 101.
  ///
  /// The second half is asserted rather than described. A future attempt to
  /// paper over a producer fault by teaching the parser to guess at digit runs
  /// has to delete a test that says, in so many words, that guessing is what
  /// this must not do. If glued text ever reaches discovery again, it is caught
  /// by cross-checking against the URL — see `entry_identity_test.dart` — and
  /// refused, not decoded.
  group('a label welded to the metadata beside it', () {
    test('the separated reading — what the bridge now produces', () {
      // The rows from the reported failure, as `elementText` renders them.
      expect(parseEntryNumber(title: 'Chapter 101 2 weeks ago'), 101);
      expect(parseEntryNumber(title: 'Chapter 102 2 weeks ago'), 102);
      expect(parseEntryNumber(title: 'Chapter 103 last week'), 103);
      expect(parseEntryNumber(title: 'Chapter 104 6 days ago'), 104);
      expect(parseEntryNumber(title: 'Chapter 104 5 days ago'), 104);
      // Indented markup always separated correctly; it is why the failure
      // looked intermittent rather than systematic.
      expect(parseEntryNumber(title: 'Chapter 101\n  2 weeks ago'), 101);
    });

    test('the glued reading cannot be recovered, and is not guessed at', () {
      // Not the behaviour anyone wants — the behaviour that is honest. The
      // digit is gone into the number and nothing in the string says which one
      // it was. Anything that "fixed" these would be inventing a number.
      expect(parseEntryNumber(title: 'Chapter 1012 weeks ago'), 1012);
      expect(parseEntryNumber(title: 'Chapter 1022 weeks ago'), 1022);
      expect(parseEntryNumber(title: 'Chapter 1045 days ago'), 1045);
      expect(parseEntryNumber(title: 'Chapter 1046 days ago'), 1046);
    });

    test('a timestamp with no digit was never affected either way', () {
      // "last week" is the only reason one row in the report looked correct.
      expect(parseEntryNumber(title: 'Chapter 103last week'), 103);
      expect(parseEntryNumber(title: 'Chapter 101new'), 101);
    });

    test('separation is what fixes every metadata shape, not just dates', () {
      // Nothing about this was ever specific to dates: a rating, a view count
      // or a numbered badge in the next element glued exactly as hard.
      expect(parseEntryNumber(title: 'Chapter 101 4.7'), 101);
      expect(parseEntryNumber(title: 'Chapter 101 12k views'), 101);
      expect(parseEntryNumber(title: 'Chapter 101 Vol. 3'), 101);
      // And the priority rule still picks the entry over the volume.
      expect(parseEntryNumber(title: 'Vol. 3 Chapter 101 4.7'), 101);
    });

    test('a decimal entry survives separation', () {
      // Glued, this read 12.53 — which sorts plausibly beside 12.5 and so hid
      // better than a large wrong integer would have.
      expect(parseEntryNumber(title: 'Chapter 12.5 3 days ago'), 12.5);
      expect(parseEntryNumber(title: 'Chapter 12.53 days ago'), 12.53);
    });

    test('metadata separated in front no longer suppresses the number', () {
      // The other symptom of the same missing separator: the word fence
      // rejects an entry word preceded by a digit — the rule that stops
      // `Watch 1080p` — so a glued badge made the row parse as *unnumbered*.
      expect(parseEntryNumber(title: 'Season 2 Chapter 12'), 12);
      expect(parseEntryNumber(title: 'Season 2Chapter 12'), isNull);
    });

    test('the marker kept for display is separated too', () {
      expect(
        sourceMarkerFrom(title: 'Chapter 101 2 weeks ago'),
        'Chapter 101',
        reason: 'the row prints what the source said, so this is on screen',
      );
    });
  });

  group('collection titles', () {
    test('drop the entry marker they carry', () {
      expect(
        collectionTitleFromPageTitle('The Long Guide Chapter 137'),
        'The Long Guide',
      );
      expect(
        collectionTitleFromPageTitle('The Long Guide 12. Part - Read Online |'),
        'The Long Guide',
      );
      expect(
        collectionTitleFromPageTitle('Setup Notes Part 3 - Example Docs'),
        'Setup Notes',
      );
    });

    test('a title that is not a marker survives', () {
      expect(collectionTitleFromPageTitle('Watch This'), 'Watch This');
    });
  });
}
