/// How far through an Entry a reading got — and where that fact comes from.
///
/// **The regression this pins.** V2 has a Measurement model, keyed `(entry,
/// source)` because a fraction of one rendering is not an approximation of
/// another's, and nothing in the app ever wrote one:
/// `MeasurementRepository.put` had a single caller, in the sync *pull* path.
/// So a device only ever held measurements another device had taken, reading
/// an Entry on its own site recorded that it had been opened and nothing
/// about how far, and `EntryProgressRing` — which exists, and has its own
/// test — was drawn on no screen in the app.
///
/// The two halves stay apart on purpose: **reading state is independent of
/// download state** (PRODUCT.md §2.3). Nothing here needs an OfflineCopy.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_reader/browser/page_data.dart';
import 'package:web_reader/data/measurement_repository.dart';
import 'package:web_reader/library_ui/collection_screen.dart';
import 'package:web_reader/reading_v2/source_reading.dart';
import 'package:web_reader/ui/status_style.dart';

import 'support/ui_harness.dart';

/// A page of the given geometry, as the bridge reports one.
PageProbe page({
  required int document,
  required int viewport,
  required int scrollY,
  String url = 'https://alpha.example/works/quiet-harbour/part-1',
  List<PageImage> images = const [],
  bool imagesTruncated = false,
}) => PageProbe(
  url: url,
  title: '',
  documentHeight: document,
  viewportHeight: viewport,
  scrollY: scrollY,
  images: images,
  imagesTruncated: imagesTruncated,
);

/// One content image, as the bridge reports one: an intrinsic size, and a
/// laid-out box at a place in the document.
///
/// [renderedHeight] is deliberately separate from the intrinsic height —
/// that difference is what a band is built from, and getting it wrong is
/// exactly the mistake the band code exists not to make.
PageImage panel({
  required int index,
  required int top,
  int renderedHeight = 1500,
  int width = 800,
  int height = 1200,
  bool hidden = false,
  bool chrome = false,
}) => PageImage(
  domIndex: index,
  src: 'https://alpha.example/img/$index.png',
  complete: true,
  naturalWidth: width,
  naturalHeight: height,
  renderedWidth: width,
  renderedHeight: renderedHeight,
  documentTop: top,
  hidden: hidden,
  inPageChrome: chrome,
);

/// A vertical strip of [count] panels, the shape an image-based Entry has:
/// one under the next, all the same width, ending well before the document
/// does because the site goes on with comments and a footer.
List<PageImage> strip({int count = 6, int from = 500, int pitch = 1500}) => [
  for (var i = 0; i < count; i++)
    panel(index: i, top: from + i * pitch, renderedHeight: pitch),
];

