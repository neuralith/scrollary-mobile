/// Walking one Source forward from the Entry in front of the reader
/// (docs/V2_SAVE_FLOW.md §4).
///
/// Everything here runs against a scripted [ForwardPageSource]: the walk's
/// judgements are about *what a page turned out to say*, not about how a page
/// is opened, so none of them needs a WebView to be proved. What is asserted
/// is the walk's own share — which Source it belongs to, what counts toward
/// the number asked for, which Entry an address joins, and that every stop
/// keeps what it had already resolved.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:web_reader/core/url_utils.dart';
import 'package:web_reader/data/schema.dart';
import 'package:web_reader/domain/collection.dart';
import 'package:web_reader/domain/entry.dart' show Placement;
import 'package:web_reader/recognition/recognise.dart';
import 'package:web_reader/recognition/walk.dart';

import 'support/forward_pages_fake.dart';
import 'support/recognition_harness.dart';

void main() {
  late RecognitionHarness h;

  setUp(() => h = RecognitionHarness());
  tearDown(() => h.close());

  LibrarySourceWalk walkOver(FakeForwardPages pages) => LibrarySourceWalk(
    entries: h.repos.entries,
    collections: h.repos.collections,
    index: h.repos.recognition,
    pages: pages,
  );

  bool alwaysContinue() => true;

  /// One Collection, one Source on [host], and the parts the library already
  /// holds — the standing furniture for a forward walk.
  Future<({CollectionRow collection, SourceRow source, LocationRow from})>
  library({
    required List<num> held,
    String host = kHostA,
    OrderingBasis basis = OrderingBasis.explicitNumericIndex,
  }) async {
    final collection = await h.collection(basis: basis);
    final source = await h.source(collection: collection, host: host);
    LocationRow? last;
    for (final number in held) {
      final (_, location) = await h.placedEntry(
        collection: collection,
        source: source,
        host: host,
        number: number.toDouble(),
      );
      last = location;
    }
    return (collection: collection, source: source, from: last!);
  }

  Future<List<LocationRow>> locationsOf(String entryId) =>
      h.repos.entries.locationsOf(entryId);

  Future<List<EntryRow>> entriesOf(CollectionRow c) =>
      h.repos.entries.entriesOf(c.id);

  // ─── the ordinary shape: the library knows some of them ───────────────────

  test('a partially known collection is walked only for what is '
      'missing', () async {
    final it = await library(held: [101, 102, 103, 104]);
    final pages = FakeForwardPages.chain(
      host: kHostA,
      parts: [104, 105, 106, 107, 108, 109, 110, 111],
    );

    final outcome = await walkOver(pages).forward(
      fromLocationId: it.from.id,
      wanted: 6,
      shouldContinue: alwaysContinue,
    );

    expect(outcome.stop, WalkStop.countReached);
    expect(outcome.resolved, 6);
    expect(outcome.requested, 6);
    expect(
      [for (final e in outcome.entries) e.printedNumber],
      [105, 106, 107, 108, 109, 110],
    );
    expect(outcome.entries.every((e) => !e.wasAlreadyHeld), isTrue);

    final entries = await entriesOf(it.collection);
    expect(entries, hasLength(10), reason: 'no twins for 101–104');
    expect(
      [for (final e in entries) e.ordinal],
      [101, 102, 103, 104, 105, 106, 107, 108, 109, 110],
    );

    for (final walked in outcome.entries) {
      final locations = await locationsOf(walked.entryId);
      expect(locations, hasLength(1));
      expect(locations.single.sourceId, it.source.id);
      expect(locations.single.discoveryBasis, kForwardWalkBasis);
    }
  });

  test('a collection holding only the page in front of the reader is walked '
      'for all of them', () async {
    final it = await library(held: [101]);
    final pages = FakeForwardPages.chain(
      host: kHostA,
      parts: [101, 102, 103, 104, 105, 106],
    );

    final outcome = await walkOver(pages).forward(
      fromLocationId: it.from.id,
      wanted: 4,
      shouldContinue: alwaysContinue,
    );

    expect(outcome.stop, WalkStop.countReached);
    expect(
      [for (final e in outcome.entries) e.printedNumber],
      [102, 103, 104, 105],
    );
    expect(await entriesOf(it.collection), hasLength(5));
  });

  test('an address the library already holds is reused, and still '
      'counts', () async {
    final collection = await h.collection();
    final source = await h.source(collection: collection, host: kHostA);
    final (_, from) = await h.placedEntry(
      collection: collection,
      source: source,
      host: kHostA,
      number: 101,
    );
    final (knownEntry, knownLocation) = await h.placedEntry(
      collection: collection,
      source: source,
      host: kHostA,
      number: 103,
    );
    final pages = FakeForwardPages.chain(
      host: kHostA,
      parts: [101, 102, 103, 104, 105],
    );

    final outcome = await walkOver(pages).forward(
      fromLocationId: from.id,
      wanted: 3,
      shouldContinue: alwaysContinue,
    );

    expect(outcome.stop, WalkStop.countReached);
    expect(outcome.resolved, 3);
    final reused = outcome.entries[1];
    expect(reused.wasAlreadyHeld, isTrue);
    expect(reused.entryId, knownEntry.id);
    expect(reused.locationId, knownLocation.id);

    expect(
      await entriesOf(collection),
      hasLength(4),
      reason: '101 and 103 were already there; 102 and 104 are new',
    );
    expect(
      await locationsOf(knownEntry.id),
      hasLength(1),
      reason: 'a reused address writes no second Location',
    );
  });

  // ─── one Entry, several Sources (V2-D16) ─────────────────────────────────

  test('a part the collection already holds from another Source gains a '
      'Location rather than a twin', () async {
    final collection = await h.collection();
    final here = await h.source(collection: collection, host: kHostA);
    final elsewhere = await h.source(collection: collection, host: kHostB);
    final (_, from) = await h.placedEntry(
      collection: collection,
      source: here,
      host: kHostA,
      number: 101,
    );
    final (shared, _) = await h.placedEntry(
      collection: collection,
      source: elsewhere,
      host: kHostB,
      number: 103,
    );
    final pages = FakeForwardPages.chain(
      host: kHostA,
      parts: [101, 102, 103, 104],
    );

    final outcome = await walkOver(pages).forward(
      fromLocationId: from.id,
      wanted: 3,
      shouldContinue: alwaysContinue,
    );

    expect(outcome.stop, WalkStop.countReached);
    final merged = outcome.entries[1];
    expect(merged.entryId, shared.id);
    expect(merged.mergedIntoExistingEntry, isTrue);
    expect(merged.wasAlreadyHeld, isFalse);

    expect(await entriesOf(collection), hasLength(4));
    final locations = await locationsOf(shared.id);
    expect(locations, hasLength(2));
    expect(
      {for (final l in locations) l.sourceId},
      {here.id, elsewhere.id},
      reason: 'one Entry, read on two sites',
    );
  });

  test('100 and 99.5 are two entries, not one', () async {
    final collection = await h.collection();
    final here = await h.source(collection: collection, host: kHostA);
    final elsewhere = await h.source(collection: collection, host: kHostB);
    final (_, from) = await h.placedEntry(
      collection: collection,
      source: here,
      host: kHostA,
      number: 99,
    );
    final (half, _) = await h.placedEntry(
      collection: collection,
      source: elsewhere,
      host: kHostB,
      number: 99.5,
    );
    final pages = FakeForwardPages.chain(host: kHostA, parts: [99, 100]);

    final outcome = await walkOver(pages).forward(
      fromLocationId: from.id,
      wanted: 1,
      shouldContinue: alwaysContinue,
    );

    expect(outcome.entries.single.mergedIntoExistingEntry, isFalse);
    expect(outcome.entries.single.entryId, isNot(half.id));
    expect(
      [for (final e in await entriesOf(collection)) e.ordinal],
      [99, 99.5, 100],
    );
    expect(await locationsOf(half.id), hasLength(1));
  });

  test('a collection ordered by anything but an explicit index leaves walked '
      'entries unplaced, and merges nothing', () async {
    final collection = await h.collection(basis: OrderingBasis.publicationDate);
    final source = await h.source(collection: collection, host: kHostA);
    final (start, _) = await h.repos.entries.createInCollection(
      collectionId: collection.id,
      placement: Placement.unplaced,
      title: 'A post',
    );
    final startUrl = partUrl(kHostA, 105);
    final (from, _) = await h.repos.entries.addLocation(
      entryId: start!.id,
      url: startUrl,
      urlKey: normalizeUrl(startUrl),
      sourceId: source.id,
    );
    final (occupied, _) = await h.repos.entries.createInCollection(
      collectionId: collection.id,
      ordinal: 106,
      title: 'Placed by hand',
    );
    final pages = FakeForwardPages.chain(host: kHostA, parts: [105, 106, 107]);

    final outcome = await walkOver(pages).forward(
      fromLocationId: from!.id,
      wanted: 2,
      shouldContinue: alwaysContinue,
    );

    expect(outcome.stop, WalkStop.countReached);
    expect(outcome.entries.every((e) => !e.mergedIntoExistingEntry), isTrue);
    for (final walked in outcome.entries) {
      final row = await h.repos.entries.byId(walked.entryId);
      expect(row!.ordinal, isNull);
      expect(row.placement, Placement.unplaced.name);
      expect(row.id, isNot(occupied!.id));
    }
  });

  // ─── ending is an answer, not a failure ──────────────────────────────────

  test('a source with fewer than were asked for ends naturally, and invents '
      'nothing', () async {
    final it = await library(held: [101]);
    final pages = FakeForwardPages.chain(
      host: kHostA,
      parts: [101, 102, 103, 104, 105],
    );

    final outcome = await walkOver(pages).forward(
      fromLocationId: it.from.id,
      wanted: 10,
      shouldContinue: alwaysContinue,
    );

    expect(outcome.stop, WalkStop.endOfSource);
    expect(outcome.endedNaturally, isTrue);
    expect(outcome.resolved, 4);
    expect(outcome.requested, 10);
    expect(await entriesOf(it.collection), hasLength(5));
  });

  test('a page that will not render stops the walk and keeps what came '
      'before', () async {
    final it = await library(held: [101]);
    final pages =
        FakeForwardPages.chain(host: kHostA, parts: [101, 102, 103, 104])..put(
          WalkedPage.unreadable(
            url: partUrl(kHostA, 103),
            stop: WalkStop.unreadable,
          ),
        );

    final outcome = await walkOver(pages).forward(
      fromLocationId: it.from.id,
      wanted: 5,
      shouldContinue: alwaysContinue,
    );

    expect(outcome.stop, WalkStop.unreadable);
    expect(outcome.endedNaturally, isFalse);
    expect([for (final e in outcome.entries) e.printedNumber], [102]);
    expect(
      [for (final e in await entriesOf(it.collection)) e.ordinal],
      [101, 102],
      reason: 'nothing is written for a page the walk could not read',
    );
  });

  test('a next control only the user can identify is a stop, not a '
      'guess', () async {
    final it = await library(held: [101]);
    final pages = FakeForwardPages.chain(host: kHostA, parts: [101, 102, 103])
      ..put(
        WalkedPage.unreadable(
          url: partUrl(kHostA, 102),
          stop: WalkStop.needsUserAssist,
        ),
      );

    final outcome = await walkOver(pages).forward(
      fromLocationId: it.from.id,
      wanted: 5,
      shouldContinue: alwaysContinue,
    );

    expect(outcome.stop, WalkStop.needsUserAssist);
    expect(outcome.entries, isEmpty);
    expect(await entriesOf(it.collection), hasLength(1));
  });

  test('a next address on another part of the site ends the walk', () async {
    final it = await library(held: [101]);
    final pages = FakeForwardPages.chain(host: kHostA, parts: [101, 102])
      ..put(
        WalkedPage(
          url: partUrl(kHostA, 102),
          printedNumber: 102,
          title: 'Part 102',
          nextUrl: 'https://$kHostA/works/another-work/part-103',
        ),
      );

    final outcome = await walkOver(pages).forward(
      fromLocationId: it.from.id,
      wanted: 5,
      shouldContinue: alwaysContinue,
    );

    expect(outcome.stop, WalkStop.leftTheSource);
    expect([for (final e in outcome.entries) e.printedNumber], [102]);
    expect(await entriesOf(it.collection), hasLength(2));
  });

  test('a next address on another site ends the walk', () async {
    final it = await library(held: [101]);
    final pages = FakeForwardPages.chain(host: kHostA, parts: [101])
      ..put(
        WalkedPage(
          url: partUrl(kHostA, 101),
          printedNumber: 101,
          title: 'Part 101',
          nextUrl: partUrl(kHostB, 102),
        ),
      );

    final outcome = await walkOver(pages).forward(
      fromLocationId: it.from.id,
      wanted: 5,
      shouldContinue: alwaysContinue,
    );

    expect(outcome.stop, WalkStop.leftTheSource);
    expect(outcome.entries, isEmpty);
    expect(await entriesOf(it.collection), hasLength(1));
  });

  test('a cancellation is taken at a page boundary, and keeps what it had '
      'already resolved', () async {
    final it = await library(held: [101]);
    final pages = FakeForwardPages.chain(
      host: kHostA,
      parts: [101, 102, 103, 104, 105],
    );
    var cancelled = false;

    final outcome = await walkOver(pages).forward(
      fromLocationId: it.from.id,
      wanted: 4,
      shouldContinue: () {
        // Two pages in, the user pressed stop.
        if (pages.reads.length >= 2) cancelled = true;
        return !cancelled;
      },
    );

    expect(outcome.stop, WalkStop.cancelledByUser);
    expect(outcome.resolved, lessThan(4));
    expect(outcome.entries, isNotEmpty);
    expect(
      await entriesOf(it.collection),
      hasLength(1 + outcome.resolved),
      reason: 'everything resolved before the stop stays in the library',
    );
  });

  test('the ceiling on pages opened bounds a walk the count would '
      'not', () async {
    final it = await library(held: [101]);
    final pages = FakeForwardPages.chain(
      host: kHostA,
      parts: [for (var n = 101; n <= 140; n++) n],
    );

    final outcome = await walkOver(pages).forward(
      fromLocationId: it.from.id,
      wanted: 30,
      shouldContinue: alwaysContinue,
      maxPages: 3,
    );

    expect(outcome.stop, WalkStop.pageCeiling);
    expect(outcome.pagesRead, 3);
    expect(outcome.resolved, 2);
  });

  test('a next link pointing back where the walk has been does not '
      'loop', () async {
    final it = await library(held: [101]);
    final pages = FakeForwardPages.chain(host: kHostA, parts: [101, 102])
      ..put(
        WalkedPage(
          url: partUrl(kHostA, 102),
          printedNumber: 102,
          title: 'Part 102',
          nextUrl: partUrl(kHostA, 101),
        ),
      );

    final outcome = await walkOver(pages).forward(
      fromLocationId: it.from.id,
      wanted: 10,
      shouldContinue: alwaysContinue,
    );

    expect(outcome.stop, WalkStop.endOfSource);
    expect(outcome.resolved, 1);
    expect(pages.reads, hasLength(2));
    expect(
      pages.visitedAtRead.last,
      contains(normalizeUrl(partUrl(kHostA, 101))),
      reason: 'the reader is told where the walk has been',
    );
  });

  // ─── there has to be a Source to walk ────────────────────────────────────

  test('a standalone entry has no Source to walk, and nothing is '
      'opened', () async {
    final root = await h.root();
    final (entry, _) = await h.repos.entries.createStandalone(
      folderId: root.id,
      title: 'A loose page',
    );
    final url = partUrl(kHostA, 101);
    final (location, _) = await h.repos.entries.addLocation(
      entryId: entry!.id,
      url: url,
      urlKey: RecognitionKeys.of(url).urlKey,
    );
    final pages = FakeForwardPages.chain(host: kHostA, parts: [101, 102, 103]);

    final outcome = await walkOver(pages).forward(
      fromLocationId: location!.id,
      wanted: 5,
      shouldContinue: alwaysContinue,
    );

    expect(outcome.stop, WalkStop.leftTheSource);
    expect(outcome.entries, isEmpty);
    expect(outcome.pagesRead, 0);
    expect(pages.reads, isEmpty);
  });

  test('an address nothing is known about is not a walk', () async {
    final pages = FakeForwardPages.chain(host: kHostA, parts: [101]);

    final outcome = await walkOver(pages).forward(
      fromLocationId: 'no-such-location',
      wanted: 3,
      shouldContinue: alwaysContinue,
    );

    expect(outcome.stop, WalkStop.leftTheSource);
    expect(outcome.entries, isEmpty);
    expect(pages.reads, isEmpty);
  });

  test('what the source called an entry reaches the entry and its '
      'location', () async {
    final it = await library(held: [101]);
    final pages = FakeForwardPages.chain(host: kHostA, parts: [101, 102]);

    final outcome = await walkOver(pages).forward(
      fromLocationId: it.from.id,
      wanted: 1,
      shouldContinue: alwaysContinue,
    );

    expect(outcome.resolved, 1);
    final entries = await entriesOf(it.collection);
    final walked = entries.firstWhere((e) => e.ordinal == 102);
    expect(
      walked.title,
      'Part 102',
      reason: 'the Entry is named by what the page called it',
    );
    final locations = await locationsOf(walked.id);
    expect(
      locations.single.sourceLabel,
      'Part 102',
      reason: 'and the Location keeps what this Source printed, as a listing '
          'row does',
    );
  });
}
