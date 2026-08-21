/// The drain (G1): ordered delivery, idempotent retry, parked rejections,
/// id translation, and download-request resolve routing.
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:web_reader/data/schema.dart';
import 'package:web_reader/domain/collection.dart';
import 'package:web_reader/domain/download_request.dart';

import 'support/sync_harness.dart';

void main() {
  late SyncHarness h;

  setUp(() async {
    h = await SyncHarness.start();
  });

  tearDown(() => h.stop());

  Future<String> makeCollection() async {
    final root = await h.folders.ensureRoot();
    final (collection, violation) = await h.collections.create(
      name: 'Quiet Harbour',
      folderId: root.id,
      orderingBasis: OrderingBasis.explicitNumericIndex,
    );
    expect(violation, isNull);
    return collection!.id;
  }

  test('offline mutations drain in order, land, and acknowledge', () async {
    final collectionId = await makeCollection();
    final (entry, _) = await h.entries.createInCollection(
      collectionId: collectionId,
      ordinal: 1,
    );
    await h.readingStates.markRead(entry!.id);
    expect(await h.outbox.pendingCount(), 3);

    final outcome = await h.engine.syncOnce(h.transport);

    expect(outcome.succeeded, isTrue);
    expect(await h.outbox.pendingCount(), 0);
    // Client-minted ids ARE the wire ids when nothing was merged.
    expect(h.backend.kindRows('collection'), contains(collectionId));
    expect(h.backend.kindRows('entry'), contains(entry.id));
    expect(h.backend.kindRows('readingState'), contains(entry.id));
  });

  test('reading-state pushes carry the whole four-field state', () async {
    final collectionId = await makeCollection();
    final (entry, _) = await h.entries.createInCollection(
      collectionId: collectionId,
      ordinal: 1,
    );
    await h.readingStates.markRead(entry!.id);
    await h.engine.syncOnce(h.transport);

    final envelope = h.backend.mutationBatches
        .expand((batch) => batch)
        .singleWhere((e) => e['entity_type'] == 'readingState');
    final fields = Map<String, Object?>.from(envelope['fields']! as Map);
    expect(
      fields.keys,
      containsAll(<String>{
        'status',
        'first_opened_at',
        'last_read_at',
        'completed_at',
      }),
    );
    expect(fields['status'], 'completed');
  });

  test('a retried batch after a server failure applies exactly once', () async {
    await makeCollection();
    h.backend.failMutationsTimes = 1;

    final first = await h.engine.syncOnce(h.transport);
    expect(first.succeeded, isFalse);
    expect(await h.outbox.pendingCount(), 1); // kept, attempt recorded

    final second = await h.engine.syncOnce(h.transport);
    expect(second.succeeded, isTrue);
    expect(await h.outbox.pendingCount(), 0);
    expect(h.backend.kindRows('collection').length, 1);
  });

  test('a duplicate mutation id produces one effect and still acks', () async {
    final collectionId = await makeCollection();
    await h.engine.syncOnce(h.transport);
    final feedBefore = h.backend.feed.length;

    // A lost ack: the same mutation id re-enters the outbox and is resent.
    final envelope = h.backend.mutationBatches.first.single;
    await h.db
        .into(h.db.outbox)
        .insert(
          OutboxCompanion.insert(
            mutationId: envelope['mutation_id']! as String,
            entityKind: 'collection',
            entityId: collectionId,
            op: 'upsert',
            payload: jsonEncode(envelope['fields']),
            createdAt: DateTime.now().toUtc(),
          ),
        );

    final outcome = await h.engine.syncOnce(h.transport);
    expect(outcome.succeeded, isTrue);
    expect(await h.outbox.pendingCount(), 0);
    expect(h.backend.feed.length, feedBefore); // ledger: no second effect
  });

  test(
    'a rejected row parks with its named reason; the queue continues',
    () async {
      final root = await h.folders.ensureRoot();
      await h.db
          .into(h.db.outbox)
          .insert(
            OutboxCompanion.insert(
              mutationId: 'poisoned-mutation',
              entityKind: 'folder',
              entityId: 'poisoned-folder',
              op: 'upsert',
              payload: jsonEncode({
                'parent_id': root.id,
                'kind': 'user',
                'name': 'Poison',
                'sort_key': 0,
                'reject_me': true,
              }),
              createdAt: DateTime.now().toUtc(),
            ),
          );
      final (folder, _) = await h.folders.create('After the poison');

      final outcome = await h.engine.syncOnce(h.transport);
      expect(outcome.succeeded, isTrue);
      // The later intent still landed.
      expect(h.backend.kindRows('folder'), contains(folder!.id));
      // The rejection is parked and named, and excluded from future drains.
      final rejected = await h.outbox.rejected();
      expect(rejected, hasLength(1));
      expect(rejected.single.lastError, 'rejected:invariant_violation');
      expect(await h.outbox.pendingAfter(0), isEmpty);
      final status = await h.engine.status();
      expect(status.rejectedCount, 1);
      expect(status.pendingCount, 0);
    },
  );

  test(
    'measurement envelopes translate the entry id and the source scope',
    () async {
      final collectionId = await makeCollection();
      final (source, _) = await h.collections.addSource(
        collectionId: collectionId,
        host: 'reading.example',
        pathKey: '/works/quiet-harbour',
      );
      final (entry, _) = await h.entries.createInCollection(
        collectionId: collectionId,
        ordinal: 1,
      );
      // These rows were merged into canonical identity earlier.
      await h.entries.applyEntryServerId(entry!.id, 'server-entry');
      await h.collections.applySourceServerId(source!.id, 'server-source');
      await h.measurements.put(
        entryId: entry.id,
        sourceId: source.id,
        fraction: 0.5,
      );

      await h.engine.syncOnce(h.transport);

      final envelope = h.backend.mutationBatches
          .expand((batch) => batch)
          .singleWhere((e) => e['entity_type'] == 'measurement');
      expect(envelope['entity_id'], 'server-entry');
      final fields = Map<String, Object?>.from(envelope['fields']! as Map);
      expect(fields['source_id'], 'server-source');
    },
  );

  test(
    'download-request resolutions route to /resolve, never /mutations',
    () async {
      final collectionId = await makeCollection();
      final (entry, _) = await h.entries.createInCollection(
        collectionId: collectionId,
        ordinal: 1,
      );
      // The intent exists on the server (created by another client) and was
      // mirrored here by a pull; this device claimed it synchronously.
      h.backend.seed('downloadRequest', {
        'id': 'request-1',
        'entry_id': entry!.id,
        'location_id': null,
        'state': 'claimed',
        'idempotency_key': 'k',
        'created_by': 'extension',
        'created_at': DateTime.now().toUtc().toIso8601String(),
        'claimed_by_device': 'this-device',
        'claimed_at': DateTime.now().toUtc().toIso8601String(),
        'resolved_at': null,
        'failure_reason': '',
      });
      await h.downloadRequests.applyRemote(
        id: 'request-1',
        serverId: 'request-1',
        entryId: entry.id,
        locationId: null,
        state: 'claimed',
        idempotencyKey: 'k',
        createdBy: 'extension',
        createdAt: DateTime.now().toUtc(),
        claimedByDevice: 'this-device',
        claimedAt: DateTime.now().toUtc(),
        resolvedAt: null,
        failureReason: '',
        revision: 1,
      );
      await h.downloadRequests.resolveLocally(
        'request-1',
        to: DownloadRequestState.completed,
      );

      final outcome = await h.engine.syncOnce(h.transport);
      expect(outcome.succeeded, isTrue);
      expect(
        h.backend.kindRows('downloadRequest')['request-1']!['state'],
        'completed',
      );
      // Nothing about the request rode the mutation endpoint.
      final kinds = h.backend.mutationBatches
          .expand((batch) => batch)
          .map((e) => e['entity_type'])
          .toSet();
      expect(kinds, isNot(contains('downloadRequest')));
      expect(await h.outbox.pendingCount(), 0);
    },
  );

  test(
    'resolving a request the server already closed converges as an ack',
    () async {
      final collectionId = await makeCollection();
      final (entry, _) = await h.entries.createInCollection(
        collectionId: collectionId,
        ordinal: 1,
      );
      h.backend.seed('downloadRequest', {
        'id': 'request-2',
        'entry_id': entry!.id,
        'location_id': null,
        'state': 'cancelled', // terminal on the server already
        'idempotency_key': 'k2',
        'created_by': 'extension',
        'created_at': DateTime.now().toUtc().toIso8601String(),
        'claimed_by_device': '',
        'claimed_at': null,
        'resolved_at': DateTime.now().toUtc().toIso8601String(),
        'failure_reason': '',
      });
      await h.downloadRequests.applyRemote(
        id: 'request-2',
        serverId: 'request-2',
        entryId: entry.id,
        locationId: null,
        state: 'claimed',
        idempotencyKey: 'k2',
        createdBy: 'extension',
        createdAt: DateTime.now().toUtc(),
        claimedByDevice: 'this-device',
        claimedAt: DateTime.now().toUtc(),
        resolvedAt: null,
        failureReason: '',
        revision: 1,
      );
      await h.downloadRequests.resolveLocally(
        'request-2',
        to: DownloadRequestState.completed,
      );

      final outcome = await h.engine.syncOnce(h.transport);
      expect(outcome.succeeded, isTrue);
      expect(await h.outbox.pendingCount(), 0); // 409 terminal → converged
    },
  );
}
