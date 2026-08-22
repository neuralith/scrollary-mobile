/// The save flow's own journey, over the real service: a work started from a
/// page, a second site added to it from another page, and a second device that
/// sees one Collection with two Sources.
///
/// **Why this file exists separately from `multi_source_test.dart`.** That
/// suite proves multi-source *semantics* — it builds the two Sources and the
/// shared Entry by hand and then asks the service the hard questions. It
/// therefore cannot prove that any product operation can reach that state, and
/// for a long time none could: every page on a site the library did not
/// already hold became a standalone Entry in the root Folder.
///
/// So this suite starts where the user starts. Every row it asserts on was
/// written by [LibraryAdoption] — the operation the save sheet calls — from an
/// address and a page title, and nothing else.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:web_reader/data/recognition_index.dart';
import 'package:web_reader/data/schema.dart';
import 'package:web_reader/domain/reading_state.dart';
import 'package:web_reader/recognition/adopt.dart';
import 'package:web_reader/recognition/page_kind.dart';
import 'package:web_reader/recognition/recognise.dart';

import 'support/e2e_support.dart';

void main() {
  if (skipWithoutBackend()) return;

  late FixtureSite fixture;
  late String library;
  late E2EClient a;
  late E2EClient b;

  LibraryAdoption adoptionOn(E2EClient client) => LibraryAdoption(
    folders: client.folders,
    collections: client.collections,
    entries: client.entries,
    index: RecognitionIndex(client.db),
  );

  setUpAll(() async {
    fixture = await FixtureSite.start();
    library = uniqueLibrary('saveflow');
    a = E2EClient.start('A', library);
    b = E2EClient.start('B', library);
    await a.folders.ensureRoot();
    await b.folders.ensureRoot();
  });

  tearDownAll(() async {
    fixture.expectNothingFetched('save flow, multi-source');
    await a.stop();
    await b.stop();
    await fixture.stop();
  });

  test(
    'a page starts a Collection, and a page on another site joins it',
    () async {
      // ── 1. The user is reading part 101 on the first site. Nothing in the
      //       library knows it, and the sheet offers to start a Collection.
      final alpha = fixture.partUrl('alpha', 101);
      final alphaShape = readPageShape(
        alpha,
        pageTitle: 'Fixture work — Part 101',
      );
      expect(
        alphaShape.kind,
        PageKind.entryPage,
        reason: 'a numbered part is an entry page, not an ordinary page',
      );
      expect(alphaShape.printedNumber, 101);

      final created = await adoptionOn(a).createCollection(
        name: 'Fixture work',
        keys: RecognitionKeys.of(alpha, pageTitle: 'Fixture work — Part 101'),
        pageTitle: 'Fixture work — Part 101',
        printedNumber: alphaShape.printedNumber,
      );
      expect(created.violation, isNull);
      expect(created.succeeded, isTrue);
      final collectionId = created.collectionId!;

      // ── 2. The same user, on a second site, at the same part. The address is
      //       unknown, so recognition can say nothing — and the user answers.
      final beta = fixture.partUrl('beta', 101);
      final betaShape = readPageShape(
        beta,
        pageTitle: 'Fixture work — Part 101',
      );
      final joined = await adoptionOn(a).addToExistingCollection(
        collectionId: collectionId,
        keys: RecognitionKeys.of(beta, pageTitle: 'Fixture work — Part 101'),
        pageTitle: 'Fixture work — Part 101',
        printedNumber: betaShape.printedNumber,
      );
      expect(joined.violation, isNull);
      expect(
        joined.mergedIntoExistingEntry,
        isTrue,
        reason:
            'equal printed ordinals under a numeric basis are one Entry '
            '(V2-D16)',
      );
      expect(joined.entryId, created.entryId);
      expect(joined.sourceId, isNot(created.sourceId));

      // ── 3. Locally: one Collection, two Sources, one Entry, two Locations —
      //       and, the point of the whole exercise, no loose Entry anywhere.
      final sources = await a.collections.sourcesOf(collectionId);
      expect(sources, hasLength(2));
      expect(await a.entries.entriesOf(collectionId), hasLength(1));
      expect(await a.entries.locationsOf(created.entryId!), hasLength(2));
      await expectNoStandaloneEntries(a);

      // ── 4. Reading state written on one site is the work's, not the site's.
      final (read, readViolation) = await a.readingStates.markRead(
        created.entryId!,
      );
      expect(readViolation, isNull);
      expect(read!.status, ReadStatus.completed);

      // ── 5. It reaches a second device as one Collection with two Sources.
      await a.sync();
      await b.sync();

      final mirrored = await soleCollectionOf(b);
      final mirroredSources = await b.collections.sourcesOf(mirrored.id);
      expect(mirroredSources, hasLength(2));

      final mirroredEntries = await b.entries.entriesOf(mirrored.id);
      expect(mirroredEntries, hasLength(1));
      expect(
        await b.entries.locationsOf(mirroredEntries.single.id),
        hasLength(2),
        reason:
            'both addresses belong to the one Entry on the second device too',
      );
      expect(
        (await b.readingStates.stateOf(mirroredEntries.single.id)).status,
        ReadStatus.completed,
        reason:
            'reading state belongs to the work, not to the site it was read '
            'on (V2-D18)',
      );
      await expectNoStandaloneEntries(b);
    },
  );

  test('an ordinary page is still saved as a standalone Entry', () async {
    // The fallback stays available and stays deliberate: an address with no
    // work behind it is a first-class library item, not a failure (I3).
    final page = '${fixture.origin}/about';
    expect(readPageShape(page, pageTitle: 'About').kind, PageKind.unknownPage);

    final root = await a.folders.ensureRoot();
    final (entry, violation) = await a.entries.createStandalone(
      folderId: root.id,
      title: 'About',
    );
    expect(violation, isNull);
    final (location, locationViolation) = await a.entries.addLocation(
      entryId: entry!.id,
      url: page,
      urlKey: RecognitionKeys.of(page).urlKey,
      discoveryBasis: 'userSave',
    );
    expect(locationViolation, isNull);
    expect(location!.sourceId, isNull, reason: 'I7');
  });
}

/// No Entry in [client]'s library sits outside a Collection except one the
/// test put there on purpose — the regression this whole suite guards.
Future<void> expectNoStandaloneEntries(E2EClient client) async {
  final loose = await (client.db.select(
    client.db.entries,
  )..where((e) => e.collectionId.isNull())).get();
  expect(
    loose,
    isEmpty,
    reason:
        'a page that belongs to a Collection was written as a loose Entry: '
        '${loose.map((e) => '${e.title} (${e.id})').join(', ')}',
  );
}

/// The one Collection [client] holds — asserting on the way that a second
/// device never ends up with a duplicate of the work.
Future<CollectionRow> soleCollectionOf(E2EClient client) async {
  final all = await client.db.select(client.db.collections).get();
  expect(
    all,
    hasLength(1),
    reason: 'the second device sees exactly one Collection, never a duplicate',
  );
  return all.single;
}
