/// What a page is, structurally (V2_SAVE_FLOW.md §2).
///
/// Shape is not identity: nothing here merges anything, and nothing here
/// decides what the library holds. Every answer is a real answer —
/// [PageKind.unknownPage] means the page did not say, which is why the user is
/// asked rather than guessed at.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:web_reader/library/collection_identity.dart';
import 'package:web_reader/recognition/page_kind.dart';

import 'support/recognition_harness.dart';

void main() {
  test('a page that printed a number is an entry of something', () {
    final shape = readPageShape(partUrl(kHostA, 5), pageTitle: 'Part 5');

    expect(shape.kind, PageKind.entryPage);
    expect(shape.printedNumber, 5);
    expect(shape.identityIsStrong, isTrue);
  });

  test('a page below a listing is an entry even with no number', () {
    final shape = readPageShape(
      postUrl(kHostA, 'epilogue'),
      pageTitle: 'Epilogue',
    );

    expect(shape.kind, PageKind.entryPage);
    expect(
      shape.printedNumber,
      isNull,
      reason: 'nothing numbered it, and a position is never guessed',
    );
  });

  test('a Source\'s own address is the listing, when the library can say '
      'so', () {
    final shape = readPageShape(
      'https://$kHostA$kWorkPath',
      pageTitle: 'Quiet Harbour',
      sourcePathKey: kWorkPath,
    );

    expect(shape.kind, PageKind.collectionIndex);
    expect(shape.identityIsStrong, isTrue);
    expect(shape.printedNumber, isNull);
  });

  test('the same address is not a listing when nothing knows it is', () {
    // An address alone cannot tell a work's listing from an about page, and
    // announcing "add this collection" over a privacy policy is the failure
    // that guess produces. Without the library's word, it did not say.
    final shape = readPageShape(
      'https://$kHostA$kWorkPath',
      pageTitle: 'Quiet Harbour',
    );

    expect(shape.kind, PageKind.unknownPage);
    expect(shape.identityIsStrong, isTrue);
  });

  test('an ordinary page did not say, and says so', () {
    final shape = readPageShape('https://$kHostA/', pageTitle: 'Alpha');

    expect(shape.kind, PageKind.unknownPage);
    expect(shape.identityIsStrong, isFalse);
    expect(shape.isSerialized, isFalse);
  });

  group('what the page called this entry', () {
    // The regression: the forward walk read a page through this function and
    // passed only the document title, so the `h1` and the `og:title` — where
    // a great many sites print the entry's number and its name — never
    // reached `parseEntryNumber` at all. Every walked Entry came back
    // unnumbered, which is what stopped a count of N being N captures.
    test('a heading numbers the entry when the document title does not', () {
      final shape = readPageShape(
        postUrl(kHostA, 'the-quiet-part'),
        pageTitle: 'Quiet Harbour',
        hints: const PageHints(h1: 'Chapter 123'),
      );

      expect(shape.printedNumber, 123);
      expect(shape.kind, PageKind.entryPage);
      expect(shape.entryLabel, 'Chapter 123');
    });

    test('the og:title counts too', () {
      final shape = readPageShape(
        postUrl(kHostA, 'the-quiet-part'),
        pageTitle: 'Quiet Harbour',
        hints: const PageHints(ogTitle: 'Episode 42 — Quiet Harbour'),
      );

      expect(shape.printedNumber, 42);
    });

    test('the entry label drops the site name the title carries', () {
      final shape = readPageShape(
        partUrl(kHostA, 18),
        pageTitle: 'Part 18 | Quiet Harbour | Example Reader',
      );

      expect(shape.entryLabel, 'Part 18');
    });

    test('a marked candidate wins over an earlier unmarked one', () {
      // Some sites put the work's name in the `h1` and the entry's in the
      // title. Whichever one carries the marker is the one naming the entry.
      final shape = readPageShape(
        partUrl(kHostA, 7),
        pageTitle: 'Part 7 - Quiet Harbour',
        hints: const PageHints(h1: 'Quiet Harbour'),
      );

      expect(shape.entryLabel, 'Part 7');
    });

    test('a page that named nothing has no label, and none is invented', () {
      final shape = readPageShape('https://$kHostA/', pageTitle: '');

      expect(shape.entryLabel, isNull);
      expect(shape.printedNumber, isNull);
    });

    test('contradictory evidence is still refused elsewhere, not repaired '
        'here', () {
      // This function reads; it never adjudicates. A label and an address
      // that disagree both survive into the evidence, and
      // `reviewEntryIdentities` is what refuses — unchanged.
      final shape = readPageShape(
        partUrl(kHostA, 102),
        pageTitle: 'Chapter 1020',
      );

      expect(shape.printedNumber, 1020, reason: 'the label is read first');
      expect(parseEntryNumber(url: partUrl(kHostA, 102)), 102);
    });
  });
}
