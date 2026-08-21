/// Cross-source placement, and the refusals it surfaces (roadmap F5).
///
/// Placing an unplaced Entry is the one library mutation this app does **not**
/// settle locally. Two devices placing the same Entry differently is a
/// contradiction, and a clock is not an answer to a contradiction, so the
/// server serialises it (`contracts/openapi.yaml` `/entries/{entry_id}/placement`,
/// V2_SYNC.md §4.6). The loser is told, in the same posture as every other
/// refusal in this app: the conflict is shown, never repaired.
///
/// Three things this file will not do, and they are the whole point of it:
///
/// * **No automatic retry.** A conflict is an answer, not a transient failure.
/// * **No silently different ordinal.** 100 and 99.5 are two Entries (V2-D16);
///   nudging a losing placement to the next free position would merge them by
///   sleight of hand.
/// * **No round trip that could not succeed.** A duplicate ordinal the device
///   can already see is refused here, with the domain's own equivalence rule
///   making the judgement and the domain's own named violation carrying it.
///
/// The transport is an interface. Nothing in this file knows what HTTP is, and
/// nothing in `lib/sync/` needs to know what placement means.
library;

import '../data/collection_repository.dart';
import '../data/data_ids.dart';
import '../data/data_violations.dart';
import '../data/entry_repository.dart';
import '../data/recognition_index.dart';
import '../data/schema.dart';
import '../domain/collection.dart';
import '../domain/equivalence.dart';
import '../domain/invariants.dart';

/// `contracts/errors.yaml`: another placement won and the current holder is
/// named. Carried as an [InvariantViolation] whose `invariant` is the contract
/// code, the same idiom `evidence.dart` uses, so a local refusal and a server
/// rejection are recognisably the same rule.
const placementConflict = InvariantViolation(
  'placement_conflict',
  'another placement won; the position is already held',
);

/// `contracts/errors.yaml`: the request itself is unacceptable — most often a
/// Collection whose ordering basis does not place Entries by ordinal at all.
const placementNotAvailable = InvariantViolation(
  'invalid_placement',
  'this Entry is not placed by ordinal',
);

/// `contracts/errors.yaml`: the Entry does not exist in this library.
const placementUnknownEntity = InvariantViolation(
  'unknown_entity',
  'the referenced Entry does not exist in this library',
);

/// The response named an Entry other than the one submitted. A trust boundary,
/// refused rather than applied — mirrors `history.dart`'s
/// `promotionSubjectMismatch`.
const placementSubjectMismatch = InvariantViolation(
  'invalid_request',
  'the placement response is about a different Entry',
);

/// An Entry row exactly as the contract's `Entry` schema carries it.
///
/// Field for field with `EntryRepository.applyRemoteEntry`, because that is
/// where it goes: an accepted placement has already been recorded centrally, so
/// it is applied through the pull path and writes no outbox row of its own.
class RemoteEntry {
  const RemoteEntry({
    required this.id,
    required this.collectionId,
    required this.folderId,
    required this.ordinal,
    required this.placement,
    required this.title,
    required this.sortKey,
    required this.revision,
    required this.updatedAt,
    this.serverId,
  });

  final String id;
  final String? serverId;
  final String? collectionId;
  final String? folderId;
  final double? ordinal;
  final String placement;
  final String title;
  final int sortKey;
  final int revision;
  final DateTime updatedAt;
}

/// What the placement endpoint answered. The contract's four outcomes, and no
/// fifth: an unrecognised body is the transport's to refuse, not this file's to
/// read as one of these.
sealed class PlacementResponse {
  const PlacementResponse();
}

/// 200: the placement won, and here is the Entry in its new state.
///
/// The response also carries a `library_revision`, which is a cursor rather
/// than a fact about this Entry; it belongs where cursors are kept and is not
/// modelled here.
final class PlacementAccepted extends PlacementResponse {
  const PlacementAccepted({required this.entry});

  final RemoteEntry entry;
}

/// 409 `placement_conflict`, with `details` naming the current holder.
final class PlacementConflicted extends PlacementResponse {
  const PlacementConflicted({this.currentEntryId, this.currentOrdinal});

  final String? currentEntryId;
  final double? currentOrdinal;
}

/// 409 `invalid_placement`: ordinal placement is not available here.
final class PlacementInvalid extends PlacementResponse {
  const PlacementInvalid();
}

/// 404 `unknown_entity`.
final class PlacementUnknownEntity extends PlacementResponse {
  const PlacementUnknownEntity();
}

/// Carries one placement submission to whatever is arbitrating it.
///
/// An interface, and never a concrete client: the sync lane owns transport, and
/// a placement is a domain act that must be provable with no network anywhere
/// near it. `mutationId` is the ledger key that makes a retried submission
/// idempotent — the contract's optional `mutation_id`, which this app always
/// sends because a submission it cannot tell apart from a second one is a
/// submission it cannot safely repeat.
abstract interface class PlacementTransport {
  Future<PlacementResponse> submitPlacement({
    required String entryId,
    required double ordinal,
    required String mutationId,
  });
}

