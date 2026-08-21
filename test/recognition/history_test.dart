/// Device-local history and promotion (F6): only what the person did is
/// recorded, none of it syncs, and unfollowed reading never expands the
/// library on its own (V2-D13).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:web_reader/domain/collection.dart';
import 'package:web_reader/domain/entry.dart';
import 'package:web_reader/recognition/history.dart';
import 'package:web_reader/recognition/recognise.dart';

import 'support/recognition_harness.dart';

void main() {
  late RecognitionHarness h;

  setUp(() => h = RecognitionHarness());
  tearDown(() => h.close());

  group('what is recorded', () {
    test('a manual visit is recorded with the derived keys', () async {
      final before = await h.repos.outboxCount();
      final (row, violation) = await h.history.recordVisit(
        url: partUrl(kHostA, 5),
        title: 'Part 5',
        userInitiated: true,
      );

      expect(violation, isNull);
      expect(row, isNotNull);
      expect(row!.url, partUrl(kHostA, 5));
      expect(row.urlKey, RecognitionKeys.of(partUrl(kHostA, 5)).urlKey);
      expect(row.host, kHostA);
      expect(row.title, 'Part 5');
      expect(row.source, 'manual');
      expect(await h.history.recent(), hasLength(1));
      expect(
        await h.repos.outboxCount(),
        before,
        reason: 'history never syncs (I11)',
      );
    });

    test('navigation the user did not perform is refused', () async {
      final (row, violation) = await h.history.recordVisit(
        url: partUrl(kHostA, 5),
        userInitiated: false,
      );

      expect(row, isNull);
      expect(violation, historyNotUserInitiated);
      expect(
        await h.history.recent(),
        isEmpty,
        reason: 'a save or a check moves the same browser',
      );
    });

    test('a load that never finished is refused', () async {
      final (row, violation) = await h.history.recordVisit(
        url: partUrl(kHostA, 5),
        userInitiated: true,
        completed: false,
      );
      expect(row, isNull);
      expect(violation, historyVisitIncomplete);
      expect(await h.history.recent(), isEmpty);
    });

    test('something that is not a page is refused', () async {
      for (final url in ['about:blank', 'scrollary://open', '   ']) {
        final (row, violation) = await h.history.recordVisit(
          url: url,
          userInitiated: true,
        );
        expect(row, isNull, reason: url);
        expect(violation, historyNotAWebPage, reason: url);
      }
      expect(await h.history.recent(), isEmpty);
    });

    test('a redirect is recorded where the load settled', () async {
      final (row, _) = await h.history.recordVisit(
        url: partUrl(kHostA, 5),
        finalUrl: partUrl(kHostB, 5),
        userInitiated: true,
      );
      expect(row!.url, partUrl(kHostB, 5));
      expect(row.host, kHostB);
      expect(row.finalUrl, partUrl(kHostB, 5));
    });

    test('reading an unknown page leaves the library alone', () async {
      await h.history.recordVisit(
        url: partUrl(kHostShifted, 5),
        userInitiated: true,
      );

      expect(await h.history.recent(), hasLength(1));
      expect(await h.repos.outboxCount(), 0);
      expect(
        await h.repos.folders.byId('any'),
        isNull,
        reason: 'nothing was created to hold it',
      );
    });
  });

  group('promotion', () {
    test('an Entry already in a followed Collection needs nothing', () async {
      final collection = await h.collection();
      final source = await h.source(collection: collection, host: kHostA);
      final (entry, location) = await h.placedEntry(
        collection: collection,
        source: source,
        host: kHostA,
        number: 5,
      );
      final (row, _) = await h.history.recordVisit(
        url: partUrl(kHostA, 5),
        userInitiated: true,
      );
      final before = await h.repos.outboxCount();

      final outcome = await h.promotion.promoteToLibrary(
        row: row!,
        result: await h.recogniser.recognise(partUrl(kHostA, 5)),
      );

      expect(outcome.kind, PromotionKind.alreadyInLibrary);
      expect(outcome.succeeded, isTrue);
      expect(outcome.entryId, entry.id);
      expect(outcome.locationId, location.id);
      expect(await h.repos.outboxCount(), before);
    });

    test('a standalone Entry is already in the library', () async {
      final root = await h.root();
      final url = postUrl(kHostJournal, 'a-lamp-in-the-window');
      final (entry, _) = await h.repos.entries.createStandalone(
        folderId: root.id,
      );
      await h.repos.entries.addLocation(
        entryId: entry!.id,
        url: url,
        urlKey: RecognitionKeys.of(url).urlKey,
      );
      final (row, _) = await h.history.recordVisit(
        url: url,
        userInitiated: true,
      );

      final outcome = await h.promotion.promoteToLibrary(
        row: row!,
        result: await h.recogniser.recognise(url),
      );

      expect(outcome.kind, PromotionKind.alreadyInLibrary);
      expect(outcome.collectionId, isNull);
      expect(outcome.entryId, entry.id);
    });

    test('a known page of an archived Collection follows it again', () async {
      final collection = await h.collection();
      final source = await h.source(collection: collection, host: kHostA);
      await h.placedEntry(
        collection: collection,
        source: source,
        host: kHostA,
        number: 5,
      );
      await h.repos.collections.archive(collection.id);
      final (row, _) = await h.history.recordVisit(
        url: partUrl(kHostA, 5),
        userInitiated: true,
      );

      final outcome = await h.promotion.promoteToLibrary(
        row: row!,
        result: await h.recogniser.recognise(partUrl(kHostA, 5)),
      );

      expect(outcome.kind, PromotionKind.followedCollection);
      expect(outcome.succeeded, isTrue);
      expect(
        (await h.repos.collections.byId(collection.id))!.lifecycle,
        CollectionLifecycle.active.name,
      );
    });

    test('a Source match follows the Collection and creates nothing', () async {
      final collection = await h.collection();
      await h.source(collection: collection, host: kHostA);
      await h.repos.collections.archive(collection.id);
      final (row, _) = await h.history.recordVisit(
        url: partUrl(kHostA, 6),
        userInitiated: true,
      );

      final result = await h.recogniser.recognise(partUrl(kHostA, 6));
      expect(result, isA<RecognisedSource>());

      final outcome = await h.promotion.promoteToLibrary(
        row: row!,
        result: result,
      );

      expect(outcome.kind, PromotionKind.followedCollection);
      expect(outcome.collectionId, collection.id);
      expect(outcome.entryId, isNull);
      expect(
        (await h.repos.collections.byId(collection.id))!.lifecycle,
        CollectionLifecycle.active.name,
      );
      expect(
        await h.repos.entries.entriesOf(collection.id),
        isEmpty,
        reason: 'following is the authorising act; discovery does the rest',
      );
    });

    test('an unrecognised page becomes a standalone Entry', () async {
      final root = await h.root();
      final url = partUrl(kHostShifted, 5);
      final (row, _) = await h.history.recordVisit(
        url: url,
        title: 'Part 4.5',
        userInitiated: true,
      );
      final before = await h.repos.outboxCount();

      final outcome = await h.promotion.promoteToLibrary(
        row: row!,
        result: await h.recogniser.recognise(url),
      );

      expect(outcome.kind, PromotionKind.createdStandalone);
      expect(outcome.succeeded, isTrue);
      expect(outcome.collectionId, isNull);

      final entry = (await h.repos.entries.byId(outcome.entryId!))!;
      expect(entry.collectionId, isNull);
      expect(entry.folderId, root.id, reason: 'I3: a Folder, not a Collection');
      expect(entry.ordinal, isNull);
      expect(entry.placement, Placement.placed.name);
      expect(entry.title, 'Part 4.5');

      final location = (await h.repos.entries.locationById(
        outcome.locationId!,
      ))!;
      expect(location.urlKey, row.urlKey);
      expect(location.sourceId, isNull, reason: 'I7');
      expect(
        await h.repos.outboxCount(),
        before + 2,
        reason: 'the Entry and its Location each carry one intent',
      );
      expect(
        await h.recogniser.recognise(url),
        isA<RecognisedLocation>(),
        reason: 'the page is recognised from now on',
      );
    });

    test('a standalone Entry can be promoted into a chosen Folder', () async {
      final root = await h.root();
      final (folder, _) = await h.repos.folders.create(
        'Reference',
        parentId: root.id,
      );
      final url = partUrl(kHostShifted, 5);
      final (row, _) = await h.history.recordVisit(
        url: url,
        userInitiated: true,
      );

      final outcome = await h.promotion.promoteToLibrary(
        row: row!,
        result: await h.recogniser.recognise(url),
        folderId: folder!.id,
      );

      expect(
        (await h.repos.entries.byId(outcome.entryId!))!.folderId,
        folder.id,
      );
    });

    test('a result about another page is refused', () async {
      final (row, _) = await h.history.recordVisit(
        url: partUrl(kHostA, 5),
        userInitiated: true,
      );

      final outcome = await h.promotion.promoteToLibrary(
        row: row!,
        result: await h.recogniser.recognise(partUrl(kHostA, 6)),
      );

      expect(outcome.succeeded, isFalse);
      expect(outcome.violation, promotionSubjectMismatch);
      expect(await h.repos.outboxCount(), 0);
    });
  });
}
