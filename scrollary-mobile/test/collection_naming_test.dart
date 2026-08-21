import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_reader/library/collection_repository.dart';
import 'package:web_reader/library/content_shape.dart';
import 'package:web_reader/storage/database.dart';

/// Naming a collection the app is about to create.
///
/// The product rule under test: a new collection's name belongs to the user.
/// Site metadata may *suggest* one — and the suggestion is exactly what the app
/// would have used on its own — but it never decides one silently.
///
/// The prompt is asked at the single point a `collections` row is written, so
/// the two things it must never interrupt are proved here too: joining a
/// collection that already exists, and saving a page that belongs to none.
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

  group('the user names a collection the app is about to create', () {
    test('the prompt fires once, carrying the detected title', () async {
      final asked = <NewCollectionProposal>[];

      final collection = await repo.resolveCollection(
        entryUrl: 'https://x.example/guide/the-long-guide/part-3',
        pageTitle: 'The Long Guide Part 3',
        sequence: sequenced,
        confirmNewName: (proposal) async {
          asked.add(proposal);
          return 'My Reading Shelf';
        },
      );

      expect(asked, hasLength(1));
      expect(asked.single.suggestedName, 'The Long Guide');
      expect(asked.single.host, 'x.example');
      expect(
        asked.single.entryUrl,
        'https://x.example/guide/the-long-guide/part-3',
      );
      expect(collection, isNotNull);
    });

    test('the chosen name is what the library prints', () async {
      final collection = (await repo.resolveCollection(
        entryUrl: 'https://x.example/guide/the-long-guide/part-3',
        pageTitle: 'The Long Guide Part 3',
        sequence: sequenced,
        confirmNewName: (_) async => 'My Reading Shelf',
      ))!;

      final stored = (await db.collectionById(collection.id))!;
      expect(stored.userTitle, 'My Reading Shelf');
      expect(displayNameFor(stored), 'My Reading Shelf');
      // What the source called this is a fact, and it is kept as one.
      expect(stored.title, 'The Long Guide');
    });

    test('surrounding whitespace is trimmed off the chosen name', () async {
      final collection = (await repo.resolveCollection(
        entryUrl: 'https://x.example/guide/the-long-guide/part-3',
        pageTitle: 'The Long Guide Part 3',
        sequence: sequenced,
        confirmNewName: (_) async => '  My Reading Shelf  ',
      ))!;

      expect(
        (await db.collectionById(collection.id))!.userTitle,
        'My Reading Shelf',
      );
    });

    test('an entry-shaped title is only ever a suggestion', () async {
      // `stripEntryMarker` only removes a *trailing* marker, so a page titled
      // like this reaches the identity layer intact and used to become the
      // whole collection's name. It is now offered, not imposed.
      final asked = <String>[];

      final collection = (await repo.resolveCollection(
        entryUrl: 'https://x.example/reading/part-24',
        pageTitle: 'Part 24: The Quiet Year',
        sequence: sequenced,
        confirmNewName: (proposal) async {
          asked.add(proposal.suggestedName);
          return 'The Quiet Year';
        },
      ))!;

      expect(asked, ['Part 24: The Quiet Year']);
      final stored = (await db.collectionById(collection.id))!;
      expect(displayNameFor(stored), 'The Quiet Year');
      expect(stored.userTitle, 'The Quiet Year');
    });

    test('a page that offered no name proposes an empty suggestion', () async {
      final asked = <NewCollectionProposal>[];

      await repo.resolveCollection(
        entryUrl: 'https://x.example/guide/the-long-guide/part-3',
        // Nothing left once the marker is stripped.
        pageTitle: 'Part 3',
        sequence: sequenced,
        confirmNewName: (proposal) async {
          asked.add(proposal);
          return 'Named By Hand';
        },
      );

      expect(asked.single.suggestedName, isEmpty);
      expect(asked.single.host, 'x.example');
    });
  });

  group('the prompt is only for creation', () {
    test('joining an existing collection never asks', () async {
      var asks = 0;
      Future<String?> confirm(NewCollectionProposal p) async {
        asks++;
        return 'My Reading Shelf';
      }

      final first = (await repo.resolveCollection(
        entryUrl: 'https://x.example/guide/the-long-guide/part-3',
        pageTitle: 'The Long Guide Part 3',
        sequence: sequenced,
        confirmNewName: confirm,
      ))!;
      final second = (await repo.resolveCollection(
        entryUrl: 'https://x.example/guide/the-long-guide/part-4',
        pageTitle: 'The Long Guide Part 4',
        sequence: sequenced,
        confirmNewName: confirm,
      ))!;

      expect(asks, 1, reason: 'the second save joined what the first made');
      expect(second.id, first.id);
      expect(second.userTitle, 'My Reading Shelf');
      expect(await db.allCollections(), hasLength(1));
    });

    test('a standalone entry never asks', () async {
      var asks = 0;

      final collection = await repo.resolveCollection(
        entryUrl: 'https://x.example/notes/a-single-page',
        pageTitle: 'A Single Page',
        sequence: noSequence,
        confirmNewName: (_) async {
          asks++;
          return 'Never Used';
        },
      );

      expect(asks, 0);
      expect(collection, isNull);
      expect(await db.allCollections(), isEmpty);
    });
  });

  group('declining', () {
    test('writes no row and returns no collection', () async {
      final collection = await repo.resolveCollection(
        entryUrl: 'https://x.example/guide/the-long-guide/part-3',
        pageTitle: 'The Long Guide Part 3',
        sequence: sequenced,
        confirmNewName: (_) async => null,
      );

      expect(collection, isNull);
      expect(await db.allCollections(), isEmpty);
    });

    test('a blank answer is a decline, not an empty name', () async {
      final collection = await repo.resolveCollection(
        entryUrl: 'https://x.example/guide/the-long-guide/part-3',
        pageTitle: 'The Long Guide Part 3',
        sequence: sequenced,
        confirmNewName: (_) async => '   ',
      );

      expect(collection, isNull);
      expect(await db.allCollections(), isEmpty);
    });

    test('declining leaves an existing collection alone', () async {
      final first = (await repo.resolveCollection(
        entryUrl: 'https://x.example/guide/the-long-guide/part-3',
        pageTitle: 'The Long Guide Part 3',
        sequence: sequenced,
        confirmNewName: (_) async => 'My Reading Shelf',
      ))!;

      // A different collection on the same host, declined.
      final declined = await repo.resolveCollection(
        entryUrl: 'https://x.example/guide/another-guide/part-1',
        pageTitle: 'Another Guide Part 1',
        sequence: sequenced,
        confirmNewName: (_) async => null,
      );

      expect(declined, isNull);
      final all = await db.allCollections();
      expect(all, hasLength(1));
      expect(all.single.id, first.id);
      expect(displayNameFor(all.single), 'My Reading Shelf');
    });
  });

  group('without a prompt, nothing changes', () {
    test('the detected title is used exactly as before', () async {
      final collection = (await repo.resolveCollection(
        entryUrl: 'https://x.example/guide/the-long-guide/part-3',
        pageTitle: 'The Long Guide Part 3',
        sequence: sequenced,
      ))!;

      expect(collection.title, 'The Long Guide');
      expect(collection.userTitle, isNull);
      expect(displayNameFor(collection), 'The Long Guide');
    });
  });
}
