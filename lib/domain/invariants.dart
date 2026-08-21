/// Named invariant violations, mirroring `backend/internal/domain/errors.go`.
///
/// Numbered against docs/V2_ARCHITECTURE.md §3 so a test, a log line and the
/// architecture document all point at the same rule. A violation is named
/// rather than free text so a new one cannot be introduced by writing a new
/// sentence.
library;

/// A broken domain invariant.
///
/// Validators return one (or null) rather than throwing, so callers decide
/// whether a violation is a programming error or a refusal to surface.
class InvariantViolation {
  const InvariantViolation(this.invariant, this.message);

  /// The invariant number from V2_ARCHITECTURE.md §3, e.g. `'I3'`.
  final String invariant;
  final String message;

  @override
  String toString() => '$invariant: $message';
}

const rootMustNotHaveParent = InvariantViolation(
  'I1',
  'the root folder must not have a parent',
);
const folderMustHaveParent = InvariantViolation(
  'I1',
  'a non-root folder must have a parent',
);
const folderCycle = InvariantViolation('I2', 'a folder may not contain itself');
const entryPlacementViolation = InvariantViolation(
  'I3',
  'an entry has a folder iff it has no collection',
);
const collectionNeedsFolder = InvariantViolation(
  'I4',
  'every collection has a folder',
);
const duplicateUrlKey = InvariantViolation(
  'I6',
  'url_key is unique within a library',
);
const locationSourcePairing = InvariantViolation(
  'I7',
  'a location has a source iff its entry has a collection',
);
const unplacedEntryHasOrdinal = InvariantViolation(
  'I8',
  'an unplaced entry carries no ordinal',
);
const preferredSourceForeign = InvariantViolation(
  'I9',
  'a preferred source must belong to its collection',
);
const measurementNeedsScope = InvariantViolation(
  'I12',
  'a measurement must name the source it was measured against',
);
const requestAlreadyClaimed = InvariantViolation(
  'I17',
  'a download request is claimed by exactly one device',
);
const requestNotTerminal = InvariantViolation(
  'I17',
  'a download request resolves only to a terminal state',
);
