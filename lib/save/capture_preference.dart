/// What a Collection is normally captured as.
///
/// **Why this file exists.** `CaptureMode` is a column on a queue row and
/// nothing else, so it was chosen per save and forgotten per save: the
/// five-hundredth Entry of a work someone has only ever wanted as images asked
/// *What to save* exactly as loudly as the first. The capability was
/// anticipated — `CaptureCapabilities.resolve` says in its own doc comment
/// that it is "the one place a stale collection preference is stopped from
/// forcing an impossible save" — and the preference it stops was never
/// written.
///
/// **Device-local, in the settings table.** The schema is frozen at version 1
/// with no migration path (CLAUDE.md, "The database has no history"), and this
/// is exactly what `LocalSettingsStore` documents itself as being for: "a
/// setting is a string under a key its owner names, so a new preference is a
/// constant beside the thing it configures rather than a column, a migration
/// and an entry in a registry three layers away".
///
/// **A preference proposes; the page disposes.** Nothing here consults a page,
/// and nothing here can force a mode: what is stored is what the user asked
/// for on this Collection, and `CaptureCapabilities.resolve` is what decides
/// whether a given page can honour it. A page that cannot says so and falls
/// back, and the preference is left alone — it was about the work, not about
/// that page.
library;

import '../data/local_settings.dart';
import 'capture_mode.dart';

/// The settings key a Collection's preference lives under.
///
/// Namespaced by the Collection's own id, so there is one row per Collection
/// and forgetting one cannot touch another. Exposed for the test that pins the
/// spelling: a key that changes silently is a preference that silently
/// vanishes.
String captureModeKeyFor(String collectionId) => 'capture_mode.$collectionId';

/// Reads and writes what a Collection is normally captured as.
class CapturePreferenceStore {
  const CapturePreferenceStore(this._settings);

  final LocalSettingsStore _settings;

  /// What this Collection is normally captured as, or null when the user has
  /// never said.
  ///
  /// Null is also the answer for a stored value this build does not recognise
  /// — `captureModeFromName` refuses to fall back to a value, because there is
  /// no "safest" capture mode and an unreadable preference has to mean "ask
  /// detection again" rather than "quietly save something else".
  Future<CaptureMode?> of(String? collectionId) async {
    if (collectionId == null || collectionId.isEmpty) return null;
    return captureModeFromName(
      await _settings.get(captureModeKeyFor(collectionId)),
    );
  }

  /// Remember [mode] for this Collection.
  ///
  /// Called only for a choice the **user** made. A mode that came from
  /// detection is the page's answer about that page, and writing it here would
  /// turn one page's shape into a standing instruction about the whole work.
  Future<void> remember(String? collectionId, CaptureMode mode) async {
    if (collectionId == null || collectionId.isEmpty) return;
    await _settings.set(captureModeKeyFor(collectionId), mode.name);
  }

  /// Go back to asking the page. Not a deletion of anything the user can see.
  Future<void> forget(String collectionId) =>
      _settings.remove(captureModeKeyFor(collectionId));
}
