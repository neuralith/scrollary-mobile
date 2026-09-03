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
/// **On the Collection row, and it synchronises.** It began in the settings
/// table because the schema was frozen; it is a column now because the answer
/// is about the *work*, not about this device — someone who said "always
/// images" on their phone has said it about the Collection, and being asked
/// again on their tablet is the question they already answered. The wire form
/// is an opaque token the service stores and never interprets
/// (contracts/openapi.yaml `Collection.capture_mode`), so the vocabulary below
/// stays the client's.
///
/// This is **not** the shape of every Collection preference. What happens to a
/// finished Entry's files stays device-local (V2-D59), because that decides
/// what happens to bytes on one device and a phone must not decide for a
/// tablet with room to keep them.
///
/// **A preference proposes; the page disposes.** Nothing here consults a page,
/// and nothing here can force a mode: what is stored is what the user asked
/// for on this Collection, and `CaptureCapabilities.resolve` is what decides
/// whether a given page can honour it. A page that cannot says so and falls
/// back, and the preference is left alone — it was about the work, not about
/// that page.
library;

import '../data/collection_repository.dart';
import '../data/schema.dart';
import 'capture_mode.dart';

/// The settings key this preference used to live under, kept for exactly one
/// reader: [adoptLegacyCollectionPreferences], which moves a value written by
/// an older build onto the Collection row and deletes the row it came from.
/// Nothing else may read or write it.
String legacyCaptureModeKeyFor(String collectionId) =>
    'capture_mode.$collectionId';

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
  CapturePreferenceStore(LibraryDatabase db)
    : _db = db,
      _collections = CollectionRepository(db);

  final LibraryDatabase _db;
  final CollectionRepository _collections;

  /// The stored token, or null where there is no Collection or no answer.
  ///
  /// Empty string and a missing row read the same, because both mean nobody
  /// has said.
  Future<String?> _stored(String? collectionId) async {
    if (collectionId == null || collectionId.isEmpty) return null;
    final row = await (_db.select(
      _db.collections,
    )..where((c) => c.id.equals(collectionId))).getSingleOrNull();
    final value = row?.captureMode ?? '';
    return value.isEmpty ? null : value;
  }

  /// What this Collection is normally captured as, or null when the user has
  /// never said.
  ///
  /// Null is also the answer for a stored value this build does not recognise
  /// — `captureModeFromName` refuses to fall back to a value, because there is
  /// no "safest" capture mode and an unreadable preference has to mean "ask
  /// detection again" rather than "quietly save something else".
  Future<CaptureMode?> of(String? collectionId) async =>
      captureModeFromName(await _stored(collectionId));

  /// Whether the user has answered *what to save* for this Collection at all.
  ///
  /// True for a stored mode **and** for *Ask each time*, which is an answer;
  /// false only where nobody has said anything yet. The distinction exists for
  /// exactly one caller — the save sheet, deciding whether proceeding with the
  /// proposed mode should record it (V2-D61) — and it is deliberately not
  /// [of]'s business: what to *propose* is a mode or nothing, and that is all
  /// the capture seam ever asks for.
  Future<bool> isAnswered(String? collectionId) async {
    final stored = await _stored(collectionId);
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
    await _collections.setCaptureMode(collectionId, mode.name);
  }

  /// *Ask each time*: keep proposing what each page can offer, and record that
  /// this is what the user asked for.
  ///
  /// Not the same as [forget]. This is an answer, and it survives the next
  /// save — which is the whole point of the label.
  Future<void> askEachTime(String? collectionId) async {
    if (collectionId == null || collectionId.isEmpty) return;
    await _collections.setCaptureMode(collectionId, kAskEachTime);
  }

  /// Drop the answer entirely, as though it had never been given.
  ///
  /// For a Collection that is going away (V2-D60), not for a user changing
  /// their mind — [askEachTime] is that. Clearing is a write like any other
  /// and travels: a Collection whose answer was dropped here has no answer
  /// anywhere.
  Future<void> forget(String collectionId) async {
    await _collections.setCaptureMode(collectionId, '');
  }
}
