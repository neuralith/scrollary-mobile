/// Device-local history and promotion into the library (roadmap F6).
///
/// V2-D13: a Collection in the library **is followed**, and following is what
/// licenses Scrollary to keep it current from the user's reading. Everything
/// else the user reads lands here — device-local, never synced (I11,
/// V2_SYNC.md §4.8) — with one tap to promote it. Cloud sync is not cloud
/// browsing history, so unfollowed reading never expands the synced library on
/// its own.
///
/// The recording rule is V1's, unchanged in spirit: **only navigation the user
/// performed themselves.** Save automation and update checks move the same
/// browser and must never appear here, which is why [HistoryStore.recordVisit]
/// takes the fact as a required flag and refuses without it rather than
/// inferring it from a caller's identity.
///
/// Collapsing repeat visits inside a short window is deliberately not here: it
/// is browser-surface behaviour and belongs with the browser lane that owns
/// the navigation callback.
library;

import 'package:drift/drift.dart';

import '../data/collection_repository.dart';
import '../data/data_ids.dart';
import '../data/entry_repository.dart';
import '../data/folder_repository.dart';
import '../data/schema.dart' hide PageHints;
import '../domain/collection.dart';
import '../domain/invariants.dart';
import 'recognise.dart';

/// V2_ARCHITECTURE.md §2.8: history records what a person did, and nothing a
/// machine did on their behalf.
const historyNotUserInitiated = InvariantViolation(
  '§2.8',
  'only navigation the user performed themselves is recorded',
);

/// A load that never finished is not a destination.
const historyVisitIncomplete = InvariantViolation(
  '§2.8',
  'only a completed destination is recorded',
);

/// `about:blank`, app schemes and junk are not pages.
const historyNotAWebPage = InvariantViolation(
  '§2.8',
  'only a renderable web page is recorded',
);

/// A promotion was handed a recognition result about a different address.
const promotionSubjectMismatch = InvariantViolation(
  '§2.8',
  'the recognition result is about a different page',
);

/// Device-local visit capture. No outbox, no server id, no revision — the
/// table has none, and an intent about history cannot be expressed (I11).
class HistoryStore {
  HistoryStore(this._db, {Clock? now, IdGenerator? newId})
    : _now = now ?? utcNow,
      _newId = newId ?? newLocalId;

  final LibraryDatabase _db;
  final Clock _now;
  final IdGenerator _newId;

  /// Record one manual visit.
  ///
  /// [userInitiated] is the whole gate: pass false — as every automated
  /// navigation must — and nothing is written.
  Future<(HistoryRow?, InvariantViolation?)> recordVisit({
    required String url,
    required bool userInitiated,
    String title = '',
    String? finalUrl,
    bool completed = true,
    DateTime? at,
  }) async {
    if (!userInitiated) return (null, historyNotUserInitiated);
    if (!completed) return (null, historyVisitIncomplete);

    // The address the load actually settled on is the one that was read.
    final landed = (finalUrl ?? url).trim();
    final keys = RecognitionKeys.of(landed);
    if (!keys.isWebPage) return (null, historyNotAWebPage);

    final id = _newId();
    final when = (at ?? _now()).toUtc();
    await _db
        .into(_db.history)
        .insert(
          HistoryCompanion.insert(
            id: id,
            url: landed,
            urlKey: keys.urlKey,
            host: keys.host,
            title: title.trim(),
            finalUrl: Value(
              finalUrl != null && finalUrl != url ? finalUrl : null,
            ),
            visitedAt: when,
          ),
        );
    return (await byId(id), null);
  }

  Future<HistoryRow?> byId(String id) => (_db.select(
    _db.history,
  )..where((h) => h.id.equals(id))).getSingleOrNull();

  /// Newest first, bounded.
  Future<List<HistoryRow>> recent({int limit = 200}) {
    return (_db.select(_db.history)
          ..orderBy([(h) => OrderingTerm.desc(h.visitedAt)])
          ..limit(limit))
        .get();
  }
}

/// What a promotion did.
enum PromotionKind {
  /// The address was already a Location of a followed Collection, or of a
  /// standalone Entry. There was nothing to create.
  alreadyInLibrary,

  /// The page sits on a Source the library holds; following the Collection is
  /// the authorising act (V2-D13).
  followedCollection,

  /// Nothing was recognised, so the page becomes a standalone Entry in a
  /// Folder — a first-class library item, never wrapped in a Collection of one
  /// (I3).
  createdStandalone,
}

class PromotionOutcome {
  const PromotionOutcome({
    required this.kind,
    this.collectionId,
    this.entryId,
    this.locationId,
    this.violation,
  });

  final PromotionKind kind;
  final String? collectionId;
  final String? entryId;
  final String? locationId;

  /// Set when the promotion refused. The history row is untouched either way.
  final InvariantViolation? violation;

  bool get succeeded => violation == null;
}

/// One tap: history → library. Every write goes through a repository, so the
/// outbox intents that make a promotion visible on the user's other devices
/// happen without this class knowing about sync.
class LibraryPromotion {
  LibraryPromotion({
    required this._folders,
    required this._collections,
    required this._entries,
  });

  final FolderRepository _folders;
  final CollectionRepository _collections;
  final EntryRepository _entries;

  /// Promote [row], using the [result] recognition already produced for it.
  ///
  /// [folderId] places a newly created standalone Entry; the system root is
  /// used when none is given.
  Future<PromotionOutcome> promoteToLibrary({
    required HistoryRow row,
    required RecognitionResult result,
    String? folderId,
  }) async {
    if (row.urlKey != result.keys.urlKey) {
      return const PromotionOutcome(
        kind: PromotionKind.alreadyInLibrary,
        violation: promotionSubjectMismatch,
      );
    }

    switch (result) {
      case RecognisedLocation():
        final collection = result.collection;
        if (collection == null ||
            collection.lifecycle == CollectionLifecycle.active.name) {
          return PromotionOutcome(
            kind: PromotionKind.alreadyInLibrary,
            collectionId: collection?.id,
            entryId: result.entry.id,
            locationId: result.location.id,
          );
        }
        // Known, but the user had stopped following it. Promotion is the act
        // of following again — a single-column write that loses nothing.
        return PromotionOutcome(
          kind: PromotionKind.followedCollection,
          collectionId: collection.id,
          entryId: result.entry.id,
          locationId: result.location.id,
          violation: await _collections.follow(collection.id),
        );

      case RecognisedSource():
        return PromotionOutcome(
          kind: PromotionKind.followedCollection,
          collectionId: result.collection.id,
          violation: await _collections.follow(result.collection.id),
        );

      case Unrecognised():
        return _createStandalone(row, folderId);
    }
  }

  Future<PromotionOutcome> _createStandalone(
    HistoryRow row,
    String? folderId,
  ) async {
    final folder = folderId ?? (await _folders.ensureRoot()).id;
    final (entry, entryViolation) = await _entries.createStandalone(
      folderId: folder,
      title: row.title,
    );
    if (entryViolation != null || entry == null) {
      return PromotionOutcome(
        kind: PromotionKind.createdStandalone,
        violation: entryViolation,
      );
    }
    // I7: a standalone Entry's Location names no Source.
    final (location, locationViolation) = await _entries.addLocation(
      entryId: entry.id,
      url: row.url,
      urlKey: row.urlKey,
      discoveryBasis: 'historyPromotion',
    );
    return PromotionOutcome(
      kind: PromotionKind.createdStandalone,
      entryId: entry.id,
      locationId: location?.id,
      violation: locationViolation,
    );
  }
}
