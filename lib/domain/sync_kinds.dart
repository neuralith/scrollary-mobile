/// What synchronises, named — and, by omission, what never does.
library;

/// The entity kinds that cross the network. The wire spelling is `name`.
///
/// OfflineCopy, browsing history, page hints, capture state and the reading
/// anchor are deliberately NOT here. Their absence from this enum is I11 as a
/// type: an outbox intent or a tombstone about them cannot even be expressed.
enum SyncedEntityKind {
  folder,
  collection,
  source,
  entry,
  location,
  readingState,
  measurement,
  downloadRequest,
}

/// A deliberate removal, recorded so a client that has been offline can learn
/// about it.
///
/// Only deliberate user removals produce one. A Location a Source stopped
/// listing does NOT: that is source-scoped evidence which each device
/// reconciles from its own reading. A tombstone never destroys bytes on any
/// device (I14) — a removal that arrives from elsewhere takes library rows and
/// leaves the package on disk.
class Tombstone {
  const Tombstone({
    required this.kind,
    required this.entityId,
    required this.deletedAt,
  });

  final SyncedEntityKind kind;
  final String entityId;
  final DateTime deletedAt;
}
