/// Provisional-identity canonicalisation (G3): arbitration mappings,
/// natural-identity collision merges, and duplicate-pair repair. Local ids
/// are never rewritten; the canonical id is recorded beside them.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:web_reader/domain/collection.dart';
import 'package:web_reader/domain/sync_kinds.dart';
import 'package:web_reader/recognition/evidence.dart';

import 'support/sync_harness.dart';

void main() {
  late SyncHarness h;

  setUp(() async {
    h = await SyncHarness.start();
  });

  tearDown(() => h.stop());

  test('arbitration mappings record server ids beside local ids', () async {
    final root = await h.folders.ensureRoot();
    final (collection, _) = await h.collections.create(
      name: 'Quiet Harbour',
      folderId: root.id,
      orderingBasis: OrderingBasis.explicitNumericIndex,
    );
    final (entry, _) = await h.entries.createInCollection(
      collectionId: collection!.id,
      ordinal: 101,
    );

    h.backend.onArbitrate = (request) => {
      'outcome': 'resolved',
      'mappings': [
        {
          'kind': 'collection',
          'provisional_id': collection.id,
          'canonical_id': 'canonical-collection',
        },
        {
          'kind': 'entry',
          'provisional_id': entry!.id,
          'canonical_id': 'canonical-entry',
        },
      ],
    };

    final response = await h.engine.identity.arbitrate(
      h.transport,
      ArbitrationRequest(
        evidence: Evidence.ofUrl(
          url: 'https://reading.example/works/quiet-harbour/101',
          observedAt: DateTime.utc(2026, 8, 21, 10),
        ),
        provisional: ProvisionalIdentity(
          collectionId: collection.id,
          entryId: entry!.id,
        ),
      ),
    );

    expect(response.isResolved, isTrue);
    expect(
      (await h.collections.byId(collection.id))!.serverId,
      'canonical-collection',
    );
    expect((await h.entries.byId(entry.id))!.serverId, 'canonical-entry');

    // The drain now speaks canonical ids for these rows.
    await h.engine.syncOnce(h.transport);
    final ids = h.backend.mutationBatches
        .expand((batch) => batch)
        .map((e) => e['entity_id'])
        .toSet();
    expect(ids, containsAll(<String>{'canonical-collection'}));
    expect(ids, isNot(contains(collection.id)));
  });

  test('a provisional Source colliding with an incoming canonical one merges '
      'instead of duplicating', () async {
    // Offline: the user followed the work; the client minted everything.
    final root = await h.folders.ensureRoot();
    final (localCollection, _) = await h.collections.create(
      name: 'Quiet Harbour',
      folderId: root.id,
      orderingBasis: OrderingBasis.explicitNumericIndex,
    );
    final (localSource, _) = await h.collections.addSource(
      collectionId: localCollection!.id,
      host: 'reading.example',
      pathKey: '/works/quiet-harbour',
      language: 'en',
    );

    // Meanwhile the server already knows this Source canonically, under its
    // own ids, attached to its own Collection row.
    final at = DateTime.utc(2026, 8, 21, 9);
    h.backend.seed('folder', {
      'id': 'srv-root',
      'parent_id': null,
      'kind': 'root',
      'name': 'Library',
      'sort_key': 0,
    }, updatedAt: at);
    h.backend.seed('collection', {
      'id': 'srv-collection',
      'folder_id': 'srv-root',
      'name': 'Quiet Harbour',
      'detected_title': '',
      'ordering_basis': 'explicitNumericIndex',
      'lifecycle': 'active',
      'preferred_source_id': null,
      'sort_key': 0,
    }, updatedAt: at);
    h.backend.seed('source', {
      'id': 'srv-source',
      'collection_id': 'srv-collection',
      'host': 'reading.example',
      'path_key': '/works/quiet-harbour',
      'language': 'en',
      'lifecycle': 'active',
      'resolved_into_source_id': null,
      'first_seen_at': at.toIso8601String(),
      'last_seen_at': at.toIso8601String(),
    }, updatedAt: at);

    // Pull: the incoming Source must merge onto the provisional local row
    // — the local unique (host, path_key) index would refuse a duplicate.
    final outcome = await h.engine.syncOnce(h.transport);
    expect(outcome.succeeded, isTrue);
    expect(outcome.pulled!.errors, isEmpty);

    final sources = await h.collections.sourcesOf(localCollection.id);
    final all = [
      ...sources,
      ...await h.collections.sourcesOf('srv-collection'),
    ];
    expect(all, hasLength(1), reason: 'one Source row, never two');
    expect(all.single.id, localSource!.id, reason: 'local id is permanent');
    expect(all.single.serverId, 'srv-source');

    // Arbitration later maps the provisional Collection onto the server's;
    // the adopted server Collection row is the duplicate and merges away.
    await h.engine.identity.applyMappings([
      IdentityMapping(
        kind: IdentityKind.collection,
        provisionalId: localCollection.id,
        canonicalId: 'srv-collection',
      ),
    ]);
    final collections = [
      await h.collections.byId(localCollection.id),
      await h.collections.byId('srv-collection'),
    ].whereType<Object>().toList();
    expect(collections, hasLength(1), reason: 'duplicate merged away');
    final surviving = await h.collections.byId(localCollection.id);
    expect(surviving!.serverId, 'srv-collection');
    final rehomed = await h.collections.sourcesOf(localCollection.id);
    expect(rehomed, hasLength(1), reason: 'references rewritten');
  });

  test(
    'merging duplicate Entries moves reading state to the survivor',
    () async {
      final root = await h.folders.ensureRoot();
      final (collection, _) = await h.collections.create(
        name: 'Quiet Harbour',
        folderId: root.id,
        orderingBasis: OrderingBasis.explicitNumericIndex,
      );
      final (survivor, _) = await h.entries.createInCollection(
        collectionId: collection!.id,
        ordinal: 1,
      );
      final (duplicate, _) = await h.entries.createInCollection(
        collectionId: collection.id,
        ordinal: 2,
      );
      await h.readingStates.markRead(duplicate!.id);

      await h.engine.identity.mergeDuplicate(
        SyncedEntityKind.entry,
        survivor: survivor!.id,
        duplicate: duplicate.id,
      );

      expect(await h.entries.byId(duplicate.id), isNull);
      final state = await h.readingStates.stateOf(survivor.id);
      expect(state.status.name, 'completed');
    },
  );
}
