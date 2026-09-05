/// OfflineCopy repository (C8): device state with provenance as values, one
/// active copy per Entry, and no path to the outbox at all (I11).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:web_reader/data/schema.dart';

import 'support/repo_harness.dart';

void main() {
  late RepoHarness h;

  setUp(() => h = RepoHarness());
  tearDown(() => h.close());

  test('one active copy per Entry: a replacement deactivates its predecessor '
      'in the same transaction (I13)', () async {
    final seeded = await h.seedLibrary();
    final first = await h.offline.recordCopy(
      entryId: seeded.entry.id,
      locationUrl: seeded.location.url,
      artifactFormat: 'imageSequence',
      contentPath: 'library/a',
      byteSize: 10,
    );
    final second = await h.offline.recordCopy(
      entryId: seeded.entry.id,
      locationUrl: seeded.location.url,
      artifactFormat: 'document',
      contentPath: 'library/b',
      byteSize: 20,
    );

    final active = await h.offline.activeCopyOf(seeded.entry.id);
    expect(active!.id, second.id);
    final all = await h.offline.allCopies();
    expect(all, hasLength(2));
    expect(all.where((c) => c.active), hasLength(1));
    expect(first.id, isNot(second.id));
  });

  test(
    'provenance is values and survives the whole library being deleted',
    () async {
      final seeded = await h.seedLibrary();
      await h.offline.recordCopy(
        entryId: seeded.entry.id,
        locationUrl: seeded.location.url,
        sourceName: 'Serial Alpha',
        sourceHost: 'reading.example.com',
        sourceLanguage: 'en',
        artifactFormat: 'imageSequence',
        contentPath: 'library/a',
        byteSize: 10,
      );

      // Remove the collection — sources, entries and locations cascade away.
      await h.collections.removeCollection(seeded.collection.id);
      expect(await h.entries.byId(seeded.entry.id), isNull);

      // The copy row still names what it holds, from its own values.
      final copies = await h.offline.allCopies();
      expect(copies, hasLength(1));
      final copy = copies.single;
      expect(copy.sourceName, 'Serial Alpha');
      expect(copy.sourceHost, 'reading.example.com');
      expect(copy.locationUrl, seeded.location.url);
    },
  );

  test('the anchor lives on the copy and nowhere else', () async {
    final seeded = await h.seedLibrary();
    await h.offline.recordCopy(
      entryId: seeded.entry.id,
      locationUrl: seeded.location.url,
      artifactFormat: 'document',
      contentPath: 'library/a',
      byteSize: 10,
    );
    await h.offline.saveAnchor(
      seeded.entry.id,
      anchorIndex: 12,
      anchorOffset: 0.4,
    );
    final copy = await h.offline.activeCopyOf(seeded.entry.id);
    expect((copy!.anchorIndex, copy.anchorOffset), (12, 0.4));
  });

  test('saving the anchor records when the reading happened', () async {
    final seeded = await h.seedLibrary();
    await h.offline.recordCopy(
      entryId: seeded.entry.id,
      locationUrl: seeded.location.url,
      artifactFormat: 'document',
      contentPath: 'library/a',
      byteSize: 10,
    );
    // A recorded copy is bytes and nothing else: downloading an Entry is not
    // reading it, so there is no reading time to have.
    expect(
      (await h.offline.activeCopyOf(seeded.entry.id))!.anchorUpdatedAt,
      isNull,
    );

    await h.offline.saveAnchor(
      seeded.entry.id,
      anchorIndex: 3,
      anchorOffset: 0.25,
      at: DateTime.utc(2026, 7, 20),
    );
    expect(
      (await h.offline.activeCopyOf(seeded.entry.id))!.anchorUpdatedAt,
      DateTime.utc(2026, 7, 20),
    );

    // It follows the reading rather than latching: moving on writes the newer
    // time, which is what makes it usable as a clock.
    await h.offline.saveAnchor(
      seeded.entry.id,
      anchorIndex: 9,
      anchorOffset: 0.1,
      at: DateTime.utc(2026, 7, 25),
    );
    expect(
      (await h.offline.activeCopyOf(seeded.entry.id))!.anchorUpdatedAt,
      DateTime.utc(2026, 7, 25),
    );
  });

  test('no OfflineCopy operation ever writes the outbox, and the outbox '
      'cannot even spell the kind (I11)', () async {
    final seeded = await h.seedLibrary();
    final before = await h.outboxCount();
    await h.offline.recordCopy(
      entryId: seeded.entry.id,
      locationUrl: seeded.location.url,
      artifactFormat: 'document',
      contentPath: 'library/a',
      byteSize: 10,
    );
    await h.offline.saveAnchor(
      seeded.entry.id,
      anchorIndex: 1,
      anchorOffset: 0.1,
    );
    await h.offline.removeCopies(seeded.entry.id);
    expect(await h.outboxCount(), before);

    // The CHECK refuses the spelling even if a caller bypassed every guard.
    expect(
      () => h.db
          .into(h.db.outbox)
          .insert(
            OutboxCompanion.insert(
              mutationId: 'm-1',
              entityKind: 'offlineCopy',
              entityId: 'x',
              op: 'upsert',
              payload: '{}',
              createdAt: DateTime.utc(2026),
            ),
          ),
      throwsException,
    );
  });

  test('removing copies frees this device\'s record only', () async {
    final seeded = await h.seedLibrary();
    await h.offline.recordCopy(
      entryId: seeded.entry.id,
      locationUrl: seeded.location.url,
      artifactFormat: 'document',
      contentPath: 'library/a',
      byteSize: 10,
    );
    final removed = await h.offline.removeCopies(seeded.entry.id);
    expect(removed, 1);
    expect(await h.offline.activeCopyOf(seeded.entry.id), isNull);
    // The Entry itself is untouched: removing a download never removes the
    // Entry.
    expect(await h.entries.byId(seeded.entry.id), isNotNull);
  });
}
