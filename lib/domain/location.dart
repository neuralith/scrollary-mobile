/// Location — one Entry, at one URL, on one Source.
library;

import 'entry.dart';
import 'invariants.dart';

/// Whether a Source still lists this address. Retraction is source-scoped: a
/// reading of Source A may retract Source A's Locations and never Source B's
/// (I15). It is evidence about one site, not a statement about the Entry.
enum LocationLifecycle { active, retracted }

/// `urlKey` is the normalised URL and is unique within a library: one URL is
/// one place. This is what makes recognition — the hot path, asked on every
/// page load — a single indexed lookup that works offline.
///
/// `sourceId` is null for a standalone Entry's Location. `sourceLabel` and
/// `sourceNumber` are what the site printed, kept as evidence and never as
/// identity.
class Location {
  const Location({
    required this.id,
    required this.entryId,
    required this.url,
    required this.urlKey,
    this.sourceId,
    this.sourceLabel = '',
    this.sourceNumber,
    this.discoveryBasis = '',
    this.discoveredAt,
    this.lifecycle = LocationLifecycle.active,
  });

  final String id;
  final String entryId;
  final String? sourceId;
  final String url;
  final String urlKey;
  final String sourceLabel;
  final double? sourceNumber;
  final DateTime? discoveredAt;
  final String discoveryBasis;
  final LocationLifecycle lifecycle;

  /// I7: a Location belongs to a Source if and only if its Entry belongs to a
  /// Collection.
  InvariantViolation? validateAgainstEntry(Entry entry) {
    if ((sourceId != null) != (entry.collectionId != null)) {
      return locationSourcePairing;
    }
    if (urlKey.isEmpty) return duplicateUrlKey;
    return null;
  }
}

/// I15 as a pure rule: whether a reading of [readingSourceId] may retract
/// [location]. Only that Source's own Locations qualify; a standalone
/// Location (no Source) is never retracted by source reading at all.
bool mayRetractLocation({
  required String? readingSourceId,
  required Location location,
}) {
  if (readingSourceId == null || location.sourceId == null) return false;
  return location.sourceId == readingSourceId;
}
