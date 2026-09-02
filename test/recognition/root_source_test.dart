/// A site given over entirely to one work, where the Entries are published
/// directly off the domain root.
///
/// The ordinary shape is a listing above its Entries — `/works/quiet-harbour`
/// with `/works/quiet-harbour/part-101` under it — and `path_key` is that
/// listing's path. A dedicated site has nothing above the Entry but the
/// domain, so the fingerprint strips the only segment there is and the Source
/// path *is* the root.
///
/// The root is also a prefix of every other address on the host, so the two
/// halves of this file are inseparable: what makes the root a key, and what
/// keeps `/about-us` out of it. Membership of a root Source is decided by the
/// same derivation that made the root a key — an address that carries an
/// entry number and nothing above it — never by the path prefix.
///
/// Hosts are the reserved `.example` names the rest of the recognition suites
/// use. No real site is named here, and nothing here is site-specific.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:web_reader/browser/page_data.dart';
import 'package:web_reader/core/url_utils.dart';
import 'package:web_reader/data/schema.dart';
import 'package:web_reader/features/source_observation_browser.dart';
import 'package:web_reader/library/collection_identity.dart';
import 'package:web_reader/recognition/page_kind.dart';
import 'package:web_reader/recognition/recognise.dart';
import 'package:web_reader/recognition/walk.dart';
import 'package:web_reader/save/page_hint.dart' show collectionFingerprint;

import '../helpers/fake_browser.dart';
import 'support/forward_pages_fake.dart';
import 'support/recognition_harness.dart';

/// The dedicated site: one work, published straight off the domain.
const String kFlatHost = 'dedicated.example';

/// An Entry of it, as such a site addresses one.
String flatEntryUrl(Object number) =>
    'https://$kFlatHost/quiet-harbour-part-$number/';

