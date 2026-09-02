/// A provider that rewrites part of its own URL structure.
///
/// The library's two identity keys are exact by construction, so a changed
/// slug makes every address of one work stop matching at once. These tests pin
/// what the app does about it: it accepts the site's *own* statement that a
/// page moved, refuses everything weaker by name, and never loses an Entry, a
/// reading position or a downloaded copy to a URL change.
///
/// Hosts are the reserved `.example` names the rest of the recognition suites
/// use. No real provider is named here or anywhere else.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:web_reader/browser/page_data.dart';
import 'package:web_reader/data/data_violations.dart';
import 'package:web_reader/data/schema.dart';
import 'package:web_reader/domain/location.dart';
import 'package:web_reader/domain/source.dart';
import 'package:web_reader/features/source_observation_browser.dart';
import 'package:web_reader/recognition/entry_identity.dart';
import 'package:web_reader/core/url_utils.dart';
import 'package:web_reader/recognition/check.dart';
import 'package:web_reader/recognition/walk.dart';
import 'package:web_reader/recognition/recognise.dart';
import 'package:web_reader/recognition/relocation.dart';

import '../helpers/fake_browser.dart';
import 'support/forward_pages_fake.dart';
import 'support/recognition_harness.dart';

/// The same work, after the provider rewrote the unstable half of its slug.
/// Long enough and wordless enough that the frozen fingerprint keeps it whole,
/// which is exactly why the change breaks matching in the first place.
const String kMovedWorkPath = '/works/quiet-harbour-a728349g';

String movedPartUrl(String host, Object part) =>
    'https://$host$kMovedWorkPath/part-$part';

