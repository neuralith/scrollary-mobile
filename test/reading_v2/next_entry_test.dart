/// What *reading on* resolves to, over the real library rows.
///
/// The three answers this exists to keep apart, and the reason each one is a
/// different answer rather than a different message:
///
///  * the next Entry is here → the reader moves;
///  * the next Entry is in the library and not on this device → it is still
///    readable, at its Source;
///  * the library knows of no next Entry → that is a fact about the library,
///    which a check can change.
///
/// `next_entry_route_test.dart` proves each one is reachable from the reader.
/// This proves they are decided correctly.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:web_reader/data/schema.dart';
import 'package:web_reader/reading_v2/next_entry.dart';

import '../data/support/repo_harness.dart';

void main() {
  late RepoHarness h;
  late NextEntryResolver resolver;
  late String collectionId;
  late String sourceId;

  setUp(() async {
    h = RepoHarness();
    final seeded = await h.seedLibrary();
    collectionId = seeded.collection.id;
    sourceId = seeded.source.id;
    resolver = NextEntryResolver(
      entries: h.entries,
      collections: h.collections,
      offlineCopies: h.offline,
    );
  });
  tearDown(() => h.db.close());

  Future<EntryRow> place(double ordinal, {String title = 'Part'}) async {
    final (entry, violation) = await h.entries.createInCollection(
      collectionId: collectionId,
      ordinal: ordinal,
      title: title,
    );
    expect(violation, isNull);
    return entry!;
  }

  Future<void> address(String entryId, String url) async {
    final (_, violation) = await h.entries.addLocation(
      entryId: entryId,
      sourceId: sourceId,
      url: url,
      urlKey: url,
      sourceLabel: '',
    );
    expect(violation, isNull);
  }

  Future<void> download(String entryId) => h.offline.recordCopy(
    entryId: entryId,
    locationUrl: 'https://reading.example.com/serial-alpha/$entryId',
    artifactFormat: 'imageSequence',
    contentPath: 'library/$entryId',
    byteSize: 1024,
  );

  test('the next entry this device holds opens in the reader', () async {
    final first = await place(201);
    final second = await place(202);
    await download(second.id);

    expect(
      await resolver.after(first.id),
      isA<NextEntryDownloaded>().having((o) => o.entryId, 'entryId', second.id),
    );
  });

  test('a next entry with no copy here is offered at its source', () async {
    final first = await place(201);
    final second = await place(202, title: 'Part 202');
    await address(second.id, 'https://reading.example.com/serial-alpha/202');

    final outcome = await resolver.after(first.id);
    expect(
      outcome,
      isA<NextEntryAtSourceOnly>()
          .having((o) => o.entryId, 'entryId', second.id)
          .having((o) => o.entryName, 'entryName', 'Part 202')
          .having(
            (o) => o.sourceUrl,
            'sourceUrl',
            'https://reading.example.com/serial-alpha/202',
          ),
    );
  });

  test('the address is the one that was recorded, never a constructed '
      'one', () async {
    final first = await place(201);
    await place(202);

    // No Location at all is an ordinary state: an Entry is not a URL. Nothing
    // is derived from the neighbour's address or from the ordinal.
    expect(
      await resolver.after(first.id),
      isA<NextEntryAtSourceOnly>().having(
        (o) => o.sourceUrl,
        'sourceUrl',
        null,
      ),
    );
  });

  test('a retracted location is not an address to send anyone to', () async {
    final first = await place(201);
    final second = await place(202);
    await address(second.id, 'https://reading.example.com/serial-alpha/202');
    final locations = await h.entries.locationsOf(second.id);
    await h.entries.retractLocation(
      locations.single.id,
      readingSourceId: sourceId,
    );

    expect(
      await resolver.after(first.id),
      isA<NextEntryAtSourceOnly>().having(
        (o) => o.sourceUrl,
        'sourceUrl',
        null,
      ),
    );
  });

  test('nothing after the last entry is a fact about the library, with the '
      'collection named so it can be checked', () async {
    final last = await place(201);

    expect(
      await resolver.after(last.id),
      isA<NoNextEntryYet>()
          .having((o) => o.collectionId, 'collectionId', collectionId)
          .having((o) => o.collectionName, 'collectionName', 'Serial Alpha'),
    );
  });

  test('the order is the collection\'s own, not the order rows were '
      'written', () async {
    final late_ = await place(203, title: 'Part 203');
    final early = await place(201, title: 'Part 201');
    final middle = await place(202, title: 'Part 202');
    await download(middle.id);
    await download(late_.id);

    expect(
      await resolver.after(early.id),
      isA<NextEntryDownloaded>().having((o) => o.entryId, 'entryId', middle.id),
    );
    expect(
      await resolver.after(middle.id),
      isA<NextEntryDownloaded>().having((o) => o.entryId, 'entryId', late_.id),
    );
  });

  test('an entry with no position in the collection is skipped, not read on '
      'to', () async {
    final first = await place(201);
    final (unplaced, violation) = await h.entries.createInCollection(
      collectionId: collectionId,
      ordinal: null,
      title: 'Somewhere in here',
    );
    expect(violation, isNull);
    final second = await place(202);
    await download(second.id);

    final outcome = await resolver.after(first.id);
    expect(
      outcome,
      isA<NextEntryDownloaded>().having((o) => o.entryId, 'entryId', second.id),
    );
    // And it has no reading order of its own to be read on from.
    expect(await resolver.after(unplaced!.id), isA<NoReadingOrder>());
  });

  test('a standalone entry has no reading order to move forward '
      'through', () async {
    final root = await h.folders.ensureRoot();
    final (loose, violation) = await h.entries.createStandalone(
      folderId: root.id,
      title: 'A page on its own',
    );
    expect(violation, isNull);

    expect(await resolver.after(loose!.id), isA<NoReadingOrder>());
  });

  test('a copy that has been freed is no longer a copy', () async {
    final first = await place(201);
    final second = await place(202);
    await download(second.id);
    expect(await resolver.after(first.id), isA<NextEntryDownloaded>());

    await h.offline.removeCopies(second.id);

    // The Entry is untouched and still next; only the bytes went.
    expect(await resolver.after(first.id), isA<NextEntryAtSourceOnly>());
  });
}
