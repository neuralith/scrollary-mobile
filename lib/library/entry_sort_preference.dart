/// What order a Collection's Entries are shown in, remembered.
///
/// **Device-local, in the settings table.** The third store built this way,
/// and for the same reasons the two before it were: the schema is frozen at
/// version 1 with no migration path (CLAUDE.md, "The database has no
/// history"), and `LocalSettingsStore` documents itself as the place for
/// exactly this — "a setting is a string under a key its owner names, so a new
/// preference is a constant beside the thing it configures rather than a
/// column, a migration and an entry in a registry three layers away".
///
/// **Local rather than synced is a judgement, and it is this one:** the
/// Collection's `ordering_basis` — what the *source* does — is library state
/// and syncs; which end of it this person likes to look at is not. It is also
/// the only option available today without changing `contracts/`, which is
/// frozen at Gate B. If it should follow a user between devices later, it
/// becomes a Collection field through `contracts/README.md`'s protocol, and
/// this store is what it replaces.
///
/// Modelled on `save/capture_preference.dart` and
/// `reading_v2/finished_cleanup.dart` deliberately, down to the tri-state:
/// **null is a question, not a default.** An unset Collection opens in the
/// order its own data earns — see `defaultEntrySort` — and only a deliberate
/// choice is stored. Nothing infers one from what the user did on another
/// Collection.
library;

import '../data/local_settings.dart';
import 'entry_sort.dart';

/// The settings key a Collection's sort lives under.
///
/// Namespaced by the Collection's own id, so there is one row per Collection
/// and forgetting one cannot touch another. Exposed for the test that pins the
/// spelling: a key that changes silently is a preference that silently
/// vanishes, and this one vanishing means a list the user arranged quietly
/// goes back to its default the next time they open it.
String entrySortKeyFor(String collectionId) => 'entry_sort.$collectionId';

/// Reads and writes the order one Collection's Entries are drawn in.
class EntrySortPreferenceStore {
  const EntrySortPreferenceStore(this._settings);

  final LocalSettingsStore _settings;

  /// This Collection's remembered sort, or null when the user has never said.
  ///
  /// Null is also the answer for a stored value this build cannot read —
  /// `parseEntrySort` refuses rather than guessing a half of it, because a
  /// preference resolved from a value nobody wrote is worse than the default
  /// the Collection's data would have chosen.
  Future<EntrySort?> of(String? collectionId) async {
    if (collectionId == null || collectionId.isEmpty) return null;
    return parseEntrySort(await _settings.get(entrySortKeyFor(collectionId)));
  }

  /// Emits this Collection's remembered sort, and again whenever it changes.
  ///
  /// The screen watches rather than reads: choosing a sort writes here, and
  /// the list has to redraw from that write. Nothing else in the library's
  /// tick stream covers the settings table.
  Stream<EntrySort?> watch(String collectionId) =>
      _settings.watch(entrySortKeyFor(collectionId)).map(parseEntrySort);

  /// Remember [sort] for this Collection.
  ///
  /// Only ever called for a choice the **user** made in the control. Nothing
  /// records the default it happened to open in: a Collection that has never
  /// been sorted by hand must keep following its data, so that an Entry with a
  /// publish date arriving in a Collection that had none moves it off
  /// *Date added* on its own.
  Future<void> remember(String? collectionId, EntrySort sort) async {
    if (collectionId == null || collectionId.isEmpty) return;
    await _settings.set(entrySortKeyFor(collectionId), sort.storedValue);
  }

  /// Go back to the order the Collection's own data chooses. Reorders a list
  /// and changes nothing else.
  Future<void> forget(String collectionId) =>
      _settings.remove(entrySortKeyFor(collectionId));
}