void main() {
  group('the keys are exact, and that is the premise', () {
    test('a rewritten slug changes both keys, so nothing matches by '
        'normalisation alone', () {
      final before = RecognitionKeys.of(partUrl(kHostA, 101));
      final after = RecognitionKeys.of(movedPartUrl(kHostA, 101));

      expect(after.urlKey, isNot(before.urlKey));
      expect(after.pathKey, isNot(before.pathKey));
      expect(before.pathKey, kWorkPath);
      expect(after.pathKey, kMovedWorkPath);
      expect(after.host, before.host);
    });
  });

  // ─── the rule, with no database anywhere near it ──────────────────────────

  group('judgeRedirectAlias', () {
    RedirectAliasCheck judge({
      String requested = '',
      String landed = '',
      bool requestedIsHeld = true,
      bool landedIsHeld = false,
      String? heldSourceId = 'source-1',
      double? heldSourceNumber = 101,
      String landedTitle = 'Part 101',
    }) {
      final from = requested.isEmpty ? partUrl(kHostA, 101) : requested;
      final to = landed.isEmpty ? movedPartUrl(kHostA, 101) : landed;
      return judgeRedirectAlias(
        requested: RecognitionKeys.of(from),
        landed: RecognitionKeys.of(to),
        requestedIsHeld: requestedIsHeld,
        landedIsHeld: landedIsHeld,
        heldSourceId: heldSourceId,
        heldSourceNumber: heldSourceNumber,
        landedReading: EntryIdentityReading.read(url: to, label: landedTitle),
      );
    }

    test('accepts a same-host redirect whose landing still prints the stored '
        'number', () {
      final check = judge();
      expect(check.isAccepted, isTrue);
      expect(check.corroboratedNumber, 101);
    });

    test('accepts when only the address corroborates, the label having lost '
        'its number', () {
      expect(judge(landedTitle: 'Quiet Harbour').isAccepted, isTrue);
    });

    test('a navigation that landed where it aimed is not a redirect', () {
      expect(
        judge(landed: partUrl(kHostA, 101)).refusal,
        RedirectAliasRefusal.notRedirected,
      );
    });

    test('refuses a landing on another host — a domain move is confirmed, '
        'never inferred', () {
      expect(
        judge(landed: movedPartUrl(kHostB, 101)).refusal,
        RedirectAliasRefusal.differentHost,
      );
    });

    test('refuses a landing on a sign-in wall: the site declined, it did not '
        'move anything', () {
      expect(
        judge(landed: 'https://$kHostA/login?next=$kWorkPath').refusal,
        RedirectAliasRefusal.deniedDestination,
      );
    });

    test('refuses when the landing prints a different number — the bounce to '
        'the newest page', () {
      expect(
        judge(
          landed: movedPartUrl(kHostA, 999),
          landedTitle: 'Part 999',
        ).refusal,
        RedirectAliasRefusal.numberNotCorroborated,
      );
    });

    test('refuses when nothing corroborates: no stored number to check '
        'against', () {
      expect(
        judge(heldSourceNumber: null).refusal,
        RedirectAliasRefusal.noStoredNumber,
      );
    });

    test('refuses when the library never held the address that was asked '
        'for', () {
      expect(
        judge(requestedIsHeld: false).refusal,
        RedirectAliasRefusal.requestedNotHeld,
      );
    });

    test('refuses when the landed address is already held — recognition '
        'answers it directly', () {
      expect(
        judge(landedIsHeld: true).refusal,
        RedirectAliasRefusal.landedAlreadyHeld,
      );
    });

    test('refuses a standalone Location, whose predecessor could not be stood '
        'down (I15)', () {
      expect(
        judge(heldSourceId: null).refusal,
        RedirectAliasRefusal.standaloneLocation,
      );
    });

    test('refuses a landing that is not a renderable web page', () {
      expect(
        judge(landed: 'about:blank').refusal,
        RedirectAliasRefusal.landedNotAWebPage,
      );
    });
  });

  // ─── applied to the library ───────────────────────────────────────────────

  group('LocationRelocator', () {
    late RecognitionHarness h;
    late LocationRelocator relocator;
    late CollectionRow collection;
    late SourceRow source;
    late EntryRow entry;
    late LocationRow original;

    setUp(() async {
      h = RecognitionHarness();
      relocator = LocationRelocator(
        entries: h.repos.entries,
        index: h.repos.recognition,
      );
      collection = await h.collection();
      source = await h.source(collection: collection, host: kHostA);
      final seeded = await h.placedEntry(
        collection: collection,
        source: source,
        host: kHostA,
        number: 101,
      );
      entry = seeded.$1;
      original = seeded.$2;
    });

    tearDown(() => h.close());

    Future<RedirectAliasOutcome> move({String title = 'Part 101'}) =>
        relocator.aliasOnRedirect(
          requestedUrl: partUrl(kHostA, 101),
          landedUrl: movedPartUrl(kHostA, 101),
          pageTitle: title,
        );

    test(
      'the moved address becomes another Location of the SAME Entry',
      () async {
        final outcome = await move();

        expect(outcome.aliased, isTrue);
        expect(outcome.entryId, entry.id, reason: 'the Entry is not recreated');
        final moved = await h.repos.entries.locationById(outcome.locationId!);
        expect(moved!.entryId, entry.id);
        expect(moved.sourceId, source.id, reason: 'same Source, same site');
        expect(moved.discoveryBasis, kProviderRedirectBasis);
      },
    );

    test('the new row keeps the evidence the stored one carried, rather than '
        'adopting the landing page\'s readings', () async {
      final outcome = await move(title: 'Part 101 — a different heading');
      final moved = await h.repos.entries.locationById(outcome.locationId!);

      expect(moved!.sourceNumber, original.sourceNumber);
      expect(moved.sourceLabel, original.sourceLabel);
    });

    test('the superseded address is retracted, never deleted', () async {
      final outcome = await move();

      expect(outcome.retractedLocationId, original.id);
      final before = await h.repos.entries.locationById(original.id);
      expect(before, isNotNull, reason: 'history survives a move');
      expect(before!.lifecycle, LocationLifecycle.retracted.name);
    });

    test('recognition answers the new address, and still answers the old '
        'one', () async {
      await move();

      final now = await h.recogniser.recognise(movedPartUrl(kHostA, 101));
      expect(now, isA<RecognisedLocation>());
      expect((now as RecognisedLocation).entry.id, entry.id);

      // A retracted Location still resolves: retraction is evidence about a
      // listing, not a statement that the address never existed.
      final then = await h.recogniser.recognise(partUrl(kHostA, 101));
      expect(then, isA<RecognisedLocation>());
      expect((then as RecognisedLocation).entry.id, entry.id);
    });

    test('the Entry is now offered at the new address and no longer at the '
        'dead one', () async {
      await move();

      final active = [
        for (final l in await h.repos.entries.locationsOf(entry.id))
          if (l.lifecycle == LocationLifecycle.active.name) l.url,
      ];
      expect(active, [movedPartUrl(kHostA, 101)]);
    });

    test('reading progress, reading state and the downloaded copy all '
        'survive', () async {
      await h.repos.reading.recordSourceAccess(entry.id);
      final (measurement, violation) = await h.repos.measurements.put(
        entryId: entry.id,
        sourceId: source.id,
        fraction: 0.5,
      );
      expect(violation, isNull);
      expect(measurement, isNotNull);
      final copy = await h.repos.offline.recordCopy(
        entryId: entry.id,
        locationUrl: partUrl(kHostA, 101),
        artifactFormat: 'imageSequence',
        contentPath: 'packages/${entry.id}',
        byteSize: 4096,
      );

      await move();

      // The measurement is keyed (entry, source) and the move keeps both, so
      // the reading is not merely preserved — it still applies.
      final after = await h.repos.measurements.of(entry.id, source.id);
      expect(after?.fraction, 0.5);
      expect((await h.repos.reading.stateOf(entry.id)).lastReadAt, isNotNull);
      final held = await h.repos.offline.activeCopyOf(entry.id);
      expect(held?.id, copy.id);
      expect(held?.byteSize, 4096);
    });

    test('a refused redirect writes nothing at all', () async {
      final before = await h.repos.entries.locationsOf(entry.id);

      final outcome = await relocator.aliasOnRedirect(
        requestedUrl: partUrl(kHostA, 101),
        landedUrl: movedPartUrl(kHostA, 999),
        pageTitle: 'Part 999',
      );

      expect(outcome.aliased, isFalse);
      expect(outcome.refusal, RedirectAliasRefusal.numberNotCorroborated);
      final after = await h.repos.entries.locationsOf(entry.id);
      expect(after.length, before.length);
      expect(
        after.single.lifecycle,
        LocationLifecycle.active.name,
        reason: 'a refusal does not retract anything either',
      );
    });

    test('a navigation with no redirect at all is not even judged', () async {
      final outcome = await relocator.aliasOnRedirect(
        requestedUrl: '',
        landedUrl: partUrl(kHostA, 101),
      );
      expect(outcome.refusal, RedirectAliasRefusal.notRedirected);
    });
  });

  // ─── where a Source's listing turned out to be ────────────────────────────

  group('landedListingPath', () {
    String resolve(String landed) => landedListingPath(
      sourceHost: kHostA,
      sourcePathKey: kWorkPath,
      landedUrl: landed,
    );

    test('a same-host redirect names the path the listing now lives at', () {
      expect(resolve('https://$kHostA$kMovedWorkPath'), kMovedWorkPath);
    });

    test('a trailing slash is normalised the way a path key is', () {
      expect(resolve('https://$kHostA$kMovedWorkPath/'), kMovedWorkPath);
    });

    test('a landing on another host keeps the stored key', () {
      expect(resolve('https://$kHostB$kMovedWorkPath'), kWorkPath);
    });

    test('a landing on a sign-in wall keeps the stored key', () {
      expect(resolve('https://$kHostA/login'), kWorkPath);
    });

    test('a landing on the bare host keeps the stored key', () {
      expect(resolve('https://$kHostA/'), kWorkPath);
    });
  });

  // ─── the check reads the listing it was sent to ───────────────────────────

  group('a listing the site redirected', () {
    SourceRow sourceRow() => SourceRow(
      id: 's1',
      collectionId: 'c1',
      host: kHostA,
      pathKey: kWorkPath,
      language: '',
      lifecycle: 'active',
      firstSeenAt: DateTime(2026),
      lastSeenAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );

    PageProbe listing(String url, List<int> parts) => PageProbe(
      url: url,
      title: 'Quiet Harbour',
      readyState: 'complete',
      documentHeight: 2000,
      viewportHeight: 800,
      viewportWidth: 400,
      atBottom: false,
      links: [
        for (final n in parts)
          PageLink(href: movedPartUrl(kHostA, n), text: 'Part $n'),
      ],
    );

    test('is read at the address it landed on, instead of being reported as '
        'not this Source\'s listing', () async {
      final browser = FakeBrowser()..setUrl('about:blank');
      final landed = 'https://$kHostA$kMovedWorkPath';
      browser.redirects['https://$kHostA$kWorkPath'] = landed;
      browser.addPage(landed, listing(landed, [103, 102, 101]));

      final observation = await BrowserSourceObservationSource(
        browser,
      ).observe(source: sourceRow(), pageUrl: null, shouldContinue: () => true);

      expect(observation.isReadable, isTrue);
      expect(observation.listRecognised, isTrue);
      expect(observation.listings.length, 3);
      expect(observation.landedPathKey, kMovedWorkPath);
    });

    test('reports no relocation when the landing produced no listing at '
        'all', () async {
      final browser = FakeBrowser()..setUrl('about:blank');
      final landed = 'https://$kHostA$kMovedWorkPath';
      browser.redirects['https://$kHostA$kWorkPath'] = landed;
      browser.addPage(landed, listing(landed, const []));

      final observation = await BrowserSourceObservationSource(
        browser,
      ).observe(source: sourceRow(), pageUrl: null, shouldContinue: () => true);

      expect(observation.listRecognised, isFalse);
      expect(
        observation.landedPathKey,
        isNull,
        reason: 'a failed reading is not evidence of a move',
      );
    });

    test('a link that leaves the host is still not this Source\'s, whatever '
        'the path says', () async {
      final browser = FakeBrowser()..setUrl('about:blank');
      final landed = 'https://$kHostA$kMovedWorkPath';
      browser.redirects['https://$kHostA$kWorkPath'] = landed;
      browser.addPage(
        landed,
        PageProbe(
          url: landed,
          title: 'Quiet Harbour',
          readyState: 'complete',
          documentHeight: 2000,
          viewportHeight: 800,
          viewportWidth: 400,
          atBottom: false,
          links: [
            PageLink(href: movedPartUrl(kHostA, 101), text: 'Part 101'),
            PageLink(href: movedPartUrl(kHostB, 102), text: 'Part 102'),
          ],
        ),
      );

      final observation = await BrowserSourceObservationSource(
        browser,
      ).observe(source: sourceRow(), pageUrl: null, shouldContinue: () => true);

      expect(observation.listings.length, 1);
      expect(observation.listings.single.url, movedPartUrl(kHostA, 101));
    });

    test(
      'an ordinary listing that did not move reports no relocation',
      () async {
        final browser = FakeBrowser()..setUrl('about:blank');
        final landed = 'https://$kHostA$kWorkPath';
        browser.addPage(
          landed,
          PageProbe(
            url: landed,
            title: 'Quiet Harbour',
            readyState: 'complete',
            documentHeight: 2000,
            viewportHeight: 800,
            viewportWidth: 400,
            atBottom: false,
            links: [
              for (final n in [102, 101])
                PageLink(href: partUrl(kHostA, n), text: 'Part $n'),
            ],
          ),
        );

        final observation = await BrowserSourceObservationSource(browser)
            .observe(
              source: sourceRow(),
              pageUrl: null,
              shouldContinue: () => true,
            );

        expect(observation.listings.length, 2);
        expect(observation.landedPathKey, kWorkPath);
      },
    );
  });

  // ─── the Source moved, and the user said so ───────────────────────────────

  group('SourceRelocator', () {
    late RecognitionHarness h;
    late SourceRelocator relocator;
    late CollectionRow collection;
    late SourceRow source;

    setUp(() async {
      h = RecognitionHarness();
      relocator = SourceRelocator(
        collections: h.repos.collections,
        index: h.repos.recognition,
        entries: h.repos.entries,
      );
      collection = await h.collection();
      source = await h.source(collection: collection, host: kHostA);
    });

    tearDown(() => h.close());

    Future<SourceRelocationOutcome> move() => relocator.relocate(
      fromSourceId: source.id,
      host: kHostA,
      pathKey: kMovedWorkPath,
    );

    test(
      'points the old Source forward instead of moving or deleting it',
      () async {
        final outcome = await move();

        expect(outcome.relocated, isTrue);
        final before = await h.repos.collections.sourceById(source.id);
        expect(before!.lifecycle, SourceLifecycle.resolvedInto.name);
        expect(before.resolvedIntoSourceId, outcome.toSourceId);
        expect(
          before.pathKey,
          kWorkPath,
          reason: 'the row that moved keeps its own identity',
        );
      },
    );

    test('the destination is a Source of the same Collection', () async {
      final outcome = await move();
      final target = await h.repos.collections.sourceById(outcome.toSourceId!);

      expect(target!.collectionId, collection.id);
      expect(target.pathKey, kMovedWorkPath);
      expect(target.host, kHostA);
      expect(target.language, source.language, reason: 'carried across');
    });

    test(
      'a check of the moved Source resolves forward to where it went',
      () async {
        final outcome = await move();
        final terminal = await relocator.readableSourceOf(source.id);

        expect(terminal?.id, outcome.toSourceId);
        expect(terminal?.pathKey, kMovedWorkPath);
      },
    );

    test(
      'the Collection keeps its Entries, and both Sources hang off it',
      () async {
        await h.placedEntry(
          collection: collection,
          source: source,
          host: kHostA,
          number: 101,
        );

        await move();

        expect((await h.repos.entries.entriesOf(collection.id)).length, 1);
        expect((await h.repos.collections.sourcesOf(collection.id)).length, 2);
      },
    );

    test(
      'relocating onto its own identity is refused, never written',
      () async {
        final outcome = await relocator.relocate(
          fromSourceId: source.id,
          host: kHostA,
          pathKey: kWorkPath,
        );

        expect(outcome.relocated, isFalse);
        final row = await h.repos.collections.sourceById(source.id);
        expect(row!.lifecycle, SourceLifecycle.active.name);
      },
    );

    test('a destination already published under another Collection is refused '
        'in words, never taken', () async {
      final other = await h.collection(name: 'Another Work');
      final (taken, _) = await h.repos.collections.addSource(
        collectionId: other.id,
        host: kHostA,
        pathKey: kMovedWorkPath,
      );

      final outcome = await move();

      expect(outcome.relocated, isFalse);
      expect(outcome.violation, isNotNull);
      final untouched = await h.repos.collections.sourceById(taken!.id);
      expect(untouched!.collectionId, other.id);
      expect(
        (await h.repos.collections.sourceById(source.id))!.lifecycle,
        SourceLifecycle.active.name,
      );
    });

    test('an unknown Source is refused', () async {
      final outcome = await relocator.relocate(
        fromSourceId: 'nope',
        host: kHostA,
        pathKey: kMovedWorkPath,
      );
      expect(outcome.relocated, isFalse);
    });
  });

  _traversalAfterRediscovery();

  // ─── the duplicate this whole exercise exists to prevent ──────────────────

  group('a second Collection for a work the library already holds', () {
    late RecognitionHarness h;
    late CollectionRow collection;
    late SourceRow source;

    setUp(() async {
      h = RecognitionHarness();
      collection = await h.collection();
      source = await h.source(collection: collection, host: kHostA);
      await h.placedEntry(
        collection: collection,
        source: source,
        host: kHostA,
        number: 101,
      );
    });

    tearDown(() => h.close());

    test(
      'is what happens today when the slug changes and nothing relocates',
      () async {
        final outcome = await h.adoption.createCollection(
          name: 'Quiet Harbour',
          keys: RecognitionKeys.of(movedPartUrl(kHostA, 102)),
          pageTitle: 'Part 102',
          printedNumber: 102,
        );

        expect(
          outcome.collectionId,
          isNot(collection.id),
          reason:
              'the moved slug is an unknown Source, so nothing refuses it — '
              'this is the failure the relocation path exists to prevent',
        );
      },
    );

    test('cannot happen once the Source has been relocated: the identity is '
        'taken and the refusal says so', () async {
      await SourceRelocator(
        collections: h.repos.collections,
        index: h.repos.recognition,
        entries: h.repos.entries,
      ).relocate(
        fromSourceId: source.id,
        host: kHostA,
        pathKey: kMovedWorkPath,
      );

      final outcome = await h.adoption.createCollection(
        name: 'Quiet Harbour',
        keys: RecognitionKeys.of(movedPartUrl(kHostA, 102)),
        pageTitle: 'Part 102',
        printedNumber: 102,
      );

      expect(outcome.collectionId, isNull);
      expect(outcome.violation, sourceIdentityTaken);
    });

    test('the moved site joins the Collection it already belongs to, merging '
        'by ordinal rather than making a second Entry', () async {
      final relocated =
          await SourceRelocator(
            collections: h.repos.collections,
            index: h.repos.recognition,
            entries: h.repos.entries,
          ).relocate(
            fromSourceId: source.id,
            host: kHostA,
            pathKey: kMovedWorkPath,
          );

      final outcome = await h.adoption.addToExistingCollection(
        collectionId: collection.id,
        keys: RecognitionKeys.of(movedPartUrl(kHostA, 101)),
        pageTitle: 'Part 101',
        printedNumber: 101,
      );

      expect(outcome.mergedIntoExistingEntry, isTrue);
      expect(outcome.sourceId, relocated.toSourceId);
      expect(
        (await h.repos.entries.entriesOf(collection.id)).length,
        1,
        reason: 'one work, one Entry at position 101',
      );
    });
  });
}

