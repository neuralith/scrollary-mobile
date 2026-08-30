/// Reading on to the next Entry **at its Source**, and what that says about
/// the one just left.
///
/// **The gap this pins.** Reading an Entry on a website recorded a fraction
/// and never anything else, so an Entry read to the end at its Source stayed
/// at 99-point-something for ever: on a website there is no *Next entry*
/// control to hang a completion question on, and the page the question would
/// be about is gone by the time the app hears about the navigation. The only
/// evidence left is the visit itself.
///
/// **Moving on is corroboration, never the signal.**
/// `ForwardTransitionService` says it for the offline reader — a reader looks
/// ahead, compares two Entries, mistaps — and it is no more true here. So each
/// test below removes exactly one of the three facts that have to hold
/// together and shows that nothing is written without it.
///
/// Nothing here needs an OfflineCopy: reading state and download state stay
/// independent (PRODUCT.md §2.3).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:web_reader/browser/page_data.dart';
import 'package:web_reader/data/measurement_repository.dart';
import 'package:web_reader/domain/reading_state.dart';
import 'package:web_reader/reading_v2/next_entry.dart';
import 'package:web_reader/reading_v2/source_completion.dart';
import 'package:web_reader/reading_v2/source_reading.dart';

import '../data/support/repo_harness.dart';

/// A vertical strip of six panels, 1500 tall, starting 500 down: nine screens
/// of entry ending at 9500, on a document that runs to 12000 because the site
/// carries on with comments and a footer.
List<PageImage> strip() => [
  for (var i = 0; i < 6; i++)
    PageImage(
      domIndex: i,
      src: 'https://reading.example.com/img/$i.png',
      complete: true,
      naturalWidth: 800,
      naturalHeight: 1200,
      renderedWidth: 800,
      renderedHeight: 1500,
      documentTop: 500 + i * 1500,
    ),
];

PageProbe imagePage({required String url, required int scrollY}) => PageProbe(
  url: url,
  title: '',
  documentHeight: 12000,
  viewportHeight: 1000,
  scrollY: scrollY,
  images: strip(),
);

