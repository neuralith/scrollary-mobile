/// The removal-semantics table of V2_SYNC.md §5, proven locally: every
/// removal's blast radius is exactly what the product promises, and no
/// library operation reaches bytes (I14 at the row layer).
library;

import 'package:flutter_test/flutter_test.dart';

import 'support/repo_harness.dart';

void main() {
  late RepoHarness h;

  setUp(() => h = RepoHarness());
  tearDown(() => h.close());

  test('remove an Entry: rows go, the offline copy row stays', () async {
    final seeded = await h.seedLibrary();
    await h.offline.recordCopy(
      entryId: seeded.entry.id,
      locationUrl: seeded.location.url,
      artifactFormat: 'imageSequence',
      contentPath: 'library/a',
      byteSize: 100,
    );

    expect(await h.entries.removeEntry(seeded.entry.id), isNull);

    expect(await h.entries.byId(seeded.entry.id), isNull);
    expect(await h.entries.locationById(seeded.location.id), isNull);
    final copies = await h.offline.allCopies();
    expect(copies, hasLength(1), reason: 'bytes are kept (I14)');
    expect(
      copies.single.locationUrl,
      seeded.location.url,
      reason: 'the copy still says where it came from',
    );
  });

  test('remove a Collection: same rule, all the way down', () async {
    final seeded = await h.seedLibrary();
    await h.reading.markRead(seeded.entry.id);
    await h.offline.recordCopy(
      entryId: seeded.entry.id,
      locationUrl: seeded.location.url,
      artifactFormat: 'document',
      contentPath: 'library/b',
      byteSize: 7,
    );

    expect(await h.collections.removeCollection(seeded.collection.id), isNull);

    expect(await h.collections.byId(seeded.collection.id), isNull);
    expect(await h.collections.sourcesOf(seeded.collection.id), isEmpty);
    expect(await h.entries.byId(seeded.entry.id), isNull);
    expect(await h.offline.allCopies(), hasLength(1));
  });

  test('archive is not removal: everything survives, reversibly', () async {
    final seeded = await h.seedLibrary();
    expect(await h.collections.archive(seeded.collection.id), isNull);

    expect(await h.collections.byId(seeded.collection.id), isNotNull);
    expect(await h.entries.byId(seeded.entry.id), isNotNull);
    expect(await h.entries.locationById(seeded.location.id), isNotNull);
    expect((await h.collections.sourcesOf(seeded.collection.id)), hasLength(1));

    expect(await h.collections.follow(seeded.collection.id), isNull);
    expect(
      (await h.collections.byId(seeded.collection.id))!.lifecycle,
      'active',
    );
  });

  test(
    'delete a Folder: children reparent, nothing content-like goes',
    () async {
      final root = await h.folders.ensureRoot();
      final (folder, _) = await h.folders.create('Doomed');
      final seeded = await h.seedLibrary();
      await h.collections.moveToFolder(seeded.collection.id, folder!.id);
      final (standalone, _) = await h.entries.createStandalone(
        folderId: folder.id,
      );

      final (counts, violation) = await h.folders.deleteWithReparent(folder.id);
      expect(violation, isNull);
      expect(counts!.collections, 1);
      expect(counts.entries, 1);

      expect(
        (await h.collections.byId(seeded.collection.id))!.folderId,
        root.id,
      );
      expect((await h.entries.byId(standalone!.id))!.folderId, root.id);
      expect(await h.entries.byId(seeded.entry.id), isNotNull);
    },
  );

  test('source-scoped retraction changes evidence, not membership, and does '
      'not sync', () async {
    final seeded = await h.seedLibrary();
    final before = await h.outboxCount();

    expect(
      await h.entries.retractLocation(
        seeded.location.id,
        readingSourceId: seeded.source.id,
      ),
      isNull,
    );

    expect(await h.outboxCount(), before);
    expect(
      await h.entries.byId(seeded.entry.id),
      isNotNull,
      reason: 'the Entry is untouched',
    );
    expect(
      (await h.entries.locationById(seeded.location.id))!.lifecycle,
      'retracted',
      reason: 'the listing fact is recorded',
    );
  });
}
