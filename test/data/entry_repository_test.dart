/// Entry and Location repository (C5): placement, ordinal uniqueness, the
/// unplaced round-trip, url_key identity, source-scoped retraction, the narrow
/// evidence writer and the source-scoped read.
library;

import 'dart:convert';

import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
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

  group('the evidence writer', () {
    test('writes the fields it is named and touches nothing else', () async {
      final seeded = await h.seedLibrary();
      final (blankEntry, _) = await h.entries.createInCollection(
        collectionId: seeded.collection.id,
        placement: Placement.unplaced,
      );
      final (blank, _) = await h.entries.addLocation(
        entryId: blankEntry!.id,
        sourceId: seeded.source.id,
        url: 'https://reading.example.com/serial-alpha/part-102',
        urlKey: 'https://reading.example.com/serial-alpha/part-102',
      );

      final before = await h.outboxCount();
      final (filled, violation) = await h.entries.updateLocationEvidence(
        blank!.id,
        sourceLabel: 'Part 102',
        sourceNumber: 102,
        discoveryBasis: 'sourceListing',
      );

      expect(violation, isNull);
      expect(
        (filled!.sourceLabel, filled.sourceNumber, filled.discoveryBasis),
        ('Part 102', 102, 'sourceListing'),
      );
      expect(
        (filled.url, filled.urlKey, filled.discoveredAt, filled.lifecycle),
        (blank.url, blank.urlKey, blank.discoveredAt, blank.lifecycle),
        reason:
            'identity, when it was found and its lifecycle are not '
            'evidence and are unreachable from here',
      );
      expect(
        filled.updatedAt.isAfter(blank.updatedAt),
        isTrue,
        reason: 'the row clock is the merge clock',
      );

      expect(await h.outboxCount(), before + 1);
      final intent = (await h.outbox.pending(limit: 100)).last;
      expect(
        (intent.entityKind, intent.entityId, intent.op),
        ('location', blank.id, 'upsert'),
      );
      expect(jsonDecode(intent.payload), {
        'source_label': 'Part 102',
        'source_number': 102,
        'discovery_basis': 'sourceListing',
      });
    });

    test('a field it was not named stays out of the row and out of the '
        'intent', () async {
      final seeded = await h.seedLibrary();
      final before = await h.outboxCount();

      final (filled, _) = await h.entries.updateLocationEvidence(
        seeded.location.id,
        sourceLabel: 'Part 101 — revised',
      );

      expect(filled!.sourceLabel, 'Part 101 — revised');
      expect(
        (filled.sourceNumber, filled.discoveryBasis),
        (seeded.location.sourceNumber, seeded.location.discoveryBasis),
        reason: 'a null argument is absent, never a clearing null',
      );
      expect(await h.outboxCount(), before + 1);
      expect(jsonDecode((await h.outbox.pending(limit: 100)).last.payload), {
        'source_label': 'Part 101 — revised',
      });
    });

    test('naming nothing is not a mutation', () async {
      final seeded = await h.seedLibrary();
      final before = await h.outboxCount();

      final (row, violation) = await h.entries.updateLocationEvidence(
        seeded.location.id,
      );

      expect(violation, isNull);
      expect(row, seeded.location, reason: 'the row is untouched, clock too');
      expect(await h.outboxCount(), before, reason: 'and so is the outbox');
    });

    test('an unknown Location is refused rather than created', () async {
      await h.seedLibrary();
      final before = await h.outboxCount();
      final (row, violation) = await h.entries.updateLocationEvidence(
        'no-such-location',
        sourceLabel: 'Part 7',
      );
      expect(row, isNull);
      expect(violation, unknownRow);
      expect(await h.outboxCount(), before);
    });
  });

  group('the publish date a reading established', () {
    test('is stored on the Location, and stays out of the outbox', () async {
      final seeded = await h.seedLibrary();
      final before = await h.outboxCount();
      final published = DateTime.utc(2026, 3, 14);

      final violation = await h.entries.recordLocationPublishedAt(
        seeded.location.id,
        published,
      );

      expect(violation, isNull);
      final row = await h.entries.locationById(seeded.location.id);
      // Instants, not objects: drift stores a unix timestamp and reads it
      // back in local time, so the round trip is never the same `DateTime`.
      expect(row!.publishedAt!.isAtSameMomentAs(published), isTrue);
      expect(
        await h.outboxCount(),
        before,
        reason:
            'published_at is not in contracts/evidence.yaml, so nothing may '
            'try to push it',
      );
      expect(
        row.updatedAt,
        seeded.location.updatedAt,
        reason:
            'the row clock is the last-writer-wins clock; moving it for a '
            'field that never syncs would let this device beat a legitimate '
            'remote update',
      );
    });

    test('leaves every other column exactly as it was', () async {
      final seeded = await h.seedLibrary();
      await h.entries.recordLocationPublishedAt(
        seeded.location.id,
        DateTime.utc(2026, 3, 14),
      );
      final row = await h.entries.locationById(seeded.location.id);
      expect(
        (
          row!.url,
          row.urlKey,
          row.sourceLabel,
          row.sourceNumber,
          row.discoveredAt,
          row.lifecycle,
        ),
        (
          seeded.location.url,
          seeded.location.urlKey,
          seeded.location.sourceLabel,
          seeded.location.sourceNumber,
          seeded.location.discoveredAt,
          seeded.location.lifecycle,
        ),
      );
    });

    test(
      'a later reading corrects it; an unchanged one writes nothing',
      () async {
        final seeded = await h.seedLibrary();
        final first = DateTime.utc(2026, 3, 14);
        final corrected = DateTime.utc(2026, 3, 15);

        await h.entries.recordLocationPublishedAt(seeded.location.id, first);
        await h.entries.recordLocationPublishedAt(seeded.location.id, first);
        expect(
          (await h.entries.locationById(
            seeded.location.id,
          ))!.publishedAt!.isAtSameMomentAs(first),
          isTrue,
        );

        await h.entries.recordLocationPublishedAt(
          seeded.location.id,
          corrected,
        );
        expect(
          (await h.entries.locationById(
            seeded.location.id,
          ))!.publishedAt!.isAtSameMomentAs(corrected),
          isTrue,
          reason: 'the last reading of the page wins where a site corrects it',
        );
      },
    );

    test('an unknown Location is refused rather than created', () async {
      await h.seedLibrary();
      final violation = await h.entries.recordLocationPublishedAt(
        'no-such-location',
        DateTime.utc(2026, 3, 14),
      );
      expect(violation, unknownRow);
    });
  });

  group('placing from what a Source printed', () {
    test('places the Entry without claiming the user did', () async {
      final seeded = await h.seedLibrary();
      final (unplaced, _) = await h.entries.createInCollection(
        collectionId: seeded.collection.id,
        placement: Placement.unplaced,
      );

      final before = await h.outboxCount();
      final (placed, violation) = await h.entries.placeFromSource(
        unplaced!.id,
        102,
      );

      expect(violation, isNull);
      expect(placed!.ordinal, 102);
      expect(
        placed.placement,
        Placement.placed.name,
        reason: 'userPlaced is the user\'s own answer, and this is not it',
      );
      expect(await h.entries.unplacedOf(seeded.collection.id), isEmpty);

      expect(await h.outboxCount(), before + 1);
      final intent = (await h.outbox.pending(limit: 100)).last;
      expect((intent.entityKind, intent.entityId), ('entry', unplaced.id));
      expect(jsonDecode(intent.payload), {
        'ordinal': 102,
        'placement': 'placed',
      });
    });

    test('a taken position is the same refusal as creating there, and the '
        'Entry stays unplaced (I8)', () async {
      final seeded = await h.seedLibrary();
      final (unplaced, _) = await h.entries.createInCollection(
        collectionId: seeded.collection.id,
        placement: Placement.unplaced,
      );

      final before = await h.outboxCount();
      final (row, violation) = await h.entries.placeFromSource(
        unplaced!.id,
        101,
      );

      expect(row, isNull);
      expect(violation, duplicateOrdinal);
      final unchanged = await h.entries.byId(unplaced.id);
      expect(unchanged!.placement, Placement.unplaced.name);
      expect(unchanged.ordinal, isNull);
      expect(await h.outboxCount(), before, reason: 'nothing happened');
    });

    test('an unknown Entry is refused', () async {
      await h.seedLibrary();
      final (row, violation) = await h.entries.placeFromSource('nobody', 1);
      expect(row, isNull);
      expect(violation, unknownRow);
    });
  });

  test('one Source\'s Locations are one indexed read, however many Entries '
      'the Collection holds', () async {
    // One database at a time: the counted one replaces the shared harness,
    // which tearDown then closes.
    await h.close();
    final counter = CountingInterceptor();
    final counted = RepoHarness(
      executor: NativeDatabase.memory().interceptWith(counter),
    );
    h = counted;
    final seeded = await counted.seedLibrary();
    final (otherSource, _) = await counted.collections.addSource(
      collectionId: seeded.collection.id,
      host: 'mirror.example.test',
      pathKey: 'serial-alpha',
    );
    for (var n = 102; n < 108; n++) {
      final (entry, _) = await counted.entries.createInCollection(
        collectionId: seeded.collection.id,
        ordinal: n.toDouble(),
      );
      await counted.entries.addLocation(
        entryId: entry!.id,
        sourceId: seeded.source.id,
        url: 'https://reading.example.com/serial-alpha/part-$n',
        urlKey: 'https://reading.example.com/serial-alpha/part-$n',
        sourceNumber: n.toDouble(),
      );
      await counted.entries.addLocation(
        entryId: entry.id,
        sourceId: otherSource!.id,
        url: 'https://mirror.example.test/serial-alpha/part-$n',
        urlKey: 'https://mirror.example.test/serial-alpha/part-$n',
        sourceNumber: n.toDouble(),
      );
    }

    counter.selects = 0;
    final ofSource = await counted.entries.locationsOfSource(seeded.source.id);

    expect(counter.selects, 1, reason: 'one read on idx_locations_source');
    expect(ofSource, hasLength(7), reason: 'the seed and six more');
    expect(ofSource.map((l) => l.sourceId).toSet(), {
      seeded.source.id,
    }, reason: 'and never the mirror\'s');
    expect(
      ofSource.map((l) => l.discoveredAt).toList(),
      orderedEquals(ofSource.map((l) => l.discoveredAt).toList()..sort()),
      reason: 'in the order they were discovered',
    );
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
