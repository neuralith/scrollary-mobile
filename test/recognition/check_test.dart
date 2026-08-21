/// Preferred-source update checking (F4): one Source per ordinary check, a
/// checkpoint that only ever moves on evidence, and the two things a check must
/// never do — claim "up to date" after a reading it cannot vouch for, and
/// overwrite something already established with a second opinion.
library;

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_reader/data/schema.dart';
import 'package:web_reader/domain/collection.dart';
import 'package:web_reader/domain/entry.dart';
import 'package:web_reader/domain/source.dart';
import 'package:web_reader/domain/location.dart';
import 'package:web_reader/recognition/check.dart';
import 'package:web_reader/recognition/discovery.dart';
import 'package:web_reader/recognition/recognise.dart';
import 'package:web_reader/save/capture_policy.dart';

import '../data/support/repo_harness.dart';
import 'support/recognition_harness.dart';

/// A scripted stand-in for whatever drives the browser. Records what it was
/// asked about, so "one Source per ordinary check" is assertable.
class ScriptedObservations implements SourceObservationSource {
  ScriptedObservations([List<SourceObservation> pages = const []])
    : _pages = [...pages];

  final List<SourceObservation> _pages;

  /// The Source id of every reading asked for, in order.
  final askedSources = <String>[];

  /// The page address of every reading asked for; null is "wherever the
  /// listing begins".
  final askedPages = <String?>[];

  /// Set by [stopAfter]: the reading count after which the run is cancelled.
  int? cancelAfter;
  bool cancelled = false;

  int _next = 0;

  bool shouldContinue() => !cancelled;

  @override
  Future<SourceObservation> observe({
    required SourceRow source,
    required String? pageUrl,
    required bool Function() shouldContinue,
  }) async {
    askedSources.add(source.id);
    askedPages.add(pageUrl);
    final page = _next < _pages.length
        ? _pages[_next]
        : SourceObservation.unreadable(
            url: pageUrl ?? '',
            stop: SourceCheckStop.listingUnreadable,
          );
    _next++;
    if (cancelAfter != null && _next >= cancelAfter!) cancelled = true;
    return page;
  }
}

String _plain(num n) => n == n.roundToDouble() ? '${n.round()}' : '$n';

/// One page of a listing: label `Part <n + printedOffset>` at `/part-<n>`.
SourceObservation listingPage({
  required String host,
  required Iterable<num> parts,
  double printedOffset = 0,
  bool listRecognised = true,
  bool orderingConfident = true,
  bool newestFirst = false,
  int dropped = 0,
  String? nextPageUrl,
  String? url,
}) => SourceObservation.read(
  url: url ?? 'https://$host$kWorkPath',
  listings: [
    for (final n in parts)
      ObservedEntryListing.read(
        url: partUrl(host, _plain(n)),
        label: 'Part ${_plain(n + printedOffset)}',
      ),
  ],
  listRecognised: listRecognised,
  orderingConfident: orderingConfident,
  newestFirst: newestFirst,
  dropped: dropped,
  nextPageUrl: nextPageUrl,
);

const kGenerousLimits = SourceCheckLimits(maxPages: 4, maxNewEntries: 20);

