/// Cross-source Entry equivalence — where merging is allowed, and where it is
/// refused (V2-D16).
library;

import 'collection.dart';

/// The three honest answers when two Sources may be describing the same Entry.
enum EquivalenceDecision {
  /// Equal ordinals under an explicit numeric basis: the same logical Entry.
  sameEntry,

  /// Different ordinals (100 against 99.5), or a basis that gives equivalence
  /// nothing to key on: two Entries, both visible, mergeable by the user.
  distinctEntries,

  /// No usable ordinal on one side: the newcomer stays unplaced — visible,
  /// readable, offered to the user to place. Never guessed into a position.
  unplaced,
}

/// Decides whether an observation from another Source matches an existing
/// Entry. Conservative by construction: this is the posture
/// `entry_identity.dart` takes inside a single Source — when independent
/// readings contradict each other, stop and keep the contradiction. No
/// "drop the last digit", no "prefer the URL".
EquivalenceDecision crossSourceEquivalence({
  required OrderingBasis basis,
  required double? existingOrdinal,
  required double? observedOrdinal,
}) {
  if (!basis.supportsCrossSourceMerge) {
    return EquivalenceDecision.distinctEntries;
  }
  if (observedOrdinal == null) return EquivalenceDecision.unplaced;
  if (existingOrdinal == null) return EquivalenceDecision.distinctEntries;
  if (existingOrdinal == observedOrdinal) return EquivalenceDecision.sameEntry;
  return EquivalenceDecision.distinctEntries;
}
