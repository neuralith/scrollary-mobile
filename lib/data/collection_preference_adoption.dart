/// Moves Collection preferences written under the old settings keys onto the
/// Collection rows that now own them.
///
/// **Why this exists rather than a schema migration step.** The database does
/// have an upgrade path now (V2-D75), and that is where the *columns* come
/// from. This is not a schema step: what moves here is *data* a previous build
/// left in `settings` rows keyed by a Collection's local id, which is an
/// application fact about a preference and not a shape the schema owns. A
/// device that never ran such a build has nothing to move and this is one
/// query that finds nothing.
///
/// **It writes through the repository**, so an adopted answer enters the
/// outbox like any other and reaches the user's other devices — which is the
/// point of moving it. The settings row is deleted in the same pass, so there
/// is one authoritative place a preference lives and no second copy to drift.
///
/// Idempotent, and safe to run at every launch: a value already adopted has no
/// settings row left to read. An answer the Collection has already been given
/// **wins** — a row that arrived from another device is newer information than
/// a key this build has not looked at since it was written.
library;

import '../library/entry_sort_preference.dart';
import '../save/capture_preference.dart';
import 'collection_repository.dart';
import 'schema.dart';

/// What one adoption pass moved. Zero of both is the ordinary answer.
class AdoptedPreferences {
  const AdoptedPreferences({this.captureModes = 0, this.entrySorts = 0});

  final int captureModes;
  final int entrySorts;

  bool get movedAnything => captureModes > 0 || entrySorts > 0;
}

/// Adopts every legacy preference row in [db], returning what it moved.
Future<AdoptedPreferences> adoptLegacyCollectionPreferences(
  LibraryDatabase db,
) async {
  final collections = CollectionRepository(db);
  var captureModes = 0;
  var entrySorts = 0;

  for (final row in await db.select(db.collections).get()) {
    final legacyCapture = legacyCaptureModeKeyFor(row.id);
    final legacySort = legacyEntrySortKeyFor(row.id);
    final stored = await (db.select(
      db.localSettings,
    )..where((s) => s.key.isIn([legacyCapture, legacySort]))).get();
    if (stored.isEmpty) continue;

    for (final setting in stored) {
      final value = setting.value.trim();
      if (setting.key == legacyCapture) {
        if (value.isNotEmpty && row.captureMode.isEmpty) {
          await collections.setCaptureMode(row.id, value);
          captureModes += 1;
        }
      } else if (value.isNotEmpty && row.entrySort.isEmpty) {
        await collections.setEntrySort(row.id, value);
        entrySorts += 1;
      }
    }
    await (db.delete(
      db.localSettings,
    )..where((s) => s.key.isIn([legacyCapture, legacySort]))).go();
  }
  return AdoptedPreferences(captureModes: captureModes, entrySorts: entrySorts);
}
