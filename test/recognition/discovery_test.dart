/// Source-scoped discovery (F3): what one Source's reading showed, and the
/// two things it is never allowed to conclude — a merge it cannot justify
/// (V2-D16) and a retraction on somebody else's Source (I15).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:web_reader/data/data_violations.dart';
import 'package:web_reader/data/schema.dart';
import 'package:web_reader/domain/collection.dart';
import 'package:web_reader/domain/entry.dart';
import 'package:web_reader/domain/location.dart';
import 'package:web_reader/recognition/discovery.dart';
import 'package:web_reader/recognition/recognise.dart';

import 'support/recognition_harness.dart';

void main() {
  late RecognitionHarness h;

  setUp(() => h = RecognitionHarness());
  tearDown(() => h.close());

  /// The Location row at [url], through the same index the app uses.
  Future<LocationRow> locationAt(String url) async {
    final hit = await h.repos.recognition.lookupUrl(
      RecognitionKeys.of(url).urlKey,
    );
    expect(hit, isNotNull, reason: 'expected a Location at $url');
    return hit!.location;
  }

  group('what a reading can vouch for', () {
    test('a clean numbered reading vouches for an interval', () {
      final (window, concerns) = ObservedEntryWindow.read(
        sourceId: 'source-a',
        listings: [
          for (final n in [5, 6, 7])
            ObservedEntryListing.read(
              url: partUrl(kHostA, n),
              label: 'Part $n',
            ),
        ],
        listRecognised: true,
        orderingConfident: true,
        newestFirst: false,
      );

      expect(concerns, isEmpty);
      expect(window, isNotNull);
      expect(window!.vouchesForInterval, isTrue);
      expect(window.from, 5);
      expect(window.to, 7);
      expect(window.covers(6), isTrue);
      expect(window.covers(4), isFalse);
      expect(window.covers(8), isFalse);
    });

    test('a newest-first reading rules out everything above it', () {
      final (window, _) = ObservedEntryWindow.read(
        sourceId: 'source-a',
        listings: [
          for (final n in [5, 6])
            ObservedEntryListing.read(
              url: partUrl(kHostA, n),
              label: 'Part $n',
            ),
        ],
        listRecognised: true,
        orderingConfident: true,
        newestFirst: true,
      );
      expect(window!.openAbove, isTrue);
      expect(window.covers(9), isTrue);
      expect(window.covers(4), isFalse);
    });

    test('an unnumbered address leaves the reading with no interval', () {
      final (window, _) = ObservedEntryWindow.read(
        sourceId: 'source-j',
        listings: [
          ObservedEntryListing.read(
            url: postUrl(kHostJournal, 'a-walk-before-rain'),
            label: 'A walk before rain',
          ),
          ObservedEntryListing.read(
            url: postUrl(kHostJournal, 'the-quiet-harbour'),
            label: 'The quiet harbour',
          ),
        ],
        listRecognised: true,
        orderingConfident: true,
        newestFirst: false,
      );

      expect(window, isNotNull, reason: 'it still saw what it saw');
      expect(window!.vouchesForInterval, isFalse);
      expect(window.covers(1), isFalse);
      expect(window.urlKeys, hasLength(2));
    });

    test('a truncated reading records but vouches for no interval', () {
      final (window, _) = ObservedEntryWindow.read(
        sourceId: 'source-a',
        listings: [
          for (final n in [5, 6])
            ObservedEntryListing.read(
              url: partUrl(kHostA, n),
              label: 'Part $n',
            ),
        ],
        listRecognised: true,
        orderingConfident: true,
        newestFirst: false,
        dropped: 3,
      );
      expect(window!.vouchesForInterval, isFalse);
    });

    test('a page that was not this list at all is no window', () {
      final (window, _) = ObservedEntryWindow.read(
        sourceId: 'source-a',
        listings: [
          ObservedEntryListing.read(url: partUrl(kHostA, 5), label: 'Part 5'),
        ],
        listRecognised: false,
        orderingConfident: true,
        newestFirst: false,
      );
      expect(window, isNull);
    });

    test('a contradiction stops the reading and is kept', () {
      // The addresses run 100..102 and the labels agree on two of them, so the
      // source demonstrably numbers both the same way. A label reading 1012
      // where its own address reads 102 is not a numbering convention.
      final (window, concerns) = ObservedEntryWindow.read(
        sourceId: 'source-a',
        listings: [
          ObservedEntryListing.read(
            url: partUrl(kHostA, 100),
            label: 'Part 100',
          ),
          ObservedEntryListing.read(
            url: partUrl(kHostA, 101),
            label: 'Part 101',
          ),
          ObservedEntryListing.read(
            url: partUrl(kHostA, 102),
            label: 'Part 1012',
          ),
        ],
        listRecognised: true,
        orderingConfident: true,
        newestFirst: false,
      );

      expect(window, isNull);
      expect(concerns, hasLength(1));
      expect(concerns.single.labelNumber, 1012);
      expect(concerns.single.urlNumber, 102);
    });

    test('a listing never takes its number from the address', () {
      final listing = ObservedEntryListing.read(
        url: 'https://$kHostA$kWorkPath/9912',
        label: 'A lamp in the window',
      );
      expect(listing.urlNumber, 9912, reason: 'the digits are readable');
      expect(
        listing.printedNumber,
        isNull,
        reason: 'the source printed no number',
      );
    });
  });

  group('applying a window', () {
    test('a first reading places what the source printed', () async {
      final collection = await h.collection();
      final source = await h.source(collection: collection, host: kHostA);

      final before = await h.repos.outboxCount();
      final outcome = await h.discovery.apply(
        h.window(source: source, host: kHostA, parts: [5, 6, 7]),
      );

      expect(outcome.createdEntryIds, hasLength(3));
      expect(outcome.unplacedEntryIds, isEmpty);
      expect(outcome.mergedEntryIds, isEmpty);
      expect(outcome.addedLocationIds, hasLength(3));
      expect(outcome.refusals, isEmpty);

      final entries = await h.repos.entries.entriesOf(collection.id);
      expect(entries.map((e) => e.ordinal), [5, 6, 7]);
      expect(
        entries.map((e) => e.placement),
        everyElement(Placement.placed.name),
      );
      expect(
        await h.repos.outboxCount(),
        before + 6,
        reason: 'three Entries and three Locations, each one intent',
      );
    });

    test('equal printed numbers on two sites are one Entry', () async {
      final collection = await h.collection();
      final alpha = await h.source(collection: collection, host: kHostA);
      final beta = await h.source(
        collection: collection,
        host: kHostB,
        language: 'tr',
      );

      await h.discovery.apply(
        h.window(source: alpha, host: kHostA, parts: [5, 6, 7]),
      );
      final outcome = await h.discovery.apply(
        h.window(source: beta, host: kHostB, parts: [5, 6, 7]),
      );

      expect(outcome.createdEntryIds, isEmpty);
      expect(outcome.mergedEntryIds, hasLength(3));
      expect(outcome.addedLocationIds, hasLength(3));

      final entries = await h.repos.entries.entriesOf(collection.id);
      expect(entries, hasLength(3), reason: 'you read the work once');
      for (final entry in entries) {
        final locations = await h.repos.entries.locationsOf(entry.id);
        expect(locations, hasLength(2));
        expect(locations.map((l) => l.sourceId).toSet(), {alpha.id, beta.id});
      }
    });

    test('an overlapping range merges only where it overlaps', () async {
      final collection = await h.collection();
      final alpha = await h.source(collection: collection, host: kHostA);
      final beta = await h.source(collection: collection, host: kHostB);

      await h.discovery.apply(
        h.window(source: alpha, host: kHostA, parts: [5, 6, 7]),
      );
      final outcome = await h.discovery.apply(
        h.window(source: beta, host: kHostB, parts: [6, 7, 8, 9]),
      );

      expect(outcome.mergedEntryIds, hasLength(2));
      expect(outcome.createdEntryIds, hasLength(2));
      final entries = await h.repos.entries.entriesOf(collection.id);
      expect(entries.map((e) => e.ordinal), [5, 6, 7, 8, 9]);
    });

    test('contradictory numbering stays two Entries', () async {
      final collection = await h.collection();
      final alpha = await h.source(collection: collection, host: kHostA);
      final shifted = await h.source(
        collection: collection,
        host: kHostShifted,
      );

      await h.discovery.apply(
        h.window(source: alpha, host: kHostA, parts: [5, 6, 7]),
      );
      // What alpha prints as Part 5, this site prints as Part 4.5.
      final outcome = await h.discovery.apply(
        h.window(
          source: shifted,
          host: kHostShifted,
          parts: [5, 6, 7],
          printedOffset: -0.5,
        ),
      );

      expect(outcome.mergedEntryIds, isEmpty, reason: '100 against 99.5');
      expect(outcome.createdEntryIds, hasLength(3));

      final entries = await h.repos.entries.entriesOf(collection.id);
      expect(entries.map((e) => e.ordinal), [4.5, 5, 5.5, 6, 6.5, 7]);
      final five = await locationAt(partUrl(kHostA, 5));
      expect(
        await h.repos.entries.locationsOf(five.entryId),
        hasLength(1),
        reason: 'the contradiction was kept, not repaired',
      );
    });

    test('a source that prints no numbers stays unplaced', () async {
      final collection = await h.collection();
      final alpha = await h.source(collection: collection, host: kHostA);
      final journal = await h.source(
        collection: collection,
        host: kHostJournal,
      );
      await h.discovery.apply(
        h.window(source: alpha, host: kHostA, parts: [5, 6, 7]),
      );

      final (window, _) = ObservedEntryWindow.read(
        sourceId: journal.id,
        listings: [
          for (final slug in ['a-walk-before-rain', 'the-long-afternoon'])
            ObservedEntryListing.read(
              url: postUrl(kHostJournal, slug),
              label: slug.replaceAll('-', ' '),
            ),
        ],
        listRecognised: true,
        orderingConfident: true,
        newestFirst: false,
      );
      final outcome = await h.discovery.apply(window!);

      expect(outcome.createdEntryIds, hasLength(2));
      expect(outcome.unplacedEntryIds, outcome.createdEntryIds);
      expect(outcome.mergedEntryIds, isEmpty);

      final unplaced = await h.repos.entries.unplacedOf(collection.id);
      expect(unplaced, hasLength(2));
      expect(unplaced.map((e) => e.ordinal), everyElement(isNull));
      expect(
        await h.repos.entries.entriesOf(collection.id),
        hasLength(5),
        reason: 'the numbered Entries are untouched and both are readable',
      );
    });

    test('an ordering basis without a number line never places', () async {
      final folder = await h.root();
      final (collection, _) = await h.repos.collections.create(
        name: 'The journal',
        folderId: folder.id,
        orderingBasis: OrderingBasis.publicationDate,
      );
      final (source, _) = await h.repos.collections.addSource(
        collectionId: collection!.id,
        host: kHostB,
        pathKey: '/works/other-work',
      );

      final (window, _) = ObservedEntryWindow.read(
        sourceId: source!.id,
        listings: [
          for (final n in [5, 6])
            ObservedEntryListing.read(
              url: 'https://$kHostB/works/other-work/part-$n',
              label: 'Part $n',
            ),
        ],
        listRecognised: true,
        orderingConfident: true,
        newestFirst: false,
      );
      final outcome = await h.discovery.apply(window!);

      expect(
        outcome.unplacedEntryIds,
        hasLength(2),
        reason: 'a printed number is not enough; the basis has to support it',
      );
      expect(
        (await h.repos.entries.entriesOf(collection.id)).map((e) => e.ordinal),
        everyElement(isNull),
      );
    });

    test(
      'an address the library already holds is not recorded twice',
      () async {
        final collection = await h.collection();
        final alpha = await h.source(collection: collection, host: kHostA);
        final window = h.window(source: alpha, host: kHostA, parts: [5, 6, 7]);

        await h.discovery.apply(window);
        final outcome = await h.discovery.apply(window);

        expect(outcome.alreadyHeld, 3);
        expect(outcome.createdEntryIds, isEmpty);
        expect(outcome.addedLocationIds, isEmpty);
        expect(outcome.refusals, isEmpty);
        expect(await h.repos.entries.entriesOf(collection.id), hasLength(3));
      },
    );

    test('a window naming a Source that is gone is refused', () async {
      final collection = await h.collection();
      final source = await h.source(collection: collection, host: kHostA);
      final window = h.window(source: source, host: kHostA, parts: [5]);
      await h.repos.collections.removeSource(source.id);

      final outcome = await h.discovery.apply(window);
      expect(outcome.refusals.single.violation, unknownRow);
      expect(outcome.createdEntryIds, isEmpty);
    });
  });

  group('retraction is source-scoped', () {
    Future<({String collectionId, String alphaId, String betaId})>
    seedTwoSources() async {
      final row = await h.collection();
      final alpha = await h.source(collection: row, host: kHostA);
      final beta = await h.source(collection: row, host: kHostB);
      await h.discovery.apply(
        h.window(source: alpha, host: kHostA, parts: [5, 6, 7]),
      );
      await h.discovery.apply(
        h.window(source: beta, host: kHostB, parts: [5, 6, 7]),
      );
      return (collectionId: row.id, alphaId: alpha.id, betaId: beta.id);
    }

    test('a Source retracts its own Location and never another\'s', () async {
      final ids = await seedTwoSources();
      final outboxBefore = await h.repos.outboxCount();

      final outcome = await h.discovery.apply(
        h.window(
          source: (await h.repos.collections.sourceById(ids.alphaId))!,
          host: kHostA,
          parts: [5, 7],
        ),
      );

      final alphaSix = await locationAt(partUrl(kHostA, 6));
      final betaSix = await locationAt(partUrl(kHostB, 6));

      expect(outcome.retractedLocationIds, [alphaSix.id]);
      expect(
        (await h.repos.entries.locationById(alphaSix.id))!.lifecycle,
        LocationLifecycle.retracted.name,
      );
      expect(
        (await h.repos.entries.locationById(betaSix.id))!.lifecycle,
        LocationLifecycle.active.name,
        reason: 'I15: a reading of one Source says nothing about another',
      );
      expect(
        await h.repos.entries.entriesOf(ids.collectionId),
        hasLength(3),
        reason: 'retraction is evidence about a listing, never a deletion',
      );
      expect(
        await h.repos.outboxCount(),
        outboxBefore,
        reason: 'retraction does not sync (V2_SYNC.md §5)',
      );
    });

    test('the repository refuses a cross-source retraction directly', () async {
      final ids = await seedTwoSources();
      final betaSix = await locationAt(partUrl(kHostB, 6));

      expect(
        await h.repos.entries.retractLocation(
          betaSix.id,
          readingSourceId: ids.alphaId,
        ),
        retractionOutOfScope,
      );
      expect(
        (await h.repos.entries.locationById(betaSix.id))!.lifecycle,
        LocationLifecycle.active.name,
      );
    });

    test('a Location the reading never covered survives', () async {
      final ids = await seedTwoSources();

      final outcome = await h.discovery.apply(
        h.window(
          source: (await h.repos.collections.sourceById(ids.alphaId))!,
          host: kHostA,
          parts: [6, 7],
        ),
      );

      expect(
        outcome.retractedLocationIds,
        isEmpty,
        reason: 'below the floor is where the previous page lives',
      );
      final alphaFive = await locationAt(partUrl(kHostA, 5));
      expect(alphaFive.lifecycle, LocationLifecycle.active.name);
    });

    test('a newest-first reading may rule out what sits above it', () async {
      final ids = await seedTwoSources();

      final outcome = await h.discovery.apply(
        h.window(
          source: (await h.repos.collections.sourceById(ids.alphaId))!,
          host: kHostA,
          parts: [5, 6],
          newestFirst: true,
        ),
      );

      final alphaSeven = await locationAt(partUrl(kHostA, 7));
      expect(outcome.retractedLocationIds, [alphaSeven.id]);
    });

    test('a reading that vouches for no interval retracts nothing', () async {
      final collection = await h.collection();
      final journal = await h.source(
        collection: collection,
        host: kHostJournal,
      );
      final slugs = ['a-walk-before-rain', 'the-long-afternoon'];
      List<ObservedEntryListing> listingsOf(Iterable<String> from) => [
        for (final slug in from)
          ObservedEntryListing.read(
            url: postUrl(kHostJournal, slug),
            label: slug.replaceAll('-', ' '),
          ),
      ];

      final (first, _) = ObservedEntryWindow.read(
        sourceId: journal.id,
        listings: listingsOf(slugs),
        listRecognised: true,
        orderingConfident: true,
        newestFirst: false,
      );
      await h.discovery.apply(first!);

      final (second, _) = ObservedEntryWindow.read(
        sourceId: journal.id,
        listings: listingsOf(slugs.take(1)),
        listRecognised: true,
        orderingConfident: true,
        newestFirst: false,
      );
      final outcome = await h.discovery.apply(second!);

      expect(
        outcome.retractedLocationIds,
        isEmpty,
        reason: 'with no number line there is no position to rule out',
      );
    });

    test('the retraction rule reads the same way as a pure question', () async {
      final ids = await seedTwoSources();
      final alphaWindow = h.window(
        source: (await h.repos.collections.sourceById(ids.alphaId))!,
        host: kHostA,
        parts: [5, 7],
      );

      expect(
        windowRetracts(alphaWindow, await locationAt(partUrl(kHostA, 6))),
        isTrue,
      );
      expect(
        windowRetracts(alphaWindow, await locationAt(partUrl(kHostB, 6))),
        isFalse,
        reason: 'I15: another Source\'s Location is out of scope',
      );
      expect(
        windowRetracts(alphaWindow, await locationAt(partUrl(kHostA, 5))),
        isFalse,
        reason: 'the reading still lists it',
      );
    });
  });
}
