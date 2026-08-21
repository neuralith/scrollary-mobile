import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_reader/library/collection_identity.dart';
import 'package:web_reader/library/collection_repository.dart';
import 'package:web_reader/library/content_shape.dart';
import 'package:web_reader/storage/database.dart';

/// Membership: which collection an entry belongs to, **whether it belongs to one
/// at all**, and what happens when the user regroups by hand.
///
/// The first group is the one that matters most for the product: a page with no
/// detected sequence produces a standalone entry and **no collection row**. A
/// library that quietly manufactures a group of one is a library where "3
/// collections" can mean "3 unrelated articles".
void main() {
  late AppDatabase db;
  late CollectionRepository repo;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = CollectionRepository(db);
  });

  tearDown(() => db.close());

  const noSequence = SequenceShape(
    kind: SequenceKind.none,
    confidence: ShapeConfidence.high,
    basis: 'test: nothing to continue into',
  );
  const sequenced = SequenceShape(
    kind: SequenceKind.explicitNextPrev,
    ordering: OrderingBasis.detectedNextLink,
    confidence: ShapeConfidence.high,
    basis: 'test: rel=next and rel=prev',
  );

  Future<Entry> insertEntry({
    required String id,
    required String url,
    String? collectionId,
    String title = 'A saved page',
  }) async {
    final entry = Entry(
      id: id,
      collectionId: collectionId,
      title: title,
      sourceUrl: url,
      urlKey: url,
      host: Uri.parse(url).host,
      contentKind: ContentKind.unknownWebContent.name,
      contentKindConfidence: ShapeConfidence.low.name,
      contentKindIsUserSet: false,
      artifactFormat: 'imageSequence',
      saveStatus: 'complete',
      contentPath: 'library/x/$id',
      detectedAssetCount: 1,
      storedAssetCount: 1,
      entryOrder: 0,
      byteSize: 10,
      readStatus: 'unread',
      progressFraction: 0,
      progressPageIndex: 0,
      progressOffsetInPage: 0,
    );
    await db.upsertEntry(entry);
    return entry;
  }

  group('standalone entries', () {
    test('a page with no detected sequence creates no collection', () async {
      final collection = await repo.resolveCollection(
        entryUrl: 'https://example.test/notes/on-typography',
        pageTitle: 'On typography',
        sequence: noSequence,
      );

      expect(collection, isNull, reason: 'no sequence means no collection');
      expect(await db.allCollections(), isEmpty);
    });

    test('a standalone entry is stored with a null collection', () async {
      await insertEntry(
        id: 'e1',
        url: 'https://example.test/notes/on-typography',
      );

      final standalone = await db.standaloneEntries();
      expect(standalone, hasLength(1));
      expect(standalone.single.collectionId, isNull);
      expect(await db.allCollections(), isEmpty);
    });

    test('the same standalone page cannot be saved twice', () async {
      await insertEntry(id: 'e1', url: 'https://example.test/a');

      // The composite UNIQUE(collection_id, url_key) cannot catch this: SQLite
      // treats NULLs as distinct. The partial unique index created in onCreate
      // is what does.
      await expectLater(
        insertEntry(id: 'e2', url: 'https://example.test/a'),
        throwsA(isA<Exception>()),
      );
      expect(await db.standaloneEntries(), hasLength(1));
    });
  });

  group('collection membership', () {
    test('a detected sequence creates one collection', () async {
      final collection = await repo.resolveCollection(
        entryUrl: 'https://example.test/guide/part-1',
        pageTitle: 'Setup — The Guide',
        sequence: sequenced,
      );

      expect(collection, isNotNull);
      expect(collection!.sequenceKind, SequenceKind.explicitNextPrev.name);
      expect(collection.orderingBasis, OrderingBasis.detectedNextLink.name);
      expect(await db.allCollections(), hasLength(1));
    });

    test(
      'later pages of the same sequence join it, they do not fork',
      () async {
        final first = (await repo.resolveCollection(
          entryUrl: 'https://example.test/guide/part-1',
          pageTitle: 'Setup — The Guide',
          sequence: sequenced,
        ))!;
        final second = (await repo.resolveCollection(
          entryUrl: 'https://example.test/guide/part-2',
          pageTitle: 'Fonts — The Guide',
          sequence: sequenced,
        ))!;

        expect(second.id, first.id);
        expect(await db.allCollections(), hasLength(1));
      },
    );

    test('renaming never forks the collection', () async {
      final first = (await repo.resolveCollection(
        entryUrl: 'https://example.test/guide/part-1',
        sequence: sequenced,
      ))!;
      await repo.rename(first.id, 'My reading list');

      final again = (await repo.resolveCollection(
        entryUrl: 'https://example.test/guide/part-2',
        sequence: sequenced,
      ))!;

      expect(again.id, first.id);
      expect(again.userTitle, 'My reading list');
      expect(displayNameFor(again), 'My reading list');
    });

    test(
      'a low-confidence identity gets a key nothing else can match',
      () async {
        // No usable path and no title: the identity falls back to the host,
        // which must never merge two unrelated things onto one shelf.
        final a = (await repo.resolveCollection(
          entryUrl: 'https://example.test/',
          sequence: sequenced,
        ))!;
        final b = (await repo.resolveCollection(
          entryUrl: 'https://example.test/',
          sequence: sequenced,
        ))!;

        expect(a.id, isNot(b.id));
        expect(a.identityConfidence, IdentityConfidence.low.name);
        expect(a.collectionKey, isNot(b.collectionKey));
      },
    );
  });

  group('shape is recorded, never assumed', () {
    test('an open-ended sequence stores no total', () async {
      final collection = (await repo.resolveCollection(
        entryUrl: 'https://example.test/blog/first-post',
        sequence: const SequenceShape(
          kind: SequenceKind.openEndedNext,
          ordering: OrderingBasis.detectedNextLink,
          confidence: ShapeConfidence.medium,
        ),
      ))!;

      expect(collection.knownEntryTotal, isNull);
      expect(
        SequenceKind.fromName(collection.sequenceKind).isOpenEnded,
        isTrue,
      );
    });

    test('a published total is stored as published', () async {
      final collection = (await repo.resolveCollection(
        entryUrl: 'https://example.test/report/page-1',
        sequence: const SequenceShape(
          kind: SequenceKind.numberedPagination,
          ordering: OrderingBasis.explicitNumericIndex,
          confidence: ShapeConfidence.high,
          knownTotal: 12,
        ),
      ))!;

      expect(collection.knownEntryTotal, 12);
    });

    test('a weaker re-detection never overwrites a stronger answer', () async {
      final collection = (await repo.resolveCollection(
        entryUrl: 'https://example.test/report/page-1',
        sequence: const SequenceShape(
          kind: SequenceKind.numberedPagination,
          ordering: OrderingBasis.explicitNumericIndex,
          confidence: ShapeConfidence.high,
          knownTotal: 12,
        ),
      ))!;

      await repo.recordShape(
        collectionId: collection.id,
        sequence: const SequenceShape(
          kind: SequenceKind.openEndedNext,
          confidence: ShapeConfidence.low,
        ),
      );

      final after = (await db.collectionById(collection.id))!;
      expect(after.sequenceKind, SequenceKind.numberedPagination.name);
      expect(
        after.knownEntryTotal,
        12,
        reason: 'one unhelpful page load must not lose a published total',
      );
    });
  });

  group('the user regroups by hand', () {
    test('standalone entries can be grouped, with manual ordering', () async {
      final a = await insertEntry(id: 'e1', url: 'https://example.test/a');
      final b = await insertEntry(id: 'e2', url: 'https://example.test/b');

      final collection = await repo.groupManually(
        title: 'Weekend reading',
        members: [b, a],
      );

      expect(collection.sequenceKind, SequenceKind.manualSelection.name);
      expect(
        collection.orderingBasis,
        OrderingBasis.userDefinedManualOrder.name,
        reason: 'the app must not later re-sort what the user arranged',
      );
      final members = await db.entriesForCollection(collection.id);
      expect(members.map((e) => e.id), ['e2', 'e1']);
      expect(await db.standaloneEntries(), isEmpty);
    });

    test(
      'an entry can be pulled back out, and no phantom row remains',
      () async {
        final a = await insertEntry(id: 'e1', url: 'https://example.test/a');
        final collection = await repo.groupManually(
          title: 'Group',
          members: [a],
        );

        await repo.setCollection(entryId: 'e1', collectionId: null);

        expect(await db.standaloneEntries(), hasLength(1));
        expect(
          await db.collectionById(collection.id),
          isNull,
          reason:
              'ungrouping the last entry must not leave an empty collection',
        );
      },
    );
  });
}
