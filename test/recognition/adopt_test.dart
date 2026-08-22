/// Establishing Collection context for a page the library does not hold
/// (V2_SAVE_FLOW.md §3).
///
/// The regression this suite guards is the one the whole flow exists for: a
/// serialized page on an unknown site used to become a loose Entry in the root
/// Folder, with no Collection, no Source and no way to attach it to one. Every
/// test below asserts the shape of what was written, and several of them
/// assert that **nothing** loose was written along the way.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:web_reader/data/data_violations.dart';
import 'package:web_reader/data/schema.dart';
import 'package:web_reader/domain/collection.dart';
import 'package:web_reader/domain/invariants.dart';
import 'package:web_reader/domain/reading_state.dart';
import 'package:web_reader/recognition/adopt.dart';
import 'package:web_reader/recognition/recognise.dart';

import 'support/recognition_harness.dart';

void main() {
  late RecognitionHarness h;

  setUp(() => h = RecognitionHarness());
  tearDown(() => h.close());

  /// Every Entry the library holds that belongs to no Collection.
  Future<List<EntryRow>> looseEntries() => (h.repos.db.select(
    h.repos.db.entries,
  )..where((e) => e.collectionId.isNull())).get();

  Future<List<LocationRow>> locationsOf(String entryId) =>
      h.repos.entries.locationsOf(entryId);

  group('an unknown site becomes a Collection', () {
    test(
      'Collection, Source, Entry and Location — and nothing loose',
      () async {
        final url = partUrl(kHostA, 5);
        final outcome = await h.adoption.createCollection(
          name: 'Quiet Harbour',
          keys: RecognitionKeys.of(url, pageTitle: 'Part 5'),
          pageTitle: 'Part 5',
          printedNumber: 5,
        );

        expect(outcome.succeeded, isTrue);
        final collection = await h.repos.collections.byId(
          outcome.collectionId!,
        );
        expect(collection!.name, 'Quiet Harbour');
        expect(
          collection.orderingBasis,
          OrderingBasis.explicitNumericIndex.name,
        );
        expect(collection.folderId, (await h.root()).id);

        final sources = await h.repos.collections.sourcesOf(collection.id);
        expect(sources, hasLength(1));
        expect(sources.single.host, kHostA);

        final entry = await h.repos.entries.byId(outcome.entryId!);
        expect(entry!.collectionId, collection.id);
        expect(entry.ordinal, 5);
        expect(entry.folderId, isNull);

        final locations = await locationsOf(entry.id);
        expect(locations.single.sourceId, sources.single.id);
        expect(locations.single.url, url);
        expect(locations.single.discoveryBasis, kUserSaveBasis);

        expect(
          await looseEntries(),
          isEmpty,
          reason: 'a serialized page never becomes standalone silently',
        );
      },
    );

    test('a page that numbers nothing claims no numeric basis', () async {
      final url = postUrl(kHostA, 'epilogue');
      final outcome = await h.adoption.createCollection(
        name: 'Quiet Harbour',
        keys: RecognitionKeys.of(url, pageTitle: 'Epilogue'),
        pageTitle: 'Epilogue',
      );

      final collection = await h.repos.collections.byId(outcome.collectionId!);
      expect(collection!.orderingBasis, OrderingBasis.discoveryOrder.name);
      final entry = await h.repos.entries.byId(outcome.entryId!);
      expect(entry!.placement, 'unplaced');
      expect(entry.ordinal, isNull);
    });

    test('a site already published under a Collection never moves', () async {
      final held = await h.collection(name: 'Held');
      await h.source(collection: held, host: kHostA);

      final outcome = await h.adoption.createCollection(
        name: 'A Second Home',
        keys: RecognitionKeys.of(partUrl(kHostA, 5)),
        pageTitle: 'Part 5',
        printedNumber: 5,
      );

      expect(outcome.violation, sourceIdentityTaken);
      expect(
        await h.repos.collections.inFolder((await h.root()).id),
        hasLength(1),
      );
    });

    test('a refused write leaves no half-built Collection', () async {
      // The address is already a Location of a standalone Entry, so the
      // Location this adoption would need cannot be written (I6). Nothing of
      // the Collection it started may survive that.
      final url = partUrl(kHostA, 5);
      final (loose, _) = await h.repos.entries.createStandalone(
        folderId: (await h.root()).id,
        title: 'Part 5',
      );
      await h.repos.entries.addLocation(
        entryId: loose!.id,
        url: url,
        urlKey: RecognitionKeys.of(url).urlKey,
      );

      final outcome = await h.adoption.createCollection(
        name: 'Quiet Harbour',
        keys: RecognitionKeys.of(url),
        pageTitle: 'Part 5',
        printedNumber: 5,
      );

      expect(outcome.violation, duplicateUrlKey);
      expect(await h.repos.collections.inFolder((await h.root()).id), isEmpty);
      expect(await h.repos.db.select(h.repos.db.sources).get(), isEmpty);
      expect(await looseEntries(), hasLength(1));
    });
  });

  group('an unknown site joins a Collection the user names', () {
    test('the site becomes another Source of it, and only that', () async {
      final collection = await h.collection();
      await h.source(collection: collection, host: kHostA);

      final url = partUrl(kHostB, 5);
      final outcome = await h.adoption.addToExistingCollection(
        collectionId: collection.id,
        keys: RecognitionKeys.of(url),
        pageTitle: 'Part 5',
        printedNumber: 5,
      );

      expect(outcome.succeeded, isTrue);
      expect(outcome.sourceReused, isFalse);
      final sources = await h.repos.collections.sourcesOf(collection.id);
      expect(sources.map((s) => s.host), [kHostA, kHostB]);
      expect(
        await h.repos.collections.inFolder((await h.root()).id),
        hasLength(1),
        reason: 'attaching a site to a Collection never makes a second one',
      );
      expect(await looseEntries(), isEmpty);
    });

    test('the same site twice reuses the Source it already has', () async {
      final collection = await h.collection();
      final first = await h.adoption.addToExistingCollection(
        collectionId: collection.id,
        keys: RecognitionKeys.of(partUrl(kHostB, 5)),
        pageTitle: 'Part 5',
        printedNumber: 5,
      );
      final second = await h.adoption.addToExistingCollection(
        collectionId: collection.id,
        keys: RecognitionKeys.of(partUrl(kHostB, 6)),
        pageTitle: 'Part 6',
        printedNumber: 6,
      );

      expect(second.sourceReused, isTrue);
      expect(second.sourceId, first.sourceId);
      expect(await h.repos.collections.sourcesOf(collection.id), hasLength(1));
    });

    test('a site held by another Collection is refused, never moved', () async {
      final held = await h.collection(name: 'Held');
      final source = await h.source(collection: held, host: kHostB);
      final other = await h.collection(name: 'Other');

      final outcome = await h.adoption.addToExistingCollection(
        collectionId: other.id,
        keys: RecognitionKeys.of(partUrl(kHostB, 5)),
        pageTitle: 'Part 5',
        printedNumber: 5,
      );

      expect(outcome.violation, sourceIdentityTaken);
      expect(
        (await h.repos.collections.sourceById(source.id))!.collectionId,
        held.id,
      );
      expect(await h.repos.collections.sourcesOf(other.id), isEmpty);
    });

    test('an address the library already holds writes nothing', () async {
      final collection = await h.collection();
      final source = await h.source(collection: collection, host: kHostA);
      final (entry, location) = await h.placedEntry(
        collection: collection,
        source: source,
        host: kHostA,
        number: 5,
      );

      final outcome = await h.adoption.addToExistingCollection(
        collectionId: collection.id,
        keys: RecognitionKeys.of(partUrl(kHostA, 5)),
        pageTitle: 'Part 5',
        printedNumber: 5,
      );

      expect(outcome.entryId, entry.id);
      expect(outcome.locationId, location.id);
      expect(await h.repos.entries.entriesOf(collection.id), hasLength(1));
      expect(await locationsOf(entry.id), hasLength(1));
    });

    test('an address with no stable Source key is refused', () async {
      final collection = await h.collection();

      final outcome = await h.adoption.addToExistingCollection(
        collectionId: collection.id,
        keys: RecognitionKeys.of('https://$kHostA/'),
        pageTitle: 'Alpha',
      );

      expect(outcome.violation, sourceKeyUnavailable);
    });
  });

  group('cross-source equivalence, through the save path', () {
    test('an equal ordinal on another site is one Entry, two '
        'Locations', () async {
      final collection = await h.collection();
      final sourceA = await h.source(collection: collection, host: kHostA);
      final (entry, _) = await h.placedEntry(
        collection: collection,
        source: sourceA,
        host: kHostA,
        number: 5,
      );

      final outcome = await h.adoption.addToExistingCollection(
        collectionId: collection.id,
        keys: RecognitionKeys.of(partUrl(kHostB, 5)),
        pageTitle: 'Part 5',
        printedNumber: 5,
      );

      expect(outcome.mergedIntoExistingEntry, isTrue);
      expect(outcome.entryId, entry.id);
      expect(await h.repos.entries.entriesOf(collection.id), hasLength(1));
      expect(await locationsOf(entry.id), hasLength(2));
    });

    test('100 against 99.5 stays two Entries', () async {
      final collection = await h.collection();
      final sourceA = await h.source(collection: collection, host: kHostA);
      await h.placedEntry(
        collection: collection,
        source: sourceA,
        host: kHostA,
        number: 100,
      );

      final outcome = await h.adoption.addToExistingCollection(
        collectionId: collection.id,
        keys: RecognitionKeys.of(partUrl(kHostShifted, 99.5)),
        pageTitle: 'Part 99.5',
        printedNumber: 99.5,
      );

      expect(outcome.mergedIntoExistingEntry, isFalse);
      final entries = await h.repos.entries.entriesOf(collection.id);
      expect(entries.map((e) => e.ordinal), [99.5, 100]);
    });

    test(
      'a save on a known Source reconciles instead of duplicating',
      () async {
        // The regression guard. A page on a Source the library already holds,
        // at an address it has never seen, whose printed number is one the
        // Collection already has: it joins that Entry rather than becoming a
        // second one beside it.
        final collection = await h.collection();
        final sourceA = await h.source(collection: collection, host: kHostA);
        final (entry, _) = await h.placedEntry(
          collection: collection,
          source: sourceA,
          host: kHostA,
          number: 5,
        );
        // The same Source, a second address for the same part.
        final url = '${partUrl(kHostA, 5)}/read';

        final outcome = await h.adoption.addToExistingCollection(
          collectionId: collection.id,
          keys: RecognitionKeys.of(url),
          pageTitle: 'Part 5',
          printedNumber: 5,
        );

        expect(outcome.entryId, entry.id);
        expect(outcome.sourceReused, isTrue);
        expect(await h.repos.entries.entriesOf(collection.id), hasLength(1));
        expect(await locationsOf(entry.id), hasLength(2));
      },
    );
  });

  group('a listing is never an Entry', () {
    test('adding one writes a Collection and a Source, and no Entry', () async {
      final outcome = await h.adoption.addListingSource(
        newCollectionName: 'Quiet Harbour',
        keys: RecognitionKeys.of('https://$kHostA$kWorkPath'),
      );

      expect(outcome.succeeded, isTrue);
      expect(outcome.createdCollection, isTrue);
      expect(
        await h.repos.collections.sourcesOf(outcome.collectionId!),
        hasLength(1),
      );
      expect(await h.repos.db.select(h.repos.db.entries).get(), isEmpty);
    });

    test('adding one to a Collection attaches the site alone', () async {
      final collection = await h.collection();
      final outcome = await h.adoption.addListingSource(
        collectionId: collection.id,
        keys: RecognitionKeys.of('https://$kHostB$kWorkPath'),
      );

      expect(outcome.succeeded, isTrue);
      expect(outcome.createdCollection, isFalse);
      expect(await h.repos.db.select(h.repos.db.entries).get(), isEmpty);
    });

    test('one target, or the other, but not both', () async {
      final collection = await h.collection();
      final outcome = await h.adoption.addListingSource(
        collectionId: collection.id,
        newCollectionName: 'Another',
        keys: RecognitionKeys.of('https://$kHostB$kWorkPath'),
      );

      expect(outcome.violation, adoptionTargetAmbiguous);
    });
  });

  group('a loose Entry moves into a Collection', () {
    /// A standalone Entry at [url], with the reading state and device content
    /// a real one carries.
    Future<EntryRow> standalone({
      required String url,
      required String title,
    }) async {
      final (entry, _) = await h.repos.entries.createStandalone(
        folderId: (await h.root()).id,
        title: title,
      );
      await h.repos.entries.addLocation(
        entryId: entry!.id,
        url: url,
        urlKey: RecognitionKeys.of(url).urlKey,
        discoveryBasis: kUserSaveBasis,
      );
      return entry;
    }

    test('it joins the Collection, keeping its own Location', () async {
      final collection = await h.collection();
      final entry = await standalone(url: partUrl(kHostB, 7), title: 'Part 7');

      final outcome = await h.adoption.adoptStandalone(
        entryId: entry.id,
        collectionId: collection.id,
      );

      expect(outcome.succeeded, isTrue);
      expect(outcome.entryId, entry.id);
      expect(outcome.mergedIntoExistingEntry, isFalse);

      final moved = await h.repos.entries.byId(entry.id);
      expect(moved!.collectionId, collection.id);
      expect(moved.folderId, isNull);
      expect(moved.ordinal, 7, reason: 'its own title numbered it');
      expect(moved.placement, 'placed');

      final source = (await h.repos.collections.sourcesOf(
        collection.id,
      )).single;
      expect((await locationsOf(entry.id)).single.sourceId, source.id);
      expect(await looseEntries(), isEmpty);
    });

    test('an Entry already in a Collection has nothing to adopt', () async {
      final collection = await h.collection();
      final source = await h.source(collection: collection, host: kHostA);
      final (entry, _) = await h.placedEntry(
        collection: collection,
        source: source,
        host: kHostA,
        number: 5,
      );
      final other = await h.collection(name: 'Other');

      final outcome = await h.adoption.adoptStandalone(
        entryId: entry.id,
        collectionId: other.id,
      );

      expect(outcome.violation, entryNotStandalone);
    });

    test(
      'a site held elsewhere is refused, and the Entry stays loose',
      () async {
        final held = await h.collection(name: 'Held');
        await h.source(collection: held, host: kHostB);
        final other = await h.collection(name: 'Other');
        final entry = await standalone(
          url: partUrl(kHostB, 7),
          title: 'Part 7',
        );

        final outcome = await h.adoption.adoptStandalone(
          entryId: entry.id,
          collectionId: other.id,
        );

        expect(outcome.violation, sourceIdentityTaken);
        expect((await h.repos.entries.byId(entry.id))!.collectionId, isNull);
      },
    );

    test('an equivalent Entry takes it over, losing nothing', () async {
      final collection = await h.collection();
      final sourceA = await h.source(collection: collection, host: kHostA);
      final (target, _) = await h.placedEntry(
        collection: collection,
        source: sourceA,
        host: kHostA,
        number: 7,
      );
      // The site the loose Entry is published on is already a Source of the
      // Collection, so a measurement taken while reading it loose names a
      // Source that exists.
      final sourceB = await h.source(collection: collection, host: kHostB);

      final entry = await standalone(url: partUrl(kHostB, 7), title: 'Part 7');
      await h.repos.reading.markRead(target.id);
      await h.repos.reading.markRead(entry.id);
      await h.repos.measurements.put(
        entryId: entry.id,
        sourceId: sourceB.id,
        fraction: 0.4,
      );
      final copy = await h.repos.offline.recordCopy(
        entryId: entry.id,
        locationUrl: partUrl(kHostB, 7),
        artifactFormat: 'imageSequence',
        contentPath: 'library/${entry.id}/manifest.json',
        byteSize: 4096,
        sourceName: 'Quiet Harbour',
        sourceHost: kHostB,
        sourceLanguage: 'en',
      );

      final outcome = await h.adoption.adoptStandalone(
        entryId: entry.id,
        collectionId: collection.id,
      );

      expect(outcome.mergedIntoExistingEntry, isTrue);
      expect(outcome.entryId, target.id);

      // One Entry, two Locations, and the loose row is gone.
      expect(await h.repos.entries.entriesOf(collection.id), hasLength(1));
      expect(await h.repos.entries.byId(entry.id), isNull);
      final locations = await locationsOf(target.id);
      expect(locations, hasLength(2));
      expect(locations.map((l) => l.sourceId).toSet(), {
        sourceA.id,
        sourceB.id,
      });

      // Reading state survives on the survivor.
      final state = await h.repos.reading.stateOf(target.id);
      expect(state.status, ReadStatus.completed);

      // The measurement keeps its scope and its number.
      final measurement = await h.repos.measurements.of(target.id, sourceB.id);
      expect(measurement!.fraction, 0.4);

      // The bytes are never touched: same row, same path, same provenance.
      final copies = await h.repos.offline.allCopies();
      expect(copies, hasLength(1));
      expect(copies.single.id, copy.id);
      expect(copies.single.entryId, target.id);
      expect(copies.single.contentPath, copy.contentPath);
      expect(copies.single.byteSize, 4096);
      expect(copies.single.sourceHost, kHostB);
      expect(copies.single.active, isTrue);
    });

    test('the survivor keeps its own active copy, and neither is '
        'deleted', () async {
      final collection = await h.collection();
      final sourceA = await h.source(collection: collection, host: kHostA);
      final (target, _) = await h.placedEntry(
        collection: collection,
        source: sourceA,
        host: kHostA,
        number: 7,
      );
      final held = await h.repos.offline.recordCopy(
        entryId: target.id,
        locationUrl: partUrl(kHostA, 7),
        artifactFormat: 'imageSequence',
        contentPath: 'library/${target.id}/manifest.json',
        byteSize: 128,
      );
      final entry = await standalone(url: partUrl(kHostB, 7), title: 'Part 7');
      final arriving = await h.repos.offline.recordCopy(
        entryId: entry.id,
        locationUrl: partUrl(kHostB, 7),
        artifactFormat: 'imageSequence',
        contentPath: 'library/${entry.id}/manifest.json',
        byteSize: 256,
      );

      await h.adoption.adoptStandalone(
        entryId: entry.id,
        collectionId: collection.id,
      );

      final copies = await h.repos.offline.allCopies();
      expect(copies, hasLength(2));
      expect(copies.every((c) => c.entryId == target.id), isTrue);
      expect(
        copies.firstWhere((c) => c.id == held.id).active,
        isTrue,
        reason: 'the survivor keeps the copy it was already reading',
      );
      final moved = copies.firstWhere((c) => c.id == arriving.id);
      expect(moved.active, isFalse, reason: 'I13: one active copy per Entry');
      expect(moved.contentPath, arriving.contentPath);
      expect(moved.byteSize, 256);
    });

    test('a merge tells the other devices what became of the rows', () async {
      final collection = await h.collection();
      final sourceA = await h.source(collection: collection, host: kHostA);
      final (target, _) = await h.placedEntry(
        collection: collection,
        source: sourceA,
        host: kHostA,
        number: 7,
      );
      await h.source(collection: collection, host: kHostB);
      final entry = await standalone(url: partUrl(kHostB, 7), title: 'Part 7');
      await h.repos.reading.markRead(entry.id);

      final before = await h.repos.outbox.pendingCount();
      await h.adoption.adoptStandalone(
        entryId: entry.id,
        collectionId: collection.id,
      );
      final intents = await h.repos.outbox.pending(limit: 100);
      final fresh = intents.skip(before).toList();

      expect(
        fresh.map((i) => '${i.entityKind}/${i.op}'),
        containsAll(<String>[
          'location/upsert',
          'readingState/upsert',
          'entry/delete',
        ]),
      );
      expect(
        fresh.where((i) => i.entityId == target.id).map((i) => i.entityKind),
        contains('readingState'),
      );
    });
  });
}