void main() {
  late RecognitionHarness h;

  setUp(() => h = RecognitionHarness());
  tearDown(() => h.close());

  SourceCheck checkerOver(ScriptedObservations observations) => SourceCheck(
    collections: h.repos.collections,
    entries: h.repos.entries,
    index: h.repos.recognition,
    discovery: h.discovery,
    observations: observations,
  );

  Future<LocationRow> locationAt(String url) async {
    final hit = await h.repos.recognition.lookupUrl(
      RecognitionKeys.of(url).urlKey,
    );
    expect(hit, isNotNull, reason: 'expected a Location at $url');
    return hit!.location;
  }

  group('what one check reads', () {
    test(
      'the ordinary check reads the preferred Source and no other',
      () async {
        final collection = await h.collection();
        final alpha = await h.source(collection: collection, host: kHostA);
        final beta = await h.source(collection: collection, host: kHostB);
        await h.repos.collections.setPreferredSource(collection.id, alpha.id);

        final observations = ScriptedObservations([
          listingPage(host: kHostA, parts: [5, 6]),
        ]);
        final outcome = await checkerOver(observations).checkPreferredSource(
          collection.id,
          limits: kGenerousLimits,
          shouldContinue: observations.shouldContinue,
        );

        expect(outcome.sourceId, alpha.id);
        expect(
          observations.askedSources,
          [alpha.id],
          reason: 'one Source per ordinary check; beta is never touched',
        );
        expect(observations.askedSources, isNot(contains(beta.id)));
      },
    );

    test('several Sources and no preference is refused, not guessed', () async {
      final collection = await h.collection();
      await h.source(collection: collection, host: kHostA);
      await h.source(collection: collection, host: kHostB);

      final observations = ScriptedObservations([
        listingPage(host: kHostA, parts: [5]),
      ]);
      final outcome = await checkerOver(observations).checkPreferredSource(
        collection.id,
        limits: kGenerousLimits,
        shouldContinue: observations.shouldContinue,
      );

      expect(outcome.state, SourceCheckState.stopped);
      expect(outcome.stopReason, SourceCheckStop.preferredSourceNotChosen);
      expect(observations.askedSources, isEmpty, reason: 'nothing was opened');
    });

    test(
      'an archived Collection is no longer followed, so nothing is read',
      () async {
        final collection = await h.collection();
        await h.source(collection: collection, host: kHostA);
        await h.repos.collections.archive(collection.id);

        final observations = ScriptedObservations([
          listingPage(host: kHostA, parts: [5]),
        ]);
        final outcome = await checkerOver(observations).checkPreferredSource(
          collection.id,
          limits: kGenerousLimits,
          shouldContinue: observations.shouldContinue,
        );

        expect(outcome.stopReason, SourceCheckStop.collectionNotFollowed);
        expect(observations.askedSources, isEmpty);
      },
    );

    test(
      'a Source on a restricted service is refused before anything opens',
      () async {
        final collection = await h.collection();
        // Read from the policy's own list rather than naming a host here.
        final restricted = restrictedCaptureDomains.first;
        final source = await h.source(collection: collection, host: restricted);

        final observations = ScriptedObservations([
          listingPage(host: restricted, parts: [5]),
        ]);
        final outcome = await checkerOver(observations).checkSource(
          source.id,
          limits: kGenerousLimits,
          shouldContinue: observations.shouldContinue,
        );

        expect(outcome.stopReason, SourceCheckStop.captureRestrictedForSite);
        expect(outcome.isCaptureRestricted, isTrue);
        expect(observations.askedSources, isEmpty);
        expect(await h.repos.entries.entriesOf(collection.id), isEmpty);
      },
    );

    test(
      'a listed address on a restricted service is never recorded',
      () async {
        final collection = await h.collection();
        await h.source(collection: collection, host: kHostA);
        final restricted = restrictedCaptureDomains.first;

        final observations = ScriptedObservations([
          SourceObservation.read(
            url: 'https://$kHostA$kWorkPath',
            listings: [
              ObservedEntryListing.read(
                url: partUrl(kHostA, 5),
                label: 'Part 5',
              ),
              ObservedEntryListing.read(
                url: partUrl(kHostA, 6),
                label: 'Part 6',
              ),
              ObservedEntryListing.read(
                url: partUrl(restricted, 7),
                label: 'Part 7',
              ),
            ],
            listRecognised: true,
            orderingConfident: true,
            newestFirst: false,
          ),
        ]);
        final outcome = await checkerOver(observations).checkPreferredSource(
          collection.id,
          limits: kGenerousLimits,
          shouldContinue: observations.shouldContinue,
        );

        expect(
          outcome.restrictedAddresses,
          1,
          reason: 'withheld and counted, never silently dropped',
        );
        expect(outcome.newEntryIds, hasLength(2));
        expect(
          await h.repos.recognition.lookupUrl(
            RecognitionKeys.of(partUrl(restricted, 7)).urlKey,
          ),
          isNull,
          reason: 'a row the user would be invited to download is not written',
        );
      },
    );
  });

  group('novelty against this Source\'s own checkpoint', () {
    test(
      'new addresses above the checkpoint are recorded, and nothing else moves',
      () async {
        final collection = await h.collection();
        final alpha = await h.source(collection: collection, host: kHostA);
        final (seeded, seededLocation) = await h.placedEntry(
          collection: collection,
          source: alpha,
          host: kHostA,
          number: 5,
        );

        final before = await h.repos.outboxCount();
        final observations = ScriptedObservations([
          listingPage(host: kHostA, parts: [5, 6, 7]),
        ]);
        final outcome = await checkerOver(observations).checkPreferredSource(
          collection.id,
          limits: kGenerousLimits,
          shouldContinue: observations.shouldContinue,
        );

        expect(outcome.state, SourceCheckState.updatesAvailable);
        expect(outcome.stopReason, isNull);
        expect(outcome.vouchesForReading, isTrue);
        expect(outcome.checkpoint, 5);
        expect(outcome.newEntryIds, hasLength(2));
        expect(outcome.discovery.unplacedEntryIds, isEmpty);
        expect(outcome.discovery.addedLocationIds, hasLength(2));
        expect(outcome.discovery.alreadyHeld, 1);
        expect(outcome.notClaimedAsNew, 0);
        expect(outcome.pagesRead, 1);

        final entries = await h.repos.entries.entriesOf(collection.id);
        expect(entries.map((e) => e.ordinal), [5, 6, 7]);
        expect(
          entries.map((e) => e.placement),
          everyElement(Placement.placed.name),
        );

        expect(
          await h.repos.entries.byId(seeded.id),
          seeded,
          reason: 'the Entry already held is not rewritten by a re-listing',
        );
        final relisted = (await h.repos.entries.locationById(
          seededLocation.id,
        ))!;
        expect(
          (relisted.sourceLabel, relisted.sourceNumber, relisted.discoveredAt),
          (
            seededLocation.sourceLabel,
            seededLocation.sourceNumber,
            seededLocation.discoveredAt,
          ),
          reason:
              'nothing its Location had established is rewritten, and a '
              're-sighting is not a discovery',
        );
        expect(
          relisted.discoveryBasis,
          kSourceListingBasis,
          reason: 'the one blank this re-listing filled',
        );
        expect(
          (await h.repos.reading.stateOf(seeded.id)).firstOpenedAt,
          isNull,
          reason: 'a check reads a listing, never the Entry',
        );
        expect(
          await h.repos.outboxCount(),
          before + 5,
          reason:
              'two Entries and two Locations, each one intent, and one more '
              'for the blank the re-listing filled',
        );
      },
    );

    test(
      'the back catalogue below the checkpoint is left where it is',
      () async {
        final collection = await h.collection();
        final alpha = await h.source(collection: collection, host: kHostA);
        await h.placedEntry(
          collection: collection,
          source: alpha,
          host: kHostA,
          number: 100,
        );

        final observations = ScriptedObservations([
          listingPage(host: kHostA, parts: [97, 98, 99, 100, 101]),
        ]);
        final outcome = await checkerOver(observations).checkPreferredSource(
          collection.id,
          limits: kGenerousLimits,
          shouldContinue: observations.shouldContinue,
        );

        expect(outcome.checkpoint, 100);
        expect(outcome.newEntryIds, hasLength(1));
        expect(
          outcome.notClaimedAsNew,
          3,
          reason: '97, 98 and 99 stay unfound',
        );
        final entries = await h.repos.entries.entriesOf(collection.id);
        expect(entries.map((e) => e.ordinal), [100, 101]);
      },
    );

    test(
      'with no checkpoint the first reading reports the whole listing',
      () async {
        final collection = await h.collection();
        await h.source(collection: collection, host: kHostA);

        final observations = ScriptedObservations([
          listingPage(host: kHostA, parts: [1, 2, 3]),
        ]);
        final outcome = await checkerOver(observations).checkPreferredSource(
          collection.id,
          limits: kGenerousLimits,
          shouldContinue: observations.shouldContinue,
        );

        expect(outcome.checkpoint, isNull);
        expect(outcome.newEntryIds, hasLength(3));
        expect(outcome.notClaimedAsNew, 0);
      },
    );

    test(
      'an unnumbered address is never claimed as new against a checkpoint',
      () async {
        final collection = await h.collection();
        final alpha = await h.source(collection: collection, host: kHostA);
        await h.placedEntry(
          collection: collection,
          source: alpha,
          host: kHostA,
          number: 5,
        );

        final observations = ScriptedObservations([
          SourceObservation.read(
            url: 'https://$kHostA$kWorkPath',
            listings: [
              ObservedEntryListing.read(
                url: partUrl(kHostA, 5),
                label: 'Part 5',
              ),
              ObservedEntryListing.read(
                url: postUrl(kHostA, 'a-walk-before-rain'),
                label: 'A walk before rain',
              ),
            ],
            listRecognised: true,
            orderingConfident: true,
            newestFirst: false,
          ),
        ]);
        final outcome = await checkerOver(observations).checkPreferredSource(
          collection.id,
          limits: kGenerousLimits,
          shouldContinue: observations.shouldContinue,
        );

        expect(outcome.notClaimedAsNew, 1);
        expect(
          outcome.newEntryIds,
          isEmpty,
          reason: 'no position to compare, so no claim — never a guessed one',
        );
        expect(await h.repos.entries.entriesOf(collection.id), hasLength(1));
      },
    );

    test(
      'an unnumbered address with no checkpoint becomes an unplaced Entry',
      () async {
        final collection = await h.collection();
        await h.source(collection: collection, host: kHostA);

        final observations = ScriptedObservations([
          SourceObservation.read(
            url: 'https://$kHostA$kWorkPath',
            listings: [
              ObservedEntryListing.read(
                url: postUrl(kHostA, 'a-walk-before-rain'),
                label: 'A walk before rain',
              ),
            ],
            listRecognised: true,
            orderingConfident: true,
            newestFirst: false,
          ),
        ]);
        final outcome = await checkerOver(observations).checkPreferredSource(
          collection.id,
          limits: kGenerousLimits,
          shouldContinue: observations.shouldContinue,
        );

        expect(outcome.newEntryIds, hasLength(1));
        expect(outcome.discovery.unplacedEntryIds, outcome.newEntryIds);
        expect(await h.repos.entries.unplacedOf(collection.id), hasLength(1));
      },
    );
  });

  group('finished, and stopped, are different outcomes', () {
    test('a complete reading that showed nothing new is up to date', () async {
      final collection = await h.collection();
      final alpha = await h.source(collection: collection, host: kHostA);
      await h.discovery.apply(
        h.window(source: alpha, host: kHostA, parts: [5, 6, 7]),
      );

      final before = await h.repos.outboxCount();
      final observations = ScriptedObservations([
        listingPage(host: kHostA, parts: [5, 6, 7]),
      ]);
      final outcome = await checkerOver(observations).checkPreferredSource(
        collection.id,
        limits: kGenerousLimits,
        shouldContinue: observations.shouldContinue,
      );

      expect(outcome.state, SourceCheckState.upToDate);
      expect(outcome.stopReason, isNull);
      expect(outcome.newEntryIds, isEmpty);
      expect(outcome.discovery.addedLocationIds, isEmpty);
      expect(outcome.discovery.alreadyHeld, 3);
      expect(await h.repos.outboxCount(), before);
    });

    test(
      'a page that could not be read is stopped, never up to date',
      () async {
        final collection = await h.collection();
        await h.source(collection: collection, host: kHostA);

        final observations = ScriptedObservations([
          const SourceObservation.unreadable(
            url: 'https://$kHostA$kWorkPath',
            stop: SourceCheckStop.listingUnreadable,
          ),
        ]);
        final outcome = await checkerOver(observations).checkPreferredSource(
          collection.id,
          limits: kGenerousLimits,
          shouldContinue: observations.shouldContinue,
        );

        expect(outcome.state, SourceCheckState.stopped);
        expect(outcome.stopReason, SourceCheckStop.listingUnreadable);
        expect(outcome.vouchesForReading, isFalse);
        expect(outcome.state, isNot(SourceCheckState.upToDate));
      },
    );

    test('a page that was not this Source\'s listing is stopped', () async {
      final collection = await h.collection();
      await h.source(collection: collection, host: kHostA);

      final observations = ScriptedObservations([
        listingPage(host: kHostA, parts: [5, 6], listRecognised: false),
      ]);
      final outcome = await checkerOver(observations).checkPreferredSource(
        collection.id,
        limits: kGenerousLimits,
        shouldContinue: observations.shouldContinue,
      );

      expect(outcome.stopReason, SourceCheckStop.listingUnrecognised);
      expect(outcome.state, SourceCheckState.stopped);
      expect(await h.repos.entries.entriesOf(collection.id), isEmpty);
    });

    test(
      'an ambiguously ordered listing cannot conclude "nothing new"',
      () async {
        final collection = await h.collection();
        final alpha = await h.source(collection: collection, host: kHostA);
        await h.discovery.apply(
          h.window(source: alpha, host: kHostA, parts: [5, 6, 7]),
        );

        final observations = ScriptedObservations([
          listingPage(host: kHostA, parts: [5, 6, 7], orderingConfident: false),
        ]);
        final outcome = await checkerOver(observations).checkPreferredSource(
          collection.id,
          limits: kGenerousLimits,
          shouldContinue: observations.shouldContinue,
        );

        expect(outcome.state, SourceCheckState.stopped);
        expect(outcome.stopReason, SourceCheckStop.listingOrderingAmbiguous);
      },
    );

    test('a contradicted number stops the check and writes nothing', () async {
      final collection = await h.collection();
      await h.source(collection: collection, host: kHostA);

      final before = await h.repos.outboxCount();
      final observations = ScriptedObservations([
        SourceObservation.read(
          url: 'https://$kHostA$kWorkPath',
          listings: [
            ObservedEntryListing.read(url: partUrl(kHostA, 5), label: 'Part 5'),
            ObservedEntryListing.read(url: partUrl(kHostA, 6), label: 'Part 6'),
            ObservedEntryListing.read(
              url: partUrl(kHostA, 7),
              label: 'Part 5000',
            ),
          ],
          listRecognised: true,
          orderingConfident: true,
          newestFirst: false,
        ),
      ]);
      final outcome = await checkerOver(observations).checkPreferredSource(
        collection.id,
        limits: kGenerousLimits,
        shouldContinue: observations.shouldContinue,
      );

      expect(outcome.state, SourceCheckState.stopped);
      expect(outcome.stopReason, SourceCheckStop.entryIdentityUnsupported);
      expect(outcome.concerns, hasLength(1));
      expect(outcome.concerns.single.labelNumber, 5000);
      expect(await h.repos.entries.entriesOf(collection.id), isEmpty);
      expect(await h.repos.outboxCount(), before);
    });

    test(
      'the new-entry ceiling stops the check and is not a clean result',
      () async {
        final collection = await h.collection();
        await h.source(collection: collection, host: kHostA);

        final observations = ScriptedObservations([
          listingPage(host: kHostA, parts: [1, 2, 3, 4]),
        ]);
        final outcome = await checkerOver(observations).checkPreferredSource(
          collection.id,
          limits: const SourceCheckLimits(maxPages: 4, maxNewEntries: 2),
          shouldContinue: observations.shouldContinue,
        );

        expect(outcome.state, SourceCheckState.updatesAvailable);
        expect(outcome.stopReason, SourceCheckStop.newEntryLimitReached);
        expect(outcome.vouchesForReading, isFalse);
        final entries = await h.repos.entries.entriesOf(collection.id);
        expect(
          entries.map((e) => e.ordinal),
          [1, 2],
          reason: 'oldest first, so what was taken is a contiguous block',
        );
      },
    );

    test(
      'the page ceiling stops the check with the listing unfinished',
      () async {
        final collection = await h.collection();
        await h.source(collection: collection, host: kHostA);

        final observations = ScriptedObservations([
          listingPage(
            host: kHostA,
            parts: [1, 2],
            nextPageUrl: 'https://$kHostA$kWorkPath?page=2',
          ),
        ]);
        final outcome = await checkerOver(observations).checkPreferredSource(
          collection.id,
          limits: const SourceCheckLimits(maxPages: 1, maxNewEntries: 20),
          shouldContinue: observations.shouldContinue,
        );

        expect(outcome.pagesRead, 1);
        expect(outcome.stopReason, SourceCheckStop.pageLimitReached);
        expect(outcome.newEntryIds, hasLength(2));
      },
    );

    test(
      'a reading that left addresses out cannot conclude anything',
      () async {
        final collection = await h.collection();
        final alpha = await h.source(collection: collection, host: kHostA);
        await h.discovery.apply(
          h.window(source: alpha, host: kHostA, parts: [5, 6, 7]),
        );

        final observations = ScriptedObservations([
          listingPage(host: kHostA, parts: [5, 7], dropped: 1),
        ]);
        final outcome = await checkerOver(observations).checkPreferredSource(
          collection.id,
          limits: kGenerousLimits,
          shouldContinue: observations.shouldContinue,
        );

        expect(outcome.state, SourceCheckState.stopped);
        expect(outcome.stopReason, SourceCheckStop.listingTruncated);
        expect(
          outcome.discovery.retractedLocationIds,
          isEmpty,
          reason: 'part 6 is absent from a reading that admits it is short',
        );
        expect(
          (await locationAt(partUrl(kHostA, 6))).lifecycle,
          LocationLifecycle.active.name,
        );
      },
    );

    test('a paginated listing is followed to its end, seams and all', () async {
      final collection = await h.collection();
      await h.source(collection: collection, host: kHostA);

      const nextPage = 'https://$kHostA$kWorkPath?page=2';
      final observations = ScriptedObservations([
        listingPage(host: kHostA, parts: [1, 2], nextPageUrl: nextPage),
        // The seam repeats part 2, as a paginated listing does.
        listingPage(host: kHostA, parts: [2, 3, 4]),
      ]);
      final outcome = await checkerOver(observations).checkPreferredSource(
        collection.id,
        limits: kGenerousLimits,
        shouldContinue: observations.shouldContinue,
      );

      expect(outcome.pagesRead, 2);
      expect(
        observations.askedPages,
        [null, nextPage],
        reason:
            'the first reading begins where the listing does; the second '
            'goes where the first said to',
      );
      expect(outcome.stopReason, isNull);
      expect(outcome.newEntryIds, hasLength(4));
      expect(
        (await h.repos.entries.entriesOf(collection.id)).map((e) => e.ordinal),
        [1, 2, 3, 4],
        reason: 'one address is one listing however many pages showed it',
      );
    });

    test(
      'a listing that ends on its last allowed page was read in full',
      () async {
        final collection = await h.collection();
        await h.source(collection: collection, host: kHostA);

        final observations = ScriptedObservations([
          listingPage(host: kHostA, parts: [1, 2]),
        ]);
        final outcome = await checkerOver(observations).checkPreferredSource(
          collection.id,
          limits: const SourceCheckLimits(maxPages: 1, maxNewEntries: 20),
          shouldContinue: observations.shouldContinue,
        );

        expect(outcome.stopReason, isNull);
        expect(outcome.state, SourceCheckState.updatesAvailable);
      },
    );
  });

  group('cancelling', () {
    test(
      'a cancelled reading keeps what it saw and retracts nothing',
      () async {
        final collection = await h.collection();
        final alpha = await h.source(collection: collection, host: kHostA);
        await h.discovery.apply(
          h.window(source: alpha, host: kHostA, parts: [6, 7]),
        );
        // An address this Source holds that the truncated reading omits, and
        // which a complete reading of 6..9 would cover.
        final (_, aside) = await h.placedEntry(
          collection: collection,
          source: alpha,
          host: kHostA,
          number: 6.5,
        );

        final observations = ScriptedObservations([
          listingPage(
            host: kHostA,
            parts: [6, 7],
            nextPageUrl: 'https://$kHostA$kWorkPath?page=2',
          ),
          listingPage(host: kHostA, parts: [8, 9]),
        ])..cancelAfter = 1;

        final outcome = await checkerOver(observations).checkPreferredSource(
          collection.id,
          limits: kGenerousLimits,
          shouldContinue: observations.shouldContinue,
        );

        expect(outcome.pagesRead, 1, reason: 'stopped at the next safe point');
        expect(outcome.stopReason, SourceCheckStop.cancelledByUser);
        expect(outcome.state, SourceCheckState.stopped);
        expect(outcome.vouchesForReading, isFalse);
        expect(outcome.discovery.retractedLocationIds, isEmpty);
        expect(
          (await h.repos.entries.locationById(aside.id))!.lifecycle,
          LocationLifecycle.active.name,
          reason: 'absence from a truncated reading proves nothing',
        );
        expect(
          await h.repos.entries.entriesOf(collection.id),
          hasLength(3),
          reason: '8 and 9 were never read',
        );
      },
    );

    test(
      'a cancelled reading still records the new addresses it did see',
      () async {
        final collection = await h.collection();
        await h.source(collection: collection, host: kHostA);

        final observations = ScriptedObservations([
          listingPage(
            host: kHostA,
            parts: [1, 2],
            nextPageUrl: 'https://$kHostA$kWorkPath?page=2',
          ),
          listingPage(host: kHostA, parts: [3, 4]),
        ])..cancelAfter = 1;

        final outcome = await checkerOver(observations).checkPreferredSource(
          collection.id,
          limits: kGenerousLimits,
          shouldContinue: observations.shouldContinue,
        );

        expect(outcome.stopReason, SourceCheckStop.cancelledByUser);
        expect(outcome.state, SourceCheckState.updatesAvailable);
        expect(outcome.newEntryIds, hasLength(2));
        expect(
          (await h.repos.entries.entriesOf(
            collection.id,
          )).map((e) => e.ordinal),
          [1, 2],
          reason:
              'what was recorded is true; rolling it back deletes nothing '
              'anybody asked to delete',
        );
      },
    );

    test('a check cancelled before it opens anything reads nothing', () async {
      final collection = await h.collection();
      await h.source(collection: collection, host: kHostA);

      final observations = ScriptedObservations([
        listingPage(host: kHostA, parts: [1]),
      ])..cancelled = true;

      final outcome = await checkerOver(observations).checkPreferredSource(
        collection.id,
        limits: kGenerousLimits,
        shouldContinue: observations.shouldContinue,
      );

      expect(outcome.stopReason, SourceCheckStop.cancelledByUser);
      expect(observations.askedSources, isEmpty);
    });
  });

  group('retraction, through the check', () {
    test(
      'a complete reading retracts what it covered and did not show',
      () async {
        final collection = await h.collection();
        final alpha = await h.source(collection: collection, host: kHostA);
        await h.discovery.apply(
          h.window(source: alpha, host: kHostA, parts: [5, 6, 7]),
        );

        final observations = ScriptedObservations([
          listingPage(host: kHostA, parts: [5, 7]),
        ]);
        final outcome = await checkerOver(observations).checkPreferredSource(
          collection.id,
          limits: kGenerousLimits,
          shouldContinue: observations.shouldContinue,
        );

        expect(outcome.discovery.retractedLocationIds, hasLength(1));
        expect(
          (await locationAt(partUrl(kHostA, 6))).lifecycle,
          LocationLifecycle.retracted.name,
        );
        expect(
          await h.repos.entries.entriesOf(collection.id),
          hasLength(3),
          reason: 'retraction is evidence about a listing, never a deletion',
        );
      },
    );

    test('a reading of one Source never retracts another\'s (I15)', () async {
      final collection = await h.collection();
      final alpha = await h.source(collection: collection, host: kHostA);
      final beta = await h.source(
        collection: collection,
        host: kHostB,
        language: 'tr',
      );
      await h.repos.collections.setPreferredSource(collection.id, alpha.id);
      await h.discovery.apply(
        h.window(source: alpha, host: kHostA, parts: [5, 6, 7]),
      );
      await h.discovery.apply(
        h.window(source: beta, host: kHostB, parts: [5, 6, 7]),
      );

      final observations = ScriptedObservations([
        listingPage(host: kHostA, parts: [5, 7]),
      ]);
      final outcome = await checkerOver(observations).checkPreferredSource(
        collection.id,
        limits: kGenerousLimits,
        shouldContinue: observations.shouldContinue,
      );

      expect(outcome.discovery.retractedLocationIds, hasLength(1));
      expect(
        (await locationAt(partUrl(kHostA, 6))).lifecycle,
        LocationLifecycle.retracted.name,
      );
      expect(
        (await locationAt(partUrl(kHostB, 6))).lifecycle,
        LocationLifecycle.active.name,
        reason: 'beta was not read, so beta said nothing',
      );
    });

    test('an address outside the interval is never retracted', () async {
      final collection = await h.collection();
      final alpha = await h.source(collection: collection, host: kHostA);
      await h.discovery.apply(
        h.window(source: alpha, host: kHostA, parts: [3, 5, 6, 7]),
      );

      final observations = ScriptedObservations([
        listingPage(host: kHostA, parts: [5, 6, 7]),
      ]);
      await checkerOver(observations).checkPreferredSource(
        collection.id,
        limits: kGenerousLimits,
        shouldContinue: observations.shouldContinue,
      );

      expect(
        (await locationAt(partUrl(kHostA, 3))).lifecycle,
        LocationLifecycle.active.name,
        reason: 'below the floor is where the previous page lives',
      );
    });

    test('a retracted address stops holding the checkpoint', () async {
      final collection = await h.collection();
      final alpha = await h.source(collection: collection, host: kHostA);
      await h.discovery.apply(
        h.window(source: alpha, host: kHostA, parts: [5, 6, 9]),
      );

      // The Source now lists 7, 6, 5 newest-first and no longer lists 9, so
      // this reading rules out everything above 7. A checkpoint of 9 would
      // make 7 look old; the reading corrects it before measuring.
      final observations = ScriptedObservations([
        listingPage(host: kHostA, parts: [7, 6, 5], newestFirst: true),
      ]);
      final outcome = await checkerOver(observations).checkPreferredSource(
        collection.id,
        limits: kGenerousLimits,
        shouldContinue: observations.shouldContinue,
      );

      expect(outcome.checkpoint, 6, reason: '9 is no longer true');
      expect(outcome.newEntryIds, hasLength(1));
      expect(
        (await locationAt(partUrl(kHostA, 7))).sourceNumber,
        7,
        reason: 'the address above the corrected checkpoint was recorded',
      );
    });
  });

  group('fill-in only', () {
    test('a blank label, number and basis are all fillable', () async {
      final collection = await h.collection();
      final alpha = await h.source(collection: collection, host: kHostA);
      final (entry, _) = await h.repos.entries.createInCollection(
        collectionId: collection.id,
        placement: Placement.unplaced,
      );
      final (blank, _) = await h.repos.entries.addLocation(
        entryId: entry!.id,
        url: partUrl(kHostA, 12),
        urlKey: RecognitionKeys.of(partUrl(kHostA, 12)).urlKey,
        sourceId: alpha.id,
      );

      expect(
        sourceFillIn(
          existing: blank!,
          observed: ObservedEntryListing.read(
            url: partUrl(kHostA, 12),
            label: 'Part 12',
          ),
        ),
        {
          SourceFillInField.sourceLabel,
          SourceFillInField.sourceNumber,
          SourceFillInField.discoveryBasis,
        },
      );
    });

    test('a stored number is never overwritten by a second reading', () async {
      final collection = await h.collection();
      final alpha = await h.source(collection: collection, host: kHostA);
      final (_, stored) = await h.placedEntry(
        collection: collection,
        source: alpha,
        host: kHostA,
        number: 5,
      );

      final fields = sourceFillIn(
        existing: stored,
        observed: ObservedEntryListing.read(
          url: partUrl(kHostA, 5),
          label: 'Part 9',
        ),
      );

      expect(
        fields,
        isNot(contains(SourceFillInField.sourceNumber)),
        reason: 'a stored number is this Source\'s checkpoint',
      );
      expect(fields, contains(SourceFillInField.sourceLabel));
    });

    test(
      'an empty label never replaces one the source printed before',
      () async {
        final collection = await h.collection();
        final alpha = await h.source(collection: collection, host: kHostA);
        final (_, stored) = await h.placedEntry(
          collection: collection,
          source: alpha,
          host: kHostA,
          number: 5,
        );

        expect(
          sourceFillIn(
            existing: stored,
            observed: const ObservedEntryListing(
              url: 'https://$kHostA$kWorkPath/part-5',
              urlKey: 'https://$kHostA$kWorkPath/part-5',
              label: '   ',
              printedNumber: null,
              urlNumber: 5,
            ),
          ),
          isNot(contains(SourceFillInField.sourceLabel)),
        );
      },
    );

    test(
      'a check reports a disagreement and keeps the stored number',
      () async {
        final collection = await h.collection();
        final alpha = await h.source(collection: collection, host: kHostA);
        final (_, stored) = await h.placedEntry(
          collection: collection,
          source: alpha,
          host: kHostA,
          number: 5,
        );

        // The site now prints "Part 9" at the address it used to print "Part 5"
        // at, alongside addresses whose two readings still agree.
        final observations = ScriptedObservations([
          SourceObservation.read(
            url: 'https://$kHostA$kWorkPath',
            listings: [
              ObservedEntryListing.read(
                url: partUrl(kHostA, 5),
                label: 'Part 9',
              ),
              ObservedEntryListing.read(
                url: partUrl(kHostA, 6),
                label: 'Part 6',
              ),
            ],
            listRecognised: true,
            orderingConfident: true,
            newestFirst: false,
          ),
        ]);
        final outcome = await checkerOver(observations).checkPreferredSource(
          collection.id,
          limits: kGenerousLimits,
          shouldContinue: observations.shouldContinue,
        );

        expect(outcome.fillIns, hasLength(1));
        expect(outcome.fillIns.single.locationId, stored.id);
        expect(outcome.fillIns.single.disagreedNumber, 9);
        expect(
          outcome.fillIns.single.fields,
          isNot(contains(SourceFillInField.sourceNumber)),
        );
        final after = (await h.repos.entries.locationById(stored.id))!;
        expect(
          after.sourceNumber,
          5,
          reason:
              'the disagreement is reported and never resolved: the stored '
              'number is this Source\'s checkpoint',
        );
        expect(
          after.sourceLabel,
          'Part 9',
          reason:
              'the label is a transcription of what the source prints, so the '
              'field the judgement did name is written',
        );
      },
    );

    test(
      'the blanks the judgement names are written, and only those',
      () async {
        final collection = await h.collection();
        final alpha = await h.source(collection: collection, host: kHostA);
        // A placed Entry whose Location carries nothing this Source said.
        final (entry, _) = await h.repos.entries.createInCollection(
          collectionId: collection.id,
          ordinal: 12,
        );
        final url = partUrl(kHostA, 12);
        final (blank, _) = await h.repos.entries.addLocation(
          entryId: entry!.id,
          url: url,
          urlKey: RecognitionKeys.of(url).urlKey,
          sourceId: alpha.id,
        );

        final before = await h.repos.outboxCount();
        final observations = ScriptedObservations([
          listingPage(host: kHostA, parts: [12]),
        ]);
        final outcome = await checkerOver(observations).checkPreferredSource(
          collection.id,
          limits: kGenerousLimits,
          shouldContinue: observations.shouldContinue,
        );

        expect(outcome.fillIns, hasLength(1));
        expect(outcome.fillIns.single.fields, {
          SourceFillInField.sourceLabel,
          SourceFillInField.sourceNumber,
          SourceFillInField.discoveryBasis,
        });
        final filled = (await h.repos.entries.locationById(blank!.id))!;
        expect(
          (filled.sourceLabel, filled.sourceNumber, filled.discoveryBasis),
          ('Part 12', 12, kSourceListingBasis),
        );
        expect(
          (filled.url, filled.urlKey, filled.discoveredAt, filled.lifecycle),
          (blank.url, blank.urlKey, blank.discoveredAt, blank.lifecycle),
          reason:
              'a re-sighting is not a discovery, and identity is not '
              'evidence',
        );
        expect(
          await h.repos.outboxCount(),
          before + 1,
          reason: 'one intent for the one Location this reading changed',
        );
      },
    );

    test('a Location of another Source is never filled in from this '
        'reading', () async {
      final collection = await h.collection();
      final alpha = await h.source(collection: collection, host: kHostA);
      final beta = await h.source(
        collection: collection,
        host: kHostB,
        language: 'tr',
      );
      await h.repos.collections.setPreferredSource(collection.id, alpha.id);
      final (entry, _) = await h.repos.entries.createInCollection(
        collectionId: collection.id,
        ordinal: 12,
      );
      final betaUrl = partUrl(kHostB, 12);
      final (betaBlank, _) = await h.repos.entries.addLocation(
        entryId: entry!.id,
        url: betaUrl,
        urlKey: RecognitionKeys.of(betaUrl).urlKey,
        sourceId: beta.id,
      );

      final observations = ScriptedObservations([
        listingPage(host: kHostA, parts: [12]),
      ]);
      final outcome = await checkerOver(observations).checkPreferredSource(
        collection.id,
        limits: kGenerousLimits,
        shouldContinue: observations.shouldContinue,
      );

      expect(outcome.fillIns, isEmpty);
      expect(
        await h.repos.entries.locationById(betaBlank!.id),
        betaBlank,
        reason: 'alpha\'s reading says nothing about beta\'s row',
      );
    });

    test(
      'an Entry already held gains this Source\'s words as a new Location',
      () async {
        final collection = await h.collection();
        final alpha = await h.source(collection: collection, host: kHostA);
        final beta = await h.source(
          collection: collection,
          host: kHostB,
          language: 'tr',
        );
        final (entry, alphaLocation) = await h.placedEntry(
          collection: collection,
          source: alpha,
          host: kHostA,
          number: 5,
        );

        final observations = ScriptedObservations([
          listingPage(host: kHostB, parts: [5]),
        ]);
        final outcome = await checkerOver(observations).checkSource(
          beta.id,
          limits: kGenerousLimits,
          shouldContinue: observations.shouldContinue,
        );

        expect(outcome.discovery.mergedEntryIds, [entry.id]);
        expect(outcome.discovery.addedLocationIds, hasLength(1));
        final locations = await h.repos.entries.locationsOf(entry.id);
        expect(locations, hasLength(2));
        expect(
          await h.repos.entries.locationById(alphaLocation.id),
          alphaLocation,
          reason: 'the blank filled is this Source\'s, and only this Source\'s',
        );
      },
    );
  });

  group('placing an Entry its Source has now numbered (V2-D16)', () {
    /// An unplaced Entry with one Location on [source], carrying whatever the
    /// Source had said about it when it was found.
    Future<(EntryRow, LocationRow)> unplacedAt({
      required CollectionRow collection,
      required SourceRow source,
      required String url,
      double? sourceNumber,
    }) async {
      final (entry, entryViolation) = await h.repos.entries.createInCollection(
        collectionId: collection.id,
        placement: Placement.unplaced,
        title: 'Found, unplaced',
      );
      expect(entryViolation, isNull);
      final (location, locationViolation) = await h.repos.entries.addLocation(
        entryId: entry!.id,
        url: url,
        urlKey: RecognitionKeys.of(url).urlKey,
        sourceId: source.id,
        sourceNumber: sourceNumber,
      );
      expect(locationViolation, isNull);
      return (entry, location!);
    }

    test('an explicit number nothing contradicts places it — as the app, '
        'never as the user', () async {
      final collection = await h.collection();
      final alpha = await h.source(collection: collection, host: kHostA);
      final (entry, _) = await unplacedAt(
        collection: collection,
        source: alpha,
        url: partUrl(kHostA, 5),
      );

      final before = await h.repos.outboxCount();
      final observations = ScriptedObservations([
        listingPage(host: kHostA, parts: [5]),
      ]);
      final outcome = await checkerOver(observations).checkPreferredSource(
        collection.id,
        limits: kGenerousLimits,
        shouldContinue: observations.shouldContinue,
      );

      expect(outcome.placedEntryIds, [entry.id]);
      final placed = (await h.repos.entries.byId(entry.id))!;
      expect(placed.ordinal, 5);
      expect(
        placed.placement,
        Placement.placed.name,
        reason: 'userPlaced is the user\'s own answer and this is not it',
      );
      expect(await h.repos.entries.unplacedOf(collection.id), isEmpty);
      expect(
        await h.repos.outboxCount(),
        before + 2,
        reason: 'the blanks this reading filled, and the placement',
      );
    });

    test('a position already taken keeps the Entry unplaced', () async {
      final collection = await h.collection();
      final alpha = await h.source(collection: collection, host: kHostA);
      // Somebody is already at 5 — the user, or an earlier reading.
      final (occupant, _) = await h.repos.entries.createInCollection(
        collectionId: collection.id,
        ordinal: 5,
        title: 'Already at five',
      );
      final (entry, _) = await unplacedAt(
        collection: collection,
        source: alpha,
        url: postUrl(kHostA, 'a-late-arrival'),
      );

      final observations = ScriptedObservations([
        SourceObservation.read(
          url: 'https://$kHostA$kWorkPath',
          listings: [
            ObservedEntryListing.read(
              url: postUrl(kHostA, 'a-late-arrival'),
              label: 'Part 5',
            ),
          ],
          listRecognised: true,
          orderingConfident: true,
          newestFirst: false,
        ),
      ]);
      final outcome = await checkerOver(observations).checkPreferredSource(
        collection.id,
        limits: kGenerousLimits,
        shouldContinue: observations.shouldContinue,
      );

      expect(outcome.placedEntryIds, isEmpty);
      expect(
        (await h.repos.entries.byId(entry.id))!.placement,
        Placement.unplaced.name,
        reason: 'a second opinion does not move an Entry already placed',
      );
      expect((await h.repos.entries.byId(occupant!.id))!.ordinal, 5);
    });

    test('one Entry its addresses number two ways stays unplaced', () async {
      final collection = await h.collection();
      final alpha = await h.source(collection: collection, host: kHostA);
      final (entry, _) = await unplacedAt(
        collection: collection,
        source: alpha,
        url: partUrl(kHostA, 5),
      );
      final second = partUrl(kHostA, 6);
      await h.repos.entries.addLocation(
        entryId: entry.id,
        url: second,
        urlKey: RecognitionKeys.of(second).urlKey,
        sourceId: alpha.id,
      );

      final observations = ScriptedObservations([
        listingPage(host: kHostA, parts: [5, 6]),
      ]);
      final outcome = await checkerOver(observations).checkPreferredSource(
        collection.id,
        limits: kGenerousLimits,
        shouldContinue: observations.shouldContinue,
      );

      expect(outcome.placedEntryIds, isEmpty);
      expect(
        (await h.repos.entries.byId(entry.id))!.placement,
        Placement.unplaced.name,
        reason: 'two answers is not an answer',
      );
    });

    test(
      'a number that contradicts the stored one keeps it unplaced',
      () async {
        final collection = await h.collection();
        final alpha = await h.source(collection: collection, host: kHostA);
        final (entry, stored) = await unplacedAt(
          collection: collection,
          source: alpha,
          url: partUrl(kHostA, 5),
          sourceNumber: 4,
        );

        final observations = ScriptedObservations([
          listingPage(host: kHostA, parts: [5]),
        ]);
        final outcome = await checkerOver(observations).checkPreferredSource(
          collection.id,
          limits: kGenerousLimits,
          shouldContinue: observations.shouldContinue,
        );

        expect(outcome.fillIns.single.disagreedNumber, 5);
        expect(outcome.placedEntryIds, isEmpty);
        expect(
          (await h.repos.entries.byId(entry.id))!.placement,
          Placement.unplaced.name,
          reason: 'a disagreement is reported, never resolved',
        );
        expect(
          (await h.repos.entries.locationById(stored.id))!.sourceNumber,
          4,
          reason: 'and the stored number is the one that stands',
        );
      },
    );

    test('a Collection ordered any other way never places', () async {
      final collection = await h.collection(
        basis: OrderingBasis.publicationDate,
      );
      final alpha = await h.source(collection: collection, host: kHostA);
      final (entry, _) = await unplacedAt(
        collection: collection,
        source: alpha,
        url: partUrl(kHostA, 5),
      );

      final observations = ScriptedObservations([
        listingPage(host: kHostA, parts: [5]),
      ]);
      final outcome = await checkerOver(observations).checkPreferredSource(
        collection.id,
        limits: kGenerousLimits,
        shouldContinue: observations.shouldContinue,
      );

      expect(outcome.placedEntryIds, isEmpty);
      expect(
        (await h.repos.entries.byId(entry.id))!.placement,
        Placement.unplaced.name,
        reason: 'only an explicit numeric index makes a number a position',
      );
    });

    test('an address with no printed number never places', () async {
      final collection = await h.collection();
      final alpha = await h.source(collection: collection, host: kHostA);
      final (entry, _) = await unplacedAt(
        collection: collection,
        source: alpha,
        url: partUrl(kHostA, 5),
      );

      // The address spells a number; the source prints none. The address's
      // digits are never adopted.
      final observations = ScriptedObservations([
        SourceObservation.read(
          url: 'https://$kHostA$kWorkPath',
          listings: [
            ObservedEntryListing.read(
              url: partUrl(kHostA, 5),
              label: 'A walk before rain',
            ),
          ],
          listRecognised: true,
          orderingConfident: true,
          newestFirst: false,
        ),
      ]);
      final outcome = await checkerOver(observations).checkPreferredSource(
        collection.id,
        limits: kGenerousLimits,
        shouldContinue: observations.shouldContinue,
      );

      expect(outcome.placedEntryIds, isEmpty);
      expect(
        (await h.repos.entries.byId(entry.id))!.placement,
        Placement.unplaced.name,
      );
    });

    test('an Entry the user placed is never re-placed', () async {
      final collection = await h.collection();
      final alpha = await h.source(collection: collection, host: kHostA);
      final (entry, _) = await unplacedAt(
        collection: collection,
        source: alpha,
        url: partUrl(kHostA, 5),
      );
      final (userPlaced, violation) = await h.repos.entries.placeEntry(
        entry.id,
        7,
      );
      expect(violation, isNull);
      expect(userPlaced!.placement, Placement.userPlaced.name);

      final observations = ScriptedObservations([
        listingPage(host: kHostA, parts: [5]),
      ]);
      final outcome = await checkerOver(observations).checkPreferredSource(
        collection.id,
        limits: kGenerousLimits,
        shouldContinue: observations.shouldContinue,
      );

      expect(outcome.placedEntryIds, isEmpty);
      final after = (await h.repos.entries.byId(entry.id))!;
      expect((after.ordinal, after.placement), (7, Placement.userPlaced.name));
    });
  });

  group('checking another Source is a separate act', () {
    test(
      'it reads only the Source named and leaves the preferred one alone',
      () async {
        final collection = await h.collection();
        final alpha = await h.source(collection: collection, host: kHostA);
        final beta = await h.source(
          collection: collection,
          host: kHostB,
          language: 'tr',
        );
        await h.repos.collections.setPreferredSource(collection.id, alpha.id);
        await h.discovery.apply(
          h.window(source: alpha, host: kHostA, parts: [5, 6, 7]),
        );
        final alphaLocations = [
          for (final n in [5, 6, 7]) await locationAt(partUrl(kHostA, n)),
        ];

        final observations = ScriptedObservations([
          listingPage(host: kHostB, parts: [5, 6, 7]),
        ]);
        final outcome = await checkerOver(observations).checkSource(
          beta.id,
          limits: kGenerousLimits,
          shouldContinue: observations.shouldContinue,
        );

        expect(observations.askedSources, [beta.id]);
        expect(outcome.sourceId, beta.id);
        expect(
          outcome.checkpoint,
          isNull,
          reason: 'beta has shown nothing; alpha\'s checkpoint is not beta\'s',
        );
        expect(outcome.discovery.mergedEntryIds, hasLength(3));
        expect(outcome.discovery.createdEntryIds, isEmpty);

        for (final location in alphaLocations) {
          expect(
            await h.repos.entries.locationById(location.id),
            location,
            reason: 'reading beta wrote nothing of alpha\'s',
          );
        }

        // And alpha's own checkpoint is exactly where it was.
        final second = ScriptedObservations([
          listingPage(host: kHostA, parts: [5, 6, 7]),
        ]);
        final alphaOutcome = await checkerOver(second).checkPreferredSource(
          collection.id,
          limits: kGenerousLimits,
          shouldContinue: second.shouldContinue,
        );
        expect(alphaOutcome.sourceId, alpha.id);
        expect(alphaOutcome.checkpoint, 7);
        expect(alphaOutcome.state, SourceCheckState.upToDate);
      },
    );

    test('a Source that numbers half a step low stays two Entries', () async {
      final collection = await h.collection();
      final alpha = await h.source(collection: collection, host: kHostA);
      final shifted = await h.source(
        collection: collection,
        host: kHostShifted,
      );
      await h.repos.collections.setPreferredSource(collection.id, alpha.id);
      await h.discovery.apply(
        h.window(source: alpha, host: kHostA, parts: [5, 6, 7]),
      );

      final observations = ScriptedObservations([
        listingPage(host: kHostShifted, parts: [5, 6, 7], printedOffset: -0.5),
      ]);
      final outcome = await checkerOver(observations).checkSource(
        shifted.id,
        limits: kGenerousLimits,
        shouldContinue: observations.shouldContinue,
      );

      expect(outcome.discovery.mergedEntryIds, isEmpty);
      expect(outcome.newEntryIds, hasLength(3));
      expect(
        (await h.repos.entries.entriesOf(collection.id)).map((e) => e.ordinal),
        [4.5, 5, 5.5, 6, 6.5, 7],
      );
    });

    test('a dead Source is not read', () async {
      final collection = await h.collection();
      final alpha = await h.source(collection: collection, host: kHostA);
      await h.repos.collections.setSourceLifecycle(
        alpha.id,
        SourceLifecycle.dead,
      );

      final observations = ScriptedObservations([
        listingPage(host: kHostA, parts: [5]),
      ]);
      final outcome = await checkerOver(observations).checkSource(
        alpha.id,
        limits: kGenerousLimits,
        shouldContinue: observations.shouldContinue,
      );

      expect(outcome.stopReason, SourceCheckStop.sourceNotReadable);
      expect(observations.askedSources, isEmpty);
    });

    test('a Source that moved is read where it moved to', () async {
      final collection = await h.collection();
      final oldSite = await h.source(collection: collection, host: kHostA);
      final newSite = await h.source(collection: collection, host: kHostB);
      await h.repos.collections.setSourceLifecycle(
        oldSite.id,
        SourceLifecycle.resolvedInto,
        resolvedIntoSourceId: newSite.id,
      );

      final observations = ScriptedObservations([
        listingPage(host: kHostB, parts: [5]),
      ]);
      final outcome = await checkerOver(observations).checkSource(
        oldSite.id,
        limits: kGenerousLimits,
        shouldContinue: observations.shouldContinue,
      );

      expect(observations.askedSources, [newSite.id]);
      expect(outcome.sourceId, newSite.id);
    });
  });

  group('what a check costs', () {
    /// One check over a Collection already holding [count] numbered parts,
    /// whose Source lists exactly those — nothing new, nothing retracted.
    ///
    /// The counted harness replaces the shared one so only ever one database
    /// is open, and tearDown closes whichever is last.
    Future<int> selectsForCheckOver(int count) async {
      await h.close();
      final counter = CountingInterceptor();
      h = RecognitionHarness(
        executor: NativeDatabase.memory().interceptWith(counter),
      );
      final collection = await h.collection();
      final alpha = await h.source(collection: collection, host: kHostA);
      final parts = [for (var n = 1; n <= count; n++) n];
      await h.discovery.apply(
        h.window(source: alpha, host: kHostA, parts: parts),
      );

      final observations = ScriptedObservations([
        listingPage(host: kHostA, parts: parts),
      ]);
      counter.selects = 0;
      final outcome = await checkerOver(observations).checkPreferredSource(
        collection.id,
        limits: kGenerousLimits,
        shouldContinue: observations.shouldContinue,
      );
      expect(outcome.state, SourceCheckState.upToDate);
      expect(outcome.fillIns, isEmpty);
      return counter.selects;
    }

    test('the checkpoint and the retraction pass are one indexed read each, '
        'however much the Collection holds', () async {
      final three = await selectsForCheckOver(3);
      final six = await selectsForCheckOver(6);

      // Measured: 15 and 21. Before the Source-scoped read they were 21 and
      // 33 — the checkpoint and the retraction pass each walked the
      // Collection's Entries and asked for one Entry's Locations at a time.
      expect(
        six - three,
        6,
        reason:
            'three more addresses cost three joined lookups here and three '
            'in discovery, and nothing else grows with the library',
      );
    });
  });
}
