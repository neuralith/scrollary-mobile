/// This device's label, as the download-request claim uses it (V2-D25).
///
/// A claim names the device that won it, and the requester's UI shows that
/// name. So the label has to be **stable across launches** and it has to be
/// **this device's own business**: it is written once into the settings table
/// and never synchronised, exactly like the sync cursor beside it. Nothing
/// derives it from the hardware — no device name, no model, no identifier the
/// platform would call an identifier. A random label minted on first use tells
/// the user which of their devices took the download without telling anyone
/// anything else, and it needs no permission and no dependency to obtain.
///
/// Device targeting stays minimal by decision (V2_SYNC.md §7): any device may
/// claim, so this value addresses nothing and grants nothing. It is a name on
/// a record. When account-level device management arrives it replaces the
/// minting here and nothing else.
library;

import 'package:drift/drift.dart';

import '../data/data_ids.dart';
import '../data/schema.dart';

class DeviceLabelStore {
  DeviceLabelStore(this._db, {IdGenerator? newId})
    : _newId = newId ?? newLocalId;

  /// The settings key. Device-local state, never an outbox row.
  static const String settingKey = 'sync.deviceLabel';

  final LibraryDatabase _db;
  final IdGenerator _newId;

  String? _cached;

  /// The stored label, minting and storing one on first use.
  ///
  /// The insert is `insertOrIgnore` and is followed by a read, so two callers
  /// racing on a fresh install still agree: the row that landed wins, and a
  /// label already on disk is never overwritten.
  Future<String> label() async {
    final held = _cached;
    if (held != null) return held;
    final stored = await _read();
    if (stored != null && stored.isNotEmpty) return _cached = stored;
    await _db
        .into(_db.localSettings)
        .insert(
          LocalSettingsCompanion.insert(key: settingKey, value: _mint()),
          mode: InsertMode.insertOrIgnore,
        );
    return _cached = (await _read())!;
  }

  Future<String?> _read() async {
    final row = await (_db.select(
      _db.localSettings,
    )..where((s) => s.key.equals(settingKey))).getSingleOrNull();
    return row?.value;
  }

  /// Short, opaque and stable. Long enough that two of the user's own devices
  /// will not collide; nothing about it describes the hardware.
  String _mint() =>
      'device-${_newId().replaceAll('-', '').substring(0, 8).toLowerCase()}';
}
