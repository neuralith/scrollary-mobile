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
}) => PageProbe(
  url: url,
  title: '',
  documentHeight: document,
  viewportHeight: viewport,
  scrollY: scrollY,
);

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
      expect(
        find.byKey(ValueKey('entryProgress-${untouched.id}')),
        findsNothing,
        reason: 'an untouched entry gets no indicator, not an empty one',
      );
      final ring = tester.widget<EntryProgressRing>(
        find.descendant(
          of: find.byKey(ValueKey('entryProgress-${read.id}')),
          matching: find.byType(EntryProgressRing),
        ),
      );
      expect(ring.fraction, closeTo(0.42, 0.0001));
      expect(ring.completed, isFalse);
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