void main() {
  late RepoHarness h;
  late SourceReadingMeter meter;
  late SourceForwardCompletion completion;

  /// The clock the meter reads. A visit's dwell is the whole difference
  /// between a reading and a flick through, so the test drives it directly.
  late DateTime clock;

  late String partOne;
  late String partTwo;
  late String partThree;
  late String sourceId;
  late String urlOne;

  setUp(() async {
    h = RepoHarness();
    clock = DateTime.utc(2026, 8, 30, 9);
    meter = SourceReadingMeter(MeasurementRepository(h.db), now: () => clock);
    completion = SourceForwardCompletion(
      entries: h.entries,
      reading: h.reading,
      nextEntry: NextEntryResolver(
        entries: h.entries,
        collections: h.collections,
        offlineCopies: h.offline,
      ),
    );

    final seeded = await h.seedLibrary();
    partOne = seeded.entry.id;
    sourceId = seeded.source.id;
    urlOne = seeded.location.url;

    Future<String> next(double ordinal) async {
      final (row, violation) = await h.entries.createInCollection(
        collectionId: seeded.collection.id,
        ordinal: ordinal,
        title: 'Part ${ordinal.toInt()}',
      );
      expect(violation, isNull);
      final url =
          'https://reading.example.com/serial-alpha/part-${ordinal.toInt()}';
      await h.entries.addLocation(
        entryId: row!.id,
        sourceId: seeded.source.id,
        url: url,
        urlKey: url,
      );
      return row.id;
    }

    partTwo = await next(102);
    partThree = await next(103);
  });
  tearDown(() => h.close());

  /// Read Part 101 to the end of its panels, at [pace] per scroll, in
  /// [scrolls] movements.
  Future<void> readToTheEnd({
    int scrolls = 12,
    Duration pace = const Duration(seconds: 5),
  }) async {
    meter.watch(entryId: partOne, sourceId: sourceId, url: urlOne);
    for (var i = 0; i < scrolls; i++) {
      clock = clock.add(pace);
      meter.noteUserScroll();
    }
    // The bottom of the viewport level with the bottom of the last panel.
    await meter.record(imagePage(url: urlOne, scrollY: 8500));
  }

  Future<ReadStatus> statusOf(String entryId) async =>
      (await h.reading.stateOf(entryId)).status;

  test('a genuine reading, then the next entry, is a completion', () async {
    await readToTheEnd();
    expect(
      meter.visit!.fraction,
      1,
      reason: 'measured against the panels, not the comments below them',
    );

    expect(
      await completion.arrivedAt(entryId: partTwo, leaving: meter.visit),
      SourceCompletionOutcome.completed,
    );
    expect(await statusOf(partOne), ReadStatus.completed);
  });

  test('a fast tap through to the next entry marks nothing', () async {
    // The site's own next link, three seconds and two flicks after landing.
    meter.watch(entryId: partOne, sourceId: sourceId, url: urlOne);
    clock = clock.add(const Duration(seconds: 2));
    meter.noteUserScroll();
    clock = clock.add(const Duration(seconds: 1));
    meter.noteUserScroll();
    await meter.record(imagePage(url: urlOne, scrollY: 8500));

    expect(
      await completion.arrivedAt(entryId: partTwo, leaving: meter.visit),
      SourceCompletionOutcome.tooFast,
    );
    expect(await statusOf(partOne), isNot(ReadStatus.completed));
  });

  test('a fling to the bottom is not nine screens of reading', () async {
    // Long enough to clear the floor, far too fast for what it covered: nine
    // viewports of content in sixteen seconds.
    await readToTheEnd(scrolls: 4, pace: const Duration(seconds: 4));
    expect(meter.visit!.viewportsCovered, 9);
    expect(meter.visit!.dwell, const Duration(seconds: 16));

    expect(
      await completion.arrivedAt(entryId: partTwo, leaving: meter.visit),
      SourceCompletionOutcome.tooFast,
    );
    expect(await statusOf(partOne), isNot(ReadStatus.completed));
  });

  test('an entry read halfway is not finished by opening another', () async {
    meter.watch(entryId: partOne, sourceId: sourceId, url: urlOne);
    for (var i = 0; i < 12; i++) {
      clock = clock.add(const Duration(seconds: 10));
      meter.noteUserScroll();
    }
    await meter.record(imagePage(url: urlOne, scrollY: 4000));
    expect(meter.visit!.fraction, 0.5);

    expect(
      await completion.arrivedAt(entryId: partTwo, leaving: meter.visit),
      SourceCompletionOutcome.notFinished,
    );
    expect(await statusOf(partOne), isNot(ReadStatus.completed));
  });

  test('reading on to something that is not the next entry means '
      'nothing', () async {
    await readToTheEnd();
    expect(
      await completion.arrivedAt(entryId: partThree, leaving: meter.visit),
      SourceCompletionOutcome.notTheNextEntry,
    );
    expect(await statusOf(partOne), isNot(ReadStatus.completed));
  });

  test('a page a download scrolled cannot complete anything', () async {
    await readToTheEnd();
    // A capture takes the Browser, scrolls the page to enumerate it, and the
    // journey moves on to the next entry's page.
    meter.noteAutomationScroll();

    expect(
      await completion.arrivedAt(entryId: partTwo, leaving: meter.visit),
      SourceCompletionOutcome.automationMoved,
    );
    expect(
      await statusOf(partOne),
      isNot(ReadStatus.completed),
      reason: 'downloading an Entry is never what marks it read',
    );
  });

  test('nothing was being read', () async {
    expect(
      await completion.arrivedAt(entryId: partTwo, leaving: null),
      SourceCompletionOutcome.noVisit,
    );
  });

  test('an entry already read is left alone', () async {
    await h.reading.markRead(partOne);
    await readToTheEnd();
    expect(
      await completion.arrivedAt(entryId: partTwo, leaving: meter.visit),
      SourceCompletionOutcome.alreadyRead,
    );
  });

  test('completion writes reading state and nothing else', () async {
    await readToTheEnd();
    await completion.arrivedAt(entryId: partTwo, leaving: meter.visit);

    expect(await h.offline.activeCopyOf(partOne), isNull);
    final entry = await h.entries.byId(partOne);
    expect(entry!.collectionId, isNotNull);
    expect(await statusOf(partTwo), ReadStatus.unread);
  });
}
