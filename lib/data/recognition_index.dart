/// Local recognition indexes (roadmap C9): the hot path, offline.
///
/// "Given this URL, what is it?" is asked on every page load, so the answer
/// must come from one indexed local lookup with no network anywhere near it
/// (V2_ARCHITECTURE.md §6.3). A known `url_key` resolves Location and Entry in
/// a single joined statement over the unique `url_key` index; `(host,
/// path_key)` resolves a Source the same way.
library;

import 'package:drift/drift.dart';

import 'schema.dart';

/// What a URL resolved to. `entry` is present whenever the Location's Entry
/// row exists (it always does under FK enforcement); `collectionId` is null
/// for a standalone Entry's Location.
class RecognitionHit {
  const RecognitionHit({required this.location, required this.entry});

  final LocationRow location;
  final EntryRow entry;

  String? get collectionId => entry.collectionId;
}

/// A [RecognitionHit] with the Entry's Collection resolved beside it, in the
/// same statement.
///
/// [collection] is null for a standalone Entry's Location — an answer (I3),
/// not a miss.
class RecognitionCollectionHit {
  const RecognitionCollectionHit({
    required this.location,
    required this.entry,
    required this.collection,
  });

  final LocationRow location;
  final EntryRow entry;
  final CollectionRow? collection;
}

class RecognitionIndex {
  RecognitionIndex(this._db);

  final LibraryDatabase _db;

  /// `url_key` → (Location, Entry) in ONE statement, or null for an unknown
  /// URL. Retracted Locations still resolve: retraction is evidence about a
  /// Source's listing, not about what the address is.
  Future<RecognitionHit?> lookupUrl(String urlKey) async {
    final query =
        _db.select(_db.locations).join([
            innerJoin(
              _db.entries,
              _db.entries.id.equalsExp(_db.locations.entryId),
            ),
          ])
          ..where(_db.locations.urlKey.equals(urlKey))
          ..limit(1);
    final row = await query.getSingleOrNull();
    if (row == null) return null;
    return RecognitionHit(
      location: row.readTable(_db.locations),
      entry: row.readTable(_db.entries),
    );
  }

  /// `url_key` → (Location, Entry, Collection) in ONE statement, or null.
  ///
  /// The same unique index as [lookupUrl], with the Entry's Collection joined
  /// on beside it for a caller that must judge an address against the rules
  /// its Collection sets — the ordering basis a placement is gated by
  /// (V2-D16). Resolving it afterwards would be a second statement per
  /// address, which on a listing of a hundred is a hundred of them.
  ///
  /// The Collection join is outer, because a standalone Entry has none.
  Future<RecognitionCollectionHit?> lookupUrlWithCollection(
    String urlKey,
  ) async {
    final query =
        _db.select(_db.locations).join([
            innerJoin(
              _db.entries,
              _db.entries.id.equalsExp(_db.locations.entryId),
            ),
            leftOuterJoin(
              _db.collections,
              _db.collections.id.equalsExp(_db.entries.collectionId),
            ),
          ])
          ..where(_db.locations.urlKey.equals(urlKey))
          ..limit(1);
    final row = await query.getSingleOrNull();
    if (row == null) return null;
    return RecognitionCollectionHit(
      location: row.readTable(_db.locations),
      entry: row.readTable(_db.entries),
      collection: row.readTableOrNull(_db.collections),
    );
  }

  /// `(host, path_key)` → Source in one statement, or null.
  Future<SourceRow?> lookupSource(String host, String pathKey) {
    return (_db.select(_db.sources)
          ..where((s) => s.host.equals(host) & s.pathKey.equals(pathKey))
          ..limit(1))
        .getSingleOrNull();
  }

  /// `(collection, ordinal)` → Entry in one statement, or null. The third
  /// recognition index of §6.3.
  Future<EntryRow?> lookupOrdinal(String collectionId, double ordinal) {
    return (_db.select(_db.entries)
          ..where(
            (e) =>
                e.collectionId.equals(collectionId) & e.ordinal.equals(ordinal),
          )
          ..limit(1))
        .getSingleOrNull();
  }
}