void main() {
  // ─── what keys the root, and what does not ────────────────────────────────

  group('the address that keys the domain root', () {
    String? keyOf(String url) => RecognitionKeys.of(url).pathKey;

    test('an Entry with nothing above it but the domain keys the root', () {
      final identity = resolveCollectionIdentity(
        entryUrl: flatEntryUrl(561),
        pageTitle: 'Quiet Harbour Part 561 - Quiet Harbour',
      );

      expect(identity.confidence, IdentityConfidence.high);
      expect(identity.collectionKey, '/');
      expect(identity.host, kFlatHost);
      expect(keyOf(flatEntryUrl(561)), '/');
    });

    test('consecutive Entries of it key the one Source', () {
      expect(keyOf(flatEntryUrl(561)), '/');
      expect(keyOf(flatEntryUrl(562)), '/');
      expect(keyOf(flatEntryUrl(562)), keyOf(flatEntryUrl(561)));
    });

    test('the key is derived from the address alone, with no page title', () {
      expect(keyOf(flatEntryUrl(561)), '/');
      expect(
        resolveCollectionIdentity(entryUrl: flatEntryUrl(561)).basis,
        isNot('page title'),
        reason: 'a title must never become Source identity (V2-D45)',
      );
    });

    // The other half of the rule, and the reason the two land together: the
    // root is a string prefix of every address on the host.
    test('an ordinary page of the same site keys itself, not the root', () {
      for (final path in const [
        '/about-us/',
        '/contact/',
        '/privacy-policy/',
        '/tag/action/',
        '/genre/fantasy/',
      ]) {
        expect(
          keyOf('https://$kFlatHost$path'),
          isNot('/'),
          reason: '$path is not an Entry of the work at the root',
        );
      }
    });

    test('an index whose slug looks like an entry word still keys no root, '
        'because it numbers nothing', () {
      // `/parts/` strips as an entry segment, so the fingerprint alone
      // would call it the root. The entry number is what refuses it.
      expect(collectionFingerprint('https://$kFlatHost/parts/'), '/');
      expect(keyOf('https://$kFlatHost/parts/'), isNot('/'));
    });

    // The other boundary of the rule. `/part/5` strips whole too, but only
    // because `part` is a short entry word — and `/part` is a better listing
    // than the root, so claiming the root would discard a path the address
    // carries. Unchanged: it keys nothing, as it always did.
    test('a two-segment address that strips whole still keys nothing', () {
      expect(collectionFingerprint('https://$kFlatHost/part/5'), '/');
      expect(keyOf('https://$kFlatHost/part/5'), isNull);
    });

    test('the site home page keys nothing at all', () {
      expect(
        keyOf('https://$kFlatHost/'),
        isNull,
        reason:
            'an address alone cannot tell a work\'s listing from a '
            'site\'s front page (V2-D44)',
      );
    });

    test('a page that keys the root also reads as an Entry', () {
      final shape = readPageShape(
        flatEntryUrl(561),
        pageTitle: 'Quiet Harbour Part 561',
      );
      expect(shape.identityIsStrong, isTrue);
      expect(shape.printedNumber, 561);
      expect(
        shape.couldBeListing,
        isFalse,
        reason: 'an Entry is not offered as its own listing',
      );
    });

    test('a page that keys no Source says so, so the sheet can stop before '
        'the user commits', () {
      expect(
        readPageShape(
          'https://$kFlatHost/',
          pageTitle: 'Quiet Harbour',
        ).identityIsStrong,
        isFalse,
      );
      expect(
        readPageShape(
          'https://$kFlatHost/parts/',
          pageTitle: 'Parts',
        ).identityIsStrong,
        isFalse,
      );
    });
  });

  // ─── the ordinary shape is untouched ──────────────────────────────────────

  group('a Source below a listing is unchanged', () {
    test('its Entries still key the listing path, not the root', () {
      expect(RecognitionKeys.of(partUrl(kHostA, 101)).pathKey, kWorkPath);
      expect(RecognitionKeys.of(partUrl(kHostA, 102)).pathKey, kWorkPath);
      // An unnumbered part keeps its own segment, because the fingerprint
      // has no entry word or digit to strip. Unchanged, and asserted here so
      // the root rule cannot quietly start claiming it.
      expect(
        RecognitionKeys.of(postUrl(kHostA, 'the-quiet-part')).pathKey,
        '$kWorkPath/the-quiet-part',
      );
    });

    test('two works on one host still stay apart', () {
      final a = RecognitionKeys.of('https://$kHostA/guide/one/part-1');
      final b = RecognitionKeys.of('https://$kHostA/guide/two/part-1');

      expect(a.pathKey, '/guide/one');
      expect(b.pathKey, isNot(a.pathKey));
    });

    test('a listing path is still its own key', () {
      expect(
        RecognitionKeys.of('https://$kHostA$kWorkPath').pathKey,
        kWorkPath,
      );
    });
  });

  // ─── adoption and the forward walk ────────────────────────────────────────

  group('a root Source in the library', () {
    late RecognitionHarness h;

    setUp(() => h = RecognitionHarness());
    tearDown(() => h.close());

    /// A Collection whose one Source is the root of [kFlatHost], holding the
    /// Entry at [from].
    Future<({CollectionRow collection, SourceRow source, LocationRow from})>
    flatLibrary({required double from}) async {
      final collection = await h.collection();
      final keys = RecognitionKeys.of(flatEntryUrl(from.round()));
      final (source, sourceViolation) = await h.repos.collections.addSource(
        collectionId: collection.id,
        host: keys.host,
        pathKey: keys.pathKey!,
        language: 'en',
      );
      if (sourceViolation != null) throw StateError('$sourceViolation');
      final (entry, entryViolation) = await h.repos.entries.createInCollection(
        collectionId: collection.id,
        ordinal: from,
        title: 'Part ${from.round()}',
      );
      if (entryViolation != null) throw StateError('$entryViolation');
      final (location, locationViolation) = await h.repos.entries.addLocation(
        entryId: entry!.id,
        url: flatEntryUrl(from.round()),
        urlKey: keys.urlKey,
        sourceId: source!.id,
        sourceLabel: 'Part ${from.round()}',
        sourceNumber: from,
      );
      if (locationViolation != null) throw StateError('$locationViolation');
      return (collection: collection, source: source, from: location!);
    }

    test('starting a Collection from a root Entry writes a Source at the '
        'root', () async {
      final outcome = await h.adoption.createCollection(
        name: 'Quiet Harbour',
        keys: RecognitionKeys.of(flatEntryUrl(561)),
        pageTitle: 'Quiet Harbour Part 561',
        printedNumber: 561,
      );

      expect(outcome.succeeded, isTrue, reason: '${outcome.violation}');
      final source = await h.repos.recognition.lookupSource(kFlatHost, '/');
      expect(source, isNotNull);
      expect(source!.id, outcome.sourceId);
    });

    test('the next Entry of the same site is recognised onto it', () async {
      await h.adoption.createCollection(
        name: 'Quiet Harbour',
        keys: RecognitionKeys.of(flatEntryUrl(561)),
        pageTitle: 'Quiet Harbour Part 561',
        printedNumber: 561,
      );

      final result = await h.recogniser.recognise(flatEntryUrl(562));

      expect(result, isA<RecognisedSource>());
      expect((result as RecognisedSource).source.pathKey, '/');
    });

    test('an unrelated page of the same site is not recognised onto '
        'it', () async {
      await h.adoption.createCollection(
        name: 'Quiet Harbour',
        keys: RecognitionKeys.of(flatEntryUrl(561)),
        pageTitle: 'Quiet Harbour Part 561',
        printedNumber: 561,
      );

      final result = await h.recogniser.recognise(
        'https://$kFlatHost/about-us/',
      );

      expect(
        result,
        isA<Unrecognised>(),
        reason: 'a root Source must not swallow its own host',
      );
    });

    test('the walk follows consecutive root Entries', () async {
      final it = await flatLibrary(from: 561);
      final pages = FakeForwardPages({
        for (var n = 561; n <= 564; n++)
          normalizeUrl(flatEntryUrl(n)): WalkedPage(
            url: flatEntryUrl(n),
            printedNumber: n.toDouble(),
            title: 'Part $n',
            nextUrl: n < 564 ? flatEntryUrl(n + 1) : null,
          ),
      });

      final outcome =
          await LibrarySourceWalk(
            entries: h.repos.entries,
            collections: h.repos.collections,
            index: h.repos.recognition,
            pages: pages,
          ).forward(
            fromLocationId: it.from.id,
            wanted: 3,
            shouldContinue: () => true,
          );

      expect(outcome.stop, WalkStop.countReached);
      expect(outcome.entries.map((e) => e.printedNumber), [562, 563, 564]);
    });

    test('the walk refuses to follow the same site off the work', () async {
      final it = await flatLibrary(from: 561);
      final pages = FakeForwardPages({
        normalizeUrl(flatEntryUrl(561)): WalkedPage(
          url: flatEntryUrl(561),
          printedNumber: 561,
          title: 'Part 561',
          nextUrl: 'https://$kFlatHost/about-us/',
        ),
        normalizeUrl('https://$kFlatHost/about-us/'): const WalkedPage(
          url: 'https://$kFlatHost/about-us/',
          printedNumber: null,
          title: 'About us',
        ),
      });

      final outcome =
          await LibrarySourceWalk(
            entries: h.repos.entries,
            collections: h.repos.collections,
            index: h.repos.recognition,
            pages: pages,
          ).forward(
            fromLocationId: it.from.id,
            wanted: 3,
            shouldContinue: () => true,
          );

      expect(outcome.stop, WalkStop.leftTheSource);
      expect(outcome.entries, isEmpty);
    });
  });

  // ─── the listing a root Source is read from ───────────────────────────────

  group('reading a root Source\'s listing', () {
    SourceRow rootSource() => SourceRow(
      id: 's1',
      collectionId: 'c1',
      host: kFlatHost,
      pathKey: '/',
      language: '',
      lifecycle: 'active',
      firstSeenAt: DateTime(2026),
      lastSeenAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );

    PageProbe pageWith(String url, List<String> hrefs) => PageProbe(
      url: url,
      title: 'Quiet Harbour',
      readyState: 'complete',
      documentHeight: 2000,
      viewportHeight: 800,
      viewportWidth: 400,
      atBottom: false,
      links: [for (final href in hrefs) PageLink(href: href, text: href)],
    );

    test('the work\'s own Entries are listed', () async {
      final landed = 'https://$kFlatHost/';
      final browser = FakeBrowser()..setUrl('about:blank');
      browser.addPage(
        landed,
        pageWith(landed, [flatEntryUrl(3), flatEntryUrl(2), flatEntryUrl(1)]),
      );

      final observation = await BrowserSourceObservationSource(browser).observe(
        source: rootSource(),
        pageUrl: null,
        shouldContinue: () => true,
      );

      expect(observation.listRecognised, isTrue);
      expect(observation.listings.map((l) => l.url), [
        flatEntryUrl(3),
        flatEntryUrl(2),
        flatEntryUrl(1),
      ]);
      expect(observation.landedPathKey, '/');
    });

    // The regression this file exists for: the root is a prefix of every path
    // on the host, so a prefix test enrols the whole site.
    test('the rest of the site is not', () async {
      final landed = 'https://$kFlatHost/';
      final browser = FakeBrowser()..setUrl('about:blank');
      browser.addPage(
        landed,
        pageWith(landed, [
          flatEntryUrl(1),
          'https://$kFlatHost/about-us/',
          'https://$kFlatHost/contact/',
          'https://$kFlatHost/privacy-policy/',
          'https://$kFlatHost/tag/action/',
          'https://$kFlatHost/parts/',
        ]),
      );

      final observation = await BrowserSourceObservationSource(browser).observe(
        source: rootSource(),
        pageUrl: null,
        shouldContinue: () => true,
      );

      expect(observation.listings.map((l) => l.url), [flatEntryUrl(1)]);
    });

    test('a link that leaves the host is still refused', () async {
      final landed = 'https://$kFlatHost/';
      final browser = FakeBrowser()..setUrl('about:blank');
      browser.addPage(
        landed,
        pageWith(landed, [
          flatEntryUrl(1),
          'https://$kHostB/quiet-harbour-part-1/',
        ]),
      );

      final observation = await BrowserSourceObservationSource(browser).observe(
        source: rootSource(),
        pageUrl: null,
        shouldContinue: () => true,
      );

      expect(observation.listings.map((l) => l.url), [flatEntryUrl(1)]);
    });

    test('a Source below a listing still reads by its path prefix', () async {
      final landed = 'https://$kHostA$kWorkPath';
      final browser = FakeBrowser()..setUrl('about:blank');
      browser.addPage(
        landed,
        pageWith(landed, [
          partUrl(kHostA, 101),
          postUrl(kHostA, 'the-quiet-part'),
          'https://$kHostA/about-us/',
        ]),
      );

      final observation = await BrowserSourceObservationSource(browser).observe(
        source: SourceRow(
          id: 's2',
          collectionId: 'c2',
          host: kHostA,
          pathKey: kWorkPath,
          language: '',
          lifecycle: 'active',
          firstSeenAt: DateTime(2026),
          lastSeenAt: DateTime(2026),
          updatedAt: DateTime(2026),
        ),
        pageUrl: null,
        shouldContinue: () => true,
      );

      expect(observation.listings.map((l) => l.url), [
        partUrl(kHostA, 101),
        postUrl(kHostA, 'the-quiet-part'),
      ], reason: 'an unnumbered part below the listing is still the work\'s');
    });
  });
}