void main() {
  group('what a page reports about its own geometry', () {
    test('the bottom of the viewport is where the reading has got to', () {
      // Halfway down a page twice the viewport's height: the reader can see
      // to 2000 of 4000.
      expect(
        sourceReadingFraction(
          page(document: 4000, viewport: 1000, scrollY: 1000),
        ),
        0.5,
      );
    });

    test('scrolled to the bottom is the end', () {
      expect(
        sourceReadingFraction(
          page(document: 4000, viewport: 1000, scrollY: 3000),
        ),
        1,
      );
    });

    test('a page no taller than the viewport has no position to be at', () {
      expect(
        sourceReadingFraction(page(document: 800, viewport: 1000, scrollY: 0)),
        isNull,
        reason:
            'not 0%, not 100% — there is nothing to measure, and a '
            'figure would be a claim about a reading nobody can observe',
      );
    });

    test('a page that reported no geometry says nothing', () {
      expect(
        sourceReadingFraction(page(document: 0, viewport: 0, scrollY: 0)),
        isNull,
      );
    });
  });

  group('the readable region of an image-based page', () {
    // Six panels, 1500 tall, starting 500 down: the entry ends at 9500 and
    // the site goes on for another 2500 of comments and footer.
    final panels = strip();

    PageProbe imagePage(int scrollY) =>
        page(document: 12000, viewport: 1000, scrollY: scrollY, images: panels);

    test('the band is the panels, not the document', () {
      final band = imageContentBand(imagePage(0));
      expect(band, isNotNull);
      expect(band!.top, 500);
      expect(band.bottom, 9500);
      expect(band.imageCount, 6);
    });

    test('reaching the end of the content is 100%, whatever the site puts '
        'after it', () {
      // The bottom of the viewport is level with the bottom of the last
      // panel. There are 2500 pixels of page left and none of them are the
      // entry.
      expect(sourceReadingFraction(imagePage(8500)), 1);
      expect(
        (8500 + 1000) / 12000,
        closeTo(0.79, 0.01),
        reason: 'what measuring the document would have claimed instead',
      );
    });

    test('the band is measured from, not just to', () {
      // 4000 down: 4500 of the 9000-pixel band is behind the viewport bottom.
      expect(sourceReadingFraction(imagePage(4000)), 0.5);
    });

    test('the top of the page is 0%, never a share of the header', () {
      expect(sourceReadingFraction(imagePage(0)), closeTo(0.0556, 0.001));
    });

    test('a page the probe could not enumerate has no knowable end', () {
      expect(
        imageContentBand(
          page(
            document: 12000,
            viewport: 1000,
            scrollY: 0,
            images: panels,
            imagesTruncated: true,
          ),
        ),
        isNull,
        reason:
            'the last image seen is not known to be the last image there is',
      );
    });

    test('a panel with no laid-out box yet establishes nothing', () {
      final unplaced = [
        ...strip(count: 5),
        panel(index: 5, top: 8000, renderedHeight: 0),
      ];
      expect(
        imageContentBand(
          page(document: 12000, viewport: 1000, scrollY: 0, images: unplaced),
        ),
        isNull,
      );
    });

    test('a grid is not a reading order', () {
      // Two columns: every pair shares a top, so no image follows another.
      final grid = [
        for (var row = 0; row < 4; row++) ...[
          panel(index: row * 2, top: 500 + row * 1500, renderedHeight: 1400),
          panel(
            index: row * 2 + 1,
            top: 500 + row * 1500,
            renderedHeight: 1400,
          ),
        ],
      ];
      expect(
        imageContentBand(
          page(document: 12000, viewport: 1000, scrollY: 0, images: grid),
        ),
        isNull,
      );
    });

    test('two photographs a long way apart are not a band', () {
      final scattered = [
        panel(index: 0, top: 500, renderedHeight: 600),
        panel(index: 1, top: 4000, renderedHeight: 600),
        panel(index: 2, top: 8000, renderedHeight: 600),
      ];
      expect(
        imageContentBand(
          page(document: 12000, viewport: 1000, scrollY: 0, images: scattered),
        ),
        isNull,
        reason: 'the region is mostly not image, so it is not the content',
      );
    });

    test('too few images to show a pattern falls back to the document', () {
      final two = strip(count: 2);
      expect(
        imageContentBand(
          page(document: 12000, viewport: 1000, scrollY: 0, images: two),
        ),
        isNull,
      );
      expect(
        sourceReadingFraction(
          page(document: 12000, viewport: 1000, scrollY: 5000, images: two),
        ),
        0.5,
        reason: 'the whole document, exactly as before',
      );
    });

    /// The band is built from whatever `selectImageCandidates` calls the
    /// content column, so a column rule that picked the wrong images took
    /// this with it. A grid below the strip won the column by member count,
    /// the band was then built from *its* boxes, several of which share a
    /// row — so the single-run test refused, and every reading of a page like
    /// this fell back to the whole document and could never reach 100%.
    test('a grid of thumbnails below the strip does not become the band', () {
      // Twenty covers in rows of five, underneath six content panels.
      final grid = [
        for (var i = 0; i < 20; i++)
          PageImage(
            domIndex: 100 + i,
            src: 'https://alpha.example/img/cover-$i.png',
            complete: true,
            naturalWidth: 400,
            naturalHeight: 580,
            renderedWidth: 200,
            renderedHeight: 290,
            documentTop: 9800 + (i ~/ 5) * 300,
          ),
      ];

      final band = imageContentBand(
        page(
          document: 12000,
          viewport: 1000,
          scrollY: 0,
          images: [...strip(), ...grid],
        ),
      );

      expect(band, isNotNull, reason: 'the page still has a readable band');
      expect(band!.imageCount, 6);
      expect(band.top, 500);
      expect(band.bottom, 9500);
    });

    test('page chrome is not the entry', () {
      final withChrome = [
        panel(index: 99, top: 0, renderedHeight: 1500, chrome: true),
        ...strip(),
      ];
      expect(imageContentBand(imagePage(0))!.top, 500);
      expect(
        imageContentBand(
          page(document: 12000, viewport: 1000, scrollY: 0, images: withChrome),
        )!.top,
        500,
      );
    });
  });

  group('the meter', () {
    late UiHarness h;
    late MeasurementRepository measurements;
    late SourceReadingMeter meter;

    setUp(() {
      h = UiHarness();
      measurements = MeasurementRepository(h.db);
      meter = SourceReadingMeter(measurements);
    });
    tearDown(() => h.close());

    /// One Collection, one Source, one Entry with a Location on it.
    Future<({String entryId, String sourceId, String url})> reading() async {
      final root = await h.root();
      final collection = await h.collection('Quiet Harbour', folderId: root.id);
      final source = await h.source(collection.id, host: 'alpha.example');
      final entry = await h.entryIn(collection.id, title: 'Part 1', ordinal: 1);
      const url = 'https://alpha.example/works/quiet-harbour/part-1';
      await h.services.entries.addLocation(
        entryId: entry.id,
        url: url,
        urlKey: url,
        sourceId: source.id,
      );
      return (entryId: entry.id, sourceId: source.id, url: url);
    }

    test('a reading at a source is recorded without any copy on this '
        'device', () async {
      final it = await reading();
      meter.watch(entryId: it.entryId, sourceId: it.sourceId, url: it.url);

      expect(
        await meter.record(
          page(document: 4000, viewport: 1000, scrollY: 1000, url: it.url),
        ),
        0.5,
      );

      final stored = await measurements.of(it.entryId, it.sourceId);
      expect(stored?.fraction, 0.5);
      expect(
        await h.services.offline.activeCopyOf(it.entryId),
        isNull,
        reason: 'nothing was downloaded, and progress does not need one',
      );
    });

    test('the measurement keeps the source it was taken against', () async {
      final it = await reading();
      meter.watch(entryId: it.entryId, sourceId: it.sourceId, url: it.url);
      await meter.record(
        page(document: 4000, viewport: 1000, scrollY: 3000, url: it.url),
      );

      final all = await measurements.allOf(it.entryId);
      expect(all, hasLength(1));
      expect(all.single.sourceId, it.sourceId);
    });

    test('it never goes down', () async {
      final it = await reading();
      meter.watch(entryId: it.entryId, sourceId: it.sourceId, url: it.url);
      await meter.record(
        page(document: 4000, viewport: 1000, scrollY: 3000, url: it.url),
      );

      // The site reloaded, or the reader scrolled back to check a name.
      expect(
        await meter.record(
          page(document: 4000, viewport: 1000, scrollY: 0, url: it.url),
        ),
        isNull,
      );
      expect(
        (await measurements.of(it.entryId, it.sourceId))?.fraction,
        1,
        reason: 'lowering progress is a deliberate act with its own verb',
      );
    });

    test('a probe of somewhere else is not this entry\'s reading', () async {
      final it = await reading();
      meter.watch(entryId: it.entryId, sourceId: it.sourceId, url: it.url);

      expect(
        await meter.record(
          page(
            document: 4000,
            viewport: 1000,
            scrollY: 2000,
            url: 'https://alpha.example/works/quiet-harbour/part-2',
          ),
        ),
        isNull,
      );
      expect(await measurements.of(it.entryId, it.sourceId), isNull);
    });

    test('a scroll performed for a download is not a reading', () async {
      final it = await reading();
      meter.watch(entryId: it.entryId, sourceId: it.sourceId, url: it.url);
      await meter.record(
        page(document: 4000, viewport: 1000, scrollY: 500, url: it.url),
      );

      // A capture takes the Browser and scrolls the page to the bottom to
      // enumerate it, then leaves it there.
      meter.noteAutomationScroll();

      expect(
        await meter.record(
          page(document: 4000, viewport: 1000, scrollY: 3000, url: it.url),
        ),
        isNull,
      );
      expect(
        (await measurements.of(it.entryId, it.sourceId))?.fraction,
        0.375,
        reason:
            'the reading stands where the reader left it — downloading an '
            'Entry must never be what marks it read',
      );
    });

    test('the seal lifts when the reader moves the page themselves', () async {
      final it = await reading();
      meter.watch(entryId: it.entryId, sourceId: it.sourceId, url: it.url);
      meter.noteAutomationScroll();
      meter.noteUserScroll();

      expect(
        await meter.record(
          page(document: 4000, viewport: 1000, scrollY: 1000, url: it.url),
        ),
        0.5,
      );
    });

    test('watching another page starts a visit that knows nothing', () async {
      final it = await reading();
      meter.watch(entryId: it.entryId, sourceId: it.sourceId, url: it.url);
      meter.noteAutomationScroll();
      meter.noteUserScroll();
      meter.noteUserScroll();
      expect(meter.visit!.scrollEvents, 2);

      meter.watch(entryId: it.entryId, sourceId: it.sourceId, url: it.url);
      final fresh = meter.visit!;
      expect(fresh.scrollEvents, 0);
      expect(fresh.fraction, isNull);
      expect(fresh.automationMoved, isFalse);
      expect(fresh.viewportsCovered, 0);
    });

    test('a visit carries how much reading it represents', () async {
      final it = await reading();
      meter.watch(entryId: it.entryId, sourceId: it.sourceId, url: it.url);
      // Six panels of 1500 over a 1000 viewport: nine screens of content, read
      // to the end.
      await meter.record(
        page(
          document: 12000,
          viewport: 1000,
          scrollY: 8500,
          url: it.url,
          images: strip(),
        ),
      );
      final visit = meter.visit!;
      expect(visit.fraction, 1);
      expect(visit.viewportsCovered, 9);
    });

    test('an unrecognised page has no entry to be a fraction of', () async {
      meter.clear();
      expect(meter.isWatching, isFalse);
      expect(
        await meter.record(page(document: 4000, viewport: 1000, scrollY: 900)),
        isNull,
      );
    });
  });

  group('the row', () {
    late UiHarness h;

    setUp(() => h = UiHarness());
    tearDown(() => h.close());

    screenTest('a measured entry draws how far through it is', (tester) async {
      final root = await h.root();
      final collection = await h.collection('Quiet Harbour', folderId: root.id);
      final source = await h.source(collection.id, host: 'alpha.example');
      final read = await h.entryIn(collection.id, title: 'Part 1', ordinal: 1);
      final untouched = await h.entryIn(
        collection.id,
        title: 'Part 2',
        ordinal: 2,
      );
      await MeasurementRepository(
        h.db,
      ).put(entryId: read.id, sourceId: source.id, fraction: 0.42);

      await tester.pumpWidget(
        h.app(CollectionScreen(collectionId: collection.id)),
      );
      await pumpUntil(tester, find.byKey(ValueKey('entryRow-${read.id}')));

      expect(find.byKey(ValueKey('entryProgress-${read.id}')), findsOneWidget);
      EntryProgressRing ringOf(String entryId) => tester.widget(
        find.descendant(
          of: find.byKey(ValueKey('entryProgress-$entryId')),
          matching: find.byType(EntryProgressRing),
        ),
      );

      final ring = ringOf(read.id);
      expect(ring.fraction, closeTo(0.42, 0.0001));
      expect(ring.completed, isFalse);

      // The untouched Entry gets an **empty** ring rather than no ring
      // (V2-D63). It was left off while the row also printed the word
      // *Unread*; with that word gone, an absent indicator would be
      // indistinguishable from an Entry nothing is known about.
      expect(
        find.byKey(ValueKey('entryProgress-${untouched.id}')),
        findsOneWidget,
      );
      final empty = ringOf(untouched.id);
      expect(empty.fraction, 0);
      expect(empty.completed, isFalse);
    });

    screenTest('a finished entry is a full ring, whatever was measured', (
      tester,
    ) async {
      final root = await h.root();
      final collection = await h.collection('Quiet Harbour', folderId: root.id);
      final source = await h.source(collection.id, host: 'alpha.example');
      final entry = await h.entryIn(collection.id, title: 'Part 1', ordinal: 1);
      await MeasurementRepository(
        h.db,
      ).put(entryId: entry.id, sourceId: source.id, fraction: 0.3);
      await h.reading.markRead(entry.id);

      await tester.pumpWidget(
        h.app(CollectionScreen(collectionId: collection.id)),
      );
      await pumpUntil(tester, find.byKey(ValueKey('entryRow-${entry.id}')));

      final ring = tester.widget<EntryProgressRing>(
        find.descendant(
          of: find.byKey(ValueKey('entryProgress-${entry.id}')),
          matching: find.byType(EntryProgressRing),
        ),
      );
      expect(ring.completed, isTrue);
      expect(
        ring.fraction,
        1,
        reason: 'completed is 100%, enforced on display',
      );
    });
  });
}
