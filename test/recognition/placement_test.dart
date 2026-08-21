/// Cross-source placement (F5): the accepted, conflicted and rejected paths of
/// the contract's placement endpoint, and the refusals this device can already
/// see without asking anyone.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:web_reader/data/data_violations.dart';
import 'package:web_reader/domain/collection.dart';
import 'package:web_reader/domain/entry.dart';
import 'package:web_reader/recognition/placement.dart';

import 'support/recognition_harness.dart';

/// A scripted stand-in for whatever carries a submission. Records everything it
/// was asked to send, so "no round trip that could not succeed" and "never a
/// second attempt" are both assertable.
class ScriptedTransport implements PlacementTransport {
  ScriptedTransport(this._response);

  final PlacementResponse Function(String entryId, double ordinal) _response;

  final sentEntryIds = <String>[];
  final sentOrdinals = <double>[];
  final sentMutationIds = <String>[];

  int get calls => sentEntryIds.length;

  @override
  Future<PlacementResponse> submitPlacement({
    required String entryId,
    required double ordinal,
    required String mutationId,
  }) async {
    sentEntryIds.add(entryId);
    sentOrdinals.add(ordinal);
    sentMutationIds.add(mutationId);
    return _response(entryId, ordinal);
  }
}

/// The accepted response the server would send for a winning placement.
PlacementAccepted acceptedFor(String entryId, String collectionId, double at) =>
    PlacementAccepted(
      entry: RemoteEntry(
        id: entryId,
        serverId: 'server-$entryId',
        collectionId: collectionId,
        folderId: null,
        ordinal: at,
        placement: Placement.userPlaced.name,
        title: 'Part $at',
        sortKey: 0,
        revision: 119,
        updatedAt: DateTime.utc(2026, 8, 21, 10, 17),
      ),
    );

