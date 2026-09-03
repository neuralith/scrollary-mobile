/// What this device's last update check of each Collection came to.
///
/// **Device state, and never synced** — the kind is absent from
/// [SyncedEntityKind], so an intent about one of these rows cannot be
/// expressed, and V2_SYNC.md §4.8 already listed per-Source check timestamps
/// among what does not cross. A phone that checked an hour ago has said
/// nothing about what a tablet has done.
///
/// It persists because *Not checked yet* on every launch is not what a device
/// that checked five minutes ago should say. What is deliberately **not**
/// stored is the run in progress and the Entries it found: a check interrupted
/// by a kill is not still running, and "what arrived while you were looking"
/// stops being a useful sentence once you have stopped looking.
library;

import 'package:drift/drift.dart';

import 'schema.dart';

class CollectionCheckRepository {
  const CollectionCheckRepository(this._db);

  final LibraryDatabase _db;

  /// Every Collection this device has a check result for.
  Future<Map<String, CollectionCheckRow>> load() async {
    final rows = await _db.select(_db.collectionCheckStates).get();
    return {for (final row in rows) row.collectionId: row};
  }

  /// Records what one check concluded. A [checkedAt] of null is a Collection
  /// whose check did not conclude — it keeps no time, and says so.
  Future<void> record(
    String collectionId, {
    required DateTime? checkedAt,
    required bool failed,
  }) async {
    await _db
        .into(_db.collectionCheckStates)
        .insertOnConflictUpdate(
          CollectionCheckStatesCompanion(
            collectionId: Value(collectionId),
            checkedAt: Value(checkedAt),
            failed: Value(failed),
          ),
        );
  }
}
