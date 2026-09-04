/// What order a Collection's Entries are shown in, remembered.
///
/// **On the Collection row, and it synchronises.** It began in the settings
/// table when the schema was frozen, with a note saying that if it should
/// follow a user between devices it becomes a Collection field through
/// `contracts/README.md`'s protocol. It should, and it has. The argument that
/// kept it local — `ordering_basis` is what the *source* does, and which end
/// of it someone likes to look at is theirs — turned out to argue the other
/// way: a list somebody arranged by hand going back to its default on their
/// other device is the arrangement being lost, not respected.
///
/// The wire form is an opaque token the service stores and never interprets
/// (contracts/openapi.yaml `Collection.entry_sort`), so a new sort field is a
/// client release and not a backend one.
///
/// Modelled on `save/capture_preference.dart` beside it, and on
/// `reading_v2/finished_cleanup.dart` — which stays device-local, because what
/// happens to a finished Entry's files is a decision about bytes on one
/// device (V2-D59). Down to the tri-state:
/// **null is a question, not a default.** An unset Collection opens in the
/// order its own data earns — see `defaultEntrySort` — and only a deliberate
/// choice is stored. Nothing infers one from what the user did on another
/// Collection.
library;

import 'package:drift/drift.dart';

import '../data/collection_repository.dart';
import '../data/schema.dart';
import 'entry_sort.dart';

/// The settings key this preference used to live under, kept for exactly one
/// reader: `adoptLegacyCollectionPreferences`, which moves a value written by
/// an older build onto the Collection row and deletes the row it came from.
/// Nothing else may read or write it.
String legacyEntrySortKeyFor(String collectionId) => 'entry_sort.$collectionId';

/// Reads and writes the order one Collection's Entries are drawn in.
class EntrySortPreferenceStore {
  EntrySortPreferenceStore(LibraryDatabase db)
    : _db = db,
      _collections = CollectionRepository(db);

  final LibraryDatabase _db;
  final CollectionRepository _collections;

  SingleOrNullSelectable<CollectionRow> _row(String collectionId) =>
      _db.select(_db.collections)..where((c) => c.id.equals(collectionId));

  /// This Collection's remembered sort, or null when the user has never said.
  ///
  /// Null is also the answer for a stored value this build cannot read —
  /// `parseEntrySort` refuses rather than guessing a half of it, because a
  /// preference resolved from a value nobody wrote is worse than the default
  /// the Collection's data would have chosen.
  Future<EntrySort?> of(String? collectionId) async {
    if (collectionId == null || collectionId.isEmpty) return null;
    final row = await _row(collectionId).getSingleOrNull();
    return parseEntrySort(row?.entrySort);
  }

  /// Emits this Collection's remembered sort, and again whenever it changes.
  ///
  /// The screen watches rather than reads: choosing a sort writes here, and
  /// the list has to redraw from that write. Nothing else in the library's
  /// tick stream covers the settings table.
  Stream<EntrySort?> watch(String collectionId) => _row(
    collectionId,
  ).watchSingleOrNull().map((row) => parseEntrySort(row?.entrySort));

  /// Remember [sort] for this Collection.
  ///
  /// Only ever called for a choice the **user** made in the control. Nothing
  /// records the default it happened to open in: a Collection that has never
  /// been sorted by hand must keep following its data, so that an Entry with a
  /// publish date arriving in a Collection that had none moves it off
  /// *Date added* on its own.
  Future<void> remember(String? collectionId, EntrySort sort) async {
    if (collectionId == null || collectionId.isEmpty) return;
    await _collections.setEntrySort(collectionId, sort.storedValue);
  }

  /// Go back to the order the Collection's own data chooses. Reorders a list
  /// and changes nothing else — and travels, so the Collection follows its own
  /// data on every device rather than only on this one.
  Future<void> forget(String collectionId) async {
    await _collections.setEntrySort(collectionId, '');
  }
}
