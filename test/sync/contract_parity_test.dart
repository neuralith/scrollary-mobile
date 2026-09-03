/// Every field the app pushes is a field the contract defines.
///
/// **The failure this exists to prevent.** The service's sparse-upsert merge is
/// an allowlist that *rejects* what it does not recognise, and the drain parks
/// a rejected intent permanently (`OutboxRepository.markRejected`). So a field
/// the app knows and the contract does not is not a no-op: it is a user's
/// change, dropped, silently, forever. Nothing failed at build time, nothing
/// failed at push time, and the only symptom was two devices disagreeing.
///
/// The fake service now applies the same allowlist, read from
/// `contracts/openapi.yaml`, so every push test in this directory carries the
/// guard. This file is the one that drives *every* synced repository mutation
/// on purpose, and the one that proves the guard bites.
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:web_reader/domain/collection.dart';
import 'package:web_reader/domain/entry.dart';
import 'package:web_reader/save/capture_mode.dart';

import 'support/contract_vocabulary.dart';
import 'support/sync_harness.dart';

void main() {
  late SyncHarness h;

  setUp(() async => h = await SyncHarness.start());
  tearDown(() => h.stop());

  /// Exercises every write that records a sync intent, so the payloads under
  /// test are the ones the app actually produces rather than a list of them.
  Future<void> everyKindOfMutation() async {
    final root = await h.folders.ensureRoot();
    final (folder, _) = await h.folders.create('Weekly', parentId: root.id);
    final (collection, _) = await h.collections.create(
      name: 'Serial Alpha',
      folderId: folder!.id,
      orderingBasis: OrderingBasis.explicitNumericIndex,
    );
    await h.collections.rename(collection!.id, 'Serial Alpha, renamed');
    await h.collections.setCaptureMode(
      collection.id,
      CaptureMode.imageSequence.name,
    );
    await h.collections.setEntrySort(collection.id, 'publishDate:descending');

    final (source, _) = await h.collections.addSource(
      collectionId: collection.id,
      host: 'reading.example.com',
      pathKey: '/serial-alpha',
    );
    await h.collections.setPreferredSource(collection.id, source!.id);

    final (entry, _) = await h.entries.createInCollection(
      collectionId: collection.id,
      ordinal: 1,
      placement: Placement.placed,
    );
    const url = 'https://reading.example.com/serial-alpha/part-1';
    final (location, _) = await h.entries.addLocation(
      entryId: entry!.id,
      sourceId: source.id,
      url: url,
      urlKey: url,
    );
    await h.entries.updateLocationEvidence(location!.id, sourceLabel: 'Part 1');
    await h.entries.recordLocationPublishedAt(
      location.id,
      DateTime.utc(2026, 3, 14),
    );

    await h.readingStates.markRead(entry.id);
    await h.measurements.put(
      entryId: entry.id,
      sourceId: source.id,
      fraction: 0.5,
    );
  }

  test('every pushed field is one the contract defines', () async {
    await everyKindOfMutation();
    final vocabulary = contractMutableFields();

    final rows = await h.outbox.pendingAfter(0, limit: 500);
    expect(
      rows,
      isNotEmpty,
      reason: 'the exercise above must actually record intents',
    );
    final seen = <String, Set<String>>{};
    for (final row in rows) {
      final allowed = vocabulary[row.entityKind];
      expect(
        allowed,
        isNotNull,
        reason:
            '${row.entityKind} is pushed but the contract defines no schema '
            'for it',
      );
      final fields = Map<String, Object?>.from(jsonDecode(row.payload) as Map);
      for (final key in fields.keys) {
        expect(
          allowed,
          contains(key),
          reason:
              '${row.entityKind}.$key is pushed but is not part of that '
              "entity's contract vocabulary — the service would reject it and "
              'the drain would park it forever',
        );
      }
      (seen[row.entityKind] ??= {}).addAll(fields.keys);
    }

    // The exercise is only evidence if it reached every kind that can be
    // pushed. A kind nobody wrote proves nothing about that kind's payload.
    expect(
      seen.keys.toSet(),
      contractSchemaFor.keys.toSet(),
      reason: 'this test must drive every mutable entity kind',
    );
  });

  test('and the service takes all of them', () async {
    await everyKindOfMutation();

    final outcome = await h.engine.syncOnce(h.transport);

    expect(outcome.succeeded, isTrue);
    expect(
      h.backend.refusedFields,
      isEmpty,
      reason: 'the fake applies the contract allowlist the service applies',
    );
    expect(await h.outbox.pendingCount(), 0);
    expect(
      await h.outbox.rejected(),
      isEmpty,
      reason: 'nothing the app writes may end up parked',
    );
  });

  test('a field outside the vocabulary is refused, not absorbed', () async {
    // The guard has to bite, or the two tests above pass for the wrong reason.
    final root = await h.folders.ensureRoot();
    final (collection, _) = await h.collections.create(
      name: 'Serial Alpha',
      folderId: root.id,
      orderingBasis: OrderingBasis.explicitNumericIndex,
    );
    await h.db.customStatement(
      "UPDATE outbox SET payload = json_set(payload, '\$.invented_field', 'x')",
    );

    await h.engine.syncOnce(h.transport);

    expect(h.backend.refusedFields, contains('collection.invented_field'));
    expect(
      (await h.outbox.rejected()).single.entityId,
      collection!.id,
      reason:
          'a rejection is deterministic, so the row is parked rather than '
          'retried forever',
    );
  });
}
