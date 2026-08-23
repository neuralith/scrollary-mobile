/// Moving from one entry to the next while reading.
///
/// The regression this pins: `b1be16d` removed the reader's bottom-bar entry
/// controls, the end-of-entry *Next entry*, the finished-entry dialog and
/// *Save again*, and it was authorised only in a port-review note — the
/// reasoning being that a reader opened over an OfflineCopy has no neighbour
/// list. That is true of the *screen*. It is not true of the **Collection**,
/// which is where neighbours live, and where the route resolves them.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:web_reader/data/schema.dart';
import 'package:web_reader/domain/entry.dart';
import 'package:web_reader/features/v2_reader_route.dart';

import 'support/ui_harness.dart';

void main() {
  late UiHarness h;

  setUp(() => h = UiHarness());
  tearDown(() => h.close());

  Future<List<EntryRow>> serial(int count) async {
    final collection = await h.collection(
      'Serial Alpha',
      folderId: (await h.root()).id,
    );
    return [
      for (var i = 1; i <= count; i++)
        await h.entryIn(collection.id, title: 'Part $i', ordinal: i.toDouble()),
    ];
  }

  test('an entry in the middle has one on each side', () async {
    final entries = await serial(3);

    final around = await readerNeighbours(h.services, entries[1].id);

    expect(around.previousEntryId, entries[0].id);
    expect(around.nextEntryId, entries[2].id);
  });

  test('the ends of a collection have one side only', () async {
    final entries = await serial(3);

    final first = await readerNeighbours(h.services, entries.first.id);
    final last = await readerNeighbours(h.services, entries.last.id);

    expect(first.previousEntryId, isNull);
    expect(first.nextEntryId, entries[1].id);
    expect(last.previousEntryId, entries[1].id);
    expect(
      last.nextEntryId,
      isNull,
      reason: 'there is no next entry — that is an answer, not a failure',
    );
  });

  test('order is the collection\'s, not the order rows were written', () async {
    final collection = await h.collection(
      'Serial Alpha',
      folderId: (await h.root()).id,
    );
    // Written out of order on purpose: discovery finds entries in whatever
    // order a site lists them.
    final third = await h.entryIn(collection.id, title: 'C', ordinal: 3);
    final first = await h.entryIn(collection.id, title: 'A', ordinal: 1);
    final second = await h.entryIn(collection.id, title: 'B', ordinal: 2);

    final around = await readerNeighbours(h.services, second.id);

    expect(around.previousEntryId, first.id);
    expect(around.nextEntryId, third.id);
  });

  test('a neighbour with no copy is still a neighbour', () async {
    // §25: the next entry need not be downloaded. Opening one this device
    // does not hold lands on the reader's own not-downloaded state, where
    // downloading and opening at the source are already offered.
    final entries = await serial(2);

    final around = await readerNeighbours(h.services, entries.first.id);

    expect(around.nextEntryId, entries[1].id);
    expect(await h.services.offline.activeCopyOf(entries[1].id), isNull);
  });

  test('an unplaced entry has no neighbours, by construction', () async {
    final collection = await h.collection(
      'Serial Alpha',
      folderId: (await h.root()).id,
    );
    await h.entryIn(collection.id, title: 'Part 1', ordinal: 1);
    final loose = await h.entryIn(
      collection.id,
      title: 'Afterword',
      placement: Placement.unplaced,
    );

    final around = await readerNeighbours(h.services, loose.id);

    expect(around.previousEntryId, isNull);
    expect(around.nextEntryId, isNull);
  });

  test('a standalone entry has none either', () async {
    final loose = await h.standaloneEntry(
      folderId: (await h.root()).id,
      title: 'One page',
    );

    final around = await readerNeighbours(h.services, loose.id);

    expect(around.previousEntryId, isNull);
    expect(around.nextEntryId, isNull);
  });
}
