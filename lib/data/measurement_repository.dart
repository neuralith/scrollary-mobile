/// Measurement repository (roadmap C7).
///
/// Keyed `(entry, source)` and the key is never dropped (I12): there is no
/// read that answers "how far through Entry X" without naming the Source the
/// number was measured against, because a fraction of one rendering is not an
/// approximation of another's (V2-D18).
library;

import 'package:drift/drift.dart';

import '../domain/invariants.dart';
import '../domain/measurement.dart';
import '../domain/sync_kinds.dart';
import 'data_ids.dart';
import 'data_violations.dart';
import 'outbox_writer.dart';
import 'schema.dart';

class MeasurementRepository {
  MeasurementRepository(this._db, {Clock? now, IdGenerator? newId})
    : _now = now ?? utcNow,
      _outbox = OutboxWriter(_db, newId: newId);

  final LibraryDatabase _db;
  final Clock _now;
  final OutboxWriter _outbox;

  /// Records a measurement, replacing this `(entry, source)` cell only.
  ///
  /// The envelope convention (contracts/openapi.yaml, MutationEnvelope):
  /// `entity_id` carries the entry id and `fields.source_id` names the scope.
  Future<(Measurement?, InvariantViolation?)> put({
    required String entryId,
    required String sourceId,
    required double fraction,
    DateTime? at,
  }) async {
    return _db.transaction(() async {
      final when = (at ?? _now()).toUtc();
      final measurement = Measurement(
        entryId: entryId,
        sourceId: sourceId,
        fraction: fraction,
        observedAt: when,
      );
      final violation = measurement.validate();
      if (violation != null) return (null, violation);
      final entry = await (_db.select(
        _db.entries,
      )..where((e) => e.id.equals(entryId))).getSingleOrNull();
      if (entry == null) return (null, unknownRow);
      await _db
          .into(_db.measurements)
          .insertOnConflictUpdate(
            MeasurementsCompanion(
              entryId: Value(entryId),
              sourceId: Value(sourceId),
              fraction: Value(fraction),
              observedAt: Value(when),
            ),
          );
      await _outbox.record(
        kind: SyncedEntityKind.measurement,
        entityId: entryId,
        op: OutboxOp.upsert,
        at: when,
        fields: {
          'source_id': sourceId,
          'fraction': fraction,
          'observed_at': wireTime(when),
        },
      );
      return (measurement, null);
    });
  }

  /// The measurement for exactly this `(entry, source)` cell, or null. There
  /// is deliberately no source-less variant.
  Future<Measurement?> of(String entryId, String sourceId) async {
    final row =
        await (_db.select(_db.measurements)..where(
              (m) => m.entryId.equals(entryId) & m.sourceId.equals(sourceId),
            ))
            .getSingleOrNull();
    if (row == null) return null;
    return Measurement(
      entryId: row.entryId,
      sourceId: row.sourceId,
      fraction: row.fraction,
      observedAt: row.observedAt,
    );
  }

  /// Every scoped measurement of an Entry — each still carrying its Source.
  Future<List<Measurement>> allOf(String entryId) async {
    final rows = await (_db.select(
      _db.measurements,
    )..where((m) => m.entryId.equals(entryId))).get();
    return [
      for (final row in rows)
        Measurement(
          entryId: row.entryId,
          sourceId: row.sourceId,
          fraction: row.fraction,
          observedAt: row.observedAt,
        ),
    ];
  }

  // ---- Pull path (sync lane): no outbox, ever. -----------------------------

  Future<void> applyRemote({
    required String entryId,
    required String sourceId,
    required double fraction,
    required DateTime observedAt,
    required int revision,
  }) async {
    await _db
        .into(_db.measurements)
        .insertOnConflictUpdate(
          MeasurementsCompanion(
            entryId: Value(entryId),
            sourceId: Value(sourceId),
            fraction: Value(fraction),
            observedAt: Value(observedAt),
            revision: Value(revision),
          ),
        );
  }

  Future<void> applyRemoteDelete({
    required String entryId,
    required String sourceId,
  }) async {
    await (_db.delete(_db.measurements)..where(
          (m) => m.entryId.equals(entryId) & m.sourceId.equals(sourceId),
        ))
        .go();
  }

  /// Moves measurements of a merged-away duplicate onto its survivor
  /// (roadmap G3). Per key, the newer observation wins.
  Future<void> rewriteEntryRef(String from, String to) =>
      _rewriteKey(fromEntry: from, toEntry: to);

  Future<void> rewriteSourceRef(String from, String to) =>
      _rewriteKey(fromSource: from, toSource: to);

  Future<void> _rewriteKey({
    String? fromEntry,
    String? toEntry,
    String? fromSource,
    String? toSource,
  }) async {
    final moving =
        await (_db.select(_db.measurements)..where(
              (m) => fromEntry != null
                  ? m.entryId.equals(fromEntry)
                  : m.sourceId.equals(fromSource!),
            ))
            .get();
    for (final row in moving) {
      final entryId = toEntry ?? row.entryId;
      final sourceId = toSource ?? row.sourceId;
      final existing =
          await (_db.select(_db.measurements)..where(
                (m) => m.entryId.equals(entryId) & m.sourceId.equals(sourceId),
              ))
              .getSingleOrNull();
      await (_db.delete(_db.measurements)..where(
            (m) =>
                m.entryId.equals(row.entryId) & m.sourceId.equals(row.sourceId),
          ))
          .go();
      if (existing == null || existing.observedAt.isBefore(row.observedAt)) {
        await _db
            .into(_db.measurements)
            .insertOnConflictUpdate(
              MeasurementsCompanion(
                entryId: Value(entryId),
                sourceId: Value(sourceId),
                fraction: Value(row.fraction),
                observedAt: Value(row.observedAt),
                revision: Value(row.revision),
              ),
            );
      }
    }
  }
}
