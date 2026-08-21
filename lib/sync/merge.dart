/// The three merge characters, and no more (roadmap G4, V2_SYNC.md §4.2).
///
/// | Character      | Merge                          | Applies to            |
/// |----------------|--------------------------------|-----------------------|
/// | Scalar         | Last write wins on the row clock | Folder name/placement, Collection rename/lifecycle, preferred Source, Source lifecycle, reading state |
/// | Set            | Add wins; removal only via tombstone | Sources, Locations, Entries of a Collection, Folder children |
/// | Keyed scalar   | Last write wins per key        | Measurements `(entry, source)` |
///
/// Set membership needs no machinery here: adds arrive as row upserts and
/// removals only ever arrive as tombstones, so the set semantics fall out of
/// the two row-level rules below. No CRDTs, no vector clocks, no three-way
/// merge — every conflict is resolved by *choosing*, never by combining.
///
/// Ties go to the remote side: the server's view is the one every other
/// client converges on, so a deterministic tie-break toward it converges in
/// one round instead of two.
library;

/// Scalar rule: does the incoming server row replace the local row?
///
/// [localClock] is the local row's clock (`updated_at`; `observed_at` for the
/// keyed scalar), null when no local row exists. [remoteClock] is the
/// incoming row's clock. Remote wins ties.
bool remoteRowWins({
  required DateTime? localClock,
  required DateTime remoteClock,
}) {
  if (localClock == null) return true;
  return !localClock.toUtc().isAfter(remoteClock.toUtc());
}

/// Tombstone rule — the "add wins" half of the set character: a removal
/// applies unless the local row was written *after* the deletion, in which
/// case the newer local add survives (and its pending push re-creates the
/// row centrally).
bool tombstoneWins({
  required DateTime? localClock,
  required DateTime deletedAt,
}) => remoteRowWins(localClock: localClock, remoteClock: deletedAt);
