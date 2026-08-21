/// Named refusals the repository layer surfaces that have no constant in
/// `lib/domain/invariants.dart` yet.
///
/// Same shape and citation style as the domain's own list, kept here because
/// the domain package is frozen for this lane. Candidates for promotion into
/// `lib/domain/invariants.dart` at the next domain review.
library;

import '../domain/invariants.dart';

/// I8 proper: two Entries of one Collection cannot share an ordinal. The
/// domain file currently uses the `I8` label only for the
/// unplaced-carries-no-ordinal rule; the uniqueness half lives in the schema's
/// partial index and is surfaced under its own name here.
const duplicateOrdinal = InvariantViolation(
  'I8',
  'an ordinal is unique within its collection',
);

/// I1: the system root is not the user's to rename, move or delete.
const rootFolderImmutable = InvariantViolation(
  'I1',
  'the root folder cannot be renamed, moved or deleted',
);

/// I1: a folder operation named a parent that does not exist.
const unknownParentFolder = InvariantViolation(
  'I1',
  'the target parent folder does not exist',
);

/// V2_ARCHITECTURE.md §6.3: `(host, path_key)` resolves to exactly one Source.
const sourceIdentityTaken = InvariantViolation(
  '§6.3',
  'a (host, path_key) pair identifies exactly one Source',
);

/// V2_ARCHITECTURE.md §2.3: a resolved-into pointer stays inside the
/// Collection whose site moved.
const resolvedIntoForeign = InvariantViolation(
  '§2.3',
  'resolvedInto must name a Source of the same Collection',
);

/// I15: only the Source whose reading is being reconciled may retract, and
/// only its own Locations.
const retractionOutOfScope = InvariantViolation(
  'I15',
  'a reading of one Source cannot retract another Source\'s Location',
);

/// A referenced row is missing. The repository refuses rather than creating
/// implicitly: implicit creation is how a typo becomes an entity.
const unknownRow = InvariantViolation(
  '§6.1',
  'the referenced row does not exist',
);
