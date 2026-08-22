/// The pull half, when the feed does not arrive in referential order (G2).
///
/// The change feed carries each row ONCE, at the revision it currently holds.
/// A Collection renamed after its Entries were placed therefore sorts *behind*
/// its own children, and a client bootstrapping from zero meets the children
/// first. Every such row must be held and retried, never counted as applied
/// and never left behind a cursor that moved past it.
library;

import 'package:flutter_test/flutter_test.dart';

import 'support/sync_harness.dart';

void main() {
  late SyncHarness h;

  /// The server rows, at the clock every seeded row starts on.
  final createdAt = DateTime.utc(2026, 8, 21, 9);

  /// The clock a later edit — a rename, a preferred Source — is stamped with.
  final editedAt = DateTime.utc(2026, 8, 21, 11);

  setUp(() async {
    h = await SyncHarness.start();
    // A local root older than anything the server holds, so the incoming root
    // row wins the merge and the count of applied rows is the whole feed.
    h.clockValue = DateTime.utc(2020);
    await h.folders.ensureRoot();
  });

  tearDown(() => h.stop());

  /// Seeds one row of every kind in referential order, then edits each parent
  /// so it moves *behind* its own children on the feed. The result exercises
  /// every parent reference the puller knows:
  ///
  /// | waiting row     | on                              |
  /// |-----------------|---------------------------------|
  /// | folder (user)   | its parent Folder               |
  /// | collection      | its Folder                      |
  /// | source          | its Collection                  |
  /// | entry           | its Collection                  |
  /// | location        | its Entry, and its Source       |
  /// | readingState    | its Entry                       |
  /// | measurement     | its Entry, and its Source       |
  /// | downloadRequest | its Entry, and its Location     |
  ///
  /// and, on the Collection, the one reference that points back *into* its own
  /// subtree: `preferred_source_id`.
  void seedFeedWithParentsLast() {
    h.backend.seed('folder', {
      'id': 'srv-root',
      'parent_id': null,
      'kind': 'root',
      'name': 'Library',
      'sort_key': 0,
    }, updatedAt: createdAt);
    h.backend.seed('folder', {
      'id': 'srv-folder',
      'parent_id': 'srv-root',
      'kind': 'user',
      'name': 'Weekly',
      'sort_key': 0,
    }, updatedAt: createdAt);
    h.backend.seed('collection', {
      'id': 'srv-collection',
      'folder_id': 'srv-folder',
      'name': 'Quiet Harbour',
      'detected_title': 'Quiet Harbour',
      'ordering_basis': 'explicitNumericIndex',
      'lifecycle': 'active',
      'preferred_source_id': null,
      'sort_key': 0,
    }, updatedAt: createdAt);
    h.backend.seed('source', {
      'id': 'srv-source',
      'collection_id': 'srv-collection',
      'host': 'reading.example',
      'path_key': '/works/quiet-harbour',
      'language': 'en',
      'lifecycle': 'active',
      'resolved_into_source_id': null,
      'first_seen_at': createdAt.toIso8601String(),
      'last_seen_at': createdAt.toIso8601String(),
    }, updatedAt: createdAt);
    h.backend.seed('entry', {
      'id': 'srv-entry',
      'collection_id': 'srv-collection',
      'folder_id': null,
      'ordinal': 101,
      'placement': 'placed',
      'title': 'Part 101',
      'sort_key': 0,
    }, updatedAt: createdAt);
    h.backend.seed('location', {
      'id': 'srv-location',
      'entry_id': 'srv-entry',
      'source_id': 'srv-source',
      'url': 'https://reading.example/works/quiet-harbour/101',
      'url_key': 'https://reading.example/works/quiet-harbour/101',
      'source_label': 'Part 101',
      'source_number': 101,
      'discovered_at': createdAt.toIso8601String(),
      'discovery_basis': 'listing',
      'lifecycle': 'active',
    }, updatedAt: createdAt);
    h.backend.seed('readingState', {
      'entry_id': 'srv-entry',
      'status': 'reading',
      'first_opened_at': createdAt.toIso8601String(),
      'last_read_at': createdAt.toIso8601String(),
      'completed_at': null,
    }, updatedAt: createdAt);
    h.backend.seed('measurement', {
      'entry_id': 'srv-entry',
      'source_id': 'srv-source',
      'fraction': 0.4,
      'observed_at': createdAt.toIso8601String(),
    }, key: 'srv-entry|srv-source');
    h.backend.seed('downloadRequest', {
      'id': 'srv-request',
      'entry_id': 'srv-entry',
      'location_id': 'srv-location',
      'state': 'pending',
      'idempotency_key': 'key-srv-request',
      'created_by': 'extension',
      'created_at': createdAt.toIso8601String(),
      'claimed_by_device': '',
      'claimed_at': null,
      'resolved_at': null,
      'failure_reason': '',
    });

    // Now the parents change — and each one moves to the end of the feed,
    // behind everything that references it.
    h.backend.touch(
      'collection',
      'srv-collection',
      updatedAt: editedAt,
      fields: {
        'name': 'Quiet Harbour, renamed',
        'preferred_source_id': 'srv-source',
      },
    );
    h.backend.touch(
      'folder',
      'srv-folder',
      updatedAt: editedAt,
      fields: {'name': 'Weekly, renamed'},
    );
    h.backend.touch('folder', 'srv-root', updatedAt: editedAt);
  }

  /// The entity kinds on the feed, in the order the client will meet them.
  List<String> feedOrder() => [
    for (final change in h.backend.feed)
      if (change['type'] == 'entity') change['entity_type']! as String,
  ];

  /// Everything the seeded library must hold once the run converges.
  Future<void> expectWholeLibrary() async {
    final root = await h.folders.ensureRoot();
    expect(root.serverId, 'srv-root');

    final folder = await h.folders.byId('srv-folder');
    expect(folder!.parentId, root.id, reason: 'the Folder found its parent');
    expect(folder.name, 'Weekly, renamed');

    final collection = await h.collections.byId('srv-collection');
    expect(collection!.folderId, 'srv-folder');
    expect(collection.name, 'Quiet Harbour, renamed');
    expect(
      collection.preferredSourceId,
      'srv-source',
      reason: 'the pointer back into its own subtree was filled in',
    );

    final sources = await h.collections.sourcesOf('srv-collection');
    expect(sources.map((s) => s.id), ['srv-source']);

    final entries = await h.entries.entriesOf('srv-collection');
    expect(entries.map((e) => e.id), ['srv-entry']);

    final locations = await h.entries.locationsOf('srv-entry');
    expect(locations, hasLength(1));
    expect(locations.single.id, 'srv-location');
    expect(locations.single.sourceId, 'srv-source');

    expect((await h.readingStates.stateOf('srv-entry')).status.name, 'reading');
    expect((await h.measurements.of('srv-entry', 'srv-source'))!.fraction, 0.4);

    final request = await h.downloadRequests.byId('srv-request');
    expect(request!.entryId, 'srv-entry');
    expect(request.locationId, 'srv-location');
  }

  test(
    'a feed whose parents all sort behind their children lands whole',
    () async {
      seedFeedWithParentsLast();
      final order = feedOrder();
      expect(
        order.indexOf('collection'),
        greaterThan(order.indexOf('entry')),
        reason: 'this feed is in the shape the case is about',
      );
      expect(order.indexOf('folder'), greaterThan(order.indexOf('collection')));

      final outcome = await h.engine.syncOnce(h.transport);
      expect(outcome.succeeded, isTrue);
      final pulled = outcome.pulled!;
      expect(pulled.errors, isEmpty);
      expect(
        pulled.skipped,
        0,
        reason: 'nothing was dropped for arriving early',
      );
      expect(pulled.orphaned, 0);
      expect(pulled.orphanedKinds, isEmpty);
      expect(pulled.applied, order.length, reason: 'every row, counted once');

      await expectWholeLibrary();
      expect(await h.syncState.cursor(), h.backend.revision);
    },
  );

  test('the same feed converges when it is paged two rows at a time', () async {
    seedFeedWithParentsLast();

    final outcome = await h.engine.syncOnce(h.transport, pullLimit: 2);
    expect(outcome.succeeded, isTrue);
    final pulled = outcome.pulled!;
    expect(pulled.pages, greaterThan(1));
    expect(pulled.errors, isEmpty);
    expect(pulled.skipped, 0);
    expect(pulled.orphaned, 0);

    await expectWholeLibrary();
    expect(await h.syncState.cursor(), h.backend.revision);
  });

  test(
    'a run cut off while rows are deferred pins the cursor below them',
    () async {
      seedFeedWithParentsLast();
      final firstDeferred = h.backend.feed.first['revision']! as int;

      // Page one is nothing but children: everything it carries is held back.
      h.backend.dieOnChangesRequest = 2;
      final killed = await h.engine.syncOnce(h.transport, pullLimit: 2);
      expect(killed.succeeded, isFalse);

      expect(
        await h.syncState.cursor(),
        firstDeferred - 1,
        reason: 'the cursor never moves past a row that has not been applied',
      );
      expect(await h.entries.byId('srv-entry'), isNull);

      // The next opportunity is offered those rows again, and converges.
      h.backend.dieOnChangesRequest = 0;
      final resumed = await h.engine.syncOnce(h.transport, pullLimit: 2);
      expect(resumed.succeeded, isTrue);
      expect(resumed.pulled!.errors, isEmpty);
      expect(resumed.pulled!.skipped, 0);
      expect(resumed.pulled!.orphaned, 0);

      await expectWholeLibrary();
      expect(await h.syncState.cursor(), h.backend.revision);
    },
    timeout: const Timeout(Duration(minutes: 1)),
  );

  test(
    'a child whose parent is nowhere in the feed is dropped and reported',
    () async {
      h.backend.seed('folder', {
        'id': 'srv-root',
        'parent_id': null,
        'kind': 'root',
        'name': 'Library',
        'sort_key': 0,
      }, updatedAt: createdAt);
      h.backend.seed('entry', {
        'id': 'ghost-entry',
        'collection_id': 'ghost-collection',
        'folder_id': null,
        'ordinal': 1,
        'placement': 'placed',
        'title': 'Orphan',
        'sort_key': 0,
      }, updatedAt: createdAt);
      h.backend.seed('location', {
        'id': 'ghost-location',
        'entry_id': 'ghost-entry',
        'source_id': null,
        'url': 'https://reading.example/ghost/1',
        'url_key': 'https://reading.example/ghost/1',
        'source_label': 'Orphan',
        'source_number': 1,
        'discovered_at': createdAt.toIso8601String(),
        'discovery_basis': 'listing',
        'lifecycle': 'active',
      }, updatedAt: createdAt);

      final outcome = await h.engine.syncOnce(h.transport);
      expect(outcome.succeeded, isTrue);
      final pulled = outcome.pulled!;
      expect(
        pulled.errors,
        isEmpty,
        reason: 'an orphan is reported, not thrown',
      );
      expect(pulled.orphaned, 2);
      expect(pulled.orphanedKinds, {'entry': 1, 'location': 1});

      expect(await h.entries.byId('ghost-entry'), isNull);
      expect(await h.entries.locationById('ghost-location'), isNull);
      expect(
        await h.syncState.cursor(),
        h.backend.revision,
        reason: 'a dead row must not pin the cursor forever',
      );

      // And the run after it has nothing left to do.
      final again = await h.engine.syncOnce(h.transport);
      expect(again.pulled!.orphaned, 0);
      expect(again.pulled!.errors, isEmpty);
    },
  );

  test(
    'a tombstone for a parent takes its deferred children with it',
    () async {
      h.backend.seed('folder', {
        'id': 'srv-root',
        'parent_id': null,
        'kind': 'root',
        'name': 'Library',
        'sort_key': 0,
      }, updatedAt: createdAt);
      h.backend.seed('collection', {
        'id': 'srv-collection',
        'folder_id': 'srv-root',
        'name': 'Quiet Harbour',
        'detected_title': 'Quiet Harbour',
        'ordering_basis': 'explicitNumericIndex',
        'lifecycle': 'active',
        'preferred_source_id': null,
        'sort_key': 0,
      }, updatedAt: createdAt);
      h.backend.seed('entry', {
        'id': 'srv-entry',
        'collection_id': 'srv-collection',
        'folder_id': null,
        'ordinal': 101,
        'placement': 'placed',
        'title': 'Part 101',
        'sort_key': 0,
      }, updatedAt: createdAt);
      h.backend.seed('location', {
        'id': 'srv-location',
        'entry_id': 'srv-entry',
        'source_id': null,
        'url': 'https://reading.example/works/quiet-harbour/101',
        'url_key': 'https://reading.example/works/quiet-harbour/101',
        'source_label': 'Part 101',
        'source_number': 101,
        'discovered_at': createdAt.toIso8601String(),
        'discovery_basis': 'listing',
        'lifecycle': 'active',
      }, updatedAt: createdAt);
      // The Collection is renamed — moving behind its children — and then
      // removed, so the feed offers the children and never the parent.
      h.backend.touch('collection', 'srv-collection', updatedAt: editedAt);
      h.backend.seedTombstone(
        'collection',
        'srv-collection',
        deletedAt: DateTime.utc(2026, 8, 21, 12),
      );
      expect(
        feedOrder(),
        ['folder', 'entry', 'location'],
        reason: 'the parent left the feed; its children are still on it',
      );

      final outcome = await h.engine.syncOnce(h.transport);
      expect(outcome.succeeded, isTrue);
      final pulled = outcome.pulled!;
      expect(pulled.errors, isEmpty, reason: 'a dead parent is not an error');
      expect(
        pulled.skipped,
        1,
        reason: 'the tombstone itself: nothing to delete',
      );
      expect(pulled.orphaned, 2);
      expect(pulled.orphanedKinds, {'entry': 1, 'location': 1});

      expect(await h.collections.byId('srv-collection'), isNull);
      expect(await h.entries.byId('srv-entry'), isNull);
      expect(await h.entries.locationById('srv-location'), isNull);
      expect(await h.syncState.cursor(), h.backend.revision);
    },
  );
}
