/// Which Entry an address belongs to — decided once, for every path.
///
/// **Why this file exists.** The rule that decides whether two addresses are
/// the same Entry (V2-D16) was written inside `SourceDiscovery`, where a
/// Source's own listing is read. Every *other* way an address enters the
/// library — the browser save, an adoption, a standalone Entry moving into a
/// Collection — then had to either re-derive it or skip it, and skipping it is
/// what let a second Source's Part 5 become a second Entry beside the first.
///
/// So it lives here, with exactly one implementation, and the callers differ
/// only in what they do with the answer:
///
/// * **[EntryReconciler.planFor]** decides and writes nothing. A caller that
///   already has an Entry — an adoption moving a standalone one in — needs the
///   decision, not a new row.
/// * **[EntryReconciler.entryFor]** decides and creates the Entry when the
///   decision is that there is not one yet.
///
/// The rule itself is unchanged and is the domain's ([crossSourceEquivalence]):
/// a position is written only when the Collection's ordering basis supports it
/// *and* the source printed a number. Equal ordinals join the Entry that
/// already holds one; 100 against 99.5 stays two Entries; no number at all
/// leaves the Entry unplaced, which is an answer.
library;

import '../data/data_violations.dart';
import '../data/entry_repository.dart';
import '../data/recognition_index.dart';
import '../data/schema.dart';
import '../domain/collection.dart';
import '../domain/entry.dart';
import '../domain/equivalence.dart';
import '../domain/invariants.dart';

/// What reconciliation came to.
enum ReconcileAction {
  /// The Collection already holds this Entry — equal ordinals under an
  /// explicit numeric basis, and nothing else (V2-D16).
  mergedExisting,

  /// A new Entry, at the position the source printed.
  createdPlaced,

  /// A new Entry with no position: visible, readable, offered to the user to
  /// place. Never guessed into a position.
  createdUnplaced,
}

/// The decision, before anything is written.
class ReconcilePlan {
  const ReconcilePlan.merge(EntryRow this.existing)
    : action = ReconcileAction.mergedExisting,
      ordinal = null;

  const ReconcilePlan.placed(double this.ordinal)
    : action = ReconcileAction.createdPlaced,
      existing = null;

  const ReconcilePlan.unplaced()
    : action = ReconcileAction.createdUnplaced,
      existing = null,
      ordinal = null;

  final ReconcileAction action;

  /// The Entry to join. Set exactly when [action] is
  /// [ReconcileAction.mergedExisting].
  final EntryRow? existing;

  /// The position to write. Set exactly when [action] is
  /// [ReconcileAction.createdPlaced].
  final double? ordinal;

  bool get merges => action == ReconcileAction.mergedExisting;

  /// The placement an Entry carrying this decision has.
  Placement get placement => action == ReconcileAction.createdUnplaced
      ? Placement.unplaced
      : Placement.placed;
}

/// The decision, and the Entry that carries it.
class ReconcileResult {
  const ReconcileResult({this.entryId, this.action, this.violation});

  const ReconcileResult.refused(InvariantViolation this.violation)
    : entryId = null,
      action = null;

  /// The Entry this address belongs to. Null only when [violation] is set.
  final String? entryId;

  /// What happened to reach it. Null only when [violation] is set.
  final ReconcileAction? action;

  final InvariantViolation? violation;

  /// Whether the address joined an Entry the Collection already held.
  bool get mergedIntoExistingEntry => action == ReconcileAction.mergedExisting;

  bool get succeeded => violation == null && entryId != null;
}

/// The one implementation of cross-source Entry equivalence.
class EntryReconciler {
  EntryReconciler({required this._entries, required this._index});

  final EntryRepository _entries;
  final RecognitionIndex _index;

  /// Which Entry of [collectionId] an address numbered [printedNumber]
  /// belongs to — reading only.
  ///
  /// [printedNumber] is what the *source printed*, never a number read out of
  /// an address (V2-D15): a number in a URL is evidence for the identity
  /// review and is never adopted as a position.
  Future<ReconcilePlan> planFor({
    required String collectionId,
    required OrderingBasis basis,
    required double? printedNumber,
  }) async {
    final placeable = basis.supportsCrossSourceMerge && printedNumber != null;
    final candidate = placeable
        ? await _index.lookupOrdinal(collectionId, printedNumber)
        : null;

    final decision = crossSourceEquivalence(
      basis: basis,
      existingOrdinal: candidate?.ordinal,
      observedOrdinal: printedNumber,
    );

    if (decision == EquivalenceDecision.sameEntry && candidate != null) {
      return ReconcilePlan.merge(candidate);
    }
    if (placeable && decision == EquivalenceDecision.distinctEntries) {
      return ReconcilePlan.placed(printedNumber);
    }
    return const ReconcilePlan.unplaced();
  }

  /// [planFor], then the Entry it names: the one it joins, or a new one
  /// carrying the position the decision allows.
  Future<ReconcileResult> entryFor({
    required String collectionId,
    required OrderingBasis basis,
    required double? printedNumber,
    required String title,
  }) async {
    final plan = await planFor(
      collectionId: collectionId,
      basis: basis,
      printedNumber: printedNumber,
    );
    final existing = plan.existing;
    if (existing != null) {
      return ReconcileResult(
        entryId: existing.id,
        action: ReconcileAction.mergedExisting,
      );
    }

    final (entry, violation) = await _entries.createInCollection(
      collectionId: collectionId,
      ordinal: plan.ordinal,
      placement: plan.placement,
      title: title,
    );
    if (violation != null || entry == null) {
      return ReconcileResult.refused(violation ?? unknownRow);
    }
    return ReconcileResult(entryId: entry.id, action: plan.action);
  }
}
