/// Collection — a logical work: a group of related Entries.
library;

import 'invariants.dart';
import 'source.dart';

/// Whether the user is following this Collection. A Collection in the library
/// IS followed; archiving is how following stops, and it preserves everything.
enum CollectionLifecycle { active, archived }

/// What decides the reading order, and with it whether cross-source Entry
/// merging is available at all. Only an explicit numeric index gives
/// equivalence something to key on; the model states which mode a Collection
/// is in rather than degrading silently.
enum OrderingBasis {
  explicitNumericIndex,
  publicationDate,
  detectedNextLink,
  discoveryOrder,
  userDefinedManualOrder;

  /// Whether Entries from different Sources of this Collection may be merged
  /// automatically (V2-D16).
  bool get supportsCrossSourceMerge => this == explicitNumericIndex;
}

/// A Collection has no URL and no host. Those belong to its Sources, which is
/// what lets a Collection outlive the site that published it.
class Collection {
  const Collection({
    required this.id,
    required this.folderId,
    required this.name,
    required this.orderingBasis,
    this.detectedTitle = '',
    this.lifecycle = CollectionLifecycle.active,
    this.preferredSourceId,
    this.sortKey = 0,
  });

  final String id;

  /// Never null: every Collection has a Folder (I4).
  final String folderId;
  final String name;
  final String detectedTitle;
  final OrderingBasis orderingBasis;
  final CollectionLifecycle lifecycle;

  /// A pointer on the Collection, not a flag on each Source, so there is
  /// exactly one place the answer lives.
  final String? preferredSourceId;
  final int sortKey;

  /// Whether Scrollary may keep this Collection current from the user's
  /// reading.
  bool get followed => lifecycle == CollectionLifecycle.active;

  InvariantViolation? validate() {
    if (folderId.isEmpty) return collectionNeedsFolder;
    return null;
  }

  /// I9: a preferred Source, when set, belongs to this Collection.
  InvariantViolation? validatePreferredSource(Source? preferred) {
    if (preferredSourceId == null) return null;
    if (preferred == null ||
        preferred.id != preferredSourceId ||
        preferred.collectionId != id) {
      return preferredSourceForeign;
    }
    return null;
  }
}
