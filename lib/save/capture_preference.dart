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

/// *Ask each time*, stored.
///
/// **Why a value and not an absent key** (V2-D61). Since accepting the sheet's
/// proposal is what creates a preference, *nobody has said* and *somebody said
/// keep asking* stop behaving alike: the first is a Collection whose next save
/// should record what it was saved as, and the second is a standing
/// instruction not to. Written as a name no [CaptureMode] has, so
/// [captureModeFromName] reads it as null — the proposal is unchanged
/// everywhere, and the engine seam (V2-D58) never sees it at all.
const String kAskEachTime = 'askEachTime';

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

  /// Whether the user has answered *what to save* for this Collection at all.
  ///
  /// True for a stored mode **and** for *Ask each time*, which is an answer;
  /// false only where nobody has said anything yet. The distinction exists for
  /// exactly one caller — the save sheet, deciding whether proceeding with the
  /// proposed mode should record it (V2-D61) — and it is deliberately not
  /// [of]'s business: what to *propose* is a mode or nothing, and that is all
  /// the capture seam ever asks for.
  Future<bool> isAnswered(String? collectionId) async {
    if (collectionId == null || collectionId.isEmpty) return false;
    final stored = await _settings.get(captureModeKeyFor(collectionId));
    return stored == kAskEachTime || captureModeFromName(stored) != null;
  }

  /// Remember [mode] for this Collection.
  ///
  /// Called for a mode the user **chose**, and for one they **accepted** by
  /// starting a save with it while the Collection had no answer of its own
  /// (V2-D61). What is never written here is a mode nothing was saved with: a
  /// sheet that was opened and dismissed has said nothing about the work.
  Future<void> remember(String? collectionId, CaptureMode mode) async {
    if (collectionId == null || collectionId.isEmpty) return;
    await _settings.set(captureModeKeyFor(collectionId), mode.name);
  }

  /// *Ask each time*: keep proposing what each page can offer, and record that
  /// this is what the user asked for.
  ///
  /// Not the same as [forget]. This is an answer, and it survives the next
  /// save — which is the whole point of the label.
  Future<void> askEachTime(String? collectionId) async {
    if (collectionId == null || collectionId.isEmpty) return;
    await _settings.set(captureModeKeyFor(collectionId), kAskEachTime);
  }

  /// Drop the answer entirely, as though it had never been given.
  ///
  /// For a Collection that is going away (V2-D60), not for a user changing
  /// their mind — [askEachTime] is that.
  Future<void> forget(String collectionId) =>
      _settings.remove(captureModeKeyFor(collectionId));
}