void main() {
  late RecognitionHarness h;

  setUp(() => h = RecognitionHarness());
  tearDown(() => h.close());

  PlacementService serviceOver(ScriptedTransport transport) => PlacementService(
    entries: h.repos.entries,
    collections: h.repos.collections,
    index: h.repos.recognition,
    transport: transport,
    newMutationId: () => 'mutation-1',
  );

  /// A Collection holding one unplaced Entry and one placed at [heldAt].
  Future<({String collectionId, String unplacedId, String placedId})>
  seedCollection({double heldAt = 100}) async {
    final collection = await h.collection();
    final source = await h.source(collection: collection, host: kHostA);
    final (placed, _) = await h.placedEntry(
      collection: collection,
      source: source,
      host: kHostA,
      number: heldAt,
    );
    final (unplaced, violation) = await h.repos.entries.createInCollection(
      collectionId: collection.id,
      placement: Placement.unplaced,
      title: 'An interlude',
    );
    expect(violation, isNull);
    return (
      collectionId: collection.id,
      unplacedId: unplaced!.id,
      placedId: placed.id,
    );
  }

  group('accepted', () {
    test(
      'the winning placement is applied from the row the server returned',
      () async {
        final seed = await seedCollection();
        final transport = ScriptedTransport(
          (id, at) => acceptedFor(id, seed.collectionId, at),
        );

        final before = await h.repos.outboxCount();
        final outcome = await serviceOver(
          transport,
        ).place(entryId: seed.unplacedId, ordinal: 101);

        expect(outcome, isA<PlacementApplied>());
        final row = (outcome as PlacementApplied).entry;
        expect(row.id, seed.unplacedId);
        expect(row.ordinal, 101);
        expect(row.placement, Placement.userPlaced.name);
        expect(row.serverId, 'server-${seed.unplacedId}');
        expect(row.revision, 119);
        expect(
          await h.repos.outboxCount(),
          before,
          reason:
              'an arbitrated placement is already recorded centrally, so it '
              'comes back through the pull path and writes no intent',
        );
      },
    );

    test('the mutation id is sent, and a caller may supply its own', () async {
      final seed = await seedCollection();
      final transport = ScriptedTransport(
        (id, at) => acceptedFor(id, seed.collectionId, at),
      );
      final service = serviceOver(transport);

      await service.place(entryId: seed.unplacedId, ordinal: 101);
      expect(transport.sentMutationIds, ['mutation-1']);

      await service.place(
        entryId: seed.unplacedId,
        ordinal: 102,
        mutationId: 'resumed-submission',
      );
      expect(transport.sentMutationIds.last, 'resumed-submission');
      expect(transport.sentEntryIds, everyElement(seed.unplacedId));
      expect(transport.sentOrdinals, [101, 102]);
    });

    test(
      'a response about a different Entry is refused, not applied',
      () async {
        final seed = await seedCollection();
        final transport = ScriptedTransport(
          (id, at) => acceptedFor('some-other-entry', seed.collectionId, at),
        );

        final outcome = await serviceOver(
          transport,
        ).place(entryId: seed.unplacedId, ordinal: 101);

        expect(outcome, isA<PlacementRefused>());
        expect(
          (outcome as PlacementRefused).violation,
          placementSubjectMismatch,
        );
        expect(
          (await h.repos.entries.byId(seed.unplacedId))!.placement,
          Placement.unplaced.name,
        );
        expect(await h.repos.entries.byId('some-other-entry'), isNull);
      },
    );
  });

  group('conflict', () {
    test(
      'a lost placement is surfaced with the current holder, and not retried',
      () async {
        final seed = await seedCollection();
        final transport = ScriptedTransport(
          (_, _) => const PlacementConflicted(
            currentEntryId: 'entry-held-elsewhere',
            currentOrdinal: 101,
          ),
        );

        final outcome = await serviceOver(
          transport,
        ).place(entryId: seed.unplacedId, ordinal: 101);

        expect(outcome, isA<PlacementRefused>());
        final refusal = outcome as PlacementRefused;
        expect(refusal.violation, placementConflict);
        expect(refusal.violation.invariant, 'placement_conflict');
        expect(refusal.currentEntryId, 'entry-held-elsewhere');
        expect(refusal.currentOrdinal, 101);
        expect(refusal.reachedTransport, isTrue);
        expect(
          transport.calls,
          1,
          reason: 'a conflict is an answer, never a transient failure',
        );
        expect(
          transport.sentOrdinals,
          [101],
          reason: 'and never a different number tried on the user\'s behalf',
        );
        expect(
          (await h.repos.entries.byId(seed.unplacedId))!.ordinal,
          isNull,
          reason:
              'the Entry stays unplaced — visible, readable, still theirs '
              'to place',
        );
      },
    );
  });

  group('rejected', () {
    test('invalid_placement comes back as a named refusal', () async {
      final seed = await seedCollection();
      final transport = ScriptedTransport((_, _) => const PlacementInvalid());

      final outcome = await serviceOver(
        transport,
      ).place(entryId: seed.unplacedId, ordinal: 101);

      expect((outcome as PlacementRefused).violation, placementNotAvailable);
      expect(outcome.violation.invariant, 'invalid_placement');
      expect(outcome.reachedTransport, isTrue);
    });

    test('unknown_entity comes back as a named refusal', () async {
      final seed = await seedCollection();
      final transport = ScriptedTransport(
        (_, _) => const PlacementUnknownEntity(),
      );

      final outcome = await serviceOver(
        transport,
      ).place(entryId: seed.unplacedId, ordinal: 101);

      expect((outcome as PlacementRefused).violation, placementUnknownEntity);
      expect(outcome.violation.invariant, 'unknown_entity');
    });
  });

  group('what this device can already answer', () {
    test('a duplicate ordinal is refused without a round trip', () async {
      final seed = await seedCollection(heldAt: 100);
      final transport = ScriptedTransport(
        (id, at) => acceptedFor(id, seed.collectionId, at),
      );

      final outcome = await serviceOver(
        transport,
      ).place(entryId: seed.unplacedId, ordinal: 100);

      expect(outcome, isA<PlacementRefused>());
      final refusal = outcome as PlacementRefused;
      expect(refusal.violation, duplicateOrdinal);
      expect(refusal.violation.invariant, 'I8');
      expect(refusal.currentEntryId, seed.placedId);
      expect(refusal.currentOrdinal, 100);
      expect(refusal.reachedTransport, isFalse);
      expect(transport.calls, 0);
    });

    test('99.5 beside 100 is not a duplicate, and is submitted', () async {
      final seed = await seedCollection(heldAt: 100);
      final transport = ScriptedTransport(
        (id, at) => acceptedFor(id, seed.collectionId, at),
      );

      final outcome = await serviceOver(
        transport,
      ).place(entryId: seed.unplacedId, ordinal: 99.5);

      expect(outcome, isA<PlacementApplied>());
      expect(transport.sentOrdinals, [99.5]);
      expect(
        (await h.repos.entries.entriesOf(
          seed.collectionId,
        )).map((e) => e.ordinal),
        [99.5, 100],
        reason: '100 against 99.5 stays two Entries',
      );
    });

    test(
      'placing an Entry where it already is asks the server anyway',
      () async {
        final seed = await seedCollection(heldAt: 100);
        final transport = ScriptedTransport(
          (id, at) => acceptedFor(id, seed.collectionId, at),
        );

        final outcome = await serviceOver(
          transport,
        ).place(entryId: seed.placedId, ordinal: 100);

        expect(outcome, isA<PlacementApplied>());
        expect(
          transport.calls,
          1,
          reason: 'the holder is this Entry, so there is nothing to refuse',
        );
      },
    );

    test(
      'a Collection with no number line does not place by ordinal',
      () async {
        final folder = await h.root();
        final (collection, _) = await h.repos.collections.create(
          name: 'The journal',
          folderId: folder.id,
          orderingBasis: OrderingBasis.publicationDate,
        );
        final (entry, _) = await h.repos.entries.createInCollection(
          collectionId: collection!.id,
          placement: Placement.unplaced,
        );
        final transport = ScriptedTransport(
          (id, at) => acceptedFor(id, collection.id, at),
        );

        final outcome = await serviceOver(
          transport,
        ).place(entryId: entry!.id, ordinal: 3);

        expect((outcome as PlacementRefused).violation, placementNotAvailable);
        expect(outcome.reachedTransport, isFalse);
        expect(transport.calls, 0);
      },
    );

    test('a standalone Entry has no sequence to sit in', () async {
      final folder = await h.root();
      final (entry, _) = await h.repos.entries.createStandalone(
        folderId: folder.id,
        title: 'A page someone kept',
      );
      final transport = ScriptedTransport(
        (id, at) => acceptedFor(id, 'no-collection', at),
      );

      final outcome = await serviceOver(
        transport,
      ).place(entryId: entry!.id, ordinal: 1);

      expect((outcome as PlacementRefused).violation, placementNotAvailable);
      expect(transport.calls, 0);
    });

    test('an Entry this library does not hold is refused here', () async {
      final transport = ScriptedTransport(
        (id, at) => acceptedFor(id, 'nowhere', at),
      );

      final outcome = await serviceOver(
        transport,
      ).place(entryId: 'never-existed', ordinal: 1);

      expect((outcome as PlacementRefused).violation, placementUnknownEntity);
      expect(outcome.reachedTransport, isFalse);
      expect(transport.calls, 0);
    });
  });
}
