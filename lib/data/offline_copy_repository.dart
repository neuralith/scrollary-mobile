/// OfflineCopy repository (roadmap C8). Device state, start to finish.
///
/// Nothing here ever touches the outbox: I11 says nothing about an
/// OfflineCopy is sent to or received from the server, and the outbox
/// table's CHECK cannot even spell the kind. Rows manage themselves —
/// provenance is values, not references (V2-D22), so no cascade from the
/// library can reach them (I14).
///
/// This repository owns rows, not files. Byte lifecycles (atomic commit,
/// `.previous` restore, staging sweeps) belong to the ported FileStore, whose
/// call sites the capture lane retargets (E2). Removing a copy here removes
/// the record that this device holds bytes; the caller deletes the package
/// through the FileStore first.
library;

import 'package:drift/drift.dart';

import '../domain/offline_copy.dart';
import 'data_ids.dart';
import 'schema.dart';

class OfflineCopyRepository {
  OfflineCopyRepository(this._db, {Clock? now, IdGenerator? newId})
    : _now = now ?? utcNow,
      _newId = newId ?? newLocalId;

  final LibraryDatabase _db;
  final Clock _now;
  final IdGenerator _newId;

  /// Records a captured copy. One active copy per Entry (I13): a previous
  /// active copy is deactivated in the same transaction the replacement
  /// becomes active in, mirroring the atomic replace-with-restore the file
  /// side already performs.
  Future<OfflineCopy> recordCopy({
    required String entryId,
    required String locationUrl,
    required String artifactFormat,
    required String contentPath,
    required int byteSize,
    String sourceName = '',
    String sourceHost = '',
    String sourceLanguage = '',
    DateTime? capturedAt,
  }) async {
    return _db.transaction(() async {
      final at = _now();
      final when = (capturedAt ?? at).toUtc();
      await (_db.update(_db.offlineCopies)
            ..where((c) => c.entryId.equals(entryId) & c.active.equals(true)))
          .write(const OfflineCopiesCompanion(active: Value(false)));
      final id = _newId();
      await _db
          .into(_db.offlineCopies)
          .insert(
            OfflineCopiesCompanion.insert(
              id: id,
              entryId: entryId,
              locationUrl: locationUrl,
              sourceName: Value(sourceName),
              sourceHost: Value(sourceHost),
              sourceLanguage: Value(sourceLanguage),
              capturedAt: when,
              artifactFormat: artifactFormat,
              contentPath: contentPath,
              byteSize: Value(byteSize),
              createdAt: at,
            ),
          );
      return OfflineCopy(
        id: id,
        entryId: entryId,
        locationUrl: locationUrl,
        sourceName: sourceName,
        sourceHost: sourceHost,
        sourceLanguage: sourceLanguage,
        capturedAt: when,
        artifactFormat: artifactFormat,
        contentPath: contentPath,
        byteSize: byteSize,
      );
    });
  }

  /// The reading anchor: position inside this artifact. Device state,
  /// meaningless without the bytes it indexes.
  Future<void> saveAnchor(
    String entryId, {
    required int anchorIndex,
    required double anchorOffset,
  }) async {
    await (_db.update(
      _db.offlineCopies,
    )..where((c) => c.entryId.equals(entryId) & c.active.equals(true))).write(
      OfflineCopiesCompanion(
        anchorIndex: Value(anchorIndex),
        anchorOffset: Value(anchorOffset),
      ),
    );
  }

  Future<OfflineCopy?> activeCopyOf(String entryId) async {
    final row =
        await (_db.select(_db.offlineCopies)
              ..where((c) => c.entryId.equals(entryId) & c.active.equals(true)))
            .getSingleOrNull();
    return row == null ? null : _toDomain(row);
  }

  /// Every copy row on this device, active first — what a cleanup surface
  /// enumerates, including copies whose Entry the library no longer claims.
  Future<List<OfflineCopy>> allCopies() async {
    final rows =
        await (_db.select(_db.offlineCopies)..orderBy([
              (c) => OrderingTerm.desc(c.active),
              (c) => OrderingTerm.desc(c.capturedAt),
            ]))
            .get();
    return [for (final row in rows) _toDomain(row)];
  }

  /// Frees this device's record of the bytes (V2_SYNC.md §5: "freed here
  /// only"). Removes every copy row of the Entry; never an outbox intent, and
  /// never anything but rows — the package itself goes through the FileStore.
  Future<int> removeCopies(String entryId) {
    return (_db.delete(
      _db.offlineCopies,
    )..where((c) => c.entryId.equals(entryId))).go();
  }

  OfflineCopy _toDomain(OfflineCopyRow row) => OfflineCopy(
    id: row.id,
    entryId: row.entryId,
    locationUrl: row.locationUrl,
    sourceName: row.sourceName,
    sourceHost: row.sourceHost,
    sourceLanguage: row.sourceLanguage,
    capturedAt: row.capturedAt,
    artifactFormat: row.artifactFormat,
    contentPath: row.contentPath,
    byteSize: row.byteSize,
    anchorIndex: row.anchorIndex,
    anchorOffset: row.anchorOffset,
    active: row.active,
  );
}
