/// Entry — one logical unit of reading, and what reading state belongs to.
library;

import 'invariants.dart';

/// Distinguishes a position the app derived from one the user chose, and marks
/// the honest third case where neither could be established.
enum Placement { placed, unplaced, userPlaced }

/// An Entry is NOT a URL. That was V1's axiom and it is what stopped an Entry
/// from existing in more than one place. Where an Entry can be read is a
/// Location; how far through it the reader got is a Measurement scoped to a
/// rendering; whether this device holds the bytes is an OfflineCopy, which the
/// server never sees.
///
/// `collectionId` is null for a standalone Entry — a first-class library item
/// that owns its Locations directly and lives in a Folder. It is never wrapped
/// in a Collection of one to make the model tidy.
class Entry {
  const Entry({
    required this.id,
    required this.placement,
    this.collectionId,
    this.folderId,
    this.ordinal,
    this.title = '',
    this.sortKey = 0,
  });

  final String id;
  final String? collectionId;
  final String? folderId;

  /// Position in the Collection's own sequence. Null means unplaced — a real,
  /// visible state, not an error.
  final double? ordinal;
  final Placement placement;
  final String title;
  final int sortKey;

  bool get standalone => collectionId == null;

  /// I3: an Entry has a Folder if and only if it has no Collection. An Entry
  /// inside a Collection is where its Collection is. Also: an unplaced Entry
  /// carries no ordinal — a position it does not have would be a guess.
  InvariantViolation? validate() {
    if ((collectionId == null) != (folderId != null)) {
      return entryPlacementViolation;
    }
    if (placement == Placement.unplaced && ordinal != null) {
      return unplacedEntryHasOrdinal;
    }
    return null;
  }
}
