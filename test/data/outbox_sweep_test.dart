/// The C10 sweep: EVERY repository operation is enumerated here with the
/// exact number of outbox rows it must produce — one per synced-entity
/// mutation, zero for device state, evidence and the pull path.
///
/// A new repository operation that forgets (or double-writes) the outbox
/// fails this test, which is the point.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:web_reader/domain/collection.dart';
import 'package:web_reader/domain/download_request.dart';
import 'package:web_reader/domain/entry.dart';
import 'package:web_reader/domain/source.dart';

import 'support/repo_harness.dart';

void main() {
  late RepoHarness h;

  setUp(() => h = RepoHarness());
  tearDown(() => h.close());

  test('every repository operation produces exactly its outbox delta', () async {
    final seeded = await h.seedLibrary();

    Future<void> expectDelta(
      String operation,
      int expected,
      Future<Object?> Function() action,
    ) async {
      final before = await h.outboxCount();
      final result = await action();
      // Surface refusals loudly: a refused operation is a test-setup bug here.
      if (result is (Object?, Object?)) {
        expect(result.$2, isNull, reason: '$operation was refused');
      } else if (result != null && result is! int && result is! List<Object?>) {
        expect(result, isNull, reason: '$operation was refused');
      }
      final after = await h.outboxCount();
      expect(after - before, expected, reason: operation);
    }

    // ---- Folders: user organisation syncs. -------------------------------
    late String folderId;
    await expectDelta('folder create', 1, () async {
      final (f, v) = await h.folders.create('Weekly');
      folderId = f!.id;
      return v;
    });
    await expectDelta('folder rename', 1, () async {
      final (_, v) = await h.folders.rename(folderId, 'Weekly 2');
      return v;
    });
    late String subFolderId;
    await expectDelta('folder create nested', 1, () async {
      final (f, v) = await h.folders.create('Nested', parentId: folderId);
      subFolderId = f!.id;
      return v;
    });
    await expectDelta('folder move', 1, () async {
      return h.folders.move(subFolderId, seeded.root.id);
    });
    await expectDelta(
      'folder delete-with-reparent (one intent total)',
      1,
      () async {
        final (_, v) = await h.folders.deleteWithReparent(subFolderId);
        return v;
      },
    );
    await expectDelta('ensureRoot is not a mutation', 0, () async {
      await h.folders.ensureRoot();
      return null;
    });

    // ---- Collections and Sources. ----------------------------------------
    late String collectionId;
    await expectDelta('collection create', 1, () async {
      final (c, v) = await h.collections.create(
        name: 'Second work',
        folderId: seeded.root.id,
        orderingBasis: OrderingBasis.explicitNumericIndex,
      );
      collectionId = c!.id;
      return v;
    });
    await expectDelta('collection rename', 1, () {
      return h.collections.rename(collectionId, 'Second work, renamed');
    });
    await expectDelta('collection archive', 1, () {
      return h.collections.archive(collectionId);
    });
    await expectDelta('collection follow', 1, () {
      return h.collections.follow(collectionId);
    });
    await expectDelta('collection move to folder', 1, () {
      return h.collections.moveToFolder(collectionId, folderId);
    });
    late String sourceId;
    await expectDelta('source add', 1, () async {
      final (s, v) = await h.collections.addSource(
        collectionId: collectionId,
        host: 'texts.example.org',
        pathKey: 'second-work',
      );
      sourceId = s!.id;
      return v;
    });
    await expectDelta('preferred source set', 1, () {
      return h.collections.setPreferredSource(collectionId, sourceId);
    });
    await expectDelta('source lifecycle', 1, () {
      return h.collections.setSourceLifecycle(
        sourceId,
        SourceLifecycle.dormant,
      );
    });

    // ---- Entries and Locations. ------------------------------------------
    late String entryId;
    await expectDelta('entry create', 1, () async {
      final (e, v) = await h.entries.createInCollection(
        collectionId: collectionId,
        ordinal: 1,
      );
      entryId = e!.id;
      return v;
    });
    late String unplacedId;
    await expectDelta('entry create unplaced', 1, () async {
      final (e, v) = await h.entries.createInCollection(
        collectionId: collectionId,
        placement: Placement.unplaced,
      );
      unplacedId = e!.id;
      return v;
    });
    await expectDelta('entry place', 1, () async {
      final (_, v) = await h.entries.placeEntry(unplacedId, 2);
      return v;
    });
    late String locationId;
    await expectDelta('location add', 1, () async {
      final (l, v) = await h.entries.addLocation(
        entryId: entryId,
        sourceId: sourceId,
        url: 'https://texts.example.org/second-work/1',
        urlKey: 'https://texts.example.org/second-work/1',
      );
      locationId = l!.id;
      return v;
    });
    await expectDelta('location retraction is evidence, not a mutation', 0, () {
      return h.entries.retractLocation(locationId, readingSourceId: sourceId);
    });
    await expectDelta('location remove by hand', 1, () {
      return h.entries.removeLocationByHand(locationId);
    });
    await expectDelta('entry remove', 1, () {
      return h.entries.removeEntry(unplacedId);
    });

    // ---- Reading state and measurements. ---------------------------------
    await expectDelta('reading recordSourceAccess', 1, () async {
      final (_, v) = await h.reading.recordSourceAccess(entryId);
      return v;
    });
    await expectDelta('reading markRead', 1, () async {
      final (_, v) = await h.reading.markRead(entryId);
      return v;
    });
    await expectDelta('reading markUnread', 1, () async {
      final (_, v) = await h.reading.markUnread(entryId);
      return v;
    });
    await expectDelta('measurement put', 1, () async {
      final (_, v) = await h.measurements.put(
        entryId: entryId,
        sourceId: sourceId,
        fraction: 0.5,
      );
      return v;
    });

    // ---- Device state: never. --------------------------------------------
    await expectDelta('offline copy record', 0, () async {
      await h.offline.recordCopy(
        entryId: entryId,
        locationUrl: 'https://texts.example.org/second-work/1',
        artifactFormat: 'document',
        contentPath: 'library/x',
        byteSize: 1,
      );
      return null;
    });
    await expectDelta('offline anchor save', 0, () async {
      await h.offline.saveAnchor(entryId, anchorIndex: 1, anchorOffset: 0.5);
      return null;
    });
    await expectDelta('offline copies remove', 0, () async {
      await h.offline.removeCopies(entryId);
      return null;
    });

    // ---- Download requests. ----------------------------------------------
    await expectDelta('download request applyRemote', 0, () async {
      await h.requests.applyRemote(
        id: 'req-1',
        serverId: 'req-1',
        entryId: entryId,
        locationId: null,
        state: DownloadRequestState.pending.name,
        idempotencyKey: 'k',
        createdBy: 'extension',
        createdAt: DateTime.utc(2026, 8, 21),
        claimedByDevice: '',
        claimedAt: null,
        resolvedAt: null,
        failureReason: '',
        revision: 1,
      );
      return null;
    });
    await expectDelta(
      'download request local claim (server already knows)',
      0,
      () {
        return h.requests.recordLocalClaim(
          'req-1',
          device: 'phone-dev-a',
          localSaveTaskId: 'task-1',
        );
      },
    );
    await expectDelta('download request resolve (the one report)', 1, () {
      return h.requests.resolveLocally(
        'req-1',
        to: DownloadRequestState.completed,
      );
    });

    // ---- The pull path: never. -------------------------------------------
    await expectDelta('applyRemote folder', 0, () async {
      await h.folders.applyRemote(
        id: 'rf-1',
        serverId: 'rf-1',
        parentId: seeded.root.id,
        kind: 'user',
        name: 'Pulled',
        sortKey: 0,
        revision: 9,
        updatedAt: DateTime.utc(2026, 8, 21),
      );
      return null;
    });
    await expectDelta('applyRemote reading state', 0, () async {
      await h.reading.applyRemote(
        entryId: entryId,
        status: 'reading',
        firstOpenedAt: DateTime.utc(2026, 8, 21),
        lastReadAt: DateTime.utc(2026, 8, 21),
        completedAt: null,
        revision: 10,
        updatedAt: DateTime.utc(2026, 8, 21),
      );
      return null;
    });
  });
}
