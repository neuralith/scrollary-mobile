/// The device's small key-value settings, over the V2 `settings` table.
///
/// V1 kept these four methods on its database class itself. They live here
/// rather than on [LibraryDatabase] for the reason the page-hint store gives: a
/// setting is an application fact, not a library one — the library knows
/// nothing about an appearance mode or a keep-working preference beyond
/// holding the row.
///
/// Deliberately untyped and unenumerated. A setting is a string under a key
/// its owner names, so a new preference is a constant beside the thing it
/// configures rather than a column, a migration and an entry in a registry
/// three layers away.
library;

import 'schema.dart';

class LocalSettingsStore {
  const LocalSettingsStore(this._db);

  final LibraryDatabase _db;

  Future<void> set(String key, String value) => _db
      .into(_db.localSettings)
      .insertOnConflictUpdate(SettingRow(key: key, value: value));

  /// One-shot read. Boot paths and tests want the value now, not the first
  /// emission of a stream: what the shell paints on its first frame is decided
  /// from values read this way, before the app builds.
  Future<String?> get(String key) async => (await (_db.select(
    _db.localSettings,
  )..where((t) => t.key.equals(key))).getSingleOrNull())?.value;

  Stream<String?> watch(String key) =>
      (_db.select(_db.localSettings)..where((t) => t.key.equals(key)))
          .watchSingleOrNull()
          .map((row) => row?.value);

  Future<int> remove(String key) =>
      (_db.delete(_db.localSettings)..where((t) => t.key.equals(key))).go();
}