// ─── the regression: discovery and traversal disagreeing about the path ─────

/// A provider that moved its listing *and* its entry addresses, reproduced end
/// to end over the real check, the real observation source and the real walk.
///
/// The bug this pins: reading a listing at a path the Source does not claim
/// wrote Locations contradicting their own Source, retracted the Locations the
/// Source really held, and left *Entries from here* refusing to traverse the
/// very rows the check had just created.
void _traversalAfterRediscovery() {
  group('a provider that moved its slug', () {
    late RecognitionHarness h;
    late CollectionRow collection;
    late SourceRow source;
    late LocationRow originalLocation;
    late FakeBrowser browser;
    late SourceCheck check;

    PageProbe listingAt(String path, List<int> parts) {
      final url = 'https://$kHostA$path';
      return PageProbe(
        url: url,
        title: 'Quiet Harbour',
        readyState: 'complete',
        documentHeight: 2000,
        viewportHeight: 800,
        viewportWidth: 400,
        atBottom: false,
        links: [
          for (final n in parts)
            PageLink(href: movedPartUrl(kHostA, n), text: 'Part $n'),
        ],
      );
    }

    setUp(() async {
      h = RecognitionHarness();
      collection = await h.collection();
      source = await h.source(collection: collection, host: kHostA);
      final seeded = await h.placedEntry(
        collection: collection,
        source: source,
        host: kHostA,
        number: 101,
      );
      originalLocation = seeded.$2;

      browser = FakeBrowser()..setUrl('about:blank');
      browser.redirects['https://$kHostA$kWorkPath'] =
          'https://$kHostA$kMovedWorkPath';
      browser.addPage(
        'https://$kHostA$kMovedWorkPath',
        listingAt(kMovedWorkPath, [103, 102, 101]),
      );

      check = SourceCheck(
        collections: h.repos.collections,
        entries: h.repos.entries,
        index: h.repos.recognition,
        discovery: h.discovery,
        observations: BrowserSourceObservationSource(browser),
      );
    });

    tearDown(() => h.close());

    Future<SourceCheckOutcome> runCheck() => check.checkSource(
      source.id,
      limits: const SourceCheckLimits(maxPages: 1, maxNewEntries: 10),
      shouldContinue: () => true,
    );

    Future<SourceRelocationOutcome> confirmMove() => SourceRelocator(
      collections: h.repos.collections,
      index: h.repos.recognition,
      entries: h.repos.entries,
    ).relocate(fromSourceId: source.id, host: kHostA, pathKey: kMovedWorkPath);

    LibrarySourceWalk walkOver(Map<String, WalkedPage> pages) =>
        LibrarySourceWalk(
          entries: h.repos.entries,
          collections: h.repos.collections,
          index: h.repos.recognition,
          pages: FakeForwardPages(pages),
        );

    /// A straight chain at the moved path: each part links to the next.
    Map<String, WalkedPage> movedChain(List<int> parts, {String? from}) {
      final pages = <String, WalkedPage>{};
      for (var i = 0; i < parts.length; i++) {
        final n = parts[i];
        final landing = movedPartUrl(kHostA, n);
        // The first page may be reached at its pre-move address and land on
        // the moved one, which is what the provider's redirect does.
        final key = i == 0 && from != null ? from : landing;
        pages[normalizeUrl(key)] = WalkedPage(
          url: landing,
          printedNumber: n.toDouble(),
          title: 'Part $n',
          nextUrl: i + 1 < parts.length
              ? movedPartUrl(kHostA, parts[i + 1])
              : null,
        );
      }
      return pages;
    }

    // --- before the move is confirmed ------------------------------------

    test('the check stops on the move rather than reading a listing this '
        'Source does not claim', () async {
      final outcome = await runCheck();

      expect(outcome.state, SourceCheckState.stopped);
      expect(outcome.stopReason, SourceCheckStop.sourceListingMoved);
      expect(outcome.relocation, isNotNull);
      expect(outcome.relocation!.previousPathKey, kWorkPath);
      expect(outcome.relocation!.pathKey, kMovedWorkPath);
    });

    test('it writes no Location that contradicts its own Source', () async {
      await runCheck();

      for (final location in await h.repos.entries.locationsOfSource(
        source.id,
      )) {
        expect(
          RecognitionKeys.of(location.url).pathKey,
          source.pathKey,
          reason: 'every row of a Source sits on that Source\'s own path',
        );
      }
    });

    test('it does not retract the Locations the Source really holds', () async {
      await runCheck();

      final stored = await h.repos.entries.locationById(originalLocation.id);
      expect(
        stored!.lifecycle,
        LocationLifecycle.active.name,
        reason: 'a listing that never covered this address cannot retract it',
      );
    });

    // --- once the user has confirmed it ----------------------------------

    test('after the move is confirmed the check reads it as an ordinary '
        'Source', () async {
      await confirmMove();
      final outcome = await runCheck();

      expect(outcome.state, SourceCheckState.updatesAvailable);
      expect(outcome.relocation, isNull, reason: 'it has already moved');
      expect(outcome.discovery.addedLocationIds, isNotEmpty);
    });

    test(
      'the rediscovered rows sit on the Source that describes them',
      () async {
        final moved = await confirmMove();
        await runCheck();

        final rows = await h.repos.entries.locationsOfSource(moved.toSourceId!);
        expect(rows, isNotEmpty);
        for (final location in rows) {
          expect(RecognitionKeys.of(location.url).pathKey, kMovedWorkPath);
        }
      },
    );

    test('REGRESSION: Entries from here traverses the rediscovered '
        'Entries', () async {
      await confirmMove();
      await runCheck();

      final hit = await h.repos.recognition.lookupUrl(
        RecognitionKeys.of(movedPartUrl(kHostA, 102)).urlKey,
      );
      expect(hit, isNotNull);

      final captured = <String>[];
      // `wanted` counts the Entries *after* the one the walk starts on: the
      // starting page is what the count counts from.
      final outcome = await walkOver(movedChain([102, 103, 104])).forward(
        fromLocationId: hit!.location.id,
        wanted: 2,
        shouldContinue: () => true,
        // A CAPTURING walk — what *Entries from here* runs. The non-capturing
        // one reuses held rows before the guard and would hide this.
        onEntry: (entry) async {
          captured.add(entry.url);
          return true;
        },
      );

      expect(outcome.stop, WalkStop.countReached);
      expect(captured, [movedPartUrl(kHostA, 103), movedPartUrl(kHostA, 104)]);
    });

    test('REGRESSION: it also traverses from an Entry discovered before the '
        'move, whose Location names the Source left behind', () async {
      await confirmMove();

      final captured = <String>[];
      final outcome =
          await walkOver(
            movedChain([101, 102, 103], from: partUrl(kHostA, 101)),
          ).forward(
            // The pre-move Location: it still names the old Source row.
            fromLocationId: originalLocation.id,
            wanted: 2,
            shouldContinue: () => true,
            onEntry: (entry) async {
              captured.add(entry.url);
              return true;
            },
          );

      expect(outcome.stop, WalkStop.countReached);
      expect(captured, [movedPartUrl(kHostA, 102), movedPartUrl(kHostA, 103)]);
    });

    // --- the refusal boundary --------------------------------------------

    test('a confirmed move does not weaken the guard: a next address in '
        'another work is still refused', () async {
      await confirmMove();
      await runCheck();

      final hit = await h.repos.recognition.lookupUrl(
        RecognitionKeys.of(movedPartUrl(kHostA, 102)).urlKey,
      );
      const foreign = 'https://$kHostA/works/a-different-work/part-1';

      final outcome =
          await walkOver({
            normalizeUrl(movedPartUrl(kHostA, 102)): WalkedPage(
              url: movedPartUrl(kHostA, 102),
              printedNumber: 102,
              title: 'Part 102',
              nextUrl: foreign,
            ),
            normalizeUrl(foreign): WalkedPage(
              url: foreign,
              printedNumber: 1,
              title: 'Part 1',
            ),
          }).forward(
            fromLocationId: hit!.location.id,
            wanted: 3,
            shouldContinue: () => true,
            onEntry: (entry) async => true,
          );

      expect(outcome.stop, WalkStop.leftTheSource);
      expect(
        await h.repos.recognition.lookupUrl(normalizeUrl(foreign)),
        isNull,
        reason: 'nothing from another work entered the library',
      );
    });

    test(
      'a next address on another host is still refused after a move',
      () async {
        await confirmMove();
        await runCheck();

        final hit = await h.repos.recognition.lookupUrl(
          RecognitionKeys.of(movedPartUrl(kHostA, 102)).urlKey,
        );
        final foreign = movedPartUrl(kHostB, 103);

        final outcome =
            await walkOver({
              normalizeUrl(movedPartUrl(kHostA, 102)): WalkedPage(
                url: movedPartUrl(kHostA, 102),
                printedNumber: 102,
                title: 'Part 102',
                nextUrl: foreign,
              ),
            }).forward(
              fromLocationId: hit!.location.id,
              wanted: 3,
              shouldContinue: () => true,
              onEntry: (entry) async => true,
            );

        expect(outcome.stop, WalkStop.leftTheSource);
      },
    );
  });
}