/// What one placement attempt did.
sealed class PlacementOutcome {
  const PlacementOutcome();
}

/// The placement won and the Entry row now says so locally.
final class PlacementApplied extends PlacementOutcome {
  const PlacementApplied(this.entry);

  final EntryRow entry;
}

/// The placement did not happen, and here is exactly why — for a surface to
/// show. Never a reason to try again with a different number.
final class PlacementRefused extends PlacementOutcome {
  const PlacementRefused(
    this.violation, {
    this.currentEntryId,
    this.currentOrdinal,
    this.reachedTransport = false,
  });

  final InvariantViolation violation;

  /// The Entry already at the requested position, when one is known. Present
  /// for both the local pre-check and the server's `placement_conflict`.
  final String? currentEntryId;
  final double? currentOrdinal;

  /// False when the device could already see the answer, so nothing was sent.
  final bool reachedTransport;
}

/// Places an Entry at an ordinal, through central arbitration.
class PlacementService {
  PlacementService({
    required this._entries,
    required this._collections,
    required this._index,
    required this._transport,
    IdGenerator? newMutationId,
  }) : _newMutationId = newMutationId ?? newLocalId;

  final EntryRepository _entries;
  final CollectionRepository _collections;
  final RecognitionIndex _index;
  final PlacementTransport _transport;
  final IdGenerator _newMutationId;

  /// Ask for [entryId] to sit at [ordinal].
  ///
  /// [mutationId] is supplied by a caller resuming a submission it has already
  /// made; omit it and a fresh one is minted. Repeating the same id is what
  /// makes a retry idempotent rather than a second placement.
  Future<PlacementOutcome> place({
    required String entryId,
    required double ordinal,
    String? mutationId,
  }) async {
    final refusal = await _localPreCheck(entryId: entryId, ordinal: ordinal);
    if (refusal != null) return refusal;

    final response = await _transport.submitPlacement(
      entryId: entryId,
      ordinal: ordinal,
      mutationId: mutationId ?? _newMutationId(),
    );

    switch (response) {
      case PlacementAccepted(:final entry):
        if (entry.id != entryId) {
          return const PlacementRefused(
            placementSubjectMismatch,
            reachedTransport: true,
          );
        }
        await _entries.applyRemoteEntry(
          id: entry.id,
          serverId: entry.serverId,
          collectionId: entry.collectionId,
          folderId: entry.folderId,
          ordinal: entry.ordinal,
          placement: entry.placement,
          title: entry.title,
          sortKey: entry.sortKey,
          revision: entry.revision,
          updatedAt: entry.updatedAt,
        );
        final row = await _entries.byId(entry.id);
        if (row == null) {
          return const PlacementRefused(
            placementUnknownEntity,
            reachedTransport: true,
          );
        }
        return PlacementApplied(row);

      // The refusal the whole design exists to surface. It is returned as it
      // arrived — no second attempt, and no other number tried.
      case PlacementConflicted(:final currentEntryId, :final currentOrdinal):
        return PlacementRefused(
          placementConflict,
          currentEntryId: currentEntryId,
          currentOrdinal: currentOrdinal,
          reachedTransport: true,
        );

      case PlacementInvalid():
        return const PlacementRefused(
          placementNotAvailable,
          reachedTransport: true,
        );

      case PlacementUnknownEntity():
        return const PlacementRefused(
          placementUnknownEntity,
          reachedTransport: true,
        );
    }
  }

  /// What this device can already answer, without asking anyone.
  ///
  /// Not an optimisation — it is the same refusal the user would get a round
  /// trip later, shown immediately, and it keeps a request the schema's own
  /// unique index would reject from being sent at all.
  Future<PlacementRefused?> _localPreCheck({
    required String entryId,
    required double ordinal,
  }) async {
    final entry = await _entries.byId(entryId);
    if (entry == null) return const PlacementRefused(placementUnknownEntity);

    // A standalone Entry is a first-class library item with no sequence to sit
    // in (I3). There is no position to place it at, which is an answer.
    final collectionId = entry.collectionId;
    if (collectionId == null) {
      return const PlacementRefused(placementNotAvailable);
    }
    final collection = await _collections.byId(collectionId);
    if (collection == null) {
      return const PlacementRefused(placementUnknownEntity);
    }

    final basis = OrderingBasis.values.byName(collection.orderingBasis);
    if (!basis.supportsCrossSourceMerge) {
      return const PlacementRefused(placementNotAvailable);
    }

    // I8: one ordinal, one Entry, within a Collection. The judgement is the
    // domain's — `sameEntry` is precisely "these two are the same position",
    // and it is the same rule that keeps 100 and 99.5 apart.
    final holder = await _index.lookupOrdinal(collectionId, ordinal);
    if (holder == null || holder.id == entryId) return null;
    final decision = crossSourceEquivalence(
      basis: basis,
      existingOrdinal: holder.ordinal,
      observedOrdinal: ordinal,
    );
    if (decision != EquivalenceDecision.sameEntry) return null;
    return PlacementRefused(
      duplicateOrdinal,
      currentEntryId: holder.id,
      currentOrdinal: holder.ordinal,
    );
  }
}
