/// Standalone Entries and Folder organisation, end to end (I3, I5, V2-D21).
///
/// A standalone Entry is a first-class library item: it lives in a Folder, it
/// is never wrapped in a Collection of one, and it synchronises like anything
/// else. Deleting a Folder is organisation, not content: the children reparent
/// and every device has to end up agreeing about where they went.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:web_reader/domain/collection.dart';
import 'package:web_reader/recognition/recognise.dart';

import 'support/e2e_support.dart';

void main() {
  if (skipWithoutBackend()) return;

  late FixtureSite fixture;
  late String library;
  late E2EClient a;
  late E2EClient b;
  late RawApi raw;

  late String readingFolderId;
  late String standaloneEntryId;

  setUpAll(() async {
    fixture = await FixtureSite.start();
    library = uniqueLibrary('folders');
    a = E2EClient.start('A', library);
    b = E2EClient.start('B', library);
    raw = RawApi(library: library);
  });

  tearDownAll(() async {
    raw.close();
    await a.stop();
    await b.stop();
    fixture.expectNothingFetched('standalone entries and folders');
    await fixture.stop();
  });

  test(
    'a standalone Entry syncs, and nothing wraps it in a Collection',
    () async {
      final root = await a.folders.ensureRoot();
      final (folder, folderViolation) = await a.folders.create(
        'Reading',
        parentId: root.id,
      );
      expect(folderViolation, isNull);
      readingFolderId = folder!.id;

      final (entry, entryViolation) = await a.entries.createStandalone(
        folderId: readingFolderId,
        title: 'A single page worth keeping',
      );
      expect(entryViolation, isNull);
      standaloneEntryId = entry!.id;

      final keys = RecognitionKeys.of('${fixture.origin}/text/1');
      final (location, locationViolation) = await a.entries.addLocation(
        entryId: standaloneEntryId,
        url: '${fixture.origin}/text/1',
        urlKey: keys.urlKey,
      );
      expect(
        locationViolation,
        isNull,
        reason: 'a standalone Entry owns its Locations directly (I7)',
      );
      await a.readingStates.markRead(standaloneEntryId);
      await a.sync();
      await b.sync();

      final onServer = (await raw.entities('entry'))[standaloneEntryId]!;
      expect(onServer['collection_id'], isNull);
      expect(onServer['folder_id'], readingFolderId);
      expect(onServer['placement'], 'placed');
      expect(
        await raw.entities('collection'),
        isEmpty,
        reason: 'a standalone Entry is never wrapped in a Collection of one',
      );

      final onB = await b.entries.byId(standaloneEntryId);
      expect(onB, isNotNull);
      expect(onB!.collectionId, isNull);
      expect(onB.folderId, readingFolderId);
      expect(onB.title, 'A single page worth keeping');
      expect(
        (await b.db.select(b.db.collections).get()),
        isEmpty,
        reason: 'and nothing on the way created one either',
      );
      expect(
        (await b.entries.locationById(location!.id))!.sourceId,
        isNull,
        reason: 'I7: no Source, because there is no Collection',
      );
    },
  );

  test('deleting a Folder reparents its children and converges', () async {
    final (nested, nestedViolation) = await a.folders.create(
      'This year',
      parentId: readingFolderId,
    );
    expect(nestedViolation, isNull);
    final nestedId = nested!.id;

    final (leaf, leafViolation) = await a.folders.create(
      'January',
      parentId: nestedId,
    );
    expect(leafViolation, isNull);

    final (collection, collectionViolation) = await a.collections.create(
      name: 'Fixture multi-source work',
      folderId: nestedId,
      orderingBasis: OrderingBasis.explicitNumericIndex,
    );
    expect(collectionViolation, isNull);

    final (tenant, tenantViolation) = await a.entries.createStandalone(
      folderId: nestedId,
      title: 'A page filed under this year',
    );
    expect(tenantViolation, isNull);

    await a.sync();
    await b.sync();
    expect(await b.folders.byId(nestedId), isNotNull);
    expect((await b.entries.byId(tenant!.id))!.folderId, nestedId);
    expect((await b.collections.byId(collection!.id))!.folderId, nestedId);

    // Delete with reparent: one intent, and the service performs the same
    // reparent on its side (I5 — tidying organisation destroys no content).
    final (counts, deleteViolation) = await a.folders.deleteWithReparent(
      nestedId,
    );
    expect(deleteViolation, isNull);
    expect(counts!.folders, 1);
    expect(counts.collections, 1);
    expect(counts.entries, 1);
    await a.sync();

    expect(
      (await raw.entities('folder'))[nestedId],
      isNull,
      reason: 'the Folder is tombstoned centrally',
    );
    expect(
      (await raw.entities('folder'))[leaf!.id]!['parent_id'],
      readingFolderId,
      reason: 'the child Folder reparented to the deleted Folder parent',
    );
    expect(
      (await raw.entities('collection'))[collection.id]!['folder_id'],
      readingFolderId,
    );
    expect(
      (await raw.entities('entry'))[tenant.id]!['folder_id'],
      readingFolderId,
    );

    // Every device has to end up agreeing about where the children went.
    final pulled = await b.sync();
    expect(
      pulled.pulled!.errors,
      isEmpty,
      reason:
          'B could not apply the change feed: ${pulled.pulled!.errors.join('; ')}',
    );
    expect(
      await b.folders.byId(nestedId),
      isNull,
      reason: 'the deleted Folder is gone on the second client too',
    );
    expect((await b.folders.byId(leaf.id))!.parentId, readingFolderId);
    expect(
      (await b.collections.byId(collection.id))!.folderId,
      readingFolderId,
    );
    expect((await b.entries.byId(tenant.id))!.folderId, readingFolderId);
    expect(
      await b.entries.byId(standaloneEntryId),
      isNotNull,
      reason: 'deleting a Folder never deletes content (I5)',
    );
  });
}
