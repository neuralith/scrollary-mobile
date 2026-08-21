/// Recognition (F1): the hot path answers locally, offline, or says so.
library;

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_reader/domain/collection.dart';
import 'package:web_reader/domain/reading_state.dart';
import 'package:web_reader/library/collection_identity.dart';
import 'package:web_reader/recognition/recognise.dart';

import '../data/support/repo_harness.dart';
import 'support/recognition_harness.dart';

void main() {
  group('key derivation', () {
    test('the keys are the frozen algorithms, one level down', () {
      final keys = RecognitionKeys.of(partUrl(kHostA, 5));
      expect(keys.urlKey, 'https://$kHostA$kWorkPath/part-5');
      expect(keys.host, kHostA);
      expect(keys.pathKey, kWorkPath);
      expect(keys.isWebPage, isTrue);
    });

    test('an address with no stable collection path reports none', () {
      // The fingerprint drops the part segment and then the bare word, which
      // leaves nothing. "No key" is the answer; a guess is not.
      final keys = RecognitionKeys.of('https://$kHostA/part/5');
      expect(keys.pathKey, isNull);
    });

    test('a page that is not a page is not recognised as one', () {
      expect(RecognitionKeys.of('about:blank').isWebPage, isFalse);
      expect(RecognitionKeys.of('scrollary://open').isWebPage, isFalse);
    });

    test('a page title supplies a title and never a key', () {
      final bare = RecognitionKeys.of(partUrl(kHostA, 5));
      final titled = RecognitionKeys.of(
        partUrl(kHostA, 5),
        pageTitle: 'Quiet Harbour Part 5 — Example Reader',
        hints: const PageHints(ogSiteName: 'Example Reader'),
      );
      expect(titled.pathKey, bare.pathKey);
      expect(titled.urlKey, bare.urlKey);
      expect(bare.detectedCollectionTitle, isNull);
      expect(titled.detectedCollectionTitle, 'Quiet Harbour');
    });
  });

  group('the fast path', () {
    late RecognitionHarness h;
    late CountingInterceptor counter;

    setUp(() {
      counter = CountingInterceptor();
      h = RecognitionHarness(
        executor: NativeDatabase.memory().interceptWith(counter),
      );
    });
    tearDown(() => h.close());

    test('a known address resolves Location, Entry and Collection', () async {
      final collection = await h.collection();
      final source = await h.source(collection: collection, host: kHostA);
      final (entry, location) = await h.placedEntry(
        collection: collection,
        source: source,
        host: kHostA,
        number: 5,
      );

      counter.selects = 0;
      final result = await h.recogniser.recognise(partUrl(kHostA, 5));

      expect(result, isA<RecognisedLocation>());
      final resolved = result as RecognisedLocation;
      expect(resolved.location.id, location.id);
      expect(resolved.entry.id, entry.id);
      expect(resolved.collection?.id, collection.id);
      expect(resolved.sourceId, source.id);
      expect(resolved.authorisesLibraryUpdate, isTrue);
      expect(
        counter.selects,
        2,
        reason: 'one indexed lookup for the address, one for its Collection',
      );
    });

    test('a standalone Entry resolves with no Collection', () async {
      final root = await h.root();
      final (entry, _) = await h.repos.entries.createStandalone(
        folderId: root.id,
        title: 'A lamp in the window',
      );
      final url = postUrl(kHostJournal, 'a-lamp-in-the-window');
      await h.repos.entries.addLocation(
        entryId: entry!.id,
        url: url,
        urlKey: RecognitionKeys.of(url).urlKey,
      );

      final result = await h.recogniser.recognise(url);
      expect(result, isA<RecognisedLocation>());
      final resolved = result as RecognisedLocation;
      expect(resolved.collection, isNull);
      expect(resolved.sourceId, isNull);
      expect(
        resolved.authorisesLibraryUpdate,
        isTrue,
        reason: 'a standalone Entry is in the library by construction',
      );
    });

    test('an unknown address on a known Source is a Source match', () async {
      final collection = await h.collection();
      final source = await h.source(collection: collection, host: kHostA);

      counter.selects = 0;
      final result = await h.recogniser.recognise(partUrl(kHostA, 6));

      expect(result, isA<RecognisedSource>());
      final matched = result as RecognisedSource;
      expect(matched.source.id, source.id);
      expect(matched.collection.id, collection.id);
      expect(matched.followed, isTrue);
      expect(matched.keys.pathKey, kWorkPath);
      expect(counter.selects, 3, reason: 'address, Source, Collection');
    });

    test(
      'another site publishing the same path is a different Source',
      () async {
        final collection = await h.collection();
        await h.source(collection: collection, host: kHostA);

        final result = await h.recogniser.recognise(partUrl(kHostB, 5));
        expect(
          result,
          isA<Unrecognised>(),
          reason: 'the host is half of Source identity',
        );
      },
    );

    test('an unknown page carries the keys it derived', () async {
      await h.collection();
      final result = await h.recogniser.recognise(partUrl(kHostShifted, 5));

      expect(result, isA<Unrecognised>());
      expect(result.keys.host, kHostShifted);
      expect(result.keys.pathKey, kWorkPath);
      expect(result.keys.urlKey, 'https://$kHostShifted$kWorkPath/part-5');
    });

    test('a retracted Location still resolves', () async {
      final collection = await h.collection();
      final source = await h.source(collection: collection, host: kHostA);
      final (_, location) = await h.placedEntry(
        collection: collection,
        source: source,
        host: kHostA,
        number: 5,
      );
      await h.repos.entries.retractLocation(
        location.id,
        readingSourceId: source.id,
      );

      final result = await h.recogniser.recognise(partUrl(kHostA, 5));
      expect(
        result,
        isA<RecognisedLocation>(),
        reason: 'retraction is evidence about a listing, not about an address',
      );
    });
  });

  group('recordAccess', () {
    late RecognitionHarness h;

    setUp(() => h = RecognitionHarness());
    tearDown(() => h.close());

    test('a resolved Entry of a followed Collection records access', () async {
      final collection = await h.collection();
      final source = await h.source(collection: collection, host: kHostA);
      final (entry, _) = await h.placedEntry(
        collection: collection,
        source: source,
        host: kHostA,
        number: 5,
      );

      final result = await h.recogniser.recognise(partUrl(kHostA, 5));
      final state = await h.recogniser.recordAccess(result);

      expect(state, isNotNull);
      expect(state!.status, ReadStatus.reading);
      expect(state.firstOpenedAt, isNotNull);
      expect(state.lastReadAt, isNotNull);
      expect(
        state.completedAt,
        isNull,
        reason: 'I16: completion is never inferred from a source read',
      );
      expect(
        (await h.repos.reading.stateOf(entry.id)).status,
        ReadStatus.reading,
      );
    });

    test('reading it again never reaches completion', () async {
      final collection = await h.collection();
      final source = await h.source(collection: collection, host: kHostA);
      final (entry, _) = await h.placedEntry(
        collection: collection,
        source: source,
        host: kHostA,
        number: 5,
      );

      for (var i = 0; i < 5; i++) {
        await h.recogniser.recordAccess(
          await h.recogniser.recognise(partUrl(kHostA, 5)),
        );
      }
      final state = await h.repos.reading.stateOf(entry.id);
      expect(state.status, ReadStatus.reading);
      expect(state.completedAt, isNull);
    });

    test('an archived Collection is not kept current', () async {
      final collection = await h.collection();
      final source = await h.source(collection: collection, host: kHostA);
      final (entry, _) = await h.placedEntry(
        collection: collection,
        source: source,
        host: kHostA,
        number: 5,
      );
      await h.repos.collections.archive(collection.id);

      final result = await h.recogniser.recognise(partUrl(kHostA, 5));
      expect((result as RecognisedLocation).authorisesLibraryUpdate, isFalse);
      expect(await h.recogniser.recordAccess(result), isNull);
      expect(
        (await h.repos.reading.stateOf(entry.id)).status,
        ReadStatus.unread,
      );
    });

    test('a Source match and an unknown page record nothing', () async {
      final collection = await h.collection();
      await h.source(collection: collection, host: kHostA);

      final onSource = await h.recogniser.recognise(partUrl(kHostA, 6));
      final unknown = await h.recogniser.recognise(partUrl(kHostJournal, 6));

      expect(await h.recogniser.recordAccess(onSource), isNull);
      expect(await h.recogniser.recordAccess(unknown), isNull);
      expect(await h.repos.outboxCount(), lessThanOrEqualTo(2));
    });
  });

  group('ordering basis', () {
    test('only an explicit numeric index permits cross-source merging', () {
      expect(
        OrderingBasis.explicitNumericIndex.supportsCrossSourceMerge,
        isTrue,
      );
      for (final basis in OrderingBasis.values) {
        if (basis == OrderingBasis.explicitNumericIndex) continue;
        expect(basis.supportsCrossSourceMerge, isFalse);
      }
    });
  });
}
