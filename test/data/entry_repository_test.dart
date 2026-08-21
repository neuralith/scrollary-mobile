/// Entry and Location repository (C5): placement, ordinal uniqueness, the
/// unplaced round-trip, url_key identity, and source-scoped retraction.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:web_reader/data/data_violations.dart';
import 'package:web_reader/domain/entry.dart';
import 'package:web_reader/domain/invariants.dart';

import 'support/repo_harness.dart';

void main() {
  late RepoHarness h;

  setUp(() => h = RepoHarness());
  tearDown(() => h.close());

  test('two Entries of one Collection cannot share an ordinal (I8)', () async {
    final seeded = await h.seedLibrary();
    final (dup, violation) = await h.entries.createInCollection(
      collectionId: seeded.collection.id,
      ordinal: 101,
    );
    expect(dup, isNull);
    expect(violation, duplicateOrdinal);
  });

  test('an unplaced Entry carries no ordinal, and round-trips through '
      'user placement', () async {
    final seeded = await h.seedLibrary();

    final (bad, badViolation) = await h.entries.createInCollection(
      collectionId: seeded.collection.id,
      ordinal: 99.5,
      placement: Placement.unplaced,
    );
    expect(bad, isNull);
    expect(badViolation, unplacedEntryHasOrdinal);

    final (unplaced, v1) = await h.entries.createInCollection(
      collectionId: seeded.collection.id,
      placement: Placement.unplaced,
      title: 'Part 99.5?',
    );
    expect(v1, isNull);
    expect(unplaced!.ordinal, isNull);
    expect((await h.entries.unplacedOf(seeded.collection.id)), hasLength(1));

    final (placed, v2) = await h.entries.placeEntry(unplaced.id, 99.5);
    expect(v2, isNull);
    expect(placed!.placement, Placement.userPlaced.name);
    expect(placed.ordinal, 99.5);
    expect(await h.entries.unplacedOf(seeded.collection.id), isEmpty);

    // Placing onto a taken position is the same refusal as creating there.
    final (unplaced2, _) = await h.entries.createInCollection(
      collectionId: seeded.collection.id,
      placement: Placement.unplaced,
    );
    final (_, v3) = await h.entries.placeEntry(unplaced2!.id, 101);
    expect(v3, duplicateOrdinal);
  });

  test('a standalone Entry is first-class in a Folder', () async {
    final root = await h.folders.ensureRoot();
    final (standalone, violation) = await h.entries.createStandalone(
      folderId: root.id,
      title: 'One-off',
    );
    expect(violation, isNull);
    expect(standalone!.collectionId, isNull);
    expect(standalone.folderId, root.id);

    // Its Location has no Source (I7)…
    final (location, lv) = await h.entries.addLocation(
      entryId: standalone.id,
      url: 'https://pages.example.org/essay',
      urlKey: 'https://pages.example.org/essay',
    );
    expect(lv, isNull);
    expect(location!.sourceId, isNull);
  });

  test('a Location belongs to a Source iff its Entry belongs to a '
      'Collection (I7)', () async {
    final seeded = await h.seedLibrary();
    final root = seeded.root;

    final (_, missingSource) = await h.entries.addLocation(
      entryId: seeded.entry.id,
      url: 'https://reading.example.com/serial-alpha/part-101-b',
      urlKey: 'https://reading.example.com/serial-alpha/part-101-b',
    );
    expect(missingSource, locationSourcePairing);

    final (standalone, _) = await h.entries.createStandalone(folderId: root.id);
    final (_, extraSource) = await h.entries.addLocation(
      entryId: standalone!.id,
      sourceId: seeded.source.id,
      url: 'https://pages.example.org/essay-2',
      urlKey: 'https://pages.example.org/essay-2',
    );
    expect(extraSource, locationSourcePairing);
  });

  test('one URL is one Location (I6)', () async {
    final seeded = await h.seedLibrary();
    final (entry2, _) = await h.entries.createInCollection(
      collectionId: seeded.collection.id,
      ordinal: 102,
    );
    final (dup, violation) = await h.entries.addLocation(
      entryId: entry2!.id,
      sourceId: seeded.source.id,
      url: seeded.location.url,
      urlKey: seeded.location.urlKey,
    );
    expect(dup, isNull);
    expect(violation, duplicateUrlKey);
  });

  test('retraction is source-scoped (I15) and never syncs', () async {
    final seeded = await h.seedLibrary();
    final (otherSource, _) = await h.collections.addSource(
      collectionId: seeded.collection.id,
      host: 'mirror.example.test',
      pathKey: 'serial-alpha',
    );

    expect(
      await h.entries.retractLocation(
        seeded.location.id,
        readingSourceId: otherSource!.id,
      ),
      retractionOutOfScope,
    );

    final before = await h.outboxCount();
    expect(
      await h.entries.retractLocation(
        seeded.location.id,
        readingSourceId: seeded.source.id,
      ),
      isNull,
    );
    expect(
      (await h.entries.locationById(seeded.location.id))!.lifecycle,
      'retracted',
    );
    expect(await h.outboxCount(), before, reason: 'evidence does not sync');
  });

  test('removing a Location by hand is a user removal and syncs', () async {
    final seeded = await h.seedLibrary();
    final before = await h.outboxCount();
    expect(await h.entries.removeLocationByHand(seeded.location.id), isNull);
    expect(await h.entries.locationById(seeded.location.id), isNull);
    expect(await h.outboxCount(), before + 1);
    final rows = await h.outbox.pending(limit: 100);
    expect(rows.last.op, 'delete');
    expect(rows.last.entityKind, 'location');
  });

  test(
    'removing an Entry cascades its library rows and keeps the copy row',
    () async {
      final seeded = await h.seedLibrary();
      await h.reading.markRead(seeded.entry.id);
      await h.measurements.put(
        entryId: seeded.entry.id,
        sourceId: seeded.source.id,
        fraction: 0.5,
      );
      await h.offline.recordCopy(
        entryId: seeded.entry.id,
        locationUrl: seeded.location.url,
        artifactFormat: 'imageSequence',
        contentPath: 'library/x',
        byteSize: 42,
      );

      expect(await h.entries.removeEntry(seeded.entry.id), isNull);
      expect(await h.entries.byId(seeded.entry.id), isNull);
      expect(await h.entries.locationById(seeded.location.id), isNull);
      expect(await h.measurements.allOf(seeded.entry.id), isEmpty);
      // I14 locally: the copy row has no foreign key and survives.
      final copies = await h.offline.allCopies();
      expect(copies, hasLength(1));
      expect(copies.single.entryId, seeded.entry.id);
    },
  );
}
